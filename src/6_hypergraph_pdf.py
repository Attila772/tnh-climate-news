"""Step 6: hypergraph figures as publication PDFs.

Input : results/figures/hypergraphs/viewer_export/<name>.svg, saved with the camera button of
        the viewer (viewer/HyperGodot.exe) from the hypergraphs and layouts in viewer/.
Output: results/figures/hypergraphs/<name>.svg  the same drawing with a semi-transparent white
                                                panel behind each label, labels drawn last
        results/figures/hypergraphs/<name>.pdf  vector PDF with the embedded label font

Font: fonts/Times New Roman.ttf if present (not redistributable; reproduces the published
figures exactly), otherwise the bundled metric-compatible fonts/LiberationSerif-Regular.ttf.
"""
import re
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.colors import HexColor
from PIL import ImageFont
from common import ROOT, RESULTS

FONT = ROOT / "fonts" / "Times New Roman.ttf"
if not FONT.exists():
    FONT = ROOT / "fonts" / "LiberationSerif-Regular.ttf"
pdfmetrics.registerFont(TTFont("LabelFont", str(FONT)))
SRC = RESULTS / "figures" / "hypergraphs" / "viewer_export"
OUT = SRC.parent
PANEL_OPACITY, PAD_X, PAD_Y, RADIUS = 0.75, 4.0, 2.0, 3.0

TEXT = re.compile(r'<text x="([-\d.]+)" y="([-\d.]+)"([^>]*)>([^<]*)</text>\n?')
ATTR = re.compile(r'([\w-]+)="([^"]*)"')
ELEM = re.compile(r'<(rect|circle|path|text)\b([^>]*?)(/>|>([^<]*)</text>)', re.S)


def col(v):
    return HexColor({"white": "#ffffff", "black": "#000000"}.get(v, v))


def add_label_panels(svg):
    """Move every label to the end of the SVG, each preceded by a white panel."""
    texts = TEXT.findall(svg)
    body = TEXT.sub("", svg)
    overlay = ['<g id="labels">']
    for x, y, attrs, label in texts:
        x, y = float(x), float(y)
        fs = float(re.search(r'font-size="([\d.]+)"', attrs).group(1))
        l, t, r, b = ImageFont.truetype(str(FONT), fs).getbbox(label.replace("&amp;", "&"), anchor="ls")
        overlay.append(f'<rect x="{x + l - PAD_X:.2f}" y="{y + t - PAD_Y:.2f}" width="{r - l + 2 * PAD_X:.2f}" '
                       f'height="{b - t + 2 * PAD_Y:.2f}" rx="{RADIUS}" fill="#ffffff" fill-opacity="{PANEL_OPACITY}"/>')
        overlay.append(f'<text x="{x}" y="{y}"{attrs}>{label}</text>')
    overlay.append("</g>")
    return body.replace("</svg>", "\n".join(overlay) + "\n</svg>")


def to_pdf(svg, dst):
    """Draw the element set written by the viewer (rect, circle, path with M/L/Z, text) as PDF."""
    W, H = map(float, re.search(r'viewBox="0 0 ([\d.]+) ([\d.]+)"', svg).groups())
    c = canvas.Canvas(str(dst), pagesize=(W, H), invariant=1)  # no dates: reruns are byte-identical
    c.setTitle(dst.stem)
    for tag, attrs, _, text in ELEM.findall(svg):
        a = dict(ATTR.findall(attrs))
        c.saveState()
        if tag == "rect":
            w = W if a.get("width", "").endswith("%") else float(a["width"])
            h = H if a.get("height", "").endswith("%") else float(a["height"])
            x, y = float(a.get("x", 0)), float(a.get("y", 0))
            c.setFillColor(col(a.get("fill", "#ffffff")))
            c.setFillAlpha(float(a.get("fill-opacity", 1)))
            c.roundRect(x, H - y - h, w, h, float(a.get("rx", 0)), stroke=0, fill=1)
        elif tag == "circle":
            c.setFillColor(col(a["fill"]))
            c.circle(float(a["cx"]), H - float(a["cy"]), float(a["r"]), stroke=0, fill=1)
        elif tag == "path":
            p = c.beginPath()
            for cmd, nums in re.findall(r'([MLZ])([^MLZ]*)', a["d"]):
                v = list(map(float, nums.split())) if nums.strip() else []
                if cmd == "M":
                    p.moveTo(v[0], H - v[1])
                elif cmd == "L":
                    p.lineTo(v[0], H - v[1])
                else:
                    p.close()
            c.setStrokeColor(col(a["stroke"]))
            c.setStrokeAlpha(float(a.get("stroke-opacity", 1)))
            c.setLineWidth(float(a["stroke-width"]))
            c.setLineJoin(1)
            if "stroke-dasharray" in a:
                c.setDash(list(map(float, a["stroke-dasharray"].split())))
            c.drawPath(p, stroke=1, fill=0)
        else:
            c.setFillColor(col(a.get("fill", "#000000")))
            c.setFont("LabelFont", float(a["font-size"]))
            c.drawString(float(a["x"]), H - float(a["y"]), text.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">"))
        c.restoreState()
    c.showPage()
    c.save()


if __name__ == "__main__":
    print("label font:", FONT.name)
    for src in sorted(SRC.glob("*.svg")):
        svg = add_label_panels(src.read_text(encoding="utf-8"))
        (OUT / src.name).write_text(svg, encoding="utf-8")
        to_pdf(svg, OUT / f"{src.stem}.pdf")
        print(src.stem, "->", f"{src.stem}.svg, {src.stem}.pdf")
