$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..\backend')
if (-not (Test-Path '.venv')) { python -m venv .venv }
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
if (-not (Test-Path '.env')) { Copy-Item .env.example .env }
.\.venv\Scripts\python.exe -m alembic upgrade head
.\.venv\Scripts\python.exe -m pytest -q
.\.venv\Scripts\python.exe -m uvicorn app.main:app --reload
