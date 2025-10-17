#!/bin/bash
# Usage : ./run-test-JIRA.sh <test_definition_file> <results_file> <DPT_registry_url> <api_version> <vault_token> <api_key> <files_to_attach>

TEST_DEFINITION_FILE=${1}
RESULTS_FILE=${2}
DPT_REGISTRY_URL=${3}
API_VERSION=${4}
VAULT_TOKEN=${5}
PTP_API_KEY=${6}

# Shift the first 6 arguments (reserved for specific variables) so that "$@" contains only files to attach
shift 6

# Convert remaining arguments into an array
IFS=' ' read -r -a FILES_TO_ATTACH <<< "$@"

# Register test results on XRAY Test Management
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

# Get JIRA URL from DPT Registry
response=$(curl -s -X 'GET' "${DPT_REGISTRY_URL}/${API_VERSION}/configuration/jira_url" \
    -H 'accept: application/json' \
    -H "X-API-Key: ${PTP_API_KEY}" \
    -H 'Content-Type: application/json')

JIRA_URL=$(echo "${response}" | jq -r '.value // empty')
if [[ -z "${JIRA_URL}" ]]; then
    echo "[ERROR] JIRA URL Failed! ${response}"
    exit 1
fi

# Get XRAY URL from DPT Registry
response=$(curl -s -X 'GET' "${DPT_REGISTRY_URL}/${API_VERSION}/configuration/xray_url" \
    -H 'accept: application/json' \
    -H "X-API-Key: ${PTP_API_KEY}" \
    -H 'Content-Type: application/json')

XRAY_URL=$(echo "${response}" | jq -r '.value // empty')
if [[ -z "${XRAY_URL}" ]]; then
    echo "[ERROR] XRAY URL Failed! ${response}"
    exit 1
fi

# Get JIRA and XRAY Tokens from Vault
response=$(curl -s \
    --header "X-Vault-Token: ${VAULT_TOKEN}" \
    --request GET ${VAULT_URL}/v1/devplatforms/data/performance-platform/application)

JIRA_TOKEN=$(echo "${response}" | jq -r '.data.data.jira_token // empty')
XRAY_CLIENT_ID=$(echo "${response}" | jq -r '.data.data.xray_client_id // empty')
XRAY_CLIENT_SECRET=$(echo "${response}" | jq -r '.data.data.xray_client_secret // empty')

if [[ -z "${JIRA_TOKEN}" || -z "${XRAY_CLIENT_ID}" || -z "${XRAY_CLIENT_SECRET}" ]]; then
    echo "[ERROR] Failed to retrieve data from Vault."
    exit 1
fi

echo "[INFO] Authenticating with XRAY Test Management..."
response=$(curl -s -X POST \
    -H "Content-Type: application/json" \
	--data "{\"client_id\": \"${XRAY_CLIENT_ID}\", \"client_secret\": \"${XRAY_CLIENT_SECRET}\"}" \
	${XRAY_URL}/authenticate)

# Check if the response contains the expected message
if [[ "${response}" != *"error"* ]]; then
    XRAY_TOKEN=$(echo "${response}" | sed 's/"//g')
else
    echo "[ERROR] Registration failed! ${response}"
    exit 1
fi

echo "[INFO] Registering test results on XRAY Test Management..."
response=$(curl -s -X 'POST' \
    -H "Content-Type: multipart/form-data" \
	-H "Authorization: Bearer ${XRAY_TOKEN}" \
	-F "info=@${TEST_DEFINITION_FILE};type=application/json" \
	-F "results=@${RESULTS_FILE};type=text/xml" \
	${XRAY_URL}/import/execution/junit/multipart)

# Check if the response contains the expected message
if [[ "${response}" != *"error"* ]]; then
    ID=$(echo "${response}" | jq -r '.id // empty')
    TEST_EXEC_KEY=$(echo "${response}" | jq -r '.key // empty')
    if [[ -z "${ID}" || -z "${TEST_EXEC_KEY}" ]]; then
        echo "[ERROR] Registration failed! ${response}"
        exit 1
    else
        echo "[INFO] Registration Successfull. ID: $ID and Test Execution Key: ${TEST_EXEC_KEY}"
    fi
else
    echo "[ERROR] Registration failed! ${response}"
    exit 1
fi

# Change the status of the XRAY Test Execution to "Test Executions"
echo  "[INFO] Changing the status of the XRAY Test Execution..."
curl -s -X POST "$JIRA_URL/2/issue/$TEST_EXEC_KEY/transitions" \
    -H "Authorization: Basic $JIRA_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"transition\": {\"id\": \"61\"}}"

if [ $? -ne 0 ]; then
    echo "[ERROR] XRAY Task Execution status change failed!"
fi

# Attach files to JIRA Test Execution
echo "[INFO] Attaching files to JIRA Test Execution..."
for FILE in "${FILES_TO_ATTACH[@]}"; do
    if [[ -f "$FILE" ]]; then
        echo -n "   $FILE..."
        output=$(curl -s -X POST "$JIRA_URL/latest/issue/$TEST_EXEC_KEY/attachments" \
            -H "Authorization: Basic $JIRA_TOKEN" \
            -H "X-Atlassian-Token: no-check" \
            -H "Content-Type: multipart/form-data" \
            -F "file=@$FILE")
        echo " uploaded!"
    else
        echo " not found!"
    fi
done