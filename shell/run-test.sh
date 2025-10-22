#!/usr/bin/env bash
set -euo pipefail

echo "[INFO] Starting test run..."
echo "[INFO] Defining runtime variables..."

# Args (mantêm a mesma ordem do teu workflow)
GITHUB_TOKEN="${1}"
REPO="${2}"
LAC_ID="${3}"
TEST_ID="${4}"
TEST_HOME="${5}"          # ← no workflow passamos ${{ github.workspace }}
USER_NAME="${6}"
GITHUB_REF_NAME="${7}"
VAULT_TOKEN="${8}"
AUTHENTICATION="${9:-none}"
SCRIPT_VERSION="${10:-}"

# Caminhos locais (a partir do repositório, não do $HOME)
SHELL_DIR="${TEST_HOME}/shell"
LIB_PATH="${SHELL_DIR}/run-test-lib.sh"

if [[ ! -f "${LIB_PATH}" ]]; then
  echo "[ERROR] Failed to load libs at ${LIB_PATH}"
  exit 1
fi
# shellcheck disable=SC1090
source "${LIB_PATH}"

# 1) Obter VAULT_URL via DPT Registry (antes de falar com o Vault!)
echo "[INFO] Resolving VAULT URL from DPT Registry..."
if [[ -z "${DPT_REGISTRY_URL:-}" || -z "${API_VERSION:-}" ]]; then
  echo "[ERROR] DPT_REGISTRY_URL or API_VERSION not set in environment."
  exit 1
fi

response=$(curl -sS -X GET "${DPT_REGISTRY_URL}/${API_VERSION}/configuration/vault_url" \
  -H 'accept: application/json' \
  -H "X-API-Key: ${PTP_API_KEY:-}" \
  -H 'Content-Type: application/json' || true)

VAULT_URL=$(echo "${response}" | jq -r '.value // empty')
if [[ -z "${VAULT_URL}" ]]; then
  echo "[ERROR] VAULT URL Failed! ${response}"
  exit 1
fi
echo "[INFO] VAULT_URL=${VAULT_URL}"

# 2) Obter PTP_API_KEY a partir do Vault (já com VAULT_URL conhecido)
echo "[INFO] Fetching PTP_API_KEY from Vault..."
PTP_API_KEY=$(curl -sS \
  --header "X-Vault-Token: ${VAULT_TOKEN}" \
  --request GET "${VAULT_URL}/v1/devplatforms/data/performance-platform/application" \
  | jq -r '.data.data.ptp_api_key // empty')

if [[ -z "${PTP_API_KEY}" ]]; then
  echo "[ERROR] Failed to retrieve API_KEY from Vault."
  exit 1
fi
export PTP_API_KEY

# 3) Obter PEM da GitHub App e gerar token de instalação
echo "[INFO] Getting GitHub App PEM and exchanging for installation token..."
GITHUB_APP_PEM=$(curl -sS \
  --header "X-Vault-Token: ${VAULT_TOKEN}" \
  --request GET "${VAULT_URL}/v1/devplatforms/data/performance-platform/application" \
  | jq -r '.data.data.github_app_pem // empty')

if [[ -z "${GITHUB_APP_PEM}" ]]; then
  echo "[ERROR] Failed to retrieve GITHUB_APP_PEM from Vault."
  exit 1
fi

APP_ID="1901339"
INSTALLATION_ID="84468745"

header=$(printf '{"alg":"RS256","typ":"JWT"}' | openssl base64 -A | tr -d '=' | tr '/+' '_-')
now=$(date +%s)
exp=$((now + 600))
payload=$(printf '{"iat":%s,"exp":%s,"iss":%s}' "$now" "$exp" "$APP_ID" | openssl base64 -A | tr -d '=' | tr '/+' '_-')
unsigned_token="${header}.${payload}"
signature=$(printf "%s" "$unsigned_token" | openssl dgst -sha256 -sign <(printf "%s" "$GITHUB_APP_PEM") | openssl base64 -A | tr -d '=' | tr '/+' '_-')
jwt="${unsigned_token}.${signature}"

response=$(curl -sS -X POST \
  -H "Authorization: Bearer ${jwt}" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/app/installations/${INSTALLATION_ID}/access_tokens")

export PTP_GITHUB_TOKEN
PTP_GITHUB_TOKEN=$(echo "${response}" | grep -oP '"token":\s*"\K[^"]+')
if [[ -z "${PTP_GITHUB_TOKEN}" ]]; then
  echo "[ERROR] Failed to obtain installation access token."
  echo "${response}"
  exit 1
fi

# 4) Renovar token do Vault (opcional)
echo "[INFO] Renewing Vault token..."
response=$(curl -sS --request POST \
  --header "X-Vault-Token: ${VAULT_TOKEN}" \
  "${VAULT_URL}/v1/auth/token/renew-self" || true)
if [[ "${response}" == *"errors"* ]]; then
  echo "[WARN] Failed to renew Vault token: ${response}"
else
  echo "[INFO] Vault token renewed successfully."
fi

# 5) Renovar certificado SSH (se existir chave pública)
if [[ -f "${HOME}/.ssh/id_rsa.pub" ]]; then
  echo "[INFO] Renewing SSH certificate..."
  PUBKEY=$(<"${HOME}/.ssh/id_rsa.pub")
  response=$(curl -sS --header "X-Vault-Token: ${VAULT_TOKEN}" \
    --request POST \
    --data "{\"public_key\":\"${PUBKEY}\", \"valid_principals\": \"jmeter\", \"ttl\": \"720h\"}" \
    "${VAULT_URL}/v1/ssh/sign/ptp-ssh-role" || true)
  if [[ "${response}" != *"errors"* ]]; then
    echo "${response}" | jq -r '.data.signed_key' > "${HOME}/.ssh/id_rsa_cert.pub"
    chmod 600 "${HOME}/.ssh/id_rsa_cert.pub"
    echo "[INFO] SSH Certificate renewed successfully."
  else
    echo "[WARN] Failed to renew SSH Certificate: ${response}"
  fi
else
  echo "[WARN] No ${HOME}/.ssh/id_rsa.pub found — skipping SSH cert renewal."
fi

# 6) Determinar versão do script (opcional) — podes manter ou remover
if [[ -z "${SCRIPT_VERSION}" ]]; then
  echo "[INFO] Fetching latest script version tag from GitHub..."
  SCRIPT_VERSION=$(curl -sS -H "Authorization: token ${PTP_GITHUB_TOKEN}" \
    "https://api.github.com/repos/${REPO}/releases/latest" | jq -r '.tag_name // empty')
  export SCRIPT_VERSION
  echo "[INFO] SCRIPT_VERSION=${SCRIPT_VERSION:-<none>}"
fi

# 7) Obter metadata do teste (do repositório de test-definitions)
echo "[INFO] Fetching test-definition.json..."
curl -sS -H "Authorization: token ${GITHUB_TOKEN}" \
     -H "Accept: application/vnd.github.v3.raw" \
     -o test-definition.json \
     "https://api.github.com/repos/${REPO}/contents/${TEST_HOME}/${LAC_ID}/${TEST_ID}/test-definition.json?ref=${GITHUB_REF_NAME}"

if [[ ! -s test-definition.json ]]; then
  echo "[ERROR] Test Metadata (test-definition.json) Fail!"
  exit 1
fi

# 8) Executar por tipo de teste
for TYPE in $(jq -r '.test | keys[]' test-definition.json); do
  case "${TYPE}" in
    "performance")
      echo "[INFO] Starting PERFORMANCE test..."
      bash "${SHELL_DIR}/cleanup-remote-job.sh" "${LAC_ID}" "${TEST_ID}" "${VAULT_TOKEN}" || true
      bash "${SHELL_DIR}/run-test-performance.sh" \
        "${GITHUB_TOKEN}" \
        "${REPO}" \
        "${LAC_ID}" \
        "${TEST_ID}" \
        "${TEST_HOME}" \
        "${USER_NAME}" \
        "${GITHUB_REF_NAME}" \
        "${VAULT_TOKEN}" \
        "${PTP_GITHUB_TOKEN}" \
        "${PTP_API_KEY}" \
        "${AUTHENTICATION}" \
        "${SCRIPT_VERSION}" || handle_error "[ERROR] Test run failed!"
      ;;
    "resilience")
      echo "[INFO] Starting RESILIENCE test..."
      bash "${SHELL_DIR}/run-test-resilience.sh" \
        "${GITHUB_TOKEN}" \
        "${REPO}" \
        "${LAC_ID}" \
        "${TEST_ID}" \
        "${TEST_HOME}" \
        "${USER_NAME}" \
        "${GITHUB_REF_NAME}" \
        "${VAULT_TOKEN}" \
        "${PTP_GITHUB_TOKEN}" \
        "${PTP_API_KEY}" || handle_error "[ERROR] Test run failed!"
      ;;
    *)
      echo "[ERROR] Unsupported test type: ${TYPE}"
      exit 1
      ;;
  esac
done

echo "[INFO] Test run completed."
