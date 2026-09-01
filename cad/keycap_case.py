"""Keycap Context - two-piece desktop housing (tray + plate).

Houses an Adafruit NeoKey 1x4 QT I2C keypad above a Seeed XIAO Sense, with the
XIAO tucked into the cavity underneath so the case keeps the keypad's footprint.

Board geometry is taken from Adafruit's official CAD model for product 4980
(cad/reference/neokey_1x4_qt_4980.step), not from the product page - the listed
76.5 x 21.5 x 4.6 mm is the packaged product, while the PCB is 76.2 x 21.59 x
1.57 mm. The NeoKey carries Kailh hot-swap sockets, so this is built as a real
keyboard plate: switches drop through 14 mm plate cutouts and their pins press
into the sockets, which is what ties the PCB to the plate.

Coordinate convention
---------------------
Origin: footprint centre of the assembled case, on the outer bottom face.
    +X  along the key row
    +Y  towards the rear of the case
    +Z  up; Z = 0 is the desk surface
Units: millimetres.

Datum stack (Z, from the desk up)
---------------------------------
    0.00    outer bottom face
    2.00    cavity floor                (XIAO compartment starts)
   11.00    PCB seating plane           (ledge + locating pegs)
   12.57    NeoKey PCB top face         <- the datum everything above keys off
   12.00    tray rim                    (plate frame seats here)
   15.53    tallest part on the PCB     (STEMMA QT, 2.96 mm)
   16.07    plate underside             (0.54 mm clear of the connectors)
   17.57    plate top = PCB + 5.00      (MX switch flange lands here)
"""

import os

from build123d import *
from cadpy.assembly import AssemblyHelper

# ------------------------------------------- NeoKey 1x4 QT (measured, 4980)
pcb_l, pcb_w, pcb_t = 76.2, 21.59, 1.57
pcb_corner_r = 1.27
pcb_comp_h = 2.96                        # STEMMA QT, tallest thing on top
key_pitch, key_count = 19.05, 4
mount_dx, mount_dy = 19.05, 8.255        # M2.5 holes, from board centre
mount_hole_d = 2.5

# Cherry MX
mx_body = 15.6                           # flange that lands on the plate
mx_plate_cut = 14.0                      # standard plate cutout
mx_flange_to_pcb = 5.0                   # sets the plate plane
mx_body_h = 11.6
keycap_w, keycap_gap = 18.0, 10.5

# Seeed XIAO Sense
xiao_l, xiao_w, xiao_t = 21.0, 17.8, 1.0
xiao_usb_l, xiao_usb_w, xiao_usb_h = 9.0, 8.9, 3.2

# --------------------------------------------------------------------- shell
outer_l, outer_w = 94.0, 32.0
corner_r = 2.0

floor_t = 2.0
ledge_z = 11.0                           # PCB underside seats here
ledge_w = 1.5
pcb_clr = 0.4                            # per side, PCB to bay wall

pcb_top = ledge_z + pcb_t                # 12.57
plate_t = 1.5                            # MX clips latch under 1.5 mm
case_h = pcb_top + mx_flange_to_pcb      # 17.57
tray_h = 12.0                            # plate frame seats on the tray rim
plate_frame_t = case_h - tray_h          # 5.57
relief_depth = plate_frame_t - plate_t   # 4.07

bay_l, bay_w = pcb_l + 2 * pcb_clr, pcb_w + 2 * pcb_clr
bay_r = pcb_corner_r + pcb_clr
cav_l, cav_w = bay_l - 2 * ledge_w, bay_w - 2 * ledge_w
cav_r = 1.0   # the XIAO's square corners stop on this fillet, not on the flat wall

# Locating pegs use the two mounting holes at +X; the XIAO occupies the -X pair.
peg_d, peg_h = mount_hole_d - 0.2, 1.4
peg_boss_d = 5.0
peg_xy = [(mount_dx, mount_dy), (mount_dx, -mount_dy)]

# USB-C tunnel through the -X end wall.
usb_w, usb_h, usb_z = 14.0, 8.0, 6.0
usb_x_out = -outer_l / 2 - 1.0
usb_x_in = -cav_l / 2 + 0.75

# Register between the parts: a lip rises from the tray rim and the plate has a
# matching rebate, so location comes from the parts, not from the screws.
lip_h, lip_w = 1.5, 1.2
plate_rebate_w = lip_w + 0.1             # 0.1 mm clearance per side

# Hold-down ribs on the plate underside. Both long edges of the NeoKey are clear
# of components for its full length, so the plate clamps the board there against
# the ledge. Sized to stop just short so a tall print cannot unseat the plate.
rib_y0, rib_y1 = 8.4, 10.4
rib_len, rib_gap = 76.0, 0.1

# Pass-through for wires soldered to the NeoKey's top-side pads: the 0.4 mm gap
# at the board edge will not clear a wire, so the channel cuts outboard of it.
notch_x0, notch_x1 = -34.0, -28.0
notch_y0, notch_y1 = -13.0, -9.0
notch_z0 = 9.0

# XIAO retention. The board has no mounting holes and only 0.8 mm/side of
# clearance, so there is nowhere to put a printed side flexure, and a
# floor-anchored snap would need ~25% strain over its 2.2 mm length. Instead the
# board is trapped mechanically: two fixed tabs at the wall end, a screwed clamp
# at the other. Plugging a USB-C cable pushes the board +X into the clamp;
# unplugging pulls it -X into the cavity end wall. Both are solid.
xiao_pad_t = 1.2
xiao_rail_y = 9.1                        # local pocket half-width -> 0.2 mm/side
xiao_rail_x1 = -14.0
xiao_tab_y0, xiao_tab_y1 = 5.5, 8.5      # clear board corners, outboard of the USB shell
xiao_tab_reach, xiao_tab_gap, xiao_tab_t = 2.5, 0.3, 1.2
xiao_clamp_x = -12.0
xiao_clamp_boss_d, xiao_clamp_pilot_d, xiao_clamp_pilot_h = 4.0, 1.7, 3.5
xiao_clamp_l, xiao_clamp_w, xiao_clamp_t = 10.0, 10.0, 2.5
xiao_clamp_lip_x0, xiao_clamp_lip_x1 = -3.7, -2.3   # clamp-local, blocks +X travel
xiao_face_x = -cav_l / 2 + 0.15
xiao_cx = xiao_face_x + xiao_l / 2
xiao_pad_w = xiao_w + 0.8
xiao_stop_t, xiao_stop_h = 2.0, 4.0

# Fasteners: M3 x 12 socket cap, entering from below.
screw_x, screw_y = 42.5, 11.5
screw_clear_d, screw_cbore_d, screw_cbore_h = 3.4, 6.0, 4.5
screw_pilot_d, screw_pilot_h = 2.6, 4.7

foot_d, foot_depth = 10.0, 0.5
foot_x, foot_y = 33.0, 9.5

edge_chamfer, face_chamfer = 0.8, 0.6

xiao_seat_z = floor_t + xiao_pad_t       # XIAO underside
xiao_top_z = xiao_seat_z + xiao_t        # XIAO top face
xiao_tab_z0 = xiao_top_z + xiao_tab_gap  # tab underside
xiao_clamp_seat_z = xiao_top_z - 0.1     # boss top, so the clamp bites the board

pcb_top_local = pcb_top - tray_h         # PCB top, in plate-local Z
rib_bottom = pcb_top_local + rib_gap
rib_h = relief_depth - rib_bottom

screw_xy = [(sx * screw_x, sy * screw_y) for sx in (-1, 1) for sy in (-1, 1)]
foot_xy = [(sx * foot_x, sy * foot_y) for sx in (-1, 1) for sy in (-1, 1)]
key_x = [(i - (key_count - 1) / 2) * key_pitch for i in range(key_count)]


# ---------------------------------------------------------------- colourways
# Filament colours for the printed parts. The tray and plate print separately,
# so two-tone costs nothing. Pick with KEYCAP_COLOURWAY=<name>.
# The clamp is internal and never visible; it takes the tray colour.
COLOURWAYS = {
    "graphite": {                        # near-monochrome, lets the RGB carry
        "tray":  "#2E3238",
        "plate": "#40464E",
        "note":  "charcoal body, graphite plate",
    },
    "bone": {                            # light and warm
        "tray":  "#E5E0D6",
        "plate": "#CFC7B8",
        "note":  "bone body, warm grey plate",
    },
    "slate_sand": {                      # two-tone, visible contrast
        "tray":  "#343A40",
        "plate": "#C4B79C",
        "note":  "slate body, sand plate",
    },
    "ink": {                             # flat black, maximum RGB contrast
        "tray":  "#1B1E22",
        "plate": "#1B1E22",
        "note":  "all black",
    },
}
COLOURWAY = os.environ.get("KEYCAP_COLOURWAY", "graphite")


def _colour(part):
    scheme = COLOURWAYS.get(COLOURWAY, COLOURWAYS["graphite"])
    return Color(scheme[part])


def _blind_cut(depth, over=1.0):
    """Centre/height for a tool cutting z=0 down to -over and up to `depth`."""
    return (depth - over) / 2, depth + over


def make_tray():
    """Bottom tray: XIAO cavity, PCB ledge + locating pegs, USB tunnel."""
    with BuildPart() as tray:
        with BuildSketch() as body:
            RectangleRounded(outer_l, outer_w, corner_r)
        extrude(amount=tray_h)

        chamfer(tray.faces().sort_by(Axis.Z)[0].edges(), length=edge_chamfer)

        # Register lip: the outer band of the wall carries on past the seating
        # rim and surrounds the plate.
        with BuildSketch(Plane.XY.offset(tray_h)) as lip:
            RectangleRounded(outer_l, outer_w, corner_r)
            RectangleRounded(outer_l - 2 * lip_w, outer_w - 2 * lip_w,
                             max(0.2, corner_r - lip_w), mode=Mode.SUBTRACT)
        extrude(amount=lip_h)

        # PCB bay, open through the rim and the lip.
        with BuildSketch(Plane.XY.offset(ledge_z)) as bay:
            RectangleRounded(bay_l, bay_w, bay_r)
        extrude(amount=tray_h + lip_h - ledge_z + 1.0, mode=Mode.SUBTRACT)

        # Cavity for the XIAO and the interconnect wires; leaves the ledge.
        with BuildSketch(Plane.XY.offset(floor_t)) as cavity:
            RectangleRounded(cav_l, cav_w, cav_r)
        extrude(amount=ledge_z - floor_t, mode=Mode.SUBTRACT)

        # USB-C tunnel through the end wall, on the XIAO connector centreline.
        with Locations(Location(((usb_x_out + usb_x_in) / 2, 0.0, usb_z))):
            Box(usb_x_in - usb_x_out, usb_w, usb_h, mode=Mode.SUBTRACT)

        # Wire pass-through, outboard of the PCB edge and down into the cavity.
        with Locations(Location(((notch_x0 + notch_x1) / 2, (notch_y0 + notch_y1) / 2,
                                 (notch_z0 + tray_h + lip_h + 1.0) / 2))):
            Box(notch_x1 - notch_x0, notch_y1 - notch_y0,
                tray_h + lip_h + 1.0 - notch_z0, mode=Mode.SUBTRACT)

        # Screw columns: clearance through, counterbore from below.
        with Locations(*[Location((x, y, tray_h / 2)) for x, y in screw_xy]):
            Cylinder(radius=screw_clear_d / 2, height=tray_h + 2.0, mode=Mode.SUBTRACT)
        cz, ch = _blind_cut(screw_cbore_h)
        with Locations(*[Location((x, y, cz)) for x, y in screw_xy]):
            Cylinder(radius=screw_cbore_d / 2, height=ch, mode=Mode.SUBTRACT)

        fz, fh = _blind_cut(foot_depth)
        with Locations(*[Location((x, y, fz)) for x, y in foot_xy]):
            Cylinder(radius=foot_d / 2, height=fh, mode=Mode.SUBTRACT)

        # XIAO nest: pad lifts the board so its USB-C lines up with the tunnel,
        # rib stops it sliding away from the port.
        with Locations(Location((xiao_cx, 0.0, floor_t + xiao_pad_t / 2))):
            Box(xiao_l, xiao_pad_w, xiao_pad_t, mode=Mode.ADD)
        # Rails narrowing the pocket to 0.2 mm/side so the board cannot shift in Y.
        rail_l = xiao_rail_x1 - (-cav_l / 2)
        for sy in (-1, 1):
            with Locations(Location((-cav_l / 2 + rail_l / 2,
                                     sy * (xiao_rail_y + cav_w / 2) / 2,
                                     (floor_t + 5.0) / 2))):
                Box(rail_l, cav_w / 2 - xiao_rail_y, 5.0 - floor_t, mode=Mode.ADD)

        # Fixed tabs at the wall end: the board tilts in underneath them.
        for sy in (-1, 1):
            with Locations(Location((-cav_l / 2 - 0.5 + (xiao_tab_reach + 0.5) / 2,
                                     sy * (xiao_tab_y0 + xiao_tab_y1) / 2,
                                     xiao_tab_z0 + xiao_tab_t / 2))):
                Box(xiao_tab_reach + 0.5, xiao_tab_y1 - xiao_tab_y0,
                    xiao_tab_t, mode=Mode.ADD)

        # Boss for the clamp screw that holds the free end down.
        with Locations(Location((xiao_clamp_x, 0.0,
                                 (floor_t + xiao_clamp_seat_z) / 2))):
            Cylinder(radius=xiao_clamp_boss_d / 2,
                     height=xiao_clamp_seat_z - floor_t, mode=Mode.ADD)
        with Locations(Location((xiao_clamp_x, 0.0,
                                 xiao_clamp_seat_z - xiao_clamp_pilot_h / 2))):
            Cylinder(radius=xiao_clamp_pilot_d / 2,
                     height=xiao_clamp_pilot_h, mode=Mode.SUBTRACT)

        # Bosses + pegs into the NeoKey's own M2.5 mounting holes: these locate
        # the board in XY so it cannot drift on the bay clearance.
        with Locations(*[Location((x, y, (floor_t + ledge_z) / 2)) for x, y in peg_xy]):
            Cylinder(radius=peg_boss_d / 2, height=ledge_z - floor_t, mode=Mode.ADD)
        with Locations(*[Location((x, y, ledge_z + peg_h / 2)) for x, y in peg_xy]):
            Cylinder(radius=peg_d / 2, height=peg_h, mode=Mode.ADD)

    return tray.part


def make_plate():
    """Top switch plate, modelled with Z = 0 at its underside (the tray rim)."""
    with BuildPart() as plate:
        with BuildSketch() as body:
            RectangleRounded(outer_l, outer_w, corner_r)
        extrude(amount=plate_frame_t)

        # Rebate that receives the tray's register lip.
        with BuildSketch(Plane.XY.offset(-1.0)) as rebate:
            RectangleRounded(outer_l, outer_w, corner_r)
            RectangleRounded(outer_l - 2 * plate_rebate_w, outer_w - 2 * plate_rebate_w,
                             max(0.2, corner_r - plate_rebate_w), mode=Mode.SUBTRACT)
        extrude(amount=lip_h + 1.0, mode=Mode.SUBTRACT)

        # Relief that clears every top-side component on the NeoKey.
        with BuildSketch(Plane.XY.offset(-1.0)) as relief:
            RectangleRounded(bay_l, bay_w, bay_r)
        extrude(amount=relief_depth + 1.0, mode=Mode.SUBTRACT)

        # Standard 14 mm MX plate cutouts; the switch flange lands on the top.
        with BuildSketch(Plane.XY.offset(relief_depth)) as cuts:
            with Locations(*[(x, 0.0) for x in key_x]):
                Rectangle(mx_plate_cut, mx_plate_cut)
        extrude(amount=plate_t + 1.0, mode=Mode.SUBTRACT)

        # Hold-down ribs: clamp the NeoKey's clear edge strips onto the ledge.
        with Locations(*[Location((0.0, sy * (rib_y0 + rib_y1) / 2,
                                   rib_bottom + rib_h / 2)) for sy in (-1, 1)]):
            Box(rib_len, rib_y1 - rib_y0, rib_h, mode=Mode.ADD)

        cz, ch = _blind_cut(screw_pilot_h)
        with Locations(*[Location((x, y, cz)) for x, y in screw_xy]):
            Cylinder(radius=screw_pilot_d / 2, height=ch, mode=Mode.SUBTRACT)

        chamfer(plate.faces().sort_by(Axis.Z)[-1].edges(), length=face_chamfer)

    return plate.part


def make_xiao_clamp():
    """Clamp bar over the XIAO's free end. Origin at its own footprint centre,
    Z = 0 at the face that lands on the board."""
    with BuildPart() as clamp:
        with Locations(Location((0, 0, xiao_clamp_t / 2))):
            Box(xiao_clamp_l, xiao_clamp_w, xiao_clamp_t)
        # Lip dropping past the board edge: this is what takes the plug-in load.
        with Locations(Location(((xiao_clamp_lip_x0 + xiao_clamp_lip_x1) / 2, 0.0,
                                 -(xiao_t + 0.1) / 2))):
            Box(xiao_clamp_lip_x1 - xiao_clamp_lip_x0, xiao_clamp_w,
                xiao_t + 0.1, mode=Mode.ADD)
        Cylinder(radius=(xiao_clamp_pilot_d + 0.5) / 2, height=xiao_clamp_t * 3,
                 mode=Mode.SUBTRACT)
    return clamp.part


def build_assembly():
    asm = AssemblyHelper("keycap_context_housing")
    tray = asm.add(make_tray(), "tray", color=_colour("tray"))
    plate = asm.add(make_plate(), "plate", color=_colour("plate"))
    asm.add(make_xiao_clamp().locate(
        Location((xiao_clamp_x, 0, xiao_top_z))), "xiao_clamp",
        color=_colour("tray"))

    seat = asm.rigid_frame(tray, "plate_seat", Location((0, 0, tray_h)))
    underside = asm.rigid_frame(plate, "underside", Location((0, 0, 0)))
    asm.face_to_face(seat, underside)
    return asm


def gen_step():
    return build_assembly().build()
