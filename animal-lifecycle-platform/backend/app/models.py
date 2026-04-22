from datetime import date, datetime
from enum import StrEnum

from sqlalchemy import JSON, Date, DateTime, Enum, Float, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .db import Base


class EventType(StrEnum):
    ENTRY = "entry"
    WEIGHT = "weight"
    HEALTH = "health"
    TRANSFER = "transfer"
    EXPERIMENT_ENROLLMENT = "experiment_enrollment"
    EXPERIMENT_SESSION = "experiment_session"
    EUTHANASIA = "euthanasia"
    NOTE = "note"


class SexType(StrEnum):
    MALE = "male"
    FEMALE = "female"
    UNKNOWN = "unknown"


class LifeStatus(StrEnum):
    ACTIVE = "active"
    EUTHANIZED = "euthanized"
    DECEASED = "deceased"
    ARCHIVED = "archived"


class Lab(Base):
    __tablename__ = "labs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    name: Mapped[str] = mapped_column(String(120), unique=True, index=True)
    code: Mapped[str] = mapped_column(String(12), unique=True, index=True)
    country: Mapped[str] = mapped_column(String(3), default="BR")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class AppUser(Base):
    __tablename__ = "app_users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    full_name: Mapped[str] = mapped_column(String(140), default="Usuário")
    email: Mapped[str | None] = mapped_column(String(160), nullable=True, index=True)
    username: Mapped[str] = mapped_column(String(80), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    is_admin: Mapped[bool] = mapped_column(default=False)
    is_active: Mapped[bool] = mapped_column(default=True)
    failed_login_count: Mapped[int] = mapped_column(Integer, default=0)
    locked_until: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    last_login_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class Species(Base):
    __tablename__ = "species"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    common_name: Mapped[str] = mapped_column(String(80), unique=True, index=True)
    scientific_name: Mapped[str | None] = mapped_column(String(120), nullable=True)
    default_enabled: Mapped[bool] = mapped_column(default=True)


class Strain(Base):
    __tablename__ = "strains"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    species_id: Mapped[int] = mapped_column(ForeignKey("species.id"), index=True)
    name: Mapped[str] = mapped_column(String(120), index=True)
    source: Mapped[str | None] = mapped_column(String(120), nullable=True)
    default_enabled: Mapped[bool] = mapped_column(default=True)

    species: Mapped["Species"] = relationship()
    __table_args__ = (UniqueConstraint("species_id", "name", name="uq_species_strain"),)


class Animal(Base):
    __tablename__ = "animals"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    lab_id: Mapped[int] = mapped_column(ForeignKey("labs.id"), index=True)
    internal_id: Mapped[str] = mapped_column(String(40), unique=True, index=True)
    external_id: Mapped[str | None] = mapped_column(String(60), nullable=True, index=True)
    species_id: Mapped[int] = mapped_column(ForeignKey("species.id"), index=True)
    strain_id: Mapped[int] = mapped_column(ForeignKey("strains.id"), index=True)
    sex: Mapped[SexType] = mapped_column(Enum(SexType), default=SexType.UNKNOWN)
    birth_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    marking_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    entry_date: Mapped[date] = mapped_column(Date, index=True)
    initial_weight_g: Mapped[float | None] = mapped_column(Float, nullable=True)
    status: Mapped[LifeStatus] = mapped_column(Enum(LifeStatus), default=LifeStatus.ACTIVE)
    euthanasia_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    euthanasia_reason: Mapped[str | None] = mapped_column(Text, nullable=True)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    lab: Mapped["Lab"] = relationship()
    species: Mapped["Species"] = relationship()
    strain: Mapped["Strain"] = relationship()
    events: Mapped[list["AnimalEvent"]] = relationship(back_populates="animal", cascade="all, delete-orphan")


class Experiment(Base):
    __tablename__ = "experiments"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    source: Mapped[str] = mapped_column(String(40), default="manual")
    source_experiment_name: Mapped[str | None] = mapped_column(String(200), nullable=True)
    source_path: Mapped[str | None] = mapped_column(String(500), nullable=True)
    context: Mapped[str | None] = mapped_column(String(120), nullable=True)
    apparatus: Mapped[str | None] = mapped_column(String(80), nullable=True)
    started_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    ended_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    meta_payload: Mapped[dict | None] = mapped_column("metadata", JSON, nullable=True)

    enrollments: Mapped[list["ExperimentEnrollment"]] = relationship(back_populates="experiment", cascade="all, delete-orphan")


class ExperimentEnrollment(Base):
    __tablename__ = "experiment_enrollments"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    experiment_id: Mapped[int] = mapped_column(ForeignKey("experiments.id"), index=True)
    animal_id: Mapped[int] = mapped_column(ForeignKey("animals.id"), index=True)
    field_number: Mapped[int | None] = mapped_column(Integer, nullable=True)
    day_number: Mapped[int | None] = mapped_column(Integer, nullable=True)
    session_label: Mapped[str | None] = mapped_column(String(80), nullable=True)
    payload: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    experiment: Mapped["Experiment"] = relationship(back_populates="enrollments")
    animal: Mapped["Animal"] = relationship()
    __table_args__ = (UniqueConstraint("experiment_id", "animal_id", "field_number", "day_number", name="uq_exp_animal_field_day"),)


class AnimalEvent(Base):
    __tablename__ = "animal_events"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    animal_id: Mapped[int] = mapped_column(ForeignKey("animals.id"), index=True)
    event_type: Mapped[EventType] = mapped_column(Enum(EventType), index=True)
    event_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, index=True)
    title: Mapped[str] = mapped_column(String(180))
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    payload: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    source: Mapped[str] = mapped_column(String(40), default="manual")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    animal: Mapped["Animal"] = relationship(back_populates="events")
