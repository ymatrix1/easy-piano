//! Dynamics and hairpin marks (`{dyn:"mf"}`, `{cresc}`, `{dim}`, `{end}`) and
//! their grading from MIDI note-on velocity.
//!
//! Reference: MuseScore `dom/dynamic.cpp` (`DYN_LIST` velocities) for the
//! classes, and `rendering/score/tlayout.cpp:layoutHairpinSegment` for the
//! hairpin span. The rendering side is `app/lib/ui/staff/dynamics_layout.dart`
//! and `song_marks_parser.dart`; keep the two in step.
//!
//! Grading is informational for now: it does not change the stars. Mic input
//! has no real velocity, so the session never feeds it here.

/// Velocity change (0-127) a hairpin must show between its first and second
/// half before it counts as passed.
pub const HAIRPIN_TREND: f64 = 8.0;

/// A dynamic text from `{dyn:"..."}`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Dynamic {
    Ppp,
    Pp,
    P,
    Mp,
    Mf,
    F,
    Ff,
    Fff,
    /// Rendered, not graded: a sudden or fp accent has no velocity band here.
    Fp,
    Sf,
    Sfz,
}

/// Graded dynamics with their MuseScore `DYN_LIST` velocity.
const GRADED: [(Dynamic, u8); 8] = [
    (Dynamic::Ppp, 16),
    (Dynamic::Pp, 33),
    (Dynamic::P, 49),
    (Dynamic::Mp, 64),
    (Dynamic::Mf, 80),
    (Dynamic::F, 96),
    (Dynamic::Ff, 112),
    (Dynamic::Fff, 126),
];

impl Dynamic {
    /// Parses the text inside `{dyn:"..."}`. Same set as the app renderer.
    pub fn parse(text: &str) -> Option<Dynamic> {
        Some(match text {
            "ppp" => Dynamic::Ppp,
            "pp" => Dynamic::Pp,
            "p" => Dynamic::P,
            "mp" => Dynamic::Mp,
            "mf" => Dynamic::Mf,
            "f" => Dynamic::F,
            "ff" => Dynamic::Ff,
            "fff" => Dynamic::Fff,
            "fp" => Dynamic::Fp,
            "sf" => Dynamic::Sf,
            "sfz" => Dynamic::Sfz,
            _ => return None,
        })
    }

    /// MuseScore velocity centre, or None when the mark is not graded.
    pub fn centre(self) -> Option<u8> {
        GRADED.iter().find(|(d, _)| *d == self).map(|(_, v)| *v)
    }

    /// The graded dynamic whose centre is nearest to `velocity` (ties go to
    /// the softer one). Every velocity maps to exactly one graded dynamic.
    pub fn classify(velocity: u8) -> Dynamic {
        let v = velocity as i32;
        GRADED
            .iter()
            .min_by_key(|(_, c)| (v - *c as i32).abs())
            .map(|(d, _)| *d)
            .unwrap_or(Dynamic::Mf)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum HairpinKind {
    Crescendo,
    Diminuendo,
}

/// One mark from a directive, before it is placed on the beat line.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Mark {
    Dyn(Dynamic),
    Open(HairpinKind),
    End,
}

impl Mark {
    /// Reads a directive (`name`, optional `arg`). `Ok(None)` for directives
    /// that are not dynamics; `Err` for a dynamics directive that is malformed.
    pub fn from_directive(name: &str, arg: Option<&str>) -> Result<Option<Mark>, String> {
        match name {
            "dyn" => {
                let text = arg.map(|a| a.trim_matches('"')).unwrap_or("");
                Dynamic::parse(text)
                    .map(|d| Some(Mark::Dyn(d)))
                    .ok_or_else(|| format!("`{{dyn:\"{text}\"}}`: unknown dynamic"))
            }
            "cresc" | "dim" | "end" if arg.is_some() => {
                Err(format!("`{{{name}}}` takes no argument"))
            }
            "cresc" => Ok(Some(Mark::Open(HairpinKind::Crescendo))),
            "dim" => Ok(Some(Mark::Open(HairpinKind::Diminuendo))),
            "end" => Ok(Some(Mark::End)),
            _ => Ok(None),
        }
    }
}

/// A mark placed on the beat line.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct TimedMark {
    pub beat: f64,
    pub mark: Mark,
}

/// A hairpin from `start` to `end` (song beats).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Span {
    pub start: f64,
    pub end: f64,
    pub kind: HairpinKind,
}

/// The score's dynamics and hairpins, positioned on the beat line.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Layout {
    pub dynamics: Vec<(f64, Dynamic)>,
    pub hairpins: Vec<Span>,
}

/// Places marks like the app does (`song_marks_parser.dart`, `_build`): a
/// dynamic closes an open hairpin, a new hairpin closes the previous one, and
/// `{end}` closes it. A hairpin still open at `end_beat` closes there. A
/// hairpin that would have zero length is dropped.
pub fn layout(marks: &[TimedMark], end_beat: f64) -> Layout {
    let mut sorted = marks.to_vec();
    sorted.sort_by(|a, b| a.beat.total_cmp(&b.beat));
    let mut out = Layout::default();
    let mut open: Option<(HairpinKind, f64)> = None;

    fn close(open: &mut Option<(HairpinKind, f64)>, at: f64, end_beat: f64, out: &mut Layout) {
        if let Some((kind, start)) = open.take() {
            let end = at.min(end_beat);
            if end > start {
                out.hairpins.push(Span { start, end, kind });
            }
        }
    }

    for m in &sorted {
        match m.mark {
            Mark::Dyn(d) => {
                close(&mut open, m.beat, end_beat, &mut out);
                out.dynamics.push((m.beat, d));
            }
            Mark::Open(kind) => {
                close(&mut open, m.beat, end_beat, &mut out);
                open = Some((kind, m.beat));
            }
            Mark::End => close(&mut open, m.beat, end_beat, &mut out),
        }
    }
    close(&mut open, end_beat, end_beat, &mut out);
    out
}

/// A matched note-on: where it belongs on the beat line and how hard it was
/// played.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Onset {
    pub beat: f64,
    pub velocity: u8,
}

/// Dynamics and hairpin counts for one performance.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Grade {
    pub dynamics_passed: u32,
    pub dynamics_total: u32,
    pub hairpins_passed: u32,
    pub hairpins_total: u32,
}

/// Grades a performance against the layout.
///
/// A dynamic covers the onsets from its beat up to the next dynamic (or the
/// end). It passes when at least half of those onsets classify as that
/// dynamic. A region with no onsets is not counted. Ungraded marks (`fp`,
/// `sf`, `sfz`) are not counted.
///
/// A hairpin covers the onsets inside its span. It needs at least two. The
/// mean velocity of the first half and the second half must move by
/// [HAIRPIN_TREND] in its direction (up for a crescendo, down for a
/// diminuendo).
pub fn grade(layout: &Layout, onsets: &[Onset], end_beat: f64) -> Grade {
    let mut g = Grade::default();
    let mut sorted = onsets.to_vec();
    sorted.sort_by(|a, b| a.beat.total_cmp(&b.beat));

    for (i, &(start, dyn_)) in layout.dynamics.iter().enumerate() {
        let Some(_) = dyn_.centre() else { continue };
        let end = layout
            .dynamics
            .get(i + 1)
            .map_or(end_beat, |&(next, _)| next);
        let region: Vec<&Onset> = sorted
            .iter()
            .filter(|o| o.beat >= start && o.beat < end)
            .collect();
        if region.is_empty() {
            continue;
        }
        g.dynamics_total += 1;
        let hits = region
            .iter()
            .filter(|o| Dynamic::classify(o.velocity) == dyn_)
            .count();
        if hits * 2 >= region.len() {
            g.dynamics_passed += 1;
        }
    }

    for span in &layout.hairpins {
        let inside: Vec<u8> = sorted
            .iter()
            .filter(|o| o.beat >= span.start && o.beat < span.end)
            .map(|o| o.velocity)
            .collect();
        if inside.len() < 2 {
            continue;
        }
        g.hairpins_total += 1;
        let half = inside.len() / 2;
        let mean = |v: &[u8]| v.iter().map(|&x| x as f64).sum::<f64>() / v.len() as f64;
        let first = mean(&inside[..half]);
        let second = mean(&inside[half..]);
        let ok = match span.kind {
            HairpinKind::Crescendo => second - first >= HAIRPIN_TREND,
            HairpinKind::Diminuendo => first - second >= HAIRPIN_TREND,
        };
        if ok {
            g.hairpins_passed += 1;
        }
    }
    g
}

#[cfg(test)]
mod tests {
    use super::*;

    fn m(beat: f64, mark: Mark) -> TimedMark {
        TimedMark { beat, mark }
    }

    #[test]
    fn dynamic_text_and_directives() {
        assert_eq!(Dynamic::parse("mf"), Some(Dynamic::Mf));
        assert_eq!(Dynamic::parse("pppp"), None);
        assert_eq!(
            Mark::from_directive("dyn", Some("\"p\"")),
            Ok(Some(Mark::Dyn(Dynamic::P)))
        );
        assert!(Mark::from_directive("dyn", Some("\"x\"")).is_err());
        assert!(Mark::from_directive("dyn", None).is_err());
        assert!(Mark::from_directive("cresc", Some("1")).is_err());
        assert_eq!(
            Mark::from_directive("dim", None),
            Ok(Some(Mark::Open(HairpinKind::Diminuendo)))
        );
        assert_eq!(Mark::from_directive("tie", None), Ok(None));
    }

    #[test]
    fn classify_is_nearest_centre() {
        assert_eq!(Dynamic::classify(49), Dynamic::P);
        assert_eq!(Dynamic::classify(60), Dynamic::Mp);
        assert_eq!(Dynamic::classify(75), Dynamic::Mf);
        assert_eq!(Dynamic::classify(127), Dynamic::Fff);
        assert_eq!(Dynamic::classify(1), Dynamic::Ppp);
    }

    #[test]
    fn layout_closes_hairpins_at_dynamics_and_end() {
        let marks = [
            m(0.0, Mark::Dyn(Dynamic::P)),
            m(1.0, Mark::Open(HairpinKind::Crescendo)),
            m(3.0, Mark::Dyn(Dynamic::F)),
            m(4.0, Mark::Open(HairpinKind::Diminuendo)),
        ];
        let l = layout(&marks, 8.0);
        assert_eq!(l.dynamics, vec![(0.0, Dynamic::P), (3.0, Dynamic::F)]);
        assert_eq!(
            l.hairpins,
            vec![
                Span {
                    start: 1.0,
                    end: 3.0,
                    kind: HairpinKind::Crescendo
                },
                Span {
                    start: 4.0,
                    end: 8.0,
                    kind: HairpinKind::Diminuendo
                },
            ]
        );
    }

    #[test]
    fn zero_length_hairpin_is_dropped() {
        let marks = [
            m(2.0, Mark::Open(HairpinKind::Crescendo)),
            m(2.0, Mark::End),
        ];
        assert!(layout(&marks, 4.0).hairpins.is_empty());
    }

    fn on(beat: f64, velocity: u8) -> Onset {
        Onset { beat, velocity }
    }

    #[test]
    fn dynamic_passes_when_most_onsets_match() {
        let l = Layout {
            dynamics: vec![(0.0, Dynamic::P), (4.0, Dynamic::F)],
            hairpins: vec![],
        };
        let onsets = [on(0.0, 50), on(1.0, 45), on(2.0, 100), on(4.0, 100)];
        let g = grade(&l, &onsets, 8.0);
        // p region: 2 of 3 soft -> passes; f region: 1 of 1 loud -> passes.
        assert_eq!((g.dynamics_passed, g.dynamics_total), (2, 2));
        let l2 = Layout {
            dynamics: vec![(0.0, Dynamic::P)],
            hairpins: vec![],
        };
        let g2 = grade(&l2, &[on(0.0, 100), on(1.0, 110), on(2.0, 50)], 4.0);
        assert_eq!((g2.dynamics_passed, g2.dynamics_total), (0, 1));
    }

    #[test]
    fn ungraded_and_empty_regions_are_not_counted() {
        let l = Layout {
            dynamics: vec![(0.0, Dynamic::Sf), (2.0, Dynamic::P)],
            hairpins: vec![],
        };
        let g = grade(&l, &[on(0.5, 120), on(3.0, 50)], 4.0);
        assert_eq!((g.dynamics_passed, g.dynamics_total), (1, 1));
    }

    #[test]
    fn hairpin_trend_is_graded_in_its_direction() {
        let cresc = Layout {
            dynamics: vec![],
            hairpins: vec![Span {
                start: 0.0,
                end: 4.0,
                kind: HairpinKind::Crescendo,
            }],
        };
        let soft_to_loud = [on(0.0, 40), on(1.0, 42), on(2.0, 70), on(3.0, 80)];
        let g = grade(&cresc, &soft_to_loud, 8.0);
        assert_eq!((g.hairpins_passed, g.hairpins_total), (1, 1));
        let loud_to_soft = [on(0.0, 80), on(1.0, 70), on(2.0, 42), on(3.0, 40)];
        let g = grade(&cresc, &loud_to_soft, 8.0);
        assert_eq!((g.hairpins_passed, g.hairpins_total), (0, 1));

        let dim = Layout {
            dynamics: vec![],
            hairpins: vec![Span {
                start: 0.0,
                end: 4.0,
                kind: HairpinKind::Diminuendo,
            }],
        };
        let g = grade(&dim, &loud_to_soft, 8.0);
        assert_eq!((g.hairpins_passed, g.hairpins_total), (1, 1));
    }

    #[test]
    fn hairpin_with_one_onset_is_not_counted() {
        let l = Layout {
            dynamics: vec![],
            hairpins: vec![Span {
                start: 0.0,
                end: 4.0,
                kind: HairpinKind::Crescendo,
            }],
        };
        let g = grade(&l, &[on(1.0, 60)], 8.0);
        assert_eq!(g.hairpins_total, 0);
    }
}
