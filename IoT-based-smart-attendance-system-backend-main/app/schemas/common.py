"""Common schemas — pagination, error envelope, base response."""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel


class ErrorDetail(BaseModel):
    """Structured error detail inside the error envelope."""

    code: str
    message: str
    timestamp: datetime
    request_id: str | None = None


class ErrorResponse(BaseModel):
    """Consistent error envelope returned by all error handlers."""

    error: ErrorDetail


class PaginationParams(BaseModel):
    """Query parameters for paginated endpoints."""

    page: int = 1
    page_size: int = 20

    @property
    def offset(self) -> int:
        """Calculate the SQL offset."""
        return (self.page - 1) * self.page_size


class PaginatedResponse(BaseModel):
    """Wrapper for paginated list responses."""

    items: list
    total: int
    page: int
    page_size: int
    total_pages: int
