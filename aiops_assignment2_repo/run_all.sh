#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVID="$ROOT/evidence"
Q3_PROFILE="aiops-m3"

mkdir -p "$EVID"

PYTHON="python3"
if [ -n "${VIRTUAL_ENV:-}" ] && [ -x "$VIRTUAL_ENV/bin/python" ]; then
    PYTHON="$VIRTUAL_ENV/bin/python"
elif [ -x "$ROOT/.venv/bin/python" ]; then
    PYTHON="$ROOT/.venv/bin/python"
fi

log() {
    echo
    echo "========== $* =========="
}

wait_for_http() {
    local url="$1"
    local timeout="${2:-60}"
    local elapsed=0

    while ! curl -fsS "$url" >/dev/null 2>&1; do
        if [ "$elapsed" -ge "$timeout" ]; then
            echo "Timed out waiting for $url" >&2
            return 1
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
}

cleanup_container() {
    docker rm -f "$1" >/dev/null 2>&1 || true
}

restore_context() {
    if [ -n "${ORIGINAL_CONTEXT:-}" ] && [ "$ORIGINAL_CONTEXT" != "${Q3_PROFILE}" ]; then
        kubectl config use-context "$ORIGINAL_CONTEXT" >/dev/null 2>&1 || true
    fi
}

cleanup() {
    cleanup_container q1-naive
    cleanup_container q1-multi
    if [ -n "${COMPOSE_STARTED:-}" ]; then
        docker compose -f "$ROOT/question2/docker-compose.yml" down --remove-orphans >/dev/null 2>&1 || true
    fi
    if [ -n "${PORT_FORWARD_PID:-}" ]; then
        kill "$PORT_FORWARD_PID" >/dev/null 2>&1 || true
    fi
    if [ -n "${PROBE_PID:-}" ]; then
        kill "$PROBE_PID" >/dev/null 2>&1 || true
    fi
    restore_context
}

on_error() {
    local line="$1"
    echo "run_all.sh failed at line $line" >&2
}

trap 'on_error $LINENO' ERR
trap cleanup EXIT

for command in docker kubectl minikube curl; do
    command -v "$command" >/dev/null || {
        echo "$command not found" >&2
        exit 1
    }
done

docker info >/dev/null 2>&1 || {
    echo "Docker daemon is not available" >&2
    exit 1
}

docker compose version >/dev/null 2>&1 || {
    echo "Docker Compose plugin is required: docker compose version" >&2
    exit 1
}

log "Install host Python dependencies"
"$PYTHON" -m pip install -q -r "$ROOT/common/host-requirements.txt"

log "Generate dataset and train model"
cd "$ROOT/common"
"$PYTHON" generate_dataset.py
"$PYTHON" train_model.py

SKLEARN_VERSION="$(tr -d '[:space:]' < "$ROOT/common/sklearn_version.txt")"

for q in question1 question2 question4; do
    cp -f "$ROOT/common/model.joblib" "$ROOT/$q/model.joblib"
    cp -f "$ROOT/common/sklearn_version.txt" "$ROOT/$q/sklearn_version.txt"
done

log "Q1: build naive image"
cd "$ROOT/question1"
docker build -t aiops-spam-api:naive -f Dockerfile .
docker image inspect aiops-spam-api:naive --format='naive={{.Size}} bytes' \
    | tee "$EVID/q1-naive-size.txt"
docker history --no-trunc aiops-spam-api:naive > "$EVID/q1-naive-history.txt"

cleanup_container q1-naive
docker run -d --name q1-naive -p 18001:8000 aiops-spam-api:naive >/dev/null
wait_for_http http://127.0.0.1:18001/healthz
{
    curl -fsS http://127.0.0.1:18001/healthz
    echo
    curl -fsS -X POST http://127.0.0.1:18001/predict \
        -H 'Content-Type: application/json' \
        -d '{"text":"Congratulations! You won a free prize"}'
    echo
} | tee "$EVID/q1-naive-endpoints.txt"
cleanup_container q1-naive

log "Q1: build multi-stage image"
docker build -t aiops-spam-api:multistage -f Dockerfile.multistage .
docker image inspect aiops-spam-api:multistage --format='multistage={{.Size}} bytes' \
    | tee "$EVID/q1-multistage-size.txt"
docker history --no-trunc aiops-spam-api:multistage > "$EVID/q1-multistage-history.txt"

NAIVE_BYTES="$(docker image inspect aiops-spam-api:naive --format='{{.Size}}')"
MULTI_BYTES="$(docker image inspect aiops-spam-api:multistage --format='{{.Size}}')"
"$PYTHON" - "$NAIVE_BYTES" "$MULTI_BYTES" <<'PY' | tee "$EVID/q1-reduction.txt"
import sys
naive = int(sys.argv[1])
multi = int(sys.argv[2])
print(f"naive_bytes={naive}")
print(f"multistage_bytes={multi}")
print(f"reduction_percent={(naive-multi)/naive*100:.2f}")
PY

cleanup_container q1-multi
docker run -d --name q1-multi -p 18002:8000 aiops-spam-api:multistage >/dev/null
wait_for_http http://127.0.0.1:18002/healthz
{
    curl -fsS http://127.0.0.1:18002/healthz
    echo
    curl -fsS -X POST http://127.0.0.1:18002/predict \
        -H 'Content-Type: application/json' \
        -d '{"text":"Congratulations! You won a free prize"}'
    echo
} | tee "$EVID/q1-multistage-endpoints.txt"
cleanup_container q1-multi

log "Q2: validate Compose file and start stack"
cd "$ROOT/question2"
docker compose config >/dev/null
docker compose down --remove-orphans >/dev/null 2>&1 || true
docker compose up -d --build
COMPOSE_STARTED=1
wait_for_http http://127.0.0.1:8001/healthz

{
    curl -fsS http://127.0.0.1:8001/healthz
    echo
    curl -fsS -X POST http://127.0.0.1:8001/predict \
        -H 'Content-Type: application/json' \
        -d '{"text":"Congratulations! You won a free prize"}'
    echo
} | tee "$EVID/q2-endpoints.txt"

"$PYTHON" benchmark.py | tee "$EVID/q2-cache-timing.txt"
docker compose ps | tee "$EVID/q2-compose-ps.txt"
docker compose logs --no-color | tee "$EVID/q2-compose-logs.txt"
docker compose down --remove-orphans
COMPOSE_STARTED=""

log "Q3: prepare Minikube profile"
ORIGINAL_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"

if ! minikube status -p "$Q3_PROFILE" 2>/dev/null | grep -q 'Running'; then
    if minikube status -p "$Q3_PROFILE" >/dev/null 2>&1; then
        minikube delete -p "$Q3_PROFILE"
    fi
    minikube start -p "$Q3_PROFILE" --driver=docker --nodes=2 --cpus=2 --memory=4096
fi

kubectl config use-context "$Q3_PROFILE" >/dev/null
NODE_COUNT="$(kubectl get nodes --no-headers | wc -l | tr -d ' ')"
if [ "$NODE_COUNT" -ne 2 ]; then
    echo "Profile $Q3_PROFILE has $NODE_COUNT nodes; recreating it with 2 nodes." >&2
    minikube delete -p "$Q3_PROFILE"
    minikube start -p "$Q3_PROFILE" --driver=docker --nodes=2 --cpus=2 --memory=4096
    kubectl config use-context "$Q3_PROFILE" >/dev/null
fi

kubectl wait --for=condition=Ready nodes --all --timeout=180s
kubectl get nodes | tee "$EVID/q3-nodes.txt"

log "Q3: generate shards and build validator"
cd "$ROOT/question3"
"$PYTHON" generate_shards.py | tee "$EVID/q3-generated-shards.txt"
docker build -t aiops-shard-validator:latest .
minikube image load -p "$Q3_PROFILE" aiops-shard-validator:latest

kubectl delete job shard-validator --ignore-not-found=true >/dev/null 2>&1 || true
kubectl apply -f job.yaml

./capture_concurrency.sh "$EVID/q3-pods-wide.txt"
kubectl wait --for=condition=complete job/shard-validator --timeout=180s

if ! "$PYTHON" -c 'import kubernetes' >/dev/null 2>&1; then
    "$PYTHON" -m pip install -q -r requirements.txt
fi
"$PYTHON" collect_logs.py | tee "$EVID/q3-log-results.txt"



log "Q4: build v1 and deploy"
cd "$ROOT/question4"

cp -f api_v1.py api.py

docker build \
    -t aiops-spam-api:k8s-v1 \
    .

minikube image load \
    -p "$Q3_PROFILE" \
    aiops-spam-api:k8s-v1

kubectl delete deployment spam-api --ignore-not-found=true >/dev/null 2>&1 || true
kubectl delete service spam-api --ignore-not-found=true >/dev/null 2>&1 || true

kubectl apply -f deployment-v1.yaml

kubectl rollout status \
    deployment/spam-api \
    --timeout=180s \
    | tee "$EVID/q4-v1-rollout-status.txt"

kubectl get pods \
    -l app=spam-api \
    -o wide \
    | tee "$EVID/q4-v1-pods.txt"

# Test v1 from inside the cluster through the Service
kubectl delete pod q4-v1-client --ignore-not-found=true >/dev/null 2>&1 || true

kubectl run q4-v1-client \
    --restart=Never \
    --image=aiops-spam-api:k8s-v1 \
    --image-pull-policy=IfNotPresent \
    --command -- \
    python3 -c 'import urllib.request; print(urllib.request.urlopen("http://spam-api:8000/healthz", timeout=5).read().decode())'

kubectl wait \
    --for=jsonpath='{.status.phase}'=Succeeded \
    pod/q4-v1-client \
    --timeout=60s

kubectl logs q4-v1-client \
    | tee "$EVID/q4-v1-healthz.txt"

kubectl delete pod q4-v1-client >/dev/null 2>&1 || true

kubectl delete pod q4-v1-client --ignore-not-found=true >/dev/null 2>&1 || true

kubectl run q4-v1-client \
    --restart=Never \
    --image=aiops-spam-api:k8s-v1 \
    --image-pull-policy=IfNotPresent \
    --command -- \
    python3 -c 'import json,urllib.request; d=json.dumps({"text":"Congratulations! You won a free prize"}).encode(); r=urllib.request.Request("http://spam-api:8000/predict",data=d,headers={"Content-Type":"application/json"},method="POST"); print(urllib.request.urlopen(r,timeout=5).read().decode())'

kubectl wait \
    --for=jsonpath='{.status.phase}'=Succeeded \
    pod/q4-v1-client \
    --timeout=60s

kubectl logs q4-v1-client \
    | tee "$EVID/q4-v1-predict.txt"

kubectl delete pod q4-v1-client >/dev/null 2>&1 || true

log "Q4: self-healing"

OLD_POD="$(
    kubectl get pods \
        -l app=spam-api \
        -o jsonpath='{.items[0].metadata.name}'
)"

{
    echo "before:"
    kubectl get pods -l app=spam-api -o wide

    echo "deleted_pod=$OLD_POD"

    kubectl delete pod "$OLD_POD"

    kubectl wait \
        --for=condition=available \
        deployment/spam-api \
        --timeout=120s

    echo "after:"
    kubectl get pods -l app=spam-api -o wide
} | tee "$EVID/q4-self-healing.txt"

log "Q4: rolling update"

cp -f api_v2.py api.py

docker build \
    -t aiops-spam-api:k8s-v2 \
    .

minikube image load \
    -p "$Q3_PROFILE" \
    aiops-spam-api:k8s-v2

# Run a continuous Service-level health check inside Kubernetes.
kubectl delete pod q4-rollout-probe --ignore-not-found=true >/dev/null 2>&1 || true

kubectl run q4-rollout-probe \
    --restart=Never \
    --image=python:3.13-slim \
    --command -- \
    python3 -c '
import time
import urllib.request

url = "http://spam-api:8000/healthz"
requests = 120
failures = 0

for _ in range(requests):
    try:
        with urllib.request.urlopen(url, timeout=2) as r:
            if r.status != 200:
                failures += 1
    except Exception:
        failures += 1
    time.sleep(0.25)

print(f"requests={requests}")
print(f"failures={failures}")

if failures == 0:
    print("CONTINUOUS_HEALTH_CHECK=PASS")
else:
    print("CONTINUOUS_HEALTH_CHECK=FAIL")

raise SystemExit(0 if failures == 0 else 1)
'

kubectl wait \
    --for=jsonpath='{.status.phase}'=Running \
    pod/q4-rollout-probe \
    --timeout=60s

kubectl apply -f deployment-v2.yaml

kubectl rollout status \
    deployment/spam-api \
    --timeout=180s \
    | tee "$EVID/q4-rollout-status.txt"

set +e

kubectl wait \
    --for=jsonpath='{.status.phase}'=Succeeded \
    pod/q4-rollout-probe \
    --timeout=180s

PROBE_STATUS=$?

set -e

kubectl logs q4-rollout-probe \
    | tee "$EVID/q4-rollout-probe.txt"

if [ "$PROBE_STATUS" -ne 0 ]; then
    echo "Continuous health check detected downtime." >&2
    exit "$PROBE_STATUS"
fi

kubectl rollout history \
    deployment/spam-api \
    | tee "$EVID/q4-rollout-history.txt"

kubectl get pods \
    -l app=spam-api \
    -o wide \
    | tee "$EVID/q4-final-pods.txt"

kubectl delete pod q4-rollout-probe \
    --ignore-not-found=true >/dev/null 2>&1 || true