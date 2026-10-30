from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


PLACEHOLDER_MARKERS = ("ChangeThisStrongPassword", "replace-me", "changeme")


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_name: str = "AS Enterprises API"
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

    upload_root: str = "./uploads/documents"

    @property
    def cors_origins(self) -> list[str]:
        return [o.strip() for o in self.backend_cors_origins.split(",") if o.strip()]

    @property
    def upload_path(self) -> Path:
        p = Path(self.upload_root)
        p.mkdir(parents=True, exist_ok=True)
        return p

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