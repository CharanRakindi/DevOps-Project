#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# build-and-push.sh
# Builds both Go microservice Docker images and pushes them to Docker Hub.
#
# Usage:
#   chmod +x scripts/build-and-push.sh
#   ./scripts/build-and-push.sh <DOCKERHUB_USERNAME> <DOCKERHUB_PASSWORD>
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ── Validate input ────────────────────────────────────────────────────────────
if [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
  echo "ERROR: Docker Hub username and password are required."
  echo "Usage: $0 <dockerhub-username> <dockerhub-password>"
  exit 1
fi

DOCKERHUB_USER="$1"
DOCKERHUB_PASS="$2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "========================================"
echo " Docker Hub User : $DOCKERHUB_USER"
echo " Project Root    : $PROJECT_ROOT"
echo "========================================"

# ── Login to Docker Hub (NON-INTERACTIVE) ─────────────────────────────────────
echo ""
echo "[1/5] Logging in to Docker Hub..."
echo "$DOCKERHUB_PASS" | docker login -u "$DOCKERHUB_USER" --password-stdin

# ── Build service-a v1 ───────────────────────────────────────────────────────
echo ""
echo "[2/5] Building service-a:v1..."
docker build \
  --build-arg APP_VERSION=v1 \
  -t "$DOCKERHUB_USER/service-a:v1" \
  -t "$DOCKERHUB_USER/service-a:latest" \
  "$PROJECT_ROOT/services/service-a"

# ── Build service-a v2 ───────────────────────────────────────────────────────
echo ""
echo "[3/5] Building service-a:v2..."
docker build \
  --build-arg APP_VERSION=v2 \
  -t "$DOCKERHUB_USER/service-a:v2" \
  "$PROJECT_ROOT/services/service-a"

# ── Build service-b v1 ───────────────────────────────────────────────────────
echo ""
echo "[4/5] Building service-b:v1..."
docker build \
  --build-arg APP_VERSION=v1 \
  -t "$DOCKERHUB_USER/service-b:v1" \
  -t "$DOCKERHUB_USER/service-b:latest" \
  "$PROJECT_ROOT/services/service-b"

# ── Push all images ───────────────────────────────────────────────────────────
echo ""
echo "[5/5] Pushing all images to Docker Hub..."
docker push "$DOCKERHUB_USER/service-a:v1"
docker push "$DOCKERHUB_USER/service-a:v2"
docker push "$DOCKERHUB_USER/service-a:latest"
docker push "$DOCKERHUB_USER/service-b:v1"
docker push "$DOCKERHUB_USER/service-b:latest"

echo ""
echo "========================================"
echo " All images pushed successfully!"
echo ""
echo " Images:"
echo "   $DOCKERHUB_USER/service-a:v1"
echo "   $DOCKERHUB_USER/service-a:v2"
echo "   $DOCKERHUB_USER/service-b:v1"
echo ""
echo " Next step:"
echo "   Run: ./scripts/deploy.sh $DOCKERHUB_USER"
echo "========================================"
echo "========================================"