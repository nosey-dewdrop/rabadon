#!/usr/bin/env python3
"""The card that shows when somebody shares the link, drawn at build time.

It used to be a picture exported once by hand with three numbers baked into
it. Two of them were wrong within the week -- the gate got slower and honest
about it (130.0us -> 262.4us) and the ledger kept counting -- and nothing on
this machine could have noticed, because a png does not fail a test. Every page
on this site is built from measured.json for exactly that reason; the card is
the last surface that was not.

So it is drawn here, from the same file the pages read, in the same colours the
stylesheet declares, on the same grid the hand-drawn one used: left margin 72,
the numbers right-aligned to a column at 282 and their sentences starting at
320, which is what `.stats` does in css. The headline is read out of
site/index.tmpl.html rather than retyped, so the card and the page cannot come
to say different things.

No new dependency: Pillow is already importable under both the interpreter this
repo is developed with and the one launchd starts the publish job with, and the
font is one macOS ships. If either is missing the existing card is left exactly
where it is and the build says so, because a share card that fails to draw is
not a reason to fail a deploy.

    python3 site/og.py        draw it, print what happened
"""
import io
import os
import re
import textwrap

W, H = 1200, 630                 # unchanged: the og:image:width/height the
                                 # pages declare, and what every scraper crops
MARGIN = 72
NUM_RIGHT = 282                  # the numbers are right-aligned to this column
CAP_LEFT = 320                   # and every sentence starts here
WRAP = 16                        # characters, the headline's own wrap

# straight out of style.css. a colour that only lives in this file is a colour
# that drifts away from the site the card is advertising.
BG = (0x17, 0x12, 0x21)          # --bg
INK = (0xef, 0xe8, 0xf7)         # --ink
DIM = (0x9d, 0x92, 0xb5)         # --ink-dim
PINK = (0xff, 0x8f, 0xb3)        # --pink
GREEN = (0xb8, 0xe3, 0x9a)       # --green
YELLOW = (0xff, 0xd4, 0x79)      # --yellow

# baselines, measured off the card this replaces rather than guessed
Y_MARK = 95
Y_H1 = (175, 243, 311, 379)      # 68px apart
Y_STAT = (386, 447, 508)         # 61px apart
Y_FOOT = 558

S_MARK, S_H1, S_NUM, S_CAP = 28, 54, 36, 19

OUT = "site/og.png"
TMPL = "site/index.tmpl.html"
HEADLINE = "run your coding agent without watching it."
DOMAIN = "rabadon.noseydewdrop.com"
AUTHOR = "Damla Su Bilge"

# The three figures the card carries, each one a key in measured.json and a
# number the site already prints. Nothing here is a literal: a key that file
# does not carry produces no row, rather than a stale row or a zero.
#   field.stop        what it refused outright, /field and the overview
#   field.would_block what it recorded without blocking, /field and the overview
#   gate.judge_us     what one judgement costs, /benchmarks and the overview
ROWS = [
    ("field.stop", PINK, "commands refused outright, so they never ran"),
    ("field.would_block", GREEN, "recorded in watch mode, where nothing is blocked"),
    ("gate.judge_us", YELLOW, "to judge one command"),
]

# macOS ships Menlo, whose advance is 0.602em against IBM Plex Mono's 0.6, so
# the grid above holds. The rest are there so this does not become a file that
# only runs on one laptop.
FACES = [
    ("/System/Library/Fonts/Menlo.ttc", 0, "/System/Library/Fonts/Menlo.ttc", 1),
    ("/System/Library/Fonts/Supplemental/Andale Mono.ttf", 0,
     "/System/Library/Fonts/Supplemental/Andale Mono.ttf", 0),
    ("/System/Library/Fonts/Monaco.ttf", 0, "/System/Library/Fonts/Monaco.ttf", 0),
    ("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 0,
     "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf", 0),
]


def headline(path=TMPL):
    """The claim on the overview, read off the template. Retyping it here is how
    a card ends up advertising a sentence the site no longer makes."""
    try:
        s = open(path, encoding="utf-8").read()
    except OSError:
        return HEADLINE
    m = re.search(r"<h1>(.*?)</h1>", s, re.S)
    if not m:
        return HEADLINE
    import html as _html
    text = _html.unescape(re.sub(r"<[^>]+>", "", m.group(1)))
    return " ".join(text.split()) or HEADLINE


def value(meas, key):
    """What the pages print for this key: the display form when there is one,
    with the html entity turned back into the character an image needs."""
    e = (meas or {}).get(key) or {}
    if e.get("value") is None:
        return None
    import html as _html
    if e.get("display"):
        return _html.unescape(str(e["display"]))
    v = e["value"]
    return "{:,}".format(v) if isinstance(v, int) else str(v)


def _fonts(ImageFont):
    for reg, ri, bold, bi in FACES:
        if not os.path.exists(reg):
            continue
        if not os.path.exists(bold):
            bold, bi = reg, ri
        return (lambda size, r=reg, i=ri: ImageFont.truetype(r, size, index=i),
                lambda size, b=bold, i=bi: ImageFont.truetype(b, size, index=i))
    return None, None


def draw(meas):
    """The card as bytes, or None if this machine cannot draw one."""
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        return None
    reg, bold = _fonts(ImageFont)
    if reg is None:
        return None

    f_mark, f_h1 = bold(S_MARK), reg(S_H1)
    f_num, f_cap = bold(S_NUM), reg(S_CAP)

    im = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(im)

    # the wordmark, with the brackets pink and the bar between them not, which
    # is what <span class="mark"><i>[</i>|<i>]</i> rabadon</span> renders
    x = MARGIN
    for part, colour in (("[", PINK), ("|", INK), ("]", PINK), (" rabadon", INK)):
        d.text((x, Y_MARK), part, font=f_mark, fill=colour, anchor="ls")
        x += f_mark.getlength(part)

    lines = textwrap.wrap(headline(), WRAP)[:len(Y_H1)]
    for y, line in zip(Y_H1, lines):
        d.text((MARGIN, y), line, font=f_h1, fill=INK, anchor="ls")

    rows = [(value(meas, k), c, cap) for k, c, cap in ROWS]
    rows = [r for r in rows if r[0]]
    for y, (num, colour, caption) in zip(Y_STAT[len(Y_STAT) - len(rows):], rows):
        d.text((NUM_RIGHT, y), num, font=f_num, fill=colour, anchor="rs")
        # a sentence that would run off the card is set smaller rather than cut:
        # the caption is the half that says what the number counts.
        f, size = f_cap, S_CAP
        while f.getlength(caption) > W - MARGIN - CAP_LEFT and size > 14:
            size -= 1
            f = reg(size)
        d.text((CAP_LEFT, y), caption, font=f, fill=DIM, anchor="ls")

    f_foot = reg(S_CAP)
    d.text((MARGIN, Y_FOOT), DOMAIN, font=f_foot, fill=DIM, anchor="ls")
    d.text((W - MARGIN, Y_FOOT), AUTHOR, font=f_foot, fill=DIM, anchor="rs")

    buf = io.BytesIO()
    im.save(buf, format="PNG", optimize=True)
    return buf.getvalue()


def render(meas, out=OUT):
    """Draw the card and write it only if it came out different, so a file that
    says the same thing does not get a new mtime 48 times a day."""
    png = draw(meas)
    if png is None:
        return "%s  left alone: no Pillow or no monospace font on this machine" % out
    old = open(out, "rb").read() if os.path.exists(out) else None
    if old == png:
        return "%s  %7d bytes  unchanged" % (out, len(png))
    with open(out, "wb") as f:
        f.write(png)
    return "%s  %7d bytes  %s" % (out, len(png), "redrawn" if old else "written")


if __name__ == "__main__":
    import json
    m = {}
    if os.path.exists("site/measured.json"):
        m = json.load(open("site/measured.json", encoding="utf-8"))
    print(render(m))
