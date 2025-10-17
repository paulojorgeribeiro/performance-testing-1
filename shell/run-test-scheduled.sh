#!/bin/bash

# Usage:
# ./run-test-scheduled.sh <github_token> <repo> <performance_home> <schedule_file_name> <time_window_minutes> <ref_name>declare -a matching_workflows=()declare -a matching_workflows=()

set -euo pipefail

GITHUB_TOKEN="$1"
REPO="$2"
PERFORMANCE_HOME="$3"
SCHEDULE_FILE="$4"
TIME_WINDOW_MINUTES="$5"
REF_NAME="$6"

# Get the schedule file from Github
curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3.raw" \
        -o "${SCHEDULE_FILE}" \
        https://api.github.com/repos/"${REPO}"/contents/"${PERFORMANCE_HOME}"/"${SCHEDULE_FILE}"?ref="${REF_NAME}"

if [ ! -f "$SCHEDULE_FILE" ]; then
  echo "Schedule file not found: $SCHEDULE_FILE"
  exit 0
fi

TIME_WINDOW="$TIME_WINDOW_MINUTES"
current_time=$(date +'%M %H %d %m %u' | sed 's/^0*//g')

declare -a matching_workflows=()

match_time() {
  local current_str="$1"
  local schedule_str="$2"
  IFS=' ' read -r -a current <<< "$current_str"
  IFS=' ' read -r -a schedule <<< "$schedule_str"

  current_min=$(echo "${current[0]:-0}" | sed 's/^0*//')
  current_hour=$(echo "${current[1]:-0}" | sed 's/^0*//')
  current_min=${current_min:-0}
  current_hour=${current_hour:-0}

  if [[ "${schedule[0]}" == "%" ]]; then
    minutes_match=true
  else
    schedule_min=$(echo "${schedule[0]:-0}" | sed 's/^0*//')
    schedule_min=${schedule_min:-0}
    if [[ $current_min -ge $schedule_min ]]; then
      min_diff=$(( current_min - schedule_min ))
    else
      min_diff=$(( 60 - schedule_min + current_min ))
    fi
    if [[ $min_diff -le $TIME_WINDOW ]]; then
      minutes_match=true
    else
      minutes_match=false
    fi
  fi

  if [[ "${schedule[1]}" == "%" ]]; then
    hours_match=true
  else
    schedule_hour=$(echo "${schedule[1]:-0}" | sed 's/^0*//')
    schedule_hour=${schedule_hour:-0}
    if [[ $current_min -lt $TIME_WINDOW && $schedule_min -ge $(( 60 - $TIME_WINDOW )) ]]; then
      if [[ $(( (current_hour - 1 + 24) % 24 )) -eq $schedule_hour ]]; then
        hours_match=true
      else
        hours_match=false
      fi
    elif [[ $current_hour -eq $schedule_hour ]]; then
      hours_match=true
    else
      hours_match=false
    fi
  fi

  if [[ $minutes_match == true && $hours_match == true ]]; then
    for i in {2..4}; do
      if [[ "${schedule[i]}" != "%" && "${schedule[i]}" != "${current[i]}" ]]; then
        return 1
      fi
    done
    return 0
  fi
  return 1
}

while IFS= read -r line || [[ -n "$line" ]]; do
  [[ "$line" =~ ^# ]] && continue
  schedule_time=$(echo $line | cut -d ' ' -f 1-5)
  workflow=$(echo $line | cut -d ' ' -f 6- | tr -d '"')
  if match_time "$current_time" "$schedule_time"; then
    matching_workflows+=("$workflow")
  fi
done < "$SCHEDULE_FILE"

if [ ${#matching_workflows[@]} -eq 0 ]; then
  echo "No workflows to trigger."
  exit 0
fi

# Get workflow list from GitHub
response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/"$REPO"/actions/workflows)

declare -a workflow_ids=()

for workflow_name in "${matching_workflows[@]}"; do
  id=$(echo "$response" | jq --arg name "$workflow_name" -r '.workflows[] | select(.name == $name) | .id')
  if [[ -n "$id" ]]; then
    workflow_ids+=("$id")
  else
    echo "No workflow found with name: $workflow_name"
  fi
done

if [ ${#workflow_ids[@]} -eq 0 ]; then
  echo "No workflow IDs found to trigger."
  exit 0
fi

for workflow_id in "${workflow_ids[@]}"; do
  echo "Triggering workflow with ID: $workflow_id"
  curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    https://api.github.com/repos/"$REPO"/actions/workflows/"$workflow_id"/dispatches \
    -d "{\"ref\":\"$REF_NAME\"}"
  echo ""
  sleep 1
done