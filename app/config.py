from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # App
    environment: str = "development"
    debug: bool = False
    allowed_origins: list[str] = ["https://safescribe.mai.style", "https://staging.safescribe.mai.style", "https://staging.safescribe.pages.dev", "http://localhost:3000", "http://localhost:5173"]

    # Database
    database_url: str = "postgresql+asyncpg://postgres:postgres@localhost:5432/safescribe"

    # Redis
    redis_url: str = "redis://localhost:6379/0"

    # JWT
    jwt_secret_key: str = "change-me-in-production"
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 15
    refresh_token_expire_days: int = 30

    # Stripe
    stripe_secret_key: str = "sk_test_placeholder"
    stripe_webhook_secret: str = "whsec_placeholder"
    stripe_price_id: str = "price_placeholder"
    stripe_success_url: str = "https://safescribe.mai.style/upgrade/success"
    stripe_cancel_url: str = "https://safescribe.mai.style/upgrade/cancel"


@lru_cache
def get_settings() -> Settings:
    return Settings()
