from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
required = [
    ROOT / "frontend" / "pubspec.yaml",
    ROOT / "frontend" / "lib" / "core" / "backend_api_client.dart",
    ROOT / "backend" / "app" / "main.py",
    ROOT / "backend" / "tests" / "test_health.py",
    ROOT / "docs" / "ARCHITECTURE.md",
    ROOT / "docs" / "API_CONTRACT.md",
    ROOT / "docs" / "ROADMAP.md",
]
missing = [str(path.relative_to(ROOT)) for path in required if not path.exists()]
if missing:
    print("Missing Phase 1 files:", *missing, sep="\n- ")
    raise SystemExit(1)

result = subprocess.run(
    [sys.executable, "-m", "pytest", "-q"],
    cwd=ROOT / "backend",
    env={**__import__("os").environ, "PYTHONPATH": "."},
)
raise SystemExit(result.returncode)
