"""Random sample of kept tunes for human review (gate bean piano-qpyc).

    python -m melody_model.sample --corpus pdmx --n 50 --seed 1

Writes data/melody/sample-<corpus>/: one song JSON per tune (listening-test
format, bpm 100), manifest.json for tools/listening-test, and sample.md
with title, composer, licence and source id per tune.
"""

from __future__ import annotations

import argparse
import json
import random
import sys

from .build import OUT
from .download import ROOT


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", default="pdmx")
    ap.add_argument("--n", type=int, default=50)
    ap.add_argument("--seed", type=int, default=1)
    args = ap.parse_args(argv)
    tunes = [json.loads(line) for line in open(OUT / "tunes.jsonl", encoding="utf-8")]
    pool = sorted((t for t in tunes if t["corpus"] == args.corpus), key=lambda t: t["id"])
    picked = random.Random(args.seed).sample(pool, min(args.n, len(pool)))
    d = ROOT / "data" / "melody" / f"sample-{args.corpus}"
    (d / "songs").mkdir(parents=True, exist_ok=True)
    items, rows = [], []
    for i, t in enumerate(picked, 1):
        name = f"{i:02d}.json"
        song = {"id": f"sample-{i:02d}", "title": t["title"], "bpm": 100, "time": t["time"], "key": t["key"], "bars": t["bars"]}
        (d / "songs" / name).write_text(json.dumps(song, indent=1, ensure_ascii=False), encoding="utf-8")
        items.append({"path": f"songs/{name}", "method": args.corpus})
        src = t["id"].split(":", 1)[1]
        rows.append(f"| {i} | {t['title'] or '?'} | {t['composer'] or '?'} | {t['license']} | {t['time']} {t['key']}, {len(t['bars'])} bars | `{src}` |")
    (d / "manifest.json").write_text(json.dumps({"items": items}, indent=1), encoding="utf-8")
    md = [f"# {args.corpus} sample: {len(picked)} of {len(pool)} kept tunes (seed {args.seed})", "",
          "| # | Title | Composer | Licence | Shape | Source id |", "|---|---|---|---|---|---|", *rows, ""]
    (d / "sample.md").write_text("\n".join(md), encoding="utf-8")
    print(d / "sample.md")


if __name__ == "__main__":
    main(sys.argv[1:])
