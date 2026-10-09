"""Role-Based Access Control — reusable FastAPI dependencies.

Usage in routers:
    @router.post("/", dependencies=[Depends(require_teacher)])
    async def create_session(user: CurrentUser = Depends(get_current_user)):
        ...
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Annotated

from fastapi import Depends, Request

from app.core.exceptions import AuthenticationError, AuthorizationError
from app.core.logging import get_logger, user_id_ctx, user_role_ctx
from app.repositories.user_repo import UserRepository
from app.security.jwt_handler import JWTPayload, decode_jwt

logger = get_logger(__name__)


@dataclass
class CurrentUser:
    """Authenticated user context available to all protected routes."""

    id: str
    email: str
    full_name: str
    role: str
    department: str | None
    is_active: bool


def _extract_token(request: Request) -> str:
    """Extract the Bearer token from the Authorization header."""
    auth_header = request.headers.get("Authorization", "")
    if not auth_header.startswith("Bearer "):
        raise AuthenticationError("Missing or malformed Authorization header")
    return auth_header[7:]


async def get_jwt_payload(request: Request) -> JWTPayload:
    """Dependency: decode and verify the JWT from the request."""
    token = _extract_token(request)
    return decode_jwt(token)


async def get_current_user(
    payload: JWTPayload = Depends(get_jwt_payload),
) -> CurrentUser:
    """Dependency: resolve the JWT subject to a full user profile.

    Also sets logging context vars for request correlation.
    """
    repo = UserRepository()
    user_data = repo.get_by_id(payload.sub)

    if user_data is None:
        raise AuthenticationError("User account not found")

    if not user_data.get("is_active", False):
        raise AuthenticationError("User account is deactivated")

    # Set logging context for this request
    user_id_ctx.set(user_data["id"])
    user_role_ctx.set(user_data["role"])

    return CurrentUser(
        id=user_data["id"],
        email=user_data["email"],
        full_name=user_data["full_name"],
        role=user_data["role"],
        department=user_data.get("department"),
        is_active=user_data["is_active"],
    )


# ── Role-restricted dependencies ──────────────────────────────────────────────


async def require_admin(
    user: CurrentUser = Depends(get_current_user),
) -> CurrentUser:
    """Dependency: require admin role."""
    if user.role != "admin":
        raise AuthorizationError("Admin access required")
    return user


async def require_teacher(
    user: CurrentUser = Depends(get_current_user),
) -> CurrentUser:
    """Dependency: require teacher role."""
    if user.role not in ("teacher", "admin"):
        raise AuthorizationError("Teacher access required")
    return user


async def require_student(
    user: CurrentUser = Depends(get_current_user),
) -> CurrentUser:
    """Dependency: require student role."""
    if user.role != "student":
        raise AuthorizationError("Student access required")
    return user


async def require_teacher_or_admin(
    user: CurrentUser = Depends(get_current_user),
) -> CurrentUser:
    """Dependency: require teacher or admin role."""
    if user.role not in ("teacher", "admin"):
        raise AuthorizationError("Teacher or admin access required")
    return user


# ── Type aliases for router signatures ────────────────────────────────────────

AuthenticatedUser = Annotated[CurrentUser, Depends(get_current_user)]
AdminUser = Annotated[CurrentUser, Depends(require_admin)]
TeacherUser = Annotated[CurrentUser, Depends(require_teacher)]
StudentUser = Annotated[CurrentUser, Depends(require_student)]
