FROM python:3.13

WORKDIR /app

COPY requirements.txt sklearn_version.txt ./
COPY api.py model.joblib ./

RUN pip install --no-cache-dir -r requirements.txt \
    "scikit-learn==$(cat sklearn_version.txt)"

CMD ["uvicorn", "api:app", "--host", "0.0.0.0", "--port", "8000"]
