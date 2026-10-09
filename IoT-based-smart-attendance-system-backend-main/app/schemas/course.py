"""Subject schemas — request/response DTOs."""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field


class SubjectCreate(BaseModel):
    """Request body to create a subject."""

    code: str = Field(min_length=2, max_length=20)
    name: str
    department: str
    semester: str | None = None
    credits: int | None = Field(default=None, gt=0)


class SubjectResponse(BaseModel):
    """Response body for a subject."""

    id: str
    code: str
    name: str
    department: str
    semester: str | None = None
    credits: int | None = None
    is_active: bool
    created_at: datetime
