# Exit codes:
# 2 = Missing file
# 3 = Login failure
# 4 = Token failure
# 5 = Upload failure

param (
    [string] $Username     = "DKBEY002",
    [string] $Password     = '2smFJpfysNx0L5Ok*%WBgSV',
    [string] $FilePath     = "C:\Users\OliverDetjen\Downloads\idgard_test_file.txt",
    [string] $BaseUrl      = "https://my.idgard.de/",
    [string] $BoxId        = "2n42g",
    [string] $ParentNodeId = "nbhfvq",
    [string] $LogFile      = "$PSScriptRoot\idgard-upload.log",
    [switch] $WhatIf
)

# === 0) Input Validation (exit code 2) ===
if (-not (Test-Path -Path $FilePath -PathType Leaf)) {
    Write-Host "[ERROR] File not found: '$FilePath'"
    exit 2
}

function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    $logEntry = @{
        timestamp = (Get-Date).ToString("s")
        level     = $Level
        message   = $Message
    } | ConvertTo-Json -Compress
    $logEntry | Out-File -FilePath $LogFile -Encoding UTF8 -Append
    Write-Host "[$Level] $Message"
}

# Prepare WebRequestSession
$session = [Microsoft.PowerShell.Commands.WebRequestSession]::new()
$session.Headers.Add("Accept", "application/json")
# Note: we’ll specify Content-Type per call

# === 1) LOGIN (exit code 3) ===
try {
    Write-Log "Starting login for user '$Username'..."
    $loginUriBuilder = [System.UriBuilder]::new($BaseUrl)
    $loginUriBuilder.Path  = "webapp/rest/login"
    $loginUri = $loginUriBuilder.Uri.AbsoluteUri

    Write-Verbose "LOGIN URI: $loginUri"
    $loginPayload = @{ payload = @{ username = $Username; password = $Password } } | ConvertTo-Json -Depth 3
    Write-Verbose "LOGIN Payload: $loginPayload"

    if ($WhatIf) {
        Write-Log "DRY-RUN: would POST to $loginUri with JSON payload" "WARN"
    }
    else {
        $loginResponse = Invoke-RestMethod `
            -Method POST `
            -Uri $loginUri `
            -Headers @{ "Content-Type" = "application/json" } `
            -Body $loginPayload `
            -WebSession $session

        $sessionId = $loginResponse.sessionId
        if (-not $sessionId) {
            throw "No sessionId in login response"
        }
        Write-Log "Login succeeded. Session-ID: $sessionId"
    }
}
catch [System.Net.WebException] {
    Write-Log "HTTP error during login: $_" "ERROR"
    exit 3
}
catch {
    Write-Log "Login failed: $_" "ERROR"
    exit 3
}

# === 2) UPLOAD TOKEN (exit code 4) ===
try {
    Write-Log "Requesting upload token..."
    $tokenUriBuilder = [System.UriBuilder]::new($BaseUrl)
    $tokenUriBuilder.Path  = "webapp/rest/boxes/$BoxId/$ParentNodeId"
    $tokenUriBuilder.Query = "cmd=up&param=nopt&opt=nopt"
    $tokenUri = $tokenUriBuilder.Uri.AbsoluteUri

    Write-Verbose "TOKEN URI: $tokenUri"
    if ($WhatIf) {
        Write-Log "DRY-RUN: would POST '{}' to $tokenUri" "WARN"
    }
    else {
        $tokenResponse = Invoke-RestMethod `
            -Method POST `
            -Uri $tokenUri `
            -Headers @{ "Content-Type" = "application/json" } `
            -Body '{}' `
            -WebSession $session

        $uploadToken = $tokenResponse.data
        if (-not $uploadToken) {
            throw "No uploadToken received"
        }
        Write-Log "Upload token received: $uploadToken"
    }
}
catch [System.Net.WebException] {
    Write-Log "HTTP error during token request: $_" "ERROR"
    exit 4
}
catch {
    Write-Log "Failed to get upload token: $_" "ERROR"
    exit 4
}

# === 3) FILE UPLOAD (exit code 5) ===
try {
    $fileInfo = Get-Item $FilePath
    Write-Log "Preparing to upload '$($fileInfo.Name)' ($($fileInfo.Length) bytes)..."
    Write-Verbose "File path: $FilePath"

    $uploadUriBuilder = [System.UriBuilder]::new($BaseUrl)
    $uploadUriBuilder.Path  = "webapp/upload/$BoxId"
    $uploadUriBuilder.Query = "parentnodeid=$ParentNodeId&id=$uploadToken"
    $uploadUri = $uploadUriBuilder.Uri.AbsoluteUri

    Write-Verbose "UPLOAD URI: $uploadUri"

    if ($WhatIf) {
        Write-Log "DRY-RUN: would upload $($fileInfo.Name) to $uploadUri" "WARN"
    }
    else {
        $uploadResponse = Invoke-RestMethod `
            -Method POST `
            -Uri $uploadUri `
            -ContentType "multipart/form-data" `
            -Form @{ file = $fileInfo } `
            -WebSession $session

        if ($uploadResponse -notmatch "^OK:$uploadToken$") {
            throw "Invalid upload response: $uploadResponse"
        }
        Write-Log "File upload succeeded: $($fileInfo.Name)"
    }
}
catch [System.IO.IOException] {
    Write-Log "File I/O error: $_" "ERROR"
    exit 5
}
catch [System.Net.WebException] {
    Write-Log "HTTP error during upload: $_" "ERROR"
    exit 5
}
catch {
    Write-Log "Unexpected upload error: $_" "ERROR"
    exit 5
}

# === End ===
if ($WhatIf) {
    Write-Log "Script run in DRY-RUN mode; no changes were made." "WARN"
}
else {
    Write-Log "Script completed successfully." "INFO"
}

# Note: if you move to System.Net.Http.HttpClient for chunked or large‑file uploads,
# ensure you Dispose() streams and client instances in a finally block to avoid resource leaks.