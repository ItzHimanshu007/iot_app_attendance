"""Timetable model — maps teacher → subject → classroom → time slot."""

from __future__ import annotations

from datetime import date, time

from sqlalchemy import (
    Boolean,
    Date,
    ForeignKey,
    SmallInteger,
    String,
    Time,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class Timetable(Base):
    """A scheduled teaching slot linking teacher, subject, classroom, and time."""

    __tablename__ = "timetables"
    __table_args__ = (
        UniqueConstraint(
            "teacher_id",
            "subject_id",
            "classroom_id",
            "day_of_week",
            "start_time",
            "effective_from",
            name="uq_timetable_slot",
        ),
    )

    teacher_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id"), nullable=False)
    subject_id: Mapped[str] = mapped_column(String(36), ForeignKey("subjects.id"), nullable=False)
    classroom_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("classrooms.id"), nullable=False
    )
    day_of_week: Mapped[int] = mapped_column(SmallInteger, nullable=False)
    start_time: Mapped[time] = mapped_column(Time, nullable=False)
    end_time: Mapped[time] = mapped_column(Time, nullable=False)
    effective_from: Mapped[date] = mapped_column(Date, nullable=False)
    effective_until: Mapped[date | None] = mapped_column(Date, nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
