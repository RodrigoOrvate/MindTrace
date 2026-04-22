import hmac
import time
from hashlib import sha256
from pathlib import Path

from fastapi import HTTPException

from .config import settings


def allowed_mindtrace_roots() -> list[Path]:
    if settings.mindtrace_allowed_roots.strip():
        roots = [Path(chunk.strip()) for chunk in settings.mindtrace_allowed_roots.split(";") if chunk.strip()]
    else:
        roots = [Path.home() / "Documents" / "MindTrace_Data" / "Experimentos"]
    return [root.resolve(strict=False) for root in roots]


def ensure_safe_experiment_path(path_str: str) -> Path:
    candidate = Path(path_str)
    if not candidate.is_absolute():
        raise HTTPException(status_code=400, detail="experiment_path deve ser absoluto.")

    resolved = candidate.resolve(strict=False)
    roots = allowed_mindtrace_roots()
    for root in roots:
        try:
            resolved.relative_to(root)
            return resolved
        except ValueError:
            continue
    raise HTTPException(status_code=403, detail="experiment_path fora das raízes permitidas.")


def verify_sync_signature(body: bytes, timestamp_header: str | None, signature_header: str | None) -> None:
    if not settings.sync_secret:
        raise HTTPException(status_code=503, detail="Sync auth não configurada no backend.")
    if not timestamp_header or not signature_header:
        raise HTTPException(status_code=401, detail="Headers de autenticação ausentes.")

    try:
        ts = int(timestamp_header)
    except ValueError as exc:
        raise HTTPException(status_code=401, detail="Timestamp inválido.") from exc

    now = int(time.time())
    if abs(now - ts) > settings.sync_max_skew_seconds:
        raise HTTPException(status_code=401, detail="Timestamp expirado.")

    expected = hmac.new(
        settings.sync_secret.encode("utf-8"),
        f"{timestamp_header}\n".encode("utf-8") + body,
        sha256,
    ).hexdigest()
    if not hmac.compare_digest(expected, signature_header.lower().strip()):
        raise HTTPException(status_code=401, detail="Assinatura inválida.")


def verify_loopback_client(client_host: str | None) -> None:
    if client_host in {"127.0.0.1", "::1", "localhost", "testclient"}:
        return
    raise HTTPException(status_code=403, detail="Sync permitido apenas via loopback local.")
