"""Renders the Hackr-family CurseForge logos (HackrLFG, HackrAH).

Usage: python make_logos.py <out_dir_lfg> <out_dir_ah>
Writes logo.png (1024x1024) and logo-400.png into each folder.
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

S = 1024
GREEN = (51, 255, 153)
WHITE = (236, 240, 245)
TANK = (59, 117, 245)
HEAL = (48, 184, 110)
DPS = (227, 66, 79)
FONTS = Path("C:/Windows/Fonts")
BOLD = str(FONTS / "segoeuib.ttf")
DIN = str(FONTS / "bahnschrift.ttf")


def din(size):
    f = ImageFont.truetype(DIN, size)
    f.set_variation_by_name("Bold")
    return f
MONO = str(FONTS / "consolab.ttf")


def base():
    img = Image.new("RGB", (S, S))
    px = img.load()
    top, bot = (16, 18, 23), (8, 9, 11)
    for y in range(S):
        t = y / (S - 1)
        c = tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3))
        for x in range(S):
            px[x, y] = c
    img = img.convert("RGBA")

    # soft green glow in the upper area
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((120, 40, 904, 560), fill=(51, 255, 153, 28))
    img = Image.alpha_composite(img, glow.filter(ImageFilter.GaussianBlur(120)))

    # window-style frame: green-tinted 1px-look border, like the in-game frames
    frame = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(frame).rounded_rectangle((36, 36, S - 37, S - 37), radius=72,
                                             outline=(51, 255, 153, 110), width=8)
    return Image.alpha_composite(img, frame)


def wordmark(img, product):
    d = ImageDraw.Draw(img)
    prompt = ImageFont.truetype(MONO, 150)
    hackr = din(150)
    big = din(340)

    # line 1: "> Hackr" (green), centered
    gap = 34
    wp = d.textlength(">", font=prompt)
    wh = d.textlength("Hackr", font=hackr)
    x = (S - (wp + gap + wh)) / 2
    base1 = 270  # shared baseline
    d.text((x, base1 - 6), ">", font=prompt, fill=GREEN, anchor="ls")
    d.text((x + wp + gap, base1), "Hackr", font=hackr, fill=GREEN, anchor="ls")

    # line 2: product name, big and white, centered
    wb = d.textlength(product, font=big)
    d.text(((S - wb) / 2, 600), product, font=big, fill=WHITE, anchor="ls")


def chip(d, box, color, label, filled):
    font = ImageFont.truetype(BOLD, 64)
    if filled:
        d.rounded_rectangle(box, radius=18, fill=color + (255,))
        text_fill = (255, 255, 255, 255)
    else:
        d.rounded_rectangle(box, radius=18, fill=color + (40,), outline=color + (230,), width=7)
        text_fill = color + (255,)
    cx, cy = (box[0] + box[2]) / 2, (box[1] + box[3]) / 2
    d.text((cx, cy), label, font=font, fill=text_fill, anchor="mm")


def lfg_motif(img):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    w, h, gap = 136, 104, 20
    total = 5 * w + 4 * gap
    x0, y0 = (S - total) / 2, 715
    # a group that still needs a healer and one DPS
    spec = [(TANK, "T", True), (HEAL, "H", False), (DPS, "D", True), (DPS, "D", True), (DPS, "D", False)]
    for i, (color, label, filled) in enumerate(spec):
        x = x0 + i * (w + gap)
        chip(d, (x, y0, x + w, y0 + h), color, label, filled)
    return Image.alpha_composite(img, layer)


def ah_motif(img):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    heights = [50, 85, 70, 120, 105, 155, 190]
    w, gap = 72, 26
    total = len(heights) * w + (len(heights) - 1) * gap
    x0, base_y = (S - total) / 2, 880
    for i, h in enumerate(heights):
        x = x0 + i * (w + gap)
        last = i == len(heights) - 1
        alpha = 255 if last else 90 + i * 22
        d.rounded_rectangle((x, base_y - h, x + w, base_y), radius=12, fill=GREEN + (alpha,))
    # baseline
    d.rounded_rectangle((x0 - 20, base_y + 14, x0 + total + 20, base_y + 22), radius=4, fill=(51, 255, 153, 120))
    return Image.alpha_composite(img, layer)


def save(img, out_dir):
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    img = img.convert("RGB")
    img.save(out / "logo.png", optimize=True)
    img.resize((400, 400), Image.LANCZOS).save(out / "logo-400.png", optimize=True)
    print(out / "logo.png")


def main():
    lfg_dir, ah_dir = sys.argv[1], sys.argv[2]
    lfg = base()
    wordmark(lfg, "LFG")
    save(lfg_motif(lfg), lfg_dir)

    ah = base()
    wordmark(ah, "AH")
    save(ah_motif(ah), ah_dir)


if __name__ == "__main__":
    main()
