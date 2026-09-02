"""Keycap Context housing - fit check against the real NeoKey board.

The printable housing plus Adafruit's official CAD model for product 4980, so
clearances are checked against measured board geometry rather than a stand-in.
Switches, keycaps and the XIAO are simplified envelopes. Not a printable part.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from build123d import *
from cadpy.assembly import AssemblyHelper

import keycap_case as kc

NEOKEY_STEP = Path(__file__).resolve().parent / "reference" / "neokey_1x4_qt_4980.step"


def make_neokey():
    """Adafruit 4980, moved from its corner origin to the case datum.

    The transform is baked into each solid: Compound.locate() alone updates the
    wrapper's bounding box but booleans still evaluate the untransformed
    children, which silently turns every clearance check into a no-op.
    """
    board = import_step(str(NEOKEY_STEP))
    at_datum = Location((-kc.pcb_l / 2, -kc.pcb_w / 2, kc.ledge_z))
    return Compound([solid.moved(at_datum) for solid in board.solids()])


def make_switch():
    """MX envelope: 14 mm lower body through the plate, 15.6 mm flange above."""
    with BuildPart() as sw:
        with Locations(Location((0, 0, kc.mx_flange_to_pcb / 2))):
            Box(kc.mx_plate_cut, kc.mx_plate_cut, kc.mx_flange_to_pcb)
        with Locations(Location((0, 0, kc.mx_flange_to_pcb
                                 + (kc.mx_body_h - kc.mx_flange_to_pcb) / 2))):
            Box(kc.mx_body, kc.mx_body, kc.mx_body_h - kc.mx_flange_to_pcb)
    return sw.part


def make_keycap():
    cap_h = 9.5
    with BuildPart() as cap:
        with BuildSketch() as base:
            RectangleRounded(kc.keycap_w, kc.keycap_w, 1.5)
        with BuildSketch(Plane.XY.offset(cap_h)) as top:
            RectangleRounded(kc.keycap_w - 4.0, kc.keycap_w - 4.0, 1.5)
        loft()
    return cap.part


def make_xiao():
    with BuildPart() as xiao:
        Box(kc.xiao_l, kc.xiao_w, kc.xiao_t)
        with Locations(Location((-kc.xiao_l / 2 + kc.xiao_usb_l / 2, 0.0,
                                 kc.xiao_t / 2 + kc.xiao_usb_h / 2))):
            Box(kc.xiao_usb_l, kc.xiao_usb_w, kc.xiao_usb_h)
    return xiao.part


def build_assembly():
    asm = AssemblyHelper("keycap_context_fitcheck")

    asm.add(kc.make_tray(), "tray")
    asm.add(kc.make_plate().locate(Location((0, 0, kc.tray_h))), "plate")
    asm.add(kc.make_xiao_clamp().locate(
        Location((kc.xiao_clamp_x, 0, kc.xiao_top_z))), "xiao_clamp")
    asm.add(make_neokey(), "neokey_1x4_qt")

    for i, x in enumerate(kc.key_x, start=1):
        asm.add(make_switch().locate(Location((x, 0, kc.pcb_top))),
                "mx_switch", f"key{i}")
        asm.add(make_keycap().locate(Location((x, 0, kc.pcb_top + kc.keycap_gap))),
                "keycap", f"key{i}")

    asm.add(make_xiao().locate(Location((kc.xiao_cx, 0,
            kc.xiao_seat_z + kc.xiao_t / 2))), "xiao_sense")
    return asm


def gen_step():
    return build_assembly().build()
