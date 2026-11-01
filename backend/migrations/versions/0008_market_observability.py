"""persist sanitized market provider telemetry

Revision ID: 0008_market_observability
Revises: 0007_forecast_validation
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = "0008_market_observability"
down_revision: Union[str, None] = "0007_forecast_validation"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, None] = None


def upgrade() -> None:
    op.create_table(
        "market_provider_metrics",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("provider", sa.String(length=40), nullable=False),
        sa.Column("operation", sa.String(length=32), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("latency_ms", sa.Integer(), nullable=True),
        sa.Column("error_kind", sa.String(length=32), nullable=True),
        sa.Column("fallback_used", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("observed_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_market_provider_metrics_observed", "market_provider_metrics", ["observed_at"])
    op.create_index("ix_market_provider_metrics_provider", "market_provider_metrics", ["provider"])


def downgrade() -> None:
    op.drop_index("ix_market_provider_metrics_provider", table_name="market_provider_metrics")
    op.drop_index("ix_market_provider_metrics_observed", table_name="market_provider_metrics")
    op.drop_table("market_provider_metrics")
