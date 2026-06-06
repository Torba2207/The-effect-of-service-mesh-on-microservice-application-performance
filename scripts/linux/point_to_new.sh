#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GHCR_OWNER="${GHCR_OWNER:-${1:-}}"
TAG="${TAG:-${2:-team-test}}"
NAMESPACE="${NAMESPACE:-thesis-test}"
AI_EXTERNAL_MANIFEST="${AI_EXTERNAL_MANIFEST:-$REPO_ROOT/deployments/k8s/ai-service/ai-service-external.yaml}"

if [[ -z "$GHCR_OWNER" ]]; then
  echo "Usage: GHCR_OWNER=<github-username> [TAG=<tag>] [NAMESPACE=<ns>] ./point_to_new.sh"
  echo "   or: ./point_to_new.sh <github-username> [tag]"
  exit 1
fi

REGISTRY="ghcr.io/${GHCR_OWNER,,}"

SERVICES=(
  "differential-equations-service"
  "fibonacci-service"
  "integration-service"
  "permutation-service"
  "digital-filters-service"
  "video-service"
)

echo "Pointing deployments in namespace '$NAMESPACE' to $REGISTRY:$TAG"

for service in "${SERVICES[@]}"; do
  kubectl set image "deployment/$service" "$service=$REGISTRY/$service:$TAG" -n "$NAMESPACE"
done

kubectl apply -f "$AI_EXTERNAL_MANIFEST"
kubectl set env deployment/permutation-service AI_SERVICE_BASEURL=http://ai-service/ -n "$NAMESPACE"
kubectl rollout status deployment/permutation-service -n "$NAMESPACE" --timeout=180s

echo "Done."
