<#
.SYNOPSIS
  Wrapper to call Upload-Idgard.ps1 with retries, pulling credentials from Windows Credential Manager.

.PARAMETER CredentialTarget
  The name under which the PSCredential is stored in Windows Credential Manager (default: IdgardApi).

.PARAMETER InputFolder
  Folder containing files to upload. Defaults to 'C:\Users\OliverDetjen\Downloads\Uploads'.

.PARAMETER BaseUrl, BoxId, ParentNodeId, LogFile
  Passed straight through to Upload‑Idgard.ps1.

.PARAMETER MaxRetries
  How many times to retry transient failures (default: 3).

.PARAMETER DelaySeconds
  Seconds to wait between retries (default: 10).

.PARAMETER WhatIf
  Dry‑run mode (no actual upload).

.EXAMPLE
  .\Upload-Idgard-With-Retry.ps1 -CredentialTarget 'IdgardApi' -WhatIf
#>
param (
    [string] $CredentialTarget = 'IdgardApi',
    [string] $InputFolder      = 'C:\Users\OliverDetjen\Downloads\Uploads',
    [string] $BaseUrl          = 'https://my.idgard.de/',
    [string] $BoxId            = '2n42g',
    [string] $ParentNodeId     = 'nbhfvq',
    [string] $LogFile          = "$PSScriptRoot\idgard-upload.log",
    [int]    $MaxRetries       = 3,
    [int]    $DelaySeconds     = 10,
    [switch] $WhatIf
)

function Write-Log {
    param($Message, $Level = 'INFO')
    $ts = (Get-Date).ToString('s')
    Write-Host "[$ts][$Level] $Message"
    "$ts [$Level] $Message" | Out-File -FilePath $LogFile -Append -Encoding UTF8
}

# --- Retrieve credentials from Windows Credential Manager ---
if (-not (Get-Module -ListAvailable CredentialManager)) {
    Write-Log "CredentialManager module not found. Install with: Install-Module CredentialManager" 'ERROR'
    exit 1
}
Import-Module CredentialManager

$storedCred = Get-StoredCredential -Target $CredentialTarget
if (-not $storedCred) {
    Write-Log "No credential found under target '$CredentialTarget'." 'ERROR'
    exit 2
}


# --- Locate the main upload script ---
$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$mainScript = Join-Path $scriptDir 'Upload-Idgard.ps1'
if (-not (Test-Path $mainScript)) {
    Write-Log "Main script not found at '$mainScript'" 'ERROR'; exit 3
}

# --- Validate input folder exists (fatal) ---
if (-not (Test-Path -Path $InputFolder -PathType Container)) {
    Write-Log "Input folder not found: '$InputFolder'" 'ERROR'; exit 4
}

# --- Build parameters for the main script ---
$childParams = @{
    CredentialTarget = $CredentialTarget
    InputFolder      = $InputFolder
    BaseUrl          = $BaseUrl
    BoxId            = $BoxId
    ParentNodeId     = $ParentNodeId
    LogFile          = $LogFile
}
if ($WhatIf) { $childParams.WhatIf = $true }

# --- Retry loop with error classification ---
for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
    Write-Log "Attempt #$attempt of $MaxRetries..."

    if ($WhatIf) {
        Write-Log "DRY-RUN: would invoke '$mainScript' with parameters: $($childParams.Keys -join ', ')" 'WARN'
        $exitCode = 0
    }
    else {
        Write-Verbose "Invoking main script: $mainScript"
        try {
            & $mainScript @childParams
            $exitCode = $LASTEXITCODE
        }
        catch {
            Write-Log "Exception running main script: $_" 'ERROR'
            $exitCode = 1
        }
    }

    switch ($exitCode) {
        0 {
            Write-Log "Success on attempt #$attempt" 'INFO'
            exit 0
        }
        4 {
            Write-Log "Fatal error: input folder not found (code 4). Aborting." 'ERROR'
            exit 4
        }
        2 {
            Write-Log "Fatal error: credential/login failure in main script (code 2). Aborting." 'ERROR'
            exit 2
        }
        3 {
            Write-Log "Fatal error: login error in main script (code 3). Aborting." 'ERROR'
            exit 3
        }
        5 {
            Write-Log "Transient error: upload failure (code 5). Will retry." 'WARN'
        }
        default {
            # treat everything else as transient up to MaxRetries
            Write-Log "Transient or unknown error (code $exitCode). Will retry if attempts remain." 'WARN'
        }
    }

    if ($attempt -lt $MaxRetries) {
        Write-Log "Waiting $DelaySeconds seconds before next attempt..." 'INFO'
        Start-Sleep -Seconds $DelaySeconds
    }
}

# --- All retries exhausted ---
Write-Log "All $MaxRetries attempts failed. Exiting with code $exitCode." 'ERROR'
exit $exitCode

#E-mail or Teams notification on final failure.
#if ($exitCode -ne 0) {
#  Send-MailMessage -To ops@rentenbank.de -Subject "Idgard Upload FAILED" `
#    -Body "Upload failed with exit code $exitCode on $(Get-Date)." -SmtpServer mail.rentenbank.de
#}
