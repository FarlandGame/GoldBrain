# Known issues for the next developer

## Fresh GitHub CI: one CoinGecko fallback test failure

The preserved original Backend CI ran on a fresh Ubuntu/Python3.12.15 GitHub runner on2026-11-01. Dependency installation, Ruff and compilation completed, but pytest reported **212 passed,1 failed,13 warnings**. The failure was:

`tests/test_phase1_providers.py::test_coingecko_fallback_keeps_usd_market_and_source_visible`

At line373, looking up `quotes["XMR"]` raised `KeyError: 'XMR'`. This contrasts with213 passing tests in the existing local Windows/Python3.14.3 environment. Do not label the fresh environment or the full backend suite universally passing.

Evidence: [original GitHub run41329253595](https://github.com/FarlandGame/GoldBrain/actions/runs/41329253595), source commit`bbae0e9c4335c392f657588642d951010e0fd1af`. Application and test source were preserved rather than altered to hide the failure.

### A candidate mechanism, not a proven CI root cause

Static review found that `backend/app/services/coingecko.py` initializes `_last_quote_attempt` to`0.0`. Its initial cache/cooldown guard returns cached results whenever `time.monotonic() - _last_quote_attempt` is below the configured minimum quote interval (60 seconds by default). If the initial monotonic value is below60, the first fetch can therefore return an empty cache. The market-data service then has no XMR fallback quote and the test's direct dictionary lookup fails.

This is a reachable condition visible in source, but the failed run did not record the monotonic value or mock-request counts. It is **a candidate to reproduce and investigate, not a confirmed diagnosis of that run**. Capture those observations in an isolated test before choosing a repair; also compare environment/dependency and test-isolation effects.

## Other continuation boundaries

See [current status](CURRENT_STATUS.md) and [continuation guide](CONTINUING.md) for the unfinished Phase6 predictor, mock real-money exchange contract, provider/deployment gaps, incomplete portfolio/payment UI and older Android scaffold. The interrupted Flutter suite is separately documented in [verification](VERIFICATION.md);352 passed/9 skipped is partial progress, not full completion.
