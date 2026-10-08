#!/usr/bin/env python3
"""Build every icon file in Assets from one description of the artwork.

The icon shows one image file at the center with converted copies around it.
The copies are not placed by hand. Each one sits a golden angle (about 137.5
degrees) past the one before it, the same rule a sunflower uses for its seeds,
which spreads them unevenly without any two crowding each other. Their distance
from the center follows equal-area rings, so every copy claims the same share of
the space around the hub, and each copy grows slightly with distance, as the
outer florets of a sunflower do.

Run it from the repository root:

    python3 Scripts/make_icons.py

It needs cairosvg and Pillow. PNG files are written with no text, time, or
color profile chunks, so they carry pixels and nothing else.
"""

import io
import math
import struct
import zlib
from pathlib import Path

import cairosvg
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "Assets"
PNG_DIR = ASSETS / "png"

PHI = (1 + 5 ** 0.5) / 2
GOLDEN_ANGLE = 360 * (1 - 1 / PHI)

FIELD = "#11161C"
PAPER = "#F4F1EA"
FOLD = "#D3CCBE"
SPOKE = "#5A6675"
SKY = "#8EC3E6"
SUN = "#F2B84B"
FAR_RIDGE = "#3E7C8C"
NEAR_RIDGE = "#1F4F5A"
HUB_LABEL = "#D9604C"

# Labels follow the order the copies are placed, so two copies that sit next
# to each other on the spiral never share a hue family.
LABELS = ["#2E9C82", "#E39B2D", "#3F7FD1", "#C9506E", "#7FA83A",
          "#8A4FA8", "#2BA0B5", "#D4B62C", "#B5489E"]

# The one arrangement every file uses. Rotation, the two ring radii, and the
# copy width were found by searching for the placement that keeps every copy
# inside the rounded tile with the widest gap between neighbors. The hub width
# was set by eye, and the golden angle itself is never tuned.
LAYOUT = {"count": 9, "rotation": 142, "inner": 265, "outer": 355, "width": 94, "hub": 207, "spoke": 11}

TILE = (100, 100, 824, 184)


def n(value):
    """Two decimals, trailing zeros dropped, so the SVG text stays short."""
    text = f"{value:.2f}".rstrip("0").rstrip(".")
    return "0" if text == "-0" else text


def placements(spec):
    """Center point and size of each copy, in the order the spiral lays them."""
    inner, outer = spec["inner"], spec["outer"]
    middle = (inner + outer) / 2
    result = []
    for index in range(1, spec["count"] + 1):
        angle = math.radians(spec["rotation"] + index * GOLDEN_ANGLE)
        # Equal-area spacing. The square root keeps the area between
        # consecutive rings constant, which a straight linear step would not.
        radius = math.sqrt(inner ** 2 + (outer ** 2 - inner ** 2) * (index - 0.5) / spec["count"])
        width = spec["width"] * radius / middle
        result.append((512 + radius * math.cos(angle), 512 + radius * math.sin(angle), width, width * 5 / 4))
    return result


def file_outline(x, y, w, h):
    fold, corner = w * 0.26, w * 0.10
    return (f"M{n(x + corner)} {n(y)}H{n(x + w - fold)}L{n(x + w)} {n(y + fold)}"
            f"V{n(y + h - corner)}A{n(corner)} {n(corner)} 0 0 1 {n(x + w - corner)} {n(y + h)}"
            f"H{n(x + corner)}A{n(corner)} {n(corner)} 0 0 1 {n(x)} {n(y + h - corner)}"
            f"V{n(y + corner)}A{n(corner)} {n(corner)} 0 0 1 {n(x + corner)} {n(y)}Z")


def fold_shape(x, y, w):
    fold = w * 0.26
    return (f"M{n(x + w - fold)} {n(y)}V{n(y + fold * 0.7)}"
            f"A{n(fold * 0.3)} {n(fold * 0.3)} 0 0 0 {n(x + w - fold * 0.7)} {n(y + fold)}H{n(x + w)}Z")


def picture_box(x, y, w, h):
    return x + w * 0.15, y + h * 0.22, w * 0.70, h * 0.40


def label_box(x, y, w, h):
    px, _, pw, _ = picture_box(x, y, w, h)
    return px, y + h * 0.73, pw, h * 0.14


def picture(x, y, w, h, clip_id):
    px, py, pw, ph = picture_box(x, y, w, h)
    return (f'<clipPath id="{clip_id}"><rect x="{n(px)}" y="{n(py)}" width="{n(pw)}" height="{n(ph)}" rx="{n(w * 0.06)}"/></clipPath>'
            f'<g clip-path="url(#{clip_id})">'
            f'<rect x="{n(px)}" y="{n(py)}" width="{n(pw)}" height="{n(ph)}" fill="{SKY}"/>'
            f'<circle cx="{n(px + pw * 0.72)}" cy="{n(py + ph * 0.32)}" r="{n(pw * 0.11)}" fill="{SUN}"/>'
            f'<path d="M{n(px)} {n(py + ph * 0.80)}L{n(px + pw * 0.34)} {n(py + ph * 0.42)}L{n(px + pw * 0.60)} {n(py + ph * 0.72)}'
            f'L{n(px + pw * 0.78)} {n(py + ph * 0.54)}L{n(px + pw)} {n(py + ph * 0.76)}V{n(py + ph)}H{n(px)}Z" fill="{FAR_RIDGE}"/>'
            f'<path d="M{n(px)} {n(py + ph * 0.94)}L{n(px + pw * 0.44)} {n(py + ph * 0.64)}L{n(px + pw)} {n(py + ph * 0.92)}'
            f'V{n(py + ph)}H{n(px)}Z" fill="{NEAR_RIDGE}"/></g>')


def image_file(x, y, w, h, label, clip_id, paper_class=""):
    paper_attr = f' class="{paper_class}"' if paper_class else f' fill="{PAPER}"'
    lx, ly, lw, lh = label_box(x, y, w, h)
    return (f'<path d="{file_outline(x, y, w, h)}"{paper_attr}/><path d="{fold_shape(x, y, w)}" fill="{FOLD}"/>'
            f'{picture(x, y, w, h, clip_id)}'
            f'<rect x="{n(lx)}" y="{n(ly)}" width="{n(lw)}" height="{n(lh)}" rx="{n(lh / 2)}" fill="{label}"/>')


def artwork(prefix, paper_class="", spoke_class=""):
    """Spokes first, then the copies, then the hub, so every spoke runs under both ends."""
    spec = LAYOUT
    spokes, copies = [], []
    spoke_attr = f' class="{spoke_class}"' if spoke_class else f' stroke="{SPOKE}"'
    for index, (cx, cy, w, h) in enumerate(placements(spec)):
        spokes.append(f'<path d="M512 512L{n(cx)} {n(cy)}"{spoke_attr} stroke-width="{spec["spoke"]}" stroke-linecap="round"/>')
        copies.append(image_file(cx - w / 2, cy - h / 2, w, h, LABELS[index], f"{prefix}{index}", paper_class))
    hub_w = spec["hub"]
    hub_h = hub_w * 4 / 3
    hub = image_file(512 - hub_w / 2, 512 - hub_h / 2, hub_w, hub_h, HUB_LABEL, f"{prefix}h", paper_class)
    return "".join(spokes) + "".join(copies) + hub


def tile_rect():
    x, y, size, radius = TILE
    return f'<rect x="{x}" y="{y}" width="{size}" height="{size}" rx="{radius}" fill="{FIELD}"/>'


def svg(view_box, body, size, style=""):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="{view_box}">'
            f'{style}{body}</svg>\n')


def app_icon():
    return svg("0 0 1024 1024", tile_rect() + artwork("c"), 1024)


def icon_transparent():
    # The same artwork without its tile, for pages and README rows. Paper on a
    # light page needs an edge to stay visible, and the stroke appears only in
    # light appearance, where the page would otherwise swallow it.
    style = ("<style>.p{fill:" + PAPER + ";stroke:#8C96A3;stroke-width:4}.k{stroke:#7A8592}"
             "@media (prefers-color-scheme:dark){.p{stroke:none}.k{stroke:" + SPOKE + "}}</style>")
    return svg("100 100 824 824", artwork("t", paper_class="p", spoke_class="k"), 824, style)


def icon_for_installer(dark):
    # Installer shows a separate background in each appearance, and the
    # renderer here does not read media queries, so each variant is fixed.
    if dark:
        style = "<style>.p{fill:" + PAPER + "}.k{stroke:" + SPOKE + "}</style>"
    else:
        style = "<style>.p{fill:" + PAPER + ";stroke:#8C96A3;stroke-width:4}.k{stroke:#7A8592}</style>"
    return svg("100 100 824 824", artwork("i", paper_class="p", spoke_class="k"), 824, style)


def icon_tile():
    # A 48 unit tile with a corner radius of 7, matching the tile used across
    # the other projects, with the same artwork scaled into it.
    scale = 48 / TILE[2]
    body = f'<g transform="scale({scale:.6f}) translate(-100 -100)">' + artwork("m") + "</g>"
    return svg("0 0 48 48", f'<rect width="48" height="48" rx="7" fill="{FIELD}"/>' + body, 48)


def rounded_rect(x, y, w, h, r):
    return (f"M{n(x + r)} {n(y)}H{n(x + w - r)}A{n(r)} {n(r)} 0 0 1 {n(x + w)} {n(y + r)}"
            f"V{n(y + h - r)}A{n(r)} {n(r)} 0 0 1 {n(x + w - r)} {n(y + h)}"
            f"H{n(x + r)}A{n(r)} {n(r)} 0 0 1 {n(x)} {n(y + h - r)}V{n(y + r)}A{n(r)} {n(r)} 0 0 1 {n(x + r)} {n(y)}Z")


def box_exit(cx, cy, tx, ty, half_w, half_h):
    """Where a ray from a box center toward a target leaves the box."""
    dx, dy = tx - cx, ty - cy
    scale = min(half_w / abs(dx) if dx else math.inf, half_h / abs(dy) if dy else math.inf)
    return cx + dx * scale, cy + dy * scale


def icon_mono():
    # One color throughout, for places that tint the mark. Each file keeps its
    # picture and label as holes, cut with the even-odd rule, so the shapes
    # stay readable in a single tint. Masks would do the same job, but several
    # renderers ignore them in icons.
    spec = LAYOUT
    hub_w = spec["hub"]
    hub_h = hub_w * 4 / 3
    files = [(512 - hub_w / 2, 512 - hub_h / 2, hub_w, hub_h)]
    spokes = []
    for cx, cy, w, h in placements(spec):
        files.append((cx - w / 2, cy - h / 2, w, h))
        # A spoke stops at both file edges rather than running underneath,
        # since in one color it would otherwise show through the holes.
        sx, sy = box_exit(512, 512, cx, cy, hub_w / 2, hub_h / 2)
        ex, ey = box_exit(cx, cy, 512, 512, w / 2, h / 2)
        spokes.append(f"M{n(sx)} {n(sy)}L{n(ex)} {n(ey)}")
    shapes = []
    for x, y, w, h in files:
        px, py, pw, ph = picture_box(x, y, w, h)
        lx, ly, lw, lh = label_box(x, y, w, h)
        shapes.append(file_outline(x, y, w, h) + rounded_rect(px, py, pw, ph, w * 0.06) + rounded_rect(lx, ly, lw, lh, lh / 2))
    body = (f'<path d="{"".join(spokes)}" fill="none" stroke="currentColor" stroke-opacity="0.55" stroke-width="{spec["spoke"]}"/>'
            f'<path d="{"".join(shapes)}" fill="currentColor" fill-rule="evenodd"/>')
    return svg("100 100 824 824", body, 824)


def strip_png(data):
    """Keep only the chunks that hold the image itself."""
    keep = {b"IHDR", b"PLTE", b"tRNS", b"IDAT", b"IEND"}
    out = [data[:8]]
    position = 8
    while position < len(data):
        length = struct.unpack(">I", data[position:position + 4])[0]
        kind = data[position + 4:position + 8]
        chunk = data[position:position + 12 + length]
        if kind in keep:
            out.append(chunk)
        position += 12 + length
    return b"".join(out)


def write_png(svg_text, size, path):
    raw = cairosvg.svg2png(bytestring=svg_text.encode(), output_width=size, output_height=size)
    buffer = io.BytesIO()
    Image.open(io.BytesIO(raw)).convert("RGBA").save(buffer, format="PNG", optimize=True)
    path.write_bytes(strip_png(buffer.getvalue()))


def write_installer_background(svg_text, path):
    """The icon for the lower left corner of the Installer window, without a tile.

    Installer draws this image at its point size. It is rendered at twice that
    size and marked as 144 dots per inch, the one chunk kept beyond the image
    data, so it stays sharp on a Retina display instead of being scaled up.
    """
    points, icon, margin = 152, 120, 16
    raw = cairosvg.svg2png(bytestring=svg_text.encode(), output_width=icon * 2, output_height=icon * 2)
    canvas = Image.new("RGBA", (points * 2, points * 2), (0, 0, 0, 0))
    canvas.paste(Image.open(io.BytesIO(raw)).convert("RGBA"), (margin * 2, (points - icon - margin) * 2))
    buffer = io.BytesIO()
    canvas.save(buffer, format="PNG", optimize=True)
    data = strip_png(buffer.getvalue())
    # pHYs goes right after IHDR: 5669 pixels per meter is 144 dots per inch.
    body = struct.pack(">IIB", 5669, 5669, 1)
    chunk = struct.pack(">I", len(body)) + b"pHYs" + body + struct.pack(">I", zlib.crc32(b"pHYs" + body))
    header_end = 8 + 12 + struct.unpack(">I", data[8:12])[0]
    path.write_bytes(data[:header_end] + chunk + data[header_end:])


def main():
    PNG_DIR.mkdir(parents=True, exist_ok=True)
    sources = {
        "AppIcon.svg": app_icon(),
        "Icon-Transparent.svg": icon_transparent(),
        "Icon-Tile.svg": icon_tile(),
        "Icon-Mono.svg": icon_mono(),
    }
    for name, text in sources.items():
        (ASSETS / name).write_text(text, encoding="utf-8")
    # Every size comes from the same artwork, so the icon in the Dock, in
    # Finder, and in the README is always the one design.
    for size in (16, 24, 32, 48, 64, 128, 256, 512, 1024):
        write_png(sources["AppIcon.svg"], size, PNG_DIR / f"AppIcon-{size}.png")
    for size in (16, 24, 32, 48):
        write_png(sources["Icon-Tile.svg"], size, PNG_DIR / f"Icon-Tile-{size}.png")
    resources = ROOT / "package" / "resources"
    write_installer_background(icon_for_installer(dark=False), resources / "background.png")
    write_installer_background(icon_for_installer(dark=True), resources / "background-dark.png")
    print(f"Wrote {len(sources)} SVG files and 13 PNG files to {ASSETS.relative_to(ROOT)}, and the installer backgrounds")


if __name__ == "__main__":
    main()
