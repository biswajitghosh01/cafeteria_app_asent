from decimal import Decimal
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user
from app.database import get_db
from app.models import (
    AuditLog,
    Employee,
    SalaryAdvance,
    SalaryRecord,
    User,
)
from app.schemas import (
    AdvanceBalance,
    SalaryAdvanceCreate,
    SalaryAdvanceOut,
)

router = APIRouter(prefix="/advances", tags=["advances"])


async def _outstanding(db: AsyncSession, employee_id: int) -> Decimal:
    given = (await db.execute(
        select(func.coalesce(func.sum(SalaryAdvance.amount), 0))
        .where(SalaryAdvance.employee_id == employee_id)
    )).scalar_one()

    recovered = (await db.execute(
        select(func.coalesce(func.sum(SalaryRecord.advance_deduction), 0))
        .where(SalaryRecord.employee_id == employee_id)
    )).scalar_one()

    return (Decimal(str(given)) - Decimal(str(recovered))).quantize(Decimal("0.01"))


@router.get("", response_model=list[SalaryAdvanceOut])
async def list_advances(
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
    employee_id: int | None = Query(None),
):
    stmt = (
        select(SalaryAdvance, Employee.full_name)
        .join(Employee, Employee.id == SalaryAdvance.employee_id)
        .order_by(SalaryAdvance.advance_date.desc(), SalaryAdvance.id.desc())
    )
    if employee_id:
        stmt = stmt.where(SalaryAdvance.employee_id == employee_id)

    result = await db.execute(stmt)
    out: list[SalaryAdvanceOut] = []
    for advance, name in result.all():
        item = SalaryAdvanceOut.model_validate(advance)
        item.employee_name = name
        out.append(item)
    return out


@router.get("/balances", response_model=list[AdvanceBalance])
async def list_balances(
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
):
    employees = (await db.execute(
        select(Employee).where(Employee.is_active.is_(True))
        .order_by(Employee.full_name)
    )).scalars().all()

    given_rows = dict((await db.execute(
        select(SalaryAdvance.employee_id,
               func.coalesce(func.sum(SalaryAdvance.amount), 0))
        .group_by(SalaryAdvance.employee_id)
    )).all())

    recovered_rows = dict((await db.execute(
        select(SalaryRecord.employee_id,
               func.coalesce(func.sum(SalaryRecord.advance_deduction), 0))
        .group_by(SalaryRecord.employee_id)
    )).all())

    out: list[AdvanceBalance] = []
    for emp in employees:
        given = Decimal(str(given_rows.get(emp.id, 0)))
        recovered = Decimal(str(recovered_rows.get(emp.id, 0)))
        outstanding = (given - recovered).quantize(Decimal("0.01"))
        out.append(AdvanceBalance(
            employee_id=emp.id,
            employee_name=emp.full_name,
            total_advances=given,
            total_recovered=recovered,
            outstanding=outstanding,
        ))
    return out


@router.get("/outstanding/{employee_id}", response_model=AdvanceBalance)
async def get_outstanding(
    employee_id: int,
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
):
    employee = await db.get(Employee, employee_id)
    if employee is None:
        raise HTTPException(404, "Employee not found")

    given = (await db.execute(
        select(func.coalesce(func.sum(SalaryAdvance.amount), 0))
        .where(SalaryAdvance.employee_id == employee_id)
    )).scalar_one()

    recovered = (await db.execute(
        select(func.coalesce(func.sum(SalaryRecord.advance_deduction), 0))
        .where(SalaryRecord.employee_id == employee_id)
    )).scalar_one()

    return AdvanceBalance(
        employee_id=employee.id,
        employee_name=employee.full_name,
        total_advances=Decimal(str(given)),
        total_recovered=Decimal(str(recovered)),
        outstanding=(Decimal(str(given)) - Decimal(str(recovered))).quantize(Decimal("0.01")),
    )


@router.post("", response_model=SalaryAdvanceOut, status_code=201)
async def create_advance(
    payload: SalaryAdvanceCreate,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    employee = await db.get(Employee, payload.employee_id)
    if employee is None:
        raise HTTPException(404, "Employee not found")

    advance = SalaryAdvance(
        employee_id=payload.employee_id,
        amount=payload.amount,
        advance_date=payload.advance_date,
        reason=payload.reason,
        notes=payload.notes,
        created_by=user.email,
    )
    db.add(advance)
    await db.flush()
    db.add(AuditLog(
        user_email=user.email,
        action="create",
        entity="salary_advance",
        entity_id=str(advance.id),
        details=f"Advance ₹{payload.amount} to {employee.full_name}",
    ))
    await db.commit()
    await db.refresh(advance)

    out = SalaryAdvanceOut.model_validate(advance)
    out.employee_name = employee.full_name
    return out


@router.delete("/{advance_id}", status_code=204)
async def delete_advance(
    advance_id: int,
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
):
    advance = await db.get(SalaryAdvance, advance_id)
    if advance is None:
        raise HTTPException(404, "Advance not found")
    await db.delete(advance)
    await db.commit()