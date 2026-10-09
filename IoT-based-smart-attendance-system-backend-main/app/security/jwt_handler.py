"""Supabase JWT verification — supports both ES256 (new projects) and HS256 (legacy).

Supabase now issues ES256-signed JWTs for new projects. Tokens are verified
against the project's public JWKS endpoint, which is fetched and cached
on first use.

For legacy projects that still use HS256, set JWT_ALGORITHM=HS256 in .env
and ensure JWT_SECRET is set correctly.
"""

from __future__ import annotations

import json
import urllib.request
from dataclasses import dataclass
from functools import lru_cache
from typing import Any

import jwt
from jwt.algorithms import ECAlgorithm

from app.core.config import get_settings
from app.core.exceptions import AuthenticationError
from app.core.logging import get_logger

logger = get_logger(__name__)


@dataclass(frozen=True)
class JWTPayload:
    """Parsed JWT claims relevant to the application."""

    sub: str  # auth.uid() — maps to users.id
    email: str
    role: str  # Supabase role claim (e.g., "authenticated")
    exp: int
    app_role: str  # user_metadata.role — "student" | "teacher" | "admin"
    raw: dict[str, Any]


# ── JWKS cache ────────────────────────────────────────────────────────────────


@lru_cache(maxsize=1)
def _fetch_jwks() -> dict[str, Any]:
    """Fetch and cache the Supabase JWKS (JSON Web Key Set).

    Supabase exposes its public signing keys at:
      {SUPABASE_URL}/auth/v1/.well-known/jwks.json

    These keys are used to verify ES256 (ECDSA) signed JWTs.
    The result is cached for the lifetime of the process.
    """
    cfg = get_settings()
    jwks_url = f"{cfg.supabase_url}/auth/v1/.well-known/jwks.json"
    logger.info("Fetching Supabase JWKS", url=jwks_url)

    try:
        req = urllib.request.Request(
            jwks_url,
            headers={
                "apikey": cfg.supabase_anon_key,
                "Accept": "application/json",
            },
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            jwks = json.loads(resp.read())
            logger.info("JWKS fetched", key_count=len(jwks.get("keys", [])))
            return jwks
    except Exception as e:
        logger.error("Failed to fetch JWKS", error=str(e))
        raise AuthenticationError(f"Cannot verify token: JWKS fetch failed ({e})")


def _get_public_key(kid: str | None) -> Any:
    """Return the public key matching the given key ID from JWKS."""
    jwks = _fetch_jwks()
    keys = jwks.get("keys", [])

    if not keys:
        raise AuthenticationError("JWKS has no keys")

    # If kid provided, find exact match; otherwise use first key
    if kid:
        matching = [k for k in keys if k.get("kid") == kid]
        if not matching:
            # Key rotated — clear cache and retry once
            _fetch_jwks.cache_clear()
            jwks = _fetch_jwks()
            matching = [k for k in jwks.get("keys", []) if k.get("kid") == kid]
        if not matching:
            raise AuthenticationError(f"JWT key ID '{kid}' not found in JWKS")
        key_data = matching[0]
    else:
        key_data = keys[0]

    # Convert JWK → public key object
    alg = key_data.get("alg", "ES256")
    if alg.startswith("ES"):
        return ECAlgorithm.from_jwk(json.dumps(key_data))
    elif alg.startswith("RS"):
        from jwt.algorithms import RSAAlgorithm

        return RSAAlgorithm.from_jwk(json.dumps(key_data))
    else:
        raise AuthenticationError(f"Unsupported JWKS algorithm: {alg}")


# ── Main decoder ──────────────────────────────────────────────────────────────


def decode_jwt(token: str) -> JWTPayload:
    """Decode and verify a Supabase Auth JWT.

    Supports:
      - ES256  (new Supabase projects — verified via JWKS)
      - HS256  (legacy Supabase projects — verified via JWT_SECRET)

    Args:
        token: Raw JWT string (without "Bearer " prefix).

    Returns:
        Parsed JWTPayload with user identity.

    Raises:
        AuthenticationError: If the token is invalid, expired, or malformed.
    """
    settings = get_settings()

    # Peek at the header to determine algorithm — no verification yet
    try:
        unverified_header = jwt.get_unverified_header(token)
    except jwt.DecodeError:
        raise AuthenticationError("Malformed token — cannot read header")

    alg = unverified_header.get("alg", "HS256")
    kid = unverified_header.get("kid")

    try:
        if alg == "HS256":
            # Legacy HS256 — use the JWT_SECRET from .env
            payload = jwt.decode(
                token,
                settings.jwt_secret,
                algorithms=["HS256"],
                audience="authenticated",
                options={"require": ["sub", "exp"]},
            )

        elif alg in ("ES256", "RS256", "RS384", "RS512", "ES384", "ES512"):
            # Modern asymmetric — verify against Supabase JWKS public key
            public_key = _get_public_key(kid)
            payload = jwt.decode(
                token,
                public_key,
                algorithms=[alg],
                audience="authenticated",
                options={"require": ["sub", "exp"]},
            )

        else:
            raise AuthenticationError(f"Unsupported JWT algorithm: {alg}")

    except jwt.ExpiredSignatureError:
        raise AuthenticationError("Token has expired")
    except jwt.InvalidAudienceError:
        raise AuthenticationError("Invalid token audience")
    except jwt.DecodeError as e:
        raise AuthenticationError(f"Malformed token: {e}")
    except jwt.InvalidTokenError as e:
        raise AuthenticationError(f"Invalid token: {e}")
    except AuthenticationError:
        raise
    except Exception as e:
        raise AuthenticationError(f"Token verification failed: {e}")

    # Extract app-level role from user_metadata (set when creating the user)
    user_metadata = payload.get("user_metadata", {})
    app_role = user_metadata.get("role", "student")

    return JWTPayload(
        sub=payload["sub"],
        email=payload.get("email", ""),
        role=payload.get("role", "authenticated"),
        exp=payload["exp"],
        app_role=app_role,
        raw=payload,
    )
