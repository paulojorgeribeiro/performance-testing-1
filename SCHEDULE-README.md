# Schedule Workflow
This GitHub Actions workflow is designed to trigger specific workflows based on a schedule defined in a file. The schedule file path is specified using a repository variable.

## Usage
Triggering the Workflow
The workflow can be manually triggered using the workflow_dispatch event.

## Schedule File
The schedule file should be specified using a repository variable named SCHEDULE_FILE_PATH. This file contains the schedule and the corresponding workflow names to be triggered.

## Schedule Format
The schedule file should contain lines in the following format:

`MM HH dd MM u "workflow-name"`

- MM: Minutes (0-59)    
- HH: Hours (0-23) or % for every hour  
- dd: Day of the month (1-31) or % for every day  
- MM: Month (1-12) or % for every month  
- u: Day of the week (0 for Sunday, 1 for Monday, ..., 6 for Saturday) or % for any day  
- "workflow-name": The name of the workflow to trigger  

## Example Schedule

    0 13 % % 1 "workflow-name"  # Trigger at 13:00 on any Monday
    30 14 % % 3 "another-workflow"  # Trigger at 14:30 on any Wednesday

## Rules
- The schedule supports wildcards (%) for any value.
- The minutes field allows for a 10-minute difference.  
- The workflow will only trigger if the current time matches the schedule.  
