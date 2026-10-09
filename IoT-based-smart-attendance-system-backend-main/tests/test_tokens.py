"""Tests for the token generation and verification service."""

from __future__ import annotations

from unittest.mock import patch

from app.services.token_service import generate_session_token, verify_session_token


def test_token_generation_deterministic():
    """Same classroom + same time window → same token."""
    with patch("app.services.token_service.time") as mock_time:
        mock_time.time.return_value = 1000.0
        token1 = generate_session_token("room-101", window_seconds=30)
        token2 = generate_session_token("room-101", window_seconds=30)
        assert token1 == token2


def test_token_length():
    """Token should be exactly 16 hex characters."""
    with patch("app.services.token_service.time") as mock_time:
        mock_time.time.return_value = 1000.0
        token = generate_session_token("room-101")
        assert len(token) == 16
        assert all(c in "0123456789abcdef" for c in token)


def test_token_verification_current_window():
    """Token for current window should verify."""
    with patch("app.services.token_service.time") as mock_time:
        mock_time.time.return_value = 1000.0
        token = generate_session_token("room-101", window_seconds=30)
        assert verify_session_token(token, "room-101", window_seconds=30)


def test_token_verification_previous_window():
    """Token from previous window should still verify (clock skew tolerance)."""
    with patch("app.services.token_service.time") as mock_time:
        # Generate in window 33 (1000 // 30)
        mock_time.time.return_value = 1000.0
        token = generate_session_token("room-101", window_seconds=30)

        # Verify in window 34 (1020 // 30)
        mock_time.time.return_value = 1020.0
        assert verify_session_token(token, "room-101", window_seconds=30)


def test_token_different_rooms():
    """Different rooms should produce different tokens."""
    with patch("app.services.token_service.time") as mock_time:
        mock_time.time.return_value = 1000.0
        token_a = generate_session_token("room-101", window_seconds=30)
        token_b = generate_session_token("room-202", window_seconds=30)
        assert token_a != token_b


def test_token_wrong_room_fails():
    """Token for room-101 should not verify for room-202."""
    with patch("app.services.token_service.time") as mock_time:
        mock_time.time.return_value = 1000.0
        token = generate_session_token("room-101", window_seconds=30)
        assert not verify_session_token(token, "room-202", window_seconds=30)


def test_token_expired_two_windows_fails():
    """Token expired by 2+ windows should fail verification."""
    with patch("app.services.token_service.time") as mock_time:
        # Generate in window 33
        mock_time.time.return_value = 1000.0
        token = generate_session_token("room-101", window_seconds=30)

        # Verify in window 35 (two windows later)
        mock_time.time.return_value = 1060.0
        assert not verify_session_token(token, "room-101", window_seconds=30)
