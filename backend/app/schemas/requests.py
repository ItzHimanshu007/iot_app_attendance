"""Request bodies for every endpoint."""

from __future__ import annotations

from datetime import date, time
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field

Fingerprint = Field(min_length=16, max_length=128)


# ── Profile ───────────────────────────────────────────────────────────────────


class MeUpdate(BaseModel):
    """Editable profile fields (name / employee ID only while pending)."""

    full_name: str | None = Field(None, min_length=2, max_length=120)
    employee_id: str | None = Field(None, min_length=1, max_length=40)
    department: str | None = Field(None, max_length=100)
    designation: str | None = Field(None, max_length=100)
    phone: str | None = Field(None, max_length=20)


# ── Device ────────────────────────────────────────────────────────────────────


class DeviceRegister(BaseModel):
    """Bind the current phone to the account."""

    device_fingerprint: str = Fingerprint
    device_model: str | None = Field(None, max_length=100)
    device_manufacturer: str | None = Field(None, max_length=100)
    os_version: str | None = Field(None, max_length=50)
    app_version: str | None = Field(None, max_length=30)
    is_physical_device: bool = True


# ── Face ──────────────────────────────────────────────────────────────────────


class FaceEnroll(BaseModel):
    """Face signatures captured live during onboarding."""

    embeddings: list[list[float]] = Field(min_length=1, max_length=10)
    model_version: str = Field(min_length=1, max_length=60)
    device_fingerprint: str = Fingerprint
    liveness_steps: list[str] = Field(default_factory=list, max_length=5)


# ── Attendance ────────────────────────────────────────────────────────────────


class BeaconReading(BaseModel):
    """What the phone decoded from the ESP32 advertisement."""

    beacon_id: UUID
    token: str = Field(pattern=r"^[0-9a-fA-F]{16}$")
    rssi: int = Field(ge=-127, le=20)


class LocationReading(BaseModel):
    """GPS fix taken during the attendance flow."""

    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    accuracy_m: float | None = Field(None, ge=0, le=100000)
    is_mocked: bool = False


Action = Literal["check_in", "check_out"]


class ChallengeRequest(BaseModel):
    """Step 1 — prove beacon proximity, receive liveness steps."""

    action: Action
    beacon: BeaconReading
    device_fingerprint: str = Fingerprint
    is_physical_device: bool = True


class SubmitRequest(BaseModel):
    """Step 2 — face signature + evidence."""

    challenge_id: UUID
    beacon: BeaconReading
    embedding: list[float] = Field(min_length=64, max_length=1024)
    completed_steps: list[str] = Field(max_length=5)
    device_fingerprint: str = Fingerprint
    location: LocationReading | None = None
    is_physical_device: bool = True
    # Face pipeline that produced the embedding; must match the enrolled template.
    model_version: str | None = Field(None, max_length=60)


# ── Admin ─────────────────────────────────────────────────────────────────────


class StaffStatusUpdate(BaseModel):
    """Enable / disable an account."""

    status: Literal["active", "disabled"]


class StaffRoleUpdate(BaseModel):
    """Promote / demote admin."""

    role: Literal["staff", "admin"]


class RejectFace(BaseModel):
    """Optional reason shown to the staff member."""

    reason: str | None = Field(None, max_length=200)


class ManualAttendance(BaseModel):
    """Admin override for one staff member on one day."""

    staff_id: UUID
    date: date
    status: Literal["present", "late", "absent", "on_leave"]
    reason: str = Field(min_length=3, max_length=300)
    check_in_time: time | None = None
    check_out_time: time | None = None


class BeaconCreate(BaseModel):
    """Register a new ESP32 beacon."""

    name: str = Field(min_length=2, max_length=60)
    location: str | None = Field(None, max_length=120)
    rssi_threshold: int = Field(-85, ge=-120, le=0)


class BeaconUpdate(BaseModel):
    """Edit a beacon."""

    name: str | None = Field(None, min_length=2, max_length=60)
    location: str | None = Field(None, max_length=120)
    rssi_threshold: int | None = Field(None, ge=-120, le=0)
    is_active: bool | None = None


class CampusUpdate(BaseModel):
    """Campus policy (any subset)."""

    campus_name: str | None = Field(None, min_length=2, max_length=100)
    timezone: str | None = Field(None, max_length=60)
    latitude: float | None = Field(None, ge=-90, le=90)
    longitude: float | None = Field(None, ge=-180, le=180)
    radius_m: int | None = Field(None, ge=50, le=20000)
    geofence_mode: Literal["off", "flag", "enforce"] | None = None
    max_location_accuracy_m: int | None = Field(None, ge=5, le=5000)
    work_start_time: time | None = None
    late_grace_minutes: int | None = Field(None, ge=0, le=240)
    face_match_threshold: float | None = Field(None, ge=0.3, le=0.95)
