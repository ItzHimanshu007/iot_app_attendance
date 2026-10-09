"""Classroom model — physical locations where attendance sessions take place."""

from __future__ import annotations

from sqlalchemy import Boolean, SmallInteger, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class Classroom(Base):
    """A physical room/hall where attendance sessions take place."""

    __tablename__ = "classrooms"
    __table_args__ = (UniqueConstraint("name", "building", name="uq_classrooms_name_building"),)

    name: Mapped[str] = mapped_column(String(100), nullable=False)
    building: Mapped[str] = mapped_column(String(100), nullable=False)
    floor: Mapped[int] = mapped_column(SmallInteger, nullable=False, default=0)
    capacity: Mapped[int | None] = mapped_column(SmallInteger, nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
