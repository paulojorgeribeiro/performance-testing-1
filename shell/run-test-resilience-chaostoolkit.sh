#!/bin/bash
# This script is used to run JMeter tests in a containerized environment.
# It sets up the environment, downloads test definitions and data, runs the tests, and collects results.
# It also cleans up the environment after the tests are completed.

EXECUTION_TYPE=${1}
GITHUB_TOKEN=${2}
REPO=${3}
TEST_DEFINITION_FILE=${4}
LAC_ID=${5}
TEST_ID=${6}
CONTAINER_NAME=${7}
TEST_HOME=${8}
TOOL_PARAMS=${9}
STREAM=${10}
TEST_TYPE=${11}
ENVIRONMENT=${12}
#USER=${13}
SSH_USER=${14}
SSH_HOST=${15}
DASHBOARD_URL=${16}
LOCATION=${17}
GITHUB_REF_NAME=${18}
RUN_ID=${19}
#JIRA_TOKEN=${20}
#JIRA_URL=${21}
DPT_REGISTRY_URL=${22}
API_VERSION=${23}
VAULT_TOKEN=${24}
PTP_API_KEY=${25}

register_test_complete() {
    local RUN_ID="$1"
    local STATUS="$2"
    local PTP_API_KEY="$3"

    curl -s -X 'POST' "$DPT_REGISTRY_URL/$API_VERSION/complete" \
        -H 'accept: application/json' \
        -H 'Content-Type: application/json' \
        -H "X-API-Key: ${PTP_API_KEY}" \
        -d "{ \"run_id\": $RUN_ID, \"status\": \"${STATUS}\" }"
}

handle_error() {
    local ERROR_MESSAGE="$1"
    local RUN_ID="$2"
    local PTP_API_KEY="$3"

    echo "${ERROR_MESSAGE}"
    if [ ! -z ${RUN_ID} ]; then
        register_test_complete "${RUN_ID}" "failed" "${PTP_API_KEY}"
    fi
    exit 1
}

# Preparing Orchestration Server
echo  "[INFO] Cleaning up files from previous runs..."
rm -rf /home/$SSH_USER/"${LAC_ID}"/"${TEST_ID}"

echo  "[INFO] Creating test directory..."
mkdir -p /home/$SSH_USER/"${LAC_ID}"/"${TEST_ID}" && cd /home/$SSH_USER/"${LAC_ID}"/"${TEST_ID}" || \
    handle_error "[ERROR] Failed to create directory /home/$SSH_USER/${LAC_ID}/${TEST_ID}" ${RUN_ID} ${PTP_API_KEY}

curl -s -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3.raw" \
        -o $TEST_DEFINITION_FILE \
        https://api.github.com/repos/$REPO/contents/$TEST_HOME/${LAC_ID}/${TEST_ID}/$TEST_DEFINITION_FILE?ref=$GITHUB_REF_NAME || \
            handle_error "[ERROR] Test Definition Fail!" ${RUN_ID}

# Execute the resilience test
echo "[INFO] Running resilience test with Chaostoolkit..."
podman run -it --rm --name chaostoolkit \
        -v /home/$SSH_USER/${LAC_ID}/${TEST_ID}:/experiments \
        chaostoolkit:latest \
        chaos run --log-file /experiments/chaostoolkit.log \
            /experiments/${TEST_DEFINITION_FILE} \
            --journal-path /experiments/journal.json 

# source ${HOME}/chaostoolkit/bin/activate
# chaos --log-file /home/$SSH_USER/${LAC_ID}/${TEST_ID}/chaostoolkit.log \
#     --log-format string \
#     run /home/$SSH_USER/${LAC_ID}/${TEST_ID}/experiment.json \
#     --journal-path /home/$SSH_USER/${LAC_ID}/${TEST_ID}/journal.json

if [ $? -ne 0 ]; then
    handle_error "[ERROR] Test execution failed!" ${RUN_ID} ${PTP_API_KEY}
fi

# Generate the output report for JIRA/XRAY Test Management
echo "[INFO] Generating test report..."
podman run -it --rm --name chaostoolkit \
    -v /home/$SSH_USER/${LAC_ID}/${TEST_ID}:/experiments \
    chaostoolkit:latest chaos report --export-format=html /experiments/journal.json /experiments/resilience-report.html

# chaos report --export-format=html \
#     /home/$SSH_USER/${LAC_ID}/${TEST_ID}/journal.json \
#     /home/$SSH_USER/${LAC_ID}/${TEST_ID}/resilience-report.html

if [ $? -ne 0 ]; then
    handle_error "[ERROR] Test execution failed!" ${RUN_ID} ${PTP_API_KEY}
fi

# Convert output in json to JUnit XML format 
echo  "[INFO] Converting journal.json to JUnit XML format..."
if ! /tmp/convert2junit.py json journal.json "NULL" journal-junit.xml; then
    handle_error "[ERROR] JTL to JUnit XML conversion failed!" ${RUN_ID} ${PTP_API_KEY}
else
    # Files to attach to the JIRA issue
    FILES_TO_ATTACH=("journal.json chaostoolkit.log resilience-report.html")

    # Register test results on XRAY Test Management
    if ! /tmp/run-test-JIRA.sh "test-definition.json" "journal-junit.xml" "${DPT_REGISTRY_URL}" "${API_VERSION}" "${VAULT_TOKEN}" "${PTP_API_KEY}" "${FILES_TO_ATTACH[@]}" ; then
        handle_error "[ERROR] Failed to register test results on XRAY Test Management!" ${RUN_ID} ${PTP_API_KEY}
    else
        echo "[INFO] Test results registered successfully on XRAY Test Management!"
        register_test_complete "$RUN_ID" "success" "$PTP_API_KEY"
    fi
fi
