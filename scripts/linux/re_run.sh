#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INVENTORY="${INVENTORY:-$REPO_ROOT/deployments/ansible/inventory.ini}"
NAMESPACE="${NAMESPACE:-thesis-test}"
RUN_BUILD_PUSH="${RUN_BUILD_PUSH:-false}"
RUN_DEPLOY_AI_VM="${RUN_DEPLOY_AI_VM:-true}"
GHCR_OWNER="${GHCR_OWNER:-}"
TAG="${TAG:-team-test}"

if [[ "$RUN_BUILD_PUSH" == "true" ]]; then
  if [[ -z "$GHCR_OWNER" ]]; then
    echo "RUN_BUILD_PUSH=true requires GHCR_OWNER to be set."
    exit 1
  fi
  GHCR_OWNER="$GHCR_OWNER" TAG="$TAG" "$SCRIPT_DIR/build_and_push.sh"
fi

if [[ "$RUN_DEPLOY_AI_VM" == "true" ]]; then
  ansible-playbook "$REPO_ROOT/deployments/ansible/deploy_ai_vm.yml" -i "$INVENTORY"
fi

ansible-playbook "$REPO_ROOT/deployments/ansible/reapply_deployments.yml" -i "$INVENTORY"

if [[ -n "$GHCR_OWNER" ]]; then
  GHCR_OWNER="$GHCR_OWNER" TAG="$TAG" NAMESPACE="$NAMESPACE" "$SCRIPT_DIR/point_to_new.sh"
fi

kubectl get pods -n "$NAMESPACE"
echo "Re-run flow complete."
