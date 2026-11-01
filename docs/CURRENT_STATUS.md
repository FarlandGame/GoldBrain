# Current status: preserved source, not a completed trading product

| Area | Evidence in current source | Boundary / unfinished work |
|---|---|---|
| UI | Flutter client,11 themes,8 existing languages,charts/settings/watchlists/About/audio controls | Portfolio UI and some settings unfinished; native/network paths need their own tests |
| Market data | FastAPI provider gateway,history/candles,quality/freshness/provenance,overview persistence,worker | Live access,rights,units/freshness/history depend on independently configured providers |
| Forecast research | Features,ensemble-v2.1,chronological evaluation/backtesting,immutable evidence | Planned Phase6 live/self-feedback predictor is not complete; assistant reports it unavailable |
| Trading | User-scoped paper-trading APIs and mock exchange capability contract | No implemented automatic real-money Wallex execution or user-funded budget allocator |
| Accounts | Email verification/reset,Argon2,JWT/refresh rotation,session revocation | SMTP not bundled; production hardening/shared limiting/full MFA need work |
| News / AI | RSS ingestion,optional translation/summaries,bounded read-only assistant | Actual provider/model access is not guaranteed; no arbitrary trading/account actions |
| Country pulse | Six-country evidence paths and explicit missing-data handling | Public endpoint integrations are not production data contracts |
| Billing | Entitlement/plan interface | No complete paid checkout/payment gateway |
| Platforms | Current Windows/web scaffolds; old separate Android scaffold | No fresh verified Android/web release or cross-platform support guarantee |

## Why it was paused

Bardiya says the project began as a way to learn programming with AI assistance, online resources and experimentation. His intended product included real-time and longer-term market prediction and automatic trading using only a portion of a user's Wallex funds chosen by that user. He describes roughly seven months of effort and says he stopped because the full vision needed substantial infrastructure and spending and carried considerable complexity and financial risk. This explanation is the creator's account, not an independent finding that the idea is impossible.

## Credits and source identity

Latest code and records identify Bardiya Alizadeh (Kabir / Farland_game) and twin brother Armiya Alizadeh (Kabir / ArmiyaFbix) as equal co-creators. The current frontend metadata says1.0.1+2; backend app metadata says0.3.0-private-beta. These component versions do not certify a completed public product. The dated preservation tag identifies this handoff independently of those historical version strings.

Existing in-app languages are English,Persian,Japanese,Russian,Simplified Chinese,Arabic,Turkish and French. The portfolio's18 documentation languages are separate; no new Arabic documentation edition was added and original language support was not removed.
