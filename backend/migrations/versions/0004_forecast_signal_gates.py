"""persist forecast signal gates

Revision ID: 0004_signal_gates
Revises: 0003_phase3
Create Date: 2026-09-08
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "0004_signal_gates"
down_revision: Union[str, None] = "0003_phase3"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    with op.batch_alter_table("forecast_records") as batch:
        batch.add_column(sa.Column("signal", sa.String(length=16), nullable=False, server_default="no_trade"))
        batch.add_column(sa.Column("signal_quality", sa.String(length=16), nullable=False, server_default="unverified"))
        batch.add_column(sa.Column("trade_allowed", sa.Boolean(), nullable=False, server_default=sa.false()))


def downgrade() -> None:
    with op.batch_alter_table("forecast_records") as batch:
        batch.drop_column("trade_allowed")
        batch.drop_column("signal_quality")
        batch.drop_column("signal")
