#!/bin/bash
set -e

# 1. Install Gateway API CRDs (Experimental version to include GRPCRoute etc.)
echo "Installing Gateway API CRDs (v1.1.0 Experimental)..."
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/experimental-install.yaml

# 2. Install Nginx Gateway Fabric via OCI
echo "Installing Nginx Gateway Fabric via Helm (OCI)..."
# Using OCI registry
helm upgrade --install ngf oci://ghcr.io/nginxinc/charts/nginx-gateway-fabric \
    --create-namespace --namespace nginx-gateway \
    --set service.type=NodePort \
    --set service.ports[0].port=80 \
    --set service.ports[0].nodePort=30000 \
    --set service.ports[0].name=http
    
echo "Gateway installation complete. Access via localhost:8081"
