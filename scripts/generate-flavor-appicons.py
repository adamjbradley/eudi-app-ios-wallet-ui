#!/usr/bin/env python3
"""
Translate Android vector drawables (ic_launcher_foreground.xml) from the
companion Android wallet repo into iOS AppIcon PNGs at 1024x1024.

Source: ../eudi-app-android-wallet-ui/.worktrees/multi-country/resources-logic/src/{au,in}/res/
Target: Wallet/Assets.xcassets/AppIcon{Au,In}.appiconset/app_icon.png + Contents.json

Requires: rsvg-convert (brew install librsvg).
"""

import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ANDROID_NS = "{http://schemas.android.com/apk/res/android}"

FLAVORS = [
    {
        "name": "Au",
        "bg_color": "#DAA520",
        "android_fg": "resources-logic/src/au/res/drawable/ic_launcher_foreground.xml",
        "ios_iconset": "Wallet/Assets.xcassets/AppIconAu.appiconset",
    },
    {
        "name": "In",
        "bg_color": "#FF9933",
        "android_fg": "resources-logic/src/in/res/drawable/ic_launcher_foreground.xml",
        "ios_iconset": "Wallet/Assets.xcassets/AppIconIn.appiconset",
    },
]

CONTENTS_JSON = """{
  "images" : [
    {
      "filename" : "app_icon.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""


def android_vector_to_svg(vector_xml_path: Path, bg_color: str) -> str:
    tree = ET.parse(vector_xml_path)
    root = tree.getroot()

    viewport_w = root.attrib.get(f"{ANDROID_NS}viewportWidth", "108")
    viewport_h = root.attrib.get(f"{ANDROID_NS}viewportHeight", "108")

    svg_parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {viewport_w} {viewport_h}">',
        f'<rect width="{viewport_w}" height="{viewport_h}" fill="{bg_color}"/>',
    ]

    def emit_group(element, depth=0):
        tx = element.attrib.get(f"{ANDROID_NS}translateX", "0")
        ty = element.attrib.get(f"{ANDROID_NS}translateY", "0")
        sx = element.attrib.get(f"{ANDROID_NS}scaleX")
        sy = element.attrib.get(f"{ANDROID_NS}scaleY")
        transforms = []
        if tx != "0" or ty != "0":
            transforms.append(f"translate({tx}, {ty})")
        if sx or sy:
            transforms.append(f"scale({sx or 1}, {sy or 1})")
        attr = f' transform="{" ".join(transforms)}"' if transforms else ""
        svg_parts.append(f"<g{attr}>")
        for child in element:
            tag = child.tag.split("}")[-1]
            if tag == "path":
                fill = child.attrib.get(f"{ANDROID_NS}fillColor", "#000000")
                d = child.attrib.get(f"{ANDROID_NS}pathData", "")
                svg_parts.append(f'<path fill="{fill}" d="{d}"/>')
            elif tag == "group":
                emit_group(child, depth + 1)
        svg_parts.append("</g>")

    # The Android <vector> root may contain <path> or <group> children directly.
    for child in root:
        tag = child.tag.split("}")[-1]
        if tag == "path":
            fill = child.attrib.get(f"{ANDROID_NS}fillColor", "#000000")
            d = child.attrib.get(f"{ANDROID_NS}pathData", "")
            svg_parts.append(f'<path fill="{fill}" d="{d}"/>')
        elif tag == "group":
            emit_group(child)

    svg_parts.append("</svg>")
    return "\n".join(svg_parts)


def render_svg(svg_text: str, out_path: Path) -> None:
    proc = subprocess.run(
        ["rsvg-convert", "-w", "1024", "-h", "1024", "-f", "png", "-o", str(out_path)],
        input=svg_text,
        text=True,
        capture_output=True,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"rsvg-convert failed: {proc.stderr}")


def main():
    ios_root = Path(__file__).resolve().parent.parent
    android_root = (
        ios_root.parent.parent.parent
        / "eudi-app-android-wallet-ui"
        / ".worktrees"
        / "multi-country"
    )
    if not android_root.exists():
        sys.exit(f"Android worktree not found: {android_root}")

    for flavor in FLAVORS:
        android_fg = android_root / flavor["android_fg"]
        if not android_fg.exists():
            sys.exit(f"Missing: {android_fg}")

        svg = android_vector_to_svg(android_fg, flavor["bg_color"])
        iconset = ios_root / flavor["ios_iconset"]
        iconset.mkdir(parents=True, exist_ok=True)

        render_svg(svg, iconset / "app_icon.png")
        (iconset / "Contents.json").write_text(CONTENTS_JSON)
        print(f"[ok] {flavor['name']}: {iconset / 'app_icon.png'}")


if __name__ == "__main__":
    main()
