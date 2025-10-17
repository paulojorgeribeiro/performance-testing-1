# endpoints.py
from fastapi import APIRouter, FastAPI, HTTPException, Depends, Response, Query
from fastapi.responses import HTMLResponse
from sqlalchemy.orm import Session
from sqlalchemy import desc, func
import models
from database import engine, get_db
from datetime import datetime
import uuid
from . import schemas

router = APIRouter()

@router.post("/register")
def register_test(req: schemas.RegisterRequest, db: Session = Depends(get_db)):
    # Default to 0 if factor is None
    new_factor = float(req.factor) if req.factor is not None else 0.0

    # Sum the factor of all currently running tests (treat NULL as 0)
    current_sum = db.query(func.coalesce(func.sum(models.TestExecution.factor), 0.0))\
        .filter(models.TestExecution.status == "running").scalar()
    current_sum = float(current_sum) if current_sum is not None else 0.0

    # Check if adding the new test would exceed 1
    if current_sum + new_factor > 1.0:
        return {
            "message": (
                f"Cannot register test: sum of running factors ({current_sum:.2f}) "
                f"+ new test factor ({new_factor:.2f}) would exceed 1.0"
            )
        }

    # Find the current max run_id
    max_run_id = db.query(models.TestExecution.run_id).order_by(models.TestExecution.run_id.desc()).first()
    next_run_id = (max_run_id[0] + 1) if max_run_id and max_run_id[0] is not None else 1

    test_id = uuid.uuid4()
    new_test = models.TestExecution(
        id=test_id,
        run_id=next_run_id,
        repo=req.repo,
        lac=req.lac,
        stream=req.stream,
        test=req.test,
        type=req.type,
        environment=req.environment,
        triggered_by=req.triggered_by,
        status="running",
        start_time=datetime.utcnow(),
        factor=req.factor,
        dashboard_url=req.dashboard_url,
        location=req.location,
        container_name=req.container_name,
        execution_type=req.execution_type  # New field for execution type
    )
    db.add(new_test)
    db.commit()
    db.refresh(new_test)
    return {"message": "Test registered", "run_id": str(next_run_id), "test_id": str(test_id)}

@router.post("/complete")
def complete_test(req: schemas.CompleteRequest, db: Session = Depends(get_db)):
    test = db.query(models.TestExecution).filter(
        models.TestExecution.run_id == req.run_id,
        models.TestExecution.status == "running"
    ).first()
    if not test:
        raise HTTPException(status_code=404, detail="Running test not found")
    test.status = req.status
    test.end_time = datetime.utcnow()
    db.commit()
    return {"message": "Test marked as complete"}

@router.post("/cancel")
def cancel_test(run_id: str, db: Session = Depends(get_db)):
    test = db.query(models.TestExecution).filter(
        models.TestExecution.run_id == run_id,
        models.TestExecution.status == "running"
    ).first()
    if not test:
        raise HTTPException(status_code=404, detail="Running test not found")
    test.status = "cancelled"
    test.end_time = datetime.utcnow()
    db.commit()
    return {"message": "Test cancelled"}

@router.get("/status", response_model=dict)
def get_status(db: Session = Depends(get_db)):
    running = db.query(models.TestExecution).filter(models.TestExecution.status == "running").all()
    return {"running": [schemas.TestExecutionSchema.from_orm(t) for t in running]}

@router.get("/history", response_model=dict)
def get_history(db: Session = Depends(get_db)):
    executions = (
        db.query(models.TestExecution)
        .order_by(models.TestExecution.start_time.desc())
        .all()
    )
    return {"executions": [schemas.TestExecutionSchema.from_orm(t) for t in executions]}
