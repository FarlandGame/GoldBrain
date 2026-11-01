"""phase 1 foundation

Revision ID: 0001_phase1
Revises:
Create Date: 2026-09-08
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "0001_phase1"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "market_quotes",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("symbol", sa.String(length=24), nullable=False),
        sa.Column("price", sa.Float(), nullable=False),
        sa.Column("currency", sa.String(length=12), nullable=False),
        sa.Column("provider", sa.String(length=32), nullable=False),
        sa.Column("upstream_source", sa.String(length=120), nullable=True),
        sa.Column("observed_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_market_quotes_symbol", "market_quotes", ["symbol"])
    op.create_index("ix_market_quotes_observed_at", "market_quotes", ["observed_at"])
    op.create_index("ix_market_quotes_symbol_observed", "market_quotes", ["symbol", "observed_at"])

    op.create_table(
        "forecast_records",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("forecast_id", sa.String(length=80), nullable=False),
        sa.Column("symbol", sa.String(length=24), nullable=False),
        sa.Column("horizon", sa.String(length=16), nullable=False),
        sa.Column("direction", sa.String(length=16), nullable=False),
        sa.Column("anchor_price", sa.Float(), nullable=False),
        sa.Column("point_estimate", sa.Float(), nullable=False),
        sa.Column("lower_bound", sa.Float(), nullable=False),
        sa.Column("upper_bound", sa.Float(), nullable=False),
        sa.Column("confidence_score", sa.Integer(), nullable=False),
        sa.Column("model_version", sa.String(length=80), nullable=False),
        sa.Column("generated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("target_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_forecast_records_forecast_id", "forecast_records", ["forecast_id"], unique=True)
    op.create_index("ix_forecast_records_symbol", "forecast_records", ["symbol"])
    op.create_index("ix_forecast_records_generated_at", "forecast_records", ["generated_at"])
    op.create_index("ix_forecast_records_target_at", "forecast_records", ["target_at"])
    op.create_index("ix_forecast_symbol_target", "forecast_records", ["symbol", "target_at"])


def downgrade() -> None:
    op.drop_table("forecast_records")
    op.drop_table("market_quotes")
