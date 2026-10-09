"""Classrooms router — list and query classrooms."""

from __future__ import annotations

from fastapi import APIRouter

from app.api.deps import AuthenticatedUser
from app.core.exceptions import NotFoundError
from app.repositories.classroom_repo import ClassroomRepository

router = APIRouter(prefix="/classrooms", tags=["classrooms"])

_repo = ClassroomRepository()


@router.get("/")
async def list_classrooms(user: AuthenticatedUser) -> list[dict]:
    """List all active classrooms."""
    return _repo.list_active()


@router.get("/{classroom_id}")
async def get_classroom(classroom_id: str, user: AuthenticatedUser) -> dict:
    """Get a single classroom by ID."""
    classroom = _repo.get_by_id(classroom_id)
    if not classroom:
        raise NotFoundError("Classroom", classroom_id)
    return classroom
