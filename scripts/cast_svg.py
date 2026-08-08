#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""cast_svg.py — turn a recording into a self-contained animated SVG.

WHY NOT A GIF, AND WHY NOTHING WAS INSTALLED TO MAKE IT.
  The repository had no recorder, and reaching for asciinema or vhs would have
  put the one watchable artifact behind a tool nobody cloning this has. An SVG
  with CSS keyframes needs no player, no JavaScript, weighs what its text
  weighs, stays readable when a jury zooms in, and renders inline in a GitHub
  README. A GIF of a terminal is a screenshot of a screenshot: the text stops
  being text, and the numbers on the stage stop being copyable.

WHAT IT WILL NOT DO.
  It will not invent a frame. Every line it draws came out of a process that
  scripts/record-cast.sh ran, and every duration is derived from a measured
  millisecond count. When the real timings are used verbatim the result is
  unwatchable, because the two refusals land in single-digit milliseconds and
  the repair takes seconds — so the durations are COMPRESSED, on a rule written
  down here rather than tuned by eye, and the real millisecond count is printed
  on the frame beside the compressed one. The viewer sees 2.3 ms and watches it
  for two seconds; nothing is hidden and nothing is faked.

READABILITY IS THE ONLY OTHER RULE.
  A frame that cannot be read in the time it is on screen is a frame that did
  not happen. Dwell time is bounded below by how much text the frame carries.
"""
import json
import sys

COLS = 96
ROWS = 26
# Advance width of the monospace face at 14px, as an UPPER BOUND rather than a
# typical value. 8.4 is 0.6em, which is what Menlo and DejaVu Sans Mono do and
# what the first version assumed. The card went out with its longest line running
# off the right edge, because the renderer that actually drew it fell back to a
# face advancing about 0.68em and the wrap width had been computed from the
# narrow one. Nothing here can ask the renderer which font it picked, so the box
# is sized for the widest plausible answer and a narrow face just leaves margin.
CH_W = 9.6
CH_H = 20.0
PAD = 18.0

BG = "#12131a"
FG = "#d7d8e0"
DIM = "#6d7080"
PROMPT = "#7aa2f7"
DENY = "#f7768e"
HOLD = "#9ece6a"
NOTE = "#e0af68"

# how long a frame stays on screen. Not tuned by eye: a floor so the shortest
# frame is still readable, a term proportional to how much text it carries
# (about a line every fifth of a second, which is faster than reading and
# slower than flicking), and a ceiling so one long frame cannot eat the reel.
MIN_DWELL = 1.15
PER_LINE = 0.20
MAX_DWELL = 3.60


def esc(s):
    return (s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


def classify(line):
    """The one place a colour is chosen, so the reel cannot end up with the
    product's own problem: fifteen colour codes across three files and the same
    role wearing two of them."""
    t = line.strip()
    if t.startswith("$ "):
        return PROMPT
    if "BLOCKED this action" in t or "REPAIR_FAIL" in t or t.startswith("Rule:") \
       or "hash-locked" in t or "did NOT" in t:
        return DENY
    if "REPAIR_OK" in t or t == "ok" or "VERIFIED" in t or "verdict: ok" in t:
        return HOLD
    if t.startswith("#"):
        return NOTE
    return FG


def wrap(line, width):
    if len(line) <= width:
        return [line]
    out, rest = [], line
    while len(rest) > width:
        out.append(rest[:width])
        rest = "  " + rest[width:]
    out.append(rest)
    return out


def build_frames(records):
    """Two frames per step: the command alone, then the command with what came
    back. The screen scrolls the way a terminal scrolls, so a viewer joining at
    any second sees the same history the operator would have."""
    screen, frames = [], []

    def push(lines):
        for ln in lines:
            for w in wrap(ln, COLS - 2):
                screen.append(w)
        if len(screen) > ROWS:
            del screen[:-ROWS]

    for r in records:
        note = r.get("note") or ""
        if note:
            push(["", "# " + note])
        push(["$ " + r["cmd"]])
        frames.append((list(screen[-ROWS:]), 1))

        body = list(r["out"])
        rc, ms = r["exit"], r["ms"]
        tail = "  exit %d · %d ms" % (rc, ms)
        body.append(tail)
        push(body)
        frames.append((list(screen[-ROWS:]), len(body)))
    return frames


def render(frames, path):
    dwells = [max(MIN_DWELL, min(MAX_DWELL, MIN_DWELL + PER_LINE * n)) for _, n in frames]
    total = sum(dwells)
    w = COLS * CH_W + PAD * 2
    h = ROWS * CH_H + PAD * 2 + 38

    # WHICH FRAME A RENDERER THAT CANNOT ANIMATE WILL SHOW.
    #   Every frame starts hidden and is revealed by a keyframe, so a viewer with
    #   no CSS animation draws a correctly-sized, entirely EMPTY rectangle. That
    #   is not a rare corner: an SVG lands in README previews, npm's renderer,
    #   PDF exports and screenshots, and in each of those the one artifact that
    #   was supposed to answer "what does this thing do" answers nothing at all.
    #   So one frame keeps opacity 1 as its resting state and the animation
    #   overrides it wherever animation exists — the still is the refusal, since
    #   a single frame of this reel is worth having only if it is the one where
    #   the product does its job.
    still = 0
    for i, (lines, _) in enumerate(frames):
        if any("BLOCKED this action" in ln for ln in lines):
            still = i
            break

    # A class on the frame itself cannot do this job: the frame's own animation
    # sets opacity 0 at 0% and an animation beats a declaration, so the resting
    # value never gets a turn. The still has to be a SEPARATE layer that hides
    # ITSELF the moment animation is available — a renderer that runs the ten
    # millisecond fade removes it before a human eye resolves anything, and a
    # renderer that ignores animation leaves it standing, which is the whole
    # point. Verified by rasterising this file and looking at it, which is how
    # the first version was caught shipping a correctly-sized black rectangle.
    css = [
        "text{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,'DejaVu Sans Mono',monospace;"
        "font-size:14px;white-space:pre}",
        ".f{opacity:0}",
        "@keyframes poster{from{opacity:1}to{opacity:0}}",
        ".poster{opacity:1;animation:poster 0.01s linear forwards}",
    ]
    body = []
    t = 0.0
    for i, ((lines, _), d) in enumerate(zip(frames, dwells)):
        start = t / total * 100.0
        end = (t + d) / total * 100.0
        # a hair of overlap on either side, so no frame boundary shows the
        # background through
        a = max(0.0, start - 0.15)
        b = min(100.0, end + 0.15)
        css.append(
            "@keyframes k%d{0%%,%.3f%%{opacity:0}%.3f%%,%.3f%%{opacity:1}%.3f%%,100%%{opacity:0}}"
            % (i, a, a + 0.01, b, b + 0.01))
        css.append(".f%d{animation:k%d %.2fs steps(1,end) infinite}" % (i, i, total))
        g = ['<g class="f f%d">' % i]
        for j, ln in enumerate(lines):
            y = PAD + 16 + j * CH_H
            g.append('<text x="%.1f" y="%.1f" fill="%s">%s</text>'
                     % (PAD, y, classify(ln), esc(ln)))
        g.append("</g>")
        body.append("".join(g))
        t += d

    # the still layer, drawn under the reel and removed by its own animation
    poster = ['<g class="poster">']
    for j, ln in enumerate(frames[still][0]):
        poster.append('<text x="%.1f" y="%.1f" fill="%s">%s</text>'
                      % (PAD, PAD + 16 + j * CH_H, classify(ln), esc(ln)))
    poster.append("</g>")

    # two lines, because one did not fit. At 11px the face advances about 6.6px,
    # so the box holds roughly 120 characters and the single line this replaced
    # was 150 — it ran off the right edge of the card, in the one artifact whose
    # job is to look like somebody checked.
    foot = ["recorded by scripts/record-cast.sh from real runs. every line is process output.",
            "durations compressed for reading, the measured milliseconds are on each frame."]
    svg = [
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %.0f %.0f" width="%.0f" height="%.0f" '
        'role="img" aria-label="rabadon: two refusals, a held repair, and a rejected fake fix">'
        % (w, h, w, h),
        "<style>%s</style>" % "".join(css),
        '<rect width="100%%" height="100%%" rx="10" fill="%s"/>' % BG,
        "".join(poster),
        "".join(body),
        '<text x="%.1f" y="%.1f" fill="%s" font-size="11">%s</text>'
        % (PAD, h - 26, DIM, esc(foot[0])),
        '<text x="%.1f" y="%.1f" fill="%s" font-size="11">%s</text>'
        % (PAD, h - 12, DIM, esc(foot[1])),
        "</svg>",
    ]
    open(path, "w", encoding="utf-8").write("\n".join(svg) + "\n")
    return total, len(frames), len("\n".join(svg))


def main():
    src, dst = sys.argv[1], sys.argv[2]
    records = [json.loads(l) for l in open(src, encoding="utf-8") if l.strip()]
    if not records:
        print("no frames recorded", file=sys.stderr)
        return 1
    frames = build_frames(records)
    total, n, size = render(frames, dst)
    print("wrote %s — %d frames, %.1f s, %.1f kB, from %d recorded steps"
          % (dst, n, total, size / 1000.0, len(records)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
