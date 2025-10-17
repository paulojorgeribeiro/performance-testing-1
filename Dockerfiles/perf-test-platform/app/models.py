# models.py
from sqlalchemy import Column, String, DateTime, Integer, Numeric
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.ext.declarative import declarative_base
import uuid

from database import Base

class TestExecution(Base):
    __tablename__ = "test_executions"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    run_id = Column(Integer, nullable=False)
    repo = Column(String(255), nullable=False)
    lac = Column(String(255), nullable=False)
    stream = Column(String(255), nullable=False)
    test = Column(String(255), nullable=False)
    type = Column(String(255), nullable=False)
    environment = Column(String(255), nullable=False)
    triggered_by = Column(String(255), nullable=False)
    status = Column(String(50), nullable=False)
    start_time = Column(DateTime(timezone=True), nullable=False)
    end_time = Column(DateTime(timezone=True), nullable=True)
    factor = Column(Numeric(3,2), nullable=False)
    dashboard_url = Column(String(255), nullable=True)
    location = Column(String(255), nullable=False)
    container_name = Column(String(255), nullable=False)
    execution_type = Column(String(50), nullable=False)
    workers = Column(JSONB, nullable=True)
    tool = Column(String(50), nullable=False)
    script_version = Column(String(8), nullable=False)

class Location(Base):
    __tablename__ = "locations"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    location = Column(String, nullable=False)
    servername = Column(String, nullable=False)
    type = Column(String, nullable=False)
    environment = Column(String, nullable=False)
    factor = Column(Numeric, nullable=False)
    status = Column(String, nullable=False)

class Configuration(Base):
    __tablename__ = "configurations"

    parameter = Column(String, nullable=False, unique=True, primary_key=True)
    value = Column(String, nullable=False)

