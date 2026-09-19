# question4/api_v2.py

from fastapi import FastAPI
from pydantic import BaseModel
import joblib

app = FastAPI()
model = joblib.load("model.joblib")


class Text(BaseModel):
    text: str


@app.get("/healthz")
def healthz():
    return {
        "status": "ok",
        "version": "v2"
    }


@app.post("/predict")
def predict(message: Text):
    prediction = model.predict([message.text])[0]
    return {"label": prediction}
