# Performance Testing Platform Documentation

## Table of Contents
1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Components](#components)
4. [Execution Types](#execution-types)
5. [API Reference](#api-reference)
6. [GitHub Actions Workflows](#github-actions-workflows)
7. [Setup and Configuration](#setup-and-configuration)
8. [Usage Guide](#usage-guide)
9. [Troubleshooting](#troubleshooting)

## Overview

The Performance Testing Platform is a comprehensive, containerized JMeter testing infrastructure that supports distributed load testing across multiple execution modes. The platform provides centralized test orchestration, dynamic resource allocation, and integrated reporting with JIRA/XRAY test management systems.

### Key Features
- **Multi-mode execution**: Client-server, standalone, and distributed testing
- **Dynamic resource allocation**: Intelligent worker server selection based on capacity
- **Centralized orchestration**: API-driven test management and monitoring
- **Container-based execution**: Podman containers for isolated test environments
- **Integration capabilities**: GitHub Actions, JIRA, XRAY, and New Relic dashboards
- **Real-time monitoring**: Status polling and centralized cancellation support

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  GitHub Actions │    │   DPT Registry  │    │   Orchestrator  │
│   Workflows     │◄──►│      API        │◄──►│     Server      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                │                        │
                                │                        │
                                ▼                        ▼
                       ┌─────────────────┐    ┌─────────────────┐
                       │   Worker Pool   │    │  JMeter Master  │
                       │   Management    │    │   Container     │
                       └─────────────────┘    └─────────────────┘
                                │                        │
                                │                        │
                                ▼                        ▼
                       ┌─────────────────┐    ┌─────────────────┐
                       │ JMeter Workers  │    │   Test Results  │
                       │   (Slaves)      │    │  & Artifacts    │
                       └─────────────────┘    └─────────────────┘
```

### Core Components
1. **DPT Registry API**: Central management and coordination service
2. **Orchestrator Server**: Primary execution coordinator
3. **Worker Servers**: Distributed JMeter execution nodes
4. **GitHub Actions**: CI/CD integration and workflow automation
5. **Container Runtime**: Podman-based isolation and resource management

## Components

### 1. DPT Registry API (`endpoints.py`)

The central API service that manages test execution lifecycle and resource allocation.

#### Key Endpoints:
- `POST /register` - Register new test execution
- `POST /complete` - Mark test as completed
- `POST /cancel` - Cancel running test
- `GET /workers` - Get available worker servers
- `GET /orchestrator` - Get orchestrator server
- `GET /locations` - Get location capacity information
- `GET /configuration/{parameter}` - Retrieve configuration values

#### Worker Allocation Algorithm:
```python
# Factor-based allocation logic
if factor <= 1:
    # Single server allocation
    for server in available_servers:
        if server.available_factor >= factor:
            return [server]
else:
    # Multi-server allocation
    n = 1
    while n <= len(available_servers):
        threshold = factor / n
        eligible = [s for s in servers if s.available_factor >= threshold]
        if len(eligible) >= n:
            return eligible[:n]
        n += 1
```

### 2. Test Execution Scripts

#### Primary Orchestration Script (`run-test.sh`)
- **Purpose**: Main entry point for test execution on runner
- **Features**:
  - Dynamic worker discovery
  - Container name generation with random suffixes
  - Central status monitoring with abort capability
  - Configuration validation and capacity checking

#### Local Execution Script (`run-test-performance.sh`)
- **Purpose**: Local execution on runner
- **Features**:
  - GitHub repository file fetching

#### Remote Execution Script (`run-test-performance-jmeter.sh`)
- **Purpose**: Remote execution on orchestrator server
- **Features**:
  - GitHub repository file fetching
  - Distributed data splitting
  - Container resource limits (CPU/RAM)
  - Result aggregation 

#### Remote Execution Script (`run-test-JIRA.sh`)
- **Purpose**: Remote execution on orchestrator server
- **Features**:
  - JIRA integration

#### Cleanup Script (`cleanup-remote-job.sh`)
- **Purpose**: Container and resource cleanup
- **Features**:
  - API-driven parameter retrieval
  - Multi-mode container termination
  - Temporary file cleanup

## Execution Types

### 1. Client-Server Mode
**Use Case**: Traditional JMeter distributed testing with master-slave architecture

**Flow**:
1. Deploy JMeter slave containers on worker servers
2. Configure RMI communication between master and slaves
3. Execute test plan from orchestrator (master)
4. Collect results from master node

**Configuration**:
```yaml
EXECUTION_TYPE=client-server
FACTOR=2.0  # Total load factor across slaves
```

### 2. Distributed Mode
**Use Case**: Independent parallel execution with result aggregation

**Flow**:
1. Split test data across worker servers
2. Deploy identical test plans to each worker
3. Execute tests in parallel with resource limits
4. Aggregate results on orchestrator

**Configuration**:
```yaml
EXECUTION_TYPE=distributed
FACTOR=3.0  # Load distributed across workers
```

### 3. Standalone Mode
**Use Case**: Single-server execution for smaller tests

**Flow**:
1. Execute test on single worker server
2. Apply resource limits based on factor
3. Return results directly

**Configuration**:
```yaml
EXECUTION_TYPE=standalone
FACTOR=0.5  # Partial server utilization
```

## API Reference

### Test Registration
```json
POST /register
{
  "repo": "mcdigital-devplatforms/performance-testing",
  "lac": "LAC.0001",
  "stream": "DIGITAL",
  "test": "TEST.0001",
  "type": "load-test",
  "environment": "PP",
  "triggered_by": "user@domain.com",
  "factor": 2.0,
  "dashboard_url": "https://dashboard.url",
  "location": "on-premise-vm",
  "container_name": "brave_turing_123",
  "execution_type": "distributed",
  "workers": ["server1", "server2"],
  "tool": "jmeter",
  "script_version": "1.2.0"
}
```

### Worker Discovery
```json
GET /workers?location=on-premise-vm&environment=PP&factor=2.0

Response:
["worker1.domain.com", "worker2.domain.com"]
```

### Configuration Management
```json
GET /configuration/ssh_user

Response:
{
  "parameter": "ssh_user",
  "value": "testuser"
}
```

## GitHub Actions Workflows

### Workflow Structure
All workflows follow a consistent pattern:

```yaml
name: LAC.{ID}-TEST.{ID}-{TestType}-{ExecutionMode}

on:
  workflow_dispatch

jobs:
  performance-test:
    runs-on: self-hosted
    timeout-minutes: 60
    
    steps:
    - name: Defining test specific environment variables
    - name: Running test
    - name: Cleanup remote job
```

### Environment Variables
| Variable | Description | Example |
|----------|-------------|---------|
| `LAC_ID` | Location Application Component ID | `LAC.0001` |
| `TEST_ID` | Unique test identifier | `TEST.0001` |
| `SECRET_VALUE` | JSON with service authentication | `{ "username": "aes" }` |

### Workflow Examples

#### Load Test - Client-Server Mode
- **File**: `lac.0001-test.0001-load-test-client-server.yml`
- **Mode**: `client-server`
- **Factor**: `2.0`
- **Use Case**: High-load distributed testing

#### Load Test - Distributed Mode
- **File**: `lac.0001-test.0001-load-test-multi-server.yml`
- **Mode**: `distributed`
- **Factor**: `3.0`
- **Use Case**: Independent parallel execution

## Setup and Configuration

### Prerequisites
1. **Container Runtime**: Podman installed on all servers
2. **SSH Access**: Passwordless SSH between orchestrator and workers
3. **API Access**: DPT Registry API accessible from GitHub Actions
4. **JIRA Integration**: Valid JIRA tokens for test management

### Server Configuration

#### Orchestrator Server
- **Role**: Test coordination and result aggregation
- **Requirements**: SSH access to all workers, GitHub API access
- **Software**: Podman, JMeter client containers, result processing tools

#### Worker Servers
- **Role**: Test execution nodes
- **Requirements**: Podman, JMeter containers
- **Scaling**: Dynamic allocation based on factor requirements

### Database Schema
```sql
-- Create table to store test execution data
CREATE TABLE test_executions (
    id UUID PRIMARY KEY,
    run_id INT NOT NULL,
    repo VARCHAR(255) NOT NULL,
    lac VARCHAR(255) NOT NULL,
    stream VARCHAR(255) NOT NULL,
    test VARCHAR(255) NOT NULL,
    type VARCHAR(255) NOT NULL,
    environment VARCHAR(255) NOT NULL,
    triggered_by VARCHAR(255) NOT NULL,
    status VARCHAR(50) NOT NULL,
    start_time TIMESTAMP WITH TIME ZONE NOT NULL,
    end_time TIMESTAMP WITH TIME ZONE,
    factor NUMERIC(3, 2) NOT NULL,
    dashboard_url VARCHAR(255) NULL,
    location VARCHAR(255) NOT NULL,
    container_name VARCHAR(255) NOT NULL,
    execution_type VARCHAR(50) NOT NULL,
    workers JSONB,
    tool VARCHAR(50) NOT NULL,
    script_version VARCHAR(8) NOT NULL
);

-- Create table to store locations (servers)
CREATE TABLE locations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    location VARCHAR(255) NOT NULL, -- "on-premise-vm", "azure-vm", "on-premise-k8s", "azure-k8s", etc.
    servername VARCHAR(255) NOT NULL,
    type VARCHAR(32) NOT NULL, -- "orchestrator", "worker"
    environment VARCHAR(32) NOT NULL, -- "PP", "PRD", "Staging", etc.
    factor NUMERIC(3, 2) NOT NULL,
    status VARCHAR(10) NOT NULL -- "up", "down"
);

-- Create conifguration table
CREATE TABLE configurations (
    parameter VARCHAR(255) PRIMARY KEY,
    value VARCHAR(255) NOT NULL
);
```

## Usage Guide

### Running a Performance Test

#### 1. Via GitHub Actions
1. Navigate to Actions tab in GitHub repository
2. Select desired workflow (e.g., `LAC.0001-TEST.0001-Load-Test-distributed`)
3. Click "Run workflow"
4. Monitor execution in workflow logs

#### 2. Manual Execution
```bash
# Execute distributed load test
./run-test.sh \
  "$GITHUB_TOKEN" \
  "mcdigital-devplatforms/performance-testing" \
  "LAC.0001" \
  "TEST.0001" \
  "testing/performance" \
  "testuser" \
  "main" \
  "ghs......." \
  "{username: <>, password: <>}" \
```

### Test Cleanup
```bash
# Cleanup containers and resources
./cleanup-remote-job.sh LAC.0001 TEST.0001 "ghs......."
```

### Monitoring Tests

#### Real-time Status
```bash
# Check running tests
curl -X GET "http://dpt-registry:8000/v2/status"

# Check server capacity
curl -X GET "http://dpt-registry:8000/v2/locations"
```

#### Emergency Cancellation
```bash
# Set system to abort mode
curl -X POST "http://dpt-registry:8000/v2/configuration/status" \
  -d '{"value": "abort"}'
```

## Troubleshooting

### Common Issues

#### 1. Insufficient Capacity
**Error**: `"Not enough servers to satisfy factor X"`
**Solution**: 
- Reduce factor value
- Wait for running tests to complete
- Add more worker servers

#### 2. SSH Connection Failures
**Error**: SSH timeouts or permission denied
**Solution**:
- Verify SSH key authentication
- Check network connectivity
- Validate SSH user configuration

#### 3. Container Startup Failures
**Error**: Podman container creation errors
**Solution**:
- Check resource limits (CPU/RAM)
- Verify container image availability
- Review container naming conflicts

#### 4. Test Result Collection Failures
**Error**: Empty or missing results.jtl files
**Solution**:
- Check JMeter test plan configuration
- Verify file permissions on worker servers
- Review JMeter log files for errors

### Debugging Commands

```bash
# Check worker server status
ssh user@worker "podman ps -a"

# Review container logs
ssh user@worker "podman logs container_name"

# Verify file transfers
ssh user@orchestrator "ls -la /home/user/LAC.*/TEST.*/"

# Test API connectivity
curl -v "http://dpt-registry:8000/v2/workers?location=X&environment=Y&factor=Z"
```

### Log Analysis

#### Key Log Locations
- **Orchestrator**: `/home/{ssh_user}/{LAC_ID}/{TEST_ID}/`
- **Workers**: Container logs via `podman logs`
- **GitHub Actions**: Workflow execution logs
- **API**: Application logs on DPT Registry server

#### Log Patterns
```bash
# Success patterns
grep "\[INFO\]" execution.log
grep "Test registered" execution.log
grep "Registration Sucessfull" execution.log

# Error patterns
grep "\[ERROR\]" execution.log
grep "failed" execution.log
grep "not found" execution.log
```

---

## Appendix

### Container Resource Limits
- **Base RAM**: 14GB maximum per container
- **Base CPU**: 4 cores maximum per container
- **Factor-based scaling**: Resources allocated as `(base * factor / num_workers)`

### File Naming Conventions
- **Test Plans**: `{test-type}.jmx` (e.g., `load-test.jmx`)
- **Test Data**: `test-data-{sequence}.csv`
- **Containers**: `{adjective}_{scientist}_{random_number}`
- **Results**: `results.jtl`, `jmeter.log`, `report.zip`

### Integration Points
- **GitHub**: Repository file access, workflow triggers
- **JIRA**: Test execution tracking, result attachments
- **XRAY**: Test management integration
- **New Relic**: Performance monitoring dashboards
- **Podman**: Container orchestration and isolation

This documentation provides a comprehensive guide to understanding, configuring, and operating the Performance Testing Platform. For additional support or feature requests, please contact the platform development team.
