"""User schemas — profile and device lock DTOs."""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel


class UserProfile(BaseModel):
    """Response body for user profile."""

    id: str
    email: str
    full_name: str
    role: str
    department: str | None = None
    student_id_number: str | None = None
    phone: str | None = None
    is_active: bool
    created_at: datetime


class DeviceRegister(BaseModel):
    """Request body for device fingerprint registration."""

    android_id: str
    device_model: str
    device_manufacturer: str | None = None
    device_fingerprint: str
    os_version: str | None = None
    app_version: str | None = None


class DeviceResponse(BaseModel):
    """Response body for a registered device."""

    id: str
    user_id: str
    device_model: str
    device_fingerprint: str
    is_active: bool
    registered_at: datetime
    last_active_at: datetime | None = None
