"""Shared test fixtures — mocked Supabase, MQTT, and auth."""

from __future__ import annotations

from collections.abc import Generator
from unittest.mock import MagicMock, patch

import pytest
from app.main import app
from app.security.rbac import CurrentUser
from fastapi.testclient import TestClient

# ── Test users ────────────────────────────────────────────────────────────────

STUDENT_USER = CurrentUser(
    id="student-001",
    email="alice@campus.edu",
    full_name="Alice Johnson",
    role="student",
    department="CS",
    is_active=True,
)

TEACHER_USER = CurrentUser(
    id="teacher-001",
    email="dr.smith@campus.edu",
    full_name="Dr. Smith",
    role="teacher",
    department="CS",
    is_active=True,
)

ADMIN_USER = CurrentUser(
    id="admin-001",
    email="admin@campus.edu",
    full_name="Admin User",
    role="admin",
    department="IT",
    is_active=True,
)


# ── Auth override helpers ─────────────────────────────────────────────────────

def _override_user(user: CurrentUser):
    """Create an auth dependency override for a specific user."""
    from app.security.rbac import get_current_user

    async def _override():
        return user

    return {get_current_user: _override}


# ── Fixtures ──────────────────────────────────────────────────────────────────


@pytest.fixture()
def client() -> TestClient:
    """Unauthenticated test client."""
    return TestClient(app)


@pytest.fixture()
def student_client() -> Generator[TestClient, None, None]:
    """Test client authenticated as a student."""
    app.dependency_overrides.update(_override_user(STUDENT_USER))
    yield TestClient(app)
    app.dependency_overrides.clear()


@pytest.fixture()
def teacher_client() -> Generator[TestClient, None, None]:
    """Test client authenticated as a teacher."""
    app.dependency_overrides.update(_override_user(TEACHER_USER))
    yield TestClient(app)
    app.dependency_overrides.clear()


@pytest.fixture()
def admin_client() -> Generator[TestClient, None, None]:
    """Test client authenticated as an admin."""
    app.dependency_overrides.update(_override_user(ADMIN_USER))
    yield TestClient(app)
    app.dependency_overrides.clear()


@pytest.fixture()
def mock_supabase() -> Generator[MagicMock, None, None]:
    """Patch the Supabase client with a MagicMock."""
    with patch("app.services.supabase_client.get_supabase") as mock:
        yield mock


@pytest.fixture()
def mock_mqtt() -> Generator[MagicMock, None, None]:
    """Patch MQTT publisher functions."""
    with patch("app.mqtt.publisher.get_mqtt_client") as mock:
        mock.return_value = MagicMock()
        yield mock
