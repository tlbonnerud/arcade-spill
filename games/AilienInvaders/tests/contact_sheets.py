#!/usr/bin/env python3
"""Setter skjermbildene fra tests/screenshots.tscn sammen til oversiktsark.

    python3 tests/contact_sheets.py /sti/til/shots

Lager ark_formasjoner.png, ark_innflyginger.png, ark_bevegelser.png og
ark_bolger.png (det som finnes bilder til) i samme mappe.
Krever Pillow (pip install pillow).
"""
import glob
import os
import sys

from PIL import Image, ImageDraw

THUMB = (480, 270)
PAD = 6
LABEL_H = 18


def sheet(files, cols, out_path):
    if not files:
        return
    rows = (len(files) + cols - 1) // cols
    w = cols * (THUMB[0] + PAD) + PAD
    h = rows * (THUMB[1] + LABEL_H + PAD) + PAD
    canvas = Image.new("RGB", (w, h), (18, 18, 24))
    draw = ImageDraw.Draw(canvas)
    for i, path in enumerate(files):
        img = Image.open(path).convert("RGB").resize(THUMB, Image.NEAREST)
        x = PAD + (i % cols) * (THUMB[0] + PAD)
        y = PAD + (i // cols) * (THUMB[1] + LABEL_H + PAD)
        canvas.paste(img, (x, y + LABEL_H))
        draw.text((x + 2, y + 3), os.path.basename(path)[:-4], fill=(235, 235, 235))
    canvas.save(out_path)
    print("skrev", out_path)


def main():
    d = sys.argv[1] if len(sys.argv) > 1 else "."
    sheet(sorted(glob.glob(os.path.join(d, "formasjon_*.png"))), 4, os.path.join(d, "ark_formasjoner.png"))
    sheet(sorted(glob.glob(os.path.join(d, "innflyging_*.png"))), 4, os.path.join(d, "ark_innflyginger.png"))
    sheet(sorted(glob.glob(os.path.join(d, "bevegelse_*.png"))), 4, os.path.join(d, "ark_bevegelser.png"))
    sheet(sorted(glob.glob(os.path.join(d, "bolge_*.png"))), 4, os.path.join(d, "ark_bolger.png"))


if __name__ == "__main__":
    main()
