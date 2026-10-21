"""Training entry point (step 4). Refuses to run without the review gate for the current dataset.

python -m melody_model.train ...
"""

from __future__ import annotations

import sys

from .gate import require_gate


def main(argv):
    gate = require_gate()
    print(f"review gate ok: seed {gate['seed']}, n {gate['n']}, approved {gate['date']}")
    raise SystemExit("training is not implemented yet (step 4)")


if __name__ == "__main__":
    main(sys.argv[1:])
