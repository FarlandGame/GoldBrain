"""Email verification and recovery challenges, preserving legacy accounts.

Revision ID: 0010_phase3_email_auth
Revises: 0009_phase5_backend_core
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "0010_phase3_email_auth"
down_revision: Union[str, None] = "0009_phase5_backend_core"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Existing users retain their real verification status and access. Only
    # new registrations require verification; suspended users stay suspended.
    with op.batch_alter_table("users") as batch:
        batch.add_column(sa.Column("email_verification_required", sa.Boolean(), nullable=False, server_default=sa.false()))
    with op.batch_alter_table("account_tokens") as batch:
        batch.add_column(sa.Column("challenge_id", sa.String(36), nullable=True))
        batch.add_column(sa.Column("attempt_count", sa.Integer(), nullable=False, server_default="0"))
        batch.add_column(sa.Column("sent_at", sa.DateTime(timezone=True), nullable=True))
    # Legacy debug reset tokens are no longer accepted by the public API.
    # Preserve audit rows while invalidating any old unused tokens before the
    # new uniqueness rule, including populated installations with duplicates.
    op.execute(sa.text("UPDATE account_tokens SET used_at = CURRENT_TIMESTAMP WHERE used_at IS NULL"))
    with op.batch_alter_table("account_tokens") as batch:
        predicate = sa.text("used_at IS NULL AND purpose IN ('email_verification', 'password_reset')")
        batch.create_index(
            "uq_account_token_pending_code", ["user_public_id", "purpose"], unique=True,
            sqlite_where=predicate, postgresql_where=predicate,
        )


def downgrade() -> None:
    with op.batch_alter_table("account_tokens") as batch:
        batch.drop_index("uq_account_token_pending_code")
        batch.drop_column("sent_at")
        batch.drop_column("attempt_count")
        batch.drop_column("challenge_id")
    with op.batch_alter_table("users") as batch:
        batch.drop_column("email_verification_required")
