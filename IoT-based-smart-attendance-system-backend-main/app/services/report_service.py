"""Report service — aggregates and generates student and session reports."""

from __future__ import annotations

from typing import Any

from app.core.exceptions import NotFoundError
from app.core.logging import get_logger
from app.repositories.attendance_repo import AttendanceRepository
from app.repositories.enrollment_repo import EnrollmentRepository
from app.repositories.session_repo import SessionRepository
from app.repositories.user_repo import UserRepository

logger = get_logger(__name__)

_user_repo = UserRepository()
_session_repo = SessionRepository()
_enrollment_repo = EnrollmentRepository()
_attendance_repo = AttendanceRepository()


def get_student_reports(
    search: str | None = None,
    category: str | None = "all",
) -> list[dict[str, Any]]:
    """Generate in-memory student attendance reports for all completed sessions.

    Avoids nested loops and aggregates data in O(N) time.
    Reports are read-only and historical.
    """
    logger.info("Generating student reports", search=search, category=category)

    # 1. Fetch active students in bulk
    students = _user_repo.get_by_role("student", active_only=True)
    student_map = {s["id"]: s for s in students}

    # 2. Fetch completed sessions
    sessions = _session_repo.list_completed()
    session_ids = [s["id"] for s in sessions]

    # 3. Fetch active enrollments
    enrollments = _enrollment_repo.list_active()

    # 4. Fetch attendance records for the completed sessions
    records = _attendance_repo.list_by_sessions(session_ids)

    # 5. Build in-memory lookup maps
    # Map subject_id -> set of student_ids enrolled in that subject
    subj_students: dict[str, set[str]] = {}
    for e in enrollments:
        sub_id = e["subject_id"]
        stud_id = e["student_id"]
        if stud_id in student_map:
            subj_students.setdefault(sub_id, set()).add(stud_id)

    # Map (session_id, student_id) -> status
    record_lookup: dict[tuple[str, str], str] = {}
    for r in records:
        record_lookup[(r["session_id"], r["student_id"])] = r["status"]

    # Map session_id -> list of (student_id, status) for custom sessions
    records_by_session: dict[str, list[tuple[str, str]]] = {}
    for r in records:
        records_by_session.setdefault(r["session_id"], []).append((r["student_id"], r["status"]))

    # Initialize stats per active student
    student_stats: dict[str, dict[str, Any]] = {}
    for s_id, s in student_map.items():
        student_stats[s_id] = {
            "student_id": s_id,
            "roll_number": s.get("student_id_number"),
            "student_name": s["full_name"],
            "total_sessions": 0,
            "sessions_attended": 0,
            "sessions_missed": 0,
            "attendance_rate": 0.0,
            "category": "normal",
        }

    # 6. Aggregate stats using lookups
    for s in sessions:
        session_id = s["id"]
        subject_id = s.get("subject_id")

        if subject_id:
            # Subject-based session: roster is all active students enrolled in this subject
            expected_students = subj_students.get(subject_id, set())
            for student_id in expected_students:
                stats = student_stats[student_id]
                stats["total_sessions"] += 1

                # Check attendance record
                status = record_lookup.get((session_id, student_id))
                if status in ("present", "late"):
                    stats["sessions_attended"] += 1
                else:
                    # 'absent', 'revoked', or no record at all count as missed
                    stats["sessions_missed"] += 1
        else:
            # Custom session: only count students who have an attendance record
            session_records = records_by_session.get(session_id, [])
            for student_id, status in session_records:
                if student_id in student_stats:
                    stats = student_stats[student_id]
                    stats["total_sessions"] += 1

                    if status in ("present", "late"):
                        stats["sessions_attended"] += 1
                    else:
                        # 'absent' or 'revoked' count as missed
                        stats["sessions_missed"] += 1

    # 7. Compute final rates and categories
    reports: list[dict[str, Any]] = []
    for stats in student_stats.values():
        tot = stats["total_sessions"]
        if tot > 0:
            rate = stats["sessions_attended"] / tot
            stats["attendance_rate"] = rate
            if rate >= 0.75:
                stats["category"] = "normal"
            elif rate >= 0.50:
                stats["category"] = "warning"
            else:
                stats["category"] = "critical"
        else:
            stats["attendance_rate"] = 0.0
            stats["category"] = "normal"

        # Apply search filter
        if search:
            search_lower = search.lower()
            name_match = search_lower in stats["student_name"].lower()
            roll_match = (
                stats["roll_number"] is not None
                and search_lower in stats["roll_number"].lower()
            )
            if not (name_match or roll_match):
                continue

        # Apply category filter
        if category and category != "all" and stats["category"] != category:
            continue

        reports.append(stats)

    return reports


def get_completed_sessions_report(
    page: int = 1,
    page_size: int = 20,
    search: str | None = None,
) -> dict[str, Any]:
    """Retrieve paginated completed session summaries with statistics.

    Avoids N+1 queries by retrieving all session records in bulk.
    Deterministic sorting: completed_at DESC, started_at DESC, session_id DESC.
    """
    logger.info(
        "Generating completed sessions report", page=page, page_size=page_size, search=search
    )

    # 1. Fetch active students in bulk
    students = _user_repo.get_by_role("student", active_only=True)
    student_ids = {s["id"] for s in students}

    # 2. Fetch completed sessions with joined relations
    sessions = _session_repo.list_completed()
    session_ids = [s["id"] for s in sessions]

    # 3. Fetch active enrollments
    enrollments = _enrollment_repo.list_active()

    # 4. Fetch attendance records in bulk
    records = _attendance_repo.list_by_sessions(session_ids)

    # 5. Build lookup maps
    # Map subject_id -> set of enrolled student_ids
    subj_students: dict[str, set[str]] = {}
    for e in enrollments:
        sub_id = e["subject_id"]
        stud_id = e["student_id"]
        if stud_id in student_ids:
            subj_students.setdefault(sub_id, set()).add(stud_id)

    # Map session_id -> list of record dicts
    records_by_session: dict[str, list[dict[str, Any]]] = {}
    for r in records:
        records_by_session.setdefault(r["session_id"], []).append(r)

    # 6. Aggregate stats for completed sessions
    session_reports: list[dict[str, Any]] = []
    for s in sessions:
        session_id = s["id"]
        subject_id = s.get("subject_id")

        # Resolve names via joined relations
        classroom_name = (s.get("classroom") or {}).get("name") or "Unknown Classroom"
        teacher_name = (s.get("teacher") or {}).get("full_name") or "Unknown Teacher"
        subject_name = (
            s.get("subject_name") or (s.get("subject") or {}).get("name") or "Unknown Subject"
        )

        present = 0
        late = 0
        absent = 0
        manual = 0
        total = 0

        session_records = records_by_session.get(session_id, [])
        record_lookup = {r["student_id"]: r for r in session_records}

        if subject_id:
            # Subject session: expected students are those active and enrolled
            expected_students = subj_students.get(subject_id, set())
            total = len(expected_students)
            for stud_id in expected_students:
                r = record_lookup.get(stud_id)
                if r:
                    status = r["status"]
                    if status == "present":
                        present += 1
                    elif status == "late":
                        late += 1
                    elif status in ("absent", "revoked"):
                        absent += 1

                    if r.get("verification_method") == "manual":
                        manual += 1
                else:
                    absent += 1
        else:
            # Custom session: expected students are active students who have record
            for r in session_records:
                stud_id = r["student_id"]
                if stud_id in student_ids:
                    total += 1
                    status = r["status"]
                    if status == "present":
                        present += 1
                    elif status == "late":
                        late += 1
                    elif status in ("absent", "revoked"):
                        absent += 1

                    if r.get("verification_method") == "manual":
                        manual += 1

        report = {
            "session_id": session_id,
            "subject_id": subject_id,
            "subject_name": subject_name,
            "classroom_id": s["classroom_id"],
            "classroom_name": classroom_name,
            "started_at": s["started_at"],
            "completed_at": s.get("ended_at"),
            "present_count": present,
            "late_count": late,
            "absent_count": absent,
            "manual_count": manual,
            "total_students": total,
            "teacher_name": teacher_name,
        }

        # Apply search filter
        if search:
            search_lower = search.lower()
            sub_match = search_lower in subject_name.lower()
            cls_match = search_lower in classroom_name.lower()
            tch_match = search_lower in teacher_name.lower()
            if not (sub_match or cls_match or tch_match):
                continue

        session_reports.append(report)

    # 7. Stable deterministic sorting: completed_at DESC, started_at DESC, session_id DESC
    session_reports.sort(
        key=lambda x: (
            x["completed_at"] or "",
            x["started_at"] or "",
            x["session_id"],
        ),
        reverse=True,
    )

    # 8. Pagination offset calculation
    total_items = len(session_reports)
    total_pages = (total_items + page_size - 1) // page_size if total_items > 0 else 0
    start_idx = (page - 1) * page_size
    end_idx = start_idx + page_size
    paginated_items = session_reports[start_idx:end_idx]

    return {
        "items": paginated_items,
        "total": total_items,
        "page": page,
        "page_size": page_size,
        "total_pages": total_pages,
    }


def get_session_detail_report(session_id: str) -> dict[str, Any]:
    """Retrieve full compliance detail report for a specific completed session.

    Reports are read-only and historical.
    Raises NotFoundError (404) if session not found or not completed.
    """
    logger.info("Generating session detail report", session_id=session_id)

    # 1. Fetch completed session with joined relations
    s = _session_repo.get_completed_with_relations(session_id)
    if not s:
        raise NotFoundError("AttendanceSession", session_id)

    # 2. Fetch active students
    students = _user_repo.get_by_role("student", active_only=True)
    student_map = {stud["id"]: stud for stud in students}

    # 3. Fetch active enrollments
    enrollments = _enrollment_repo.list_active()

    # 4. Fetch attendance records for this session
    records = _attendance_repo.list_by_sessions([session_id])

    # 5. Build in-memory lookup maps
    subj_students: set[str] = set()
    subject_id = s.get("subject_id")
    if subject_id:
        for e in enrollments:
            if e["subject_id"] == subject_id and e["student_id"] in student_map:
                subj_students.add(e["student_id"])

    record_lookup = {r["student_id"]: r for r in records}

    # Resolve display names
    classroom_name = (s.get("classroom") or {}).get("name") or "Unknown Classroom"
    teacher_name = (s.get("teacher") or {}).get("full_name") or "Unknown Teacher"
    subject_name = (
        s.get("subject_name") or (s.get("subject") or {}).get("name") or "Unknown Subject"
    )

    # Build Header
    session_header = {
        "session_id": session_id,
        "subject_name": subject_name,
        "classroom_name": classroom_name,
        "teacher_name": teacher_name,
        "started_at": s["started_at"],
        "completed_at": s.get("ended_at"),
    }

    # Compile Student Rows & Counts
    present = 0
    late = 0
    absent = 0
    manual = 0
    total = 0

    student_rows: list[dict[str, Any]] = []

    if subject_id:
        # Subject session: expected students enrolled
        total = len(subj_students)
        for stud_id in sorted(list(subj_students)):
            stud = student_map[stud_id]
            r = record_lookup.get(stud_id)

            status = "absent"
            v_method = None
            marked_at = None

            if r:
                status = r["status"]
                if status == "present":
                    present += 1
                elif status == "late":
                    late += 1
                elif status in ("absent", "revoked"):
                    absent += 1

                v_method = "manual" if r.get("verification_method") == "manual" else "automatic"
                marked_at = r.get("marked_at")
                if r.get("verification_method") == "manual":
                    manual += 1
            else:
                absent += 1

            student_rows.append(
                {
                    "student_id": stud_id,
                    "roll_number": stud.get("student_id_number"),
                    "student_name": stud["full_name"],
                    "attendance_status": status,
                    "verification_method": v_method,
                    "marked_at": marked_at,
                }
            )
    else:
        # Custom session: only records
        # Determine unique student IDs that have marked attendance in this session
        sorted_record_student_ids = sorted(
            [r["student_id"] for r in records if r["student_id"] in student_map]
        )
        total = len(sorted_record_student_ids)

        for stud_id in sorted_record_student_ids:
            stud = student_map[stud_id]
            r = record_lookup[stud_id]

            status = r["status"]
            if status == "present":
                present += 1
            elif status == "late":
                late += 1
            elif status in ("absent", "revoked"):
                absent += 1

            v_method = "manual" if r.get("verification_method") == "manual" else "automatic"
            marked_at = r.get("marked_at")
            if r.get("verification_method") == "manual":
                manual += 1

            student_rows.append(
                {
                    "student_id": stud_id,
                    "roll_number": stud.get("student_id_number"),
                    "student_name": stud["full_name"],
                    "attendance_status": status,
                    "verification_method": v_method,
                    "marked_at": marked_at,
                }
            )

    # Sort student rows naturally: first by roll number, then by name
    def sort_key(row: dict[str, Any]) -> tuple[str, str]:
        roll = row["roll_number"] or ""
        name = row["student_name"].lower()
        return (roll, name)

    student_rows.sort(key=sort_key)

    summary_stats = {
        "present_count": present,
        "late_count": late,
        "absent_count": absent,
        "manual_count": manual,
        "total_students": total,
    }

    return {
        "session": session_header,
        "summary": summary_stats,
        "students": student_rows,
    }
