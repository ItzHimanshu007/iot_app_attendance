"""Tests for the attendance validation engine."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from unittest.mock import patch

import pytest
from app.core.exceptions import (
    DuplicateAttendanceError,
    EnrollmentRequiredError,
    InvalidTokenError,
    NotFoundError,
    SessionExpiredError,
    SessionNotActiveError,
)
from app.services.attendance_service import submit_attendance


@pytest.fixture()
def mock_repos():
    """Patch all repositories and services used by submit_attendance."""
    now = datetime.now(UTC)
    active_session = {
        "id": "session-001",
        "teacher_id": "teacher-001",
        "subject_id": "subject-001",
        "classroom_id": "classroom-001",
        "status": "active",
        "started_at": (now - timedelta(minutes=5)).isoformat(),
        "expires_at": (now + timedelta(minutes=55)).isoformat(),
        "total_present": 3,
    }

    with (
        patch("app.services.attendance_service._session_repo") as session_repo,
        patch("app.services.attendance_service._user_repo") as user_repo,
        patch("app.services.attendance_service._attendance_repo") as attendance_repo,
        patch("app.services.attendance_service._enrollment_repo") as enrollment_repo,
        patch("app.services.attendance_service._subject_repo") as subject_repo,
        patch("app.services.attendance_service.validate_device") as validate_dev,
        patch("app.services.attendance_service.verify_session_token") as verify_token,
        patch("app.services.attendance_service.notification_service") as notif,
    ):
        session_repo.get_by_id.return_value = active_session
        user_repo.get_by_id.return_value = {
            "id": "student-001",
            "full_name": "Test Student",
            "student_id_number": "T001",
            "is_active": True,
        }
        enrollment_repo.is_enrolled.return_value = True
        validate_dev.return_value = {"id": "dev-001", "device_fingerprint": "fp-001"}
        attendance_repo.has_marked.return_value = False

        verify_token.return_value = True
        attendance_repo.insert.return_value = {
            "id": "record-001",
            "session_id": "session-001",
            "student_id": "student-001",
            "status": "present",
            "marked_at": now.isoformat(),
            "verified_at": now.isoformat(),
            "biometric_verified": True,
            "verification_method": "ble_biometric",
            "beacon_token": "tok123",
            "device_fingerprint": "fp-001",
            "created_at": now.isoformat(),
        }
        subject_repo.get_by_id.return_value = {"name": "IoT Systems"}

        yield {
            "session_repo": session_repo,
            "attendance_repo": attendance_repo,
            "enrollment_repo": enrollment_repo,
            "subject_repo": subject_repo,
            "validate_device": validate_dev,
            "verify_token": verify_token,
            "notification_service": notif,
        }


class TestSubmitAttendance:
    """Tests for the 8-step attendance validation pipeline."""

    def test_successful_attendance(self, mock_repos):
        """All validations pass → attendance recorded."""
        result = submit_attendance(
            student_id="student-001",
            session_id="session-001",
            beacon_token="tok123",
            device_fingerprint="fp-001",
            biometric_verified=True,
        )
        assert result["id"] == "record-001"
        assert result["status"] == "present"
        mock_repos["attendance_repo"].insert.assert_called_once()

    def test_session_not_found(self, mock_repos):
        """Missing session → NotFoundError."""
        mock_repos["session_repo"].get_by_id.return_value = None

        with pytest.raises(NotFoundError, match="AttendanceSession"):
            submit_attendance(
                student_id="student-001",
                session_id="nonexistent",
                beacon_token="tok123",
                device_fingerprint="fp-001",
            )

    def test_session_not_active(self, mock_repos):
        """Completed session → SessionNotActiveError."""
        mock_repos["session_repo"].get_by_id.return_value = {
            "id": "session-001",
            "status": "completed",
            "subject_id": "subject-001",
            "classroom_id": "classroom-001",
            "started_at": datetime.now(UTC).isoformat(),
            "expires_at": datetime.now(UTC).isoformat(),
            "total_present": 0,
        }

        with pytest.raises(SessionNotActiveError):
            submit_attendance(
                student_id="student-001",
                session_id="session-001",
                beacon_token="tok123",
                device_fingerprint="fp-001",
            )

    def test_session_expired(self, mock_repos):
        """Expired session → SessionExpiredError."""
        past = datetime.now(UTC) - timedelta(hours=1)
        mock_repos["session_repo"].get_by_id.return_value = {
            "id": "session-001",
            "status": "active",
            "subject_id": "subject-001",
            "classroom_id": "classroom-001",
            "started_at": (past - timedelta(hours=1)).isoformat(),
            "expires_at": past.isoformat(),
            "total_present": 0,
        }

        with pytest.raises(SessionExpiredError):
            submit_attendance(
                student_id="student-001",
                session_id="session-001",
                beacon_token="tok123",
                device_fingerprint="fp-001",
            )

    def test_not_enrolled(self, mock_repos):
        """Student not enrolled → EnrollmentRequiredError.

        The enrollment check is feature-flagged by
        get_settings().enforce_subject_enrollment (default False).
        Patch it to True so the guard actually executes in tests.
        """
        mock_repos["enrollment_repo"].is_enrolled.return_value = False

        with patch(
            "app.services.attendance_service.get_settings"
        ) as mock_settings:
            mock_settings.return_value.enforce_subject_enrollment = True
            with pytest.raises(EnrollmentRequiredError):
                submit_attendance(
                    student_id="student-001",
                    session_id="session-001",
                    beacon_token="tok123",
                    device_fingerprint="fp-001",
                )

    def test_duplicate_attendance(self, mock_repos):
        """Already marked → DuplicateAttendanceError."""
        mock_repos["attendance_repo"].has_marked.return_value = True

        with pytest.raises(DuplicateAttendanceError):
            submit_attendance(
                student_id="student-001",
                session_id="session-001",
                beacon_token="tok123",
                device_fingerprint="fp-001",
            )

    def test_invalid_token(self, mock_repos):
        """Wrong beacon token → InvalidTokenError."""
        mock_repos["verify_token"].return_value = False

        with pytest.raises(InvalidTokenError):
            submit_attendance(
                student_id="student-001",
                session_id="session-001",
                beacon_token="wrong-token",
                device_fingerprint="fp-001",
            )
