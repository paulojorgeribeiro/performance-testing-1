#!/usr/bin/env bash
set -euo pipefail

# -------- Args & usage --------
LAC_ID="${1:-}"
TEST_ID="${2:-}"
VAULT_TOKEN="${3:-}"

if [[ -z "$LAC_ID" || -z "$TEST_ID" || -z "$VAULT_TOKEN" ]]; then
  echo "Usage: $0 <lac_id> <test_id> <vault_token>"
  echo "   <lac_id>: ID of the LAC being tested"
  echo "   <test_id>: ID of the test being executed"
  echo "   <vault_token>: Token for Vault secrets access"
  exit 1
fi

# -------- Lib loading (absolute, robust) --------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CANDIDATES=(
  "$REPO_ROOT/shell/run-test-lib.sh"
  "$REPO_ROOT/run-test-lib.sh"
  "${GITHUB_WORKSPACE:-}/shell/run-test-lib.sh"
  "${PERFORMANCE_HOME:-}/shell/run-test-lib.sh"
  "${HOME}/run-test-lib.sh"
)

LIB_PATH=""
for p in "${CANDIDATES[@]}"; do
  if [[ -n "$p" && -f "$p" ]]; then
    LIB_PATH="$p"
    break
  fi
done

if [[ -z "$LIB_PATH" ]]; then
  echo "Error:  Failed to load libs."
  echo "Hint: none of these exist: ${CANDIDATES[*]}"
  exit 1
fi

# shellcheck disable=SC1091
source "$LIB_PATH"

# -------- Vault endpoint & PTP_API_KEY --------
VAULT_ENDPOINT="${VAULT_ADDR:-${VAULT_URL:-}}"
if [[ -z "$VAULT_ENDPOINT" ]]; then
  VAULT_ENDPOINT="http://host.containers.internal:18200"
fi
echo "[INFO] Using Vault endpoint: $VAULT_ENDPOINT"

# Read PTP_API_KEY from Vault (KV v2 path)
PTP_API_KEY="$(
  curl -sS -H "X-Vault-Token: ${VAULT_TOKEN}" \
       --get "${VAULT_ENDPOINT}/v1/devplatforms/data/performance-platform/application" \
  | jq -r '.data.data.ptp_api_key // empty'
)"

if [[ -z "$PTP_API_KEY" ]]; then
  echo "[ERROR] Failed to retrieve API_KEY from Vault at ${VAULT_ENDPOINT}."
  exit 1
fi
export PTP_API_KEY

# Optionally refresh Vault endpoint from DPT Registry (when configured)
if [[ -n "${DPT_REGISTRY_URL:-}" && -n "${API_VERSION:-}" ]]; then
  response="$(
    curl -sS -X GET "${DPT_REGISTRY_URL}/${API_VERSION}/configuration/vault_url" \
      -H 'accept: application/json' \
      -H "X-API-Key: ${PTP_API_KEY}" \
      -H 'Content-Type: application/json' || true
  )"
  reg_vault="$(echo "$response" | jq -r '.value // empty' || true)"
  if [[ -n "$reg_vault" ]]; then
    VAULT_ENDPOINT="$reg_vault"
    echo "[INFO] Vault endpoint (registry): $VAULT_ENDPOINT"
  else
    echo "[WARN] DPT Registry did not return vault_url; keeping $VAULT_ENDPOINT"
  fi
fi

# -------- Run ID file --------
RUN_FILE="/tmp/.${LAC_ID}-${TEST_ID}.run_id"
if [[ ! -f "$RUN_FILE" ]]; then
  echo "[ERROR] Run ID file $RUN_FILE does not exist."
  exit 1
fi
RUN_ID="$(<"$RUN_FILE")"
if [[ -z "$RUN_ID" ]]; then
  echo "[ERROR] Run ID not found in file $RUN_FILE"
  exit 1
fi

# -------- Execution data --------
SSH_USER="$(get_parameter "ssh_user" "${PTP_API_KEY}")"
EXECUTION_DATA="$(get_all_execution_data "$RUN_ID" "${PTP_API_KEY}")"

if [[ -z "$EXECUTION_DATA" || "$EXECUTION_DATA" == *"No test execution found"* ]]; then
  echo "[ERROR] Failed to retrieve execution data for Run ID: $RUN_ID"
  exit 1
fi

echo "$EXECUTION_DATA" | jq empty >/dev/null 2>&1 || {
  echo "[ERROR] EXECUTION_DATA is not valid JSON for Run ID: $RUN_ID"
  exit 1
}

EXECUTION_TYPE="$(echo "$EXECUTION_DATA" | jq -r '.execution_type')"
LOCATION="$(echo "$EXECUTION_DATA" | jq -r '.location')"
ENVIRONMENT="$(echo "$EXECUTION_DATA" | jq -r '.environment')"
CONTAINER_NAME="$(echo "$EXECUTION_DATA" | jq -r '.container_name')"
SLAVE_SERVERS="$(echo "$EXECUTION_DATA" | jq -r '.workers | join(",")')"

# -------- Orchestrator (SSH_HOST) --------
if [[ -n "${DPT_REGISTRY_URL:-}" && -n "${API_VERSION:-}" ]]; then
  response="$(
    curl -sS -X GET "${DPT_REGISTRY_URL}/${API_VERSION}/orchestrator?location=${LOCATION}&environment=${ENVIRONMENT}" \
      -H 'accept: application/json' \
      -H "X-API-Key: ${PTP_API_KEY}" \
      -H 'Content-Type: application/json'
  )"
else
  response="No orchestrator found (DPT_REGISTRY_URL/API_VERSION not set)"
fi

if [[ "$response" != *"No orchestrator found"* ]]; then
  SSH_HOST="$(echo "$response" | jq -r '.servername')"
  echo "[INFO] The Orchestration Server is: $SSH_HOST."
else
  echo "[ERROR] $response"
  exit 1
fi

# -------- Cleanup containers --------
if [[ "$EXECUTION_TYPE" == "client-server" ]]; then
  # Kill the JMeter client container
  ssh -q "$SSH_USER@$SSH_HOST" \
    "if podman container exists '${CONTAINER_NAME}'; then podman kill '${CONTAINER_NAME}' 2>/dev/null || true; podman rm '${CONTAINER_NAME}'; echo '[INFO] Removed container ${CONTAINER_NAME} on ${SSH_HOST}'; else echo '[INFO] No container named ${CONTAINER_NAME} on ${SSH_HOST}'; fi"

  # Kill the JMeter server containers on slave servers
  IFS=',' read -r -a SERVER_ARRAY <<< "$SLAVE_SERVERS"
  for SERVER in "${SERVER_ARRAY[@]}"; do
    ssh -q "$SSH_USER@$SERVER" \
      "if podman container exists '${CONTAINER_NAME}'; then podman kill '${CONTAINER_NAME}' 2>/dev/null || true; podman rm '${CONTAINER_NAME}'; echo '[INFO] Removed container ${CONTAINER_NAME} on ${SERVER}'; else echo '[INFO] No container named ${CONTAINER_NAME} on ${SERVER}'; fi"
  done
  rm -f "$RUN_FILE"
else
  # Kill all JMeter containers on multiple servers (no client-server split)
  IFS=',' read -r -a SERVER_ARRAY <<< "$SLAVE_SERVERS"
  for SERVER in "${SERVER_ARRAY[@]}"; do
    ssh -q "$SSH_USER@$SERVER" \
      "if podman container exists '${CONTAINER_NAME}'; then podman kill '${CONTAINER_NAME}' 2>/dev/null || true; podman rm '${CONTAINER_NAME}'; echo '[INFO] Removed container ${CONTAINER_NAME} on ${SERVER}'; else echo '[INFO] No container named ${CONTAINER_NAME} on ${SERVER}'; fi"
  done
  rm -f "$RUN_FILE"
fi

register_test_complete "$RUN_ID" "cancelled" "${PTP_API_KEY}"
