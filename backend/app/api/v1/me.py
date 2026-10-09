"""Own profile, device binding, face enrollment, campus info."""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Request

from app.schemas.requests import DeviceRegister, FaceEnroll, MeUpdate
from app.security.auth import SignedInStaff, client_ip
from app.services import campus_service, device_service, face_service, staff_service

router = APIRouter(tags=["me"])


@router.get("/me")
async def get_me(staff: SignedInStaff) -> dict[str, Any]:
    """Profile + device + face status + onboarding next step."""
    return staff_service.me(staff)


@router.patch("/me")
async def patch_me(body: MeUpdate, staff: SignedInStaff) -> dict[str, Any]:
    """Update own profile."""
    return staff_service.update_me(staff, body)


@router.post("/devices/register")
async def register_device(
    body: DeviceRegister, staff: SignedInStaff, request: Request
) -> dict[str, Any]:
    """Bind this phone to the account."""
    return device_service.register(staff, body, client_ip(request))


@router.get("/devices/me")
async def my_device(staff: SignedInStaff) -> dict[str, Any] | None:
    """Currently bound phone (or null)."""
    return device_service.public_device(device_service.get_device(staff.id))


@router.post("/face/enroll")
async def enroll_face(body: FaceEnroll, staff: SignedInStaff, request: Request) -> dict[str, Any]:
    """Store live face signatures (pending admin approval)."""
    return face_service.enroll(staff, body, client_ip(request))


@router.get("/face/status")
async def face_status(staff: SignedInStaff) -> dict[str, Any] | None:
    """Enrollment status (never returns the signatures)."""
    return face_service.public_face(face_service.get_template(staff.id))


@router.get("/campus")
async def campus(staff: SignedInStaff) -> dict[str, Any]:
    """Campus settings shown in the app."""
    return campus_service.get_campus()
