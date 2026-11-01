"""add provenance, quality and immutable raw-data metadata

Revision ID: 0006_market_data_quality
Revises: 0005_forecast_explanations
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "0006_market_data_quality"
down_revision: Union[str, None] = "0005_forecast_explanations"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    for table in ("market_quotes", "market_candles"):
        with op.batch_alter_table(table) as batch:
            batch.add_column(sa.Column("unit", sa.String(length=24), nullable=True))
            batch.add_column(sa.Column("market", sa.String(length=24), nullable=True))
            batch.add_column(sa.Column("provider_timestamp", sa.DateTime(timezone=True), nullable=True))
            batch.add_column(sa.Column("received_at", sa.DateTime(timezone=True), nullable=True))
            batch.add_column(sa.Column("latency_ms", sa.Integer(), nullable=True))
            batch.add_column(sa.Column("freshness_status", sa.String(length=16), nullable=True))
            batch.add_column(sa.Column("data_quality_status", sa.String(length=16), nullable=True))
            batch.add_column(sa.Column("quality_flags", sa.JSON(), nullable=True))
    with op.batch_alter_table("market_quotes") as batch:
        batch.add_column(sa.Column("fallback_from", sa.String(length=32), nullable=True))
        batch.add_column(sa.Column("provider_spread_percent", sa.Float(), nullable=True))
        batch.add_column(sa.Column("content_fingerprint", sa.String(length=96), nullable=True))
        batch.create_unique_constraint("uq_market_quote_content_fingerprint", ["content_fingerprint"])
    with op.batch_alter_table("market_candles") as batch:
        batch.add_column(sa.Column("source_tick_ids", sa.JSON(), nullable=True))
        batch.add_column(sa.Column("is_complete", sa.Boolean(), nullable=True))
        batch.add_column(sa.Column("content_fingerprint", sa.String(length=96), nullable=True))
        batch.create_unique_constraint("uq_market_candle_content_fingerprint", ["content_fingerprint"])
    # Legacy rows remain readable but are explicitly marked unverified.  NULL
    # completeness must not make historical data disappear after the upgrade.
    op.execute("UPDATE market_quotes SET unit = COALESCE(unit, 'unknown'), market = COALESCE(market, 'unknown'), freshness_status = COALESCE(freshness_status, 'UNVERIFIED'), data_quality_status = COALESCE(data_quality_status, 'UNVERIFIED')")
    op.execute("UPDATE market_candles SET unit = COALESCE(unit, 'unknown'), market = COALESCE(market, 'unknown'), freshness_status = COALESCE(freshness_status, 'UNVERIFIED'), data_quality_status = COALESCE(data_quality_status, 'UNVERIFIED'), is_complete = COALESCE(is_complete, 1)")


def downgrade() -> None:
    with op.batch_alter_table("market_candles") as batch:
        batch.drop_constraint("uq_market_candle_content_fingerprint", type_="unique")
        for name in ("content_fingerprint", "is_complete", "source_tick_ids", "quality_flags", "data_quality_status", "freshness_status", "latency_ms", "received_at", "provider_timestamp", "market", "unit"):
            batch.drop_column(name)
    with op.batch_alter_table("market_quotes") as batch:
        batch.drop_constraint("uq_market_quote_content_fingerprint", type_="unique")
        for name in ("content_fingerprint", "provider_spread_percent", "fallback_from", "quality_flags", "data_quality_status", "freshness_status", "latency_ms", "received_at", "provider_timestamp", "market", "unit"):
            batch.drop_column(name)
