"""Application-wide constants shared across the backend.

Add new shared constants here rather than scattering magic values through
individual modules.  All values are intentionally module-level so they can
be imported directly without instantiating any class.
"""

from __future__ import annotations

# ── Session duration allow-list ───────────────────────────────────────────────
# The Flutter UI offers exactly these durations (in minutes) for the teacher
# to choose from.  The backend enforces the same list so that arbitrary values
# cannot be injected via direct API calls.
#
# Sorted for human readability; stored as a frozenset for O(1) membership
# tests at validation time.
ALLOWED_SESSION_DURATIONS: frozenset[int] = frozenset({3, 5, 10, 15, 20, 30, 45, 60})

# Human-readable string used in error messages.
_ALLOWED_DURATIONS_DISPLAY = ", ".join(str(d) for d in sorted(ALLOWED_SESSION_DURATIONS))
ALLOWED_SESSION_DURATIONS_MSG: str = (
    f"duration_minutes must be one of: {_ALLOWED_DURATIONS_DISPLAY}"
)
