# === Konfiguration ===
$baseUrl        = "https://my.idgard.de/webapp"
$boxId          = "2n42g"
$parentnodeid   = "nbhfvq"
$username       = "DKBEY002"
$password       = '2smFJpfysNx0L5Ok*%WBgSV'
$filePath       = "C:\Users\OliverDetjen\Downloads\idgard_test_file.txt"    # <-- hier anpassen
$logFile        = "C:\Users\OliverDetjen\Downloads\log.txt"     # <-- hier anpassen

# === Log-Funktion ===
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $entry = "$timestamp [$Level] $Message"
    $entry | Out-File -FilePath $logFile -Encoding UTF8 -Append
    Write-Host $entry
}

# Hilfsfunktion für HTTP-Errors
function Throw-IfError($response, $step) {
    if (-not $response.IsSuccessStatusCode) {
        $status  = $response.StatusCode.value__
        $reason  = $response.ReasonPhrase
        $body    = $response.Content.ReadAsStringAsync().Result
        Write-Log "Fehler bei '$step': HTTP $status – $reason`n$body" "ERROR"
        throw "HTTP $status – $reason"
    } else {
        Write-Log "Erfolgreicher Call: '$step' (Status $($response.StatusCode.value__))"
    }
}

# === 1) Login & Session einrichten ===
try {
    Write-Log "Starte Login..."
    $loginEndpoint = "$baseUrl/rest/login"
    $loginBody     = @{
        payload = @{
            username = $username
            password = $password
        }
    } | ConvertTo-Json

    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.CookieContainer = New-Object System.Net.CookieContainer
    $client  = [System.Net.Http.HttpClient]::new($handler)

    $request = [System.Net.Http.StringContent]::new($loginBody, [Text.Encoding]::UTF8, "application/json")
    $resp    = $client.PostAsync($loginEndpoint, $request).Result
    Throw-IfError $resp "Login"

    $json      = $resp.Content.ReadAsStringAsync().Result | ConvertFrom-Json
    $sessionId = $json.payload.sessionid
    Write-Log "Login erfolgreich. Session-ID: $sessionId"
}
catch {
    Write-Log "Login fehlgeschlagen: $_" "ERROR"
    exit 1
}

# === 2) Upload-Token abrufen ===
try {
    Write-Log "Rufe Upload-Token ab..."
    $tokenEndpoint = "$baseUrl/rest/boxes/${boxId}/${parentnodeid}?cmd=up&param=nopt&opt=nopt"
    $resp = $client.PostAsync(
        $tokenEndpoint,
        [System.Net.Http.StringContent]::new("{}", [Text.Encoding]::UTF8, "application/json")
    ).Result
    Throw-IfError $resp "Token-Abruf"

    $json        = $resp.Content.ReadAsStringAsync().Result | ConvertFrom-Json
    $uploadToken = $json.data
    Write-Log "Upload-Token erhalten: $uploadToken"
}
catch {
    Write-Log "Token-Abruf fehlgeschlagen: $_" "ERROR"
    exit 1
}

## === 3) Datei hochladen ===
try {
    Write-Log "Starte Datei-Upload..."
    $uploadEndpoint = "$baseUrl/upload/$boxId?parentnodeid=nbhfvq&id=$uploadToken"

    # Multipart/Form-Data Content
    $multipart   = New-Object System.Net.Http.MultipartFormDataContent
    $fileStream  = [System.IO.File]::OpenRead($filePath)
    $fileName    = [System.IO.Path]::GetFileName($filePath)
    $fileContent = [System.Net.Http.StreamContent]::new($fileStream)
    $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("application/octet-stream")
    $multipart.Add($fileContent, "file", $fileName)

    # Request absenden
    $resp = $client.PostAsync($uploadEndpoint, $multipart).Result

    # Roh-Body auslesen
    $rawUploadResponse = $resp.Content.ReadAsStringAsync().Result
    Write-Log "Raw Upload-Response: $rawUploadResponse"

    # HTTP-Status prüfen
    Throw-IfError $resp "Datei-Upload"

    # Business-Logik prüfen: enthält die Antwort OK:<uploadToken>?
    if ($rawUploadResponse -notmatch "OK:$uploadToken") {
        Write-Log "Upload-Response enthält nicht das erwartete OK:$uploadToken" "ERROR"
        throw "Ungültige Upload-Antwort"
    }

    Write-Log "Datei-Upload erfolgreich: $fileName (Upload-Token OK)"
}
catch {
    Write-Log "Upload fehlgeschlagen: $($_.Exception.Message)" "ERROR"
    Write-Log "Exception Type: $($_.Exception.GetType().FullName)" "ERROR"
    Write-Log "Stack Trace: $($_.Exception.ScriptStackTrace)" "ERROR"
    if ($_.Exception.Response) {
        $respBodyStream = $_.Exception.Response.GetResponseStream()
        $sr = New-Object System.IO.StreamReader($respBodyStream)
        $sr.BaseStream.Position = 0; $sr.DiscardBufferedData()
        $body = $sr.ReadToEnd()
        Write-Log "Response Body: $body" "ERROR"
    }
    exit 1
}
finally {
    # Ressourcen aufräumen
    if ($fileStream) { $fileStream.Dispose() }
    Write-Log "Datei-Upload Block beendet."
}