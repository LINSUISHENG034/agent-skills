param(
    [string]$RuntimeDir = "E:\Projects\node-whisper-runtime"
)

$ErrorActionPreference = "Stop"

$runtimeDirResolved = [System.IO.Path]::GetFullPath($RuntimeDir)
$venvDir = Join-Path $runtimeDirResolved ".venv"
$pythonExe = Join-Path $venvDir "Scripts\python.exe"
$scriptPath = Join-Path $runtimeDirResolved "smoke_test_faster_whisper.py"

if (-not (Test-Path $pythonExe)) {
    throw "Missing venv python: $pythonExe"
}

if (-not (Test-Path $scriptPath)) {
    throw "Missing smoke test script: $scriptPath"
}

& $pythonExe $scriptPath
