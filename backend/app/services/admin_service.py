"""Admin operations: approvals, resets, roster, manual marks, alerts."""

from __future__ import annotations

from datetime import date, datetime, timedelta
from typing import Any

from app.core.exceptions import ConflictError, NotFoundError, ValidationError
from app.core.timeutil import campus_zone, local_today, now_utc
from app.repositories.attempt_repo import AttemptRepository
from app.repositories.attendance_repo import AttendanceRepository
from app.repositories.audit_repo import AuditRepository
from app.repositories.face_repo import FaceTemplateRepository
from app.repositories.staff_repo import StaffRepository
from app.schemas.requests import ManualAttendance
from app.security.auth import CurrentStaff
from app.services import campus_service, device_service, face_service
from app.services.attempt_service import audit
from app.services.attendance_service import public_record
from app.services.staff_service import next_step, public_profile

_staff = StaffRepository()
_faces = FaceTemplateRepository()
_attendance = AttendanceRepository()
_attempts = AttemptRepository()
_audit = AuditRepository()

ROSTER_STATUSES = ("present", "late", "absent", "on_leave", "not_marked")


def _get_staff(staff_id: str) -> dict[str, Any]:
    row = _staff.get_by_id(staff_id)
    if row is None:
        raise NotFoundError("Staff", staff_id)
    return row


def _staff_names() -> dict[str, dict[str, Any]]:
    return {s["id"]: s for s in _staff.list_staff(limit=5000)}


# ── Staff management ──────────────────────────────────────────────────────────


def list_staff(status: str | None = None, query: str | None = None) -> list[dict[str, Any]]:
    """Staff with device + face summary, optionally filtered."""
    devices = device_service.active_devices_by_staff()
    faces = {f["staff_id"]: f for f in _faces.list_status()}
    needle = (query or "").strip().lower()
    result = []
    for row in _staff.list_staff(status=status, limit=5000):
        if needle and not any(
            needle in str(row.get(k) or "").lower() for k in ("full_name", "email", "employee_id")
        ):
            continue
        device = devices.get(row["id"])
        face = faces.get(row["id"])
        result.append(
            {
                **public_profile(row),
                "device": device_service.public_device(device),
                "face": face_service.public_face(face),
                "next_step": next_step(row["status"], device, face),
            }
        )
    return result


def approve(admin: CurrentStaff, staff_id: str) -> dict[str, Any]:
    """Activate the account and approve the pending face template."""
    row = _get_staff(staff_id)
    template = _faces.get(staff_id)
    now = now_utc().isoformat()
    if template and template.get("status") != "approved":
        threshold = float(campus_service.get_campus()["face_match_threshold"])
        duplicate = face_service.find_duplicate(staff_id, template["embeddings"], threshold)
        if duplicate:
            other = _staff.get_by_id(duplicate[0]) or {}
            raise ConflictError(
                f"This face matches {other.get('full_name', 'another staff member')} "
                f"({other.get('employee_id') or other.get('email', '')}). "
                "Possible proxy enrollment — not approved.",
                code="FACE_DUPLICATE",
            )
        _faces.update_status(
            staff_id, {"status": "approved", "reviewed_by": admin.id, "reviewed_at": now}
        )
    if row["status"] != "active":
        row = _staff.update(
            staff_id, {"status": "active", "approved_by": admin.id, "approved_at": now}
        )
    audit(admin.id, "staff_approve", staff_id, face_approved=template is not None)
    return public_profile(row)


def reject_face(admin: CurrentStaff, staff_id: str, reason: str | None) -> dict[str, Any]:
    """Ask the staff member to enroll again."""
    _get_staff(staff_id)
    if _faces.get(staff_id) is None:
        raise NotFoundError("Face enrollment", staff_id)
    row = _faces.update_status(
        staff_id,
        {"status": "rejected", "reviewed_by": admin.id, "reviewed_at": now_utc().isoformat()},
    )
    audit(admin.id, "face_reject", staff_id, reason=reason)
    return face_service.public_face(row) or {}


def reset_face(admin: CurrentStaff, staff_id: str) -> None:
    """Delete the face template (staff must enroll again)."""
    _get_staff(staff_id)
    _faces.delete(staff_id)
    audit(admin.id, "face_reset", staff_id)


def reset_device(admin: CurrentStaff, staff_id: str) -> dict[str, Any]:
    """Unbind the phone so the staff member can bind a new one."""
    _get_staff(staff_id)
    count = device_service.reset_for_staff(staff_id)
    audit(admin.id, "device_reset", staff_id, devices_unbound=count)
    return {"devices_unbound": count}


def set_status(admin: CurrentStaff, staff_id: str, status: str) -> dict[str, Any]:
    """Enable / disable an account."""
    if staff_id == admin.id and status != "active":
        raise ValidationError("You cannot disable your own account.", "SELF_ACTION")
    _get_staff(staff_id)
    data: dict[str, Any] = {"status": status}
    if status == "active":
        data.update(approved_by=admin.id, approved_at=now_utc().isoformat())
    row = _staff.update(staff_id, data)
    audit(admin.id, "staff_status", staff_id, status=status)
    return public_profile(row)


def set_role(admin: CurrentStaff, staff_id: str, role: str) -> dict[str, Any]:
    """Promote / demote admin."""
    if staff_id == admin.id and role != "admin":
        raise ValidationError("You cannot remove your own admin role.", "SELF_ACTION")
    _get_staff(staff_id)
    row = _staff.update(staff_id, {"role": role})
    audit(admin.id, "staff_role", staff_id, role=role)
    return public_profile(row)


# ── Daily roster ──────────────────────────────────────────────────────────────


def day_roster(day: date | None) -> dict[str, Any]:
    """Every active staff member with their status for one day."""
    campus = campus_service.get_campus()
    tz = campus_zone(campus.get("timezone"))
    target = (day or local_today(tz)).isoformat()
    records = {r["staff_id"]: r for r in _attendance.list_range(target, target)}

    rows = []
    summary = dict.fromkeys(ROSTER_STATUSES, 0)
    summary.update(total=0, checked_out=0, flagged=0)
    for staff in _staff.list_active():
        record = records.get(staff["id"])
        status = record["status"] if record else "not_marked"
        summary[status] += 1
        summary["total"] += 1
        if record and record.get("check_out_at"):
            summary["checked_out"] += 1
        if record and record.get("flags"):
            summary["flagged"] += 1
        rows.append(
            {
                "staff": public_profile(staff),
                "status": status,
                "attendance": public_record(record),
            }
        )
    rows.sort(key=lambda r: (ROSTER_STATUSES.index(r["status"]), r["staff"]["full_name"]))
    return {"date": target, "summary": summary, "rows": rows}


def manual_mark(admin: CurrentStaff, req: ManualAttendance) -> dict[str, Any]:
    """Admin override (audited)."""
    staff_id = str(req.staff_id)
    _get_staff(staff_id)
    tz = campus_zone(campus_service.get_campus().get("timezone"))
    day = req.date.isoformat()

    def at(t: Any) -> str | None:
        return datetime.combine(req.date, t, tzinfo=tz).isoformat() if t else None

    data: dict[str, Any] = {
        "status": req.status,
        "is_manual": True,
        "manual_reason": req.reason,
        "marked_by": admin.id,
    }
    if req.status in ("present", "late"):
        if req.check_in_time:
            data["check_in_at"] = at(req.check_in_time)
        if req.check_out_time:
            data["check_out_at"] = at(req.check_out_time)
    else:
        data.update(check_in_at=None, check_out_at=None)

    existing = _attendance.get_for_day(staff_id, day)
    if existing:
        row = _attendance.update(existing["id"], data)
    else:
        row = _attendance.insert({"staff_id": staff_id, "attendance_date": day, **data})
    audit(admin.id, "attendance_manual", staff_id, date=day, status=req.status, reason=req.reason)
    return public_record(row) or {}


# ── Alerts ────────────────────────────────────────────────────────────────────


def attempts(day: date | None, only_failed: bool, limit: int = 200) -> list[dict[str, Any]]:
    """Attempts for one campus day (default today), newest first, with staff names."""
    tz = campus_zone(campus_service.get_campus().get("timezone"))
    target = day or local_today(tz)
    start = datetime.combine(target, datetime.min.time(), tzinfo=tz)
    end = start + timedelta(days=1)
    rows = _attempts.list_attempts(
        start.isoformat(), end.isoformat(), success=False if only_failed else None, limit=limit
    )
    names = _staff_names()
    for row in rows:
        staff = names.get(row.get("staff_id") or "")
        row["staff_name"] = staff.get("full_name") if staff else None
        row["employee_id"] = staff.get("employee_id") if staff else None
        row.pop("device_fingerprint", None)
    return rows


def audit_log(limit: int = 100) -> list[dict[str, Any]]:
    """Recent admin actions with names."""
    names = _staff_names()
    rows = _audit.recent(limit)
    for row in rows:
        row["admin_name"] = (names.get(row.get("admin_id") or "") or {}).get("full_name")
        row["target_name"] = (names.get(row.get("target_staff_id") or "") or {}).get("full_name")
    return rows
