"""Style labels per tune, from corpus and metadata (genres, tags, groups, titles).

A small fixed set (tokenizer.STYLES), so free-text tags never reach the vocab.
A tune can have several styles. Training drops them at random so the model also
runs unconditioned; generation picks the styles the app allows.
"""

from __future__ import annotations

import re

from .filters import is_chinese

# PDMX `genres` values -> styles
PDMX_GENRE = {
    "classical": "classical",
    "folk": "folk",
    "religiousmusic": "religious",
    "worldmusic": "world",
    "pop": "pop",
    "rock": "rock",
    "metal": "rock",
    "soundtrack": "soundtrack",
    "jazz": "jazz",
    "blues": "jazz",
    "electronic": "electronic",
    "rbfunksoul": "pop",
    "hiphop": "pop",
    "country": "folk",
    "disco": "pop",
    "reggaeska": "pop",
    "darkwave": "electronic",
    "newage": "electronic",
}
# keywords in tags/groups/title -> style (checked in order; a tune can match several)
KEYWORDS = [
    (
        "game",
        r"video ?games?|videogame|game ?music|nintendo|zelda|mario|pok[eé]mon|undertale|deltarune|minecraft|"
        r"kirby|sonic|final ?fantasy|touhou|genshin|chiptune|8 ?bit|fnaf|celeste|terraria|hollow ?knight|"
        r"kingdom ?hearts|metroid|castlevania|megaman|mega man|halo|tetris|smash ?bros|persona|nier",
    ),
    (
        "soundtrack",
        r"soundtrack|\bost\b|film|movie|cinema|anime|disney|pixar|ghibli|musical|broadway|theme song|tv ?theme",
    ),
    ("children", r"nursery|children'?s?|kids|lullaby|kinderlied"),
    ("religious", r"hymn|hymnal|gospel|psalm|chorale|carol|sacred|liturgical|worship|church"),
    ("folk", r"\bfolk\b|traditional|\btrad\b|jig|reel|hornpipe|fiddle|ceilidh|celtic|irish|scottish|shanty"),
    ("jazz", r"\bjazz\b|swing|blues|ragtime|bossa"),
    ("pop", r"\bpop\b|\bk-?pop\b|j-?pop|\bcover\b"),
    ("rock", r"\brock\b|\bmetal\b|punk|grunge"),
    (
        "classical",
        r"sonata|concerto|symphony|baroque|minuet|etude|nocturne|prelude|fugue|waltz|mazurka|madrigal|motet",
    ),
]
_KW = [(style, re.compile(pat, re.I)) for style, pat in KEYWORDS]
MUTOPIA_STYLE = {
    "Folk": "folk",
    "Song": "classical",
    "Hymn": "religious",
    "Children": "children",
    "Traditional": "folk",
}


def styles_for(corpus: str, meta: dict) -> list[str]:
    out: set[str] = set()
    if corpus == "nottingham":
        out.add("folk")
    elif corpus == "own":
        out.add("children")
    elif corpus == "mutopia" and meta.get("style") in MUTOPIA_STYLE:
        out.add(MUTOPIA_STYLE[meta["style"]])
    for g in (meta.get("genres") or "").split("-"):
        if g in PDMX_GENRE:
            out.add(PDMX_GENRE[g])
    text = " ".join(str(meta.get(k) or "") for k in ("tags", "groups", "title")).replace("-", " ")
    for style, rx in _KW:
        if rx.search(text):
            out.add(style)
    if is_chinese(
        [meta.get(k) or "" for k in ("title", "composer", "arranger")],
        " ".join(str(meta.get(k) or "") for k in ("tags", "genres", "groups")),
    ):
        out.add("chinese")
    for s in meta.get("styles", []):  # local datasets may state styles
        out.add(s)
    return sorted(out)
