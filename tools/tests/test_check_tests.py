import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import check_tests as ct  # noqa: E402


def write(root: Path, rel: str, text: str) -> Path:
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return path


def names(paths):
    return sorted(Path(p).name for p in paths)


# --- Rust: a unit test in the same file -------------------------------------


def test_rust_file_without_test_is_uncovered(tmp_path):
    write(tmp_path, "core/src/a.rs", "pub fn add(a: i32, b: i32) -> i32 { a + b }\n")
    result = ct.audit(tmp_path)
    assert result["rust"] == (1, ["core/src/a.rs"])


def test_rust_file_with_inline_test_is_covered(tmp_path):
    write(
        tmp_path,
        "core/src/b.rs",
        "pub fn add(a: i32, b: i32) -> i32 { a + b }\n"
        "#[cfg(test)]\nmod tests {\n    use super::*;\n"
        "    #[test]\n    fn adds() { assert_eq!(add(1, 2), 3); }\n}\n",
    )
    assert ct.audit(tmp_path)["rust"] == (1, [])


def test_rust_test_module_without_test_fn_is_uncovered(tmp_path):
    write(tmp_path, "core/src/c.rs", "pub fn f() {}\n#[cfg(test)]\nmod tests {}\n")
    assert ct.audit(tmp_path)["rust"] == (1, ["core/src/c.rs"])


def test_rust_declaration_only_file_is_exempt(tmp_path):
    write(
        tmp_path,
        "audio/src/lib.rs",
        "//! docs\n#[cfg(feature = \"decode\")]\npub mod decode;\npub use bank::Sample;\n",
    )
    assert ct.audit(tmp_path)["rust"] == (0, [])


def test_rust_target_directory_is_skipped(tmp_path):
    write(tmp_path, "core/target/gen.rs", "pub fn g() {}\n")
    assert ct.audit(tmp_path)["rust"] == (0, [])


# --- Python: a test file imports the module ---------------------------------


def test_python_module_imported_by_a_test_is_covered(tmp_path):
    write(tmp_path, "tools/pkg/widget.py", "def f():\n    return 1\n")
    write(tmp_path, "tools/tests/test_widget.py", "from pkg.widget import f\n")
    assert ct.audit(tmp_path)["python"] == (1, [])


def test_python_module_not_imported_is_uncovered(tmp_path):
    write(tmp_path, "tools/pkg/widget.py", "def f():\n    return 1\n")
    write(tmp_path, "tools/tests/test_other.py", "import os\n")
    assert ct.audit(tmp_path)["python"] == (1, ["tools/pkg/widget.py"])


def test_python_package_init_and_conftest_are_not_sources(tmp_path):
    write(tmp_path, "tools/pkg/__init__.py", "")
    write(tmp_path, "tools/tests/conftest.py", "")
    assert ct.audit(tmp_path)["python"] == (0, [])


def test_python_tests_are_not_sources(tmp_path):
    write(tmp_path, "tools/tests/test_x.py", "def test_ok():\n    pass\n")
    assert ct.audit(tmp_path)["python"] == (0, [])


# --- Dart: a test file under app/test imports the library -------------------


def test_dart_file_imported_by_a_test_is_covered(tmp_path):
    write(tmp_path, "app/lib/input/note_event.dart", "class NoteEvent {}\n")
    write(
        tmp_path,
        "app/test/input/note_event_test.dart",
        "import 'package:easy_piano/input/note_event.dart';\n",
    )
    assert ct.audit(tmp_path)["dart"] == (1, [])


def test_dart_file_without_a_test_is_uncovered(tmp_path):
    write(tmp_path, "app/lib/input/note_event.dart", "class NoteEvent {}\n")
    assert ct.audit(tmp_path)["dart"] == (1, ["app/lib/input/note_event.dart"])


def test_dart_generated_files_are_not_sources(tmp_path):
    write(tmp_path, "app/lib/l10n/app_localizations_en.dart", "class L {}\n")
    write(tmp_path, "app/lib/src/rust/api/audio.dart", "class A {}\n")
    write(tmp_path, "app/lib/x.g.dart", "class G {}\n")
    write(tmp_path, "app/lib/frb_generated.dart", "// GENERATED CODE - DO NOT MODIFY\n")
    assert ct.audit(tmp_path)["dart"] == (0, [])


# --- Kotlin: a test under src/test names the class --------------------------


def test_kotlin_class_named_in_a_test_is_covered(tmp_path):
    base = "app/android/app/src"
    write(tmp_path, f"{base}/main/kotlin/dev/MidiParser.kt", "class MidiParser\n")
    write(
        tmp_path,
        f"{base}/test/kotlin/dev/MidiParserTest.kt",
        "class T { val p = MidiParser() }\n",
    )
    assert ct.audit(tmp_path)["kotlin"] == (1, [])


def test_kotlin_class_without_a_test_is_uncovered(tmp_path):
    base = "app/android/app/src"
    write(tmp_path, f"{base}/main/kotlin/dev/MicBridge.kt", "class MicBridge\n")
    assert ct.audit(tmp_path)["kotlin"] == (1, [f"{base}/main/kotlin/dev/MicBridge.kt"])


# --- Ratchet: new files fail, baseline may only shrink ----------------------


def test_compare_reports_new_and_stale_entries():
    new, stale = ct.compare({"a.rs", "b.rs"}, {"b.rs", "c.rs"})
    assert new == ["a.rs"]
    assert stale == ["c.rs"]


def test_main_fails_on_a_new_untested_file(tmp_path, capsys):
    write(tmp_path, "tools/tests/__init__.py", "")
    write(tmp_path, "core/src/new.rs", "pub fn f() {}\n")
    code = ct.main([], root=tmp_path)
    assert code == 1
    assert "core/src/new.rs" in capsys.readouterr().out


def test_main_passes_when_untested_files_are_in_the_baseline(tmp_path):
    write(tmp_path, "core/src/old.rs", "pub fn f() {}\n")
    write(
        tmp_path,
        "tools/test-baseline.txt",
        "# header\ncore/src/old.rs\n",
    )
    assert ct.main([], root=tmp_path) == 0


def test_main_fails_when_a_baseline_entry_is_already_covered(tmp_path):
    write(
        tmp_path,
        "core/src/done.rs",
        "pub fn f() {}\n#[cfg(test)]\nmod t { #[test] fn ok() {} }\n",
    )
    write(tmp_path, "tools/test-baseline.txt", "core/src/done.rs\n")
    assert ct.main([], root=tmp_path) == 1


def test_update_baseline_writes_current_uncovered_files(tmp_path):
    write(tmp_path, "core/src/a.rs", "pub fn f() {}\n")
    assert ct.main(["--update-baseline"], root=tmp_path) == 0
    assert ct.read_baseline(ct.baseline_path(tmp_path)) == {"core/src/a.rs"}


def test_read_baseline_ignores_comments_and_blank_lines(tmp_path):
    path = write(tmp_path, "b.txt", "# c\n\nx.rs\n")
    assert ct.read_baseline(path) == {"x.rs"}


def test_read_baseline_of_missing_file_is_empty(tmp_path):
    assert ct.read_baseline(tmp_path / "missing.txt") == set()
