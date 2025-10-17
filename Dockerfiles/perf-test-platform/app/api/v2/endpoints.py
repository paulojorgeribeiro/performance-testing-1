# envpoints.py
from fastapi import APIRouter, FastAPI, HTTPException, Depends, Response, Query
from sqlalchemy.dialects.postgresql import JSONB
from fastapi.responses import HTMLResponse
from sqlalchemy.orm import Session
from sqlalchemy import desc, func, literal_column
import models
from database import engine, get_db
from datetime import datetime
import uuid
from . import schemas

router = APIRouter()

@router.post("/register")
def register_test(req: schemas.RegisterRequest, db: Session = Depends(get_db)):

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
        execution_type=req.execution_type,  # New field for execution type
        workers=req.workers,
        tool=req.tool,
        script_version=req.script_version
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

@router.get("/locations")
def get_location_factors(db: Session = Depends(get_db)):
    # Subquery: Explode workers and distribute factor
    running_load_subquery = (
        db.query(
            func.jsonb_array_elements_text(models.TestExecution.workers).label("worker_name"),
            models.TestExecution.location,
            models.TestExecution.environment,
            (models.TestExecution.factor / func.jsonb_array_length(models.TestExecution.workers)).label("worker_load")
        )
        .filter(models.TestExecution.status == "running")
        .subquery()
    )

    # Aggregate load per worker
    worker_load_summary = (
        db.query(
            running_load_subquery.c.worker_name.label("servername"),
            running_load_subquery.c.location,
            running_load_subquery.c.environment,
            func.sum(running_load_subquery.c.worker_load).label("running_sum")
        )
        .group_by(
            running_load_subquery.c.worker_name,
            running_load_subquery.c.location,
            running_load_subquery.c.environment
        )
        .subquery()
    )

    # Main query: Join locations with load summary
    results = (
        db.query(
            models.Location.location,
            models.Location.servername,
            models.Location.environment,
            models.Location.factor.label("location_factor"),
            func.coalesce(worker_load_summary.c.running_sum, 0).label("running_sum"),
            (models.Location.factor - func.coalesce(worker_load_summary.c.running_sum, 0)).label("available_factor"),
            models.Location.status
        )
        .outerjoin(
            worker_load_summary,
            (models.Location.location == worker_load_summary.c.location) &
            (models.Location.servername == worker_load_summary.c.servername) &
            (models.Location.environment == worker_load_summary.c.environment)
        )
        .filter(models.Location.type == "worker")
        .all()
    )

    return [
        {
            "location": row.location,
            "servername": row.servername,
            "environment": row.environment,
            "location_factor": float(row.location_factor),
            "running_sum": float(row.running_sum),
            "available_factor": float(row.available_factor),
            "status": row.status
        }
        for row in results
    ]

# Endpoints to get and set location status
@router.get("/location_status")
def get_locations_status(
    location: str = Query(..., description="Location name"),
    servername: str = Query(..., description="Server name"),
    db: Session = Depends(get_db)
):
    loc = (
        db.query(models.Location)
        .filter(models.Location.location == location)
        .filter(models.Location.servername == servername)
        .first()
    )
    if not loc:
        raise HTTPException(status_code=404, detail="Location/server not found")
    return {"location": location, "servername": servername, "status": loc.status}


@router.post("/location_status")
def set_location_status(
    location: str = Query(..., description="Location name"),
    servername: str = Query(..., description="Server name"),
    status: str = Query(..., description="New status"),
    db: Session = Depends(get_db)
):
    loc = (
        db.query(models.Location)
        .filter(models.Location.location == location)
        .filter(models.Location.servername == servername)
        .first()
    )
    if not loc:
        raise HTTPException(status_code=404, detail="Location/server not found")
    loc.status = status
    db.commit()
    return {"location": location, "servername": servername, "status": status}

@router.get("/workers")
def get_servers_to_run(
    location: str = Query(..., description="Location to filter servers"),
    environment: str = Query(..., description="Environment to filter servers"),
    factor: float = Query(..., gt=0, description="Total factor required"),
    db: Session = Depends(get_db)
):
    # Subquery: Calculate load per worker (only if tests are running)
    running_load_subquery = (
        db.query(
            func.jsonb_array_elements_text(models.TestExecution.workers).label("worker_name"),
            (models.TestExecution.factor / func.jsonb_array_length(models.TestExecution.workers)).label("worker_load"),
            models.TestExecution.location,
            models.TestExecution.environment
        )
        .filter(models.TestExecution.status == "running")
        .filter(models.TestExecution.environment == environment)
        .filter(models.TestExecution.location == location)
        .subquery()
    )

    # Aggregate load per worker
    worker_load_summary = (
        db.query(
            running_load_subquery.c.worker_name.label("servername"),
            running_load_subquery.c.location,
            running_load_subquery.c.environment,
            func.coalesce(func.sum(running_load_subquery.c.worker_load), 0).label("running_sum")
        )
        .group_by(
            running_load_subquery.c.worker_name,
            running_load_subquery.c.location,
            running_load_subquery.c.environment
        )
        .subquery()
    )

    # Main query: Join locations with load summary (handles empty load data)
    servers = (
        db.query(
            models.Location.servername,
            models.Location.location,
            models.Location.environment,
            models.Location.factor.label("location_factor"),
            func.coalesce(worker_load_summary.c.running_sum, 0).label("running_sum"),
            (models.Location.factor - func.coalesce(worker_load_summary.c.running_sum, 0)).label("available_factor")
        )
        .outerjoin(
            worker_load_summary,
            (models.Location.location == worker_load_summary.c.location) &
            (models.Location.servername == worker_load_summary.c.servername) &
            (models.Location.environment == worker_load_summary.c.environment)
        )
        .filter(models.Location.location == location)
        .filter(models.Location.environment == environment)
        .filter(models.Location.type == "worker")
        .filter(models.Location.status == "up")  # Only consider locations with status='up'        
        .order_by(desc("available_factor"))
        .all()
    )

    # Handle empty results
    if not servers:
        return {
            "message": f"No servers found for location '{location}' and environment '{environment}'"
        }

    # Convert to list format for response
    available_factors = [float(row.available_factor) for row in servers]
    servernames = [row.servername for row in servers]

    # Determine how many servers are needed
    if factor <= 1:
        # Find a single server with enough available_factor
        for idx, af in enumerate(available_factors):
            if af >= factor:
                return [servernames[idx]]
        return {
            "message": f"No single server found with available_factor > {factor} in location '{location}' and environment '{environment}'."
        }
    else:
        # Find the minimum number of servers such that each has available_factor > factor / number_of_servers
        n = 1
        while n <= len(available_factors):
            threshold = factor / n
            eligible = [i for i, af in enumerate(available_factors) if af >= threshold]
            if len(eligible) >= n:
                return [servernames[i] for i in eligible[:n]]
            n += 1
        return {
            "message": (
                f"Not enough servers to satisfy factor {factor} in location '{location}' and environment '{environment}'."
            )
        }

@router.get("/orchestrator")
def get_orchestrator_server(
    location: str = Query(..., description="Location to filter for orchestrator"),
    environment: str = Query(..., description="Environment to filter for orchestrator"),
    db: Session = Depends(get_db)
):
    orchestrator = db.query(models.Location.servername)\
        .filter(models.Location.location == location)\
        .filter(models.Location.environment == environment)\
        .filter(models.Location.type == "orchestrator")\
        .filter(models.Location.status == "up")\
        .first()
    if orchestrator:
        return {"servername": orchestrator.servername}
    return {"message": f"No orchestrator found for location '{location}' and environment '{environment}'"}

@router.get("/configuration/{parameter}")
def get_configuration(parameter: str, db: Session = Depends(get_db)):
    """
    Get configuration value by parameter name.

    Args:
        parameter: The configuration parameter name to retrieve

    Returns:
        JSON object with parameter, value, and last updated timestamp

    Raises:
        HTTPException: 404 if parameter not found
    """
    config = db.query(models.Configuration).filter(
        models.Configuration.parameter == parameter
    ).first()

    if not config:
        raise HTTPException(
            status_code=404,
            detail=f"Configuration parameter '{parameter}' not found"
        )

    return {
        "parameter": config.parameter,
        "value": config.value
    }

# POST endpoint - Update configuration value
@router.post("/configuration/{parameter}")
def update_configuration(
    parameter: str,
    req: schemas.ConfigurationUpdateRequest,
    db: Session = Depends(get_db)
):
    """
    Update configuration value by parameter name.

    Args:
        parameter: The configuration parameter name to update
        req: Request body containing the new value

    Returns:
        JSON object with updated parameter, value, and timestamp

    Raises:
        HTTPException: 404 if parameter not found
    """
    config = db.query(models.Configuration).filter(
        models.Configuration.parameter == parameter
    ).first()

    if not config:
        raise HTTPException(
            status_code=404,
            detail=f"Configuration parameter '{parameter}' not found"
        )

    # Update the value and timestamp
    old_value = config.value
    config.value = req.value

    db.commit()
    db.refresh(config)

    return {
        "message": f"Configuration parameter '{parameter}' updated successfully",
        "parameter": config.parameter,
        "old_value": old_value,
        "new_value": config.value
    }

@router.post("/configuration")
def create_configuration(
    req: schemas.ConfigurationCreateRequest,
    db: Session = Depends(get_db)
):
    """
    Create a new configuration parameter.

    Args:
        req: Request body containing parameter name and value

    Returns:
        JSON object with created parameter details

    Raises:
        HTTPException: 400 if parameter already exists
    """
    # Check if parameter already exists
    existing = db.query(models.Configuration).filter(
        models.Configuration.parameter == req.parameter
    ).first()

    if existing:
        raise HTTPException(
            status_code=400,
            detail=f"Configuration parameter '{req.parameter}' already exists"
        )

    # Create new configuration
    new_config = models.Configuration(
        parameter=req.parameter,
        value=req.value
    )

    db.add(new_config)
    db.commit()
    db.refresh(new_config)

    return {
        "message": f"Configuration parameter '{req.parameter}' created successfully",
        "parameter": new_config.parameter,
        "value": new_config.value
    }

@router.get("/test-data")
def get_test_execution_column(
    column: str = Query(..., description="Column name to retrieve"),
    run_id: int = Query(..., description="Run ID to filter"),
    db: Session = Depends(get_db)
):
    # Validate the column name to prevent SQL injection
    allowed_columns = {c.name for c in models.TestExecution.__table__.columns}
    if column not in allowed_columns:
        raise HTTPException(status_code=400, detail=f"Invalid column: {column}")

    # Dynamically get the column attribute
    column_attr = getattr(models.TestExecution, column)
    result = db.query(column_attr).filter(models.TestExecution.run_id == run_id).first()
    if not result:
        raise HTTPException(status_code=404, detail=f"No test execution found for run_id {run_id}")

    return {column: result[0]}

@router.get("/test-data-all")
def get_test_execution_all_columns(
    run_id: int = Query(..., description="Run ID to filter"),
    db: Session = Depends(get_db)
):
    result = db.query(models.TestExecution).filter(models.TestExecution.run_id == run_id).first()
    if not result:
        raise HTTPException(status_code=404, detail=f"No test execution found for run_id {run_id}")

    # Convert SQLAlchemy model instance to dict
    return {c.name: getattr(result, c.name) for c in models.TestExecution.__table__.columns}