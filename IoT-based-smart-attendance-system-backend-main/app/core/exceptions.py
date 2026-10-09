"""Extended exception hierarchy for the Smart Campus Attendance system.

Routers raise typed exceptions. The global handler in main.py converts them
into consistent JSON error envelopes with request correlation IDs.
"""

from __future__ import annotations


class AppError(Exception):
    """Base for all application errors."""

    def __init__(self, message: str, code: str, status_code: int = 500) -> None:
        super().__init__(message)
        self.message = message
        self.code = code
        self.status_code = status_code


# ── 4xx Client Errors ─────────────────────────────────────────────────────────


class NotFoundError(AppError):
    """Resource not found (404)."""

    def __init__(self, resource: str, resource_id: str) -> None:
        super().__init__(
            message=f"{resource} '{resource_id}' not found",
            code="NOT_FOUND",
            status_code=404,
        )


class ConflictError(AppError):
    """Business-rule conflict (409)."""

    def __init__(self, message: str) -> None:
        super().__init__(message=message, code="CONFLICT", status_code=409)


class AuthenticationError(AppError):
    """Missing or invalid credentials (401)."""

    def __init__(self, message: str = "Invalid or expired token") -> None:
        super().__init__(message=message, code="UNAUTHORIZED", status_code=401)


class AuthorizationError(AppError):
    """Insufficient permissions (403)."""

    def __init__(self, message: str = "Insufficient permissions") -> None:
        super().__init__(message=message, code="FORBIDDEN", status_code=403)


class ValidationError(AppError):
    """Application-level validation failure (422)."""

    def __init__(self, message: str) -> None:
        super().__init__(message=message, code="VALIDATION_ERROR", status_code=422)


# ── Domain-Specific Errors ────────────────────────────────────────────────────


class AttendanceError(AppError):
    """Attendance validation failure."""

    def __init__(self, message: str, code: str = "ATTENDANCE_ERROR") -> None:
        super().__init__(message=message, code=code, status_code=422)


class SessionExpiredError(AttendanceError):
    """Session has expired — no more attendance."""

    def __init__(self, session_id: str) -> None:
        super().__init__(
            message=f"Session '{session_id}' has expired",
            code="SESSION_EXPIRED",
        )


class DuplicateAttendanceError(AttendanceError):
    """Student already marked attendance for this session."""

    def __init__(self, session_id: str, student_id: str) -> None:
        super().__init__(
            message=f"Student '{student_id}' already marked attendance for session '{session_id}'",
            code="DUPLICATE_ATTENDANCE",
        )


class EnrollmentRequiredError(AttendanceError):
    """Student is not enrolled in the subject."""

    def __init__(self, student_id: str, subject_id: str) -> None:
        super().__init__(
            message=f"Student '{student_id}' is not enrolled in subject '{subject_id}'",
            code="NOT_ENROLLED",
        )


class InvalidTokenError(AttendanceError):
    """Beacon token mismatch — possible replay or wrong room."""

    def __init__(self) -> None:
        super().__init__(
            message="Invalid or expired beacon token",
            code="INVALID_TOKEN",
        )


class DeviceError(AppError):
    """Device registration/validation failure."""

    def __init__(self, message: str, code: str = "DEVICE_ERROR") -> None:
        super().__init__(message=message, code=code, status_code=422)


class DeviceMismatchError(DeviceError):
    """Device fingerprint does not match registered device."""

    def __init__(self, student_id: str) -> None:
        super().__init__(
            message=f"Device fingerprint does not match registered device for user '{student_id}'",
            code="DEVICE_MISMATCH",
        )


class DeviceNotRegisteredError(DeviceError):
    """Student has no registered device."""

    def __init__(self, student_id: str) -> None:
        super().__init__(
            message=f"No active registered device for user '{student_id}'",
            code="DEVICE_NOT_REGISTERED",
        )


class SessionError(AppError):
    """Session lifecycle error."""

    def __init__(self, message: str, code: str = "SESSION_ERROR") -> None:
        super().__init__(message=message, code=code, status_code=422)


class SessionNotActiveError(SessionError):
    """Session is not in active state."""

    def __init__(self, session_id: str) -> None:
        super().__init__(
            message=f"Session '{session_id}' is not active",
            code="SESSION_NOT_ACTIVE",
        )


# ── 5xx Server Errors ─────────────────────────────────────────────────────────


class ExternalServiceError(AppError):
    """An external dependency (Supabase, MQTT) failed (502)."""

    def __init__(self, service: str, detail: str) -> None:
        super().__init__(
            message=f"{service}: {detail}",
            code="EXTERNAL_ERROR",
            status_code=502,
        )
