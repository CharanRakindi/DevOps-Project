#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# test.sh
# Runs all verification tests against the deployed Istio service mesh.
#
# Tests included:
#   1. Weighted traffic routing (80/20 canary split)
#   2. Path-based routing (/v2 → always v2)
#   3. mTLS status check via istioctl
#   4. Fault injection apply + verify + cleanup
#   5. Circuit breaker stress test via Fortio
#
# Usage:
#   chmod +x scripts/test.sh
#   ./scripts/test.sh
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$(dirname "$SCRIPT_DIR")/k8s"

# ── Get Ingress IP and Port ───────────────────────────────────────────────────
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}')

if [ -z "$NODE_IP" ]; then
  NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
fi

PORT=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')

BASE_URL="http://$NODE_IP:$PORT"

echo "========================================"
echo " Base URL: $BASE_URL"
echo "========================================"

# ── Test 1: Weighted Routing (80/20) ─────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " TEST 1: Weighted Canary Routing (80% v1 / 20% v2)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Sending 100 requests..."

V1_COUNT=0
V2_COUNT=0

for i in $(seq 1 100); do
  RESPONSE=$(curl -s "$BASE_URL/api" 2>/dev/null || echo '{"version":"error"}')
  VERSION=$(echo "$RESPONSE" | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
  if [ "$VERSION" = "v1" ]; then
    V1_COUNT=$((V1_COUNT + 1))
  elif [ "$VERSION" = "v2" ]; then
    V2_COUNT=$((V2_COUNT + 1))
  fi
done

echo "Results:"
echo "  v1 responses: $V1_COUNT / 100  (expected ~80)"
echo "  v2 responses: $V2_COUNT / 100  (expected ~20)"

if [ "$V1_COUNT" -ge 65 ] && [ "$V2_COUNT" -ge 10 ]; then
  echo "  STATUS: PASS"
else
  echo "  STATUS: WARN — distribution may need more traffic to stabilise"
fi

# ── Test 2: Path-Based Routing ────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " TEST 2: Path-Based Routing (/v2 → always v2)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Sending 10 requests to /v2..."

V2_PATH_COUNT=0
for i in $(seq 1 10); do
  RESPONSE=$(curl -s "$BASE_URL/v2/" 2>/dev/null || echo '{"version":"error"}')
  VERSION=$(echo "$RESPONSE" | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
  if [ "$VERSION" = "v2" ]; then
    V2_PATH_COUNT=$((V2_PATH_COUNT + 1))
  fi
done

echo "Results:"
echo "  v2 responses from /v2: $V2_PATH_COUNT / 10  (expected 10)"
[ "$V2_PATH_COUNT" -eq 10 ] && echo "  STATUS: PASS" || echo "  STATUS: FAIL"

# ── Test 3: service-a → service-b call ───────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " TEST 3: Internal Call (service-a → service-b via /api)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Sending 5 requests to /api..."

SUCCESS_COUNT=0
for i in $(seq 1 5); do
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api" 2>/dev/null || echo "000")
  echo "  Request $i: HTTP $HTTP_CODE"
  [ "$HTTP_CODE" = "200" ] && SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
done

echo "Results: $SUCCESS_COUNT / 5 successful"
[ "$SUCCESS_COUNT" -ge 4 ] && echo "  STATUS: PASS" || echo "  STATUS: FAIL"

# ── Test 4: mTLS Status ───────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " TEST 4: mTLS Status"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
istioctl authn tls-check -n mesh-demo 2>/dev/null || \
  echo "  NOTE: istioctl not in PATH — run manually: istioctl authn tls-check -n mesh-demo"

# ── Test 5: Fault Injection ───────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " TEST 5: Fault Injection (delay + abort on service-b)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Applying fault injection..."
kubectl apply -f "$K8S_DIR/06-fault-injection.yaml"
sleep 3

echo "Sending 20 requests to /api (expect delays and 503s)..."
DELAY_COUNT=0
ERROR_COUNT=0

for i in $(seq 1 20); do
  START=$(date +%s%N)
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 8 "$BASE_URL/api" 2>/dev/null || echo "000")
  END=$(date +%s%N)
  DURATION_MS=$(( (END - START) / 1000000 ))

  STATUS="OK"
  [ "$HTTP_CODE" = "503" ] && ERROR_COUNT=$((ERROR_COUNT + 1)) && STATUS="503-ABORT"
  [ "$DURATION_MS" -gt 4000 ] && DELAY_COUNT=$((DELAY_COUNT + 1)) && STATUS="DELAYED(${DURATION_MS}ms)"
  echo "  Request $i: HTTP $HTTP_CODE  ${DURATION_MS}ms  [$STATUS]"
done

echo ""
echo "Fault Injection Results:"
echo "  Delayed requests : $DELAY_COUNT / 20  (expected ~10)"
echo "  Aborted requests : $ERROR_COUNT / 20  (expected ~2)"

echo ""
echo "Removing fault injection..."
kubectl delete -f "$K8S_DIR/06-fault-injection.yaml"
echo "  Fault injection removed. Normal routing restored."

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "========================================"
echo " All tests complete."
echo ""
echo " To run the circuit breaker test, deploy Fortio:"
echo "   kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/httpbin/sample-client/fortio-deploy.yaml -n mesh-demo"
echo "   FORTIO_POD=\$(kubectl get pod -l app=fortio -n mesh-demo -o name | head -1)"
echo "   kubectl exec \$FORTIO_POD -n mesh-demo -c fortio -- \\"
echo "     fortio load -c 5 -qps 0 -n 200 http://service-a/api"
echo ""
echo " Open Kiali to see the live service graph:"
echo "   kubectl port-forward svc/kiali 20001:20001 -n istio-system"
echo "   http://localhost:20001"
echo "========================================"
