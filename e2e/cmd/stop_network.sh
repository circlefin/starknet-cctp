# Copyright 2025 Circle Internet Group, Inc. All rights reserved.
# 
# SPDX-License-Identifier: Apache-2.0
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

LOG_FILE="$PWD/starknet-node.log"
DEVNET_RUNTIME=${STARKNET_DEVNET_RUNTIME:-docker}
DEVNET_PORT=${STARKNET_DEVNET_PORT:-5050}
DEVNET_COMPOSE_FILE=${STARKNET_DEVNET_COMPOSE_FILE:-"$PWD/repros/denylist_poc/devnet/docker-compose.yml"}
DEVNET_SERVICE_NAME=${STARKNET_DEVNET_SERVICE_NAME:-starknet-devnet}

if [ -f "$LOG_FILE" ]; then
  rm "$LOG_FILE"
fi

if [[ "$DEVNET_RUNTIME" == "docker" ]]; then
  if command -v docker >/dev/null 2>&1; then
    COMPOSE_CMD=(docker compose)
    echo "Stopping dockerized Starknet devnet..."
    "${COMPOSE_CMD[@]}" -f "$DEVNET_COMPOSE_FILE" down >/dev/null 2>&1 || true
  else
    echo "Docker runtime requested but docker command not found" >&2
  fi
else
  # Find the PID of the node using the lsof command
  # -t = only return PID
  # -c starknet-devnet = where command name is 'starknet-devnet'
  # -a = <AND>
  # -i:PORT = where the port is being used
  PID=$(lsof -t -c starknet-devnet -a -i:${DEVNET_PORT} || true)

  if [ ! -z "$PID" ]; then
    echo "Stopping network at pid: $PID..."
    kill "$PID" &>/dev/null || true
  fi
fi
