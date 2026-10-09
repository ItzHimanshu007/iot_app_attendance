"""Notification service — creates and queries notifications for all event types."""

from __future__ import annotations

from typing import Any

from app.core.logging import get_logger
from app.repositories.notification_repo import NotificationRepository

logger = get_logger(__name__)

_repo = NotificationRepository()


# ── Core factory ──────────────────────────────────────────────────────────────


def create_notification(
    recipient_id: str | None,
    category: str,
    title: str,
    body: str,
    sender_type: str = "system",
    severity: str = "info",
    reference_type: str | None = None,
    reference_id: str | None = None,
) -> dict[str, Any]:
    """Insert a notification record."""
    data: dict[str, Any] = {
        "recipient_id": recipient_id,
        "category": category,
        "title": title,
        "body": body,
        "sender_type": sender_type,
        "severity": severity,
    }
    if reference_type:
        data["reference_type"] = reference_type
    if reference_id:
        data["reference_id"] = reference_id

    record = _repo.insert(data)
    logger.info(
        "Notification created",
        category=category,
        recipient_id=recipient_id or "broadcast",
        severity=severity,
    )
    return record


# ── Domain shortcuts ──────────────────────────────────────────────────────────


def send_attendance_confirmation(
    student_id: str, session_id: str, subject_name: str
) -> dict[str, Any]:
    """Notify student that attendance was marked."""
    return create_notification(
        recipient_id=student_id,
        category="attendance_marked",
        title="Attendance Marked",
        body=f"Your attendance for {subject_name} has been recorded.",
        reference_type="session",
        reference_id=session_id,
    )


def send_session_started(
    student_ids: list[str], session_id: str, subject_name: str, classroom_name: str
) -> None:
    """Notify enrolled students that a session started."""
    for sid in student_ids:
        create_notification(
            recipient_id=sid,
            category="session_started",
            title="Session Started",
            body=f"{subject_name} session started in {classroom_name}. Mark your attendance now.",
            sender_type="teacher",
            reference_type="session",
            reference_id=session_id,
        )
    logger.info("Session start notifications sent", count=len(student_ids))


def send_session_ended(student_ids: list[str], session_id: str, subject_name: str) -> None:
    """Notify enrolled students that a session ended."""
    for sid in student_ids:
        create_notification(
            recipient_id=sid,
            category="session_ended",
            title="Session Ended",
            body=f"{subject_name} session has ended.",
            reference_type="session",
            reference_id=session_id,
        )


def send_device_registered(user_id: str, device_model: str) -> dict[str, Any]:
    """Notify student that their device was registered."""
    return create_notification(
        recipient_id=user_id,
        category="device_registered",
        title="Device Registered",
        body=f"Your device ({device_model}) has been registered for attendance.",
    )


def send_device_revoked(user_id: str, reason: str) -> dict[str, Any]:
    """Notify student that their device was revoked."""
    return create_notification(
        recipient_id=user_id,
        category="device_revoked",
        title="Device Revoked",
        body=f"Your registered device has been deactivated. Reason: {reason}.",
        severity="warning",
    )


def send_security_alert(
    title: str, body: str, reference_type: str | None = None, reference_id: str | None = None
) -> dict[str, Any]:
    """Send a critical security alert to all admins (broadcast)."""
    return create_notification(
        recipient_id=None,
        category="security_alert",
        title=title,
        body=body,
        sender_type="backend",
        severity="critical",
        reference_type=reference_type,
        reference_id=reference_id,
    )


def send_hardware_alert(device_id: str, classroom_name: str, detail: str) -> dict[str, Any]:
    """Send an ESP32 failure alert to admins."""
    return create_notification(
        recipient_id=None,
        category="esp32_offline",
        title=f"ESP32 Offline: {classroom_name}",
        body=detail,
        sender_type="esp32",
        severity="error",
        reference_type="device",
        reference_id=device_id,
    )


# ── Query helpers ─────────────────────────────────────────────────────────────


def list_user_notifications(
    user_id: str, unread_only: bool = False, limit: int = 50
) -> list[dict[str, Any]]:
    """Get notifications for a user."""
    return _repo.list_for_user(user_id, unread_only=unread_only, limit=limit)


def get_unread_count(user_id: str) -> int:
    """Get unread notification count."""
    return _repo.unread_count(user_id)


def mark_read(notification_id: str, user_id: str) -> dict[str, Any] | None:
    """Mark a single notification as read."""
    return _repo.mark_read(notification_id, user_id)


def mark_all_read(user_id: str) -> int:
    """Mark all notifications as read. Returns count updated."""
    return _repo.mark_all_read(user_id)
