import base64
import hashlib
import hmac
import os
import secrets
import time

from fastapi import Depends, HTTPException, Request
from sqlalchemy.orm import Session

from .config import settings
from .db import get_db
from .models import AppUser
from .security_network import ensure_admin_ip_allowed, ensure_client_ip_allowed


_DEFAULT_AUTH_SECRET = "dev-local-auth-secret-change-me"


def _auth_secret_bytes() -> bytes:
    raw = settings.auth_secret.strip() or _DEFAULT_AUTH_SECRET
    return raw.encode("utf-8")


def hash_password(password: str, salt: bytes | None = None, iterations: int = 200_000) -> str:
    if not password:
        raise ValueError("Senha vazia.")
    salt = salt or os.urandom(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, iterations)
    return f"pbkdf2_sha256${iterations}${salt.hex()}${digest.hex()}"


def verify_password(password: str, password_hash: str) -> bool:
    try:
        algo, iter_text, salt_hex, digest_hex = password_hash.split("$", 3)
        if algo != "pbkdf2_sha256":
            return False
        iterations = int(iter_text)
        salt = bytes.fromhex(salt_hex)
        expected = bytes.fromhex(digest_hex)
    except Exception:
        return False
    got = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, iterations)
    return hmac.compare_digest(got, expected)


def create_access_token(*, user_id: int, username: str) -> str:
    now = int(time.time())
    exp = now + max(60, int(settings.auth_token_ttl_seconds))
    nonce = secrets.token_hex(8)
    payload = f"{user_id}:{username}:{exp}:{nonce}"
    signature = hmac.new(_auth_secret_bytes(), payload.encode("utf-8"), hashlib.sha256).hexdigest()
    token_raw = f"{payload}:{signature}".encode("utf-8")
    return base64.urlsafe_b64encode(token_raw).decode("ascii")


def parse_access_token(token: str) -> tuple[int, str]:
    try:
        decoded = base64.urlsafe_b64decode(token.encode("ascii")).decode("utf-8")
        user_id_text, username, exp_text, nonce, signature = decoded.split(":", 4)
        payload = f"{user_id_text}:{username}:{exp_text}:{nonce}"
        expected = hmac.new(_auth_secret_bytes(), payload.encode("utf-8"), hashlib.sha256).hexdigest()
        if not hmac.compare_digest(expected, signature):
            raise ValueError("assinatura invalida")
        exp = int(exp_text)
        if int(time.time()) > exp:
            raise ValueError("token expirado")
        return int(user_id_text), username
    except Exception as exc:
        raise HTTPException(status_code=401, detail="Token invalido ou expirado.") from exc


def _extract_bearer_token(request: Request) -> str:
    auth = request.headers.get("Authorization", "")
    if not auth.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Authorization Bearer obrigatorio.")
    token = auth[7:].strip()
    if not token:
        raise HTTPException(status_code=401, detail="Token ausente.")
    return token


def require_auth(request: Request, db: Session = Depends(get_db)) -> AppUser:
    ensure_client_ip_allowed(request.client.host if request.client else None)
    token = _extract_bearer_token(request)
    user_id, username = parse_access_token(token)
    user = db.get(AppUser, user_id)
    if not user or not user.is_active or user.username != username:
        raise HTTPException(status_code=401, detail="Sessao invalida.")
    return user


def require_admin(user: AppUser = Depends(require_auth)) -> AppUser:
    if not user.is_admin:
        raise HTTPException(status_code=403, detail="Apenas administrador pode executar esta acao.")
    return user


def require_admin_local(request: Request, user: AppUser = Depends(require_admin)) -> AppUser:
    ensure_admin_ip_allowed(request.client.host if request.client else None)
    return user
