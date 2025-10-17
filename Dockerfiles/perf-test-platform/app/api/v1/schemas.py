# schemas.py
from pydantic import BaseModel
from typing import Optional
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

    class Config:
        orm_mode = True
