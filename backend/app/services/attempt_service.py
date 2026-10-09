"""Writes the attempt log and admin audit log. Never breaks the main flow."""

from __future__ import annotations

from typing import Any

from app.core.logging import get_logger
from app.repositories.attempt_repo import AttemptRepository
from app.repositories.audit_repo import AuditRepository

logger = get_logger(__name__)

_attempts = AttemptRepository()
_audit = AuditRepository()


def record_attempt(
    staff_id: str | None,
    action: str,
    success: bool,
    reason_code: str | None = None,
    message: str | None = None,
    **fields: Any,
) -> None:
    """Store one attempt (success or failure)."""
    row = {
        "staff_id": staff_id,
        "action": action,
        "success": success,
        "reason_code": reason_code,
        "message": message,
        **{k: v for k, v in fields.items() if v is not None},
    }
    try:
        _attempts.insert(row)
    except Exception as e:  # logging must never block attendance
        logger.error("Failed to record attempt", error=str(e), action=action)
    log = logger.info if success else logger.warning
    log("Attendance attempt", action=action, success=success, reason=reason_code)


def audit(admin_id: str, action: str, target_staff_id: str | None, **details: Any) -> None:
    """Store one admin action."""
    try:
        _audit.insert(
            {
                "admin_id": admin_id,
                "action": action,
                "target_staff_id": target_staff_id,
                "details": details,
            }
        )
    except Exception as e:
        logger.error("Failed to write audit log", error=str(e), action=action)
