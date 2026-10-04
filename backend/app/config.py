from typing import Literal

from pydantic import Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=None,
        case_sensitive=False,
        extra="ignore",
    )

    jwt_secret_key: SecretStr = Field(min_length=32)
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = Field(default=30, gt=0, le=1440)
    database_url: str = "sqlite:///./finance.db"
    cors_origins: str = "http://localhost:3000,http://localhost:5173,http://localhost:8000"
    app_env: Literal["development", "production"] = "development"
    otp_provider: Literal["mock", "twilio"] = "twilio"

    twilio_account_sid: str | None = None
    twilio_api_key: str | None = None
    twilio_api_secret: SecretStr | None = None
    twilio_auth_token: SecretStr | None = None
    twilio_verify_service_sid: str | None = None

    @property
    def cors_origin_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]
