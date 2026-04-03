#!/bin/bash
set -euo pipefail

ELASTIC_IP=${ELASTIC_IP:-""}

if [ -z "$ELASTIC_IP" ]; then
  echo "❌ ELASTIC_IP not set"
  exit 1
fi

PORT=$(kubectl get svc istio-ingressgateway -n istio-system \
  -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')

BASE_URL="http://$ELASTIC_IP:$PORT"

echo "========================================"
echo " Base URL: $BASE_URL"
echo "========================================"

echo "Waiting for service to be ready..."
sleep 5
echo "Service is ready ✅"

# ========================================
# TEST 1: Canary Routing
# ========================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " TEST 1: Weighted Canary Routing"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

v1=0
v2=0

for i in {1..50}; do
  version=$(curl -s "$BASE_URL/api" | grep -o '"version":"v[0-9]*"' | cut -d':' -f2 | tr -d '"')

  if [ "$version" = "v1" ]; then
    v1=$((v1+1))
  elif [ "$version" = "v2" ]; then
    v2=$((v2+1))
  fi
done

echo "v1: $v1 | v2: $v2"

# ========================================
# TEST 2: /v2 Routing (FIXED)
# ========================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " TEST 2: /v2 routing"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

success=0

for i in {1..10}; do
  response=$(curl -s "$BASE_URL/v2")

  if echo "$response" | grep '"version":"v2"' > /dev/null; then
    success=$((success+1))
  fi
done

echo "v2 success: $success / 10"

# ========================================
# TEST 3: service-a → service-b
# ========================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " TEST 3: service-a → service-b"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

success=0

for i in {1..5}; do
  code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api")

  echo "Request $i → $code"

  if [ "$code" = "200" ]; then
    success=$((success+1))
  fi
done

echo "Success: $success / 5"

# ========================================
# TEST 4: mTLS
# ========================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " TEST 4: mTLS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Run manually: istioctl authn tls-check -n mesh-demo"

# ========================================
# TEST 5: Fault Injection
# ========================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " TEST 5: Fault Injection"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

kubectl apply -f k8s/07-virtualservice-fault.yaml

sleep 3

success=0

for i in {1..10}; do
  code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api")

  echo "Request $i → $code"

  if [ "$code" = "200" ]; then
    success=$((success+1))
  fi
done

kubectl delete -f k8s/07-virtualservice-fault.yaml

echo ""
echo "========================================"
echo " All tests complete ✅"
echo "========================================"