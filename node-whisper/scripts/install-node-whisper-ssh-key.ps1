param(
    [string]$PublicKey = "",
    [string]$EnvFile = ""
)

$ErrorActionPreference = "Stop"
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

function Get-DotenvValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    if (-not (Test-Path $Path)) {
        return $null
    }

    foreach ($line in Get-Content $Path -ErrorAction Stop) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith("#")) {
            continue
        }

        $separatorIndex = $trimmed.IndexOf("=")
        if ($separatorIndex -lt 1) {
            continue
        }

        $candidateKey = $trimmed.Substring(0, $separatorIndex).Trim()
        if ($candidateKey -ne $Key) {
            continue
        }

        $value = $trimmed.Substring($separatorIndex + 1).Trim()
        if (
            ($value.StartsWith('"') -and $value.EndsWith('"')) -or
            ($value.StartsWith("'") -and $value.EndsWith("'"))
        ) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        return $value
    }

    return $null
}

if (-not $EnvFile) {
    $EnvFile = Join-Path (Split-Path $PSScriptRoot -Parent) ".env"
}

if (-not $PublicKey) {
    $PublicKey = $env:NODE_WHISPER_SSH_PUBLIC_KEY
}

if (-not $PublicKey) {
    $PublicKey = Get-DotenvValue -Path $EnvFile -Key "NODE_WHISPER_SSH_PUBLIC_KEY"
}

if (-not $PublicKey) {
    throw "Missing SSH public key. Set NODE_WHISPER_SSH_PUBLIC_KEY in the environment or in the skill-root .env, or pass -PublicKey explicitly."
}

function Add-PublicKeyLine {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    if (Test-Path $Path) {
        $existing = Get-Content $Path -ErrorAction SilentlyContinue
        if ($existing -contains $Key) {
            Write-Host "Public key already exists in $Path"
        } else {
            Add-Content -Path $Path -Value $Key -Encoding ascii
            Write-Host "Public key appended to $Path"
        }
    } else {
        Set-Content -Path $Path -Value $Key -Encoding ascii
        Write-Host "Created $Path"
    }
}

if ($isAdmin) {
    $authorizedKeys = Join-Path $env:ProgramData "ssh\administrators_authorized_keys"
    Add-PublicKeyLine -Path $authorizedKeys -Key $publicKey

    icacls $authorizedKeys /inheritance:r | Out-Null
    icacls $authorizedKeys /grant "Administrators:F" | Out-Null
    icacls $authorizedKeys /grant "SYSTEM:F" | Out-Null
} else {
    $sshDir = Join-Path $HOME ".ssh"
    $authorizedKeys = Join-Path $sshDir "authorized_keys"
    New-Item -ItemType Directory -Force -Path $sshDir | Out-Null

    Add-PublicKeyLine -Path $authorizedKeys -Key $publicKey

    icacls $sshDir /inheritance:r | Out-Null
    icacls $sshDir /grant "${env:USERNAME}:(OI)(CI)F" | Out-Null
    icacls $authorizedKeys /inheritance:r | Out-Null
    icacls $authorizedKeys /grant "${env:USERNAME}:F" | Out-Null
}

if (Get-Service sshd -ErrorAction SilentlyContinue) {
    Restart-Service sshd
}

Write-Host "SSH key installation complete"
Write-Host "authorized_keys path: $authorizedKeys"
Write-Host "admin mode: $isAdmin"
if (Get-Service sshd -ErrorAction SilentlyContinue) {
    Get-Service sshd
}
