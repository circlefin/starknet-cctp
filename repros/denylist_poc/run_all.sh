#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname "$0")/../.." && pwd)
cd "$ROOT_DIR"

cleanup() {
  echo "Stopping Starknet devnet..."
  bash e2e/cmd/stop_network.sh || true
}

trap cleanup EXIT

bash e2e/cmd/start_network.sh

corepack yarn install --immutable
corepack yarn build-contracts
corepack yarn deploy
corepack yarn tsx repros/denylist_poc/run.ts
