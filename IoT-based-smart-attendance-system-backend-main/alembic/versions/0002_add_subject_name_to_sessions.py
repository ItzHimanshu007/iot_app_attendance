"""Add subject_name column to attendance_sessions; make subject_id nullable.

Revision ID: 0002
Revises    : 0001
Create Date: 2026-07-05

Changes
-------
* attendance_sessions.subject_id  → nullable (DROP NOT NULL)
* attendance_sessions.subject_name → new TEXT NULL column

This is an additive-only migration.  No existing rows are modified.
Historical sessions keep their subject_id; new sessions store subject_name.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

# ---------------------------------------------------------------------------
# Alembic revision identifiers
# ---------------------------------------------------------------------------
revision: str = "0002"
down_revision: str | None = "0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 1. Allow subject_id to be NULL (new sessions do not have one).
    op.alter_column(
        "attendance_sessions",
        "subject_id",
        nullable=True,
        existing_type=sa.String(36),
    )

    # 2. Add free-text subject_name column (NULL for all historical rows).
    op.add_column(
        "attendance_sessions",
        sa.Column("subject_name", sa.Text(), nullable=True),
    )


def downgrade() -> None:
    # Remove subject_name first.
    op.drop_column("attendance_sessions", "subject_name")

    # Restore NOT NULL on subject_id.
    # WARNING: this will fail if any rows were inserted after the upgrade
    # (those rows have subject_id = NULL).  Truncate or backfill first.
    op.alter_column(
        "attendance_sessions",
        "subject_id",
        nullable=False,
        existing_type=sa.String(36),
    )
