# schemas.py
from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime
from uuid import UUID
from decimal import Decimal

class RegisterRequest(BaseModel):
    repo: str
    lac: str
    stream: str
    test: str
    type: str
    environment: str
    triggered_by: str
    factor: Decimal
    dashboard_url: Optional[str] = None
    location: str
    container_name: str
    execution_type: str  # "distributed", "client-server", etc.
    workers: List[str]  # List of server names running the test
    tool: str
    script_version: str


class CompleteRequest(BaseModel):
    run_id: int
    status: str  # "success", "failure", "cancelled"

class TestExecutionSchema(BaseModel):
    id: UUID
    run_id: int
    repo: str
    lac: str
    stream: str
    test: str
    type: str
    environment: str
    triggered_by: str
    status: str
    start_time: datetime
    end_time: Optional[datetime]
    factor: Decimal
    dashboard_url: Optional[str] = None
    location: str
    container_name: str
    execution_type: str  # "distributed", "client-server", etc.
    workers: List[str]  # List of server names running the test
    tool: str
    script_version: str

    class Config:
        orm_mode = True

class LocationSchema(BaseModel):
    id : UUID
    location: str # "on-premise-vm", "azure-vm", "on-premise-k8s", "azure-k8s", etc.
    servername: str
    type: str # "orchestrator", "worker"
    environment: str # "PP", "PRD", "Staging", etc.
    factor: Decimal
    status: str # "up", "down"

    class Config:
        orm_mode = True


class ConfigurationSchema(BaseModel):
    parameter: str
    value: str

    class Config:
        orm_mode = True

class ConfigurationResponse(BaseModel):
    parameter: str
    value: str

class ConfigurationUpdateRequest(BaseModel):
    value: str

class ConfigurationCreateRequest(BaseModel):
    parameter: str
    value: str

