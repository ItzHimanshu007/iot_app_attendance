"""Device service — register, validate, and deactivate student devices.

Business rules enforced:
  1. One active device per student (partial unique index backs this up)
  2. New registration auto-deactivates the previous device
  3. Fingerprint mismatch blocks attendance
  4. Every device change is logged via notification
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from app.core.exceptions import (
    ConflictError,
    DeviceMismatchError,
    DeviceNotRegisteredError,
    NotFoundError,
    ValidationError,
)
from app.core.logging import get_logger
from app.repositories.device_repo import DeviceRepository
from app.services import notification_service

logger = get_logger(__name__)

_repo = DeviceRepository()


def register_device(
    user_id: str,
    android_id: str,
    device_model: str,
    device_fingerprint: str,
    device_manufacturer: str | None = None,
    os_version: str | None = None,
    app_version: str | None = None,
) -> dict[str, Any]:
    """Register a device for a student.

    If the student already has an active device, it is deactivated first.
    If the fingerprint is already registered to another user, registration is rejected.
    """
    # Check if fingerprint is already claimed by another user
    existing = _repo.get_by_fingerprint(device_fingerprint)
    if existing and existing["user_id"] != user_id:
        if existing.get("is_active", True):
            logger.warning(
                "Device fingerprint already registered to another active user",
                fingerprint_prefix=device_fingerprint[:8] + "...",
                owner_id=existing["user_id"],
                requester_id=user_id,
            )
            notification_service.send_security_alert(
                title="Duplicate Device Registration Attempt",
                body=f"User {user_id} attempted to register a device already owned by {existing['user_id']}",
                reference_type="user",
                reference_id=user_id,
            )
            raise ConflictError("This device is already registered to another account")
        else:
            # Delete old inactive record of another user to free the unique fingerprint constraint
            logger.info(
                "Deleting inactive device fingerprint record of another user to free unique constraint",
                fingerprint_prefix=device_fingerprint[:8] + "...",
                old_owner_id=existing["user_id"],
                new_user_id=user_id,
            )
            _repo.delete(existing["id"])
            existing = None


    # ── Same-user active path (re-registering active device) ──────────────────
    if existing and existing["user_id"] == user_id and existing.get("is_active", True):
        logger.info(
            "[DEVICE] Fingerprint already registered and active for this user — updating metadata",
            user_id=user_id,
            device_id=existing["id"],
            fingerprint_prefix=device_fingerprint[:8] + "...",
        )
        now = datetime.now(UTC).isoformat()
        update_data = {
            "android_id": android_id,
            "device_model": device_model,
            "device_manufacturer": device_manufacturer,
            "os_version": os_version,
            "app_version": app_version,
            "last_active_at": now,
        }
        record = _repo.update(existing["id"], update_data)
        notification_service.send_device_registered(user_id, device_model)
        return record

    # ── Same-user reactivation path ──────────────────────────────────────────
    # The fingerprint belongs to this user but was deactivated (e.g. by a prior
    # replacement).  Reactivate the existing row instead of inserting a new one
    # to avoid hitting the unique constraint on device_fingerprint.
    if existing and existing["user_id"] == user_id and not existing.get("is_active", True):
        logger.info(
            "[DEVICE] Found inactive fingerprint — reactivating existing device",
            user_id=user_id,
            device_id=existing["id"],
            fingerprint_prefix=device_fingerprint[:8] + "...",
        )
        record = _repo.reactivate(existing["id"])
        logger.info(
            "[DEVICE] Device reactivated successfully",
            user_id=user_id,
            device_id=record["id"],
            device_model=device_model,
        )
        notification_service.send_device_registered(user_id, device_model)
        return record

    # Deactivate any existing active device for this user
    current = _repo.get_active_by_user(user_id)
    if current:
        _repo.deactivate_user_devices(user_id, "replacement")
        notification_service.send_device_revoked(user_id, "replacement")
        logger.info(
            "Previous device deactivated",
            user_id=user_id,
            old_device_id=current["id"],
        )

    # Register the new device
    now = datetime.now(UTC).isoformat()
    data: dict[str, Any] = {
        "user_id": user_id,
        "android_id": android_id,
        "device_model": device_model,
        "device_fingerprint": device_fingerprint,
        "device_manufacturer": device_manufacturer,
        "os_version": os_version,
        "app_version": app_version,
        "is_active": True,
        "registered_at": now,
        "last_active_at": now,
    }
    record = _repo.insert(data)

    notification_service.send_device_registered(user_id, device_model)
    logger.info(
        "Device registered",
        user_id=user_id,
        device_id=record["id"],
        device_model=device_model,
    )
    return record


def validate_device(user_id: str, device_fingerprint: str) -> dict[str, Any]:
    """Validate that a device fingerprint matches the student's registered device.

    Also updates last_active_at.

    Raises:
        DeviceNotRegisteredError: No active device for this student.
        DeviceMismatchError: Fingerprint does not match.
    """
    device = _repo.get_active_by_user(user_id)

    if device is None:
        raise DeviceNotRegisteredError(user_id)

    if device["device_fingerprint"] != device_fingerprint:
        logger.warning(
            "Device mismatch detected",
            user_id=user_id,
            expected_prefix=device["device_fingerprint"][:8] + "...",
            received_prefix=device_fingerprint[:8] + "...",
        )
        raise DeviceMismatchError(user_id)

    # Touch last active
    _repo.touch_last_active(device["id"])
    return device


def deactivate_device(user_id: str, reason: str = "admin_revoke") -> None:
    """Deactivate a student's device (admin action).

    Raises:
        NotFoundError: No active device found.
    """
    device = _repo.get_active_by_user(user_id)
    if device is None:
        raise NotFoundError("RegisteredDevice", user_id)

    if reason not in ("replacement", "lost", "admin_revoke"):
        raise ValidationError(f"Invalid deactivation reason: {reason}")

    _repo.deactivate_user_devices(user_id, reason)
    notification_service.send_device_revoked(user_id, reason)
    logger.info(
        "Device deactivated",
        user_id=user_id,
        reason=reason,
        device_id=device["id"],
    )


def get_user_device(user_id: str) -> dict[str, Any] | None:
    """Get the active device for a user (or None)."""
    return _repo.get_active_by_user(user_id)


def get_device_history(user_id: str) -> list[dict[str, Any]]:
    """Get all devices (active + deactivated) for a user."""
    return _repo.get_history_by_user(user_id)
