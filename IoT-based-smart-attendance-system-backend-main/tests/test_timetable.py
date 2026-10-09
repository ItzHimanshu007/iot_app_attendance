"""Tests for the Timetable API router (Phase 4.1)."""

from __future__ import annotations

from datetime import UTC, datetime
from unittest.mock import patch

import pytest


@pytest.fixture()
def mock_timetable_repo():
    """Patch the timetable repository."""
    with patch("app.services.timetable_service._timetable_repo") as mock:
        yield mock


@pytest.fixture()
def mock_session_repo():
    """Patch the session repository."""
    with patch("app.services.timetable_service._session_repo") as mock:
        yield mock


class TestTimetableAPI:
    """Integration and authorization tests for GET /api/v1/timetable."""

    # Mock timetable slots database records
    MOCK_SLOTS = [
        {
            "id": "slot-1",
            "teacher_id": "teacher-001",
            "subject_id": "subject-1",
            "classroom_id": "classroom-1",
            "day_of_week": 4,
            "start_time": "09:00:00",
            "end_time": "10:00:00",
            "is_active": True,
            "subject": {"name": "Software Engineering"},
            "classroom": {"name": "Room 101"},
            "effective_until": None,
        },
        {
            "id": "slot-2",
            "teacher_id": "teacher-001",
            "subject_id": "subject-2",
            "classroom_id": "classroom-2",
            "day_of_week": 4,
            "start_time": "11:00:00",
            "end_time": "12:30:00",
            "is_active": True,
            "subject": {"name": "Database Systems"},
            "classroom": {"name": "Room 102"},
            "effective_until": "2026-12-31",
        },
        {
            "id": "slot-other",
            "teacher_id": "teacher-999",
            "subject_id": "subject-3",
            "classroom_id": "classroom-3",
            "day_of_week": 4,
            "start_time": "14:00:00",
            "end_time": "15:00:00",
            "is_active": True,
            "subject": {"name": "Compiler Design"},
            "classroom": {"name": "Room 103"},
            "effective_until": None,
        },
    ]

    def test_teacher_receives_only_own_timetable(self, teacher_client, mock_timetable_repo):
        """Teachers only receive timetable slots that belong to them."""
        # Mock get_teacher_timetable to return only teacher-001's slots
        teacher_slots = [s for s in self.MOCK_SLOTS if s["teacher_id"] == "teacher-001"]
        mock_timetable_repo.get_teacher_timetable.return_value = teacher_slots

        response = teacher_client.get("/api/v1/timetable/")
        assert response.status_code == 200, response.text
        data = response.json()
        assert len(data) == 2
        assert data[0]["id"] == "slot-1"
        assert data[0]["subject_name"] == "Software Engineering"
        assert data[0]["classroom_name"] == "Room 101"
        assert data[0]["duration_minutes"] == 60
        assert data[1]["id"] == "slot-2"
        assert data[1]["duration_minutes"] == 90

        mock_timetable_repo.get_teacher_timetable.assert_called_once_with("teacher-001")
        mock_timetable_repo.get_all_active_timetable.assert_not_called()

    def test_admin_receives_all_timetable_entries(self, admin_client, mock_timetable_repo):
        """Admins receive all active timetable slots across all teachers."""
        mock_timetable_repo.get_all_active_timetable.return_value = self.MOCK_SLOTS

        response = admin_client.get("/api/v1/timetable/")
        assert response.status_code == 200, response.text
        data = response.json()
        assert len(data) == 3
        mock_timetable_repo.get_all_active_timetable.assert_called_once()

    def test_student_is_rejected_with_403(self, student_client):
        """Students are not allowed to access the timetable and receive 403 Forbidden."""
        response = student_client.get("/api/v1/timetable/")
        assert response.status_code == 403
        assert "not authorized" in response.json()["error"]["message"].lower()

    def test_empty_timetable_returns_empty_list(self, teacher_client, mock_timetable_repo):
        """An empty timetable slot database returns a 200 with an empty list."""
        mock_timetable_repo.get_teacher_timetable.return_value = []

        response = teacher_client.get("/api/v1/timetable/")
        assert response.status_code == 200
        assert response.json() == []

    def test_today_timetable_filters_correctly(self, teacher_client, mock_timetable_repo):
        """Today's timetable filters by weekday, sorts by start_time, and ignores expired slots."""
        # slot-2 expired, slot-1 active, slot-3 active
        today_slots = [
            {
                "id": "slot-1",
                "teacher_id": "teacher-001",
                "subject_id": "subject-1",
                "classroom_id": "classroom-1",
                "day_of_week": 4,  # Thursday
                "start_time": "14:00:00",
                "end_time": "15:00:00",
                "is_active": True,
                "subject": {"name": "Software Engineering"},
                "classroom": {"name": "Room 101"},
                "effective_until": None,
            },
            {
                "id": "slot-2-expired",
                "teacher_id": "teacher-001",
                "subject_id": "subject-2",
                "classroom_id": "classroom-2",
                "day_of_week": 4,  # Thursday
                "start_time": "09:00:00",
                "end_time": "10:00:00",
                "is_active": True,
                "subject": {"name": "Expired Class"},
                "classroom": {"name": "Room 102"},
                "effective_until": "2026-07-08",  # Expired yesterday
            },
            {
                "id": "slot-3",
                "teacher_id": "teacher-001",
                "subject_id": "subject-3",
                "classroom_id": "classroom-3",
                "day_of_week": 4,  # Thursday
                "start_time": "11:00:00",
                "end_time": "12:00:00",
                "is_active": True,
                "subject": {"name": "Database Systems"},
                "classroom": {"name": "Room 103"},
                "effective_until": None,
            },
        ]
        mock_timetable_repo.get_today_timetable.return_value = today_slots

        # Thursday, July 9th 2026
        fixed_dt = datetime(2026, 7, 9, 10, 0, 0, tzinfo=UTC)

        with patch("app.services.timetable_service.datetime") as mock_datetime:
            mock_datetime.now.return_value = fixed_dt
            mock_datetime.combine = datetime.combine

            response = teacher_client.get("/api/v1/timetable/today")
            assert response.status_code == 200, response.text
            data = response.json()

            # Should filter out slot-2-expired, and sort by start_time ascending (slot-3 starts at 11:00, slot-1 at 14:00)
            assert len(data) == 2
            assert data[0]["id"] == "slot-3"
            assert data[1]["id"] == "slot-1"

            mock_timetable_repo.get_today_timetable.assert_called_once_with(4, "teacher-001")

    def test_upcoming_timetable_filters_correctly(self, teacher_client, mock_timetable_repo, mock_session_repo):
        """Upcoming classes exclude past classes, completed sessions, and cancelled sessions."""
        today_slots = [
            {
                "id": "slot-past",  # starts at 09:00, current time is 10:00 -> past (expired)
                "teacher_id": "teacher-001",
                "subject_id": "subj-1",
                "classroom_id": "class-1",
                "day_of_week": 4,
                "start_time": "09:00:00",
                "end_time": "10:00:00",
                "is_active": True,
                "subject": {"name": "Past Class"},
                "classroom": {"name": "Room 1"},
                "effective_until": None,
            },
            {
                "id": "slot-completed",  # starts at 11:00, but has completed session today -> exclude
                "teacher_id": "teacher-001",
                "subject_id": "subj-2",
                "classroom_id": "class-2",
                "day_of_week": 4,
                "start_time": "11:00:00",
                "end_time": "12:00:00",
                "is_active": True,
                "subject": {"name": "Completed Class"},
                "classroom": {"name": "Room 2"},
                "effective_until": None,
            },
            {
                "id": "slot-cancelled",  # starts at 13:00, but has cancelled session today -> exclude
                "teacher_id": "teacher-001",
                "subject_id": "subj-3",
                "classroom_id": "class-3",
                "day_of_week": 4,
                "start_time": "13:00:00",
                "end_time": "14:00:00",
                "is_active": True,
                "subject": {"name": "Cancelled Class"},
                "classroom": {"name": "Room 3"},
                "effective_until": None,
            },
            {
                "id": "slot-upcoming-valid",  # starts at 15:00, no session -> include
                "teacher_id": "teacher-001",
                "subject_id": "subj-4",
                "classroom_id": "class-4",
                "day_of_week": 4,
                "start_time": "15:00:00",
                "end_time": "16:00:00",
                "is_active": True,
                "subject": {"name": "Valid Upcoming Class"},
                "classroom": {"name": "Room 4"},
                "effective_until": None,
            },
        ]
        mock_timetable_repo.get_today_timetable.return_value = today_slots

        # Mock sessions today
        mock_session_repo.list_sessions_for_date.return_value = [
            {
                "id": "sess-completed",
                "timetable_id": "slot-completed",
                "status": "completed",
                "started_at": "2026-07-09T11:00:00+00:00",
            },
            {
                "id": "sess-cancelled",
                "timetable_id": "slot-cancelled",
                "status": "cancelled",
                "started_at": "2026-07-09T13:00:00+00:00",
            },
        ]

        # Thursday, July 9th 2026 at 10:00:00 UTC
        fixed_dt = datetime(2026, 7, 9, 10, 0, 0, tzinfo=UTC)

        with patch("app.services.timetable_service.datetime") as mock_datetime:
            mock_datetime.now.return_value = fixed_dt
            mock_datetime.combine = datetime.combine

            response = teacher_client.get("/api/v1/timetable/upcoming")
            assert response.status_code == 200, response.text
            data = response.json()

            # Should only return slot-upcoming-valid
            assert len(data) == 1
            assert data[0]["id"] == "slot-upcoming-valid"
            assert data[0]["subject_name"] == "Valid Upcoming Class"

            mock_session_repo.list_sessions_for_date.assert_called_once_with("2026-07-09")
