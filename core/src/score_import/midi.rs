//! Standard MIDI files, format 0 and 1, with metrical (PPQ) timing.
//!
//! Hands: with two or more tracks that contain notes, the first such track is the
//! right hand and the second the left; further tracks go by average pitch. With a
//! single note track, each note is split at middle C (MIDI 60). Channel 10 (drums)
//! is ignored. Time and key signatures and tempo come from meta events in any track.

use super::{build_measures, sort_notes, Change, Clef, Hand, ImportedNote, ImportedScore};
use std::collections::HashMap;

/// A note span in ticks, from a matched note-on / note-off pair.
struct Span {
    start: u64,
    dur: u64,
    pitch: u8,
    channel: u8,
}

#[derive(Default)]
struct TrackData {
    name: Option<String>,
    spans: Vec<Span>,
    tempos: Vec<(u64, f64)>,
    times: Vec<(u64, (u32, u32))>,
    keys: Vec<(u64, i8)>,
}

fn at(data: &[u8], i: usize) -> Result<u8, String> {
    data.get(i)
        .copied()
        .ok_or_else(|| "midi: unexpected end of data".to_string())
}

fn slice(data: &[u8], start: usize, len: usize) -> Result<&[u8], String> {
    data.get(start..start + len)
        .ok_or_else(|| "midi: unexpected end of data".to_string())
}

fn be_u32(data: &[u8], i: usize) -> Result<u32, String> {
    let s = slice(data, i, 4)?;
    Ok(u32::from_be_bytes([s[0], s[1], s[2], s[3]]))
}

/// Variable-length quantity: returns (value, next index).
fn varlen(data: &[u8], mut i: usize) -> Result<(u64, usize), String> {
    let mut value = 0u64;
    for _ in 0..4 {
        let b = at(data, i)?;
        i += 1;
        value = (value << 7) | u64::from(b & 0x7f);
        if b & 0x80 == 0 {
            return Ok((value, i));
        }
    }
    Err("midi: variable-length value too long".into())
}

fn parse_track(body: &[u8]) -> Result<TrackData, String> {
    let mut t = TrackData::default();
    let mut p = 0usize;
    let mut tick = 0u64;
    let mut running: u8 = 0;
    let mut open: HashMap<(u8, u8), Vec<u64>> = HashMap::new();

    while p < body.len() {
        let (delta, next) = varlen(body, p)?;
        p = next;
        tick += delta;

        let mut status = at(body, p)?;
        if status & 0x80 != 0 {
            p += 1;
            if status < 0xf0 {
                running = status;
            }
        } else {
            if running == 0 {
                return Err("midi: data byte without running status".into());
            }
            status = running;
        }

        match status {
            0xff => {
                let kind = at(body, p)?;
                let (len, next) = varlen(body, p + 1)?;
                let len = len as usize;
                let data = slice(body, next, len)?;
                p = next + len;
                match kind {
                    0x03 if t.name.is_none() => {
                        t.name = Some(String::from_utf8_lossy(data).trim().to_string());
                    }
                    0x51 if len == 3 => {
                        let us = (u32::from(data[0]) << 16)
                            | (u32::from(data[1]) << 8)
                            | u32::from(data[2]);
                        if us > 0 {
                            t.tempos.push((tick, 60_000_000.0 / f64::from(us)));
                        }
                    }
                    0x58 if len >= 2 && data[1] <= 6 => {
                        t.times.push((tick, (u32::from(data[0]), 1u32 << data[1])));
                    }
                    0x59 if len >= 2 => {
                        t.keys.push((tick, data[0] as i8));
                    }
                    0x2f => break,
                    _ => {}
                }
            }
            0xf0 | 0xf7 => {
                let (len, next) = varlen(body, p)?;
                p = next + len as usize;
                running = 0;
            }
            _ => {
                let channel = status & 0x0f;
                match status & 0xf0 {
                    0x80 => {
                        let pitch = at(body, p)?;
                        p += 2;
                        close_note(&mut t, &mut open, channel, pitch, tick);
                    }
                    0x90 => {
                        let pitch = at(body, p)?;
                        let vel = at(body, p + 1)?;
                        p += 2;
                        if vel == 0 {
                            close_note(&mut t, &mut open, channel, pitch, tick);
                        } else {
                            open.entry((channel, pitch)).or_default().push(tick);
                        }
                    }
                    0xc0 | 0xd0 => p += 1,
                    _ => p += 2,
                }
            }
        }
    }
    Ok(t)
}

fn close_note(
    t: &mut TrackData,
    open: &mut HashMap<(u8, u8), Vec<u64>>,
    channel: u8,
    pitch: u8,
    tick: u64,
) {
    if let Some(stack) = open.get_mut(&(channel, pitch)) {
        if !stack.is_empty() {
            let start = stack.remove(0);
            t.spans.push(Span {
                start,
                dur: tick.saturating_sub(start),
                pitch,
                channel,
            });
        }
    }
}

/// Parses a standard MIDI file.
pub fn parse(data: &[u8]) -> Result<ImportedScore, String> {
    if slice(data, 0, 4)? != b"MThd" {
        return Err("midi: missing MThd header".into());
    }
    let header_len = be_u32(data, 4)? as usize;
    let header = slice(data, 8, header_len)?;
    if header.len() < 6 {
        return Err("midi: short header".into());
    }
    let division = u16::from_be_bytes([header[4], header[5]]);
    if division & 0x8000 != 0 {
        return Err("midi: SMPTE time division is not supported".into());
    }
    let ppq = f64::from(division);
    if ppq == 0.0 {
        return Err("midi: zero ticks per quarter note".into());
    }

    let mut tracks = Vec::new();
    let mut pos = 8 + header_len;
    while pos + 8 <= data.len() {
        let id = slice(data, pos, 4)?;
        let len = be_u32(data, pos + 4)? as usize;
        let body = slice(data, pos + 8, len)?;
        if id == b"MTrk" {
            tracks.push(parse_track(body)?);
        }
        pos += 8 + len;
    }

    // Tracks that play notes, in file order; drums (channel 10) excluded.
    let note_tracks: Vec<usize> = tracks
        .iter()
        .enumerate()
        .filter(|(_, t)| t.spans.iter().any(|s| s.channel != 9))
        .map(|(i, _)| i)
        .collect();

    let mut notes = Vec::new();
    for (rank, &ti) in note_tracks.iter().enumerate() {
        let spans: Vec<&Span> = tracks[ti].spans.iter().filter(|s| s.channel != 9).collect();
        let avg = spans.iter().map(|s| f64::from(s.pitch)).sum::<f64>() / spans.len() as f64;
        for s in spans {
            let hand = if note_tracks.len() == 1 {
                if s.pitch >= 60 {
                    Hand::Right
                } else {
                    Hand::Left
                }
            } else {
                match rank {
                    0 => Hand::Right,
                    1 => Hand::Left,
                    _ if avg >= 60.0 => Hand::Right,
                    _ => Hand::Left,
                }
            };
            notes.push(ImportedNote {
                midi: s.pitch,
                start: s.start as f64 / ppq,
                beats: s.dur as f64 / ppq,
                hand,
            });
        }
    }
    sort_notes(&mut notes);

    let mut tempos: Vec<(u64, f64)> = tracks.iter().flat_map(|t| t.tempos.clone()).collect();
    tempos.sort_by_key(|(tick, _)| *tick);
    let tempo_bpm = tempos.first().map(|(_, bpm)| *bpm);

    // Time and key changes, merged across tracks, as bar-grid changes in beats.
    let mut time_events: Vec<(u64, (u32, u32))> =
        tracks.iter().flat_map(|t| t.times.clone()).collect();
    let mut key_events: Vec<(u64, i8)> = tracks.iter().flat_map(|t| t.keys.clone()).collect();
    time_events.sort_by_key(|(tick, _)| *tick);
    key_events.sort_by_key(|(tick, _)| *tick);

    let mut time = (4u32, 4u32);
    let mut key = 0i8;
    let mut changes = vec![Change {
        start: 0.0,
        time,
        key_fifths: key,
    }];
    let mut ticks: Vec<u64> = time_events
        .iter()
        .map(|(t, _)| *t)
        .chain(key_events.iter().map(|(t, _)| *t))
        .collect();
    ticks.sort_unstable();
    ticks.dedup();
    for tick in ticks {
        if let Some((_, t)) = time_events.iter().rev().find(|(t, _)| *t <= tick) {
            time = *t;
        }
        if let Some((_, k)) = key_events.iter().rev().find(|(t, _)| *t <= tick) {
            key = *k;
        }
        changes.push(Change {
            start: tick as f64 / ppq,
            time,
            key_fifths: key,
        });
    }

    let end = notes
        .iter()
        .map(|n| n.start + n.beats)
        .fold(0.0f64, f64::max);
    let measures = build_measures(&changes, end);

    let title = tracks
        .first()
        .and_then(|t| t.name.clone())
        .unwrap_or_default();

    Ok(ImportedScore {
        title,
        composer: String::new(),
        tempo_bpm,
        right_clef: Clef::Treble,
        left_clef: Clef::Bass,
        measures,
        notes,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn vlq(mut v: u32) -> Vec<u8> {
        let mut out = vec![(v & 0x7f) as u8];
        v >>= 7;
        while v > 0 {
            out.insert(0, ((v & 0x7f) as u8) | 0x80);
            v >>= 7;
        }
        out
    }

    /// Track chunk from (delta, event bytes) pairs, ending with end-of-track.
    fn track(events: &[(u32, Vec<u8>)]) -> Vec<u8> {
        let mut body = Vec::new();
        for (delta, ev) in events {
            body.extend(vlq(*delta));
            body.extend(ev);
        }
        body.extend([0x00, 0xff, 0x2f, 0x00]);
        let mut out = b"MTrk".to_vec();
        out.extend((body.len() as u32).to_be_bytes());
        out.extend(body);
        out
    }

    fn smf(format: u16, ppq: u16, tracks: &[Vec<u8>]) -> Vec<u8> {
        let mut out = b"MThd".to_vec();
        out.extend(6u32.to_be_bytes());
        out.extend(format.to_be_bytes());
        out.extend((tracks.len() as u16).to_be_bytes());
        out.extend(ppq.to_be_bytes());
        for t in tracks {
            out.extend(t);
        }
        out
    }

    fn on(ch: u8, pitch: u8) -> Vec<u8> {
        vec![0x90 | ch, pitch, 80]
    }

    fn off(ch: u8, pitch: u8) -> Vec<u8> {
        vec![0x80 | ch, pitch, 0]
    }

    fn meta(kind: u8, data: &[u8]) -> Vec<u8> {
        let mut v = vec![0xff, kind, data.len() as u8];
        v.extend(data);
        v
    }

    #[test]
    fn single_track_splits_at_middle_c() {
        // ppq 480: C4 quarter, then C3 quarter (both on channel 0).
        let t = track(&[
            (0, on(0, 60)),
            (480, off(0, 60)),
            (0, on(0, 48)),
            (480, off(0, 48)),
        ]);
        let s = parse(&smf(0, 480, &[t])).unwrap();
        assert_eq!(s.notes.len(), 2);
        assert_eq!(s.notes[0].midi, 60);
        assert_eq!(s.notes[0].hand, Hand::Right);
        assert_eq!(s.notes[1].midi, 48);
        assert_eq!(s.notes[1].hand, Hand::Left);
        assert_eq!(s.notes[1].start, 1.0);
        assert_eq!(s.notes[1].beats, 1.0);
    }

    #[test]
    fn two_tracks_map_to_hands() {
        let rh = track(&[(0, on(0, 72)), (960, off(0, 72))]);
        let lh = track(&[(0, on(1, 40)), (960, off(1, 40))]);
        let s = parse(&smf(1, 480, &[rh, lh])).unwrap();
        let hands: Vec<(u8, Hand)> = s.notes.iter().map(|n| (n.midi, n.hand)).collect();
        assert_eq!(hands, vec![(40, Hand::Left), (72, Hand::Right)]);
        assert_eq!(s.notes[1].beats, 2.0);
    }

    #[test]
    fn reads_tempo_time_and_key_into_measures() {
        // 90 bpm = 666667 us per quarter; 3/4; key G (one sharp).
        let t = track(&[
            (0, meta(0x51, &[0x0a, 0x2c, 0x2b])),
            (0, meta(0x58, &[3, 2, 24, 8])),
            (0, meta(0x59, &[1, 0])),
            (0, on(0, 67)),
            (1440, off(0, 67)),
        ]);
        let s = parse(&smf(0, 480, &[t])).unwrap();
        assert!((s.tempo_bpm.unwrap() - 90.0).abs() < 0.01);
        assert_eq!(s.measures.len(), 1);
        assert_eq!(s.measures[0].time, (3, 4));
        assert_eq!(s.measures[0].key_fifths, 1);
        assert_eq!(s.measures[0].beats, 3.0);
    }

    #[test]
    fn running_status_and_note_on_zero_velocity() {
        // Second note uses running status (0x90 omitted) and velocity 0 as note-off.
        let body_events: Vec<(u32, Vec<u8>)> = vec![
            (0, vec![0x90, 60, 80]),
            (480, vec![60, 0]), // running status note-on, vel 0 => off
            (0, vec![62, 80]),  // running status note-on
            (480, vec![62, 0]),
        ];
        let s = parse(&smf(0, 480, &[track(&body_events)])).unwrap();
        assert_eq!(
            s.notes.iter().map(|n| n.midi).collect::<Vec<_>>(),
            vec![60, 62]
        );
        assert_eq!(s.notes[1].start, 1.0);
    }

    #[test]
    fn rejects_bad_header() {
        assert!(parse(b"RIFF0000").is_err());
    }
}
