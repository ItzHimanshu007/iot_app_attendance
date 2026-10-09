"""Shared fixtures: in-memory Supabase, fake auth, seed helpers, controllable clock."""

from __future__ import annotations

import os
import random
import time
from collections.abc import Generator
from datetime import UTC, datetime
from typing import Any

os.environ.setdefault("DEBUG", "true")

import pytest
from app.db.supabase_client import set_supabase_client
from app.main import app
from app.security import auth as auth_module
from app.security.jwt_handler import JWTPayload
from app.services import admin_service, attendance_service, device_service, face_service
from app.services.beacon_token import compute_token, current_window
from fastapi.testclient import TestClient

from tests.fake_supabase import FakeSupabase

DIM = 192
CAMPUS_LAT, CAMPUS_LNG = 26.8226, 75.8644


def vector(seed: int, dim: int = DIM) -> list[float]:
    rng = random.Random(seed)
    return [rng.gauss(0, 1) for _ in range(dim)]


def near(base: list[float], seed: int, noise: float = 0.25) -> list[float]:
    rng = random.Random(seed)
    return [v + rng.gauss(0, noise) for v in base]


class World:
    """Seed helpers bound to one fake database."""

    def __init__(self, db: FakeSupabase) -> None:
        self.db = db
        self.db.insert(
            "campus_settings",
            {
                "id": 1,
                "campus_name": "Test Campus",
                "timezone": "Asia/Kolkata",
                "latitude": CAMPUS_LAT,
                "longitude": CAMPUS_LNG,
                "radius_m": 500,
                "geofence_mode": "flag",
                "max_location_accuracy_m": 150,
                "work_start_time": "09:00:00",
                "late_grace_minutes": 15,
                "face_match_threshold": 0.55,
            },
        )

    def staff(
        self,
        name: str = "Asha Rao",
        role: str = "staff",
        status: str = "active",
        employee_id: str | None = None,
    ) -> dict[str, Any]:
        sid = f"00000000-0000-0000-0000-{len(self.db.rows('staff')) + 1:012d}"
        return self.db.insert(
            "staff",
            {
                "id": sid,
                "email": f"{name.split()[0].lower()}@college.edu",
                "full_name": name,
                "employee_id": employee_id or f"EMP{len(self.db.rows('staff')) + 1:03d}",
                "department": "CSE",
                "role": role,
                "status": status,
            },
        )

    def device(self, staff_id: str, fingerprint: str | None = None) -> dict[str, Any]:
        return self.db.insert(
            "devices",
            {
                "staff_id": staff_id,
                "device_fingerprint": fingerprint or f"fp-{staff_id}-abcdef0123456789",
                "device_model": "Pixel 8",
                "is_active": True,
            },
        )

    def face(self, staff_id: str, seed: int, status: str = "approved") -> list[float]:
        base = vector(seed)
        samples = [face_service.normalize(near(base, seed * 10 + i)) for i in range(3)]
        self.db.insert(
            "face_templates",
            {
                "staff_id": staff_id,
                "embeddings": samples,
                "embedding_dim": DIM,
                "sample_count": 3,
                "model_version": "mobilefacenet-v1",
                "status": status,
            },
        )
        return base

    def beacon(self, name: str = "Staff Room", rssi_threshold: int = -85) -> dict[str, Any]:
        return self.db.insert(
            "beacons",
            {
                "id": "43905a99-a513-5a9d-8cb5-e109b98166bb",
                "name": name,
                "secret": "a" * 64,
                "rssi_threshold": rssi_threshold,
                "is_active": True,
            },
        )

    def ready_staff(
        self, seed: int = 7, **kwargs: Any
    ) -> tuple[dict[str, Any], dict[str, Any], list[float]]:
        staff = self.staff(**kwargs)
        device = self.device(staff["id"])
        base = self.face(staff["id"], seed)
        return staff, device, base


def beacon_token(beacon: dict[str, Any], windows_ago: int = 0) -> str:
    return compute_token(
        beacon["secret"], beacon["id"], current_window(30, time.time()) - windows_ago
    )


def headers(staff: dict[str, Any]) -> dict[str, str]:
    return {"Authorization": f"Bearer test:{staff['id']}"}


@pytest.fixture()
def db() -> Generator[FakeSupabase, None, None]:
    fake = FakeSupabase()
    set_supabase_client(fake)
    yield fake
    set_supabase_client(None)


@pytest.fixture()
def world(db: FakeSupabase) -> World:
    return World(db)


@pytest.fixture(autouse=True)
def fake_jwt(monkeypatch: pytest.MonkeyPatch) -> None:
    def decode(token: str) -> JWTPayload:
        from app.core.exceptions import AuthenticationError

        if not token.startswith("test:"):
            raise AuthenticationError("bad token")
        return JWTPayload(sub=token[5:], email="", exp=9999999999, raw={})

    monkeypatch.setattr(auth_module, "decode_jwt", decode)


class Clock:
    def __init__(self, monkeypatch: pytest.MonkeyPatch) -> None:
        self.now = datetime.now(UTC)
        for module in (attendance_service, device_service, admin_service):
            monkeypatch.setattr(module, "now_utc", lambda: self.now)

    def set_local(self, hour: int, minute: int) -> None:
        """Set the clock to today at HH:MM India time (UTC+5:30)."""
        from zoneinfo import ZoneInfo

        tz = ZoneInfo("Asia/Kolkata")
        local = datetime.now(tz).replace(hour=hour, minute=minute, second=0, microsecond=0)
        self.now = local.astimezone(UTC)


@pytest.fixture()
def clock(monkeypatch: pytest.MonkeyPatch) -> Clock:
    return Clock(monkeypatch)


@pytest.fixture()
def client(db: FakeSupabase) -> TestClient:
    return TestClient(app)
