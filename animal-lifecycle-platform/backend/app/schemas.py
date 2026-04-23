from datetime import date, datetime, timezone
from typing import Annotated

from pydantic import BaseModel, Field
from pydantic.functional_serializers import PlainSerializer

# Serializa datetime naive (UTC sem tzinfo) como ISO 8601 com sufixo Z.
# Sem isso, o JavaScript interpreta a string sem fuso como horário local do dispositivo.
UTCDatetime = Annotated[
    datetime,
    PlainSerializer(
        lambda v: (v.replace(tzinfo=timezone.utc) if v.tzinfo is None else v).isoformat().replace("+00:00", "Z"),
        return_type=str,
    ),
]

from .models import EventType, LifeStatus, SexType


class SpeciesOut(BaseModel):
    id: int
    common_name: str
    scientific_name: str | None

    model_config = {"from_attributes": True}


class StrainOut(BaseModel):
    id: int
    species_id: int
    name: str
    source: str | None

    model_config = {"from_attributes": True}


class AnimalCreate(BaseModel):
    entry_date: date
    species_id: int
    strain_id: int
    sex: SexType = SexType.UNKNOWN
    birth_date: date | None = None
    marking_date: date | None = None
    initial_weight_g: float | None = None
    external_id: str | None = None
    notes: str | None = None
    id_cc: str = Field(min_length=2, max_length=2, description="Codigo da colônia")
    rr_override: int | None = Field(default=None, ge=1, le=99, description="Número do animal (1-99). Se omitido, gera automaticamente.")


class AnimalUpdate(BaseModel):
    species_id: int | None = None
    strain_id: int | None = None
    sex: SexType | None = None
    birth_date: date | None = None
    initial_weight_g: float | None = None
    external_id: str | None = None
    status: LifeStatus | None = None
    notes: str | None = None


class AnimalOut(BaseModel):
    id: int
    internal_id: str
    external_id: str | None
    species_id: int
    strain_id: int
    sex: SexType
    birth_date: date | None
    marking_date: date | None
    entry_date: date
    initial_weight_g: float | None
    status: LifeStatus
    euthanasia_date: date | None
    euthanasia_reason: str | None
    notes: str | None
    created_at: UTCDatetime

    model_config = {"from_attributes": True}


class AnimalEventCreate(BaseModel):
    event_type: EventType
    event_at: datetime | None = None
    title: str
    description: str | None = None
    payload: dict | None = None
    source: str = "manual"


class AnimalEventOut(BaseModel):
    id: int
    animal_id: int
    event_type: EventType
    event_at: UTCDatetime
    title: str
    description: str | None
    payload: dict | None
    source: str

    model_config = {"from_attributes": True}


class EuthanasiaInput(BaseModel):
    date: date
    reason: str
    method: str | None = None
    notes: str | None = None


class BulkEuthanasiaInput(BaseModel):
    entry_date: date
    euthanasia_date: date
    animal_ids: list[int] = Field(min_length=1)
    reason: str
    method: str | None = None
    notes: str | None = None


class BulkEuthanasiaResult(BaseModel):
    requested: int
    euthanized: int
    skipped: int
    details: list[str]


class ResearcherOut(BaseModel):
    username: str
    full_name: str

    model_config = {"from_attributes": True}


class ExperimentCreate(BaseModel):
    source: str = "manual"
    source_experiment_name: str | None = None
    source_path: str | None = None
    context: str | None = None
    apparatus: str | None = None
    responsible_username: str | None = None
    metadata: dict | None = None


class EnrollmentCreate(BaseModel):
    animal_id: int
    field_number: int | None = None
    day_number: int | None = None
    session_label: str | None = None
    payload: dict | None = None


class ExperimentOut(BaseModel):
    id: int
    source: str
    source_experiment_name: str | None
    source_path: str | None
    context: str | None
    apparatus: str | None
    responsible_username: str | None
    metadata: dict | None = Field(alias="meta_payload")

    model_config = {"from_attributes": True, "populate_by_name": True}


class EnrollmentOut(BaseModel):
    id: int
    experiment_id: int
    animal_id: int
    field_number: int | None
    day_number: int | None
    session_label: str | None
    payload: dict | None

    model_config = {"from_attributes": True}


class MindTraceImportInput(BaseModel):
    experiment_path: str
    context: str | None = None
    create_missing_animals: bool = False
    id_cc_default: str = "00"
    dry_run: bool = False


class MindTraceImportResult(BaseModel):
    imported_experiment_id: int | None
    sessions_found: int
    enrollments_created: int
    animals_linked: int
    missing_animals: list[str]
    warnings: list[str]


class MindTraceDeleteInput(BaseModel):
    experiment_name: str = Field(min_length=1)
    context: str | None = None
    source_path: str | None = None


class MindTraceDeleteResult(BaseModel):
    experiments_matched: int
    animals_notified: int
    notes_created: int
    warnings: list[str]


class LoginInput(BaseModel):
    username: str = Field(min_length=3, max_length=80)
    password: str = Field(min_length=6, max_length=120)


class LoginResult(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int
    username: str
    full_name: str
    email: str | None = None
    is_admin: bool


class UserCreateInput(BaseModel):
    full_name: str = Field(min_length=3, max_length=140)
    email: str | None = Field(default=None, max_length=160)
    username: str = Field(min_length=3, max_length=80)
    password: str = Field(min_length=8, max_length=120)
    is_admin: bool = False


class UserOut(BaseModel):
    id: int
    full_name: str
    email: str | None
    username: str
    is_admin: bool
    is_active: bool
    created_at: UTCDatetime

    model_config = {"from_attributes": True}


class UserPreferencesInput(BaseModel):
    theme: str | None = Field(default=None, pattern="^(light|dark)$")
    language: str | None = Field(default=None, pattern="^(pt|en|es)$")


class DateFormatInput(BaseModel):
    date_format: str = Field(pattern="^(DD/MM/YYYY|MM/DD/YYYY|YYYY-MM-DD)$")


class AuthSettingsOut(BaseModel):
    theme: str
    language: str
    date_format: str
    is_admin: bool
