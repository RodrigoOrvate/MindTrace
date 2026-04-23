from pydantic import AliasChoices, Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "Animal Lifecycle API"
    app_env: str = "dev"
    database_url: str = "sqlite:///./animal_lifecycle.db"
    default_lab_name: str = "MemoryLab"
    default_country: str = "BR"
    sync_secret: str = Field(default="", validation_alias=AliasChoices("SYNC_SECRET", "MINDTRACE_SYNC_SECRET"))
    sync_max_skew_seconds: int = Field(default=120, validation_alias=AliasChoices("SYNC_MAX_SKEW_SECONDS", "MINDTRACE_SYNC_MAX_SKEW_SECONDS"))
    mindtrace_allowed_roots: str = Field(default="", validation_alias=AliasChoices("MINDTRACE_ALLOWED_ROOTS", "MINDTRACE_ALLOWED_ROOT"))
    mindtrace_allow_any_path: bool = Field(
        default=False,
        validation_alias=AliasChoices("MINDTRACE_ALLOW_ANY_PATH", "MINDTRACE_SYNC_ALLOW_ANY_PATH"),
    )
    auth_secret: str = Field(default="", validation_alias=AliasChoices("AUTH_SECRET", "ANIMAL_AUTH_SECRET"))
    auth_token_ttl_seconds: int = Field(default=43200, validation_alias=AliasChoices("AUTH_TOKEN_TTL_SECONDS", "ANIMAL_AUTH_TOKEN_TTL_SECONDS"))
    auth_max_failed_attempts: int = Field(default=5, validation_alias=AliasChoices("AUTH_MAX_FAILED_ATTEMPTS", "ANIMAL_AUTH_MAX_FAILED_ATTEMPTS"))
    auth_lock_minutes: int = Field(default=15, validation_alias=AliasChoices("AUTH_LOCK_MINUTES", "ANIMAL_AUTH_LOCK_MINUTES"))
    user_bootstrap_enabled: bool = Field(default=False, validation_alias=AliasChoices("USER_BOOTSTRAP_ENABLED", "ANIMAL_USER_BOOTSTRAP_ENABLED"))
    auth_allowed_cidrs: str = Field(
        default="127.0.0.1/32;::1/128",
        validation_alias=AliasChoices("AUTH_ALLOWED_CIDRS", "ANIMAL_AUTH_ALLOWED_CIDRS"),
    )
    auth_login_allowed_cidrs: str = Field(
        default="127.0.0.1/32;::1/128",
        validation_alias=AliasChoices("AUTH_LOGIN_ALLOWED_CIDRS", "ANIMAL_AUTH_LOGIN_ALLOWED_CIDRS"),
    )
    auth_admin_allowed_cidrs: str = Field(
        default="127.0.0.1/32;::1/128",
        validation_alias=AliasChoices("AUTH_ADMIN_ALLOWED_CIDRS", "ANIMAL_AUTH_ADMIN_ALLOWED_CIDRS"),
    )
    auth_admin_allowed_macs: str = Field(
        default="",
        validation_alias=AliasChoices("AUTH_ADMIN_ALLOWED_MACS", "ANIMAL_AUTH_ADMIN_ALLOWED_MACS"),
    )
    cors_allowed_origins: str = Field(
        default="http://localhost:8081;http://localhost:19006;http://127.0.0.1:8081;http://127.0.0.1:19006",
        validation_alias=AliasChoices("CORS_ALLOWED_ORIGINS", "ANIMAL_CORS_ALLOWED_ORIGINS"),
    )

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


settings = Settings()
