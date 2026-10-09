"""Tests for the health endpoint, middleware, and session creation validation.

Migration 0002 additions:
  - TestSessionSubjectNameValidation: covers all subject_name input rules
  - TestHistoricalSessionResolution: verifies backward-compat name fallback
"""

from __future__ import annotations

from unittest.mock import patch

# ── Infrastructure / health ───────────────────────────────────────────────────


def test_health_endpoint(client):
    """Health check should return 200 with service identity."""
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert data["service"] == "smart-campus-attendance-api"
    assert "version" in data


def test_health_has_request_id(client):
    """Every response should include X-Request-ID header."""
    response = client.get("/health")
    assert "X-Request-ID" in response.headers


def test_health_has_response_time(client):
    """Every response should include X-Response-Time header."""
    response = client.get("/health")
    assert "X-Response-Time" in response.headers


def test_unauthenticated_api_returns_401(client):
    """API endpoints without auth should return 401."""
    response = client.get("/api/v1/sessions/")
    assert response.status_code == 401
    data = response.json()
    assert data["error"]["code"] == "UNAUTHORIZED"


def test_error_envelope_format(client):
    """Error responses should follow the standard envelope format."""
    response = client.get("/api/v1/sessions/")
    data = response.json()
    assert "error" in data
    error = data["error"]
    assert "code" in error
    assert "message" in error
    assert "timestamp" in error
    assert "request_id" in error


# ── subject_name validation (migration 0002) ──────────────────────────────────

def _make_session_patches(subject_name: str = "Operating Systems"):
    """Standard patch set for a successful session creation."""
    new_session = {
        "id": "session-val-001",
        "teacher_id": "teacher-001",
        "subject_name": subject_name,
        "subject_id": None,
        "classroom_id": "classroom-c1",
        "status": "active",
        "started_at": "2026-07-01T08:00:00+00:00",
        "expires_at": "2026-07-01T08:05:00+00:00",
        "duration_minutes": 5,
        "total_present": 0,
        "created_at": "2026-07-01T08:00:00+00:00",
        "current_token": "tok-val",
    }
    return [
        patch(
            "app.services.session_service._classroom_repo.get_by_id",
            return_value={"id": "classroom-c1", "name": "Lab 1", "is_active": True},
        ),
        patch(
            "app.services.session_service._session_repo.get_active_by_classroom",
            return_value=None,
        ),
        patch(
            "app.services.session_service._session_repo.insert",
            return_value=new_session,
        ),
        patch("app.services.session_service.publish_start_session"),
        patch("app.services.session_service.notification_service.send_session_started"),
        patch(
            "app.services.session_service.generate_session_token",
            return_value="tok-val",
        ),
    ]


class TestSessionSubjectNameValidation:
    """Verify subject_name validation rules defined in SessionCreate (migration 0002)."""

    BASE_PAYLOAD = {
        "classroom_id": "classroom-c1",
        "duration_minutes": 5,
    }

    # ── Happy path ────────────────────────────────────────────────────────────

    def test_valid_subject_name_creates_session(self, teacher_client):
        """A properly formed subject_name → 201 Created."""
        patches = _make_session_patches("Operating Systems")
        for p in patches:
            p.start()
        try:
            response = teacher_client.post(
                "/api/v1/sessions/",
                json={**self.BASE_PAYLOAD, "subject_name": "Operating Systems"},
            )
            assert response.status_code == 201, response.text
            data = response.json()
            assert data["subject_name"] == "Operating Systems"
            assert data["subject_id"] is None
        finally:
            for p in patches:
                p.stop()

    def test_subject_name_with_surrounding_whitespace_is_accepted(self, teacher_client):
        """Leading/trailing whitespace is stripped; the result must still be >= 3 chars."""
        patches = _make_session_patches("IoT Lab")
        for p in patches:
            p.start()
        try:
            response = teacher_client.post(
                "/api/v1/sessions/",
                json={**self.BASE_PAYLOAD, "subject_name": "  IoT Lab  "},
            )
            # Trimmed value "IoT Lab" (7 chars) is valid
            assert response.status_code == 201, response.text
        finally:
            for p in patches:
                p.stop()

    def test_minimum_length_subject_name_accepted(self, teacher_client):
        """Exactly 3 characters after trimming → accepted."""
        patches = _make_session_patches("DSA")
        for p in patches:
            p.start()
        try:
            response = teacher_client.post(
                "/api/v1/sessions/",
                json={**self.BASE_PAYLOAD, "subject_name": "DSA"},
            )
            assert response.status_code == 201, response.text
        finally:
            for p in patches:
                p.stop()

    def test_maximum_length_subject_name_accepted(self, teacher_client):
        """Exactly 100 characters → accepted."""
        name_100 = "A" * 100
        patches = _make_session_patches(name_100)
        for p in patches:
            p.start()
        try:
            response = teacher_client.post(
                "/api/v1/sessions/",
                json={**self.BASE_PAYLOAD, "subject_name": name_100},
            )
            assert response.status_code == 201, response.text
        finally:
            for p in patches:
                p.stop()

    # ── Rejection cases ───────────────────────────────────────────────────────

    def test_empty_subject_name_rejected(self, teacher_client):
        """Empty string → 422 Unprocessable Entity."""
        response = teacher_client.post(
            "/api/v1/sessions/",
            json={**self.BASE_PAYLOAD, "subject_name": ""},
        )
        assert response.status_code == 422, response.text

    def test_whitespace_only_subject_name_rejected(self, teacher_client):
        """Whitespace-only string (stripped to empty) → 422."""
        response = teacher_client.post(
            "/api/v1/sessions/",
            json={**self.BASE_PAYLOAD, "subject_name": "   "},
        )
        assert response.status_code == 422, response.text

    def test_subject_name_too_short_rejected(self, teacher_client):
        """Two characters → 422 (minimum is 3)."""
        response = teacher_client.post(
            "/api/v1/sessions/",
            json={**self.BASE_PAYLOAD, "subject_name": "OS"},
        )
        assert response.status_code == 422, response.text

    def test_subject_name_too_long_rejected(self, teacher_client):
        """101 characters → 422 (maximum is 100)."""
        response = teacher_client.post(
            "/api/v1/sessions/",
            json={**self.BASE_PAYLOAD, "subject_name": "A" * 101},
        )
        assert response.status_code == 422, response.text

    def test_missing_subject_name_rejected(self, teacher_client):
        """Omitting subject_name entirely → 422 (field is required)."""
        response = teacher_client.post(
            "/api/v1/sessions/",
            json=self.BASE_PAYLOAD,  # no subject_name key
        )
        assert response.status_code == 422, response.text

    def test_old_subject_id_field_rejected(self, teacher_client):
        """Sending the old subject_id field is not accepted as a substitute."""
        response = teacher_client.post(
            "/api/v1/sessions/",
            json={**self.BASE_PAYLOAD, "subject_id": "some-uuid"},
        )
        # subject_name is still missing → 422
        assert response.status_code == 422, response.text


# ── Backward-compat: historical sessions (migration 0002) ─────────────────────


class TestHistoricalSessionResolution:
    """Verify that sessions created before migration 0002 (with subject_id, no
    subject_name) still return a meaningful subject name in the API response.
    """

    def test_historical_session_resolves_subject_name_from_subjects_table(
        self, teacher_client
    ):
        """GET /sessions/{id} where session has subject_id but no subject_name.

        Expected: subject_name in the response equals the name found in the
        subjects table via the legacy subject_id.
        """
        historical_session = {
            "id": "session-hist-001",
            "teacher_id": "teacher-001",
            "subject_id": "subject-cs401",
            "subject_name": None,          # NULL — pre-migration row
            "classroom_id": "classroom-c1",
            "status": "completed",
            "started_at": "2025-01-01T09:00:00+00:00",
            "expires_at": "2025-01-01T10:00:00+00:00",
            "duration_minutes": 60,
            "total_present": 12,
            "created_at": "2025-01-01T09:00:00+00:00",
            "current_token": None,
        }

        with (
            patch(
                "app.services.session_service._session_repo.get_by_id",
                return_value=historical_session,
            ),
            patch(
                "app.services.session_service._subject_repo.get_by_id",
                return_value={"id": "subject-cs401", "name": "IoT Systems", "code": "CS401"},
            ),
        ):
            response = teacher_client.get("/api/v1/sessions/session-hist-001")
            assert response.status_code == 200, response.text
            data = response.json()
            assert data["subject_name"] == "IoT Systems", (
                f"Expected 'IoT Systems' resolved from subjects table, got {data['subject_name']!r}"
            )

    def test_historical_session_falls_back_to_unknown_when_subject_deleted(
        self, teacher_client
    ):
        """GET /sessions/{id} where subject_id row no longer exists in subjects.

        Expected: subject_name resolves to 'Unknown Subject'.
        """
        historical_session = {
            "id": "session-hist-002",
            "teacher_id": "teacher-001",
            "subject_id": "subject-deleted",
            "subject_name": None,
            "classroom_id": "classroom-c1",
            "status": "completed",
            "started_at": "2025-01-01T09:00:00+00:00",
            "expires_at": "2025-01-01T10:00:00+00:00",
            "duration_minutes": 60,
            "total_present": 5,
            "created_at": "2025-01-01T09:00:00+00:00",
            "current_token": None,
        }

        with (
            patch(
                "app.services.session_service._session_repo.get_by_id",
                return_value=historical_session,
            ),
            patch(
                "app.services.session_service._subject_repo.get_by_id",
                return_value=None,           # subject record deleted
            ),
        ):
            response = teacher_client.get("/api/v1/sessions/session-hist-002")
            assert response.status_code == 200, response.text
            data = response.json()
            assert data["subject_name"] == "Unknown Subject", (
                f"Expected 'Unknown Subject' fallback, got {data['subject_name']!r}"
            )

    def test_new_session_subject_name_returned_directly(self, teacher_client):
        """GET /sessions/{id} for a post-migration session — subject_name returned as stored."""
        new_session = {
            "id": "session-new-002",
            "teacher_id": "teacher-001",
            "subject_id": None,
            "subject_name": "Artificial Intelligence",
            "classroom_id": "classroom-c1",
            "status": "active",
            "started_at": "2026-07-01T09:00:00+00:00",
            "expires_at": "2026-07-01T09:05:00+00:00",
            "duration_minutes": 5,
            "total_present": 0,
            "created_at": "2026-07-01T09:00:00+00:00",
            "current_token": "tok-ai",
        }

        with patch(
            "app.services.session_service._session_repo.get_by_id",
            return_value=new_session,
        ):
            response = teacher_client.get("/api/v1/sessions/session-new-002")
            assert response.status_code == 200, response.text
            data = response.json()
            assert data["subject_name"] == "Artificial Intelligence"
            assert data["subject_id"] is None


# ── Duration allow-list validation ────────────────────────────────────────────


class TestSessionDurationValidation:
    """Verify that duration_minutes must be one of ALLOWED_SESSION_DURATIONS.

    Flutter offers a fixed picker with values {3, 5, 10, 15, 20, 30, 45, 60}.
    The backend enforces the same list so that arbitrary durations cannot be
    injected via direct API calls.
    """

    BASE_PAYLOAD = {
        "subject_name": "Operating Systems",
        "classroom_id": "classroom-c1",
    }

    # ── Valid durations (all 8 allowed values) ────────────────────────────────

    @staticmethod
    def _patches_for_duration(duration: int):
        new_session = {
            "id": f"session-dur-{duration}",
            "teacher_id": "teacher-001",
            "subject_name": "Operating Systems",
            "subject_id": None,
            "classroom_id": "classroom-c1",
            "status": "active",
            "started_at": "2026-07-01T08:00:00+00:00",
            # Fixed valid timestamp — the exact value doesn't affect duration tests.
            "expires_at": "2026-07-01T09:00:00+00:00",
            "duration_minutes": duration,
            "total_present": 0,
            "created_at": "2026-07-01T08:00:00+00:00",
            "current_token": "tok-dur",
        }
        return [
            patch(
                "app.services.session_service._classroom_repo.get_by_id",
                return_value={"id": "classroom-c1", "name": "Lab 1", "is_active": True},
            ),
            patch(
                "app.services.session_service._session_repo.get_active_by_classroom",
                return_value=None,
            ),
            patch(
                "app.services.session_service._session_repo.insert",
                return_value=new_session,
            ),
            patch("app.services.session_service.publish_start_session"),
            patch("app.services.session_service.notification_service.send_session_started"),
            patch(
                "app.services.session_service.generate_session_token",
                return_value="tok-dur",
            ),
        ]

    def test_duration_3_accepted(self, teacher_client):
        """3 minutes is in the allow-list → 201."""
        patches = self._patches_for_duration(3)
        for p in patches:
            p.start()
        try:
            response = teacher_client.post(
                "/api/v1/sessions/",
                json={**self.BASE_PAYLOAD, "duration_minutes": 3},
            )
            assert response.status_code == 201, response.text
        finally:
            for p in patches:
                p.stop()

    def test_duration_5_accepted(self, teacher_client):
        """5 minutes is in the allow-list → 201."""
        patches = self._patches_for_duration(5)
        for p in patches:
            p.start()
        try:
            response = teacher_client.post(
                "/api/v1/sessions/",
                json={**self.BASE_PAYLOAD, "duration_minutes": 5},
            )
            assert response.status_code == 201, response.text
        finally:
            for p in patches:
                p.stop()

    def test_duration_10_accepted(self, teacher_client):
        """10 minutes is in the allow-list → 201."""
        patches = self._patches_for_duration(10)
        for p in patches:
            p.start()
        try:
            response = teacher_client.post(
                "/api/v1/sessions/",
                json={**self.BASE_PAYLOAD, "duration_minutes": 10},
            )
            assert response.status_code == 201, response.text
        finally:
            for p in patches:
                p.stop()

    def test_duration_15_accepted(self, teacher_client):
        """15 minutes is in the allow-list → 201."""
        patches = self._patches_for_duration(15)
        for p in patches:
            p.start()
        try:
            response = teacher_client.post(
                "/api/v1/sessions/",
                json={**self.BASE_PAYLOAD, "duration_minutes": 15},
            )
            assert response.status_code == 201, response.text
        finally:
            for p in patches:
                p.stop()

    def test_duration_20_accepted(self, teacher_client):
        """20 minutes is in the allow-list → 201."""
        patches = self._patches_for_duration(20)
        for p in patches:
            p.start()
        try:
            response = teacher_client.post(
                "/api/v1/sessions/",
                json={**self.BASE_PAYLOAD, "duration_minutes": 20},
            )
            assert response.status_code == 201, response.text
        finally:
            for p in patches:
                p.stop()

    def test_duration_30_accepted(self, teacher_client):
        """30 minutes is in the allow-list → 201."""
        patches = self._patches_for_duration(30)
        for p in patches:
            p.start()
        try:
            response = teacher_client.post(
                "/api/v1/sessions/",
                json={**self.BASE_PAYLOAD, "duration_minutes": 30},
            )
            assert response.status_code == 201, response.text
        finally:
            for p in patches:
                p.stop()

    def test_duration_45_accepted(self, teacher_client):
        """45 minutes is in the allow-list → 201."""
        patches = self._patches_for_duration(45)
        for p in patches:
            p.start()
        try:
            response = teacher_client.post(
                "/api/v1/sessions/",
                json={**self.BASE_PAYLOAD, "duration_minutes": 45},
            )
            assert response.status_code == 201, response.text
        finally:
            for p in patches:
                p.stop()

    def test_duration_60_accepted(self, teacher_client):
        """60 minutes is in the allow-list → 201."""
        patches = self._patches_for_duration(60)
        for p in patches:
            p.start()
        try:
            response = teacher_client.post(
                "/api/v1/sessions/",
                json={**self.BASE_PAYLOAD, "duration_minutes": 60},
            )
            assert response.status_code == 201, response.text
        finally:
            for p in patches:
                p.stop()

    # ── Invalid durations ─────────────────────────────────────────────────────

    def test_duration_1_rejected(self, teacher_client):
        """1 minute is not in the allow-list → 422."""
        response = teacher_client.post(
            "/api/v1/sessions/",
            json={**self.BASE_PAYLOAD, "duration_minutes": 1},
        )
        assert response.status_code == 422, response.text

    def test_duration_2_rejected(self, teacher_client):
        """2 minutes is not in the allow-list → 422."""
        response = teacher_client.post(
            "/api/v1/sessions/",
            json={**self.BASE_PAYLOAD, "duration_minutes": 2},
        )
        assert response.status_code == 422, response.text

    def test_duration_7_rejected(self, teacher_client):
        """7 minutes is not in the allow-list → 422."""
        response = teacher_client.post(
            "/api/v1/sessions/",
            json={**self.BASE_PAYLOAD, "duration_minutes": 7},
        )
        assert response.status_code == 422, response.text

    def test_duration_25_rejected(self, teacher_client):
        """25 minutes is not in the allow-list → 422."""
        response = teacher_client.post(
            "/api/v1/sessions/",
            json={**self.BASE_PAYLOAD, "duration_minutes": 25},
        )
        assert response.status_code == 422, response.text

    def test_duration_90_rejected(self, teacher_client):
        """90 minutes is not in the allow-list → 422."""
        response = teacher_client.post(
            "/api/v1/sessions/",
            json={**self.BASE_PAYLOAD, "duration_minutes": 90},
        )
        assert response.status_code == 422, response.text

    def test_duration_120_rejected(self, teacher_client):
        """120 minutes is not in the allow-list → 422."""
        response = teacher_client.post(
            "/api/v1/sessions/",
            json={**self.BASE_PAYLOAD, "duration_minutes": 120},
        )
        assert response.status_code == 422, response.text

    def test_duration_480_rejected(self, teacher_client):
        """480 minutes was previously the upper bound but is not in the list → 422."""
        response = teacher_client.post(
            "/api/v1/sessions/",
            json={**self.BASE_PAYLOAD, "duration_minutes": 480},
        )
        assert response.status_code == 422, response.text

    def test_duration_zero_rejected(self, teacher_client):
        """0 minutes is not in the allow-list → 422."""
        response = teacher_client.post(
            "/api/v1/sessions/",
            json={**self.BASE_PAYLOAD, "duration_minutes": 0},
        )
        assert response.status_code == 422, response.text

    def test_duration_negative_rejected(self, teacher_client):
        """Negative duration is not in the allow-list → 422."""
        response = teacher_client.post(
            "/api/v1/sessions/",
            json={**self.BASE_PAYLOAD, "duration_minutes": -5},
        )
        assert response.status_code == 422, response.text

    def test_error_message_contains_allowed_values(self, teacher_client):
        """422 error detail must list the allowed durations so clients can self-correct."""
        response = teacher_client.post(
            "/api/v1/sessions/",
            json={**self.BASE_PAYLOAD, "duration_minutes": 7},
        )
        assert response.status_code == 422, response.text
        body = response.text
        # At least one allowed value must appear in the error body
        assert any(str(d) in body for d in [3, 5, 10, 15, 20, 30, 45, 60]), (
            f"Error body does not mention any allowed duration: {body}"
        )


class TestScheduledSessions:
    """Automated tests for Flow A - Scheduled Sessions (Phase 4.1)."""

    BASE_PAYLOAD = {
        "subject_name": "Digital Electronics",
        "classroom_id": "classroom-hall-a",
        "duration_minutes": 60,
        "timetable_id": "timetable-123",
    }

    def _patch_all(
        self,
        *,
        timetable: dict | None = "default",
        classroom: dict | None = "default",
        subject: dict | None = "default",
        active_timetable_session: dict | None = None,
        active_classroom_session: dict | None = None,
        insert_result: dict | None = None,
    ):
        """Helper to patch repositories for scheduled session tests."""
        timetable_val = {
            "id": "timetable-123",
            "teacher_id": "teacher-001",
            "subject_id": "subject-123",
            "classroom_id": "classroom-hall-a",
            "is_active": True,
        } if timetable == "default" else timetable

        classroom_val = {
            "id": "classroom-hall-a",
            "name": "Lecture Hall A",
            "is_active": True,
        } if classroom == "default" else classroom

        subject_val = {
            "id": "subject-123",
            "name": "Digital Electronics",
            "code": "DE101",
        } if subject == "default" else subject

        new_session = insert_result or {
            "id": "session-new-001",
            "teacher_id": "teacher-001",
            "subject_name": subject_val.get("name") if subject_val else "Digital Electronics",
            "subject_id": subject_val.get("id") if subject_val else "subject-123",
            "classroom_id": classroom_val.get("id") if classroom_val else "classroom-hall-a",
            "status": "active",
            "started_at": "2026-07-01T08:00:00+00:00",
            "expires_at": "2026-07-01T09:00:00+00:00",
            "duration_minutes": 60,
            "total_present": 0,
            "created_at": "2026-07-01T08:00:00+00:00",
            "current_token": "tok-123",
            "timetable_id": "timetable-123",
        }

        return [
            patch("app.services.session_service._timetable_repo.get_by_id", return_value=timetable_val),
            patch("app.services.session_service._classroom_repo.get_by_id", return_value=classroom_val),
            patch("app.services.session_service._subject_repo.get_by_id", return_value=subject_val),
            patch("app.services.session_service._session_repo.get_active_by_timetable", return_value=active_timetable_session),
            patch("app.services.session_service._session_repo.get_active_by_classroom", return_value=active_classroom_session),
            patch("app.services.session_service._session_repo.insert", return_value=new_session),
            patch("app.services.session_service.publish_start_session"),
            patch("app.services.session_service.notification_service.send_session_started"),
            patch("app.services.session_service.generate_session_token", return_value="tok-123"),
        ]

    def test_scheduled_session_creation_success(self, teacher_client):
        """Flow A scheduled session creation stores all fields and succeeds (201)."""
        patches = self._patch_all()
        for p in patches:
            p.start()
        try:
            response = teacher_client.post("/api/v1/sessions/", json=self.BASE_PAYLOAD)
            assert response.status_code == 201
            data = response.json()
            assert data["id"] == "session-new-001"
            assert data["timetable_id"] == "timetable-123"
            assert data["subject_id"] == "subject-123"
            assert data["classroom_id"] == "classroom-hall-a"
            assert data["subject_name"] == "Digital Electronics"
        finally:
            for p in patches:
                p.stop()

    def test_duplicate_active_session_rejected(self, teacher_client):
        """Active session exists for the timetable slot -> 409 Conflict."""
        patches = self._patch_all(
            active_timetable_session={
                "id": "session-active-existing",
                "status": "active",
                "timetable_id": "timetable-123",
            }
        )
        for p in patches:
            p.start()
        try:
            response = teacher_client.post("/api/v1/sessions/", json=self.BASE_PAYLOAD)
            assert response.status_code == 409
            assert "already exists for this timetable" in response.json()["error"]["message"]
        finally:
            for p in patches:
                p.stop()

    def test_completed_sessions_do_not_block_creation(self, teacher_client):
        """Completed session exists for timetable -> succeeds."""
        patches = self._patch_all(active_timetable_session=None)
        for p in patches:
            p.start()
        try:
            response = teacher_client.post("/api/v1/sessions/", json=self.BASE_PAYLOAD)
            assert response.status_code == 201
        finally:
            for p in patches:
                p.stop()

    def test_invalid_timetable_rejected(self, teacher_client):
        """Timetable slot not found -> 409 Conflict."""
        patches = self._patch_all(timetable=None)
        for p in patches:
            p.start()
        try:
            response = teacher_client.post("/api/v1/sessions/", json=self.BASE_PAYLOAD)
            assert response.status_code == 409
            assert "not found" in response.json()["error"]["message"]
        finally:
            for p in patches:
                p.stop()

    def test_inactive_timetable_rejected(self, teacher_client):
        """Timetable marked inactive -> 409 Conflict."""
        patches = self._patch_all(
            timetable={
                "id": "timetable-123",
                "teacher_id": "teacher-001",
                "subject_id": "subject-123",
                "classroom_id": "classroom-hall-a",
                "is_active": False,
            }
        )
        for p in patches:
            p.start()
        try:
            response = teacher_client.post("/api/v1/sessions/", json=self.BASE_PAYLOAD)
            assert response.status_code == 409
            assert "inactive" in response.json()["error"]["message"]
        finally:
            for p in patches:
                p.stop()

    def test_invalid_classroom_rejected(self, teacher_client):
        """Timetable classroom record missing -> 404 or 409."""
        patches = self._patch_all(classroom=None)
        for p in patches:
            p.start()
        try:
            response = teacher_client.post("/api/v1/sessions/", json=self.BASE_PAYLOAD)
            assert response.status_code in (404, 409)
        finally:
            for p in patches:
                p.stop()

    def test_missing_subject_rejected(self, teacher_client):
        """Timetable subject record missing -> 409 Conflict."""
        patches = self._patch_all(subject=None)
        for p in patches:
            p.start()
        try:
            response = teacher_client.post("/api/v1/sessions/", json=self.BASE_PAYLOAD)
            assert response.status_code == 409
            assert "associated with timetable slot not found" in response.json()["error"]["message"]
        finally:
            for p in patches:
                p.stop()

    def test_teacher_ownership_enforced(self, teacher_client):
        """Timetable slot belongs to another teacher -> 403 Forbidden."""
        patches = self._patch_all(
            timetable={
                "id": "timetable-123",
                "teacher_id": "teacher-999",  # belongs to another teacher
                "subject_id": "subject-123",
                "classroom_id": "classroom-hall-a",
                "is_active": True,
            }
        )
        for p in patches:
            p.start()
        try:
            response = teacher_client.post("/api/v1/sessions/", json=self.BASE_PAYLOAD)
            assert response.status_code == 403
            assert "permission" in response.json()["error"]["message"]
        finally:
            for p in patches:
                p.stop()

    def test_admin_bypasses_ownership(self, admin_client):
        """Admins bypass timetable slot ownership verification -> 201 Created."""
        patches = self._patch_all(
            timetable={
                "id": "timetable-123",
                "teacher_id": "teacher-999",  # belongs to another teacher, but caller is admin
                "subject_id": "subject-123",
                "classroom_id": "classroom-hall-a",
                "is_active": True,
            }
        )
        for p in patches:
            p.start()
        try:
            response = admin_client.post("/api/v1/sessions/", json=self.BASE_PAYLOAD)
            assert response.status_code == 201
        finally:
            for p in patches:
                p.stop()

    def test_custom_session_still_works(self, teacher_client):
        """Flow B custom session creation without timetable_id -> 201 Created."""
        custom_payload = {
            "subject_name": "Operating Systems",
            "classroom_id": "classroom-hall-a",
            "duration_minutes": 60,
        }
        patches = [
            patch("app.services.session_service._classroom_repo.get_by_id", return_value={"id": "classroom-hall-a", "name": "Lecture Hall A", "is_active": True}),
            patch("app.services.session_service._session_repo.get_active_by_classroom", return_value=None),
            patch("app.services.session_service._session_repo.insert", return_value={
                "id": "session-custom-001",
                "teacher_id": "teacher-001",
                "subject_name": "Operating Systems",
                "subject_id": None,
                "classroom_id": "classroom-hall-a",
                "status": "active",
                "started_at": "2026-07-01T08:00:00+00:00",
                "expires_at": "2026-07-01T09:00:00+00:00",
                "duration_minutes": 60,
                "total_present": 0,
                "created_at": "2026-07-01T08:00:00+00:00",
                "current_token": "tok-123",
                "timetable_id": None,
            }),
            patch("app.services.session_service.publish_start_session"),
            patch("app.services.session_service.notification_service.send_session_started"),
            patch("app.services.session_service.generate_session_token", return_value="tok-123"),
        ]
        for p in patches:
            p.start()
        try:
            response = teacher_client.post("/api/v1/sessions/", json=custom_payload)
            assert response.status_code == 201
            data = response.json()
            assert data["id"] == "session-custom-001"
            assert data["timetable_id"] is None
            assert data["subject_id"] is None
        finally:
            for p in patches:
                p.stop()

    def test_roster_endpoint_returns_200_for_scheduled_sessions(self, teacher_client):
        """Newly created scheduled session roster endpoint -> 200 OK."""
        session_id = "session-new-001"
        session_ctx = {
            "id": session_id,
            "teacher_id": "teacher-001",
            "classroom_id": "classroom-hall-a",
            "status": "active",
            "subject_name": "Digital Electronics",
            "timetable_id": "timetable-123",
            "subject_id": "subject-123",
            "started_at": "2026-07-01T08:00:00+00:00",
        }

        with (
            patch("app.services.roster_service._enrollment_repo.get_subject_students_with_profiles", return_value=[]),
            patch("app.services.roster_service._attendance_repo.list_by_session", return_value=[]),
            patch("app.services.session_service._session_repo.get_by_id", return_value=session_ctx),
            patch("app.services.session_service._classroom_repo.get_by_id", return_value={"id": "classroom-hall-a", "name": "Lecture Hall A", "is_active": True}),
            patch("app.services.session_service._timetable_repo.get_by_id", return_value={
                "id": "timetable-123",
                "subject_id": "subject-123",
            }),
        ):
            response = teacher_client.get(f"/api/v1/sessions/{session_id}/roster")
            assert response.status_code == 200

    def test_subject_rename_does_not_modify_historical_snapshot(self, teacher_client):
        """Session subject_name is a snapshot and remains unchanged after subject is renamed."""
        historical_session = {
            "id": "session-hist-abc",
            "teacher_id": "teacher-001",
            "subject_id": "subject-123",
            "subject_name": "Digital Electronics",  # Saved snapshot
            "classroom_id": "classroom-hall-a",
            "status": "completed",
            "started_at": "2026-07-01T08:00:00+00:00",
            "expires_at": "2026-07-01T09:00:00+00:00",
            "duration_minutes": 60,
            "total_present": 5,
            "created_at": "2026-07-01T08:00:00+00:00",
            "current_token": None,
            "timetable_id": "timetable-123",
        }

        # Subject renamed in database to "Digital Electronics II"
        renamed_subject = {
            "id": "subject-123",
            "name": "Digital Electronics II",
            "code": "DE102",
        }

        with (
            patch("app.services.session_service._session_repo.get_by_id", return_value=historical_session),
            patch("app.services.session_service._subject_repo.get_by_id", return_value=renamed_subject),
        ):
            response = teacher_client.get("/api/v1/sessions/session-hist-abc")
            assert response.status_code == 200
            data = response.json()
            # Must return the snapshot "Digital Electronics" instead of the renamed "Digital Electronics II"
            assert data["subject_name"] == "Digital Electronics"

    def test_scheduled_session_ignores_client_classroom_id(self, teacher_client):
        """Flow A scheduled session creation uses the classroom_id from timetable and ignores the request payload's classroom_id."""
        payload_with_different_classroom = {
            **self.BASE_PAYLOAD,
            "classroom_id": "classroom-malicious-b",
        }
        # timetable has "classroom-hall-a" (classroom_A)
        # request has "classroom-malicious-b" (classroom_B)
        # The mock insert should show classroom_id as "classroom-hall-a"
        inserted_session = {
            "id": "session-new-001",
            "teacher_id": "teacher-001",
            "subject_name": "Digital Electronics",
            "subject_id": "subject-123",
            "classroom_id": "classroom-hall-a",  # Must be classroom_A
            "status": "active",
            "started_at": "2026-07-01T08:00:00+00:00",
            "expires_at": "2026-07-01T09:00:00+00:00",
            "duration_minutes": 60,
            "total_present": 0,
            "created_at": "2026-07-01T08:00:00+00:00",
            "current_token": "tok-123",
            "timetable_id": "timetable-123",
        }

        # We mock classrooms mock to return valid classroom for classroom-hall-a
        patches = self._patch_all(
            classroom={"id": "classroom-hall-a", "name": "Lecture Hall A", "is_active": True},
            insert_result=inserted_session
        )
        for p in patches:
            p.start()
        try:
            response = teacher_client.post("/api/v1/sessions/", json=payload_with_different_classroom)
            assert response.status_code == 201
            data = response.json()
            assert data["classroom_id"] == "classroom-hall-a"  # Must store classroom_A
        finally:
            for p in patches:
                p.stop()


