"""Timetable router — retrieve weekly, today's, and upcoming classes."""

from __future__ import annotations

from fastapi import APIRouter

from app.api.deps import AuthenticatedUser
from app.schemas.timetable import TimetableSlotResponse
from app.services import timetable_service

router = APIRouter(prefix="/timetable", tags=["timetable"])


@router.get("/", response_model=list[TimetableSlotResponse])
async def get_timetable(user: AuthenticatedUser) -> list[dict]:
    """Get all active timetable entries for the authenticated teacher (or all for admins)."""
    return timetable_service.get_timetable_slots(user_id=user.id, user_role=user.role)


@router.get("/today", response_model=list[TimetableSlotResponse])
async def get_today_timetable(user: AuthenticatedUser) -> list[dict]:
    """Get active timetable slots scheduled for today, sorted by start time."""
    return timetable_service.get_today_timetable_slots(user_id=user.id, user_role=user.role)


@router.get("/upcoming", response_model=list[TimetableSlotResponse])
async def get_upcoming_timetable(user: AuthenticatedUser) -> list[dict]:
    """Get upcoming timetable slots scheduled for the remainder of today."""
    return timetable_service.get_upcoming_timetable_slots(user_id=user.id, user_role=user.role)
