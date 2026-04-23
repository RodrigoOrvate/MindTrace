from sqlalchemy import text
from sqlalchemy.engine import Engine


def ensure_schema_compat(engine: Engine) -> None:
    """Aplica migrações de schema retrocompatíveis para bancos já existentes."""
    if engine.dialect.name == "sqlite":
        _ensure_schema_compat_sqlite(engine)
    elif engine.dialect.name == "postgresql":
        _ensure_schema_compat_postgresql(engine)


def _ensure_schema_compat_sqlite(engine: Engine) -> None:
    with engine.begin() as conn:
        users_cols = {
            row[1] for row in conn.execute(text("PRAGMA table_info(app_users)")).fetchall()
        }
        if users_cols:
            if "full_name" not in users_cols:
                conn.execute(text("ALTER TABLE app_users ADD COLUMN full_name TEXT DEFAULT 'Usuário'"))
            if "email" not in users_cols:
                conn.execute(text("ALTER TABLE app_users ADD COLUMN email TEXT"))
            if "is_admin" not in users_cols:
                conn.execute(text("ALTER TABLE app_users ADD COLUMN is_admin INTEGER DEFAULT 0"))
            if "failed_login_count" not in users_cols:
                conn.execute(text("ALTER TABLE app_users ADD COLUMN failed_login_count INTEGER DEFAULT 0"))
            if "locked_until" not in users_cols:
                conn.execute(text("ALTER TABLE app_users ADD COLUMN locked_until DATETIME"))
            if "last_login_at" not in users_cols:
                conn.execute(text("ALTER TABLE app_users ADD COLUMN last_login_at DATETIME"))
            if "preferred_theme" not in users_cols:
                conn.execute(text("ALTER TABLE app_users ADD COLUMN preferred_theme TEXT DEFAULT 'light'"))
            if "preferred_language" not in users_cols:
                conn.execute(text("ALTER TABLE app_users ADD COLUMN preferred_language TEXT DEFAULT 'pt'"))

        exp_cols = {
            row[1] for row in conn.execute(text("PRAGMA table_info(experiments)")).fetchall()
        }
        if exp_cols and "responsible_username" not in exp_cols:
            conn.execute(text("ALTER TABLE experiments ADD COLUMN responsible_username TEXT"))


def _ensure_schema_compat_postgresql(engine: Engine) -> None:
    with engine.begin() as conn:
        conn.execute(text(
            "ALTER TABLE app_users ADD COLUMN IF NOT EXISTS preferred_theme VARCHAR(16) DEFAULT 'light'"
        ))
        conn.execute(text(
            "ALTER TABLE app_users ADD COLUMN IF NOT EXISTS preferred_language VARCHAR(8) DEFAULT 'pt'"
        ))
        conn.execute(text(
            "ALTER TABLE experiments ADD COLUMN IF NOT EXISTS responsible_username VARCHAR(80)"
        ))
