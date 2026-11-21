#!/usr/bin/env python3
"""Builds a clean copy of the mod for a Steam Workshop upload.

  python3 tools/make_release.py            # -> dist/better-mods-menu
  python3 tools/make_release.py --out DIR

Only files tracked by git go in, minus developer-only ones (tests, gfx generator).
Covers of other mods (generated locally by make_thumbs.py) are never included:
they are other authors' pictures and are untracked anyway.
"""
import argparse
import os
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKIP_PREFIXES = ("tests/", "tools/build_gfx.py", "tools/make_release.py", ".gitignore")
OWN_THUMB = "resources/gfx/ui/bettermods/thumbs/better-mods-menu.png"


def tracked_files():
    out = subprocess.run(["git", "ls-files", "-z"], cwd=ROOT, check=True, capture_output=True).stdout
    return [f for f in out.decode().split("\0") if f]


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=os.path.join(ROOT, "dist", "better-mods-menu"))
    args = ap.parse_args(argv)

    files = [f for f in tracked_files() if not f.startswith(SKIP_PREFIXES)]
    # new files must be committed (or at least added) to ship
    for f in files:
        if not os.path.isfile(os.path.join(ROOT, f)):
            sys.exit(f"missing on disk: {f}")
    thumbs = [f for f in files if "/thumbs/" in f]
    if thumbs != [OWN_THUMB]:
        sys.exit(f"unexpected covers in the release: {thumbs}")

    if os.path.isdir(args.out):
        shutil.rmtree(args.out)
    for f in files:
        dst = os.path.join(args.out, f)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(os.path.join(ROOT, f), dst)

    meta = ET.parse(os.path.join(args.out, "metadata.xml")).getroot()
    size = sum(os.path.getsize(os.path.join(args.out, f)) for f in files)
    print(f"Better Mods Menu {meta.findtext('version')} (Workshop {meta.findtext('id')}): "
          f"{len(files)} files, {size // 1024} KB -> {args.out}")


if __name__ == "__main__":
    main()
