"""Alembic environment configuration.

Loads the SQLAlchemy URL from the application config and runs migrations
against the Supabase PostgreSQL database.
"""

from logging.config import fileConfig

from alembic import context
from app.core.config import get_settings
from app.models import Base
from sqlalchemy import engine_from_config, pool

# Alembic Config object
config = context.config

# Override sqlalchemy.url with a valid Postgres connection string
import os

settings = get_settings()
db_url = os.environ.get("DATABASE_URL")

if not db_url:
    db_url = getattr(settings, "database_url", None)
    if not db_url and hasattr(settings, "supabase_url"):
        val = settings.supabase_url
        if val.startswith("http://") or val.startswith("https://"):
            raise RuntimeError(
                "Alembic database migration failed: The configured URL is a Supabase HTTPS REST endpoint. "
                "Migrations require direct database access (a PostgreSQL connection string starting with "
                "'postgresql://' or 'postgres://') instead of the API REST URL. "
                "Please configure DATABASE_URL in your environment or .env file."
            )
        elif val.startswith("postgresql://") or val.startswith("postgres://"):
            db_url = val

if not db_url or not (db_url.startswith("postgresql://") or db_url.startswith("postgres://")):
    raise RuntimeError(
        "Alembic database migration failed: No valid PostgreSQL connection string found. "
        "Please set the DATABASE_URL environment variable (e.g., 'postgresql://user:pass@host:port/db') "
        "in your environment or .env file."
    )

config.set_main_option("sqlalchemy.url", db_url)


# Interpret the config file for Python logging
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# Target metadata for autogenerate
target_metadata = Base.metadata


def run_migrations_offline() -> None:
    """Run migrations in 'offline' mode."""
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """Run migrations in 'online' mode."""
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    with connectable.connect() as connection:
        context.configure(connection=connection, target_metadata=target_metadata)
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
