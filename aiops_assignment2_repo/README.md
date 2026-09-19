# AIOps Module 3 — Assignment 2

This repository implements the four questions in the assignment:

- Q1: single-stage and multi-stage Docker images
- Q2: FastAPI + Redis with Docker Compose
- Q3: Kubernetes Indexed Job for eight CSV shards
- Q4: Kubernetes Deployment, self-healing, and rolling update

The assignment requires a spam/ham REST API, a naive and multi-stage Docker build, Redis caching with Compose, an Indexed Job for eight unrelated CSV shards, and a two-replica Deployment with readiness, self-healing, and rolling-update evidence.

## Requirements

Install these before running the assignment:

- Docker Engine
- Docker Compose plugin (`docker compose`)
- `kubectl`
- Minikube
- Python 3
- `curl`

Use a Python virtual environment for the host-side scripts.

## One-command run

From the repository root:

```bash
chmod +x run_all.sh
./run_all.sh
```

The script:

1. Generates the deterministic 1,000-row dataset and trains the TF-IDF + MultinomialNB model.
2. Copies the model and exact scikit-learn version into Q1, Q2, and Q4 so the serialized model is loaded with the same scikit-learn version used for training.
3. Builds and tests both Q1 Docker images and records sizes, history, and endpoint output.
4. Starts Q2 on host port `8001` with Redis at the Compose service name `cache` and records cache timings/logs.
5. Creates a dedicated two-node Minikube profile named `aiops-m3`, with two CPUs per node, for Q3/Q4.
6. Runs the eight-shard Indexed Job, captures actual concurrent pods, and collects pod logs through the Kubernetes API.
7. Deploys Q4 v1, demonstrates self-healing, builds v2, performs a rolling update, and runs a continuous readiness check during the rollout.

The script leaves the dedicated Minikube profile running so the final Kubernetes resources can be inspected. It does not delete unrelated Minikube profiles.

## Port layout

| Workload | Host port | Container port |
|---|---:|---:|
| Q1 naive test | 18001 | 8000 |
| Q1 multi-stage test | 18002 | 8000 |
| Q2 Compose API | 8001 | 8000 |
| Q4 Kubernetes Service | 18004 via port-forward | 8000 |

Q3 has no HTTP port.

## Important implementation details

### Q1

The naive image uses `python:3.13`. The multi-stage build uses `python:3.13` as the builder and `python:3.13-slim` as the final runtime image. Only the installed application dependencies are copied from the builder's `/install` directory.

The actual image sizes and reduction percentage are generated at runtime in `evidence/` rather than hard-coded.

### Q2

The API generates a SHA-256 cache key from the exact input text. A cache miss performs model inference and stores the label for 60 seconds. A hit returns the cached label without model inference.

Compose exposes the API on host port `8001`, while the API reaches Redis through the service hostname `cache:6379`.

### Q3

The Job uses:

```yaml
completions: 8
parallelism: 4
completionMode: Indexed
```

Each validator requests and is limited to one CPU, so four concurrently running validators consume four CPUs. The Indexed Job supplies `JOB_COMPLETION_INDEX`; the Downward API supplies `POD_NAME` and `NODE_NAME`.

The shard CSV files are copied into the validator image rather than placed on a shared volume. Minikube's default host-path provisioner is not a shared multi-node filesystem, so image-bundled shards avoid node-local storage coordination.

The validator holds briefly before reading its shard so that `kubectl get pods -o wide` can observe the four real Running pods concurrently.

### Q4

The Deployment has two replicas, CPU requests/limits, and a readiness probe on `/healthz`. The update changes the `/healthz` version from `v1` to `v2`. `maxUnavailable: 0` and `maxSurge: 1` preserve existing ready capacity while the new replica becomes ready.


