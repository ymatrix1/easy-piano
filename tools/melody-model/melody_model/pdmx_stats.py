"""Raw PDMX metadata counts quoted in docs/research/melody-corpora.md.

python -m melody_model.pdmx_stats      # reads data/melody/raw/pdmx/PDMX.csv (sha256 pinned in download.py)
"""

from __future__ import annotations

import collections
import csv
import json
import sys

from .download import PDMX_SHA256, RAW, file_sha256


def main(argv):
    path = RAW / "pdmx" / "PDMX.csv"
    if file_sha256(path) != PDMX_SHA256["PDMX.csv"]:
        raise SystemExit("PDMX.csv does not match the pinned sha256")
    csv.field_size_limit(10**9)
    c = collections.Counter()
    lic_all, lic_subset = collections.Counter(), collections.Counter()
    for r in csv.DictReader(open(path, encoding="utf-8")):
        c["rows"] += 1
        lic_all[r["license"]] += 1
        if r["subset:no_license_conflict"] == "True":
            c["no_license_conflict"] += 1
            lic_subset[r["license"]] += 1
            c["no_license_conflict, composer missing"] += r["composer_name"] == "NA"
            if r["subset:deduplicated"] == "True":
                c["no_license_conflict and deduplicated"] += 1
        else:
            c["license_conflict"] += 1
    print(
        json.dumps(
            {"counts": c, "license (all rows)": lic_all, "license (no_license_conflict)": lic_subset},
            indent=1,
        )
    )


if __name__ == "__main__":
    main(sys.argv[1:])
