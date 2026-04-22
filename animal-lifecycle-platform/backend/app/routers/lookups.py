from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..db import get_db
from ..models import Species, Strain
from ..schemas import SpeciesOut, StrainOut
from ..security_auth import require_auth


router = APIRouter(prefix="/lookups", tags=["lookups"], dependencies=[Depends(require_auth)])


@router.get("/species", response_model=list[SpeciesOut])
def list_species(db: Session = Depends(get_db)) -> list[Species]:
    return list(db.execute(select(Species).order_by(Species.common_name)).scalars().all())


@router.get("/strains", response_model=list[StrainOut])
def list_strains(species_id: int | None = None, db: Session = Depends(get_db)) -> list[Strain]:
    stmt = select(Strain).order_by(Strain.name)
    if species_id is not None:
        stmt = stmt.where(Strain.species_id == species_id)
    return list(db.execute(stmt).scalars().all())
