from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..config import settings
from ..db import get_db
from ..models import AppUser
from ..schemas import LoginInput, LoginResult, UserCreateInput, UserOut
from ..security_auth import create_access_token, hash_password, require_admin_local, require_auth, verify_password
from ..security_network import is_client_ip_allowed_for_login


router = APIRouter(prefix="/auth", tags=["auth"])


def _raise_invalid_login() -> None:
    raise HTTPException(status_code=401, detail="Login invalido.")


@router.post("/login", response_model=LoginResult)
def login(payload: LoginInput, request: Request, db: Session = Depends(get_db)) -> LoginResult:
    if not is_client_ip_allowed_for_login(request.client.host if request.client else None):
        _raise_invalid_login()
    username = payload.username.strip()
    now = datetime.utcnow()

    user = db.execute(select(AppUser).where(AppUser.username == username)).scalar_one_or_none()
    if not user or not user.is_active:
        _raise_invalid_login()

    if user.locked_until and user.locked_until > now:
        _raise_invalid_login()

    if not verify_password(payload.password, user.password_hash):
        user.failed_login_count = int(user.failed_login_count or 0) + 1
        if user.failed_login_count >= max(1, int(settings.auth_max_failed_attempts)):
            lock_minutes = max(1, int(settings.auth_lock_minutes))
            user.locked_until = now + timedelta(minutes=lock_minutes)
            user.failed_login_count = 0
        db.commit()
        _raise_invalid_login()

    user.failed_login_count = 0
    user.locked_until = None
    user.last_login_at = now
    db.commit()

    token = create_access_token(user_id=user.id, username=user.username)
    return LoginResult(
        access_token=token,
        token_type="bearer",
        expires_in=max(60, int(settings.auth_token_ttl_seconds)),
        username=user.username,
        full_name=user.full_name or user.username,
        email=user.email,
        is_admin=user.is_admin,
    )


@router.get("/me")
def me(request: Request, user: AppUser = Depends(require_auth)) -> dict[str, str]:
    return {
        "username": user.username,
        "full_name": user.full_name or user.username,
        "email": user.email or "",
        "is_admin": "true" if user.is_admin else "false",
        "authenticated": "true",
        "client": request.client.host if request.client else "",
    }


@router.get("/users", response_model=list[UserOut])
def list_users(_admin: AppUser = Depends(require_admin_local), db: Session = Depends(get_db)) -> list[AppUser]:
    return list(db.execute(select(AppUser).order_by(AppUser.created_at.asc())).scalars().all())


@router.post("/users", response_model=UserOut)
def create_user(payload: UserCreateInput, _admin: AppUser = Depends(require_admin_local), db: Session = Depends(get_db)) -> AppUser:
    username = payload.username.strip()
    if payload.is_admin:
        raise HTTPException(
            status_code=403,
            detail="Criacao de novo administrador bloqueada por politica de seguranca.",
        )

    exists = db.execute(select(AppUser).where(AppUser.username == username)).scalar_one_or_none()
    if exists:
        raise HTTPException(status_code=409, detail="Usuario ja existe.")
    if payload.email:
        email_exists = db.execute(select(AppUser).where(AppUser.email == payload.email.strip())).scalar_one_or_none()
        if email_exists:
            raise HTTPException(status_code=409, detail="Email ja cadastrado.")

    user = AppUser(
        full_name=payload.full_name.strip(),
        email=payload.email.strip() if payload.email else None,
        username=username,
        password_hash=hash_password(payload.password),
        is_admin=payload.is_admin,
        is_active=True,
        failed_login_count=0,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user
