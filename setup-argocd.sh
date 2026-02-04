#!/bin/bash
set -e

# 1. Create Namespace
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# 2. Install ArgoCD using Kustomize (Declarative)
echo "Installing ArgoCD via Kustomize..."
# Applies the kustomization from argocd-install directory
# This includes the server-side apply equivalent needed for large CRDs? 
# Usually 'kubectl apply -k' is enough, but for ArgoCD CRDs sometimes --server-side is needed if using raw manifests. 
# Kustomize build + apply --server-side is safer.
kubectl apply -k argocd-install --server-side --force-conflicts

echo "Waiting for ArgoCD Server to be ready..."
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s

echo "ArgoCD installed."
