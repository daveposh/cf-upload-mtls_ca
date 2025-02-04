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

2. Copy `config.example.txt` to `config.txt` and update with your values:
   ```txt
   API_TOKEN=your_api_token_here
   AUTH_EMAIL=your.email@example.com
   ACCOUNT_ID=your_account_id
   CA_CERT_PATH=C:\path\to\your\custom_ca.crt
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

The script will:
1. Read the configuration file
2. Upload the CA certificate to Cloudflare
3. Allow you to associate the certificate with specific zones and hostnames

## Configuration File

- `API_TOKEN`: Your Cloudflare API Token
- `AUTH_EMAIL`: Your Cloudflare account email
- `ACCOUNT_ID`: Your Cloudflare Account ID
- `CA_CERT_PATH`: Full path to your CA certificate file
- `CERT_NAME`: (Optional) Custom name for your certificate
- `ZONE_ID`: (Optional) Specific Zone ID to work with

## Notes

- The script supports uploading and associating CA certificates
- Certificates can be associated with multiple zones and hostnames
- All operations use secure API Token authentication

## Error Handling

The script includes comprehensive error handling and validation:
- Validates all required configuration values
- Verifies certificate file existence
- Confirms operations before execution
- Provides detailed error messages
- Verifies successful completion of operations

## Security Notes

- Store your API Token securely
- Never share your config.txt file
- Use environment-specific certificates
- Follow the principle of least privilege when creating API tokens

## Troubleshooting

If you encounter issues:

1. Verify your API Token has the correct permissions
2. Ensure your Account ID and Zone ID are correct
3. Check that your CA certificate is in valid PEM format
4. Look for detailed error messages in the script output

## Common Errors

- 404 Not Found: Usually indicates incorrect Account ID or Zone ID
- 403 Forbidden: Typically means insufficient API Token permissions
- 400 Bad Request: Often related to invalid certificate format or request body

## Support

For issues with the script, please:
1. Check the error messages
2. Verify your configuration
3. Ensure your Cloudflare account has mTLS capabilities enabled
