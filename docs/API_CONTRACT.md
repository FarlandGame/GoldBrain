# GoldBrain API Contract — Private Beta Foundation

Local base URL: `http://127.0.0.1:8000`

Shared market/intelligence endpoints accept either:

- owner header: `X-GoldBrain-Key`, or
- user header: `Authorization: Bearer <access-token>`.

User-specific routes require a Bearer token. Public auth/health endpoints do not.

## System

- `GET /api/v1/health`
- `GET /api/v1/ready` — includes database readiness
- `GET /api/v1/capabilities`

## Auth

- `POST /api/v1/auth/register`
- `POST /api/v1/auth/login`
- `POST /api/v1/auth/refresh`
- `GET /api/v1/auth/me`
- `GET /api/v1/auth/sessions`
- `DELETE /api/v1/auth/sessions/{session_id}`
- `POST /api/v1/auth/logout`
- `POST /api/v1/auth/logout-all`
- `POST /api/v1/auth/email-verification/request`
- `POST /api/v1/auth/email-verification/confirm`
- `POST /api/v1/auth/password-reset/request`
- `POST /api/v1/auth/password-reset/confirm`

Access tokens are short-lived. Refresh tokens are rotated and only their SHA-256 hashes are stored server-side.
Passwords use Argon2id.

### Phase 3 email verification and recovery

Registration accepts the existing `email`, `password`, `display_name` and
`device_name` fields. It returns HTTP 201 with
`{email, verification_required: true, expires_in: 900, resend_after: 60}`.
This is a pending registration, **not** an authenticated session: there are
no access or refresh tokens until verification succeeds. New accounts cannot
log in while pending. Existing accounts are preserved by the migration's
`email_verification_required=false` legacy default; their emails are not
falsely marked verified.

`POST /auth/email-verification/request` takes `{email}` and returns an
accepted response with email and the expiry/resend timings. The matching
`/confirm` takes `{email, code, new_password, device_name}` (the existing optional
client fingerprint header is retained) and returns the normal `AuthTokens`
session. The email owner chooses the password at verification; a password
submitted by an earlier pending registration is never silently retained.
Verification changes the hash and revokes any previous sessions atomically
with consuming the code. An administratively suspended account cannot verify
or reset itself into an active account.
`POST /auth/password-reset/request` takes `{email}` and returns
`{accepted: true, expires_in: 900, resend_after: 60}` without disclosing a code
or a debug token. Its `/confirm` takes `{email, code, new_password}` and
returns HTTP 204. Password reset invalidates all account sessions and
remaining account challenges; old access tokens are rejected on personal
**and shared** Bearer-protected routes, and old refresh tokens cannot renew.

Challenges expire after 15 minutes, are single-use, and use purpose-separated
secret-keyed hashes rather than plaintext OTP storage. A new successful issue
invalidates earlier codes of the same purpose. Resend cooldown is 60 seconds;
wrong-code attempts are bounded. Real email delivery is configured only in
Backend environment variables. Missing SMTP configuration or delivery failure
returns a sanitized failure and retry path, never a pretend delivery success.
Unknown addresses receive a non-enumerating accepted recovery response.
Auth errors use `detail: {code, message}`; clients retain HTTP status handling
and inspect the stable code for verification, expiry, invalid-code, cooldown
and delivery-failure UI. Validation responses omit submitted passwords/codes.
See [Persian SMTP setup](EMAIL_SETUP_FA.md) for developer configuration and
the separate real-email acceptance checklist.

## Market / history

- `GET /api/v1/market/assets`
- `GET /api/v1/market/quotes?symbols=XAU&symbols=BTC`
- `GET /api/v1/market/{asset}/quote` — single-asset quote alias for Flutter clients
- `GET /api/v1/market/gold18-context` — fresh Gold18 / USDT / XAU implied-price and premium analysis
- `GET /api/v1/market/status` — fresh/stale/missing state for the three private-beta assets
- `GET /api/v1/market/overview` — one persisted, read-only payload for the private-beta dashboard: latest quote, data freshness and latest forecast for Gold18, USDT and BTC
- `GET /api/v1/market/observability?window_minutes=60` — sanitized provider success/error rate, latency, fallback count, market age, last successful update, historical gaps and stale-data count
- `GET /api/v1/history/candles?symbol=BTC&timeframe=1h`
- `GET /api/v1/market/{asset}/candles?timeframe=1h` — single-asset candle alias
- `GET /api/v1/market/{asset}/samples?range=24h` — timestamped domestic price observations for the 24-hour chart (`USD`, `EUR`, `GOLD18`); these are price samples, not OHLC candles
- `POST /api/v1/history/candles` — owner/private ingestion only
- `POST /api/v1/history/aggregate-quotes` — owner/private ingestion only
- `POST /api/v1/history/fetch-wallex` — owner/private BTC/USDT historical-candle ingestion

Current canonical symbols: `USD`, `USDT`, `GOLD18`, `XAU`, `XAG`, `BTC`, `ETH`.

`fetch-wallex` accepts `symbol`, `timeframe` (`1m`, `1h`, `1d`) and
`lookback_hours`; it uses the public Wallex OHLCV endpoint only for BTC and
USDT. Gold18 history continues to be derived from persisted verified quotes
until a licensed historical-gold provider is selected.

Every quote and candle carries `unit`, `market`, `provider_timestamp`,
`received_at`, `latency_ms`, `freshness_status`, `data_quality_status` and
`quality_flags`. `provider_timestamp` is nullable when an upstream snapshot
does not publish one; `received_at` is always the server receipt time. No
consumer may infer currency or unit from a symbol.

For Navasan `usd_sell`, `eur`, and `18ayar`, the provider's own public widget
labels its price column **Toman** and matches the authenticated API values
exactly. Their canonical API currency is `IRT` (Toman); `18ayar` is per gram
of 18K gold. If a future provider response explicitly specifies `IRR`, the
adapter divides that response by ten once at ingestion. The 24-hour sample
response has `symbol`, `range`, and an ordered `samples` array. Each sample
includes `price`, `currency`, `unit`, `market`, `provider`,
`upstream_source`, `provider_timestamp`, `received_at`,
`freshness_status`, `data_quality_status`, and `quality_flags` containing
`price_sample_not_ohlc`. Missing observations are never interpolated. USD
and GOLD18 come from Navasan's `/dailyCurrency/` price-update history.
Navasan returns HTTP 422 for EUR at that endpoint; EUR samples come only
from timestamped `/latest/` observations persisted by GoldBrain. EUR's
24-hour chart is therefore sparse and may be unavailable until two distinct
observations have been collected. The Navasan free feed is **not real-time**:
its published source update interval is about two hours, while GoldBrain's
development quota guard requests it no more often than once per eight hours.
A particular sample's source age does not prove the feed is streaming.

The provider chain is explicit: Wallex is primary for BTC/USDT snapshots and
history, Nobitex is the independent fallback, and Navasan is the preferred
key-based source for Iranian Gold18/fiat FX when a key and valid response are
available. PersianToolbox is **not** a GOLD18 provider: its documented market
API derives a generic gold-per-gram reference from global tokenized gold and
FX. ZARIX is a reachable experimental aggregator but has no verified source
timestamp for domestic USD/EUR. Neither is eligible as a domestic-price
fallback in the market gateway. Without a valid Navasan response, domestic
GOLD18/USD/EUR quotes are unavailable or explicitly stale last-known Navasan
data. Gold18 historical backfill still requires live Navasan verification.

The private-beta worker collects a live snapshot every 60 seconds by default
and aggregates it into both 1-minute and 1-hour quote-derived candles. It
does not interpolate missing observations. Raw quote fingerprints and candle
source IDs make repeated worker runs idempotent; a duplicate or revised source
candle is rejected rather than overwritten. Gaps are reported through the
observability endpoint. Gold18 forecasts remain unavailable until at least 24
real hourly candles have accumulated from eligible evidence.
Only completed candles are exposed as historical evidence to forecasts,
backtests and forecast evaluation; a currently forming candle is excluded.

## Forecasting / research

- `POST /api/v1/forecast`
- `GET /api/v1/forecast/latest?symbol=BTC&horizon=1h&timeframe=1h` — latest persisted, auditable forecast including reasons, model breakdown and signal gate
- `POST /api/v1/forecast/evaluate` — owner/private evaluation job
- `GET /api/v1/forecast/metrics?symbol=BTC&horizon=1h`
- `POST /api/v1/forecasts` and `GET /api/v1/forecasts/{asset}` — plural aliases
- `GET /api/v1/forecast-performance?symbol=BTC&horizon=1h`
- `POST /api/v1/forecast/backtest` — owner/private research endpoint

Forecast V2 combines a deterministic baseline with a scikit-learn challenger. The challenger only receives material weight when chronological validation supports it. Confidence remains provisional until sufficient independent evaluated forecasts exist.

Every forecast includes `signal`, `signal_quality`, `trade_allowed` and
`decision_reasons`. A provisional forecast fails closed as `no_trade`.
Chronologically validated forecasts may emit `buy`/`sell` with
`signal_quality: paper_only`, but remain ineligible for real-money execution.
They must also meet the minimum 55% directional-accuracy threshold on their
validation slice; otherwise they fail closed as `no_trade`.

Forecast rows are immutable after creation. Each row stores a deterministic
input key and an evidence manifest containing candle IDs, providers, units,
currencies, data timestamps and model version. The unique key makes repeated
worker execution safe. Evaluation selects only the first valid completed
candle at or after the target from the same evidence series; a stale, invalid
or missing target remains pending/expired and is never forced into metrics.
`/forecast/metrics` reports MAE, RMSE, MAPE, directional accuracy, interval
hit rate, Brier score, average confidence, strong-signal accuracy and sample
counts.

## Intelligence

### Phase 2 country market pulse evidence

`GET /api/v1/pulse/countries/{country}?window=24h|7d|30d` accepts `usa`,
`germany`, `japan`, `china`, `france`, or `iran` and the same client access
credentials as other shared market routes. It returns the requested country
and window, `index_symbol`, `index_name`, `currency`, `unit=index_points`,
`index_provider`, `index_source_url`, `index_status` (`available`, `stale`,
`unavailable`), ordered `index_points` (`time`, `close`),
`last_observation_at`, `news_provider`, `news_status` (`available` or
`unavailable`), optional `news_tone`, `news_source_url`, and `checked_at`.
No missing observations are interpolated. A market holiday, inaccessible
provider, or too few points yields no pulse score in Flutter. The five
non-Iranian indices currently use Yahoo Finance's public chart response for
development; it is not a production licensing contract. Iran uses the
TSETMC TEDPIX daily-history endpoint when accessible. Its daily session dates
are normalized to UTC midnight for ordering and do not assert an intraday
provider timestamp. TSETMC is currently unreachable from the development
host, so Iran normally returns `index_status=unavailable` here. Optional
GDELT DOC 2.0 macro/financial news tone is explicitly marked unavailable on
timeout or rate limit; the client then computes an index-only score.

- `GET /api/v1/intelligence/news`
- `POST /api/v1/intelligence/deep-analysis`

The numerical forecast is produced by the forecasting engine. The optional LLM may explain supplied evidence but must not invent forecast numbers.

## Paper Trading

Authenticated-user scoped:

- `POST /api/v1/paper/accounts`
- `POST /api/v1/paper/orders`
- `GET /api/v1/paper/portfolio/me`

Watchlist and preferences are authenticated and persisted in PostgreSQL:

- `GET/POST /api/v1/watchlist`
- `DELETE /api/v1/watchlist/{symbol}`
- `GET/PUT /api/v1/preferences`

This is long-only spot simulation. It is the only executable trading path in the repository.

## Product scaffolding

- `GET /api/v1/entitlements/me`
- `GET /api/v1/alerts`
- `POST /api/v1/alerts`
- `DELETE /api/v1/alerts/{alert_id}`
- `POST /api/v1/alerts/evaluate`
- `GET /api/v1/exchange/capabilities`

Subscription/payment enforcement and real exchange execution are intentionally not enabled yet.

## Phase 5 storage and errors

Migration `0009_phase5_backend_core` adds the `market_assets`, `watchlists`,
`user_preferences` and `model_versions` entities and converts persisted
price, candle, forecast, evaluation, alert and paper-trading values to
PostgreSQL `NUMERIC`. Internal timestamps are UTC. The migration seeds the
three MVP assets (`BTC`, `USDT`, `GOLD18`) and is safe to run from an empty
database with `alembic upgrade head`.

HTTP errors retain the legacy `detail` field and also include a normalized
`error` object with `code`, `message` and optional `details` fields.

## Phase 4 — authenticated assistant

`POST /api/v1/assistant/chat` requires a valid, non-revoked Bearer session.
Guest/owner keys alone do not authorize user chat. Provider keys remain only
in Backend environment; clients cannot supply a system prompt or tool definitions.

```json
{
  "messages": [{"role": "user", "content": "قیمت BTC چقدره؟"}],
  "language": "persian",
  "tone": "concise",
  "temperature": 0.35,
  "market_context": true,
  "display_currency": "IRT"
}
```

Roles: `user`/`assistant`; last message must be user. Languages match the eight
existing Flutter language names. Tone: balanced/concise/detailed. Temperature:
0..1. Request: 1..24 messages, 1..4,000 characters each; execution retains at
most 12 messages/12,000 history characters. At most 6 read-only tool calls and
4 provider completions, including any shared language/style repair; total server deadline
85s, client wait 95s. Response is final JSON (not first-token streaming):
`{text, model, evidence: [{tool, data}], history_trimmed}`. Model is the actual
returned model identifier. Development now selects `qwen/qwen3.8-27b:free`
instead of the variable free router; quota/outage errors remain explicit.
Simple price answers use brief conversational prose in the selected currency.
One bounded fact-preserving repair can correct an obvious report-style answer;
explicit requests for lists/tables/details are respected. Assistant text is
Markdown, rendered by Flutter with the existing palette and paragraph direction.
User text stays literal; model images cannot fetch network or local files.

Tools reuse the catalog, quote and 24h/7d/30d history routes without force
refresh. Evidence retains original source, currency, unit, timestamp, quality
and freshness. Display conversion is separately identified with its sourced
USD/USDT basis and stale/unavailable status; it never rewrites canonical data.
Quote/display/summary evidence includes `currency_name` and `currency_name_fa`:
`IRT` is Toman/تومان, `IRR` is Rial/ریال, `USD` is US dollar and `USDT` is Tether.
These labels do not change the number; a labelled IRR -> IRT conversion divides
by ten once. Model instructions must preserve the supplied label.
When a quote's display conversion is stale, Backend appends a localized disclosure even
if the model omits it. This changes neither the amount nor the exchange rate.
Unsupported assets/insufficient history explicitly return unavailable.
`get_latest_forecast` reports Phase 6 not implemented, with no target/confidence;
this is an honest availability check, not a completed prediction integration.

Safe error codes: `assistant_rate_limited` (429), `assistant_timeout` (504),
`assistant_not_configured`, `assistant_unavailable`, `assistant_tool_limit`,
`assistant_invalid_response`, `assistant_missing_evidence`,
`assistant_wrong_language`, `assistant_free_model_required` (503), and
`assistant_invalid_history` (422). Upstream payloads, credentials and URLs are
never returned as diagnostic messages. No automatic paid fallback/retry.

## Phase 5 — Backend news and evidence-bound AI

`GET /api/v1/intelligence/news?refresh=true` uses the existing client-access
policy. Both refresh and normal reads respect one shared **300-second** source
cadence. Flutter polls every five minutes while Dashboard/News is retained.
Feeds fetch concurrently with a 12s timeout and conditional ETag/Last-Modified
requests when supplied by the publisher. This is polling, not push/instant news.

Response: `{articles, source_errors, fetched_at, from_cache,
polling_interval_seconds}`. Each existing article additionally carries
`fetched_at`, `source_information_url`, `relevant_assets`, `relevance_score`.
`published_at` is the publisher's UTC publication timestamp; `fetched_at` is
the actual last successful retrieval/check, never the current time of a cached
read. A failed source retains its dated stored articles and appears in
`source_errors`; other sources continue. If no usable articles exist, return
503 `news_unavailable`. No simulated news or invented dates. Source URLs are
fixed/allowlisted; arbitrary URLs, HTML scraping, DTD and oversized XML are not
accepted. Existing SQLAlchemy news storage is reused; no migration added.

Sources: existing Tasnim economy and Mehr economy/gold RSS, plus first-party
Cointelegraph and CNBC finance RSS. Ranking counts tracked-asset words/phrases
(headline 4, excerpt 1, generic crypto headline 2, total capped at 16), then
publication time, over the latest seven days / at most 300 stored candidates.
Return at most 60 representatives. Exact canonical URL/title duplicates are
collapsed; near titles require same language, within 48h, at least six distinct
words each, identical numeric tokens and relevant asset sets, token Jaccard
and sequence similarity both **>=0.92**. No cross-language semantic merging;
prefer retaining similar but distinct stories. Original records remain in DB.

`POST /api/v1/intelligence/news/{article_id}/summary`: `{language}` →
`{article_id, language, text, model, source_url, from_cache}`.
`POST /api/v1/intelligence/news/translations`: `{article_ids: [id...], language}`
(1..6 unique stored IDs) → `{translations: [{article_id, language, title,
summary, category}], model, from_cache}`. Eight existing language names.
Six-item client batches split into at most two concurrent three-item model
requests; incomplete/truncated JSON is rejected, never displayed as success.
Both AI routes require a valid verified Bearer session; an owner key alone
cannot authorize them. Unknown IDs: 404; invalid/duplicate IDs: 422.

Clients send IDs/language only. Backend loads publisher headline/excerpt,
instructs the **Phase 4 AssistantService** to summarize/translate only quoted
evidence with no tools, currency conversion, invented facts or forecasts.
Same free-only model guard, 2,000-token output cap, 85s server deadline and 95s
client wait apply. Structured translations validate exact IDs, field lengths
and selected-language script separately from JSON metadata. Summary output
rejects empty/generic short answers. Safe provider errors reuse
`assistant_rate_limited` (429), `assistant_timeout` (504), and sanitized 503
codes, plus `news_invalid_summary` / `news_invalid_translation`. No paid fallback.
Public-result memory cache: 100 bounded entries keyed by action, language,
model and publisher content/date; identical concurrent requests coalesce.
Publisher corrections invalidate the entry; failures are not cached as success.
Flutter retains its existing local translation/summary caches and renders AI
Markdown with the Phase 4 widget. A publisher-text fallback is explicitly
labelled as publisher text, never reported as AI output. Summaries cover the
RSS excerpt, not the full article or paywalled text; attribution/link remain.


## 2026-10-17 — Requested Wallex catalog additions

The existing `/market/assets`, `/market/quotes` and `/market/{asset}/candles` flow now includes **DOT, PAXG, NOT, AVAX, TON, PEPE, ARB**, with native `USDT` quotes from their respective `*USDT` Wallex pairs. The original dated top-20 crypto snapshot remains unchanged; these seven additions are a separate, explicit requested set. Catalog: 32 assets (27 crypto plus USD/EUR/GOLD18/XAU/XAG). Forecast capability remains false for the additions; no trading/model feature is enabled.

PAXG is a crypto token with unit `coin`, not an alias for XAU or an independently verified global gold spot price. The Wallex snapshot does not supply a last-trade timestamp; receiving a new HTTP response alone must not promote it to `LIVE`. Existing `DELAYED` / `provider_timestamp_unavailable` behavior remains. Invalid `lastPrice` (including `-`) is rejected; the catalog's `live_quote` is capability, not a claim that every listed market currently has a valid price. Actual verification found TON quotes and all requested TON histories unavailable; no zero/interpolation/synthetic price is introduced.

The existing UI checks each minute. No WebSocket, paid-provider integration, Navasan plan/configuration change, migration, UI restyle or Phase 6 work is part of this update. XAG's market-screen title now explicitly says **Global Silver Ounce / اونس جهانی نقره**; it is not domestic silver per gram.
