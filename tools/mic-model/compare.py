"""DSP detector vs trained models, held-out sets -> runs/compare.md (tables for docs/research/mic-input.md).

Reads the dart scorer outputs (runs/dsp_*.txt, `cd app && dart run tool/mic_eval.dart <dir> --mode=<m>`) and
the report.py outputs (runs/<model>.report.txt). Nothing is typed in by hand.
"""

import re
from pathlib import Path

RUNS = Path(__file__).parent / "runs"
MODELS = {"model (shipped, 21k)": "v2_16-16-24-24", "model (larger, 37k)": "v2_16-24-32-32"}
SETS = {
    "syn": (
        "synthetic fixtures (3 pianos)",
        {"score": "dsp_score.txt", "blind": "dsp_blind.txt", "wrong": "dsp_wrong.txt"},
    ),
    "real": (
        "real piano (MAESTRO test excerpts)",
        {"score": "dsp_real_score.txt", "blind": "dsp_real_blind.txt"},
    ),
    "noise": (
        "independent noise (eSpeak speech, alone and over piano)",
        {"score": "dsp_noise_score.txt", "blind": "dsp_noise_blind.txt"},
    ),
}
ROW = re.compile(r"^\| ([^|]+?) \| (\d+) \| (.+) \|$")


def rows(text):
    """test-split rows of a table dump -> {group: [cells]}"""
    test = text.split("tune set")[0]
    out = {}
    for line in test.split("\n"):
        m = ROW.match(line)
        if m:
            out[m.group(1)] = [c.strip() for c in m.group(3).split("|")]
    return out


def model_rows(model, set_title, mode):
    t = (RUNS / f"{model}.report.txt").read_text(encoding="utf8", errors="ignore")
    sec = re.search(rf"## {re.escape(set_title)}, {mode} mode\n(.*?)(?=\n## |\Z)", t, re.DOTALL)
    return rows(sec.group(1))


def cell(r, g, i):
    return r[g][i] if g in r else "-"


def noise_cell(r, g):
    m = re.search(r"= ([\d.]+)/min", r[g][0]) if g in r else None
    return m.group(1) if m else "-"


def main():
    out = []
    for title, dsp_files in SETS.values():
        for mode, f in dsp_files.items():
            dsp = rows((RUNS / f).read_text(encoding="utf8", errors="ignore"))
            ms = {name: model_rows(tag, title, mode) for name, tag in MODELS.items()}
            out.append(f"\n#### {title}, {mode} mode (held-out test split)\n")
            out.append(
                "| Group | Notes | DSP P / R / F1 | " + " | ".join(f"{n} P / R / F1" for n in MODELS) + " |"
            )
            out.append("|---|---|---|" + "---|" * len(MODELS))
            groups = [g for g in dsp if g not in ("noise", "speech")]
            dsp_text = (RUNS / f).read_text(encoding="utf8", errors="ignore").split("tune set")[0]

            def prf(r, g):
                c = r[g]
                return f"{c[0]} / {c[1]} / {c[2]}"

            for g in groups:
                if g not in ms["model (shipped, 21k)"]:
                    continue
                n = re.search(rf"^\| {re.escape(g)} \| (\d+) \|", dsp_text, re.MULTILINE).group(1)
                out.append(
                    f"| {g} | {n} | {prf(dsp, g)} | " + " | ".join(prf(ms[name], g) for name in MODELS) + " |"
                )
            for g in ("noise", "speech"):
                if g in dsp:
                    out.append(
                        f"| {g}: false notes/min | | {noise_cell(dsp, g)} | "
                        + " | ".join(noise_cell(ms[name], g) for name in MODELS)
                        + " |"
                    )
            # delay and phantom summary
            out.append(
                f"| report delay p50 / p95 (ms), all | | {dsp['all'][4]} | "
                + " | ".join(ms[name]["all"][4] for name in MODELS)
                + " |"
            )
            if mode == "wrong":
                out.append(
                    f"| phantom passes (all) | | {dsp['all'][5].strip()} | "
                    + " | ".join(ms[name]["all"][5].strip() for name in MODELS)
                    + " |"
                )
    (RUNS / "compare.md").write_text("\n".join(out), encoding="utf8")
    print("\n".join(out))


if __name__ == "__main__":
    main()
