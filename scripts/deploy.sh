#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# deploy.sh
# Substitutes your Docker Hub username into manifests and applies them
# to the Kubernetes cluster in the correct order.
#
# Prerequisites:
#   - kubectl is configured and pointing to your kubeadm cluster
#   - Istio is installed (istioctl install --set profile=demo -y)
#   - Images have been pushed (run build-and-push.sh first)
#
# Usage:
#   chmod +x scripts/deploy.sh
#   ./scripts/deploy.sh <YOUR_DOCKERHUB_USERNAME>
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

if [ -z "${1:-}" ]; then
  echo "ERROR: Docker Hub username is required."
  echo "Usage: $0 <dockerhub-username>"
  exit 1
fi

DOCKERHUB_USER="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$(dirname "$SCRIPT_DIR")/k8s"

echo "========================================"
echo " Docker Hub User : $DOCKERHUB_USER"
echo " Manifests Dir   : $K8S_DIR"
echo "========================================"

# ── Substitute Docker Hub username in deployments.yaml ───────────────────────
echo ""
echo "[1/6] Substituting image names..."
DEPLOY_FILE="$K8S_DIR/02-deployments.yaml"
if [[ "$OSTYPE" == "darwin"* ]]; then
  sed -i '' "s|YOUR_DOCKERHUB_USERNAME|$DOCKERHUB_USER|g" "$DEPLOY_FILE"
else
  sed -i "s|YOUR_DOCKERHUB_USERNAME|$DOCKERHUB_USER|g" "$DEPLOY_FILE"
fi
echo "  Updated: $DEPLOY_FILE"

# ── Apply manifests in order ──────────────────────────────────────────────────
echo ""
echo "[2/6] Creating namespace with Istio injection label..."
kubectl apply -f "$K8S_DIR/01-namespace.yaml"

echo ""
echo "[3/6] Deploying services..."
kubectl apply -f "$K8S_DIR/02-deployments.yaml"

echo ""
echo "[4/6] Applying Istio Gateway..."
kubectl apply -f "$K8S_DIR/03-gateway.yaml"

echo ""
echo "[5/6] Applying VirtualService and DestinationRule..."
kubectl apply -f "$K8S_DIR/04-virtualservice.yaml"
kubectl apply -f "$K8S_DIR/05-destinationrule.yaml"

echo ""
echo "[6/6] Enforcing strict mTLS..."
kubectl apply -f "$K8S_DIR/07-peer-authentication.yaml"

# ── Wait for rollout ──────────────────────────────────────────────────────────
echo ""
echo "Waiting for deployments to roll out..."
kubectl rollout status deployment/service-a-v1 -n mesh-demo --timeout=120s
kubectl rollout status deployment/service-a-v2 -n mesh-demo --timeout=120s
kubectl rollout status deployment/service-b-v1 -n mesh-demo --timeout=120s

# ── Print status ──────────────────────────────────────────────────────────────
echo ""
echo "========================================"
echo " Deployment complete!"
echo ""
echo " Pod status (should show 2/2 READY):"
kubectl get pods -n mesh-demo
echo ""
echo " Ingress Gateway:"
kubectl get svc istio-ingressgateway -n istio-system
echo ""
echo " Next steps:"
echo "   Test routing:     ./scripts/test.sh"
echo "   Open Kiali:       kubectl port-forward svc/kiali 20001:20001 -n istio-system"
echo "========================================"
