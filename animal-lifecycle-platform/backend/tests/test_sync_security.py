import json
import os
import time
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

os.environ["APP_SKIP_DB_INIT"] = "1"

from app.main import app
from app.schemas import MindTraceDeleteResult, MindTraceImportResult
from app.config import settings
from app.db import get_db
from app.security_sync import verify_loopback_client

_TEST_ROOT = Path(__file__).resolve().parent / "_tmp_sync_tests"
_TEST_ROOT.mkdir(parents=True, exist_ok=True)


class _DummySession:
    def commit(self) -> None:
        return None

    def rollback(self) -> None:
        return None


@pytest.fixture
def client():
    def _override_db():
        yield _DummySession()

    app.dependency_overrides[get_db] = _override_db
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()


def _sign(secret: str, timestamp: str, body: bytes) -> str:
    import hmac
    from hashlib import sha256

    return hmac.new(secret.encode("utf-8"), f"{timestamp}\n".encode("utf-8") + body, sha256).hexdigest()


def _test_dir(name: str) -> Path:
    path = (_TEST_ROOT / name).resolve()
    path.mkdir(parents=True, exist_ok=True)
    return path


def test_sync_rejects_missing_auth_headers(monkeypatch, client: TestClient) -> None:
    tmp_path = _test_dir("missing_auth")
    monkeypatch.setattr(settings, "sync_secret", "abc123")
    monkeypatch.setattr(settings, "mindtrace_allowed_roots", str(tmp_path))

    payload = {"experiment_path": str(tmp_path), "dry_run": True}
    res = client.post("/sync/mindtrace/import-folder", json=payload)
    assert res.status_code == 401
    assert "autenticação" in res.json()["detail"]


def test_sync_rejects_non_loopback_client() -> None:
    import pytest
    from fastapi import HTTPException

    with pytest.raises(HTTPException) as err:
        verify_loopback_client("10.10.10.10")
    assert err.value.status_code == 403


def test_sync_rejects_bad_signature(monkeypatch, client: TestClient) -> None:
    tmp_path = _test_dir("bad_signature")
    monkeypatch.setattr(settings, "sync_secret", "abc123")
    monkeypatch.setattr(settings, "mindtrace_allowed_roots", str(tmp_path))

    body = json.dumps({"experiment_path": str(tmp_path), "dry_run": True}).encode("utf-8")
    ts = str(int(time.time()))
    res = client.post(
        "/sync/mindtrace/import-folder",
        content=body,
        headers={
            "Content-Type": "application/json",
            "X-MindTrace-Timestamp": ts,
            "X-MindTrace-Signature": "00" * 32,
        },
    )
    assert res.status_code == 401
    assert "Assinatura inválida" in res.json()["detail"]


def test_sync_rejects_path_traversal_outside_allowed_root(monkeypatch, client: TestClient) -> None:
    tmp_path = _test_dir("path_traversal")
    monkeypatch.setattr(settings, "sync_secret", "abc123")
    monkeypatch.setattr(settings, "mindtrace_allowed_roots", str(tmp_path))

    forbidden_path = str((tmp_path.parent / "outside-exp").resolve())
    body = json.dumps({"experiment_path": forbidden_path, "dry_run": True}).encode("utf-8")
    ts = str(int(time.time()))
    sig = _sign("abc123", ts, body)
    res = client.post(
        "/sync/mindtrace/import-folder",
        content=body,
        headers={
            "Content-Type": "application/json",
            "X-MindTrace-Timestamp": ts,
            "X-MindTrace-Signature": sig,
        },
    )
    assert res.status_code == 403
    assert "fora das raízes permitidas" in res.json()["detail"]


def test_sync_rejects_replay_timestamp(monkeypatch, client: TestClient) -> None:
    tmp_path = _test_dir("replay")
    monkeypatch.setattr(settings, "sync_secret", "abc123")
    monkeypatch.setattr(settings, "mindtrace_allowed_roots", str(tmp_path))
    monkeypatch.setattr(settings, "sync_max_skew_seconds", 5)

    body = json.dumps({"experiment_path": str(tmp_path), "dry_run": True}).encode("utf-8")
    ts = str(int(time.time()) - 3600)
    sig = _sign("abc123", ts, body)
    res = client.post(
        "/sync/mindtrace/import-folder",
        content=body,
        headers={
            "Content-Type": "application/json",
            "X-MindTrace-Timestamp": ts,
            "X-MindTrace-Signature": sig,
        },
    )
    assert res.status_code == 401
    assert "Timestamp expirado" in res.json()["detail"]


def test_sync_allows_valid_signed_local_request(monkeypatch, client: TestClient) -> None:
    tmp_path = _test_dir("valid_request")
    monkeypatch.setattr(settings, "sync_secret", "abc123")
    monkeypatch.setattr(settings, "mindtrace_allowed_roots", str(tmp_path))

    # evita tocar disco e banco real no import
    import app.routers.sync as sync_router

    def fake_import(_db, _payload):
        return MindTraceImportResult(
            imported_experiment_id=1,
            sessions_found=2,
            enrollments_created=2,
            animals_linked=2,
            missing_animals=[],
            warnings=[],
        )

    monkeypatch.setattr(sync_router, "import_mindtrace_folder", fake_import)

    body = json.dumps({"experiment_path": str(tmp_path), "dry_run": True}).encode("utf-8")
    ts = str(int(time.time()))
    sig = _sign("abc123", ts, body)
    res = client.post(
        "/sync/mindtrace/import-folder",
        content=body,
        headers={
            "Content-Type": "application/json",
            "X-MindTrace-Timestamp": ts,
            "X-MindTrace-Signature": sig,
        },
    )
    assert res.status_code == 200
    assert res.json()["sessions_found"] == 2


def test_delete_sync_rejects_missing_auth_headers(monkeypatch, client: TestClient) -> None:
    monkeypatch.setattr(settings, "sync_secret", "abc123")
    payload = {"experiment_name": "NOR-01", "context": "NOR"}
    res = client.post("/sync/mindtrace/experiment-deleted", json=payload)
    assert res.status_code == 401
    assert "autentica" in res.json()["detail"].lower()


def test_delete_sync_rejects_bad_signature(monkeypatch, client: TestClient) -> None:
    monkeypatch.setattr(settings, "sync_secret", "abc123")
    body = json.dumps({"experiment_name": "NOR-01", "context": "NOR"}).encode("utf-8")
    ts = str(int(time.time()))
    res = client.post(
        "/sync/mindtrace/experiment-deleted",
        content=body,
        headers={
            "Content-Type": "application/json",
            "X-MindTrace-Timestamp": ts,
            "X-MindTrace-Signature": "11" * 32,
        },
    )
    assert res.status_code == 401
    assert "assinatura" in res.json()["detail"].lower()


def test_delete_sync_allows_valid_signed_local_request(monkeypatch, client: TestClient) -> None:
    monkeypatch.setattr(settings, "sync_secret", "abc123")

    import app.routers.sync as sync_router

    def fake_delete(_db, payload):
        assert payload.experiment_name == "NOR-01"
        return MindTraceDeleteResult(
            experiments_matched=1,
            animals_notified=3,
            notes_created=3,
            warnings=[],
        )

    monkeypatch.setattr(sync_router, "mark_experiment_deleted", fake_delete)

    body = json.dumps({"experiment_name": "NOR-01", "context": "NOR"}).encode("utf-8")
    ts = str(int(time.time()))
    sig = _sign("abc123", ts, body)
    res = client.post(
        "/sync/mindtrace/experiment-deleted",
        content=body,
        headers={
            "Content-Type": "application/json",
            "X-MindTrace-Timestamp": ts,
            "X-MindTrace-Signature": sig,
        },
    )
    assert res.status_code == 200
    assert res.json()["animals_notified"] == 3
