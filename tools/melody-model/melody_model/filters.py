"""Dataset filters: licence/pop screens per corpus, playability, dedupe key."""

from __future__ import annotations

import hashlib
import re

from .labels import melody
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

# A PD composition does not clear a modern arrangement (docs/research/melody-corpora.md).
ARRANGED = re.compile(r"\b(arr\.?|arranged|arrangement|version|easy piano|simplified)\b", re.I)


def pdmx_flags(row: dict) -> list[str]:
    """Clean-data risks of a PDMX row. Kept, not dropped (D21): exclude flagged tunes to train a clean model."""
    flags = []
    if row.get("subset:no_license_conflict", "True") != "True":
        flags.append("licence-conflict")  # user, 2026-10-20: include, flagged
    genres = set(row["genres"].split("-")) - {"NA"}
    original = row["is_original"] == "True"
    if genres and not genres <= PDMX_GENRES:
        flags.append("genre")
    if not genres and not original:
        flags.append("untagged")
    if row["composer_name"] == "NA" and not original:
        flags.append("no-composer")
    names = " ".join(row[k] for k in ("composer_name", "artist_name") if row[k] != "NA")
    if names and BLOCKED_NAMES.search(names):
        flags.append("pop-name")
    title = " ".join(row[k] for k in ("title", "song_name", "subtitle") if row[k] != "NA")
    if BLOCKED_TITLES.search(title):
        flags.append("pop-title")
    if not original and ARRANGED.search(title):
        flags.append("arrangement")
    return flags


def pdmx_ok(row: dict) -> tuple[bool, str]:
    """Hard rejects: duplicates, Chinese music, length. Licence conflicts are flagged (pdmx_flags)."""
    if row["subset:deduplicated"] != "True":
        return False, "pdmx duplicate"
    if is_chinese([row.get(k, "") for k in ("title", "song_name", "subtitle", "composer_name", "artist_name")],
                  " ".join(row.get(k, "") for k in ("tags", "genres", "groups"))):
        return False, "chinese music (user rule)"
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
    """Transposition-invariant hash of the first bars' melody: rhythm + pitch relative to the tune's first note.

    Pitches are relative to the first note of the tune, not of each bar, so tunes
    whose bars share a shape but move to other degrees do not collide.
    """
    line = []
    for b in song["bars"][:bars]:
        for e in melody(b):
            top = max(e.pitches, key=lambda p: p.midi).midi if e.pitches else None
            line.append((e.dur, top))
        line.append("|")
    first = next((x[1] for x in line if x != "|" and x[1] is not None), 0)
    norm = [x if x == "|" else (x[0], None if x[1] is None else x[1] - first) for x in line]
    return hashlib.sha1(repr((song["time"], norm)).encode()).hexdigest()


def split_of(corpus: str, tune_id: str) -> str:
    """Deterministic 90/5/5 split by source tune, so variants never cross splits."""
    h = int(hashlib.sha1(f"{corpus}:{tune_id}".encode()).hexdigest(), 16) % 100
    return "train" if h < 90 else ("valid" if h < 95 else "test")


# --- Chinese music (user rule, 2026-10-20: "i just dont want chinese music") --------------
HAN = re.compile("[㐀-䶿一-鿿豈-﫿]")
KANA = re.compile("[぀-ヿ]")  # Japanese titles mix kanji with kana; Japanese music is allowed
CHINESE_TAGS = re.compile(r"\b(chinese\w*|china|c-?pop|mandopop|cantopop|mandarin|cantonese|guzheng|erhu|pipa|dizi|guqin|"
                          r"taiwan\w*|hong ?kong|xinjiang|uyghur|qing ?dynasty)\b", re.I)
CHINESE_WORDS = re.compile(r"\b(erhu|guzheng|pipa|dizi|guqin|c-?pop|mandopop|cantopop)\b", re.I)
CHINESE_NAMES = re.compile(r"\b(jay chou|teresa teng|michael wong|wu bai|xian xinghai|abing|tan dun|faye wong|eason chan|"
                           r"jj lin|g\.?e\.?m\.?|joker xue|hua chenyu|leslie cheung|jacky cheung|andy lau|mayday|"
                           r"david tao|jolin tsai|stefanie sun|wang leehom|lin junjie|zhou jielun|deng lijun)\b", re.I)


def _demojibake(text: str) -> str:
    """PDMX.csv holds some UTF-8 text decoded as Latin-1; undo that when it round-trips."""
    try:
        return text.encode("latin-1").decode("utf-8")
    except (UnicodeEncodeError, UnicodeDecodeError):
        return text


def is_chinese(texts: list[str], tags: str = "") -> bool:
    """Chinese music by metadata: Chinese tags, Han script without kana, instrument/genre words, artist names.

    Errs toward excluding (a Western piece tagged "china" is dropped too); generic
    "China"/"Chinese" in a title alone does not count (Tchaikovsky's Chinese Dance,
    the American hymn tune "China").
    """
    text = " ".join(_demojibake(t) for t in texts if t and t != "NA")
    if HAN.search(text) and not KANA.search(text):
        return True
    if CHINESE_WORDS.search(text) or CHINESE_NAMES.search(text):
        return True
    return bool(tags and CHINESE_TAGS.search(_demojibake(tags).replace("-", " ")))
