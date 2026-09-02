"""Keycap Context housing - internals, plate removed and NeoKey lifted clear.

Shows how both boards sit in the tray: the XIAO in its nest on the cavity floor,
and the NeoKey hovering directly above its two locating pegs. Review artifact.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from build123d import *
from cadpy.assembly import AssemblyHelper

import keycap_case as kc
import keycap_case_fitcheck as fc
from keycap_case_cutaway import C_TRAY, C_PCB, C_XIAO

lift = 16.0     # how far the NeoKey is raised off its seat, for visibility


def build_assembly():
    asm = AssemblyHelper("keycap_context_internals")
    asm.add(kc.make_tray(), "tray", color=C_TRAY)
    asm.add(kc.make_xiao_clamp().locate(
        Location((kc.xiao_clamp_x, 0, kc.xiao_top_z))), "xiao_clamp", color=C_TRAY)
    asm.add(Compound([s.moved(Location((0, 0, lift)))
                      for s in fc.make_neokey().solids()]),
            "neokey_1x4_qt", color=C_PCB)
    asm.add(fc.make_xiao().locate(Location((kc.xiao_cx, 0,
            kc.xiao_seat_z + kc.xiao_t / 2))),
            "xiao_sense", color=C_XIAO)
    return asm


def gen_step():
    return build_assembly().build()
