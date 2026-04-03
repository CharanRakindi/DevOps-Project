#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$(dirname "$SCRIPT_DIR")/k8s"

# ── FIXED: Use Public IP instead of Internal ────────────────────────────────

# 🔥 OPTION 1 (BEST): Hardcode your EC2 public IP
PUBLIC_IP="65.0.11.29"

# 🔥 OPTION 2 (fallback): Try to auto-detect external IP
if [ -z "$PUBLIC_IP" ]; then
  PUBLIC_IP=$(curl -s ifconfig.me || echo "")
fi

PORT=$(kubectl get svc istio-ingressgateway -n istio-system \
  -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')

BASE_URL="http://$PUBLIC_IP:$PORT"

echo "========================================"
echo " Base URL: $BASE_URL"
echo "========================================"

# ── Wait for service to be ready ────────────────────────────────────────────
echo "Waiting for service to be ready..."
for i in {1..20}; do
  if curl -s "$BASE_URL/api" >/dev/null 2>&1; then
    echo "Service is ready ✅"
    break
  fi
  echo "Retrying... ($i)"
  sleep 3
done

# ── Test 1: Weighted Routing ────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " TEST 1: Weighted Canary Routing (80% v1 / 20% v2)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

V1_COUNT=0
V2_COUNT=0

for i in $(seq 1 100); do
  RESPONSE=$(curl -s "$BASE_URL/api" || echo '{"version":"error"}')
  VERSION=$(echo "$RESPONSE" | grep -o '"version":"[^"]*"' | cut -d'"' -f4)

  [ "$VERSION" = "v1" ] && V1_COUNT=$((V1_COUNT + 1))
  [ "$VERSION" = "v2" ] && V2_COUNT=$((V2_COUNT + 1))
done

echo "v1: $V1_COUNT | v2: $V2_COUNT"

# ── Test 2: Path Routing ────────────────────────────────────────────────────
echo ""
echo "TEST 2: /v2 routing"

SUCCESS=0
for i in $(seq 1 10); do
  RESPONSE=$(curl -s "$BASE_URL/v2/" || echo '{"version":"error"}')
  VERSION=$(echo "$RESPONSE" | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
  [ "$VERSION" = "v2" ] && SUCCESS=$((SUCCESS + 1))
done

echo "v2 success: $SUCCESS / 10"

# ── Test 3: Service-to-Service ──────────────────────────────────────────────
echo ""
echo "TEST 3: service-a → service-b"

SUCCESS_COUNT=0
for i in $(seq 1 5); do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api" || echo "000")
  echo "Request $i → $CODE"
  [ "$CODE" = "200" ] && SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
done

echo "Success: $SUCCESS_COUNT / 5"

# ── Test 4: mTLS ────────────────────────────────────────────────────────────
echo ""
echo "TEST 4: mTLS"

istioctl authn tls-check -n mesh-demo 2>/dev/null || \
echo "Run manually: istioctl authn tls-check -n mesh-demo"

# ── Test 5: Fault Injection ─────────────────────────────────────────────────
echo ""
echo "TEST 5: Fault Injection"

kubectl apply -f "$K8S_DIR/06-fault-injection.yaml"
sleep 3

for i in $(seq 1 10); do
  curl -s -o /dev/null -w "Request $i → %{http_code}\n" "$BASE_URL/api" || true
done

kubectl delete -f "$K8S_DIR/06-fault-injection.yaml"

echo ""
echo "========================================"
echo " All tests complete ✅"
echo "========================================"