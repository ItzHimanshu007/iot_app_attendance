"""Attendance record model — one row per student per session. Core evidence table."""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import (
    Boolean,
    DateTime,
    ForeignKey,
    SmallInteger,
    String,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import INET
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class AttendanceRecord(Base):
    """A verified attendance record for a student in a session."""

    __tablename__ = "attendance_records"
    __table_args__ = (
        UniqueConstraint("session_id", "student_id", name="uq_records_session_student"),
    )

    session_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("attendance_sessions.id"), nullable=False
    )
    student_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id"), nullable=False)
    beacon_token: Mapped[str] = mapped_column(String(64), nullable=False)
    ble_rssi: Mapped[int | None] = mapped_column(SmallInteger, nullable=True)
    biometric_verified: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    device_fingerprint: Mapped[str] = mapped_column(String(255), nullable=False)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="present")
    verification_method: Mapped[str] = mapped_column(
        String(30), nullable=False, default="ble_biometric"
    )
    marked_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    ip_address: Mapped[str | None] = mapped_column(INET, nullable=True)
    rejection_reason: Mapped[str | None] = mapped_column(String(100), nullable=True)
