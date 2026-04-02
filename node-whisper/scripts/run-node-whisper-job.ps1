param(
    [Parameter(Mandatory = $true)]
    [string]$RuntimeDir,
    [Parameter(Mandatory = $true)]
    [string]$JobId,
    [Parameter(Mandatory = $true)]
    [string]$InputPath,
    [string]$Model = "large-v3",
    [string]$Language = "",
    [switch]$WantJson,
    [switch]$Timestamps
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$runtimeDirResolved = [System.IO.Path]::GetFullPath($RuntimeDir)
$venvPython = Join-Path $runtimeDirResolved ".venv\Scripts\python.exe"
$transcriber = Join-Path $runtimeDirResolved "bin\transcribe_faster_whisper.py"
$jobDir = Join-Path $runtimeDirResolved ("jobs\" + $JobId)
$outputDir = Join-Path $jobDir "output"
$textOut = Join-Path $outputDir "transcript.txt"
$jsonOut = Join-Path $outputDir "transcript.json"

if (-not (Test-Path $venvPython)) {
    throw "Missing runtime Python: $venvPython"
}

if (-not (Test-Path $transcriber)) {
    throw "Missing transcriber script: $transcriber"
}

$args = @(
    $transcriber,
    "--audio", $InputPath,
    "--model", $Model,
    "--device", "cuda",
    "--compute-type", "float16",
    "--beam-size", "5",
    "--text-out", $textOut
)

if ($Language) {
    $args += @("--language", $Language)
}

$args += @("--json-out", $jsonOut)

if ($Timestamps) {
    $args += "--timestamps"
}

& $venvPython @args
$pythonExit = $LASTEXITCODE

if (Test-Path $jsonOut) {
    Get-Content -Raw $jsonOut
    exit 0
}

if ($pythonExit -ne 0) {
    exit $pythonExit
}

exit $pythonExit
