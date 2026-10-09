"""Token service — beacon token generation and verification.

There are two verification modes, controlled by FIXED_TOKEN_MODE:

  FIXED_TOKEN_MODE = True   (development / hardware testing)
  ─────────────────────────────────────────────────────────────────────
  Token is generated ONCE when the session is created via
  generate_session_token(), stored in attendance_sessions.current_token,
  and never rotated while the session is active.

  verify_stored_token(submitted, stored) does a simple constant-time
  string comparison:  submitted == stored_token → valid.

  Token is valid for the entire session duration (15–60 min).
  ESP32 firmware token only needs to match the stored token.

  FIXED_TOKEN_MODE = False  (production — MQTT automatic rotation enabled)
  ─────────────────────────────────────────────────────────────────────
  Tokens are HMAC-SHA256 hashes of (room_id : time_window), valid for
  one 30-second window with a one-window grace period for clock skew.
  verify_session_token() is used for time-window validation.
  The automatic scheduler (_token_rotation_loop in main.py) pushes a
  fresh MQTT token to the ESP32 every TOKEN_ROTATION_INTERVAL_SECONDS.
"""

from __future__ import annotations

import hashlib
import hmac
import time

from app.core.config import get_settings
from app.core.logging import get_logger

logger = get_logger(__name__)

_WINDOW_SECONDS = 30
_TOKEN_LENGTH = 16  # hex chars

# How often the automatic rotation scheduler fires (seconds).
# Must be ≤ _WINDOW_SECONDS so the ESP32 always holds a token valid
# for the current HMAC window.  Exported so main.py can log it and
# session_service.py can import it without a circular dependency.
TOKEN_ROTATION_INTERVAL_SECONDS: int = _WINDOW_SECONDS

# ── Production mode flag ────────────────────────────────────────────────────────────────
#
# FIXED_TOKEN_MODE = True
#   Token is generated once at session creation and stored in
#   attendance_sessions.current_token.  verify_stored_token() validates
#   the submitted token against this stored value — no time-window logic.
#
# FIXED_TOKEN_MODE = False   ← CURRENT (production mode)
#   Original HMAC time-window behaviour.  verify_session_token() recalculates
#   the expected HMAC for the current (and previous) 30-second window.
#   The automatic rotation scheduler (_token_rotation_loop in main.py) pushes
#   a fresh MQTT token to each active ESP32 every TOKEN_ROTATION_INTERVAL_SECONDS.
#
FIXED_TOKEN_MODE: bool = False


def _make_token(secret: str, room_id: str, window: int) -> str:
    """Create HMAC-SHA256 token for a room + time window."""
    message = f"{room_id}:{window}".encode()
    digest = hmac.new(
        key=secret.encode(),
        msg=message,
        digestmod=hashlib.sha256,
    ).hexdigest()
    return digest[:_TOKEN_LENGTH]


def generate_session_token(
    classroom_id: str,
    window_seconds: int = _WINDOW_SECONDS,
) -> str:
    """Generate a beacon token for the current time window.

    Args:
        classroom_id: Classroom identifier.
        window_seconds: Token validity window in seconds.

    Returns:
        16-char hex token string.
    """
    settings = get_settings()
    current_window = int(time.time()) // window_seconds
    token = _make_token(settings.jwt_secret, classroom_id, current_window)
    logger.info(
        "Token generated",
        classroom_id=classroom_id,
        window=current_window,
    )
    return token


def verify_session_token(
    token: str,
    classroom_id: str,
    window_seconds: int = _WINDOW_SECONDS,
) -> bool:
    """Verify a beacon token against current and previous time windows.

    Checks both current window and one previous window to account
    for clock skew between ESP32 and the student's phone.

    Args:
        token: The token received from the student's BLE scan.
        classroom_id: Classroom where the session is running.
        window_seconds: Token validity window in seconds.

    Returns:
        True if the token matches either the current or previous window.
    """
    settings = get_settings()
    current_window = int(time.time()) // window_seconds

    for offset in (0, -1):  # current, then previous
        expected = _make_token(settings.jwt_secret, classroom_id, current_window + offset)
        if hmac.compare_digest(token, expected):
            logger.info(
                "Token verified",
                classroom_id=classroom_id,
                window_offset=offset,
            )
            return True

    logger.warning(
        "Token verification failed",
        classroom_id=classroom_id,
        token_prefix=token[:4] + "...",
    )
    return False


def verify_stored_token(submitted_token: str, stored_token: str | None) -> bool:
    """Validate a beacon token against the pre-stored session token.

    Used when FIXED_TOKEN_MODE is True (development / pre-MQTT phase).

    Performs a constant-time comparison to prevent timing-based attacks,
    matching the security standard of the original hmac.compare_digest() call.

    Args:
        submitted_token: The token received from the student's BLE scan.
        stored_token:    The value of attendance_sessions.current_token.

    Returns:
        True  — submitted_token matches stored_token exactly.
        False — mismatch, or stored_token is None/empty (session has no token).
    """
    if not stored_token:
        logger.warning(
            "verify_stored_token: session has no stored token",
            submitted_prefix=submitted_token[:4] + "...",
        )
        return False

    match = hmac.compare_digest(submitted_token, stored_token)
    if match:
        logger.info(
            "Token verified (fixed-token mode)",
            token_prefix=submitted_token[:4] + "...",
        )
    else:
        logger.warning(
            "Token verification failed (fixed-token mode)",
            submitted_prefix=submitted_token[:4] + "...",
            stored_prefix=stored_token[:4] + "...",
        )
    return match
