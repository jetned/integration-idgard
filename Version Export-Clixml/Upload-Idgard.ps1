# Exit codes:
# 2 = Missing file // Origin not available
# 3 = Login failure
# 4 = Token failure
# 5 = Upload failure


param (
    [string] $InputFolder,
    [string] $BaseUrl        = 'https://my.idgard.de/',
    [string] $BoxId          = '2n42g',
    [string] $ParentNodeId   = 'nbhfvq',
    [string] $LogFile        = "$PSScriptRoot\idgard-upload.log"
)

function Write-Log {
    param($Message, $Level = 'INFO')
    $entry = @{
        timestamp = (Get-Date).ToString('s')
        level     = $Level
        message   = $Message
    } | ConvertTo-Json -Compress
    $entry | Out-File -FilePath $LogFile -Append -Encoding UTF8
    Write-Host "[$Level] $Message"
}

# === Load encrypted credentials from file ===
$credPath = Join-Path $env:USERPROFILE "idgard-cred.xml"
if (-not (Test-Path $credPath)) {
    Write-Log "Credential file not found at $credPath" 'ERROR'
    exit 1
}

try {
    $cred = Import-Clixml -Path $credPath
    $username = $cred.UserName
    $password = $cred.GetNetworkCredential().Password
    Write-Log "Retrieved credential for user '$username'."
}
catch {
    Write-Log "Failed to load credentials from ${credPath}: $_" 'ERROR'
    exit 1
}


# === 0) Prepare and validate folders ===
if (-not (Test-Path $InputFolder -PathType Container)) {
    Write-Log "Input folder not found: $InputFolder" 'ERROR'; exit 1
}
$uploadedFolder = Join-Path $InputFolder 'uploaded'
if (-not (Test-Path $uploadedFolder)) {
    New-Item -Path $uploadedFolder -ItemType Directory | Out-Null
    Write-Log "Created processed-folder: $uploadedFolder"
}

# Get all files to upload
$files = Get-ChildItem -Path $InputFolder -File
if ($files.Count -eq 0) {
    Write-Log "No files found in $InputFolder, nothing to do." 'INFO'
    exit 0
}

# === 1) LOGIN ===
try {
    Write-Log "Starting login for user '$Username'..."
    $loginUri = ([System.UriBuilder]::new($BaseUrl))
    $loginUri.Path = 'webapp/rest/login'

    $loginPayload = @{ payload = @{ username = $Username; password = $Password } } |
                    ConvertTo-Json -Depth 3
    $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $loginResp = Invoke-RestMethod -Method POST -Uri $loginUri.Uri.AbsoluteUri `
                  -Headers @{ 'Content-Type' = 'application/json'; Accept = 'application/json' } `
                  -Body $loginPayload -WebSession $session

    $sessionId = $loginResp.sessionId
    if (-not $sessionId) { throw 'No sessionId in login response.' }
    Write-Log "Login succeeded. Session-ID: $sessionId"
}
catch {
    Write-Log "Login failed: $_" 'ERROR'; exit 2
}

# Process each file
foreach ($file in $files) {
    $filePath = $file.FullName
    $fileName = $file.Name
    Write-Log "---- Processing file: $fileName ($($file.Length) bytes) ----"

    # 2) Get upload token per file
    try {
        $tokenUriB = [System.UriBuilder]::new($BaseUrl)
        $tokenUriB.Path  = "webapp/rest/boxes/$BoxId/$ParentNodeId"
        $tokenUriB.Query = 'cmd=up&param=nopt&opt=nopt'

        $tokenResp = Invoke-RestMethod -Method POST -Uri $tokenUriB.Uri.AbsoluteUri `
                        -Headers @{ 'Content-Type' = 'application/json'; Accept = 'application/json' } `
                        -Body '{}' -WebSession $session

        $uploadToken = $tokenResp.data
        if (-not $uploadToken) { throw 'No uploadToken received.' }
        Write-Log "Upload token: $uploadToken"
    }
    catch {
        Write-Log "Failed to get token for $($fileName): $_" 'ERROR'
        continue   # skip to next file
    }

    # 3) Upload the file
    try {
        $uploadUriB = [System.UriBuilder]::new($BaseUrl)
        $uploadUriB.Path  = "webapp/upload/$BoxId"
        $uploadUriB.Query = "parentnodeid=$ParentNodeId&id=$uploadToken"

        $uploadResp = Invoke-RestMethod -Method POST `
                         -Uri $uploadUriB.Uri.AbsoluteUri `
                         -ContentType 'multipart/form-data' `
                         -Form @{ file = $file } `
                         -WebSession $session

        if ($uploadResp -notmatch "^OK:$uploadToken$") {
            throw "Invalid response: $uploadResp"
        }
        Write-Log "Upload succeeded: $fileName"

        # 4) Move to 'uploaded' subfolder
        $dest = Join-Path $uploadedFolder $fileName
        Move-Item -Path $filePath -Destination $dest -Force
        Write-Log "Moved $fileName → $uploadedFolder"
    }
    catch {
        Write-Log "Error uploading $($fileName): $_" 'ERROR'
        # do not move file; leave for retry next run
    }
}

Write-Log "=== SCRIPT END ===" 'INFO'
exit 0