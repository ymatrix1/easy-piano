"""Build the training set from data/melody/raw into data/melody/dataset.

    python -m melody_model.build [--corpora own nottingham pdmx mutopia] [--limit N] [--jobs 28]

Writes tunes.jsonl (one tune per line: id, corpus, split, licence, title,
composer, time, key, bars, plan) and stats.json. Phrase windows and
transposition happen at training time (augment.py), so the file holds each
source tune once. Splits are by source tune (filters.split_of).
"""

from __future__ import annotations

import argparse
import collections
import csv
import json
import re
import sys
import time
from multiprocessing import Pool
from pathlib import Path

from .download import RAW, ROOT
from .filters import dedupe_key, nmd_ok, pdmx_ok, playable, split_of
from .labels import plan
from .notation import Unsupported
from .tokenizer import MAX_BARS, encode_song

OUT = ROOT / "data" / "melody" / "dataset"


def jobs_own():
    for p in sorted((ROOT / "content" / "songs").glob("*.json")):
        yield ("own", p.stem, "json", str(p), {"license": json.loads(p.read_text(encoding="utf-8"))["license"]})


def jobs_nottingham():
    for f in sorted((RAW / "nottingham").glob("*.abc")):
        text = f.read_text(encoding="latin-1")
        for block in re.split(r"\n(?=X:)", text):
            if not block.lstrip().startswith("X:"):
                continue
            x = re.match(r"\s*X:\s*(\d+)", block).group(1)
            meta = {"license": "traditional (NMD)", "skip": None if nmd_ok(block) else "nmd named composer"}
            yield ("nottingham", f"{f.stem}-{x}", "abc", block, meta)


def jobs_pdmx(limit: int | None):
    d = RAW / "pdmx"
    csv.field_size_limit(10**9)
    n = 0
    with open(d / "PDMX.csv", encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            ok, why = pdmx_ok(row)
            tune_id = row["mxl"].rsplit("/", 1)[-1].removesuffix(".mxl")
            meta = {"license": row["license"], "title": row["title"], "composer": row["composer_name"],
                    "n_tracks": row["n_tracks"], "skip": None if ok else why}
            if not ok:
                yield ("pdmx", tune_id, "skip", "", meta)
                continue
            yield ("pdmx", tune_id, "mxl", str(d / row["mxl"]), meta)
            n += 1
            if limit and n >= limit:
                return


def jobs_mutopia():
    man = RAW / "mutopia" / "manifest.json"
    if not man.exists():
        return
    for e in json.loads(man.read_text(encoding="utf-8"))["files"]:
        yield ("mutopia", e["path"].removesuffix(".mid"), "mid", str(RAW / "mutopia" / e["path"]),
               {"license": e["license"], "title": e["title"], "composer": e["composer"]})


def work(job):
    """Convert one source item; returns (job meta, [songs], [errors])."""
    corpus, tune_id, kind, src, meta = job
    if meta.get("skip"):
        return corpus, tune_id, meta, [], [meta["skip"]]
    try:
        import music21 as m21
        from .convert import convert_score
        if kind == "json":
            s = json.loads(Path(src).read_text(encoding="utf-8"))
            songs = [{"title": s["title"], "composer": s.get("composer", ""), "time": s["time"], "key": s["key"],
                      "bars": [{h: b[h] for h in ("RH", "LH") if h in b} for b in s["bars"]]}]
        else:
            if kind == "abc":
                parsed = m21.converter.parseData(src, format="abc")
            else:
                parsed = m21.converter.parse(src, forceSource=True, quantizePost=kind == "mid")
            scores = list(parsed.scores) if isinstance(parsed, m21.stream.Opus) else [parsed]
            melody_only = kind == "mid" or (kind == "mxl" and meta.get("n_tracks") != "1")
            songs = [convert_score(sc, melody_only=melody_only) for sc in scores[:1]]
        return corpus, tune_id, meta, songs, []
    except Unsupported as e:
        return corpus, tune_id, meta, [], [_reason(str(e))]
    except Exception as e:  # parser crashes on malformed sources
        return corpus, tune_id, meta, [], [f"parse error: {type(e).__name__}"]


def _reason(msg: str) -> str:
    return re.sub(r"\d+(/\d+)?", "N", msg)


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpora", nargs="+", default=["own", "nottingham", "mutopia", "pdmx"])
    ap.add_argument("--limit", type=int, default=None, help="max PDMX candidates (smoke runs)")
    ap.add_argument("--jobs", type=int, default=28)
    args = ap.parse_args(argv)

    gens = {"own": jobs_own, "nottingham": jobs_nottingham, "mutopia": jobs_mutopia,
            "pdmx": lambda: jobs_pdmx(args.limit)}
    jobs = [j for c in args.corpora for j in gens[c]()]
    OUT.mkdir(parents=True, exist_ok=True)
    stats = collections.defaultdict(lambda: collections.Counter())
    seen: dict[str, str] = {}
    t0 = time.time()
    with Pool(args.jobs) as pool, open(OUT / "tunes.jsonl", "w", encoding="utf-8") as out:
        for i, (corpus, tune_id, meta, songs, errors) in enumerate(pool.imap_unordered(work, jobs, chunksize=8)):
            st = stats[corpus]
            st["sources"] += 1
            for e in errors:
                st["reject: " + e] += 1
            for song in songs:
                song["bars"] = song["bars"][:MAX_BARS]
                ok, why = playable(song)
                if not ok:
                    st["reject: " + why] += 1
                    continue
                try:
                    encode_song(song)  # vocab coverage (keys, ranges, durations)
                except Unsupported as e:
                    st["reject: " + _reason(str(e))] += 1
                    continue
                key = dedupe_key(song)
                if key in seen and corpus != "own":
                    st["reject: duplicate"] += 1
                    continue
                seen[key] = f"{corpus}:{tune_id}"
                split = "train" if corpus == "own" else split_of(corpus, tune_id)
                rec = {"id": f"{corpus}:{tune_id}", "corpus": corpus, "split": split, "license": meta.get("license"),
                       "title": song.get("title") or meta.get("title", ""), "composer": song.get("composer") or meta.get("composer", ""),
                       "time": song["time"], "key": song["key"], "bars": song["bars"], "plan": plan(song)}
                out.write(json.dumps(rec, ensure_ascii=False) + "\n")
                st["kept"] += 1
                st[f"split {split}"] += 1
                st[f"time {song['time']}"] += 1
                st["bars total"] += len(song["bars"])
                st["two hands"] += any("LH" in b for b in song["bars"]) and any("RH" in b for b in song["bars"])
            if i % 2000 == 0:
                print(f"{i}/{len(jobs)} {time.time() - t0:.0f}s", flush=True)
    summary = {c: dict(sorted(s.items())) for c, s in stats.items()}
    summary["_elapsed_s"] = round(time.time() - t0)
    (OUT / "stats.json").write_text(json.dumps(summary, indent=1), encoding="utf-8")
    print(json.dumps(summary, indent=1))


if __name__ == "__main__":
    main(sys.argv[1:])
