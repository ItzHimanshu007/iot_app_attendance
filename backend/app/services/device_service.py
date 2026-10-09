"""Device binding — one phone per staff member.

Rules:
  * The first registration binds the phone immediately.
  * Re-registering the same phone just refreshes its metadata.
  * A DIFFERENT phone is refused until an admin resets the device
    (prevents silently moving an account to a friend's phone).
  * A phone already bound to another active account is refused.
"""

from __future__ import annotations

import contextlib
from typing import Any

from app.core.config import get_settings
from app.core.exceptions import ConflictError, ValidationError, VerificationError
from app.core.timeutil import now_utc
from app.repositories.device_repo import DeviceRepository
from app.schemas.requests import DeviceRegister
from app.security.auth import CurrentStaff
from app.services.attempt_service import record_attempt

_repo = DeviceRepository()

_PUBLIC_FIELDS = (
    "id",
    "device_model",
    "device_manufacturer",
    "os_version",
    "app_version",
    "registered_at",
    "last_seen_at",
)


def public_device(row: dict[str, Any] | None) -> dict[str, Any] | None:
    """Device fields safe to return to the app."""
    if row is None:
        return None
    return {k: row.get(k) for k in _PUBLIC_FIELDS}


def register(staff: CurrentStaff, req: DeviceRegister, ip: str | None = None) -> dict[str, Any]:
    """Bind the caller's phone."""
    if get_settings().block_emulators and not req.is_physical_device:
        raise ValidationError("Emulators cannot be registered.", "EMULATOR_NOT_ALLOWED")

    now = now_utc().isoformat()
    meta = {
        "device_model": req.device_model,
        "device_manufacturer": req.device_manufacturer,
        "os_version": req.os_version,
        "app_version": req.app_version,
        "last_seen_at": now,
    }

    current = _repo.get_active_by_staff(staff.id)
    if current:
        if current["device_fingerprint"] == req.device_fingerprint:
            return public_device(_repo.update(current["id"], meta)) or {}
        record_attempt(
            staff.id,
            "device_register",
            False,
            "DEVICE_ALREADY_BOUND",
            "Tried to bind a second phone",
            device_fingerprint=req.device_fingerprint,
            ip_address=ip,
        )
        model = current.get("device_model") or "another phone"
        raise ConflictError(
            f"Your account is already bound to {model}. Ask an admin to reset your device "
            "if you changed phones.",
            code="DEVICE_ALREADY_BOUND",
        )

    owner = _repo.get_active_by_fingerprint(req.device_fingerprint)
    if owner and owner["staff_id"] != staff.id:
        record_attempt(
            staff.id,
            "device_register",
            False,
            "DEVICE_IN_USE",
            f"Phone already bound to staff {owner['staff_id']}",
            device_fingerprint=req.device_fingerprint,
            ip_address=ip,
        )
        raise ConflictError(
            "This phone is already registered to another staff account.", code="DEVICE_IN_USE"
        )

    row = _repo.insert(
        {
            "staff_id": staff.id,
            "device_fingerprint": req.device_fingerprint,
            "is_active": True,
            "registered_at": now,
            **meta,
        }
    )
    return public_device(row) or {}


def get_device(staff_id: str) -> dict[str, Any] | None:
    """The staff member's active device row."""
    return _repo.get_active_by_staff(staff_id)


def require_bound_device(staff_id: str, fingerprint: str) -> dict[str, Any]:
    """Ensure the request comes from the staff member's bound phone."""
    device = _repo.get_active_by_staff(staff_id)
    if device is None:
        raise VerificationError("Register this phone first.", "DEVICE_NOT_REGISTERED")
    if device["device_fingerprint"] != fingerprint:
        raise VerificationError(
            "This is not the phone registered to your account.", "DEVICE_MISMATCH"
        )
    return device


def touch(device_id: str) -> None:
    """Update last_seen_at (best effort)."""
    with contextlib.suppress(Exception):
        _repo.update(device_id, {"last_seen_at": now_utc().isoformat()})


def reset_for_staff(staff_id: str) -> int:
    """Admin: unbind every active phone of a staff member."""
    return len(_repo.deactivate_for_staff(staff_id, "admin_reset", now_utc().isoformat()))


def active_devices_by_staff() -> dict[str, dict[str, Any]]:
    """Map staff_id → active device (admin lists)."""
    return {d["staff_id"]: d for d in _repo.list_active()}
