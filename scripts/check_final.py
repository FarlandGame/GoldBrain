from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
required = [
    "frontend/pubspec.yaml",
    "frontend/lib/core/backend_api_client.dart",
    "backend/app/main.py",
    "backend/app/services/forecasting.py",
    "backend/app/services/auth.py",
    "backend/app/services/paper_trading.py",
    "backend/migrations/versions/0003_phase3_private_beta.py",
    "docs/TEAM_HANDOFF.md",
    "docs/SECURITY.md",
    "docs/PHASE1_REPORT.md",
    "docs/PHASE2_REPORT.md",
    "docs/PHASE3_REPORT.md",
]
missing = [item for item in required if not (ROOT / item).exists()]
if missing:
    print("Missing final files:", *missing, sep="\n- ")
    raise SystemExit(1)

env = {**os.environ, "PYTHONPATH": ".", "GOLDBRAIN_ENVIRONMENT": "test"}
commands = [
    ([sys.executable, "-m", "compileall", "-q", "app", "tests"], ROOT / "backend"),
    ([sys.executable, "-m", "pytest", "-q"], ROOT / "backend"),
]
for command, cwd in commands:
    result = subprocess.run(command, cwd=cwd, env=env)
    if result.returncode:
        raise SystemExit(result.returncode)
print("GoldBrain final checks passed.")
