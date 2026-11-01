# Continuing GoldBrain

GoldBrain is a preserved, unfinished financial-intelligence research project. Start from the current integrated source at repository root. The source creator reports roughly seven months of work; this is a personal development account, not a claim about the duration of recorded Git history.

## 1. Reproduce the current baseline

Read [SETUP.md](SETUP.md), [CURRENT_STATUS.md](CURRENT_STATUS.md), [VERIFICATION.md](VERIFICATION.md) and [VERSION_MAP.md](VERSION_MAP.md). Use a fresh local database and independently configured service credentials. Restore the optional audio pack if desired. Run backend tests and Flutter analysis/tests before changing functionality. Pin the checked-in dependency manifests/lockfile for the first reproduction.

## 2. Separate existing research from the planned product

The backend has feature extraction, an ensemble research forecast, chronological backtests, forecast/evaluation evidence and paper-trading APIs. The planned Phase 6 live/self-feedback predictor is unfinished; the assistant's latest-forecast tool explicitly returns unavailable. Automated real-money Wallex execution and the proposed allocation of a user-selected portion of funds were product ambitions, not implemented features. The current exchange adapter is a mock contract.

Do not infer validated prediction accuracy, profitability, risk limits or executable trading from an attractive dashboard, mock contract or roadmap checkbox. A future strategy needs its own reproducible evaluation and paper-trading evidence before anyone can assess it.

## 3. Resolve the known engineering boundaries

1. Verify providers' units, timestamps, allowed usage, historical coverage and availability using your own configuration. Preserve provenance and unavailable/stale states.
2. Decide the design and evidence requirements for Phase 6 before implementing feedback/recalibration. Preserve immutable evaluation records and chronological splits.
3. Complete the portfolio UI against the existing paper-trading API if that is your chosen next feature. Keep real-money execution disabled until independently designed and reviewed.
4. Harden deployment separately: process supervision, shared rate limiting, TLS/proxy configuration, secret management, backups and recovery. The local launcher is not a production supervisor.
5. Review the older Android scaffold as reference. Port it deliberately to the current frontend; it is not a drop-in current release. Verify web compatibility independently.
6. Revisit unfinished billing, optional settings and model/provider configuration without changing the historical record into a false completion report.

## 4. Navigate original records

`PROJECT_BRIEF.md`, `PROGRESS.md`, `DECISIONS.md` and `docs/PHASE*_REPORT.md` are preserved development records. The eight-phase brief describes intended work, including work never completed. Early README/handoff documents predate later authentication, news and provider changes. Dated provider prices, quotas and reachability observations are historical evidence, not current purchase recommendations.

The October 18 no-VPN report is partial: about 15 accepted minutes before the route changed. It is not a completed 25-minute benchmark. OpenRouter completion/global-metals issues and an AvalAI trial were unresolved at that checkpoint.

## 5. Contribute with clear evidence

Fork the repository, identify the exact snapshot and propose one concrete change with relevant tests. Keep both co-creators credited. Do not commit real credentials, account data, private databases, personal signing keys or third-party media without the appropriate rights. Read the published license/asset terms first. The original authors do not promise active maintenance or review timelines.
