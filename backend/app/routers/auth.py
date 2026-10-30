from datetime import datetime, timezone
from typing import Annotated
from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import create_access_token, get_current_user, verify_password
from app.database import get_db
from app.models import AuditLog, User
from app.schemas import TokenResponse, UserOut

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/login", response_model=TokenResponse)
async def login(
    request: Request,
    form: Annotated[OAuth2PasswordRequestForm, Depends()],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    user = (await db.execute(select(User).where(User.email == form.username))).scalar_one_or_none()
    ip = request.client.host if request.client else None
    if not user or not verify_password(form.password, user.hashed_password):
        db.add(AuditLog(user_email=form.username, action="login_failed",
                        entity="auth", details="Incorrect credentials", ip_address=ip))
        await db.commit()
        raise HTTPException(status_code=401, detail="Incorrect email or password")
    if not user.is_active:
        raise HTTPException(status_code=403, detail="Account disabled")
    user.last_login_at = datetime.now(timezone.utc)
    db.add(AuditLog(user_email=user.email, action="login", entity="auth",
                    details="Successful login", ip_address=ip))
    await db.commit()
    return TokenResponse(access_token=create_access_token(user.email, user.role.value))


@router.post("/logout")
async def logout(
    request: Request,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    db.add(AuditLog(user_email=user.email, action="logout", entity="auth",
                    ip_address=request.client.host if request.client else None))
    await db.commit()
    return {"status": "ok"}


@router.get("/me", response_model=UserOut)
async def me(user: Annotated[User, Depends(get_current_user)]):
    return user
