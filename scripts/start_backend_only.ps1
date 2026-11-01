[CmdletBinding()]
param(
    [string]$BackendDirectory = '',
    [ValidateRange(1, 65535)][int]$Port = 8000
)

$ErrorActionPreference = 'Stop'
if (-not $BackendDirectory) {
    $BackendDirectory = Join-Path (Split-Path -Parent $PSScriptRoot) 'backend'
}
$BackendDirectory = [System.IO.Path]::GetFullPath($BackendDirectory)
$BackendPython = Join-Path $BackendDirectory '.venv\Scripts\python.exe'
$RuntimeState = Join-Path (Split-Path -Parent $BackendDirectory) '.goldbrain'

Add-Type -AssemblyName System.Net.Http
$HttpHandler = New-Object System.Net.Http.HttpClientHandler
$HttpHandler.UseProxy = $false
$HttpClient = New-Object System.Net.Http.HttpClient($HttpHandler)
$HttpClient.Timeout = [TimeSpan]::FromSeconds(2)

function Test-GoldBrainReady {
    foreach ($Route in @('health', 'ready')) {
        $Response = $null
        try {
            $Response = $HttpClient.GetAsync("http://127.0.0.1:$Port/api/v1/$Route").GetAwaiter().GetResult()
            if (-not $Response.IsSuccessStatusCode) { return $false }
            $Payload = $Response.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
            if ($Payload.service -notlike 'GoldBrain*') { return $false }
            if (($Route -eq 'health' -and $Payload.status -ne 'ok') -or
                ($Route -eq 'ready' -and $Payload.status -ne 'ready')) { return $false }
        } catch { return $false }
        finally { if ($Response) { $Response.Dispose() } }
    }
    return $true
}

$StartupLock = New-Object System.Threading.Mutex($false, 'Local\GoldBrainBackendStartup')
$LockAcquired = $false
try {
    try { $LockAcquired = $StartupLock.WaitOne(30000) }
    catch [System.Threading.AbandonedMutexException] { $LockAcquired = $true }
    if (-not $LockAcquired) { throw 'Another GoldBrain start is in progress. Please try again shortly.' }

    if (-not (Test-GoldBrainReady)) {
        if (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) {
            throw "Port $Port is busy, but GoldBrain is not ready. Do not start a second server."
        }
        if (-not (Test-Path -LiteralPath $BackendPython -PathType Leaf)) {
            throw 'The Backend Python environment is missing. Complete the initial project setup first.'
        }
        if (-not (Test-Path -LiteralPath (Join-Path $BackendDirectory '.env') -PathType Leaf)) {
            throw 'backend/.env is missing. Configure the Backend first; existing settings are never replaced.'
        }
        Write-Host 'Starting GoldBrain Backend...'
        Push-Location $BackendDirectory
        try {
            & $BackendPython -m alembic upgrade head
            if ($LASTEXITCODE -ne 0) { throw 'Database migration failed; Backend was not started.' }
        } finally { Pop-Location }

        # Windows management starts the server independently of this console.
        $Startup = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ ShowWindow = [uint16]0 }
        $Launch = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
            CommandLine = ('"' + $BackendPython + '" -m uvicorn app.main:app --host 127.0.0.1 --port ' + $Port + ' --no-access-log')
            CurrentDirectory = $BackendDirectory
            ProcessStartupInformation = $Startup
        }
        if ($Launch.ReturnValue -ne 0) { throw 'Windows could not start the Backend.' }
        $Wait = [System.Diagnostics.Stopwatch]::StartNew()
        while (-not (Test-GoldBrainReady)) {
            if ($Wait.Elapsed.TotalSeconds -ge 45) { throw 'Backend did not become ready. Check its configuration and retry.' }
            Start-Sleep -Milliseconds 500
        }
    }

    $Listener = Get-NetTCPConnection -LocalPort $Port -State Listen | Select-Object -First 1
    New-Item -ItemType Directory -Path $RuntimeState -Force | Out-Null
    $Listener.OwningProcess | Set-Content -LiteralPath (Join-Path $RuntimeState 'backend.pid') -Encoding ascii
    Write-Host "GoldBrain Backend is ready: http://127.0.0.1:$Port" -ForegroundColor Green
    Write-Host 'You can close this window and use GoldBrain. Run Start-Backend.bat again after restarting Windows.'
} finally {
    if ($LockAcquired) { $StartupLock.ReleaseMutex() }
    $StartupLock.Dispose()
    $HttpClient.Dispose()
    $HttpHandler.Dispose()
}
