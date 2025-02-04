# Cloudflare mTLS CA Certificate Manager

A PowerShell script for managing Cloudflare mTLS (mutual TLS) CA certificates. This tool allows you to upload, associate, deassociate, and delete CA certificates for your Cloudflare account.

## Features

- Upload new CA certificates
- Associate certificates with zones/hostnames
- Delete existing certificates
- View all certificates
- Deassociate certificates from zones
- View certificate associations

## Prerequisites

- PowerShell 5.1 or higher
- Cloudflare API Token with the following permissions:
  - Access: mTLS Certificates (Edit)
  - Zone: SSL and Certificates (Edit)

## Configuration

Create a `config.txt` file in the same directory as the script with the following content:

```plaintext
# Cloudflare API Token (Required for all operations)
API_TOKEN=your_api_token_here

# Cloudflare Account ID (Found in the URL when viewing your account or in Account Settings)
ACCOUNT_ID=your_account_id_here

# Path to your CA certificate file
CA_CERT_PATH=path_to_your_ca_cert.crt

# Optional: Zone ID (If not provided, will be prompted when needed)
# ZONE_ID=your_zone_id_here
```

## Usage

Run the script using PowerShell:

```powershell
.\Upload-CloudFlareCACert.ps1
```

The script provides a menu-driven interface with the following options:

1. Upload new CA certificate
2. Associate CA certificate with zone
3. Delete CA certificate
4. View certificates
5. Deassociate CA certificate
6. View certificate associations
7. Exit

### Quick Delete Mode

You can also run the script in delete mode:

```powershell
.\Upload-CloudFlareCACert.ps1 -Delete
```

This will directly open the certificate deletion interface.

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
