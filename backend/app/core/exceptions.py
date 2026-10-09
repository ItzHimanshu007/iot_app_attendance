"""Typed application errors.

Routers and services raise these. The global handler in ``main.py`` turns
them into a consistent JSON envelope::

    {"error": {"code": "FACE_MISMATCH", "message": "...", "request_id": "..."}}

The ``code`` values are part of the API contract — the Flutter app maps them
to user-friendly messages.
"""

from __future__ import annotations


class AppError(Exception):
    """Base for all application errors."""

    def __init__(self, message: str, code: str, status_code: int = 500) -> None:
        super().__init__(message)
        self.message = message
        self.code = code
        self.status_code = status_code


# ── Generic 4xx ───────────────────────────────────────────────────────────────


class NotFoundError(AppError):
    """Resource not found (404)."""

    def __init__(self, resource: str, resource_id: str = "") -> None:
        suffix = f" '{resource_id}'" if resource_id else ""
        super().__init__(f"{resource}{suffix} not found", "NOT_FOUND", 404)


class ConflictError(AppError):
    """Business-rule conflict (409)."""

    def __init__(self, message: str, code: str = "CONFLICT") -> None:
        super().__init__(message, code, 409)


class AuthenticationError(AppError):
    """Missing or invalid credentials (401)."""

    def __init__(self, message: str = "Invalid or expired token") -> None:
        super().__init__(message, "UNAUTHORIZED", 401)


class AuthorizationError(AppError):
    """Authenticated but not allowed (403)."""

    def __init__(self, message: str = "Insufficient permissions", code: str = "FORBIDDEN") -> None:
        super().__init__(message, code, 403)


class ValidationError(AppError):
    """Application-level validation failure (422)."""

    def __init__(self, message: str, code: str = "VALIDATION_ERROR") -> None:
        super().__init__(message, code, 422)


# ── Attendance verification ───────────────────────────────────────────────────


class VerificationError(AppError):
    """An attendance verification check failed (422).

    Every instance is also written to ``attendance_attempts`` so admins can
    see proxy attempts.
    """

    def __init__(self, message: str, code: str) -> None:
        super().__init__(message, code, 422)


# ── 5xx ───────────────────────────────────────────────────────────────────────


class ExternalServiceError(AppError):
    """An external dependency (Supabase) failed (502)."""

    def __init__(self, service: str, detail: str) -> None:
        super().__init__(f"{service}: {detail}", "EXTERNAL_ERROR", 502)
