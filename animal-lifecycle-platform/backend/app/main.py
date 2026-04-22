import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .bootstrap import ensure_schema_compat
from .config import settings
from .db import Base, SessionLocal, engine
from .routers import animals, auth, experiments, lookups, sync
from .seed import run_seed


def create_app() -> FastAPI:
    app = FastAPI(
        title=settings.app_name,
        description="API para rastrear ciclo de vida de animais de laboratório e integrar sessões do MindTrace.",
        version="0.1.0",
    )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=False,
        allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
        allow_headers=["*"],
    )
    app.include_router(auth.router)
    app.include_router(lookups.router)
    app.include_router(animals.router)
    app.include_router(experiments.router)
    app.include_router(sync.router)

    @app.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ok", "env": settings.app_env}

    return app


app = create_app()

if os.getenv("APP_SKIP_DB_INIT", "0").strip().lower() not in {"1", "true", "yes"}:
    Base.metadata.create_all(bind=engine)
    ensure_schema_compat(engine)
    with SessionLocal() as db:
        run_seed(db)
        db.commit()
