import json

import music21 as m21
import pytest

from melody_model import mikrokosmos as mk
from melody_model.notation import Unsupported


def score(time="4/4", sharps=None, tempo=None, voices=False, rh=("C5", "D5", "E5", "C5")):
    s = m21.stream.Score()
    for hand, notes in (("RH", rh), ("LH", ("C3", "D3", "E3", "C3"))):
        part = m21.stream.Part(id=hand)
        m = m21.stream.Measure(number=1)
        m.append(m21.meter.TimeSignature(time))
        if sharps is not None:
            m.append(m21.key.KeySignature(sharps))
        if tempo and hand == "RH":
            m.append(m21.tempo.MetronomeMark(number=tempo[0], referent=m21.note.Note(type=tempo[1])))
        if voices and hand == "RH":
            for top in (True, False):
                v = m21.stream.Voice()
                for n in notes:
                    v.append(m21.note.Note(n if top else n.replace("5", "4"), quarterLength=1))
                m.insert(0, v)
        else:
            for n in notes:
                m.append(
                    m21.note.Note(
                        n, quarterLength=m21.meter.TimeSignature(time).barDuration.quarterLength / 4
                    )
                )
        part.append(m)
        s.insert(0, part)
    return s


def test_written_key_never_invents_a_signature():
    assert mk.written_key(score()) in ("C", "Am")
    assert mk.written_key(score(sharps=2)) in ("D", "Bm")
    assert mk.written_key(score(sharps=-1)) in ("F", "Dm")


def test_bpm_counts_the_time_signature_beat():
    assert mk.bpm(score(tempo=(96, "quarter")), "4/4") == 96
    assert mk.bpm(score(time="2/2", tempo=(80, "half")), "2/2") == 80
    assert mk.bpm(score(time="2/2", tempo=(120, "quarter")), "2/2") == 60
    with pytest.raises(Unsupported):
        mk.bpm(score(), "4/4")


def test_two_voices_in_one_hand_are_accepted():
    s = mk.song(1, "T", score(tempo=(96, "quarter"), voices=True))
    assert s["bars"][0]["RH"] == "C5:4 D5:4 E5:4 C5:4"
    assert s["bars"][0]["RH2"] == "C4:4 D4:4 E4:4 C4:4"


def test_three_voices_in_one_hand_are_refused():
    s = score(tempo=(96, "quarter"))
    m = s.parts[0].getElementsByClass(m21.stream.Measure)[0]
    for _ in range(3):
        v = m21.stream.Voice()
        v.append(m21.note.Note("C4", quarterLength=4))
        m.insert(0, v)
    with pytest.raises(Unsupported, match="three or more voices"):
        mk.song(1, "T", s)


def test_song_carries_provenance_and_the_us_restriction():
    s = mk.song(7, "Dotted Notes", score(tempo=(112, "quarter")))
    assert s["id"] == "mikrokosmos-007"
    assert s["source_url"].endswith("/musicxml/7.xml")
    assert s["restricted_in"] == [{"region": "US", "until": "2036-01-01"}]
    assert s["bars"] == [{"RH": "C5:4 D5:4 E5:4 C5:4", "LH": "C3:4 D3:4 E3:4 C3:4"}]


def test_main_writes_songs_levels_and_a_chained_journey(tmp_path):
    data, out = tmp_path / "data", tmp_path / "content"
    (data / "musicxml").mkdir(parents=True)
    (data / "mikrokosmos_metadata.csv").write_text(
        'piece number,work\n1,"A, Mikrokosmos, Sz. 107"\n2,"B, Mikrokosmos, Sz. 107"\n3,"C, Mikrokosmos, Sz. 107"\n',
        encoding="utf-8",
    )
    for n in (1, 3):
        score(tempo=(100, "quarter")).write("musicxml", fp=str(data / "musicxml" / f"{n}.xml"))
    mk.main([str(data), str(out), "--pieces", "1-3"])
    journey = json.loads((out / "courses" / "mikrokosmos-1" / "journey.json").read_text(encoding="utf-8"))
    assert [n["id"] for n in journey["nodes"]] == ["piece-01", "piece-03"]
    assert journey["nodes"][0]["next"] == ["piece-03"] and journey["nodes"][1]["next"] == []
    assert (out / "songs" / "mikrokosmos-003.json").exists()
    level = json.loads(
        (out / "courses" / "mikrokosmos-1" / "levels" / "mk1-01.json").read_text(encoding="utf-8")
    )
    assert [st["type"] for st in level["stages"]] == ["wait", "wait", "play_along"]


def test_pieces_belong_to_bartoks_six_volumes():
    assert [mk.book_of(n) for n in (1, 36, 37, 66, 67, 96, 97, 121, 122, 139, 140, 153)] == [
        1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
    ]  # fmt: skip


def test_csv_accent_escapes_are_decoded():
    assert mk.unescape("Hommage " + chr(92) + "u00e0 J. S. B.") == "Hommage à J. S. B."
    assert mk.unescape("Chorale") == "Chorale"


def test_main_splits_pieces_into_one_course_per_book(tmp_path):
    data, out = tmp_path / "data", tmp_path / "content"
    (data / "musicxml").mkdir(parents=True)
    (data / "mikrokosmos_metadata.csv").write_text(
        'piece number,work\n36,"A, Mikrokosmos, Sz. 107"\n37,"B, Mikrokosmos, Sz. 107"\n',
        encoding="utf-8",
    )
    for n in (36, 37):
        score(tempo=(100, "quarter")).write("musicxml", fp=str(data / "musicxml" / f"{n}.xml"))
    mk.main([str(data), str(out), "--pieces", "36-37"])
    for book, n in ((1, 36), (2, 37)):
        journey = json.loads(
            (out / "courses" / f"mikrokosmos-{book}" / "journey.json").read_text(encoding="utf-8")
        )
        assert journey["course"] == f"mikrokosmos-{book}"
        assert journey["nodes"][0]["levels"] == [f"mk{book}-{n:02d}"]
        assert journey["nodes"][0]["title"] == f"str:node.mk{book}.{n:02d}"
        assert (out / "courses" / f"mikrokosmos-{book}" / "levels" / f"mk{book}-{n:02d}.json").exists()
