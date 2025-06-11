# === Konfiguration ===
$baseUrl    = "https://my.idgard.de/webapp"
$boxId      = "2n42g"
$username   = "DKBEY002"
$password   = '2smFJpfysNx0L5Ok*%WBgSV'
$filePath   = "C:\Users\OliverDetjen\Downloads\idgard_test_file.txt"  # <-- hier anpassen

# === Hilfsfunktion für HTTP-Errors ===
function Throw-IfError($response) {
    if (-not $response.IsSuccessStatusCode) {
        $status  = $response.StatusCode.value__
        $reason  = $response.ReasonPhrase
        $body    = $response.Content.ReadAsStringAsync().Result
        throw "HTTP $status – $reason`n$body"
    }
}

# === 1) Login & Session einrichten ===
try {
    $loginEndpoint = "$baseUrl/rest/login"
    $loginBody     = @{
        payload = @{
            username = $username
            password = $password
        }
    } | ConvertTo-Json

    # Verwende HttpClient für mehr Kontrolle
    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.CookieContainer = New-Object System.Net.CookieContainer
    $client  = [System.Net.Http.HttpClient]::new($handler)

    $request = [System.Net.Http.StringContent]::new($loginBody, [Text.Encoding]::UTF8, "application/json")
    $resp    = $client.PostAsync($loginEndpoint, $request).Result
    Throw-IfError $resp

    $json    = $resp.Content.ReadAsStringAsync().Result | ConvertFrom-Json
    $sessionId = $json.payload.sessionid
    Write-Host "✅ Login erfolgreich. Session-ID: $sessionId`n"
}
catch {
    Write-Error "Login fehlgeschlagen:`n$_"
    exit 1
}

# === 2) Upload-Token abrufen ===
try {
    $tokenEndpoint = "$baseUrl/rest/boxes/$boxId/nbhfvq?cmd=up&param=nopt&opt=nopt"
    $resp = $client.PostAsync($tokenEndpoint, [System.Net.Http.StringContent]::new("{}", [Text.Encoding]::UTF8, "application/json")).Result
    Throw-IfError $resp

    $json = $resp.Content.ReadAsStringAsync().Result | ConvertFrom-Json
    $uploadToken = $json.data
    Write-Host "✅ Upload-Token erhalten: $uploadToken`n"
}
catch {
    Write-Error "Token-Abruf fehlgeschlagen:`n$_"
    exit 1
}




# === 3) Datei hochladen ===
try {
    $uploadEndpoint = "$baseUrl/upload/$boxId?parentnodeid=nbhfvq&id=$uploadToken"
    
    # Multipart/Form-Data Content
    $multipart = New-Object System.Net.Http.MultipartFormDataContent
    $fileStream = [System.IO.File]::OpenRead($filePath)
    $fileName   = [System.IO.Path]::GetFileName($filePath)
    $fileContent = [System.Net.Http.StreamContent]::new($fileStream)
    $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("application/octet-stream")

    $multipart.Add($fileContent, "file", $fileName)

    $resp = $client.PostAsync($uploadEndpoint, $multipart).Result
    Throw-IfError $resp

    Write-Host "✅ Datei-Upload erfolgreich: $fileName"
}
catch {
    Write-Error "Upload fehlgeschlagen:`n$_"
    exit 1
}

# === Cleanup ===
$fileStream.Dispose()
$client.Dispose()
Erläuterungen
HttpClient statt Invoke‑RestMethod
Mit System.Net.Http.HttpClient kannst du Cookies und multipart/form-data‑Uploads zuverlässiger handhaben.

Robustes Fehler‑Handling
Die Funktion Throw-IfError wirft bei jedem HTTP‑Statuscode ≠ 2xx eine detaillierte Ausnahme mit Statuscode, Reason-Phrase und Response‑Body.

Multipart Upload

Der MultipartFormDataContent-Container enthält deine Datei mit dem Feld‑Namen "file".

Achte darauf, dass der Parametername ("file") und der Query‑Parameter (id=$uploadToken) mit der idgard‑API dokumentiert übereinstimmen.

Session & Cookies
Der Cookie‑Container aus dem HttpClientHandler übernimmt automatisch die Session‑ID und alle erforderlichen Cookies aus dem Login‑Aufruf.

Passe die Variablen am Anfang an, und schon sollte der komplette Workflow (Login → Token → Datei‑Upload) fehlerfrei durchlaufen. Wenn es trotzdem noch hakt, gib die konkrete Fehlermeldung durch, dann schauen wir weiter!







Du:
Bitte generierte ein log für jeden erfolgreichen oder nicht erforgreichen api-request....


ChatGPT:
Hier ein erweitertes Skript, das für jeden API-Call Einträge in eine Log-Datei schreibt – sowohl bei Erfolg als auch bei Fehlern. Du findest am Anfang eine $logFile-Variable, in die alle Logs geschrieben werden.

powershell
Kopieren
Bearbeiten
# === Konfiguration ===
$baseUrl    = "https://my.idgard.de/webapp"
$boxId      = "2n42g"
$username   = "DKBEY002"
$password   = '2smFJpfysNx0L5Ok*%WBgSV'
$filePath   = "C:\Pfad\zu\deiner\Datei.txt"    # <-- hier anpassen
$logFile    = "C:\Pfad\zu\deinem\log.txt"     # <-- hier anpassen

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
    $tokenEndpoint = "$baseUrl/rest/boxes/$boxId/nbhfvq?cmd=up&param=nopt&opt=nopt"
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

# === 3) Datei hochladen ===
try {
    Write-Log "Starte Datei-Upload..."
    $uploadEndpoint = "$baseUrl/upload/$boxId?parentnodeid=nbhfvq&id=$uploadToken"

    $multipart   = New-Object System.Net.Http.MultipartFormDataContent
    $fileStream  = [System.IO.File]::OpenRead($filePath)
    $fileName    = [System.IO.Path]::GetFileName($filePath)
    $fileContent = [System.Net.Http.StreamContent]::new($fileStream)
    $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("application/octet-stream")
    $multipart.Add($fileContent, "file", $fileName)

    $resp = $client.PostAsync($uploadEndpoint, $multipart).Result
    Throw-IfError $resp "Datei-Upload"

    Write-Log "Datei-Upload erfolgreich: $fileName"
}
catch {
    Write-Log "Upload fehlgeschlagen: $_" "ERROR"
    exit 1
}
finally {
    # Ressourcen aufräumen
    if ($fileStream) { $fileStream.Dispose() }
    $client.Dispose()
    Write-Log "Skript beendet."
}