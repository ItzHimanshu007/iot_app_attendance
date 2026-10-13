"""Supabase Auth pass-through (for networks that block supabase.co)."""

from __future__ import annotations

from collections.abc import Iterator

import httpx
import pytest
from app.api import supabase_proxy
from app.core.config import get_settings
from app.main import app
from fastapi.testclient import TestClient

seen: list[httpx.Request] = []


def _upstream(request: httpx.Request) -> httpx.Response:
    seen.append(request)
    if request.url.path.endswith("/down"):
        raise httpx.ConnectError("blocked", request=request)
    return httpx.Response(
        200,
        json={"access_token": "jwt", "token_type": "bearer"},
        headers={"x-upstream": "supabase"},
    )


@pytest.fixture
def proxy() -> Iterator[TestClient]:
    seen.clear()
    supabase_proxy.set_http_client(httpx.AsyncClient(transport=httpx.MockTransport(_upstream)))
    yield TestClient(app)
    supabase_proxy.set_http_client(None)


def test_forwards_auth_requests_unchanged(proxy: TestClient) -> None:
    r = proxy.post(
        "/supabase/auth/v1/token?grant_type=password",
        json={"email": "a@skit.in", "password": "secret"},
        headers={"apikey": "anon-key", "Authorization": "Bearer anon-key"},
    )
    assert r.status_code == 200
    assert r.json() == {"access_token": "jwt", "token_type": "bearer"}
    assert r.headers["x-upstream"] == "supabase"

    sent = seen[-1]
    base = get_settings().supabase_url.rstrip("/")
    assert str(sent.url) == f"{base}/auth/v1/token?grant_type=password"
    assert sent.method == "POST"
    assert sent.headers["apikey"] == "anon-key"
    assert sent.headers["authorization"] == "Bearer anon-key"
    assert sent.headers["host"] == httpx.URL(base).host  # not the backend's host
    assert b'"password":"secret"' in sent.content


def test_only_the_auth_api_is_forwarded(proxy: TestClient) -> None:
    assert proxy.get("/supabase/rest/v1/staff").status_code == 404
    assert proxy.get("/supabase/auth/v1/../../rest/v1/staff").status_code == 404
    assert proxy.get("/supabase/auth/v1/%2e%2e/%2e%2e/rest/v1/staff").status_code == 404
    assert not any("/rest/" in str(r.url) for r in seen)


def test_unreachable_supabase_gives_502(proxy: TestClient) -> None:
    r = proxy.get("/supabase/auth/v1/down")
    assert r.status_code == 502
    assert r.json()["code"] == "upstream_unreachable"
