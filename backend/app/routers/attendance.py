from calendar import monthrange
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user
from app.database import get_db
from app.models import (
    Attendance,
    AttendanceStatus,
    AuditLog,
    Employee,
    User,
)
from app.schemas import (
    AttendanceBulkCreate,
    AttendanceBulkResponse,
    AttendanceCreate,
    AttendanceMonthResponse,
    AttendanceMonthRow,
    AttendanceOut,
)

router = APIRouter(prefix="/attendance", tags=["attendance"])


async def _log(db, user, action, entity, entity_id, details=""):
    db.add(AuditLog(
        user_email=user.email,
        action=action,
        entity=entity,
        entity_id=entity_id,
        details=details,
    ))


@router.get("", response_model=list[AttendanceOut])
async def list_attendance(
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
    employee_id: int = Query(...),
    year: int = Query(...),
    month: int = Query(..., ge=1, le=12),
):
    start = date(year, month, 1)
    end = date(year, month, monthrange(year, month)[1])
    stmt = (
        select(Attendance)
        .where(
            Attendance.employee_id == employee_id,
            Attendance.attendance_date.between(start, end),
        )
        .order_by(Attendance.attendance_date)
    )
    return (await db.execute(stmt)).scalars().all()


@router.get("/month", response_model=AttendanceMonthResponse)
async def month_view(
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
    year: int = Query(...),
    month: int = Query(..., ge=1, le=12),
):
    days_in_month = monthrange(year, month)[1]
    start = date(year, month, 1)
    end = date(year, month, days_in_month)

    employees = (await db.execute(
        select(Employee)
        .where(Employee.is_active.is_(True))
        .order_by(Employee.full_name)
    )).scalars().all()

    rows = (await db.execute(
        select(Attendance)
        .where(Attendance.attendance_date.between(start, end))
    )).scalars().all()

    lookup: dict[int, dict[str, AttendanceStatus]] = {}
    for r in rows:
        lookup.setdefault(r.employee_id, {})[r.attendance_date.isoformat()] = r.status

    result: list[AttendanceMonthRow] = []
    for emp in employees:
        emp_map = lookup.get(emp.id, {})
        days: dict[str, AttendanceStatus | None] = {}
        present = absent = on_leave = 0
        for d in range(1, days_in_month + 1):
            key = date(year, month, d).isoformat()
            status = emp_map.get(key)
            days[key] = status
            if status == AttendanceStatus.present:
                present += 1
            elif status == AttendanceStatus.absent:
                absent += 1
            elif status == AttendanceStatus.on_leave:
                on_leave += 1

        result.append(AttendanceMonthRow(
            employee_id=emp.id,
            employee_name=emp.full_name,
            emp_code=emp.emp_code,
            days=days,
            present=present,
            absent=absent,
            on_leave=on_leave,
            payable_days=present,
        ))

    return AttendanceMonthResponse(
        year=year,
        month=month,
        days_in_month=days_in_month,
        employees=result,
    )


@router.post("", response_model=AttendanceOut, status_code=201)
async def upsert_attendance(
    payload: AttendanceCreate,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    existing = (await db.execute(
        select(Attendance).where(
            Attendance.employee_id == payload.employee_id,
            Attendance.attendance_date == payload.attendance_date,
        )
    )).scalar_one_or_none()

    if existing:
        existing.status = payload.status
        if payload.notes is not None:
            existing.notes = payload.notes
        existing.marked_by = user.email
        await db.commit()
        await db.refresh(existing)
        return existing

    record = Attendance(
        employee_id=payload.employee_id,
        attendance_date=payload.attendance_date,
        status=payload.status,
        notes=payload.notes,
        marked_by=user.email,
    )
    db.add(record)
    await _log(db, user, "create", "attendance",
               f"{payload.employee_id}/{payload.attendance_date}",
               f"Marked {payload.status.value}")
    await db.commit()
    await db.refresh(record)
    return record


@router.post("/bulk", response_model=AttendanceBulkResponse)
async def bulk_upsert(
    payload: AttendanceBulkCreate,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    count = 0
    for item in payload.entries:
        existing = (await db.execute(
            select(Attendance).where(
                Attendance.employee_id == item.employee_id,
                Attendance.attendance_date == item.attendance_date,
            )
        )).scalar_one_or_none()

        if existing:
            existing.status = item.status
            existing.marked_by = user.email
        else:
            db.add(Attendance(
                employee_id=item.employee_id,
                attendance_date=item.attendance_date,
                status=item.status,
                marked_by=user.email,
            ))
        count += 1

    await db.commit()
    return AttendanceBulkResponse(updated=count)


@router.delete("/{attendance_id}", status_code=204)
async def delete_attendance(
    attendance_id: int,
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
):
    record = await db.get(Attendance, attendance_id)
    if record is None:
        raise HTTPException(404, "Attendance entry not found")
    await db.delete(record)
    await db.commit()