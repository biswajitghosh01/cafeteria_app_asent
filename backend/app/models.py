import enum
from datetime import date, datetime
from decimal import Decimal

from sqlalchemy import (
    Boolean,
    Date,
    DateTime,
    Enum,
    ForeignKey,
    Numeric,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class UserRole(str, enum.Enum):
    admin = "admin"
    counter = "counter"


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    full_name: Mapped[str] = mapped_column(String(255))
    hashed_password: Mapped[str] = mapped_column(String(255))
    role: Mapped[UserRole] = mapped_column(Enum(UserRole), default=UserRole.counter)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    last_login_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class Sale(Base):
    __tablename__ = "sales"

    id: Mapped[int] = mapped_column(primary_key=True)
    invoice_no: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    period_start: Mapped[date] = mapped_column(Date, index=True)
    period_end: Mapped[date] = mapped_column(Date, index=True)
    customer: Mapped[str] = mapped_column(String(255))
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)

    transaction_value: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    tds: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    gst_payable: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)

    commission_gross: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    commission_base: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    commission_gst: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)

    compliance_gross: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    compliance_base: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    compliance_gst: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)

    other_gross: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    other_base: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    other_gst: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)

    total_gross: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    net_receivable: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    created_by: Mapped[int | None] = mapped_column(ForeignKey("users.id"))


class Purchase(Base):
    __tablename__ = "purchases"

    id: Mapped[int] = mapped_column(primary_key=True)
    bill_no: Mapped[str] = mapped_column(String(64), index=True)
    purchase_date: Mapped[date] = mapped_column(Date, index=True)
    vendor: Mapped[str] = mapped_column(String(255))
    amount: Mapped[Decimal] = mapped_column(Numeric(14, 2))
    gst: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    total: Mapped[Decimal] = mapped_column(Numeric(14, 2))
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class ExpenseCategory(str, enum.Enum):
    rent = "rent"
    electricity = "electricity"
    maintenance = "maintenance"
    other = "other"


class FixedExpense(Base):
    __tablename__ = "fixed_expenses"

    id: Mapped[int] = mapped_column(primary_key=True)
    category: Mapped[ExpenseCategory] = mapped_column(Enum(ExpenseCategory))
    description: Mapped[str] = mapped_column(String(255))
    amount: Mapped[Decimal] = mapped_column(Numeric(14, 2))
    expense_date: Mapped[date] = mapped_column(Date, index=True)
    due_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    is_paid: Mapped[bool] = mapped_column(Boolean, default=False)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class BalanceSheetSnapshot(Base):
    __tablename__ = "balance_sheet_snapshots"

    id: Mapped[int] = mapped_column(primary_key=True)
    as_of_date: Mapped[date] = mapped_column(Date, unique=True, index=True)

    cash_and_bank: Mapped[Decimal] = mapped_column(
        Numeric(14, 2), default=Decimal("0.00")
    )
    accounts_receivable: Mapped[Decimal] = mapped_column(
        Numeric(14, 2), default=Decimal("0.00")
    )
    inventory: Mapped[Decimal] = mapped_column(
        Numeric(14, 2), default=Decimal("0.00")
    )
    other_current_assets: Mapped[Decimal] = mapped_column(
        Numeric(14, 2), default=Decimal("0.00")
    )
    property_and_equipment: Mapped[Decimal] = mapped_column(
        Numeric(14, 2), default=Decimal("0.00")
    )

    accounts_payable: Mapped[Decimal] = mapped_column(
        Numeric(14, 2), default=Decimal("0.00")
    )
    loans_payable: Mapped[Decimal] = mapped_column(
        Numeric(14, 2), default=Decimal("0.00")
    )
    gst_payable: Mapped[Decimal] = mapped_column(
        Numeric(14, 2), default=Decimal("0.00")
    )
    other_liabilities: Mapped[Decimal] = mapped_column(
        Numeric(14, 2), default=Decimal("0.00")
    )

    owner_capital: Mapped[Decimal] = mapped_column(
        Numeric(14, 2), default=Decimal("0.00")
    )
    retained_earnings: Mapped[Decimal] = mapped_column(
        Numeric(14, 2), default=Decimal("0.00")
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class EmployeeStatus(str, enum.Enum):
    active = "active"
    on_notice = "on_notice"
    resigned = "resigned"
    terminated = "terminated"
    retired = "retired"


class Employee(Base):
    __tablename__ = "employees"

    id: Mapped[int] = mapped_column(primary_key=True)
    emp_code: Mapped[str] = mapped_column(String(32), unique=True, index=True)
    full_name: Mapped[str] = mapped_column(String(255))
    designation: Mapped[str] = mapped_column(String(128))
    department: Mapped[str | None] = mapped_column(String(128), nullable=True)
    date_of_joining: Mapped[date] = mapped_column(Date)

    status: Mapped[EmployeeStatus] = mapped_column(
        Enum(EmployeeStatus), default=EmployeeStatus.active
    )
    date_of_leaving: Mapped[date | None] = mapped_column(Date, nullable=True)
    all_dues_clear: Mapped[bool] = mapped_column(Boolean, default=False)
    no_dues_email: Mapped[str | None] = mapped_column(String(255), nullable=True)

    basic_salary: Mapped[Decimal] = mapped_column(Numeric(14, 2))
    hra: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    allowances: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)

    pan: Mapped[str | None] = mapped_column(String(16), nullable=True)
    uan: Mapped[str | None] = mapped_column(String(20), nullable=True)
    esi_no: Mapped[str | None] = mapped_column(String(20), nullable=True)
    bank_account: Mapped[str | None] = mapped_column(String(32), nullable=True)

    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    salary_records: Mapped[list["SalaryRecord"]] = relationship(
        back_populates="employee", cascade="all, delete-orphan"
    )
    attendance_records: Mapped[list["Attendance"]] = relationship(
        back_populates="employee", cascade="all, delete-orphan"
    )
    advances: Mapped[list["SalaryAdvance"]] = relationship(
        back_populates="employee", cascade="all, delete-orphan"
    )


class AttendanceStatus(str, enum.Enum):
    present = "present"
    absent = "absent"
    on_leave = "on_leave"


class Attendance(Base):
    __tablename__ = "attendance"

    id: Mapped[int] = mapped_column(primary_key=True)
    employee_id: Mapped[int] = mapped_column(
        ForeignKey("employees.id", ondelete="CASCADE"), index=True
    )
    attendance_date: Mapped[date] = mapped_column(Date, index=True)
    status: Mapped[AttendanceStatus] = mapped_column(Enum(AttendanceStatus))
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    marked_by: Mapped[str | None] = mapped_column(String(255), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    employee: Mapped[Employee] = relationship(back_populates="attendance_records")

    __table_args__ = (
        UniqueConstraint(
            "employee_id", "attendance_date",
            name="uq_attendance_employee_date",
        ),
    )


class SalaryAdvance(Base):
    """A salary advance or loan given to an employee.

    The amount is recovered over one or more payslips via the
    ``advance_deduction`` field on SalaryRecord.
    """

    __tablename__ = "salary_advances"

    id: Mapped[int] = mapped_column(primary_key=True)
    employee_id: Mapped[int] = mapped_column(
        ForeignKey("employees.id", ondelete="CASCADE"), index=True
    )
    amount: Mapped[Decimal] = mapped_column(Numeric(14, 2))
    advance_date: Mapped[date] = mapped_column(Date, index=True)
    reason: Mapped[str | None] = mapped_column(String(255), nullable=True)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)

    created_by: Mapped[str | None] = mapped_column(String(255), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    employee: Mapped[Employee] = relationship(back_populates="advances")


class SalaryRecord(Base):
    __tablename__ = "salary_records"

    id: Mapped[int] = mapped_column(primary_key=True)
    employee_id: Mapped[int] = mapped_column(ForeignKey("employees.id"))
    pay_period: Mapped[str] = mapped_column(String(7), index=True)

    # Attendance-based computation
    days_in_month: Mapped[int] = mapped_column(default=0)
    days_present: Mapped[int] = mapped_column(default=0)
    days_absent: Mapped[int] = mapped_column(default=0)
    days_on_leave: Mapped[int] = mapped_column(default=0)
    payable_days: Mapped[int] = mapped_column(default=0)
    daily_rate: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    base_gross: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)

    # Actual pay
    gross: Mapped[Decimal] = mapped_column(Numeric(14, 2))
    pf_employee: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    pf_employer: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    esi_employee: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    esi_employer: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    income_tax: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    other_deductions: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)

    # Advance recovery
    advance_deduction: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    advance_balance_before: Mapped[Decimal] = mapped_column(
        Numeric(14, 2), default=0
    )
    advance_balance_after: Mapped[Decimal] = mapped_column(
        Numeric(14, 2), default=0
    )

    net_pay: Mapped[Decimal] = mapped_column(Numeric(14, 2))

    paid: Mapped[bool] = mapped_column(Boolean, default=False)
    paid_on: Mapped[date | None] = mapped_column(Date, nullable=True)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    employee: Mapped[Employee] = relationship(back_populates="salary_records")


class AuditLog(Base):
    __tablename__ = "audit_logs"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_email: Mapped[str | None] = mapped_column(
        String(255), nullable=True, index=True
    )
    action: Mapped[str] = mapped_column(String(64), index=True)
    entity: Mapped[str] = mapped_column(String(64), index=True)
    entity_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    details: Mapped[str | None] = mapped_column(Text, nullable=True)
    ip_address: Mapped[str | None] = mapped_column(String(64), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), index=True
    )


class Document(Base):
    __tablename__ = "documents"

    id: Mapped[int] = mapped_column(primary_key=True)
    title: Mapped[str] = mapped_column(String(255), index=True)
    category: Mapped[str] = mapped_column(String(64), index=True)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)

    current_version: Mapped[int] = mapped_column(default=0)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)

    created_by: Mapped[str | None] = mapped_column(String(255), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    versions: Mapped[list["DocumentVersion"]] = relationship(
        back_populates="document",
        cascade="all, delete-orphan",
        order_by="DocumentVersion.version.desc()",
    )


class DocumentVersion(Base):
    __tablename__ = "document_versions"

    id: Mapped[int] = mapped_column(primary_key=True)
    document_id: Mapped[int] = mapped_column(
        ForeignKey("documents.id", ondelete="CASCADE")
    )

    version: Mapped[int] = mapped_column()
    original_filename: Mapped[str] = mapped_column(String(255))
    stored_path: Mapped[str] = mapped_column(String(512))
    content_type: Mapped[str | None] = mapped_column(String(128), nullable=True)
    file_size: Mapped[int] = mapped_column(default=0)

    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    uploaded_by: Mapped[str | None] = mapped_column(String(255), nullable=True)
    uploaded_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    document: Mapped[Document] = relationship(back_populates="versions")