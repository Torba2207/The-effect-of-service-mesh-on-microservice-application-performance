#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BASE_DIR="${BASE_DIR:-$REPO_ROOT/ServiceMeshTestApplication}"
GHCR_OWNER="${GHCR_OWNER:-${1:-}}"
TAG="${TAG:-${2:-team-test}}"

if [[ -z "$GHCR_OWNER" ]]; then
  echo "Usage: GHCR_OWNER=<github-username> [TAG=<tag>] ./build_and_push.sh"
  echo "   or: ./build_and_push.sh <github-username> [tag]"
  exit 1
fi

REGISTRY="ghcr.io/${GHCR_OWNER,,}"

SERVICES=(
  "DifferentialEquationsService:differential-equations-service"
  "FibonacciService:fibonacci-service"
  "IntegrationService:integration-service"
  "PermutationService:permutation-service"
  "DigitalFiltersService:digital-filters-service"
  "VideoService:video-service"
)

echo "Building and pushing images to $REGISTRY with tag $TAG"

for service in "${SERVICES[@]}"; do
  dir="${service%%:*}"
  image="${service#*:}"
  dockerfile="$BASE_DIR/$dir/Dockerfile"
  image_ref="$REGISTRY/$image:$TAG"

  if [[ ! -f "$dockerfile" ]]; then
    echo "Skipping $image (missing Dockerfile: $dockerfile)"
    continue
  fi

  echo "Building $image_ref"
  docker build -t "$image_ref" -f "$dockerfile" "$BASE_DIR"
  docker push "$image_ref"
done

echo "Done."
