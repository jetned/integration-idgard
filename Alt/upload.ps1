#[Threading.Thread]::CurrentThread.CurrentUICulture = 'en-US';

add-type -AssemblyName System.Net.Http

$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("Content-Type", "application/json")
$headers.Add("Accept", "application/json")

$body = @"
  {
  `"payload`": {
    `"password`": `"2smFJpfysNx0L5Ok*%WBgSV`",
    `"username`": `"DKBEY002`"
  }
}
"@

$session = [Microsoft.PowerShell.Commands.WebRequestSession]::new()

$url_login = 'https://my.idgard.de/webapp/rest/login' 
$login = try {Invoke-WebRequest -Method POST -Uri $url_login -UseBasicParsing -Headers $headers -Body $body -SessionVariable websession} catch { $_.Exception.Response.Headers.ToString() }
$cookies = $websession.Cookies.GetCookies($url_login) 

foreach ($cookie in $cookies) { 
     
    $session.Cookies.Add('https://my.idgard.de', $cookie)   
     }

#Getuploadtoken

$url_uploadtoken = "$BaseUrl/rest/boxes/$BoxId/$ParentNodeId?cmd=up&param=nopt&opt=nopt"
$uploadtoken = Invoke-RestMethod -Method 'POST' -Uri $url_uploadtoken -Headers $headers -WebSession $session
#$uploadtoken | ConvertTo-Json 
$uploadtoken = $uploadtoken.data

#upload file

$filePath = "C:\Users\OliverDetjen\OneDrive - Uniscon GmbH\Dokumente\EY\test.txt"  # Bitte den Pfad zur Datei anpassen
$uploadNodeUrl = 'https://my.idgard.de/webapp/upload/2n42g?parentnodeid=nbhfvq&id=' + $uploadToken
      

$file_contents = Get-Item $filePath
$uploadNodeResponse = Invoke-RestMethod -Uri $uploadNodeUrl -Method 'POST' -ContentType "multipart/form-data" -Headers $headers -WebSession $session -Form @{ file = $file_contents }
$uploadNodeResponse | ConvertTo-Json 
