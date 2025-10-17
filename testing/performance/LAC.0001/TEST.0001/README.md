# JMeter Automated Test Setup

This repository contains the necessary files to define and execute an automated test using Apache JMeter. Below is a description of each file and its purpose in the testing workflow.

## Files

### 1. `dashboard.url`
This file contains the URL to the dashboard associated with the test. The dashboard provides a visual representation of the test results and performance metrics. It can point to a newly created dashboard or an existing one.

### 2. `load-test.jmx`
This is the JMeter test plan file. It defines the structure of the test including thread groups, samplers, listeners, and other test elements. This file is used by JMeter to execute the test scenario.

### 3. `info.json`
This JSON file contains metadata about the test for the test automation platform. It includes information such as the test name, description, author, creation date, and other relevant configuration details.

### 4. `test-data-001.csv`
This CSV file provides sample input data used during the test execution. It can include user credentials, input parameters, or any other data required by the test plan.

## Usage

1. Open the `default.jmx` file in JMeter to review or modify the test plan.
2. Ensure the `test-data-001.csv` file is correctly referenced in the test plan.
3. Run the test using JMeter.
4. View the results on the dashboard using the URL provided in `dashboard.url`.

## Notes

- Make sure all files are placed in the appropriate directory as expected by the test plan.
- Update the `info.json` file with accurate metadata before running the test.

