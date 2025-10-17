#!/bin/bash
# This script is used to run JMeter tests in a containerized environment.
# It sets up the environment, downloads test definitions and data, runs the tests, and collects results.
# It also cleans up the environment after the tests are completed.

EXECUTION_TYPE="${1}"
GITHUB_TOKEN="${2}"
REPO="${3}"
TEST_DEFINITION_FILE="${4}"
TEST_DATA_FILE="${5}"
LAC_ID="${6}"
TEST_ID="${7}"
CONTAINER_NAME="${8}"
TEST_HOME="${9}"
TOOL_PARAMS="${10}"
STREAM="${11}"
TEST_TYPE="${12}"
ENVIRONMENT="${13}"
SSH_USER="${14}"
SSH_HOST="${15}"
FACTOR="${16}"
DASHBOARD_URL="${17}"
LOCATION="${18}"
SLAVE_SERVERS="${19}"
GITHUB_REF_NAME="${20}"
RUN_ID="${21}"
DPT_REGISTRY_URL="${22}"
API_VERSION="${23}"
VAULT_TOKEN="${24}"
PTP_API_KEY="${25}"
AUTHENTICATION="${26}"

RAM=14336 # 14GB RAM Max for container
CPU=4 # 4 CPU Max for container

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
    handle_error "[ERROR] Failed to create directory /home/$SSH_USER/${LAC_ID}/${TEST_ID}" ${RUN_ID} "${PTP_API_KEY}"

# Fetching test data and definition files from GitHub
echo  "[INFO] Fetching Test from Github..."
for file in $TEST_DATA_FILE; do
  echo "    Downloading $file..."
  curl -s -H "Authorization: token $GITHUB_TOKEN" \
       -H "Accept: application/vnd.github.v3.raw" \
       -o "$file" \
       "https://api.github.com/repos/$REPO/contents/$TEST_HOME/${LAC_ID}/${TEST_ID}/$file?ref=$GITHUB_REF_NAME" || \
         handle_error "[ERROR] Test Data Fail!" ${RUN_ID} "${PTP_API_KEY}"
done

curl -s -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3.raw" \
        -o $TEST_DEFINITION_FILE \
        https://api.github.com/repos/$REPO/contents/$TEST_HOME/${LAC_ID}/${TEST_ID}/$TEST_DEFINITION_FILE?ref=$GITHUB_REF_NAME || \
            handle_error "[ERROR] Test Definition Fail!" ${RUN_ID} "${PTP_API_KEY}"

# Fetching test metadata from GitHub
curl -s -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3.raw" \
        -o test-definition.json \
        https://api.github.com/repos/$REPO/contents/$TEST_HOME/${LAC_ID}/${TEST_ID}/test-definition.json?ref=$GITHUB_REF_NAME || \
            handle_error "[ERROR] Test Metadata (test-definition.json) Fail!" ${RUN_ID} "${PTP_API_KEY}"

# Count the number of slave servers into NUM_SLAVES
NUM_SLAVES=$(echo $SLAVE_SERVERS | tr ',' '\n' | wc -l)
PERCENT=$(echo "$FACTOR / $NUM_SLAVES" | bc -l | awk '{printf "%.2f", $0}')

# Set the max number of CPU and RAM for the container
LIMIT_RAM=$(echo "$RAM * $PERCENT" | bc -l | awk '{printf "%.0f", $0}')
LIMIT_CPU=$(echo "$CPU * $PERCENT"| bc -l | awk '{printf "%.0f", $0}')

# Replace authentication placeholders in TOOL_PARAMS using AUTHENTICATION JSON if provided
if [ "$AUTHENTICATION" != "none" ]; then
    UNENCODED_AUTHENTICATION=$(echo "$AUTHENTICATION" | base64 --decode)

    if ! echo "$UNENCODED_AUTHENTICATION" | jq empty >/dev/null; then
        handle_error "[ERROR] AUTHENTICATION is not a valid JSON object" "${RUN_ID}" "${PTP_API_KEY}"
    else
        # Build sed rules into a temp file
        RULES=$(mktemp)
        echo "$UNENCODED_AUTHENTICATION" \
            | jq -r 'to_entries[] | "\(.key)=\(.value)"' \
            | while IFS='=' read -r key value; do
                # Escape forward slashes and &
                esc_value=$(printf '%s\n' "$value" | sed -e 's/[\/&]/\\&/g')
                echo "s|<$key>|$esc_value|g"
              done > "$RULES"

        # Apply substitutions
        TOOL_PARAMS=$(echo "$TOOL_PARAMS" | sed -f "$RULES")

        rm -f "$RULES"
    fi
fi

# Test type specific parameters
if [ "$EXECUTION_TYPE" == "client-server" ]; then
    echo "[INFO] Launching SLAVE..."

    # Generate a random even port for RMI_PORT between 2000 and 30000. Add 1 to it for LOCAL_RMI_PORT.
    RMI_PORT=$(( 2000 + 2 * (RANDOM % (( (30000 - 2000) / 2 + 1)) ) ))
    LOCAL_RMI_PORT=$((RMI_PORT + 1))

    IFS=',' read -r -a SERVER_ARRAY <<< $SLAVE_SERVERS

    for SERVER in "${SERVER_ARRAY[@]}"; do

        # --cpus ${LIMIT_CPU} --memory ${LIMIT_RAM}m
        ssh -q $SSH_USER@$SERVER "podman run --replace -d --name ${CONTAINER_NAME} \
            -e RMI_PORT=${RMI_PORT} \
            -e LOCAL_RMI_PORT=${LOCAL_RMI_PORT} \
            -p ${LOCAL_RMI_PORT}:${LOCAL_RMI_PORT} \
            -p ${RMI_PORT}:${RMI_PORT} jmeter-server" || \
            handle_error "[ERROR] Failed to start on $SERVER" ${RUN_ID} "${PTP_API_KEY}"

        # Append server and port to SLAVE_HOSTS
        if [ -z "$SLAVE_HOSTS" ]; then
            SLAVE_HOSTS="$SERVER:$RMI_PORT"
        else
            SLAVE_HOSTS="$SLAVE_HOSTS,$SERVER:$RMI_PORT"
        fi

    done

    # Use Orchestration Server to run MASTER
    echo "[INFO] Launching MASTER..."
    echo " "
    echo "_________________________________________________________________________________"
    echo " "
    podman run --replace --network=host --name "${CONTAINER_NAME}" -e SLAVE_HOSTS="${SLAVE_HOSTS}" -v /home/${SSH_USER}/"${LAC_ID}"/"${TEST_ID}":/opt/jmeter/staging jmeter-client "${TEST_DEFINITION_FILE}" "${TOOL_PARAMS}" || \
        handle_error "[ERROR] Failed to start MASTER" ${RUN_ID} "${PTP_API_KEY}"
    echo " "
    echo "_________________________________________________________________________________"
    echo " "

    # Verify results exist
    if [ ! -s "/home/$SSH_USER/${LAC_ID}/${TEST_ID}/results.jtl" ]; then
        handle_error "[ERROR] File results.jtl is empty or does not exist..." ${RUN_ID} "${PTP_API_KEY}"
    else
        cd /home/$SSH_USER/"${LAC_ID}"/"${TEST_ID}" && zip -q -r report.zip report/*
    fi

    FILES_TO_ATTACH=("results.jtl" "jmeter.log" "report.zip")

else 

    # Distributed execution # of workers depends on the test FACTOR
    echo "[INFO] Spliting test data files for distributed execution..."

    # Count the number of slave servers into NUM_SLAVES
    NUM_SLAVES=$(echo $SLAVE_SERVERS | tr ',' '\n' | wc -l)

     for file in $TEST_DATA_FILE; do
     
        # Preserve the header and split the file into chunks  
        HEADER=$(head -n 1 "$file")
        TOTAL_LINES=$(($(wc -l < "$file") - 1))
        LINES_PER_CHUNK=$(( (TOTAL_LINES + NUM_SLAVES - 1) / NUM_SLAVES ))

        if [ $TOTAL_LINES -eq 0 ]; then
            handle_error "[ERROR] File $file is empty or does not exist..." ${RUN_ID} "${PTP_API_KEY}"
        fi

        tail -n +2 "$file" | split -l "$LINES_PER_CHUNK" -d -a 2 - "${file}-data-"

        # Add the header to each split file
        for FILEN in ${file}-data-*; do
            echo "$HEADER" > "split-$(basename $FILEN)"
            cat "$FILEN" >> "split-$(basename $FILEN)"
            rm "$FILEN"
        done

    done

    IFS=',' read -r -a SERVER_ARRAY <<< $SLAVE_SERVERS

    i=0
    for SERVER in "${SERVER_ARRAY[@]}"; do
        
        # Create a directory for the test files
        ssh -q $SSH_USER@$SERVER "rm -rf /home/$SSH_USER/${LAC_ID}/${TEST_ID}; mkdir -p /home/$SSH_USER/${LAC_ID}/${TEST_ID}"

        # Copy the test data file to each server
        for ORIGINAL in ${TEST_DATA_FILE}; do
               
            # Copy file to each server (fixed PATH)
            num=$(printf "%02d" "$i")
            scp -q split-${ORIGINAL}-data-${num} $SSH_USER@$SERVER:/home/$SSH_USER/${LAC_ID}/${TEST_ID}/$ORIGINAL

        done

        # Copy the test definition file to each server
        scp -q $TEST_DEFINITION_FILE $SSH_USER@$SERVER:/home/$SSH_USER/${LAC_ID}/${TEST_ID}/
        
        # Copy the test-definition.json file to each server
        scp -q test-definition.json $SSH_USER@$SERVER:/home/$SSH_USER/${LAC_ID}/${TEST_ID}/

        echo "[INFO] Starting test..."

        # Run on each server
        # --cpus ${LIMIT_CPU} --memory ${LIMIT_RAM}m
        { ssh -q "$SSH_USER@$SERVER" "podman run --replace --name ${CONTAINER_NAME} \
            -v /home/${SSH_USER}/${LAC_ID}/${TEST_ID}:/opt/jmeter/staging \
            jmeter-test ${TEST_DEFINITION_FILE} ${TOOL_PARAMS}" || \
            handle_error "[ERROR] Failed to start on $SERVER" "${RUN_ID}" "${PTP_API_KEY}"
        } &
     
        i=$((i + 1))

    done
    # Wait for all servers to finish execution
    wait

    # Prepare files to attach
    FILES_TO_ATTACH=("results.jtl")

    # Copy results back to the master server
    echo "[INFO] Copying results back to server..."
    for SERVER in "${SERVER_ARRAY[@]}"; do
        scp -q $SSH_USER@$SERVER:/home/$SSH_USER/${LAC_ID}/${TEST_ID}/results.jtl /home/$SSH_USER/${LAC_ID}/${TEST_ID}/results.jtl-$SERVER
        scp -q $SSH_USER@$SERVER:/home/$SSH_USER/${LAC_ID}/${TEST_ID}/jmeter.log /home/$SSH_USER/${LAC_ID}/${TEST_ID}/jmeter.log-$SERVER
        ssh -q $SSH_USER@$SERVER "cd /home/$SSH_USER/${LAC_ID}/${TEST_ID} && zip -q -r report.zip report/*" && \
            scp -q $SSH_USER@$SERVER:/home/$SSH_USER/${LAC_ID}/${TEST_ID}/report.zip /home/$SSH_USER/${LAC_ID}/${TEST_ID}/report.zip-$SERVER

        FILES_TO_ATTACH+=("report.zip-${SERVER}" "jmeter.log-${SERVER}")
    done

    # Merge results from all slave servers
    echo "[INFO] Merging results from all servers..."

    # Initialize the merged file with the header from the first JTL
    head -1 "results.jtl-${SERVER_ARRAY[0]}" > merged.jtl

    for SERVER in "${SERVER_ARRAY[@]}"; do
        tail -n +2 results.jtl-$SERVER >> merged.jtl
    done

    # Rename the merged file to results.jtl
    mv merged.jtl results.jtl

fi

if [ $? -ne 0 ]; then
    handle_error "[ERROR] Test execution failed!" ${RUN_ID} "${PTP_API_KEY}"
fi

# Convert results.jtl to JUnit XML format results-junit.xml
echo  "[INFO] Converting results.jtl to JUnit XML format..."
if ! /tmp/convert2junit.py csv results.jtl "test-definition.json" results-junit.xml; then
    handle_error "[ERROR] JTL to JUnit XML conversion failed!" ${RUN_ID} "${PTP_API_KEY}"
else
    # Register test results on XRAY Test Management
    if ! /tmp/run-test-JIRA.sh "test-definition.json" "results-junit.xml" "${DPT_REGISTRY_URL}" "${API_VERSION}" "${VAULT_TOKEN}" "${PTP_API_KEY}" "${FILES_TO_ATTACH[@]}" ; then
        handle_error "[ERROR] Failed to register test results on XRAY Test Management!" ${RUN_ID} "${PTP_API_KEY}"
    else
        echo "[INFO] Test results registered successfully on XRAY Test Management!"
        register_test_complete "$RUN_ID" "success" "${PTP_API_KEY}"
    fi
fi
