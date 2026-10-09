"""Structured logging with correlation context.

Usage:
    from app.core.logging import get_logger
    logger = get_logger(__name__)
    logger.info("action", staff_id="abc", beacon_id="xyz")
"""

from __future__ import annotations

import json
import logging
import sys
from contextvars import ContextVar
from datetime import UTC, datetime
from typing import Any

# ── Context Variables (set per-request by middleware) ──────────────────────────

request_id_ctx: ContextVar[str | None] = ContextVar("request_id", default=None)
user_id_ctx: ContextVar[str | None] = ContextVar("user_id", default=None)
user_role_ctx: ContextVar[str | None] = ContextVar("user_role", default=None)


class StructuredFormatter(logging.Formatter):
    """JSON-lines log formatter with correlation context."""

    def format(self, record: logging.LogRecord) -> str:
        log_entry: dict[str, Any] = {
            "timestamp": datetime.now(UTC).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }

        # Attach request context if available
        req_id = request_id_ctx.get()
        if req_id:
            log_entry["request_id"] = req_id

        uid = user_id_ctx.get()
        if uid:
            log_entry["user_id"] = uid

        role = user_role_ctx.get()
        if role:
            log_entry["user_role"] = role

        # Attach any extra fields passed via logger.info("msg", extra={...})
        if hasattr(record, "extra_fields"):
            log_entry.update(record.extra_fields)

        # Attach exception info
        if record.exc_info and record.exc_info[1]:
            log_entry["exception"] = str(record.exc_info[1])

        return json.dumps(log_entry, default=str)


class ContextLogger(logging.LoggerAdapter):
    """Logger adapter that injects extra fields into structured output."""

    def process(self, msg: str, kwargs: dict[str, Any]) -> tuple[str, dict[str, Any]]:
        extra = kwargs.get("extra", {})
        # Merge caller-provided fields into a dedicated attribute
        extra_fields = {
            k: v
            for k, v in kwargs.items()
            if k not in ("exc_info", "stack_info", "stacklevel", "extra")
        }
        if extra_fields:
            extra["extra_fields"] = extra_fields
            # Clean non-standard kwargs so logging doesn't choke
            for k in extra_fields:
                kwargs.pop(k, None)
        kwargs["extra"] = extra
        return msg, kwargs


def setup_logging(debug: bool = False) -> None:
    """Configure root logger with structured JSON output."""
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(StructuredFormatter())

    root = logging.getLogger()
    root.handlers.clear()
    root.addHandler(handler)
    root.setLevel(logging.DEBUG if debug else logging.INFO)

    # Quiet noisy libraries
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("httpcore").setLevel(logging.WARNING)
    logging.getLogger("hpack").setLevel(logging.WARNING)


def get_logger(name: str) -> ContextLogger:
    """Create a structured logger with context injection."""
    return ContextLogger(logging.getLogger(name), {})
