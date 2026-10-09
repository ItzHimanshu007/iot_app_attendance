"""Attendance session model — time-bounded window created by teacher."""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, SmallInteger, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class AttendanceSession(Base):
    """A time-bounded attendance session for a subject in a classroom.

    subject_id  — populated for sessions created before migration 0002.
                  NULL for all sessions created after the migration.
    subject_name — free-text name typed by the teacher (migration 0002+).
                  NULL for all historical sessions; resolved at read-time
                  via the subjects table fallback.
    """

    __tablename__ = "attendance_sessions"

    timetable_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("timetables.id", ondelete="SET NULL"), nullable=True
    )
    teacher_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id"), nullable=False)
    # Nullable after migration 0002: new sessions leave this NULL and use
    # subject_name instead.  Historical sessions keep their original UUID.
    subject_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("subjects.id"), nullable=True
    )
    # Free-text subject name entered by the teacher (migration 0002+).
    # NULL for all historical rows that pre-date the migration.
    subject_name: Mapped[str | None] = mapped_column(Text, nullable=True)
    classroom_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("classrooms.id"), nullable=False
    )
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="active")
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    ended_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    duration_minutes: Mapped[int] = mapped_column(SmallInteger, nullable=False, default=60)
    current_token: Mapped[str | None] = mapped_column(String(64), nullable=True)
    token_rotated_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    total_present: Mapped[int] = mapped_column(SmallInteger, nullable=False, default=0)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
