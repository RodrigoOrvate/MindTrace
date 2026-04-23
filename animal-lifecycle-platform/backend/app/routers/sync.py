from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from ..db import get_db
from ..models import Animal, AppUser, LifeStatus
from ..schemas import (
    AnimalOut,
    MindTraceDeleteInput,
    MindTraceDeleteResult,
    MindTraceImportInput,
    MindTraceImportResult,
    ResearcherOut,
)
from ..security_sync import ensure_safe_experiment_path, verify_loopback_client, verify_sync_signature
from ..services.mindtrace_import_service import import_mindtrace_folder, mark_experiment_deleted


router = APIRouter(prefix="/sync", tags=["sync"])


@router.get("/mindtrace/researchers", response_model=list[ResearcherOut])
async def sync_mindtrace_researchers(request: Request, db: Session = Depends(get_db)) -> list[AppUser]:
    verify_loopback_client(request.client.host if request.client else None)
    verify_sync_signature(
        body=b"",
        timestamp_header=request.headers.get("X-MindTrace-Timestamp"),
        signature_header=request.headers.get("X-MindTrace-Signature"),
    )
    return list(
        db.execute(
            select(AppUser)
            .where(AppUser.is_admin == False)  # noqa: E712
            .where(or_(AppUser.is_active == True, AppUser.is_active.is_(None)))  # noqa: E712
            .order_by(AppUser.full_name.asc())
        ).scalars().all()
    )


@router.get("/mindtrace/animals", response_model=list[AnimalOut])
async def sync_mindtrace_animals(
    request: Request,
    q: str | None = Query(default=None),
    status: LifeStatus = Query(default=LifeStatus.ACTIVE),
    db: Session = Depends(get_db),
) -> list[Animal]:
    verify_loopback_client(request.client.host if request.client else None)
    verify_sync_signature(
        body=b"",
        timestamp_header=request.headers.get("X-MindTrace-Timestamp"),
        signature_header=request.headers.get("X-MindTrace-Signature"),
    )

    stmt = select(Animal).order_by(Animal.created_at.desc())
    if q:
        stmt = stmt.where(or_(Animal.internal_id.ilike(f"%{q}%"), Animal.external_id.ilike(f"%{q}%")))
    if status:
        stmt = stmt.where(Animal.status == status)
    return list(db.execute(stmt).scalars().all())


@router.post("/mindtrace/import-folder", response_model=MindTraceImportResult)
async def sync_mindtrace(request: Request, db: Session = Depends(get_db)) -> MindTraceImportResult:
    verify_loopback_client(request.client.host if request.client else None)
    raw_body = await request.body()
    verify_sync_signature(
        body=raw_body,
        timestamp_header=request.headers.get("X-MindTrace-Timestamp"),
        signature_header=request.headers.get("X-MindTrace-Signature"),
    )

    try:
        payload = MindTraceImportInput.model_validate_json(raw_body)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"Payload invalido: {exc}") from exc

    safe_path = ensure_safe_experiment_path(payload.experiment_path)
    payload = payload.model_copy(update={"experiment_path": str(safe_path)})

    try:
        result = import_mindtrace_folder(db, payload)
        if not payload.dry_run:
            db.commit()
        return result
    except FileNotFoundError as exc:
        db.rollback()
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except Exception as exc:
        db.rollback()
        raise HTTPException(status_code=400, detail=f"Falha na importacao: {exc}") from exc


@router.post("/mindtrace/experiment-deleted", response_model=MindTraceDeleteResult)
async def sync_mindtrace_experiment_deleted(request: Request, db: Session = Depends(get_db)) -> MindTraceDeleteResult:
    verify_loopback_client(request.client.host if request.client else None)
    raw_body = await request.body()
    verify_sync_signature(
        body=raw_body,
        timestamp_header=request.headers.get("X-MindTrace-Timestamp"),
        signature_header=request.headers.get("X-MindTrace-Signature"),
    )

    try:
        payload = MindTraceDeleteInput.model_validate_json(raw_body)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"Payload invalido: {exc}") from exc

    if payload.source_path:
        safe_path = ensure_safe_experiment_path(payload.source_path)
        payload = payload.model_copy(update={"source_path": str(safe_path)})

    try:
        result = mark_experiment_deleted(db, payload)
        db.commit()
        return result
    except Exception as exc:
        db.rollback()
        raise HTTPException(status_code=400, detail=f"Falha ao registrar exclusao: {exc}") from exc
