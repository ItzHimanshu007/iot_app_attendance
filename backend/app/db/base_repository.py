"""Base repository — thin, defensive wrapper around the Supabase table API.

Every domain repository extends :class:`BaseRepository` and uses the
``_rows`` / ``_one`` / ``_write`` helpers instead of calling ``.execute()``
directly, so that:

* network / PostgREST failures become a typed ``RepositoryError`` (500),
* unique-constraint violations (Postgres 23505) become a ``ConflictError`` (409),
* "no row" is always ``None`` / ``[]`` — never an AttributeError.
"""

from __future__ import annotations

from typing import Any

from app.core.exceptions import AppError, ConflictError
from app.core.logging import get_logger
from app.db.supabase_client import get_supabase

logger = get_logger(__name__)

UNIQUE_VIOLATION = "23505"


class RepositoryError(AppError):
    """A Supabase query failed unexpectedly."""

    def __init__(self, message: str, table: str = "", operation: str = "") -> None:
        context = f"[{table}.{operation}] " if table or operation else ""
        super().__init__(f"{context}{message}", "REPOSITORY_ERROR", 500)


def _error_code(exc: Exception) -> str | None:
    code = getattr(exc, "code", None)
    if code is None and exc.args and isinstance(exc.args[0], dict):
        code = exc.args[0].get("code")
    return str(code) if code is not None else None


class BaseRepository:
    """Generic Supabase table repository with lazy client resolution."""

    table_name: str = ""

    @property
    def table(self) -> Any:
        """Query builder for this repository's table."""
        return get_supabase().table(self.table_name)

    # ── Execution helpers ─────────────────────────────────────────────────────

    def _execute(self, query: Any, operation: str) -> Any:
        try:
            return query.execute()
        except Exception as exc:
            if _error_code(exc) == UNIQUE_VIOLATION:
                raise ConflictError(
                    f"Duplicate {self.table_name} record", code="DUPLICATE"
                ) from exc
            logger.error(
                "Supabase query failed",
                table=self.table_name,
                operation=operation,
                error=str(exc),
            )
            raise RepositoryError(f"Query failed: {exc}", self.table_name, operation) from exc

    def _rows(self, query: Any, operation: str) -> list[dict[str, Any]]:
        """Execute and return all rows ([] when none)."""
        resp = self._execute(query, operation)
        if resp is None:
            return []
        return list(resp.data or [])

    def _one(self, query: Any, operation: str) -> dict[str, Any] | None:
        """Execute a ``.maybe_single()`` query; None when no row matched."""
        resp = self._execute(query, operation)
        if resp is None or not resp.data:
            return None
        return dict(resp.data)

    def _write(self, query: Any, operation: str) -> dict[str, Any]:
        """Execute an insert/update/upsert and return the first written row."""
        rows = self._rows(query, operation)
        if not rows:
            raise RepositoryError(
                f"{operation} returned no rows (RLS block or no match)",
                self.table_name,
                operation,
            )
        return rows[0]

    # ── Common operations ─────────────────────────────────────────────────────

    def get_by_id(self, record_id: str) -> dict[str, Any] | None:
        """Fetch a single row by primary key ``id``."""
        return self._one(self.table.select("*").eq("id", record_id).maybe_single(), "get_by_id")

    def insert(self, data: dict[str, Any]) -> dict[str, Any]:
        """Insert one row and return it."""
        return self._write(self.table.insert(data), "insert")

    def update(self, record_id: str, data: dict[str, Any]) -> dict[str, Any]:
        """Update a row by ``id`` and return it."""
        return self._write(self.table.update(data).eq("id", record_id), "update")
