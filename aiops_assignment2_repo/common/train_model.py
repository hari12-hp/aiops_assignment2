import csv
from pathlib import Path

import joblib
from sklearn import __version__ as sklearn_version
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.naive_bayes import MultinomialNB
from sklearn.pipeline import Pipeline


ROOT = Path(__file__).resolve().parent
DATASET = ROOT / "spam_dataset.csv"
MODEL = ROOT / "model.joblib"
VERSION = ROOT / "sklearn_version.txt"


def main() -> None:
    texts = []
    labels = []

    with DATASET.open(newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            texts.append(row["text"])
            labels.append(row["label"])

    model = Pipeline(
        [
            ("tfidf", TfidfVectorizer()),
            ("nb", MultinomialNB()),
        ]
    )
    model.fit(texts, labels)

    joblib.dump(model, MODEL)
    VERSION.write_text(sklearn_version + "\n", encoding="utf-8")

    print(f"Saved {MODEL.name}")
    print(f"scikit-learn={sklearn_version}")


if __name__ == "__main__":
    main()
