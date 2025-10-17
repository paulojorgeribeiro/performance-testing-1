#!/bin/bash

# Export default URL and version environment variables
export DPT_REGISTRY_URL="http://dcvx-jmtapp-g1.mch.moc.sgps:8000"
export API_VERSION="v3"
export JIRA_URL="https://ecom4isi.atlassian.net/rest/api"
export VAULT_URL="http://dcvx-jmtapp-g1:8200"

# Get parameter from DPT Registry
# Usage: get_parameter <parameter_name>
get_parameter() {
    local PARAMETER="$1"
    local PTP_API_KEY="$2"

    response=$(curl -s -X 'GET' "${DPT_REGISTRY_URL}/${API_VERSION}/configuration/${PARAMETER}" \
        -H 'accept: application/json' \
        -H "X-API-Key: ${PTP_API_KEY}" \
        -H 'Content-Type: application/json')

    VALUE=$(echo "${response}" | jq -r '.value // empty')
    if [[ -z "${VALUE}" ]]; then
        echo "[ERROR] Failed! ${response}"
        exit 1
    else
        echo ${VALUE}
    fi
}

# Get execution data from running tests
# Usage: get_execution_data <parameter_name> <run_id>
get_execution_data() {
    local PARAMETER="$1"
    local RUN_ID="$2"
    local PTP_API_KEY="$3"

    response=$(curl -s -X 'GET' "${DPT_REGISTRY_URL}/${API_VERSION}/test-data?column=${PARAMETER}&run_id=${RUN_ID}" \
        -H 'accept: application/json' \
        -H "X-API-Key: ${PTP_API_KEY}" \
        -H 'Content-Type: application/json')

    if [[ "${response}" != *"No test execution found"* ]]; then
        VALUE=$(echo "${response}" | jq -r ".${PARAMETER}")
        echo ${VALUE}
    else
        echo "[ERROR] ${response}"
        exit 1
    fi
}

get_all_execution_data() {
    local RUN_ID="$1"
    local PTP_API_KEY="$2"

    response=$(curl -s -X 'GET' "${DPT_REGISTRY_URL}/${API_VERSION}/test-data-all?run_id=${RUN_ID}" \
        -H 'accept: application/json' \
        -H "X-API-Key: ${PTP_API_KEY}" \
        -H 'Content-Type: application/json')

    if [[ "${response}" != *"No test execution found"* ]]; then
        echo ${response}
    else
        echo "[ERROR] ${response}"
        exit 1
    fi
}

# Register test failure or success in DPT Registry
# Usage: register_test_complete <run_id> <status>
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

# Handle errors and register test failure
# Usage: handle_error <error_message> <run_id>
handle_error() {
    local ERROR_MESSAGE="$1"
    local RUN_ID="$2"
    local PTP_API_KEY="$3"

    echo "${ERROR_MESSAGE}"
    if [ ! -z "${RUN_ID}" ]; then
        register_test_complete "${RUN_ID}" "failed" "${PTP_API_KEY}"
    fi
    exit 1
}

# Generate a random container name with a suffix
# Usage: generate_container_name_with_suffix
generate_container_name_with_suffix() {
    local adjectives=("brave" "eager" "mighty" "silent" "witty" "jolly" "clever" "daring" "graceful" "radiant")
    local nouns=("turing" "lovelace" "curie" "hopper" "einstein" "galilei" "newton" "fermat" "noether" "bohr")

    local rand_adj=$((RANDOM % ${#adjectives[@]}))
    local rand_noun=$((RANDOM % ${#nouns[@]}))

    local base_name="${adjectives[$rand_adj]}_${nouns[$rand_noun]}"

    local suffix=$((RANDOM % 1000))
    echo "${base_name}_${suffix}"
}

# Download a file from Central Performance Testing GitHub repository
# Usage: download_file <file_type> <file_name> <github_token>
download_file() {
    local file_type="$1"
    local file_name="$2"
    local github_token="$3"
    local url="https://raw.githubusercontent.com/mcdigital-devplatforms/performance-testing/${SCRIPT_VERSION}/${file_type}/${file_name}"

    http_status=$(curl -s -w "%{http_code}" -H "Authorization: token ${github_token}" \
        -H "Accept: application/vnd.github.v3.raw" \
        -o "/tmp/${file_name}" \
        "${url}")

    if [[ "$http_status" -ne 200 ]]; then
    echo "[ERROR] Error accessing repository. HTTP status: $http_status"
    exit 1
    fi

    if [ -f "/tmp/${file_name}" ]; then
        echo "[INFO] Successfully downloaded ${file_name}."
        remote_file_md5=$(md5sum "/tmp/${file_name}" | awk '{print $1}') 

        if [ -f "${HOME}/${file_name}" ]; then
            # If the file already exists in the home directory, compare MD5 checksums
            local_file_md5=$(md5sum "${HOME}/${file_name}" | awk '{print $1}')
        else
            # If the file does not exist, set local_file_md5 to an empty string
            local_file_md5=""
        fi

        if [ "$local_file_md5" != "$remote_file_md5" ]; then
            # Files are different
            echo "[INFO] New version detected of file ${file_name}."
            mv "/tmp/${file_name}" "${HOME}/${file_name}" && chmod 755 "${HOME}/${file_name}"
        else
            rm "/tmp/${file_name}"
        fi
    else
        echo "[ERROR] Failed to download ${file_name}."
        exit 1
    fi
}