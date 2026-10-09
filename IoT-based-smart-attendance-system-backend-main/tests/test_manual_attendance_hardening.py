"""Hardening test suite for manual attendance state transitions and constraints."""

from __future__ import annotations

from unittest.mock import patch

import pytest
from app.core.exceptions import ConflictError, NotFoundError
from app.repositories.base import RepositoryError
from app.services.attendance_service import mark_manual_attendance


@pytest.fixture()
def mock_harden_repos():
    """Mock database repos at the service boundary."""
    with (
        patch("app.services.attendance_service._session_repo") as session_repo,
        patch("app.services.attendance_service._user_repo") as user_repo,
        patch("app.services.attendance_service._enrollment_repo") as enrollment_repo,
        patch("app.services.attendance_service._attendance_repo") as attendance_repo,
        patch("app.services.attendance_service._audit_repo") as audit_repo,
        patch("app.services.attendance_service._resolve_subject_id") as resolve_subject_id,
    ):
        yield {
            "session_repo": session_repo,
            "user_repo": user_repo,
            "enrollment_repo": enrollment_repo,
            "attendance_repo": attendance_repo,
            "audit_repo": audit_repo,
            "resolve_subject_id": resolve_subject_id,
        }


class TestManualAttendanceHardening:
    """Validate all 10 edge cases and state transitions for manual marking."""

    def test_case_1_student_never_marked_marks_present(self, mock_harden_repos):
        """Case 1: Student never marked attendance. Teacher marks Present.

        Outcome: Inserts record, status is present, summary count is updated.
        """
        mock_harden_repos["session_repo"].get_by_id.return_value = {
            "id": "session-123",
            "teacher_id": "teacher-001",
            "classroom_id": "room-001",
            "status": "active",
        }
        mock_harden_repos["user_repo"].get_by_id.return_value = {
            "id": "student-123",
            "full_name": "Test Student",
            "student_id_number": "ROLL-001",
            "is_active": True,
        }
        mock_harden_repos["resolve_subject_id"].return_value = "subject-123"
        mock_harden_repos["enrollment_repo"].is_enrolled.return_value = True
        mock_harden_repos["attendance_repo"].get_by_session_and_student.return_value = None

        inserted_record = {
            "id": "rec-123",
            "session_id": "session-123",
            "student_id": "student-123",
            "status": "present",
            "verification_method": "manual",
            "biometric_verified": False,
            "marked_at": "2026-07-12T00:00:00Z",
            "created_at": "2026-07-12T00:00:00Z",
        }
        mock_harden_repos["attendance_repo"].insert.return_value = inserted_record

        # For summary metrics
        mock_harden_repos["enrollment_repo"].get_subject_students_with_profiles.return_value = [
            {"student": {"id": "student-123", "is_active": True}}
        ]
        mock_harden_repos["attendance_repo"].list_by_session.return_value = [inserted_record]
        mock_harden_repos["attendance_repo"].get_session_present_count.return_value = 1

        result = mark_manual_attendance(
            session_id="session-123",
            student_id="student-123",
            status="present",
            teacher_id="teacher-001",
            user_role="teacher",
        )

        assert result["id"] == "rec-123"
        assert result["operation"] == "created"
        assert result["status"] == "present"
        assert result["summary"]["present"] == 1
        mock_harden_repos["attendance_repo"].insert.assert_called_once()

    def test_case_2_student_marked_present_changes_to_late(self, mock_harden_repos):
        """Case 2: Student marked Present. Teacher changes to Late.

        Outcome: Updates the existing record and increments summary.
        """
        mock_harden_repos["session_repo"].get_by_id.return_value = {
            "id": "session-123",
            "teacher_id": "teacher-001",
            "status": "active",
        }
        mock_harden_repos["user_repo"].get_by_id.return_value = {
            "id": "student-123",
            "full_name": "Test Student",
            "is_active": True,
        }
        mock_harden_repos["resolve_subject_id"].return_value = "subject-123"
        mock_harden_repos["enrollment_repo"].is_enrolled.return_value = True

        mock_harden_repos["attendance_repo"].get_by_session_and_student.return_value = {
            "id": "rec-123",
            "student_id": "student-123",
            "status": "present",
            "created_at": "2026-07-12T00:00:00Z",
        }

        updated_record = {
            "id": "rec-123",
            "session_id": "session-123",
            "student_id": "student-123",
            "status": "late",
            "verification_method": "manual",
            "biometric_verified": False,
            "marked_at": "2026-07-12T00:05:00Z",
            "created_at": "2026-07-12T00:00:00Z",
        }
        mock_harden_repos["attendance_repo"].update_with_concurrency_check.return_value = updated_record
        mock_harden_repos["enrollment_repo"].get_subject_students_with_profiles.return_value = [
            {"student": {"id": "student-123", "is_active": True}}
        ]
        mock_harden_repos["attendance_repo"].list_by_session.return_value = [updated_record]

        result = mark_manual_attendance(
            session_id="session-123",
            student_id="student-123",
            status="late",
            teacher_id="teacher-001",
            user_role="teacher",
        )

        assert result["operation"] == "updated"
        assert result["status"] == "late"
        mock_harden_repos["attendance_repo"].update_with_concurrency_check.assert_called_once()

    def test_case_3_student_marked_present_changes_to_absent(self, mock_harden_repos):
        """Case 3: Student marked Present. Teacher changes to Absent.

        Outcome: Recalculates stats correctly to decrement present count.
        """
        mock_harden_repos["session_repo"].get_by_id.return_value = {
            "id": "session-123",
            "teacher_id": "teacher-001",
            "status": "active",
        }
        mock_harden_repos["user_repo"].get_by_id.return_value = {
            "id": "student-123",
            "full_name": "Test Student",
            "is_active": True,
        }
        mock_harden_repos["resolve_subject_id"].return_value = "subject-123"
        mock_harden_repos["enrollment_repo"].is_enrolled.return_value = True

        mock_harden_repos["attendance_repo"].get_by_session_and_student.return_value = {
            "id": "rec-123",
            "student_id": "student-123",
            "status": "present",
            "created_at": "2026-07-12T00:00:00Z",
        }

        updated_record = {
            "id": "rec-123",
            "session_id": "session-123",
            "student_id": "student-123",
            "status": "absent",
            "verification_method": "manual",
            "biometric_verified": False,
            "marked_at": "2026-07-12T00:05:00Z",
            "created_at": "2026-07-12T00:00:00Z",
        }
        mock_harden_repos["attendance_repo"].update_with_concurrency_check.return_value = updated_record
        mock_harden_repos["enrollment_repo"].get_subject_students_with_profiles.return_value = [
            {"student": {"id": "student-123", "is_active": True}}
        ]
        mock_harden_repos["attendance_repo"].list_by_session.return_value = [updated_record]

        result = mark_manual_attendance(
            session_id="session-123",
            student_id="student-123",
            status="absent",
            teacher_id="teacher-001",
            user_role="teacher",
        )

        assert result["status"] == "absent"
        assert result["summary"]["present"] == 0
        assert result["summary"]["absent"] == 1

    def test_case_4_student_already_manually_marked_changes_again(self, mock_harden_repos):
        """Case 4: Student already manually marked. Teacher changes again."""
        mock_harden_repos["session_repo"].get_by_id.return_value = {
            "id": "session-123",
            "teacher_id": "teacher-001",
            "status": "active",
        }
        mock_harden_repos["user_repo"].get_by_id.return_value = {
            "id": "student-123",
            "full_name": "Test Student",
            "is_active": True,
        }
        mock_harden_repos["resolve_subject_id"].return_value = "subject-123"
        mock_harden_repos["enrollment_repo"].is_enrolled.return_value = True

        mock_harden_repos["attendance_repo"].get_by_session_and_student.return_value = {
            "id": "rec-123",
            "student_id": "student-123",
            "status": "absent",
            "verification_method": "manual",
            "created_at": "2026-07-12T00:00:00Z",
        }

        updated_record = {
            "id": "rec-123",
            "session_id": "session-123",
            "student_id": "student-123",
            "status": "present",
            "verification_method": "manual",
            "biometric_verified": False,
            "marked_at": "2026-07-12T00:05:00Z",
            "created_at": "2026-07-12T00:00:00Z",
        }
        mock_harden_repos["attendance_repo"].update_with_concurrency_check.return_value = updated_record
        mock_harden_repos["enrollment_repo"].get_subject_students_with_profiles.return_value = []
        mock_harden_repos["attendance_repo"].list_by_session.return_value = []

        result = mark_manual_attendance(
            session_id="session-123",
            student_id="student-123",
            status="present",
            teacher_id="teacher-001",
            user_role="teacher",
        )

        assert result["operation"] == "updated"
        assert result["status"] == "present"

    def test_case_5_identical_status_returns_unchanged(self, mock_harden_repos):
        """Case 5: Teacher submits identical status.

        Outcome: operation is "unchanged", no database writes.
        """
        mock_harden_repos["session_repo"].get_by_id.return_value = {
            "id": "session-123",
            "teacher_id": "teacher-001",
            "status": "active",
        }
        mock_harden_repos["user_repo"].get_by_id.return_value = {
            "id": "student-123",
            "full_name": "Test Student",
            "is_active": True,
        }
        mock_harden_repos["resolve_subject_id"].return_value = "subject-123"
        mock_harden_repos["enrollment_repo"].is_enrolled.return_value = True

        mock_harden_repos["attendance_repo"].get_by_session_and_student.return_value = {
            "id": "rec-123",
            "student_id": "student-123",
            "status": "present",
            "verification_method": "manual",
            "created_at": "2026-07-12T00:00:00Z",
            "marked_at": "2026-07-12T00:00:00Z",
        }

        mock_harden_repos["enrollment_repo"].get_subject_students_with_profiles.return_value = []
        mock_harden_repos["attendance_repo"].list_by_session.return_value = []

        result = mark_manual_attendance(
            session_id="session-123",
            student_id="student-123",
            status="present",
            teacher_id="teacher-001",
            user_role="teacher",
        )

        assert result["operation"] == "unchanged"
        mock_harden_repos["attendance_repo"].insert.assert_not_called()
        mock_harden_repos["attendance_repo"].update_with_concurrency_check.assert_not_called()

    def test_case_6_invalid_student_id_raises_404(self, mock_harden_repos):
        """Case 6: Invalid student ID raises 404 NotFoundError."""
        mock_harden_repos["session_repo"].get_by_id.return_value = {
            "id": "session-123",
            "teacher_id": "teacher-001",
            "status": "active",
        }
        mock_harden_repos["user_repo"].get_by_id.return_value = None

        with pytest.raises(NotFoundError, match="User"):
            mark_manual_attendance(
                session_id="session-123",
                student_id="nonexistent-student",
                status="present",
                teacher_id="teacher-001",
                user_role="teacher",
            )

    def test_case_7_invalid_session_id_raises_404(self, mock_harden_repos):
        """Case 7: Invalid session ID raises 404 NotFoundError."""
        mock_harden_repos["session_repo"].get_by_id.return_value = None

        with pytest.raises(NotFoundError, match="AttendanceSession"):
            mark_manual_attendance(
                session_id="nonexistent-session",
                student_id="student-123",
                status="present",
                teacher_id="teacher-001",
                user_role="teacher",
            )

    def test_case_8_cancelled_session_raises_409(self, mock_harden_repos):
        """Case 8: Cancelled session raises 409 Conflict."""
        mock_harden_repos["session_repo"].get_by_id.return_value = {
            "id": "session-123",
            "teacher_id": "teacher-001",
            "status": "cancelled",
        }
        mock_harden_repos["user_repo"].get_by_id.return_value = {
            "id": "student-123",
            "is_active": True,
        }

        with pytest.raises(ConflictError, match="Cannot manually modify attendance"):
            mark_manual_attendance(
                session_id="session-123",
                student_id="student-123",
                status="present",
                teacher_id="teacher-001",
                user_role="teacher",
            )

    def test_case_9_expired_completed_session_allowed(self, mock_harden_repos):
        """Case 9: Completed/expired session manual edit is allowed."""
        mock_harden_repos["session_repo"].get_by_id.return_value = {
            "id": "session-123",
            "teacher_id": "teacher-001",
            "status": "completed",  # Expired session
        }
        mock_harden_repos["user_repo"].get_by_id.return_value = {
            "id": "student-123",
            "full_name": "Test Student",
            "is_active": True,
        }
        mock_harden_repos["resolve_subject_id"].return_value = "subject-123"
        mock_harden_repos["enrollment_repo"].is_enrolled.return_value = True
        mock_harden_repos["attendance_repo"].get_by_session_and_student.return_value = None

        inserted_record = {
            "id": "rec-123",
            "session_id": "session-123",
            "student_id": "student-123",
            "status": "present",
            "verification_method": "manual",
            "biometric_verified": False,
            "marked_at": "2026-07-12T00:00:00Z",
            "created_at": "2026-07-12T00:00:00Z",
        }
        mock_harden_repos["attendance_repo"].insert.return_value = inserted_record
        mock_harden_repos["enrollment_repo"].get_subject_students_with_profiles.return_value = []
        mock_harden_repos["attendance_repo"].list_by_session.return_value = []

        result = mark_manual_attendance(
            session_id="session-123",
            student_id="student-123",
            status="present",
            teacher_id="teacher-001",
            user_role="teacher",
        )

        assert result["status"] == "present"
        mock_harden_repos["attendance_repo"].insert.assert_called_once()

    def test_case_10_concurrent_requests_handled_correctly(self, mock_harden_repos):
        """Case 10: Optimistic locking correctly protects concurrent requests."""
        mock_harden_repos["session_repo"].get_by_id.return_value = {
            "id": "session-123",
            "teacher_id": "teacher-001",
            "status": "active",
        }
        mock_harden_repos["user_repo"].get_by_id.return_value = {
            "id": "student-123",
            "full_name": "Test Student",
            "is_active": True,
        }
        mock_harden_repos["resolve_subject_id"].return_value = "subject-123"
        mock_harden_repos["enrollment_repo"].is_enrolled.return_value = True

        mock_harden_repos["attendance_repo"].get_by_session_and_student.return_value = {
            "id": "rec-123",
            "student_id": "student-123",
            "status": "present",
            "updated_at": "2026-07-12T00:00:00Z",
        }

        # Raise RepositoryError on update to simulate concurrency mismatch
        mock_harden_repos["attendance_repo"].update_with_concurrency_check.side_effect = RepositoryError(
            "returned no rows — possible concurrency update",
            table="attendance_records",
            operation="update_with_concurrency_check",
        )

        with pytest.raises(ConflictError, match="Concurrent modification detected"):
            mark_manual_attendance(
                session_id="session-123",
                student_id="student-123",
                status="late",
                teacher_id="teacher-001",
                user_role="teacher",
            )
