#!/usr/bin/env bash
# =============================================================================
# Food Court Counter — Consolidated Bootstrap
#
# Wipes any existing project folder and rebuilds everything from scratch:
#   • FastAPI backend (SQLite dev fallback + PostgreSQL production)
#   • React/Vite frontend with Admin Console
#   • Local dev + Ubuntu production deployment scripts
#
# Usage:
#   chmod +x bootstrap.sh
#   ./bootstrap.sh                   # prompts before wiping existing folder
#   FORCE=1 ./bootstrap.sh           # wipe without prompting
#   ./bootstrap.sh my-project        # custom folder name
# =============================================================================
set -euo pipefail

ROOT="${1:-food-court-counter}"
FORCE="${FORCE:-0}"

say()  { printf '\033[1;34m▸\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# =============================================================================
# STEP 0 — Wipe existing folder
# =============================================================================
if [[ -e "$ROOT" ]]; then
  warn "Folder '$ROOT' already exists."
  if [[ "$FORCE" != "1" ]]; then
    read -r -p "Delete and rebuild from scratch? [y/N] " yn
    [[ "${yn:-N}" =~ ^[Yy] ]] || die "Aborted."
  fi
  rm -rf "$ROOT"
  ok "Removed existing '$ROOT'"
fi

say "Creating fresh directory structure under ./$ROOT"
mkdir -p "$ROOT"/{backend/app/routers,frontend/{public/assets/companies,src/{components/{Layout,ui},config,context,lib,pages/admin,styles}},deploy/{apache,systemd,scripts}}

# =============================================================================
# ROOT FILES
# =============================================================================

cat > "$ROOT/.gitignore" <<'EOF'
node_modules/
.venv/
__pycache__/
*.pyc
frontend/dist/
frontend/.vite/
.env
.env.*
!.env.example
*.log
logs/
*.db
*.sqlite3
.DS_Store
Thumbs.db
*.sql
backup-*
EOF

cat > "$ROOT/README.md" <<'EOF'
# Food Court Counter

Multi-company operations platform: sales, purchases, fixed expenses,
employee salary with PF / ESI / Income Tax deductions, statutory payments,
reports, audit logs, and a dedicated Admin Console.

## Stack

| Layer      | Dev                           | Production                     |
|------------|-------------------------------|--------------------------------|
| Frontend   | Vite dev server (:5173)       | Apache static + reverse proxy  |
| Backend    | Uvicorn --reload (:8000)      | Gunicorn/Uvicorn via systemd   |
| Database   | SQLite (auto, zero setup)     | PostgreSQL 14+                 |

## Default Users (seeded on first launch)

| Role    | Email                 | Password      | Access                     |
|---------|-----------------------|---------------|----------------------------|
| Admin   | admin@example.com     | Admin@12345   | Full app + Admin Console   |
| Counter | counter@example.com   | Counter@12345 | Sales/purchases/expenses   |

Change both immediately in production via Admin Console → Users.

## Quick Start (Local)

    ./deploy/scripts/setup-local.sh
    # Terminal 1
    cd backend && source .venv/bin/activate && uvicorn app.main:app --reload
    # Terminal 2
    cd frontend && npm run dev

Open http://localhost:5173

Backend works out of the box on SQLite — no PostgreSQL required.

## Quick Start (Ubuntu Server)

    export DOMAIN=counter.example.com
    export LETSENCRYPT_EMAIL=admin@example.com
    sudo -v && ./deploy/scripts/deploy-ubuntu.sh

## Admin Console (/admin)

Visible only to `admin` role. Four tabs:

1. System Health — uptime, DB latency, CPU/mem/disk, request + error counters
2. User Management — create / edit / disable / reset password / delete
3. Application Logs — audit trail with filters (action, entity, user)
4. Server Logs — tail of rotating file log with level filter + download

## Sales Components

1. Commission (Including GST)
2. CLRA Charges (Including GST)
3. Compliance Fee (Including GST)
4. Other Charges (Including GST)
5. TDS
6. GST Payable

GST auto-split at 18% into base + GST per component.

## Fixed Expenses

Rent · Electricity · Maintenance · Other (custom)

## Salary & Statutory

- PF: 12% employee + 12% employer, wage ceiling 15,000
- ESI: 0.75% / 3.25%, gross ceiling 21,000
- Income Tax: entered per slab

## Log Locations (Production)

| Log             | Path                                       |
|-----------------|--------------------------------------------|
| Application     | /var/log/food-court-counter/api.log        |
| Apache access   | /var/log/apache2/food-court-access.log     |
| Apache error    | /var/log/apache2/food-court-error.log      |
| systemd         | journalctl -u food-court-api               |

## Security Checklist

- [ ] Change both default passwords on first login
- [ ] Random SECRET_KEY (32+ bytes)
- [ ] ENVIRONMENT=production in production
- [ ] Enforce HTTPS (Certbot)
- [ ] UFW: allow 22, 80, 443 only
- [ ] Never expose port 8000 publicly
- [ ] Nightly PostgreSQL backups
- [ ] Treat all VITE_* values as public
- [ ] Never commit .env

## License

Proprietary — All rights reserved.
EOF

# =============================================================================
# BACKEND
# =============================================================================

cat > "$ROOT/backend/requirements.txt" <<'EOF'
fastapi==0.115.6
uvicorn[standard]==0.34.0
gunicorn==23.0.0
sqlalchemy==2.0.36
asyncpg==0.30.0
aiosqlite==0.20.0
alembic==1.14.0
pydantic==2.10.4
pydantic-settings==2.7.0
python-jose[cryptography]==3.3.0
passlib[bcrypt]==1.7.4
python-multipart==0.0.20
openpyxl==3.1.5
reportlab==4.2.5
psutil==6.1.1
EOF

cat > "$ROOT/backend/.env.example" <<'EOF'
APP_NAME="Food Court Counter API"
ENVIRONMENT=development
DEBUG=True

HOST=0.0.0.0
PORT=8000

# In development, leave the placeholder and the app auto-uses SQLite.
# In production, provide a real postgresql+asyncpg:// URL.
DATABASE_URL=postgresql+asyncpg://fc_user:ChangeThisStrongPassword@localhost:5432/food_court_db

SECRET_KEY=replace-with-a-32-byte-random-hex
ACCESS_TOKEN_EXPIRE_MINUTES=720

BACKEND_CORS_ORIGINS=http://localhost:5173,http://localhost:8080

DEFAULT_ADMIN_EMAIL=admin@example.com
DEFAULT_ADMIN_PASSWORD=Admin@12345
DEFAULT_COUNTER_EMAIL=counter@example.com
DEFAULT_COUNTER_PASSWORD=Counter@12345

LOG_DIR=./logs
LOG_LEVEL=INFO
LOG_MAX_BYTES=10485760
LOG_BACKUP_COUNT=5
EOF

cat > "$ROOT/backend/app/__init__.py" <<'EOF'
__version__ = "1.0.1"
EOF

cat > "$ROOT/backend/app/config.py" <<'EOF'
from functools import lru_cache
from pydantic_settings import BaseSettings, SettingsConfigDict

PLACEHOLDER_MARKERS = ("ChangeThisStrongPassword", "replace-me", "changeme")


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_name: str = "Food Court Counter API"
    environment: str = "development"
    debug: bool = True
    host: str = "0.0.0.0"
    port: int = 8000

    database_url: str = ""
    secret_key: str = "dev-only-insecure-key-change-me"
    access_token_expire_minutes: int = 720
    algorithm: str = "HS256"

    backend_cors_origins: str = "http://localhost:5173"

    default_admin_email: str = "admin@example.com"
    default_admin_password: str = "Admin@12345"
    default_counter_email: str = "counter@example.com"
    default_counter_password: str = "Counter@12345"

    log_dir: str = "./logs"
    log_level: str = "INFO"
    log_max_bytes: int = 10 * 1024 * 1024
    log_backup_count: int = 5

    @property
    def cors_origins(self) -> list[str]:
        return [o.strip() for o in self.backend_cors_origins.split(",") if o.strip()]

    def _is_placeholder(self) -> bool:
        url = (self.database_url or "").strip()
        if not url:
            return True
        return any(m in url for m in PLACEHOLDER_MARKERS)

    @property
    def resolved_database_url(self) -> str:
        if self._is_placeholder():
            if self.environment == "production":
                raise RuntimeError(
                    "DATABASE_URL is unset or contains a placeholder while "
                    "ENVIRONMENT=production. Set a real postgresql+asyncpg:// URL."
                )
            return "sqlite+aiosqlite:///./food_court_dev.db"
        return self.database_url.strip()

    @property
    def is_sqlite(self) -> bool:
        return self.resolved_database_url.startswith("sqlite")


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
EOF

cat > "$ROOT/backend/app/database.py" <<'EOF'
from collections.abc import AsyncGenerator
from sqlalchemy.ext.asyncio import (
    AsyncSession, async_sessionmaker, create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase
from app.config import settings


class Base(DeclarativeBase):
    pass


_url = settings.resolved_database_url
_kwargs: dict = {"echo": False, "future": True}
if _url.startswith("sqlite"):
    _kwargs["connect_args"] = {"check_same_thread": False}
else:
    _kwargs["pool_pre_ping"] = True

engine = create_async_engine(_url, **_kwargs)
SessionLocal = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with SessionLocal() as session:
        yield session
EOF

cat > "$ROOT/backend/app/logging_config.py" <<'EOF'
import logging, logging.handlers, os
from pathlib import Path
from app.config import settings


def configure_logging() -> Path:
    log_dir = Path(settings.log_dir)
    log_dir.mkdir(parents=True, exist_ok=True)
    log_path = log_dir / "api.log"
    level = getattr(logging, settings.log_level.upper(), logging.INFO)
    root = logging.getLogger()
    root.setLevel(level)
    for h in list(root.handlers):
        root.removeHandler(h)
    fmt = logging.Formatter(
        "%(asctime)s | %(levelname)-7s | %(name)s | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )
    fh = logging.handlers.RotatingFileHandler(
        log_path, maxBytes=settings.log_max_bytes,
        backupCount=settings.log_backup_count, encoding="utf-8",
    )
    fh.setFormatter(fmt)
    root.addHandler(fh)
    ch = logging.StreamHandler()
    ch.setFormatter(fmt)
    root.addHandler(ch)
    logging.getLogger("uvicorn.access").setLevel(logging.WARNING)
    logging.getLogger("sqlalchemy.engine").setLevel(logging.WARNING)
    if os.getenv("LOG_TO_FILE_ONLY"):
        root.removeHandler(ch)
    return log_path


def get_log_path() -> Path:
    return Path(settings.log_dir) / "api.log"
EOF

cat > "$ROOT/backend/app/middleware.py" <<'EOF'
import logging, time
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request

access_logger = logging.getLogger("food-court.access")


class RequestLoggingMiddleware(BaseHTTPMiddleware):
    SKIP_PREFIXES = ("/api/health",)

    async def dispatch(self, request: Request, call_next):
        if request.url.path.startswith(self.SKIP_PREFIXES):
            return await call_next(request)
        start = time.perf_counter()
        client = request.client.host if request.client else "-"
        try:
            response = await call_next(request)
            code = response.status_code
        except Exception as exc:
            ms = (time.perf_counter() - start) * 1000
            access_logger.exception(
                "%s %s | 500 | %.1fms | %s | %s",
                request.method, request.url.path, ms, client, exc,
            )
            raise
        ms = (time.perf_counter() - start) * 1000
        access_logger.info(
            "%s %s | %d | %.1fms | %s",
            request.method, request.url.path, code, ms, client,
        )
        return response
EOF

cat > "$ROOT/backend/app/auth.py" <<'EOF'
from datetime import datetime, timedelta, timezone
from typing import Annotated
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt
from passlib.context import CryptContext
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.database import get_db
from app.models import User, UserRole

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/auth/login")


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)


def create_access_token(subject: str, role: str) -> str:
    expires = datetime.now(timezone.utc) + timedelta(
        minutes=settings.access_token_expire_minutes
    )
    return jwt.encode(
        {"sub": subject, "role": role, "exp": expires},
        settings.secret_key, algorithm=settings.algorithm,
    )


async def get_current_user(
    token: Annotated[str, Depends(oauth2_scheme)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> User:
    err = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, settings.secret_key, algorithms=[settings.algorithm])
        email = payload.get("sub")
        if not email:
            raise err
    except JWTError as exc:
        raise err from exc
    user = (await db.execute(select(User).where(User.email == email))).scalar_one_or_none()
    if not user or not user.is_active:
        raise err
    return user


def require_admin(user: Annotated[User, Depends(get_current_user)]) -> User:
    if user.role != UserRole.admin:
        raise HTTPException(status_code=403, detail="Administrator privileges required")
    return user
EOF

cat > "$ROOT/backend/app/models.py" <<'EOF'
import enum
from datetime import date, datetime
from decimal import Decimal
from sqlalchemy import (
    Boolean, Date, DateTime, Enum, ForeignKey, Numeric, String, Text, func,
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
    last_login_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Sale(Base):
    __tablename__ = "sales"
    id: Mapped[int] = mapped_column(primary_key=True)
    invoice_no: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    sale_date: Mapped[date] = mapped_column(Date, index=True)
    customer: Mapped[str] = mapped_column(String(255))
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    commission_gross: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    commission_base: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    commission_gst: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    clra_gross: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    clra_base: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    clra_gst: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    compliance_gross: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    compliance_base: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    compliance_gst: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    other_gross: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    other_base: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    other_gst: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    tds: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    gst_payable: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    total_gross: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    net_receivable: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
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
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


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
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Employee(Base):
    __tablename__ = "employees"
    id: Mapped[int] = mapped_column(primary_key=True)
    emp_code: Mapped[str] = mapped_column(String(32), unique=True, index=True)
    full_name: Mapped[str] = mapped_column(String(255))
    designation: Mapped[str] = mapped_column(String(128))
    department: Mapped[str | None] = mapped_column(String(128), nullable=True)
    date_of_joining: Mapped[date] = mapped_column(Date)
    basic_salary: Mapped[Decimal] = mapped_column(Numeric(14, 2))
    hra: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    allowances: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    pan: Mapped[str | None] = mapped_column(String(16), nullable=True)
    uan: Mapped[str | None] = mapped_column(String(20), nullable=True)
    esi_no: Mapped[str | None] = mapped_column(String(20), nullable=True)
    bank_account: Mapped[str | None] = mapped_column(String(32), nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    salary_records: Mapped[list["SalaryRecord"]] = relationship(back_populates="employee", cascade="all, delete-orphan")


class SalaryRecord(Base):
    __tablename__ = "salary_records"
    id: Mapped[int] = mapped_column(primary_key=True)
    employee_id: Mapped[int] = mapped_column(ForeignKey("employees.id"))
    pay_period: Mapped[str] = mapped_column(String(7), index=True)
    gross: Mapped[Decimal] = mapped_column(Numeric(14, 2))
    pf_employee: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    pf_employer: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    esi_employee: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    esi_employer: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    income_tax: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    other_deductions: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    net_pay: Mapped[Decimal] = mapped_column(Numeric(14, 2))
    paid: Mapped[bool] = mapped_column(Boolean, default=False)
    paid_on: Mapped[date | None] = mapped_column(Date, nullable=True)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    employee: Mapped[Employee] = relationship(back_populates="salary_records")


class AuditLog(Base):
    __tablename__ = "audit_logs"
    id: Mapped[int] = mapped_column(primary_key=True)
    user_email: Mapped[str | None] = mapped_column(String(255), nullable=True, index=True)
    action: Mapped[str] = mapped_column(String(64), index=True)
    entity: Mapped[str] = mapped_column(String(64), index=True)
    entity_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    details: Mapped[str | None] = mapped_column(Text, nullable=True)
    ip_address: Mapped[str | None] = mapped_column(String(64), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), index=True)
EOF

cat > "$ROOT/backend/app/schemas.py" <<'EOF'
from datetime import date, datetime
from decimal import Decimal
from pydantic import BaseModel, ConfigDict, EmailStr, Field
from app.models import ExpenseCategory, UserRole


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


class SaleBase(BaseModel):
    invoice_no: str
    sale_date: date
    customer: str
    notes: str | None = None
    commission_gross: Decimal = 0
    commission_base: Decimal = 0
    commission_gst: Decimal = 0
    clra_gross: Decimal = 0
    clra_base: Decimal = 0
    clra_gst: Decimal = 0
    compliance_gross: Decimal = 0
    compliance_base: Decimal = 0
    compliance_gst: Decimal = 0
    other_gross: Decimal = 0
    other_base: Decimal = 0
    other_gst: Decimal = 0
    tds: Decimal = 0
    gst_payable: Decimal = 0
    total_gross: Decimal = 0
    net_receivable: Decimal = 0


class SaleCreate(SaleBase): pass


class SaleOut(SaleBase):
    model_config = ConfigDict(from_attributes=True)
    id: int
    created_at: datetime


class PurchaseBase(BaseModel):
    bill_no: str
    purchase_date: date
    vendor: str
    amount: Decimal
    gst: Decimal = 0
    total: Decimal
    notes: str | None = None


class PurchaseCreate(PurchaseBase): pass


class PurchaseOut(PurchaseBase):
    model_config = ConfigDict(from_attributes=True)
    id: int
    created_at: datetime


class ExpenseBase(BaseModel):
    category: ExpenseCategory
    description: str
    amount: Decimal
    expense_date: date
    due_date: date | None = None
    is_paid: bool = False
    notes: str | None = None


class ExpenseCreate(ExpenseBase): pass


class ExpenseOut(ExpenseBase):
    model_config = ConfigDict(from_attributes=True)
    id: int
    created_at: datetime


class EmployeeBase(BaseModel):
    emp_code: str
    full_name: str
    designation: str
    department: str | None = None
    date_of_joining: date
    basic_salary: Decimal
    hra: Decimal = 0
    allowances: Decimal = 0
    pan: str | None = None
    uan: str | None = None
    esi_no: str | None = None
    bank_account: str | None = None
    is_active: bool = True


class EmployeeCreate(EmployeeBase): pass


class EmployeeOut(EmployeeBase):
    model_config = ConfigDict(from_attributes=True)
    id: int


class SalaryBase(BaseModel):
    employee_id: int
    pay_period: str = Field(pattern=r"^\d{4}-\d{2}$")
    gross: Decimal
    pf_employee: Decimal = 0
    pf_employer: Decimal = 0
    esi_employee: Decimal = 0
    esi_employer: Decimal = 0
    income_tax: Decimal = 0
    other_deductions: Decimal = 0
    net_pay: Decimal
    paid: bool = False
    paid_on: date | None = None
    notes: str | None = None


class SalaryCreate(SalaryBase): pass


class SalaryOut(SalaryBase):
    model_config = ConfigDict(from_attributes=True)
    id: int
    employee_name: str | None = None


class DashboardSummary(BaseModel):
    period_start: date
    period_end: date
    total_sales_gross: Decimal
    total_commission: Decimal
    total_clra: Decimal
    total_compliance: Decimal
    total_other: Decimal
    total_tds: Decimal
    total_gst_payable: Decimal
    total_net_receivable: Decimal
    total_purchases: Decimal
    total_fixed_expenses: Decimal
    total_salary_paid: Decimal
    net_position: Decimal


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
EOF

cat > "$ROOT/backend/app/main.py" <<'EOF'
import logging, time
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import select

from app.auth import hash_password
from app.config import settings
from app.database import Base, SessionLocal, engine
from app.logging_config import configure_logging, get_log_path
from app.middleware import RequestLoggingMiddleware
from app.models import User, UserRole
from app.routers import (
    admin, audit, auth, employees, expenses, purchases,
    reports, salary, sales, settings as settings_router,
)

configure_logging()
logger = logging.getLogger("food-court")

START_TIME = time.time()
REQUEST_COUNTER = {"requests": 0, "errors": 0}


async def seed_users() -> None:
    defaults = [
        (settings.default_admin_email, "Default Administrator",
         settings.default_admin_password, UserRole.admin),
        (settings.default_counter_email, "Default Counter Operator",
         settings.default_counter_password, UserRole.counter),
    ]
    async with SessionLocal() as db:
        for email, name, password, role in defaults:
            exists = (await db.execute(select(User).where(User.email == email))).scalar_one_or_none()
            if not exists:
                db.add(User(email=email, full_name=name,
                            hashed_password=hash_password(password), role=role))
                logger.warning("Seeded default %s user: %s — CHANGE THE PASSWORD.",
                               role.value, email)
        await db.commit()


@asynccontextmanager
async def lifespan(app: FastAPI):
    if settings.is_sqlite:
        logger.warning("Running on SQLite fallback (%s). Set DATABASE_URL for production.",
                       settings.resolved_database_url)
    else:
        logger.info("Database: %s", settings.resolved_database_url.split("@")[-1])
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    await seed_users()
    logger.info("Startup complete. Log file: %s", get_log_path())
    yield
    logger.info("Shutdown complete.")


app = FastAPI(title=settings.app_name, version="1.0.1", lifespan=lifespan)
app.add_middleware(RequestLoggingMiddleware)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

for router_module in (auth, sales, purchases, expenses, employees,
                     salary, reports, settings_router, audit, admin):
    app.include_router(router_module.router, prefix="/api")


@app.get("/api/health")
async def health() -> dict[str, str]:
    return {"status": "ok", "environment": settings.environment}
EOF

touch "$ROOT/backend/app/routers/__init__.py"

cat > "$ROOT/backend/app/routers/auth.py" <<'EOF'
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
EOF

cat > "$ROOT/backend/app/routers/sales.py" <<'EOF'
from datetime import date
from typing import Annotated
from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.auth import get_current_user
from app.database import get_db
from app.models import AuditLog, Sale, User
from app.schemas import SaleCreate, SaleOut

router = APIRouter(prefix="/sales", tags=["sales"])


def _totals(p: SaleCreate) -> SaleCreate:
    total = p.commission_gross + p.clra_gross + p.compliance_gross + p.other_gross
    p.total_gross = total
    p.net_receivable = total - p.tds - p.gst_payable
    return p


async def _log(db, user, request, action, entity, eid, details=""):
    db.add(AuditLog(user_email=user.email, action=action, entity=entity,
                    entity_id=eid, details=details,
                    ip_address=request.client.host if request.client else None))


@router.get("", response_model=list[SaleOut])
async def list_sales(
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
    start: date | None = Query(None), end: date | None = Query(None),
    limit: int = Query(200, le=1000),
):
    stmt = select(Sale).order_by(Sale.sale_date.desc(), Sale.id.desc()).limit(limit)
    if start: stmt = stmt.where(Sale.sale_date >= start)
    if end: stmt = stmt.where(Sale.sale_date <= end)
    return (await db.execute(stmt)).scalars().all()


@router.post("", response_model=SaleOut, status_code=201)
async def create_sale(
    request: Request, payload: SaleCreate,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    payload = _totals(payload)
    sale = Sale(**payload.model_dump(), created_by=user.id)
    db.add(sale); await db.flush()
    await _log(db, user, request, "create", "sale", str(sale.id), f"Invoice {sale.invoice_no}")
    await db.commit(); await db.refresh(sale)
    return sale


@router.put("/{sale_id}", response_model=SaleOut)
async def update_sale(
    sale_id: int, request: Request, payload: SaleCreate,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    sale = await db.get(Sale, sale_id)
    if sale is None: raise HTTPException(404, "Sale not found")
    payload = _totals(payload)
    for k, v in payload.model_dump().items(): setattr(sale, k, v)
    await _log(db, user, request, "update", "sale", str(sale.id), f"Invoice {sale.invoice_no}")
    await db.commit(); await db.refresh(sale)
    return sale


@router.delete("/{sale_id}", status_code=204)
async def delete_sale(
    sale_id: int, request: Request,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    sale = await db.get(Sale, sale_id)
    if sale is None: raise HTTPException(404, "Sale not found")
    await _log(db, user, request, "delete", "sale", str(sale.id), f"Invoice {sale.invoice_no}")
    await db.delete(sale); await db.commit()
EOF

cat > "$ROOT/backend/app/routers/purchases.py" <<'EOF'
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
EOF

cat > "$ROOT/backend/app/routers/expenses.py" <<'EOF'
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
EOF

cat > "$ROOT/backend/app/routers/employees.py" <<'EOF'
from typing import Annotated
from fastapi import APIRouter, Depends, HTTPException
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
):
    return (await db.execute(select(Employee).order_by(Employee.full_name))).scalars().all()


@router.post("", response_model=EmployeeOut, status_code=201)
async def create_employee(
    payload: EmployeeCreate,
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
):
    emp = Employee(**payload.model_dump())
    db.add(emp); await db.commit(); await db.refresh(emp)
    return emp


@router.put("/{eid}", response_model=EmployeeOut)
async def update_employee(
    eid: int, payload: EmployeeCreate,
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
):
    emp = await db.get(Employee, eid)
    if emp is None: raise HTTPException(404, "Employee not found")
    for k, v in payload.model_dump().items(): setattr(emp, k, v)
    await db.commit(); await db.refresh(emp)
    return emp


@router.delete("/{eid}", status_code=204)
async def delete_employee(
    eid: int,
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
):
    emp = await db.get(Employee, eid)
    if emp is None: raise HTTPException(404, "Employee not found")
    await db.delete(emp); await db.commit()
EOF

cat > "$ROOT/backend/app/routers/salary.py" <<'EOF'
from decimal import Decimal
from typing import Annotated
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.auth import get_current_user
from app.database import get_db
from app.models import Employee, SalaryRecord, User
from app.schemas import SalaryCreate, SalaryOut

router = APIRouter(prefix="/salary", tags=["salary"])

PF_EMPLOYEE_RATE = Decimal("0.12")
PF_EMPLOYER_RATE = Decimal("0.12")
PF_CEILING = Decimal("15000")
ESI_EMPLOYEE_RATE = Decimal("0.0075")
ESI_EMPLOYER_RATE = Decimal("0.0325")
ESI_CEILING = Decimal("21000")


def compute_deductions(gross: Decimal) -> dict[str, Decimal]:
    pf_base = min(gross, PF_CEILING)
    pf_e = (pf_base * PF_EMPLOYEE_RATE).quantize(Decimal("0.01"))
    pf_r = (pf_base * PF_EMPLOYER_RATE).quantize(Decimal("0.01"))
    if gross <= ESI_CEILING:
        esi_e = (gross * ESI_EMPLOYEE_RATE).quantize(Decimal("0.01"))
        esi_r = (gross * ESI_EMPLOYER_RATE).quantize(Decimal("0.01"))
    else:
        esi_e = esi_r = Decimal("0.00")
    return {"pf_employee": pf_e, "pf_employer": pf_r,
            "esi_employee": esi_e, "esi_employer": esi_r}


@router.get("/preview")
async def preview(
    gross: Decimal = Query(...),
    _: Annotated[User, Depends(get_current_user)] = None,
):
    return compute_deductions(gross)


@router.get("", response_model=list[SalaryOut])
async def list_salary(
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
    pay_period: str | None = Query(None, pattern=r"^\d{4}-\d{2}$"),
):
    stmt = select(SalaryRecord, Employee.full_name).join(
        Employee, Employee.id == SalaryRecord.employee_id
    )
    if pay_period: stmt = stmt.where(SalaryRecord.pay_period == pay_period)
    stmt = stmt.order_by(SalaryRecord.pay_period.desc(), Employee.full_name)
    out = []
    for record, name in (await db.execute(stmt)).all():
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
    emp = await db.get(Employee, payload.employee_id)
    if emp is None: raise HTTPException(404, "Employee not found")
    record = SalaryRecord(**payload.model_dump())
    db.add(record); await db.commit(); await db.refresh(record)
    out = SalaryOut.model_validate(record)
    out.employee_name = emp.full_name
    return out


@router.patch("/{rid}/paid", response_model=SalaryOut)
async def mark_paid(
    rid: int,
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
):
    record = await db.get(SalaryRecord, rid)
    if record is None: raise HTTPException(404, "Salary record not found")
    from datetime import date as _d
    record.paid = True; record.paid_on = _d.today()
    await db.commit(); await db.refresh(record)
    return SalaryOut.model_validate(record)


@router.delete("/{rid}", status_code=204)
async def delete_salary(
    rid: int,
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
):
    record = await db.get(SalaryRecord, rid)
    if record is None: raise HTTPException(404, "Salary record not found")
    await db.delete(record); await db.commit()
EOF

cat > "$ROOT/backend/app/routers/reports.py" <<'EOF'
from datetime import date
from decimal import Decimal
from typing import Annotated
from fastapi import APIRouter, Depends, Query
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from app.auth import get_current_user
from app.database import get_db
from app.models import FixedExpense, Purchase, SalaryRecord, Sale, User
from app.schemas import DashboardSummary

router = APIRouter(prefix="/reports", tags=["reports"])


@router.get("/dashboard", response_model=DashboardSummary)
async def dashboard(
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
    start: date = Query(...), end: date = Query(...),
):
    row = (await db.execute(select(
        func.coalesce(func.sum(Sale.total_gross), 0),
        func.coalesce(func.sum(Sale.commission_gross), 0),
        func.coalesce(func.sum(Sale.clra_gross), 0),
        func.coalesce(func.sum(Sale.compliance_gross), 0),
        func.coalesce(func.sum(Sale.other_gross), 0),
        func.coalesce(func.sum(Sale.tds), 0),
        func.coalesce(func.sum(Sale.gst_payable), 0),
        func.coalesce(func.sum(Sale.net_receivable), 0),
    ).where(Sale.sale_date.between(start, end)))).one()

    purchases = (await db.execute(select(func.coalesce(func.sum(Purchase.total), 0))
                                  .where(Purchase.purchase_date.between(start, end)))).scalar_one()
    expenses = (await db.execute(select(func.coalesce(func.sum(FixedExpense.amount), 0))
                                 .where(FixedExpense.expense_date.between(start, end)))).scalar_one()
    salary = (await db.execute(select(func.coalesce(func.sum(SalaryRecord.net_pay), 0))
                               .where(SalaryRecord.paid.is_(True)))).scalar_one()

    net = Decimal(row[7]) - (Decimal(purchases) + Decimal(expenses) + Decimal(salary))
    return DashboardSummary(
        period_start=start, period_end=end,
        total_sales_gross=row[0], total_commission=row[1], total_clra=row[2],
        total_compliance=row[3], total_other=row[4], total_tds=row[5],
        total_gst_payable=row[6], total_net_receivable=row[7],
        total_purchases=purchases, total_fixed_expenses=expenses,
        total_salary_paid=salary, net_position=net,
    )
EOF

cat > "$ROOT/backend/app/routers/settings.py" <<'EOF'
from typing import Annotated
from fastapi import APIRouter, Depends
from app.auth import get_current_user
from app.config import settings
from app.models import User

router = APIRouter(prefix="/settings", tags=["settings"])


@router.get("/server")
async def server_settings(_: Annotated[User, Depends(get_current_user)]):
    return {
        "app_name": settings.app_name,
        "environment": settings.environment,
        "database": "sqlite" if settings.is_sqlite else "postgresql",
    }
EOF

cat > "$ROOT/backend/app/routers/audit.py" <<'EOF'
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
EOF

cat > "$ROOT/backend/app/routers/admin.py" <<'EOF'
import os, re, time
from pathlib import Path
from typing import Annotated
import psutil
from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app import __version__
from app.auth import hash_password, require_admin
from app.config import settings
from app.database import get_db
from app.logging_config import get_log_path
from app.models import AuditLog, User, UserRole
from app.schemas import (
    AuditOut, HealthResponse, PasswordReset,
    ServerLogEntry, ServerLogResponse,
    UserCreate, UserOut, UserUpdate,
)

router = APIRouter(prefix="/admin", tags=["admin"])
START_TIME = time.time()

_LOG_RE = re.compile(
    r"^(?P<ts>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) \| "
    r"(?P<level>\w+)\s*\| (?P<logger>[^|]+?) \| (?P<msg>.*)$"
)


@router.get("/health", response_model=HealthResponse)
async def system_health(
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(require_admin)],
):
    t0 = time.perf_counter()
    try:
        await db.execute(select(1)); db_ok = True
    except Exception:
        db_ok = False
    latency = (time.perf_counter() - t0) * 1000

    user_count = (await db.execute(select(func.count(User.id)))).scalar_one()
    active = (await db.execute(select(func.count(User.id))
                               .where(User.is_active.is_(True)))).scalar_one()

    log_path = get_log_path()
    log_size = log_path.stat().st_size if log_path.exists() else 0

    from app.main import REQUEST_COUNTER
    try:
        cpu = psutil.cpu_percent(interval=0.1)
        mem = psutil.virtual_memory().percent
        disk = psutil.disk_usage("/").percent
    except Exception:
        cpu = mem = disk = 0.0

    return HealthResponse(
        status="ok" if db_ok else "degraded",
        environment=settings.environment, version=__version__,
        database="sqlite" if settings.is_sqlite else "postgresql",
        uptime_seconds=time.time() - START_TIME,
        db_ok=db_ok, db_latency_ms=round(latency, 2),
        cpu_percent=cpu, memory_percent=mem, disk_percent=disk,
        log_file=str(log_path), log_size_bytes=log_size,
        request_count=REQUEST_COUNTER["requests"],
        error_count=REQUEST_COUNTER["errors"],
        user_count=user_count, active_session_count=active,
    )


@router.get("/users", response_model=list[UserOut])
async def list_users(
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(require_admin)],
):
    return (await db.execute(select(User).order_by(User.created_at.desc()))).scalars().all()


@router.post("/users", response_model=UserOut, status_code=201)
async def create_user(
    request: Request, payload: UserCreate,
    db: Annotated[AsyncSession, Depends(get_db)],
    admin: Annotated[User, Depends(require_admin)],
):
    if (await db.execute(select(User).where(User.email == payload.email))).scalar_one_or_none():
        raise HTTPException(409, "A user with this email already exists")
    user = User(email=payload.email, full_name=payload.full_name,
                hashed_password=hash_password(payload.password),
                role=payload.role, is_active=payload.is_active)
    db.add(user); await db.flush()
    db.add(AuditLog(user_email=admin.email, action="create", entity="user",
                    entity_id=str(user.id),
                    details=f"Created {payload.role.value} user {payload.email}",
                    ip_address=request.client.host if request.client else None))
    await db.commit(); await db.refresh(user)
    return user


@router.put("/users/{uid}", response_model=UserOut)
async def update_user(
    uid: int, request: Request, payload: UserUpdate,
    db: Annotated[AsyncSession, Depends(get_db)],
    admin: Annotated[User, Depends(require_admin)],
):
    user = await db.get(User, uid)
    if user is None: raise HTTPException(404, "User not found")
    if user.id == admin.id and payload.is_active is False:
        raise HTTPException(400, "You cannot disable your own account")
    if user.id == admin.id and payload.role and payload.role != UserRole.admin:
        raise HTTPException(400, "You cannot demote your own account")
    for k, v in payload.model_dump(exclude_unset=True).items():
        if v is not None: setattr(user, k, v)
    db.add(AuditLog(user_email=admin.email, action="update", entity="user",
                    entity_id=str(user.id), details=f"Updated user {user.email}",
                    ip_address=request.client.host if request.client else None))
    await db.commit(); await db.refresh(user)
    return user


@router.post("/users/{uid}/reset-password", response_model=UserOut)
async def reset_password(
    uid: int, request: Request, payload: PasswordReset,
    db: Annotated[AsyncSession, Depends(get_db)],
    admin: Annotated[User, Depends(require_admin)],
):
    user = await db.get(User, uid)
    if user is None: raise HTTPException(404, "User not found")
    user.hashed_password = hash_password(payload.new_password)
    db.add(AuditLog(user_email=admin.email, action="reset_password", entity="user",
                    entity_id=str(user.id), details=f"Reset password for {user.email}",
                    ip_address=request.client.host if request.client else None))
    await db.commit(); await db.refresh(user)
    return user


@router.delete("/users/{uid}", status_code=204)
async def delete_user(
    uid: int, request: Request,
    db: Annotated[AsyncSession, Depends(get_db)],
    admin: Annotated[User, Depends(require_admin)],
):
    if uid == admin.id:
        raise HTTPException(400, "You cannot delete your own account")
    user = await db.get(User, uid)
    if user is None: raise HTTPException(404, "User not found")
    db.add(AuditLog(user_email=admin.email, action="delete", entity="user",
                    entity_id=str(user.id), details=f"Deleted user {user.email}",
                    ip_address=request.client.host if request.client else None))
    await db.delete(user); await db.commit()


@router.get("/logs/app", response_model=list[AuditOut])
async def app_logs(
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(require_admin)],
    action: str | None = Query(None), entity: str | None = Query(None),
    user_email: str | None = Query(None), limit: int = Query(200, le=2000),
):
    stmt = select(AuditLog).order_by(AuditLog.created_at.desc()).limit(limit)
    if action: stmt = stmt.where(AuditLog.action == action)
    if entity: stmt = stmt.where(AuditLog.entity == entity)
    if user_email: stmt = stmt.where(AuditLog.user_email.ilike(f"%{user_email}%"))
    return (await db.execute(stmt)).scalars().all()


def _tail(path: Path, n: int) -> list[str]:
    if not path.exists(): return []
    with path.open("rb") as fh:
        fh.seek(0, os.SEEK_END); size = fh.tell()
        block = 8192; data = b""; lines: list[bytes] = []; pos = size
        while pos > 0 and len(lines) < n:
            rs = min(block, pos); pos -= rs; fh.seek(pos)
            data = fh.read(rs) + data; lines = data.splitlines()
        return [ln.decode("utf-8", errors="replace") for ln in lines[-n:]]


@router.get("/logs/server", response_model=ServerLogResponse)
async def server_logs(
    _: Annotated[User, Depends(require_admin)],
    level: str | None = Query(None), search: str | None = Query(None),
    limit: int = Query(500, le=5000),
):
    log_path = get_log_path()
    if not log_path.exists():
        return ServerLogResponse(entries=[], total_matched=0,
                                 file_size_bytes=0, lines_scanned=0)
    raw = _tail(log_path, min(limit * 4, 20000))
    entries: list[ServerLogEntry] = []
    for line in raw:
        m = _LOG_RE.match(line)
        if m:
            entry = ServerLogEntry(timestamp=m.group("ts"),
                                   level=m.group("level").strip(),
                                   logger=m.group("logger").strip(),
                                   message=m.group("msg"))
        else:
            if entries: entries[-1].message += "\n" + line
            continue
        if level and entry.level.upper() != level.upper(): continue
        if search:
            n = search.lower()
            if (n not in entry.message.lower()
                and n not in entry.logger.lower()
                and n not in entry.level.lower()): continue
        entries.append(entry)
    entries = list(reversed(entries))[:limit]
    return ServerLogResponse(
        entries=entries, total_matched=len(entries),
        file_size_bytes=log_path.stat().st_size, lines_scanned=len(raw),
    )


@router.get("/logs/server/download")
async def download_log(_: Annotated[User, Depends(require_admin)]):
    from fastapi.responses import FileResponse
    log_path = get_log_path()
    if not log_path.exists():
        raise HTTPException(status_code=404, detail="Log file not found")
    return FileResponse(log_path, media_type="text/plain",
                        filename="food-court-api.log")
EOF

# =============================================================================
# FRONTEND
# =============================================================================

cat > "$ROOT/frontend/package.json" <<'EOF'
{
  "name": "food-court-counter-frontend",
  "private": true,
  "version": "1.0.1",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc -b && vite build",
    "preview": "vite preview",
    "lint": "tsc --noEmit"
  },
  "dependencies": {
    "axios": "^1.7.9",
    "lucide-react": "^0.468.0",
    "react": "^19.1.0",
    "react-dom": "^19.1.0",
    "react-router-dom": "^7.1.1"
  },
  "devDependencies": {
    "@types/react": "^19.1.0",
    "@types/react-dom": "^19.1.0",
    "@vitejs/plugin-react": "^4.3.4",
    "typescript": "^5.7.2",
    "vite": "^6.0.7"
  }
}
EOF

cat > "$ROOT/frontend/vite.config.ts" <<'EOF'
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: { '/api': { target: 'http://127.0.0.1:8000', changeOrigin: true } },
  },
  build: { outDir: 'dist', sourcemap: false, chunkSizeWarningLimit: 900 },
});
EOF

cat > "$ROOT/frontend/tsconfig.json" <<'EOF'
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "moduleResolution": "bundler",
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true,
    "esModuleInterop": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "skipLibCheck": true,
    "noEmit": true,
    "types": ["vite/client"]
  },
  "include": ["src"]
}
EOF

cat > "$ROOT/frontend/tsconfig.node.json" <<'EOF'
{
  "compilerOptions": {
    "composite": true,
    "module": "ESNext",
    "moduleResolution": "bundler",
    "allowSyntheticDefaultImports": true,
    "skipLibCheck": true,
    "types": ["node"]
  },
  "include": ["vite.config.ts"]
}
EOF

cat > "$ROOT/frontend/index.html" <<'EOF'
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <meta name="description" content="Multi-company operations console" />
    <link rel="icon" href="/favicon.svg" />
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500;600&display=swap" rel="stylesheet" />
    <title>Operations Console</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
EOF

cat > "$ROOT/frontend/.env.example" <<'EOF'
VITE_COMPANY_NAME="Food Court Counter"
VITE_COMPANY_ID="default"
VITE_TITLE_MODIFIER="Operations Console"
VITE_LOGO_URL="/assets/logo-placeholder.svg"
VITE_BRAND_IMAGE_URL="/assets/login-placeholder.svg"
VITE_FAVICON_URL="/favicon.svg"
VITE_PRIMARY_COLOR="#1e3a5f"
VITE_ACCENT_COLOR="#059669"
VITE_GSTIN=""
VITE_PAN=""
VITE_ADDRESS=""
VITE_CONTACT_EMAIL=""
VITE_CONTACT_PHONE=""
EOF

cat > "$ROOT/frontend/public/favicon.svg" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
  <rect width="64" height="64" rx="14" fill="#1e3a5f"/>
  <path d="M20 44V22h4.8l7.2 12.6L39.2 22H44v22h-4.6V30.4L32.2 43.2h-1.4L23.6 30.4V44z" fill="#fff"/>
</svg>
EOF

cat > "$ROOT/frontend/public/assets/logo-placeholder.svg" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 64">
  <rect x="6" y="10" width="44" height="44" rx="10" fill="#1e3a5f"/>
  <text x="28" y="40" text-anchor="middle" font-family="Inter,sans-serif" font-size="22" font-weight="700" fill="#fff">FC</text>
  <text x="62" y="34" font-family="Inter,sans-serif" font-size="17" font-weight="700" fill="#0f172a">Food Court</text>
  <text x="62" y="52" font-family="Inter,sans-serif" font-size="11" letter-spacing="1.5" fill="#64748b">COUNTER</text>
</svg>
EOF

cat > "$ROOT/frontend/public/assets/login-placeholder.svg" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 600 800">
  <defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#1e3a5f"/><stop offset="1" stop-color="#0f2438"/>
  </linearGradient></defs>
  <rect width="600" height="800" fill="url(#g)"/>
  <circle cx="140" cy="180" r="90" fill="#ffffff" opacity="0.06"/>
  <circle cx="470" cy="640" r="140" fill="#ffffff" opacity="0.06"/>
  <text x="60" y="420" font-family="Inter,sans-serif" font-size="34" font-weight="700" fill="#ffffff">Operations Console</text>
  <text x="60" y="462" font-family="Inter,sans-serif" font-size="16" fill="#cbd5e1">Sales · Purchases · Payroll · Compliance</text>
</svg>
EOF

cat > "$ROOT/frontend/src/vite-env.d.ts" <<'EOF'
/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_COMPANY_NAME: string;
  readonly VITE_COMPANY_ID: string;
  readonly VITE_TITLE_MODIFIER: string;
  readonly VITE_LOGO_URL: string;
  readonly VITE_BRAND_IMAGE_URL: string;
  readonly VITE_FAVICON_URL: string;
  readonly VITE_PRIMARY_COLOR: string;
  readonly VITE_ACCENT_COLOR: string;
  readonly VITE_GSTIN: string;
  readonly VITE_PAN: string;
  readonly VITE_ADDRESS: string;
  readonly VITE_CONTACT_EMAIL: string;
  readonly VITE_CONTACT_PHONE: string;
}
interface ImportMeta { readonly env: ImportMetaEnv; }
EOF

cat > "$ROOT/frontend/src/main.tsx" <<'EOF'
import React from 'react';
import ReactDOM from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';
import App from './App';
import { AuthProvider } from './context/AuthContext';
import './styles/globals.css';

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <BrowserRouter>
      <AuthProvider>
        <App />
      </AuthProvider>
    </BrowserRouter>
  </React.StrictMode>,
);
EOF

cat > "$ROOT/frontend/src/config/branding.config.ts" <<'EOF'
export interface Branding {
  companyId: string; companyName: string; titleModifier: string;
  logoUrl: string; brandImageUrl: string; faviconUrl: string;
  primaryColor: string; accentColor: string;
  gstin: string; pan: string; address: string;
  contactEmail: string; contactPhone: string;
}

const env = import.meta.env;

export const branding: Branding = {
  companyId: env.VITE_COMPANY_ID || 'default',
  companyName: env.VITE_COMPANY_NAME || 'Food Court Counter',
  titleModifier: env.VITE_TITLE_MODIFIER || 'Operations Console',
  logoUrl: env.VITE_LOGO_URL || '/assets/logo-placeholder.svg',
  brandImageUrl: env.VITE_BRAND_IMAGE_URL || '/assets/login-placeholder.svg',
  faviconUrl: env.VITE_FAVICON_URL || '/favicon.svg',
  primaryColor: env.VITE_PRIMARY_COLOR || '#1e3a5f',
  accentColor: env.VITE_ACCENT_COLOR || '#059669',
  gstin: env.VITE_GSTIN || '', pan: env.VITE_PAN || '',
  address: env.VITE_ADDRESS || '',
  contactEmail: env.VITE_CONTACT_EMAIL || '',
  contactPhone: env.VITE_CONTACT_PHONE || '',
};

export function applyBrandingToDocument(): void {
  document.title = `${branding.companyName} · ${branding.titleModifier}`;
  let link = document.querySelector<HTMLLinkElement>('link[rel="icon"]');
  if (!link) { link = document.createElement('link'); link.rel = 'icon'; document.head.appendChild(link); }
  link.href = branding.faviconUrl;
  const root = document.documentElement;
  root.style.setProperty('--color-primary-500', branding.primaryColor);
  root.style.setProperty('--color-success', branding.accentColor);
}
EOF

cat > "$ROOT/frontend/src/lib/api.ts" <<'EOF'
import axios, { AxiosError } from 'axios';

const TOKEN_KEY = 'fcc.token';
export const api = axios.create({ baseURL: '/api', timeout: 30000 });

api.interceptors.request.use((config) => {
  const token = localStorage.getItem(TOKEN_KEY);
  if (token) config.headers.Authorization = `Bearer ${token}`;
  return config;
});

api.interceptors.response.use(
  (r) => r,
  (error: AxiosError) => {
    if (error.response?.status === 401) {
      localStorage.removeItem(TOKEN_KEY);
      if (!window.location.pathname.startsWith('/login')) window.location.href = '/login';
    }
    return Promise.reject(error);
  },
);

export const setToken = (t: string) => localStorage.setItem(TOKEN_KEY, t);
export const clearToken = () => localStorage.removeItem(TOKEN_KEY);
export const getToken = () => localStorage.getItem(TOKEN_KEY);

export function apiErrorMessage(err: unknown): string {
  if (axios.isAxiosError(err)) {
    const detail = err.response?.data?.detail;
    if (typeof detail === 'string') return detail;
    if (Array.isArray(detail) && detail[0]?.msg) return detail[0].msg as string;
    return err.message;
  }
  return String(err);
}
EOF

cat > "$ROOT/frontend/src/lib/format.ts" <<'EOF'
const inr = new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR',
  maximumFractionDigits: 2, minimumFractionDigits: 2 });

export const formatINR = (v: number | string): string => inr.format(Number(v ?? 0));
export const formatNumber = (v: number | string): string =>
  new Intl.NumberFormat('en-IN').format(Number(v ?? 0));
export const formatDate = (v: string | Date): string => {
  const d = typeof v === 'string' ? new Date(v) : v;
  return d.toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' });
};
export const todayISO = (): string => new Date().toISOString().slice(0, 10);
export const firstOfMonthISO = (): string => {
  const d = new Date(); d.setDate(1);
  return d.toISOString().slice(0, 10);
};
EOF

cat > "$ROOT/frontend/src/context/AuthContext.tsx" <<'EOF'
import { createContext, useCallback, useContext, useEffect, useMemo, useState,
  type ReactNode } from 'react';
import { api, clearToken, getToken, setToken } from '../lib/api';

export type UserRole = 'admin' | 'counter';
export interface CurrentUser { id: number; email: string; full_name: string; role: UserRole; is_active: boolean }
interface AuthContextValue {
  user: CurrentUser | null; loading: boolean;
  login: (email: string, password: string) => Promise<void>;
  logout: () => void;
}
const AuthContext = createContext<AuthContextValue | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<CurrentUser | null>(null);
  const [loading, setLoading] = useState(true);

  const loadMe = useCallback(async () => {
    if (!getToken()) { setUser(null); setLoading(false); return; }
    try { const { data } = await api.get<CurrentUser>('/auth/me'); setUser(data); }
    catch { clearToken(); setUser(null); }
    finally { setLoading(false); }
  }, []);

  useEffect(() => { loadMe(); }, [loadMe]);

  const login = useCallback(async (email: string, password: string) => {
    const body = new URLSearchParams();
    body.append('username', email); body.append('password', password);
    const { data } = await api.post<{ access_token: string }>(
      '/auth/login', body,
      { headers: { 'Content-Type': 'application/x-www-form-urlencoded' } },
    );
    setToken(data.access_token);
    const me = await api.get<CurrentUser>('/auth/me');
    setUser(me.data);
  }, []);

  const logout = useCallback(async () => {
    try { await api.post('/auth/logout'); } catch { /* ignore */ }
    clearToken(); setUser(null);
  }, []);

  const value = useMemo(() => ({ user, loading, login, logout }),
    [user, loading, login, logout]);
  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used inside AuthProvider');
  return ctx;
}
EOF

cat > "$ROOT/frontend/src/components/ui/Button.tsx" <<'EOF'
import type { ButtonHTMLAttributes, ReactNode } from 'react';
type Variant = 'primary' | 'secondary' | 'ghost' | 'danger';
type Size = 'sm' | 'md';
interface Props extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant; size?: Size; loading?: boolean; icon?: ReactNode;
}
export default function Button({ variant = 'primary', size = 'md', loading = false,
  icon, children, className = '', disabled, ...rest }: Props) {
  return (
    <button {...rest} disabled={disabled || loading}
      className={`btn btn-${variant} btn-${size} ${className}`.trim()}>
      {loading ? <span className="spinner-sm" /> : icon}
      {children}
    </button>
  );
}
EOF

cat > "$ROOT/frontend/src/components/ui/Card.tsx" <<'EOF'
import type { ReactNode } from 'react';
interface Props { title?: string; subtitle?: string; actions?: ReactNode; children: ReactNode; padded?: boolean }
export default function Card({ title, subtitle, actions, children, padded = true }: Props) {
  return (
    <section className="card">
      {(title || actions) && (
        <header className="card-header">
          <div>
            {title && <h3 className="card-title">{title}</h3>}
            {subtitle && <p className="card-subtitle">{subtitle}</p>}
          </div>
          {actions && <div className="card-actions">{actions}</div>}
        </header>
      )}
      <div className={padded ? 'card-body' : ''}>{children}</div>
    </section>
  );
}
EOF

cat > "$ROOT/frontend/src/components/ui/Input.tsx" <<'EOF'
import type { InputHTMLAttributes, SelectHTMLAttributes, ReactNode } from 'react';
interface FieldProps { label: string; hint?: string; error?: string; children: ReactNode }
export function Field({ label, hint, error, children }: FieldProps) {
  return (
    <label className="field">
      <span className="field-label">{label}</span>
      {children}
      {hint && !error && <span className="field-hint">{hint}</span>}
      {error && <span className="field-error">{error}</span>}
    </label>
  );
}
interface InputProps extends InputHTMLAttributes<HTMLInputElement> {
  label: string; hint?: string; error?: string;
}
export function Input({ label, hint, error, ...rest }: InputProps) {
  return (
    <Field label={label} hint={hint} error={error}>
      <input {...rest} className="input" />
    </Field>
  );
}
interface SelectProps extends SelectHTMLAttributes<HTMLSelectElement> {
  label: string; children: ReactNode;
}
export function Select({ label, children, ...rest }: SelectProps) {
  return <Field label={label}><select {...rest} className="input">{children}</select></Field>;
}
EOF

cat > "$ROOT/frontend/src/components/ui/Table.tsx" <<'EOF'
import type { ReactNode } from 'react';
export interface Column<T> {
  key: string; header: string; align?: 'left' | 'right' | 'center';
  render: (row: T) => ReactNode;
}
interface Props<T> { columns: Column<T>[]; rows: T[]; empty?: string }
export default function Table<T>({ columns, rows, empty = 'No records yet.' }: Props<T>) {
  if (rows.length === 0) return <div className="table-empty">{empty}</div>;
  return (
    <div className="table-wrap">
      <table className="data-table">
        <thead><tr>{columns.map((c) => (
          <th key={c.key} style={{ textAlign: c.align ?? 'left' }}>{c.header}</th>
        ))}</tr></thead>
        <tbody>{rows.map((row, i) => (
          <tr key={i}>{columns.map((c) => (
            <td key={c.key} style={{ textAlign: c.align ?? 'left' }}>{c.render(row)}</td>
          ))}</tr>
        ))}</tbody>
      </table>
    </div>
  );
}
EOF

cat > "$ROOT/frontend/src/components/ui/Badge.tsx" <<'EOF'
import type { ReactNode } from 'react';
type Tone = 'neutral' | 'success' | 'danger' | 'warning' | 'info';
export default function Badge({ tone = 'neutral', children }: { tone?: Tone; children: ReactNode }) {
  return <span className={`badge badge-${tone}`}>{children}</span>;
}
EOF

cat > "$ROOT/frontend/src/components/ui/StatTile.tsx" <<'EOF'
import type { ReactNode } from 'react';
interface Props {
  label: string; value: string;
  delta?: { value: string; positive: boolean };
  hint?: string; icon?: ReactNode;
  tone?: 'neutral' | 'success' | 'danger' | 'warning';
}
export default function StatTile({ label, value, delta, hint, icon, tone = 'neutral' }: Props) {
  return (
    <div className={`stat-tile stat-${tone}`}>
      <div className="stat-head">
        <span className="stat-label">{label}</span>
        {icon && <span className="stat-icon">{icon}</span>}
      </div>
      <div className="stat-value mono">{value}</div>
      {(delta || hint) && (
        <div className="stat-foot">
          {delta && <span className={delta.positive ? 'delta up' : 'delta down'}>
            {delta.positive ? '▲' : '▼'} {delta.value}</span>}
          {hint && <span className="stat-hint">{hint}</span>}
        </div>
      )}
    </div>
  );
}
EOF

cat > "$ROOT/frontend/src/components/Layout/Sidebar.tsx" <<'EOF'
import { LayoutDashboard, ShoppingCart, Package, Receipt, Users, Wallet,
  BarChart3, Settings as SettingsIcon, ScrollText, ShieldCheck } from 'lucide-react';
import { NavLink } from 'react-router-dom';
import { branding } from '../../config/branding.config';
import { useAuth } from '../../context/AuthContext';

const NAV = [
  { to: '/', label: 'Dashboard', icon: LayoutDashboard, end: true },
  { to: '/sales', label: 'Sales', icon: ShoppingCart },
  { to: '/purchases', label: 'Purchases', icon: Package },
  { to: '/expenses', label: 'Fixed Expenses', icon: Receipt },
  { to: '/employees', label: 'Employees', icon: Users },
  { to: '/salary', label: 'Salary & Statutory', icon: Wallet },
  { to: '/reports', label: 'Reports', icon: BarChart3 },
  { to: '/settings', label: 'Settings', icon: SettingsIcon },
];

export default function Sidebar() {
  const { user } = useAuth();
  const isAdmin = user?.role === 'admin';
  return (
    <aside className="sidebar">
      <div className="sidebar-brand">
        <img src={branding.logoUrl} alt={branding.companyName} />
        <div className="sidebar-brand-text">
          <strong>{branding.companyName}</strong>
          <small>{branding.titleModifier}</small>
        </div>
      </div>
      <nav className="sidebar-nav">
        {NAV.map(({ to, label, icon: Icon, end }) => (
          <NavLink key={to} to={to} end={end}
            className={({ isActive }) => `nav-link${isActive ? ' nav-link-active' : ''}`}>
            <Icon size={18} strokeWidth={1.9} /><span>{label}</span>
          </NavLink>
        ))}
        {isAdmin && (<>
          <div className="nav-divider"><span>Administration</span></div>
          <NavLink to="/admin" className={({ isActive }) => `nav-link${isActive ? ' nav-link-active' : ''}`}>
            <ShieldCheck size={18} strokeWidth={1.9} /><span>Admin Console</span>
          </NavLink>
          <NavLink to="/audit" className={({ isActive }) => `nav-link${isActive ? ' nav-link-active' : ''}`}>
            <ScrollText size={18} strokeWidth={1.9} /><span>Audit Logs</span>
          </NavLink>
        </>)}
      </nav>
      <footer className="sidebar-foot">
        <div className="sidebar-company-meta">
          {branding.gstin && <span>GSTIN: {branding.gstin}</span>}
          {branding.pan && <span>PAN: {branding.pan}</span>}
        </div>
      </footer>
    </aside>
  );
}
EOF

cat > "$ROOT/frontend/src/components/Layout/Topbar.tsx" <<'EOF'
import { LogOut, UserCircle2 } from 'lucide-react';
import { useAuth } from '../../context/AuthContext';
export default function Topbar() {
  const { user, logout } = useAuth();
  return (
    <header className="topbar">
      <div className="topbar-left" />
      <div className="topbar-right">
        <div className="user-chip">
          <UserCircle2 size={20} />
          <div className="user-chip-text">
            <strong>{user?.full_name}</strong>
            <small>{user?.role === 'admin' ? 'Administrator' : 'Counter'}</small>
          </div>
        </div>
        <button className="icon-btn" onClick={logout} title="Sign out"><LogOut size={18} /></button>
      </div>
    </header>
  );
}
EOF

cat > "$ROOT/frontend/src/components/Layout/AppLayout.tsx" <<'EOF'
import { Outlet } from 'react-router-dom';
import Sidebar from './Sidebar';
import Topbar from './Topbar';
export default function AppLayout() {
  return (
    <div className="app-shell">
      <Sidebar />
      <div className="app-main">
        <Topbar />
        <main className="app-content"><Outlet /></main>
      </div>
    </div>
  );
}
EOF

cat > "$ROOT/frontend/src/components/ProtectedRoute.tsx" <<'EOF'
import { Navigate, Outlet } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
export default function ProtectedRoute() {
  const { user, loading } = useAuth();
  if (loading) return <div className="app-loader"><div className="spinner" /></div>;
  if (!user) return <Navigate to="/login" replace />;
  return <Outlet />;
}
EOF

cat > "$ROOT/frontend/src/components/AdminRoute.tsx" <<'EOF'
import { Navigate, Outlet } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
export default function AdminRoute() {
  const { user, loading } = useAuth();
  if (loading) return <div className="app-loader"><div className="spinner" /></div>;
  if (!user) return <Navigate to="/login" replace />;
  if (user.role !== 'admin') return <Navigate to="/" replace />;
  return <Outlet />;
}
EOF

cat > "$ROOT/frontend/src/App.tsx" <<'EOF'
import { useEffect } from 'react';
import { Navigate, Route, Routes } from 'react-router-dom';
import AdminRoute from './components/AdminRoute';
import AppLayout from './components/Layout/AppLayout';
import ProtectedRoute from './components/ProtectedRoute';
import { applyBrandingToDocument } from './config/branding.config';
import AdminConsole from './pages/admin/AdminConsole';
import AuditLogs from './pages/AuditLogs';
import Dashboard from './pages/Dashboard';
import Employees from './pages/Employees';
import Expenses from './pages/Expenses';
import Login from './pages/Login';
import Purchases from './pages/Purchases';
import Reports from './pages/Reports';
import Salary from './pages/Salary';
import Sales from './pages/Sales';
import Settings from './pages/Settings';

export default function App() {
  useEffect(() => { applyBrandingToDocument(); }, []);
  return (
    <Routes>
      <Route path="/login" element={<Login />} />
      <Route element={<ProtectedRoute />}>
        <Route element={<AppLayout />}>
          <Route index element={<Dashboard />} />
          <Route path="sales" element={<Sales />} />
          <Route path="purchases" element={<Purchases />} />
          <Route path="expenses" element={<Expenses />} />
          <Route path="employees" element={<Employees />} />
          <Route path="salary" element={<Salary />} />
          <Route path="reports" element={<Reports />} />
          <Route path="settings" element={<Settings />} />
          <Route element={<AdminRoute />}>
            <Route path="admin" element={<AdminConsole />} />
            <Route path="audit" element={<AuditLogs />} />
          </Route>
        </Route>
      </Route>
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}
EOF

cat > "$ROOT/frontend/src/pages/Login.tsx" <<'EOF'
import { FormEvent, useState } from 'react';
import { Navigate } from 'react-router-dom';
import Button from '../components/ui/Button';
import { branding } from '../config/branding.config';
import { useAuth } from '../context/AuthContext';
import { apiErrorMessage } from '../lib/api';

export default function Login() {
  const { user, login } = useAuth();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  if (user) return <Navigate to="/" replace />;
  const onSubmit = async (e: FormEvent) => {
    e.preventDefault(); setError(null); setSubmitting(true);
    try { await login(email.trim(), password); }
    catch (err) { setError(apiErrorMessage(err)); }
    finally { setSubmitting(false); }
  };
  return (
    <div className="login-screen">
      <div className="login-brand"><img src={branding.brandImageUrl} alt="" /></div>
      <div className="login-form-wrap">
        <div className="login-card">
          <img className="login-logo" src={branding.logoUrl} alt={branding.companyName} />
          <h1 className="login-title">Welcome back</h1>
          <p className="login-subtitle">
            Sign in to {branding.companyName} {branding.titleModifier}
          </p>
          <form onSubmit={onSubmit}>
            {error && <div className="login-error">{error}</div>}
            <label className="field">
              <span className="field-label">Email</span>
              <input type="email" autoComplete="username" required className="input"
                value={email} onChange={(e) => setEmail(e.target.value)} />
            </label>
            <label className="field">
              <span className="field-label">Password</span>
              <input type="password" autoComplete="current-password" required className="input"
                value={password} onChange={(e) => setPassword(e.target.value)} />
            </label>
            <Button type="submit" loading={submitting}>Sign in</Button>
          </form>
          <div className="login-footnote">
            © {new Date().getFullYear()} {branding.companyName}
            {branding.contactEmail && <> · {branding.contactEmail}</>}
          </div>
        </div>
      </div>
    </div>
  );
}
EOF

cat > "$ROOT/frontend/src/pages/Dashboard.tsx" <<'EOF'
import { useEffect, useState } from 'react';
import { ArrowDownRight, ArrowUpRight, IndianRupee, Receipt, Wallet, TrendingUp } from 'lucide-react';
import Button from '../components/ui/Button';
import Card from '../components/ui/Card';
import StatTile from '../components/ui/StatTile';
import { api, apiErrorMessage } from '../lib/api';
import { firstOfMonthISO, formatDate, formatINR, todayISO } from '../lib/format';

interface Summary {
  period_start: string; period_end: string;
  total_sales_gross: string; total_commission: string; total_clra: string;
  total_compliance: string; total_other: string; total_tds: string;
  total_gst_payable: string; total_net_receivable: string;
  total_purchases: string; total_fixed_expenses: string;
  total_salary_paid: string; net_position: string;
}

export default function Dashboard() {
  const [start, setStart] = useState(firstOfMonthISO());
  const [end, setEnd] = useState(todayISO());
  const [data, setData] = useState<Summary | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const load = async () => {
    setLoading(true); setError(null);
    try {
      const { data } = await api.get<Summary>('/reports/dashboard', { params: { start, end } });
      setData(data);
    } catch (err) { setError(apiErrorMessage(err)); }
    finally { setLoading(false); }
  };
  useEffect(() => { load(); /* eslint-disable-next-line */ }, []);
  const positive = Number(data?.net_position ?? 0) >= 0;
  return (
    <>
      <div className="page-header">
        <div>
          <h1 className="page-title">Dashboard</h1>
          <p className="page-subtitle">
            {data ? `${formatDate(data.period_start)} – ${formatDate(data.period_end)}` : 'Loading…'}
          </p>
        </div>
        <div className="page-actions">
          <input type="date" className="input" value={start} onChange={(e) => setStart(e.target.value)} style={{ width: 150 }} />
          <span style={{ color: 'var(--text-muted)' }}>→</span>
          <input type="date" className="input" value={end} onChange={(e) => setEnd(e.target.value)} style={{ width: 150 }} />
          <Button onClick={load} loading={loading}>Apply</Button>
        </div>
      </div>
      {error && <div className="login-error" style={{ marginBottom: 16 }}>{error}</div>}
      <div className="grid-stats">
        <StatTile label="Gross Sales" value={formatINR(data?.total_sales_gross ?? 0)} icon={<TrendingUp size={18} />} />
        <StatTile label="Commission" value={formatINR(data?.total_commission ?? 0)} icon={<IndianRupee size={18} />} />
        <StatTile label="TDS" value={formatINR(data?.total_tds ?? 0)} icon={<ArrowDownRight size={18} />} tone="warning" />
        <StatTile label="GST Payable" value={formatINR(data?.total_gst_payable ?? 0)} tone="warning" />
        <StatTile label="Purchases" value={formatINR(data?.total_purchases ?? 0)} icon={<Receipt size={18} />} />
        <StatTile label="Fixed Expenses" value={formatINR(data?.total_fixed_expenses ?? 0)} icon={<Receipt size={18} />} tone="danger" />
        <StatTile label="Salary Paid" value={formatINR(data?.total_salary_paid ?? 0)} icon={<Wallet size={18} />} tone="danger" />
        <StatTile label="Net Position" value={formatINR(data?.net_position ?? 0)} tone={positive ? 'success' : 'danger'}
          icon={positive ? <ArrowUpRight size={18} /> : <ArrowDownRight size={18} />} />
      </div>
      <div className="grid-2">
        <Card title="Sales Composition" subtitle="Current period">
          <CompositionBars data={data} />
        </Card>
        <Card title="Net Receivable" subtitle="Gross − TDS − GST Payable">
          <div className="mono" style={{ fontSize: 32, fontWeight: 700 }}>
            {formatINR(data?.total_net_receivable ?? 0)}
          </div>
          <p style={{ color: 'var(--text-muted)', fontSize: 12.5, marginTop: 6 }}>
            Amount owed by customers after statutory deductions.
          </p>
        </Card>
      </div>
    </>
  );
}

function CompositionBars({ data }: { data: Summary | null }) {
  if (!data) return <div className="table-empty">No data.</div>;
  const rows = [
    { label: 'Commission', value: Number(data.total_commission), color: '#1e3a5f' },
    { label: 'CLRA Charges', value: Number(data.total_clra), color: '#2563eb' },
    { label: 'Compliance Fee', value: Number(data.total_compliance), color: '#0891b2' },
    { label: 'Other Charges', value: Number(data.total_other), color: '#7c3aed' },
  ];
  const max = Math.max(...rows.map((r) => r.value), 1);
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
      {rows.map((r) => (
        <div key={r.label}>
          <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 6, fontSize: 12.5 }}>
            <span style={{ color: 'var(--text-muted)' }}>{r.label}</span>
            <span className="mono" style={{ color: 'var(--text-strong)' }}>{formatINR(r.value)}</span>
          </div>
          <div style={{ height: 8, background: 'var(--bg-muted)', borderRadius: 999, overflow: 'hidden' }}>
            <div style={{ width: `${(r.value / max) * 100}%`, height: '100%', background: r.color, transition: 'width .4s ease' }} />
          </div>
        </div>
      ))}
    </div>
  );
}
EOF

cat > "$ROOT/frontend/src/pages/Sales.tsx" <<'EOF'
import { FormEvent, useEffect, useState } from 'react';
import { Plus, Trash2 } from 'lucide-react';
import Button from '../components/ui/Button';
import Card from '../components/ui/Card';
import { Input } from '../components/ui/Input';
import Table, { type Column } from '../components/ui/Table';
import { api, apiErrorMessage } from '../lib/api';
import { formatDate, formatINR, todayISO } from '../lib/format';

interface Sale {
  id: number; invoice_no: string; sale_date: string; customer: string;
  commission_gross: string; clra_gross: string; compliance_gross: string;
  other_gross: string; tds: string; gst_payable: string;
  total_gross: string; net_receivable: string;
}
const GST_RATE = 0.18;
const splitGross = (g: number) => {
  const base = +(g / (1 + GST_RATE)).toFixed(2);
  return { base, gst: +(g - base).toFixed(2) };
};
const emptyForm = {
  invoice_no: '', sale_date: todayISO(), customer: '',
  commission_gross: '', clra_gross: '', compliance_gross: '', other_gross: '',
  tds: '', gst_payable: '', notes: '',
};

export default function Sales() {
  const [rows, setRows] = useState<Sale[]>([]);
  const [form, setForm] = useState({ ...emptyForm });
  const [showForm, setShowForm] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const load = async () => {
    try { const { data } = await api.get<Sale[]>('/sales'); setRows(data); }
    catch (err) { setError(apiErrorMessage(err)); }
  };
  useEffect(() => { load(); }, []);
  const set = (k: keyof typeof form, v: string) => setForm((f) => ({ ...f, [k]: v }));
  const onSubmit = async (e: FormEvent) => {
    e.preventDefault(); setError(null); setSubmitting(true);
    const cg = Number(form.commission_gross || 0);
    const cl = Number(form.clra_gross || 0);
    const co = Number(form.compliance_gross || 0);
    const ot = Number(form.other_gross || 0);
    const c = splitGross(cg), cl2 = splitGross(cl), co2 = splitGross(co), ot2 = splitGross(ot);
    try {
      await api.post('/sales', {
        invoice_no: form.invoice_no, sale_date: form.sale_date, customer: form.customer,
        notes: form.notes || null,
        commission_gross: cg, commission_base: c.base, commission_gst: c.gst,
        clra_gross: cl, clra_base: cl2.base, clra_gst: cl2.gst,
        compliance_gross: co, compliance_base: co2.base, compliance_gst: co2.gst,
        other_gross: ot, other_base: ot2.base, other_gst: ot2.gst,
        tds: Number(form.tds || 0), gst_payable: Number(form.gst_payable || 0),
        total_gross: 0, net_receivable: 0,
      });
      setForm({ ...emptyForm }); setShowForm(false); await load();
    } catch (err) { setError(apiErrorMessage(err)); }
    finally { setSubmitting(false); }
  };
  const remove = async (id: number) => {
    if (!confirm('Delete this sale record?')) return;
    await api.delete(`/sales/${id}`); await load();
  };
  const totalGross = rows.reduce((s, r) => s + Number(r.total_gross), 0);
  const totalNet = rows.reduce((s, r) => s + Number(r.net_receivable), 0);
  const columns: Column<Sale>[] = [
    { key: 'date', header: 'Date', render: (r) => formatDate(r.sale_date) },
    { key: 'invoice', header: 'Invoice', render: (r) => <span className="mono">{r.invoice_no}</span> },
    { key: 'customer', header: 'Customer', render: (r) => r.customer },
    { key: 'commission', header: 'Commission', align: 'right', render: (r) => <span className="mono">{formatINR(r.commission_gross)}</span> },
    { key: 'clra', header: 'CLRA', align: 'right', render: (r) => <span className="mono">{formatINR(r.clra_gross)}</span> },
    { key: 'compliance', header: 'Compliance', align: 'right', render: (r) => <span className="mono">{formatINR(r.compliance_gross)}</span> },
    { key: 'other', header: 'Other', align: 'right', render: (r) => <span className="mono">{formatINR(r.other_gross)}</span> },
    { key: 'tds', header: 'TDS', align: 'right', render: (r) => <span className="mono">{formatINR(r.tds)}</span> },
    { key: 'gst', header: 'GST Payable', align: 'right', render: (r) => <span className="mono">{formatINR(r.gst_payable)}</span> },
    { key: 'total', header: 'Total', align: 'right', render: (r) => <strong className="mono">{formatINR(r.total_gross)}</strong> },
    { key: 'actions', header: '', align: 'right',
      render: (r) => <button className="icon-btn" onClick={() => remove(r.id)}><Trash2 size={15} /></button> },
  ];
  return (
    <>
      <div className="page-header">
        <div>
          <h1 className="page-title">Sales</h1>
          <p className="page-subtitle">Commission, CLRA, Compliance, Other (incl. GST), TDS, GST Payable</p>
        </div>
        <div className="page-actions">
          <Button variant={showForm ? 'secondary' : 'primary'} icon={<Plus size={15} />}
            onClick={() => setShowForm((s) => !s)}>
            {showForm ? 'Cancel' : 'New Sale'}
          </Button>
        </div>
      </div>
      {error && <div className="login-error" style={{ marginBottom: 16 }}>{error}</div>}
      {showForm && (
        <Card title="New Sales Entry" subtitle="All amounts are inclusive of GST unless noted">
          <form onSubmit={onSubmit}>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 14 }}>
              <Input label="Invoice No." value={form.invoice_no} onChange={(e) => set('invoice_no', e.target.value)} required />
              <Input label="Sale Date" type="date" value={form.sale_date} onChange={(e) => set('sale_date', e.target.value)} required />
              <Input label="Customer" value={form.customer} onChange={(e) => set('customer', e.target.value)} required />
              <Input label="Commission (incl. GST)" type="number" step="0.01" value={form.commission_gross} onChange={(e) => set('commission_gross', e.target.value)} />
              <Input label="CLRA Charges (incl. GST)" type="number" step="0.01" value={form.clra_gross} onChange={(e) => set('clra_gross', e.target.value)} />
              <Input label="Compliance Fee (incl. GST)" type="number" step="0.01" value={form.compliance_gross} onChange={(e) => set('compliance_gross', e.target.value)} />
              <Input label="Other Charges (incl. GST)" type="number" step="0.01" value={form.other_gross} onChange={(e) => set('other_gross', e.target.value)} />
              <Input label="TDS" type="number" step="0.01" value={form.tds} onChange={(e) => set('tds', e.target.value)} />
              <Input label="GST Payable" type="number" step="0.01" value={form.gst_payable} onChange={(e) => set('gst_payable', e.target.value)} />
            </div>
            <div style={{ marginTop: 14 }}>
              <Input label="Notes (optional)" value={form.notes} onChange={(e) => set('notes', e.target.value)} />
            </div>
            <div style={{ marginTop: 18, display: 'flex', gap: 10, justifyContent: 'flex-end' }}>
              <Button variant="secondary" type="button" onClick={() => setShowForm(false)}>Cancel</Button>
              <Button type="submit" loading={submitting}>Save Sale</Button>
            </div>
          </form>
        </Card>
      )}
      <div style={{ marginTop: showForm ? 20 : 0 }}>
        <Card title="Sales Records"
          subtitle={`${rows.length} records · Total: ${formatINR(totalGross)} · Net: ${formatINR(totalNet)}`}
          padded={false}>
          <Table columns={columns} rows={rows} empty="No sales recorded yet." />
        </Card>
      </div>
    </>
  );
}
EOF

cat > "$ROOT/frontend/src/pages/Purchases.tsx" <<'EOF'
import { FormEvent, useEffect, useState } from 'react';
import { Plus, Trash2 } from 'lucide-react';
import Button from '../components/ui/Button';
import Card from '../components/ui/Card';
import { Input } from '../components/ui/Input';
import Table, { type Column } from '../components/ui/Table';
import { api, apiErrorMessage } from '../lib/api';
import { formatDate, formatINR, todayISO } from '../lib/format';

interface Purchase {
  id: number; bill_no: string; purchase_date: string; vendor: string;
  amount: string; gst: string; total: string; notes: string | null;
}
const emptyForm = { bill_no: '', purchase_date: todayISO(), vendor: '', amount: '', gst: '', notes: '' };

export default function Purchases() {
  const [rows, setRows] = useState<Purchase[]>([]);
  const [form, setForm] = useState({ ...emptyForm });
  const [showForm, setShowForm] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const load = async () => {
    try { const { data } = await api.get<Purchase[]>('/purchases'); setRows(data); }
    catch (err) { setError(apiErrorMessage(err)); }
  };
  useEffect(() => { load(); }, []);
  const set = (k: keyof typeof form, v: string) => setForm((f) => ({ ...f, [k]: v }));
  const onSubmit = async (e: FormEvent) => {
    e.preventDefault(); setError(null); setSubmitting(true);
    const amount = Number(form.amount || 0);
    const gst = Number(form.gst || 0);
    try {
      await api.post('/purchases', {
        bill_no: form.bill_no, purchase_date: form.purchase_date, vendor: form.vendor,
        amount, gst, total: amount + gst, notes: form.notes || null,
      });
      setForm({ ...emptyForm }); setShowForm(false); await load();
    } catch (err) { setError(apiErrorMessage(err)); }
    finally { setSubmitting(false); }
  };
  const remove = async (id: number) => {
    if (!confirm('Delete this purchase?')) return;
    await api.delete(`/purchases/${id}`); await load();
  };
  const columns: Column<Purchase>[] = [
    { key: 'date', header: 'Date', render: (r) => formatDate(r.purchase_date) },
    { key: 'bill', header: 'Bill', render: (r) => <span className="mono">{r.bill_no}</span> },
    { key: 'vendor', header: 'Vendor', render: (r) => r.vendor },
    { key: 'amount', header: 'Amount', align: 'right', render: (r) => <span className="mono">{formatINR(r.amount)}</span> },
    { key: 'gst', header: 'GST', align: 'right', render: (r) => <span className="mono">{formatINR(r.gst)}</span> },
    { key: 'total', header: 'Total', align: 'right', render: (r) => <strong className="mono">{formatINR(r.total)}</strong> },
    { key: 'actions', header: '', align: 'right',
      render: (r) => <button className="icon-btn" onClick={() => remove(r.id)}><Trash2 size={15} /></button> },
  ];
  return (
    <>
      <div className="page-header">
        <div>
          <h1 className="page-title">Purchases</h1>
          <p className="page-subtitle">Vendor bills and inward GST</p>
        </div>
        <div className="page-actions">
          <Button variant={showForm ? 'secondary' : 'primary'} icon={<Plus size={15} />}
            onClick={() => setShowForm((s) => !s)}>
            {showForm ? 'Cancel' : 'New Purchase'}
          </Button>
        </div>
      </div>
      {error && <div className="login-error" style={{ marginBottom: 16 }}>{error}</div>}
      {showForm && (
        <Card title="New Purchase">
          <form onSubmit={onSubmit}>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 14 }}>
              <Input label="Bill No." value={form.bill_no} onChange={(e) => set('bill_no', e.target.value)} required />
              <Input label="Purchase Date" type="date" value={form.purchase_date} onChange={(e) => set('purchase_date', e.target.value)} required />
              <Input label="Vendor" value={form.vendor} onChange={(e) => set('vendor', e.target.value)} required />
              <Input label="Amount (excl. GST)" type="number" step="0.01" value={form.amount} onChange={(e) => set('amount', e.target.value)} required />
              <Input label="GST" type="number" step="0.01" value={form.gst} onChange={(e) => set('gst', e.target.value)} />
              <Input label="Notes" value={form.notes} onChange={(e) => set('notes', e.target.value)} />
            </div>
            <div style={{ marginTop: 18, display: 'flex', gap: 10, justifyContent: 'flex-end' }}>
              <Button variant="secondary" type="button" onClick={() => setShowForm(false)}>Cancel</Button>
              <Button type="submit" loading={submitting}>Save Purchase</Button>
            </div>
          </form>
        </Card>
      )}
      <div style={{ marginTop: showForm ? 20 : 0 }}>
        <Card title="Purchase Records" padded={false}>
          <Table columns={columns} rows={rows} empty="No purchases yet." />
        </Card>
      </div>
    </>
  );
}
EOF

cat > "$ROOT/frontend/src/pages/Expenses.tsx" <<'EOF'
import { FormEvent, useEffect, useState } from 'react';
import { CheckCircle2, Plus } from 'lucide-react';
import Badge from '../components/ui/Badge';
import Button from '../components/ui/Button';
import Card from '../components/ui/Card';
import { Input, Select } from '../components/ui/Input';
import Table, { type Column } from '../components/ui/Table';
import { api, apiErrorMessage } from '../lib/api';
import { formatDate, formatINR, todayISO } from '../lib/format';

type Category = 'rent' | 'electricity' | 'maintenance' | 'other';
interface Expense {
  id: number; category: Category; description: string; amount: string;
  expense_date: string; due_date: string | null; is_paid: boolean; notes: string | null;
}
const LABEL: Record<Category, string> = {
  rent: 'Rent', electricity: 'Electricity', maintenance: 'Maintenance', other: 'Other',
};
const emptyForm = {
  category: 'rent' as Category, description: '', amount: '',
  expense_date: todayISO(), due_date: '', notes: '',
};

export default function Expenses() {
  const [rows, setRows] = useState<Expense[]>([]);
  const [form, setForm] = useState({ ...emptyForm });
  const [showForm, setShowForm] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const load = async () => {
    try { const { data } = await api.get<Expense[]>('/expenses'); setRows(data); }
    catch (err) { setError(apiErrorMessage(err)); }
  };
  useEffect(() => { load(); }, []);
  const set = <K extends keyof typeof form>(k: K, v: (typeof form)[K]) =>
    setForm((f) => ({ ...f, [k]: v }));
  const onSubmit = async (e: FormEvent) => {
    e.preventDefault(); setError(null); setSubmitting(true);
    try {
      await api.post('/expenses', {
        category: form.category, description: form.description,
        amount: Number(form.amount || 0), expense_date: form.expense_date,
        due_date: form.due_date || null, is_paid: false, notes: form.notes || null,
      });
      setForm({ ...emptyForm }); setShowForm(false); await load();
    } catch (err) { setError(apiErrorMessage(err)); }
    finally { setSubmitting(false); }
  };
  const markPaid = async (id: number) => { await api.patch(`/expenses/${id}/paid`); await load(); };
  const columns: Column<Expense>[] = [
    { key: 'category', header: 'Category', render: (r) => LABEL[r.category] },
    { key: 'description', header: 'Description', render: (r) => r.description },
    { key: 'date', header: 'Date', render: (r) => formatDate(r.expense_date) },
    { key: 'due', header: 'Due', render: (r) => (r.due_date ? formatDate(r.due_date) : '—') },
    { key: 'amount', header: 'Amount', align: 'right', render: (r) => <span className="mono">{formatINR(r.amount)}</span> },
    { key: 'status', header: 'Status',
      render: (r) => (r.is_paid ? <Badge tone="success">Paid</Badge> : <Badge tone="warning">Pending</Badge>) },
    { key: 'actions', header: '', align: 'right',
      render: (r) => r.is_paid ? null :
        <button className="icon-btn" onClick={() => markPaid(r.id)} title="Mark paid"><CheckCircle2 size={16} /></button> },
  ];
  const total = rows.reduce((s, r) => s + Number(r.amount), 0);
  const unpaid = rows.filter((r) => !r.is_paid).reduce((s, r) => s + Number(r.amount), 0);
  return (
    <>
      <div className="page-header">
        <div>
          <h1 className="page-title">Fixed Expenses</h1>
          <p className="page-subtitle">Total: {formatINR(total)} · Outstanding: {formatINR(unpaid)}</p>
        </div>
        <div className="page-actions">
          <Button variant={showForm ? 'secondary' : 'primary'} icon={<Plus size={15} />}
            onClick={() => setShowForm((s) => !s)}>
            {showForm ? 'Cancel' : 'Add Expense'}
          </Button>
        </div>
      </div>
      {error && <div className="login-error" style={{ marginBottom: 16 }}>{error}</div>}
      {showForm && (
        <Card title="New Fixed Expense">
          <form onSubmit={onSubmit}>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 14 }}>
              <Select label="Category" value={form.category}
                onChange={(e) => set('category', e.target.value as Category)}>
                <option value="rent">Rent</option>
                <option value="electricity">Electricity</option>
                <option value="maintenance">Maintenance</option>
                <option value="other">Other</option>
              </Select>
              <Input label="Description" value={form.description} onChange={(e) => set('description', e.target.value)} required />
              <Input label="Amount" type="number" step="0.01" value={form.amount} onChange={(e) => set('amount', e.target.value)} required />
              <Input label="Expense Date" type="date" value={form.expense_date} onChange={(e) => set('expense_date', e.target.value)} required />
              <Input label="Due Date (optional)" type="date" value={form.due_date} onChange={(e) => set('due_date', e.target.value)} />
              <Input label="Notes" value={form.notes} onChange={(e) => set('notes', e.target.value)} />
            </div>
            <div style={{ marginTop: 18, display: 'flex', gap: 10, justifyContent: 'flex-end' }}>
              <Button variant="secondary" type="button" onClick={() => setShowForm(false)}>Cancel</Button>
              <Button type="submit" loading={submitting}>Save Expense</Button>
            </div>
          </form>
        </Card>
      )}
      <div style={{ marginTop: showForm ? 20 : 0 }}>
        <Card title="Expense Records" padded={false}>
          <Table columns={columns} rows={rows} empty="No expenses recorded." />
        </Card>
      </div>
    </>
  );
}
EOF

cat > "$ROOT/frontend/src/pages/Employees.tsx" <<'EOF'
import { FormEvent, useEffect, useState } from 'react';
import { Plus } from 'lucide-react';
import Badge from '../components/ui/Badge';
import Button from '../components/ui/Button';
import Card from '../components/ui/Card';
import { Input } from '../components/ui/Input';
import Table, { type Column } from '../components/ui/Table';
import { api, apiErrorMessage } from '../lib/api';
import { formatDate, formatINR, todayISO } from '../lib/format';

interface Employee {
  id: number; emp_code: string; full_name: string; designation: string;
  department: string | null; date_of_joining: string;
  basic_salary: string; hra: string; allowances: string;
  pan: string | null; uan: string | null; esi_no: string | null; is_active: boolean;
}
const emptyForm = {
  emp_code: '', full_name: '', designation: '', department: '',
  date_of_joining: todayISO(), basic_salary: '', hra: '', allowances: '',
  pan: '', uan: '', esi_no: '',
};

export default function Employees() {
  const [rows, setRows] = useState<Employee[]>([]);
  const [form, setForm] = useState({ ...emptyForm });
  const [showForm, setShowForm] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const load = async () => {
    try { const { data } = await api.get<Employee[]>('/employees'); setRows(data); }
    catch (err) { setError(apiErrorMessage(err)); }
  };
  useEffect(() => { load(); }, []);
  const set = (k: keyof typeof form, v: string) => setForm((f) => ({ ...f, [k]: v }));
  const onSubmit = async (e: FormEvent) => {
    e.preventDefault(); setError(null); setSubmitting(true);
    try {
      await api.post('/employees', {
        ...form, basic_salary: Number(form.basic_salary || 0),
        hra: Number(form.hra || 0), allowances: Number(form.allowances || 0),
        department: form.department || null,
        pan: form.pan || null, uan: form.uan || null, esi_no: form.esi_no || null,
        is_active: true,
      });
      setForm({ ...emptyForm }); setShowForm(false); await load();
    } catch (err) { setError(apiErrorMessage(err)); }
    finally { setSubmitting(false); }
  };
  const columns: Column<Employee>[] = [
    { key: 'code', header: 'Code', render: (r) => <span className="mono">{r.emp_code}</span> },
    { key: 'name', header: 'Name', render: (r) => r.full_name },
    { key: 'desig', header: 'Designation', render: (r) => r.designation },
    { key: 'doj', header: 'Joined', render: (r) => formatDate(r.date_of_joining) },
    { key: 'basic', header: 'Basic', align: 'right', render: (r) => <span className="mono">{formatINR(r.basic_salary)}</span> },
    { key: 'hra', header: 'HRA', align: 'right', render: (r) => <span className="mono">{formatINR(r.hra)}</span> },
    { key: 'allow', header: 'Allowances', align: 'right', render: (r) => <span className="mono">{formatINR(r.allowances)}</span> },
    { key: 'active', header: 'Status',
      render: (r) => r.is_active ? <Badge tone="success">Active</Badge> : <Badge>Inactive</Badge> },
  ];
  return (
    <>
      <div className="page-header">
        <div>
          <h1 className="page-title">Employees</h1>
          <p className="page-subtitle">{rows.length} employees · salary & statutory tracked on the Salary page</p>
        </div>
        <div className="page-actions">
          <Button variant={showForm ? 'secondary' : 'primary'} icon={<Plus size={15} />}
            onClick={() => setShowForm((s) => !s)}>
            {showForm ? 'Cancel' : 'New Employee'}
          </Button>
        </div>
      </div>
      {error && <div className="login-error" style={{ marginBottom: 16 }}>{error}</div>}
      {showForm && (
        <Card title="New Employee">
          <form onSubmit={onSubmit}>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 14 }}>
              <Input label="Employee Code" value={form.emp_code} onChange={(e) => set('emp_code', e.target.value)} required />
              <Input label="Full Name" value={form.full_name} onChange={(e) => set('full_name', e.target.value)} required />
              <Input label="Designation" value={form.designation} onChange={(e) => set('designation', e.target.value)} required />
              <Input label="Department" value={form.department} onChange={(e) => set('department', e.target.value)} />
              <Input label="Date of Joining" type="date" value={form.date_of_joining} onChange={(e) => set('date_of_joining', e.target.value)} required />
              <Input label="Basic Salary" type="number" step="0.01" value={form.basic_salary} onChange={(e) => set('basic_salary', e.target.value)} required />
              <Input label="HRA" type="number" step="0.01" value={form.hra} onChange={(e) => set('hra', e.target.value)} />
              <Input label="Allowances" type="number" step="0.01" value={form.allowances} onChange={(e) => set('allowances', e.target.value)} />
              <Input label="PAN" value={form.pan} onChange={(e) => set('pan', e.target.value)} />
              <Input label="UAN" value={form.uan} onChange={(e) => set('uan', e.target.value)} />
              <Input label="ESI No." value={form.esi_no} onChange={(e) => set('esi_no', e.target.value)} />
            </div>
            <div style={{ marginTop: 18, display: 'flex', gap: 10, justifyContent: 'flex-end' }}>
              <Button variant="secondary" type="button" onClick={() => setShowForm(false)}>Cancel</Button>
              <Button type="submit" loading={submitting}>Save Employee</Button>
            </div>
          </form>
        </Card>
      )}
      <div style={{ marginTop: showForm ? 20 : 0 }}>
        <Card title="Employees" padded={false}>
          <Table columns={columns} rows={rows} empty="No employees yet." />
        </Card>
      </div>
    </>
  );
}
EOF

cat > "$ROOT/frontend/src/pages/Salary.tsx" <<'EOF'
import { FormEvent, useEffect, useState } from 'react';
import { CheckCircle2, Plus } from 'lucide-react';
import Badge from '../components/ui/Badge';
import Button from '../components/ui/Button';
import Card from '../components/ui/Card';
import { Input, Select } from '../components/ui/Input';
import Table, { type Column } from '../components/ui/Table';
import { api, apiErrorMessage } from '../lib/api';
import { formatINR } from '../lib/format';

interface Employee { id: number; full_name: string; emp_code: string; basic_salary: string }
interface Salary {
  id: number; employee_id: number; employee_name: string | null;
  pay_period: string; gross: string; pf_employee: string; pf_employer: string;
  esi_employee: string; esi_employer: string; income_tax: string;
  other_deductions: string; net_pay: string; paid: boolean; paid_on: string | null;
}
const emptyForm = {
  employee_id: '', pay_period: new Date().toISOString().slice(0, 7),
  gross: '', income_tax: '', other_deductions: '', notes: '',
};

export default function Salary() {
  const [rows, setRows] = useState<Salary[]>([]);
  const [employees, setEmployees] = useState<Employee[]>([]);
  const [form, setForm] = useState({ ...emptyForm });
  const [showForm, setShowForm] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [preview, setPreview] = useState<{ pf_employee: string; pf_employer: string; esi_employee: string; esi_employer: string } | null>(null);
  const load = async () => {
    try {
      const [s, e] = await Promise.all([api.get<Salary[]>('/salary'), api.get<Employee[]>('/employees')]);
      setRows(s.data); setEmployees(e.data);
    } catch (err) { setError(apiErrorMessage(err)); }
  };
  useEffect(() => { load(); }, []);
  const set = (k: keyof typeof form, v: string) => setForm((f) => ({ ...f, [k]: v }));
  const onGrossChange = async (v: string) => {
    set('gross', v);
    const g = Number(v);
    if (g > 0) {
      try {
        const { data } = await api.get('/salary/preview', { params: { gross: g } });
        setPreview(data);
      } catch { /* ignore */ }
    } else setPreview(null);
  };
  const onSubmit = async (e: FormEvent) => {
    e.preventDefault(); setError(null); setSubmitting(true);
    const gross = Number(form.gross || 0);
    const pfEmp = Number(preview?.pf_employee ?? 0);
    const pfEr = Number(preview?.pf_employer ?? 0);
    const esiEmp = Number(preview?.esi_employee ?? 0);
    const esiEr = Number(preview?.esi_employer ?? 0);
    const it = Number(form.income_tax || 0);
    const other = Number(form.other_deductions || 0);
    const net = gross - pfEmp - esiEmp - it - other;
    try {
      await api.post('/salary', {
        employee_id: Number(form.employee_id), pay_period: form.pay_period,
        gross, pf_employee: pfEmp, pf_employer: pfEr,
        esi_employee: esiEmp, esi_employer: esiEr,
        income_tax: it, other_deductions: other, net_pay: net,
        paid: false, notes: form.notes || null,
      });
      setForm({ ...emptyForm }); setPreview(null); setShowForm(false); await load();
    } catch (err) { setError(apiErrorMessage(err)); }
    finally { setSubmitting(false); }
  };
  const markPaid = async (id: number) => { await api.patch(`/salary/${id}/paid`); await load(); };
  const columns: Column<Salary>[] = [
    { key: 'period', header: 'Period', render: (r) => <span className="mono">{r.pay_period}</span> },
    { key: 'emp', header: 'Employee', render: (r) => r.employee_name ?? `#${r.employee_id}` },
    { key: 'gross', header: 'Gross', align: 'right', render: (r) => <span className="mono">{formatINR(r.gross)}</span> },
    { key: 'pf', header: 'PF (Emp)', align: 'right', render: (r) => <span className="mono">{formatINR(r.pf_employee)}</span> },
    { key: 'esi', header: 'ESI (Emp)', align: 'right', render: (r) => <span className="mono">{formatINR(r.esi_employee)}</span> },
    { key: 'it', header: 'Income Tax', align: 'right', render: (r) => <span className="mono">{formatINR(r.income_tax)}</span> },
    { key: 'net', header: 'Net Pay', align: 'right', render: (r) => <strong className="mono">{formatINR(r.net_pay)}</strong> },
    { key: 'status', header: 'Status',
      render: (r) => r.paid ? <Badge tone="success">Paid</Badge> : <Badge tone="warning">Pending</Badge> },
    { key: 'actions', header: '', align: 'right',
      render: (r) => r.paid ? null :
        <button className="icon-btn" onClick={() => markPaid(r.id)}><CheckCircle2 size={16} /></button> },
  ];
  return (
    <>
      <div className="page-header">
        <div>
          <h1 className="page-title">Salary & Statutory</h1>
          <p className="page-subtitle">PF 12% · ESI 0.75/3.25% · Income tax per slab</p>
        </div>
        <div className="page-actions">
          <Button variant={showForm ? 'secondary' : 'primary'} icon={<Plus size={15} />}
            onClick={() => setShowForm((s) => !s)}>
            {showForm ? 'Cancel' : 'New Salary'}
          </Button>
        </div>
      </div>
      {error && <div className="login-error" style={{ marginBottom: 16 }}>{error}</div>}
      {showForm && (
        <Card title="New Salary Record">
          <form onSubmit={onSubmit}>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 14 }}>
              <Select label="Employee" value={form.employee_id}
                onChange={(e) => set('employee_id', e.target.value)} required>
                <option value="">Select employee…</option>
                {employees.map((emp) => (
                  <option key={emp.id} value={emp.id}>{emp.emp_code} · {emp.full_name}</option>
                ))}
              </Select>
              <Input label="Pay Period (YYYY-MM)" value={form.pay_period}
                onChange={(e) => set('pay_period', e.target.value)} required />
              <Input label="Gross" type="number" step="0.01" value={form.gross}
                onChange={(e) => onGrossChange(e.target.value)} required />
              <Input label="Income Tax" type="number" step="0.01" value={form.income_tax}
                onChange={(e) => set('income_tax', e.target.value)} />
              <Input label="Other Deductions" type="number" step="0.01" value={form.other_deductions}
                onChange={(e) => set('other_deductions', e.target.value)} />
              <Input label="Notes" value={form.notes} onChange={(e) => set('notes', e.target.value)} />
            </div>
            {preview && (
              <div className="stat-tile" style={{ marginTop: 18 }}>
                <div className="stat-head"><span className="stat-label">Auto-computed statutory</span></div>
                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 12, marginTop: 8 }}>
                  <div><div className="field-label">PF (Emp)</div><div className="mono">{formatINR(preview.pf_employee)}</div></div>
                  <div><div className="field-label">PF (Er)</div><div className="mono">{formatINR(preview.pf_employer)}</div></div>
                  <div><div className="field-label">ESI (Emp)</div><div className="mono">{formatINR(preview.esi_employee)}</div></div>
                  <div><div className="field-label">ESI (Er)</div><div className="mono">{formatINR(preview.esi_employer)}</div></div>
                </div>
              </div>
            )}
            <div style={{ marginTop: 18, display: 'flex', gap: 10, justifyContent: 'flex-end' }}>
              <Button variant="secondary" type="button" onClick={() => setShowForm(false)}>Cancel</Button>
              <Button type="submit" loading={submitting}>Save Salary</Button>
            </div>
          </form>
        </Card>
      )}
      <div style={{ marginTop: showForm ? 20 : 0 }}>
        <Card title="Salary Records" padded={false}>
          <Table columns={columns} rows={rows} empty="No salary records." />
        </Card>
      </div>
    </>
  );
}
EOF

cat > "$ROOT/frontend/src/pages/Reports.tsx" <<'EOF'
import Card from '../components/ui/Card';
export default function Reports() {
  return (
    <>
      <div className="page-header">
        <div>
          <h1 className="page-title">Reports</h1>
          <p className="page-subtitle">Export and audit summaries</p>
        </div>
      </div>
      <Card title="Reports" subtitle="Excel / PDF export scaffolding" padded>
        <p style={{ color: 'var(--text-muted)' }}>
          Backend endpoints for Excel (with ₹ symbol) and PDF are stubbed in
          <code> backend/app/routers/reports.py</code>. Extend there to add
          per-entity export routes.
        </p>
      </Card>
    </>
  );
}
EOF

cat > "$ROOT/frontend/src/pages/Settings.tsx" <<'EOF'
import { useEffect, useState } from 'react';
import Badge from '../components/ui/Badge';
import Card from '../components/ui/Card';
import { branding } from '../config/branding.config';
import { api } from '../lib/api';

interface ServerSettings { app_name: string; environment: string; database: string }

export default function Settings() {
  const [srv, setSrv] = useState<ServerSettings | null>(null);
  useEffect(() => {
    api.get<ServerSettings>('/settings/server').then(({ data }) => setSrv(data)).catch(() => {});
  }, []);
  return (
    <>
      <div className="page-header">
        <div>
          <h1 className="page-title">Settings</h1>
          <p className="page-subtitle">Branding is embedded at build time</p>
        </div>
      </div>
      <Card title="Company Branding" subtitle="From VITE_* environment variables" padded>
        <div className="kv"><span>Company Name</span><code>{branding.companyName}</code></div>
        <div className="kv"><span>Company ID</span><code>{branding.companyId}</code></div>
        <div className="kv"><span>Title Modifier</span><code>{branding.titleModifier}</code></div>
        <div className="kv"><span>GSTIN</span><code>{branding.gstin || '—'}</code></div>
        <div className="kv"><span>PAN</span><code>{branding.pan || '—'}</code></div>
        <div className="kv"><span>Contact Email</span><code>{branding.contactEmail || '—'}</code></div>
        <div className="kv"><span>Contact Phone</span><code>{branding.contactPhone || '—'}</code></div>
      </Card>
      <div style={{ marginTop: 20 }}>
        <Card title="Server" subtitle="From /api/settings/server" padded>
          {srv ? (
            <>
              <div className="kv"><span>App Name</span><code>{srv.app_name}</code></div>
              <div className="kv"><span>Environment</span>
                <Badge tone={srv.environment === 'production' ? 'success' : 'warning'}>
                  {srv.environment}
                </Badge>
              </div>
              <div className="kv"><span>Database</span>
                <Badge tone={srv.database === 'sqlite' ? 'warning' : 'success'}>
                  {srv.database}
                </Badge>
              </div>
            </>
          ) : <div className="table-empty">Loading…</div>}
        </Card>
      </div>
    </>
  );
}
EOF

cat > "$ROOT/frontend/src/pages/AuditLogs.tsx" <<'EOF'
import { useEffect, useState } from 'react';
import Badge from '../components/ui/Badge';
import Card from '../components/ui/Card';
import Table, { type Column } from '../components/ui/Table';
import { api, apiErrorMessage } from '../lib/api';

interface AuditEntry {
  id: number; user_email: string | null; action: string; entity: string;
  entity_id: string | null; details: string | null;
  ip_address: string | null; created_at: string;
}

export default function AuditLogs() {
  const [rows, setRows] = useState<AuditEntry[]>([]);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    api.get<AuditEntry[]>('/audit').then(({ data }) => setRows(data))
      .catch((err) => setError(apiErrorMessage(err)));
  }, []);
  const columns: Column<AuditEntry>[] = [
    { key: 'ts', header: 'Timestamp',
      render: (r) => <span className="mono" style={{ fontSize: 12 }}>{new Date(r.created_at).toLocaleString('en-IN')}</span> },
    { key: 'user', header: 'User', render: (r) => r.user_email ?? '—' },
    { key: 'action', header: 'Action', render: (r) => <Badge>{r.action}</Badge> },
    { key: 'entity', header: 'Entity', render: (r) => r.entity },
    { key: 'id', header: 'Entity ID',
      render: (r) => r.entity_id ? <span className="mono">{r.entity_id}</span> : '—' },
    { key: 'details', header: 'Details', render: (r) => r.details ?? '—' },
    { key: 'ip', header: 'IP',
      render: (r) => <span className="mono" style={{ fontSize: 12 }}>{r.ip_address ?? '—'}</span> },
  ];
  return (
    <>
      <div className="page-header">
        <div>
          <h1 className="page-title">Audit Logs</h1>
          <p className="page-subtitle">Full audit trail is available in Admin Console → Application Logs</p>
        </div>
      </div>
      {error && <div className="login-error" style={{ marginBottom: 16 }}>{error}</div>}
      <Card title="Recent Activity" padded={false}>
        <Table columns={columns} rows={rows} empty="No audit entries." />
      </Card>
    </>
  );
}
EOF

cat > "$ROOT/frontend/src/pages/admin/AdminConsole.tsx" <<'EOF'
import { Activity, ScrollText, Server, Users } from 'lucide-react';
import { useState } from 'react';
import AppLogsTab from './AppLogsTab';
import HealthTab from './HealthTab';
import ServerLogsTab from './ServerLogsTab';
import UsersTab from './UsersTab';

type Tab = 'health' | 'users' | 'app-logs' | 'server-logs';
const TABS: { key: Tab; label: string; icon: typeof Activity }[] = [
  { key: 'health', label: 'System Health', icon: Activity },
  { key: 'users', label: 'User Management', icon: Users },
  { key: 'app-logs', label: 'Application Logs', icon: ScrollText },
  { key: 'server-logs', label: 'Server Logs', icon: Server },
];

export default function AdminConsole() {
  const [tab, setTab] = useState<Tab>('health');
  return (
    <>
      <div className="page-header">
        <div>
          <h1 className="page-title">Admin Console</h1>
          <p className="page-subtitle">
            Monitor system health, manage users, and inspect application and server logs
          </p>
        </div>
      </div>
      <div className="tabs">
        {TABS.map(({ key, label, icon: Icon }) => (
          <button key={key} className={`tab${tab === key ? ' tab-active' : ''}`}
            onClick={() => setTab(key)}>
            <Icon size={16} /><span>{label}</span>
          </button>
        ))}
      </div>
      <div className="tab-panel">
        {tab === 'health' && <HealthTab />}
        {tab === 'users' && <UsersTab />}
        {tab === 'app-logs' && <AppLogsTab />}
        {tab === 'server-logs' && <ServerLogsTab />}
      </div>
    </>
  );
}
EOF

cat > "$ROOT/frontend/src/pages/admin/HealthTab.tsx" <<'EOF'
import { Activity, AlertTriangle, CheckCircle2, Clock, Cpu, Database, HardDrive, MemoryStick, Users } from 'lucide-react';
import { useCallback, useEffect, useState } from 'react';
import Badge from '../../components/ui/Badge';
import Button from '../../components/ui/Button';
import Card from '../../components/ui/Card';
import StatTile from '../../components/ui/StatTile';
import { api, apiErrorMessage } from '../../lib/api';

interface Health {
  status: string; environment: string; version: string; database: string;
  uptime_seconds: number; db_ok: boolean; db_latency_ms: number;
  cpu_percent: number; memory_percent: number; disk_percent: number;
  log_file: string; log_size_bytes: number;
  request_count: number; error_count: number;
  user_count: number; active_session_count: number;
}
const uptime = (s: number) => {
  const d = Math.floor(s / 86400);
  const h = Math.floor((s % 86400) / 3600);
  const m = Math.floor((s % 3600) / 60);
  if (d > 0) return `${d}d ${h}h ${m}m`;
  if (h > 0) return `${h}h ${m}m`;
  return `${m}m`;
};
const bytes = (b: number) =>
  b < 1024 ? `${b} B`
  : b < 1024 * 1024 ? `${(b / 1024).toFixed(1)} KB`
  : `${(b / (1024 * 1024)).toFixed(2)} MB`;

export default function HealthTab() {
  const [data, setData] = useState<Health | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [autoRefresh, setAutoRefresh] = useState(true);

  const load = useCallback(async () => {
    setLoading(true); setError(null);
    try { const { data } = await api.get<Health>('/admin/health'); setData(data); }
    catch (err) { setError(apiErrorMessage(err)); }
    finally { setLoading(false); }
  }, []);

  useEffect(() => {
    load();
    if (!autoRefresh) return;
    const t = setInterval(load, 10000);
    return () => clearInterval(t);
  }, [load, autoRefresh]);

  const errorRate = data && data.request_count > 0
    ? ((data.error_count / data.request_count) * 100).toFixed(2) : '0.00';

  return (
    <>
      <div className="page-actions" style={{ marginBottom: 16, justifyContent: 'flex-end' }}>
        <label className="checkbox-line">
          <input type="checkbox" checked={autoRefresh}
            onChange={(e) => setAutoRefresh(e.target.checked)} />
          Auto-refresh every 10s
        </label>
        <Button variant="secondary" onClick={load} loading={loading}>Refresh</Button>
      </div>
      {error && <div className="login-error" style={{ marginBottom: 16 }}>{error}</div>}
      {data && (<>
        <Card padded>
          <div className="status-banner">
            {data.status === 'ok' ? (<>
              <CheckCircle2 size={22} color="var(--color-success)" />
              <div>
                <strong>All systems operational</strong>
                <p>Environment <code>{data.environment}</code> · Version <code>{data.version}</code> · Database <code>{data.database}</code></p>
              </div>
            </>) : (<>
              <AlertTriangle size={22} color="var(--color-danger)" />
              <div><strong>Degraded</strong><p>The database is unresponsive.</p></div>
            </>)}
          </div>
        </Card>
        <div className="grid-stats" style={{ marginTop: 20 }}>
          <StatTile label="Uptime" value={uptime(data.uptime_seconds)} icon={<Clock size={18} />} />
          <StatTile label="Database" value={data.db_ok ? 'Healthy' : 'Down'}
            tone={data.db_ok ? 'success' : 'danger'}
            icon={<Database size={18} />} hint={`${data.db_latency_ms.toFixed(1)} ms`} />
          <StatTile label="CPU" value={`${data.cpu_percent.toFixed(1)}%`}
            tone={data.cpu_percent > 85 ? 'danger' : 'neutral'} icon={<Cpu size={18} />} />
          <StatTile label="Memory" value={`${data.memory_percent.toFixed(1)}%`}
            tone={data.memory_percent > 85 ? 'danger' : 'neutral'} icon={<MemoryStick size={18} />} />
          <StatTile label="Disk" value={`${data.disk_percent.toFixed(1)}%`}
            tone={data.disk_percent > 85 ? 'danger' : 'neutral'} icon={<HardDrive size={18} />} />
          <StatTile label="Users" value={String(data.user_count)}
            hint={`${data.active_session_count} active`} icon={<Users size={18} />} />
          <StatTile label="Requests" value={data.request_count.toLocaleString()} icon={<Activity size={18} />} />
          <StatTile label="Errors" value={String(data.error_count)}
            tone={data.error_count > 0 ? 'danger' : 'neutral'} hint={`${errorRate}% rate`} />
        </div>
        <Card title="Log File" subtitle="Rotating file — readable from Server Logs tab" padded>
          <div className="kv"><span>Path</span><code>{data.log_file}</code></div>
          <div className="kv"><span>Size</span><code>{bytes(data.log_size_bytes)}</code></div>
          <div className="kv"><span>Environment</span>
            <Badge tone={data.environment === 'production' ? 'success' : 'warning'}>
              {data.environment}
            </Badge>
          </div>
          <div className="kv"><span>Database</span>
            <Badge tone={data.database === 'sqlite' ? 'warning' : 'success'}>
              {data.database}
            </Badge>
          </div>
        </Card>
      </>)}
    </>
  );
}
EOF

cat > "$ROOT/frontend/src/pages/admin/UsersTab.tsx" <<'EOF'
import { FormEvent, useEffect, useState } from 'react';
import { KeyRound, Plus, ShieldCheck, Trash2, UserCog } from 'lucide-react';
import Badge from '../../components/ui/Badge';
import Button from '../../components/ui/Button';
import Card from '../../components/ui/Card';
import { Input, Select } from '../../components/ui/Input';
import Table, { type Column } from '../../components/ui/Table';
import { useAuth } from '../../context/AuthContext';
import { api, apiErrorMessage } from '../../lib/api';
import { formatDate } from '../../lib/format';

type Role = 'admin' | 'counter';
interface AdminUser {
  id: number; email: string; full_name: string; role: Role; is_active: boolean;
  last_login_at: string | null; created_at: string | null;
}
const emptyCreate = { email: '', full_name: '', password: '', role: 'counter' as Role };

export default function UsersTab() {
  const { user: me } = useAuth();
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [showCreate, setShowCreate] = useState(false);
  const [creating, setCreating] = useState(false);
  const [form, setForm] = useState({ ...emptyCreate });
  const [editing, setEditing] = useState<AdminUser | null>(null);
  const [resetting, setResetting] = useState<AdminUser | null>(null);
  const [newPassword, setNewPassword] = useState('');

  const load = async () => {
    try { const { data } = await api.get<AdminUser[]>('/admin/users'); setUsers(data); }
    catch (err) { setError(apiErrorMessage(err)); }
  };
  useEffect(() => { load(); }, []);

  const set = (k: keyof typeof form, v: string) => setForm((f) => ({ ...f, [k]: v }));
  const onCreate = async (e: FormEvent) => {
    e.preventDefault(); setError(null); setCreating(true);
    try { await api.post('/admin/users', form); setForm({ ...emptyCreate }); setShowCreate(false); await load(); }
    catch (err) { setError(apiErrorMessage(err)); }
    finally { setCreating(false); }
  };
  const onSaveEdit = async (e: FormEvent) => {
    e.preventDefault(); if (!editing) return;
    try {
      await api.put(`/admin/users/${editing.id}`, {
        full_name: editing.full_name, role: editing.role, is_active: editing.is_active,
      });
      setEditing(null); await load();
    } catch (err) { setError(apiErrorMessage(err)); }
  };
  const onResetPassword = async (e: FormEvent) => {
    e.preventDefault(); if (!resetting) return;
    try {
      await api.post(`/admin/users/${resetting.id}/reset-password`, { new_password: newPassword });
      setResetting(null); setNewPassword(''); await load();
    } catch (err) { setError(apiErrorMessage(err)); }
  };
  const onDelete = async (u: AdminUser) => {
    if (!confirm(`Delete user ${u.email}? This cannot be undone.`)) return;
    try { await api.delete(`/admin/users/${u.id}`); await load(); }
    catch (err) { setError(apiErrorMessage(err)); }
  };
  const columns: Column<AdminUser>[] = [
    { key: 'name', header: 'Name',
      render: (u) => (
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <strong>{u.full_name}</strong>
          {u.id === me?.id && <Badge tone="info">You</Badge>}
        </div>
      ) },
    { key: 'email', header: 'Email', render: (u) => u.email },
    { key: 'role', header: 'Role',
      render: (u) => u.role === 'admin'
        ? <Badge tone="info"><ShieldCheck size={12} /> Admin</Badge>
        : <Badge>Counter</Badge> },
    { key: 'status', header: 'Status',
      render: (u) => u.is_active ? <Badge tone="success">Active</Badge> : <Badge tone="danger">Disabled</Badge> },
    { key: 'last', header: 'Last Login',
      render: (u) => u.last_login_at ? formatDate(u.last_login_at) : '—' },
    { key: 'created', header: 'Created',
      render: (u) => u.created_at ? formatDate(u.created_at) : '—' },
    { key: 'actions', header: '', align: 'right',
      render: (u) => (
        <div style={{ display: 'flex', gap: 4, justifyContent: 'flex-end' }}>
          <button className="icon-btn" title="Edit user" onClick={() => setEditing({ ...u })}>
            <UserCog size={15} />
          </button>
          <button className="icon-btn" title="Reset password"
            onClick={() => { setResetting(u); setNewPassword(''); }}>
            <KeyRound size={15} />
          </button>
          <button className="icon-btn" title="Delete user"
            onClick={() => onDelete(u)} disabled={u.id === me?.id}>
            <Trash2 size={15} />
          </button>
        </div>
      ) },
  ];
  return (
    <>
      <div className="page-actions" style={{ justifyContent: 'flex-end', marginBottom: 16 }}>
        <Button variant={showCreate ? 'secondary' : 'primary'} icon={<Plus size={15} />}
          onClick={() => setShowCreate((s) => !s)}>
          {showCreate ? 'Cancel' : 'New User'}
        </Button>
      </div>
      {error && <div className="login-error" style={{ marginBottom: 16 }}>{error}</div>}
      {showCreate && (
        <Card title="Create User" padded>
          <form onSubmit={onCreate}>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: 14 }}>
              <Input label="Full Name" value={form.full_name} onChange={(e) => set('full_name', e.target.value)} required />
              <Input label="Email" type="email" value={form.email} onChange={(e) => set('email', e.target.value)} required />
              <Input label="Password" type="password" value={form.password}
                onChange={(e) => set('password', e.target.value)} required hint="Minimum 8 characters" />
              <Select label="Role" value={form.role}
                onChange={(e) => set('role', e.target.value as Role)}>
                <option value="counter">Counter</option>
                <option value="admin">Administrator</option>
              </Select>
            </div>
            <div style={{ marginTop: 18, display: 'flex', gap: 10, justifyContent: 'flex-end' }}>
              <Button variant="secondary" type="button" onClick={() => setShowCreate(false)}>Cancel</Button>
              <Button type="submit" loading={creating}>Create User</Button>
            </div>
          </form>
        </Card>
      )}
      {editing && (
        <Card title={`Edit User: ${editing.email}`} padded>
          <form onSubmit={onSaveEdit}>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: 14 }}>
              <Input label="Full Name" value={editing.full_name}
                onChange={(e) => setEditing({ ...editing, full_name: e.target.value })} />
              <Select label="Role" value={editing.role}
                onChange={(e) => setEditing({ ...editing, role: e.target.value as Role })}>
                <option value="counter">Counter</option>
                <option value="admin">Administrator</option>
              </Select>
              <Select label="Status" value={editing.is_active ? 'active' : 'disabled'}
                onChange={(e) => setEditing({ ...editing, is_active: e.target.value === 'active' })}>
                <option value="active">Active</option>
                <option value="disabled">Disabled</option>
              </Select>
            </div>
            <div style={{ marginTop: 18, display: 'flex', gap: 10, justifyContent: 'flex-end' }}>
              <Button variant="secondary" type="button" onClick={() => setEditing(null)}>Cancel</Button>
              <Button type="submit">Save Changes</Button>
            </div>
          </form>
        </Card>
      )}
      {resetting && (
        <Card title={`Reset Password: ${resetting.email}`} padded>
          <form onSubmit={onResetPassword}>
            <Input label="New Password" type="password" value={newPassword}
              onChange={(e) => setNewPassword(e.target.value)} required hint="Minimum 8 characters" />
            <div style={{ marginTop: 18, display: 'flex', gap: 10, justifyContent: 'flex-end' }}>
              <Button variant="secondary" type="button" onClick={() => setResetting(null)}>Cancel</Button>
              <Button type="submit">Reset Password</Button>
            </div>
          </form>
        </Card>
      )}
      <div style={{ marginTop: showCreate || editing || resetting ? 20 : 0 }}>
        <Card title="Users"
          subtitle={`${users.length} users · ${users.filter((u) => u.is_active).length} active`}
          padded={false}>
          <Table columns={columns} rows={users} empty="No users found." />
        </Card>
      </div>
    </>
  );
}
EOF

cat > "$ROOT/frontend/src/pages/admin/AppLogsTab.tsx" <<'EOF'
import { Filter } from 'lucide-react';
import { useEffect, useState } from 'react';
import Badge from '../../components/ui/Badge';
import Button from '../../components/ui/Button';
import Card from '../../components/ui/Card';
import Table, { type Column } from '../../components/ui/Table';
import { api, apiErrorMessage } from '../../lib/api';

interface AuditEntry {
  id: number; user_email: string | null; action: string; entity: string;
  entity_id: string | null; details: string | null;
  ip_address: string | null; created_at: string;
}
const TONE: Record<string, 'success' | 'danger' | 'warning' | 'info' | 'neutral'> = {
  login: 'success', login_failed: 'danger', logout: 'neutral',
  create: 'success', update: 'info', delete: 'danger', reset_password: 'warning',
};

export default function AppLogsTab() {
  const [rows, setRows] = useState<AuditEntry[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [action, setAction] = useState('');
  const [entity, setEntity] = useState('');
  const [userEmail, setUserEmail] = useState('');
  const load = async () => {
    setLoading(true); setError(null);
    try {
      const params: Record<string, string> = {};
      if (action) params.action = action;
      if (entity) params.entity = entity;
      if (userEmail) params.user_email = userEmail;
      const { data } = await api.get<AuditEntry[]>('/admin/logs/app', { params });
      setRows(data);
    } catch (err) { setError(apiErrorMessage(err)); }
    finally { setLoading(false); }
  };
  useEffect(() => { load(); /* eslint-disable-next-line */ }, []);
  const columns: Column<AuditEntry>[] = [
    { key: 'ts', header: 'Timestamp',
      render: (r) => <span className="mono" style={{ fontSize: 12 }}>{new Date(r.created_at).toLocaleString('en-IN')}</span> },
    { key: 'user', header: 'User', render: (r) => r.user_email ?? '—' },
    { key: 'action', header: 'Action',
      render: (r) => <Badge tone={TONE[r.action] ?? 'neutral'}>{r.action}</Badge> },
    { key: 'entity', header: 'Entity', render: (r) => r.entity },
    { key: 'id', header: 'Entity ID',
      render: (r) => r.entity_id ? <span className="mono">{r.entity_id}</span> : '—' },
    { key: 'details', header: 'Details', render: (r) => r.details ?? '—' },
    { key: 'ip', header: 'IP',
      render: (r) => <span className="mono" style={{ fontSize: 12 }}>{r.ip_address ?? '—'}</span> },
  ];
  return (
    <>
      <Card title="Filters" padded>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 12 }}>
          <label className="field">
            <span className="field-label">Action</span>
            <input className="input" placeholder="login, create, delete…"
              value={action} onChange={(e) => setAction(e.target.value)} />
          </label>
          <label className="field">
            <span className="field-label">Entity</span>
            <input className="input" placeholder="sale, user, purchase…"
              value={entity} onChange={(e) => setEntity(e.target.value)} />
          </label>
          <label className="field">
            <span className="field-label">User Email</span>
            <input className="input" placeholder="partial match"
              value={userEmail} onChange={(e) => setUserEmail(e.target.value)} />
          </label>
          <div style={{ display: 'flex', alignItems: 'flex-end', gap: 8 }}>
            <Button onClick={load} loading={loading} icon={<Filter size={15} />}>Apply</Button>
            <Button variant="secondary"
              onClick={() => { setAction(''); setEntity(''); setUserEmail(''); }}>Clear</Button>
          </div>
        </div>
      </Card>
      {error && <div className="login-error" style={{ margin: '16px 0' }}>{error}</div>}
      <div style={{ marginTop: 20 }}>
        <Card title="Application Audit Log" subtitle={`${rows.length} entries shown`} padded={false}>
          <Table columns={columns} rows={rows} empty="No log entries match." />
        </Card>
      </div>
    </>
  );
}
EOF

cat > "$ROOT/frontend/src/pages/admin/ServerLogsTab.tsx" <<'EOF'
import { Download, RefreshCw, Search } from 'lucide-react';
import { useEffect, useState } from 'react';
import Badge from '../../components/ui/Badge';
import Button from '../../components/ui/Button';
import Card from '../../components/ui/Card';
import { api, apiErrorMessage } from '../../lib/api';

interface LogEntry { timestamp: string; level: string; logger: string; message: string }
interface LogResponse {
  entries: LogEntry[]; total_matched: number;
  file_size_bytes: number; lines_scanned: number;
}
const TONE: Record<string, 'success' | 'danger' | 'warning' | 'info' | 'neutral'> = {
  DEBUG: 'neutral', INFO: 'info', WARNING: 'warning', ERROR: 'danger', CRITICAL: 'danger',
};

export default function ServerLogsTab() {
  const [data, setData] = useState<LogResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [level, setLevel] = useState('');
  const [search, setSearch] = useState('');
  const [autoRefresh, setAutoRefresh] = useState(true);
  const load = async () => {
    setLoading(true); setError(null);
    try {
      const params: Record<string, string | number> = { limit: 500 };
      if (level) params.level = level;
      if (search) params.search = search;
      const { data } = await api.get<LogResponse>('/admin/logs/server', { params });
      setData(data);
    } catch (err) { setError(apiErrorMessage(err)); }
    finally { setLoading(false); }
  };
  useEffect(() => { load(); /* eslint-disable-next-line */ }, [level]);
  useEffect(() => {
    if (!autoRefresh) return;
    const t = setInterval(load, 10000);
    return () => clearInterval(t);
    /* eslint-disable-next-line */
  }, [autoRefresh, level, search]);
  const download = async () => {
    const res = await api.get('/admin/logs/server/download', { responseType: 'blob' });
    const url = URL.createObjectURL(res.data);
    const a = document.createElement('a');
    a.href = url;
    a.download = `food-court-api-${new Date().toISOString().slice(0, 10)}.log`;
    a.click();
    URL.revokeObjectURL(url);
  };
  return (
    <>
      <Card title="Filters" padded>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 12 }}>
          <label className="field">
            <span className="field-label">Level</span>
            <select className="input" value={level} onChange={(e) => setLevel(e.target.value)}>
              <option value="">All levels</option>
              <option value="DEBUG">DEBUG</option>
              <option value="INFO">INFO</option>
              <option value="WARNING">WARNING</option>
              <option value="ERROR">ERROR</option>
              <option value="CRITICAL">CRITICAL</option>
            </select>
          </label>
          <label className="field">
            <span className="field-label">Search</span>
            <input className="input" placeholder="substring match…"
              value={search} onChange={(e) => setSearch(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && load()} />
          </label>
          <div style={{ display: 'flex', alignItems: 'flex-end', gap: 8 }}>
            <Button onClick={load} loading={loading} icon={<Search size={15} />}>Apply</Button>
            <Button variant="secondary" onClick={download} icon={<Download size={15} />}>Download</Button>
          </div>
          <div style={{ display: 'flex', alignItems: 'flex-end', gap: 12, justifyContent: 'flex-end' }}>
            <label className="checkbox-line">
              <input type="checkbox" checked={autoRefresh}
                onChange={(e) => setAutoRefresh(e.target.checked)} /> Auto-refresh
            </label>
            <button className="icon-btn" onClick={load} title="Refresh"><RefreshCw size={16} /></button>
          </div>
        </div>
      </Card>
      {error && <div className="login-error" style={{ margin: '16px 0' }}>{error}</div>}
      <div style={{ marginTop: 20 }}>
        <Card title="Server Log"
          subtitle={data
            ? `${data.total_matched} matched of ${data.lines_scanned} lines · ${(data.file_size_bytes / 1024).toFixed(1)} KB`
            : 'Loading…'}
          padded={false}>
          <div className="log-viewer">
            {!data || data.entries.length === 0 ? (
              <div className="table-empty">No log entries match the filter.</div>
            ) : (
              data.entries.map((entry, i) => (
                <div key={i} className={`log-line log-${entry.level.toLowerCase()}`}>
                  <span className="log-ts">{entry.timestamp}</span>
                  <Badge tone={TONE[entry.level] ?? 'neutral'}>{entry.level}</Badge>
                  <span className="log-logger">{entry.logger}</span>
                  <span className="log-msg">{entry.message}</span>
                </div>
              ))
            )}
          </div>
        </Card>
      </div>
    </>
  );
}
EOF

cat > "$ROOT/frontend/src/styles/globals.css" <<'EOF'
:root {
  --color-primary-50: #f0f4f8;
  --color-primary-100: #d9e3ee;
  --color-primary-500: #1e3a5f;
  --color-primary-600: #16304d;
  --color-primary-700: #0f2438;
  --color-success: #059669; --color-success-soft: #d1fae5;
  --color-danger: #dc2626;  --color-danger-soft: #fee2e2;
  --color-warning: #d97706; --color-warning-soft: #fef3c7;
  --color-info: #2563eb;    --color-info-soft: #dbeafe;
  --bg-page: #f7f9fc; --bg-surface: #ffffff; --bg-muted: #f1f5f9;
  --border: #e2e8f0; --border-strong: #cbd5e1;
  --text-strong: #0f172a; --text: #1f2937;
  --text-muted: #64748b; --text-subtle: #94a3b8;
  --radius-sm: 6px; --radius: 10px; --radius-lg: 14px;
  --shadow-sm: 0 1px 2px rgba(15,23,42,.04);
  --shadow: 0 4px 16px rgba(15,23,42,.06);
  --shadow-lg: 0 12px 40px rgba(15,23,42,.10);
  --font-sans: 'Inter', system-ui, -apple-system, 'Segoe UI', sans-serif;
  --font-mono: 'JetBrains Mono', ui-monospace, 'SFMono-Regular', monospace;
}
* { box-sizing: border-box; }
html, body, #root { height: 100%; }
body { margin: 0; font-family: var(--font-sans); font-size: 14px;
  color: var(--text); background: var(--bg-page); -webkit-font-smoothing: antialiased; }
.mono { font-family: var(--font-mono); font-feature-settings: "tnum"; }
button { font-family: inherit; cursor: pointer; }
a { color: inherit; text-decoration: none; }

.btn { display: inline-flex; align-items: center; gap: 8px;
  border: 1px solid transparent; border-radius: var(--radius-sm);
  font-weight: 500; transition: all .15s ease; white-space: nowrap; }
.btn-sm { padding: 6px 10px; font-size: 12.5px; }
.btn-md { padding: 9px 16px; font-size: 13.5px; }
.btn-primary { background: var(--color-primary-500); color: #fff; }
.btn-primary:hover:not(:disabled) { background: var(--color-primary-600); }
.btn-secondary { background: var(--bg-surface); color: var(--text-strong);
  border-color: var(--border-strong); }
.btn-secondary:hover:not(:disabled) { background: var(--bg-muted); }
.btn-ghost { background: transparent; color: var(--text-muted); }
.btn-ghost:hover:not(:disabled) { background: var(--bg-muted); color: var(--text); }
.btn-danger { background: var(--color-danger); color: #fff; }
.btn:disabled { opacity: .55; cursor: not-allowed; }
.icon-btn { display: inline-flex; align-items: center; justify-content: center;
  width: 34px; height: 34px; border-radius: var(--radius-sm);
  background: transparent; border: 1px solid transparent; color: var(--text-muted); }
.icon-btn:hover { background: var(--bg-muted); color: var(--text); }

.field { display: flex; flex-direction: column; gap: 6px; min-width: 0; }
.field-label { font-size: 12.5px; font-weight: 500; color: var(--text-muted); }
.field-hint { font-size: 11.5px; color: var(--text-subtle); }
.field-error { font-size: 11.5px; color: var(--color-danger); }
.input { width: 100%; padding: 9px 12px; font-size: 13.5px; font-family: inherit;
  color: var(--text-strong); background: var(--bg-surface);
  border: 1px solid var(--border-strong); border-radius: var(--radius-sm); }
.input:focus { outline: none; border-color: var(--color-primary-500);
  box-shadow: 0 0 0 3px rgba(30,58,95,.10); }

.app-shell { display: flex; min-height: 100vh; }
.sidebar { width: 250px; flex-shrink: 0; background: var(--bg-surface);
  border-right: 1px solid var(--border); display: flex; flex-direction: column; }
.sidebar-brand { display: flex; align-items: center; gap: 12px;
  padding: 18px 20px; border-bottom: 1px solid var(--border); }
.sidebar-brand img { width: 40px; height: 40px; object-fit: contain; border-radius: 8px; }
.sidebar-brand-text { display: flex; flex-direction: column; min-width: 0; }
.sidebar-brand-text strong { font-size: 14px; color: var(--text-strong); font-weight: 700; }
.sidebar-brand-text small { font-size: 11px; color: var(--text-muted); }
.sidebar-nav { flex: 1; padding: 12px; display: flex; flex-direction: column;
  gap: 2px; overflow-y: auto; }
.nav-link { display: flex; align-items: center; gap: 10px;
  padding: 9px 12px; border-radius: var(--radius-sm);
  font-size: 13.5px; font-weight: 500; color: var(--text-muted); }
.nav-link:hover { background: var(--bg-muted); color: var(--text-strong); }
.nav-link-active { background: var(--color-primary-50);
  color: var(--color-primary-500); font-weight: 600; }
.sidebar-foot { padding: 14px 20px; border-top: 1px solid var(--border); }
.sidebar-company-meta { display: flex; flex-direction: column; gap: 2px;
  font-size: 11px; color: var(--text-subtle); }
.app-main { flex: 1; display: flex; flex-direction: column; min-width: 0; }
.topbar { height: 60px; flex-shrink: 0; display: flex;
  align-items: center; justify-content: space-between; padding: 0 24px;
  background: var(--bg-surface); border-bottom: 1px solid var(--border); }
.topbar-right { display: flex; align-items: center; gap: 14px; }
.user-chip { display: flex; align-items: center; gap: 10px; color: var(--text-muted); }
.user-chip-text { display: flex; flex-direction: column; line-height: 1.15; }
.user-chip-text strong { font-size: 12.5px; color: var(--text-strong); }
.user-chip-text small { font-size: 11px; }
.app-content { flex: 1; padding: 24px; overflow-y: auto; }
.app-loader { display: flex; align-items: center; justify-content: center;
  height: 100vh; background: var(--bg-page); }

.page-header { display: flex; align-items: flex-start; justify-content: space-between;
  gap: 16px; margin-bottom: 20px; flex-wrap: wrap; }
.page-title { font-size: 22px; font-weight: 700; color: var(--text-strong);
  margin: 0 0 4px; letter-spacing: -0.01em; }
.page-subtitle { font-size: 13px; color: var(--text-muted); margin: 0; }
.page-actions { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; }
.grid-stats { display: grid;
  grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
  gap: 14px; margin-bottom: 20px; }
.grid-2 { display: grid; grid-template-columns: 1.4fr 1fr; gap: 16px; }
@media (max-width: 980px) { .grid-2 { grid-template-columns: 1fr; } }

.stat-tile { background: var(--bg-surface); border: 1px solid var(--border);
  border-radius: var(--radius); padding: 16px; display: flex;
  flex-direction: column; gap: 8px; box-shadow: var(--shadow-sm); }
.stat-head { display: flex; align-items: center; justify-content: space-between; }
.stat-label { font-size: 12px; font-weight: 500; color: var(--text-muted);
  text-transform: uppercase; letter-spacing: .04em; }
.stat-icon { color: var(--text-subtle); }
.stat-value { font-size: 22px; font-weight: 600; color: var(--text-strong); }
.stat-foot { display: flex; align-items: center; gap: 8px; }
.stat-hint { font-size: 11.5px; color: var(--text-subtle); }
.delta { font-size: 11.5px; font-weight: 500; }
.delta.up { color: var(--color-success); }
.delta.down { color: var(--color-danger); }
.stat-success .stat-value { color: var(--color-success); }
.stat-danger .stat-value { color: var(--color-danger); }
.stat-warning .stat-value { color: var(--color-warning); }

.card { background: var(--bg-surface); border: 1px solid var(--border);
  border-radius: var(--radius); box-shadow: var(--shadow-sm); overflow: hidden; }
.card-header { display: flex; align-items: flex-start; justify-content: space-between;
  gap: 12px; padding: 16px 18px; border-bottom: 1px solid var(--border); }
.card-title { font-size: 14.5px; font-weight: 600; color: var(--text-strong); margin: 0; }
.card-subtitle { font-size: 12px; color: var(--text-muted); margin: 3px 0 0; }
.card-actions { display: flex; gap: 8px; align-items: center; }
.card-body { padding: 18px; }

.table-wrap { overflow-x: auto; }
.data-table { width: 100%; border-collapse: collapse; font-size: 13px; }
.data-table thead th { text-align: left; font-weight: 500; color: var(--text-muted);
  font-size: 11.5px; text-transform: uppercase; letter-spacing: .04em;
  padding: 10px 14px; background: var(--bg-muted);
  border-bottom: 1px solid var(--border); }
.data-table tbody td { padding: 12px 14px;
  border-bottom: 1px solid var(--border); color: var(--text); }
.data-table tbody tr:last-child td { border-bottom: none; }
.data-table tbody tr:hover { background: var(--bg-muted); }
.table-empty { padding: 40px 20px; text-align: center;
  color: var(--text-subtle); font-size: 13px; }

.badge { display: inline-flex; align-items: center; padding: 2px 9px;
  border-radius: 999px; font-size: 11.5px; font-weight: 500; line-height: 1.6; }
.badge-neutral { background: var(--bg-muted); color: var(--text-muted); }
.badge-success { background: var(--color-success-soft); color: var(--color-success); }
.badge-danger { background: var(--color-danger-soft); color: var(--color-danger); }
.badge-warning { background: var(--color-warning-soft); color: var(--color-warning); }
.badge-info { background: var(--color-info-soft); color: var(--color-info); }

.spinner, .spinner-sm { display: inline-block;
  border: 2px solid rgba(30,58,95,.18); border-top-color: var(--color-primary-500);
  border-radius: 50%; animation: spin .7s linear infinite; }
.spinner { width: 32px; height: 32px; border-width: 3px; }
.spinner-sm { width: 13px; height: 13px; }
@keyframes spin { to { transform: rotate(360deg); } }

.login-screen { min-height: 100vh; display: grid;
  grid-template-columns: 1.05fr 1fr; background: var(--bg-page); }
@media (max-width: 900px) {
  .login-screen { grid-template-columns: 1fr; }
  .login-brand { display: none; }
}
.login-brand { background: linear-gradient(150deg, #1e3a5f 0%, #0f2438 100%);
  position: relative; overflow: hidden; display: flex;
  align-items: center; justify-content: center; }
.login-brand img { width: 100%; height: 100%; object-fit: cover; opacity: .92; }
.login-form-wrap { display: flex; align-items: center;
  justify-content: center; padding: 40px; }
.login-card { width: 100%; max-width: 400px; background: var(--bg-surface);
  border-radius: var(--radius-lg); padding: 36px 32px;
  box-shadow: var(--shadow-lg); }
.login-logo { width: 160px; height: 44px; object-fit: contain; margin-bottom: 24px; }
.login-title { font-size: 22px; font-weight: 700; color: var(--text-strong); margin: 0 0 4px; }
.login-subtitle { font-size: 13px; color: var(--text-muted); margin: 0 0 26px; }
.login-card form { display: flex; flex-direction: column; gap: 14px; }
.login-error { background: var(--color-danger-soft); color: var(--color-danger);
  padding: 9px 12px; border-radius: var(--radius-sm); font-size: 12.5px; }
.login-footnote { margin-top: 26px; font-size: 11.5px;
  color: var(--text-subtle); text-align: center; line-height: 1.6; }

.tabs { display: flex; gap: 4px; border-bottom: 1px solid var(--border);
  margin-bottom: 20px; overflow-x: auto; }
.tab { display: inline-flex; align-items: center; gap: 8px;
  padding: 10px 16px; background: transparent; border: none;
  border-bottom: 2px solid transparent; font-size: 13.5px;
  font-weight: 500; color: var(--text-muted); white-space: nowrap;
  margin-bottom: -1px; }
.tab:hover { color: var(--text-strong); }
.tab-active { color: var(--color-primary-500);
  border-bottom-color: var(--color-primary-500); font-weight: 600; }
.tab-panel { animation: fadeIn .18s ease; }
@keyframes fadeIn { from { opacity: 0; transform: translateY(3px); } to { opacity: 1; transform: none; } }

.nav-divider { padding: 14px 12px 4px; font-size: 10.5px;
  font-weight: 600; letter-spacing: .08em; color: var(--text-subtle);
  text-transform: uppercase; }

.status-banner { display: flex; gap: 14px; align-items: center; }
.status-banner strong { display: block; font-size: 14.5px; color: var(--text-strong); }
.status-banner p { font-size: 12.5px; color: var(--text-muted); margin: 3px 0 0; }
.status-banner code { font-family: var(--font-mono); font-size: 12px;
  background: var(--bg-muted); padding: 1px 6px; border-radius: 4px; }

.kv { display: flex; align-items: center; gap: 12px; padding: 8px 0;
  border-bottom: 1px solid var(--border); font-size: 13px; }
.kv:last-child { border-bottom: none; }
.kv > span:first-child { min-width: 120px; color: var(--text-muted);
  font-size: 12px; text-transform: uppercase; letter-spacing: .04em; }
.kv code { font-family: var(--font-mono); font-size: 12.5px;
  color: var(--text-strong); word-break: break-all; }

.log-viewer { max-height: 640px; overflow-y: auto;
  font-family: var(--font-mono); font-size: 12px;
  background: #0b1220; border-radius: 0 0 var(--radius) var(--radius); }
.log-line { display: grid;
  grid-template-columns: 150px 72px 140px 1fr; gap: 10px;
  padding: 8px 14px; border-bottom: 1px solid #1a2333;
  align-items: start; color: #cbd5e1; }
.log-line:last-child { border-bottom: none; }
.log-line:hover { background: rgba(255,255,255,.03); }
.log-ts { color: #94a3b8; }
.log-logger { color: #7dd3fc; }
.log-msg { white-space: pre-wrap; word-break: break-word; color: #e2e8f0; }
.log-error .log-msg, .log-critical .log-msg { color: #fca5a5; }
.log-warning .log-msg { color: #fcd34d; }

.checkbox-line { display: inline-flex; align-items: center; gap: 6px;
  font-size: 12.5px; color: var(--text-muted); cursor: pointer; }
EOF

# =============================================================================
# DEPLOY FILES
# =============================================================================

cat > "$ROOT/deploy/systemd/food-court-api.service" <<'EOF'
[Unit]
Description=Food Court Counter FastAPI Backend
After=network.target postgresql.service

[Service]
User=www-data
Group=www-data
WorkingDirectory=/var/www/food-court-counter/backend
Environment="PATH=/var/www/food-court-counter/backend/.venv/bin"
Environment="LOG_DIR=/var/log/food-court-counter"
ExecStart=/var/www/food-court-counter/backend/.venv/bin/gunicorn \
    --workers 4 \
    --worker-class uvicorn.workers.UvicornWorker \
    --bind 127.0.0.1:8000 \
    --timeout 120 \
    --access-logfile - \
    --error-logfile - \
    app.main:app
Restart=always
RestartSec=5

LogsDirectory=food-court-counter
LogsDirectoryMode=0750

[Install]
WantedBy=multi-user.target
EOF

cat > "$ROOT/deploy/apache/food-court-counter.conf" <<'EOF'
<VirtualHost *:80>
    ServerName counter.example.com
    Redirect permanent / https://counter.example.com/
</VirtualHost>

<VirtualHost *:443>
    ServerName counter.example.com
    ServerAdmin admin@example.com
    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/counter.example.com/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/counter.example.com/privkey.pem

    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"
    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"

    DocumentRoot /var/www/food-court-counter/frontend/dist
    <Directory /var/www/food-court-counter/frontend/dist>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
        RewriteEngine On
        RewriteBase /
        RewriteRule ^index\.html$ - [L]
        RewriteCond %{REQUEST_FILENAME} !-f
        RewriteCond %{REQUEST_FILENAME} !-d
        RewriteRule . /index.html [L]
    </Directory>

    ProxyPreserveHost On
    ProxyPass /api/ http://127.0.0.1:8000/api/ retry=0
    ProxyPassReverse /api/ http://127.0.0.1:8000/api/
    <Location /api/>
        ProxySet connectiontimeout=30 timeout=120
    </Location>

    ErrorLog ${APACHE_LOG_DIR}/food-court-error.log
    CustomLog ${APACHE_LOG_DIR}/food-court-access.log combined
</VirtualHost>
EOF

cat > "$ROOT/deploy/scripts/backup.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
BACKUP_DIR="${BACKUP_DIR:-/var/backups/food-court-counter}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
DB_NAME="${POSTGRES_DB:-food_court_db}"
mkdir -p "$BACKUP_DIR"
STAMP="$(date +%F_%H%M)"
OUT="$BACKUP_DIR/db-${STAMP}.sql"
sudo -u postgres pg_dump "$DB_NAME" > "$OUT"
gzip "$OUT"
find "$BACKUP_DIR" -name 'db-*.sql.gz' -mtime "+${RETENTION_DAYS}" -delete
echo "Backup written: ${OUT}.gz"
EOF
chmod +x "$ROOT/deploy/scripts/backup.sh"

cat > "$ROOT/deploy/scripts/setup-local.sh" <<'EOF'
#!/usr/bin/env bash
# =============================================================
# Food Court Counter — Local Development Setup
#
# Default: SQLite (zero-config). Optional: local PostgreSQL.
# =============================================================
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_ROOT"

say()  { printf '\033[1;34m▸\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Required tool not found: $1"; }

gen_secret() {
  if command -v openssl >/dev/null 2>&1; then openssl rand -hex 32
  else python3 -c 'import secrets; print(secrets.token_hex(32))'; fi
}

sed_inplace() {
  if sed --version >/dev/null 2>&1; then sed -i "$@"; else sed -i '' "$@"; fi
}

say "Checking prerequisites"
need python3; need node; need npm
ok "python3: $(python3 --version 2>&1)"
ok "node:    $(node --version)"
ok "npm:     $(npm  --version)"

if [[ "${SKIP_BACKEND:-0}" != "1" ]]; then
  say "Setting up backend"
  pushd backend >/dev/null
  [[ -d .venv ]] || { python3 -m venv .venv; ok "Created backend/.venv"; }
  # shellcheck disable=SC1091
  source .venv/bin/activate
  pip install --upgrade pip >/dev/null
  pip install -r requirements.txt
  ok "Installed Python dependencies"
  if [[ ! -f .env ]]; then
    cp .env.example .env
    sed_inplace "s|^SECRET_KEY=.*|SECRET_KEY=$(gen_secret)|" .env
    ok "Created backend/.env with a fresh SECRET_KEY"
  else
    ok "backend/.env already exists — leaving untouched"
  fi
  deactivate
  popd >/dev/null
fi

if [[ "${SKIP_FRONTEND:-0}" != "1" ]]; then
  say "Setting up frontend"
  pushd frontend >/dev/null
  npm install
  ok "Installed frontend dependencies"
  [[ -f .env.local ]] || { cp .env.example .env.local; ok "Created frontend/.env.local"; }
  popd >/dev/null
fi

if [[ "${SKIP_DB:-0}" != "1" ]]; then
  echo
  echo "Database choice:"
  echo "  [1] SQLite     — zero-config, recommended for development (default)"
  echo "  [2] PostgreSQL — requires a running local PostgreSQL server"
  read -r -p "Choose [1/2]: " db_choice
  case "${db_choice:-1}" in
    2)
      if ! command -v psql >/dev/null 2>&1; then
        warn "psql not found — staying on SQLite."
      else
        DB_NAME="${POSTGRES_DB:-food_court_db}"
        DB_USER="${POSTGRES_USER:-fc_user}"
        DB_PASS="${POSTGRES_PASSWORD:-$(gen_secret | cut -c1-24)}"
        if sudo -n true 2>/dev/null; then SUDO="sudo"; else SUDO=""; fi
        $SUDO -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1 \
          || $SUDO -u postgres createdb "${DB_NAME}"
        $SUDO -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" | grep -q 1 \
          && $SUDO -u postgres psql -c "ALTER USER ${DB_USER} WITH PASSWORD '${DB_PASS}';" \
          || $SUDO -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';"
        $SUDO -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};"
        $SUDO -u postgres psql -c "ALTER DATABASE ${DB_NAME} OWNER TO ${DB_USER};"
        sed_inplace \
          "s|^DATABASE_URL=.*|DATABASE_URL=postgresql+asyncpg://${DB_USER}:${DB_PASS}@localhost:5432/${DB_NAME}|" \
          backend/.env
        ok "PostgreSQL configured — credentials written to backend/.env"
      fi
      ;;
    *)
      sed_inplace "s|^ENVIRONMENT=.*|ENVIRONMENT=development|" backend/.env
      ok "Using SQLite — data will live in backend/food_court_dev.db"
      ;;
  esac
fi

echo
ok "Local setup complete."
cat <<'EOM'

Next steps — open two terminals:

  ── Terminal 1: backend ─────────────────────────────────────
    cd backend
    source .venv/bin/activate
    uvicorn app.main:app --reload --port 8000

  ── Terminal 2: frontend ────────────────────────────────────
    cd frontend
    npm run dev

Open http://localhost:5173
Log in with:
  admin@example.com   / Admin@12345
  counter@example.com / Counter@12345

Change both passwords immediately via Admin Console → Users.
EOM
EOF
chmod +x "$ROOT/deploy/scripts/setup-local.sh"

cat > "$ROOT/deploy/scripts/deploy-ubuntu.sh" <<'EOF'
#!/usr/bin/env bash
# =============================================================
# Food Court Counter — Ubuntu Production Deployment
#
#   export DOMAIN=counter.example.com
#   export LETSENCRYPT_EMAIL=admin@example.com     # optional
#   sudo -v && ./deploy/scripts/deploy-ubuntu.sh
# =============================================================
set -euo pipefail

say()  { printf '\033[1;34m▸\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] && die "Do NOT run as root. Use a sudo-capable user."

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_ROOT"

[[ -f /etc/os-release ]] || die "Not Ubuntu."
# shellcheck disable=SC1091
. /etc/os-release
case "${ID:-}" in
  ubuntu) ok "Detected Ubuntu ${VERSION_ID}" ;;
  debian) warn "Detected Debian ${VERSION_ID} — proceeding" ;;
  *)      die "Unsupported distro: ${ID:-unknown}" ;;
esac

: "${DOMAIN:?Set DOMAIN=<your.domain> first (export DOMAIN=counter.example.com)}"
APP_DIR="${APP_DIR:-/var/www/food-court-counter}"
DB_NAME="${DB_NAME:-food_court_db}"
DB_USER="${DB_USER:-fc_user}"
DB_PASS="${DB_PASS:-$(openssl rand -hex 16)}"
LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-admin@${DOMAIN}}"
SERVICE_NAME="food-court-api"
LOG_DIR="/var/log/food-court-counter"

say "[1/9] Installing system packages"
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  apache2 postgresql postgresql-contrib \
  python3 python3-venv python3-pip \
  nodejs npm git curl rsync openssl \
  certbot python3-certbot-apache
ok "System packages installed"

say "[2/9] Enabling Apache modules"
sudo a2enmod proxy proxy_http rewrite headers ssl deflate expires >/dev/null
sudo systemctl restart apache2
ok "Apache modules enabled"

say "[3/9] Syncing project to $APP_DIR"
sudo mkdir -p "$APP_DIR"
sudo chown -R "$USER":"$USER" "$APP_DIR"
rsync -a --delete \
  --exclude '.git' --exclude 'node_modules' --exclude '.venv' \
  --exclude 'frontend/dist' --exclude 'backend/logs' \
  --exclude 'backend/food_court_dev.db' \
  "$PROJECT_ROOT"/ "$APP_DIR"/
ok "Project synced"

say "[4/9] Setting up PostgreSQL"
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" \
  | grep -q 1 || sudo -u postgres createdb "${DB_NAME}"
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" \
  | grep -q 1 \
    && sudo -u postgres psql -c "ALTER USER ${DB_USER} WITH PASSWORD '${DB_PASS}';" \
    || sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};"
sudo -u postgres psql -c "ALTER DATABASE ${DB_NAME} OWNER TO ${DB_USER};"
ok "Database ready"

say "[5/9] Writing backend/.env"
cd "$APP_DIR/backend"
SECRET="$(openssl rand -hex 32)"
cat > .env <<ENVEOF
APP_NAME="Food Court Counter API"
ENVIRONMENT=production
DEBUG=False
HOST=127.0.0.1
PORT=8000
DATABASE_URL=postgresql+asyncpg://${DB_USER}:${DB_PASS}@localhost:5432/${DB_NAME}
SECRET_KEY=${SECRET}
ACCESS_TOKEN_EXPIRE_MINUTES=720
BACKEND_CORS_ORIGINS=https://${DOMAIN}
DEFAULT_ADMIN_EMAIL=admin@example.com
DEFAULT_ADMIN_PASSWORD=Admin@12345
DEFAULT_COUNTER_EMAIL=counter@example.com
DEFAULT_COUNTER_PASSWORD=Counter@12345
LOG_DIR=${LOG_DIR}
LOG_LEVEL=INFO
LOG_MAX_BYTES=10485760
LOG_BACKUP_COUNT=5
ENVEOF
chmod 640 .env
ok "backend/.env written"

say "[6/9] Installing backend dependencies"
python3 -m venv .venv
# shellcheck disable=SC1091
source .venv/bin/activate
pip install --upgrade pip >/dev/null
pip install -r requirements.txt
pip install gunicorn 'uvicorn[standard]'
deactivate
ok "Backend virtualenv ready"

say "[7/9] Installing systemd service"
sudo tee /etc/systemd/system/${SERVICE_NAME}.service >/dev/null <<SVCEOF
[Unit]
Description=Food Court Counter FastAPI Backend
After=network.target postgresql.service

[Service]
User=www-data
Group=www-data
WorkingDirectory=${APP_DIR}/backend
Environment="PATH=${APP_DIR}/backend/.venv/bin"
Environment="LOG_DIR=${LOG_DIR}"
ExecStart=${APP_DIR}/backend/.venv/bin/gunicorn \\
    --workers 4 \\
    --worker-class uvicorn.workers.UvicornWorker \\
    --bind 127.0.0.1:8000 \\
    --timeout 120 \\
    --access-logfile - \\
    --error-logfile - \\
    app.main:app
Restart=always
RestartSec=5

LogsDirectory=food-court-counter
LogsDirectoryMode=0750

[Install]
WantedBy=multi-user.target
SVCEOF
sudo systemctl daemon-reload
sudo systemctl enable --now ${SERVICE_NAME}
sleep 2
sudo systemctl is-active --quiet ${SERVICE_NAME} \
  || { sudo journalctl -u ${SERVICE_NAME} -n 40; die "Backend failed to start"; }
ok "Backend service running"

say "[8/9] Building frontend"
cd "$APP_DIR/frontend"
cat > .env.production <<ENVEOF
VITE_COMPANY_NAME="${COMPANY_NAME:-Food Court Counter}"
VITE_COMPANY_ID="default"
VITE_TITLE_MODIFIER="Operations Console"
VITE_LOGO_URL="/assets/logo-placeholder.svg"
VITE_BRAND_IMAGE_URL="/assets/login-placeholder.svg"
VITE_FAVICON_URL="/favicon.svg"
VITE_PRIMARY_COLOR="#1e3a5f"
VITE_ACCENT_COLOR="#059669"
VITE_GSTIN=""
VITE_PAN=""
VITE_ADDRESS=""
VITE_CONTACT_EMAIL=""
VITE_CONTACT_PHONE=""
ENVEOF
npm ci --no-audit --no-fund
npm run build
ok "Frontend built"

say "[9/9] Configuring Apache"
VHOST=/etc/apache2/sites-available/food-court-counter.conf
sudo tee "$VHOST" >/dev/null <<APEOF
<VirtualHost *:80>
    ServerName ${DOMAIN}
    ServerAdmin ${LETSENCRYPT_EMAIL}
    DocumentRoot ${APP_DIR}/frontend/dist
    <Directory ${APP_DIR}/frontend/dist>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
        RewriteEngine On
        RewriteBase /
        RewriteRule ^index\\.html\$ - [L]
        RewriteCond %{REQUEST_FILENAME} !-f
        RewriteCond %{REQUEST_FILENAME} !-d
        RewriteRule . /index.html [L]
    </Directory>
    ProxyPreserveHost On
    ProxyPass /api/ http://127.0.0.1:8000/api/ retry=0
    ProxyPassReverse /api/ http://127.0.0.1:8000/api/
    <Location /api/>
        ProxySet connectiontimeout=30 timeout=120
    </Location>
    ErrorLog \${APACHE_LOG_DIR}/food-court-error.log
    CustomLog \${APACHE_LOG_DIR}/food-court-access.log combined
</VirtualHost>
APEOF
sudo a2ensite food-court-counter >/dev/null
sudo a2dissite 000-default >/dev/null 2>&1 || true
sudo apachectl configtest
sudo systemctl reload apache2
ok "Apache vhost enabled"

sudo chown -R www-data:www-data "$APP_DIR"
sudo chmod -R 755 "$APP_DIR"
sudo chmod 640 "$APP_DIR/backend/.env"
ok "Permissions adjusted"

if [[ "${SKIP_SSL:-0}" == "1" ]]; then
  warn "SKIP_SSL=1 — skipping Let's Encrypt. App is on http://${DOMAIN}"
else
  say "Requesting Let's Encrypt certificate for ${DOMAIN}"
  sudo certbot --apache --non-interactive --agree-tos \
    -m "${LETSENCRYPT_EMAIL}" -d "${DOMAIN}" --redirect \
    || warn "Certbot failed — retry: sudo certbot --apache -d ${DOMAIN}"
  ok "HTTPS configured (if certbot succeeded)"
fi

echo
ok "Deployment complete."
cat <<SUMMARY

────────────────────────────────────────────────────────────────
  Application URL:  https://${DOMAIN}/
  API base:         https://${DOMAIN}/api/
  Backend service:  systemctl status ${SERVICE_NAME}
  Backend logs:     ${LOG_DIR}/api.log
  Apache logs:      /var/log/apache2/food-court-{error,access}.log
  Database:         ${DB_NAME}  (owner: ${DB_USER})
  DB password:      ${DB_PASS}   ← save this now!

  First login:
    admin@example.com   / Admin@12345
    counter@example.com / Counter@12345
    Change both immediately via Admin Console → Users.
────────────────────────────────────────────────────────────────
SUMMARY
EOF
chmod +x "$ROOT/deploy/scripts/deploy-ubuntu.sh"

# =============================================================================
# DONE
# =============================================================================

say "Tree:"
if command -v tree >/dev/null 2>&1; then
  tree -I 'node_modules|.venv|dist|__pycache__|*.db' "$ROOT"
else
  find "$ROOT" -type f | sort
fi

echo
ok "Project regenerated at ./$ROOT"
echo
echo "════════════════════════════════════════════════════════════"
echo "  Next: Local development setup"
echo "════════════════════════════════════════════════════════════"
echo "    cd $ROOT"
echo "    ./deploy/scripts/setup-local.sh"
echo
echo "  Then start two terminals:"
echo "    # Terminal 1 (backend)"
echo "    cd $ROOT/backend && source .venv/bin/activate"
echo "    uvicorn app.main:app --reload --port 8000"
echo
echo "    # Terminal 2 (frontend)"
echo "    cd $ROOT/frontend && npm run dev"
echo
echo "  Log in at http://localhost:5173"
echo "    admin@example.com   / Admin@12345"
echo "    counter@example.com / Counter@12345"
echo
echo "════════════════════════════════════════════════════════════"
echo "  Ubuntu server deployment"
echo "════════════════════════════════════════════════════════════"
echo "    export DOMAIN=counter.example.com"
echo "    export LETSENCRYPT_EMAIL=admin@example.com"
echo "    sudo -v && ./deploy/scripts/deploy-ubuntu.sh"
echo
echo "════════════════════════════════════════════════════════════"
echo "  Rebuild anytime (wipes and regenerates everything)"
echo "════════════════════════════════════════════════════════════"
echo "    FORCE=1 ./bootstrap.sh"
echo "════════════════════════════════════════════════════════════"