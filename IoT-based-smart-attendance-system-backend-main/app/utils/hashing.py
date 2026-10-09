"""HMAC hashing helpers for beacon tokens and integrity checks."""

from __future__ import annotations

import hashlib
import hmac


def hmac_sha256(key: str, message: str) -> str:
    """Generate HMAC-SHA256 hex digest.

    Args:
        key: Secret key string.
        message: Message to sign.

    Returns:
        Full hex-encoded HMAC-SHA256 digest.
    """
    return hmac.new(
        key=key.encode(),
        msg=message.encode(),
        digestmod=hashlib.sha256,
    ).hexdigest()


def hmac_sha256_truncated(key: str, message: str, length: int = 16) -> str:
    """Generate a truncated HMAC-SHA256 for BLE payload size constraints.

    Args:
        key: Secret key string.
        message: Message to sign.
        length: Number of hex chars to keep (default 16 = 8 bytes).

    Returns:
        Truncated hex-encoded HMAC-SHA256 digest.
    """
    return hmac_sha256(key, message)[:length]
