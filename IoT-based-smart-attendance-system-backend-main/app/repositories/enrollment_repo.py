"""Enrollment repository."""

from __future__ import annotations

from typing import Any

from app.repositories.base import BaseRepository


class EnrollmentRepository(BaseRepository):
    table_name = "enrollments"

    def is_enrolled(self, student_id: str, subject_id: str) -> bool:
        """Check if a student has an active enrollment for a subject."""
        rows = self._safe_execute(
            self.table.select("id")
            .eq("student_id", student_id)
            .eq("subject_id", subject_id)
            .eq("status", "active")
            .limit(1),
            operation="is_enrolled",
        )
        return bool(rows)

    def get_student_subjects(self, student_id: str) -> list[dict[str, Any]]:
        """All active enrollments for a student."""
        return self._safe_execute(
            self.table.select("*").eq("student_id", student_id).eq("status", "active"),
            operation="get_student_subjects",
        )

    def get_subject_students(self, subject_id: str) -> list[dict[str, Any]]:
        """All active enrollments for a subject."""
        return self._safe_execute(
            self.table.select("*").eq("subject_id", subject_id).eq("status", "active"),
            operation="get_subject_students",
        )

    def get_subject_students_with_profiles(self, subject_id: str) -> list[dict[str, Any]]:
        """Fetch all active enrollments for a subject along with the student's user profile."""
        return self._safe_execute(
            self.table.select("*, student:users(*)")
            .eq("subject_id", subject_id)
            .eq("status", "active"),
            operation="get_subject_students_with_profiles",
        )

    def list_active(self) -> list[dict[str, Any]]:
        """All active enrollments across all subjects."""
        return self._safe_execute(
            self.table.select("*").eq("status", "active"),
            operation="list_active",
        )

