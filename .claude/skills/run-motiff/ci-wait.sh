#!/usr/bin/env bash
# Waits for a CI run of build.yml and prints each job's result, plus any failed steps.
# Exits as soon as a step fails, or when every job has finished.
#
#   ci-wait.sh <branch>          waits for the newest run on that branch
#   ci-wait.sh --run <run-id>    waits for that run
#
# Uses the public GitHub API without a token (60 requests an hour), so it polls every 75s.
set -euo pipefail
REPO="mdotavci/Motiff"
API="https://api.github.com/repos/$REPO/actions"

if [ "${1:-}" = "--run" ]; then
  RUN="$2"
else
  RUN=$(curl -sS "$API/runs?branch=$1&per_page=1" | python3 -c 'import json,sys; print(json.load(sys.stdin)["workflow_runs"][0]["id"])')
fi
echo "Run $RUN: https://github.com/$REPO/actions/runs/$RUN"

while true; do
  summary=$(curl -sS "$API/runs/$RUN/jobs" | python3 -c '
import json, sys
jobs = json.load(sys.stdin).get("jobs", [])
failed = [(j, s) for j in jobs for s in j["steps"] if s["conclusion"] == "failure"]
done = bool(jobs) and all(j["status"] == "completed" for j in jobs)
if failed or done:
    for j in jobs:
        print("{}: {} (job {})".format(j["name"], j["conclusion"] or j["status"], j["id"]))
    for j, s in failed:
        print("  failed step: {} / {}".format(j["name"], s["name"]))
' || true)
  if [ -n "$summary" ]; then
    echo "$summary"
    break
  fi
  sleep 75
done
