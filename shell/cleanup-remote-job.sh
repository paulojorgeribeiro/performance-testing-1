#!/bin/bash

LAC_ID="${1}"
TEST_ID="${2}"
VAULT_TOKEN="${3}"

if [[ -z "${1}" || -z "${2}" || -z "${3}" ]]; then
    echo "Usage: $0 <lac_id> <test_id>"
    echo "   <lac_id>: ID of the LAC being tested"
    echo "   <test_id>: ID of the test being executed"
    echo "   <vault token>: Token for Vault secrets access"
    exit 1
fi

if [ -f ${HOME}/run-test-lib.sh ]; then
    source ${HOME}/run-test-lib.sh
else
    echo "[ERROR] Failed to load libs."
    exit 1
fi

# Get DPT Registry API Key
PTP_API_KEY=$(curl -s \
   --header "X-Vault-Token: ${VAULT_TOKEN}" \
   --request GET ${VAULT_URL}/v1/devplatforms/data/performance-platform/application | jq -r '.data.data.ptp_api_key // empty')

if [ -z "${PTP_API_KEY}" ]; then
    echo "[ERROR] Failed to retrieve API_KEY from Vault."
    exit 1
else
    export PTP_API_KEY=${PTP_API_KEY}
fi

# Get Vault URL from DPT Registry
response=$(curl -s -X 'GET' "${DPT_REGISTRY_URL}/${API_VERSION}/configuration/vault_url" \
    -H 'accept: application/json' \
    -H "X-API-Key: ${PTP_API_KEY}" \
    -H 'Content-Type: application/json')

VAULT_URL=$(echo "${response}" | jq -r '.value // empty')
if [[ -z "${VAULT_URL}" ]]; then
    echo "[ERROR] VAULT URL Failed! ${response}"
    exit 1
fi

# Get runid from file
if [ ! -f /tmp/.$LAC_ID-$TEST_ID.run_id ]; then
    echo "[ERROR] Run ID file /tmp/.$LAC_ID-$TEST_ID.run_id does not exist."
    exit 1
else
    RUN_ID=$(cat /tmp/.$LAC_ID-$TEST_ID.run_id)
    if [ -z "$RUN_ID" ]; then
        echo "[ERROR] Run ID not found in file /tmp/.$LAC_ID-$TEST_ID.run_id"
        exit 1
    fi
fi

# Get Information from running test using API.
SSH_USER=$(get_parameter "ssh_user" "${PTP_API_KEY}")
EXECUTION_DATA=$(get_all_execution_data "$RUN_ID" "${PTP_API_KEY}")

if [[ -z "$EXECUTION_DATA" ]]; then
    echo "[ERROR] Execution data is empty for Run ID: $RUN_ID"
    exit 1
fi

if [[ "$EXECUTION_DATA" == *"No test execution found"* ]]; then
    echo "[ERROR] Failed to retrieve execution data for Run ID: $RUN_ID"
    exit 1
fi

# Test if EXECUTION_DATA is valid JSON
echo "$EXECUTION_DATA" | jq empty
if [ $? -ne 0 ]; then
    echo "[ERROR] EXECUTION_DATA is not valid JSON for Run ID: $RUN_ID"
    exit 1
fi

EXECUTION_TYPE=$(echo $EXECUTION_DATA | jq -r '.execution_type')
LOCATION=$(echo $EXECUTION_DATA | jq -r '.location')
ENVIRONMENT=$(echo $EXECUTION_DATA | jq -r '.environment')
CONTAINER_NAME=$(echo $EXECUTION_DATA | jq -r '.container_name')
SLAVE_SERVER=$(echo $EXECUTION_DATA | jq -r '.workers | join(",")')

#EXECUTION_TYPE=$(get_execution_data "execution_type" "$RUN_ID" "${PTP_API_KEY}")
#LOCATION=$(get_execution_data "location" "$RUN_ID" "${PTP_API_KEY}")
#ENVIRONMENT=$(get_execution_data "environment" "$RUN_ID" "${PTP_API_KEY}")
#CONTAINER_NAME=$(get_execution_data "container_name" "$RUN_ID" "${PTP_API_KEY}")
#SLAVE_SERVERS=$(get_execution_data "workers" "$RUN_ID" "${PTP_API_KEY}" | jq -r 'join(",")')

# Get Orchestrator Server (SSH_HOST)
response=$(curl -s -X 'GET' "$DPT_REGISTRY_URL/$API_VERSION/orchestrator?location=$LOCATION&environment=$ENVIRONMENT" \
    -H 'accept: application/json' \
    -H "X-API-Key: ${PTP_API_KEY}" \
    -H 'Content-Type: application/json')

if [[ "$response" != *"No orchestrator found"* ]]; then
   SSH_HOST=$(echo "$response" | jq -r '.servername')
   echo "[INFO] The Orchestration Server is: $SSH_HOST."
else
    echo "[ERROR] $response"
    exit 1
fi

# Check execution type
if [ "$EXECUTION_TYPE" == "client-server" ]; then

    # Kill the JMeter client container
    ssh -q $SSH_USER@$SSH_HOST "if podman container exists ${CONTAINER_NAME}; then podman kill ${CONTAINER_NAME} 2>/dev/null || true; podman rm ${CONTAINER_NAME}; echo '[INFO] Removed container ${CONTAINER_NAME} on ${SSH_HOST}'; else echo '[INFO] No container named ${CONTAINER_NAME} on ${SSH_HOST}'; fi"

    # Kill the JMeter server containers on slave servers
    IFS=',' read -r -a SERVER_ARRAY <<< $SLAVE_SERVERS

    for SERVER in "${SERVER_ARRAY[@]}"; do

        ssh -q $SSH_USER@$SERVER "if podman container exists ${CONTAINER_NAME}; then podman kill ${CONTAINER_NAME} 2>/dev/null || true; podman rm ${CONTAINER_NAME}; echo '[INFO] Removed container ${CONTAINER_NAME} on ${SERVER}'; else echo '[INFO] No container named ${CONTAINER_NAME} on ${SERVER}'; fi"

    done
    rm -f /tmp/.$LAC_ID-$TEST_ID.run_id

else
    # Kill all JMeter containers on multiple servers
    IFS=',' read -r -a SERVER_ARRAY <<< $SLAVE_SERVERS

    for SERVER in "${SERVER_ARRAY[@]}"; do

        ssh -q $SSH_USER@$SERVER "if podman container exists ${CONTAINER_NAME}; then podman kill ${CONTAINER_NAME} 2>/dev/null || true; podman rm ${CONTAINER_NAME}; echo '[INFO] Removed container ${CONTAINER_NAME} on ${SERVER}'; else echo '[INFO] No container named ${CONTAINER_NAME} on ${SERVER}'; fi"

    done
    rm -f /tmp/.$LAC_ID-$TEST_ID.run_id
fi

register_test_complete "$RUN_ID" "cancelled" "${PTP_API_KEY}"