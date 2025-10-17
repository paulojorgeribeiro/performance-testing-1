#!/bin/bash
# Script to run performance tests on a remote host. Retrieves configuration and latest version of scripts from a GitHub repository, using secrets from Hashicorp Vault, and executes the tests.

echo "[INFO] Starting test run..."
echo "[INFO] Defining runtime variables..."

GITHUB_TOKEN="${1}"
REPO="${2}"
LAC_ID="${3}"
TEST_ID="${4}"
TEST_HOME="${5}"
USER="${6}"
GITHUB_REF_NAME="${7}"
VAULT_TOKEN="${8}"
AUTHENTICATION="${9:-none}"
SCRIPT_VERSION="${10}"

if [ -f ${HOME}/run-test-lib.sh ]; then
    source ${HOME}/run-test-lib.sh
else
    echo "[ERROR] Failed to load libs"
    exit 1
fi

PTP_API_KEY=$(curl -s \
   --header "X-Vault-Token: ${VAULT_TOKEN}" \
   --request GET ${VAULT_URL}/v1/devplatforms/data/performance-platform/application | jq -r '.data.data.ptp_api_key // empty')

if [ -z "${PTP_API_KEY}" ]; then
    echo "[ERROR] Failed to retrieve API_KEY from Vault."
    exit 1
else
    export PTP_API_KEY=${PTP_API_KEY}
fi

# Get VAULT URL .
response=$(curl -s -X 'GET' "${DPT_REGISTRY_URL}/${API_VERSION}/configuration/vault_url" \
    -H 'accept: application/json' \
    -H "X-API-Key: ${PTP_API_KEY}" \
    -H 'Content-Type: application/json')

VAULT_URL=$(echo "${response}" | jq -r '.value // empty')
if [[ -z "${VAULT_URL}" ]]; then
    echo "[ERROR] VAULT URL Failed! ${response}"
    exit 1
fi

# Get Github App PEM from Vault and generate a JWT to get an installation token
GITHUB_APP_PEM=$(curl -s \
   --header "X-Vault-Token: ${VAULT_TOKEN}" \
   --request GET ${VAULT_URL}/v1/devplatforms/data/performance-platform/application | jq -r '.data.data.github_app_pem // empty')

if [ -z "${GITHUB_APP_PEM}" ]; then
    echo "[ERROR] Failed to retrieve GITHUB_APP_PEM from Vault."
    exit 1
else
    APP_ID="1901339"
    INSTALLATION_ID="84468745"
    
    # Step 1: Create a JWT
    # Header: {"alg":"RS256","typ":"JWT"}
    header=$(echo -n '{"alg":"RS256","typ":"JWT"}' | openssl base64 -A | tr -d '=' | tr '/+' '_-')

    # Payload: {"iat": <now>, "exp": <now+600>, "iss": <app_id>}
    now=$(date +%s)

    # Expiration max = 10 minutes (600s).
    exp=$((now + 600))

    payload=$(echo -n "{\"iat\":$now,\"exp\":$exp,\"iss\":$APP_ID}" | openssl base64 -A | tr -d '=' | tr '/+' '_-')

    unsigned_token="$header.$payload"

    signature=$(echo -n "$unsigned_token" | openssl dgst -sha256 -sign <(echo -n "$GITHUB_APP_PEM") | openssl base64 -A | tr -d '=' | tr '/+' '_-')

    jwt="$unsigned_token.$signature"

    # Step 2: Exchange JWT for installation access token
    response=$(curl -s -X POST \
    -H "Authorization: Bearer $jwt" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/app/installations/$INSTALLATION_ID/access_tokens")

    export PTP_GITHUB_TOKEN=$(echo "$response" | grep -oP '"token":\s*"\K[^"]+')
fi

# Renew Vault token everytime the script runs.
# This is optional, but can be useful if the token has a short TTL.
response=$(curl -s --request POST \
   --header "X-Vault-Token: ${VAULT_TOKEN}" \
   ${VAULT_URL}/v1/auth/token/renew-self)

if [[ "${response}" == *"errors"* ]]; then
    echo "[ERROR] Failed to renew Vault token! ${response}"
else
    echo "[INFO] Vault token renewed successfully."
    export VAULT_TOKEN=${VAULT_TOKEN}
fi

# Renew SSH Certificate (to access with jmeter login) on every run from more 30 days.
PUBKEY=$(<${HOME}/.ssh/id_rsa.pub)
response=$(curl -s --header "X-Vault-Token: ${VAULT_TOKEN}" \
     --request POST \
     --data "{\"public_key\":\"${PUBKEY}\", \"valid_principals\": \"jmeter\", \"ttl\": \"720h\"}" \
     ${VAULT_URL}/v1/ssh/sign/ptp-ssh-role)

if [[ "${response}" != *"errors"* ]]; then
    echo ${response} | jq -r '.data.signed_key' > ${HOME}/.ssh/id_rsa_cert.pub
    chmod 600 ${HOME}/.ssh/id_rsa_cert.pub
    echo "[INFO] SSH Certificate renewed successfully."
else
    echo "[ERROR] Failed to renew SSH Certificate! ${response}"
fi

echo "[INFO] Fetching latest script version from GitHub Performance Testing Repository..."
if [ -z "${SCRIPT_VERSION}" ]; then
    export SCRIPT_VERSION=$(curl -s -H "Authorization: token ${PTP_GITHUB_TOKEN}" \
    "https://api.github.com/repos/${REPO}/releases/latest" | jq -r '.tag_name')
else
    export SCRIPT_VERSION=${SCRIPT_VERSION}
fi

# Download the run-test-lib.sh from Github Performance Testing Repository
download_file "shell" "run-test-lib.sh" "${PTP_GITHUB_TOKEN}"

# Download the run-test.sh from Github Performance Testing Repository
download_file "shell" "run-test.sh" "${PTP_GITHUB_TOKEN}"

# Get the test definition file from Github
curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3.raw" \
        -o test-definition.json \
        https://api.github.com/repos/${REPO}/contents/${TEST_HOME}/${LAC_ID}/${TEST_ID}/test-definition.json?ref=${GITHUB_REF_NAME}

if [ $? -ne 0 ]; then
    echo "[ERROR] Test Metadata (test-definition.json) Fail!"
    exit 1
fi

for TYPE in $(jq -r '.test | keys[]' test-definition.json); do

    case "${TYPE}" in
        "performance")
        
            # Get cleanup script from Github Performance Testing Repository
            download_file "shell" "cleanup-remote-job.sh" "${PTP_GITHUB_TOKEN}"

            # Get init script from Github Performance Testing Repository
            download_file "shell" "run-test-performance.sh" "${PTP_GITHUB_TOKEN}"

            # Get JIRA script from Github Performance Testing Repository
            download_file "shell" "run-test-JIRA.sh" "${PTP_GITHUB_TOKEN}"

            # Run the main script with the EXPORTED parameters
            ${HOME}/run-test-performance.sh \
                "${GITHUB_TOKEN}" \
                "${REPO}" \
                "${LAC_ID}" \
                "${TEST_ID}" \
                "${TEST_HOME}" \
                "${USER}" \
                "${GITHUB_REF_NAME}" \
                "${VAULT_TOKEN}" \
                "${PTP_GITHUB_TOKEN}" \
                "${PTP_API_KEY}" \
                "${AUTHENTICATION}" \
                "${SCRIPT_VERSION}" || \
                handle_error "[ERROR] Test run failed!"

            ;;
        "resilience")

            # Get init script from Github Performance Testing Repository
            download_file "shell" "run-test-resilience.sh" "${PTP_GITHUB_TOKEN}"

            # Get JIRA script from Github Performance Testing Repository
            download_file "shell" "run-test-JIRA.sh" "${PTP_GITHUB_TOKEN}"

            # Run the main script with the EXPORTED parameters
            ${HOME}/run-test-resilience.sh \
                "${GITHUB_TOKEN}" \
                "${REPO}" \
                "${LAC_ID}" \
                "${TEST_ID}" \
                "${TEST_HOME}" \
                "${USER}" \
                "${GITHUB_REF_NAME}" \
                "${VAULT_TOKEN}" \
                "${PTP_GITHUB_TOKEN}" \
                "${PTP_API_KEY}" || \
                handle_error "[ERROR] Test run failed!"

            ;;
        *)
            echo "[ERROR] Unsupported test type: ${TYPE}"
            exit 1
            ;;
    esac

done

echo "[INFO] Test run completed."
