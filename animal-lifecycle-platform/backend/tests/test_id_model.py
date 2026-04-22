from datetime import date

import pytest

from app.id_model import format_animal_id, parse_animal_id


def test_format_and_parse_round_trip() -> None:
    identifier = format_animal_id(date(2026, 4, 21), "cc", 7)
    assert identifier == "210426-CC07"
    parsed = parse_animal_id(identifier)
    assert parsed["date"] == "210426"
    assert parsed["cc"] == "CC"
    assert parsed["rr"] == "07"


def test_invalid_id_rejected() -> None:
    with pytest.raises(ValueError):
        parse_animal_id("21-04-26-CC07")


def test_rr_limits() -> None:
    with pytest.raises(ValueError):
        format_animal_id(date.today(), "AA", 0)
    with pytest.raises(ValueError):
        format_animal_id(date.today(), "AA", 100)
