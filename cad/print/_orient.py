"""Shared helper: drop a part onto the print bed."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from build123d import *  # noqa: F401,E402
import keycap_case as kc  # noqa: E402


def on_bed(part, flip=False):
    """Return `part` sitting on Z = 0, optionally rolled 180 deg about X."""
    if flip:
        part = part.rotate(Axis.X, 180)
    bb = part.bounding_box()
    return part.moved(Location((0, 0, -bb.min.Z)))
