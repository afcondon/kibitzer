#!/usr/bin/env python3
"""The worlds canvas: the SMT view of one game, as a page.

The engine reasons through justification chains; Z3 reasons over the
whole model space at once. This script makes the model space visible:
it enumerates every world (complete card assignment) consistent with
the public transcript at the first moment the space fits on a screen
(<= CAP worlds), then replays the remaining events purely — each world
is a full assignment, so pass/show constraints are direct evaluations,
no solver needed. The browser receives the world set plus per-position
death lists and animates the collapse down to the solved view.

Two markers fall out for free: the position where all surviving worlds
agree on the envelope IS the optimal (Z3) solve moment, and the trace
carries the engine's own solve position — the completeness gap, visible
on one strip.

Usage:
  spago run --quiet -p kibitzer-example -- trace 33 --players 6 > smt/trace-33.json
  smt/.venv/bin/python smt/worlds_trace.py smt/trace-33.json > frontend/public/worlds.html
"""

import argparse
import json
import sys

from z3 import And, If, Int, Or, Solver, Sum, sat

SUSPECTS = range(0, 6)
WEAPONS = range(6, 12)
ROOMS = range(12, 21)

CARD_SHORT = [
    "Scarlett", "Mustard", "White", "Green", "Peacock", "Plum",
    "Candlestick", "Knife", "Lead Pipe", "Revolver", "Rope", "Wrench",
    "Kitchen", "Ballroom", "Conservatory", "Dining", "Billiard",
    "Library", "Lounge", "Hall", "Study",
]


def base_solver(trace, place):
    n = trace["players"]
    env = n
    s = Solver()
    for c in range(21):
        s.add(place[c] >= 0, place[c] <= env)
    for p in range(n):
        s.add(Sum([If(place[c] == p, 1, 0) for c in range(21)]) == trace["handSizes"][p])
    for cat in (SUSPECTS, WEAPONS, ROOMS):
        s.add(Sum([If(place[c] == env, 1, 0) for c in cat]) == 1)
    return s


def constraints_upto(trace, place, pos):
    """The watcher-visible constraints of events[0..pos)."""
    out = []
    for e in trace["events"][:pos]:
        k = e["constraint"]
        if k is None:
            continue
        p = k["player"]
        if k["type"] == "pass":
            out.extend(place[c] != p for c in k["cards"])
        else:  # show
            out.append(Or([place[c] == p for c in k["cards"]]))
    return out


def enumerate_worlds(trace, pos, cap):
    """All worlds consistent at `pos`, stopping at cap+1 (the +1 marks
    'more than cap')."""
    place = [Int(f"place_{c}") for c in range(21)]
    s = base_solver(trace, place)
    s.add(constraints_upto(trace, place, pos))
    worlds = []
    while len(worlds) <= cap and s.check() == sat:
        m = s.model()
        w = [m[place[c]].as_long() for c in range(21)]
        worlds.append(w)
        s.add(Or([place[c] != w[c] for c in range(21)]))
    return worlds


def satisfies(world, constraint):
    p = constraint["player"]
    if constraint["type"] == "pass":
        return all(world[c] != p for c in constraint["cards"])
    return any(world[c] == p for c in constraint["cards"])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("trace")
    ap.add_argument("--cap", type=int, default=1500)
    args = ap.parse_args()
    trace = json.load(open(args.trace))
    total = len(trace["events"])
    env = trace["players"]

    # first position where the space fits: counts shrink monotonically,
    # so binary search; each probe is an early-exiting enumeration
    print(f"probing for the first position with <= {args.cap} worlds…", file=sys.stderr)
    lo, hi = 0, total
    while lo < hi:
        mid = (lo + hi) // 2
        n = len(enumerate_worlds(trace, mid, args.cap))
        print(f"  position {mid}: {'>' if n > args.cap else ''}{min(n, args.cap)} worlds", file=sys.stderr)
        if n > args.cap:
            lo = mid + 1
        else:
            hi = mid
    p0 = lo
    worlds = enumerate_worlds(trace, p0, args.cap)
    print(f"space fits at position {p0}: {len(worlds)} worlds", file=sys.stderr)

    # pure replay: which of the p0 worlds die at each later position
    alive = list(range(len(worlds)))
    deaths = {}  # position -> [world indices]
    optimal_solved_at = None

    def envelope_of(w):
        return tuple(c for c in range(21) if w[c] == env)

    def check_solved(pos, current):
        nonlocal optimal_solved_at
        if optimal_solved_at is None and current:
            triples = {envelope_of(worlds[i]) for i in current}
            if len(triples) == 1:
                optimal_solved_at = pos

    check_solved(p0, alive)
    for pos in range(p0 + 1, total + 1):
        k = trace["events"][pos - 1]["constraint"]
        if k is None:
            continue
        dying = [i for i in alive if not satisfies(worlds[i], k)]
        if dying:
            deaths[pos] = dying
            alive = [i for i in alive if satisfies(worlds[i], k)]
        check_solved(pos, alive)

    print(f"final worlds: {len(alive)}; optimal solve at {optimal_solved_at}; "
          f"engine solve at {trace['engineSolvedAt']}", file=sys.stderr)

    data = {
        "seed": trace["seed"],
        "players": trace["players"],
        "cap": args.cap,
        "p0": p0,
        "total": total,
        "worlds": worlds,
        "deaths": deaths,
        "labels": [e["label"] for e in trace["events"]],
        "informative": [e["constraint"] is not None for e in trace["events"]],
        "solution": trace["solution"],
        "engineSolvedAt": trace["engineSolvedAt"],
        "optimalSolvedAt": optimal_solved_at,
        "cardKnownAt": trace.get("cardKnownAt", [None] * 21),
        "cardNames": CARD_SHORT,
    }
    print(render_page(data))


def render_page(data):
    payload = json.dumps(data, separators=(",", ":"))
    n = data["players"]
    return (
        PAGE_TEMPLATE
        .replace("__DATA__", payload)
        .replace("__SEED__", str(data["seed"]))
        .replace("__PLAYERS__", str(n))
        .replace("__CAP__", str(data["cap"]))
        .replace("__P0E__", "E" + str(data["p0"] - 1))
        .replace("__NWORLDS__", f"{len(data['worlds']):,}")
    )


PAGE_TEMPLATE = r"""<!doctype html><meta charset="utf-8">
<title>kibitzer — the model space</title>
<style>
 :root { --ink: #141414; --muted: #767676; --accent: #d92b2b; --hairline: #e6e6e6; }
 body { font-family: "Helvetica Neue", Arial, sans-serif; color: var(--ink);
        max-width: 72rem; margin: 2rem auto; padding: 0 1.5rem; }
 h1 { font-size: 1.4rem; letter-spacing: -0.01em; margin-bottom: 0.25rem; }
 p.intro { max-width: 66ch; color: #444; font-size: .9rem; }
 .stage { margin-top: 1.25rem; }
 .collabels { display: grid; grid-template-columns: repeat(21, 1fr); gap: 0;
              margin-bottom: 2px; }
 .collabels span { font-size: 9px; color: var(--muted); writing-mode: vertical-rl;
                   transform: rotate(180deg); height: 4.4rem; justify-self: center; }
 .certs { display: grid; grid-template-columns: repeat(21, 1fr); height: 14px;
          margin-bottom: 3px; }
 .certs i { border-radius: 50%; width: 8px; height: 8px; justify-self: center;
            opacity: 0; transition: opacity .4s, box-shadow .4s; }
 .certs i.known { box-shadow: 0 0 0 2px #fff, 0 0 0 3.5px var(--ink); }
 canvas { width: 100%; display: block; border: 1px solid var(--hairline); }
 .rail { display: flex; gap: 1.25rem; align-items: baseline;
         font-size: .85rem; min-height: 1.4rem; }
 .rail .count { font-variant-numeric: tabular-nums; color: var(--muted); }
 .rail .verdict { color: var(--accent); font-weight: 600; }
 .rail .gap { color: var(--accent); font-size: .78rem; }
 .controls { display: flex; gap: .75rem; align-items: center; margin-top: .35rem; }
 .controls button { font: inherit; font-size: .9rem; padding: .2rem .7rem;
                    border: 1px solid var(--ink); background: #fff; cursor: pointer; }
 .controls button:hover { background: var(--ink); color: #fff; }
 .controls input[type=range] { flex: 1; accent-color: var(--accent); }
 .top { position: sticky; top: 0; z-index: 5; background: #fff;
        padding: .4rem 0 .5rem; border-bottom: 1px solid var(--hairline); }
 #chart { display: block; width: 100%; height: 96px; margin-top: .4rem;
          cursor: crosshair; }
 .legend { display: flex; gap: 1rem; margin-top: .9rem; font-size: .75rem;
           color: var(--muted); flex-wrap: wrap; }
 .legend i { display: inline-block; width: 10px; height: 10px; margin-right: .3rem;
             vertical-align: -1px; }
</style>
<h1>The model space</h1>
<p class="intro">Seed __SEED__, __PLAYERS__ players. Every row is one complete world —
an assignment of all 21 cards to hands and envelope — consistent with the public
transcript; every column is a card, coloured by where that world puts it. Before
__P0E__ the space is astronomically large, so the page begins at the first event
after which <em>every</em> consistent world fits on one page — all __NWORLDS__ of
them, the totality, not a sample. Each further event kills the worlds it
contradicts. When a column goes monochrome, that card's place is certain — it gets
a dot, and an ink ring once the watcher's notebook knows it too. When the three
red columns agree, the space itself has solved the murder.</p>
<div class="stage">
  <div class="top">
    <div class="rail">
      <span id="evline">—</span>
      <span class="count" id="count"></span>
      <span class="verdict" id="verdict"></span>
      <span class="gap" id="gapline"></span>
    </div>
    <div class="controls">
      <button id="b0">⏮</button><button id="bb">◀</button>
      <button id="bp">▶</button><button id="bf">▶▶</button><button id="be">⏭</button>
      <input type="range" id="scrub" min="0" step="1">
      <span class="count" id="pos"></span>
    </div>
    <svg id="chart"></svg>
  </div>
  <div class="collabels" id="collabels"></div>
  <div class="certs" id="certs"></div>
  <canvas id="cv"></canvas>
  <div class="legend" id="legend"></div>
</div>
<script>
const D = __DATA__;
// players in pastel so the envelope red is the only loud colour on
// the field — late in the collapse the eye keys on red + the dots
const PLAYER_COLOURS = ["#aabfd8","#dbc79c","#abc9b5","#c3b6da","#d8abbc","#abd2ce"];
const ENV_COLOUR = "#d92b2b";
const colour = loc => loc === D.players ? ENV_COLOUR : PLAYER_COLOURS[loc];
const W = D.worlds.length;

// deaths by position -> death position per world (Infinity = survives)
const dieAt = new Array(W).fill(Infinity);
for (const [pos, idxs] of Object.entries(D.deaths))
  for (const i of idxs) dieAt[i] = +pos;

const aliveAt = pos => {
  const out = [];
  for (let i = 0; i < W; i++) if (dieAt[i] > pos) out.push(i);
  return out;
};

// ---- static chrome
const labels = document.getElementById("collabels");
D.cardNames.forEach(nm => {
  const s = document.createElement("span"); s.textContent = nm; labels.appendChild(s);
});
const certsEl = document.getElementById("certs");
const certDots = D.cardNames.map(() => {
  const i = document.createElement("i"); certsEl.appendChild(i); return i;
});
const legend = document.getElementById("legend");
for (let p = 0; p < D.players; p++) {
  const s = document.createElement("span");
  s.innerHTML = `<i style="background:${PLAYER_COLOURS[p]}"></i>${String.fromCharCode(65+p)} holds it`;
  legend.appendChild(s);
}
const es = document.createElement("span");
es.innerHTML = `<i style="background:${ENV_COLOUR}"></i>in the envelope`;
legend.appendChild(es);

// ---- the collapse curve: worlds alive per position, on log paper.
// The solve markers live here; clicking anywhere on it scrubs.
const counts = [];
for (let p = D.p0; p <= D.total; p++) {
  let n = 0;
  for (let i = 0; i < W; i++) if (dieAt[i] > p) n++;
  counts.push(n);
}
const chart = document.getElementById("chart");
const NS = "http://www.w3.org/2000/svg";
const CW = 860, CHH = 96, PADL = 34, PADR = 10, PADT = 16, PADB = 6;
chart.setAttribute("viewBox", `0 0 ${CW} ${CHH}`);
chart.setAttribute("preserveAspectRatio", "none");
const xOf = p => PADL + (CW - PADL - PADR) * (p - D.p0) / (D.total - D.p0);
const maxLog = Math.log10(counts[0]);
const yOf = n => PADT + (CHH - PADT - PADB) * (1 - Math.log10(Math.max(n, 1)) / maxLog);
function svgEl(tag, attrs, text) {
  const e = document.createElementNS(NS, tag);
  for (const k in attrs) e.setAttribute(k, attrs[k]);
  if (text != null) e.textContent = text;
  chart.appendChild(e); return e;
}
// decade gridlines — the log paper
for (let k = 0; Math.pow(10, k) <= counts[0]; k++) {
  const y = yOf(Math.pow(10, k));
  svgEl("line", { x1: PADL, y1: y, x2: CW - PADR, y2: y,
                  stroke: "#e6e6e6", "stroke-width": 1 });
  svgEl("text", { x: PADL - 5, y: y + 3, "text-anchor": "end",
                  "font-size": 9, fill: "#767676" }, Math.pow(10, k).toLocaleString());
}
// the curve, step-after
let d = `M ${xOf(D.p0)} ${yOf(counts[0])}`;
for (let p = D.p0 + 1; p <= D.total; p++)
  d += ` H ${xOf(p)} V ${yOf(counts[p - D.p0])}`;
svgEl("path", { d, fill: "none", stroke: "#141414", "stroke-width": 1.4 });
// solve markers
function chartMarker(pos, label, col) {
  if (pos == null) return;
  const x = xOf(pos);
  svgEl("line", { x1: x, y1: PADT - 4, x2: x, y2: CHH - PADB,
                  stroke: col, "stroke-width": 1, "stroke-dasharray": "3 3" });
  svgEl("text", { x: Math.min(x, CW - 150), y: 9, "font-size": 9, fill: col,
                  "text-anchor": x > CW - 160 ? "end" : "start" }, label);
}
if (D.optimalSolvedAt != null && D.optimalSolvedAt === D.engineSolvedAt) {
  chartMarker(D.optimalSolvedAt, `space and notebook agree · E${D.optimalSolvedAt-1}`, ENV_COLOUR);
} else {
  if (D.optimalSolvedAt != null)
    chartMarker(D.optimalSolvedAt, `space pins the envelope · E${D.optimalSolvedAt-1}`, ENV_COLOUR);
  if (D.engineSolvedAt != null)
    chartMarker(D.engineSolvedAt, `notebook catches up · E${D.engineSolvedAt-1}`, "#141414");
}
// the cursor: a line and a dot riding the curve
const curLine = svgEl("line", { y1: PADT - 4, y2: CHH - PADB,
                                stroke: ENV_COLOUR, "stroke-width": 1.2 });
const curDot = svgEl("circle", { r: 3, fill: ENV_COLOUR });
function updateChart() {
  const x = xOf(position), y = yOf(counts[position - D.p0]);
  curLine.setAttribute("x1", x); curLine.setAttribute("x2", x);
  curDot.setAttribute("cx", x); curDot.setAttribute("cy", y);
}
// click (or drag) to scrub
function chartSeek(e) {
  const r = chart.getBoundingClientRect();
  const frac = ((e.clientX - r.left) / r.width * CW - PADL) / (CW - PADL - PADR);
  stop(); goTo(Math.round(D.p0 + frac * (D.total - D.p0)));
}
chart.addEventListener("click", chartSeek);
chart.addEventListener("mousemove", e => { if (e.buttons & 1) chartSeek(e); });

// ---- canvas
const cv = document.getElementById("cv");
const ctx = cv.getContext("2d");
const CSS_H = Math.min(1100, Math.max(620, Math.round(W * 0.85)));
function sizeCanvas() {
  const dpr = window.devicePixelRatio || 1;
  cv.width = cv.clientWidth * dpr;
  cv.height = CSS_H * dpr;
  cv.style.height = CSS_H + "px";
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
}

// per-world animation state: y, h, alpha (targets set on position change)
const rows = D.worlds.map(() => ({ y: 0, h: 0, a: 1, ty: 0, th: 0, ta: 1 }));
let position = 0;

function retarget() {
  const alive = aliveAt(position);
  const h = Math.min(24, CSS_H / Math.max(alive.length, 26));
  const gap = h > 6 ? 1 : 0;
  alive.forEach((w, slot) => {
    const r = rows[w];
    r.ty = slot * (h + gap); r.th = h; r.ta = 1;
  });
  for (let i = 0; i < W; i++) if (dieAt[i] <= position) {
    const r = rows[i]; r.ta = 0; r.th = Math.min(r.th, 2);
  }
  updateChrome(alive);
  kick();
}

function updateChrome(alive) {
  // certainty dots: filled when every surviving world agrees on the
  // column; ink-ringed once the engine's notebook knows it too. A dot
  // without a ring IS the completeness gap, per card, live.
  let gap = 0;
  for (let c = 0; c < 21; c++) {
    let loc = alive.length ? D.worlds[alive[0]][c] : -1;
    for (const w of alive) if (D.worlds[w][c] !== loc) { loc = -1; break; }
    const dot = certDots[c];
    const known = D.cardKnownAt[c] != null && position >= D.cardKnownAt[c];
    if (loc >= 0) {
      dot.style.background = colour(loc); dot.style.opacity = 1;
      dot.classList.toggle("known", known);
      if (!known) gap++;
    } else {
      dot.style.opacity = 0; dot.classList.remove("known");
    }
  }
  document.getElementById("gapline").textContent =
    gap > 0 ? `${gap} card${gap > 1 ? "s" : ""} the space knows and the notebook doesn't` : "";
  document.getElementById("count").textContent =
    `${alive.length.toLocaleString()} worlds remain`;
  document.getElementById("evline").textContent =
    `E${position-1} · ${D.labels[position-1]}`;
  const v = document.getElementById("verdict");
  v.textContent = (D.optimalSolvedAt != null && position >= D.optimalSolvedAt)
    ? "the space has pinned the envelope" : "";
  document.getElementById("pos").textContent = `E${position-1} / E${D.total-1}`;
  document.getElementById("scrub").value = position;
  updateChart();
}

// ---- draw loop (runs only while something is moving)
const COLS = 21;
let running = false, last = 0;
function kick() { if (!running) { running = true; last = performance.now(); requestAnimationFrame(tick); } }
function tick(now) {
  const dt = Math.min(50, now - last); last = now;
  const k = 1 - Math.pow(0.002, dt / 900); // exponential approach, ~900ms to settle
  let moving = false;
  for (const r of rows) {
    r.y += (r.ty - r.y) * k; r.h += (r.th - r.h) * k; r.a += (r.ta - r.a) * k;
    if (Math.abs(r.ty - r.y) > 0.2 || Math.abs(r.th - r.h) > 0.1 || Math.abs(r.ta - r.a) > 0.01)
      moving = true;
  }
  draw();
  if (moving) requestAnimationFrame(tick); else { running = false; draw(true); }
}
function draw(snap) {
  const w = cv.clientWidth;
  const colW = w / COLS;
  ctx.clearRect(0, 0, w, CSS_H);
  for (let i = 0; i < W; i++) {
    const r = rows[i];
    const a = snap ? r.ta : r.a;
    if (a < 0.01) continue;
    const y = snap ? r.ty : r.y, h = Math.max(0.4, snap ? r.th : r.h);
    if (y > CSS_H) continue;
    ctx.globalAlpha = a;
    const world = D.worlds[i];
    for (let c = 0; c < COLS; c++) {
      ctx.fillStyle = colour(world[c]);
      ctx.fillRect(c * colW + 0.5, y, colW - 1, h);
    }
  }
  ctx.globalAlpha = 1;
}

// ---- transport
const scrub = document.getElementById("scrub");
scrub.min = D.p0;
scrub.max = D.total;
function goTo(p) { position = Math.max(D.p0, Math.min(D.total, p)); retarget(); }
document.getElementById("b0").onclick = () => { stop(); goTo(D.p0); };
document.getElementById("bb").onclick = () => { stop(); goTo(position - 1); };
document.getElementById("bf").onclick = () => { stop(); goTo(position + 1); };
document.getElementById("be").onclick = () => { stop(); goTo(D.total); };
scrub.oninput = () => { stop(); goTo(+scrub.value); };

let player = null;
const bp = document.getElementById("bp");
function stop() { if (player) { clearInterval(player); player = null; bp.textContent = "▶"; } }
bp.onclick = () => {
  if (player) { stop(); return; }
  if (position >= D.total) goTo(D.p0);
  bp.textContent = "⏸";
  player = setInterval(() => {
    // skip straight to the next informative event so the collapse keeps pace
    let next = position + 1;
    while (next < D.total && !D.informative[next - 1]) next++;
    goTo(next);
    if (position >= D.total) stop();
  }, 950);
};

window.addEventListener("resize", () => { sizeCanvas(); retarget(); });
sizeCanvas();
goTo(Math.max(0, D.p0));
</script>
"""


if __name__ == "__main__":
    main()
