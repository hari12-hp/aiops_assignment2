FROM python:3.13-slim

WORKDIR /app

COPY validator.py ./
COPY shards ./shards

CMD ["python", "validator.py"]
