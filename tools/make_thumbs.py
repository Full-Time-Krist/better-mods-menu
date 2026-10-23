#!/usr/bin/env python3
"""Builds the 96x96 mod previews shown in the Better Mods Menu info card.

The game can only load images from inside a mod's resources folder, so this
copies each installed mod's thumb.png/thumb.jpg into
resources/gfx/ui/bettermods/thumbs/<folder>.png (pixel-art friendly downscale).

  python3 tools/make_thumbs.py              # use thumbs found in mod folders
  python3 tools/make_thumbs.py --download   # also fetch missing Workshop previews from Steam

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

from PIL import Image, ImageEnhance

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODS = os.path.dirname(HERE)
OUT = os.path.join(HERE, "resources", "gfx", "ui", "bettermods", "thumbs")
SIZE = 96  # drawn at half scale: the menu renders at 2x the game resolution
STEAM_API = "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/"


def key_for(folder):
    # must match thumbPath() in bmm/ui.lua: m.dir:gsub("[^%w%-_]", "_")
    return re.sub(r"[^A-Za-z0-9\-_]", "_", folder)


def workshop_id(folder):
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
        if not url:
            continue
        try:
            with urllib.request.urlopen(url, timeout=20) as r:
                out[d["publishedfileid"]] = r.read()
        except Exception as e:  # one broken preview shouldn't stop the rest
            print(f"  ! {d['publishedfileid']}: {e}")
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--download", action="store_true", help="fetch missing Workshop previews from Steam")
    args = ap.parse_args()

    os.makedirs(OUT, exist_ok=True)
    folders = sorted(f for f in os.listdir(MODS) if os.path.isfile(os.path.join(MODS, f, "metadata.xml")))
    missing = []
    made = 0
    for folder in folders:
        src = None
        for name in ("thumb.png", "thumb.jpg", "thumb.jpeg"):
            p = os.path.join(MODS, folder, name)
            if os.path.isfile(p):
                src = p
                break
        dst = os.path.join(OUT, key_for(folder) + ".png")
        if src:
            try:
                to_thumb(Image.open(src)).save(dst)
                made += 1
                print(f"  + {folder}")
                continue
            except Exception as e:
                print(f"  ! {folder}: {e}")
        wid = workshop_id(folder)
        if wid:
            missing.append((folder, wid))

    if args.download and missing:
        print(f"downloading {len(missing)} Workshop previews...")
        data = fetch_previews([w for _, w in missing])
        for folder, wid in missing:
            if wid in data:
                try:
                    to_thumb(Image.open(io.BytesIO(data[wid]))).save(os.path.join(OUT, key_for(folder) + ".png"))
                    made += 1
                    print(f"  + {folder} (workshop)")
                except Exception as e:
                    print(f"  ! {folder}: {e}")
    elif missing:
        print(f"{len(missing)} mods have no local thumb (use --download to fetch them from the Workshop)")

    print(f"done: {made} previews in {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
