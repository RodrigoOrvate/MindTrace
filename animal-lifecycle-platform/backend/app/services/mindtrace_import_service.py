import json
from datetime import datetime
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..id_model import format_animal_id, next_rr_for_day
from ..models import Animal, AnimalEvent, EventType, Experiment, ExperimentEnrollment, Lab, LifeStatus
from ..schemas import MindTraceDeleteInput, MindTraceDeleteResult, MindTraceImportInput, MindTraceImportResult


def _load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _find_animal(db: Session, raw_name: str) -> Animal | None:
    raw_name = raw_name.strip()
    if not raw_name:
        return None
    by_internal = db.execute(select(Animal).where(Animal.internal_id == raw_name)).scalar_one_or_none()
    if by_internal:
        return by_internal
    return db.execute(select(Animal).where(Animal.external_id == raw_name)).scalar_one_or_none()


def _create_stub_animal(db: Session, lab_id: int, raw_name: str, id_cc_default: str) -> Animal:
    today = datetime.utcnow().date()
    rr = next_rr_for_day(db, today, id_cc_default)
    internal_id = format_animal_id(today, id_cc_default, rr)
    animal = Animal(
        lab_id=lab_id,
        internal_id=internal_id,
        external_id=raw_name,
        species_id=1,
        strain_id=1,
        entry_date=today,
        status=LifeStatus.ACTIVE,
        notes="Criado automaticamente durante importacao do MindTrace.",
    )
    db.add(animal)
    db.flush()
    db.add(
        AnimalEvent(
            animal_id=animal.id,
            event_type=EventType.ENTRY,
            title="Entrada automática (importação MindTrace)",
            description=f"Stub criado para vincular '{raw_name}'.",
            payload={"external_name": raw_name},
            source="mindtrace",
        )
    )
    return animal


def import_mindtrace_folder(db: Session, data: MindTraceImportInput) -> MindTraceImportResult:
    exp_path = Path(data.experiment_path).resolve(strict=False)
    meta_path = exp_path / "metadata.json"
    sessions_dir = exp_path / "sessions"

    warnings: list[str] = []
    missing_animals: list[str] = []

    if not meta_path.exists():
        raise FileNotFoundError(f"metadata.json não encontrado em {exp_path}")
    if not sessions_dir.exists():
        warnings.append("Pasta sessions/ ausente. Apenas metadados do experimento foram importados.")

    meta = _load_json(meta_path)
    session_files = sorted(sessions_dir.glob("session_*.json")) if sessions_dir.exists() else []

    lab = db.execute(select(Lab).limit(1)).scalar_one()
    experiment = Experiment(
        source="mindtrace",
        source_experiment_name=meta.get("name") or exp_path.name,
        source_path=str(exp_path),
        context=data.context or meta.get("context"),
        apparatus=meta.get("aparato"),
        meta_payload=meta,
    )
    db.add(experiment)
    db.flush()

    enrollments_created = 0
    animals_linked = 0

    for session_file in session_files:
        session_data = _load_json(session_file)
        campos = session_data.get("campos", [])
        if not campos and session_data.get("animal"):
            campos = [{"animal": session_data.get("animal"), "campo": 1}]

        for campo in campos:
            animal_name = str(campo.get("animal", "")).strip()
            if not animal_name:
                continue

            animal = _find_animal(db, animal_name)
            if not animal:
                if data.create_missing_animals:
                    animal = _create_stub_animal(db, lab.id, animal_name, data.id_cc_default)
                else:
                    missing_animals.append(animal_name)
                    continue

            animals_linked += 1
            enrollment = ExperimentEnrollment(
                experiment_id=experiment.id,
                animal_id=animal.id,
                field_number=campo.get("campo"),
                day_number=int(session_data.get("dia")) if str(session_data.get("dia", "")).isdigit() else None,
                session_label=session_data.get("fase"),
                payload={
                    "session_file": session_file.name,
                    "raw": session_data,
                    "campo": campo,
                },
            )
            db.add(enrollment)
            enrollments_created += 1

            db.add(
                AnimalEvent(
                    animal_id=animal.id,
                    event_type=EventType.EXPERIMENT_SESSION,
                    event_at=datetime.utcnow(),
                    title=f"Sessão MindTrace ({meta.get('aparato', 'experimento')})",
                    description=f"{session_data.get('fase', 'Sessão')} - dia {session_data.get('dia', '?')}",
                    payload={
                        "experiment_id": experiment.id,
                        "experiment_name": meta.get("name"),
                        "session_file": session_file.name,
                        "campo": campo.get("campo"),
                    },
                    source="mindtrace",
                )
            )

    if data.dry_run:
        db.rollback()
        return MindTraceImportResult(
            imported_experiment_id=None,
            sessions_found=len(session_files),
            enrollments_created=enrollments_created,
            animals_linked=animals_linked,
            missing_animals=sorted(set(missing_animals)),
            warnings=warnings + ["Execução em dry_run. Nenhum dado foi salvo."],
        )

    return MindTraceImportResult(
        imported_experiment_id=experiment.id,
        sessions_found=len(session_files),
        enrollments_created=enrollments_created,
        animals_linked=animals_linked,
        missing_animals=sorted(set(missing_animals)),
        warnings=warnings,
    )


def mark_experiment_deleted(db: Session, data: MindTraceDeleteInput) -> MindTraceDeleteResult:
    exp_name = data.experiment_name.strip()
    warnings: list[str] = []
    if not exp_name:
        return MindTraceDeleteResult(
            experiments_matched=0,
            animals_notified=0,
            notes_created=0,
            warnings=["experiment_name vazio."],
        )

    stmt = select(Experiment).where(
        Experiment.source == "mindtrace",
        Experiment.source_experiment_name == exp_name,
    )
    if data.context and data.context.strip():
        stmt = stmt.where(Experiment.context == data.context.strip())
    if data.source_path and data.source_path.strip():
        stmt = stmt.where(Experiment.source_path == data.source_path.strip())

    experiments = list(db.execute(stmt).scalars().all())
    if not experiments:
        warnings.append("Nenhum experimento MindTrace correspondente foi encontrado para auditoria.")
        return MindTraceDeleteResult(
            experiments_matched=0,
            animals_notified=0,
            notes_created=0,
            warnings=warnings,
        )

    exp_ids = [exp.id for exp in experiments]
    enrollment_rows = db.execute(
        select(ExperimentEnrollment.animal_id).where(ExperimentEnrollment.experiment_id.in_(exp_ids))
    ).all()
    animal_ids = sorted({int(row[0]) for row in enrollment_rows if row and row[0] is not None})

    if not animal_ids:
        warnings.append("Experimento encontrado, mas sem animais vinculados.")
        return MindTraceDeleteResult(
            experiments_matched=len(experiments),
            animals_notified=0,
            notes_created=0,
            warnings=warnings,
        )

    now = datetime.utcnow()
    notes_created = 0
    for animal_id in animal_ids:
        note = AnimalEvent(
            animal_id=animal_id,
            event_type=EventType.NOTE,
            event_at=now,
            title="Experimento excluído",
            description=(
                f'Excluído no MindTrace: experimento "{exp_name}"'
                + (f" (contexto: {data.context.strip()})" if data.context and data.context.strip() else "")
                + "."
            ),
            payload={
                "audit": True,
                "action": "experiment_deleted",
                "experiment_name": exp_name,
                "context": data.context.strip() if data.context else None,
                "matched_experiment_ids": exp_ids,
            },
            source="mindtrace",
        )
        db.add(note)
        notes_created += 1

    return MindTraceDeleteResult(
        experiments_matched=len(experiments),
        animals_notified=len(animal_ids),
        notes_created=notes_created,
        warnings=warnings,
    )
