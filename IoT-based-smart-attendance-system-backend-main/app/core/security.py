"""Security utilities — beacon token generation.

Full implementation lives in:
  - app.services.token_service (token gen/verify)
  - app.security.jwt_handler (JWT decode)
  - app.security.rbac (RBAC dependencies)

This module re-exports for backward compatibility.
"""

from app.security.jwt_handler import decode_jwt as decode_supabase_jwt
from app.services.token_service import (
    generate_session_token as generate_beacon_token,
)
from app.services.token_service import (
    verify_session_token as verify_beacon_token,
)

__all__ = [
    "decode_supabase_jwt",
    "generate_beacon_token",
    "verify_beacon_token",
]
