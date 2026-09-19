#!/usr/bin/env bash
set -euo pipefail

JOB_NAME="shard-validator"
OUT="${1:-../evidence/q3-pods-wide.txt}"
TIMEOUT=45
ELAPSED=0

mkdir -p "$(dirname "$OUT")"

while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
    RUNNING=$(kubectl get pods -l "job-name=${JOB_NAME}" \
        -o jsonpath='{range .items[*]}{.status.phase}{"\n"}{end}' \
        | awk '$1 == "Running" {count++} END {print count+0}')

    if [ "$RUNNING" -ge 4 ]; then
        {
            echo "observed_running_pods=${RUNNING}"
            echo
            kubectl get pods -l "job-name=${JOB_NAME}" -o wide
        } | tee "$OUT"
        exit 0
    fi

    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

echo "Did not observe 4 concurrent Running pods within ${TIMEOUT}s." >&2
kubectl get pods -l "job-name=${JOB_NAME}" -o wide >&2 || true
exit 1
