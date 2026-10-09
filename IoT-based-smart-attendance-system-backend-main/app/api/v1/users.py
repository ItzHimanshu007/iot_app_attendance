"""Users router — profile management and device registration."""

from __future__ import annotations

from fastapi import APIRouter

from app.api.deps import AdminUser, AuthenticatedUser, StudentUser
from app.repositories.user_repo import UserRepository
from app.schemas.user import DeviceRegister, DeviceResponse, UserProfile
from app.services import device_service

router = APIRouter(prefix="/users", tags=["users"])

_user_repo = UserRepository()


@router.get("/me", response_model=UserProfile)
async def get_profile(user: AuthenticatedUser) -> dict:
    """Get the current user's profile."""
    data = _user_repo.get_by_id(user.id)
    return data


@router.post("/me/device", response_model=DeviceResponse, status_code=201)
async def register_device(body: DeviceRegister, user: StudentUser) -> dict:
    """Register the student's device for attendance verification.

    Automatically deactivates any previously registered device.
    """
    return device_service.register_device(
        user_id=user.id,
        android_id=body.android_id,
        device_model=body.device_model,
        device_fingerprint=body.device_fingerprint,
        device_manufacturer=body.device_manufacturer,
        os_version=body.os_version,
        app_version=body.app_version,
    )


@router.get("/me/device", response_model=DeviceResponse | None)
async def get_my_device(user: StudentUser) -> dict | None:
    """Get the current student's active registered device."""
    return device_service.get_user_device(user.id)


@router.delete("/{user_id}/device", status_code=204)
async def admin_revoke_device(user_id: str, user: AdminUser) -> None:
    """Admin: revoke a student's device registration."""
    device_service.deactivate_device(user_id, reason="admin_revoke")
