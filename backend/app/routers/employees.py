from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user
from app.database import get_db
from app.models import Employee, User
from app.schemas import EmployeeCreate, EmployeeOut

router = APIRouter(prefix="/employees", tags=["employees"])


@router.get("", response_model=list[EmployeeOut])
async def list_employees(
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
    include_inactive: bool = Query(
        False, description="Include employees marked as not visible in lists"
    ),
):
    stmt = select(Employee).order_by(Employee.full_name)
    if not include_inactive:
        stmt = stmt.where(Employee.is_active.is_(True))
    result = await db.execute(stmt)
    return result.scalars().all()


@router.get("/{employee_id}", response_model=EmployeeOut)
async def get_employee(
    employee_id: int,
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
):
    emp = await db.get(Employee, employee_id)
    if emp is None:
        raise HTTPException(404, "Employee not found")
    return emp


@router.post("", response_model=EmployeeOut, status_code=201)
async def create_employee(
    payload: EmployeeCreate,
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
):
    existing = (
        await db.execute(select(Employee).where(Employee.emp_code == payload.emp_code))
    ).scalar_one_or_none()
    if existing:
        raise HTTPException(409, "Employee code already exists")

    emp = Employee(**payload.model_dump())
    db.add(emp)
    await db.commit()
    await db.refresh(emp)
    return emp


@router.put("/{employee_id}", response_model=EmployeeOut)
async def update_employee(
    employee_id: int,
    payload: EmployeeCreate,
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
):
    emp = await db.get(Employee, employee_id)
    if emp is None:
        raise HTTPException(404, "Employee not found")

    # If emp_code is being changed, ensure it remains unique
    if payload.emp_code != emp.emp_code:
        clash = (
            await db.execute(
                select(Employee).where(
                    Employee.emp_code == payload.emp_code,
                    Employee.id != employee_id,
                )
            )
        ).scalar_one_or_none()
        if clash:
            raise HTTPException(409, "Employee code already exists")

    for key, value in payload.model_dump().items():
        setattr(emp, key, value)

    await db.commit()
    await db.refresh(emp)
    return emp


@router.delete("/{employee_id}", status_code=204)
async def delete_employee(
    employee_id: int,
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
):
    emp = await db.get(Employee, employee_id)
    if emp is None:
        raise HTTPException(404, "Employee not found")
    await db.delete(emp)
    await db.commit()