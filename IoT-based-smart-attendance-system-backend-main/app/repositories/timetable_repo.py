"""Timetable repository."""

from __future__ import annotations

from typing import Any

from app.repositories.base import BaseRepository


class TimetableRepository(BaseRepository):
    table_name = "timetables"

    def get_teacher_subjects(self, teacher_id: str) -> list[dict[str, Any]]:
        """All active timetable entries for a teacher."""
        return self._safe_execute(
            self.table.select("*").eq("teacher_id", teacher_id).eq("is_active", True),
            operation="get_teacher_subjects",
        )

    def teacher_owns_subject(self, teacher_id: str, subject_id: str) -> bool:
        """Check if a teacher is assigned to a subject."""
        rows = self._safe_execute(
            self.table.select("id")
            .eq("teacher_id", teacher_id)
            .eq("subject_id", subject_id)
            .eq("is_active", True)
            .limit(1),
            operation="teacher_owns_subject",
        )
        return bool(rows)

    def teacher_owns_classroom(self, teacher_id: str, classroom_id: str) -> bool:
        """Check if a teacher has any timetable slot in a classroom."""
        rows = self._safe_execute(
            self.table.select("id")
            .eq("teacher_id", teacher_id)
            .eq("classroom_id", classroom_id)
            .eq("is_active", True)
            .limit(1),
            operation="teacher_owns_classroom",
        )
        return bool(rows)

    def teacher_owns_subject_in_classroom(
        self, teacher_id: str, subject_id: str, classroom_id: str
    ) -> bool:
        """Check the full teacher+subject+classroom authorization triple."""
        rows = self._safe_execute(
            self.table.select("id")
            .eq("teacher_id", teacher_id)
            .eq("subject_id", subject_id)
            .eq("classroom_id", classroom_id)
            .eq("is_active", True)
            .limit(1),
            operation="teacher_owns_subject_in_classroom",
        )
        return bool(rows)

    def get_teacher_timetable(self, teacher_id: str) -> list[dict[str, Any]]:
        """Get all active timetable entries for a teacher with subject and classroom names."""
        return self._safe_execute(
            self.table.select("*, subject:subjects(name), classroom:classrooms(name)")
            .eq("teacher_id", teacher_id)
            .eq("is_active", True),
            operation="get_teacher_timetable",
        )

    def get_all_active_timetable(self) -> list[dict[str, Any]]:
        """Get all active timetable entries (for admin view)."""
        return self._safe_execute(
            self.table.select("*, subject:subjects(name), classroom:classrooms(name)")
            .eq("is_active", True),
            operation="get_all_active_timetable",
        )

    def get_today_timetable(self, day_of_week: int, teacher_id: str | None = None) -> list[dict[str, Any]]:
        """Get active timetable slots for a specific day of week, optionally filtered by teacher."""
        query = self.table.select("*, subject:subjects(name), classroom:classrooms(name)").eq("day_of_week", day_of_week).eq("is_active", True)
        if teacher_id:
            query = query.eq("teacher_id", teacher_id)
        return self._safe_execute(query, operation="get_today_timetable")
