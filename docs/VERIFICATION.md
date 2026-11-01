# Preservation verification — 2026-11-01

Checks ran against a separate publication copy, leaving the installed/original project unchanged. Live provider and SMTP values were removed from child-process environments. Ordinary service tests use their source mocks/fixtures; no real account signup, email or financial order was performed.

| Check | Actual result |
|---|---|
| Backend pytest | **213 passed**,13 warnings,78.87 seconds |
| Backend Ruff | Passed |
| Flutter static analysis | No issues,51.6 seconds |
| Flutter unit/widget suite | **Interrupted at the user's request to reduce RAM**; last logged progress352 passed,9 optional skipped. The complete suite is NOT reported as passed |
| Fresh SQLite migrations | Passed through0010_phase3_email_auth on an isolated new database |
| Source preservation | 333 original files unchanged, including all staged application/test source; original README preserved separately and ignore rules adjusted for publication |
| Curated-source secret scan | 852 current/historical files checked;0 matches for configured private values/high-confidence key patterns. This is a scoped scan, not a claim that all possible secrets in the universe can be detected |

Backend execution used the existing Python3.14.3 development environment. The preserved Docker/CI setup targets Python3.12; a clean Python3.12 dependency installation was not reproduced locally. Flutter3.44.6/Dart3.12.2 was used. Dependency resolution used the local offline cache; source manifests/lockfiles were retained.

No fresh Windows release build,Android/web build,native audio smoke run,PostgreSQL E2E,live provider/model completion or SMTP delivery was certified by this publication. No real-money trading or prediction-performance validation is claimed. Older numerical test results in original progress notes remain dated historical records.

Machine-readable results: [verification.json](../verification.json). Private test logs remain in the owner's disposable preparation folder; no personal runtime state or keys are distributed. The interrupted Flutter suite was not restarted after the user reported memory pressure.
