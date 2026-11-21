#!/usr/bin/env python3
"""Builds the 96x96 mod previews shown in the Better Mods Menu info card.

The game can only load images from inside a mod's resources folder, so this
copies each installed mod's thumb.png/thumb.jpg into
resources/gfx/ui/bettermods/thumbs/<folder>.png (pixel-art friendly downscale).

  python3 tools/make_thumbs.py              # use thumbs found in mod folders
  python3 tools/make_thumbs.py --download   # fetch Workshop covers (preferred over local thumbs)

Run it again after installing new mods; restart the game afterwards.
"""
import argparse
import io
import json
import os
import re
import sys
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

from PIL import Image, ImageEnhance

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODS = os.path.dirname(HERE)
OUT = os.path.join(HERE, "resources", "gfx", "ui", "bettermods", "thumbs")
SIZE = 96  # drawn at half scale: the menu renders at 2x the game resolution
STEAM_API = "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/"


def key_for(folder):
    # Must match bmm/thumbs.lua: m.dir:gsub("[^%w%-_]", "_").
    return re.sub(rb"[^A-Za-z0-9\-_]", b"_", folder.encode("utf-8")).decode("ascii")


def workshop_id(folder, metadata=None):
    if metadata is not None:
        try:
            wid = (ET.parse(metadata).getroot().findtext("id") or "").strip()
            if re.fullmatch(r"[0-9]+", wid) and int(wid) > 0:
                return wid
        except (OSError, ET.ParseError):
            pass
    m = re.search(r"_(\d{6,})$", folder)
    return m.group(1) if m else None


def to_thumb(img):
    img = img.convert("RGBA")
    w, h = img.size
    side = min(w, h)
    img = img.crop(((w - side) // 2, (h - side) // 2, (w - side) // 2 + side, (h - side) // 2 + side))
    img = img.resize((SIZE, SIZE), Image.LANCZOS)
    return ImageEnhance.Sharpness(img).enhance(1.3)


def fetch_previews(ids):
    """Returns {id: image bytes} for Workshop items (public Steam Web API, no key needed)."""
    if not ids:
        return {}
    form = {"itemcount": str(len(ids))}
    for i, wid in enumerate(ids):
        form[f"publishedfileids[{i}]"] = wid
    req = urllib.request.Request(STEAM_API, data=urllib.parse.urlencode(form).encode(), method="POST")
    with urllib.request.urlopen(req, timeout=20) as r:
        details = json.load(r)["response"].get("publishedfiledetails", [])
    out = {}
    for d in details:
        url = d.get("preview_url")
        if not url or d.get("result", 1) != 1:
            continue
        try:
            with urllib.request.urlopen(url, timeout=20) as r:
                out[str(d["publishedfileid"])] = r.read()
        except Exception as e:  # one broken preview shouldn't stop the rest
            print(f"  ! {d['publishedfileid']}: {e}")
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--download", action="store_true", help="fetch Workshop covers, preferred over local thumbs")
    ap.add_argument("--mods-dir", default=MODS, help="installed Isaac mods directory")
    ap.add_argument("--output", default=OUT, help="thumbnail cache directory")
    args = ap.parse_args(argv)

    os.makedirs(args.output, exist_ok=True)
    folders = sorted(f for f in os.listdir(args.mods_dir) if os.path.isfile(os.path.join(args.mods_dir, f, "metadata.xml")))
    missing = []
    workshop = []
    made = 0
    for folder in folders:
        wid = workshop_id(folder, os.path.join(args.mods_dir, folder, "metadata.xml"))
        if wid:
            workshop.append((folder, wid))
        src = None
        for name in ("thumb.png", "thumb.jpg", "thumb.jpeg"):
            p = os.path.join(args.mods_dir, folder, name)
            if os.path.isfile(p):
                src = p
                break
        dst = os.path.join(args.output, key_for(folder) + ".png")
        if src:
            try:
                with Image.open(src) as img:
                    to_thumb(img).save(dst)
                made += 1
                print(f"  + {folder}")
                continue
            except Exception as e:
                print(f"  ! {folder}: {e}")
        if wid:
            missing.append((folder, wid))

    failed = False
    if args.download and workshop:
        print(f"downloading {len(workshop)} Workshop previews...")
        data = {}
        ids = list(dict.fromkeys(w for _, w in workshop))
        for offset in range(0, len(ids), 100):
            try:
                data.update(fetch_previews(ids[offset:offset + 100]))
            except Exception as e:
                print(f"  ! Steam unavailable, keeping cached/local previews: {e}")
                failed = True
        remote_dir = os.path.join(args.output, "workshop")
        os.makedirs(remote_dir, exist_ok=True)
        for folder, wid in workshop:
            if wid in data:
                try:
                    dst = os.path.join(remote_dir, wid + ".png")
                    with Image.open(io.BytesIO(data[wid])) as img:
                        to_thumb(img).save(dst + ".tmp", format="PNG")
                    os.replace(dst + ".tmp", dst)
                    made += 1
                    print(f"  + {folder} (workshop)")
                except Exception as e:
                    print(f"  ! {folder}: {e}")
                    failed = True
            else:
                print(f"  ! {folder}: Workshop preview unavailable; keeping cached/local preview")
                failed = True
    elif missing:
        print(f"{len(missing)} mods have no local thumb (use --download to fetch them from the Workshop)")

    print(f"done: {made} previews in {args.output}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
