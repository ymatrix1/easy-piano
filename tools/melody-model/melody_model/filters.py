"""Dataset filters: licence/pop screens per corpus, playability, dedupe key."""

from __future__ import annotations

import hashlib
import re

from .labels import melody, signature
from .notation import parse_hand

# --- PDMX pop screen (docs/research/melody-corpora.md) ---------------------
PDMX_GENRES = {"classical", "folk", "religiousmusic", "worldmusic"}
# Composers/artists whose work is in copyright and often mis-tagged as PD on MuseScore.
BLOCKED_NAMES = re.compile(
    r"williams|zimmer|shore|uematsu|kondo|einaudi|yiruma|tiersen|elfman|morricone|hisaishi|"
    r"badelt|giacchino|horner|silvestri|desplat|djawadi|toby fox|c418|mitsuda|sakimoto|"
    r"beatles|lennon|mccartney|queen|disney|menken|lloyd webber|sondheim|piazzolla|"
    r"gershwin|anime",
    re.I)
BLOCKED_TITLES = re.compile(
    r"\b(theme|ost|soundtrack|anime|undertale|zelda|mario|pokemon|minecraft|naruto|star wars|"
    r"harry potter|hedwig|pirates|frozen|game of thrones|interstellar|megalovania|tetris|"
    r"opening|ending|meme|remix|cover|fnaf|genshin|tiktok)\b",
    re.I)


def pdmx_ok(row: dict) -> tuple[bool, str]:
    if row["subset:no_license_conflict"] != "True":
        return False, "pdmx licence conflict"
    if row["subset:deduplicated"] != "True":
        return False, "pdmx duplicate"
    genres = set(row["genres"].split("-")) - {"NA"}
    if genres and not genres <= PDMX_GENRES:
        return False, "pdmx genre"
    if not genres and row["is_original"] != "True":
        return False, "pdmx untagged non-original"
    names = " ".join(row[k] for k in ("composer_name", "artist_name") if row[k] != "NA")
    if names and BLOCKED_NAMES.search(names):
        return False, "pdmx blocked name"
    title = " ".join(row[k] for k in ("title", "song_name", "subtitle") if row[k] != "NA")
    if BLOCKED_TITLES.search(title):
        return False, "pdmx blocked title"
    try:
        bars = int(float(row["song_length.bars"]))
    except ValueError:
        return False, "pdmx no length"
    if not 4 <= bars <= 256:
        return False, "pdmx length"
    return True, ""


# --- Nottingham: drop tunes credited to a named (possibly living) composer --
NMD_COMPOSED = re.compile(r"^S:\s*(by|composed|written|words and music|music by)\b", re.I | re.M)


def nmd_ok(abc_tune: str) -> bool:
    return not NMD_COMPOSED.search(abc_tune)


# --- playability ------------------------------------------------------------
MAX_RANGE = 24   # semitones per hand
MAX_LEAP = 12    # melody, semitones
MAX_EVENTS = 16  # per bar per hand
MAX_CHORD = {"RH": 3, "LH": 4}
MIN_NOTES = 8


def playable(song: dict) -> tuple[bool, str]:
    notes = 0
    for hand in ("RH", "LH"):
        lo, hi = 999, -1
        for bar in song["bars"]:
            if hand not in bar:
                continue
            events = parse_hand(bar[hand])
            if len(events) > MAX_EVENTS:
                return False, "too dense"
            for e in events:
                if len(e.pitches) > MAX_CHORD[hand]:
                    return False, "big chord"
                for p in e.pitches:
                    lo, hi = min(lo, p.midi), max(hi, p.midi)
                notes += bool(e.pitches)
        if hi >= 0 and hi - lo > MAX_RANGE:
            return False, "wide range"
    if notes < MIN_NOTES:
        return False, "too few notes"
    line = [max(e.pitches, key=lambda p: p.midi).midi for b in song["bars"] for e in melody(b) if e.pitches]
    if any(abs(a - b) > MAX_LEAP for a, b in zip(line, line[1:])):
        return False, "big leap"
    return True, ""


def dedupe_key(song: dict, bars: int = 16) -> str:
    """Transposition-invariant hash of the first bars' melody rhythm + intervals."""
    sig = []
    for b in song["bars"][:bars]:
        sig.extend(signature(melody(b)))
    first = next((x[1] for x in sig if x[1] is not None), 0)
    norm = [(d, None if n is None else n - first) for d, n in sig]
    return hashlib.sha1(repr((song["time"], norm)).encode()).hexdigest()


def split_of(corpus: str, tune_id: str) -> str:
    """Deterministic 90/5/5 split by source tune, so variants never cross splits."""
    h = int(hashlib.sha1(f"{corpus}:{tune_id}".encode()).hexdigest(), 16) % 100
    return "train" if h < 90 else ("valid" if h < 95 else "test")
