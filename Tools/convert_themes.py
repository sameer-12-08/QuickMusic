#!/usr/bin/env python3
"""Builds Sources/QuickFLAC/Resources/themes.json from Monkeytype's theme data.

Run it from the project folder (needs internet, Python 3, no extra packages):

    python3 Tools/convert_themes.py          # normal: reads themes.ts
    python3 Tools/convert_themes.py --css    # fallback: reads the static/themes/*.css files

Monkeytype color  ->  our UI role
    bg        ->  background
    main      ->  main      (accent)
    caret     ->  caption   (Monkeytype has no "caption"; the caret color is a visible
                             accent-ish color, so we borrow it. Change CAPTION_FROM to
                             "sub" or "main" if you prefer.)
    text      ->  text
    sub       ->  sub
    subAlt    ->  subAlt    (extra role: panels / search box background)
    error     ->  error

Monkeytype is GPL-3.0. The output file records where the data came from.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.request
from pathlib import Path

RAW = "https://raw.githubusercontent.com/monkeytypegame/monkeytype/master/"
THEMES_TS_URL = RAW + "frontend/src/ts/constants/themes.ts"
CSS_DIR_API = ("https://api.github.com/repos/monkeytypegame/monkeytype/contents/"
               "frontend/static/themes")
OUT_FILE = Path(__file__).resolve().parent.parent / "Sources/QuickFLAC/Resources/themes.json"

CAPTION_FROM = "caret"          # which Monkeytype color becomes our "caption"
HEX = r"#[0-9a-fA-F]{3,8}"
REQUIRED = ("bg", "main", "sub", "subAlt", "text", "error")


def fetch(url: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": "quickflac-theme-converter"})
    with urllib.request.urlopen(req, timeout=30) as response:
        return response.read().decode("utf-8")


def parse_themes_ts(text: str) -> dict:
    """Finds blocks like   serika_dark: { bg: "#323437", main: "#e2b714", ... }   """
    themes = {}
    for match in re.finditer(r'["\']?([\w-]+)["\']?\s*:\s*\{([^{}]*)\}', text):
        name, body = match.groups()
        fields = dict(re.findall(r'(\w+)\s*:\s*["\'](' + HEX + r')["\']', body))
        if all(key in fields for key in REQUIRED):
            themes[name] = fields
    return themes


CSS_NAMES = {"bg-color": "bg", "main-color": "main", "caret-color": "caret",
             "sub-color": "sub", "sub-alt-color": "subAlt",
             "text-color": "text", "error-color": "error"}


def parse_css(text: str) -> dict | None:
    """Reads the  :root { --bg-color: #...; ... }  block of one theme file."""
    root = re.search(r':root\s*\{([^}]*)\}', text)
    if not root:
        return None
    variables = dict(re.findall(r'--([\w-]+)\s*:\s*(' + HEX + r')\s*;', root.group(1)))
    fields = {CSS_NAMES[k]: v for k, v in variables.items() if k in CSS_NAMES}
    return fields if all(key in fields for key in REQUIRED) else None


def load_from_css() -> dict:
    listing = json.loads(fetch(CSS_DIR_API))
    themes = {}
    css_files = [item for item in listing if item["name"].endswith(".css")]
    for i, item in enumerate(css_files, 1):
        print(f"\r  css {i}/{len(css_files)}", end="", file=sys.stderr)
        try:
            fields = parse_css(fetch(item["download_url"]))
        except Exception:
            fields = None
        if fields:
            themes[item["name"][:-4]] = fields
    print(file=sys.stderr)
    return themes


def to_ours(name: str, f: dict) -> dict:
    return {
        "name": name,
        "background": f["bg"].lower(),
        "main": f["main"].lower(),
        "caption": f.get(CAPTION_FROM, f["main"]).lower(),
        "text": f["text"].lower(),
        "sub": f["sub"].lower(),
        "subAlt": f["subAlt"].lower(),
        "error": f["error"].lower(),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--css", action="store_true", help="read the CSS files instead of themes.ts")
    args = parser.parse_args()

    themes = {}
    if not args.css:
        print("Downloading themes.ts ...", file=sys.stderr)
        themes = parse_themes_ts(fetch(THEMES_TS_URL))
        if len(themes) < 10:
            print(f"Only {len(themes)} themes found in themes.ts; trying the CSS files.", file=sys.stderr)
            themes = {}
    if not themes:
        print("Downloading CSS theme files ...", file=sys.stderr)
        themes = load_from_css()
    if not themes:
        sys.exit("No themes found. Monkeytype's file layout may have changed; check the repo.")

    result = {
        "source": ("Colors from Monkeytype, https://github.com/monkeytypegame/monkeytype "
                   "(GPL-3.0). Personal use only."),
        "themes": [to_ours(name, themes[name]) for name in sorted(themes)],
    }
    OUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    OUT_FILE.write_text(json.dumps(result, indent=1), encoding="utf-8")
    print(f"Wrote {len(themes)} themes to {OUT_FILE}")


if __name__ == "__main__":
    main()
