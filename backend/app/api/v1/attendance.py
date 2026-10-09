"""Mark attendance (challenge → submit) and read own records."""

from __future__ import annotations

from datetime import date
from typing import Any

from fastapi import APIRouter, Query, Request

from app.schemas.requests import ChallengeRequest, SubmitRequest
from app.security.auth import ActiveStaff, client_ip
from app.services import attendance_service

router = APIRouter(prefix="/attendance", tags=["attendance"])


@router.post("/challenge")
async def challenge(body: ChallengeRequest, staff: ActiveStaff, request: Request) -> dict[str, Any]:
    """Prove beacon proximity and receive the liveness steps."""
    return attendance_service.create_challenge(staff, body, client_ip(request))


@router.post("/submit")
async def submit(body: SubmitRequest, staff: ActiveStaff, request: Request) -> dict[str, Any]:
    """Face signature + evidence → attendance record."""
    return attendance_service.submit(staff, body, client_ip(request))


@router.get("/today")
async def today(staff: ActiveStaff) -> dict[str, Any]:
    """Today's record."""
    return attendance_service.today(staff)


@router.get("/history")
async def history(
    staff: ActiveStaff,
    date_from: date | None = Query(None, alias="from"),
    date_to: date | None = Query(None, alias="to"),
) -> list[dict[str, Any]]:
    """Own records (default: last 30 days)."""
    return attendance_service.history(
        staff,
        date_from.isoformat() if date_from else None,
        date_to.isoformat() if date_to else None,
    )
