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
