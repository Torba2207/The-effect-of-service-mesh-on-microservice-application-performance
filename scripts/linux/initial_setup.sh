#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INVENTORY="${INVENTORY:-$REPO_ROOT/deployments/ansible/inventory.ini}"
RUN_SETUP_KEYS="${RUN_SETUP_KEYS:-true}"

if [[ "$RUN_SETUP_KEYS" == "true" ]]; then
  "$SCRIPT_DIR/setup_keys.sh"
fi

ansible-playbook "$REPO_ROOT/deployments/ansible/setup_ai_vm.yml" -i "$INVENTORY"
ansible-playbook "$REPO_ROOT/deployments/ansible/deploy_ai_vm.yml" -i "$INVENTORY"
ansible-playbook "$REPO_ROOT/deployments/ansible/apply_baseline.yml" -i "$INVENTORY"

echo "Initial environment setup complete."
