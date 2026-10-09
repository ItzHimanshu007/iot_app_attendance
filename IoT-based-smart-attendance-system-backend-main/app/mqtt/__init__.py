"""MQTT topic constants — single source of truth for all topic strings.

Topic hierarchy:
    campus/classroom/{classroom_id}/control    — session start/stop
    campus/classroom/{classroom_id}/token      — beacon token rotation
    campus/classroom/{classroom_id}/heartbeat  — ESP32 status
    campus/classroom/{classroom_id}/status     — device status updates
"""

from __future__ import annotations

# ── Topic Templates ───────────────────────────────────────────────────────────

_PREFIX = "campus/classroom"


def session_start(classroom_id: str) -> str:
    """Backend → ESP32: start BLE advertising."""
    return f"{_PREFIX}/{classroom_id}/control/start"


def session_stop(classroom_id: str) -> str:
    """Backend → ESP32: stop BLE advertising."""
    return f"{_PREFIX}/{classroom_id}/control/stop"


def token_rotation(classroom_id: str) -> str:
    """Backend → ESP32: update beacon token."""
    return f"{_PREFIX}/{classroom_id}/token"


def heartbeat(classroom_id: str) -> str:
    """ESP32 → Backend: periodic health report."""
    return f"{_PREFIX}/{classroom_id}/heartbeat"


def device_status(classroom_id: str) -> str:
    """ESP32 → Backend: status updates."""
    return f"{_PREFIX}/{classroom_id}/status"


# ── Wildcard patterns for subscriptions ───────────────────────────────────────

HEARTBEAT_WILDCARD = f"{_PREFIX}/+/heartbeat"
STATUS_WILDCARD = f"{_PREFIX}/+/status"
