//! `content lint <content_dir>`: validates every content file and cross-reference.
//! Exit code 1 on any error. Layout: docs/specs/content-format.md.
//! `content check <content_dir> <course/node> <song.json>...`: rubric errors of outside songs (generated tunes)
//! `content specs <content_dir> [--out <file>]`: cumulative taught set per journey
//! node plus its skill spec (docs/specs/skill-specs.md).

mod similar;

use easy_piano_core::rubric::{check, CourseSpecs, NodeSpec, TaughtSet};
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
    /// Non-fatal: printed, exit code stays 0 (e.g. untranslated strings).
    warnings: Vec<String>,
    str_keys: BTreeSet<String>,
}

impl Lint {
    fn err(&mut self, file: &Path, msg: impl AsRef<str>) {
        self.errors
            .push(format!("{}: {}", file.display(), msg.as_ref()));
    }

    fn warn(&mut self, file: &Path, msg: impl AsRef<str>) {
        self.warnings
            .push(format!("{}: {}", file.display(), msg.as_ref()));
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
    let text = fs::read_to_string(path)
        .map_err(|e| lint.err(path, e.to_string()))
        .ok()?;
    serde_json::from_str(&text)
        .map_err(|e| lint.err(path, format!("json: {e}")))
        .ok()
}

fn id_matches_file(lint: &mut Lint, path: &Path, v: &Value) -> Option<String> {
    let id = v.get("id").and_then(Value::as_str).map(str::to_string);
    let stem = path
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or_default();
    match &id {
        None => lint.err(path, "missing `id`"),
        Some(id) if id != stem => {
            lint.err(path, format!("id `{id}` must match file name `{stem}`"))
        }
        _ => {}
    }
    id
}

/// Songs by id, plus the files that failed to read or parse.
fn load_songs(root: &Path) -> (BTreeMap<String, Song>, Vec<(PathBuf, String)>) {
    let (mut songs, mut bad) = (BTreeMap::new(), Vec::new());
    for p in json_files(&root.join("songs")) {
        match fs::read_to_string(&p)
            .map_err(|e| e.to_string())
            .and_then(|t| Song::from_json(&t))
        {
            Ok(s) => {
                songs.insert(s.id.clone(), s);
            }
            Err(e) => bad.push((p, e)),
        }
    }
    (songs, bad)
}

/// One journey node with the songs its levels play and everything taught so far.
struct NodeTaught {
    course: String,
    node: String,
    kind: String,
    songs: Vec<String>,
    taught: TaughtSet,
}

/// Walks courses in `courses.json` order and nodes in journey order, adding each
/// node's level scores and song-slot variants to a running taught set. Lint
/// requires every course to come after the courses it `requires`, so this order
/// is a valid learning order. Generated songs never widen the set.
fn taught_walk(lint: &mut Lint, root: &Path, songs: &BTreeMap<String, Song>) -> Vec<NodeTaught> {
    let read = |p: PathBuf| {
        fs::read_to_string(p)
            .ok()
            .and_then(|t| serde_json::from_str::<Value>(&t).ok())
    };
    let courses_path = root.join("courses.json");
    let mut out = Vec::new();
    let mut taught = TaughtSet::default();
    let mut seen: BTreeSet<String> = BTreeSet::new();
    let courses = read(courses_path.clone()).unwrap_or(Value::Null);
    for course in courses
        .get("courses")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
    {
        let Some(cid) = course.get("id").and_then(Value::as_str) else {
            continue;
        };
        for r in course
            .get("requires")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter_map(Value::as_str)
        {
            if !seen.contains(r) {
                lint.err(
                    &courses_path,
                    format!("course `{cid}` requires `{r}`, which must be listed before it"),
                );
            }
        }
        seen.insert(cid.to_string());
        if course.get("status").and_then(Value::as_str) == Some("planned") {
            continue;
        }
        let expected = format!("courses/{cid}/journey.json");
        match course.get("journey").and_then(Value::as_str) {
            Some(j) if j == expected => {}
            other => lint.err(
                &courses_path,
                format!("course `{cid}`: `journey` must be `{expected}`, found {other:?}"),
            ),
        }
        let cdir = root.join("courses").join(cid);
        let Some(journey) = read(cdir.join("journey.json")) else {
            continue;
        };
        for node in journey
            .get("nodes")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
        {
            let mut ids: Vec<String> = Vec::new();
            for level in node
                .get("levels")
                .and_then(Value::as_array)
                .into_iter()
                .flatten()
                .filter_map(Value::as_str)
            {
                let Some(lv) = read(cdir.join("levels").join(format!("{level}.json"))) else {
                    continue;
                };
                for st in lv
                    .get("stages")
                    .and_then(Value::as_array)
                    .into_iter()
                    .flatten()
                {
                    if let Some(s) = st
                        .get("score")
                        .and_then(Value::as_str)
                        .filter(|s| !ids.iter().any(|i| i == s))
                    {
                        ids.push(s.to_string());
                    }
                }
            }
            // Profile variants (`songs` slots) teach the same node to other learners.
            for s in node
                .get("songs")
                .and_then(Value::as_object)
                .into_iter()
                .flat_map(|o| o.values())
                .filter_map(Value::as_str)
            {
                if !ids.iter().any(|i| i == s) {
                    ids.push(s.to_string());
                }
            }
            for s in ids
                .iter()
                .filter_map(|i| songs.get(i))
                .filter(|s| s.source != "generated")
            {
                match TaughtSet::from_song(s) {
                    Ok(t) => taught.merge(&t),
                    Err(es) => {
                        let path = root.join("songs").join(format!("{}.json", s.id));
                        es.iter()
                            .for_each(|e| lint.err(&path, format!("not counted as taught: {e}")));
                    }
                }
            }
            out.push(NodeTaught {
                course: cid.to_string(),
                node: node
                    .get("id")
                    .and_then(Value::as_str)
                    .unwrap_or("?")
                    .to_string(),
                kind: node
                    .get("kind")
                    .and_then(Value::as_str)
                    .unwrap_or("")
                    .to_string(),
                songs: ids,
                taught: taught.clone(),
            });
        }
    }
    out
}

/// `skill-specs/<course>.json` files keyed by `course/node`. Problems go to `lint`.
fn load_specs(lint: &mut Lint, root: &Path, walk: &[NodeTaught]) -> BTreeMap<String, NodeSpec> {
    let mut out = BTreeMap::new();
    for path in json_files(&root.join("skill-specs")) {
        let Ok(text) = fs::read_to_string(&path) else {
            continue;
        };
        let specs: CourseSpecs = match serde_json::from_str(&text) {
            Ok(s) => s,
            Err(e) => {
                lint.err(&path, format!("json: {e}"));
                continue;
            }
        };
        let stem = path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or_default();
        if specs.course != stem {
            lint.err(
                &path,
                format!("course `{}` must match file name `{stem}`", specs.course),
            );
        }
        for n in specs.nodes {
            if !walk
                .iter()
                .any(|w| w.course == specs.course && w.node == n.node)
            {
                lint.err(
                    &path,
                    format!("node `{}` is not in the course journey", n.node),
                );
            }
            for e in n.validate() {
                lint.err(&path, format!("node `{}`: {e}", n.node));
            }
            let key = format!("{}/{}", specs.course, n.node);
            if out.insert(key.clone(), n).is_some() {
                lint.err(&path, format!("duplicate spec for `{key}`"));
            }
        }
    }
    out
}

/// `content specs` report: per node, the taught set, its spec and how the node's
/// own songs fare against that spec (`self_check`, song id → rubric errors).
fn specs_report(root: &Path) -> (Value, Lint) {
    let mut lint = Lint::default();
    let (songs, bad) = load_songs(root);
    for (p, e) in bad {
        lint.err(
            &p,
            format!("song not loaded, taught sets may be too small: {e}"),
        );
    }
    let walk = taught_walk(&mut lint, root, &songs);
    let specs = load_specs(&mut lint, root, &walk);
    let nodes = walk
        .iter()
        .map(|w| {
            let spec = specs.get(&format!("{}/{}", w.course, w.node));
            let self_check: BTreeMap<&String, Vec<String>> = spec
                .map(|sp| w.songs.iter().filter_map(|id| Some((id, check(songs.get(id)?, &w.taught, sp)))).collect())
                .unwrap_or_default();
            serde_json::json!({
                "course": w.course,
                "node": w.node,
                "kind": w.kind,
                "songs": w.songs,
                "taught": w.taught.to_json(),
                "spec": spec.map(|s| serde_json::json!({
                    "new_skill": s.new_skill, "bars": s.bars, "bpm": s.bpm, "hands": s.hands, "time": s.time,
                    "required": s.required.len(),
                })),
                "self_check": self_check,
            })
        })
        .collect();
    (Value::Array(nodes), lint)
}

/// `content check <content_dir> <course/node> <song.json>...`: rubric errors of
/// outside songs (e.g. generated tunes) against one node's taught set and spec.
/// Prints `{file: [errors]}` as JSON; exit 0 when every song passes, 1 otherwise.
fn check_songs(root: &Path, node: &str, files: &[String]) -> i32 {
    let mut lint = Lint::default();
    let (songs, _) = load_songs(root);
    let walk = taught_walk(&mut lint, root, &songs);
    let specs = load_specs(&mut lint, root, &walk);
    let (Some(w), Some(spec)) = (
        walk.iter()
            .find(|w| format!("{}/{}", w.course, w.node) == node),
        specs.get(node),
    ) else {
        eprintln!("error: no node or spec `{node}`");
        return 2;
    };
    let mut out = BTreeMap::new();
    for f in files {
        let errors = match fs::read_to_string(f)
            .map_err(|e| e.to_string())
            .and_then(|t| Song::from_json(&t).map_err(|e| e.to_string()))
        {
            Ok(song) => check(&song, &w.taught, spec),
            Err(e) => vec![format!("not a song: {e}")],
        };
        out.insert(f.clone(), errors);
    }
    let all_pass = out.values().all(Vec::is_empty);
    println!("{}", serde_json::to_string_pretty(&out).unwrap_or_default());
    i32::from(!all_pass)
}

fn lint_dir(root: &Path) -> Lint {
    let mut lint = Lint::default();

    // Songs.
    let mut songs = BTreeSet::new();
    for path in json_files(&root.join("songs")) {
        let Ok(text) = fs::read_to_string(&path) else {
            continue;
        };
        match Song::from_json(&text) {
            Err(e) => lint.err(&path, e),
            Ok(song) => {
                let stem = path
                    .file_stem()
                    .and_then(|s| s.to_str())
                    .unwrap_or_default();
                if song.id != stem {
                    lint.err(
                        &path,
                        format!("id `{}` must match file name `{stem}`", song.id),
                    );
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
        let Some(v) = read_json(&mut lint, &path) else {
            continue;
        };
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
    let course_list = courses
        .get("courses")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    if course_list.is_empty() {
        lint.err(&courses_path, "`courses` must be a non-empty array");
    }
    let section_ids: BTreeSet<String> = courses
        .get("sections")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(|s| s.get("id").and_then(Value::as_str))
        .map(str::to_string)
        .collect();
    let course_ids: BTreeSet<String> = course_list
        .iter()
        .filter_map(|c| c.get("id").and_then(Value::as_str))
        .map(str::to_string)
        .collect();

    for course in &course_list {
        let Some(cid) = course.get("id").and_then(Value::as_str) else {
            lint.err(&courses_path, "course without `id`");
            continue;
        };
        for req in course
            .get("requires")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
        {
            if let Some(r) = req.as_str().filter(|r| !course_ids.contains(*r)) {
                lint.err(
                    &courses_path,
                    format!("course `{cid}` requires unknown course `{r}`"),
                );
            }
        }
        if let Some(sec) = course.get("section").and_then(Value::as_str) {
            if !section_ids.is_empty() && !section_ids.contains(sec) {
                lint.err(
                    &courses_path,
                    format!("course `{cid}`: unknown section `{sec}`"),
                );
            }
        }
        // Planned courses are listed (locked) in the app but have no journey yet.
        match course.get("status").and_then(Value::as_str) {
            Some("planned") => continue,
            Some(st) if st != "ready" => {
                lint.err(
                    &courses_path,
                    format!("course `{cid}`: unknown status `{st}`"),
                );
            }
            _ => {}
        }
        let cdir = root.join("courses").join(cid);
        for path in json_files(&cdir.join("levels")) {
            let Some(v) = read_json(&mut lint, &path) else {
                continue;
            };
            lint.collect_strs(&v);
            let Some(id) = id_matches_file(&mut lint, &path, &v) else {
                continue;
            };
            if let Some(ui) = v
                .get("ui")
                .and_then(Value::as_str)
                .filter(|u| !UI_TYPES.contains(u))
            {
                lint.err(&path, format!("unknown ui `{ui}`"));
            }
            if v.get("keyboard").is_some_and(|k| !k.is_boolean()) {
                lint.err(&path, "`keyboard` must be true or false");
            }
            let stages = v
                .get("stages")
                .and_then(Value::as_array)
                .cloned()
                .unwrap_or_default();
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
                    Some(s) if !songs.contains(s) => {
                        lint.err(&path, format!("stage {n}: unknown score `{s}`"))
                    }
                    None if needs_score => {
                        lint.err(&path, format!("stage {n}: `{ty}` needs `score`"))
                    }
                    _ => {}
                }
                match st.get("scene").and_then(Value::as_str) {
                    Some(s) if !scenes.contains(s) => {
                        lint.err(&path, format!("stage {n}: unknown scene `{s}`"))
                    }
                    None if ty == "animation" => {
                        lint.err(&path, format!("stage {n}: animation needs `scene`"))
                    }
                    _ => {}
                }
                if let Some(t) = st
                    .get("tempo")
                    .and_then(Value::as_f64)
                    .filter(|t| !(0.3..=1.5).contains(t))
                {
                    lint.err(&path, format!("stage {n}: tempo {t} out of 0.3..1.5"));
                }
                if let Some(p) = st
                    .get("pass")
                    .and_then(Value::as_f64)
                    .filter(|p| !(0.0..=1.0).contains(p))
                {
                    lint.err(&path, format!("stage {n}: pass {p} out of 0..1"));
                }
                if let Some(r) = st.get("repeats") {
                    if !r.as_u64().is_some_and(|r| (1..=10).contains(&r)) {
                        lint.err(&path, format!("stage {n}: repeats must be 1..10"));
                    }
                }
                if let Some(h) = st
                    .get("hand")
                    .and_then(Value::as_str)
                    .filter(|h| !["RH", "LH", "both"].contains(h))
                {
                    lint.err(&path, format!("stage {n}: unknown hand `{h}`"));
                }
            }
            levels.insert(id, path.clone());
        }

        let jpath = cdir.join("journey.json");
        let Some(j) = read_json(&mut lint, &jpath) else {
            continue;
        };
        lint.collect_strs(&j);
        let nodes = j
            .get("nodes")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default();
        let node_ids: BTreeSet<String> = nodes
            .iter()
            .filter_map(|n| n.get("id").and_then(Value::as_str))
            .map(str::to_string)
            .collect();
        if node_ids.len() != nodes.len() {
            lint.err(&jpath, "every node needs a unique `id`");
        }
        for node in &nodes {
            let nid = node.get("id").and_then(Value::as_str).unwrap_or("?");
            let kind = node.get("kind").and_then(Value::as_str).unwrap_or("");
            if !NODE_KINDS.contains(&kind) {
                lint.err(&jpath, format!("node `{nid}`: unknown kind `{kind}`"));
            }
            let n_levels = node
                .get("levels")
                .and_then(Value::as_array)
                .map_or(0, Vec::len);
            match (kind, node.get("stars_needed").map(Value::as_u64)) {
                ("star_gate", Some(Some(n))) if n >= 1 && n as usize <= 3 * n_levels => {}
                ("star_gate", _) => lint.err(
                    &jpath,
                    format!(
                        "node `{nid}`: star_gate needs `stars_needed` 1..={}",
                        3 * n_levels
                    ),
                ),
                (_, Some(_)) => lint.err(
                    &jpath,
                    format!("node `{nid}`: `stars_needed` only on star_gate"),
                ),
                _ => {}
            }
            for l in node
                .get("levels")
                .and_then(Value::as_array)
                .into_iter()
                .flatten()
            {
                if let Some(l) = l.as_str().filter(|l| !levels.contains_key(*l)) {
                    lint.err(&jpath, format!("node `{nid}`: unknown level `{l}`"));
                }
            }
            for nx in node
                .get("next")
                .and_then(Value::as_array)
                .into_iter()
                .flatten()
            {
                if let Some(nx) = nx.as_str().filter(|nx| !node_ids.contains(*nx)) {
                    lint.err(&jpath, format!("node `{nid}`: unknown next node `{nx}`"));
                }
            }
            for s in node
                .get("songs")
                .and_then(Value::as_object)
                .into_iter()
                .flat_map(|o| o.values())
            {
                if let Some(s) = s.as_str().filter(|s| !songs.contains(*s)) {
                    lint.err(&jpath, format!("node `{nid}`: unknown song slot `{s}`"));
                }
            }
        }
    }

    // Skill specs, and the rubric for songs that target a node.
    // Unparseable songs were reported above; they are missing from taught sets.
    let (song_map, _) = load_songs(root);
    let walk = taught_walk(&mut lint, root, &song_map);
    let specs = load_specs(&mut lint, root, &walk);
    for song in song_map.values() {
        let Some(key) = &song.spec_node else { continue };
        let path = root.join("songs").join(format!("{}.json", song.id));
        let w = walk
            .iter()
            .find(|w| format!("{}/{}", w.course, w.node) == *key);
        let (Some(spec), Some(w)) = (specs.get(key), w) else {
            lint.err(&path, format!("spec_node `{key}` has no skill spec"));
            continue;
        };
        for e in check(song, &w.taught, spec) {
            lint.err(&path, format!("rubric {key}: {e}"));
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
    // Other locales: English is the fallback, so gaps only warn (docs/specs/i18n.md).
    let en_keys: BTreeSet<String> = en
        .as_object()
        .map(|o| o.keys().cloned().collect())
        .unwrap_or_default();
    let mut locales = 0;
    for path in json_files(&root.join("strings")) {
        if path == en_path {
            continue;
        }
        let Some(v) = read_json(&mut lint, &path) else {
            continue;
        };
        let Some(o) = v.as_object() else {
            lint.err(&path, "strings file must be an object");
            continue;
        };
        locales += 1;
        for (k, val) in o {
            if !val.is_string() {
                lint.err(&path, format!("string `{k}` must be text"));
            } else if !en_keys.contains(k) {
                lint.warn(&path, format!("`{k}` is not in en.json (stale?)"));
            }
        }
        let missing: Vec<&String> = en_keys.iter().filter(|k| !o.contains_key(*k)).collect();
        if !missing.is_empty() {
            let list: Vec<&str> = missing.iter().map(|k| k.as_str()).collect();
            lint.warn(
                &path,
                format!(
                    "{} untranslated string(s), English fallback: {}",
                    missing.len(),
                    list.join(", ")
                ),
            );
        }
    }
    println!(
        "checked {} songs, {} scenes, {} levels, {} courses, {} string keys, {} other locales",
        songs.len(),
        scenes.len(),
        levels.len(),
        course_ids.len(),
        lint.str_keys.len(),
        locales
    );
    lint
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.get(1).map(String::as_str) == Some("similar") {
        std::process::exit(similar::run(&args[2..]));
    }
    if args.get(1).map(String::as_str) == Some("check") {
        let (Some(dir), Some(node)) = (args.get(2), args.get(3)) else {
            eprintln!("usage: content check <content_dir> <course/node> <song.json>...");
            std::process::exit(2);
        };
        std::process::exit(check_songs(Path::new(dir), node, &args[4..]));
    }
    let (Some(cmd @ ("lint" | "specs")), Some(dir)) =
        (args.get(1).map(String::as_str), args.get(2))
    else {
        eprintln!("usage: content lint <content_dir>\n       content specs <content_dir> [--out <file>]\n       content check <content_dir> <course/node> <song.json>...");
        std::process::exit(2);
    };
    if cmd == "specs" {
        let (report, lint) = specs_report(Path::new(dir));
        let text = serde_json::to_string_pretty(&report).unwrap_or_default();
        match (args.get(3).map(String::as_str), args.get(4)) {
            (Some("--out"), Some(out)) => {
                if let Err(e) = fs::write(out, text + "\n") {
                    eprintln!("error: {out}: {e}");
                    std::process::exit(1);
                }
                eprintln!("wrote {out}");
            }
            _ => println!("{text}"),
        }
        for e in &lint.errors {
            eprintln!("error: {e}");
        }
        std::process::exit(i32::from(!lint.errors.is_empty()));
    }
    let lint = lint_dir(Path::new(dir));
    for w in &lint.warnings {
        eprintln!("warning: {w}");
    }
    for e in &lint.errors {
        eprintln!("error: {e}");
    }
    if !lint.errors.is_empty() {
        eprintln!("{} error(s)", lint.errors.len());
        std::process::exit(1);
    }
    println!("ok");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn check_songs_reports_each_file_and_fails_closed() {
        let content = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../content");
        let dir = std::env::temp_dir().join(format!("content-check-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let good = content
            .join("songs/cdefg-drill.json")
            .to_string_lossy()
            .into_owned();
        let bad = dir.join("bad.json");
        fs::write(&bad, "{not json").unwrap();
        let bad = bad.to_string_lossy().into_owned();
        assert_eq!(
            check_songs(
                &content,
                "piano-basics/f-and-g",
                std::slice::from_ref(&good)
            ),
            0
        );
        assert_eq!(
            check_songs(&content, "piano-basics/f-and-g", &[good.clone(), bad]),
            1,
            "an unparsable song fails"
        );
        assert_eq!(
            check_songs(&content, "no-such/node", &[good]),
            2,
            "unknown node is an error, not a pass"
        );
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn missing_locale_strings_warn_but_do_not_fail() {
        let dir = std::env::temp_dir().join(format!("content-lint-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(dir.join("strings")).unwrap();
        fs::write(
            dir.join("courses.json"),
            r#"{"courses":[{"id":"c","title":"str:a","status":"planned"}]}"#,
        )
        .unwrap();
        fs::write(dir.join("strings/en.json"), r#"{"a":"A","b":"B"}"#).unwrap();
        fs::write(dir.join("strings/es.json"), r#"{"a":"A es","z":"stale"}"#).unwrap();
        fs::write(dir.join("strings/fr.json"), r#"{"a":1}"#).unwrap();
        let lint = lint_dir(&dir);
        fs::remove_dir_all(&dir).unwrap();
        let w = lint.warnings.join(
            "
",
        );
        assert!(
            w.contains("1 untranslated string(s), English fallback: b"),
            "{w}"
        );
        assert!(w.contains("`z` is not in en.json"), "{w}");
        assert_eq!(lint.errors.len(), 1, "{:?}", lint.errors);
        assert!(lint.errors[0].contains("string `a` must be text"));
    }

    fn song_json(id: &str, source: &str, bars: &str, extra: &str) -> String {
        let license = if source == "generated" {
            "CC0-1.0"
        } else {
            "CC-BY-SA-4.0"
        };
        format!(
            r#"{{"id":"{id}","title":"T","composer":"Trad.","arranger":"X","source":"{source}","source_url":null,
            "license":"{license}","composition_license":"public-domain","bpm":80,"time":"4/4","key":"C",
            "bars":{bars}{extra}}}"#
        )
    }

    /// Two courses, one node each, plus generated songs that target `c2/b`.
    fn fixture(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("content-specs-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        for d in [
            "songs",
            "strings",
            "skill-specs",
            "courses/c1/levels",
            "courses/c2/levels",
        ] {
            fs::create_dir_all(dir.join(d)).unwrap();
        }
        let w = |p: &str, t: &str| fs::write(dir.join(p), t).unwrap();
        w("strings/en.json", "{}");
        w(
            "courses.json",
            r#"{"courses":[{"id":"c1","requires":[],"journey":"courses/c1/journey.json"},{"id":"c2","requires":["c1"],"journey":"courses/c2/journey.json"}]}"#,
        );
        for (c, n, l, s) in [("c1", "a", "l1", "s1"), ("c2", "b", "l2", "s2")] {
            w(
                &format!("courses/{c}/journey.json"),
                &format!(r#"{{"nodes":[{{"id":"{n}","kind":"lesson","levels":["{l}"]}}]}}"#),
            );
            w(
                &format!("courses/{c}/levels/{l}.json"),
                &format!(r#"{{"id":"{l}","stages":[{{"type":"wait","score":"{s}"}}]}}"#),
            );
        }
        w(
            "songs/s1.json",
            &song_json("s1", "original", r#"[{"RH":"C4:4 D4:4 E4:2"}]"#, ""),
        );
        w(
            "songs/s2.json",
            &song_json(
                "s2",
                "original",
                r#"[{"RH":"C4:8 D4:8 E4:8 F4:8 G4:2"}]"#,
                "",
            ),
        );
        w(
            "skill-specs/c2.json",
            r#"{"course":"c2","nodes":[{"node":"b","new_skill":"eighths","required":[{"rhythm":"8"}],
            "bars":[1,8],"bpm":[60,100],"hands":"RH","time":"4/4"}]}"#,
        );
        dir
    }

    #[test]
    fn taught_set_accumulates_across_courses_and_skips_generated_songs() {
        let dir = fixture("walk");
        fs::write(
            dir.join("courses/c2/levels/l2.json"),
            r#"{"id":"l2","stages":[{"type":"wait","score":"s2"},{"type":"wait","score":"g"}]}"#,
        )
        .unwrap();
        fs::write(
            dir.join("songs/g.json"),
            song_json(
                "g",
                "generated",
                r#"[{"RH":"A4:1"}]"#,
                r#","generator":{"method":"rules","seed":1}"#,
            ),
        )
        .unwrap();
        let walk = taught_walk(&mut Lint::default(), &dir, &load_songs(&dir).0);
        let (report, lint) = specs_report(&dir);
        fs::remove_dir_all(&dir).unwrap();
        assert_eq!(walk.len(), 2);
        assert_eq!(walk[0].taught.pitches["RH"], BTreeSet::from([60, 62, 64]));
        assert!(!walk[0].taught.durations.contains("8"));
        assert_eq!(walk[1].songs, vec!["s2", "g"]);
        assert_eq!(
            walk[1].taught.pitches["RH"],
            BTreeSet::from([60, 62, 64, 65, 67]),
            "A4 from the generated song must not count"
        );
        assert!(walk[1].taught.durations.contains("8") && walk[1].taught.durations.contains("4"));
        assert!(lint.errors.is_empty(), "{:?}", lint.errors);
        assert_eq!(
            report[1]["taught"]["pitches"]["RH"],
            serde_json::json!(["C4", "D4", "E4", "F4", "G4"])
        );
        assert_eq!(report[1]["self_check"]["s2"], serde_json::json!([]));
        assert!(report[0]["spec"].is_null());
    }

    #[test]
    fn lint_runs_the_rubric_for_songs_with_spec_node() {
        let dir = fixture("rubric");
        let gen = r#","generator":{"method":"llm","tool":"compose-song"},"spec_node":"c2/b""#;
        fs::write(
            dir.join("songs/good.json"),
            song_json(
                "good",
                "generated",
                r#"[{"RH":"E4:8 D4:8 C4:4 D4:2"}]"#,
                gen,
            ),
        )
        .unwrap();
        fs::write(
            dir.join("songs/bad.json"),
            song_json("bad", "generated", r#"[{"RH":"C4:4 A4:4 C4:2"}]"#, gen),
        )
        .unwrap();
        fs::write(
            dir.join("songs/lost.json"),
            song_json(
                "lost",
                "generated",
                r#"[{"RH":"C4:1"}]"#,
                &gen.replace("c2/b", "c2/zz"),
            ),
        )
        .unwrap();
        fs::write(
            dir.join("skill-specs/c1.json"),
            r#"{"course":"c1","nodes":[{"node":"nope","new_skill":"x","bars":[1,1],"bpm":[60,60],"hands":"RH","time":"4/4"}]}"#,
        )
        .unwrap();
        let lint = lint_dir(&dir);
        fs::remove_dir_all(&dir).unwrap();
        let e = lint.errors.join("\n");
        assert!(!e.contains("good.json"), "{e}");
        assert!(
            e.contains("bad.json: rubric c2/b: RH: pitches not taught: A4"),
            "{e}"
        );
        assert!(
            e.contains("bad.json: rubric c2/b: missing required pattern {\"rhythm\":\"8\"}"),
            "{e}"
        );
        assert!(
            e.contains("lost.json: spec_node `c2/zz` has no skill spec"),
            "{e}"
        );
        assert!(
            e.contains("node `nope` is not in the course journey"),
            "{e}"
        );
    }

    #[test]
    fn walk_checks_course_order_journey_field_variants_and_bad_songs() {
        let dir = fixture("order");
        fs::write(
            dir.join("courses.json"),
            r#"{"courses":[{"id":"c2","requires":["c1"],"journey":"courses/c2/journey.json"},{"id":"c1","requires":[]}]}"#,
        )
        .unwrap();
        fs::write(
            dir.join("courses/c2/journey.json"),
            r#"{"nodes":[{"id":"b","kind":"song","levels":["l2"],"songs":{"default":"s2","folk":"v"}}]}"#,
        )
        .unwrap();
        fs::write(
            dir.join("songs/v.json"),
            song_json("v", "original", r#"[{"RH":"B4:1"}]"#, ""),
        )
        .unwrap();
        fs::write(dir.join("songs/broken.json"), "{").unwrap();
        let (report, lint) = specs_report(&dir);
        fs::remove_dir_all(&dir).unwrap();
        let e = lint.errors.join("\n");
        assert!(
            e.contains("course `c2` requires `c1`, which must be listed before it"),
            "{e}"
        );
        assert!(
            e.contains("course `c1`: `journey` must be `courses/c1/journey.json`, found None"),
            "{e}"
        );
        assert!(e.contains("broken.json: song not loaded"), "{e}");
        assert_eq!(report[0]["songs"], serde_json::json!(["s2", "v"]));
        assert!(report[0]["taught"]["pitches"]["RH"]
            .as_array()
            .unwrap()
            .contains(&serde_json::json!("B4")));
    }

    #[test]
    fn repo_skill_specs_cover_every_node_and_parse() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../content");
        let (report, lint) = specs_report(&root);
        assert!(lint.errors.is_empty(), "{:?}", lint.errors);
        let nodes = report.as_array().unwrap();
        let missing: Vec<String> = nodes
            .iter()
            .filter(|n| n["spec"].is_null())
            .map(|n| {
                format!(
                    "{}/{}",
                    n["course"].as_str().unwrap(),
                    n["node"].as_str().unwrap()
                )
            })
            .collect();
        assert!(
            missing.is_empty(),
            "nodes without a skill spec: {missing:?}"
        );
    }
}
