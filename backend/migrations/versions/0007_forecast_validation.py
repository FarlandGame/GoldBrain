"""make forecast/evaluation evidence immutable and exactly-once

Revision ID: 0007_forecast_validation
Revises: 0006_market_data_quality
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = "0007_forecast_validation"
down_revision: Union[str, None] = "0006_market_data_quality"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, None] = None


def upgrade() -> None:
    with op.batch_alter_table("forecast_records") as batch:
        batch.add_column(sa.Column("input_key", sa.String(length=128), nullable=True))
        batch.add_column(sa.Column("evidence_manifest", sa.JSON(), nullable=True))
        batch.create_unique_constraint("uq_forecast_input_key", ["input_key"])
    with op.batch_alter_table("forecast_evaluations") as batch:
        batch.add_column(sa.Column("actual_provider", sa.String(length=40), nullable=True))
        batch.add_column(sa.Column("actual_currency", sa.String(length=12), nullable=True))
        batch.add_column(sa.Column("actual_unit", sa.String(length=24), nullable=True))
        batch.add_column(sa.Column("actual_quality_status", sa.String(length=16), nullable=True))
        batch.add_column(sa.Column("actual_evidence_id", sa.Integer(), nullable=True))
        batch.add_column(sa.Column("actual_evidence_timestamp", sa.DateTime(timezone=True), nullable=True))
        batch.add_column(sa.Column("confidence_score", sa.Integer(), nullable=True))
        batch.add_column(sa.Column("probability_up", sa.Float(), nullable=True))


def downgrade() -> None:
    with op.batch_alter_table("forecast_evaluations") as batch:
        for name in ("probability_up", "confidence_score", "actual_evidence_timestamp", "actual_evidence_id", "actual_quality_status", "actual_unit", "actual_currency", "actual_provider"):
            batch.drop_column(name)
    with op.batch_alter_table("forecast_records") as batch:
        batch.drop_constraint("uq_forecast_input_key", type_="unique")
        batch.drop_column("evidence_manifest")
        batch.drop_column("input_key")
