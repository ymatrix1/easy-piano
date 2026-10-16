//! `content lint <content_dir>`: validates every content file and cross-reference.
//! Exit code 1 on any error. Layout: docs/specs/content-format.md.

use easy_piano_core::song::Song;
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};

const STAGE_TYPES: [&str; 5] = ["wait", "play_along", "one_note", "animation", "quiz"];
const NODE_KINDS: [&str; 5] = ["lesson", "song", "star_gate", "boss", "mini_boss"];
const UI_TYPES: [&str; 4] = ["treble", "bass", "both", "touch"];

#[derive(Default)]
struct Lint {
    errors: Vec<String>,
    str_keys: BTreeSet<String>,
}

impl Lint {
    fn err(&mut self, file: &Path, msg: impl AsRef<str>) {
        self.errors.push(format!("{}: {}", file.display(), msg.as_ref()));
    }

    /// Collects `str:` references anywhere in a JSON value.
    fn collect_strs(&mut self, v: &Value) {
        match v {
            Value::String(s) if s.starts_with("str:") => {
                self.str_keys.insert(s[4..].to_string());
            }
            Value::Array(a) => a.iter().for_each(|x| self.collect_strs(x)),
            Value::Object(o) => o.values().for_each(|x| self.collect_strs(x)),
            _ => {}
        }
    }
}

fn json_files(dir: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    if let Ok(rd) = fs::read_dir(dir) {
        for e in rd.flatten() {
            let p = e.path();
            if p.is_dir() {
                out.extend(json_files(&p));
            } else if p.extension().is_some_and(|x| x == "json") {
                out.push(p);
            }
        }
    }
    out.sort();
    out
}

fn read_json(lint: &mut Lint, path: &Path) -> Option<Value> {
    let text = fs::read_to_string(path).map_err(|e| lint.err(path, e.to_string())).ok()?;
    serde_json::from_str(&text).map_err(|e| lint.err(path, format!("json: {e}"))).ok()
}

fn id_matches_file(lint: &mut Lint, path: &Path, v: &Value) -> Option<String> {
    let id = v.get("id").and_then(Value::as_str).map(str::to_string);
    let stem = path.file_stem().and_then(|s| s.to_str()).unwrap_or_default();
    match &id {
        None => lint.err(path, "missing `id`"),
        Some(id) if id != stem => lint.err(path, format!("id `{id}` must match file name `{stem}`")),
        _ => {}
    }
    id
}

fn lint_dir(root: &Path) -> Lint {
    let mut lint = Lint::default();

    // Songs.
    let mut songs = BTreeSet::new();
    for path in json_files(&root.join("songs")) {
        let Ok(text) = fs::read_to_string(&path) else { continue };
        match Song::from_json(&text) {
            Err(e) => lint.err(&path, e),
            Ok(song) => {
                let stem = path.file_stem().and_then(|s| s.to_str()).unwrap_or_default();
                if song.id != stem {
                    lint.err(&path, format!("id `{}` must match file name `{stem}`", song.id));
                }
                for e in song.validate() {
                    lint.err(&path, e);
                }
                songs.insert(song.id);
            }
        }
    }

    // Scenes (shape only; the scene player is Phase 2).
    let mut scenes = BTreeSet::new();
    for path in json_files(&root.join("scenes")) {
        let Some(v) = read_json(&mut lint, &path) else { continue };
        if let Some(id) = id_matches_file(&mut lint, &path, &v) {
            scenes.insert(id);
        }
        if !v.get("tracks").is_some_and(Value::is_array) {
            lint.err(&path, "`tracks` must be an array");
        }
        lint.collect_strs(&v);
    }

    // Levels, journeys and courses.
    let mut levels = BTreeMap::new();
    let courses_path = root.join("courses.json");
    let courses = read_json(&mut lint, &courses_path).unwrap_or(Value::Null);
    lint.collect_strs(&courses);
    let course_list = courses.get("courses").and_then(Value::as_array).cloned().unwrap_or_default();
    if course_list.is_empty() {
        lint.err(&courses_path, "`courses` must be a non-empty array");
    }
    let course_ids: BTreeSet<String> =
        course_list.iter().filter_map(|c| c.get("id").and_then(Value::as_str)).map(str::to_string).collect();

    for course in &course_list {
        let Some(cid) = course.get("id").and_then(Value::as_str) else {
            lint.err(&courses_path, "course without `id`");
            continue;
        };
        for req in course.get("requires").and_then(Value::as_array).into_iter().flatten() {
            if let Some(r) = req.as_str().filter(|r| !course_ids.contains(*r)) {
                lint.err(&courses_path, format!("course `{cid}` requires unknown course `{r}`"));
            }
        }
        let cdir = root.join("courses").join(cid);
        for path in json_files(&cdir.join("levels")) {
            let Some(v) = read_json(&mut lint, &path) else { continue };
            lint.collect_strs(&v);
            let Some(id) = id_matches_file(&mut lint, &path, &v) else { continue };
            if let Some(ui) = v.get("ui").and_then(Value::as_str).filter(|u| !UI_TYPES.contains(u)) {
                lint.err(&path, format!("unknown ui `{ui}`"));
            }
            let stages = v.get("stages").and_then(Value::as_array).cloned().unwrap_or_default();
            if stages.is_empty() {
                lint.err(&path, "level needs at least one stage");
            }
            for (i, st) in stages.iter().enumerate() {
                let n = i + 1;
                let ty = st.get("type").and_then(Value::as_str).unwrap_or("");
                if !STAGE_TYPES.contains(&ty) {
                    lint.err(&path, format!("stage {n}: unknown type `{ty}`"));
                }
                let needs_score = matches!(ty, "wait" | "play_along" | "one_note");
                match st.get("score").and_then(Value::as_str) {
                    Some(s) if !songs.contains(s) => lint.err(&path, format!("stage {n}: unknown score `{s}`")),
                    None if needs_score => lint.err(&path, format!("stage {n}: `{ty}` needs `score`")),
                    _ => {}
                }
                match st.get("scene").and_then(Value::as_str) {
                    Some(s) if !scenes.contains(s) => lint.err(&path, format!("stage {n}: unknown scene `{s}`")),
                    None if ty == "animation" => lint.err(&path, format!("stage {n}: animation needs `scene`")),
                    _ => {}
                }
                if let Some(t) = st.get("tempo").and_then(Value::as_f64).filter(|t| !(0.3..=1.5).contains(t)) {
                    lint.err(&path, format!("stage {n}: tempo {t} out of 0.3..1.5"));
                }
                if let Some(p) = st.get("pass").and_then(Value::as_f64).filter(|p| !(0.0..=1.0).contains(p)) {
                    lint.err(&path, format!("stage {n}: pass {p} out of 0..1"));
                }
                if let Some(h) = st.get("hand").and_then(Value::as_str).filter(|h| !["RH", "LH", "both"].contains(h)) {
                    lint.err(&path, format!("stage {n}: unknown hand `{h}`"));
                }
            }
            levels.insert(id, path.clone());
        }

        let jpath = cdir.join("journey.json");
        let Some(j) = read_json(&mut lint, &jpath) else { continue };
        lint.collect_strs(&j);
        let nodes = j.get("nodes").and_then(Value::as_array).cloned().unwrap_or_default();
        let node_ids: BTreeSet<String> =
            nodes.iter().filter_map(|n| n.get("id").and_then(Value::as_str)).map(str::to_string).collect();
        if node_ids.len() != nodes.len() {
            lint.err(&jpath, "every node needs a unique `id`");
        }
        for node in &nodes {
            let nid = node.get("id").and_then(Value::as_str).unwrap_or("?");
            let kind = node.get("kind").and_then(Value::as_str).unwrap_or("");
            if !NODE_KINDS.contains(&kind) {
                lint.err(&jpath, format!("node `{nid}`: unknown kind `{kind}`"));
            }
            for l in node.get("levels").and_then(Value::as_array).into_iter().flatten() {
                if let Some(l) = l.as_str().filter(|l| !levels.contains_key(*l)) {
                    lint.err(&jpath, format!("node `{nid}`: unknown level `{l}`"));
                }
            }
            for nx in node.get("next").and_then(Value::as_array).into_iter().flatten() {
                if let Some(nx) = nx.as_str().filter(|nx| !node_ids.contains(*nx)) {
                    lint.err(&jpath, format!("node `{nid}`: unknown next node `{nx}`"));
                }
            }
            for s in node.get("songs").and_then(Value::as_object).into_iter().flat_map(|o| o.values()) {
                if let Some(s) = s.as_str().filter(|s| !songs.contains(*s)) {
                    lint.err(&jpath, format!("node `{nid}`: unknown song slot `{s}`"));
                }
            }
        }
    }

    // Strings: every referenced key exists in English.
    let en_path = root.join("strings").join("en.json");
    let en = read_json(&mut lint, &en_path).unwrap_or(Value::Null);
    let keys: Vec<String> = lint.str_keys.iter().cloned().collect();
    for k in keys {
        if en.get(&k).and_then(Value::as_str).is_none() {
            lint.err(&en_path, format!("missing string `{k}`"));
        }
    }
    println!(
        "checked {} songs, {} scenes, {} levels, {} courses, {} string keys",
        songs.len(),
        scenes.len(),
        levels.len(),
        course_ids.len(),
        lint.str_keys.len()
    );
    lint
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let (Some("lint"), Some(dir)) = (args.get(1).map(String::as_str), args.get(2)) else {
        eprintln!("usage: content lint <content_dir>");
        std::process::exit(2);
    };
    let lint = lint_dir(Path::new(dir));
    for e in &lint.errors {
        eprintln!("error: {e}");
    }
    if !lint.errors.is_empty() {
        eprintln!("{} error(s)", lint.errors.len());
        std::process::exit(1);
    }
    println!("ok");
}
