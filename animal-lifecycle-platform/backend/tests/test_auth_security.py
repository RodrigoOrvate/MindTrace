import os

os.environ["APP_SKIP_DB_INIT"] = "1"

from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.db import Base, get_db
from app.main import app
from app.models import AppUser
from app.security_auth import create_access_token, hash_password
from app.security_network import ensure_admin_ip_allowed, ensure_client_ip_allowed, is_client_ip_allowed_for_login
from app.config import settings


def _make_client():
    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        future=True,
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine, future=True)
    Base.metadata.create_all(bind=engine)

    with TestingSessionLocal() as db:
        db.add(
            AppUser(
                full_name="Lab Admin",
                email="admin@lab.local",
                username="labadmin",
                password_hash=hash_password("SenhaForte123"),
                is_admin=True,
                is_active=True,
                failed_login_count=0,
            )
        )
        db.add(
            AppUser(
                full_name="Usuário Comum",
                email="user@lab.local",
                username="user1",
                password_hash=hash_password("SenhaForte123"),
                is_admin=False,
                is_active=True,
                failed_login_count=0,
            )
        )
        db.commit()

    def _override_db():
        db: Session = TestingSessionLocal()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = _override_db
    client = TestClient(app)
    return client, TestingSessionLocal


def test_login_rejects_invalid_password() -> None:
    client, _ = _make_client()
    res = client.post("/auth/login", json={"username": "labadmin", "password": "errada"})
    assert res.status_code == 401


def test_protected_endpoint_rejects_missing_token() -> None:
    client, _ = _make_client()
    res = client.get("/animals")
    assert res.status_code == 401
    assert "Bearer" in res.json()["detail"]


def test_protected_endpoint_rejects_tampered_token() -> None:
    client, _ = _make_client()
    res = client.get("/animals", headers={"Authorization": "Bearer invalid.token.payload"})
    assert res.status_code == 401


def test_login_then_access_animals_ok() -> None:
    client, _ = _make_client()
    auth = client.post("/auth/login", json={"username": "labadmin", "password": "SenhaForte123"})
    assert auth.status_code == 200
    token = auth.json()["access_token"]
    res = client.get("/animals", headers={"Authorization": f"Bearer {token}"})
    assert res.status_code == 200
    me = client.get("/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert me.status_code == 200
    assert me.json()["full_name"] == "Lab Admin"


def test_admin_can_create_user() -> None:
    client, _ = _make_client()
    auth = client.post("/auth/login", json={"username": "labadmin", "password": "SenhaForte123"})
    token = auth.json()["access_token"]
    res = client.post(
        "/auth/users",
        headers={"Authorization": f"Bearer {token}"},
        json={
            "full_name": "Pesquisador 2",
            "email": "p2@lab.local",
            "username": "p02",
            "password": "SenhaForte123",
            "is_admin": False,
        },
    )
    assert res.status_code == 200
    assert res.json()["username"] == "p02"


def test_admin_cannot_create_another_admin() -> None:
    client, _ = _make_client()
    auth = client.post("/auth/login", json={"username": "labadmin", "password": "SenhaForte123"})
    token = auth.json()["access_token"]
    res = client.post(
        "/auth/users",
        headers={"Authorization": f"Bearer {token}"},
        json={
            "full_name": "Novo Admin",
            "email": "admin2@lab.local",
            "username": "admin2",
            "password": "SenhaForte123",
            "is_admin": True,
        },
    )
    assert res.status_code == 403


def test_non_admin_cannot_create_user() -> None:
    client, _ = _make_client()
    auth = client.post("/auth/login", json={"username": "user1", "password": "SenhaForte123"})
    token = auth.json()["access_token"]
    res = client.post(
        "/auth/users",
        headers={"Authorization": f"Bearer {token}"},
        json={
            "full_name": "Sem Permissão",
            "username": "xpto",
            "password": "SenhaForte123",
        },
    )
    assert res.status_code == 403


def test_token_for_nonexistent_user_is_rejected() -> None:
    client, _ = _make_client()
    token = create_access_token(user_id=9999, username="ghost")
    res = client.get("/animals", headers={"Authorization": f"Bearer {token}"})
    assert res.status_code == 401


def test_login_bruteforce_block_after_retries() -> None:
    client, _ = _make_client()
    for _ in range(5):
        client.post("/auth/login", json={"username": "labadmin", "password": "errada"})
    blocked = client.post("/auth/login", json={"username": "labadmin", "password": "errada"})
    assert blocked.status_code == 401
    assert blocked.json()["detail"] == "Login invalido."


def test_network_gate_rejects_disallowed_ip(monkeypatch) -> None:
    import pytest
    from fastapi import HTTPException

    monkeypatch.setattr(settings, "auth_allowed_cidrs", "10.0.0.0/24")
    with pytest.raises(HTTPException) as err:
        ensure_client_ip_allowed("192.168.0.10")
    assert err.value.status_code == 403


def test_admin_network_gate_rejects_disallowed_ip(monkeypatch) -> None:
    import pytest
    from fastapi import HTTPException

    monkeypatch.setattr(settings, "auth_admin_allowed_cidrs", "127.0.0.1/32")
    with pytest.raises(HTTPException) as err:
        ensure_admin_ip_allowed("192.168.0.50")
    assert err.value.status_code == 403


def test_admin_network_gate_accepts_main_pc_ip(monkeypatch) -> None:
    monkeypatch.setattr(settings, "auth_admin_allowed_cidrs", "127.0.0.1/32;192.168.1.10/32")
    ensure_admin_ip_allowed("192.168.1.10")


def test_login_network_gate_rejects_disallowed_ip_bool(monkeypatch) -> None:
    monkeypatch.setattr(settings, "auth_login_allowed_cidrs", "127.0.0.1/32")
    assert is_client_ip_allowed_for_login("192.168.0.10") is False


def test_login_network_gate_accepts_main_pc_ip_bool(monkeypatch) -> None:
    monkeypatch.setattr(settings, "auth_login_allowed_cidrs", "127.0.0.1/32;192.168.1.10/32")
    assert is_client_ip_allowed_for_login("192.168.1.10") is True


def test_login_from_disallowed_ip_returns_generic_invalid(monkeypatch) -> None:
    import app.routers.auth as auth_router

    client, _ = _make_client()
    monkeypatch.setattr(auth_router, "is_client_ip_allowed_for_login", lambda _ip: False)
    res = client.post("/auth/login", json={"username": "labadmin", "password": "SenhaForte123"})
    assert res.status_code == 401
    assert res.json()["detail"] == "Login invalido."
