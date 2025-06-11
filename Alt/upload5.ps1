param (
    [string] $Username     = "DKBEY002",
    [string] $Password     = '2smFJpfysNx0L5Ok*%WBgSV',
    [string] $FilePath     = "C:\Users\OliverDetjen\Downloads\idgard_test_file.txt",
    [string] $BaseUrl      = "https://my.idgard.de/",
    [string] $BoxId        = "2n42g",
    [string] $ParentNodeId = "nbhfvq",
    [string] $LogFile      = "$PSScriptRoot\idgard-upload.log"
)

# Convert SecureString to plain text for API payload
#$PlainPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
#    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
#)

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

# Prepare a single WebRequestSession with default headers
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$session.Headers.Add("Accept", "application/json")
$session.Headers.Add("Content-Type", "application/json")

# === 1) LOGIN ===
try {
    Write-Log "Starting login for user '$Username'..."

    $loginUri = [System.UriBuilder]::new($BaseUrl)
    $loginUri.Path  = "webapp/rest/login"
    $loginUri.Query = ""
    $loginResponse = Invoke-RestMethod `
        -Method POST `
        -Uri $loginUri.Uri.AbsoluteUri `
        -Body (@{ payload = @{ username = $Username; password = $Password } } | ConvertTo-Json -Depth 3) `
        -WebSession $session

    $sessionId = $loginResponse.sessionId
    if (-not $sessionId) {
        throw "No sessionId in login response"
    }

    Write-Log "Login succeeded. Session-ID: $sessionId"
}
catch {
    Write-Log "Login failed: $_" "ERROR"
    exit 1
}

# === 2) UPLOAD TOKEN ===
try {
    Write-Log "Requesting upload token..."

    $tokenUriBuilder = [System.UriBuilder]::new($BaseUrl)
    $tokenUriBuilder.Path  = "webapp/rest/boxes/$BoxId/$ParentNodeId"
    $tokenUriBuilder.Query = "cmd=up&param=nopt&opt=nopt"
    $tokenEndpoint = $tokenUriBuilder.Uri.AbsoluteUri

    $tokenResponse = Invoke-RestMethod `
        -Method POST `
        -Uri $tokenEndpoint `
        -Body '{}' `
        -WebSession $session

    $uploadToken = $tokenResponse.data
    if (-not $uploadToken) {
        throw "No uploadToken received"
    }

    Write-Log "Upload token received: $uploadToken"
}
catch {
    Write-Log "Failed to get upload token: $_" "ERROR"
    exit 1
}

# === 3) FILE UPLOAD ===
try {
    $fileInfo = Get-Item $FilePath
    Write-Log "Preparing to upload '$($fileInfo.Name)' ($($fileInfo.Length) bytes)..."

    $uploadUriBuilder = [System.UriBuilder]::new($BaseUrl)
    $uploadUriBuilder.Path  = "webapp/upload/$BoxId"
    $uploadUriBuilder.Query = "parentnodeid=$ParentNodeId&id=$uploadToken"
    $uploadEndpoint = $uploadUriBuilder.Uri.AbsoluteUri

    $uploadResponse = Invoke-RestMethod `
        -Method POST `
        -Uri $uploadEndpoint `
        -ContentType "multipart/form-data" `
        -Form @{ file = $fileInfo } `
        -WebSession $session

    # Expect exact "OK:<token>" response
    if ($uploadResponse -notmatch "^OK:$uploadToken$") {
        throw "Invalid upload response: $uploadResponse"
    }

    Write-Log "File upload succeeded: $($fileInfo.Name)"
}
catch {
    Write-Log "Upload error: $_" "ERROR"
    exit 1
}