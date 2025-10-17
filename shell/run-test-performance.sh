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
AUTHENTICATION="${11}"
SCRIPT_VERSION="${12}"

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
TOOL=$(jq -r '.test.performance.tool // empty' test-definition.json)
EXECUTION_TYPE=$(jq -r '.test.performance.execution_type // empty' test-definition.json)
TEST_DEFINITION_FILE=$(jq -r '.test.performance.test_definition_file // empty' test-definition.json)
TEST_DATA_FILE=$(jq -r '.test.performance.test_data_file // empty' test-definition.json)    
TOOL_PARAMS=$(jq -r '.test.performance.parameters // empty' test-definition.json)
STREAM=$(jq -r '.stream // empty' test-definition.json)
TEST_TYPE=$(jq -r '.test.performance.test_type // empty' test-definition.json)
ENVIRONMENT=$(jq -r '.xrayFields.environments | join(",")' test-definition.json)
FACTOR=$(jq -r '.test.performance.factor // empty' test-definition.json)
DASHBOARD_URL=$(jq -r '.test.performance.dashboard_url // empty' test-definition.json)
LOCATION=$(jq -r '.test.performance.location // empty' test-definition.json)

if [[ -z "${TOOL}" || -z "${EXECUTION_TYPE}" || -z "${TEST_DEFINITION_FILE}" || -z "${TEST_DATA_FILE}" || -z "${STREAM}" || -z "${TEST_TYPE}" || -z "${ENVIRONMENT}" || -z "${FACTOR}" || -z "${DASHBOARD_URL}" || -z "${LOCATION}" ]]; then
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

# Check if there is enough capacity to run the test with factor specified.
echo "[INFO] Checking available capacity..."
response=$(curl -s -X 'GET' "${DPT_REGISTRY_URL}/${API_VERSION}/workers?location=${LOCATION}&environment=${ENVIRONMENT}&factor=${FACTOR}" \
    -H 'accept: application/json' \
    -H "X-API-Key: ${PTP_API_KEY}" \
    -H 'Content-Type: application/json')

if [[ "${response}" != *"No servers found for location"* && "${response}" != *"Not enough servers to satisfy factor"* ]]; then
WORKERS=${response}
SLAVE_SERVERS=$(echo "${response}" | jq -r 'join(",")')
echo "[INFO] The Worker Servers are: ${SLAVE_SERVERS}."
else
    echo "[ERROR] Failed! ${response}"
    exit 1
fi

# Get SSH_USER to connect to the orchestrator server and workers.
response=$(curl -s -X 'GET' "$DPT_REGISTRY_URL/$API_VERSION/configuration/ssh_user" \
    -H 'accept: application/json' \
    -H "X-API-Key: ${PTP_API_KEY}" \
    -H 'Content-Type: application/json')

SSH_USER=$(echo "${response}" | jq -r '.value // empty')
if [[ -z "${SSH_USER}" ]]; then
    echo "[ERROR] Failed! ${response}"
    exit 1
else
    echo "[INFO] The SSH User is: ${SSH_USER}."
fi

echo "[INFO] Deploying configuration on remote host..."

# Get the tool corresponding script from Github Performance Testing Repository
download_file "shell" "run-test-performance-${TOOL}.sh" "${PTP_GITHUB_TOKEN}"

if [ -f ${HOME}/run-test-performance-${TOOL}.sh ]; then
    scp -q ${HOME}/run-test-performance-${TOOL}.sh ${SSH_USER}@${SSH_HOST}:/tmp/run-test-performance-${TOOL}.sh && \
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
    "jmeter")
        # Get the tool corresponding script from Github Performance Testing Repository
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
    -H 'Content-Type: application/json' \
    -H "X-API-Key: ${PTP_API_KEY}" \
    -d "${DATA}")

# Check if the response contains the expected message.
if [[ "${response}" == *"Test registered"* ]]; then
    message=$(echo "${response}" | jq -r '.message // empty')
    RUN_ID=$(echo "${response}" | jq -r '.run_id // empty')
    test_id=$(echo "${response}" | jq -r '.test_id // empty')
    if [[ -z "${RUN_ID}" || -z "${test_id}" ]]; then
        echo "[ERROR] Registration failed! ${response}"
        exit 1
    else
        echo "[INFO] Test registered successfully with run_id ${RUN_ID} and test_id ${test_id}"
    fi
else
    echo "[ERROR] Registration failed! ${response}"
    exit 1
fi

# Register the run_id in a temporary file for later use.
echo "${RUN_ID}" > /tmp/.${LAC_ID}-${TEST_ID}.run_id

ssh -q ${SSH_USER}@${SSH_HOST} "/tmp/run-test-performance-${TOOL}.sh \
    \"${EXECUTION_TYPE}\" \
    \"${GITHUB_TOKEN}\" \
    \"${REPO}\" \
    \"${TEST_DEFINITION_FILE}\" \
    \"${TEST_DATA_FILE}\" \
    \"${LAC_ID}\" \
    \"${TEST_ID}\" \
    \"${CONTAINER_NAME}\" \
    \"${TEST_HOME}\" \
    \"${TOOL_PARAMS}\" \
    \"${STREAM}\" \
    \"${TEST_TYPE}\" \
    \"${ENVIRONMENT}\" \
    \"${SSH_USER}\" \
    \"${SSH_HOST}\" \
    \"${FACTOR}\" \
    \"${DASHBOARD_URL}\" \
    \"${LOCATION}\" \
    \"${SLAVE_SERVERS}\" \
    \"${GITHUB_REF_NAME}\" \
    \"${RUN_ID}\" \
    \"${DPT_REGISTRY_URL}\" \
    \"${API_VERSION}\" \
    \"${VAULT_TOKEN}\" \
    \"${PTP_API_KEY}\" \
    \"${AUTHENTICATION}\"" &

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

