#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Submit one AgentRequest JSON object from stdin and print its resolution."""

from __future__ import annotations

import json
import pathlib
import sys

SHARED_PATH = pathlib.Path(__file__).resolve().parents[1] / "shared"
sys.path.insert(0, str(SHARED_PATH))
from keycap_client import submit  # noqa: E402


def main() -> int:
    try:
        request = json.load(sys.stdin)
    except json.JSONDecodeError:
        return 2
    if not isinstance(request, dict):
        return 2
    response = submit(request)
    if response is None:
        return 1
    json.dump(response, sys.stdout, separators=(",", ":"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
