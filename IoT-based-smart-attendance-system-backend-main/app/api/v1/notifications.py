"""Notifications router — query and manage user notifications."""

from __future__ import annotations

from fastapi import APIRouter

from app.api.deps import AuthenticatedUser
from app.services import notification_service

router = APIRouter(prefix="/notifications", tags=["notifications"])


@router.get("/")
async def list_notifications(
    user: AuthenticatedUser,
    unread_only: bool = False,
    limit: int = 50,
) -> list[dict]:
    """List notifications for the current user."""
    return notification_service.list_user_notifications(
        user.id, unread_only=unread_only, limit=limit
    )


@router.get("/unread-count")
async def unread_count(user: AuthenticatedUser) -> dict:
    """Get the unread notification count for badge display."""
    count = notification_service.get_unread_count(user.id)
    return {"unread_count": count}


@router.patch("/{notification_id}/read")
async def mark_read(notification_id: str, user: AuthenticatedUser) -> dict:
    """Mark a single notification as read."""
    result = notification_service.mark_read(notification_id, user.id)
    return result or {"status": "not_found"}


@router.patch("/read-all")
async def mark_all_read(user: AuthenticatedUser) -> dict:
    """Mark all notifications as read."""
    count = notification_service.mark_all_read(user.id)
    return {"marked_count": count}
