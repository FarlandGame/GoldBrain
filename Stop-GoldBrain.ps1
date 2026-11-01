$ErrorActionPreference = 'SilentlyContinue'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$State = Join-Path $Root '.goldbrain'

Get-Process -Name goldbrain | Stop-Process -Force
foreach ($file in @('backend.pid','frontend.pid','market-worker.pid')) {
  $path = Join-Path $State $file
  if (Test-Path $path) {
    $id = [int](Get-Content $path)
    Stop-Process -Id $id -Force
    Remove-Item $path -Force
  }
}
Get-Process -Name python | Where-Object { $_.Path -like '*GoldBrain-main*backend\.venv*' } | Stop-Process -Force
Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" |
  Where-Object { $_.CommandLine -like '*GoldBrain-main*app.jobs.run_private_beta_worker*' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Write-Host 'GoldBrain stopped.' -ForegroundColor Yellow
