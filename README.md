# Cloudflare MTLS Certificate Upload Tool

A PowerShell script for uploading and managing mTLS CA certificates to Cloudflare.

## Prerequisites

- PowerShell 5.1 or higher
- A Cloudflare account with API Token access
- A valid CA certificate file (.crt format)

## Setup

1. Create an API Token in Cloudflare dashboard (https://dash.cloudflare.com/profile/api-tokens) with the following permissions:
   - Zone.SSL and Certificates (Edit)
   - Zone.Zone (Read)
   - Account.mTLS Certificates (Edit)
   - Account Settings (Read)

2. Copy `config.example.txt` to `config.txt` and update with your values:
   ```txt
   API_TOKEN=your_api_token_here
   AUTH_EMAIL=your.email@example.com
   ACCOUNT_ID=your_account_id
   CA_CERT_PATH=C:\path\to\your\custom_ca.crt
   ZONE_ID=your_zone_id_here
   CERT_NAME=your_certificate_name
   ```

## Usage

Run the script with:
```powershell
.\Upload-CloudFlareCACert.ps1
```

Optional parameters:
```powershell
.\Upload-CloudFlareCACert.ps1 -ConfigPath "path\to\your\config.txt"
```

The script provides the following options:
1. Upload a new CA certificate
2. List all certificates
3. Delete a certificate
4. View certificate details
5. Associate certificate with hostname
6. View certificate associations

### Certificate Management
- Upload new certificates with custom names
- List all certificates in your account
- View detailed certificate information
- Delete unwanted certificates

### Hostname Associations
- Associate certificates with specific hostnames
- View existing hostname associations
- Append new hostnames to existing associations
- Override existing hostname associations
- Automatic validation of hostname associations

## Configuration File

- `API_TOKEN`: Your Cloudflare API Token
- `AUTH_EMAIL`: Your Cloudflare account email
- `ACCOUNT_ID`: Your Cloudflare Account ID
- `CA_CERT_PATH`: Full path to your CA certificate file
- `CERT_NAME`: (Optional) Custom name for your certificate
- `ZONE_ID`: (Optional) Specific Zone ID to work with

## Certificate Association Features

When associating certificates with hostnames:
1. View existing associations for any certificate
2. Add new hostname associations with options to:
   - Append to existing hostname list
   - Override existing hostname associations
3. Automatic verification of successful associations
4. Protection against duplicate hostname associations

## Notes

- The script supports uploading and associating CA certificates
- Certificates can be associated with multiple zones and hostnames
- All operations use secure API Token authentication
- Hostname associations are maintained across sessions
- Automatic validation prevents duplicate associations

## Error Handling

The script includes comprehensive error handling and validation:
- Validates all required configuration values
- Verifies certificate file existence
- Confirms operations before execution
- Provides detailed error messages
- Verifies successful completion of operations
- Validates hostname associations

## Security Notes

- Store your API Token securely
- Never share your config.txt file
- Use environment-specific certificates
- Follow the principle of least privilege when creating API tokens
- Verify hostname associations before production use

## Troubleshooting

If you encounter issues:

1. Verify your API Token has the correct permissions
2. Ensure your Account ID and Zone ID are correct
3. Check that your CA certificate is in valid PEM format
4. Look for detailed error messages in the script output
5. Verify hostname associations using the view option

## Common Errors

- 404 Not Found: Usually indicates incorrect Account ID or Zone ID
- 403 Forbidden: Typically means insufficient API Token permissions
- 400 Bad Request: Often related to invalid certificate format or request body
- Duplicate hostname: Attempting to associate an already associated hostname

## Support

For issues with the script, please:
1. Check the error messages
2. Verify your configuration
3. Ensure your Cloudflare account has mTLS capabilities enabled
4. Verify hostname associations are correctly configured
