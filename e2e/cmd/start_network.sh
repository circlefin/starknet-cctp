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

echo "Starting Starknet node using runtime: $DEVNET_RUNTIME"

if [[ "$DEVNET_RUNTIME" == "docker" ]]; then
  if ! command -v docker >/dev/null 2>&1; then
    echo "Docker is required for docker runtime; set STARKNET_DEVNET_RUNTIME=native to use local binary." >&2
    exit 1
  fi

  COMPOSE_CMD=(docker compose)
  echo ">> Launching container via ${COMPOSE_CMD[*]} -f $DEVNET_COMPOSE_FILE up"
  "${COMPOSE_CMD[@]}" -f "$DEVNET_COMPOSE_FILE" up -d --build "$DEVNET_SERVICE_NAME"
else
  echo ">> Launching local starknet-devnet binary"
  starknet-devnet --seed=0 &> "$LOG_FILE" &
fi

WAIT_TIME=120
echo ">> Waiting for Starknet node to come online within $WAIT_TIME seconds..."

ELAPSED=0
SECONDS=0
while [[ "$ELAPSED" -lt "$WAIT_TIME" ]]; do
  HEALTHCHECK_STATUS_CODE="$(curl -k -s -o /dev/null -w %{http_code} http://localhost:${DEVNET_PORT}/is_alive)"
  if [[ "$HEALTHCHECK_STATUS_CODE" -eq 200 ]]; then
    echo ">> Starknet node is started after $ELAPSED seconds!"
    if [[ "$DEVNET_RUNTIME" != "docker" && -f "$LOG_FILE" ]]; then
      cat "$LOG_FILE"
    fi
    exit 0
  fi

  if [[ $(( ELAPSED % 10 )) == 0 && "$ELAPSED" -gt 0 ]]; then
    echo ">> Waiting for Starknet node for $ELAPSED seconds.. (Status: $HEALTHCHECK_STATUS_CODE)"
    if [[ "$DEVNET_RUNTIME" != "docker" ]]; then
      echo ">> Last few lines of log:"
      tail -5 "$LOG_FILE" 2>/dev/null || echo "   No log content yet"
    else
      echo ">> View container logs with: docker logs -f $DEVNET_SERVICE_NAME"
    fi
  fi

  sleep 1
  ELAPSED=$SECONDS
done

echo ">> Starknet node failed to start within $WAIT_TIME seconds!"
if [[ "$DEVNET_RUNTIME" != "docker" ]]; then
  echo ">> Showing log file contents:"
  cat "$LOG_FILE"
else
  echo ">> Showing container logs:"
  docker logs "$DEVNET_SERVICE_NAME" || true
fi
exit 1
