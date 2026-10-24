#!/usr/bin/env python3
"""Every source file ships tests (AGENTS.md rule 9, .agents/rules/testing.md).

Per language, a source file is covered when:

- Rust (`*.rs` under any `src/`): the same file has a `#[test]`. Files that only
  declare modules, re-export and carry cfg attributes (`lib.rs`) are exempt.
- Python (`tools/**/*.py`): a test file (under a `tests/` folder or named
  `test_*.py`) imports the module.
- Dart (`app/lib/**/*.dart`): a file under `app/test/` imports it by path.
- Kotlin (`app/android/app/src/main/**/*.kt`): a file under `src/test/` names
  its class.

Generated files and package boilerplate are exempt (see `is_exempt`).

Ratchet: the repository already has files without tests. They are listed in
`tools/test-baseline.txt`. The check fails when a file outside the baseline has
no test (new code), and when a baselined file has since gained a test or been
removed (delete it from the baseline, so the list only shrinks).

Usage:
  python tools/check_tests.py                 # check against the baseline
  python tools/check_tests.py --update-baseline   # rewrite the baseline (review the diff!)
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

SKIP_DIRS = {
    ".git",
    ".claude",
    ".dart_tool",
    ".venv",
    "venv",
    "__pycache__",
    "build",
    "data",
    "dist",
    "node_modules",
    "references",
    "target",
}

RUST_TEST = re.compile(r"#\[test\]")
RUST_DECLARATION_ONLY = re.compile(
    r"^\s*(//.*|(pub(\(crate\))? )?mod \w+;|(pub(\(crate\))? )?use [\w:{}, ]+;|#\[cfg\(.*\)\])?\s*$"
)
GENERATED = re.compile(r"GENERATED|DO NOT EDIT|Code generated")


def walk(base: Path, suffix: str):
    """Yields files under `base` ending in `suffix`, skipping vendored and build dirs."""
    if not base.exists():
        return
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            if name.endswith(suffix):
                yield Path(dirpath) / name


def rel(path: Path, root: Path) -> str:
    return path.relative_to(root).as_posix()


def is_rust_declaration_only(text: str) -> bool:
    """True for files with only comments, module declarations and re-exports (lib.rs)."""
    return all(RUST_DECLARATION_ONLY.match(line) for line in text.splitlines())


def is_generated(text: str) -> bool:
    return bool(GENERATED.search("\n".join(text.splitlines()[:3])))


def is_python_test(path: Path) -> bool:
    return "tests" in path.parts or path.name.startswith("test_")


def sources(root: Path, lang: str) -> list[Path]:
    """Source files of one language that need tests (generated files excluded)."""
    out: list[Path] = []
    if lang == "rust":
        for path in walk(root, ".rs"):
            if "src" not in path.parts or "frb_generated" in path.name:
                continue
            if is_rust_declaration_only(path.read_text(encoding="utf-8")):
                continue
            out.append(path)
    elif lang == "python":
        for path in walk(root / "tools", ".py"):
            if is_python_test(path) or path.name in {"__init__.py", "conftest.py"}:
                continue
            out.append(path)
    elif lang == "dart":
        for path in walk(root / "app" / "lib", ".dart"):
            if "l10n" in path.parts or path.name.startswith("app_localizations"):
                continue
            if path.name.endswith(".g.dart") or "frb_generated" in path.name:
                continue
            if "/src/rust/" in path.as_posix():
                continue
            out.append(path)
    elif lang == "kotlin":
        for path in walk(root / "app" / "android" / "app" / "src" / "main", ".kt"):
            out.append(path)
    return [p for p in out if not is_generated(p.read_text(encoding="utf-8"))]


def test_texts(root: Path, lang: str) -> list[str]:
    """Text of every test file for a language. Rust tests live in the source file."""
    if lang == "rust":
        return []
    if lang == "python":
        return [
            p.read_text(encoding="utf-8")
            for p in walk(root / "tools", ".py")
            if is_python_test(p)
        ]
    if lang == "dart":
        return [p.read_text(encoding="utf-8") for p in walk(root / "app" / "test", ".dart")]
    if lang == "kotlin":
        return [
            p.read_text(encoding="utf-8")
            for p in walk(root / "app" / "android" / "app" / "src" / "test", ".kt")
        ]
    return []


def is_covered(path: Path, lang: str, texts: list[str]) -> bool:
    text = path.read_text(encoding="utf-8")
    if lang == "rust":
        return bool(RUST_TEST.search(text))
    stem = re.escape(path.stem)
    if lang == "python":
        pattern = re.compile(rf"^\s*(from|import)\s+[\w.]*\b{stem}\b", re.MULTILINE)
    elif lang == "dart":
        pattern = re.compile(rf"""[/'"]{stem}\.dart['"]""")
    else:  # kotlin
        pattern = re.compile(rf"\b{stem}\b")
    return any(pattern.search(t) for t in texts)


def audit(root: Path) -> dict[str, tuple[int, list[str]]]:
    """Per language: (number of sources, sorted repo-relative paths with no test)."""
    result: dict[str, tuple[int, list[str]]] = {}
    for lang in ("rust", "python", "dart", "kotlin"):
        files = sources(root, lang)
        texts = test_texts(root, lang)
        uncovered = [rel(p, root) for p in files if not is_covered(p, lang, texts)]
        result[lang] = (len(files), sorted(uncovered))
    return result


def read_baseline(path: Path) -> set[str]:
    if not path.exists():
        return set()
    return {
        line.strip()
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.startswith("#")
    }


def compare(uncovered: set[str], baseline: set[str]) -> tuple[list[str], list[str]]:
    """(new untested files, stale baseline entries that now pass or are gone)."""
    new = sorted(uncovered - baseline)
    stale = sorted(e for e in baseline - uncovered)
    return new, stale


def baseline_path(root: Path) -> Path:
    return root / "tools" / "test-baseline.txt"


def main(argv: list[str], root: Path = ROOT) -> int:
    result = audit(root)
    uncovered = {f for _, files in result.values() for f in files}
    baseline_file = baseline_path(root)
    if "--update-baseline" in argv:
        header = (
            "# Source files without a unit test (tools/check_tests.py).\n"
            "# This list may only shrink. Add a test, then delete the line.\n"
        )
        baseline_file.parent.mkdir(parents=True, exist_ok=True)
        baseline_file.write_text(
            header + "".join(f"{f}\n" for f in sorted(uncovered)), encoding="utf-8"
        )
        print(f"wrote {len(uncovered)} entries to {rel(baseline_file, root)}")
        return 0

    total = sum(n for n, _ in result.values())
    for lang, (n, files) in result.items():
        print(f"{lang:7} {n - len(files):4} / {n:4} covered, {len(files)} without a test")
    new, stale = compare(uncovered, read_baseline(baseline_file))
    if new:
        print(f"\n{len(new)} new file(s) without a unit test (add tests in the same change):")
        for f in new:
            print(f"  {f}")
    if stale:
        print(
            f"\n{len(stale)} baseline entr(y/ies) now covered or removed; delete them from "
            f"{rel(baseline_file, root)}:"
        )
        for f in stale:
            print(f"  {f}")
    if new or stale:
        return 1
    print(f"\nok: {total} source file(s) checked, no new untested files")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
