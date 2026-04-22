from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from ..db import get_db
from ..models import Animal, AnimalEvent, AppUser, EventType, Lab, LifeStatus
from ..schemas import AnimalCreate, AnimalEventCreate, AnimalEventOut, AnimalOut, AnimalUpdate, EuthanasiaInput
from ..security_auth import require_auth
from ..services.animal_service import add_event, create_animal, euthanize_animal


router = APIRouter(prefix="/animals", tags=["animals"])


def _actor_name(user: AppUser) -> str:
    return user.full_name or user.username


def _actor_payload(user: AppUser) -> dict:
    return {
        "actor_name": _actor_name(user),
        "actor_username": user.username,
        "actor_email": user.email,
    }


@router.get("", response_model=list[AnimalOut])
def list_animals(
    q: str | None = Query(default=None),
    status: LifeStatus | None = Query(default=None),
    _user: AppUser = Depends(require_auth),
    db: Session = Depends(get_db),
) -> list[Animal]:
    stmt = select(Animal).order_by(Animal.created_at.desc())
    if q:
        stmt = stmt.where(or_(Animal.internal_id.ilike(f"%{q}%"), Animal.external_id.ilike(f"%{q}%")))
    if status:
        stmt = stmt.where(Animal.status == status)
    return list(db.execute(stmt).scalars().all())


@router.get("/{animal_id}", response_model=AnimalOut)
def get_animal(animal_id: int, _user: AppUser = Depends(require_auth), db: Session = Depends(get_db)) -> Animal:
    animal = db.get(Animal, animal_id)
    if not animal:
        raise HTTPException(status_code=404, detail="Animal nao encontrado.")
    return animal


@router.post("", response_model=AnimalOut)
def create_animal_endpoint(
    payload: AnimalCreate,
    current_user: AppUser = Depends(require_auth),
    db: Session = Depends(get_db),
) -> Animal:
    lab = db.execute(select(Lab).limit(1)).scalar_one_or_none()
    if not lab:
        raise HTTPException(status_code=500, detail="Laboratorio padrao nao configurado.")

    animal = create_animal(
        db,
        lab.id,
        payload,
        actor_name=_actor_name(current_user),
        actor_username=current_user.username,
        actor_email=current_user.email,
    )
    db.commit()
    db.refresh(animal)
    return animal


@router.patch("/{animal_id}", response_model=AnimalOut)
def update_animal(
    animal_id: int,
    payload: AnimalUpdate,
    current_user: AppUser = Depends(require_auth),
    db: Session = Depends(get_db),
) -> Animal:
    animal = db.get(Animal, animal_id)
    if not animal:
        raise HTTPException(status_code=404, detail="Animal nao encontrado.")

    changes = payload.model_dump(exclude_unset=True)
    if not changes:
        return animal

    for field, value in changes.items():
        setattr(animal, field, value)

    db.add(
        AnimalEvent(
            animal_id=animal.id,
            event_type=EventType.NOTE,
            event_at=datetime.utcnow(),
            title="Cadastro atualizado",
            description=f"Dados do animal atualizados por {_actor_name(current_user)}.",
            payload={
                "audit": True,
                "action": "update_animal",
                "changed_fields": sorted(changes.keys()),
                **_actor_payload(current_user),
            },
            source="app",
        )
    )

    db.commit()
    db.refresh(animal)
    return animal


@router.get("/{animal_id}/events", response_model=list[AnimalEventOut])
def list_events(animal_id: int, _user: AppUser = Depends(require_auth), db: Session = Depends(get_db)) -> list[AnimalEvent]:
    if not db.get(Animal, animal_id):
        raise HTTPException(status_code=404, detail="Animal nao encontrado.")
    stmt = select(AnimalEvent).where(AnimalEvent.animal_id == animal_id).order_by(AnimalEvent.event_at.asc())
    return list(db.execute(stmt).scalars().all())


@router.post("/{animal_id}/events", response_model=AnimalEventOut)
def add_event_endpoint(
    animal_id: int,
    payload: AnimalEventCreate,
    current_user: AppUser = Depends(require_auth),
    db: Session = Depends(get_db),
) -> AnimalEvent:
    animal = db.get(Animal, animal_id)
    if not animal:
        raise HTTPException(status_code=404, detail="Animal nao encontrado.")

    event = add_event(
        db,
        animal,
        payload,
        actor_name=_actor_name(current_user),
        actor_username=current_user.username,
        actor_email=current_user.email,
    )
    if payload.event_type == EventType.EUTHANASIA:
        animal.status = LifeStatus.EUTHANIZED
    db.commit()
    db.refresh(event)
    return event


@router.delete("/{animal_id}/events/{event_id}", status_code=204)
def delete_event(
    animal_id: int,
    event_id: int,
    current_user: AppUser = Depends(require_auth),
    db: Session = Depends(get_db),
) -> Response:
    animal = db.get(Animal, animal_id)
    if not animal:
        raise HTTPException(status_code=404, detail="Animal nao encontrado.")
    event = db.get(AnimalEvent, event_id)
    if not event or event.animal_id != animal_id:
        raise HTTPException(status_code=404, detail="Evento nao encontrado.")

    audit = AnimalEvent(
        animal_id=animal_id,
        event_type=EventType.NOTE,
        event_at=datetime.utcnow(),
        title="Registro excluido",
        description=(
            f'Excluido por {_actor_name(current_user)}: [{event.event_type}] "{event.title}" '
            f'registrado em {event.event_at.strftime("%d/%m/%Y %H:%M")}. '
        ),
        payload={
            "audit": True,
            "action": "delete",
            "deleted_event_id": event_id,
            "deleted_event_type": str(event.event_type),
            "deleted_event_title": event.title,
            **_actor_payload(current_user),
        },
        source="app",
    )
    db.add(audit)
    db.delete(event)
    db.commit()
    return Response(status_code=204)


@router.delete("/{animal_id}", status_code=204)
def delete_animal(animal_id: int, _user: AppUser = Depends(require_auth), db: Session = Depends(get_db)) -> Response:
    animal = db.get(Animal, animal_id)
    if not animal:
        raise HTTPException(status_code=404, detail="Animal nao encontrado.")
    db.delete(animal)
    db.commit()
    return Response(status_code=204)


@router.post("/{animal_id}/euthanasia", response_model=AnimalEventOut)
def euthanasia_endpoint(
    animal_id: int,
    payload: EuthanasiaInput,
    current_user: AppUser = Depends(require_auth),
    db: Session = Depends(get_db),
) -> AnimalEvent:
    animal = db.get(Animal, animal_id)
    if not animal:
        raise HTTPException(status_code=404, detail="Animal nao encontrado.")
    event = euthanize_animal(
        db,
        animal,
        payload,
        actor_name=_actor_name(current_user),
        actor_username=current_user.username,
        actor_email=current_user.email,
    )
    db.commit()
    db.refresh(event)
    return event
