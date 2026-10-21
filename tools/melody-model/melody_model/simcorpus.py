"""Export every dataset tune as song JSON for the similarity gate (git-ignored, local only).

    python -m melody_model.simcorpus

Writes data/melody/similarity-corpus/<corpus>/<n>.json from data/melody/dataset/tunes.jsonl
(all splits: the gate compares generated tunes with everything the model saw).
These files are for `content similar` only; their metadata records the source,
never a licence we do not have.
"""

from __future__ import annotations

import json
import shutil
import sys

from .build import OUT
from .generate import SIM_CORPUS


def main(argv):
    if SIM_CORPUS.exists():
        shutil.rmtree(SIM_CORPUS)
    n = 0
    with open(OUT / "tunes.jsonl", encoding="utf-8") as fh:
        for i, line in enumerate(fh):
            t = json.loads(line)
            d = SIM_CORPUS / t["corpus"]
            d.mkdir(parents=True, exist_ok=True)
            song = {"id": f"train-{i}", "title": t["title"] or t["id"], "composer": t["composer"] or "unknown",
                    "arranger": t.get("arranger") or "unknown", "source": "training-corpus",
                    "source_url": t.get("source_url") or None, "license": t.get("license") or "unknown",
                    "composition_license": t.get("composition_license") or "unknown",
                    "bpm": 100, "time": t["time"], "key": t["key"], "bars": t["bars"]}
            (d / f"{i}.json").write_text(json.dumps(song, ensure_ascii=False), encoding="utf-8")
            n += 1
    print(f"wrote {n} songs to {SIM_CORPUS}")


if __name__ == "__main__":
    main(sys.argv[1:])
