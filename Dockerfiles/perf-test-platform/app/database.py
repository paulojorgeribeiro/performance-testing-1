# database.py
import os, urllib.parse, hvac
from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker

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
db_username = secret_response['data']['data']['db_app_user']
db_password = secret_response['data']['data']['db_app_password']
db_host = secret_response['data']['data'].get('db_server')
db_name = secret_response['data']['data'].get('db_name')
db_server_port = secret_response['data']['data'].get('db_server_port')

# Build your DB URL
SQLALCHEMY_DATABASE_URL = f"postgresql://{db_username}:{db_password}@{db_host}:{db_server_port}/{db_name}"

engine = create_engine(SQLALCHEMY_DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
