"""Tests for the read-only Session Roster API."""

from __future__ import annotations

from unittest.mock import patch

import pytest


@pytest.fixture()
def mock_roster_repos():
    """Mock all repositories used in subject resolution and roster loading."""
    with (
        patch("app.services.session_service._session_repo") as session_repo,
        patch("app.services.session_service._classroom_repo") as classroom_repo,
        patch("app.services.session_service._timetable_repo") as timetable_repo,
        patch("app.services.session_service._subject_repo") as subject_repo,
        patch("app.services.roster_service._enrollment_repo") as enrollment_repo,
        patch("app.services.roster_service._attendance_repo") as attendance_repo,
    ):
        yield {
            "session_repo": session_repo,
            "classroom_repo": classroom_repo,
            "timetable_repo": timetable_repo,
            "subject_repo": subject_repo,
            "enrollment_repo": enrollment_repo,
            "attendance_repo": attendance_repo,
        }


class TestSessionRosterAuth:
    """Verify authorization constraints on the Roster endpoint."""

    def test_student_blocked(self, student_client, mock_roster_repos):
        """Students should be blocked from accessing any roster (403)."""
        response = student_client.get("/api/v1/sessions/session-123/roster")
        assert response.status_code == 403
        assert response.json()["error"]["code"] == "FORBIDDEN"

    def test_unauthenticated_blocked(self, client):
        """Unauthenticated requests are blocked (401)."""
        response = client.get("/api/v1/sessions/session-123/roster")
        assert response.status_code == 401
        assert response.json()["error"]["code"] == "UNAUTHORIZED"

    def test_teacher_owns_session(self, teacher_client, mock_roster_repos):
        """Teachers can fetch the roster of a session they own."""
        mock_roster_repos["session_repo"].get_by_id.return_value = {
            "id": "session-123",
            "teacher_id": "teacher-001",  # Matches TEACHER_USER in conftest.py
            "classroom_id": "classroom-123",
            "status": "active",
            "subject_name": "CS 101",
            "timetable_id": "timetable-123",
            "started_at": "2026-07-01T08:00:00+00:00",
        }
        mock_roster_repos["classroom_repo"].get_by_id.return_value = {
            "id": "classroom-123",
            "name": "Room 404",
        }
        mock_roster_repos["timetable_repo"].get_by_id.return_value = {
            "id": "timetable-123",
            "subject_id": "subject-123",
        }
        mock_roster_repos["enrollment_repo"].get_subject_students_with_profiles.return_value = []
        mock_roster_repos["attendance_repo"].list_by_session.return_value = []

        response = teacher_client.get("/api/v1/sessions/session-123/roster")
        assert response.status_code == 200

    def test_teacher_does_not_own_session(self, teacher_client, mock_roster_repos):
        """Teachers cannot query other teachers' sessions."""
        mock_roster_repos["session_repo"].get_by_id.return_value = {
            "id": "session-123",
            "teacher_id": "teacher-999",  # Mismatch
            "classroom_id": "classroom-123",
            "status": "active",
            "subject_name": "CS 101",
            "timetable_id": "timetable-123",
            "started_at": "2026-07-01T08:00:00+00:00",
        }

        response = teacher_client.get("/api/v1/sessions/session-123/roster")
        assert response.status_code == 403
        assert response.json()["error"]["code"] == "FORBIDDEN"

    def test_admin_bypass_ownership(self, admin_client, mock_roster_repos):
        """Admins bypass ownership checks and can retrieve any session roster."""
        mock_roster_repos["session_repo"].get_by_id.return_value = {
            "id": "session-123",
            "teacher_id": "teacher-999",  # Mismatches admin-001, but admin role overrides
            "classroom_id": "classroom-123",
            "status": "active",
            "subject_name": "CS 101",
            "timetable_id": "timetable-123",
            "started_at": "2026-07-01T08:00:00+00:00",
        }
        mock_roster_repos["classroom_repo"].get_by_id.return_value = {
            "id": "classroom-123",
            "name": "Room 404",
        }
        mock_roster_repos["timetable_repo"].get_by_id.return_value = {
            "id": "timetable-123",
            "subject_id": "subject-123",
        }
        mock_roster_repos["enrollment_repo"].get_subject_students_with_profiles.return_value = []
        mock_roster_repos["attendance_repo"].list_by_session.return_value = []

        response = admin_client.get("/api/v1/sessions/session-123/roster")
        assert response.status_code == 200


class TestSessionRosterData:
    """Verify roster generation logic, subject resolution, and formatting."""

    def test_valid_empty_roster(self, teacher_client, mock_roster_repos):
        """If resolved subject has no active enrollments, return empty roster (200)."""
        mock_roster_repos["session_repo"].get_by_id.return_value = {
            "id": "session-123",
            "teacher_id": "teacher-001",
            "classroom_id": "classroom-123",
            "status": "active",
            "subject_name": "CS 101",
            "timetable_id": "timetable-123",
            "started_at": "2026-07-01T08:00:00+00:00",
        }
        mock_roster_repos["classroom_repo"].get_by_id.return_value = {
            "id": "classroom-123",
            "name": "Room 404",
        }
        mock_roster_repos["timetable_repo"].get_by_id.return_value = {
            "id": "timetable-123",
            "subject_id": "subject-123",
        }
        mock_roster_repos["enrollment_repo"].get_subject_students_with_profiles.return_value = []
        mock_roster_repos["attendance_repo"].list_by_session.return_value = []

        response = teacher_client.get("/api/v1/sessions/session-123/roster")
        assert response.status_code == 200
        data = response.json()
        assert data["summary"]["total_students"] == 0
        assert data["summary"]["present"] == 0
        assert data["summary"]["absent"] == 0
        assert data["students"] == []

    def test_roster_resolution_failure(self, teacher_client, mock_roster_repos):
        """If all subject resolution methods fail, return 200 with empty roster instead of 409 Conflict."""
        mock_roster_repos["session_repo"].get_by_id.return_value = {
            "id": "session-123",
            "teacher_id": "teacher-001",
            "classroom_id": "classroom-123",
            "status": "active",
            "subject_name": "Unmatched Subject Name",
            "timetable_id": None,
            "subject_id": None,
            "started_at": "2026-07-01T08:00:00+00:00",
        }
        mock_roster_repos["classroom_repo"].get_by_id.return_value = {
            "id": "classroom-123",
            "name": "Room 404",
        }
        mock_roster_repos["subject_repo"].get_by_name.return_value = None
        mock_roster_repos["attendance_repo"].list_by_session.return_value = []

        response = teacher_client.get("/api/v1/sessions/session-123/roster")
        assert response.status_code == 200
        data = response.json()
        assert data["summary"]["total_students"] == 0
        assert data["students"] == []


    def test_mixed_attendance_mapping_and_sorting(self, teacher_client, mock_roster_repos):
        """Verify sorting, status calculations, and exclusion of inactive profiles."""
        mock_roster_repos["session_repo"].get_by_id.return_value = {
            "id": "session-123",
            "teacher_id": "teacher-001",
            "classroom_id": "classroom-123",
            "status": "active",
            "subject_name": "CS 101",
            "timetable_id": None,
            "subject_id": "subject-123",
            "started_at": "2026-07-01T08:00:00+00:00",
        }
        mock_roster_repos["classroom_repo"].get_by_id.return_value = {
            "id": "classroom-123",
            "name": "Room 404",
        }
        # 4 enrolled students: Charlie, Bob, Alice, and an inactive student (should be filtered)
        mock_roster_repos["enrollment_repo"].get_subject_students_with_profiles.return_value = [
            {
                "student_id": "charlie-id",
                "student": {"id": "charlie-id", "full_name": "Charlie Brown", "student_id_number": "C03", "is_active": True},
            },
            {
                "student_id": "bob-id",
                "student": {"id": "bob-id", "full_name": "Bob Smith", "student_id_number": "B02", "is_active": True},
            },
            {
                "student_id": "alice-id",
                "student": {"id": "alice-id", "full_name": "Alice Johnson", "student_id_number": "A01", "is_active": True},
            },
            {
                "student_id": "inactive-id",
                "student": {"id": "inactive-id", "full_name": "Inactive Student", "student_id_number": "I04", "is_active": False},
            },
        ]
        # Present and Late records
        mock_roster_repos["attendance_repo"].list_by_session.return_value = [
            {"student_id": "alice-id", "status": "present", "marked_at": "2026-07-01T08:02:00+00:00"},
            {"student_id": "bob-id", "status": "late", "marked_at": "2026-07-01T08:20:00+00:00"},
        ]

        response = teacher_client.get("/api/v1/sessions/session-123/roster")
        assert response.status_code == 200
        data = response.json()

        # Inactive student is filtered, leaving Alice, Bob, Charlie (3 students total)
        assert data["summary"]["total_students"] == 3
        assert data["summary"]["present"] == 2  # Alice (present) + Bob (late)
        assert data["summary"]["absent"] == 1   # Charlie (absent)

        students = data["students"]
        # Assert alphabetical sorting: Alice -> Bob -> Charlie
        assert students[0]["full_name"] == "Alice Johnson"
        assert students[0]["attendance_status"] == "present"
        assert students[0]["marked_at"] == "2026-07-01T08:02:00Z"

        assert students[1]["full_name"] == "Bob Smith"
        assert students[1]["attendance_status"] == "late"
        assert students[1]["marked_at"] == "2026-07-01T08:20:00Z"

        assert students[2]["full_name"] == "Charlie Brown"
        assert students[2]["attendance_status"] == "absent"
        assert students[2]["marked_at"] is None

    def test_subject_resolution_hierarchy(self, teacher_client, mock_roster_repos):
        """Validate the precedence: Timetable -> direct subject_id -> fallback name match."""
        # Scenario A: Timetable has highest priority
        mock_roster_repos["session_repo"].get_by_id.return_value = {
            "id": "session-123",
            "teacher_id": "teacher-001",
            "classroom_id": "classroom-123",
            "status": "active",
            "subject_name": "CS 101",
            "timetable_id": "timetable-123",
            "subject_id": "direct-subject-id",
            "started_at": "2026-07-01T08:00:00+00:00",
        }
        mock_roster_repos["classroom_repo"].get_by_id.return_value = {
            "id": "classroom-123",
            "name": "Room 404",
        }
        mock_roster_repos["timetable_repo"].get_by_id.return_value = {
            "id": "timetable-123",
            "subject_id": "timetable-subject-id",
        }
        mock_roster_repos["enrollment_repo"].get_subject_students_with_profiles.return_value = []
        mock_roster_repos["attendance_repo"].list_by_session.return_value = []

        response = teacher_client.get("/api/v1/sessions/session-123/roster")
        assert response.status_code == 200
        mock_roster_repos["enrollment_repo"].get_subject_students_with_profiles.assert_called_with("timetable-subject-id")

        # Scenario B: Direct subject_id is used if timetable_id is missing
        mock_roster_repos["session_repo"].get_by_id.return_value = {
            "id": "session-123",
            "teacher_id": "teacher-001",
            "classroom_id": "classroom-123",
            "status": "active",
            "subject_name": "CS 101",
            "timetable_id": None,
            "subject_id": "direct-subject-id",
            "started_at": "2026-07-01T08:00:00+00:00",
        }
        response = teacher_client.get("/api/v1/sessions/session-123/roster")
        assert response.status_code == 200
        mock_roster_repos["enrollment_repo"].get_subject_students_with_profiles.assert_called_with("direct-subject-id")

        # Scenario C: Name matching is used as fallback if both are missing
        mock_roster_repos["session_repo"].get_by_id.return_value = {
            "id": "session-123",
            "teacher_id": "teacher-001",
            "classroom_id": "classroom-123",
            "status": "active",
            "subject_name": "CS 101 Name",
            "timetable_id": None,
            "subject_id": None,
            "started_at": "2026-07-01T08:00:00+00:00",
        }
        mock_roster_repos["subject_repo"].get_by_name.return_value = {
            "id": "fallback-subject-id",
            "name": "CS 101 Name",
        }
        response = teacher_client.get("/api/v1/sessions/session-123/roster")
        assert response.status_code == 200
        mock_roster_repos["subject_repo"].get_by_name.assert_called_with("CS 101 Name")
        mock_roster_repos["enrollment_repo"].get_subject_students_with_profiles.assert_called_with("fallback-subject-id")


class TestSessionRosterHardening:
    """Tests for Phase 3.2.1 — Production API Hardening."""

    @pytest.fixture()
    def mixed_roster_setup(self, mock_roster_repos):
        """Prepare a list of 15 students with specific roll numbers and names."""
        mock_roster_repos["session_repo"].get_by_id.return_value = {
            "id": "session-123",
            "teacher_id": "teacher-001",
            "classroom_id": "classroom-123",
            "status": "active",
            "subject_name": "CS 101",
            "timetable_id": None,
            "subject_id": "subject-123",
            "started_at": "2026-07-01T08:00:00+00:00",
        }
        mock_roster_repos["classroom_repo"].get_by_id.return_value = {
            "id": "classroom-123",
            "name": "Room 404",
        }

        # 15 students with unsorted names and mixed natural roll numbers
        mock_roster_repos["enrollment_repo"].get_subject_students_with_profiles.return_value = [
            {"student_id": "s1", "student": {"id": "s1", "full_name": "Student A", "student_id_number": "22AIDS010", "is_active": True}},
            {"student_id": "s2", "student": {"id": "s2", "full_name": "Student B", "student_id_number": "22AIDS002", "is_active": True}},
            {"student_id": "s3", "student": {"id": "s3", "full_name": "Student C", "student_id_number": "22AIDS001", "is_active": True}},
            {"student_id": "s4", "student": {"id": "s4", "full_name": "Student D", "student_id_number": None, "is_active": True}},
            {"student_id": "s5", "student": {"id": "s5", "full_name": "Student E", "student_id_number": "22AIDS001A", "is_active": True}},
            {"student_id": "s6", "student": {"id": "s6", "full_name": "Student F", "student_id_number": "22AIDS015", "is_active": True}},
            {"student_id": "s7", "student": {"id": "s7", "full_name": "Student G", "student_id_number": "22AIDS011", "is_active": True}},
            {"student_id": "s8", "student": {"id": "s8", "full_name": "Student H", "student_id_number": "22AIDS008", "is_active": True}},
            {"student_id": "s9", "student": {"id": "s9", "full_name": "Student I", "student_id_number": "22AIDS009", "is_active": True}},
            {"student_id": "s10", "student": {"id": "s10", "full_name": "Student J", "student_id_number": "22AIDS004", "is_active": True}},
            {"student_id": "s11", "student": {"id": "s11", "full_name": "Student K", "student_id_number": "22AIDS003", "is_active": True}},
            {"student_id": "s12", "student": {"id": "s12", "full_name": "Student L", "student_id_number": "22AIDS007", "is_active": True}},
            {"student_id": "s13", "student": {"id": "s13", "full_name": "Student M", "student_id_number": "22AIDS006", "is_active": True}},
            {"student_id": "s14", "student": {"id": "s14", "full_name": "Student N", "student_id_number": "22AIDS005", "is_active": True}},
            {"student_id": "s15", "student": {"id": "s15", "full_name": "Student O", "student_id_number": "22AIDS012", "is_active": True}},
        ]

        # Attendance records: s2 is marked manual, s3 is marked normal BLE, others are absent
        mock_roster_repos["attendance_repo"].list_by_session.return_value = [
            {"student_id": "s2", "status": "present", "marked_at": "2026-07-01T08:02:00+00:00", "verification_method": "manual"},
            {"student_id": "s3", "status": "present", "marked_at": "2026-07-01T08:05:00+00:00", "verification_method": "ble_only"},
        ]

    def test_default_sorting_by_roll(self, teacher_client, mock_roster_repos, mixed_roster_setup):
        """Default sort should be by roll number naturally, with None at the end."""
        response = teacher_client.get("/api/v1/sessions/session-123/roster")
        assert response.status_code == 200
        data = response.json()
        students = data["students"]

        # Expected order (first 5 and last 2 verified):
        # 1. 22AIDS001 (Student C)
        # 2. 22AIDS001A (Student E)
        # 3. 22AIDS002 (Student B)
        # 4. 22AIDS003 (Student K)
        # 5. 22AIDS004 (Student J)
        # ...
        # 14. 22AIDS015 (Student F)
        # 15. None (Student D)
        assert students[0]["roll_number"] == "22AIDS001"
        assert students[0]["full_name"] == "Student C"
        assert students[1]["roll_number"] == "22AIDS001A"
        assert students[1]["full_name"] == "Student E"
        assert students[2]["roll_number"] == "22AIDS002"
        assert students[2]["full_name"] == "Student B"
        assert students[3]["roll_number"] == "22AIDS003"
        assert students[3]["full_name"] == "Student K"
        assert students[4]["roll_number"] == "22AIDS004"
        assert students[4]["full_name"] == "Student J"
        assert students[13]["roll_number"] == "22AIDS015"
        assert students[13]["full_name"] == "Student F"
        assert students[14]["roll_number"] is None
        assert students[14]["full_name"] == "Student D"

    def test_sorting_by_name(self, teacher_client, mock_roster_repos, mixed_roster_setup):
        """Explicit sort=name should sort alphabetically case-insensitively."""
        response = teacher_client.get("/api/v1/sessions/session-123/roster?sort=name")
        assert response.status_code == 200
        data = response.json()
        students = data["students"]

        # Expected order: Student A to Student O
        assert students[0]["full_name"] == "Student A"
        assert students[1]["full_name"] == "Student B"
        assert students[2]["full_name"] == "Student C"
        assert students[13]["full_name"] == "Student N"
        assert students[14]["full_name"] == "Student O"

    def test_manual_attendance_flags(self, teacher_client, mock_roster_repos, mixed_roster_setup):
        """Verify is_manual is mapped based on verification_method."""
        response = teacher_client.get("/api/v1/sessions/session-123/roster?sort=name")
        assert response.status_code == 200
        data = response.json()
        students = data["students"]

        # Student B is manual -> is_manual should be True
        student_b = next(s for s in students if s["full_name"] == "Student B")
        assert student_b["is_manual"] is True

        # Student C is BLE -> is_manual should be False
        student_c = next(s for s in students if s["full_name"] == "Student C")
        assert student_c["is_manual"] is False

        # Student D has no record -> is_manual should be False
        student_d = next(s for s in students if s["full_name"] == "Student D")
        assert student_d["is_manual"] is False

    def test_pagination_page_1(self, teacher_client, mock_roster_repos, mixed_roster_setup):
        """Page 1 of page_size=10 should return first ten elements and pagination metadata."""
        response = teacher_client.get("/api/v1/sessions/session-123/roster?page=1&page_size=10")
        assert response.status_code == 200
        data = response.json()

        assert data["pagination"] == {
            "page": 1,
            "page_size": 10,
            "total_students": 15,
            "total_pages": 2,
        }
        students = data["students"]
        assert len(students) == 10
        # Default sort is roll:
        # First should be Student C (22AIDS001), 10th should be Student I (22AIDS009)
        assert students[0]["full_name"] == "Student C"
        assert students[9]["full_name"] == "Student I"

    def test_pagination_page_2(self, teacher_client, mock_roster_repos, mixed_roster_setup):
        """Page 2 of page_size=10 should return remaining five elements."""
        response = teacher_client.get("/api/v1/sessions/session-123/roster?page=2&page_size=10")
        assert response.status_code == 200
        data = response.json()

        assert data["pagination"] == {
            "page": 2,
            "page_size": 10,
            "total_students": 15,
            "total_pages": 2,
        }
        students = data["students"]
        assert len(students) == 5
        # Default sort is roll:
        # 11th should be Student A (22AIDS010), 15th should be Student D (None)
        assert students[0]["full_name"] == "Student A"
        assert students[4]["full_name"] == "Student D"

    def test_pagination_page_out_of_bounds(self, teacher_client, mock_roster_repos, mixed_roster_setup):
        """Page higher than total pages should return empty list but valid metadata."""
        response = teacher_client.get("/api/v1/sessions/session-123/roster?page=3&page_size=10")
        assert response.status_code == 200
        data = response.json()

        assert data["pagination"] == {
            "page": 3,
            "page_size": 10,
            "total_students": 15,
            "total_pages": 2,
        }
        assert data["students"] == []

    def test_invalid_page_fails(self, teacher_client, mock_roster_repos, mixed_roster_setup):
        """Page < 1 should return 422 ValidationError."""
        response = teacher_client.get("/api/v1/sessions/session-123/roster?page=0")
        assert response.status_code == 422

    def test_invalid_page_size_fails(self, teacher_client, mock_roster_repos, mixed_roster_setup):
        """page_size outside 10..200 should return 422 ValidationError."""
        response = teacher_client.get("/api/v1/sessions/session-123/roster?page_size=5")
        assert response.status_code == 422

        response = teacher_client.get("/api/v1/sessions/session-123/roster?page_size=300")
        assert response.status_code == 422

    def test_invalid_sort_value_fails(self, teacher_client, mock_roster_repos, mixed_roster_setup):
        """Sort value other than roll/name should return 422 ValidationError."""
        response = teacher_client.get("/api/v1/sessions/session-123/roster?sort=invalid_sort")
        assert response.status_code == 422

