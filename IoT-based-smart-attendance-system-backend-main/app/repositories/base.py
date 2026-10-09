"""Base repository — generic CRUD operations via Supabase REST client.

Every domain repository extends this class and inherits standard
get / list / insert / update / delete operations.

LAZY INITIALIZATION:
    Repositories can be instantiated at module load time (e.g. as module-level
    singletons). To avoid triggering a Supabase DNS lookup before .env is
    loaded, the Supabase client is resolved lazily on first table access via
    the ``_db`` property, NOT in ``__init__``.

DEFENSIVE EXECUTION:
    All methods that call ``.execute()`` must guard against:
      - resp being None (network drop, misconfigured mock)
      - resp.data being None (empty Supabase response)
      - resp.data being [] for operations that expect exactly one row

    These guards are implemented in the ``_safe_execute`` and
    ``_safe_single`` helpers below.  Domain repositories must use
    these helpers rather than calling ``.execute()`` directly.
"""

from __future__ import annotations

from typing import Any

from supabase import Client

from app.core.exceptions import AppError
from app.core.logging import get_logger
from app.services.supabase_client import get_supabase

logger = get_logger(__name__)


# ── Domain exception for repository-level failures ────────────────────────────


class RepositoryError(AppError):
    """Raised when a Supabase query fails unexpectedly at the repository layer.

    This is *not* raised for normal empty-result cases — those return
    None or [] as documented on each method.  It is raised when the
    Supabase client itself returns None or an unusable response object.
    """

    def __init__(self, message: str, table: str = "", operation: str = "") -> None:
        context = f"[{table}.{operation}] " if table or operation else ""
        super().__init__(
            message=f"{context}{message}",
            code="REPOSITORY_ERROR",
            status_code=500,
        )


class BaseRepository:
    """Generic Supabase table repository with lazy client initialization."""

    table_name: str = ""

    def __init__(self, client: Client | None = None) -> None:
        # Store the pre-provided client (for tests / DI), or None to use lazy init.
        # Do NOT call get_supabase() here — it would trigger a DNS lookup on
        # import when Supabase is not yet configured.
        self._provided_client: Client | None = client
        self.__client: Client | None = None  # lazy cache

    @property
    def _db(self) -> Client:
        """Return the Supabase client, resolving it lazily on first access."""
        if self.__client is None:
            self.__client = self._provided_client or get_supabase()
        return self.__client

    @property
    def table(self):
        """Shortcut to the Supabase table builder."""
        return self._db.table(self.table_name)

    # ── Internal safety helpers ────────────────────────────────────────────────

    def _safe_execute(self, query, *, operation: str) -> list[dict[str, Any]]:
        """Execute a query and return resp.data as a list.

        Guarantees:
          - Never raises AttributeError / TypeError from resp being None.
          - Returns [] for empty result sets.
          - Raises RepositoryError for genuinely unexpected None responses.
        """
        try:
            resp = query.execute()
        except Exception as exc:
            logger.error(
                "Supabase query failed",
                table=self.table_name,
                operation=operation,
                error=str(exc),
            )
            raise RepositoryError(
                f"Query failed: {exc}",
                table=self.table_name,
                operation=operation,
            ) from exc

        if resp is None:
            # Supabase client returned None — shouldn't happen, but guard anyway.
            raise RepositoryError(
                "Supabase returned None response",
                table=self.table_name,
                operation=operation,
            )

        return resp.data or []

    def _safe_single(self, query, *, operation: str) -> dict[str, Any] | None:
        """Execute a maybe_single() query and return the row or None.

        Supabase/postgrest-py 2.30.0 contract for SyncMaybeSingleRequestBuilder.execute():
          - 0 rows → returns None          ← normal "not found", NOT a failure
          - 1 row  → returns SingleAPIResponse(data=<dict>, ...)
          - >1 rows → raises APIError
          - HTTP/network error → raises APIError / ValidationError

        Guarantees this method provides:
          - Returns None when no matching row exists (empty table, filtered-out rows).
          - Returns the row dict when exactly one row matches.
          - Raises RepositoryError on Supabase-level failures (exceptions only).
          - Never raises AttributeError / TypeError.
        """
        try:
            resp = query.execute()
        except Exception as exc:
            logger.error(
                "Supabase maybe_single query failed",
                table=self.table_name,
                operation=operation,
                error=str(exc),
            )
            raise RepositoryError(
                f"Query failed: {exc}",
                table=self.table_name,
                operation=operation,
            ) from exc

        # resp is None when the query matched 0 rows — this is the documented
        # postgrest-py behavior, not a failure.  Return None to signal "not found".
        if resp is None:
            return None

        # resp.data is the matched row dict (SingleAPIResponse wraps it).
        # Guard against any edge case where resp exists but data is somehow falsy.
        return resp.data if resp.data else None

    def _safe_write(self, query, *, operation: str) -> dict[str, Any]:
        """Execute an insert/update/upsert and return the first returned row.

        Guarantees:
          - Returns the written row dict.
          - Raises RepositoryError when the response is empty (write failed silently).
          - Never raises AttributeError / TypeError.
        """
        rows = self._safe_execute(query, operation=operation)
        if not rows:
            raise RepositoryError(
                f"{operation} returned no rows — possible RLS policy block or missing RETURNING clause",
                table=self.table_name,
                operation=operation,
            )
        return rows[0]

    # ── Read ──────────────────────────────────────────────────────────────────

    def get_by_id(self, record_id: str) -> dict[str, Any] | None:
        """Fetch a single record by primary key.

        Returns:
            Row dict if found, None if not found.

        Raises:
            RepositoryError: On Supabase connection / query failure.
        """
        return self._safe_single(
            self.table.select("*").eq("id", record_id).maybe_single(),
            operation="get_by_id",
        )

    def list_all(
        self,
        filters: dict[str, Any] | None = None,
        order_by: str = "created_at",
        ascending: bool = False,
        limit: int = 100,
        offset: int = 0,
    ) -> list[dict[str, Any]]:
        """List records with optional filters, ordering, and pagination."""
        query = self.table.select("*")
        if filters:
            for col, val in filters.items():
                query = query.eq(col, val)
        query = query.order(order_by, desc=not ascending)
        query = query.range(offset, offset + limit - 1)
        return self._safe_execute(query, operation="list_all")

    def count(self, filters: dict[str, Any] | None = None) -> int:
        """Count records matching filters."""
        query = self._db.table(self.table_name).select("id", count="exact")
        if filters:
            for col, val in filters.items():
                query = query.eq(col, val)
        try:
            resp = query.execute()
        except Exception as exc:
            logger.error(
                "Supabase count query failed",
                table=self.table_name,
                error=str(exc),
            )
            raise RepositoryError(
                f"Count query failed: {exc}",
                table=self.table_name,
                operation="count",
            ) from exc

        if resp is None:
            raise RepositoryError(
                "Supabase returned None on count",
                table=self.table_name,
                operation="count",
            )
        return resp.count or 0

    # ── Write ─────────────────────────────────────────────────────────────────

    def insert(self, data: dict[str, Any]) -> dict[str, Any]:
        """Insert a single record and return it."""
        return self._safe_write(
            self.table.insert(data),
            operation="insert",
        )

    def upsert(self, data: dict[str, Any]) -> dict[str, Any]:
        """Insert or update a record (uses PK conflict resolution)."""
        return self._safe_write(
            self.table.upsert(data),
            operation="upsert",
        )

    def update(self, record_id: str, data: dict[str, Any]) -> dict[str, Any]:
        """Update a record by ID and return the updated version."""
        return self._safe_write(
            self.table.update(data).eq("id", record_id),
            operation="update",
        )

    def delete(self, record_id: str) -> None:
        """Hard-delete a record by ID."""
        self._safe_execute(
            self.table.delete().eq("id", record_id),
            operation="delete",
        )

    def soft_delete(self, record_id: str) -> dict[str, Any]:
        """Soft-delete by setting is_active = False."""
        return self.update(record_id, {"is_active": False})
