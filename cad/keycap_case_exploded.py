"""Keycap Context housing - exploded assembly view.

Review artifact only. Shows the build order along +Z; screws are drawn below
the tray because they enter from underneath. Not a printable part.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from build123d import *
from cadpy.assembly import AssemblyHelper

import keycap_case as kc
import keycap_case_fitcheck as fc

# Explode offsets along Z, in build order.
dz_xiao = 24.0
dz_pcb = 44.0
dz_bezel = 74.0
dz_screw = -20.0

screw_head_d, screw_head_h = 5.5, 3.0
screw_shank_d, screw_shank_l = 3.0, 12.0


def make_screw():
    """M3 x 12 socket cap, origin at the underside of the head."""
    with BuildPart() as screw:
        with Locations(Location((0, 0, screw_head_h / 2))):
            Cylinder(radius=screw_head_d / 2, height=screw_head_h)
        with Locations(Location((0, 0, -screw_shank_l / 2))):
            Cylinder(radius=screw_shank_d / 2, height=screw_shank_l)
    return screw.part


def build_assembly():
    asm = AssemblyHelper("keycap_context_exploded")
    asm.add(kc.make_tray(), "tray")

    xiao_z = kc.xiao_seat_z + kc.xiao_t / 2
    asm.add(fc.make_xiao().locate(Location((kc.xiao_cx, 0, xiao_z + dz_xiao))),
            "xiao_sense")

    asm.add(Compound([so.moved(Location((0, 0, dz_pcb)))
                      for so in fc.make_neokey().solids()]), "neokey_1x4_qt")

    for i, x in enumerate(kc.key_x, start=1):
        asm.add(fc.make_switch().locate(
            Location((x, 0, kc.pcb_top + dz_pcb))),
            "mx_switch", f"key{i}")
        asm.add(fc.make_keycap().locate(
            Location((x, 0, kc.pcb_top + kc.keycap_gap + dz_pcb))),
            "keycap", f"key{i}")

    asm.add(kc.make_plate().locate(Location((0, 0, kc.tray_h + dz_bezel))),
            "plate")

    # Screw head underside seats on the counterbore ceiling at z = cbore depth.
    for (x, y), name in zip(kc.screw_xy,
                            ["front_left", "rear_left", "front_right", "rear_right"]):
        asm.add(make_screw().locate(
            Location((x, y, kc.screw_cbore_h + dz_screw))), "m3x12", name)

    return asm


def gen_step():
    return build_assembly().build()
