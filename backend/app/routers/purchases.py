from datetime import date
from typing import Annotated
from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.auth import get_current_user
from app.database import get_db
from app.models import AuditLog, Purchase, User
from app.schemas import PurchaseCreate, PurchaseOut

router = APIRouter(prefix="/purchases", tags=["purchases"])


@router.get("", response_model=list[PurchaseOut])
async def list_purchases(
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
    start: date | None = Query(None), end: date | None = Query(None),
):
    stmt = select(Purchase).order_by(Purchase.purchase_date.desc()).limit(500)
    if start: stmt = stmt.where(Purchase.purchase_date >= start)
    if end: stmt = stmt.where(Purchase.purchase_date <= end)
    return (await db.execute(stmt)).scalars().all()


@router.post("", response_model=PurchaseOut, status_code=201)
async def create_purchase(
    request: Request, payload: PurchaseCreate,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    p = Purchase(**payload.model_dump())
    db.add(p); await db.flush()
    db.add(AuditLog(user_email=user.email, action="create", entity="purchase",
                    entity_id=str(p.id),
                    ip_address=request.client.host if request.client else None))
    await db.commit(); await db.refresh(p)
    return p


@router.delete("/{pid}", status_code=204)
async def delete_purchase(
    pid: int, request: Request,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    p = await db.get(Purchase, pid)
    if p is None: raise HTTPException(404, "Purchase not found")
    db.add(AuditLog(user_email=user.email, action="delete", entity="purchase",
                    entity_id=str(pid),
                    ip_address=request.client.host if request.client else None))
    await db.delete(p); await db.commit()
