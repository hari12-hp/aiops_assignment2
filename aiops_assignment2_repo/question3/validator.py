import csv
import os
import re
import time
from pathlib import Path

index = os.environ.get("JOB_COMPLETION_INDEX")
pod_name = os.environ.get("POD_NAME")
node_name = os.environ.get("NODE_NAME")

if index is None:
    raise RuntimeError("JOB_COMPLETION_INDEX is not set")
if pod_name is None or node_name is None:
    raise RuntimeError("POD_NAME or NODE_NAME is not set")

shard_path = Path("/app/shards") / f"shard_{index}.csv"
email_pattern = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")

print(
    f"START shard={index} pod={pod_name} node={node_name}",
    flush=True,
)

# Gives kubectl get pods -o wide a real observation window while
# the four selected pods are actually executing this validator.
time.sleep(5)

invalid = 0
total = 0

with shard_path.open(newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f)
    for row in reader:
        total += 1
        email = row.get("email", "")
        required = row.get("required", "")

        email_ok = bool(email_pattern.fullmatch(email))
        required_ok = bool(required.strip())

        if not email_ok or not required_ok:
            invalid += 1

print(
    f"RESULT shard={index} pod={pod_name} node={node_name} "
    f"total_rows={total} invalid_rows={invalid}",
    flush=True,
)
