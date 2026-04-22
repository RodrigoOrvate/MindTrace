from datetime import datetime, time

from sqlalchemy.orm import Session

from ..id_model import format_animal_id, next_rr_for_day
from ..models import Animal, AnimalEvent, EventType, LifeStatus
from ..schemas import AnimalCreate, AnimalEventCreate, EuthanasiaInput


def _actor_meta(actor_name: str, actor_username: str, actor_email: str | None = None) -> dict:
    return {
        "actor_name": actor_name,
        "actor_username": actor_username,
        "actor_email": actor_email,
    }


def create_animal(
    db: Session,
    lab_id: int,
    payload: AnimalCreate,
    *,
    actor_name: str,
    actor_username: str,
    actor_email: str | None = None,
) -> Animal:
    rr = payload.rr_override if payload.rr_override is not None else next_rr_for_day(db, payload.entry_date, payload.id_cc)
    internal_id = format_animal_id(payload.entry_date, payload.id_cc, rr)

    animal = Animal(
        lab_id=lab_id,
        internal_id=internal_id,
        external_id=payload.external_id,
        species_id=payload.species_id,
        strain_id=payload.strain_id,
        sex=payload.sex,
        birth_date=payload.birth_date,
        marking_date=payload.marking_date,
        entry_date=payload.entry_date,
        initial_weight_g=payload.initial_weight_g,
        notes=payload.notes,
        status=LifeStatus.ACTIVE,
    )
    db.add(animal)
    db.flush()

    db.add(
        AnimalEvent(
            animal_id=animal.id,
            event_type=EventType.ENTRY,
            event_at=datetime.combine(payload.entry_date, time(hour=12)),
            title="Entrada no laboratório",
            description=f"Cadastro inicial do animal {animal.internal_id}.",
            payload={
                "initial_weight_g": payload.initial_weight_g,
                "species_id": payload.species_id,
                "strain_id": payload.strain_id,
                **_actor_meta(actor_name, actor_username, actor_email),
            },
            source="app",
        )
    )
    return animal


def add_event(
    db: Session,
    animal: Animal,
    payload: AnimalEventCreate,
    *,
    actor_name: str,
    actor_username: str,
    actor_email: str | None = None,
) -> AnimalEvent:
    merged_payload = dict(payload.payload or {})
    merged_payload.update(_actor_meta(actor_name, actor_username, actor_email))
    event = AnimalEvent(
        animal_id=animal.id,
        event_type=payload.event_type,
        event_at=payload.event_at or datetime.utcnow(),
        title=payload.title,
        description=payload.description,
        payload=merged_payload,
        source=payload.source,
    )
    db.add(event)
    return event


def euthanize_animal(
    db: Session,
    animal: Animal,
    payload: EuthanasiaInput,
    *,
    actor_name: str,
    actor_username: str,
    actor_email: str | None = None,
) -> AnimalEvent:
    animal.status = LifeStatus.EUTHANIZED
    animal.euthanasia_date = payload.date
    animal.euthanasia_reason = payload.reason

    event = AnimalEvent(
        animal_id=animal.id,
        event_type=EventType.EUTHANASIA,
        event_at=datetime.combine(payload.date, time(hour=12)),
        title="Eutanasia",
        description=payload.notes or payload.reason,
        payload={"method": payload.method, "reason": payload.reason, **_actor_meta(actor_name, actor_username, actor_email)},
        source="app",
    )
    db.add(event)
    return event
