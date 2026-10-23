"""Converter edge cases from the PR #41 review (keys, accidentals, ties, chords, voices, parts)."""

from pathlib import Path

import music21 as m21
import pytest

from melody_model import convert
from melody_model.notation import Unsupported

FIXTURES = Path(__file__).parent / "fixtures"


def score(*parts, time="4/4", key=None):
    """parts: list of bars, each bar a list of music21 elements (or a Voice list)."""
    s = m21.stream.Score()
    for bars, clef in parts:
        p = m21.stream.Part()
        for i, bar in enumerate(bars):
            m = m21.stream.Measure(number=i + 1)
            if i == 0:
                m.append([clef, m21.meter.TimeSignature(time)])
                if key is not None:
                    m.append(key)
            if bar and isinstance(bar[0], m21.stream.Voice):
                for v in bar:
                    m.insert(0, v)
            else:
                m.append(bar)
            p.append(m)
        s.append(p)
    return s


def n(name, ql=1.0, tie=None, finger=None):
    x = m21.note.Note(name, quarterLength=ql)
    if tie:
        x.tie = m21.tie.Tie(tie)
    if finger:
        x.articulations.append(m21.articulations.Fingering(finger))
    return x


def via_xml(s, tmp_path):
    fp = tmp_path / "t.musicxml"
    s.write("musicxml", fp=str(fp))
    [song] = convert.convert_file(fp)
    return song


T = m21.clef.TrebleClef
B = m21.clef.BassClef


@pytest.mark.parametrize(
    "key,name",
    [
        (m21.key.Key("G"), "G"),
        (m21.key.Key("B-"), "Bb"),
        (m21.key.Key("D"), "D"),
        (m21.key.Key("a"), "Am"),
        (m21.key.Key("d"), "Dm"),
    ],
)
def test_keys_with_sharps_flats_and_minor(key, name, tmp_path):
    tonic = key.tonic.name
    s = score(([[n(tonic + "4", 4)]], T()), key=key)
    assert via_xml(s, tmp_path)["key"] == name


def test_accidental_persistence_and_natural(tmp_path):
    s = score(([[n("F#4"), n("F#4"), n("F4"), n("G4")]], T()), key=m21.key.Key("C"))
    assert via_xml(s, tmp_path)["bars"][0]["RH"] == "F#4:4 F#4:4 F4:4 G4:4"


def test_tie_inside_bar_is_merged(tmp_path):
    s = score(([[n("C4", 1, "start"), n("C4", 1, "stop"), n("D4", 2)]], T()), key=m21.key.Key("C"))
    assert via_xml(s, tmp_path)["bars"][0]["RH"] == "C4:2 D4:2"


def test_tie_chain_of_three_is_merged(tmp_path):
    s = score(
        ([[n("C4", 1, "start"), n("C4", 1, "continue"), n("C4", 1, "stop"), n("D4", 1)]], T()),
        key=m21.key.Key("C"),
    )
    assert via_xml(s, tmp_path)["bars"][0]["RH"] == "C4:2. D4:4"


def test_tie_across_barline_is_kept(tmp_path):
    s = score(
        ([[n("C4", 2), n("D4", 2, "start")], [n("D4", 2, "stop"), n("E4", 2)]], T()), key=m21.key.Key("C")
    )
    song = convert.convert_score(s)
    assert [b["RH"] for b in song["bars"]] == ["C4:2 D4:2 {tie}", "D4:2 E4:2"]
    assert (
        via_xml(convert.song_to_score(song), tmp_path)["bars"] == song["bars"]
    )  # MusicXML round trip keeps the tie


def test_tie_sum_without_single_duration_stays_tied():
    s = score(
        ([[n("C4", 1, "start"), n("C4", 0.25, "stop"), n("D4", 0.75), n("E4", 2)]], T()), key=m21.key.Key("C")
    )
    assert convert.convert_score(s)["bars"][0]["RH"] == "C4:4 {tie} C4:16 D4:8. E4:2"


def test_tie_to_a_different_pitch_is_rejected():
    s = score(([[n("C4", 2, "start"), n("D4", 2, "stop")]], T()), key=m21.key.Key("C"))
    with pytest.raises(Unsupported, match="different pitch"):
        convert.convert_score(s)


def test_dangling_tie_on_last_note_is_dropped():
    s = score(([[n("C4", 2), n("D4", 2, "start")]], T()), key=m21.key.Key("C"))
    assert convert.convert_score(s)["bars"][0]["RH"] == "C4:2 D4:2"


def test_key_signature_and_key_with_same_sharps_is_not_a_change():
    s = score(([[n("C4", 4)], [m21.key.Key("C"), n("D4", 4)]], T()), key=m21.key.KeySignature(0))
    assert convert.convert_score(s)["key"] in ("C", "Am")


def test_lenient_errors_are_unsupported(tmp_path):
    bad = tmp_path / "bad.musicxml"
    bad.write_text("<score-partwise", encoding="utf-8")
    _, errors = convert.convert_file_lenient(bad)
    assert errors and all(isinstance(e, Unsupported) for e in errors)


XML_CHORD = """<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="4.0"><part-list><score-part id="P1"><part-name>P</part-name></score-part></part-list>
<part id="P1"><measure number="1"><attributes><divisions>1</divisions><key><fifths>0</fifths><mode>major</mode></key>
<time><beats>4</beats><beat-type>4</beat-type></time><clef><sign>F</sign><line>4</line></clef></attributes>
<note><pitch><step>G</step><octave>3</octave></pitch><duration>4</duration><type>whole</type>
 <notations><technical><fingering>1</fingering></technical></notations></note>
<note><chord/><pitch><step>C</step><octave>3</octave></pitch><duration>4</duration><type>whole</type>
 <notations><technical><fingering>5</fingering></technical></notations></note>
<note><chord/><pitch><step>E</step><octave>3</octave></pitch><duration>4</duration><type>whole</type>
 <notations><technical><fingering>3</fingering></technical></notations></note>
</measure></part></score-partwise>
"""


def test_chord_fingering_is_never_misassigned(tmp_path):
    """Chord written G3, C3, E3 with fingers 1, 5, 3: music21 loses which finger is which, so none is kept."""
    fp = tmp_path / "chord.musicxml"
    fp.write_text(XML_CHORD, encoding="utf-8")
    [song] = convert.convert_file(fp)
    assert song["bars"][0]["LH"] == "C3E3G3:1"


def test_chord_level_fingering_with_wrong_count_is_dropped():
    c = m21.chord.Chord(["C3", "E3", "G3"], quarterLength=4)
    c.articulations.append(m21.articulations.Fingering(5))
    s = score(([[c]], B()), key=m21.key.Key("C"))
    assert convert.convert_score(s)["bars"][0]["LH"] == "C3E3G3:1"


def test_multi_voice_bar_reads_top_voice():
    low, high = m21.stream.Voice(), m21.stream.Voice()
    low.append([n("C4", 2), n("D4", 2)])  # voice 1
    high.append([n("E5", 2), n("F5", 2)])  # voice 2
    s = score(([[low, high]], T()), key=m21.key.Key("C"))
    bar = convert.convert_score(s)["bars"][0]
    assert bar["RH"] == "C4:2 D4:2"
    assert bar["RH2"] == "E5:2 F5:2"


def test_same_signature_mode_change_is_rejected():
    s = score(([[n("C4", 4)], [m21.key.Key("a"), n("A3", 4)]], T()), key=m21.key.Key("C"))
    with pytest.raises(Unsupported, match="key changes"):
        convert.convert_score(s)


def test_meter_change_is_rejected():
    s = score(
        (
            [
                [n("C4", 4)],
                [m21.meter.TimeSignature("3/4"), n("D4", 3)],
                [m21.meter.TimeSignature("4/4"), n("E4", 4)],
                [m21.meter.TimeSignature("6/4"), n("F4", 6)],
            ],
            T(),
        ),
        key=m21.key.Key("C"),
    )
    with pytest.raises(Unsupported, match="time"):
        convert.convert_score(s)


def test_hands_assigned_by_pitch_not_part_order():
    s = score(([[n("C3", 4)]], B()), ([[n("E5", 4)]], T()), key=m21.key.Key("C"))  # bass part first
    assert convert.convert_score(s)["bars"][0] == {"RH": "E5:1", "LH": "C3:1"}


def test_three_parts_rejected_unless_melody_only():
    s = score(([[n("E5", 4)]], T()), ([[n("C4", 4)]], T()), ([[n("C3", 4)]], B()), key=m21.key.Key("C"))
    with pytest.raises(Unsupported, match="3 parts"):
        convert.convert_score(s)
    assert convert.convert_score(s, melody_only=True)["bars"][0] == {"RH": "E5:1"}


def test_parse_error_becomes_unsupported(tmp_path):
    bad = tmp_path / "bad.musicxml"
    bad.write_text("<score-partwise><part id='P1'><measure", encoding="utf-8")
    songs, errors = convert.convert_file_lenient(bad)
    assert songs == [] and str(errors[0]).startswith("parse error")


def test_real_mutopia_midi():
    s = m21.converter.parse(str(FIXTURES / "mutopia-easter.mid"), quantizePost=True)
    song = convert.convert_score(s, melody_only=True)
    assert (song["time"], song["key"], len(song["bars"])) == ("2/4", "C", 32)
    assert song["bars"][0] == {"RH": "C4:4 E4:4"}


def test_real_mutopia_midi_unsupported_meter():
    s = m21.converter.parse(str(FIXTURES / "mutopia-old100-4-2.mid"), quantizePost=True)
    with pytest.raises(Unsupported, match="time 4/2"):
        convert.convert_score(s, melody_only=True)
