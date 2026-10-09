"""Supabase JWT verification — asymmetric (JWKS) and legacy HS256."""

from __future__ import annotations

import json
import time

import jwt
import pytest
from app.core.config import get_settings
from app.core.exceptions import AuthenticationError
from app.security import jwt_handler
from cryptography.hazmat.primitives.asymmetric import ec
from jwt.algorithms import ECAlgorithm


def _claims(**extra: object) -> dict[str, object]:
    return {
        "sub": "00000000-0000-0000-0000-000000000001",
        "email": "a@x.com",
        "aud": "authenticated",
        "exp": int(time.time()) + 600,
        **extra,
    }


def test_es256_via_jwks(monkeypatch: pytest.MonkeyPatch) -> None:
    key = ec.generate_private_key(ec.SECP256R1())
    jwk = json.loads(ECAlgorithm.to_jwk(key.public_key()))
    jwk.update(kid="k1", alg="ES256")
    monkeypatch.setattr(jwt_handler, "_fetch_jwks", lambda: {"keys": [jwk]})
    token = jwt.encode(_claims(), key, algorithm="ES256", headers={"kid": "k1"})
    payload = jwt_handler.decode_jwt(token)
    assert payload.sub.endswith("1") and payload.email == "a@x.com"

    other = ec.generate_private_key(ec.SECP256R1())
    forged = jwt.encode(_claims(), other, algorithm="ES256", headers={"kid": "k1"})
    with pytest.raises(AuthenticationError):
        jwt_handler.decode_jwt(forged)


def test_hs256_legacy(monkeypatch: pytest.MonkeyPatch) -> None:
    secret = "s" * 40
    monkeypatch.setattr(get_settings(), "jwt_secret", secret)
    token = jwt.encode(_claims(), secret, algorithm="HS256")
    assert jwt_handler.decode_jwt(token).email == "a@x.com"

    expired = jwt.encode(_claims(exp=int(time.time()) - 10), secret, algorithm="HS256")
    with pytest.raises(AuthenticationError, match="expired"):
        jwt_handler.decode_jwt(expired)

    wrong_aud = jwt.encode(_claims(aud="anon"), secret, algorithm="HS256")
    with pytest.raises(AuthenticationError):
        jwt_handler.decode_jwt(wrong_aud)


def test_hs256_without_secret_is_rejected(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(get_settings(), "jwt_secret", "")
    token = jwt.encode(_claims(), "x" * 40, algorithm="HS256")
    with pytest.raises(AuthenticationError, match="JWT_SECRET"):
        jwt_handler.decode_jwt(token)
