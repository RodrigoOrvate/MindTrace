from sqlalchemy import text
from sqlalchemy.engine import Engine


def ensure_schema_compat(engine: Engine) -> None:
    with engine.begin() as conn:
        cols = {
            row[1] for row in conn.execute(text("PRAGMA table_info(app_users)")).fetchall()
        }
        if not cols:
            return

        if "full_name" not in cols:
            conn.execute(text("ALTER TABLE app_users ADD COLUMN full_name TEXT DEFAULT 'Usuário'"))
        if "email" not in cols:
            conn.execute(text("ALTER TABLE app_users ADD COLUMN email TEXT"))
        if "is_admin" not in cols:
            conn.execute(text("ALTER TABLE app_users ADD COLUMN is_admin INTEGER DEFAULT 0"))
        if "failed_login_count" not in cols:
            conn.execute(text("ALTER TABLE app_users ADD COLUMN failed_login_count INTEGER DEFAULT 0"))
        if "locked_until" not in cols:
            conn.execute(text("ALTER TABLE app_users ADD COLUMN locked_until DATETIME"))
        if "last_login_at" not in cols:
            conn.execute(text("ALTER TABLE app_users ADD COLUMN last_login_at DATETIME"))
