import getpass
import os
import sys
from pathlib import Path

from sqlalchemy import select

# Garante que "backend/" esteja no sys.path quando rodar como arquivo.
BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from app.bootstrap import ensure_schema_compat
from app.config import settings
from app.db import Base, SessionLocal, engine
from app.models import AppUser
from app.security_auth import hash_password


def _bootstrap_enabled() -> bool:
    if settings.user_bootstrap_enabled:
        return True
    flag = os.getenv("USER_BOOTSTRAP_ENABLED", "0").strip().lower()
    return flag in {"1", "true", "yes"}


def main() -> int:
    if not _bootstrap_enabled():
        print("Bloqueado por seguranca: habilite USER_BOOTSTRAP_ENABLED=1 temporariamente para criar usuarios via script.")
        return 1
    if not sys.stdin.isatty():
        print("Bloqueado: execucao nao interativa nao permitida para create_user.py.")
        return 1

    print("=== Criar usuario de acesso (Animal Lifecycle) ===")
    full_name = input("Nome completo: ").strip()
    if len(full_name) < 3:
        print("Erro: nome deve ter ao menos 3 caracteres.")
        return 1

    email = input("Email (opcional): ").strip() or None
    username = input("Usuario: ").strip()
    if len(username) < 3:
        print("Erro: usuario deve ter ao menos 3 caracteres.")
        return 1

    password = getpass.getpass("Senha: ")
    password2 = getpass.getpass("Confirmar senha: ")
    if password != password2:
        print("Erro: senhas nao conferem.")
        return 1
    if len(password) < 8:
        print("Erro: use senha com ao menos 8 caracteres.")
        return 1

    Base.metadata.create_all(bind=engine)
    ensure_schema_compat(engine)

    with SessionLocal() as db:
        has_admin = db.execute(select(AppUser).where(AppUser.is_admin.is_(True))).scalar_one_or_none() is not None
        if has_admin:
            is_admin = False
            print("Politica ativa: ja existe administrador. Novas contas serao criadas/atualizadas como usuario comum.")
        else:
            admin_answer = input("Primeiro administrador detectado. Tornar esta conta admin? (S/n): ").strip().lower()
            is_admin = admin_answer not in {"n", "nao", "no"}

        existing = db.execute(select(AppUser).where(AppUser.username == username)).scalar_one_or_none()
        if existing:
            existing.full_name = full_name
            existing.email = email
            existing.password_hash = hash_password(password)
            if not existing.is_admin:
                existing.is_admin = is_admin
            existing.is_active = True
            existing.failed_login_count = 0
            existing.locked_until = None
            db.commit()
            print("Usuario atualizado com sucesso.")
            return 0

        user = AppUser(
            full_name=full_name,
            email=email,
            username=username,
            password_hash=hash_password(password),
            is_admin=is_admin,
            is_active=True,
            failed_login_count=0,
        )
        db.add(user)
        db.commit()
        print("Usuario criado com sucesso.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
