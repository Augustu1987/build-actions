#!/bin/sh -e
git_sha="$1"
pull_request="$2"

summarize_and_quit() {
  echo "$1" | tee "$GITHUB_STEP_SUMMARY"
  exit $2
}

if [ -z "$git_sha" ]; then
  summarize_and_quit "Usage $0 GIT_SHA [PULL_REQUEST]" 1
fi

if [ -z "$pull_request" ]; then
  pull_request="master"
fi

export workflow_name="${pull_request}-${git_sha}"

while true; do
  workflow_status=$(
    kubectl get -n e2e-tests workflow/$workflow_name -o json 2>/dev/null |
    jq -r .status.phase
  )
  if [ -z "$workflow_status" ]; then
    echo "Waiting for e2e workflow for $workflow_name to appear..."
  elif [ "$workflow_status" = "Pending" ] ||
       [ "$workflow_status" = "Running" ] ||
       [ "$workflow_status" = "null" ]; then
    echo "Waiting for e2e workflow for $workflow_name to complete..."
  else
    break
  fi
  sleep 5
done

echo "E2E workflow for $workflow_name finished with status $workflow_status"
if [ "$workflow_status" = "Succeeded" ]; then
  exit 0
fi

while true; do
  e2e_pod=$(
    kubectl get pods -n e2e-tests -l "$POD_LABEL_NAME=$POD_LABEL_VALUE" --sort-by=.status.startTime --no-headers |
    perl -ne 'next unless /$ENV{workflow_name}/; s/^\s*(\S+).*/$1/; print;' |
    tail -n 1
  )
  if [ -z "$e2e_pod" ]; then
    echo "Unable to find the $POD_LABEL_VALUE pod for $workflow_name"
    sleep 5
  else
    break
  fi
done

if [ -z "$CAPTURE_LOG" ]; then
  echo "Showing log for pod: $e2e_pod"
  log_file=/dev/stdout
else
  log_file=$(mktemp)
  echo "log=$log_file" >> "$GITHUB_OUTPUT"
fi

kubectl -n e2e-tests logs "$e2e_pod" -c main >> "$log_file"
if [ -z "$CAPTURE_LOG" ]; then
  exit 1
fi
