#!/usr/bin/env python3
"""Generate Velum icon SVGs (colourways + app-icon variants) from the master symbol geometry."""
import sys, os

HIGHLIGHT = "M34 151 H79.5 L109.52 203 H34 A26 26 0 0 1 34 151 Z M222 151 H176.5 L146.48 203 H222 A26 26 0 0 0 222 151 Z"
V = "M21.8 35 H68 L128 138.92 L188 35 H234.2 L128 219 Z"
CX, CY = 128, 127  # symbol bbox centre

COLOURWAYS = {
    "green":  dict(bg=("#4BE88A", "#12A150"), v="#FFFFFF", bar="#FFE14D"),
    "violet": dict(bg=("#8B5CFF", "#3A1FC1"), v="#FFFFFF", bar="#FFD23F"),
    "coral":  dict(bg=("#FF8A4C", "#E62E5C"), v="#FFFFFF", bar="#2D0B45"),
}

def symbol(s, v, bar, lift=0.008, size=1024):
    tx = size / 2 - CX * s
    ty = size / 2 - size * lift - CY * s
    return (f'<g transform="translate({tx:.2f} {ty:.2f}) scale({s:.4f})">'
            f'<path fill="{bar}" d="{HIGHLIGHT}"/><path fill="{v}" d="{V}"/></g>')

def bg_defs(c):
    a, b = c["bg"]
    return (f'<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">'
            f'<stop offset="0" stop-color="{a}"/><stop offset="1" stop-color="{b}"/></linearGradient></defs>')

def svg(body, defs=""):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">'
            f'{defs}{body}</svg>\n')

def variant(name, c):
    """name: tile | square | circle | foreground | background | monochrome | maskable"""
    if name == "tile":        # rounded-square tile (web icons, previews)
        return svg(f'<rect width="1024" height="1024" rx="228" fill="url(#g)"/>' + symbol(2.6, c["v"], c["bar"]), bg_defs(c))
    if name == "square":      # full-bleed square (iOS, Play Store — platform applies the mask)
        return svg(f'<rect width="1024" height="1024" fill="url(#g)"/>' + symbol(2.6, c["v"], c["bar"]), bg_defs(c))
    if name == "circle":      # legacy Android launcher icon
        return svg(f'<circle cx="512" cy="512" r="496" fill="url(#g)"/>' + symbol(2.3, c["v"], c["bar"]), bg_defs(c))
    if name == "maskable":    # web maskable: symbol inside the 80% safe circle
        return svg(f'<rect width="1024" height="1024" fill="url(#g)"/>' + symbol(2.2, c["v"], c["bar"]), bg_defs(c))
    if name == "foreground":  # adaptive foreground: symbol within 66dp/108dp safe circle (r 141 units * 2.2 = 310 < 313)
        return svg(symbol(2.2, c["v"], c["bar"]))
    if name == "background":
        return svg('<rect width="1024" height="1024" fill="url(#g)"/>', bg_defs(c))
    if name == "monochrome":
        return svg(symbol(2.2, "#FFFFFF", "#FFFFFF"))
    raise ValueError(name)

if __name__ == "__main__":
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    names = sys.argv[2:] or list(COLOURWAYS)
    for cw in names:
        for v in ("tile", "square", "circle", "maskable", "foreground", "background", "monochrome"):
            with open(os.path.join(out, f"velum-{cw}-{v}.svg"), "w") as f:
                f.write(variant(v, COLOURWAYS[cw]))
