#!/bin/bash
set -e

# Setup Script for K3d + ArgoCD + Gateway API Demo

echo "🚀 Starting Setup Loop..."

# 1. Install ArgoCD
echo "📦 [1/5] Installing ArgoCD (Bootstrap)..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -k bootstrap --server-side --force-conflicts
echo "⏳ Waiting for ArgoCD Server to be ready..."
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s

# 2. Install Infrastructure (Gateway API CRDs + Nginx Gateway) via ArgoCD
echo "🏗️  [2/5] Installing Infrastructure (Gateway API, Nginx Gateway)..."
kubectl apply -f gitops/core/gateway-crds-app.yaml
kubectl apply -f gitops/core/gateway-app.yaml

# 3. Wait for Nginx Gateway to be synced and ready
echo "⏳ Waiting for Nginx Gateway to be instantiated..."
# We wait for the Application to sync
# (Optional) We could wait for the actual Deployment if we knew the final name, but let's trust ArgoCD for now or wait a bit.
sleep 10 
# Note: The Gateway itself (the resource) is deployed later, but the Controller comes from step 2.

# 4. Deploy Gateway Resource & Manifests (Workloads)
echo "🚀 [3/5] Deploying Gateway Resource && Workloads..."
# Deploy the Gateway resource (infra definition)
kubectl apply -f manifests/infra/gateway.yaml
# Deploy the Apps
# kubectl apply -f manifests/workloads/demo-app.yaml

# 5. Deploy Routes
echo "🔗 [4/5] Deploying Routes..."
kubectl apply -f manifests/routes/argocd-route.yaml
# rancher-route.yaml is optional/leftover?

echo "✅ Setup Complete!"
echo "------------------------------------------------"
echo "👉 Front App: http://localhost:8081/front"
echo "👉 Back App:  http://localhost:8081/back"
echo "👉 ArgoCD:    http://argocd.localhost:8081"
echo "------------------------------------------------"
