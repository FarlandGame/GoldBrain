$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Backend = Join-Path $Root 'backend'
$Frontend = Join-Path $Root 'frontend'
$State = Join-Path $Root '.goldbrain'
New-Item -ItemType Directory -Force -Path $State | Out-Null

if (-not (Test-Path (Join-Path $Backend '.venv\Scripts\python.exe'))) {
  Write-Host 'Creating backend virtual environment...'
  python -m venv (Join-Path $Backend '.venv')
  & (Join-Path $Backend '.venv\Scripts\python.exe') -m pip install -r (Join-Path $Backend 'requirements-dev.txt')
}
if (-not (Test-Path (Join-Path $Backend '.env'))) {
  Copy-Item (Join-Path $Backend '.env.example') (Join-Path $Backend '.env')
}

$python = Join-Path $Backend '.venv\Scripts\python.exe'
Push-Location $Backend
try {
  & $python -m alembic upgrade head
  if ($LASTEXITCODE -ne 0) { throw 'Database migration failed. GoldBrain was not started.' }
} finally { Pop-Location }
$backendProcess = Start-Process -FilePath $python -ArgumentList '-m','uvicorn','app.main:app','--reload','--host','127.0.0.1','--port','8000' -WorkingDirectory $Backend -WindowStyle Hidden -PassThru
$backendProcess.Id | Set-Content (Join-Path $State 'backend.pid')
$workerProcess = Start-Process -FilePath $python -ArgumentList '-m','app.jobs.run_private_beta_worker' -WorkingDirectory $Backend -WindowStyle Hidden -PassThru
$workerProcess.Id | Set-Content (Join-Path $State 'market-worker.pid')

Push-Location $Frontend
try { flutter pub get } finally { Pop-Location }
$flutterProcess = Start-Process -FilePath 'flutter.bat' -ArgumentList 'run','-d','windows' -WorkingDirectory $Frontend -PassThru
$flutterProcess.Id | Set-Content (Join-Path $State 'frontend.pid')

Write-Host 'GoldBrain started.' -ForegroundColor Green
Write-Host 'Backend: http://127.0.0.1:8000/docs'
Write-Host 'Private-beta market worker: collecting every 60 seconds'
Write-Host 'Frontend: Windows desktop app'
