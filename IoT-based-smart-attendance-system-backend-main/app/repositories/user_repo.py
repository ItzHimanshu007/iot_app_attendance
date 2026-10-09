"""User repository."""

from __future__ import annotations

from typing import Any

from app.repositories.base import BaseRepository


class UserRepository(BaseRepository):
    table_name = "users"

    def get_by_email(self, email: str) -> dict[str, Any] | None:
        return self._safe_single(
            self.table.select("*").eq("email", email).maybe_single(),
            operation="get_by_email",
        )

    def get_by_role(self, role: str, active_only: bool = True) -> list[dict[str, Any]]:
        query = self.table.select("*").eq("role", role)
        if active_only:
            query = query.eq("is_active", True)
        return self._safe_execute(query, operation="get_by_role")

    def deactivate(self, user_id: str) -> dict[str, Any]:
        return self.update(user_id, {"is_active": False})
