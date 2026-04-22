import hashlib
import os
import shutil
import sqlite3
from datetime import datetime, timedelta, timezone
from pathlib import Path


def _env(name: str, default: str = "") -> str:
    return os.getenv(name, default).strip()


def _ensure_path(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _sqlite_backup(db_path: Path, out_path: Path) -> None:
    with sqlite3.connect(db_path) as src:
        with sqlite3.connect(out_path) as dst:
            src.backup(dst)


def _cleanup_retention(backup_dir: Path, retention_days: int) -> int:
    cutoff = datetime.now(timezone.utc) - timedelta(days=retention_days)
    removed = 0
    for file in backup_dir.glob("animal_lifecycle_*.sqlite"):
        mtime = datetime.fromtimestamp(file.stat().st_mtime, tz=timezone.utc)
        if mtime < cutoff:
            file.unlink(missing_ok=True)
            sha = file.with_suffix(file.suffix + ".sha256")
            sha.unlink(missing_ok=True)
            removed += 1
    return removed


def main() -> int:
    db_path = Path(_env("ANIMAL_DB_PATH", "animal_lifecycle.db")).resolve()
    backup_root = Path(
        _env("ANIMAL_BACKUP_DIR", str(Path.home() / "Google Drive" / "AnimalLifecycleBackups"))
    ).resolve()
    retention_days = int(_env("ANIMAL_BACKUP_RETENTION_DAYS", "30"))

    if not db_path.exists():
        print(f"ERRO: banco nao encontrado em {db_path}")
        return 1

    _ensure_path(backup_root)

    now = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_file = backup_root / f"animal_lifecycle_{now}.sqlite"

    try:
        _sqlite_backup(db_path, backup_file)
    except sqlite3.Error:
        shutil.copy2(db_path, backup_file)

    digest = _sha256(backup_file)
    (backup_file.with_suffix(backup_file.suffix + ".sha256")).write_text(
        f"{digest}  {backup_file.name}\n", encoding="utf-8"
    )

    removed = _cleanup_retention(backup_root, retention_days)
    print(f"OK: backup criado em {backup_file}")
    print(f"SHA256: {digest}")
    print(f"Retencao: {removed} arquivo(s) antigo(s) removido(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
