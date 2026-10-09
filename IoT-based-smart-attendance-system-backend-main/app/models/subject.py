"""Subject model — academic subjects/courses offered by the institution."""

from __future__ import annotations

from sqlalchemy import Boolean, SmallInteger, String
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class Subject(Base):
    """An academic subject around which sessions and enrollments are organized."""

    __tablename__ = "subjects"

    code: Mapped[str] = mapped_column(String(20), unique=True, nullable=False)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    department: Mapped[str] = mapped_column(String(100), nullable=False)
    semester: Mapped[str | None] = mapped_column(String(20), nullable=True)
    credits: Mapped[int | None] = mapped_column(SmallInteger, nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
