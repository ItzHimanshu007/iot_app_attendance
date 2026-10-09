"""Admin endpoints."""

from __future__ import annotations

from datetime import date
from typing import Any

from fastapi import APIRouter, Query, Response

from app.schemas.requests import (
    BeaconCreate,
    BeaconUpdate,
    CampusUpdate,
    ManualAttendance,
    RejectFace,
    StaffRoleUpdate,
    StaffStatusUpdate,
)
from app.security.auth import AdminStaff
from app.services import admin_service, beacon_service, campus_service, report_service
from app.services.attempt_service import audit

router = APIRouter(prefix="/admin", tags=["admin"])


# ── Staff ─────────────────────────────────────────────────────────────────────


@router.get("/staff")
async def list_staff(
    admin: AdminStaff,
    status: str | None = Query(None, pattern="^(pending|active|disabled)$"),
    q: str | None = Query(None, max_length=100),
) -> list[dict[str, Any]]:
    """Staff list with device / face summary."""
    return admin_service.list_staff(status, q)


@router.post("/staff/{staff_id}/approve")
async def approve(staff_id: str, admin: AdminStaff) -> dict[str, Any]:
    """Activate account + approve face."""
    return admin_service.approve(admin, staff_id)


@router.post("/staff/{staff_id}/reject-face")
async def reject_face(staff_id: str, body: RejectFace, admin: AdminStaff) -> dict[str, Any]:
    """Ask the staff member to re-enroll."""
    return admin_service.reject_face(admin, staff_id, body.reason)


@router.post("/staff/{staff_id}/reset-face", status_code=204)
async def reset_face(staff_id: str, admin: AdminStaff) -> Response:
    """Delete the face template."""
    admin_service.reset_face(admin, staff_id)
    return Response(status_code=204)


@router.post("/staff/{staff_id}/reset-device")
async def reset_device(staff_id: str, admin: AdminStaff) -> dict[str, Any]:
    """Unbind the phone."""
    return admin_service.reset_device(admin, staff_id)


@router.post("/staff/{staff_id}/status")
async def set_status(staff_id: str, body: StaffStatusUpdate, admin: AdminStaff) -> dict[str, Any]:
    """Enable / disable."""
    return admin_service.set_status(admin, staff_id, body.status)


@router.post("/staff/{staff_id}/role")
async def set_role(staff_id: str, body: StaffRoleUpdate, admin: AdminStaff) -> dict[str, Any]:
    """Promote / demote admin."""
    return admin_service.set_role(admin, staff_id, body.role)


# ── Attendance ────────────────────────────────────────────────────────────────


@router.get("/attendance")
async def roster(admin: AdminStaff, day: date | None = Query(None, alias="date")) -> dict[str, Any]:
    """Day roster + summary (default: today on campus)."""
    return admin_service.day_roster(day)


@router.post("/attendance/manual")
async def manual(body: ManualAttendance, admin: AdminStaff) -> dict[str, Any]:
    """Manual mark with reason (audited)."""
    return admin_service.manual_mark(admin, body)


@router.get("/attempts")
async def attempts(
    admin: AdminStaff,
    day: date | None = Query(None, alias="date"),
    failed_only: bool = True,
    limit: int = Query(200, ge=1, le=1000),
) -> list[dict[str, Any]]:
    """Verification attempts (proxy alerts)."""
    return admin_service.attempts(day, failed_only, limit)


@router.get("/audit")
async def audit_log(
    admin: AdminStaff, limit: int = Query(100, ge=1, le=500)
) -> list[dict[str, Any]]:
    """Recent admin actions."""
    return admin_service.audit_log(limit)


@router.get("/reports/export")
async def export(
    admin: AdminStaff,
    date_from: date = Query(alias="from"),
    date_to: date = Query(alias="to"),
) -> Response:
    """Excel report for a date range."""
    data = report_service.build_export(date_from, date_to)
    audit(admin.id, "report_export", None, date_from=str(date_from), date_to=str(date_to))
    filename = f"staff-attendance_{date_from}_{date_to}.xlsx"
    return Response(
        content=data,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


# ── Beacons ───────────────────────────────────────────────────────────────────


@router.get("/beacons")
async def list_beacons(admin: AdminStaff) -> list[dict[str, Any]]:
    """Beacons (without secrets)."""
    return beacon_service.list_beacons()


@router.post("/beacons", status_code=201)
async def create_beacon(body: BeaconCreate, admin: AdminStaff) -> dict[str, Any]:
    """Create a beacon — response includes the secret for the firmware."""
    return beacon_service.create(admin, body)


@router.get("/beacons/{beacon_id}/secret")
async def beacon_secret(beacon_id: str, admin: AdminStaff) -> dict[str, Any]:
    """Secret + firmware snippet (audited)."""
    return beacon_service.get_secret(admin, beacon_id)


@router.patch("/beacons/{beacon_id}")
async def update_beacon(beacon_id: str, body: BeaconUpdate, admin: AdminStaff) -> dict[str, Any]:
    """Edit a beacon."""
    return beacon_service.update(admin, beacon_id, body)


@router.post("/beacons/{beacon_id}/rotate-secret")
async def rotate_beacon_secret(beacon_id: str, admin: AdminStaff) -> dict[str, Any]:
    """New secret (re-flash the ESP32 afterwards)."""
    return beacon_service.rotate_secret(admin, beacon_id)


# ── Campus ────────────────────────────────────────────────────────────────────


@router.get("/campus")
async def get_campus(admin: AdminStaff) -> dict[str, Any]:
    """Campus settings."""
    return campus_service.get_campus()


@router.put("/campus")
async def put_campus(body: CampusUpdate, admin: AdminStaff) -> dict[str, Any]:
    """Update campus settings."""
    data = body.model_dump(exclude_none=True)
    result = campus_service.update_campus(data)
    audit(admin.id, "campus_update", None, changes={k: str(v) for k, v in data.items()})
    return result
