# Pyroscope Authentication Setup

This document describes the authentication setup for Pyroscope using Kong as a reverse proxy with basic authentication.

## Overview

Pyroscope does not natively support HTTP basic authentication. To secure access to Pyroscope, we use Kong as a reverse proxy with an NGINX gateway that handles authentication using htpasswd-based basic auth.

This approach is consistent with the Loki authentication setup in this repository.

## Architecture

```
Client → Kong Ingress (HTTPS) → NGINX Gateway (Basic Auth) → Pyroscope Service
```

### Components

1. **Kong Ingress Controller**: Handles external HTTPS traffic and routes to the gateway service
2. **NGINX Gateway**: Performs basic authentication using `.htpasswd` file
3. **Pyroscope Service**: The actual Pyroscope application

## Configuration

### Gateway Configuration

The gateway is configured in `values.yaml` with the following key settings:

- **Image**: `nginxinc/nginx-unprivileged:1.27-alpine`
- **Basic Auth**: Enabled via `.htpasswd` file
- **Service Annotations**: Kong timeout settings (600 seconds)
- **Ingress**: Kong ingress with HTTPS redirect

### Secret Structure

Authentication credentials are stored in the `pyroscope-secret` Kubernetes Secret with the following fields:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: pyroscope-secret
  namespace: oe-pyroscope
type: Opaque
data:
  AZURE_ACCOUNT_KEY: <base64-encoded>
  AZURE_ACCOUNT_NAME: <base64-encoded>
  AZURE_CONTAINER_NAME: <base64-encoded>
  .htpasswd: <base64-encoded htpasswd content>
```

The `.htpasswd` field contains bcrypt-hashed credentials for basic authentication.

## Setup Instructions

### 1. Generate htpasswd Credentials

Use the `htpasswd` utility to generate credentials:

```bash
# Install htpasswd (if not already installed)
# On macOS:
brew install httpd

# On Ubuntu/Debian:
sudo apt-get install apache2-utils

# Generate htpasswd entry
htpasswd -nb <username> <password>
```

This will output a line like:
```
username:$apr1$....
```

### 2. Update the Secret

For each environment (dev, staging, prod), update the `pyroscope-secret.yaml` file in the respective region directory:

**Example for dev environment:**
```bash
# Navigate to the region directory
cd regions/euw/dev/

# Edit the secret using SOPS (if using encrypted secrets)
sops pyroscope-secret.yaml

# Add the .htpasswd field with the generated htpasswd content
# The content should be base64 encoded
```

**Example structure:**
```yaml
data:
  .htpasswd: <base64-encoded htpasswd line>
```

To base64 encode your htpasswd line:
```bash
echo -n 'username:$apr1$....' | base64
```

### 3. Update Kustomization

Ensure the kustomization file includes the `.htpasswd` literal in the secretGenerator:

```yaml
secretGenerator:
  - name: pyroscope-secret
    namespace: oe-pyroscope
    literals:
      - AZURE_ACCOUNT_KEY=changeme
      - AZURE_ACCOUNT_NAME=changeme
      - AZURE_CONTAINER_NAME=changeme
      - .htpasswd=changeme  # Add this line
    options:
      disableNameSuffixHash: true
```

### 4. Deploy Changes

Deploy the updated configuration using your deployment pipeline or manually with kubectl:

```bash
# Apply kustomization
kubectl apply -k regions/euw/dev/

# Verify the gateway is running
kubectl get pods -n oe-pyroscope -l app.kubernetes.io/component=gateway

# Check gateway logs
kubectl logs -n oe-pyroscope -l app.kubernetes.io/component=gateway
```

## Accessing Pyroscope

### Via Web Browser

Access Pyroscope using the configured ingress hostname:

- **Dev**: `https://pyroscope-dev-<region>.sitecorecloud.app` or `https://pyroscope-dev-<region>.sitecorecloud.io`
- **Staging**: `https://pyroscope-staging-<region>.sitecorecloud.app` or `https://pyroscope-staging-<region>.sitecorecloud.io`
- **Production**: `https://pyroscope-prod-<region>.sitecorecloud.app` or `https://pyroscope-prod-<region>.sitecorecloud.io`

When prompted, enter the username and password configured in the `.htpasswd` file.

### Via API/CLI

Use basic authentication with curl or other HTTP clients:

```bash
# Example: Query Pyroscope API
curl -u username:password https://pyroscope-dev-euw.sitecorecloud.app/api/apps

# Example: Push profiles with authentication
curl -u username:password \
  -X POST \
  -H "Content-Type: application/json" \
  -d @profile.json \
  https://pyroscope-dev-euw.sitecorecloud.app/ingest
```

### Via Grafana Data Source

When configuring Pyroscope as a data source in Grafana:

1. Set the URL to your Pyroscope ingress endpoint
2. Enable "Basic auth" in the authentication section
3. Enter the username and password

Example configuration:
```yaml
datasources:
  - name: Pyroscope
    type: grafana-pyroscope-datasource
    url: https://pyroscope-dev-euw.sitecorecloud.app
    basicAuth: true
    basicAuthUser: <username>
    secureJsonData:
      basicAuthPassword: <password>
```

## Security Considerations

1. **Password Strength**: Use strong, randomly generated passwords for production environments
2. **Secret Management**: All secrets are encrypted using SOPS with Azure Key Vault
3. **HTTPS Only**: Kong ingress is configured to redirect HTTP to HTTPS (301 redirect)
4. **Timeout Settings**: Kong timeout settings are configured for long-running queries (600 seconds)
5. **Gateway Isolation**: The gateway runs in a separate container with minimal privileges

## Troubleshooting

### Authentication Failures

1. **Check gateway logs**:
   ```bash
   kubectl logs -n oe-pyroscope -l app.kubernetes.io/component=gateway
   ```

2. **Verify secret contents**:
   ```bash
   kubectl get secret pyroscope-secret -n oe-pyroscope -o yaml
   ```

3. **Test .htpasswd file**:
   ```bash
   # Decode the .htpasswd from the secret
   kubectl get secret pyroscope-secret -n oe-pyroscope -o jsonpath='{.data.\.htpasswd}' | base64 -d
   
   # Verify the htpasswd works locally
   echo "username:password" | htpasswd -v /path/to/.htpasswd username
   ```

### Gateway Not Starting

1. **Check pod status**:
   ```bash
   kubectl get pods -n oe-pyroscope -l app.kubernetes.io/component=gateway
   kubectl describe pod <gateway-pod-name> -n oe-pyroscope
   ```

2. **Verify ConfigMap**:
   ```bash
   kubectl get configmap -n oe-pyroscope
   kubectl describe configmap <nginx-config-map> -n oe-pyroscope
   ```

### Connection Timeouts

If experiencing timeout issues:

1. Check Kong service annotations are properly set
2. Verify NGINX configuration timeout settings
3. Check backend Pyroscope service is responding

```bash
# Test direct connection to Pyroscope (without authentication)
kubectl port-forward -n oe-pyroscope svc/pyroscope 4040:4040
curl http://localhost:4040/ready
```

## Comparison with Loki Authentication

This Pyroscope authentication setup mirrors the Loki implementation:

| Aspect | Loki | Pyroscope |
|--------|------|-----------|
| Ingress Controller | Kong | Kong |
| Gateway | NGINX Unprivileged | NGINX Unprivileged |
| Auth Method | Basic Auth (htpasswd) | Basic Auth (htpasswd) |
| Secret Name | loki-secret | pyroscope-secret |
| Namespace | oe-loki | oe-pyroscope |
| Timeout Settings | 600s | 600s |
| HTTPS Redirect | 301 | 301 |

## References

- [Grafana Pyroscope Documentation](https://grafana.com/docs/pyroscope/latest/)
- [Kong Ingress Controller](https://docs.konghq.com/kubernetes-ingress-controller/)
- [NGINX Basic Authentication](https://docs.nginx.com/nginx/admin-guide/security-controls/configuring-http-basic-authentication/)
- [Apache htpasswd](https://httpd.apache.org/docs/2.4/programs/htpasswd.html)
