"""complete the PostgreSQL-ready backend core

Revision ID: 0009_phase5_backend_core
Revises: 0008_market_observability
"""
from datetime import datetime, timezone
from typing import Sequence, Union

from alembic import op
from alembic import context
import sqlalchemy as sa
from sqlalchemy import inspect

revision: str = "0009_phase5_backend_core"
down_revision: Union[str, None] = "0008_market_observability"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, None] = None


def _numeric_columns() -> dict[str, tuple[str, ...]]:
    return {
        "market_quotes": ("price", "provider_spread_percent"),
        "market_candles": ("open", "high", "low", "close", "volume"),
        "forecast_records": ("anchor_price", "point_estimate", "lower_bound", "upper_bound", "probability_up"),
        "forecast_evaluations": ("actual_price", "absolute_error", "absolute_percentage_error", "probability_up"),
        "alert_rules": ("threshold",),
        "paper_accounts": ("initial_balance", "cash_balance"),
        "paper_positions": ("quantity", "average_entry_price"),
        "paper_trades": ("quantity", "price", "notional", "fee", "realized_pnl"),
    }


def _table_exists(name: str) -> bool:
    if context.is_offline_mode():
        return False
    return inspect(op.get_bind()).has_table(name)


def _index_exists(name: str, table: str) -> bool:
    if context.is_offline_mode():
        return False
    return any(item.get("name") == name for item in inspect(op.get_bind()).get_indexes(table))


def upgrade() -> None:
    # Numeric is used for persisted prices and money. ``asdecimal=False`` at
    # the SQLAlchemy boundary preserves the existing service arithmetic while
    # the database stores exact NUMERIC values instead of binary floats.
    for table, columns in _numeric_columns().items():
        with op.batch_alter_table(table) as batch:
            for column in columns:
                scale = 12 if column in {"provider_spread_percent", "absolute_percentage_error", "probability_up", "threshold"} else 18
                batch.alter_column(
                    column,
                    type_=sa.Numeric(38, scale),
                    existing_type=sa.Float(),
                    existing_nullable=column == "volume" or column in {"provider_spread_percent", "probability_up"},
                )

    if not _table_exists("market_assets"):
        op.create_table(
            "market_assets",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("symbol", sa.String(length=24), nullable=False),
            sa.Column("name", sa.String(length=120), nullable=False),
            sa.Column("asset_class", sa.String(length=32), nullable=False),
            sa.Column("quote_currency", sa.String(length=12), nullable=False),
            sa.Column("unit", sa.String(length=24), nullable=False),
            sa.Column("market", sa.String(length=24), nullable=False),
            sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.true()),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
            sa.UniqueConstraint("symbol", name="uq_market_assets_symbol"),
        )
    market_assets = sa.table(
        "market_assets",
        sa.column("symbol", sa.String), sa.column("name", sa.String),
        sa.column("asset_class", sa.String), sa.column("quote_currency", sa.String),
        sa.column("unit", sa.String), sa.column("market", sa.String),
        sa.column("enabled", sa.Boolean()), sa.column("created_at", sa.DateTime(timezone=True)),
    )
    for row in (
        {"symbol": "BTC", "name": "Bitcoin", "asset_class": "crypto", "quote_currency": "USDT", "unit": "coin", "market": "GLOBAL", "enabled": True},
        {"symbol": "USDT", "name": "Tether / Toman", "asset_class": "crypto_fx", "quote_currency": "IRT", "unit": "coin", "market": "IRAN", "enabled": True},
        {"symbol": "GOLD18", "name": "18K Gold / Gram", "asset_class": "gold", "quote_currency": "IRT", "unit": "gram_18k", "market": "IRAN", "enabled": True},
    ):
        row["created_at"] = datetime.now(timezone.utc)
        if context.is_offline_mode():
            op.bulk_insert(market_assets, [row])
        else:
            op.execute(sa.insert(market_assets).from_select(
                list(row.keys()), sa.select(*[sa.bindparam(key, value=value) for key, value in row.items()]).where(
                    ~sa.exists(sa.select(1).select_from(market_assets).where(market_assets.c.symbol == row["symbol"]))
                )
            ))

    if not _table_exists("watchlists"):
        op.create_table(
            "watchlists",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("user_public_id", sa.String(length=36), nullable=False),
        sa.Column("symbol", sa.String(length=24), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["user_public_id"], ["users.public_id"]),
        sa.UniqueConstraint("user_public_id", "symbol", name="uq_watchlist_user_symbol"),
        )
    if not _index_exists("ix_watchlists_user_public_id", "watchlists"):
        op.create_index("ix_watchlists_user_public_id", "watchlists", ["user_public_id"])
    if not _index_exists("ix_watchlists_symbol", "watchlists"):
        op.create_index("ix_watchlists_symbol", "watchlists", ["symbol"])

    if not _table_exists("user_preferences"):
        op.create_table(
            "user_preferences",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("user_public_id", sa.String(length=36), nullable=False),
        sa.Column("preferences", sa.JSON(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["user_public_id"], ["users.public_id"]),
        sa.UniqueConstraint("user_public_id", name="uq_user_preferences_user"),
        )

    if not _table_exists("model_versions"):
        op.create_table(
            "model_versions",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("version", sa.String(length=80), nullable=False),
        sa.Column("model_name", sa.String(length=80), nullable=False),
        sa.Column("metadata_json", sa.JSON(), nullable=False),
        sa.Column("active", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("version", name="uq_model_versions_version"),
        )
    if not _index_exists("ix_model_versions_active", "model_versions"):
        op.create_index("ix_model_versions_active", "model_versions", ["active"])

    # The earlier quality migration used nullable columns so legacy rows could
    # be upgraded. All rows have explicit values now; enforce the invariant
    # for PostgreSQL and SQLite alike.
    op.execute("UPDATE market_quotes SET unit = COALESCE(unit, 'unknown'), market = COALESCE(market, 'unknown'), freshness_status = COALESCE(freshness_status, 'UNVERIFIED'), data_quality_status = COALESCE(data_quality_status, 'UNVERIFIED')")
    op.execute("UPDATE market_candles SET unit = COALESCE(unit, 'unknown'), market = COALESCE(market, 'unknown'), freshness_status = COALESCE(freshness_status, 'UNVERIFIED'), data_quality_status = COALESCE(data_quality_status, 'UNVERIFIED'), is_complete = COALESCE(is_complete, 1)")
    with op.batch_alter_table("market_quotes") as batch:
        for column in ("unit", "market", "freshness_status", "data_quality_status"):
            batch.alter_column(column, nullable=False, existing_nullable=True)
    with op.batch_alter_table("market_candles") as batch:
        for column in ("unit", "market", "freshness_status", "data_quality_status", "is_complete"):
            batch.alter_column(column, nullable=False, existing_nullable=True)


def downgrade() -> None:
    op.drop_index("ix_model_versions_active", table_name="model_versions")
    op.drop_table("model_versions")
    op.drop_table("user_preferences")
    op.drop_index("ix_watchlists_symbol", table_name="watchlists")
    op.drop_index("ix_watchlists_user_public_id", table_name="watchlists")
    op.drop_table("watchlists")
    op.drop_table("market_assets")

    for table, columns in reversed(tuple(_numeric_columns().items())):
        with op.batch_alter_table(table) as batch:
            for column in columns:
                batch.alter_column(column, type_=sa.Float(), existing_type=sa.Numeric(38, 18))
