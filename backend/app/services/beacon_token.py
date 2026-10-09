"""Rotating BLE beacon tokens (TOTP-style, computed independently by the ESP32).

    window = floor(unix_time / WINDOW_SECONDS)
    token  = first 8 bytes of HMAC-SHA256(key=secret, msg=f"{beacon_id}:{window}")
             → 16 lowercase hex chars

``secret`` is used as its UTF-8 bytes (the 64-char hex string itself, not the
decoded bytes) and ``beacon_id`` is the lowercase UUID string. The firmware in
``firmware/staff_beacon/token_generator.cpp`` implements exactly this.
"""

from __future__ import annotations

import hashlib
import hmac
import re
import secrets
import time

TOKEN_HEX_LENGTH = 16
_TOKEN_RE = re.compile(r"^[0-9a-f]{16}$")


def new_secret() -> str:
    """Generate a fresh 256-bit beacon secret as 64 hex chars."""
    return secrets.token_hex(32)


def current_window(window_seconds: int, now: float | None = None) -> int:
    """Index of the current rotation window."""
    ts = time.time() if now is None else now
    return int(ts) // window_seconds


def compute_token(secret: str, beacon_id: str, window: int) -> str:
    """Token the beacon advertises during ``window``."""
    message = f"{beacon_id.lower()}:{window}".encode()
    digest = hmac.new(secret.encode(), message, hashlib.sha256).hexdigest()
    return digest[:TOKEN_HEX_LENGTH]


def verify_token(
    token: str,
    secret: str,
    beacon_id: str,
    *,
    window_seconds: int,
    past_windows: int,
    future_windows: int = 1,
    now: float | None = None,
) -> int | None:
    """Check a token against the current and nearby windows.

    Returns:
        The age of the token in windows (0 = current, 1 = previous, -1 = next)
        when valid, otherwise None.
    """
    candidate = (token or "").strip().lower()
    if not _TOKEN_RE.match(candidate):
        return None
    base = current_window(window_seconds, now)
    for age in range(-future_windows, past_windows + 1):
        expected = compute_token(secret, beacon_id, base - age)
        if hmac.compare_digest(candidate, expected):
            return age
    return None
