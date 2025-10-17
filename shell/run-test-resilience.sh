#!/bin/bash

GITHUB_TOKEN="${1}"
REPO="${2}"
LAC_ID="${3}"
TEST_ID="${4}"
TEST_HOME="${5}"
USER="${6}"
GITHUB_REF_NAME="${7}"
VAULT_TOKEN="${8}"
PTP_GITHUB_TOKEN="${9}"
PTP_API_KEY="${10}"

if [ -f ${HOME}/run-test-lib.sh ]; then
    source ${HOME}/run-test-lib.sh
else
    echo "[ERROR] Failed to load libs."
    exit 1
fi

# Check if running performance tests is allowed
echo "[INFO] Checking if performance tests are allowed..."
response=$(curl -s -X 'GET' "${DPT_REGISTRY_URL}/${API_VERSION}/configuration/status" \
    -H 'accept: application/json' \
    -H "X-API-Key: ${PTP_API_KEY}" \
    -H 'Content-Type: application/json')

if [[ "${response}" != *"online"* ]]; then
    echo "[ERROR] Performance tests are currently not allowed. Exiting..."
    exit 1
fi

# Get the test definition file from Github
curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3.raw" \
        -o test-definition.json \
        https://api.github.com/repos/${REPO}/contents/${TEST_HOME}/${LAC_ID}/${TEST_ID}/test-definition.json?ref=${GITHUB_REF_NAME}

if [ $? -ne 0 ]; then
    echo "[ERROR] Test Metadata (test-definition.json) Fail!"
    exit 1
fi

# Process the test definition file
TOOL=$(jq -r '.test.resilience.tool' test-definition.json)
TEST_DEFINITION_FILE=$(jq -r '.test.resilience.test_definition_file' test-definition.json)
TOOL_PARAMS=$(jq -r '.test.resilience.parameters' test-definition.json)
STREAM=$(jq -r '.stream' test-definition.json)
ENVIRONMENT=$(jq -r '.xrayFields.environments | join(",")' test-definition.json)
LOCATION=$(jq -r '.test.resilience.location' test-definition.json)
DASHBOARD_URL=$(jq -r '.test.resilience.dashboard_url' test-definition.json)
TEST_TYPE=$(jq -r '.test.resilience.test_type' test-definition.json)
EXECUTION_TYPE="N/A"
WORKERS="N/A"

if [[ -z "${TOOL}" || -z "${TEST_DEFINITION_FILE}" || -z "${STREAM}" || -z "${ENVIRONMENT}" || -z "${LOCATION}" ]]; then
    echo "[ERROR] Missing required fields in test-definition.json."
    exit 1
fi

echo "[INFO] Getting Orchestration Server..."
response=$(curl -s -X 'GET' "${DPT_REGISTRY_URL}/${API_VERSION}/orchestrator?location=${LOCATION}&environment=${ENVIRONMENT}" \
    -H 'accept: application/json' \
    -H "X-API-Key: ${PTP_API_KEY}" \
    -H 'Content-Type: application/json')

if [[ "${response}" != *"No orchestrator found"* ]]; then
SSH_HOST=$(echo "${response}" | jq -r '.servername')
echo "[INFO] The Orchestration Server is: ${SSH_HOST}."
else
    echo "[ERROR] ${response}"
    exit 1
fi

# Get SSH_USER to connect to the orchestrator server and workers.
response=$(curl -s -X 'GET' "$DPT_REGISTRY_URL/$API_VERSION/configuration/ssh_user" \
    -H 'accept: application/json' \
    -H "X-API-Key: ${PTP_API_KEY}" \
    -H 'Content-Type: application/json')

if [[ "${response}" != *"not found"* ]]; then
SSH_USER=$(echo "${response}" | jq -r '.value')
echo "[INFO] The SSH User is: ${SSH_USER}."
else
    echo "[ERROR] Failed! ${response}"
    exit 1
fi

echo "[INFO] Deploying configuration on remote host..."

# Get the tool corresponding script from Github Performance Testing Repository
download_file "shell" "run-test-resilience-${TOOL}.sh" "${PTP_GITHUB_TOKEN}"

if [ -f ${HOME}/run-test-resilience-${TOOL}.sh ]; then
    scp -q ${HOME}/run-test-resilience-${TOOL}.sh ${SSH_USER}@${SSH_HOST}:/tmp/run-test-resilience-${TOOL}.sh && \
        scp -q ${HOME}/run-test-JIRA.sh ${SSH_USER}@${SSH_HOST}:/tmp/run-test-JIRA.sh
    if [ $? -ne 0 ]; then
        echo "[ERROR] Deployment Failed!"
        exit 1
    fi
else
    echo "[ERROR] Script not found!"
    exit 1
fi

case ${TOOL} in
    "chaostoolkit")
        # Get the tool corresponding script from Github Performance Testing Repository
        echo "[INFO] Using Chaostoolkit for resilience testing."
        download_file "python" "convert2junit.py" "${PTP_GITHUB_TOKEN}"
        scp -q ${HOME}/convert2junit.py ${SSH_USER}@${SSH_HOST}:/tmp/convert2junit.py
        ;;
    *)
        echo "[ERROR] Unsupported tool: ${TOOL}"
        exit 1
        ;;
esac

# Generate a unique container name
CONTAINER_NAME=$(generate_container_name_with_suffix)
echo "[INFO] Generating Container Name: ${CONTAINER_NAME}"

# Register Test Execution.
echo "[INFO] Registering test run centrally..."
DATA="{ \"repo\": \"${REPO}\", \"lac\": \"${LAC_ID}\", \"stream\": \"${STREAM}\", \"test\": \"${TEST_ID}\", \"type\": \"${TEST_TYPE}\", \"environment\": \"${ENVIRONMENT}\", \"triggered_by\": \"${USER}\", \"factor\": \"${FACTOR}\", \"dashboard_url\": \"${DASHBOARD_URL}\", \"location\": \"${LOCATION}\", \"container_name\": \"${CONTAINER_NAME}\", \"execution_type\": \"${EXECUTION_TYPE}\", \"workers\": ${WORKERS}, \"tool\": \"${TOOL}\", \"script_version\": \"${SCRIPT_VERSION}\" }"

response=$(curl -s -X 'POST' "${DPT_REGISTRY_URL}/${API_VERSION}/register" \
    -H 'accept: application/json' \
    -H "X-API-Key: ${PTP_API_KEY}" \
    -H 'Content-Type: application/json' \
    -d "${DATA}")

# Check if the response contains the expected message.
if [[ "${response}" == *"Test registered"* ]]; then
    message=$(echo "${response}" | jq -r '.message')
    RUN_ID=$(echo "${response}" | jq -r '.run_id')
    test_id=$(echo "${response}" | jq -r '.test_id')
    echo "[INFO] Test registered successfully with run_id ${RUN_ID} and test_id ${test_id}"
else
    echo "[ERROR] Registration failed! ${response}"
    exit 1
fi

# Register the run_id in a temporary file for later use.
echo "${RUN_ID}" > /tmp/.${LAC_ID}-${TEST_ID}.run_id

ssh -q ${SSH_USER}@${SSH_HOST} "/tmp/run-test-resilience-${TOOL}.sh \
    \"${EXECUTION_TYPE}\" \
    \"${GITHUB_TOKEN}\" \
    \"${REPO}\" \
    \"${TEST_DEFINITION_FILE}\" \
    \"${LAC_ID}\" \
    \"${TEST_ID}\" \
    \"${CONTAINER_NAME}\" \
    \"${TEST_HOME}\" \
    \"${TOOL_PARAMS}\" \
    \"${STREAM}\" \
    \"${TEST_TYPE}\" \
    \"${ENVIRONMENT}\" \
    \"${USER}\" \
    \"${SSH_USER}\" \
    \"${SSH_HOST}\" \
    \"${DASHBOARD_URL}\" \
    \"${LOCATION}\" \
    \"${GITHUB_REF_NAME}\" \
    \"${RUN_ID}\" \
    \"${JIRA_TOKEN}\" \
    \"${JIRA_URL}\" \
    \"${DPT_REGISTRY_URL}\" \
    \"${API_VERSION}\" \
    \"${VAULT_TOKEN}\" \
    \"${PTP_API_KEY}\"" &

SCRIPT_PID=$!

# Poll API while script is running
while kill -0 "$SCRIPT_PID" 2>/dev/null; do
response=$(curl -s "${DPT_REGISTRY_URL}/${API_VERSION}/configuration/status" \
    -H 'accept: application/json' \
    -H "X-API-Key: ${PTP_API_KEY}" \
    -H 'Content-Type: application/json')

if [[ "${response}" == *"abort"* ]]; then
    echo "[WARN] Central cancellation requested. Stopping test..."
    exit 1
fi

sleep 60
done

