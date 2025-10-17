# main.py
from fastapi import FastAPI, HTTPException, Depends, Response, Query
from fastapi.responses import HTMLResponse
from sqlalchemy.orm import Session
from sqlalchemy import desc, func
import models
from database import engine, get_db
from datetime import datetime
import uuid
from api.v1 import endpoints as v1_endpoints
from api.v2 import endpoints as v2_endpoints
from api.v3 import endpoints as v3_endpoints
from security import get_api_key  

models.Base.metadata.create_all(bind=engine)

app = FastAPI(
    title="Performance Test Execution Registry",
    description="Central API to control and track performance test executions",
    version="2.0.0"
)

# Include version-specific routers
app.include_router( v3_endpoints.router, prefix="/v3", tags=["v3"], dependencies=[Depends(get_api_key)])
app.include_router( v2_endpoints.router, prefix="/v2", tags=["v2"])
#app.include_router( v1_endpoints.router, prefix="/v1", tags=["v1"])
    
@app.get("/")
def root():
    return {
        "message": "Performance Test API",
        "available_versions": ["v1", "v2"],
        "current_version": "v2"
    }