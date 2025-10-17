# Performance Test Execution Registry API

A FastAPI application to **control, track, and visualize performance test executions** with a PostgreSQL backend.  
Supports advanced features like concurrent test control by factor, rich execution metadata, and HTML/JSON reporting.

---

## 🚀 Features

- **Register, complete, and cancel test executions**
- **Concurrent execution control:** sum of `factor` for running tests at the same location must be less than 1
- **Execution metadata:** includes repo, stream, environment, factor, dashboard URL, and location
- **Auto-incremented run IDs**
- **HTML and JSON endpoints** for status and history
- **Filter and search executions by stream**
- **Clickable dashboard links in HTML views**

---

## 🏗️ Project Structure

app/
├── main.py # FastAPI endpoints
├── models.py # SQLAlchemy models
├── schemas.py # Pydantic schemas
├── database.py # DB connection/session
└── ...


---

## 🗄️ Database Model

Table: `test_executions`

| Column         | Type           | Description                              |
|----------------|----------------|------------------------------------------|
| id             | UUID           | Primary key                              |
| run_id         | Integer        | Auto-incremented run identifier          |
| repo           | String         | Source repository                        |
| lac            | String         | LAC info                                 |
| stream         | String         | Stream info                              |
| test           | String         | Test name                                |
| type           | String         | Test type                                |
| environment    | String         | Test environment                         |
| triggered_by   | String         | Who triggered the test                   |
| status         | String         | running/success/failure/cancelled        |
| start_time     | DateTime       | UTC start time                           |
| end_time       | DateTime       | UTC end time                             |
| factor         | Numeric        | Fractional resource usage (0-1)          |
| dashboard_url  | String         | Link to external dashboard               |
| location       | String         | Test execution location                  |

---

## ⚡ API Endpoints

### Registration and Control

- `POST /register`  
  Register a new test execution.  
  **Constraint:** The sum of `factor` for all running tests at the same `location` plus the new test's `factor` must be less than 1.  
  Returns an explicit error if not allowed.

- `POST /complete`  
  Mark a running test as complete (success/failure/cancelled).

- `POST /cancel`  
  Cancel a running test by `run_id`.

### Status and History

- `GET /status`  
  **JSON**: List of currently running tests.

- `GET /status-html`  
  **HTML Table**: Running tests, including clickable dashboard links.

- `GET /history`  
  **JSON**: All test executions, ordered by most recent.

- `GET /history-html`  
  **HTML Table**: Full execution history.

- `GET /history-html-filter?stream=...`  
  **HTML Table**: Filtered history by stream (supports `%` wildcards, case-insensitive).

---

## 🛠️ Getting Started


### Prerequisites

- Python 3.8+
- PostgreSQL database

### Installation

1. **Clone the repo**

git clone https://github.com/your-org/perf-test-registry.git
cd perf-test-registry/app


2. **Install dependencies**

pip install fastapi uvicorn sqlalchemy psycopg2-binary pydantic


3. **Configure database**

Edit `database.py` and set your connection string:
SQLALCHEMY_DATABASE_URL = "postgresql://performance:testing@<host>/performance_testing"


4. **Create database table**

Run this SQL in your PostgreSQL instance:

CREATE TABLE test_executions (
id UUID PRIMARY KEY,
run_id INTEGER NOT NULL,
repo VARCHAR NOT NULL,
lac VARCHAR NOT NULL,
stream VARCHAR NOT NULL,
test VARCHAR NOT NULL,
type VARCHAR NOT NULL,
environment VARCHAR NOT NULL,
triggered_by VARCHAR NOT NULL,
status VARCHAR NOT NULL,
start_time TIMESTAMP WITH TIME ZONE NOT NULL,
end_time TIMESTAMP WITH TIME ZONE,
factor NUMERIC,
dashboard_url VARCHAR,
location VARCHAR
);



5. **Run the API**

uvicorn main:app --reload



6. **Access the API**
- Interactive docs: [http://localhost:8000/docs](http://localhost:8000/docs)
- HTML status/history: [http://localhost:8000/status-html](http://localhost:8000/status-html)

---

## 📝 Example Register Request

POST /register
{
"repo": "myrepo",
"lac": "lac1",
"stream": "main",
"test": "load",
"type": "performance",
"environment": "prod",
"triggered_by": "user1",
"factor": 0.5,
"dashboard_url": "https://dashboard.example.com/run/123",
"location": "azure-k8s"
}



---

## 🧪 Testing

- Use [pytest](https://docs.pytest.org/) and [FastAPI TestClient](https://fastapi.tiangolo.com/tutorial/testing/) for endpoint tests.
- Example:

from fastapi.testclient import TestClient
from main import app

client = TestClient(app)

def test_status():
response = client.get("/status")
assert response.status_code == 200



---

## 🏆 Best Practices

- Store all timestamps in UTC.
- Use environment variables for secrets and DB credentials.
- Use `/status-html` and `/history-html` for quick operational visibility.
- Enforce all business rules (like factor sum per location) in backend logic.

---

## 📄 License

MIT License

---

## 🙌 Contributing

Pull requests and issues are welcome!

---

## 📣 Acknowledgements

- [FastAPI](https://fastapi.tiangolo.com/)
- [SQLAlchemy](https://www.sqlalchemy.org/)
- [PostgreSQL](https://www.postgresql.org/)

---

*Built with ❤️ for performance test management.*
