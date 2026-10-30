import logging
import time
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
    admin,
    advances,
    attendance,
    audit,
    auth,
    documents,
    employees,
    expenses,
    purchases,
    reports,
    salary,
    sales,
    settings as settings_router,
)

configure_logging()
logger = logging.getLogger("as-enterprises")

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
            exists = (await db.execute(
                select(User).where(User.email == email)
            )).scalar_one_or_none()
            if not exists:
                db.add(User(
                    email=email,
                    full_name=name,
                    hashed_password=hash_password(password),
                    role=role,
                ))
                logger.warning(
                    "Seeded default %s user: %s — CHANGE THE PASSWORD.",
                    role.value, email,
                )
        await db.commit()


@asynccontextmanager
async def lifespan(app: FastAPI):
    if settings.is_sqlite:
        logger.warning("Running on SQLite fallback (%s).",
                       settings.resolved_database_url)
    else:
        logger.info("Database: %s",
                    settings.resolved_database_url.split("@")[-1])

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    await seed_users()
    logger.info("Startup complete. Log file: %s", get_log_path())
    yield
    logger.info("Shutdown complete.")


app = FastAPI(title="AS Enterprises API", version="1.0.1", lifespan=lifespan)
app.add_middleware(RequestLoggingMiddleware)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

for router_module in (
    auth,
    sales,
    purchases,
    expenses,
    employees,
    attendance,
    advances,
    salary,
    reports,
    settings_router,
    audit,
    admin,
    documents,
):
    app.include_router(router_module.router, prefix="/api")


@app.get("/api/health")
async def health() -> dict[str, str]:
    return {"status": "ok", "environment": settings.environment}