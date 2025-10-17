# GitHub Actions Schedule Workflow

## Overview
This repository contains all the performance tests for each LAC, and a main schedule workflow that reads a `schedule.txt` file with crontab format and triggers specific test workflows based on the schedule. The main workflow checks the schedule file every 30 minutes and triggers the appropriate workflows if the current time is within 10 minutes before or after the scheduled time.

## Usage

### Schedule File
Create a `schedule.txt` file in the `testing/performance` directory with the following format:

    30 15 % % % "LAC.0002-TEST.0001-Soak-Test"
    00 % % % % "LAC.0001-TEST.0002-Spike-Test"
    30 % % % % "LAC.0001-TEST.0001-Load-Test"
    30 10 % % % "LAC.0003-TEST.0001-Stress-Test"
    0 % % % % "LAC.0005-TEST.0001-FAKE.0003"
    30 % % % % "LAC.0004-TEST.0001-FAKE.0001"

