This repository contains a set of PowerShell scripts to automate secure file uploads to an Idgard data room via its REST API, including:

🔄 Automatic retries on transient failures

🔧 Scheduled execution support (e.g., Task Scheduler)

📁 Upload from CIFS/NFS share

🌐 HTTP proxy support

🔐 Secure credential storage using Export-Clixml


📁 Scripts

Upload-Idgard.ps1	Main script for uploading files to Idgard using the API
Upload-Idgard-With-Retry.ps1	Wrapper script that adds retry logic and logging

🔧 Setup Instructions

1. Prerequisites

PowerShell 5.1+ or PowerShell Core (7+)

Windows Server or client with access to:

CIFS/NFS share

Outbound HTTPS via proxy (if applicable)

2. Credential Storage (Recommended)

Run once to store encrypted credentials:

Get-Credential | Export-Clixml -Path "$env:USERPROFILE\idgard-cred.xml"

🔒 The credentials are encrypted for the current user and machine.

3. Configuration
4. 
Update or pass these values as parameters:

- InputFolder: Path to source folder (e.g. mounted share)
- BaseUrl: Idgard API base URL (https://my.idgard.de/)
- BoxId: Target Box ID in Idgard
- ParentNodeId: Target parent node in the Box
- LogFile: Path to log file (default: idgard-upload.log)
- CredentialTarget (optional):used in older version with CredentialManager
