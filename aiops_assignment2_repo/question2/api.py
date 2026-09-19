import hashlib

import joblib
import redis
from fastapi import FastAPI
from pydantic import BaseModel

app = FastAPI()
model = joblib.load("model.joblib")

cache = redis.Redis(
    host="cache",
    port=6379,
    decode_responses=True,
)


class Text(BaseModel):
    text: str


def cache_key(text: str) -> str:
    digest = hashlib.sha256(text.encode("utf-8")).hexdigest()
    return f"prediction:{digest}"


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.post("/predict")
def predict(message: Text):
    key = cache_key(message.text)

    cached = cache.get(key)
    if cached is not None:
        print("cache HIT", flush=True)
        return {"label": cached}

    print("cache MISS", flush=True)
    prediction = model.predict([message.text])[0]
    cache.setex(key, 60, prediction)

    return {"label": prediction}
