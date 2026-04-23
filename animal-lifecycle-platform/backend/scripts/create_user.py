"""Bootstrap do primeiro administrador do Animal Lifecycle.

Este script serve EXCLUSIVAMENTE para criar a conta admin inicial, antes de
qualquer acesso ao aplicativo. Após o admin existir, todos os usuários comuns
devem ser criados pelo próprio admin dentro do aplicativo (POST /auth/users).

Uso único — com USER_BOOTSTRAP_ENABLED=1:
    $env:USER_BOOTSTRAP_ENABLED="1"
    python scripts\create_user.py
    $env:USER_BOOTSTRAP_ENABLED="0"
"""
import getpass
import os
import sys
from pathlib import Path

from sqlalchemy import select

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
        print("Bloqueado: habilite USER_BOOTSTRAP_ENABLED=1 temporariamente.")
        return 1
    if not sys.stdin.isatty():
        print("Bloqueado: execucao nao interativa nao permitida.")
        return 1

    Base.metadata.create_all(bind=engine)
    ensure_schema_compat(engine)

    with SessionLocal() as db:
        has_admin = (
            db.execute(select(AppUser).where(AppUser.is_admin.is_(True))).scalar_one_or_none()
            is not None
        )

    if has_admin:
        print(
            "\n[BLOQUEADO] Ja existe um administrador no banco.\n"
            "\n"
            "Para criar usuarios comuns, use o aplicativo:\n"
            "  - Faca login como admin\n"
            "  - Acesse a tela de Usuarios\n"
            "  - Crie a conta diretamente pelo app (POST /auth/users)\n"
            "\n"
            "Este script so pode ser executado uma vez, para o admin inicial."
        )
        return 1

    print("=== Criar administrador inicial (Animal Lifecycle) ===\n")
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

    with SessionLocal() as db:
        existing = db.execute(select(AppUser).where(AppUser.username == username)).scalar_one_or_none()
        if existing:
            print(f"Erro: usuario '{username}' ja existe.")
            return 1

        user = AppUser(
            full_name=full_name,
            email=email,
            username=username,
            password_hash=hash_password(password),
            is_admin=True,
            is_active=True,
            failed_login_count=0,
        )
        db.add(user)
        db.commit()

    print(f"\nAdministrador '{username}' criado com sucesso.")
    print("Agora voce pode criar usuarios comuns pelo aplicativo (como admin logado).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
