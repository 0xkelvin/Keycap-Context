"""Tray, print orientation: as designed, flat on its outer bottom face.

No supports. The 1.5 mm PCB ledge and the 14 mm USB tunnel roof are routine
bridges; the two XIAO tabs cantilever 2.5 mm and will droop slightly, which the
0.3 mm clearance above the board absorbs.
"""

from _orient import kc, on_bed


def gen_step():
    return on_bed(kc.make_tray())
