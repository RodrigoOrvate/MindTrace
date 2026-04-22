from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..db import get_db
from ..models import Animal, AnimalEvent, EventType, Experiment, ExperimentEnrollment
from ..schemas import EnrollmentCreate, EnrollmentOut, ExperimentCreate, ExperimentOut
from ..security_auth import require_auth


router = APIRouter(prefix="/experiments", tags=["experiments"], dependencies=[Depends(require_auth)])


@router.get("", response_model=list[ExperimentOut])
def list_experiments(db: Session = Depends(get_db)) -> list[Experiment]:
    return list(db.execute(select(Experiment).order_by(Experiment.id.desc())).scalars().all())


@router.post("", response_model=ExperimentOut)
def create_experiment(payload: ExperimentCreate, db: Session = Depends(get_db)) -> Experiment:
    data = payload.model_dump()
    exp = Experiment(
        source=data["source"],
        source_experiment_name=data["source_experiment_name"],
        source_path=data["source_path"],
        context=data["context"],
        apparatus=data["apparatus"],
        meta_payload=data["metadata"],
    )
    db.add(exp)
    db.commit()
    db.refresh(exp)
    return exp


@router.post("/{experiment_id}/enrollments", response_model=EnrollmentOut)
def enroll_animal(experiment_id: int, payload: EnrollmentCreate, db: Session = Depends(get_db)) -> ExperimentEnrollment:
    exp = db.get(Experiment, experiment_id)
    if not exp:
        raise HTTPException(status_code=404, detail="Experimento não encontrado.")
    animal = db.get(Animal, payload.animal_id)
    if not animal:
        raise HTTPException(status_code=404, detail="Animal não encontrado.")

    enrollment = ExperimentEnrollment(experiment_id=experiment_id, **payload.model_dump())
    db.add(enrollment)
    db.flush()
    db.add(
        AnimalEvent(
            animal_id=animal.id,
            event_type=EventType.EXPERIMENT_ENROLLMENT,
            title=f"Inclusão no experimento #{exp.id}",
            description=exp.source_experiment_name or "Experimento manual",
            payload={
                "experiment_id": exp.id,
                "field_number": payload.field_number,
                "day_number": payload.day_number,
                "session_label": payload.session_label,
            },
            source=exp.source,
        )
    )
    db.commit()
    db.refresh(enrollment)
    return enrollment
