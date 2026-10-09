"""Supabase JWT verification — ES256/RS256 via JWKS (new projects) and HS256 (legacy).

New Supabase projects sign access tokens with asymmetric keys. The public keys
are published at ``{SUPABASE_URL}/auth/v1/.well-known/jwks.json`` and cached
here. Projects that still use the legacy shared secret need ``JWT_SECRET``.
"""

from __future__ import annotations

import json
import urllib.request
from dataclasses import dataclass
from functools import lru_cache
from typing import Any

import jwt
from jwt.algorithms import ECAlgorithm, RSAAlgorithm

from app.core.config import get_settings
from app.core.exceptions import AuthenticationError
from app.core.logging import get_logger

logger = get_logger(__name__)

_ASYMMETRIC = ("ES256", "ES384", "ES512", "RS256", "RS384", "RS512")


@dataclass(frozen=True)
class JWTPayload:
    """Verified JWT claims relevant to the application."""

    sub: str  # auth.uid() == staff.id
    email: str
    exp: int
    raw: dict[str, Any]


@lru_cache(maxsize=1)
def _fetch_jwks() -> dict[str, Any]:
    """Fetch and cache the project's JWKS."""
    cfg = get_settings()
    url = f"{cfg.supabase_url.rstrip('/')}/auth/v1/.well-known/jwks.json"
    headers = {"Accept": "application/json"}
    if cfg.supabase_anon_key:
        headers["apikey"] = cfg.supabase_anon_key
    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=10) as resp:
            jwks: dict[str, Any] = json.loads(resp.read())
    except Exception as e:
        logger.error("Failed to fetch JWKS", url=url, error=str(e))
        raise AuthenticationError(f"Cannot verify token: JWKS fetch failed ({e})") from e
    logger.info("JWKS fetched", key_count=len(jwks.get("keys", [])))
    return jwks


def _public_key(kid: str | None) -> Any:
    keys = _fetch_jwks().get("keys", [])
    match = [k for k in keys if not kid or k.get("kid") == kid]
    if not match and kid:
        # Keys were rotated — refresh once.
        _fetch_jwks.cache_clear()
        match = [k for k in _fetch_jwks().get("keys", []) if k.get("kid") == kid]
    if not match:
        raise AuthenticationError("Token signing key not found in JWKS")
    key_data = match[0]
    if key_data.get("kty") == "RSA":
        return RSAAlgorithm.from_jwk(json.dumps(key_data))
    return ECAlgorithm.from_jwk(json.dumps(key_data))


def decode_jwt(token: str) -> JWTPayload:
    """Verify a Supabase access token and return its claims.

    Raises:
        AuthenticationError: invalid, expired or malformed token.
    """
    settings = get_settings()
    try:
        header = jwt.get_unverified_header(token)
    except jwt.DecodeError as e:
        raise AuthenticationError("Malformed token") from e

    alg = header.get("alg", "HS256")
    options = {"require": ["sub", "exp"]}
    try:
        if alg == "HS256":
            if not settings.jwt_secret:
                raise AuthenticationError(
                    "Token uses legacy HS256 but JWT_SECRET is not configured on the server"
                )
            payload = jwt.decode(
                token,
                settings.jwt_secret,
                algorithms=["HS256"],
                audience="authenticated",
                options=options,
            )
        elif alg in _ASYMMETRIC:
            payload = jwt.decode(
                token,
                _public_key(header.get("kid")),
                algorithms=[alg],
                audience="authenticated",
                options=options,
            )
        else:
            raise AuthenticationError(f"Unsupported JWT algorithm: {alg}")
    except jwt.ExpiredSignatureError as e:
        raise AuthenticationError("Token has expired") from e
    except jwt.InvalidTokenError as e:
        raise AuthenticationError(f"Invalid token: {e}") from e

    return JWTPayload(
        sub=str(payload["sub"]),
        email=str(payload.get("email", "")),
        exp=int(payload["exp"]),
        raw=payload,
    )
