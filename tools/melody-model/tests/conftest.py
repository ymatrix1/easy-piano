import os

import pytest

# CI=1 or MELODY_REQUIRE_ALL=1: a missing optional tool (node, onnxruntime) fails the run instead of skipping.
REQUIRE_ALL = bool(os.environ.get("CI") or os.environ.get("MELODY_REQUIRE_ALL"))


def need(ok: bool, what: str):
    if ok:
        return
    if REQUIRE_ALL:
        pytest.fail(f"{what} is required (CI / MELODY_REQUIRE_ALL set)")
    pytest.skip(f"{what} not installed")


def pytest_configure(config):
    config.addinivalue_line("markers", "slow: real model size (11M params); deselect with -m 'not slow'")
