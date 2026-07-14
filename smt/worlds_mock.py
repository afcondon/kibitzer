#!/usr/bin/env python3
"""Illustration of the 'collapsing worlds' visualization: sample the
deals still consistent with the public transcript at several positions
of the golden game (seed 42, 4 players, classic), using the same Z3
encoding as smt/optimal_watcher.py. Emits a static HTML mock."""

import json
import sys
from z3 import And, If, Int, Or, Solver, Sum, sat

CORPUS = sys.argv[1] if len(sys.argv) > 1 else "smt/corpus.jsonl"

SUSPECTS, WEAPONS, ROOMS = range(0, 6), range(6, 12), range(12, 21)
CATEGORIES = (SUSPECTS, WEAPONS, ROOMS)
CARD_SHORT = ["Sc","Mu","Wh","Gr","Pe","Pl","Ca","Kn","LP","Re","Ro","Wr",
              "Ki","Ba","Co","Di","Bi","Li","Lo","Ha","St"]

def load_game():
    for line in open(CORPUS):
        g = json.loads(line)
        if g["seed"] == 42 and g["players"] == 4 and not g["movement"]:
            return g
    raise SystemExit("seed 42 4p classic not in corpus")

def solver_for(game, prefix):
    n = game["players"]; env = n
    place = [Int(f"p{c}") for c in range(21)]
    s = Solver()
    for c in range(21):
        s.add(place[c] >= 0, place[c] <= env)
    for cat in CATEGORIES:
        s.add(Sum([If(place[c] == env, 1, 0) for c in cat]) == 1)
    for p in range(n):
        s.add(Sum([If(place[c] == p, 1, 0) for c in range(21)]) == game["handSizes"][p])
    for e in game["events"][:prefix]:
        if e["type"] == "pass":
            s.add(And([place[c] != e["player"] for c in e["cards"]]))
        else:
            s.add(Or([place[c] == e["by"] for c in e["cards"]]))
    return s, place, env

def sample_worlds(game, prefix, k):
    s, place, env = solver_for(game, prefix)
    worlds = []
    while len(worlds) < k and s.check() == sat:
        m = s.model()
        w = [m[place[c]].as_long() for c in range(21)]
        worlds.append(w)
        s.add(Or([place[c] != w[c] for c in range(21)]))
    return worlds

def count_worlds(game, prefix, cap):
    s, place, env = solver_for(game, prefix)
    count = 0
    while count < cap and s.check() == sat:
        m = s.model()
        s.add(Or([place[c] != m[place[c]].as_long() for c in range(21)]))
        count += 1
    return count, count >= cap

def certain_columns(game, prefix):
    s, place, env = solver_for(game, prefix)
    cols = []
    for c in range(21):
        vals = set()
        s.push(); ok = s.check() == sat
        if ok: vals.add(s.model()[place[c]].as_long())
        s.pop()
        for v in range(env + 1):
            if v in vals: continue
            s.push(); s.add(place[c] == v)
            if s.check() == sat: vals.add(v)
            s.pop()
        cols.append(vals)
    return cols

game = load_game()
E = len(game["events"])
prefixes = sorted(set([0, E//5, 2*E//5, 3*E//5, 4*E//5, E]))
K, CAP = 24, 1500
PLACE_COLOUR = ["#5f7fbf", "#c9973b", "#69a284", "#8b6bb0", "#d92b2b"]
PLACE_NAME = ["A", "B", "C", "D", "ENV"]

snapshots = []
for pre in prefixes:
    worlds = sample_worlds(game, pre, K)
    worlds.sort()
    n, capped = count_worlds(game, pre, CAP)
    certain = certain_columns(game, pre)
    snapshots.append({"prefix": pre, "worlds": worlds, "count": n,
                      "capped": capped, "certain": [len(v) == 1 for v in certain]})
    print(f"prefix {pre}: sampled {len(worlds)}, count {'>' if capped else ''}{n}, "
          f"settled {sum(1 for v in certain if len(v)==1)}/21")

CW, CH, GAP = 13, 9, 8
def svg_matrix(snap):
    rows = snap["worlds"]
    out = []
    x0 = 0
    xs = []
    for c in range(21):
        gap = (GAP if c in (6, 12) else 0)
        x0 += gap
        xs.append(x0)
        x0 += CW
    width = x0
    height = (len(rows)) * CH + 26
    out.append(f'<svg viewBox="0 0 {width} {height}" width="{width}">')
    for c in range(21):
        anchor = xs[c] + CW/2
        out.append(f'<text x="{anchor}" y="10" text-anchor="middle" font-size="7" fill="#767676">{CARD_SHORT[c]}</text>')
        if snap["certain"][c]:
            out.append(f'<circle cx="{anchor}" cy="17" r="2.4" fill="#d92b2b"/>')
    for r, w in enumerate(rows):
        y = 24 + r * CH
        for c in range(21):
            colour = PLACE_COLOUR[w[c]]
            out.append(f'<rect x="{xs[c]}" y="{y}" width="{CW-1.5}" height="{CH-1.5}" fill="{colour}" opacity="0.85"/>')
    out.append('</svg>')
    return "".join(out)

counts_html = " → ".join(
    (f'>{s["count"]}' if s["capped"] else str(s["count"])) for s in snapshots)

sections = []
for s in snapshots:
    label = f'after {s["prefix"]} of {E} public events'
    cnt = f'>{s["count"]} worlds remain' if s["capped"] else f'{s["count"]} worlds remain'
    settled = sum(1 for v in s["certain"] if v)
    sections.append(f'''
  <figure>
    <figcaption><strong>{label}</strong> · {cnt} · {settled}/21 cards settled</figcaption>
    {svg_matrix(s)}
  </figure>''')

legend = " ".join(
    f'<span style="color:{PLACE_COLOUR[i]}">■ {PLACE_NAME[i]}</span>'
    for i in range(5))

html = f'''<!doctype html><meta charset="utf-8">
<title>kibitzer — the collapsing worlds (illustration)</title>
<style>
 body {{ font-family: "Helvetica Neue", Arial, sans-serif; max-width: 60rem;
        margin: 2rem auto; padding: 0 1rem; color: #111; }}
 h1 {{ font-size: 1.3rem; }} p {{ max-width: 58ch; color: #444; font-size: .9rem; }}
 figure {{ margin: 1.6rem 0; }} figcaption {{ font-size: .8rem; margin-bottom: .4rem; }}
 .legend {{ font-size: .8rem; letter-spacing: .04em; }}
 .note {{ color: #767676; font-size: .8rem; }}
</style>
<h1>The collapsing worlds — seed 42, four players, classic (real Z3 samples)</h1>
<p>Each row is one complete deal still consistent with everything the watcher
has seen. Columns are the 21 cards; a cell's colour says where that card sits
in that world. A <span style="color:#d92b2b">red dot</span> over a column means
every consistent world agrees — the watcher is <em>certain</em>. Deduction is
watching columns go monochrome.</p>
<p class="legend">{legend}</p>
{''.join(sections)}
<p class="note">Worlds remaining along the game: {counts_html}
(counted by enumeration, capped at 1500). Sampled {K} worlds per position with
Z3 blocking clauses — the same encoding as smt/optimal_watcher.py. This game
ends unsolved for the watcher: the cloud never fully collapses, but five
columns go monochrome — one more than the propagation engine settles,
which is the completeness gap made visible.</p>
'''
open("worlds-mock.html", "w").write(html)
print("wrote worlds-mock.html")
