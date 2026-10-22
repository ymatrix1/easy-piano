//! `content practice-pack <content_dir> [--out <file>]`: what the app's
//! practice mode needs per node (docs/specs/practice-mode.md, D28): the
//! cumulative taught set and skill spec for the rubric gate (`practice`), and
//! the generation spec and decoding masks for the melody model (`gen`),
//! mirroring tools/melody-model/melody_model/generate.py (build_prefix, Masker,
//! level_for).

use super::{load_songs, load_specs, taught_walk, Lint};
use easy_piano_core::pitch::pitch_name;
use easy_piano_core::rubric::{NodeSpec, PracticeNode, TaughtSet};
use serde_json::{json, Value};
use std::path::Path;

/// Order of duration labels in the model vocabulary (melody.js DURATIONS).
const DURATIONS: [&str; 13] = [
    "1", "1.", "2", "2.", "2..", "4", "4.", "4..", "8", "8.", "16", "16.", "32",
];

/// Length of a duration label in quarter notes (`4.` = 1.5).
fn quarters(label: &str) -> Option<f64> {
    let base: f64 = label.trim_end_matches('.').parse().ok()?;
    let dots = label.len() - label.trim_end_matches('.').len();
    let (mut len, mut add) = (4.0 / base, 4.0 / base);
    for _ in 0..dots {
        add /= 2.0;
        len += add;
    }
    Some(len)
}

/// generate.py `level_for`: the difficulty level the taught set allows.
pub fn level_for(t: &TaughtSet) -> u8 {
    let mut score = 0;
    for ps in t.pitches.values() {
        let span = ps
            .iter()
            .max()
            .zip(ps.iter().min())
            .map_or(0, |(a, b)| a - b);
        score = score.max(if span <= 7 {
            0
        } else if span <= 12 {
            1
        } else if span <= 19 {
            2
        } else {
            3
        });
    }
    let shortest = t
        .durations
        .iter()
        .filter_map(|d| quarters(d))
        .fold(f64::INFINITY, f64::min);
    score += if shortest >= 1.0 {
        0
    } else if shortest >= 0.5 {
        1
    } else if shortest >= 0.25 {
        2
    } else {
        3
    };
    score += match t.accidentals.len() {
        0 => 0,
        1 | 2 => 1,
        _ => 2,
    };
    score += u8::from(t.pitches.len() == 2);
    score += u8::from(t.polyphony.values().copied().max().unwrap_or(0) > 1);
    match score {
        0 | 1 => 1,
        2 | 3 => 2,
        4..=6 => 3,
        7..=9 => 4,
        _ => 5,
    }
}

/// Generation spec for one node, or why practice is unavailable there.
pub fn gen_spec(course: &str, t: &TaughtSet, s: &NodeSpec) -> Result<Value, String> {
    let hands: Vec<&str> = match s.hands.as_str() {
        "both" => vec!["RH", "LH"],
        h => vec![h],
    };
    for h in &hands {
        if t.pitches.get(*h).is_none_or(|p| p.is_empty()) {
            return Err(format!("no {h} pitches taught yet"));
        }
    }
    let all: Vec<u8> = hands
        .iter()
        .flat_map(|h| t.pitches[*h].iter().copied())
        .collect();
    let (lo, hi) = (
        *all.iter().min().unwrap_or(&60),
        *all.iter().max().unwrap_or(&60),
    );
    let durs: Vec<&str> = DURATIONS
        .iter()
        .copied()
        .filter(|d| t.durations.contains(*d))
        .collect();
    if durs.is_empty() {
        return Err("no model durations taught yet".into());
    }
    let rest_durs: Vec<&str> = if t.rests {
        DURATIONS
            .iter()
            .copied()
            .filter(|d| t.rest_durations.contains(*d))
            .collect()
    } else {
        vec![]
    };
    let names = |h: &str| {
        t.pitches[h]
            .iter()
            .map(|&p| pitch_name(p))
            .collect::<Vec<_>>()
    };
    Ok(json!({
        "time": s.time,
        "key": "C",
        "bars": s.bars[1],
        "bpm": ((s.bpm[0] + s.bpm[1]) / 2.0).round(),
        "range_lo": pitch_name(lo),
        "range_hi": pitch_name(hi),
        "durs": durs,
        "hands": match s.hands.as_str() { "both" => "BOTH", h => h },
        "course": course,
        "patterns": s.required,
        "level": level_for(t),
        "source": "own",
        "mask": {
            "pitches": hands.iter().map(|h| (h.to_string(), json!(names(h)))).collect::<serde_json::Map<_, _>>(),
            "max_leap": t.max_interval,
            "poly": hands.iter().map(|h| (h.to_string(), json!(t.polyphony.get(*h).copied().unwrap_or(1).max(1)))).collect::<serde_json::Map<_, _>>(),
            "rest_durs": rest_durs,
        },
    }))
}

pub fn pack(root: &Path) -> (Value, Lint) {
    let mut lint = Lint::default();
    let (songs, _) = load_songs(root);
    let walk = taught_walk(&mut lint, root, &songs);
    let specs = load_specs(&mut lint, root, &walk);
    let nodes: Vec<Value> = walk
        .iter()
        .filter_map(|w| {
            let spec = specs.get(&format!("{}/{}", w.course, w.node))?;
            let mut v = json!({
                "course": w.course,
                "node": w.node,
                "practice": PracticeNode { taught: w.taught.clone(), spec: spec.clone() },
            });
            match gen_spec(&w.course, &w.taught, spec) {
                Ok(g) => v["gen"] = g,
                Err(e) => v["unavailable"] = json!(e),
            }
            Some(v)
        })
        .collect();
    (json!({ "version": 1, "nodes": nodes }), lint)
}

#[cfg(test)]
mod tests {
    use super::*;
    use easy_piano_core::rubric::check_generated;

    #[test]
    fn pack_has_a_rubric_node_and_gen_spec_for_every_spec() {
        let content = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../content");
        let (p, lint) = pack(&content);
        assert!(lint.errors.is_empty(), "{:?}", lint.errors);
        let nodes = p["nodes"].as_array().unwrap();
        assert!(nodes.len() > 10);
        let n = nodes
            .iter()
            .find(|n| n["course"] == "piano-basics" && n["node"] == "f-and-g")
            .unwrap();
        let g = &n["gen"];
        assert_eq!(
            g["mask"]["pitches"]["RH"],
            json!(["C4", "D4", "E4", "F4", "G4"])
        );
        assert_eq!(
            (g["range_lo"].as_str(), g["range_hi"].as_str()),
            (Some("C4"), Some("G4"))
        );
        assert_eq!(g["hands"], "RH");
        // The rubric node round-trips into the bridge's check: a taught tune passes, a course song is refused.
        let node = n["practice"].to_string();
        let song = json!({"id":"g","title":"G","composer":"m","arranger":"m","source":"generated",
            "generator":{"method":"melody-model"},"license":"CC0-1.0","composition_license":"CC0-1.0",
            "bpm": g["bpm"], "time": g["time"], "key":"C",
            "bars": vec![json!({"RH":"C4:4 D4:4 E4:4 D4:4"}); g["bars"].as_u64().unwrap() as usize]});
        let errs = check_generated(&song.to_string(), &node);
        assert!(
            errs.iter().all(|e| e.contains("missing required pattern")),
            "{errs:?}"
        );
    }

    #[test]
    fn levels_and_quarters() {
        assert_eq!(quarters("4."), Some(1.5));
        assert_eq!(quarters("2.."), Some(3.5));
        let mut t = TaughtSet::default();
        t.pitches.insert("RH".into(), [60, 62, 64].into());
        t.durations.insert("4".into());
        assert_eq!(level_for(&t), 1);
        t.durations.insert("16".into());
        t.pitches.insert("LH".into(), [48, 67].into());
        assert_eq!(level_for(&t), 3);
    }
}
