# Pyroscope Deployment

This directory contains the Helm chart configuration for deploying Grafana Pyroscope, a continuous profiling platform.

## Overview

Pyroscope is deployed in microservices mode with the following components:

- **Querier**: Handles query requests
- **Query Frontend**: Query routing and caching
- **Query Scheduler**: Coordinates query execution
- **Distributor**: Receives incoming profile data
- **Ingester**: Writes profile data to storage (with WAL)
- **Compactor**: Compacts and optimizes stored data
- **Store Gateway**: Serves queries from long-term storage

## Authentication

Pyroscope is secured using Kong as a reverse proxy with NGINX-based basic authentication. See [AUTHENTICATION.md](./AUTHENTICATION.md) for detailed setup instructions.

### Quick Start

1. The gateway handles authentication via `.htpasswd` stored in `pyroscope-secret`
2. Access Pyroscope via the Kong ingress endpoints:
   - Dev: `https://pyroscope-dev-<region>.sitecorecloud.app`
   - Staging: `https://pyroscope-staging-<region>.sitecorecloud.app`
   - Production: `https://pyroscope-prod-<region>.sitecorecloud.app`

## Files

- `values.yaml`: Base Helm values configuration
- `helm-release.yaml`: FluxCD HelmRelease definition
- `helm-repo.yaml`: Helm repository definition
- `kustomization.yaml`: Kustomize configuration
- `namespace.yaml`: Namespace definition
- `AUTHENTICATION.md`: Detailed authentication setup guide

## Storage

Pyroscope uses Azure Blob Storage as the backend storage. Configuration is provided via environment variables in the `pyroscope-secret`:

- `AZURE_ACCOUNT_NAME`: Storage account name
- `AZURE_ACCOUNT_KEY`: Storage account key
- `AZURE_CONTAINER_NAME`: Container name for profile data

## Regional Configuration

Regional configurations can be found in the `regions/<region>/<env>/` directories:

- `helm-values-pyroscope-stack-regional.yaml`: Region-specific Helm values
- `pyroscope-secret.yaml`: Encrypted secret with storage and auth credentials

## Monitoring

Pyroscope components are monitored via:

- **ServiceMonitor**: Prometheus scraping configuration (enabled by default)
- **Self-profiling**: Pyroscope profiles itself (see pod annotations in values.yaml)

## Deployment

Deployment is managed via FluxCD GitOps. Changes to configuration files are automatically applied by Flux.

To manually apply changes:

```bash
# For dev environment
kubectl apply -k regions/euw/dev/

# For staging environment
kubectl apply -k regions/euw/staging/
```

## Resources

- [Grafana Pyroscope Documentation](https://grafana.com/docs/pyroscope/latest/)
- [Pyroscope Helm Chart](https://github.com/grafana/pyroscope/tree/main/operations/pyroscope/helm/pyroscope)
- [Authentication Setup Guide](./AUTHENTICATION.md)

## Support

For questions or issues:
- Slack: [#ask-observability](https://sitecore.slack.com/archives/C03JUSXFA9K)
- Email: [ObservabilityEnablement@sitecore.com](mailto:ObservabilityEnablement@sitecore.com)
