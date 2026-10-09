"""Subjects router — list and query subjects."""

from __future__ import annotations

from fastapi import APIRouter

from app.api.deps import AdminUser, AuthenticatedUser
from app.core.exceptions import NotFoundError
from app.repositories.subject_repo import SubjectRepository
from app.schemas.course import SubjectCreate, SubjectResponse

router = APIRouter(prefix="/subjects", tags=["subjects"])

_repo = SubjectRepository()


@router.post("/", response_model=SubjectResponse, status_code=201)
async def create_subject(body: SubjectCreate, user: AdminUser) -> dict:
    """Create a new subject. Admin only."""
    data = {
        "code": body.code,
        "name": body.name,
        "department": body.department,
        "semester": body.semester,
        "credits": body.credits,
        "is_active": True,
    }
    return _repo.insert(data)


@router.get("/", response_model=list[SubjectResponse])
async def list_subjects(user: AuthenticatedUser, department: str | None = None) -> list[dict]:
    """List active subjects, optionally filtered by department."""
    return _repo.list_active(department=department)


@router.get("/{subject_id}", response_model=SubjectResponse)
async def get_subject(subject_id: str, user: AuthenticatedUser) -> dict:
    """Get a single subject by ID."""
    subject = _repo.get_by_id(subject_id)
    if not subject:
        raise NotFoundError("Subject", subject_id)
    return subject
