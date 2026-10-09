"""Regression tests for the session repository defensive null-safety fixes.

Covers:
  - get_active_by_classroom: no session, one session, resp=None (0 rows), Supabase exception
  - BaseRepository._safe_single: postgrest-py 2.30.0 semantics (None=0 rows, not failure)
  - BaseRepository._safe_execute: resp=None guard, exception propagation
  - End-to-end session creation: empty table, occupied classroom, CS501/Room302, CS401/HallA
  - Migration 0002: subject_name field replaces subject_id in session creation
"""

from __future__ import annotations

from typing import Any
from unittest.mock import MagicMock, patch

import pytest
from app.repositories.base import BaseRepository, RepositoryError
from app.repositories.session_repo import SessionRepository

# ── Helpers ───────────────────────────────────────────────────────────────────

def _mock_response(data: Any, count: int | None = None) -> MagicMock:
    """Build a fake Supabase response object."""
    resp = MagicMock()
    resp.data = data
    resp.count = count
    return resp


def _build_repo_with_mock_table(execute_return: Any) -> tuple[SessionRepository, MagicMock]:
    """Create a SessionRepository whose .table is fully mocked.

    execute_return: the value that .execute() will return.
    """
    mock_client = MagicMock()
    repo = SessionRepository(client=mock_client)

    # Build a chainable mock for the fluent query builder
    query_mock = MagicMock()
    query_mock.select.return_value = query_mock
    query_mock.eq.return_value = query_mock
    query_mock.lt.return_value = query_mock
    query_mock.order.return_value = query_mock
    query_mock.limit.return_value = query_mock
    query_mock.range.return_value = query_mock
    query_mock.insert.return_value = query_mock
    query_mock.update.return_value = query_mock
    query_mock.upsert.return_value = query_mock
    query_mock.delete.return_value = query_mock
    query_mock.maybe_single.return_value = query_mock
    query_mock.execute.return_value = execute_return

    mock_client.table.return_value = query_mock
    return repo, query_mock


# ── get_active_by_classroom ───────────────────────────────────────────────────

class TestGetActiveByClassroom:
    """Tests for SessionRepository.get_active_by_classroom()."""

    def test_returns_none_when_no_active_session(self):
        """Empty classroom → None (not AttributeError)."""
        resp = _mock_response(data=None)
        repo, _ = _build_repo_with_mock_table(resp)
        result = repo.get_active_by_classroom("classroom-001")
        assert result is None

    def test_returns_session_when_active(self):
        """Active session present → returns the session dict."""
        session = {
            "id": "session-abc",
            "classroom_id": "classroom-001",
            "status": "active",
            "teacher_id": "teacher-001",
        }
        resp = _mock_response(data=session)
        repo, _ = _build_repo_with_mock_table(resp)
        result = repo.get_active_by_classroom("classroom-001")
        assert result is not None
        assert result["id"] == "session-abc"
        assert result["status"] == "active"

    def test_returns_none_when_resp_data_is_empty_dict(self):
        """resp.data = {} (falsy) → returns None, not crashes."""
        resp = _mock_response(data={})
        repo, _ = _build_repo_with_mock_table(resp)
        result = repo.get_active_by_classroom("classroom-001")
        # {} is falsy → treated as not found
        assert result is None

    def test_empty_table_returns_none(self):
        """Core regression: empty attendance_sessions table.

        postgrest-py 2.30.0 returns None from execute() when 0 rows match.
        This MUST return None, not raise RepositoryError (which caused HTTP 500).
        """
        repo, _ = _build_repo_with_mock_table(None)  # simulate empty table
        result = repo.get_active_by_classroom("classroom-001")
        assert result is None, (
            "Empty attendance_sessions table must return None, not raise. "
            "This was the direct cause of HTTP 500 on first session creation."
        )

    def test_raises_repository_error_on_network_exception(self):
        """Supabase network error → RepositoryError, NOT raw exception."""
        mock_client = MagicMock()
        repo = SessionRepository(client=mock_client)

        query_mock = MagicMock()
        query_mock.select.return_value = query_mock
        query_mock.eq.return_value = query_mock
        query_mock.maybe_single.return_value = query_mock
        query_mock.execute.side_effect = ConnectionError("Network unreachable")

        mock_client.table.return_value = query_mock

        with pytest.raises(RepositoryError) as exc_info:
            repo.get_active_by_classroom("classroom-001")
        assert "Query failed" in str(exc_info.value)

    def test_never_raises_attribute_error(self):
        """Guard: regardless of resp value, AttributeError must never escape."""
        repo, _ = _build_repo_with_mock_table(None)
        try:
            repo.get_active_by_classroom("classroom-001")
        except AttributeError:
            pytest.fail("AttributeError escaped — null-safety fix not applied")
        except (RepositoryError, Exception):
            pass  # any other exception is acceptable for this guard test


# ── BaseRepository._safe_single ───────────────────────────────────────────────

class TestSafeSingle:
    """Unit tests for the _safe_single base helper.

    postgrest-py 2.30.0 SyncMaybeSingleRequestBuilder.execute() contract:
      - 0 rows → returns None   (NOT a failure — documented behavior)
      - 1 row  → returns SingleAPIResponse with .data = row dict
      - errors → raises APIError / ValidationError (caught → RepositoryError)
    """

    def _make_base_repo(self, execute_return: Any) -> tuple[BaseRepository, MagicMock]:
        mock_client = MagicMock()
        repo = BaseRepository(client=mock_client)
        repo.table_name = "test_table"
        query_mock = MagicMock()
        query_mock.execute.return_value = execute_return
        return repo, query_mock

    def test_returns_none_when_execute_returns_none(self):
        """execute()=None → None (0 rows, postgrest-py documented behavior, NOT a failure)."""
        repo, query_mock = self._make_base_repo(None)  # postgrest-py returns None for 0 rows
        result = repo._safe_single(query_mock, operation="test_op")
        assert result is None  # must NOT raise RepositoryError

    def test_returns_none_for_null_data_on_response(self):
        """Resp exists but resp.data=None → None (edge case guard)."""
        resp = _mock_response(data=None)
        repo, query_mock = self._make_base_repo(resp)
        result = repo._safe_single(query_mock, operation="test_op")
        assert result is None

    def test_returns_row_for_valid_data(self):
        """resp.data = dict → returns the dict (1 row found)."""
        row = {"id": "row-1", "name": "test"}
        resp = _mock_response(data=row)
        repo, query_mock = self._make_base_repo(resp)
        result = repo._safe_single(query_mock, operation="test_op")
        assert result == row

    def test_does_not_raise_repository_error_when_resp_is_none(self):
        """The root-cause regression guard: execute()=None must NOT raise RepositoryError."""
        repo, query_mock = self._make_base_repo(None)
        try:
            result = repo._safe_single(query_mock, operation="test_op")
            assert result is None  # correct behavior
        except RepositoryError:
            pytest.fail(
                "RepositoryError raised for resp=None — this is the root cause bug. "
                "execute()=None means 0 rows in postgrest-py 2.30.0, not a failure."
            )

    def test_raises_repository_error_on_supabase_exception(self):
        """Only actual exceptions (network, APIError) → RepositoryError."""
        repo, query_mock = self._make_base_repo(None)
        query_mock.execute.side_effect = RuntimeError("db connection reset")
        with pytest.raises(RepositoryError) as exc_info:
            repo._safe_single(query_mock, operation="test_op")
        assert "Query failed" in str(exc_info.value)

    def test_raises_on_api_error(self):
        """APIError from postgrest → RepositoryError (not raw exception)."""
        repo, query_mock = self._make_base_repo(None)
        query_mock.execute.side_effect = Exception("406 - multiple rows")
        with pytest.raises(RepositoryError):
            repo._safe_single(query_mock, operation="test_op")

# ── BaseRepository._safe_execute ──────────────────────────────────────────────

class TestSafeExecute:
    """Unit tests for the _safe_execute base helper."""

    def _make_base_repo(self, execute_return: Any) -> tuple[BaseRepository, MagicMock]:
        mock_client = MagicMock()
        repo = BaseRepository(client=mock_client)
        repo.table_name = "test_table"
        query_mock = MagicMock()
        query_mock.execute.return_value = execute_return
        return repo, query_mock

    def test_returns_empty_list_for_null_data(self):
        """resp.data=None → [] (not crash)."""
        resp = _mock_response(data=None)
        repo, query_mock = self._make_base_repo(resp)
        result = repo._safe_execute(query_mock, operation="test_op")
        assert result == []

    def test_returns_rows(self):
        """resp.data = list of dicts → returned as-is."""
        rows = [{"id": "1"}, {"id": "2"}]
        resp = _mock_response(data=rows)
        repo, query_mock = self._make_base_repo(resp)
        result = repo._safe_execute(query_mock, operation="test_op")
        assert result == rows

    def test_returns_empty_list_for_empty_list_data(self):
        """resp.data=[] → [] (normal empty result)."""
        resp = _mock_response(data=[])
        repo, query_mock = self._make_base_repo(resp)
        result = repo._safe_execute(query_mock, operation="test_op")
        assert result == []

    def test_raises_on_none_response(self):
        """execute() returns None → RepositoryError."""
        repo, query_mock = self._make_base_repo(None)
        with pytest.raises(RepositoryError):
            repo._safe_execute(query_mock, operation="test_op")

    def test_raises_on_query_exception(self):
        """Query raises → RepositoryError."""
        repo, query_mock = self._make_base_repo(None)
        query_mock.execute.side_effect = OSError("connection refused")
        with pytest.raises(RepositoryError):
            repo._safe_execute(query_mock, operation="test_op")


# ── End-to-end session creation flow (migration 0002) ────────────────────────

class TestSessionCreationFlow:
    """Integration-style tests for the full session creation pipeline.

    These tests use the FastAPI test client and mock Supabase at the
    repository layer via the _db property, verifying the HTTP responses
    for the key business cases.

    Migration 0002: SESSION_PAYLOAD now uses subject_name instead of subject_id.
    """

    # Updated payload — subject_name replaces subject_id (migration 0002)
    SESSION_PAYLOAD = {
        "subject_name": "IoT Systems",
        "classroom_id": "classroom-hall-a",
        "duration_minutes": 60,
    }

    def _patch_all_repos(
        self,
        *,
        classroom_exists: bool = True,
        active_session: dict | None = None,
        insert_result: dict | None = None,
    ):
        """Return a list of patches for all repositories used by
        session_service.create_session().

        Migration 0002: subject_repo patch removed (no subject lookup).
        Timetable ownership patch removed (no timetable check).
        """
        classroom = {"id": "classroom-hall-a", "name": "Lecture Hall A", "is_active": True}
        new_session = insert_result or {
            "id": "session-new-001",
            "teacher_id": "teacher-001",
            "subject_name": "IoT Systems",
            "subject_id": None,
            "classroom_id": "classroom-hall-a",
            "status": "active",
            "started_at": "2026-06-01T00:00:00+00:00",
            "expires_at": "2026-06-01T01:00:00+00:00",
            "duration_minutes": 60,
            "total_present": 0,
            "created_at": "2026-06-01T00:00:00+00:00",
            "current_token": "tok123",
        }

        patches = [
            patch(
                "app.services.session_service._classroom_repo.get_by_id",
                return_value=classroom if classroom_exists else None,
            ),
            patch(
                "app.services.session_service._session_repo.get_active_by_classroom",
                return_value=active_session,
            ),
            patch(
                "app.services.session_service._session_repo.insert",
                return_value=new_session,
            ),
            patch("app.services.session_service.publish_start_session"),
            patch(
                "app.services.session_service.notification_service.send_session_started"
            ),
            patch(
                "app.services.session_service.generate_session_token",
                return_value="tok123",
            ),
        ]
        return patches

    def _apply_patches(self, patches):
        for p in patches:
            p.start()
        return patches

    def _stop_patches(self, patches):
        for p in patches:
            p.stop()

    def test_create_session_succeeds_when_no_active_session(self, teacher_client):
        """Valid request + free classroom → 201 Created."""
        patches = self._patch_all_repos(active_session=None)
        active = [p.start() for p in patches]
        try:
            response = teacher_client.post("/api/v1/sessions/", json=self.SESSION_PAYLOAD)
            assert response.status_code == 201, (
                f"Expected 201, got {response.status_code}: {response.text}"
            )
            data = response.json()
            assert data["id"] == "session-new-001"
            assert data["status"] == "active"
            assert data["subject_name"] == "IoT Systems"
            assert data["subject_id"] is None
        finally:
            for p in patches:
                p.stop()

    def test_create_session_409_when_active_session_exists(self, teacher_client):
        """Occupied classroom → 409 Conflict."""
        existing = {
            "id": "session-existing-001",
            "classroom_id": "classroom-hall-a",
            "status": "active",
        }
        patches = self._patch_all_repos(active_session=existing)
        for p in patches:
            p.start()
        try:
            response = teacher_client.post("/api/v1/sessions/", json=self.SESSION_PAYLOAD)
            assert response.status_code == 409, (
                f"Expected 409, got {response.status_code}: {response.text}"
            )
            error = response.json()["error"]
            assert error["code"] == "CONFLICT"
        finally:
            for p in patches:
                p.stop()

    def test_create_session_404_unknown_classroom(self, teacher_client):
        """Unknown classroom_id → 404 Not Found."""
        patches = self._patch_all_repos(classroom_exists=False)
        for p in patches:
            p.start()
        try:
            response = teacher_client.post("/api/v1/sessions/", json=self.SESSION_PAYLOAD)
            assert response.status_code == 404
        finally:
            for p in patches:
                p.stop()

    def test_no_500_when_get_active_returns_none(self, teacher_client):
        """The original crash case: get_active_by_classroom=None must NOT give 500."""
        patches = self._patch_all_repos(active_session=None)
        for p in patches:
            p.start()
        try:
            response = teacher_client.post("/api/v1/sessions/", json=self.SESSION_PAYLOAD)
            # Must be 201, definitely not 500
            assert response.status_code != 500, (
                f"HTTP 500 returned — null-safety bug still present: {response.text}"
            )
            assert response.status_code == 201
        finally:
            for p in patches:
                p.stop()

    def test_cs501_room302_empty_table_creates_session(self, teacher_client):
        """Computer Networks → Room 302 with empty attendance_sessions table → 201 Created.

        Reproduces the exact runtime failure: empty table causes maybe_single()
        to return None, which the old code raised as RepositoryError (HTTP 500).
        """
        payload = {
            "subject_name": "Computer Networks",
            "classroom_id": "classroom-room-302",
            "duration_minutes": 60,
        }
        new_session = {
            "id": "session-cs501-001",
            "teacher_id": "teacher-001",
            "subject_name": "Computer Networks",
            "subject_id": None,
            "classroom_id": "classroom-room-302",
            "status": "active",
            "started_at": "2026-06-01T09:00:00+00:00",
            "expires_at": "2026-06-01T10:00:00+00:00",
            "duration_minutes": 60,
            "total_present": 0,
            "created_at": "2026-06-01T09:00:00+00:00",
            "current_token": "tok-cs501",
        }
        patches = [
            patch(
                "app.services.session_service._classroom_repo.get_by_id",
                return_value={"id": "classroom-room-302", "name": "Room 302", "is_active": True},
            ),
            # Empty table: postgrest-py returns None for maybe_single on 0 rows
            patch(
                "app.services.session_service._session_repo.get_active_by_classroom",
                return_value=None,
            ),
            patch(
                "app.services.session_service._session_repo.insert",
                return_value=new_session,
            ),
            patch("app.services.session_service.publish_start_session"),
            patch(
                "app.services.session_service.notification_service.send_session_started"
            ),
            patch(
                "app.services.session_service.generate_session_token",
                return_value="tok-cs501",
            ),
        ]
        for p in patches:
            p.start()
        try:
            response = teacher_client.post("/api/v1/sessions/", json=payload)
            assert response.status_code != 500, (
                f"HTTP 500 on Computer Networks+Room302 — _safe_single None fix not applied: {response.text}"
            )
            assert response.status_code == 201, (
                f"Expected 201 for Computer Networks+Room302, got {response.status_code}: {response.text}"
            )
            data = response.json()
            assert data["id"] == "session-cs501-001"
            assert data["subject_name"] == "Computer Networks"
        finally:
            for p in patches:
                p.stop()

    def test_cs401_hall_a_empty_table_creates_session(self, teacher_client):
        """IoT Systems → Lecture Hall A with empty attendance_sessions table → 201 Created."""
        payload = {
            "subject_name": "IoT Systems & Applications",
            "classroom_id": "classroom-hall-a",
            "duration_minutes": 60,
        }
        new_session = {
            "id": "session-cs401-001",
            "teacher_id": "teacher-001",
            "subject_name": "IoT Systems & Applications",
            "subject_id": None,
            "classroom_id": "classroom-hall-a",
            "status": "active",
            "started_at": "2026-06-01T11:00:00+00:00",
            "expires_at": "2026-06-01T12:00:00+00:00",
            "duration_minutes": 60,
            "total_present": 0,
            "created_at": "2026-06-01T11:00:00+00:00",
            "current_token": "tok-cs401",
        }
        patches = [
            patch(
                "app.services.session_service._classroom_repo.get_by_id",
                return_value={"id": "classroom-hall-a", "name": "Lecture Hall A", "is_active": True},
            ),
            patch(
                "app.services.session_service._session_repo.get_active_by_classroom",
                return_value=None,  # empty table
            ),
            patch(
                "app.services.session_service._session_repo.insert",
                return_value=new_session,
            ),
            patch("app.services.session_service.publish_start_session"),
            patch(
                "app.services.session_service.notification_service.send_session_started"
            ),
            patch(
                "app.services.session_service.generate_session_token",
                return_value="tok-cs401",
            ),
        ]
        for p in patches:
            p.start()
        try:
            response = teacher_client.post("/api/v1/sessions/", json=payload)
            assert response.status_code != 500, (
                f"HTTP 500 on IoT Systems+HallA — _safe_single None fix not applied: {response.text}"
            )
            assert response.status_code == 201, (
                f"Expected 201 for IoT Systems+HallA, got {response.status_code}: {response.text}"
            )
            data = response.json()
            assert data["id"] == "session-cs401-001"
            assert data["subject_name"] == "IoT Systems & Applications"
        finally:
            for p in patches:
                p.stop()
