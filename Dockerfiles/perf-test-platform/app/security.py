import os, hvac
from fastapi import Security, HTTPException, status, Depends
from fastapi.security.api_key import APIKeyHeader

# Set your Vault details (in production, pull these from environment variables)
vault_url = os.environ.get("VAULT_URL")
vault_token = os.environ.get("VAULT_TOKEN")

# Initialize Vault client
client = hvac.Client(url=vault_url, token=vault_token)

# Retrieve secret from Vault (update the path to match your setup)
secret_response = client.secrets.kv.v1.read_secret(
    path='/data/performance-platform/application',
    mount_point='devplatforms'
)

# Extract credentials
API_KEY = secret_response['data']['data']['ptp_api_key']
API_KEY_NAME = "X-API-Key"
api_key_header = APIKeyHeader(name=API_KEY_NAME, auto_error=True)

def get_api_key(api_key: str = Security(api_key_header)):
    if api_key != API_KEY:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or missing API Key",
        )
