# Steps to Complete on Office Machine

This file contains the commands to run on your office machine (with Azure Key Vault access) to complete the Pyroscope authentication setup.

## Prerequisites

Ensure you have these tools installed:
- `git`
- `sops` (install with: `brew install sops` or appropriate package manager)
- `htpasswd` (install with: `brew install httpd` on macOS, or `sudo apt-get install apache2-utils` on Linux)
- `az` (Azure CLI - install with: `brew install azure-cli` on macOS)

## Step-by-Step Instructions

### 1. Pull the Latest Changes

```bash
cd /path/to/your/workspace/sitecore.oe.observability-main

# Fetch and checkout the authentication branch
git fetch origin
git checkout authentication
git pull origin authentication
```

### 2. Authenticate with Azure

```bash
# Login to Azure
az login

# Verify you have access to the Key Vault
az keyvault show --name global-e1-sopskv-01
```

### 3. Generate htpasswd Credentials for Dev Environment

```bash
# Generate htpasswd for dev environment
# Replace <username> and <password> with your desired credentials
htpasswd -nb <username> <password>

# Example:
# htpasswd -nb pyroscope-user MySecureP@ssw0rd123

# Save the output - it will look like:
# pyroscope-user:$2y$05$abcdefghijklmnopqrstuvwxyz1234567890...
```

### 4. Encrypt Dev Secret

```bash
# Edit the dev secret with SOPS
sops regions/euw/dev/pyroscope-secret.yaml

# In the editor that opens:
# 1. Find the line:
#    .htpasswd: ENC[AES256_GCM,data:changeme_htpasswd_will_be_encrypted_by_sops,iv:changeme,tag:changeme,type:str]
#
# 2. Replace it with your htpasswd output (WITHOUT the ENC wrapper):
#    .htpasswd: pyroscope-user:$2y$05$abcdefghijklmnopqrstuvwxyz1234567890...
#
# 3. Save and exit (SOPS will automatically encrypt it)
```

### 5. Generate htpasswd Credentials for Staging Environment

```bash
# Generate htpasswd for staging environment
# You can use the same or different credentials from dev
htpasswd -nb <username> <password>

# Save the output
```

### 6. Encrypt Staging Secret

```bash
# Edit the staging secret with SOPS
sops regions/euw/staging/pyroscope-secret.yaml

# Replace the .htpasswd placeholder with your htpasswd output
# Save and exit
```

### 7. Verify Encryption

```bash
# Check that the secrets are properly encrypted
# The .htpasswd field should now look like:
# .htpasswd: ENC[AES256_GCM,data:xyz123...,iv:abc456...,tag:def789...,type:str]

# View dev secret
cat regions/euw/dev/pyroscope-secret.yaml | grep -A 1 "\.htpasswd"

# View staging secret
cat regions/euw/staging/pyroscope-secret.yaml | grep -A 1 "\.htpasswd"

# Make sure you DON'T see "changeme" in the output
```

### 8. Commit and Push Encrypted Secrets

```bash
# Stage only the secret files
git add regions/euw/dev/pyroscope-secret.yaml regions/euw/staging/pyroscope-secret.yaml

# Commit the encrypted credentials
git commit -m "chore: encrypt Pyroscope authentication credentials with SOPS

- Added encrypted .htpasswd for dev environment
- Added encrypted .htpasswd for staging environment
- Credentials encrypted using Azure Key Vault (global-e1-sopskv-01)"

# Push to GitHub
git push origin authentication
```

### 9. Verify the Changes

```bash
# Check the latest commit
git log -1 --stat

# Verify the secrets are encrypted by viewing them
git show HEAD:regions/euw/dev/pyroscope-secret.yaml | grep "\.htpasswd"
```

## Troubleshooting

### If `sops` fails with "Failed to get the data key"

This means you don't have access to the Azure Key Vault. Contact the observability team:
- Slack: [#ask-observability](https://sitecore.slack.com/archives/C03JUSXFA9K)
- Email: ObservabilityEnablement@sitecore.com

### If `htpasswd` is not found

Install it:
- **macOS**: `brew install httpd`
- **Ubuntu/Debian**: `sudo apt-get install apache2-utils`
- **Red Hat/CentOS**: `sudo yum install httpd-tools`

### If Azure CLI authentication fails

Make sure you're logged in with an account that has access to the `global-e1-sopskv-01` Key Vault.

## What Happens Next?

After pushing the encrypted credentials:

1. The changes will be in the `authentication` branch
2. You (or your team) can review the changes and create a Pull Request to merge into the main branch
3. Once merged and deployed, Pyroscope will require authentication via the credentials you set
4. Access Pyroscope at:
   - Dev: `https://pyroscope-dev-euw.sitecorecloud.app`
   - Staging: `https://pyroscope-staging-euw.sitecorecloud.app`

## Security Notes

- **Never commit unencrypted credentials** to the repository
- **Use strong passwords** for production environments
- **Store credentials securely** - consider using a password manager
- The `.htpasswd` file uses bcrypt hashing for secure password storage
- All secrets are encrypted at rest using Azure Key Vault encryption

## Reference Documentation

See `pyroscope/AUTHENTICATION.md` for complete authentication documentation.
