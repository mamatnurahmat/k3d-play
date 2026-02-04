#!/bin/bash
set -e

# 1. Create Namespace
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# 2. Install ArgoCD (Stable) using server-side apply with force-conflicts
echo "Installing ArgoCD..."
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 3. Patch ArgoCD Server to run in insecure mode (HTTP)
# We must replace the 'args' usage with a clean 'command' + 'args' definition
# because 'exec --insecure' fails if we just replace 'args' and the image expects entrypoint logic.
echo "Patching ArgoCD Server to run in insecure mode..."
# Wait for deployment to be created
kubectl wait --for=condition=Available=False deployment/argocd-server -n argocd --timeout=30s || true

# Use JSON patch to standardise the command
kubectl patch deployment argocd-server -n argocd --type json \
  -p '[
    {"op": "add", "path": "/spec/template/spec/containers/0/command", "value": ["argocd-server", "--insecure"]}, 
    {"op": "remove", "path": "/spec/template/spec/containers/0/args"}
  ]'

echo "Waiting for ArgoCD Server to be ready..."
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s

echo "ArgoCD installed."
