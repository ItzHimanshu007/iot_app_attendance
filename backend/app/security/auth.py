"""Authentication & role dependencies for FastAPI routes.

get_current_staff   any signed-in user that has a staff profile
                    (pending users need this for onboarding)
require_active      approved staff (status = active)
require_admin       active staff with role = admin
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Annotated, Any

from fastapi import Depends, Request

from app.core.exceptions import AuthenticationError, AuthorizationError
from app.core.logging import user_id_ctx, user_role_ctx
from app.repositories.staff_repo import StaffRepository
from app.security.jwt_handler import decode_jwt

_staff_repo = StaffRepository()


@dataclass
class CurrentStaff:
    """The authenticated staff member for this request."""

    id: str
    email: str
    full_name: str
    role: str
    status: str
    employee_id: str | None
    department: str | None
    row: dict[str, Any]

    @property
    def is_admin(self) -> bool:
        return self.role == "admin"


def _bearer(request: Request) -> str:
    header = request.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        raise AuthenticationError("Missing or malformed Authorization header")
    return header[7:].strip()


async def get_current_staff(request: Request) -> CurrentStaff:
    """Verify the JWT and load the staff profile."""
    payload = decode_jwt(_bearer(request))
    row = _staff_repo.get_by_id(payload.sub)
    if row is None:
        raise AuthorizationError(
            "No staff profile exists for this account. Run the database migration "
            "(it creates profiles automatically on sign-up).",
            code="PROFILE_MISSING",
        )
    user_id_ctx.set(row["id"])
    user_role_ctx.set(row["role"])
    return CurrentStaff(
        id=row["id"],
        email=row["email"],
        full_name=row["full_name"],
        role=row["role"],
        status=row["status"],
        employee_id=row.get("employee_id"),
        department=row.get("department"),
        row=row,
    )


async def require_active(staff: CurrentStaff = Depends(get_current_staff)) -> CurrentStaff:
    """Only approved staff may mark attendance."""
    if staff.status == "disabled":
        raise AuthorizationError("Your account has been disabled.", code="ACCOUNT_DISABLED")
    if staff.status != "active":
        raise AuthorizationError(
            "Your account is waiting for admin approval.", code="ACCOUNT_PENDING"
        )
    return staff


async def require_admin(staff: CurrentStaff = Depends(require_active)) -> CurrentStaff:
    """Admin-only routes."""
    if not staff.is_admin:
        raise AuthorizationError("Admin access required")
    return staff


SignedInStaff = Annotated[CurrentStaff, Depends(get_current_staff)]
ActiveStaff = Annotated[CurrentStaff, Depends(require_active)]
AdminStaff = Annotated[CurrentStaff, Depends(require_admin)]


def client_ip(request: Request) -> str | None:
    """Best-effort client IP (Render/other proxies set X-Forwarded-For)."""
    forwarded = request.headers.get("X-Forwarded-For")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else None
