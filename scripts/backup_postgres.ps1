$ErrorActionPreference = 'Stop'
$Root = Join-Path $PSScriptRoot '..'
Set-Location $Root
New-Item -ItemType Directory -Force -Path 'backups' | Out-Null
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$File = "backups/goldbrain-$Stamp.dump"
docker compose exec -T postgres pg_dump -U goldbrain -d goldbrain -Fc | Set-Content -Encoding Byte $File
Write-Host "Created $File"
