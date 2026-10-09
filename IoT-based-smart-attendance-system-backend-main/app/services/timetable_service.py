"""Timetable service — retrieve, filter, and sort weekly timetable slots."""

from __future__ import annotations

from datetime import UTC, date, datetime, time
from typing import Any

from app.core.exceptions import AuthorizationError
from app.repositories.session_repo import SessionRepository
from app.repositories.timetable_repo import TimetableRepository

_timetable_repo = TimetableRepository()
_session_repo = SessionRepository()


def _format_slot(slot: dict[str, Any]) -> dict[str, Any]:
    """Helper to resolve relationships and format slot dict for response schema."""
    # Extract subject name from relation
    subject_name = "Unknown Subject"
    if "subject" in slot and isinstance(slot["subject"], dict):
        subject_name = slot["subject"].get("name") or "Unknown Subject"

    # Extract classroom name from relation
    classroom_name = "Unknown Room"
    if "classroom" in slot and isinstance(slot["classroom"], dict):
        classroom_name = slot["classroom"].get("name") or "Unknown Room"

    # Parse start and end times
    start_val = slot["start_time"]
    end_val = slot["end_time"]

    if isinstance(start_val, str):
        start_t = time.fromisoformat(start_val)
    else:
        start_t = start_val

    if isinstance(end_val, str):
        end_t = time.fromisoformat(end_val)
    else:
        end_t = end_val

    # Calculate duration
    start_mins = start_t.hour * 60 + start_t.minute
    end_mins = end_t.hour * 60 + end_t.minute
    duration = end_mins - start_mins

    return {
        "id": slot["id"],
        "teacher_id": slot["teacher_id"],
        "subject_id": slot["subject_id"],
        "subject_name": subject_name,
        "classroom_id": slot["classroom_id"],
        "classroom_name": classroom_name,
        "day_of_week": slot["day_of_week"],
        "start_time": start_t,
        "end_time": end_t,
        "duration_minutes": duration,
        "is_active": slot["is_active"],
    }


def _is_expired(slot: dict[str, Any], current_date: date) -> bool:
    """Helper to check if a timetable slot is expired via effective_until."""
    if slot.get("effective_until"):
        eff_until = slot["effective_until"]
        if isinstance(eff_until, str):
            eff_until = date.fromisoformat(eff_until)
        if eff_until < current_date:
            return True
    return False


def get_timetable_slots(user_id: str, user_role: str) -> list[dict[str, Any]]:
    """Get all active timetable slots for the user role."""
    if user_role not in ("admin", "teacher"):
        raise AuthorizationError("Permission denied: Students are not authorized to view the timetable.")

    if user_role == "admin":
        slots = _timetable_repo.get_all_active_timetable()
    else:
        slots = _timetable_repo.get_teacher_timetable(user_id)

    return [_format_slot(s) for s in slots]


def get_today_timetable_slots(
    user_id: str, user_role: str, now: datetime | None = None
) -> list[dict[str, Any]]:
    """Get active timetable slots scheduled for today, sorted by start time."""
    if user_role not in ("admin", "teacher"):
        raise AuthorizationError("Permission denied: Students are not authorized to view the timetable.")

    if now is None:
        now = datetime.now(UTC)

    current_day = now.isoweekday()
    current_date = now.date()

    if user_role == "admin":
        slots = _timetable_repo.get_today_timetable(current_day)
    else:
        slots = _timetable_repo.get_today_timetable(current_day, user_id)

    formatted_slots = []
    for slot in slots:
        if _is_expired(slot, current_date):
            continue
        formatted_slots.append(_format_slot(slot))

    # Sort by start_time ascending
    formatted_slots.sort(key=lambda x: x["start_time"])
    return formatted_slots


def get_upcoming_timetable_slots(
    user_id: str, user_role: str, now: datetime | None = None
) -> list[dict[str, Any]]:
    """Get upcoming timetable slots scheduled for the remainder of today.

    Excludes completed, cancelled, or expired classes. Sorted by start time.
    """
    if user_role not in ("admin", "teacher"):
        raise AuthorizationError("Permission denied: Students are not authorized to view the timetable.")

    if now is None:
        now = datetime.now(UTC)

    current_day = now.isoweekday()
    current_date = now.date()
    current_time = now.time()

    if user_role == "admin":
        slots = _timetable_repo.get_today_timetable(current_day)
    else:
        slots = _timetable_repo.get_today_timetable(current_day, user_id)

    # Load attendance sessions started today to check for completed/cancelled status
    sessions_today = _session_repo.list_sessions_for_date(current_date.isoformat())
    completed_or_cancelled_timetable_ids = {
        sess["timetable_id"]
        for sess in sessions_today
        if sess.get("status") in ("completed", "cancelled") and sess.get("timetable_id")
    }

    formatted_slots = []
    for slot in slots:
        # Check date-level expiration
        if _is_expired(slot, current_date):
            continue

        # Format slot to compute time objects
        formatted = _format_slot(slot)

        # Check time-level expiration (class has already started/passed)
        if formatted["start_time"] <= current_time:
            continue

        # Exclude slots that have been completed or cancelled
        if slot["id"] in completed_or_cancelled_timetable_ids:
            continue

        formatted_slots.append(formatted)

    # Sort by start_time ascending
    formatted_slots.sort(key=lambda x: x["start_time"])
    return formatted_slots
