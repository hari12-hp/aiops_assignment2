import csv
from pathlib import Path

OUT = Path(__file__).resolve().parent / "shards"


def main() -> None:
    OUT.mkdir(exist_ok=True)

    for shard in range(8):
        expected_invalid = shard + 1
        path = OUT / f"shard_{shard}.csv"

        with path.open("w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(["name", "email", "required"])

            for row_index in range(100):
                name = f"user_{shard}_{row_index}"
                email = f"{name}@example.com"
                required = "ok"

                if row_index < expected_invalid:
                    if row_index % 2 == 0:
                        email = f"{name}@"
                    else:
                        required = ""

                writer.writerow([name, email, required])

        print(f"{path.name}: expected_invalid_rows={expected_invalid}")


if __name__ == "__main__":
    main()
