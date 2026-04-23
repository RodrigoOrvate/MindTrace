from collections.abc import Generator

from sqlalchemy import create_engine
from sqlalchemy.orm import Session, declarative_base, sessionmaker

from .config import settings


def _build_engine():
    url = settings.database_url
    if url.startswith("postgresql"):
        return create_engine(url, future=True, pool_pre_ping=True)
    # SQLite: passthrough (sem pool_pre_ping, sem connect_args extras)
    return create_engine(url, future=True)


engine = _build_engine()
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine, future=True)
Base = declarative_base()


def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
