#!/usr/bin/env bash
set -u

URL="${1:?URL required}"
OUT="${2:-../evidence/q4-rollout-probe.txt}"

failures=0
total=0

for _ in $(seq 1 80); do
    total=$((total + 1))

    if ! curl -fsS --max-time 2 "$URL" >/dev/null 2>&1; then
        failures=$((failures + 1))
    fi

    sleep 0.25
done

{
    echo "url=$URL"
    echo "requests=$total"
    echo "failures=$failures"

    if [ "$failures" -eq 0 ]; then
        echo "CONTINUOUS_HEALTH_CHECK=PASS"
        exit_code=0
    else
        echo "CONTINUOUS_HEALTH_CHECK=FAIL"
        exit_code=1
    fi
} > "$OUT"

cat "$OUT"
exit "$exit_code"