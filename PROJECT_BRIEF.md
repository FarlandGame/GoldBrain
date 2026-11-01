# GoldBrain — Feature Extension Brief (Flutter App)

This document is the single source of truth for this project. It is long and detailed on purpose: every requirement below should be treated as a real specification, not a suggestion. If something is ambiguous, ask before guessing.

---

## 0. How to Work Through This Document

- Re-read this entire file (`PROJECT_BRIEF.md`) at the start of every work session, even if you think you remember it. Do not rely on chat/conversation memory alone — it is not reliable across long sessions.
- Read `PROGRESS.md` before starting any phase to see what has already been done, what decisions were made, and what is still open.
- Work on exactly **one phase at a time**, strictly in numeric order (Phase 1 → Phase 8). Never start work on a later phase "while you're at it," even if it seems related.
- Every phase ends with a **stop-and-report** — see Section 1.4. Do not continue automatically.
- Every phase must satisfy the **Global Definition of Done** in Section 2, in addition to its own phase-specific acceptance criteria.
- If a requirement conflicts with something already in the codebase, stop and ask instead of silently choosing one side.

---

## 1. Execution Protocol

### 1.1 Session Start Checklist
At the start of every session:
1. Read `PROJECT_BRIEF.md` fully.
2. Read `PROGRESS.md` fully.
3. State in one short paragraph: which phase is currently active, what was done last, and what you are about to do next. Wait for confirmation only if anything is unclear — otherwise proceed.

### 1.2 File/Folder Convention
- `PROJECT_BRIEF.md` — this file. Read-only for you; only the human updates it.
- `PROGRESS.md` — append-only log you maintain. Each entry must include: date, phase, what was built, files changed/added, any third-party service configured, any decision made and why, and any known limitation or TODO left behind.
- `DECISIONS.md` — create this file the first time you need to make a non-trivial technical choice (e.g., picking a package, a data model shape, a naming convention). Log the decision and a one-line reason, so future sessions don't relitigate it.

### 1.3 Working Rules (apply to every phase)
- **Never redesign, restyle, or rebuild the app's existing UI, theme, colors, typography, or animations.** Every new screen/widget must visually match the current design system exactly — same widget library usage, same spacing scale, same color tokens, same animation curves/durations already used elsewhere in the app. If you're not sure what the existing pattern is for something, find and copy the closest existing example in the codebase rather than inventing a new one.
- Never introduce a new state-management approach, folder structure convention, or architecture pattern different from what the project already uses. Match the existing conventions.
- Test every change locally and confirm it works before committing. Commit and push to GitHub **per phase**, not all at once at the end — one clean commit (or a small number of logical commits) per phase, with a clear commit message referencing the phase number.
- Never commit secrets, API keys, or credentials to the repository. Use environment variables / secure local config that is git-ignored. Call this out explicitly in your phase report if a new secret needs to be set up.
- **Total budget constraint: all paid third-party services/APIs combined, across every phase, must stay within approximately 20–30 million Toman.** Before subscribing to or integrating any paid service in any phase, present the cost (monthly and/or annual) and get explicit approval first. Prefer the cheapest option that still meets the phase's reliability/accuracy requirements. Track a running total of committed monthly cost in `PROGRESS.md`.

### 1.4 Stop-and-Report Format
When a phase (or sub-stage, for Phase 7) is fully built, tested locally, and working, stop. Do not proceed to the next phase automatically. Report using exactly this structure:

```
✅ Phase [N] complete: [one-line summary of what now works]

Files changed/added:
- path/to/file — [what changed]
- ...

Services/APIs configured (if any):
- [service name] — [cost] — [what it's used for]

Known limitations / left for later:
- ...

Definition of Done checklist: [confirm each item from Section 2, one line each — pass/fail]

Ready for Phase [N+1] — waiting for your go-ahead.
```

Only start the next phase after the human explicitly approves (e.g., "go ahead", "برو مرحله بعد", "approved").

---

## 2. Global Definition of Done (applies to every phase)

A phase is not "done" until ALL of the following are true:

1. **Functional** — the feature works as specified, including the edge cases listed in that phase's section.
2. **Visually consistent** — matches existing theme/typography/spacing/animation style; no new colors, fonts, or component styles introduced without an existing precedent in the app.
3. **No regressions** — every other existing tab/feature still works exactly as before. Explicitly re-check the tabs adjacent to whatever you touched.
4. **Error states handled** — no unhandled exceptions shown to the user; network failures, empty data, and invalid input all show a reasonable in-app message consistent with how errors are shown elsewhere in the app (if the app has no existing error-UI convention, propose one and flag it for approval before building others).
5. **Performance** — no feature introduces a noticeable UI freeze/jank on the main thread; long-running work (network calls, heavy computation) happens off the main isolate/thread where the existing app already does this, and inline otherwise with a loading indicator.
6. **Multi-currency correctness** (for any phase touching prices) — verified working in both Toman and USD display modes, with charts and numeric displays updating consistently.
7. **Security** — no credentials, API keys, or user secrets logged to console, sent to any LLM prompt, or committed to git.
8. **Tested locally** — actually run the app and manually verify the feature, not just "should work" from reading the code.
9. **PROGRESS.md updated** and pushed alongside the code changes.
10. **Stop-and-report given**, per Section 1.4.

---

## 3. Glossary (existing in-app Persian terms — use these exact mappings, do not invent new English names for existing features)

| Persian (in-app) | English reference used in this doc |
|---|---|
| داشبورد | Dashboard |
| بازارها | Markets |
| دستیار هوشمند | AI Chat Assistant |
| نبض عصبی بازار | Market Neural Pulse |
| سبد دارایی | Portfolio |
| اخبار | News |
| خلاصه هوش مصنوعی | AI Summary |
| تنظیمات | Settings |
| طلای ۱۸ عیار | 18k Gold |
| اونس جهانی طلا | Global Gold Ounce |

If you find additional existing Persian labels not listed here, add them to `DECISIONS.md` with their English mapping the first time you touch them, so naming stays consistent across sessions.

---

## PHASE 1 — Market Data & Multi-Currency Support

### 1.A Current State / Problem
Prices and charts for 18k gold, global gold ounce, silver, USD, USDT, and Bitcoin currently rely on free/unofficial sources (Google, free APIs). This causes: stale/delayed values, occasional missing data, inconsistent decimal precision, and unreliable historical data for the 24h/7d/30d charts.

### 1.B Requirements

**Data provider research (deliverable before any code):**
- Identify 2–3 candidate paid data providers covering: 18k gold, global gold ounce (XAU), silver (XAG), USD/IRR, EUR/IRR, USDT, and at least the top 20 cryptocurrencies by market cap (individually priced, not just an index).
- For each candidate, report: update frequency actually offered at the affordable tier (not the enterprise tier), whether it provides OHLC/historical data needed for 24h/7d/30d charts, rate limits, and monthly cost.
- Recommend one primary provider and, if reasonably priced, one fallback provider to switch to automatically if the primary is unreachable (see error handling below).

**Data layer:**
- Build a repository/service layer that abstracts the data source behind an interface (e.g., `PriceRepository`), so swapping providers later doesn't require touching UI code.
- Normalize every asset into one internal model, e.g. conceptually: `{ assetId, displayNameFa, displayNameEn, priceIRR, priceUSD, change24hPercent, lastUpdated }`. Match this to whatever model shape the app's existing price objects already use if one exists — do not create a second, parallel data model.
- Cache the latest successful response in local storage so the dashboard shows the last-known price (clearly marked as "آخرین به‌روزرسانی: [time]") instead of a blank/broken UI if the network call fails.

**Multi-currency support:**
- When the user changes the display currency in Settings (Toman ↔ USD, and any others the app already supports), every price and every chart across the entire app (Dashboard, Markets tab, Portfolio, anywhere prices appear) must recompute using a live, accurate exchange rate — not a cached/stale conversion from app install time.
- The conversion must use the same exchange-rate source consistently everywhere (do not mix "USD/IRR from provider A" in one screen and "from provider B" in another).
- Switching currency must not require an app restart and should complete within roughly 1–2 seconds, showing a brief loading state on affected widgets if needed.

**New assets:**
- Add EUR/IRR as a new trackable price with its own 24h/7d/30d chart, in the same visual style as existing assets.
- Add additional cryptocurrencies (beyond BTC) as new trackable assets, each with the same chart/detail treatment as BTC currently has. Confirm with the human which specific coins to prioritize if the provider's coverage requires picking a subset.

### 1.C Edge Cases & Error Handling
- Provider API down/timeout → fall back to cached last-known value + a visible "stale data" indicator; if a fallback provider was set up, try it before falling back to cache.
- Provider returns a price that differs from the previous value by an implausible amount (e.g., >20% in under a minute) → do not display it as-is without at least logging a warning to `PROGRESS.md`/console; this usually indicates a bad API response, not a real market move.
- Currency conversion rate temporarily unavailable → keep showing the last known conversion rate rather than blocking the UI, with the same "stale data" indicator.

### 1.D Acceptance Criteria
- [ ] All 6 original assets plus EUR and the new cryptocurrencies show live prices from the new provider.
- [ ] 24h/7d/30d charts render correctly for every asset, including the newly added ones.
- [ ] Switching currency in Settings updates every price and every chart app-wide, correctly, without restart.
- [ ] Network failure shows cached data + stale indicator, not a blank screen or crash.
- [ ] Actual refresh interval is documented in `PROGRESS.md` (state the real number, e.g. "every 15 seconds", not "real-time").

---

## PHASE 2 — Market Neural Pulse (نبض عصبی بازار)

### 2.A Current State / Problem
An existing dashboard widget with this name is low quality / not very useful.

### 2.B Requirements
- Design and compute a composite "pulse score" per asset (every price tracked in Phase 1) from: recent price momentum, volatility (e.g., standard deviation of recent returns), and available volume or news-sentiment signal.
- Compute this score over three windows: 24h, 7d, 30d, selectable by the user.
- Let the user pick which specific asset's pulse to view (dropdown or similar, matching existing UI patterns).
- Add country-level market pulse for: USA, Germany, Japan, China, France, and Iran — computed from that country's relevant market index and macro/financial news sentiment for the period.
- Document the exact formula/weighting used for the pulse score in `DECISIONS.md` so it is auditable and can be explained to a user later (not a black box, even internally).

### 2.C Edge Cases
- Insufficient historical data for a newly added asset (e.g., a brand-new crypto listing) → show "insufficient data yet" rather than a misleading score.
- News sentiment source temporarily unavailable → fall back to a momentum/volatility-only score and label it as such.

### 2.D Acceptance Criteria
- [ ] Pulse score displays correctly for every tracked asset across all three time windows.
- [ ] Country-level pulse section shows all six listed countries/regions.
- [ ] The scoring formula is written down and explainable in one paragraph.

---

## PHASE 3 — Authentication: Email Verification & Password Recovery

### 3.A Requirements
- On signup: generate a one-time code, email it to the address provided, and block account activation until the correct code is entered (standard OTP pattern). Code should expire after a reasonable window (e.g., 10–15 minutes) and support a "resend code" action with basic rate-limiting (e.g., max 1 resend per 60 seconds) to prevent abuse.
- "Forgot password" flow: user requests reset by email → a reset code/link is emailed → user sets a new password → old sessions/tokens for that account are invalidated.
- Passwords must never be stored or logged in plain text; use whatever hashing the existing backend already relies on, or bcrypt/argon2 if none exists yet.
- Recommend the simplest, ideally free-tier-compatible option for sending transactional emails, compatible with the app's current backend stack. Present the recommendation with cost (if any) before implementing.
- Provide plain-language, step-by-step Persian setup instructions for the human to follow (account creation, DNS/domain verification if required, where to paste the API key).

### 3.B Edge Cases
- Email fails to send (provider outage) → show a clear retry option, don't silently fail.
- User requests multiple reset codes in a row → invalidate older codes when a new one is issued.
- User enters an expired code → clear message that it expired, with a way to request a new one.

### 3.C Acceptance Criteria
- [ ] New signups cannot use the app until email is verified.
- [ ] Forgot-password flow fully works end to end, tested with a real email address.
- [ ] No plaintext password or verification code appears in logs.

---

## PHASE 4 — AI Chat Assistant ("دستیار هوشمند")

### 4.A Current Problems
- Mixed Persian/English text renders with broken text direction and missing font glyphs.
- Settings controls for tone and creativity exist in the UI but have no effect on the assistant's actual output.
- The assistant has no access to any in-app data (prices, charts, predictions) and cannot answer questions about them.

### 4.B Requirements
- Fix bidirectional text rendering: mixed Persian/English messages must display each language segment in its correct direction, with a font (or font fallback chain) that supports both scripts cleanly — no missing glyphs (tofu boxes), no reversed word order.
- Wire the "tone" and "creativity" (temperature) settings to actually influence the LLM call: tone should adjust the system prompt (e.g., formal vs. casual vs. friendly), creativity should adjust the model's temperature/top-p parameter within a sane range (avoid values that make responses incoherent).
- Give the assistant tool-calling access to: current live prices (Phase 1), chart/historical data, and — once Phase 6 exists — the prediction engine's latest output, so it can answer questions like "الان طلا چقدره" or "پیش‌بینی بیت‌کوین چیه" using real in-app data rather than generic/outdated knowledge.
- The assistant must keep functioning normally (in-progress responses continue, chat history is preserved) if the user switches to another tab and comes back — do not reset, cancel, or interrupt an in-progress AI response just because the tab lost focus.
- Recommend a paid LLM API accessible from Iran without a VPN, with Rial payment support. Present at least two real options with approximate cost per usage tier, and provide simple, numbered Persian instructions for signing up and adding the API key to the app.

### 4.C Edge Cases
- LLM API rate-limited or down → show a clear "دستیار موقتاً در دسترس نیست" message, don't crash the chat screen.
- User asks about an asset not tracked by the app → assistant should say it doesn't have data for that asset rather than hallucinating a price.
- Very long conversation history → decide and document a reasonable context-window/history-trimming strategy so cost doesn't grow unbounded.

### 4.D Acceptance Criteria
- [ ] Mixed-language messages render correctly in both directions with no missing characters.
- [ ] Changing tone/creativity in Settings visibly changes assistant behavior.
- [ ] Assistant correctly answers a live price question and a "what does the predictor say" question using real app data.
- [ ] Chat continues uninterrupted across tab switches.

---

## PHASE 5 — News Section

### 5.A Requirements
- Pull news from multiple sources: existing Iranian sources plus additional relevant international financial/crypto outlets.
- Refresh near real-time (define and document the actual polling interval you can sustain given the source APIs used).
- Deduplicate near-identical stories from different sources before display.
- Rank/sort by relevance to the assets tracked in the app (e.g., a Bitcoin regulation story ranks above unrelated general news).
- Ensure the existing "خلاصه هوش مصنوعی" (AI Summary) button uses the improved LLM integration from Phase 4, not the old one.

### 5.B Edge Cases
- A news source is temporarily unreachable → continue showing news from the remaining sources rather than failing the whole feed.
- Duplicate detection false-positive (two genuinely different stories look similar) → prefer under-merging over losing real stories; document the dedup threshold used.

### 5.C Acceptance Criteria
- [ ] News feed shows items from at least one Iranian and one international source simultaneously.
- [ ] Obvious duplicate stories are not shown twice.
- [ ] AI Summary produces a correct, on-topic summary for a real news item.

---

## PHASE 6 — Prediction Engine

Two modes on the Dashboard, accessible via two new, simple, cleaner icons (replace the current two icons for the assistant and predictor — icon redesign only, no layout change).

### 6a. Real-Time / Short-Term Prediction

**Requirements:**
- On demand (user selects an asset and triggers a prediction), the engine pulls: latest relevant news (Phase 5 data), current price/volatility data (Phase 1), and recent chart patterns for that specific asset.
- Combine an LLM-based reasoning step with an actual quantitative signal (e.g., momentum indicators, volatility bands, recent rate of change) — the LLM must not be the sole source of the numeric prediction; it should reason over the quantitative output, not invent numbers independently.
- Output format: direction (up/down), a target price **range** (not a single falsely-precise number), and a confidence score.
- **Confidence score must be derived from the model's actual backtested historical accuracy at this horizon for this asset class — it must not be hardcoded or forced into an 80–99% range.** If backtested accuracy for a given horizon is, say, 55–65%, display that honestly. Store backtest results so the displayed confidence can be justified/audited later.
- Works for any tracked asset (any fiat currency, metal, or crypto in the app).

**Edge cases:**
- Insufficient recent data for a newly added asset → show "not enough history yet for a reliable prediction" instead of guessing.
- News/quant signals conflict strongly → surface this as lower confidence rather than picking one arbitrarily.

### 6b. Long-Term Prediction (Next-Day and 30-Day)

**Requirements:**
- Next-day prediction: a projected price/range for a **specific clock time tomorrow** (e.g., "فردا ساعت ۱۸:۰۰"), with a direction color (green = expected up, red = expected down) and a calibrated confidence score as in 6a.
- 30-day prediction: same structure, but clearly and visibly labeled in the UI as a longer-horizon, inherently more speculative projection — include a short, plain-language note explaining the methodology and its real limitations (e.g., "این پیش‌بینی بلندمدت‌تر و به‌طور ذاتی کمتر قطعی است").
- Both the real-time and long-term predictors must keep running/processing in the background even if the user navigates away to another tab (Dashboard, Assistant, etc.) — do not pause, cancel, or reset an in-progress prediction just because its tab isn't currently visible.

### 6c. Shared Engineering Notes
- Present your proposed model/backtesting approach to the human before building this phase — this is one of the two most important features in the whole app and deserves review before implementation.
- No model, however well engineered, can predict daily financial market moves with near-certainty. Build the most rigorous version realistically possible (multi-signal fusion, real backtesting, honest calibrated uncertainty) rather than one that fakes high confidence to look impressive.

### 6D Acceptance Criteria
- [ ] Real-time prediction works for at least 3 different asset types (a metal, a fiat currency, a crypto) with a visibly reasoned range + confidence.
- [ ] Next-day prediction shows a specific target time, direction color, and confidence.
- [ ] 30-day prediction is clearly labeled as more speculative with a limitations note.
- [ ] Confidence scores are traceable to actual backtest numbers stored somewhere in the codebase/logs, not hardcoded constants.
- [ ] Both prediction modes continue running across tab switches.

### 6E. Self-Improving Feedback Loop (expanded by request)

Goal: the prediction engine must get measurably better over time on its own, without a human manually re-teaching it after every miss.

1. Prediction logging: every prediction is stored with timestamp, asset, predicted value/range, confidence, and the exact news/signals considered at the time.
2. Outcome logging: once the predicted horizon passes, automatically fetch the real price and compute the error (predicted vs. actual).
3. Automated causal post-mortem: for predictions that miss by more than a defined threshold, use the LLM to analyze what happened during that window (e.g., "USD strengthened due to X event, which likely drove gold beyond the predicted range") and store this as a structured, queryable "lesson" (asset, factor, magnitude, date) — not a vague note.
4. Recalibration loop: on a schedule (e.g., weekly), aggregate lessons and error data to adjust the quantitative model's feature weights and confidence calibration, so accuracy claims stay honest and improve over time.
5. Transparency: add a simple "track record" view in the app showing real accuracy over the last N predictions per asset, so I can see actual improvement, not just a claim.

This is an automated feedback/recalibration system grounded in logged data — not a model that rewrites its own architecture or is self-aware. This is the single most important feature in the app and deserves top engineering priority once we reach Phase 6.

This addition is documentation only for now. Do not implement it during Phase 5; the Phase 6 proposal/review and execution gates still apply.

---

## PHASE 7 — Portfolio Tab — Automated Trading (Simulation First, Then Wallex)

### 7.0 Entry Experience
When the user opens the Portfolio tab, it must load with a distinct, polished entry animation matching the app's existing animation library/style — this should feel like the flagship section of the app, not a plain screen. Specify the animation approach (e.g., reuse whatever transition/animation controller pattern the app already uses elsewhere) and get it visually approved before moving on to the trading logic.

Build the trading functionality in **three sub-stages, strictly in order.** Do not skip ahead to a later sub-stage without the human explicitly approving the previous one, even if it looks like it's working.

### 7a. Internal Paper Trading (build first — no external account needed)

**Requirements:**
- Use the app's own real, live price feed (Phase 1) combined with a fake starting balance the user sets themselves (e.g., a simulated $20).
- The automated strategy (using the Phase 6a real-time predictor plus live news/data) makes simulated buy/sell decisions against real live prices — no real money, no real exchange account involved at this stage.
- Log every simulated decision with: timestamp, asset, action (buy/sell/hold), the signal/reasoning behind it, the price at the time, and the resulting hypothetical running P&L.
- Show a performance dashboard: hypothetical balance over time (chart), win rate, max drawdown, and total simulated trades.
- This stage should run for an extended trial period (weeks, not hours/minutes) before the human considers moving to 7b/7c — build the UI so it's easy to check in on this periodically.

### 7b. Optional: Binance Testnet (crypto pairs only)

- For more realistic order-execution testing specifically on crypto pairs, support connecting to Binance's official Testnet (free demo trading environment with fake funds and realistic order-book behavior).
- This only covers crypto assets — gold, USD, and EUR strategies remain validated only through 7a's internal simulation, since no equivalent demo exchange exists for those.

### 7c. Real Trading via Wallex (only after 7a, and 7b if used, show consistent results)

**Requirements:**
- Let the user connect their own Wallex account via Wallex's official API (developers.wallex.ir) using their own credentials/API key.
- Store credentials only in secure local storage; never log them, never send them to the LLM, never commit them to git.
- Show the user's real Wallex balance/holdings once connected.
- Let the user allocate a specific sub-amount of their balance to be managed by the auto-trader (e.g., $20 of $100 available). Default the suggested initial allocation to something small regardless of how well the simulation performed.
- Provide a clear Start/Stop toggle. While "Start" is active, the same strategy validated in 7a/7b trades only within the allocated amount; "Stop" halts all trading immediately and cancels any pending orders.
- **Mandatory safety features (non-negotiable, since this trades real money):**
  - A hard daily loss limit (e.g., auto-stop trading for the day if the allocated amount drops more than a user-configurable X%).
  - A maximum position size per individual trade.
  - A single, always-visible one-tap emergency stop, reachable from the Portfolio tab without extra navigation.
  - A full trade log in the same format as 7a's log, so real performance can be directly compared to the simulated performance that justified moving to real money.
- Like the prediction engine, active real trading must keep running in the background across tab switches — it must not pause simply because the user navigated elsewhere, but the emergency stop must always work instantly regardless of which tab is open.

### 7.D Edge Cases (all sub-stages)
- Wallex API temporarily unreachable while a trade is in progress → do not retry blindly in a way that could double-execute an order; log the failure and surface it to the user.
- Strategy wants to place a trade larger than the allocated amount or the configured max position size → clamp it or skip it, never exceed the configured limits.
- Daily loss limit is hit mid-trade → finish/cancel the current order safely, then halt further new trades for the remainder of the day and notify the user clearly.

### 7.E Acceptance Criteria
- [ ] 7a fully functional: simulated trades execute against real live prices with a visible performance dashboard and full log.
- [ ] (If used) 7b connects to Binance Testnet and executes real (fake-money) orders successfully.
- [ ] 7c only begins after explicit human approval, referencing 7a/7b results.
- [ ] All four mandatory safety features are implemented and manually tested (deliberately trigger the daily loss limit and the emergency stop to confirm they work).
- [ ] Entry animation matches existing app style and is visually approved.

---

## PHASE 8 — About Us Section

### 8.A Requirements
Update the "About Us" / "درباره ما" page to credit:
- **Bardia Alizadeh ("Kabir")** — brand name **farland_game** — co-creator, 50% contribution.
- **Armia Alizadeh ("Kabir")** — Bardia's brother — co-creator, 50% contribution.

These are the only two project creators. Credit their work equally (50/50); neither is a helper or subordinate contributor. Creator links must use the exact human-approved list, grouped with Persian labels, and open externally. Preserve the existing About UI, animations and layout style.

Match the existing visual style of the About page (or the closest existing static-content page if no About page exists yet) rather than introducing a new layout pattern.

### 8.B Acceptance Criteria
- [ ] Only Bardia and Armia appear as co-creators, each with a 50% contribution; Bardia's farland_game brand is credited.
- [ ] Page styling matches the rest of the app.

---

## Appendix A — Running Budget Tracker Template
Maintain this table in `PROGRESS.md`, updating it after every phase that adds a paid service:

| Phase | Service | Purpose | Monthly Cost | Approved? |
|---|---|---|---|---|
| 1 | [TBD] | Price data | [TBD] | [ ] |
| 3 | [TBD] | Transactional email | [TBD] | [ ] |
| 4 | [TBD] | LLM API | [TBD] | [ ] |

Running total must stay within ~20–30 million Toman (one-time budget, not necessarily monthly recurring — clarify with the human whether the budget is a one-time cap or must cover recurring costs too, and record the answer in `DECISIONS.md`).

## Appendix B — What NOT to Do
- Do not rewrite or "clean up" unrelated parts of the codebase while working on a phase.
- Do not upgrade Flutter, major dependencies, or change the app's package manager/build tooling without explicit approval — this is a stability risk unrelated to the requested features.
- Do not introduce a new backend/database technology without approval if the app already has one in use.
- Do not skip the stop-and-report step "to save time" — the human needs to check in at every phase boundary.
