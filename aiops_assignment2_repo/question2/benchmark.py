import json
import statistics
import time
import urllib.request

URL = "http://127.0.0.1:8001/predict"
TRIALS = 20


def request(text: str):
    payload = json.dumps({"text": text}).encode("utf-8")
    req = urllib.request.Request(
        URL,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    start = time.perf_counter()
    with urllib.request.urlopen(req, timeout=10) as response:
        body = response.read().decode("utf-8")
        status = response.status
    elapsed_ms = (time.perf_counter() - start) * 1000
    return status, body, elapsed_ms


miss_times = []
hit_times = []

for i in range(TRIALS):
    text = f"cache benchmark message {time.time_ns()} trial={i}"

    miss_status, miss_body, miss_ms = request(text)
    hit_status, hit_body, hit_ms = request(text)

    if miss_status != 200 or hit_status != 200:
        raise RuntimeError(
            f"Unexpected status: miss={miss_status}, hit={hit_status}"
        )

    miss_label = json.loads(miss_body)["label"]
    hit_label = json.loads(hit_body)["label"]

    if miss_label != hit_label:
        raise RuntimeError("Cache changed the prediction")

    miss_times.append(miss_ms)
    hit_times.append(hit_ms)

miss_median = statistics.median(miss_times)
hit_median = statistics.median(hit_times)

print(f"trials={TRIALS}")
print(f"miss_mean_ms={statistics.mean(miss_times):.3f}")
print(f"hit_mean_ms={statistics.mean(hit_times):.3f}")
print(f"miss_median_ms={miss_median:.3f}")
print(f"hit_median_ms={hit_median:.3f}")
print(f"speedup_x={miss_median / hit_median:.2f}")

if hit_median >= miss_median:
    print("WARNING: median cache hit was not faster in this run; repeat benchmark.py.")
else:
    print("CACHE_SPEEDUP_CONFIRMED=1")
