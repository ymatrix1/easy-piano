"""Join ratings with the hidden key and print per-method stats.

Usage: python summarize.py ratings.json [--key out/key.json]
"""
import argparse
import json
import statistics
from collections import defaultdict
from pathlib import Path


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("ratings")
    ap.add_argument("--key", default=str(Path(__file__).parent / "out" / "key.json"))
    args = ap.parse_args()

    key = json.loads(Path(args.key).read_text(encoding="utf-8"))
    ratings = json.loads(Path(args.ratings).read_text(encoding="utf-8"))["ratings"]

    by_method = defaultdict(list)
    familiar = defaultdict(list)
    unknown = 0
    for r in ratings:
        entry = key.get(r["id"])
        if entry is None:
            unknown += 1
            continue
        if r.get("rating"):
            by_method[entry["method"]].append(r["rating"])
        if r.get("familiar"):
            familiar[entry["method"]].append((entry["path"], r.get("note", "")))

    print(f"{'method':<16}{'n':>4}{'mean':>7}{'median':>8}{'familiar':>10}")
    for method in sorted(set(by_method) | set(familiar), key=lambda m: -statistics.mean(by_method[m] or [0])):
        scores = by_method[method]
        mean = f"{statistics.mean(scores):.2f}" if scores else "-"
        median = f"{statistics.median(scores):.1f}" if scores else "-"
        print(f"{method:<16}{len(scores):>4}{mean:>7}{median:>8}{len(familiar[method]):>10}")
    if unknown:
        print(f"\n{unknown} rating(s) had ids not in the key (wrong key file?)")
    if familiar:
        print("\nSounds familiar:")
        for method, hits in sorted(familiar.items()):
            for path, note in hits:
                print(f"  [{method}] {path}" + (f": {note}" if note else ""))


if __name__ == "__main__":
    main()
