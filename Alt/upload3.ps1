param (
    [string]$Username = "DKBEY002",
    [string]$Password = "2smFJpfysNx0L5Ok*%WBgSV",
    [string]$FilePath     = "C:\Users\OliverDetjen\Downloads\idgard_test_file.txt",
    [string]$BaseUrl      = "https://my.idgard.de/webapp",
    [string]$BoxId        = "2n42g",
    [string]$ParentNodeId = "nbhfvq",
    [string]$LogFile      = "$PSScriptRoot\idgard-upload.log"
)



# === Log helper ===
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

# === Web session setup ===
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$headers = @{
    "Content-Type" = "application/json"
    "Accept"       = "application/json"
}

# === LOGIN ===
try {
    Write-Log "Starte Login mit Benutzer $Username..."
    $loginUri = "$BaseUrl/rest/login"
    $loginPayload = @{ payload = @{ username = $Username; password = $Password } } | ConvertTo-Json -Depth 3

    $loginResponse = Invoke-RestMethod -Method POST -Uri $loginUri -Headers $headers -Body $loginPayload -WebSession $session
    $sessionId = $loginResponse.sessionId

    if (-not $sessionId) {
        throw "Session-ID nicht gefunden in Antwort"
    }

    Write-Log "Login erfolgreich. Session-ID: $sessionId"
}
catch {
    Write-Log "Login fehlgeschlagen: $_" "ERROR"
    exit 1
}

# === Get Upload-Token ===

try {
    Write-Log "Fordere Upload-Token an..."

    $url_uploadtoken = "$BaseUrl/rest/boxes/$BoxId/$nbhfvq?cmd=up&param=nopt&opt=nopt"
    #$url_uploadtoken = "https://my.idgard.de/webapp/rest/boxes/2n42g/nbhfvq?cmd=up&param=nopt&opt=nopt"
    $uploadtoken = Invoke-RestMethod -Method 'POST' -Uri $url_uploadtoken -Headers $headers -WebSession $session
    $uploadtoken = $uploadtoken.data

    if (-not $uploadToken) {
        throw "Kein Upload-Token empfangen"
    }

    Write-Log "Upload-Token erhalten: $uploadToken"
}
catch {
    Write-Log "Upload-Token-Abruf fehlgeschlagen: $_" "ERROR"
    exit 1
}

# === Datei-Upload ===
try {
    $fileInfo = Get-Item $FilePath
    $uploadUri = "$BaseUrl/upload/$BoxId?parentnodeid=$ParentNodeId&id=$uploadToken"

    Write-Log "Bereite Datei-Upload vor: $($fileInfo.Name) ($($fileInfo.Length) Bytes)"

    $form = @{
        file = $fileInfo
    }

    $uploadResponse = Invoke-RestMethod -Uri $uploadUri -Method POST -ContentType "multipart/form-data" -Form $form -WebSession $session

    # API erwartet "OK:<uploadToken>" als einfache Antwort
    if ($uploadResponse -notmatch "^OK:$uploadToken$") {
        throw "Upload-Antwort ungültig: $uploadResponse"
    }

    Write-Log "Datei erfolgreich hochgeladen: $($fileInfo.Name)"
}
catch {
    Write-Log "Fehler beim Upload: $_" "ERROR"
    exit 1
}