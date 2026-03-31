param(
    [Parameter(Mandatory = $true)]
    [string]$RuntimeDir,
    [Parameter(Mandatory = $true)]
    [string]$JobId
)

$ErrorActionPreference = "Stop"

function To-DrivePath {
    param([string]$Path)
    return ($Path -replace "\\", "/")
}

$runtimeDirResolved = [System.IO.Path]::GetFullPath($RuntimeDir)
$binDir = Join-Path $runtimeDirResolved "bin"
$jobDir = Join-Path $runtimeDirResolved ("jobs\" + $JobId)
$inputDir = Join-Path $jobDir "input"
$outputDir = Join-Path $jobDir "output"
$logDir = Join-Path $jobDir "logs"

New-Item -ItemType Directory -Force -Path $runtimeDirResolved | Out-Null
New-Item -ItemType Directory -Force -Path $binDir | Out-Null
New-Item -ItemType Directory -Force -Path $inputDir | Out-Null
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$payload = [ordered]@{
    ok = $true
    stage = "prepare"
    runtimeDir = To-DrivePath $runtimeDirResolved
    binDir = To-DrivePath $binDir
    jobDir = To-DrivePath $jobDir
    inputDir = To-DrivePath $inputDir
    outputDir = To-DrivePath $outputDir
    logDir = To-DrivePath $logDir
    inputPath = To-DrivePath (Join-Path $inputDir "input")
    textOut = To-DrivePath (Join-Path $outputDir "transcript.txt")
    jsonOut = To-DrivePath (Join-Path $outputDir "transcript.json")
    logOut = To-DrivePath (Join-Path $logDir "run.log")
}

$payload | ConvertTo-Json -Depth 4
