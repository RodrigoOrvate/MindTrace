from datetime import UTC, datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from ..config import settings
from ..db import get_db
from ..models import AppSetting, AppUser
from ..schemas import (
    AuthSettingsOut,
    DateFormatInput,
    LoginInput,
    LoginResult,
    ResearcherOut,
    UserCreateInput,
    UserOut,
    UserPreferencesInput,
)
from ..security_auth import create_access_token, hash_password, require_admin_local, require_auth, verify_password
from ..security_network import is_admin_ip_allowed_for_login, is_client_ip_allowed_for_login


router = APIRouter(prefix="/auth", tags=["auth"])
DATE_FORMAT_KEY = "global.date_format"
DEFAULT_DATE_FORMAT = "DD/MM/YYYY"


def _get_or_create_date_format(db: Session) -> str:
    row = db.execute(select(AppSetting).where(AppSetting.key == DATE_FORMAT_KEY)).scalar_one_or_none()
    if row is None:
        row = AppSetting(key=DATE_FORMAT_KEY, value=DEFAULT_DATE_FORMAT)
        db.add(row)
        db.commit()
        db.refresh(row)
    return row.value or DEFAULT_DATE_FORMAT


def _raise_invalid_login() -> None:
    raise HTTPException(status_code=401, detail="Login invalido.")


@router.post("/login", response_model=LoginResult)
def login(payload: LoginInput, request: Request, db: Session = Depends(get_db)) -> LoginResult:
    if not is_client_ip_allowed_for_login(request.client.host if request.client else None):
        _raise_invalid_login()
    username = payload.username.strip()
    now = datetime.now(UTC).replace(tzinfo=None)

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

    if user.is_admin and not is_admin_ip_allowed_for_login(request.client.host if request.client else None):
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
        "theme": user.preferred_theme or "light",
        "language": user.preferred_language or "pt",
    }


@router.get("/settings", response_model=AuthSettingsOut)
def get_settings(user: AppUser = Depends(require_auth), db: Session = Depends(get_db)) -> AuthSettingsOut:
    return AuthSettingsOut(
        theme=(user.preferred_theme or "light"),
        language=(user.preferred_language or "pt"),
        date_format=_get_or_create_date_format(db),
        is_admin=bool(user.is_admin),
    )


@router.patch("/settings/preferences", response_model=AuthSettingsOut)
def update_my_preferences(
    payload: UserPreferencesInput,
    user: AppUser = Depends(require_auth),
    db: Session = Depends(get_db),
) -> AuthSettingsOut:
    changed = False
    if payload.theme is not None:
        user.preferred_theme = payload.theme
        changed = True
    if payload.language is not None:
        user.preferred_language = payload.language
        changed = True
    if changed:
        db.commit()
        db.refresh(user)
    return AuthSettingsOut(
        theme=(user.preferred_theme or "light"),
        language=(user.preferred_language or "pt"),
        date_format=_get_or_create_date_format(db),
        is_admin=bool(user.is_admin),
    )


@router.patch("/settings/date-format", response_model=AuthSettingsOut)
def update_global_date_format(
    payload: DateFormatInput,
    admin: AppUser = Depends(require_admin_local),
    db: Session = Depends(get_db),
) -> AuthSettingsOut:
    row = db.execute(select(AppSetting).where(AppSetting.key == DATE_FORMAT_KEY)).scalar_one_or_none()
    if row is None:
        row = AppSetting(key=DATE_FORMAT_KEY, value=payload.date_format)
        db.add(row)
    else:
        row.value = payload.date_format
    db.commit()
    return AuthSettingsOut(
        theme=(admin.preferred_theme or "light"),
        language=(admin.preferred_language or "pt"),
        date_format=payload.date_format,
        is_admin=True,
    )


@router.get("/users/researchers", response_model=list[ResearcherOut])
def list_researchers(db: Session = Depends(get_db), _user: AppUser = Depends(require_auth)) -> list[AppUser]:
    return list(
        db.execute(
            select(AppUser)
            .where(AppUser.is_admin == False)  # noqa: E712
            .where(or_(AppUser.is_active == True, AppUser.is_active.is_(None)))  # noqa: E712
            .order_by(AppUser.full_name.asc())
        ).scalars().all()
    )


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
