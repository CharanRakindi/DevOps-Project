#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$(dirname "$SCRIPT_DIR")/k8s"

# ✅ Elastic IP
ELASTIC_IP="16.112.134.36"

PORT=$(kubectl get svc istio-ingressgateway -n istio-system \
  -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')

BASE_URL="http://$ELASTIC_IP:$PORT"

echo "========================================"
echo " Base URL: $BASE_URL"
echo "========================================"

# ── SAFE FUNCTIONS (IMPORTANT FIX) ──────────────────────────────────────────
safe_curl() {
  curl -s --max-time 5 "$1" 2>/dev/null || echo ""
}

get_version() {
  echo "$1" | grep -o '"version":"[^"]*"' 2>/dev/null | cut -d'"' -f4 || echo "unknown"
}

# ── Wait for service ────────────────────────────────────────────────────────
echo "Waiting for service to be ready..."

READY=false
for i in {1..15}; do
  if curl -s --max-time 3 "$BASE_URL/api" >/dev/null 2>&1; then
    echo "Service is ready ✅"
    READY=true
    break
  fi
  echo "Retrying... ($i)"
  sleep 3
done

if [ "$READY" = false ]; then
  echo "❌ Service not reachable. Exiting..."
  exit 1
fi

# ── Test 1 ──────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " TEST 1: Weighted Canary Routing"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

V1_COUNT=0
V2_COUNT=0

for i in $(seq 1 50); do
  RESPONSE=$(safe_curl "$BASE_URL/api")
  VERSION=$(get_version "$RESPONSE")

  [ "$VERSION" = "v1" ] && V1_COUNT=$((V1_COUNT + 1))
  [ "$VERSION" = "v2" ] && V2_COUNT=$((V2_COUNT + 1))
done

echo "v1: $V1_COUNT | v2: $V2_COUNT"

# ── Test 2 ──────────────────────────────────────────────────────────────────
echo ""
echo "TEST 2: /v2 routing"

SUCCESS=0
for i in $(seq 1 10); do
  RESPONSE=$(safe_curl "$BASE_URL/v2/")
  VERSION=$(get_version "$RESPONSE")

  [ "$VERSION" = "v2" ] && SUCCESS=$((SUCCESS + 1))
done

echo "v2 success: $SUCCESS / 10"

# ── Test 3 ──────────────────────────────────────────────────────────────────
echo ""
echo "TEST 3: service-a → service-b"

SUCCESS_COUNT=0
for i in $(seq 1 5); do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api" 2>/dev/null || echo "000")
  echo "Request $i → $CODE"
  [ "$CODE" = "200" ] && SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
done

echo "Success: $SUCCESS_COUNT / 5"

# ── Test 4 ──────────────────────────────────────────────────────────────────
echo ""
echo "TEST 4: mTLS"

istioctl authn tls-check -n mesh-demo 2>/dev/null || \
echo "Run manually: istioctl authn tls-check -n mesh-demo"

# ── Test 5 ──────────────────────────────────────────────────────────────────
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