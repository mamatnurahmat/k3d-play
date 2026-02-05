# Rancher Installation Guide

This guide details the steps to install Rancher on a local K3d cluster using ArgoCD, Gateway API, and Cert-Manager.

## Prerequisites

-   **Docker**: Running.
-   **K3d**: Installed.
-   **Kubectl**: Installed.
-   **ArgoCD CLI** (optional): For checking app status.

## 1. Cluster Setup

Ensure your K3d cluster is created with the necessary port mappings (8443) as defined in `k3d-config.yaml`.

```bash
k3d cluster create --config k3d-config.yaml
```

*Note: Port 8443 on localhost is mapped to the internal NodePort 30443 (HTTPS).*

## 2. Infrastructure Components

Ensure the following core components are installed via GitOps (ArgoCD):
-   **Cert-Manager**: For certificate management.
-   **NGINX Gateway Fabric**: For handling ingress traffic via Gateway API.

## 3. Gateway Configuration

Configure the Gateway to handle `*.localhost` traffic and use a shared TLS certificate.

**File**: `manifests/infra/gateway.yaml`

```yaml
spec:
  listeners:
  - name: https
    port: 443
    hostname: "*.localhost" # Important for matching subdomains
    tls:
      mode: Terminate
      certificateRefs:
      - name: localhost-tls
```

Apply the changes:
```bash
kubectl apply -f manifests/infra/gateway.yaml
```

## 4. Local TLS Certificate

Create a self-signed certificate for `*.localhost` to be used by the Gateway.

**File**: `manifests/certs/localhost-cert.yaml`

```bash
kubectl apply -f manifests/certs/localhost-cert.yaml
```

## 5. Rancher Installation

Deploy Rancher using the official Helm chart via ArgoCD.

**File**: `gitops/core/rancher-app.yaml`
-   **Hostname**: `rancher.localhost`
-   **Ingress**: Disabled (`ingress.enabled: false`) to use Gateway API.

Sync the application in ArgoCD:
```bash
argocd app sync rancher
```

## 6. Route Configuration

Expose the Rancher service using an `HTTPRoute` attached to the Gateway's HTTPS listener.

**File**: `manifests/routes/rancher-route.yaml`
-   **Hostname**: `rancher.localhost`
-   **ParentRef**: `https` section of `my-gateway`.

```bash
kubectl apply -f manifests/routes/rancher-route.yaml
```

## 7. Verification & Access

Access Rancher dashboard at: 

👉 **[https://rancher.localhost:8443](https://rancher.localhost:8443)**

### Troubleshooting
-   **Connection Refused**: Ensure you are using port **8443**. Port 443 is not directly mapped unless you run a manual port-forward.
-   **SSL Error**: Ignore the self-signed certificate warning (use `curl -k`).
