from calendar import monthrange
from datetime import date
from decimal import Decimal
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user
from app.database import get_db
from app.models import (
    Attendance,
    AttendanceStatus,
    Employee,
    SalaryAdvance,
    SalaryRecord,
    User,
)
from app.schemas import (
    AttendancePreview,
    SalaryCreate,
    SalaryOut,
)

router = APIRouter(prefix="/salary", tags=["salary"])

PF_EMPLOYEE_RATE = Decimal("0.12")
PF_EMPLOYER_RATE = Decimal("0.12")
PF_WAGE_CEILING = Decimal("15000")
ESI_EMPLOYEE_RATE = Decimal("0.0075")
ESI_EMPLOYER_RATE = Decimal("0.0325")
ESI_GROSS_CEILING = Decimal("21000")


def compute_deductions(gross: Decimal) -> dict[str, Decimal]:
    pf_base = min(gross, PF_WAGE_CEILING)
    pf_employee = (pf_base * PF_EMPLOYEE_RATE).quantize(Decimal("0.01"))
    pf_employer = (pf_base * PF_EMPLOYER_RATE).quantize(Decimal("0.01"))

    if gross <= ESI_GROSS_CEILING:
        esi_employee = (gross * ESI_EMPLOYEE_RATE).quantize(Decimal("0.01"))
        esi_employer = (gross * ESI_EMPLOYER_RATE).quantize(Decimal("0.01"))
    else:
        esi_employee = Decimal("0.00")
        esi_employer = Decimal("0.00")

    return {
        "pf_employee": pf_employee,
        "pf_employer": pf_employer,
        "esi_employee": esi_employee,
        "esi_employer": esi_employer,
    }


async def _outstanding_advance(db: AsyncSession, employee_id: int) -> Decimal:
    given = (await db.execute(
        select(func.coalesce(func.sum(SalaryAdvance.amount), 0))
        .where(SalaryAdvance.employee_id == employee_id)
    )).scalar_one()
    recovered = (await db.execute(
        select(func.coalesce(func.sum(SalaryRecord.advance_deduction), 0))
        .where(SalaryRecord.employee_id == employee_id)
    )).scalar_one()
    return (Decimal(str(given)) - Decimal(str(recovered))).quantize(Decimal("0.01"))


@router.get("/preview")
async def preview(
    gross: Decimal = Query(...),
    _: Annotated[User, Depends(get_current_user)] = None,
):
    return compute_deductions(gross)


@router.get("/attendance-preview", response_model=AttendancePreview)
async def attendance_preview(
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
    employee_id: int = Query(...),
    pay_period: str = Query(..., pattern=r"^\d{4}-\d{2}$"),
):
    employee = await db.get(Employee, employee_id)
    if employee is None:
        raise HTTPException(404, "Employee not found")

    year, month = map(int, pay_period.split("-"))
    days_in_month = monthrange(year, month)[1]
    start = date(year, month, 1)
    end = date(year, month, days_in_month)

    rows = (await db.execute(
        select(Attendance).where(
            Attendance.employee_id == employee_id,
            Attendance.attendance_date.between(start, end),
        )
    )).scalars().all()

    present = sum(1 for r in rows if r.status == AttendanceStatus.present)
    absent = sum(1 for r in rows if r.status == AttendanceStatus.absent)
    on_leave = sum(1 for r in rows if r.status == AttendanceStatus.on_leave)
    payable = present

    base_gross = (
        Decimal(str(employee.basic_salary or 0))
        + Decimal(str(employee.hra or 0))
        + Decimal(str(employee.allowances or 0))
    )

    daily_rate = (base_gross / days_in_month).quantize(Decimal("0.01")) \
        if days_in_month > 0 else Decimal("0.00")
    adjusted_gross = (daily_rate * payable).quantize(Decimal("0.01"))

    ded = compute_deductions(adjusted_gross)
    advance_out = await _outstanding_advance(db, employee_id)

    return AttendancePreview(
        employee_id=employee.id,
        employee_name=employee.full_name,
        emp_code=employee.emp_code,
        pay_period=pay_period,
        days_in_month=days_in_month,
        days_present=present,
        days_absent=absent,
        days_on_leave=on_leave,
        payable_days=payable,
        base_gross=base_gross,
        daily_rate=daily_rate,
        adjusted_gross=adjusted_gross,
        pf_employee=ded["pf_employee"],
        pf_employer=ded["pf_employer"],
        esi_employee=ded["esi_employee"],
        esi_employer=ded["esi_employer"],
        advance_outstanding=advance_out,
    )


@router.get("", response_model=list[SalaryOut])
async def list_salary(
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
    pay_period: str | None = Query(None, pattern=r"^\d{4}-\d{2}$"),
):
    stmt = (
        select(SalaryRecord, Employee.full_name)
        .join(Employee, Employee.id == SalaryRecord.employee_id)
        .order_by(SalaryRecord.pay_period.desc(), Employee.full_name)
    )
    if pay_period:
        stmt = stmt.where(SalaryRecord.pay_period == pay_period)

    result = await db.execute(stmt)
    out: list[SalaryOut] = []
    for record, name in result.all():
        item = SalaryOut.model_validate(record)
        item.employee_name = name
        out.append(item)
    return out


@router.post("", response_model=SalaryOut, status_code=201)
async def create_salary(
    payload: SalaryCreate,
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
):
    employee = await db.get(Employee, payload.employee_id)
    if employee is None:
        raise HTTPException(404, "Employee not found")

    # Compute the outstanding balance and reconcile against the payload
    outstanding_before = await _outstanding_advance(db, payload.employee_id)

    deduction = Decimal(str(payload.advance_deduction or 0)).quantize(Decimal("0.01"))
    if deduction < 0:
        raise HTTPException(400, "Advance deduction cannot be negative")
    if deduction > outstanding_before:
        raise HTTPException(
            400,
            f"Deduction ({deduction}) exceeds outstanding advance "
            f"({outstanding_before})",
        )

    balance_after = (outstanding_before - deduction).quantize(Decimal("0.01"))

    # Force the stored balance values (ignoring whatever the client sent)
    data = payload.model_dump()
    data["advance_balance_before"] = outstanding_before
    data["advance_balance_after"] = balance_after

    record = SalaryRecord(**data)
    db.add(record)
    await db.commit()
    await db.refresh(record)

    out = SalaryOut.model_validate(record)
    out.employee_name = employee.full_name
    return out


@router.patch("/{record_id}/paid", response_model=SalaryOut)
async def mark_salary_paid(
    record_id: int,
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
):
    record = await db.get(SalaryRecord, record_id)
    if record is None:
        raise HTTPException(404, "Salary record not found")

    record.paid = True
    record.paid_on = date.today()
    await db.commit()
    await db.refresh(record)
    return SalaryOut.model_validate(record)


@router.delete("/{record_id}", status_code=204)
async def delete_salary(
    record_id: int,
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
):
    record = await db.get(SalaryRecord, record_id)
    if record is None:
        raise HTTPException(404, "Salary record not found")
    await db.delete(record)
    await db.commit()


# ---------------------------------------------------------------------------
# Payslip PDF
# ---------------------------------------------------------------------------
from fastapi.responses import StreamingResponse  # noqa: E402
from app.payslip import generate_payslip_pdf  # noqa: E402


def _employee_dict(employee: Employee) -> dict:
    return {
        "emp_code": employee.emp_code,
        "full_name": employee.full_name,
        "designation": employee.designation,
        "department": employee.department,
        "date_of_joining": employee.date_of_joining,
        "pan": employee.pan,
        "uan": employee.uan,
        "esi_no": employee.esi_no,
        "bank_account": employee.bank_account,
    }


def _payroll_dict(record: SalaryRecord) -> dict:
    return {
        "pay_period": record.pay_period,
        "days_in_month": record.days_in_month,
        "days_present": record.days_present,
        "days_absent": record.days_absent,
        "days_on_leave": record.days_on_leave,
        "payable_days": record.payable_days,
        "daily_rate": record.daily_rate,
        "base_gross": record.base_gross,
        "gross": record.gross,
        "pf_employee": record.pf_employee,
        "pf_employer": record.pf_employer,
        "esi_employee": record.esi_employee,
        "esi_employer": record.esi_employer,
        "income_tax": record.income_tax,
        "other_deductions": record.other_deductions,
        "advance_deduction": record.advance_deduction,
        "advance_balance_before": record.advance_balance_before,
        "advance_balance_after": record.advance_balance_after,
        "net_pay": record.net_pay,
    }


@router.get("/{record_id}/payslip.pdf")
async def payslip_for_record(
    record_id: int,
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
):
    record = await db.get(SalaryRecord, record_id)
    if record is None:
        raise HTTPException(404, "Salary record not found")
    employee = await db.get(Employee, record.employee_id)
    if employee is None:
        raise HTTPException(404, "Employee not found")

    buffer = generate_payslip_pdf(_employee_dict(employee), _payroll_dict(record))
    filename = f"payslip-{employee.emp_code}-{record.pay_period}.pdf"
    return StreamingResponse(
        buffer,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )