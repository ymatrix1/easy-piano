"""Import Bartok's Mikrokosmos from the Mikrokosmos-difficulty MusicXML (D33) as a Methods course.

    uv run python -m melody_model.mikrokosmos <dataset_dir> <content_dir> --pieces 1-36

<dataset_dir> holds the dataset's `musicxml/<n>.xml` and `mikrokosmos_metadata.csv`
(github.com/PRamoneda/Mikrokosmos-difficulty, kept in git-ignored `data/`). Writes
`songs/mikrokosmos-NNN.json`, `courses/mikrokosmos-1/levels/mk1-NN.json` and the
course journey, and prints the pieces it skipped with the reason.

Beyond convert.py: the key is the written signature (most pieces have none, so C
or Am, never an analysed modal key), tempo is the metronome mark, and bars where a
hand has two voices are refused because convert.py would keep only the top voice.
"""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

import music21 as m21

from .convert import convert_score
from .notation import Unsupported

COURSE = "mikrokosmos-1"
REPO = "https://github.com/PRamoneda/Mikrokosmos-difficulty"
# Composition protected in the US until 95 years after first publication (1940): D33.
RESTRICTED_IN = [{"region": "US", "until": "2036-01-01"}]
_MAJOR_TONIC = {0: "C", 1: "G", 2: "D", 3: "A", 4: "E", -1: "F", -2: "Bb", -3: "Eb", -4: "Ab"}
_MINOR_TONIC = {0: "Am", 1: "Em", 2: "Bm", 3: "F#m", 4: "C#m", -1: "Dm", -2: "Gm", -3: "Cm", -4: "Fm"}


def written_key(score: m21.stream.Score) -> str:
    """Key name from the written signature; the mode comes from analysis (C vs Am)."""
    sigs = list(score.parts[0].recurse().getElementsByClass(m21.key.KeySignature))
    sharps = {k.sharps for k in sigs}
    if len(sharps) > 1:
        raise Unsupported("key changes")
    n = sharps.pop() if sharps else 0
    if n not in _MAJOR_TONIC:
        raise Unsupported(f"{n} sharps")
    minor = score.analyze("key").mode == "minor"
    return (_MINOR_TONIC if minor else _MAJOR_TONIC)[n]


def bpm(score: m21.stream.Score, time: str) -> int:
    """Metronome mark counted in the time signature's beat unit (content-format.md)."""
    marks = list(score.recurse().getElementsByClass(m21.tempo.MetronomeMark))
    if not marks:
        raise Unsupported("no metronome mark")
    denom = int(time.split("/")[1])
    return round(marks[0].getQuarterBPM() * denom / 4)


def check_single_voice(score: m21.stream.Score) -> None:
    for p in score.parts:
        for m in p.getElementsByClass(m21.stream.Measure):
            if sum(1 for v in m.voices if v.notes) > 1:
                raise Unsupported(f"two voices in one hand, bar {m.number}")


def song(n: int, title: str, score: m21.stream.Score) -> dict:
    check_single_voice(score)
    tune = convert_score(score, key=written_key(score))
    return {
        "id": f"mikrokosmos-{n:03d}",
        "title": f"Mikrokosmos {n}: {title}",
        "composer": "Béla Bartók",
        "arranger": "Béla Bartók; MusicXML by Pedro Ramoneda (Mikrokosmos-difficulty)",
        "source": "Mikrokosmos-difficulty",
        "source_url": f"{REPO}/blob/main/musicxml/{n}.xml",
        "license": "public-domain",
        "composition_license": "public-domain",
        "restricted_in": RESTRICTED_IN,
        "bpm": bpm(score, tune["time"]),
        "time": tune["time"],
        "key": tune["key"],
        "bars": tune["bars"],
    }


def level(n: int, song_id: str) -> dict:
    """Hands alone at the learner's pace, then both hands along with the app."""
    return {
        "id": f"mk1-{n:02d}",
        "title": f"str:node.mk1.{n:02d}",
        "ui": "both",
        "stages": [
            {"type": "wait", "score": song_id, "pre_listen": True, "hand": "RH"},
            {"type": "wait", "score": song_id, "hand": "LH"},
            {"type": "play_along", "score": song_id, "tempo": 0.8, "pass": 0.7, "hand": "both"},
        ],
    }


def journey(pieces: list[tuple[int, str]]) -> dict:
    nodes = []
    for i, (n, song_id) in enumerate(pieces):
        nxt = [f"piece-{pieces[i + 1][0]:02d}"] if i + 1 < len(pieces) else []
        nodes.append(
            {
                "id": f"piece-{n:02d}",
                "kind": "song",
                "title": f"str:node.mk1.{n:02d}",
                "icon": "play",
                "levels": [f"mk1-{n:02d}"],
                "next": nxt,
                "songs": {"default": song_id},
            }
        )
    return {"course": COURSE, "nodes": nodes}


def parse_range(text: str) -> list[int]:
    out: list[int] = []
    for part in text.split(","):
        lo, _, hi = part.partition("-")
        out += range(int(lo), int(hi or lo) + 1)
    return out


def write(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("dataset", type=Path)
    ap.add_argument("content", type=Path)
    ap.add_argument("--pieces", default="1-36")
    args = ap.parse_args(argv)
    with open(args.dataset / "mikrokosmos_metadata.csv", encoding="utf-8") as f:
        titles = {int(r["piece number"]): r["work"] for r in csv.DictReader(f)}
    done: list[tuple[int, str]] = []
    for n in parse_range(args.pieces):
        xml = args.dataset / "musicxml" / f"{n}.xml"
        if not xml.exists():
            print(f"skip {n}: not in dataset")
            continue
        try:
            s = song(n, titles[n].split(", Mikrokosmos")[0], m21.converter.parse(str(xml)))
        except Unsupported as e:
            print(f"skip {n}: {e}")
            continue
        write(args.content / "songs" / f"{s['id']}.json", s)
        write(args.content / "courses" / COURSE / "levels" / f"mk1-{n:02d}.json", level(n, s["id"]))
        done.append((n, s["id"]))
        print(f"ok {n}: {s['title']} ({s['time']}, {s['key']}, {s['bpm']} bpm, {len(s['bars'])} bars)")
    write(args.content / "courses" / COURSE / "journey.json", journey(done))


if __name__ == "__main__":
    main()
