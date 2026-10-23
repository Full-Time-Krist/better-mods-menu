#!/usr/bin/env python3
"""Generates the hand-drawn UI atlas + anm2 files used by Better Mods Menu.

Run from anywhere:  python3 tools/build_gfx.py
Output: resources/gfx/ui/bettermods/{icons.png,icons.anm2,pixel.png,pixel.anm2,thumb.anm2}
"""
import os
import random

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "resources", "gfx", "ui", "bettermods")
INK = (30, 24, 26, 255)
CELL = 16

# Icon frame order (keep in sync with ICON in bmm/ui.lua)
ICONS = ["box", "box_on", "star", "warn", "dot", "glass", "arrow", "box_x"]

rnd = random.Random(1337)


def wobble_line(d, p0, p1, width=1):
    """Ink line with a tiny hand-drawn wobble in the middle."""
    (x0, y0), (x1, y1) = p0, p1
    mx = (x0 + x1) / 2 + rnd.choice([-0.5, 0, 0.5])
    my = (y0 + y1) / 2 + rnd.choice([-0.5, 0, 0.5])
    d.line([(x0, y0), (mx, my), (x1, y1)], fill=INK, width=width)


def box(d, ox, oy):
    # 11x11 sketchy square, slightly uneven corners like the vanilla UI
    a, b, c, e = (ox + 2, oy + 3), (ox + 13, oy + 2), (ox + 13, oy + 13), (ox + 3, oy + 13)
    wobble_line(d, a, b)
    wobble_line(d, b, c)
    wobble_line(d, c, e)
    wobble_line(d, e, a)


def draw_icon(d, name, ox, oy):
    if name == "box":
        box(d, ox, oy)
    elif name == "box_on":
        box(d, ox, oy)
        # bold check mark overshooting the box, like a quick pen stroke
        d.line([(ox + 4, oy + 7), (ox + 7, oy + 11), (ox + 15, oy + 1)], fill=INK, width=2)
    elif name == "box_x":
        box(d, ox, oy)
        d.line([(ox + 5, oy + 5), (ox + 11, oy + 11)], fill=INK, width=1)
        d.line([(ox + 11, oy + 5), (ox + 5, oy + 11)], fill=INK, width=1)
    elif name == "star":
        pts = [(8, 1), (10, 6), (15, 6), (11, 9), (13, 14), (8, 11), (3, 14), (5, 9), (1, 6), (6, 6)]
        d.polygon([(ox + x, oy + y) for x, y in pts], fill=INK)
    elif name == "warn":
        d.polygon([(ox + 8, oy + 1), (ox + 15, oy + 14), (ox + 1, oy + 14)], outline=INK, fill=None)
        d.line([(ox + 8, oy + 5), (ox + 8, oy + 9)], fill=INK, width=2)
        d.point([(ox + 8, oy + 12), (ox + 7, oy + 12)], fill=INK)
    elif name == "dot":
        d.ellipse([ox + 6, oy + 6, ox + 10, oy + 10], fill=INK)
    elif name == "glass":
        d.ellipse([ox + 2, oy + 2, ox + 10, oy + 10], outline=INK, width=2)
        d.line([(ox + 9, oy + 9), (ox + 14, oy + 14)], fill=INK, width=2)
    elif name == "arrow":
        d.line([(ox + 2, oy + 8), (ox + 13, oy + 8)], fill=INK, width=2)
        d.line([(ox + 9, oy + 4), (ox + 13, oy + 8), (ox + 9, oy + 12)], fill=INK, width=2)


FRAME = ('<Frame XPosition="0" YPosition="0" XPivot="{px}" YPivot="{py}" XCrop="{cx}" YCrop="{cy}" '
         'Width="{w}" Height="{h}" XScale="100" YScale="100" Delay="1" Visible="true" RedTint="255" '
         'GreenTint="255" BlueTint="255" AlphaTint="255" RedOffset="0" GreenOffset="0" BlueOffset="0" '
         'Rotation="0" Interpolated="false" />')


def anm2(sheet, anims, default):
    """anims: list of (name, [frame dicts])"""
    out = ['<AnimatedActor>',
           '  <Info CreatedBy="Better Mods Menu" CreatedOn="10/14/2026 12:00:00 PM" Version="1" Fps="30" />',
           '  <Content>',
           '    <Spritesheets>',
           f'      <Spritesheet Path="{sheet}" Id="0" />',
           '    </Spritesheets>',
           '    <Layers>',
           '      <Layer Name="main" Id="0" SpritesheetId="0" />',
           '    </Layers>',
           '    <Nulls />',
           '    <Events />',
           '  </Content>',
           f'  <Animations DefaultAnimation="{default}">']
    for name, frames in anims:
        out.append(f'    <Animation Name="{name}" FrameNum="{len(frames)}" Loop="false">')
        out.append('      <RootAnimation>')
        out.append('        <Frame XPosition="0" YPosition="0" Delay="{}" Visible="true" XScale="100" YScale="100" '
                   'RedTint="255" GreenTint="255" BlueTint="255" AlphaTint="255" RedOffset="0" GreenOffset="0" '
                   'BlueOffset="0" Rotation="0" Interpolated="false" />'.format(len(frames)))
        out.append('      </RootAnimation>')
        out.append('      <LayerAnimations>')
        out.append('        <LayerAnimation LayerId="0" Visible="true">')
        for f in frames:
            out.append('          ' + FRAME.format(**f))
        out.append('        </LayerAnimation>')
        out.append('      </LayerAnimations>')
        out.append('      <NullAnimations />')
        out.append('      <Triggers />')
        out.append('    </Animation>')
    out.append('  </Animations>')
    out.append('</AnimatedActor>')
    return "\n".join(out) + "\n"


PAPER = (233, 218, 224, 255)    # vanilla menu paper texture colour
EDGE = (104, 97, 100, 255)      # paper outline
EDGE_DARK = (62, 56, 58, 255)
SHADOW = (40, 30, 32, 90)
CARD_W, CARD_H = 166, 146


def torn_edge(length, rng, amp=2):
    """Random walk used for the torn paper borders (values 0..amp)."""
    out, v = [], rng.randint(0, amp)
    for _ in range(length):
        if rng.random() < 0.35:
            v = max(0, min(amp, v + rng.choice([-1, 1])))
        out.append(v)
    return out


def paper_card(w, h, seed, smudge=True):
    """Straight note paper in the style of the vanilla menu notes."""
    rng = random.Random(seed)
    pad = 4  # room for the shadow
    img = Image.new("RGBA", (w + pad, h + pad), (0, 0, 0, 0))
    top, bottom = torn_edge(w, rng), torn_edge(w, rng, 3)
    left, right = torn_edge(h, rng), torn_edge(h, rng)

    def inside(x, y):
        return (top[x] <= y <= h - 1 - bottom[x]) and (left[y] <= x <= w - 1 - right[y])

    px = img.load()
    # shadow first (offset down-right)
    for y in range(h):
        for x in range(w):
            if inside(x, y):
                px[x + 3, y + 3] = SHADOW
    for y in range(h):
        for x in range(w):
            if inside(x, y):
                px[x, y] = PAPER
    # 2px outline: dark outer pixel, softer inner pixel
    for y in range(h):
        for x in range(w):
            if not inside(x, y):
                continue
            n1 = any(not (0 <= x + dx < w and 0 <= y + dy < h and inside(x + dx, y + dy))
                     for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
            if n1:
                px[x, y] = EDGE_DARK
                continue
            n2 = any(not (0 <= x + dx < w and 0 <= y + dy < h and inside(x + dx, y + dy))
                     for dx, dy in ((2, 0), (-2, 0), (0, 2), (0, -2)))
            if n2:
                px[x, y] = EDGE
    # a faint grey smudge like the ones on vanilla notes
    if smudge:
        d = ImageDraw.Draw(img)
        sx, sy = int(w * 0.84), int(h * 0.86)
        for _ in range(10):
            r = rng.randint(2, 5)
            cx, cy = sx + rng.randint(-7, 7), sy + rng.randint(-5, 5)
            d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(222, 208, 214, 255))
    return img


def mod_icon(path):
    """512x512 Workshop/thumbnail icon: a mods-list page with checkboxes, 8x pixel art."""
    S = 64
    rng = random.Random(7)
    img = Image.new("RGBA", (S, S), (204, 191, 187, 255))
    card = paper_card(46, 54, 99, smudge=False)
    img.alpha_composite(card, (5, 4))
    d = ImageDraw.Draw(img)
    ink = INK
    # "MODS" title scribble
    d.rectangle([14, 9, 41, 12], fill=ink)
    d.line([(12, 15), (44, 15)], fill=(120, 112, 115, 255))
    rows = [(19, True), (27, False), (35, True), (43, False)]
    for y, on in rows:
        d.rectangle([11, y, 16, y + 5], outline=ink)
        if on:
            d.line([(12, y + 2), (13, y + 4), (18, y - 2)], fill=ink, width=2)
        n = rng.randint(14, 24)
        col = ink if on else (150, 140, 144, 255)
        d.line([(20, y + 3), (20 + n, y + 3)], fill=col, width=2)
    # star on the first row, cursor arrow on the third
    d.polygon([(45, 18), (46, 21), (49, 21), (47, 23), (48, 26), (45, 24), (42, 26), (43, 23), (41, 21), (44, 21)], fill=ink)
    d.polygon([(6, 35), (6, 41), (9, 38)], fill=ink)
    # magnifying glass over the corner
    d.ellipse([40, 38, 54, 52], outline=ink, width=3)
    d.ellipse([43, 41, 51, 49], fill=(240, 232, 236, 255))
    d.line([(52, 50), (59, 57)], fill=ink, width=4)
    img.resize((512, 512), Image.NEAREST).save(path)


def main():
    os.makedirs(OUT, exist_ok=True)

    paper_card(CARD_W, CARD_H, 5).save(os.path.join(OUT, "card.png"))
    with open(os.path.join(OUT, "card.anm2"), "w") as f:
        f.write(anm2("card.png", [("Idle", [dict(px=0, py=0, cx=0, cy=0, w=CARD_W + 4, h=CARD_H + 4)])], "Idle"))
    mod_icon(os.path.join(ROOT, "thumb.png"))

    atlas = Image.new("RGBA", (CELL * len(ICONS), CELL), (0, 0, 0, 0))
    d = ImageDraw.Draw(atlas)
    for i, name in enumerate(ICONS):
        draw_icon(d, name, i * CELL, 0)
    atlas.save(os.path.join(OUT, "icons.png"))
    frames = [dict(px=0, py=0, cx=i * CELL, cy=0, w=CELL, h=CELL) for i in range(len(ICONS))]
    with open(os.path.join(OUT, "icons.anm2"), "w") as f:
        f.write(anm2("icons.png", [("Icon", frames)], "Icon"))

    Image.new("RGBA", (4, 4), (255, 255, 255, 255)).save(os.path.join(OUT, "pixel.png"))
    with open(os.path.join(OUT, "pixel.anm2"), "w") as f:
        f.write(anm2("pixel.png", [("Idle", [dict(px=0, py=0, cx=0, cy=0, w=1, h=1)])], "Idle"))

    # thumbnails get swapped in at runtime with ReplaceSpritesheet
    with open(os.path.join(OUT, "thumb.anm2"), "w") as f:
        f.write(anm2("pixel.png", [("Idle", [dict(px=0, py=0, cx=0, cy=0, w=96, h=96)]),
                                   # any-size image (a mod's own thumb.png), measured and scaled at runtime
                                   ("Big", [dict(px=0, py=0, cx=0, cy=0, w=2048, h=2048)])], "Idle"))
    print("wrote", OUT)


if __name__ == "__main__":
    main()
