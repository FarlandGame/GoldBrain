"""phase 3 private beta foundation

Revision ID: 0003_phase3
Revises: 0002_phase2
Create Date: 2026-09-08
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "0003_phase3"
down_revision: Union[str, None] = "0002_phase2"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("public_id", sa.String(length=36), nullable=False),
        sa.Column("email", sa.String(length=320), nullable=False),
        sa.Column("display_name", sa.String(length=100), nullable=False),
        sa.Column("password_hash", sa.String(length=500), nullable=False),
        sa.Column("role", sa.String(length=24), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False),
        sa.Column("email_verified", sa.Boolean(), nullable=False),
        sa.Column("mfa_enabled", sa.Boolean(), nullable=False),
        sa.Column("mfa_secret_encrypted", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_users_public_id", "users", ["public_id"], unique=True)
    op.create_index("ix_users_email", "users", ["email"], unique=True)

    with op.batch_alter_table("paper_accounts") as batch:
        batch.add_column(sa.Column("owner_user_public_id", sa.String(length=36), nullable=True))
        batch.create_index("ix_paper_accounts_owner_user_public_id", ["owner_user_public_id"])
        batch.create_foreign_key(
            "fk_paper_accounts_owner_user",
            "users",
            ["owner_user_public_id"],
            ["public_id"],
        )

    op.create_table(
        "user_sessions",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("session_id", sa.String(length=36), nullable=False),
        sa.Column("user_public_id", sa.String(length=36), nullable=False),
        sa.Column("refresh_token_hash", sa.String(length=64), nullable=False),
        sa.Column("device_name", sa.String(length=160), nullable=False),
        sa.Column("client_fingerprint", sa.String(length=64), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("last_seen_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["user_public_id"], ["users.public_id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_user_sessions_session_id", "user_sessions", ["session_id"], unique=True)
    op.create_index("ix_user_sessions_user_public_id", "user_sessions", ["user_public_id"])
    op.create_index("ix_user_sessions_refresh_token_hash", "user_sessions", ["refresh_token_hash"], unique=True)
    op.create_index("ix_user_sessions_expires_at", "user_sessions", ["expires_at"])
    op.create_index("ix_user_session_user_active", "user_sessions", ["user_public_id", "revoked_at"])

    op.create_table(
        "account_tokens",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("token_hash", sa.String(length=64), nullable=False),
        sa.Column("user_public_id", sa.String(length=36), nullable=False),
        sa.Column("purpose", sa.String(length=32), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("used_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["user_public_id"], ["users.public_id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_account_tokens_token_hash", "account_tokens", ["token_hash"], unique=True)
    op.create_index("ix_account_tokens_user_public_id", "account_tokens", ["user_public_id"])
    op.create_index("ix_account_tokens_expires_at", "account_tokens", ["expires_at"])
    op.create_index("ix_account_token_user_purpose", "account_tokens", ["user_public_id", "purpose"])

    op.create_table(
        "audit_logs",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("user_public_id", sa.String(length=36), nullable=True),
        sa.Column("action", sa.String(length=80), nullable=False),
        sa.Column("resource", sa.String(length=120), nullable=False),
        sa.Column("outcome", sa.String(length=24), nullable=False),
        sa.Column("metadata_json", sa.String(length=2000), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_audit_logs_user_public_id", "audit_logs", ["user_public_id"])
    op.create_index("ix_audit_logs_action", "audit_logs", ["action"])
    op.create_index("ix_audit_logs_created_at", "audit_logs", ["created_at"])
    op.create_index("ix_audit_user_time", "audit_logs", ["user_public_id", "created_at"])

    op.create_table(
        "alert_rules",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("alert_id", sa.String(length=36), nullable=False),
        sa.Column("user_public_id", sa.String(length=36), nullable=False),
        sa.Column("symbol", sa.String(length=24), nullable=False),
        sa.Column("condition", sa.String(length=16), nullable=False),
        sa.Column("threshold", sa.Float(), nullable=False),
        sa.Column("enabled", sa.Boolean(), nullable=False),
        sa.Column("last_triggered_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["user_public_id"], ["users.public_id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_alert_rules_alert_id", "alert_rules", ["alert_id"], unique=True)
    op.create_index("ix_alert_rules_user_public_id", "alert_rules", ["user_public_id"])
    op.create_index("ix_alert_rules_symbol", "alert_rules", ["symbol"])
    op.create_index("ix_alert_user_enabled", "alert_rules", ["user_public_id", "enabled"])

    op.create_table(
        "entitlements",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("user_public_id", sa.String(length=36), nullable=False),
        sa.Column("plan", sa.String(length=24), nullable=False),
        sa.Column("status", sa.String(length=24), nullable=False),
        sa.Column("starts_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("ends_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("source", sa.String(length=40), nullable=False),
        sa.ForeignKeyConstraint(["user_public_id"], ["users.public_id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_entitlements_user_public_id", "entitlements", ["user_public_id"], unique=True)


def downgrade() -> None:
    with op.batch_alter_table("paper_accounts") as batch:
        batch.drop_constraint("fk_paper_accounts_owner_user", type_="foreignkey")
        batch.drop_index("ix_paper_accounts_owner_user_public_id")
        batch.drop_column("owner_user_public_id")
    op.drop_table("entitlements")
    op.drop_table("alert_rules")
    op.drop_table("audit_logs")
    op.drop_table("account_tokens")
    op.drop_table("user_sessions")
    op.drop_table("users")
