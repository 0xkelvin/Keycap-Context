"""Plate, print orientation: top face DOWN on the bed.

This puts the visible surface against the build plate and turns every internal
feature (relief, hold-down ribs, lip rebate) into an upward-facing pocket, so it
prints without supports. Enable elephant-foot compensation: the 14 mm switch
cutouts are in the first layers and the MX clips latch on that dimension.
"""

from _orient import kc, on_bed


def gen_step():
    return on_bed(kc.make_plate(), flip=True)
