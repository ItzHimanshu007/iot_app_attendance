"""Tests for the Phase 4.0 Manual Attendance Backend endpoint."""

from __future__ import annotations

from unittest.mock import patch

import pytest
from app.repositories.base import RepositoryError


@pytest.fixture()
def mock_manual_repos():
    """Mock repositories and services for manual attendance tests."""
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


class TestManualAttendanceAuth:
    """Verify authorization constraints on the manual attendance endpoint."""

    def test_student_blocked(self, student_client):
        """Students are blocked from manual marking (403)."""
        response = student_client.post(
            "/api/v1/attendance/manual",
            json={
                "session_id": "session-123",
                "student_id": "student-abc",
                "status": "present",
            },
        )
        assert response.status_code == 403
        assert response.json()["error"]["code"] == "FORBIDDEN"

    def test_unauthenticated_blocked(self, client):
        """Unauthenticated requests are blocked (401)."""
        response = client.post(
            "/api/v1/attendance/manual",
            json={
                "session_id": "session-123",
                "student_id": "student-abc",
                "status": "present",
            },
        )
        assert response.status_code == 401
        assert response.json()["error"]["code"] == "UNAUTHORIZED"

    def test_teacher_owns_session(self, teacher_client, mock_manual_repos):
        """Teachers can mark attendance for a session they own."""
        mock_manual_repos["session_repo"].get_by_id.return_value = {
            "id": "session-123",
            "teacher_id": "teacher-001",  # Owns it
            "classroom_id": "classroom-123",
            "status": "active",
        }
        mock_manual_repos["user_repo"].get_by_id.return_value = {
            "id": "student-abc",
            "is_active": True,
        }
        mock_manual_repos["resolve_subject_id"].return_value = "subject-123"
        mock_manual_repos["enrollment_repo"].is_enrolled.return_value = True
        mock_manual_repos["attendance_repo"].get_by_session_and_student.return_value = None
        mock_manual_repos["attendance_repo"].insert.return_value = {
            "id": "rec-123",
            "session_id": "session-123",
            "student_id": "student-abc",
            "status": "present",
            "verification_method": "manual",
            "biometric_verified": False,
            "marked_at": "2026-07-01T08:00:00Z",
            "created_at": "2026-07-01T08:00:00Z",
        }
        mock_manual_repos["enrollment_repo"].get_subject_students_with_profiles.return_value = []
        mock_manual_repos["attendance_repo"].list_by_session.return_value = []

        response = teacher_client.post(
            "/api/v1/attendance/manual",
            json={
                "session_id": "session-123",
                "student_id": "student-abc",
                "status": "present",
            },
        )
        assert response.status_code == 200

    def test_teacher_does_not_own_session(self, teacher_client, mock_manual_repos):
        """Teachers cannot mark manual attendance for other teachers' sessions (403)."""
        mock_manual_repos["session_repo"].get_by_id.return_value = {
            "id": "session-123",
            "teacher_id": "teacher-999",  # Mismatch
            "classroom_id": "classroom-123",
            "status": "active",
        }

        response = teacher_client.post(
            "/api/v1/attendance/manual",
            json={
                "session_id": "session-123",
                "student_id": "student-abc",
                "status": "present",
            },
        )
        assert response.status_code == 403
        assert response.json()["error"]["code"] == "FORBIDDEN"

    def test_admin_bypasses_ownership(self, admin_client, mock_manual_repos):
        """Admins bypass ownership checks and can manually mark attendance."""
        mock_manual_repos["session_repo"].get_by_id.return_value = {
            "id": "session-123",
            "teacher_id": "teacher-999",  # Admin (admin-001) doesn't own it, but bypasses
            "classroom_id": "classroom-123",
            "status": "active",
        }
        mock_manual_repos["user_repo"].get_by_id.return_value = {
            "id": "student-abc",
            "is_active": True,
        }
        mock_manual_repos["resolve_subject_id"].return_value = "subject-123"
        mock_manual_repos["enrollment_repo"].is_enrolled.return_value = True
        mock_manual_repos["attendance_repo"].get_by_session_and_student.return_value = None
        mock_manual_repos["attendance_repo"].insert.return_value = {
            "id": "rec-123",
            "session_id": "session-123",
            "student_id": "student-abc",
            "status": "present",
            "verification_method": "manual",
            "biometric_verified": False,
            "marked_at": "2026-07-01T08:00:00Z",
            "created_at": "2026-07-01T08:00:00Z",
        }
        mock_manual_repos["enrollment_repo"].get_subject_students_with_profiles.return_value = []
        mock_manual_repos["attendance_repo"].list_by_session.return_value = []

        response = admin_client.post(
            "/api/v1/attendance/manual",
            json={
                "session_id": "session-123",
                "student_id": "student-abc",
                "status": "present",
            },
        )
        assert response.status_code == 200


class TestManualAttendanceValidation:
    """Verify core domain validations (missing resources, non-editable states, enrollment)."""

    def test_session_not_found(self, teacher_client, mock_manual_repos):
        """Missing session -> 404 NotFoundError."""
        mock_manual_repos["session_repo"].get_by_id.return_value = None

        response = teacher_client.post(
            "/api/v1/attendance/manual",
            json={
                "session_id": "session-999",
                "student_id": "student-abc",
                "status": "present",
            },
        )
        assert response.status_code == 404
        assert response.json()["error"]["code"] == "NOT_FOUND"

    def test_student_not_found(self, teacher_client, mock_manual_repos):
        """Missing student -> 404 NotFoundError."""
        mock_manual_repos["session_repo"].get_by_id.return_value = {
            "id": "session-123",
            "teacher_id": "teacher-001",
            "status": "active",
        }
        mock_manual_repos["user_repo"].get_by_id.return_value = None

        response = teacher_client.post(
            "/api/v1/attendance/manual",
            json={
                "session_id": "session-123",
                "student_id": "student-999",
                "status": "present",
            },
        )
        assert response.status_code == 404
        assert response.json()["error"]["code"] == "NOT_FOUND"

    def test_session_not_editable(self, teacher_client, mock_manual_repos):
        """Cancelled or other status sessions cannot be manually edited (409)."""
        mock_manual_repos["session_repo"].get_by_id.return_value = {
            "id": "session-123",
            "teacher_id": "teacher-001",
            "status": "cancelled",  # Non-editable
        }
        mock_manual_repos["user_repo"].get_by_id.return_value = {
            "id": "student-abc",
            "is_active": True,
        }

        response = teacher_client.post(
            "/api/v1/attendance/manual",
            json={
                "session_id": "session-123",
                "student_id": "student-abc",
                "status": "present",
            },
        )
        assert response.status_code == 409
        assert response.json()["error"]["code"] == "CONFLICT"

    def test_student_not_enrolled(self, teacher_client, mock_manual_repos):
        """Student must have active enrollment to be manual-marked (409)."""
        mock_manual_repos["session_repo"].get_by_id.return_value = {
            "id": "session-123",
            "teacher_id": "teacher-001",
            "status": "active",
        }
        mock_manual_repos["user_repo"].get_by_id.return_value = {
            "id": "student-abc",
            "is_active": True,
        }
        mock_manual_repos["resolve_subject_id"].return_value = "subject-123"
        mock_manual_repos["enrollment_repo"].is_enrolled.return_value = False  # Not enrolled

        response = teacher_client.post(
            "/api/v1/attendance/manual",
            json={
                "session_id": "session-123",
                "student_id": "student-abc",
                "status": "present",
            },
        )
        assert response.status_code == 409
        assert response.json()["error"]["code"] == "CONFLICT"


class TestManualAttendanceOperations:
    """Verify modification paths (idempotent no-op, inserts, updates, and rollback compensation)."""

    def test_idempotent_no_change_present(self, teacher_client, mock_manual_repos):
        """Marking present on already present status is a no-op (operation='unchanged')."""
        mock_manual_repos["session_repo"].get_by_id.return_value = {
            "id": "session-123",
            "teacher_id": "teacher-001",
            "status": "active",
        }
        mock_manual_repos["user_repo"].get_by_id.return_value = {
            "id": "student-abc",
            "is_active": True,
        }
        mock_manual_repos["resolve_subject_id"].return_value = "subject-123"
        mock_manual_repos["enrollment_repo"].is_enrolled.return_value = True

        # Existing record is already present
        mock_manual_repos["attendance_repo"].get_by_session_and_student.return_value = {
            "id": "rec-123",
            "session_id": "session-123",
            "student_id": "student-abc",
            "status": "present",
            "verification_method": "manual",
            "biometric_verified": False,
            "marked_at": "2026-07-01T08:00:00Z",
            "created_at": "2026-07-01T08:00:00Z",
        }
        mock_manual_repos["enrollment_repo"].get_subject_students_with_profiles.return_value = []
        mock_manual_repos["attendance_repo"].list_by_session.return_value = []

        response = teacher_client.post(
            "/api/v1/attendance/manual",
            json={
                "session_id": "session-123",
                "student_id": "student-abc",
                "status": "present",
            },
        )
        assert response.status_code == 200
        data = response.json()
        assert data["operation"] == "unchanged"
        assert data["previous_status"] == "present"

        # Repos should not write or log audit
        mock_manual_repos["attendance_repo"].update.assert_not_called()
        mock_manual_repos["attendance_repo"].insert.assert_not_called()
        mock_manual_repos["audit_repo"].insert.assert_not_called()

    def test_idempotent_no_change_absent(self, teacher_client, mock_manual_repos):
        """Marking absent when student has no database record (implicitly absent) is a no-op."""
        mock_manual_repos["session_repo"].get_by_id.return_value = {
            "id": "session-123",
            "teacher_id": "teacher-001",
            "status": "active",
        }
        mock_manual_repos["user_repo"].get_by_id.return_value = {
            "id": "student-abc",
            "is_active": True,
        }
        mock_manual_repos["resolve_subject_id"].return_value = "subject-123"
        mock_manual_repos["enrollment_repo"].is_enrolled.return_value = True

        # Student has NO attendance record
        mock_manual_repos["attendance_repo"].get_by_session_and_student.return_value = None
        mock_manual_repos["enrollment_repo"].get_subject_students_with_profiles.return_value = []
        mock_manual_repos["attendance_repo"].list_by_session.return_value = []

        response = teacher_client.post(
            "/api/v1/attendance/manual",
            json={
                "session_id": "session-123",
                "student_id": "student-abc",
                "status": "absent",
            },
        )
        assert response.status_code == 200
        data = response.json()
        assert data["operation"] == "unchanged"
        assert data["previous_status"] is None

        mock_manual_repos["attendance_repo"].insert.assert_not_called()
        mock_manual_repos["audit_repo"].insert.assert_not_called()

    def test_update_absent_to_present(self, teacher_client, mock_manual_repos):
        """Transition absent (no record) -> present (inserts new record, operation='created')."""
        mock_manual_repos["session_repo"].get_by_id.return_value = {
            "id": "session-123",
            "teacher_id": "teacher-001",
            "status": "active",
        }
        mock_manual_repos["user_repo"].get_by_id.return_value = {
            "id": "student-abc",
            "is_active": True,
        }
        mock_manual_repos["resolve_subject_id"].return_value = "subject-123"
        mock_manual_repos["enrollment_repo"].is_enrolled.return_value = True
        mock_manual_repos["attendance_repo"].get_by_session_and_student.return_value = None

        mock_manual_repos["attendance_repo"].insert.return_value = {
            "id": "rec-123",
            "session_id": "session-123",
            "student_id": "student-abc",
            "status": "present",
            "verification_method": "manual",
            "biometric_verified": False,
            "marked_at": "2026-07-01T08:00:00Z",
            "created_at": "2026-07-01T08:00:00Z",
        }
        mock_manual_repos["enrollment_repo"].get_subject_students_with_profiles.return_value = []
        mock_manual_repos["attendance_repo"].list_by_session.return_value = []

        response = teacher_client.post(
            "/api/v1/attendance/manual",
            json={
                "session_id": "session-123",
                "student_id": "student-abc",
                "status": "present",
                "reason": "marked late bus",
            },
        )
        assert response.status_code == 200
        data = response.json()
        assert data["operation"] == "created"
        assert data["previous_status"] is None
        assert data["status"] == "present"
        assert data["modified_by"] == "teacher-001"

        # Verify audit write
        mock_manual_repos["audit_repo"].insert.assert_called_once()
        audit_args = mock_manual_repos["audit_repo"].insert.call_args[0][0]
        assert audit_args["teacher_id"] == "teacher-001"
        assert audit_args["student_id"] == "student-abc"
        assert audit_args["new_status"] == "present"
        assert audit_args["previous_status"] is None
        assert audit_args["operation"] == "created"
        assert audit_args["reason"] == "marked late bus"

    def test_update_present_to_late(self, teacher_client, mock_manual_repos):
        """Transition present -> late (updates existing record, operation='updated')."""
        mock_manual_repos["session_repo"].get_by_id.return_value = {
            "id": "session-123",
            "teacher_id": "teacher-001",
            "status": "active",
        }
        mock_manual_repos["user_repo"].get_by_id.return_value = {
            "id": "student-abc",
            "is_active": True,
        }
        mock_manual_repos["resolve_subject_id"].return_value = "subject-123"
        mock_manual_repos["enrollment_repo"].is_enrolled.return_value = True

        # Existing record is present
        mock_manual_repos["attendance_repo"].get_by_session_and_student.return_value = {
            "id": "rec-123",
            "session_id": "session-123",
            "student_id": "student-abc",
            "status": "present",
            "verification_method": "manual",
            "biometric_verified": False,
            "updated_at": "2026-07-01T08:00:00Z",
            "marked_at": "2026-07-01T08:00:00Z",
            "created_at": "2026-07-01T08:00:00Z",
        }
        mock_manual_repos["attendance_repo"].update_with_concurrency_check.return_value = {
            "id": "rec-123",
            "session_id": "session-123",
            "student_id": "student-abc",
            "status": "late",
            "verification_method": "manual",
            "biometric_verified": False,
            "marked_at": "2026-07-01T08:10:00Z",
            "created_at": "2026-07-01T08:00:00Z",
        }
        mock_manual_repos["enrollment_repo"].get_subject_students_with_profiles.return_value = []
        mock_manual_repos["attendance_repo"].list_by_session.return_value = []

        response = teacher_client.post(
            "/api/v1/attendance/manual",
            json={
                "session_id": "session-123",
                "student_id": "student-abc",
                "status": "late",
            },
        )
        assert response.status_code == 200
        data = response.json()
        assert data["operation"] == "updated"
        assert data["previous_status"] == "present"
        assert data["status"] == "late"

        # Verify audit logging
        mock_manual_repos["audit_repo"].insert.assert_called_once()
        audit_args = mock_manual_repos["audit_repo"].insert.call_args[0][0]
        assert audit_args["new_status"] == "late"
        assert audit_args["previous_status"] == "present"
        assert audit_args["operation"] == "updated"

    def test_update_late_to_absent(self, teacher_client, mock_manual_repos):
        """Transition late -> absent (updates status value to absent)."""
        mock_manual_repos["session_repo"].get_by_id.return_value = {
            "id": "session-123",
            "teacher_id": "teacher-001",
            "status": "active",
        }
        mock_manual_repos["user_repo"].get_by_id.return_value = {
            "id": "student-abc",
            "is_active": True,
        }
        mock_manual_repos["resolve_subject_id"].return_value = "subject-123"
        mock_manual_repos["enrollment_repo"].is_enrolled.return_value = True

        # Existing record is late
        mock_manual_repos["attendance_repo"].get_by_session_and_student.return_value = {
            "id": "rec-123",
            "session_id": "session-123",
            "student_id": "student-abc",
            "status": "late",
            "verification_method": "manual",
            "biometric_verified": False,
            "updated_at": "2026-07-01T08:00:00Z",
            "marked_at": "2026-07-01T08:00:00Z",
            "created_at": "2026-07-01T08:00:00Z",
        }
        mock_manual_repos["attendance_repo"].update_with_concurrency_check.return_value = {
            "id": "rec-123",
            "session_id": "session-123",
            "student_id": "student-abc",
            "status": "absent",
            "verification_method": "manual",
            "biometric_verified": False,
            "marked_at": "2026-07-01T08:15:00Z",
            "created_at": "2026-07-01T08:00:00Z",
        }
        mock_manual_repos["enrollment_repo"].get_subject_students_with_profiles.return_value = []
        mock_manual_repos["attendance_repo"].list_by_session.return_value = []

        response = teacher_client.post(
            "/api/v1/attendance/manual",
            json={
                "session_id": "session-123",
                "student_id": "student-abc",
                "status": "absent",
            },
        )
        assert response.status_code == 200
        data = response.json()
        assert data["operation"] == "updated"
        assert data["previous_status"] == "late"
        assert data["status"] == "absent"

    def test_optimistic_concurrency_protection(self, teacher_client, mock_manual_repos):
        """If record is concurrently modified (mismatching updated_at), return 409 Conflict."""
        mock_manual_repos["session_repo"].get_by_id.return_value = {
            "id": "session-123",
            "teacher_id": "teacher-001",
            "status": "active",
        }
        mock_manual_repos["user_repo"].get_by_id.return_value = {
            "id": "student-abc",
            "is_active": True,
        }
        mock_manual_repos["resolve_subject_id"].return_value = "subject-123"
        mock_manual_repos["enrollment_repo"].is_enrolled.return_value = True

        # Record with initial updated_at timestamp
        mock_manual_repos["attendance_repo"].get_by_session_and_student.return_value = {
            "id": "rec-123",
            "session_id": "session-123",
            "student_id": "student-abc",
            "status": "present",
            "verification_method": "manual",
            "biometric_verified": False,
            "updated_at": "2026-07-01T08:00:00Z",
            "marked_at": "2026-07-01T08:00:00Z",
            "created_at": "2026-07-01T08:00:00Z",
        }
        # Simulate concurrency check failure in repo (returning no rows raises RepositoryError)
        mock_manual_repos["attendance_repo"].update_with_concurrency_check.side_effect = RepositoryError(
            "update_with_concurrency_check returned no rows — possible concurrency update",
            table="attendance_records",
            operation="update_with_concurrency_check",
        )

        response = teacher_client.post(
            "/api/v1/attendance/manual",
            json={
                "session_id": "session-123",
                "student_id": "student-abc",
                "status": "late",
            },
        )
        assert response.status_code == 409
        assert "Concurrent modification" in response.json()["error"]["message"]

    def test_audit_failure_triggers_rollback(self, teacher_client, mock_manual_repos):
        """If audit log write fails, the database change must be reverted (rollback compensation)."""
        mock_manual_repos["session_repo"].get_by_id.return_value = {
            "id": "session-123",
            "teacher_id": "teacher-001",
            "status": "active",
        }
        mock_manual_repos["user_repo"].get_by_id.return_value = {
            "id": "student-abc",
            "is_active": True,
        }
        mock_manual_repos["resolve_subject_id"].return_value = "subject-123"
        mock_manual_repos["enrollment_repo"].is_enrolled.return_value = True

        # Student starts with no record (marking present inserts a record)
        mock_manual_repos["attendance_repo"].get_by_session_and_student.return_value = None
        mock_manual_repos["attendance_repo"].insert.return_value = {
            "id": "rec-inserted-123",
            "session_id": "session-123",
            "student_id": "student-abc",
            "status": "present",
            "verification_method": "manual",
            "biometric_verified": False,
            "marked_at": "2026-07-01T08:00:00Z",
            "created_at": "2026-07-01T08:00:00Z",
        }
        # Simulate audit log write failure
        mock_manual_repos["audit_repo"].insert.side_effect = Exception("Audit write failed")

        with pytest.raises(Exception, match="Audit write failed"):
            from app.services.attendance_service import mark_manual_attendance
            mark_manual_attendance(
                session_id="session-123",
                student_id="student-abc",
                status="present",
                teacher_id="teacher-001",
                user_role="teacher",
            )

        # Reversion must be called to delete the inserted attendance record
        mock_manual_repos["attendance_repo"].delete.assert_called_once_with("rec-inserted-123")
