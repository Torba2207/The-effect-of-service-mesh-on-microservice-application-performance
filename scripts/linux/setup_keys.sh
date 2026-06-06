#!/usr/bin/env bash

set -euo pipefail

KEY_DIR="${KEY_DIR:-$HOME/Documents/PG/Projects/.sshkeys}"
KEY_NAME="${KEY_NAME:-pgPB}"
KEY_PATH="$KEY_DIR/$KEY_NAME"
SSH_USER="${SSH_USER:-root}"

HOSTS=(
  "10.29.20.101" # node1 (control plane)
  "10.29.20.102" # control plane
  "10.29.20.103" # control plane
  "10.29.20.111" # node4 (worker)
  "10.29.20.112" # node5 (worker)
  "10.29.20.113" # node6 (worker)
  "10.29.20.120" # ai vm
  "10.29.20.130" # load generator
)

echo "Creating key directory: $KEY_DIR"
mkdir -p "$KEY_DIR"
chmod 700 "$KEY_DIR"

if [[ -f "$KEY_PATH" ]]; then
  echo "Existing key found: $KEY_PATH"
else
  echo "Generating SSH key: $KEY_PATH"
  ssh-keygen -t rsa -b 4096 -f "$KEY_PATH" -N ""
fi

chmod 600 "$KEY_PATH"
chmod 644 "${KEY_PATH}.pub"

echo "Distributing public key to infrastructure nodes..."
for ip in "${HOSTS[@]}"; do
  echo "Copying key to $SSH_USER@$ip (password prompt is expected)..."
  ssh-copy-id -i "${KEY_PATH}.pub" "$SSH_USER@$ip"
done

echo "Done."
