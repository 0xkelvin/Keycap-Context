"""XIAO clamp bar, print orientation: clamping face DOWN, lip upward.

Printed as modelled the lip would hang below the body and need support.
"""

from _orient import kc, on_bed


def gen_step():
    return on_bed(kc.make_xiao_clamp(), flip=True)
