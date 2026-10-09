"""Timetable schemas — response DTOs for the timetable router."""

from __future__ import annotations

from datetime import time

from pydantic import BaseModel


class TimetableSlotResponse(BaseModel):
    """Response body representing a timetable slot."""

    id: str
    teacher_id: str
    subject_id: str
    subject_name: str
    classroom_id: str
    classroom_name: str
    day_of_week: int
    start_time: time
    end_time: time
    duration_minutes: int
    is_active: bool
