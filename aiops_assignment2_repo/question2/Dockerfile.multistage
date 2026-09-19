FROM python:3.13 AS builder

WORKDIR /build

COPY requirements.txt sklearn_version.txt ./

RUN pip install --no-cache-dir --prefix=/install -r requirements.txt \
    "scikit-learn==$(cat sklearn_version.txt)"

FROM python:3.13-slim

WORKDIR /app

COPY api.py model.joblib ./
COPY --from=builder /install /usr/local

CMD ["uvicorn", "api:app", "--host", "0.0.0.0", "--port", "8000"]
