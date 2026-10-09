"""Shared API dependencies."""

from app.security.rbac import (
    AdminUser,
    AuthenticatedUser,
    CurrentUser,
    StudentUser,
    TeacherUser,
    get_current_user,
    require_admin,
    require_student,
    require_teacher,
    require_teacher_or_admin,
)

__all__ = [
    "AdminUser",
    "AuthenticatedUser",
    "CurrentUser",
    "StudentUser",
    "TeacherUser",
    "get_current_user",
    "require_admin",
    "require_student",
    "require_teacher",
    "require_teacher_or_admin",
]
