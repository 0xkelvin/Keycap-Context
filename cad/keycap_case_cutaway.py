"""Keycap Context housing - cutaway through the key row.

Everything in the fit-check assembly, clipped to Y <= 0 so the internal stack is
visible: XIAO on its pad, the wiring cavity, the NeoKey resting on the ledge and
locating pegs, and the switches through the plate. Review artifact, not a part.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from build123d import *
from cadpy.assembly import AssemblyHelper

import keycap_case as kc
import keycap_case_fitcheck as fc

# Keep the half at -Y; oversize the tool well past every face it crosses.
KEEP = Box(kc.outer_l + 20, kc.outer_w + 20, kc.case_h + 40).locate(
    Location((0, -(kc.outer_w + 20) / 2, (kc.case_h + 40) / 2 - 20)))


def clip(shape):
    """Intersect a part (or an imported compound) with the keep half."""
    solids = shape.solids()
    if len(solids) == 1:
        return solids[0] & KEEP
    kept = [s & KEEP for s in solids]
    return Compound([k for k in kept if k is not None and k.volume > 1e-9])


# Colours are review aids only; they carry no manufacturing meaning.
C_TRAY   = Color(0.72, 0.74, 0.78)
C_PLATE  = Color(0.42, 0.45, 0.50)
C_PCB    = Color(0.05, 0.45, 0.28)
C_XIAO   = Color(0.10, 0.42, 0.72)
C_SWITCH = Color(0.18, 0.18, 0.20)
C_CAP    = Color(0.86, 0.82, 0.74)


def build_assembly():
    asm = AssemblyHelper("keycap_context_cutaway")

    asm.add(clip(kc.make_tray()), "tray", color=C_TRAY)
    asm.add(clip(kc.make_plate().locate(Location((0, 0, kc.tray_h)))),
            "plate", color=C_PLATE)
    asm.add(clip(kc.make_xiao_clamp().locate(
        Location((kc.xiao_clamp_x, 0, kc.xiao_top_z)))), "xiao_clamp", color=C_TRAY)
    asm.add(clip(fc.make_neokey()), "neokey_1x4_qt", color=C_PCB)

    for i, x in enumerate(kc.key_x, start=1):
        asm.add(clip(fc.make_switch().locate(Location((x, 0, kc.pcb_top)))),
                "mx_switch", f"key{i}", color=C_SWITCH)
        asm.add(clip(fc.make_keycap().locate(
            Location((x, 0, kc.pcb_top + kc.keycap_gap)))),
            "keycap", f"key{i}", color=C_CAP)

    asm.add(clip(fc.make_xiao().locate(Location((kc.xiao_cx, 0,
            kc.xiao_seat_z + kc.xiao_t / 2)))),
            "xiao_sense", color=C_XIAO)
    return asm


def gen_step():
    return build_assembly().build()
