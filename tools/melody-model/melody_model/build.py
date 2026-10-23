"""Build the training set from data/melody/raw into data/melody/dataset.

    python -m melody_model.build [--corpora own nottingham mutopia pdmx <local names>] [--limit N] [--jobs 28]

Writes tunes.jsonl (one tune per line) and stats.json. Each tune carries its
provenance (corpus, source_url, sha256, license, composition_license, arranger,
flags) so any corpus or flag can be dropped and the model retrained. Phrase
windows and transposition happen at training time (augment.py), so the file
holds each source tune once.

Deterministic: jobs run in a fixed order, results are consumed in job order
(Pool.imap), dedupe keeps the first tune of a duplicate group, splits are by
source tune or group (filters.split_of). Same inputs give byte-identical output.
"""

from __future__ import annotations

import argparse
import collections
import csv
import hashlib
import json
import re
import sys
import time
from multiprocessing import Pool
from pathlib import Path

from .download import NMD_URL, RAW, ROOT
from .filters import dedupe_key, nmd_ok, pdmx_flags, pdmx_ok, playable, split_of
from .labels import plan
from .notation import Unsupported
from .styles import styles_for
from .tokenizer import MAX_BARS, encode_song

OUT = ROOT / "data" / "melody" / "dataset"
BUILTIN = ("own", "nottingham", "mutopia", "pdmx")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def jobs_own():
    for p in sorted((ROOT / "content" / "songs").glob("*.json")):
        s = json.loads(p.read_text(encoding="utf-8"))
        yield (
            "own",
            p.stem,
            "json",
            str(p),
            {
                "license": s["license"],
                "composition_license": s.get("composition_license"),
                "arranger": s.get("arranger"),
                "source_url": s.get("source_url") or f"content/songs/{p.name}",
                "sha256": sha256(p.read_bytes()),
            },
        )


def jobs_nottingham():
    for f in sorted((RAW / "nottingham").glob("*.abc")):
        text = f.read_text(encoding="latin-1")
        for block in re.split(r"\n(?=X:)", text):
            if not block.lstrip().startswith("X:"):
                continue
            x = re.match(r"\s*X:\s*(\d+)", block).group(1)
            yield (
                "nottingham",
                f"{f.stem}-{x}",
                "abc",
                block,
                {
                    "license": "no licence stated; used under D18 (risk accepted)",
                    "composition_license": "traditional",
                    "arranger": "Nottingham Music Database (E. Foxley)",
                    "source_url": NMD_URL.format(name=f.stem),
                    "sha256": sha256(block.encode("utf-8")),
                    "skip": None if nmd_ok(block) else "nmd named composer",
                },
            )


def jobs_pdmx(limit: int | None):
    d = RAW / "pdmx"
    csv.field_size_limit(10**9)
    n = 0
    with open(d / "PDMX.csv", encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            ok, why = pdmx_ok(row)
            tune_id = row["mxl"].rsplit("/", 1)[-1].removesuffix(".mxl")
            meta = {
                "license": row["license"],
                "composition_license": "unverified (uploader tag)",
                "arranger": row["artist_name"] if row["artist_name"] != "NA" else "",
                "source_url": f"https://zenodo.org/records/15571083 {row['mxl']}",
                "title": row["title"],
                "composer": row["composer_name"],
                "n_tracks": row["n_tracks"],
                "genres": row["genres"],
                "tags": row["tags"],
                "groups": row["groups"],
                "skip": None if ok else why,
                "flags": pdmx_flags(row),
            }
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
        yield (
            "mutopia",
            e["path"].removesuffix(".mid"),
            "mid",
            str(RAW / "mutopia" / e["path"]),
            {
                "license": e["license"],
                "composition_license": "public-domain (Mutopia header)",
                "arranger": "Mutopia typesetter",
                "source_url": e["url"],
                "sha256": e["sha256"],
                "title": e["title"],
                "composer": e["composer"],
                "style": e.get("style", ""),
            },
        )


LOCAL = ROOT / "data" / "melody" / "local-datasets.json"
TIMINGS = ("score", "performed")
METERS = ("2/4", "3/4", "4/4")


def load_local() -> list[dict]:
    """Local MIDI datasets registered in data/melody/local-datasets.json (git-ignored).

    Required: name, path (folder of .mid/.midi, searched recursively), source,
    license (non-empty strings, recorded as given), flags (list of strings, may
    be empty). Optional: timing ("score": tempo-mapped, quantized by music21;
    "performed": tempo estimated from onsets), track (index or name of the
    melody part/track, default 0), meter (performed only, default "4/4"),
    group_by ("file" or "folder": split unit, default "file").
    Template: tools/melody-model/local-datasets.example.json.
    """
    if not LOCAL.exists():
        return []
    entries = json.loads(LOCAL.read_text(encoding="utf-8"))
    if not isinstance(entries, list):
        raise SystemExit(f"{LOCAL}: expected a list of datasets")
    names = set()
    for e in entries:
        where = f"{LOCAL}: dataset {e.get('name')!r}"
        for k in ("name", "path", "source", "license"):
            if not isinstance(e.get(k), str) or not e[k].strip():
                raise SystemExit(f"{where}: {k} must be a non-empty string")
        if not isinstance(e.get("flags"), list) or not all(isinstance(f, str) and f for f in e["flags"]):
            raise SystemExit(f"{where}: flags must be a list of strings")
        if e.get("timing", "score") not in TIMINGS:
            raise SystemExit(f"{where}: timing must be one of {TIMINGS}")
        if e.get("meter", "4/4") not in METERS:
            raise SystemExit(f"{where}: meter must be one of {METERS}")
        from .tokenizer import STYLES

        if not isinstance(e.get("styles", []), list) or not set(e.get("styles", [])) <= set(STYLES):
            raise SystemExit(f"{where}: styles must be a list from {STYLES}")
        if e.get("group_by", "file") not in ("file", "folder"):
            raise SystemExit(f"{where}: group_by must be 'file' or 'folder'")
        if not isinstance(e.get("track", 0), (int, str)) or isinstance(e.get("track", 0), bool):
            raise SystemExit(f"{where}: track must be an index or a name")
        if e["name"] in BUILTIN or e["name"] in names:
            raise SystemExit(f"{where}: name is reserved or used twice")
        names.add(e["name"])
    return entries


def jobs_local(entry: dict):
    root = Path(entry["path"])
    if not root.is_absolute():
        root = ROOT / root
    kind = "performed" if entry.get("timing") == "performed" else "mid"
    files = sorted(set(root.rglob("*.mid")) | set(root.rglob("*.midi")))
    for f in files:
        rel = f.relative_to(root)
        group = rel.parent.as_posix() if entry.get("group_by") == "folder" else rel.as_posix()
        yield (
            entry["name"],
            rel.with_suffix("").as_posix(),
            kind,
            str(f),
            {
                "license": entry["license"],
                "composition_license": entry.get("composition_license", ""),
                "arranger": entry.get("arranger", ""),
                "source_url": entry["source"],
                "sha256": sha256(f.read_bytes()),
                "flags": list(entry["flags"]),
                "group": group,
                "track": entry.get("track", 0),
                "meter": entry.get("meter", "4/4"),
                "styles": list(entry.get("styles", [])),
            },
        )


def work(job):
    """Convert one source item; returns (corpus, tune_id, meta, [songs], [errors])."""
    corpus, tune_id, kind, src, meta = job
    if meta.get("skip"):
        return corpus, tune_id, meta, [], [meta["skip"]]
    try:
        import music21 as m21

        from .convert import convert_score

        if kind == "performed":
            from .timed import performed_song

            return corpus, tune_id, meta, [performed_song(src, meta["track"], meter=meta["meter"])], []
        if kind == "json":
            s = json.loads(Path(src).read_text(encoding="utf-8"))
            songs = [
                {
                    "title": s["title"],
                    "composer": s.get("composer", ""),
                    "time": s["time"],
                    "key": s["key"],
                    "bars": [{h: b[h] for h in ("RH", "LH") if h in b} for b in s["bars"]],
                }
            ]
        else:
            if kind == "abc":
                parsed = m21.converter.parseData(src, format="abc")
            else:
                parsed = m21.converter.parse(src, forceSource=True, quantizePost=kind == "mid")
                if kind == "mxl":
                    meta = {**meta, "sha256": sha256(Path(src).read_bytes())}
            scores = list(parsed.scores) if isinstance(parsed, m21.stream.Opus) else [parsed]
            melody_only = kind == "mid" or (kind == "mxl" and meta.get("n_tracks") != "1")
            if len(scores) != 1:
                raise Unsupported(f"{len(scores)} scores in one file")  # an Opus of movements: not one tune
            songs = [convert_score(scores[0], melody_only=melody_only, part=meta.get("track", 0))]
        return corpus, tune_id, meta, songs, []
    except Unsupported as e:
        return corpus, tune_id, meta, [], [_reason(str(e))]
    except Exception as e:  # parser crashes on malformed sources
        return corpus, tune_id, meta, [], [f"parse error: {type(e).__name__}"]


def _reason(msg: str) -> str:
    return re.sub(r"\d+(/\d+)?", "N", msg)


def phrase_cut(song: dict) -> int | None:
    """Bar count to keep for a tune over MAX_BARS: the last phrase end (stable cadence on a
    4-bar boundary) within bars 32..MAX_BARS, so a cut never falls mid-phrase."""
    labels = plan({**song, "bars": song["bars"][:MAX_BARS]})
    for n in range(MAX_BARS, MAX_BARS // 2 - 1, -1):
        if n % 4 == 0 and labels[n - 1][1] == "STABLE":
            return n
    return None


def record(corpus, tune_id, meta, song, split) -> dict:
    return {
        "id": f"{corpus}:{tune_id}",
        "corpus": corpus,
        "split": split,
        "source_url": meta.get("source_url", ""),
        "sha256": meta.get("sha256", ""),
        "license": meta.get("license", ""),
        "composition_license": meta.get("composition_license", ""),
        "arranger": meta.get("arranger", ""),
        "flags": meta.get("flags", []),
        "styles": styles_for(corpus, {**meta, "title": song.get("title") or meta.get("title", "")}),
        "title": song.get("title") or meta.get("title", ""),
        "composer": song.get("composer") or meta.get("composer", ""),
        "time": song["time"],
        "key": song["key"],
        "bars": song["bars"],
        "plan": plan(song),
    }


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--corpora",
        nargs="+",
        default=list(BUILTIN),
        help="built-in corpora and/or names from data/melody/local-datasets.json (local ones are opt-in)",
    )
    ap.add_argument("--limit", type=int, default=None, help="max PDMX candidates (smoke runs)")
    ap.add_argument("--jobs", type=int, default=28)
    args = ap.parse_args(argv)

    gens = {
        "own": jobs_own,
        "nottingham": jobs_nottingham,
        "mutopia": jobs_mutopia,
        "pdmx": lambda: jobs_pdmx(args.limit),
    }
    for entry in load_local():
        gens[entry["name"]] = lambda e=entry: jobs_local(e)
    unknown = [c for c in args.corpora if c not in gens]
    if unknown:
        raise SystemExit(f"unknown corpora {unknown}")
    # own first, so other corpora's copies of our songs are the ones dropped as duplicates
    order = sorted(args.corpora, key=lambda c: (c != "own", args.corpora.index(c)))
    jobs = [j for c in order for j in gens[c]()]
    OUT.mkdir(parents=True, exist_ok=True)
    stats = collections.defaultdict(collections.Counter)
    seen: dict[str, str] = {}
    t0 = time.time()
    with Pool(args.jobs) as pool, open(OUT / "tunes.jsonl", "w", encoding="utf-8", newline="\n") as out:
        for i, (corpus, tune_id, meta, songs, errors) in enumerate(pool.imap(work, jobs, chunksize=8)):
            st = stats[corpus]
            st["sources"] += 1
            for e in errors:
                st["reject: " + e] += 1
            for song in songs:
                if len(song["bars"]) > MAX_BARS:
                    cut = phrase_cut(song)
                    if cut is None:
                        st["reject: too long, no phrase end in bars 32-64"] += 1
                        continue
                    st["cut at a phrase end (over 64 bars)"] += 1
                    song["bars"] = song["bars"][:cut]
                try:
                    ok, why = playable(song)
                    if not ok:
                        st["reject: " + why] += 1
                        continue
                    encode_song(song)  # vocab coverage (keys, ranges, durations)
                except Unsupported as e:  # e.g. triplets in our own advanced courses
                    st["reject: " + _reason(str(e))] += 1
                    continue
                key = dedupe_key(song)
                if key in seen:
                    st["reject: duplicate"] += 1
                    continue
                seen[key] = f"{corpus}:{tune_id}"
                split = "train" if corpus == "own" else split_of(corpus, meta.get("group", tune_id))
                rec = record(corpus, tune_id, meta, song, split)
                out.write(json.dumps(rec, ensure_ascii=False, sort_keys=True) + "\n")
                st["kept"] += 1
                st["kept unflagged"] += not rec["flags"]
                for f in rec["flags"]:
                    st[f"flag {f}"] += 1
                for x in rec["styles"] or ["(none)"]:
                    st[f"style {x}"] += 1
                st[f"split {split}"] += 1
                st[f"time {song['time']}"] += 1
                st["bars total"] += len(song["bars"])
            if i % 5000 == 0:
                print(f"{i}/{len(jobs)} {time.time() - t0:.0f}s", flush=True)
    import music21

    summary = {c: dict(sorted(s.items())) for c, s in sorted(stats.items())}
    summary["_build"] = {
        "corpora": order,
        "music21": music21.__version__,
        "tunes_sha256": sha256((OUT / "tunes.jsonl").read_bytes()),
    }
    (OUT / "stats.json").write_text(json.dumps(summary, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=1))
    print(f"elapsed {time.time() - t0:.0f}s")


if __name__ == "__main__":
    main(sys.argv[1:])
