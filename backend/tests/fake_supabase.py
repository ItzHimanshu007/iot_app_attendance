"""In-memory stand-in for the supabase-py table API used by the repositories.

Supports exactly the builder calls the app uses:
    table(name).select(cols).eq/neq/gte/lte/lt/gt/is_/in_(...).order(...).limit(n)
               .maybe_single().execute()
    table(name).insert(row | rows).execute()
    table(name).update(data).<filters>.execute()
    table(name).upsert(row, on_conflict="col").execute()
    table(name).delete().<filters>.execute()

Unique constraints from the SQL migration are emulated so that duplicate
inserts raise an error with ``code == "23505"`` like PostgREST does.
"""

from __future__ import annotations

import copy
import uuid
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any

# (table, columns, partial-index predicate)
UNIQUE: list[tuple[str, tuple[str, ...], Callable[[dict[str, Any]], bool]]] = [
    ("attendance", ("staff_id", "attendance_date"), lambda r: True),
    ("devices", ("staff_id",), lambda r: bool(r.get("is_active"))),
    ("devices", ("device_fingerprint",), lambda r: bool(r.get("is_active"))),
    ("staff", ("employee_id",), lambda r: r.get("employee_id") is not None),
    ("face_templates", ("staff_id",), lambda r: True),
]

PRIMARY_KEY = {"face_templates": "staff_id"}


class FakeAPIError(Exception):
    """Mimics postgrest.exceptions.APIError."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


@dataclass
class FakeResponse:
    data: Any
    count: int | None = None


def _norm(value: Any) -> Any:
    if isinstance(value, bool) or value is None:
        return value
    if isinstance(value, (int, float)):
        return value
    return str(value)


class FakeQuery:
    def __init__(self, db: FakeSupabase, table: str) -> None:
        self.db = db
        self.table_name = table
        self.op = "select"
        self.payload: Any = None
        self.filters: list[Callable[[dict[str, Any]], bool]] = []
        self.order_by: list[tuple[str, bool]] = []
        self.limit_n: int | None = None
        self.single = False
        self.on_conflict: str | None = None
        self.columns = "*"

    # ── operations ────────────────────────────────────────────────────────
    def select(self, columns: str = "*", **_: Any) -> FakeQuery:
        self.op = "select"
        self.columns = columns
        return self

    def insert(self, payload: Any) -> FakeQuery:
        self.op, self.payload = "insert", payload
        return self

    def update(self, payload: dict[str, Any]) -> FakeQuery:
        self.op, self.payload = "update", payload
        return self

    def upsert(self, payload: Any, on_conflict: str | None = None, **_: Any) -> FakeQuery:
        self.op, self.payload, self.on_conflict = "upsert", payload, on_conflict
        return self

    def delete(self) -> FakeQuery:
        self.op = "delete"
        return self

    # ── filters ───────────────────────────────────────────────────────────
    def eq(self, col: str, value: Any) -> FakeQuery:
        self.filters.append(lambda r: _norm(r.get(col)) == _norm(value))
        return self

    def neq(self, col: str, value: Any) -> FakeQuery:
        self.filters.append(lambda r: _norm(r.get(col)) != _norm(value))
        return self

    def gte(self, col: str, value: Any) -> FakeQuery:
        self.filters.append(lambda r: r.get(col) is not None and str(r[col]) >= str(value))
        return self

    def lte(self, col: str, value: Any) -> FakeQuery:
        self.filters.append(lambda r: r.get(col) is not None and str(r[col]) <= str(value))
        return self

    def gt(self, col: str, value: Any) -> FakeQuery:
        self.filters.append(lambda r: r.get(col) is not None and str(r[col]) > str(value))
        return self

    def lt(self, col: str, value: Any) -> FakeQuery:
        self.filters.append(lambda r: r.get(col) is not None and str(r[col]) < str(value))
        return self

    def is_(self, col: str, value: str) -> FakeQuery:
        assert value == "null"
        self.filters.append(lambda r: r.get(col) is None)
        return self

    def in_(self, col: str, values: list[Any]) -> FakeQuery:
        wanted = {_norm(v) for v in values}
        self.filters.append(lambda r: _norm(r.get(col)) in wanted)
        return self

    # ── modifiers ─────────────────────────────────────────────────────────
    def order(self, col: str, desc: bool = False, **_: Any) -> FakeQuery:
        self.order_by.append((col, desc))
        return self

    def limit(self, n: int) -> FakeQuery:
        self.limit_n = n
        return self

    def range(self, start: int, end: int) -> FakeQuery:
        self.limit_n = end + 1
        return self

    def maybe_single(self) -> FakeQuery:
        self.single = True
        return self

    # ── execution ─────────────────────────────────────────────────────────
    def _matches(self) -> list[dict[str, Any]]:
        rows = self.db.tables.setdefault(self.table_name, [])
        return [r for r in rows if all(f(r) for f in self.filters)]

    def execute(self) -> FakeResponse | None:
        self.db.calls.append((self.table_name, self.op))
        if self.db.fail_tables and self.table_name in self.db.fail_tables:
            raise FakeAPIError("XX000", f"simulated failure on {self.table_name}")
        handler = getattr(self, f"_exec_{self.op}")
        return handler()

    def _project(self, row: dict[str, Any]) -> dict[str, Any]:
        if self.columns.strip() == "*":
            return copy.deepcopy(row)
        cols = [c.strip() for c in self.columns.split(",")]
        return {c: copy.deepcopy(row.get(c)) for c in cols}

    def _exec_select(self) -> FakeResponse | None:
        rows = self._matches()
        for col, desc in reversed(self.order_by):
            rows = sorted(
                rows, key=lambda r, c=col: (r.get(c) is None, str(r.get(c))), reverse=desc
            )
        if self.limit_n is not None:
            rows = rows[: self.limit_n]
        data = [self._project(r) for r in rows]
        if self.single:
            if not data:
                return None
            if len(data) > 1:
                raise FakeAPIError("PGRST116", "multiple rows")
            return FakeResponse(data=data[0])
        return FakeResponse(data=data)

    def _exec_insert(self) -> FakeResponse:
        items = self.payload if isinstance(self.payload, list) else [self.payload]
        out = []
        for item in items:
            row = self.db.with_defaults(self.table_name, dict(item))
            self.db.check_unique(self.table_name, row)
            self.db.tables.setdefault(self.table_name, []).append(row)
            out.append(copy.deepcopy(row))
        return FakeResponse(data=out)

    def _exec_update(self) -> FakeResponse:
        out = []
        for row in self._matches():
            candidate = {**row, **copy.deepcopy(self.payload)}
            if "updated_at" in row:
                candidate["updated_at"] = datetime.now(UTC).isoformat()
            self.db.check_unique(self.table_name, candidate, ignore=row)
            row.update(candidate)
            out.append(copy.deepcopy(row))
        return FakeResponse(data=out)

    def _exec_upsert(self) -> FakeResponse:
        key = self.on_conflict or PRIMARY_KEY.get(self.table_name, "id")
        items = self.payload if isinstance(self.payload, list) else [self.payload]
        out = []
        rows = self.db.tables.setdefault(self.table_name, [])
        for item in items:
            existing = next((r for r in rows if r.get(key) == item.get(key)), None)
            if existing:
                existing.update(copy.deepcopy(item))
                existing["updated_at"] = datetime.now(UTC).isoformat()
                out.append(copy.deepcopy(existing))
            else:
                row = self.db.with_defaults(self.table_name, dict(item))
                rows.append(row)
                out.append(copy.deepcopy(row))
        return FakeResponse(data=out)

    def _exec_delete(self) -> FakeResponse:
        matches = self._matches()
        self.db.tables[self.table_name] = [
            r for r in self.db.tables.get(self.table_name, []) if r not in matches
        ]
        return FakeResponse(data=copy.deepcopy(matches))


class FakeSupabase:
    """Holds tables as lists of dicts."""

    def __init__(self) -> None:
        self.tables: dict[str, list[dict[str, Any]]] = {}
        self.calls: list[tuple[str, str]] = []
        self.fail_tables: set[str] = set()

    def table(self, name: str) -> FakeQuery:
        return FakeQuery(self, name)

    def with_defaults(self, table: str, row: dict[str, Any]) -> dict[str, Any]:
        now = datetime.now(UTC).isoformat()
        if PRIMARY_KEY.get(table, "id") == "id":
            row.setdefault("id", str(uuid.uuid4()))
        row.setdefault("created_at", now)
        if table in ("staff", "face_templates", "beacons", "attendance", "campus_settings"):
            row.setdefault("updated_at", now)
        if table == "attendance":
            row.setdefault("flags", [])
            row.setdefault("is_manual", False)
        if table == "devices":
            row.setdefault("is_active", True)
        return row

    def check_unique(
        self, table: str, row: dict[str, Any], ignore: dict[str, Any] | None = None
    ) -> None:
        for tname, cols, predicate in UNIQUE:
            if tname != table or not predicate(row):
                continue
            key = tuple(_norm(row.get(c)) for c in cols)
            for other in self.tables.get(table, []):
                if other is ignore or not predicate(other):
                    continue
                if tuple(_norm(other.get(c)) for c in cols) == key:
                    raise FakeAPIError("23505", f"duplicate key on {table}{cols}")

    # Convenience for tests
    def insert(self, table: str, row: dict[str, Any]) -> dict[str, Any]:
        full = self.with_defaults(table, dict(row))
        self.tables.setdefault(table, []).append(full)
        return full

    def rows(self, table: str) -> list[dict[str, Any]]:
        return self.tables.get(table, [])
