"""persist forecast explanations

Revision ID: 0005_forecast_explanations
Revises: 0004_signal_gates
Create Date: 2026-09-08
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0005_forecast_explanations"
down_revision: Union[str, None] = "0004_signal_gates"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    with op.batch_alter_table("forecast_records") as batch:
        batch.add_column(sa.Column("decision_reasons", sa.JSON(), nullable=True))
        batch.add_column(sa.Column("reasons", sa.JSON(), nullable=True))
        batch.add_column(sa.Column("model_breakdown", sa.JSON(), nullable=True))


def downgrade() -> None:
    with op.batch_alter_table("forecast_records") as batch:
        batch.drop_column("model_breakdown")
        batch.drop_column("reasons")
        batch.drop_column("decision_reasons")
