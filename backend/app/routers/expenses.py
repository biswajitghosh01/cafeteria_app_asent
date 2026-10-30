from datetime import date
from typing import Annotated
from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.auth import get_current_user
from app.database import get_db
from app.models import AuditLog, FixedExpense, User
from app.schemas import ExpenseCreate, ExpenseOut

router = APIRouter(prefix="/expenses", tags=["expenses"])


@router.get("", response_model=list[ExpenseOut])
async def list_expenses(
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
    start: date | None = Query(None), end: date | None = Query(None),
):
    stmt = select(FixedExpense).order_by(FixedExpense.expense_date.desc()).limit(500)
    if start: stmt = stmt.where(FixedExpense.expense_date >= start)
    if end: stmt = stmt.where(FixedExpense.expense_date <= end)
    return (await db.execute(stmt)).scalars().all()


@router.post("", response_model=ExpenseOut, status_code=201)
async def create_expense(
    request: Request, payload: ExpenseCreate,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    e = FixedExpense(**payload.model_dump())
    db.add(e); await db.flush()
    db.add(AuditLog(user_email=user.email, action="create", entity="fixed_expense",
                    entity_id=str(e.id),
                    ip_address=request.client.host if request.client else None))
    await db.commit(); await db.refresh(e)
    return e


@router.patch("/{eid}/paid", response_model=ExpenseOut)
async def mark_paid(
    eid: int,
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
):
    e = await db.get(FixedExpense, eid)
    if e is None: raise HTTPException(404, "Expense not found")
    e.is_paid = True
    await db.commit(); await db.refresh(e)
    return e


@router.delete("/{eid}", status_code=204)
async def delete_expense(
    eid: int,
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
):
    e = await db.get(FixedExpense, eid)
    if e is None: raise HTTPException(404, "Expense not found")
    await db.delete(e); await db.commit()
