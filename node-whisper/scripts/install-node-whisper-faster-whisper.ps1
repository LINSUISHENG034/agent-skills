param(
    [string]$RuntimeDir = "E:\Projects\node-whisper-runtime",
    [string]$PythonVersion = "3.12"
)

$ErrorActionPreference = "Stop"

function Require-Command {
    param([string]$Command)
    if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $Command"
    }
}

Require-Command "uv"
Require-Command "ffmpeg"

$runtimeDirResolved = [System.IO.Path]::GetFullPath($RuntimeDir)
$venvDir = Join-Path $runtimeDirResolved ".venv"
$pythonExe = Join-Path $venvDir "Scripts\python.exe"
New-Item -ItemType Directory -Force -Path $runtimeDirResolved | Out-Null
$binDir = Join-Path $runtimeDirResolved "bin"
New-Item -ItemType Directory -Force -Path $binDir | Out-Null

Write-Host "Runtime dir: $runtimeDirResolved"
if (-not (Test-Path $pythonExe)) {
    Write-Host "Creating venv with uv (Python $PythonVersion)..."
    & uv venv $venvDir --python $PythonVersion
} else {
    Write-Host "Reusing existing venv: $venvDir"
}

Write-Host "Installing faster-whisper..."
& uv pip install --python $pythonExe --upgrade faster-whisper

Write-Host "Install complete"
Write-Host "Venv python: $pythonExe"
& $pythonExe --version
