#!/usr/bin/env python3
"""The bettor (the Watcher-Watcher): EV over proof, as a page.

The engine proves (⊢) and Z3 entails (⊨); both wait for certainty. The
bettor sits behind the watcher and makes a CALL: under a uniform prior
over deals, the posterior over envelope triples is world-counting, and
the risk of waiting is the chance some rival is ALREADY certain. Both
are computable from the same enumeration the worlds pages use — no new
machinery, just counting:

  P(triple)    = surviving worlds with that envelope / all survivors
  hazard       = fraction of survivors in which some rival's view
                 (their exact hand in that world, plus the cards shown
                 to them, resolved in that world) pins the envelope

The rival model is semantic (⊨-strong): a rival is "certain" when every
surviving world consistent with their view agrees on the envelope. That
is an upper bound on any real rival; our probes found the engine's
timing equals the optimum on the envelope, so the bound is tight in
practice.

Decision rule (arbitrary but explainable — we don't have to beat a
market): bet at the first position where

  P(top) >= THETA                        (confident), or
  P(top) >= 0.5 and P(top) > 1 - hazard  (forced by the race)

strictly before the winning accusation. Before the space is countable
(<= cap worlds) the bettor is asleep — no posterior, no bet.

Usage:
  spago run --quiet -p kibitzer-example -- trace 33 --players 6 > smt/trace-33.json
  smt/.venv/bin/python smt/bettor.py smt/trace-33.json > frontend/public/bettor.html
  smt/.venv/bin/python smt/bettor.py smt/trace-33.json --validation smt/bettor-validation.jsonl > frontend/public/bettor.html

  spago run --quiet -p kibitzer-example -- traces 200 --players 6 > smt/traces-6p.jsonl
  smt/.venv/bin/python smt/bettor.py --validate smt/traces-6p.jsonl > smt/bettor-validation.jsonl
"""

import argparse
import json
import math
import sys

from worlds_trace import CARD_SHORT, base_solver, constraints_upto, enumerate_worlds, satisfies

THETA = 0.9
FLOOR = 0.5


def find_p0(trace, cap):
    """First position where the space fits (monotone -> binary search)."""
    lo, hi = 0, len(trace["events"])
    while lo < hi:
        mid = (lo + hi) // 2
        n = len(enumerate_worlds(trace, mid, cap))
        if n > cap:
            lo = mid + 1
        else:
            hi = mid
    return lo


def shows_to(trace, rival):
    """(position, shower, cards) for every card shown TO this rival —
    position is the index AFTER the event lands, matching replay."""
    out = []
    for i, e in enumerate(trace["events"]):
        k = e["constraint"]
        if k and k["type"] == "show" and k.get("to") == rival:
            out.append((i + 1, k["player"], tuple(k["cards"])))
    return out


def resolve_shown(world, shower, cards):
    """Which card the rival saw, if the deal were this world: canonical
    lowest-index match (the sim picks uniformly; any deterministic pick
    is as good a sample — a stated modelling assumption)."""
    for c in cards:
        if world[c] == shower:
            return c
    return None  # world violates the show constraint; caller filters first


def bettor_series(trace, cap, log=lambda *_: None):
    """The full bettor timeline: per position from p0, the posterior top,
    the hazard, and the decision — plus the markers the page narrates."""
    n = trace["players"]
    env = n
    total = len(trace["events"])

    p0 = find_p0(trace, cap)
    worlds = enumerate_worlds(trace, p0, cap)
    if not worlds or len(worlds) > cap:
        return None  # never countable: the bettor sleeps through the game
    log(f"space fits at position {p0}: {len(worlds)} worlds")

    def envelope_of(w):
        return tuple(c for c in range(21) if w[c] == env)

    # per world, per rival: the rival's exact hand (frozenset)
    hands = [
        [frozenset(c for c in range(21) if w[c] == r) for r in range(n)]
        for w in worlds
    ]
    rival_shows = [shows_to(trace, r) for r in range(n)]

    def hazard_at(pos, alive):
        """Fraction of survivors in which some rival's view pins the
        envelope. A rival's consistent set lives inside their own
        same-hand group, so all scans are within groups."""
        certain = set()
        for r in range(n):
            shows = [s for s in rival_shows[r] if s[0] <= pos]
            groups = {}
            for i in alive:
                groups.setdefault(hands[i][r], []).append(i)
            for group in groups.values():
                verdicts = {}
                for i in group:
                    seen = tuple(resolve_shown(worlds[i], b, cs) for _, b, cs in shows)
                    if seen not in verdicts:
                        triple = envelope_of(worlds[i])
                        ok = True
                        for j in group:
                            if any(worlds[j][c] != b for c, (_, b, _cs) in zip(seen, shows)):
                                continue  # j inconsistent with what r saw
                            if envelope_of(worlds[j]) != triple:
                                ok = False
                                break
                        verdicts[seen] = ok
                    if verdicts[seen]:
                        certain.add(i)
        return len(certain) / len(alive) if alive else 0.0

    # replay: survivors per position, posterior + hazard at each
    ends_with_accusation = "accuses" in trace["events"][-1]["label"]
    last_bettable = total - 1 if ends_with_accusation else total
    solution = tuple(sorted(trace["solution"]))

    alive = list(range(len(worlds)))
    series = []
    proof_at = None
    bet = None
    for pos in range(p0, total + 1):
        if pos > p0:
            k = trace["events"][pos - 1]["constraint"]
            if k is not None:
                alive = [i for i in alive if satisfies(worlds[i], k)]
        counts = {}
        for i in alive:
            t = envelope_of(worlds[i])
            counts[t] = counts.get(t, 0) + 1
        top, top_n = max(counts.items(), key=lambda kv: kv[1])
        p_top = top_n / len(alive)
        hz = hazard_at(pos, alive)
        series.append({
            "pos": pos,
            "count": len(alive),
            "pTop": round(p_top, 4),
            "hazard": round(hz, 4),
            "top": sorted(top),
        })
        if proof_at is None and len(counts) == 1:
            proof_at = pos
        if bet is None and pos <= last_bettable and (
            p_top >= THETA or (p_top >= FLOOR and p_top > 1.0 - hz)
        ):
            bet = {
                "at": pos,
                "pTop": round(p_top, 4),
                "hazard": round(hz, 4),
                "triple": sorted(top),
                "correct": tuple(sorted(top)) == solution,
            }
    return {
        "p0": p0,
        "nWorlds": len(worlds),
        "total": total,
        "endsWithAccusation": ends_with_accusation,
        "proofAt": proof_at,
        "engineSolvedAt": trace["engineSolvedAt"],
        "bet": bet,
        "series": series,
    }


# ---------------------------------------------------------------------------
# validate mode: run the bettor silently over a corpus of traces

def _validate_one(job):
    line, cap = job
    trace = json.loads(line)
    r = bettor_series(trace, cap)
    row = {
        "seed": trace["seed"],
        "players": trace["players"],
        "total": len(trace["events"]),
    }
    if r is None:
        row.update({"p0": None, "proofAt": None,
                    "engineSolvedAt": trace["engineSolvedAt"], "bet": None})
    else:
        row.update({k: r[k] for k in
                    ("p0", "nWorlds", "proofAt", "engineSolvedAt", "bet")})
    return row


def validate(path, cap, jobs):
    import multiprocessing as mp
    lines = [l.strip() for l in open(path) if l.strip()]
    results = []
    with mp.get_context("spawn").Pool(jobs) as pool:
        for row in pool.imap(_validate_one, [(l, cap) for l in lines]):
            results.append(row)
            b = row["bet"]
            print(f"seed {row['seed']}: " + (
                f"bet@{b['at']} P={b['pTop']} hz={b['hazard']} "
                f"{'CORRECT' if b['correct'] else 'WRONG'} "
                f"(proof@{row['proofAt']}, engine@{row['engineSolvedAt']}, end {row['total']})"
                if b else
                f"abstains (p0={row.get('p0')}, proof@{row.get('proofAt')}, end {row['total']})"
            ), file=sys.stderr)
            print(json.dumps(row), flush=True)
    summarize(results, sys.stderr)


def summarize(results, out):
    bets = [r for r in results if r["bet"]]
    correct = [r for r in bets if r["bet"]["correct"]]
    print(f"\n{len(results)} games: {len(bets)} bets, "
          f"{len(correct)} correct ({100 * len(correct) / max(1, len(bets)):.0f}%), "
          f"{len(results) - len(bets)} abstains", file=out)
    leads_proof = [r["proofAt"] - r["bet"]["at"] for r in bets if r["proofAt"] is not None]
    leads_engine = [r["engineSolvedAt"] - r["bet"]["at"] for r in bets
                    if r["engineSolvedAt"] is not None]
    if leads_proof:
        print(f"mean lead over ⊨ proof: {sum(leads_proof) / len(leads_proof):.1f} events "
              f"(max {max(leads_proof)})", file=out)
    if leads_engine:
        print(f"mean lead over ⊢ engine: {sum(leads_engine) / len(leads_engine):.1f} events "
              f"(max {max(leads_engine)})", file=out)
    # calibration: stated confidence vs realised accuracy
    buckets = {}
    for r in bets:
        b = min(9, int(r["bet"]["pTop"] * 10))
        buckets.setdefault(b, []).append(r["bet"]["correct"])
    for b in sorted(buckets):
        got = buckets[b]
        print(f"  P in [{b / 10:.1f},{(b + 1) / 10:.1f}): {len(got)} bets, "
              f"{100 * sum(got) / len(got):.0f}% correct", file=out)


def validation_summary(path):
    """Digest a results JSONL into the numbers the page shows."""
    results = [json.loads(l) for l in open(path) if l.strip()]
    bets = [r for r in results if r["bet"]]
    correct = sum(1 for r in bets if r["bet"]["correct"])
    leads_proof = [r["proofAt"] - r["bet"]["at"] for r in bets if r["proofAt"] is not None]
    leads_engine = [r["engineSolvedAt"] - r["bet"]["at"] for r in bets
                    if r["engineSolvedAt"] is not None]
    buckets = {}
    for r in bets:
        b = min(9, int(r["bet"]["pTop"] * 10))
        buckets.setdefault(b, []).append(r["bet"]["correct"])
    confident = [r for r in bets if r["bet"]["pTop"] >= THETA]
    forced = [r for r in bets if r["bet"]["pTop"] < THETA]
    return {
        "games": len(results),
        "bets": len(bets),
        "correct": correct,
        "abstains": len(results) - len(bets),
        "confident": len(confident),
        "confidentEarly": sum(1 for r in confident
                              if r["proofAt"] is not None
                              and r["proofAt"] - r["bet"]["at"] > 0),
        "forced": len(forced),
        "forcedCorrect": sum(1 for r in forced if r["bet"]["correct"]),
        "forcedMeanP": round(sum(r["bet"]["pTop"] for r in forced) / len(forced), 3)
                       if forced else None,
        "meanLeadProof": round(sum(leads_proof) / len(leads_proof), 1) if leads_proof else None,
        "maxLeadProof": max(leads_proof) if leads_proof else None,
        "meanLeadEngine": round(sum(leads_engine) / len(leads_engine), 1) if leads_engine else None,
        "calibration": [
            {"lo": b / 10, "hi": (b + 1) / 10,
             "n": len(buckets[b]), "correct": sum(buckets[b])}
            for b in sorted(buckets)
        ],
    }


# ---------------------------------------------------------------------------
# the page

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("trace", nargs="?")
    ap.add_argument("--cap", type=int, default=1500)
    ap.add_argument("--validate", help="traces JSONL: run the corpus, emit results JSONL")
    ap.add_argument("--validation", help="results JSONL from a prior --validate run, for the page")
    ap.add_argument("--jobs", type=int, default=6, help="parallel workers for --validate")
    args = ap.parse_args()

    if args.validate:
        validate(args.validate, args.cap, args.jobs)
        return

    trace = json.load(open(args.trace))
    r = bettor_series(trace, args.cap, log=lambda *a: print(*a, file=sys.stderr))
    if r is None:
        print("the space never fits under the cap — the bettor sleeps; no page",
              file=sys.stderr)
        sys.exit(1)
    b = r["bet"]
    print(
        f"bet: {b}" if b else "abstains", file=sys.stderr)

    data = {
        "seed": trace["seed"],
        "players": trace["players"],
        "cap": args.cap,
        "theta": THETA,
        "cardNames": CARD_SHORT,
        "solution": sorted(trace["solution"]),
        "eventLabels": [e["label"] for e in trace["events"]],
        "validation": validation_summary(args.validation) if args.validation else None,
        **{k: r[k] for k in ("p0", "nWorlds", "total", "proofAt",
                             "engineSolvedAt", "bet", "series")},
    }
    print(PAGE_TEMPLATE
          .replace("__DATA__", json.dumps(data))
          .replace("__THETA__", str(THETA))
          .replace("__CAP__", f"{args.cap:,}"))


PAGE_TEMPLATE = r"""<!doctype html><meta charset="utf-8">
<title>kibitzer — the bettor</title>
<style>
 :root { --ink: #141414; --muted: #767676; --accent: #d92b2b; --hairline: #e6e6e6;
         --bet: #1f6f43; }
 body { font-family: "Helvetica Neue", Arial, sans-serif; color: var(--ink);
        max-width: 62rem; margin: 2rem auto; padding: 0 1.5rem; }
 h1 { font-size: 1.4rem; letter-spacing: -0.01em; margin-bottom: 0.25rem; }
 h2 { font-size: 1.0rem; margin: 2rem 0 .4rem; }
 p.intro, p.body { max-width: 66ch; color: #444; font-size: .9rem; }
 .verdict { margin: 1.4rem 0; padding: 1rem 1.2rem; border-left: 4px solid var(--bet); }
 .verdict.wrong { border-left-color: var(--accent); }
 .verdict.abstain { border-left-color: var(--muted); }
 .verdict .call { font-size: 1.25rem; font-weight: 700; letter-spacing: -0.01em; }
 .verdict .detail { font-size: .85rem; color: var(--muted); margin-top: .3rem; }
 svg.chart { display: block; width: 100%; border: 1px solid var(--hairline);
             margin-top: .4rem; }
 .legend { display: flex; gap: 1.2rem; margin-top: .5rem; font-size: .75rem;
           color: var(--muted); flex-wrap: wrap; }
 .legend i { display: inline-block; width: 14px; height: 3px; margin-right: .35rem;
             vertical-align: 3px; }
 table { border-collapse: collapse; font-size: .85rem; margin-top: .6rem; }
 th, td { text-align: right; padding: .25rem .8rem; border-bottom: 1px solid var(--hairline); }
 th:first-child, td:first-child { text-align: left; }
 .assume { font-size: .8rem; color: var(--muted); max-width: 66ch; }
 .assume li { margin-bottom: .3rem; }
 .num { font-variant-numeric: tabular-nums; }
</style>
<h1>The bettor</h1>
<p class="intro">The engine <em>proves</em> (⊢); the solver <em>entails</em> (⊨);
both wait for certainty. The bettor makes a call. Under a uniform prior over
deals, the probability of an envelope triple is just the fraction of surviving
worlds that contain it — the worlds page, read as a distribution. The risk of
waiting is the chance some rival is <em>already</em> certain — measurable over
the same worlds, because inside each world every rival's hand (and everything
they were shown) is fixed. Bet when confidence clears __THETA__, or when the
race forces your hand: when the chance a rival has it beats your own chance of
being wrong.</p>

<div id="verdict" class="verdict"></div>

<h2>The race, position by position</h2>
<p class="body">The bettor wakes at <span class="num" id="wakeE"></span>, when
the space first fits under __CAP__ worlds (before that there is no countable
posterior — it is asleep, honestly). From there: confidence is the posterior
mass of the leading triple; hazard is the share of worlds in which at least
one rival's view already pins the envelope.</p>
<svg class="chart" id="belief" height="220"></svg>
<div class="legend">
  <span><i style="background:#1f6f43"></i>P(top triple) — confidence</span>
  <span><i style="background:#d92b2b"></i>hazard — a rival is already certain</span>
  <span><i style="background:#141414; height:1px"></i>θ = __THETA__</span>
</div>
<svg class="chart" id="counts" height="130"></svg>
<div class="legend">
  <span><i style="background:#767676"></i>surviving worlds (log scale)</span>
</div>

<h2 id="valh" style="display:none">Does it pay? The silent-run validation</h2>
<div id="validation"></div>

<h2>What the bettor assumes</h2>
<ul class="assume">
  <li><b>Uniform prior.</b> Every deal consistent with the transcript is
      equally likely. True of the shuffle; it ignores what players' <em>choices</em>
      leak (a player rarely suggests cards she holds) — the posterior here is
      counting, not psychology.</li>
  <li><b>Perfect-logician rivals, measured semantically.</b> A rival counts as
      certain when every surviving world consistent with their view (their
      exact hand, plus the cards shown to them) agrees on the envelope. That is
      an upper bound on any real rival — and a tight one: on every six-player
      seed probed, the engine's envelope timing equalled this optimum.</li>
  <li><b>Canonical shown-card resolution.</b> Inside a hypothetical world, when
      a shower holds more than one matching card, the bettor assumes the
      lowest-numbered one was shown. The simulation actually picks uniformly;
      any deterministic pick is one sample from that coin.</li>
  <li><b>It sleeps until the space is countable.</b> No posterior is offered
      while the world count exceeds the cap — no pretence of precision over an
      unenumerated space.</li>
</ul>
<script>
const D = __DATA__;
const name = c => D.cardNames[c];
const tripleName = t => t.map(name).join(" + ");
const E = pos => pos === 0 ? "the deal" : "E" + (pos - 1);

// ---- verdict box
const v = document.getElementById("verdict");
if (D.bet) {
  const b = D.bet;
  const right = b.correct;
  v.className = "verdict" + (right ? "" : " wrong");
  const leadProof = D.proofAt != null ? D.proofAt - b.at : null;
  const leadEngine = D.engineSolvedAt != null ? D.engineSolvedAt - b.at : null;
  const leadLine =
    leadProof != null && leadProof > 0
      ? ` · ${leadProof} events before the space could prove it` +
        (leadEngine != null && leadEngine !== leadProof
          ? `, ${leadEngine} before the notebook` : "")
      : ` · exactly at the proof moment — this seed offered no earlier call`;
  v.innerHTML =
    `<div class="call">Bets <em>${tripleName(b.triple)}</em> at ${E(b.at)} — ` +
    `${right ? "correct" : "wrong"}.</div>` +
    `<div class="detail">confidence ${(100 * b.pTop).toFixed(0)}%, ` +
    `hazard ${(100 * b.hazard).toFixed(0)}%` + leadLine +
    ` · seed ${D.seed}, ${D.players} players, game ends at ${E(D.total)}</div>`;
} else {
  v.className = "verdict abstain";
  v.innerHTML = `<div class="call">Lets it run.</div>` +
    `<div class="detail">confidence never cleared the bar before the accusation — ` +
    `seed ${D.seed}, ${D.players} players</div>`;
}
document.getElementById("wakeE").textContent = E(D.p0);

// ---- charts
function chart(el, w, h, pad) {
  el.setAttribute("viewBox", `0 0 ${w} ${h}`);
  const x = pos => pad.l + (pos - D.p0) / (D.total - D.p0) * (w - pad.l - pad.r);
  return { el, w, h, pad, x,
    add(tag, attrs, text) {
      const n = document.createElementNS("http://www.w3.org/2000/svg", tag);
      for (const [k, val] of Object.entries(attrs)) n.setAttribute(k, val);
      if (text) n.textContent = text;
      el.appendChild(n); return n;
    } };
}

function markers(c, yTop, yBot) {
  // coincident positions share one line and one combined label
  const wanted = [];
  if (D.bet) wanted.push({ pos: D.bet.at, label: "bet", color: "#1f6f43", dash: null });
  if (D.proofAt != null)
    wanted.push({ pos: D.proofAt, label: "⊨ proof", color: "#141414", dash: "3,3" });
  if (D.engineSolvedAt != null)
    wanted.push({ pos: D.engineSolvedAt, label: "⊢ notebook", color: "#767676", dash: "3,3" });
  const byPos = new Map();
  for (const m of wanted) {
    if (byPos.has(m.pos)) byPos.get(m.pos).label += " = " + m.label;
    else byPos.set(m.pos, { ...m });
  }
  for (const m of byPos.values()) {
    c.add("line", { x1: c.x(m.pos), x2: c.x(m.pos), y1: yTop, y2: yBot,
                    stroke: m.color, "stroke-width": 1,
                    "stroke-dasharray": m.dash || "none" });
    const nearRight = c.x(m.pos) > c.w - 90;
    c.add("text", { x: c.x(m.pos) + (nearRight ? -3 : 3), y: yTop + 9,
                    "font-size": 9, fill: m.color,
                    "text-anchor": nearRight ? "end" : "start" }, m.label);
  }
}

// belief chart: P(top) + hazard, linear 0..1
{
  const c = chart(document.getElementById("belief"), 920, 220, { l: 38, r: 14, t: 8, b: 18 });
  const y = p => c.pad.t + (1 - p) * (c.h - c.pad.t - c.pad.b);
  for (const g of [0, 0.25, 0.5, 0.75, 1]) {
    c.add("line", { x1: c.pad.l, x2: c.w - c.pad.r, y1: y(g), y2: y(g),
                    stroke: "#eee", "stroke-width": 1 });
    c.add("text", { x: c.pad.l - 5, y: y(g) + 3, "font-size": 9,
                    fill: "#767676", "text-anchor": "end" }, g.toFixed(2));
  }
  c.add("line", { x1: c.pad.l, x2: c.w - c.pad.r, y1: y(D.theta), y2: y(D.theta),
                  stroke: "#141414", "stroke-width": 0.7, "stroke-dasharray": "5,4" });
  const path = key => D.series.map((s, i) =>
    (i ? "L" : "M") + c.x(s.pos).toFixed(1) + " " + y(s[key]).toFixed(1)).join(" ");
  c.add("path", { d: path("pTop"), fill: "none", stroke: "#1f6f43", "stroke-width": 2 });
  // dashed so it stays visible where it rides exactly on the confidence line
  c.add("path", { d: path("hazard"), fill: "none", stroke: "#d92b2b",
                  "stroke-width": 1.6, "stroke-dasharray": "6,4" });
  markers(c, c.pad.t, c.h - c.pad.b);
  const step = Math.max(1, Math.round((D.total - D.p0) / 10));
  for (const s of D.series) if ((s.pos - D.p0) % step === 0 || s.pos === D.total)
    c.add("text", { x: c.x(s.pos), y: c.h - 4, "font-size": 9, fill: "#767676",
                    "text-anchor": "middle" }, E(s.pos));
}

// counts chart: world count, log scale
{
  const c = chart(document.getElementById("counts"), 920, 130, { l: 38, r: 14, t: 8, b: 18 });
  const lmax = Math.log10(D.series[0].count);
  const y = n => c.pad.t + (1 - Math.log10(Math.max(1, n)) / Math.max(1e-9, lmax))
                 * (c.h - c.pad.t - c.pad.b);
  for (let d = 0; d <= Math.ceil(lmax); d++) {
    c.add("line", { x1: c.pad.l, x2: c.w - c.pad.r, y1: y(10 ** d), y2: y(10 ** d),
                    stroke: "#eee", "stroke-width": 1 });
    c.add("text", { x: c.pad.l - 5, y: y(10 ** d) + 3, "font-size": 9,
                    fill: "#767676", "text-anchor": "end" },
          (10 ** d).toLocaleString("en-US"));
  }
  const d = D.series.map((s, i) =>
    (i ? "L" : "M") + c.x(s.pos).toFixed(1) + " " + y(s.count).toFixed(1)).join(" ");
  c.add("path", { d, fill: "none", stroke: "#767676", "stroke-width": 1.6 });
  markers(c, c.pad.t, c.h - c.pad.b);
  const step = Math.max(1, Math.round((D.total - D.p0) / 10));
  for (const s of D.series) if ((s.pos - D.p0) % step === 0 || s.pos === D.total)
    c.add("text", { x: c.x(s.pos), y: c.h - 4, "font-size": 9, fill: "#767676",
                    "text-anchor": "middle" }, E(s.pos));
}

// ---- validation table
if (D.validation) {
  const val = D.validation;
  document.getElementById("valh").style.display = "";
  const el = document.getElementById("validation");
  const pct = (a, b) => b ? (100 * a / b).toFixed(0) + "%" : "—";
  let html =
    `<p class="body">${val.games} games run silently (same players, same policy, ` +
    `seeds 1–${val.games}). The bettor placed <b>${val.bets}</b> bets ` +
    `(${pct(val.bets, val.games)} of games) and was right in ` +
    `<b>${val.correct}</b> of them (${pct(val.correct, val.bets)}). ` +
    (val.meanLeadProof != null ?
      `On average the bet landed <b>${val.meanLeadProof}</b> events before the ` +
      `space could prove the answer (best: ${val.maxLeadProof})` +
      (val.meanLeadEngine != null ?
        ` and ${val.meanLeadEngine} before the notebook` : "") + ". " : "") +
    `It abstained ${val.abstains} times rather than guess under the bar.</p>` +
    `<table><tr><th>stated confidence</th><th>bets</th><th>correct</th><th>realised</th></tr>`;
  for (const r of val.calibration)
    html += `<tr><td>${r.lo.toFixed(1)}–${r.hi.toFixed(1)}</td>` +
            `<td class="num">${r.n}</td><td class="num">${r.correct}</td>` +
            `<td class="num">${pct(r.correct, r.n)}</td></tr>`;
  html += `</table>` +
    `<p class="body">Calibration is the honesty test: a bettor who says "90%" ` +
    `should be right about nine times in ten. If the realised column tracks the ` +
    `stated one, the uniform-prior posterior is telling the truth.</p>`;
  if (val.confident > 0 && val.confidentEarly === 0)
    html +=
      `<p class="body"><b>The finding:</b> none of the ${val.confident} confident ` +
      `bets (P ≥ ${D.theta}) preceded proof — in this game the posterior does not ` +
      `climb, it <em>snaps</em>: constraints kill triples in blocks, so the space ` +
      `goes from ambiguous to certain in a step. The bettor's real edge is all in ` +
      `the forced clause: ${val.forced} priced coin flips (mean stated ` +
      `${(100 * val.forcedMeanP).toFixed(0)}%, realised ` +
      `${(100 * val.forcedCorrect / val.forced).toFixed(0)}%) taken because ` +
      `waiting meant near-certain loss to a rival. EV over proof, literally: not ` +
      `foresight — knowing when the race is lost, and taking the odds instead of ` +
      `nothing.</p>`;
  el.innerHTML = html;
}
</script>
"""


if __name__ == "__main__":
    main()
