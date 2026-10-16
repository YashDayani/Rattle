#!/usr/bin/env python3
"""Recolours Open Doodles (Pablo Stanley, CC0, https://www.opendoodles.com) for Rattle's onboarding and empty states.

Downloads each doodle from https://opendoodles.s3-us-west-1.amazonaws.com/<name>.svg and writes
Illustrations/<name>.svg in Rattle ink, cream skin and one pastel per screen. Run from the repo root.
"""
import re, urllib.request, pathlib

INK, SKIN = "#1a1a1a", "#FFF8EC"
LAVENDER, PEACH, PINK = ("#D9C8F5", "#BFA8EC"), ("#F8D2AE", "#EDB585"), ("#F6C9DD", "#E9A6C4")
# One doodle per onboarding step, pastels rotating like Wispr Flow's.
ART = [("loving", LAVENDER), ("swinging", PEACH), ("unboxing", PINK),
       ("sitting-reading", LAVENDER), ("groovy", PEACH), ("jumping", PINK),
       # Empty states: Dictation, Meetings, Notes.
       ("float", LAVENDER), ("coffee", PEACH), ("reading", PINK)]

def recolour(svg, accent, shade):
    svg = re.sub(r"<\?xml[^>]*>|<!--.*?-->|<title>.*?</title>|<desc>.*?</desc>", "", svg, flags=re.S)
    colours = {"#000000": INK, "#ffffff": SKIN, "#ff5678": accent, "#cf536d": shade}
    return re.sub(r"#[0-9a-fA-F]{6}", lambda m: colours.get(m.group(0).lower(), m.group(0)), svg).strip() + "\n"

out = pathlib.Path("Illustrations"); out.mkdir(exist_ok=True)
for name, (accent, shade) in ART:
    src = urllib.request.urlopen(f"https://opendoodles.s3-us-west-1.amazonaws.com/{name}.svg").read().decode()
    (out / f"{name}.svg").write_text(recolour(src, accent, shade))
    print("wrote", out / f"{name}.svg")
