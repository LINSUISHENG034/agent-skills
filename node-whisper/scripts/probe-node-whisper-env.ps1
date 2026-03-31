$ErrorActionPreference = "Continue"

function Test-CommandExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command
    )

    $cmd = Get-Command $Command -ErrorAction SilentlyContinue
    return $null -ne $cmd
}

function Get-CommandVersionText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,
        [string[]]$Args = @("--version")
    )

    try {
        $output = & $Command @Args 2>&1 | Select-Object -First 5
        return ($output -join "`n").Trim()
    } catch {
        return "ERROR: $($_.Exception.Message)"
    }
}

function Get-NvidiaSummary {
    if (-not (Test-CommandExists "nvidia-smi")) {
        return @{
            available = $false
            detail = "nvidia-smi not found"
        }
    }

    try {
        $gpuName = & nvidia-smi --query-gpu=name --format=csv,noheader 2>$null | Select-Object -First 1
        $driverVersion = & nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>$null | Select-Object -First 1
        return @{
            available = $true
            gpuName = ($gpuName | Out-String).Trim()
            driverVersion = ($driverVersion | Out-String).Trim()
        }
    } catch {
        return @{
            available = $false
            detail = "nvidia-smi exists but query failed: $($_.Exception.Message)"
        }
    }
}

function Get-UvPythonSummary {
    if (-not (Test-CommandExists "uv")) {
        return @{
            available = $false
            detail = "uv not found"
        }
    }

    try {
        $pythonList = & uv python list 2>&1 | Select-Object -First 20
        return @{
            available = $true
            pythonList = ($pythonList -join "`n").Trim()
        }
    } catch {
        return @{
            available = $true
            pythonList = "ERROR: $($_.Exception.Message)"
        }
    }
}

$report = [ordered]@{
    timestamp = (Get-Date).ToString("s")
    computerName = $env:COMPUTERNAME
    user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    powershellVersion = $PSVersionTable.PSVersion.ToString()
    commands = [ordered]@{
        uv = [ordered]@{
            available = (Test-CommandExists "uv")
            version = $(if (Test-CommandExists "uv") { Get-CommandVersionText -Command "uv" } else { "missing" })
        }
        python = [ordered]@{
            available = (Test-CommandExists "python")
            version = $(if (Test-CommandExists "python") { Get-CommandVersionText -Command "python" } else { "missing" })
        }
        py = [ordered]@{
            available = (Test-CommandExists "py")
            version = $(if (Test-CommandExists "py") { Get-CommandVersionText -Command "py" } else { "missing" })
        }
        ffmpeg = [ordered]@{
            available = (Test-CommandExists "ffmpeg")
            version = $(if (Test-CommandExists "ffmpeg") { Get-CommandVersionText -Command "ffmpeg" -Args @("-version") } else { "missing" })
        }
        whisper = [ordered]@{
            available = (Test-CommandExists "whisper")
            version = $(if (Test-CommandExists "whisper") { Get-CommandVersionText -Command "whisper" -Args @("--help") } else { "missing" })
        }
        nvidiaSmi = Get-NvidiaSummary
    }
    uvPython = Get-UvPythonSummary
}

$json = $report | ConvertTo-Json -Depth 6
Write-Output $json
