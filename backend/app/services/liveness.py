"""Random liveness challenges performed in front of the camera."""

from __future__ import annotations

import secrets

# Steps the Flutter app knows how to detect with ML Kit.
ALL_STEPS: tuple[str, ...] = ("blink", "smile", "turn_head")


def pick_steps(count: int) -> list[str]:
    """Pick ``count`` distinct steps in a random order (CSPRNG)."""
    pool = list(ALL_STEPS)
    count = max(1, min(count, len(pool)))
    chosen: list[str] = []
    for _ in range(count):
        chosen.append(pool.pop(secrets.randbelow(len(pool))))
    return chosen
