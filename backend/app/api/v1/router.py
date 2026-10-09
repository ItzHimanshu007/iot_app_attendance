"""Aggregates all v1 routers under /api/v1."""

from fastapi import APIRouter

from app.api.v1 import admin, attendance, me

v1_router = APIRouter(prefix="/api/v1")
v1_router.include_router(me.router)
v1_router.include_router(attendance.router)
v1_router.include_router(admin.router)
