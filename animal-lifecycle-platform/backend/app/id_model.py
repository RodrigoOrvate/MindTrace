import re
from datetime import date

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from .models import Animal


# Format: DDMMAAAA-CCRR  (ex: 21042026-A501 = rato 01 da caixa A5, entrou em 21/04/2026)
ID_PATTERN = re.compile(r"^(?P<date>\d{8})-(?P<cc>[A-Z0-9]{2})(?P<rr>\d{2})$")


def format_animal_id(entry_date: date, cc: str, rr: int) -> str:
    cc_norm = cc.strip().upper()
    if len(cc_norm) != 2 or not cc_norm.isalnum():
        raise ValueError("CC deve ter exatamente 2 caracteres alfanumericos.")
    if rr < 1 or rr > 99:
        raise ValueError("RR deve estar entre 01 e 99.")
    ddmmaaaa = entry_date.strftime("%d%m%Y")
    return f"{ddmmaaaa}-{cc_norm}{rr:02d}"


def parse_animal_id(raw: str) -> dict[str, str]:
    match = ID_PATTERN.match(raw.strip().upper())
    if not match:
        raise ValueError("Formato de ID invalido. Use DDMMAAAA-CCRR (ex: 21042026-A501).")
    return match.groupdict()


def next_rr_for_day(db: Session, entry_date: date, cc: str) -> int:
    ddmmaaaa = entry_date.strftime("%d%m%Y")
    prefix = f"{ddmmaaaa}-{cc.strip().upper()}"
    stmt = select(func.max(Animal.internal_id)).where(Animal.internal_id.like(f"{prefix}%"))
    current_max = db.execute(stmt).scalar_one_or_none()
    if not current_max:
        return 1
    parsed = parse_animal_id(current_max)
    next_rr = int(parsed["rr"]) + 1
    if next_rr > 99:
        raise ValueError(f"Limite diario atingido para prefixo {prefix} (99 animais).")
    return next_rr
