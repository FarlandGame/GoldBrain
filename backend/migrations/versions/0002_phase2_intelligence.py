"""phase 2 intelligence private alpha

Revision ID: 0002_phase2
Revises: 0001_phase1
Create Date: 2026-09-08
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "0002_phase2"
down_revision: Union[str, None] = "0001_phase1"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    with op.batch_alter_table("forecast_records") as batch:
        batch.alter_column("forecast_id", type_=sa.String(length=96))
        batch.add_column(sa.Column("timeframe", sa.String(length=12), nullable=False, server_default="1h"))
        batch.add_column(sa.Column("probability_up", sa.Float(), nullable=False, server_default="0.5"))
        batch.add_column(sa.Column("data_quality", sa.Integer(), nullable=False, server_default="0"))
        batch.add_column(sa.Column("feature_version", sa.String(length=40), nullable=False, server_default="price-features-v2"))
        batch.add_column(sa.Column("evidence_fingerprint", sa.String(length=80), nullable=False, server_default="legacy"))
        batch.add_column(sa.Column("calibration_status", sa.String(length=24), nullable=False, server_default="provisional"))
        batch.create_index("ix_forecast_records_horizon", ["horizon"])
        batch.create_index("ix_forecast_records_evidence_fingerprint", ["evidence_fingerprint"])

    op.create_table(
        "market_candles",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("symbol", sa.String(length=24), nullable=False),
        sa.Column("timeframe", sa.String(length=12), nullable=False),
        sa.Column("currency", sa.String(length=12), nullable=False),
        sa.Column("provider", sa.String(length=40), nullable=False),
        sa.Column("upstream_source", sa.String(length=160), nullable=True),
        sa.Column("opened_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("closed_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("open", sa.Float(), nullable=False),
        sa.Column("high", sa.Float(), nullable=False),
        sa.Column("low", sa.Float(), nullable=False),
        sa.Column("close", sa.Float(), nullable=False),
        sa.Column("volume", sa.Float(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("symbol", "timeframe", "provider", "opened_at", name="uq_market_candle_source_time"),
    )
    op.create_index("ix_market_candles_symbol", "market_candles", ["symbol"])
    op.create_index("ix_market_candles_timeframe", "market_candles", ["timeframe"])
    op.create_index("ix_market_candles_opened_at", "market_candles", ["opened_at"])
    op.create_index("ix_market_candles_symbol_tf_time", "market_candles", ["symbol", "timeframe", "opened_at"])

    op.create_table(
        "news_articles",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("article_id", sa.String(length=80), nullable=False),
        sa.Column("title", sa.String(length=1000), nullable=False),
        sa.Column("summary", sa.Text(), nullable=False),
        sa.Column("source", sa.String(length=120), nullable=False),
        sa.Column("category", sa.String(length=80), nullable=False),
        sa.Column("language", sa.String(length=20), nullable=False),
        sa.Column("url", sa.String(length=1200), nullable=False),
        sa.Column("published_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("fetched_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_news_articles_article_id", "news_articles", ["article_id"], unique=True)
    op.create_index("ix_news_articles_source", "news_articles", ["source"])
    op.create_index("ix_news_articles_published_at", "news_articles", ["published_at"])
    op.create_index("ix_news_published_source", "news_articles", ["published_at", "source"])

    op.create_table(
        "forecast_evaluations",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("forecast_id", sa.String(length=96), nullable=False),
        sa.Column("symbol", sa.String(length=24), nullable=False),
        sa.Column("horizon", sa.String(length=16), nullable=False),
        sa.Column("target_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("actual_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("actual_price", sa.Float(), nullable=False),
        sa.Column("absolute_error", sa.Float(), nullable=False),
        sa.Column("absolute_percentage_error", sa.Float(), nullable=False),
        sa.Column("direction_hit", sa.Boolean(), nullable=False),
        sa.Column("interval_hit", sa.Boolean(), nullable=False),
        sa.Column("evaluated_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_forecast_evaluations_forecast_id", "forecast_evaluations", ["forecast_id"], unique=True)
    op.create_index("ix_forecast_evaluations_symbol", "forecast_evaluations", ["symbol"])
    op.create_index("ix_forecast_evaluations_horizon", "forecast_evaluations", ["horizon"])
    op.create_index("ix_forecast_eval_target", "forecast_evaluations", ["symbol", "target_at"])

    op.create_table(
        "paper_accounts",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("account_key", sa.String(length=64), nullable=False),
        sa.Column("name", sa.String(length=80), nullable=False),
        sa.Column("base_currency", sa.String(length=12), nullable=False),
        sa.Column("initial_balance", sa.Float(), nullable=False),
        sa.Column("cash_balance", sa.Float(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_paper_accounts_account_key", "paper_accounts", ["account_key"], unique=True)

    op.create_table(
        "paper_positions",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("account_key", sa.String(length=64), nullable=False),
        sa.Column("symbol", sa.String(length=24), nullable=False),
        sa.Column("quantity", sa.Float(), nullable=False),
        sa.Column("average_entry_price", sa.Float(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("account_key", "symbol", name="uq_paper_position_account_symbol"),
    )
    op.create_index("ix_paper_positions_account_key", "paper_positions", ["account_key"])
    op.create_index("ix_paper_positions_symbol", "paper_positions", ["symbol"])

    op.create_table(
        "paper_trades",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("trade_id", sa.String(length=96), nullable=False),
        sa.Column("account_key", sa.String(length=64), nullable=False),
        sa.Column("symbol", sa.String(length=24), nullable=False),
        sa.Column("side", sa.String(length=8), nullable=False),
        sa.Column("quantity", sa.Float(), nullable=False),
        sa.Column("price", sa.Float(), nullable=False),
        sa.Column("notional", sa.Float(), nullable=False),
        sa.Column("fee", sa.Float(), nullable=False),
        sa.Column("realized_pnl", sa.Float(), nullable=False),
        sa.Column("reason", sa.String(length=240), nullable=True),
        sa.Column("forecast_id", sa.String(length=96), nullable=True),
        sa.Column("executed_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_paper_trades_trade_id", "paper_trades", ["trade_id"], unique=True)
    op.create_index("ix_paper_trades_account_key", "paper_trades", ["account_key"])
    op.create_index("ix_paper_trades_symbol", "paper_trades", ["symbol"])
    op.create_index("ix_paper_trades_executed_at", "paper_trades", ["executed_at"])
    op.create_index("ix_paper_trade_account_time", "paper_trades", ["account_key", "executed_at"])


def downgrade() -> None:
    op.drop_table("paper_trades")
    op.drop_table("paper_positions")
    op.drop_table("paper_accounts")
    op.drop_table("forecast_evaluations")
    op.drop_table("news_articles")
    op.drop_table("market_candles")
    with op.batch_alter_table("forecast_records") as batch:
        batch.drop_index("ix_forecast_records_evidence_fingerprint")
        batch.drop_index("ix_forecast_records_horizon")
        batch.drop_column("calibration_status")
        batch.drop_column("evidence_fingerprint")
        batch.drop_column("feature_version")
        batch.drop_column("data_quality")
        batch.drop_column("probability_up")
        batch.drop_column("timeframe")
        batch.alter_column("forecast_id", type_=sa.String(length=80))
