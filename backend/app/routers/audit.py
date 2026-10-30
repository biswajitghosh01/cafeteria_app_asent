from typing import Annotated
from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.auth import require_admin
from app.database import get_db
from app.models import AuditLog, User
from app.schemas import AuditOut

router = APIRouter(prefix="/audit", tags=["audit"])


@router.get("", response_model=list[AuditOut])
async def list_audit(
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(require_admin)],
    limit: int = Query(200, le=1000),
):
    return (await db.execute(
        select(AuditLog).order_by(AuditLog.created_at.desc()).limit(limit)
    )).scalars().all()
