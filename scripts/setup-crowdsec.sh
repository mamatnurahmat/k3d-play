#!/bin/bash
# CrowdSec Setup Script for WAF Integration
# Run this after deploying the base CrowdSec resources

set -e

NAMESPACE="default"
LAPI_POD=""

echo "=== CrowdSec WAF Setup ==="

# Step 1: Apply base resources
echo "[1/5] Applying CrowdSec resources..."
kubectl apply -f manifests/waf/crowdsec-config.yaml
kubectl apply -f manifests/waf/crowdsec-lapi.yaml

# Step 2: Wait for LAPI to be ready
echo "[2/5] Waiting for CrowdSec LAPI to be ready..."
kubectl wait --for=condition=ready pod -l app=crowdsec-lapi -n $NAMESPACE --timeout=120s

# Get LAPI pod name
LAPI_POD=$(kubectl get pod -l app=crowdsec-lapi -n $NAMESPACE -o jsonpath='{.items[0].metadata.name}')
echo "LAPI Pod: $LAPI_POD"

# Step 3: Register the WAF agent
echo "[3/5] Registering WAF agent..."
AGENT_PASSWORD=$(openssl rand -base64 32)
kubectl exec -n $NAMESPACE $LAPI_POD -- cscli machines add waf-app001-agent --password "$AGENT_PASSWORD" --force || true

# Create agent credentials secret
kubectl create secret generic crowdsec-agent-credentials \
  --from-literal=password="$AGENT_PASSWORD" \
  -n $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
echo "Agent credentials created"

# Step 4: Create bouncer API key
echo "[4/5] Creating bouncer API key..."
BOUNCER_KEY=$(kubectl exec -n $NAMESPACE $LAPI_POD -- cscli bouncers add waf-app001-bouncer -o raw 2>/dev/null || \
              kubectl exec -n $NAMESPACE $LAPI_POD -- cscli bouncers list -o json | grep -o '"api_key":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -z "$BOUNCER_KEY" ]; then
  echo "Warning: Could not get bouncer key. It may already exist."
  echo "Run: kubectl exec -it $LAPI_POD -- cscli bouncers list"
else
  kubectl create secret generic crowdsec-bouncer-key \
    --from-literal=api-key="$BOUNCER_KEY" \
    -n $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
  echo "Bouncer API key created"
fi

# Step 5: Apply WAF deployment with agent
echo "[5/5] Deploying WAF with CrowdSec agent..."
kubectl apply -f manifests/waf/waf-deployments.yaml

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Verify deployment:"
echo "  kubectl get pods -l app=crowdsec-lapi"
echo "  kubectl get pods -l app=waf-app001"
echo ""
echo "Check agent connection:"
echo "  kubectl exec -it $LAPI_POD -- cscli machines list"
echo ""
echo "Check bouncer connection:"
echo "  kubectl exec -it $LAPI_POD -- cscli bouncers list"
echo ""
echo "View decisions:"
echo "  kubectl exec -it $LAPI_POD -- cscli decisions list"
