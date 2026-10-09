"""Tests for device registration and validation service."""

from __future__ import annotations

from unittest.mock import patch

import pytest
from app.core.exceptions import ConflictError, DeviceMismatchError, DeviceNotRegisteredError
from app.services.device_service import register_device, validate_device


@pytest.fixture()
def mock_device_repo():
    with patch("app.services.device_service._repo") as mock:
        yield mock


@pytest.fixture()
def mock_notifications():
    with patch("app.services.device_service.notification_service") as mock:
        yield mock


class TestRegisterDevice:
    """Tests for device registration."""

    def test_register_new_device(self, mock_device_repo, mock_notifications):
        """First-time registration should succeed."""
        mock_device_repo.get_by_fingerprint.return_value = None
        mock_device_repo.get_active_by_user.return_value = None
        mock_device_repo.insert.return_value = {
            "id": "dev-001",
            "user_id": "student-001",
            "device_model": "Pixel 8",
            "device_fingerprint": "abc123",
            "is_active": True,
            "registered_at": "2026-01-01T00:00:00Z",
        }

        result = register_device(
            user_id="student-001",
            android_id="android-001",
            device_model="Pixel 8",
            device_fingerprint="abc123",
        )

        assert result["id"] == "dev-001"
        mock_device_repo.insert.assert_called_once()
        mock_notifications.send_device_registered.assert_called_once()

    def test_register_replaces_existing_device(self, mock_device_repo, mock_notifications):
        """Registering a new device should deactivate the old one."""
        mock_device_repo.get_by_fingerprint.return_value = None
        mock_device_repo.get_active_by_user.return_value = {
            "id": "old-dev",
            "user_id": "student-001",
        }
        mock_device_repo.insert.return_value = {
            "id": "new-dev",
            "user_id": "student-001",
            "device_model": "Pixel 9",
            "device_fingerprint": "def456",
            "is_active": True,
            "registered_at": "2026-01-01T00:00:00Z",
        }

        result = register_device(
            user_id="student-001",
            android_id="android-002",
            device_model="Pixel 9",
            device_fingerprint="def456",
        )

        assert result["id"] == "new-dev"
        mock_device_repo.deactivate_user_devices.assert_called_once_with(
            "student-001", "replacement"
        )

    def test_register_fingerprint_conflict(self, mock_device_repo, mock_notifications):
        """Fingerprint already owned by another user should raise ConflictError."""
        mock_device_repo.get_by_fingerprint.return_value = {
            "user_id": "other-user",
            "device_fingerprint": "abc123",
        }

        with pytest.raises(ConflictError, match="already registered"):
            register_device(
                user_id="student-001",
                android_id="android-001",
                device_model="Pixel 8",
                device_fingerprint="abc123",
            )

    def test_register_fingerprint_conflict_inactive_deleted(self, mock_device_repo, mock_notifications):
        """Fingerprint owned by another user but is inactive should delete old record and succeed."""
        mock_device_repo.get_by_fingerprint.return_value = {
            "id": "dev-old",
            "user_id": "other-user",
            "device_fingerprint": "abc123",
            "is_active": False,
        }
        mock_device_repo.get_active_by_user.return_value = None
        mock_device_repo.insert.return_value = {
            "id": "dev-new",
            "user_id": "student-001",
            "device_model": "Pixel 8",
            "device_fingerprint": "abc123",
            "is_active": True,
            "registered_at": "2026-01-01T00:00:00Z",
        }

        result = register_device(
            user_id="student-001",
            android_id="android-001",
            device_model="Pixel 8",
            device_fingerprint="abc123",
        )

        assert result["id"] == "dev-new"
        mock_device_repo.delete.assert_called_once_with("dev-old")
        mock_device_repo.insert.assert_called_once()
        mock_notifications.send_device_registered.assert_called_once()

    def test_register_same_active_device_updates_metadata(self, mock_device_repo, mock_notifications):
        """Registering the same active device should update metadata and not create new rows."""
        mock_device_repo.get_by_fingerprint.return_value = {
            "id": "dev-active",
            "user_id": "student-001",
            "device_fingerprint": "abc123",
            "is_active": True,
        }
        mock_device_repo.update.return_value = {
            "id": "dev-active",
            "user_id": "student-001",
            "device_fingerprint": "abc123",
            "is_active": True,
        }

        result = register_device(
            user_id="student-001",
            android_id="android-updated",
            device_model="Pixel 8",
            device_fingerprint="abc123",
        )

        assert result["id"] == "dev-active"
        mock_device_repo.update.assert_called_once()
        mock_device_repo.insert.assert_not_called()
        mock_device_repo.deactivate_user_devices.assert_not_called()
        mock_notifications.send_device_registered.assert_called_once()




class TestValidateDevice:
    """Tests for device fingerprint validation."""

    def test_validate_matching_device(self, mock_device_repo):
        """Matching fingerprint should pass."""
        mock_device_repo.get_active_by_user.return_value = {
            "id": "dev-001",
            "device_fingerprint": "abc123",
        }

        result = validate_device("student-001", "abc123")
        assert result["id"] == "dev-001"
        mock_device_repo.touch_last_active.assert_called_once()

    def test_validate_no_registered_device(self, mock_device_repo):
        """No active device should raise DeviceNotRegisteredError."""
        mock_device_repo.get_active_by_user.return_value = None

        with pytest.raises(DeviceNotRegisteredError):
            validate_device("student-001", "abc123")

    def test_validate_fingerprint_mismatch(self, mock_device_repo):
        """Wrong fingerprint should raise DeviceMismatchError."""
        mock_device_repo.get_active_by_user.return_value = {
            "id": "dev-001",
            "device_fingerprint": "abc123",
        }

        with pytest.raises(DeviceMismatchError):
            validate_device("student-001", "wrong-fingerprint")
