from datetime import date, datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, EmailStr, Field

from app.models import (
    AttendanceStatus,
    EmployeeStatus,
    ExpenseCategory,
    UserRole,
)


# ---------------------------------------------------------------------------
# Financial statements
# ---------------------------------------------------------------------------
class ProfitLossOut(BaseModel):
    start: date
    end: date
    sales_revenue: Decimal
    purchases: Decimal
    gross_profit: Decimal
    commission_expense: Decimal
    compliance_expense: Decimal
    other_sales_expense: Decimal
    fixed_expenses: Decimal
    payroll_expense: Decimal
    total_expenses: Decimal
    net_profit: Decimal


class BalanceSheetInput(BaseModel):
    as_of_date: date
    cash_and_bank: Decimal = Field(
        default=Decimal("0.00"), ge=0, max_digits=14, decimal_places=2
    )
    accounts_receivable: Decimal = Field(
        default=Decimal("0.00"), ge=0, max_digits=14, decimal_places=2
    )
    inventory: Decimal = Field(
        default=Decimal("0.00"), ge=0, max_digits=14, decimal_places=2
    )
    other_current_assets: Decimal = Field(
        default=Decimal("0.00"), ge=0, max_digits=14, decimal_places=2
    )
    property_and_equipment: Decimal = Field(
        default=Decimal("0.00"), ge=0, max_digits=14, decimal_places=2
    )
    accounts_payable: Decimal = Field(
        default=Decimal("0.00"), ge=0, max_digits=14, decimal_places=2
    )
    loans_payable: Decimal = Field(
        default=Decimal("0.00"), ge=0, max_digits=14, decimal_places=2
    )
    gst_payable: Decimal = Field(
        default=Decimal("0.00"), ge=0, max_digits=14, decimal_places=2
    )
    other_liabilities: Decimal = Field(
        default=Decimal("0.00"), ge=0, max_digits=14, decimal_places=2
    )
    owner_capital: Decimal = Field(
        default=Decimal("0.00"), ge=0, max_digits=14, decimal_places=2
    )
    retained_earnings: Decimal = Field(
        default=Decimal("0.00"), max_digits=14, decimal_places=2
    )


class BalanceSheetOut(BalanceSheetInput):
    model_config = ConfigDict(from_attributes=True)

    id: int
    created_at: datetime
    updated_at: datetime | None = None
    total_assets: Decimal
    total_liabilities: Decimal
    total_equity: Decimal
    total_liabilities_and_equity: Decimal
    balanced: bool


# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------
class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    email: EmailStr
    full_name: str
    role: UserRole
    is_active: bool
    last_login_at: datetime | None = None
    created_at: datetime | None = None


class UserCreate(BaseModel):
    email: EmailStr
    full_name: str
    password: str = Field(min_length=8)
    role: UserRole = UserRole.counter
    is_active: bool = True


class UserUpdate(BaseModel):
    full_name: str | None = None
    role: UserRole | None = None
    is_active: bool | None = None


class PasswordReset(BaseModel):
    new_password: str = Field(min_length=8)


# ---------------------------------------------------------------------------
# Sales
# ---------------------------------------------------------------------------
class SaleBase(BaseModel):
    invoice_no: str
    period_start: date
    period_end: date
    customer: str
    notes: str | None = None

    transaction_value: Decimal = 0
    tds: Decimal = 0
    gst_payable: Decimal = 0

    commission_gross: Decimal = 0
    commission_base: Decimal = 0
    commission_gst: Decimal = 0
    compliance_gross: Decimal = 0
    compliance_base: Decimal = 0
    compliance_gst: Decimal = 0
    other_gross: Decimal = 0
    other_base: Decimal = 0
    other_gst: Decimal = 0

    total_gross: Decimal = 0
    net_receivable: Decimal = 0


class SaleCreate(SaleBase):
    pass


class SaleOut(SaleBase):
    model_config = ConfigDict(from_attributes=True)
    id: int
    created_at: datetime


# ---------------------------------------------------------------------------
# Purchases
# ---------------------------------------------------------------------------
class PurchaseBase(BaseModel):
    bill_no: str
    purchase_date: date
    vendor: str
    amount: Decimal
    gst: Decimal = 0
    total: Decimal
    notes: str | None = None


class PurchaseCreate(PurchaseBase):
    pass


class PurchaseOut(PurchaseBase):
    model_config = ConfigDict(from_attributes=True)
    id: int
    created_at: datetime


# ---------------------------------------------------------------------------
# Fixed Expenses
# ---------------------------------------------------------------------------
class ExpenseBase(BaseModel):
    category: ExpenseCategory
    description: str
    amount: Decimal
    expense_date: date
    due_date: date | None = None
    is_paid: bool = False
    notes: str | None = None


class ExpenseCreate(ExpenseBase):
    pass


class ExpenseOut(ExpenseBase):
    model_config = ConfigDict(from_attributes=True)
    id: int
    created_at: datetime


# ---------------------------------------------------------------------------
# Employees
# ---------------------------------------------------------------------------
class EmployeeBase(BaseModel):
    emp_code: str
    full_name: str
    designation: str
    department: str | None = None
    date_of_joining: date

    status: EmployeeStatus = EmployeeStatus.active
    date_of_leaving: date | None = None
    all_dues_clear: bool = False
    no_dues_email: str | None = None

    basic_salary: Decimal
    hra: Decimal = 0
    allowances: Decimal = 0

    pan: str | None = None
    uan: str | None = None
    esi_no: str | None = None
    bank_account: str | None = None

    is_active: bool = True


class EmployeeCreate(EmployeeBase):
    pass


class EmployeeOut(EmployeeBase):
    model_config = ConfigDict(from_attributes=True)
    id: int


# ---------------------------------------------------------------------------
# Attendance
# ---------------------------------------------------------------------------
class AttendanceCreate(BaseModel):
    employee_id: int
    attendance_date: date
    status: AttendanceStatus
    notes: str | None = None


class AttendanceBulkItem(BaseModel):
    employee_id: int
    attendance_date: date
    status: AttendanceStatus


class AttendanceBulkCreate(BaseModel):
    entries: list[AttendanceBulkItem]


class AttendanceBulkResponse(BaseModel):
    updated: int


class AttendanceOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    employee_id: int
    attendance_date: date
    status: AttendanceStatus
    notes: str | None
    marked_by: str | None


class AttendanceMonthRow(BaseModel):
    employee_id: int
    employee_name: str
    emp_code: str
    days: dict[str, AttendanceStatus | None]
    present: int
    absent: int
    on_leave: int
    payable_days: int


class AttendanceMonthResponse(BaseModel):
    year: int
    month: int
    days_in_month: int
    employees: list[AttendanceMonthRow]


class AttendancePreview(BaseModel):
    employee_id: int
    employee_name: str
    emp_code: str
    pay_period: str
    days_in_month: int
    days_present: int
    days_absent: int
    days_on_leave: int
    payable_days: int
    base_gross: Decimal
    daily_rate: Decimal
    adjusted_gross: Decimal
    pf_employee: Decimal
    pf_employer: Decimal
    esi_employee: Decimal
    esi_employer: Decimal
    advance_outstanding: Decimal


# ---------------------------------------------------------------------------
# Salary Advances
# ---------------------------------------------------------------------------
class SalaryAdvanceCreate(BaseModel):
    employee_id: int
    amount: Decimal = Field(gt=0)
    advance_date: date
    reason: str | None = None
    notes: str | None = None


class SalaryAdvanceOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    employee_id: int
    employee_name: str | None = None
    amount: Decimal
    advance_date: date
    reason: str | None
    notes: str | None
    created_by: str | None
    created_at: datetime


class AdvanceBalance(BaseModel):
    employee_id: int
    employee_name: str
    total_advances: Decimal
    total_recovered: Decimal
    outstanding: Decimal


# ---------------------------------------------------------------------------
# Salary
# ---------------------------------------------------------------------------
class SalaryBase(BaseModel):
    employee_id: int
    pay_period: str = Field(pattern=r"^\d{4}-\d{2}$")

    days_in_month: int = 0
    days_present: int = 0
    days_absent: int = 0
    days_on_leave: int = 0
    payable_days: int = 0
    daily_rate: Decimal = 0
    base_gross: Decimal = 0

    gross: Decimal
    pf_employee: Decimal = 0
    pf_employer: Decimal = 0
    esi_employee: Decimal = 0
    esi_employer: Decimal = 0
    income_tax: Decimal = 0
    other_deductions: Decimal = 0

    advance_deduction: Decimal = 0
    advance_balance_before: Decimal = 0
    advance_balance_after: Decimal = 0

    net_pay: Decimal
    paid: bool = False
    paid_on: date | None = None
    notes: str | None = None


class SalaryCreate(SalaryBase):
    pass


class SalaryOut(SalaryBase):
    model_config = ConfigDict(from_attributes=True)
    id: int
    employee_name: str | None = None


# ---------------------------------------------------------------------------
# Dashboard
# ---------------------------------------------------------------------------
class DashboardSummary(BaseModel):
    period_start: date
    period_end: date
    total_transaction_value: Decimal
    total_tds: Decimal
    total_gst_payable: Decimal
    total_commission: Decimal
    total_compliance: Decimal
    total_other: Decimal
    total_charges: Decimal
    total_net_payable: Decimal
    total_purchases: Decimal
    total_fixed_expenses: Decimal
    total_salary_paid: Decimal
    total_advances_outstanding: Decimal = 0
    net_position: Decimal


# ---------------------------------------------------------------------------
# Audit
# ---------------------------------------------------------------------------
class AuditOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    user_email: str | None
    action: str
    entity: str
    entity_id: str | None
    details: str | None
    ip_address: str | None
    created_at: datetime


# ---------------------------------------------------------------------------
# Admin / Health
# ---------------------------------------------------------------------------
class HealthResponse(BaseModel):
    status: str
    environment: str
    version: str
    database: str
    uptime_seconds: float
    db_ok: bool
    db_latency_ms: float
    cpu_percent: float
    memory_percent: float
    disk_percent: float
    log_file: str
    log_size_bytes: int
    request_count: int
    error_count: int
    user_count: int
    active_session_count: int


class ServerLogEntry(BaseModel):
    timestamp: str
    level: str
    logger: str
    message: str


class ServerLogResponse(BaseModel):
    entries: list[ServerLogEntry]
    total_matched: int
    file_size_bytes: int
    lines_scanned: int


# ---------------------------------------------------------------------------
# Documents
# ---------------------------------------------------------------------------
class DocumentVersionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    version: int
    original_filename: str
    content_type: str | None
    file_size: int
    notes: str | None
    uploaded_by: str | None
    uploaded_at: datetime


class DocumentOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    title: str
    category: str
    description: str | None
    current_version: int
    is_active: bool
    created_by: str | None
    created_at: datetime
    versions: list[DocumentVersionOut] = []


class DocumentCreate(BaseModel):
    title: str
    category: str = "general"
    description: str | None = None