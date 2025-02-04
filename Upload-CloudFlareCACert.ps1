# Remove the [switch] parameter
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = ".\config.txt"
)

# Define the path to the config file (in the same directory as the script)
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $scriptPath "config.txt"

function Show-Menu {
    Clear-Host
    Write-Host "================ Cloudflare mTLS CA Certificate Manager ================"
    Write-Host "1: Upload new CA certificate"
    Write-Host "2: Associate CA certificate with zone"
    Write-Host "3: Delete CA certificate"
    Write-Host "4: View certificates"
    Write-Host "5: Deassociate CA certificate"
    Write-Host "6: View certificate associations"
    Write-Host "7: Exit"
    Write-Host "=================================================================="
}

function Read-ConfigFile {
    $configDict = @{}
    
    if (Test-Path -Path $configPath) {
        Get-Content -Path $configPath | ForEach-Object {
            if (-not [string]::IsNullOrWhiteSpace($_) -and -not $_.StartsWith("#")) {
                if ($_ -match "(.+?)=(.+)") {
                    $key = $matches[1].Trim()
                    $value = $matches[2].Trim()
                    $configDict[$key] = $value
                }
            }
        }
    }
    
    # Prompt for missing required values
    if (-not $configDict['API_TOKEN']) {
        $configDict['API_TOKEN'] = Read-Host "Enter your Cloudflare API Token"
    }
    
    if (-not $configDict['AUTH_EMAIL']) {
        $configDict['AUTH_EMAIL'] = Read-Host "Enter your Cloudflare Auth Email"
    }
    
    if (-not $configDict['ACCOUNT_ID']) {
        $configDict['ACCOUNT_ID'] = Read-Host "Enter your Cloudflare Account ID"
    }
    
    if (-not $configDict['CA_CERT_PATH']) {
        $configDict['CA_CERT_PATH'] = Read-Host "Enter the path to your CA certificate file"
    }
    
    return $configDict
}

function Get-CloudflareHeaders {
    param (
        [string]$apiToken
    )
    
    $configDict = Read-ConfigFile
    return @{
        'Authorization' = "Bearer $apiToken"
        'Content-Type' = 'application/json'
    }
}

function Get-Certificates {
    $configDict = Read-ConfigFile
    $apiToken = $configDict['API_TOKEN']
    $accountId = $configDict['ACCOUNT_ID']

    # Use common headers
    $headers = Get-CloudflareHeaders -apiToken $apiToken

    # Define the API endpoint for listing mTLS certificates
    $uri = "https://api.cloudflare.com/client/v4/accounts/$accountId/mtls_certificates"

    try {
        $response = Invoke-WebRequest -Uri $uri -Method Get -Headers $headers
        $certificates = ($response.Content | ConvertFrom-Json).result

        if ($certificates.Count -eq 0) {
            Write-Host "`nNo certificates found."
        } else {
            Write-Host "`nFound $($certificates.Count) certificate(s):`n"
            foreach ($cert in $certificates) {
                Write-Host "Certificate ID: $($cert.id)"
                Write-Host "Name: $($cert.name)"
                Write-Host "Issuer: $($cert.issuer)"
                Write-Host "Uploaded On: $($cert.uploaded_on)"
                Write-Host "Expires On: $($cert.expires_on)"
                Write-Host "Type: $($cert.type)"
                Write-Host "CA: $($cert.ca)"
                Write-Host "----------------------------------------`n"
            }
        }
    } catch {
        Write-Host "Failed to retrieve certificates."
        if ($_.Exception.Response) {
            $errorResponse = $_.Exception.Response
            $errorStream = $errorResponse.GetResponseStream()
            $streamReader = New-Object System.IO.StreamReader($errorStream)
            $errorMessage = $streamReader.ReadToEnd()
            Write-Host "Error Response: $errorMessage"
            Write-Host "Status Code: $($errorResponse.StatusCode.value__)"
            Write-Host "Status Description: $($errorResponse.StatusDescription)"
    } else {
            Write-Host "Error: $($_.Exception.Message)"
        }
    }
    pause
}

function Remove-Certificate {
    $configDict = Read-ConfigFile
    $accountId = $configDict['ACCOUNT_ID']

    # Get list of certificates first using the common headers
    $headers = Get-CloudflareHeaders -apiToken $configDict['API_TOKEN']

    try {
        # First, get all certificates
        $uri = "https://api.cloudflare.com/client/v4/accounts/$accountId/mtls_certificates"
        $response = Invoke-WebRequest -Uri $uri -Method Get -Headers $headers
        $certificates = ($response.Content | ConvertFrom-Json).result

        if ($certificates.Count -eq 0) {
            Write-Host "`nNo certificates found to delete."
            pause
            return
        }

        # Display certificates with numbers for selection
        Write-Host "`nAvailable certificates:"
        for ($i = 0; $i -lt $certificates.Count; $i++) {
            Write-Host "[$($i + 1)] $($certificates[$i].name) (ID: $($certificates[$i].id))"
        }

        # Get user selection
        $selection = Read-Host "`nEnter the number of the certificate to delete (or 'C' to cancel)"
        if ($selection -eq 'C') {
            Write-Host "Operation cancelled."
            pause
            return
        }

        $index = [int]$selection - 1
        if ($index -lt 0 -or $index -ge $certificates.Count) {
            Write-Host "Invalid selection."
            pause
            return
        }

        $certId = $certificates[$index].id
        $certName = $certificates[$index].name

        # Confirm deletion
        $confirm = Read-Host "Are you sure you want to delete certificate '$certName'? (Y/N)"
        if ($confirm -ne 'Y') {
            Write-Host "Operation cancelled."
            pause
            return
        }

        # Zone ID handling
        $zoneId = $configDict['ZONE_ID']
        $useConfigZoneId = $false

        if ($zoneId) {
            $useConfig = Read-Host "`nZone ID found in config.txt. Use this Zone ID? (Y/N)"
            $useConfigZoneId = $useConfig -eq 'Y'
        }

        if (-not $useConfigZoneId) {
            $zoneId = Read-Host "Enter the Zone ID"
            if ([string]::IsNullOrWhiteSpace($zoneId)) {
                Write-Host "Zone ID cannot be empty."
                pause
                return
            }
        }

        # First, deassociate the certificate from any hostnames
        Write-Host "Checking for and removing any hostname associations..."
        $associationsRemoved = Remove-CertificateAssociations -certificateId $certId -zoneId $zoneId -headers $headers
        
        if ($associationsRemoved) {
            # Then delete the certificate itself
            Write-Host "Deleting certificate from account..."
            $deleteUri = "https://api.cloudflare.com/client/v4/accounts/$accountId/mtls_certificates/$certId"
            $deleteResponse = Invoke-WebRequest -Uri $deleteUri -Method Delete -Headers $headers
            $result = $deleteResponse.Content | ConvertFrom-Json
            
            if ($result.success) {
                Write-Host "Successfully deleted CA certificate '$certName'" -ForegroundColor Green
                $result | ConvertTo-Json -Depth 4
                
                # Verify deletion by listing certificates
                Write-Host "`nVerifying deletion by listing remaining certificates..." -ForegroundColor Yellow
                Start-Sleep -Seconds 2  # Brief pause to allow deletion to propagate
                
                $verifyResponse = Invoke-WebRequest -Uri $uri -Method Get -Headers $headers
                $remainingCerts = ($verifyResponse.Content | ConvertFrom-Json).result
                
                if ($remainingCerts.Count -eq 0) {
                    Write-Host "No certificates found - deletion confirmed." -ForegroundColor Green
                } else {
                    Write-Host "`nRemaining certificates:" -ForegroundColor Yellow
                    foreach ($cert in $remainingCerts) {
                        Write-Host "Certificate ID: $($cert.id)"
                        Write-Host "Name: $($cert.name)"
                        Write-Host "----------------------------------------"
                    }
                    
                    # Check if the deleted certificate is still present
                    $stillExists = $remainingCerts | Where-Object { $_.id -eq $certId }
                    if ($stillExists) {
                        Write-Host "`nWarning: The certificate appears to still exist!" -ForegroundColor Red
                    } else {
                        Write-Host "`nConfirmed: Certificate '$certName' has been deleted." -ForegroundColor Green
                    }
                }
            } else {
                Write-Host "Failed to delete certificate:" -ForegroundColor Red
                $result.errors | ForEach-Object {
                    Write-Host "Error: $($_.message) (Code: $($_.code))" -ForegroundColor Red
                }
            }
        }

    } catch {
        Write-Host "Failed to delete CA certificate."
        if ($_.Exception.Response) {
            $errorResponse = $_.Exception.Response
            $errorStream = $errorResponse.GetResponseStream()
            $streamReader = New-Object System.IO.StreamReader($errorStream)
            $errorMessage = $streamReader.ReadToEnd()
            Write-Host "Error Response: $errorMessage"
            Write-Host "Status Code: $($errorResponse.StatusCode.value__)"
            Write-Host "Status Description: $($errorResponse.StatusDescription)"
        } else {
            Write-Host "Error: $($_.Exception.Message)"
        }
    }
    pause
}

function Upload-Certificate {
    $configDict = Read-ConfigFile
    $apiToken = $configDict['API_TOKEN']
    $accountId = $configDict['ACCOUNT_ID']
    $caCertPath = $configDict['CA_CERT_PATH']

    # Use common headers
    $headers = Get-CloudflareHeaders -apiToken $apiToken

    # Validate CA certificate path
    if (-Not (Test-Path -Path $caCertPath)) {
        Write-Host "CA certificate not found at path: $caCertPath"
        pause
        return
    }

    try {
        # Read certificate content
        $caCertContent = Get-Content -Path $caCertPath -Raw
        
        # Clean and format the certificate content
        $caCertContent = $caCertContent.Trim()
        
        # Get certificate name from user
        $certName = Read-Host "Enter a name for the certificate (or press Enter for 'example_ca_cert')"
        if ([string]::IsNullOrWhiteSpace($certName)) {
            $certName = "example_ca_cert"
        }

        # Create the request body
        $body = @{
            "ca" = $true
            "certificates" = $caCertContent
            "name" = $certName
        }

        # Convert the body to JSON
        $jsonBody = ConvertTo-Json -InputObject $body -Depth 10 -Compress
        
        # Debug information
        Write-Host "`n=== Debug Information ==="
        Write-Host "Headers:"
        $headers.GetEnumerator() | ForEach-Object {
            Write-Host "  $($_.Key): $(if ($_.Key -eq 'Authorization') {'Bearer [HIDDEN]'} else {$_.Value})"
        }
        Write-Host "Account ID: $accountId"
        Write-Host "Certificate Path: $caCertPath"
        Write-Host "Certificate Content Length: $($caCertContent.Length)"
        Write-Host "Request Body Length: $($jsonBody.Length)"
        
        # Define the API endpoint
        $uri = "https://api.cloudflare.com/client/v4/accounts/$accountId/mtls_certificates"
        Write-Host "Request URL: $uri"
        Write-Host "=======================`n"

        # Make the API request
        $response = Invoke-WebRequest -Uri $uri -Method Post -Headers $headers -Body $jsonBody
        $result = $response.Content | ConvertFrom-Json

        if ($result.success) {
            Write-Host "Successfully uploaded CA certificate"
            Write-Host "Certificate ID: $($result.result.id)"
            Write-Host "Name: $($result.result.name)"
            Write-Host "Issuer: $($result.result.issuer)"
            Write-Host "Expires On: $($result.result.expires_on)"
        } else {
            Write-Host "Failed to upload certificate:"
            $result.errors | ForEach-Object {
                Write-Host "Error: $($_.message) (Code: $($_.code))"
            }
        }

    } catch {
        Write-Host "Failed to upload CA certificate."
        if ($_.Exception.Response) {
            $errorResponse = $_.Exception.Response
            $errorStream = $errorResponse.GetResponseStream()
            $streamReader = New-Object System.IO.StreamReader($errorStream)
            $errorMessage = $streamReader.ReadToEnd()
            Write-Host "Error Response: $errorMessage"
            Write-Host "Status Code: $($errorResponse.StatusCode.value__)"
            Write-Host "Status Description: $($errorResponse.StatusDescription)"
        } else {
            Write-Host "Error: $($_.Exception.Message)"
        }
    }
    pause
}

function Associate-Certificate {
    $configDict = Read-ConfigFile
    $apiToken = $configDict['API_TOKEN']
    $accountId = $configDict['ACCOUNT_ID']

    # Get list of certificates first using the common headers
    $headers = Get-CloudflareHeaders -apiToken $apiToken

    try {
        # First, get all certificates
        $uri = "https://api.cloudflare.com/client/v4/accounts/$accountId/mtls_certificates"
        $response = Invoke-WebRequest -Uri $uri -Method Get -Headers $headers
        $certificates = ($response.Content | ConvertFrom-Json).result

        if ($certificates.Count -eq 0) {
            Write-Host "`nNo certificates found to associate."
            pause
            return
        }

        # Display certificates with numbers for selection
        Write-Host "`nAvailable certificates:"
        for ($i = 0; $i -lt $certificates.Count; $i++) {
            Write-Host "[$($i + 1)] $($certificates[$i].name) (ID: $($certificates[$i].id))"
        }

        # Get user selection for certificate
        $selection = Read-Host "`nEnter the number of the certificate to associate (or 'C' to cancel)"
        if ($selection -eq 'C') {
            Write-Host "Operation cancelled."
            pause
            return
        }

        $index = [int]$selection - 1
        if ($index -lt 0 -or $index -ge $certificates.Count) {
            Write-Host "Invalid selection."
            pause
            return
        }

        $certId = $certificates[$index].id
        $certName = $certificates[$index].name

        # Get hostname to associate
        $hostname = Read-Host "`nEnter the hostname to associate with this certificate (e.g., example.com)"
        if ([string]::IsNullOrWhiteSpace($hostname)) {
            Write-Host "Hostname cannot be empty."
            pause
            return
        }

        # Zone ID handling
        $zoneId = $configDict['ZONE_ID']
        $useConfigZoneId = $false

        if ($zoneId) {
            $useConfig = Read-Host "`nZone ID found in config.txt. Use this Zone ID? (Y/N)"
            $useConfigZoneId = $useConfig -eq 'Y'
        }

        if (-not $useConfigZoneId) {
            $zoneId = Read-Host "Enter the Zone ID"
            if ([string]::IsNullOrWhiteSpace($zoneId)) {
                Write-Host "Zone ID cannot be empty."
                pause
                return
            }
        }

        # Confirm the association
        Write-Host "`nPlease confirm the following:"
        Write-Host "Certificate: $certName (ID: $certId)"
        Write-Host "Hostname: $hostname"
        Write-Host "Zone ID: $zoneId"
        
        $confirm = Read-Host "`nProceed with this association? (Y/N)"
        if ($confirm -ne 'Y') {
            Write-Host "Operation cancelled."
            pause
            return
        }

        # Create the request body with the correct format and order
        $body = @{
            "mtls_certificate_id" = $certId  # Certificate UUID first
            "hostnames" = @($hostname)  # Array of hostnames second
        }

        # Create the request parameters
        $params = @{
            Uri = "https://api.cloudflare.com/client/v4/zones/$zoneId/certificate_authorities/hostname_associations"
            Method = 'PUT'
            Headers = $headers
            Body = ConvertTo-Json -InputObject $body -Depth 10 -Compress
        }

        Write-Host "`nAssociating certificate '$certName' with hostname '$hostname' in zone..."
        
        # Debug information
        Write-Host "`nDebug Information:"
        Write-Host "URI: $($params.Uri)"
        Write-Host "Method: $($params.Method)"
        Write-Host "Request Body:"
        Write-Host $params.Body

        # Make the request
        $associateResponse = Invoke-WebRequest @params
        $result = $associateResponse.Content | ConvertFrom-Json

        if ($result.success) {
            Write-Host "`nSuccessfully associated certificate with hostname"
            $result | ConvertTo-Json -Depth 4
        } else {
            Write-Host "`nFailed to associate certificate:"
            $result.errors | ForEach-Object {
                Write-Host "Error: $($_.message) (Code: $($_.code))"
            }
        }

    } catch {
        Write-Host "Failed to associate certificate."
        if ($_.Exception.Response) {
            $errorResponse = $_.Exception.Response
            $errorStream = $errorResponse.GetResponseStream()
            $streamReader = New-Object System.IO.StreamReader($errorStream)
            $errorMessage = $streamReader.ReadToEnd()
            Write-Host "Error Response: $errorMessage"
            Write-Host "Status Code: $($errorResponse.StatusCode.value__)"
            Write-Host "Status Description: $($errorResponse.StatusDescription)"
        } else {
            Write-Host "Error: $($_.Exception.Message)"
        }
    }
    pause
}

function Deassociate-Certificate {
    $configDict = Read-ConfigFile
    $accountId = $configDict['ACCOUNT_ID']

    # Get list of certificates first using the common headers
    $headers = Get-CloudflareHeaders -apiToken $configDict['API_TOKEN']

    try {
        # First, get all certificates
        $uri = "https://api.cloudflare.com/client/v4/accounts/$accountId/mtls_certificates"
        $response = Invoke-WebRequest -Uri $uri -Method Get -Headers $headers
        $certificates = ($response.Content | ConvertFrom-Json).result

        if ($certificates.Count -eq 0) {
            Write-Host "`nNo certificates found to deassociate."
            pause
            return
        }

        # Display certificates with numbers for selection
        Write-Host "`nAvailable certificates:"
        for ($i = 0; $i -lt $certificates.Count; $i++) {
            Write-Host "[$($i + 1)] $($certificates[$i].name) (ID: $($certificates[$i].id))"
        }

        # Get user selection for certificate with better validation
        do {
            $selection = Read-Host "`nEnter the number of the certificate to deassociate (1-$($certificates.Count), or 'C' to cancel)"
            if ($selection -eq 'C') {
                Write-Host "Operation cancelled."
                pause
                return
            }

            $validNumber = [int]::TryParse($selection, [ref]$null)
            $index = if ($validNumber) { [int]$selection - 1 } else { -1 }

            if (-not $validNumber -or $index -lt 0 -or $index -ge $certificates.Count) {
                Write-Host "Invalid selection. Please enter a number between 1 and $($certificates.Count)."
                continue
            }
            break
        } while ($true)

        $certId = $certificates[$index].id
        $certName = $certificates[$index].name

        # Zone ID handling
        $zoneId = $configDict['ZONE_ID']
        $useConfigZoneId = $false

        if ($zoneId) {
            $useConfig = Read-Host "`nZone ID found in config.txt. Use this Zone ID? (Y/N)"
            $useConfigZoneId = $useConfig -eq 'Y'
        }

        if (-not $useConfigZoneId) {
            $zoneId = Read-Host "Enter the Zone ID"
            if ([string]::IsNullOrWhiteSpace($zoneId)) {
                Write-Host "Zone ID cannot be empty."
                pause
                return
            }
        }

        # First, get current associations
        $associationsUri = "https://api.cloudflare.com/client/v4/zones/$zoneId/certificate_authorities/hostname_associations"
        $getResponse = Invoke-WebRequest -Uri $associationsUri -Method Get -Headers $headers
        $currentAssociations = ($getResponse.Content | ConvertFrom-Json).result

        Write-Host "`nCurrent associations:"
        Write-Host ($currentAssociations | ConvertTo-Json)

        # Confirm the deassociation
        Write-Host "`nPlease confirm the following:"
        Write-Host "Certificate: $certName (ID: $certId)"
        Write-Host "Zone ID: $zoneId"
        
        $confirm = Read-Host "`nProceed with deassociation? (Y/N)"
        if ($confirm -ne 'Y') {
            Write-Host "Operation cancelled."
            pause
            return
        }

        # Create the request body with empty hostnames array
        $body = @{
            "hostnames" = @()
            "mtls_certificate_id" = $certId
        }

        # Create the request parameters
        $params = @{
            Uri = $associationsUri
            Method = 'PUT'
            Headers = $headers
            Body = (ConvertTo-Json -InputObject $body -Depth 10 -Compress)
        }

        Write-Host "`nDeassociating certificate '$certName' from zone..."
        Write-Host "Request Body: $($params.Body)"
        
        # Make the request
        $deassociateResponse = Invoke-WebRequest @params
        $result = $deassociateResponse.Content | ConvertFrom-Json

        if ($result.success) {
            Write-Host "`nSuccessfully deassociated certificate" -ForegroundColor Green
            
            # Verify the deassociation
            $verifyResponse = Invoke-WebRequest -Uri $associationsUri -Method Get -Headers $headers
            $verifyResult = ($verifyResponse.Content | ConvertFrom-Json).result
            
            Write-Host "`nVerifying associations after deassociation:"
            Write-Host ($verifyResult | ConvertTo-Json)
            
            $result | ConvertTo-Json -Depth 4
        } else {
            Write-Host "`nFailed to deassociate certificate:" -ForegroundColor Red
            $result.errors | ForEach-Object {
                Write-Host "Error: $($_.message) (Code: $($_.code))" -ForegroundColor Red
            }
        }

    } catch {
        Write-Host "Failed to deassociate certificate."
        if ($_.Exception.Response) {
            $errorResponse = $_.Exception.Response
            $errorStream = $errorResponse.GetResponseStream()
            $streamReader = New-Object System.IO.StreamReader($errorStream)
            $errorMessage = $streamReader.ReadToEnd()
            Write-Host "Error Response: $errorMessage"
            Write-Host "Status Code: $($errorResponse.StatusCode.value__)"
            Write-Host "Status Description: $($errorResponse.StatusDescription)"
        } else {
            Write-Host "Error: $($_.Exception.Message)"
        }
    }
    pause
}

# Add the new function to view associations:
function Get-CertificateAssociations {
    $configDict = Read-ConfigFile
    $apiToken = $configDict['API_TOKEN']
    $accountId = $configDict['ACCOUNT_ID']

    # Get list of certificates first using the common headers
    $headers = Get-CloudflareHeaders -apiToken $apiToken

    try {
        # First, get all certificates
        $uri = "https://api.cloudflare.com/client/v4/accounts/$accountId/mtls_certificates"
        $response = Invoke-WebRequest -Uri $uri -Method Get -Headers $headers
        $certificates = ($response.Content | ConvertFrom-Json).result

        if ($certificates.Count -eq 0) {
            Write-Host "`nNo certificates found."
            pause
            return
        }

        # Display certificates with numbers for selection
        Write-Host "`nAvailable certificates:"
        for ($i = 0; $i -lt $certificates.Count; $i++) {
            Write-Host "[$($i + 1)] $($certificates[$i].name) (ID: $($certificates[$i].id))"
        }

        # Get user selection for certificate
        $selection = Read-Host "`nEnter the number of the certificate to view associations (or 'C' to cancel)"
        if ($selection -eq 'C') {
            Write-Host "Operation cancelled."
            pause
            return
        }

        $index = [int]$selection - 1
        if ($index -lt 0 -or $index -ge $certificates.Count) {
            Write-Host "Invalid selection."
            pause
            return
        }

        $certId = $certificates[$index].id
        $certName = $certificates[$index].name

        # Zone ID handling
        $zoneId = $configDict['ZONE_ID']
        $useConfigZoneId = $false

        if ($zoneId) {
            $useConfig = Read-Host "`nZone ID found in config.txt. Use this Zone ID? (Y/N)"
            $useConfigZoneId = $useConfig -eq 'Y'
        }

        if (-not $useConfigZoneId) {
            $zoneId = Read-Host "Enter the Zone ID"
            if ([string]::IsNullOrWhiteSpace($zoneId)) {
                Write-Host "Zone ID cannot be empty."
                pause
                return
            }
        }

        # Get the associations with certificate ID filter
        $uri = "https://api.cloudflare.com/client/v4/zones/$zoneId/certificate_authorities/hostname_associations?mtls_certificate_id=$certId"
        
        Write-Host "`nRetrieving CA hostname associations for certificate '$certName'..."
        Write-Host "URI: $uri"
        
        $response = Invoke-WebRequest -Uri $uri -Method Get -Headers $headers
        $result = ($response.Content | ConvertFrom-Json)

        if ($result.success) {
            Write-Host "`nCA Hostname Associations for certificate '$certName':"
            Write-Host "----------------------------------------"
            
            if ($null -ne $result.result -and $null -ne $result.result.hostnames) {
                Write-Host "Hostnames:"
                foreach ($hostname in $result.result.hostnames) {
                    Write-Host "  - $hostname"
                }
                Write-Host "mTLS Certificate ID: $certId"
            } else {
                Write-Host "No hostname associations found for this certificate."
            }
            Write-Host "----------------------------------------"
        } else {
            Write-Host "`nFailed to retrieve CA associations:"
            $result.errors | ForEach-Object {
                Write-Host "Error: $($_.message) (Code: $($_.code))"
            }
        }

    } catch {
        Write-Host "Failed to retrieve CA hostname associations."
        if ($_.Exception.Response) {
            $errorResponse = $_.Exception.Response
            $errorStream = $errorResponse.GetResponseStream()
            $streamReader = New-Object System.IO.StreamReader($errorStream)
            $errorMessage = $streamReader.ReadToEnd()
            Write-Host "Error Response: $errorMessage"
            Write-Host "Status Code: $($errorResponse.StatusCode.value__)"
            Write-Host "Status Description: $($errorResponse.StatusDescription)"
        } else {
            Write-Host "Error: $($_.Exception.Message)"
        }
    }
    pause
}

# Read and parse the config file
$configDict = Read-ConfigFile

# Extract values from config
$apiToken = $configDict['API_TOKEN']
$accountId = $configDict['ACCOUNT_ID']
$caCertPath = $configDict['CA_CERT_PATH']

# Validate CA certificate path
if (-Not (Test-Path -Path $caCertPath)) {
    Write-Host "CA certificate not found at path: $caCertPath"
    exit
}

# Read the CA certificate content and ensure proper formatting
try {
    # Read certificate content
    $caCertContent = Get-Content -Path $caCertPath -Raw
    
    # Clean and format the certificate content
    $caCertContent = $caCertContent.Trim()
    
    # Create the request body with the raw certificate content
    $body = @{
        "ca" = $true
        "certificates" = $caCertContent
        "name" = "example_ca_cert"
    }

    # Convert the body to JSON with special handling for newlines
    $jsonBody = ConvertTo-Json -InputObject $body -Depth 10 -Compress
    
    # Debug: Show the JSON body
    Write-Host "`nJSON Body:"
    Write-Host $jsonBody
    
} catch {
    Write-Host "Error reading CA certificate: $_"
    exit
}

# Define the API endpoint for uploading the mTLS CA
$uri = "https://api.cloudflare.com/client/v4/accounts/$accountId/mtls_certificates"

# Set up the headers for the API request
$headers = Get-CloudflareHeaders -apiToken $apiToken

# Debug information
Write-Host "=== Debug Information ==="
Write-Host "Headers:"
$headers.GetEnumerator() | ForEach-Object {
    Write-Host "  $($_.Key): $(if ($_.Key -eq 'Authorization') {'Bearer [HIDDEN]'} else {$_.Value})"
}
Write-Host "Account ID: $accountId"
Write-Host "Certificate Path: $caCertPath"
Write-Host "Certificate Content Length: $($caCertContent.Length)"
Write-Host "Request Body Length: $($jsonBody.Length)"
Write-Host "Request URL: $uri"
Write-Host "======================="

# Main menu loop
do {
    Show-Menu
    $selection = Read-Host "Please make a selection"
    
    switch ($selection) {
        '1' {
            Upload-Certificate
        }
        '2' {
            Associate-Certificate
        }
        '3' {
            Remove-Certificate
        }
        '4' {
            Get-Certificates
        }
        '5' {
            Deassociate-Certificate
        }
        '6' {
            Get-CertificateAssociations
        }
        '7' {
            Write-Host "Exiting..."
            return
        }
        default {
            Write-Host "Invalid selection. Please try again."
            pause
        }
    }
} while ($selection -ne '7')
