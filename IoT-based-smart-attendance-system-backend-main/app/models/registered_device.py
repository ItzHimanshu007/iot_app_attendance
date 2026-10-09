"""Registered device model — hardware-lock: one active device per student."""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Index, String
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class RegisteredDevice(Base):
    """A registered Android device locked to a student account."""

    __tablename__ = "registered_devices"
    __table_args__ = (
        # One active device per user — partial unique index
        Index(
            "idx_one_active_device_per_user",
            "user_id",
            unique=True,
            postgresql_where="is_active = TRUE",
        ),
    )

    user_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    android_id: Mapped[str] = mapped_column(String(64), nullable=False)
    device_model: Mapped[str] = mapped_column(String(255), nullable=False)
    device_manufacturer: Mapped[str | None] = mapped_column(String(100), nullable=True)
    device_fingerprint: Mapped[str] = mapped_column(String(255), unique=True, nullable=False)
    os_version: Mapped[str | None] = mapped_column(String(50), nullable=True)
    app_version: Mapped[str | None] = mapped_column(String(20), nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    registered_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    last_active_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    deactivated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    deactivation_reason: Mapped[str | None] = mapped_column(String(50), nullable=True)
