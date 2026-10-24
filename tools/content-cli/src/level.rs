//! `content level <content_dir> [--node <course/node>] [--course] [--jsonl <file>] [song.json ...]`:
//! song difficulty (docs/specs/difficulty.md). Prints JSON.
//! - song files: one full report each (level, node_fit, skills, hardest bars,
//!   reasons; with `--node`, what exceeds that node).
//! - `--course`: every course song in learning order with its node, the node's
//!   expected level and its skills (input of `tools/difficulty/calibrate.py`).
//! - `--jsonl <file>`: one compact line per tune of a JSON-lines file whose rows
//!   carry `bars`, `time`, `key` (and optionally `bpm`); missing song metadata is
//!   filled in, so melody-model datasets can be scored.

use crate::{load_songs, taught_walk, Lint, NodeTaught};
use easy_piano_core::difficulty::{evaluate, exceeds, features, node_fit, skills, Model, Skills};
use easy_piano_core::rubric::TaughtSet;
use easy_piano_core::song::Song;
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::fs;
use std::path::Path;

/// A course song at the node where it first appears.
pub struct CourseSong {
    pub id: String,
    pub node: String,
    pub index: usize,
    /// Prerequisite depth + node fraction (see `NodeTaught::stage`).
    pub stage: f64,
    pub expected: f64,
    pub skills: Skills,
    pub level_score: f64,
    pub level: u8,
}

/// Course songs (not generated) in learning order, each at its first node, plus
/// each node's skill envelope (most of each skill seen up to that node).
/// Nodes off the ramp (Methods courses) add no songs; their envelope is the last one.
pub fn course_songs(
    walk: &[NodeTaught],
    songs: &BTreeMap<String, Song>,
    model: &Model,
) -> (Vec<CourseSong>, Vec<Skills>) {
    // Expected level ramps with the learning stage (prerequisite depth), so
    // parallel tracks after the same course expect the same level.
    let top = walk
        .iter()
        .filter(|w| w.on_ramp)
        .map(|w| w.stage)
        .fold(0.0, f64::max)
        .max(1.0);
    let [lo, hi] = model.course_levels;
    let (mut out, mut envs) = (Vec::<CourseSong>::new(), Vec::new());
    let mut env: Skills = [0.0; 8];
    for (i, w) in walk.iter().enumerate() {
        if !w.on_ramp {
            envs.push(env);
            continue;
        }
        for s in w
            .songs
            .iter()
            .filter_map(|id| songs.get(id))
            .filter(|s| s.source != "generated")
        {
            if out.iter().any(|c| c.id == s.id) {
                continue;
            }
            let sk = skills(&features(s));
            env.iter_mut().zip(&sk).for_each(|(e, x)| *e = (*e).max(*x));
            let score = model.level_score(model.z(&sk));
            out.push(CourseSong {
                id: s.id.clone(),
                node: format!("{}/{}", w.course, w.node),
                index: i,
                stage: w.stage,
                expected: lo + (hi - lo) * w.stage / top,
                skills: sk,
                level_score: score,
                level: model.level(&sk),
            });
        }
        envs.push(env);
    }
    (out, envs)
}

/// Song metadata a tune row may lack, so `Song` deserializes.
fn fill_song_fields(v: &mut Value) {
    let Some(o) = v.as_object_mut() else { return };
    for (k, d) in [
        ("id", json!("tune")),
        ("title", json!("?")),
        ("composer", json!("?")),
        ("arranger", json!("?")),
        ("source", json!("dataset")),
        ("license", json!("?")),
        ("composition_license", json!("?")),
        ("bpm", json!(100)),
        ("time", json!("4/4")),
        ("key", json!("C")),
    ] {
        if o.get(k).is_none_or(Value::is_null) {
            o.insert(k.into(), d);
        }
    }
    // Rows from other pipelines may carry fields `Song` would not know; drop them.
    for k in ["generator", "spec_node"] {
        o.remove(k);
    }
}

/// Validation errors about the music. License and provenance rules are left
/// out: dataset rows are scored, never published, and keep their own license
/// values, which this command does not verify (`license_checked: false`).
fn music_errors(s: &Song) -> Vec<String> {
    const NOT_MUSIC: [&str; 6] = [
        "license",
        "composition_license",
        "source_url",
        "`generator`",
        "generated songs",
        "generator.",
    ];
    s.validate()
        .into_iter()
        .filter(|e| !NOT_MUSIC.iter().any(|p| e.starts_with(p)))
        .collect()
}

fn round3(x: f64) -> f64 {
    (x * 1000.0).round() / 1000.0
}

pub fn run(args: &[String]) -> i32 {
    let Some(dir) = args.first() else {
        eprintln!("usage: content level <content_dir> [--node <course/node>] [--course] [--jsonl <file>] [song.json ...]");
        return 2;
    };
    let root = Path::new(dir);
    let model = Model::builtin();
    let (mut node, mut course, mut jsonl, mut files) = (None, false, None, Vec::new());
    let mut it = args[1..].iter();
    while let Some(a) = it.next() {
        match a.as_str() {
            "--node" => node = it.next().cloned(),
            "--course" => course = true,
            "--jsonl" => jsonl = it.next().cloned(),
            f => files.push(f.to_string()),
        }
    }
    if let Some(path) = jsonl {
        let Ok(text) = fs::read_to_string(&path) else {
            eprintln!("error: cannot read {path}");
            return 1;
        };
        for line in text.lines().filter(|l| !l.trim().is_empty()) {
            let mut v: Value = serde_json::from_str(line).unwrap_or(Value::Null);
            let id = v.get("id").cloned().unwrap_or(Value::Null);
            fill_song_fields(&mut v);
            let row = match serde_json::from_value::<Song>(v).map_err(|e| e.to_string()) {
                Ok(s) if music_errors(&s).is_empty() => {
                    let sk = skills(&features(&s));
                    json!({"id": id, "skills": sk.map(round3), "level_score": round3(model.level_score(model.z(&sk))), "level": model.level(&sk),
                        "license": s.license, "license_checked": false})
                }
                Ok(s) => json!({"id": id, "error": music_errors(&s).join("; ")}),
                Err(e) => json!({"id": id, "error": e}),
            };
            println!("{row}");
        }
        return 0;
    }
    let mut lint = Lint::default();
    let (songs, _) = load_songs(root);
    let walk = taught_walk(&mut lint, root, &songs);
    let (course_list, envs) = course_songs(&walk, &songs, &model);
    if course {
        let rows: Vec<Value> = course_list
            .iter()
            .map(|c| json!({"id": c.id, "node": c.node, "index": c.index, "stage": round3(c.stage), "expected": round3(c.expected), "skills": c.skills.map(round3), "level_score": round3(c.level_score), "level": c.level}))
            .collect();
        println!(
            "{}",
            serde_json::to_string_pretty(&json!({"nodes": walk.len(), "songs": rows}))
                .unwrap_or_default()
        );
        return 0;
    }
    let nodes: Vec<(String, TaughtSet)> = walk
        .iter()
        .map(|w| (format!("{}/{}", w.course, w.node), w.taught.clone()))
        .collect();
    let target = node.as_ref().map(|k| {
        (
            k,
            walk.iter()
                .position(|w| format!("{}/{}", w.course, w.node) == *k),
        )
    });
    if let Some((k, None)) = &target {
        eprintln!("error: unknown node `{k}`");
        return 1;
    }
    let mut out = Vec::new();
    let mut code = 0;
    for f in &files {
        let song = match fs::read_to_string(f)
            .map_err(|e| e.to_string())
            .and_then(|t| Song::from_json(&t))
        {
            Ok(s) => s,
            Err(e) => {
                eprintln!("error: {f}: {e}");
                code = 1;
                continue;
            }
        };
        let errs = song.validate();
        if !errs.is_empty() {
            eprintln!("error: {f}: {}", errs.join("; "));
            code = 1;
            continue;
        }
        let mut v = serde_json::to_value(evaluate(&song, &model)).unwrap_or(Value::Null);
        v["id"] = json!(song.id);
        v["node_fit"] = json!(node_fit(&song, &nodes));
        if let Some((k, Some(i))) = &target {
            v["node"] = json!(k);
            v["exceeds"] = json!(exceeds(&song, &walk[*i].taught, Some(&envs[*i])));
        }
        out.push(v);
    }
    println!("{}", serde_json::to_string_pretty(&out).unwrap_or_default());
    code
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round3_keeps_three_decimals() {
        assert_eq!(round3(1.23456), 1.235);
        assert_eq!(round3(-0.0004), 0.0);
    }

    #[test]
    fn fill_song_fields_adds_defaults_and_keeps_given_values() {
        let mut v = json!({"id": "x", "title": null, "generator": {}, "spec_node": "a/b"});
        fill_song_fields(&mut v);
        assert_eq!(v["id"], "x");
        assert_eq!(v["title"], "?");
        assert_eq!(v["bpm"], 100);
        assert_eq!(v["time"], "4/4");
        assert!(v.get("generator").is_none());
        assert!(v.get("spec_node").is_none());
    }

    #[test]
    fn fill_song_fields_ignores_non_objects() {
        let mut v = json!([1, 2]);
        fill_song_fields(&mut v);
        assert_eq!(v, json!([1, 2]));
    }

    #[test]
    fn music_errors_skip_license_and_provenance() {
        let song = Song::from_json(
            r#"{"id":"x","title":"t","composer":"c","arranger":"a","source":"original",
                "license":"?","composition_license":"?","bpm":100,"time":"4/4","key":"C",
                "bars":[]}"#,
        )
        .unwrap();
        assert_eq!(music_errors(&song), vec!["no bars".to_string()]);
    }

    #[test]
    fn course_songs_of_an_empty_walk_are_empty() {
        let (songs, envs) = course_songs(&[], &BTreeMap::new(), &Model::builtin());
        assert!(songs.is_empty());
        assert!(envs.is_empty());
    }
}
