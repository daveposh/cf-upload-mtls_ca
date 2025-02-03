# Cloudflare mTLS Worker with Custom CA

This project implements a Cloudflare Worker that forwards client certificate details to origin servers using Nginx-style headers.

## Prerequisites

- Cloudflare Account with Access to:
  - SSL/TLS Configuration
  - Workers
  - WAF Rules
- Node.js and npm installed
- Your own Certificate Authority (CA)

## Setup Steps

### 1. Configure Cloudflare mTLS

1. Go to SSL/TLS > Client Certificates in your Cloudflare dashboard
2. Enable Client Certificate Verification
3. Upload your CA Certificate:
   ```bash
   # Convert your CA cert to PEM format if needed
   openssl x509 -in your-ca.crt -out your-ca.pem -outform PEM
   ```
4. Set Client Certificate Verification mode to "Required"

### 2. Create WAF Rule

1. Navigate to Security > WAF
2. Create a new Custom Rule:
   ```
   Rule Name: Require Client Certificate
   Expression: not cf.tls_client_auth.cert_verified
   Action: Block
   ```
   This blocks requests without valid client certificates.

### 3. Install and Configure Wrangler

1. Install Wrangler globally:
   ```bash
   npm install -g wrangler
   ```

2. Authenticate with Cloudflare:
   ```bash
   wrangler login
   ```

3. Create project structure:
   ```bash
   mkdir mtls-worker
   cd mtls-worker
   ```

4. Create `wrangler.toml`:
   ```toml
   name = "mtls_client_cert_details_nginx_formated_headers"
   main = "src/index.js"
   compatibility_date = "2024-01-01"

   routes = ["your-domain.com/*"]  # Replace with your domain
   ```

### 4. Implement the Worker

Create `src/index.js`:
```javascript
addEventListener('fetch', event => {
  event.respondWith(handleRequest(event.request))
})

async function handleRequest(request) {
  // Clone the request to modify headers
  let modifiedRequest = new Request(request.url, {
    method: request.method,
    headers: request.headers,
    body: request.body,
    cf: request.cf
  })

  // Get TLS certificate details from request.cf
  const clientCertInfo = request.cf

  // Add Nginx-style SSL headers
  const newHeaders = new Headers(modifiedRequest.headers)
  
  // SSL Protocol version
  if (clientCertInfo.tlsVersion) {
    newHeaders.set('ssl-protocol', clientCertInfo.tlsVersion)
  }

  // SSL Cipher
  if (clientCertInfo.tlsCipher) {
    newHeaders.set('ssl-cipher', clientCertInfo.tlsCipher)
  }

  // Client certificate verification status
  newHeaders.set('ssl-verify', 'SUCCESS')

  // Client certificate details if available
  if (clientCertInfo.tlsClientAuth) {
    if (clientCertInfo.tlsClientAuth.certIssuerDN) {
      newHeaders.set('ssl-client-i-dn', clientCertInfo.tlsClientAuth.certIssuerDN)
    }
    if (clientCertInfo.tlsClientAuth.certSubjectDN) {
      newHeaders.set('ssl-client-s-dn', clientCertInfo.tlsClientAuth.certSubjectDN)
    }
    if (clientCertInfo.tlsClientAuth.certNotBefore) {
      newHeaders.set('ssl-client-not-before', clientCertInfo.tlsClientAuth.certNotBefore)
    }
    if (clientCertInfo.tlsClientAuth.certNotAfter) {
      newHeaders.set('ssl-client-not-after', clientCertInfo.tlsClientAuth.certNotAfter)
    }
  }

  // Create new request with modified headers
  const finalRequest = new Request(request.url, {
    method: request.method,
    headers: newHeaders,
    body: request.body
  })

  // Forward the request to the origin
  return fetch(finalRequest)
}
```

### 5. Deploy the Worker

```bash
wrangler deploy
```

## Testing

1. Generate a client certificate signed by your CA:
   ```bash
   # Generate private key
   openssl genrsa -out client.key 2048

   # Generate CSR
   openssl req -new -key client.key -out client.csr

   # Sign with your CA
   openssl x509 -req -in client.csr -CA your-ca.crt -CAkey your-ca.key -CAcreateserial -out client.crt -days 365
   ```

2. Test with curl:
   ```bash
   curl --cert client.crt --key client.key https://your-domain.com
   ```

## Headers Added by Worker

The worker adds the following Nginx-style headers to requests:
- `ssl-protocol`: TLS version used
- `ssl-cipher`: Cipher suite used
- `ssl-verify`: Certificate verification status
- `ssl-client-i-dn`: Client certificate issuer DN
- `ssl-client-s-dn`: Client certificate subject DN
- `ssl-client-not-before`: Certificate validity start date
- `ssl-client-not-after`: Certificate validity end date

## Security Considerations

- Keep your CA private key secure
- Regularly rotate client certificates
- Monitor WAF logs for unauthorized access attempts
- Consider implementing certificate revocation checks
- Ensure proper access controls for your CA infrastructure
- Review and update WAF rules periodically
- Monitor Cloudflare logs for any unusual patterns

## Implementation Options

### Option 1: Using Workers (as shown above)

The Worker implementation above provides full programmatic control over header manipulation and request processing.

### Option 2: Using Transform Rules

You can alternatively use Cloudflare Transform Rules to add certificate headers without deploying a Worker:

1. Go to Rules > Transform Rules in your Cloudflare dashboard
2. Click "Create Transform Rule"
3. Configure the rule:
   ```
   Rule Name: mTLS Certificate Headers
   When incoming requests match...
     Hostname: your-domain.com
   Then...
   Add the following response headers:
     ssl-protocol: http.tls_version
     ssl-cipher: http.tls_cipher
     ssl-client-i-dn: cf.tls_client_auth.cert_issuer_dn
     ssl-client-s-dn: cf.tls_client_auth.cert_subject_dn
     ssl-client-not-before: cf.tls_client_auth.cert_not_before
     ssl-client-not-after: cf.tls_client_auth.cert_not_after
     ssl-verify: "SUCCESS"
   ```

Advantages of Transform Rules:
- No code to maintain
- Lower latency
- Simpler configuration
- No Worker usage costs

Choose the implementation that best fits your needs based on:
- Required customization
- Performance requirements
- Maintenance preferences
- Cost considerations

## API Reference

### List Certificates
```bash
curl -X GET "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/mtls_certificates" \
  -H "Authorization: Bearer ${API_TOKEN}"
```

### Upload CA Certificate
```bash
curl -X POST "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/mtls_certificates" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  -H "Content-Type: application/json" \
  --data '{
    "name": "My Private CA",
    "certificates": "'$(cat your-ca.base64)'",
    "ca": true
  }'
```

### Associate CA with Zone
```bash
curl -X PUT "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/mtls_certificates" \
  -H "X-Auth-Email: ${EMAIL}" \
  -H "X-Auth-Key: ${GLOBAL_API_KEY}" \
  -H "Content-Type: application/json" \
  --data '{
    "ca": "'${CA_ID}'",
    "enabled": true,
    "hostname": "your-domain.com"
  }'
```

### Remove Association
```bash
curl -X PUT "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/mtls_certificates" \
  -H "X-Auth-Email: ${EMAIL}" \
  -H "X-Auth-Key: ${GLOBAL_API_KEY}" \
  -H "Content-Type: application/json" \
  --data '{
    "ca": "'${CA_ID}'",
    "enabled": true,
    "hostname": ""
  }'
```

### Delete Certificate
```bash
# Note: Certificate must not be associated with any zone
curl -X DELETE "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/mtls_certificates/${MTLS_CERTIFICATE_ID}" \
  -H "Authorization: Bearer ${API_TOKEN}"
```

### API Payload Reference

#### Upload Certificate Payload
```json
{
  "name": "string (optional)",     // Human readable name
  "certificates": "string",        // Base64 encoded PEM certificate
  "ca": true                      // true for CA certificate, false for leaf
}
```

#### Association Payload
```json
{
  "ca": "string",                 // CA ID from upload response
  "enabled": true,                // Enable/disable mTLS
  "hostname": "string"            // Domain to associate, or "" to remove
}
```

### Important Notes
- Certificate deletion requires removing association first
- Global API Key is required for association/disassociation
- API Token can be used for all other operations
- Only one CA can be associated with a hostname at a time
- Changes may take up to 5 minutes to propagate











