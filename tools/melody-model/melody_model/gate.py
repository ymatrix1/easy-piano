"""50-tune review gate before training (docs/research/melody-corpora.md, bean piano-qpyc).

    python -m melody_model.gate approve --seed 1 --n 50 --approver-words "<the user's words>" --date 2026-10-20
    python -m melody_model.gate check

The approval is tied to the dataset it was sampled from (sha256 of tunes.jsonl).
A rebuild changes the hash, so a new sample must be reviewed and approved.
Record an approval only with the user's own words.
"""

from __future__ import annotations

import argparse
import json
import sys

from .build import OUT
from .download import ROOT, file_sha256

GATE = ROOT / "data" / "melody" / "gate.json"


def dataset_hash() -> str:
    return file_sha256(OUT / "tunes.jsonl")


def require_gate() -> dict:
    """Raise SystemExit unless the current dataset has a recorded approval."""
    if not GATE.exists():
        raise SystemExit(f"no review gate at {GATE}: sample 50 PDMX tunes (melody_model.sample) and record the user's approval")
    gate = json.loads(GATE.read_text(encoding="utf-8"))
    current = dataset_hash()
    if gate.get("dataset_sha256") != current:
        raise SystemExit(f"review gate is for dataset {gate.get('dataset_sha256')}, current is {current}: review a new sample")
    return gate


def main(argv):
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("approve")
    a.add_argument("--seed", type=int, required=True)
    a.add_argument("--n", type=int, required=True)
    a.add_argument("--approver-words", required=True)
    a.add_argument("--date", required=True)
    sub.add_parser("check")
    args = ap.parse_args(argv)
    if args.cmd == "approve":
        GATE.write_text(json.dumps({"corpus": "pdmx", "seed": args.seed, "n": args.n, "dataset_sha256": dataset_hash(),
                                    "approver_words": args.approver_words, "date": args.date}, indent=1) + "\n", encoding="utf-8")
        print(f"recorded {GATE}")
    else:
        print(json.dumps(require_gate(), indent=1))


if __name__ == "__main__":
    main(sys.argv[1:])
