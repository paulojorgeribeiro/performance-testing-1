#!/bin/bash

VAULT_TOKEN=${1}
VALID_PRINCIPALS=${2}

if [ -z "$VAULT_TOKEN" || -z "$VALID_PRINCIPALS" ]; then
  echo "Usage: $0 <vault_token> <valid_principals>"
  exit 1
fi

response=$(curl -s --request POST \
  --header "X-Vault-Token: ${VAULT_TOKEN}" \
  http://dcvx-jmtapp-g1:8200/v1/auth/token/renew-self)

echo $response | jq

PUBKEY=$(<$HOME/.ssh/id_rsa.pub)
response=$(curl -s --header "X-Vault-Token: ${VAULT_TOKEN}" \
     --request POST \
     --data "{\"public_key\":\"$PUBKEY\", \"valid_principals\": \"${VALID_PRINCIPALS}\", \"ttl\": \"720h\"}" \
     http://dcvx-jmtapp-g1:8200/v1/ssh/sign/ptp-ssh-role)

echo $response | jq

new_signed_key=$(echo $response | jq -r '.data.signed_key')
echo $new_signed_key > $HOME/id_rsa_cert.pub
