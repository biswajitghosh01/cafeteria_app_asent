import os, re, time
from pathlib import Path
from typing import Annotated
import psutil
from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app import __version__
from app.auth import hash_password, require_admin
from app.config import settings
from app.database import get_db
from app.logging_config import get_log_path
from app.models import AuditLog, User, UserRole
from app.schemas import (
    AuditOut, HealthResponse, PasswordReset,
    ServerLogEntry, ServerLogResponse,
    UserCreate, UserOut, UserUpdate,
)

router = APIRouter(prefix="/admin", tags=["admin"])
START_TIME = time.time()

_LOG_RE = re.compile(
    r"^(?P<ts>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) \| "
    r"(?P<level>\w+)\s*\| (?P<logger>[^|]+?) \| (?P<msg>.*)$"
)


@router.get("/health", response_model=HealthResponse)
async def system_health(
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(require_admin)],
):
    t0 = time.perf_counter()
    try:
        await db.execute(select(1)); db_ok = True
    except Exception:
        db_ok = False
    latency = (time.perf_counter() - t0) * 1000

    user_count = (await db.execute(select(func.count(User.id)))).scalar_one()
    active = (await db.execute(select(func.count(User.id))
                               .where(User.is_active.is_(True)))).scalar_one()

    log_path = get_log_path()
    log_size = log_path.stat().st_size if log_path.exists() else 0

    from app.main import REQUEST_COUNTER
    try:
        cpu = psutil.cpu_percent(interval=0.1)
        mem = psutil.virtual_memory().percent
        disk = psutil.disk_usage("/").percent
    except Exception:
        cpu = mem = disk = 0.0

    return HealthResponse(
        status="ok" if db_ok else "degraded",
        environment=settings.environment, version=__version__,
        database="sqlite" if settings.is_sqlite else "postgresql",
        uptime_seconds=time.time() - START_TIME,
        db_ok=db_ok, db_latency_ms=round(latency, 2),
        cpu_percent=cpu, memory_percent=mem, disk_percent=disk,
        log_file=str(log_path), log_size_bytes=log_size,
        request_count=REQUEST_COUNTER["requests"],
        error_count=REQUEST_COUNTER["errors"],
        user_count=user_count, active_session_count=active,
    )


@router.get("/users", response_model=list[UserOut])
async def list_users(
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(require_admin)],
):
    return (await db.execute(select(User).order_by(User.created_at.desc()))).scalars().all()


@router.post("/users", response_model=UserOut, status_code=201)
async def create_user(
    request: Request, payload: UserCreate,
    db: Annotated[AsyncSession, Depends(get_db)],
    admin: Annotated[User, Depends(require_admin)],
):
    if (await db.execute(select(User).where(User.email == payload.email))).scalar_one_or_none():
        raise HTTPException(409, "A user with this email already exists")
    user = User(email=payload.email, full_name=payload.full_name,
                hashed_password=hash_password(payload.password),
                role=payload.role, is_active=payload.is_active)
    db.add(user); await db.flush()
    db.add(AuditLog(user_email=admin.email, action="create", entity="user",
                    entity_id=str(user.id),
                    details=f"Created {payload.role.value} user {payload.email}",
                    ip_address=request.client.host if request.client else None))
    await db.commit(); await db.refresh(user)
    return user


@router.put("/users/{uid}", response_model=UserOut)
async def update_user(
    uid: int, request: Request, payload: UserUpdate,
    db: Annotated[AsyncSession, Depends(get_db)],
    admin: Annotated[User, Depends(require_admin)],
):
    user = await db.get(User, uid)
    if user is None: raise HTTPException(404, "User not found")
    if user.id == admin.id and payload.is_active is False:
        raise HTTPException(400, "You cannot disable your own account")
    if user.id == admin.id and payload.role and payload.role != UserRole.admin:
        raise HTTPException(400, "You cannot demote your own account")
    for k, v in payload.model_dump(exclude_unset=True).items():
        if v is not None: setattr(user, k, v)
    db.add(AuditLog(user_email=admin.email, action="update", entity="user",
                    entity_id=str(user.id), details=f"Updated user {user.email}",
                    ip_address=request.client.host if request.client else None))
    await db.commit(); await db.refresh(user)
    return user


@router.post("/users/{uid}/reset-password", response_model=UserOut)
async def reset_password(
    uid: int, request: Request, payload: PasswordReset,
    db: Annotated[AsyncSession, Depends(get_db)],
    admin: Annotated[User, Depends(require_admin)],
):
    user = await db.get(User, uid)
    if user is None: raise HTTPException(404, "User not found")
    user.hashed_password = hash_password(payload.new_password)
    db.add(AuditLog(user_email=admin.email, action="reset_password", entity="user",
                    entity_id=str(user.id), details=f"Reset password for {user.email}",
                    ip_address=request.client.host if request.client else None))
    await db.commit(); await db.refresh(user)
    return user


@router.delete("/users/{uid}", status_code=204)
async def delete_user(
    uid: int, request: Request,
    db: Annotated[AsyncSession, Depends(get_db)],
    admin: Annotated[User, Depends(require_admin)],
):
    if uid == admin.id:
        raise HTTPException(400, "You cannot delete your own account")
    user = await db.get(User, uid)
    if user is None: raise HTTPException(404, "User not found")
    db.add(AuditLog(user_email=admin.email, action="delete", entity="user",
                    entity_id=str(user.id), details=f"Deleted user {user.email}",
                    ip_address=request.client.host if request.client else None))
    await db.delete(user); await db.commit()


@router.get("/logs/app", response_model=list[AuditOut])
async def app_logs(
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(require_admin)],
    action: str | None = Query(None), entity: str | None = Query(None),
    user_email: str | None = Query(None), limit: int = Query(200, le=2000),
):
    stmt = select(AuditLog).order_by(AuditLog.created_at.desc()).limit(limit)
    if action: stmt = stmt.where(AuditLog.action == action)
    if entity: stmt = stmt.where(AuditLog.entity == entity)
    if user_email: stmt = stmt.where(AuditLog.user_email.ilike(f"%{user_email}%"))
    return (await db.execute(stmt)).scalars().all()


def _tail(path: Path, n: int) -> list[str]:
    if not path.exists(): return []
    with path.open("rb") as fh:
        fh.seek(0, os.SEEK_END); size = fh.tell()
        block = 8192; data = b""; lines: list[bytes] = []; pos = size
        while pos > 0 and len(lines) < n:
            rs = min(block, pos); pos -= rs; fh.seek(pos)
            data = fh.read(rs) + data; lines = data.splitlines()
        return [ln.decode("utf-8", errors="replace") for ln in lines[-n:]]


@router.get("/logs/server", response_model=ServerLogResponse)
async def server_logs(
    _: Annotated[User, Depends(require_admin)],
    level: str | None = Query(None), search: str | None = Query(None),
    limit: int = Query(500, le=5000),
):
    log_path = get_log_path()
    if not log_path.exists():
        return ServerLogResponse(entries=[], total_matched=0,
                                 file_size_bytes=0, lines_scanned=0)
    raw = _tail(log_path, min(limit * 4, 20000))
    entries: list[ServerLogEntry] = []
    for line in raw:
        m = _LOG_RE.match(line)
        if m:
            entry = ServerLogEntry(timestamp=m.group("ts"),
                                   level=m.group("level").strip(),
                                   logger=m.group("logger").strip(),
                                   message=m.group("msg"))
        else:
            if entries: entries[-1].message += "\n" + line
            continue
        if level and entry.level.upper() != level.upper(): continue
        if search:
            n = search.lower()
            if (n not in entry.message.lower()
                and n not in entry.logger.lower()
                and n not in entry.level.lower()): continue
        entries.append(entry)
    entries = list(reversed(entries))[:limit]
    return ServerLogResponse(
        entries=entries, total_matched=len(entries),
        file_size_bytes=log_path.stat().st_size, lines_scanned=len(raw),
    )


@router.get("/logs/server/download")
async def download_log(_: Annotated[User, Depends(require_admin)]):
    from fastapi.responses import FileResponse
    log_path = get_log_path()
    if not log_path.exists():
        raise HTTPException(status_code=404, detail="Log file not found")
    return FileResponse(log_path, media_type="text/plain",
                        filename="food-court-api.log")
