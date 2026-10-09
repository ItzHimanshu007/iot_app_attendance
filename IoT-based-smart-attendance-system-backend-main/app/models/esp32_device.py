"""ESP32 device model — registry of BLE broadcaster hardware in classrooms."""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, SmallInteger, String
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class Esp32Device(Base):
    """An ESP32 BLE broadcaster deployed in a classroom."""

    __tablename__ = "esp32_devices"

    mac_address: Mapped[str] = mapped_column(String(17), unique=True, nullable=False)
    classroom_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("classrooms.id"), nullable=False
    )
    label: Mapped[str | None] = mapped_column(String(100), nullable=True)
    firmware_version: Mapped[str | None] = mapped_column(String(20), nullable=True)
    mqtt_client_id: Mapped[str] = mapped_column(String(100), unique=True, nullable=False)
    last_heartbeat_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    wifi_rssi: Mapped[int | None] = mapped_column(SmallInteger, nullable=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="offline")
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
