
-- Create database

-- Grant all privileges on database
GRANT ALL PRIVILEGES ON DATABASE performancetesting[pp|prd] TO performance_installer;

-- Connect to the new database
\c performancetesting[pp|prd]

-- Grant schema privileges (essential for object creation)
GRANT USAGE, CREATE ON SCHEMA public TO performance_installer, performance_app, performance_dash;

-- Grant table privileges for existing objects
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO performance_installer, performance_app, performance_dash;

-- Set default privileges for future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT ALL PRIVILEGES ON TABLES TO performance_installer;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

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

INSERT  INTO locations (id,location, servername, type, environment, factor, status) VALUES
(gen_random_uuid(),'on-premise-vm', 'dcvx-jmtapp-g1.mch.moc.sgps', 'orchestrator' ,'PP', 1.0, 'up'),
(gen_random_uuid(),'on-premise-vm', 'dcvx-jmtapp-g2.mch.moc.sgps', 'worker','PP', 1.0, 'up'),
(gen_random_uuid(),'on-premise-vm', 'dcvx-jmtapp-g3.mch.moc.sgps', 'worker','PP', 1.0, 'up'),
(gen_random_uuid(),'on-premise-vm', 'dcvx-jmtapp-g4.mch.moc.sgps', 'worker','PP', 1.0, 'up'),
(gen_random_uuid(),'on-premise-vm', 'dcvx-jmtapp-g5.mch.moc.sgps', 'worker','PP', 1.0, 'up'),
(gen_random_uuid(),'on-premise-vm', 'dcvx-jmtapp-g6.mch.moc.sgps', 'worker','PP', 1.0, 'up'),
(gen_random_uuid(),'azure-vm', 'azvx-jmtapp-g1.mch.moc.sgps', 'orchestrator','PP', 1.0, 'up')
;

-- Create configuration table
CREATE TABLE configurations (
    parameter VARCHAR(255) PRIMARY KEY,
    value VARCHAR(512) NOT NULL
);

INSERT INTO configurations (parameter, value) VALUES
('dpt_registry_url', 'http://dcvx-jmtapp-g1.mch.moc.sgps:8000'), 
('jira_url', 'https://ecom4isi.atlassian.net/rest/api'),
('status', 'online'), --online: jobs allowed, offline: jobs not allowed, abort: abort all running jobs
('ssh_user','jmeter'),
('vault_url','http://dcvx-jmtapp-g1:8200'),
('xray_url', 'https://eu.xray.cloud.getxray.app/api/v2');