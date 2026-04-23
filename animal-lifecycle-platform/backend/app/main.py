import logging
import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .bootstrap import ensure_schema_compat
from .config import settings
from .db import Base, SessionLocal, engine
from .routers import animals, auth, experiments, lookups, sync
from .seed import run_seed

logger = logging.getLogger("animal_lifecycle.startup")


def _parse_origins(raw: str) -> list[str]:
    return [o.strip() for o in raw.split(";") if o.strip()]


def _check_startup_secrets() -> None:
    """Falha rápido se segredos obrigatórios não estiverem configurados em produção."""
    if settings.app_env != "dev" and not settings.auth_secret.strip():
        raise RuntimeError(
            "AUTH_SECRET nao configurado. Defina a variavel no .env antes de subir em producao."
        )
    if not settings.auth_secret.strip():
        logger.warning(
            "AUTH_SECRET ausente — usando segredo padrao de desenvolvimento. "
            "NUNCA use assim em producao."
        )


def create_app() -> FastAPI:
    _check_startup_secrets()

    app = FastAPI(
        title=settings.app_name,
        description="API para rastrear ciclo de vida de animais de laboratório e integrar sessões do MindTrace.",
        version="0.1.0",
    )

    origins = _parse_origins(settings.cors_allowed_origins)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=origins,
        allow_credentials=False,
        allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type"],
    )

    app.include_router(auth.router)
    app.include_router(lookups.router)
    app.include_router(animals.router)
    app.include_router(experiments.router)
    app.include_router(sync.router)

    @app.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ok"}

    return app


app = create_app()

if os.getenv("APP_SKIP_DB_INIT", "0").strip().lower() not in {"1", "true", "yes"}:
    Base.metadata.create_all(bind=engine)
    ensure_schema_compat(engine)
    with SessionLocal() as db:
        run_seed(db)
        db.commit()
