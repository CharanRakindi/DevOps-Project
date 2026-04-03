#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$(dirname "$SCRIPT_DIR")/k8s"

# ── Detect Node IP ──────────────────────────────────────────────────────────
# Priority: ELASTIC_IP env > ExternalIP > InternalIP
if [ -n "${ELASTIC_IP:-}" ]; then
  NODE_IP="$ELASTIC_IP"
else
  NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null || echo "")
  if [ -z "$NODE_IP" ]; then
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "")
  fi
fi

if [ -z "$NODE_IP" ]; then
  echo "❌ Could not determine node IP"
  exit 1
fi

PORT=$(kubectl get svc istio-ingressgateway -n istio-system \
  -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')

BASE_URL="http://$NODE_IP:$PORT"

echo "========================================"
echo " Base URL: $BASE_URL"
echo "========================================"

# ── Wait for service readiness ──────────────────────────────────────────────
echo ""
echo "Waiting for service to be ready..."
READY=false
for i in $(seq 1 15); do
  if curl -s --max-time 3 "$BASE_URL/api" >/dev/null 2>&1; then
    echo "Service is ready ✅"
    READY=true
    break
  fi
  echo "  Retrying... ($i/15)"
  sleep 3
done

if [ "$READY" = false ]; then
  echo "⚠️  Service may not be ready, continuing tests anyway..."
fi

# ========================================
# TEST 1: Weighted Canary Routing
# ========================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " TEST 1: Weighted Canary Routing (80/20)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

v1=0
v2=0

for i in $(seq 1 50); do
  version=$(curl -s --max-time 5 "$BASE_URL/api" 2>/dev/null \
    | grep -o '"version":"[^"]*"' | cut -d'"' -f4 || echo "")

  if [ "$version" = "v1" ]; then
    v1=$((v1+1))
  elif [ "$version" = "v2" ]; then
    v2=$((v2+1))
  fi
done

echo "  v1: $v1 | v2: $v2  (expected ~40/10)"

# ========================================
# TEST 2: /v2 Path Routing
# ========================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " TEST 2: /v2 routing → must return v2"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

success=0

for i in $(seq 1 10); do
  response=$(curl -s --max-time 5 "$BASE_URL/v2" 2>/dev/null || echo "")

  if echo "$response" | grep -q '"version":"v2"' 2>/dev/null; then
    success=$((success+1))
  fi
done

echo "  v2 success: $success / 10"
[ "$success" -ge 9 ] && echo "  STATUS: PASS ✅" || echo "  STATUS: FAIL ❌"

# ========================================
# TEST 3: service-a → service-b
# ========================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " TEST 3: service-a → service-b (HTTP 200)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

success=0

for i in $(seq 1 5); do
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$BASE_URL/api" 2>/dev/null || echo "000")
  echo "  Request $i → HTTP $code"
  [ "$code" = "200" ] && success=$((success+1))
done

echo "  Success: $success / 5"
[ "$success" -ge 4 ] && echo "  STATUS: PASS ✅" || echo "  STATUS: FAIL ❌"

# ========================================
# TEST 4: mTLS Verification
# ========================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " TEST 4: mTLS (STRICT mode)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

MTLS_STATUS=$(kubectl get peerauthentication -n mesh-demo -o jsonpath='{.items[0].spec.mtls.mode}' 2>/dev/null || echo "UNKNOWN")
echo "  mTLS mode: $MTLS_STATUS"
[ "$MTLS_STATUS" = "STRICT" ] && echo "  STATUS: PASS ✅" || echo "  STATUS: WARN ⚠️ (expected STRICT)"

# ========================================
# TEST 5: Fault Injection
# ========================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " TEST 5: Fault Injection (service-b delay)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "  Applying fault injection..."
kubectl apply -f "$K8S_DIR/07-virtualservice-fault.yaml"
sleep 5

delayed=0
ok=0

for i in $(seq 1 10); do
  START=$(date +%s%N 2>/dev/null || date +%s)
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$BASE_URL/api" 2>/dev/null || echo "000")
  END=$(date +%s%N 2>/dev/null || date +%s)

  # Calculate duration in ms (handle both nanosecond and second precision)
  if [ ${#START} -gt 10 ]; then
    DURATION_MS=$(( (END - START) / 1000000 ))
  else
    DURATION_MS=$(( (END - START) * 1000 ))
  fi

  STATUS="OK"
  [ "$DURATION_MS" -gt 1500 ] && delayed=$((delayed+1)) && STATUS="DELAYED"
  [ "$code" = "200" ] && ok=$((ok+1))

  echo "  Request $i → HTTP $code  ${DURATION_MS}ms  [$STATUS]"
done

echo ""
echo "  Delayed: $delayed / 10  (expected ~5)"
echo "  OK:      $ok / 10"

echo "  Removing fault injection..."
kubectl delete -f "$K8S_DIR/07-virtualservice-fault.yaml"
echo "  Fault injection removed ✅"

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "========================================"
echo " All tests complete ✅"
echo ""
echo " Kiali dashboard:"
echo "   kubectl port-forward svc/kiali 20001:20001 -n istio-system"
echo "   http://localhost:20001"
echo "========================================"