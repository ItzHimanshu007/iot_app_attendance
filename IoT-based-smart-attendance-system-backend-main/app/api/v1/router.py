"""Aggregated v1 router — single import for main.py.

All v1 sub-routers are mounted here so the main app only needs:
    from app.api.v1.router import v1_router
    app.include_router(v1_router)
"""

from fastapi import APIRouter

from app.api.v1 import attendance, courses, notifications, reports, rooms, sessions, timetable, users

v1_router = APIRouter(prefix="/api/v1")

v1_router.include_router(sessions.router)
v1_router.include_router(attendance.router)
v1_router.include_router(users.router)
v1_router.include_router(courses.router)  # serves /subjects
v1_router.include_router(rooms.router)  # serves /classrooms
v1_router.include_router(notifications.router)
v1_router.include_router(timetable.router)
v1_router.include_router(reports.router)

