from sqlalchemy import select
from sqlalchemy.orm import Session

from .config import settings
from .models import Lab, Species, Strain


def run_seed(db: Session) -> None:
    if not db.execute(select(Lab).limit(1)).scalar_one_or_none():
        db.add(Lab(name=settings.default_lab_name, code="MLB", country=settings.default_country))

    species_data = [
        ("Rato", "Rattus norvegicus"),
        ("Camundongo", "Mus musculus"),
    ]
    for common, sci in species_data:
        if not db.execute(select(Species).where(Species.common_name == common)).scalar_one_or_none():
            db.add(Species(common_name=common, scientific_name=sci))
    db.flush()

    rat = db.execute(select(Species).where(Species.common_name == "Rato")).scalar_one()
    mouse = db.execute(select(Species).where(Species.common_name == "Camundongo")).scalar_one()

    strains_data = [
        (rat.id, "Wistar"),
        (rat.id, "Sprague-Dawley"),
        (mouse.id, "C57BL/6"),
        (mouse.id, "BALB/c"),
    ]
    for species_id, strain_name in strains_data:
        exists = db.execute(select(Strain).where(Strain.species_id == species_id, Strain.name == strain_name)).scalar_one_or_none()
        if not exists:
            db.add(Strain(species_id=species_id, name=strain_name, source="pre-cadastro"))
