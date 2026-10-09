"""The signed-in staff member's own profile and onboarding state."""

from __future__ import annotations

from typing import Any

from app.core.exceptions import ConflictError, ValidationError
from app.repositories.staff_repo import StaffRepository
from app.schemas.requests import MeUpdate
from app.security.auth import CurrentStaff
from app.services import device_service, face_service

_repo = StaffRepository()

_PROFILE_FIELDS = (
    "id",
    "email",
    "full_name",
    "employee_id",
    "department",
    "designation",
    "phone",
    "role",
    "status",
    "approved_at",
    "created_at",
)


def public_profile(row: dict[str, Any]) -> dict[str, Any]:
    """Profile fields safe to return."""
    return {k: row.get(k) for k in _PROFILE_FIELDS}


def next_step(status: str, device: Any, face: dict[str, Any] | None) -> str:
    """What the app should show next."""
    if status == "disabled":
        return "disabled"
    if device is None:
        return "register_device"
    if face is None or face.get("status") == "rejected":
        return "enroll_face"
    if status != "active" or face.get("status") != "approved":
        return "await_approval"
    return "ready"


def me(staff: CurrentStaff) -> dict[str, Any]:
    """Profile + device + face + onboarding state."""
    device = device_service.get_device(staff.id)
    face = face_service.get_template(staff.id)
    step = next_step(staff.status, device, face)
    return {
        "profile": public_profile(staff.row),
        "device": device_service.public_device(device),
        "face": face_service.public_face(face),
        "onboarding": {
            "device_registered": device is not None,
            "face_enrolled": face is not None and face.get("status") != "rejected",
            "face_status": face.get("status") if face else None,
            "approved": staff.status == "active",
            "next_step": step,
        },
    }


def update_me(staff: CurrentStaff, req: MeUpdate) -> dict[str, Any]:
    """Update own profile."""
    data = req.model_dump(exclude_none=True)
    locked = {"full_name", "employee_id"} & data.keys()
    if locked and staff.status != "pending":
        raise ValidationError(
            "Name and employee ID can only be changed by an admin after approval.",
            "PROFILE_LOCKED",
        )
    if not data:
        return public_profile(staff.row)
    try:
        row = _repo.update(staff.id, data)
    except ConflictError as e:
        raise ConflictError("That employee ID is already registered.", "EMPLOYEE_ID_TAKEN") from e
    return public_profile(row)
