#!/usr/bin/env python3
"""The optimal watcher: Z3 plays maximal sound inference over kibitzer's
public transcripts.

The kibitzer engine is sound but deliberately incomplete — it propagates
certainties and never searches. This script computes, per game, everything
that is *logically* certain from the same public metadata (deck structure,
hand sizes, passes, shows), by encoding the transcript as finite-domain
constraints: a (card, place) statement is certain iff its negation is
unsatisfiable. Comparing against the engine's notebook measures the
completeness gap — how much the kibitzer leaves on the table.

Usage:
  spago run --quiet -p kibitzer-example -- corpus 100 > smt/corpus.jsonl
  smt/.venv/bin/python smt/optimal_watcher.py smt/corpus.jsonl
  smt/.venv/bin/python smt/optimal_watcher.py smt/corpus.jsonl --game 42 --players 4

Card indices mirror kibitzer-core's `allCards`:
0-5 suspects, 6-11 weapons, 12-20 rooms.
"""

import argparse
import json
import sys
from collections import defaultdict

from z3 import And, If, Int, Or, Solver, Sum, sat, unsat

SUSPECTS = range(0, 6)
WEAPONS = range(6, 12)
ROOMS = range(12, 21)
CATEGORIES = (SUSPECTS, WEAPONS, ROOMS)

CARD_NAMES = [
    "Miss Scarlett", "Colonel Mustard", "Mrs. White",
    "Rev. Green", "Mrs. Peacock", "Professor Plum",
    "Candlestick", "Knife", "Lead Pipe", "Revolver", "Rope", "Wrench",
    "Kitchen", "Ballroom", "Conservatory", "Dining Room",
    "Billiard Room", "Library", "Lounge", "Hall", "Study",
]


def feasible_places(game):
    """For each card, the set of places (0..n-1 seats, n = envelope) it
    could still occupy given the public transcript. Sat models are
    harvested across all cards, so most (card, place) pairs are settled
    without their own solver query."""
    n = game["players"]
    env = n
    place = [Int(f"place_{c}") for c in range(21)]
    s = Solver()
    for c in range(21):
        s.add(place[c] >= 0, place[c] <= env)
    for cat in CATEGORIES:
        s.add(Sum([If(place[c] == env, 1, 0) for c in cat]) == 1)
    for p in range(n):
        s.add(Sum([If(place[c] == p, 1, 0) for c in range(21)]) == game["handSizes"][p])
    for e in game["events"]:
        if e["type"] == "pass":
            s.add(And([place[c] != e["player"] for c in e["cards"]]))
        else:  # show: the shower holds at least one of the three
            s.add(Or([place[c] == e["by"] for c in e["cards"]]))

    assert s.check() == sat, "public transcript is inconsistent (bug!)"

    feasible = [set() for _ in range(21)]

    def harvest(model):
        for c in range(21):
            feasible[c].add(model[place[c]].as_long())

    harvest(s.model())
    for c in range(21):
        for v in range(env + 1):
            if v in feasible[c]:
                continue
            s.push()
            s.add(place[c] == v)
            if s.check() == sat:
                harvest(s.model())
            s.pop()
    return feasible


def determined_pairs(feasible, n):
    """The set of certainly-known (card, place, holds?) statements."""
    out = set()
    for c in range(21):
        for v in range(n + 1):
            if v not in feasible[c]:
                out.add((c, v, False))
            elif len(feasible[c]) == 1:
                out.add((c, v, True))
    return out


def engine_pairs(game):
    """The engine watcher's certainties, in the same (card, place, holds?) shape."""
    n = game["players"]
    w = game["watcher"]
    out = set()
    for c in w["envelopeIn"]:
        out.add((c, n, True))
    for c in w["envelopeOut"]:
        out.add((c, n, False))
    for p in range(n):
        for c in w["holds"][p]:
            out.add((c, p, True))
        for c in w["lacks"][p]:
            out.add((c, p, False))
    return out


def envelope_solved(feasible, n):
    return all(
        any(feasible[c] == {n} for c in cat) for cat in CATEGORIES
    )


def engine_solved(game):
    env_in = game["watcher"]["envelopeIn"]
    return all(any(c in cat for c in env_in) for cat in CATEGORIES)


def analyse_game(game):
    n = game["players"]
    feasible = feasible_places(game)
    optimal = determined_pairs(feasible, n)
    engine = engine_pairs(game)
    unsound = engine - optimal  # must be empty: engine certainty Z3 doesn't share
    return {
        "engine_pairs": len(engine),
        "optimal_pairs": len(optimal),
        "gap": len(optimal - engine),
        "engine_solved": engine_solved(game),
        "optimal_solved": envelope_solved(feasible, n),
        "unsound": len(unsound),
        "feasible": feasible,
    }


def show_game(game, result):
    n = game["players"]
    seats = "ABCDEF"[:n]
    print(f"seed {game['seed']}, {n} players, movement {'on' if game['movement'] else 'off'}")
    print("✓/✗ known to both · ●/○ optimal-only (the engine's completeness gap) · · unknown\n")
    print(f"{'':16}" + " ".join(seats) + "  Env")
    engine = engine_pairs(game)
    for c in range(21):
        cells = []
        for v in range(n + 1):
            fs = result["feasible"][c]
            if v not in fs:
                cells.append("✗" if (c, v, False) in engine else "○")
            elif len(fs) == 1:
                cells.append("✓" if (c, v, True) in engine else "●")
            else:
                cells.append("·")
        print(f"{CARD_NAMES[c]:<16}" + " ".join(cells[:n]) + "   " + cells[n])
    print(
        f"engine: {result['engine_pairs']} certainties, solved={result['engine_solved']} | "
        f"optimal: {result['optimal_pairs']}, solved={result['optimal_solved']} | "
        f"gap {result['gap']}"
    )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("corpus", help="JSONL from: spago run -p kibitzer-example -- corpus N")
    ap.add_argument("--game", type=int, help="seed of a single game to display")
    ap.add_argument("--players", type=int, default=4, help="with --game: table size")
    ap.add_argument("--moves", action="store_true", help="with --game: movement variant")
    args = ap.parse_args()

    games = [json.loads(line) for line in open(args.corpus) if line.strip()]

    if args.game is not None:
        wanted = [
            g for g in games
            if g["seed"] == args.game and g["players"] == args.players and g["movement"] == args.moves
        ]
        if not wanted:
            sys.exit("game not in corpus")
        show_game(wanted[0], analyse_game(wanted[0]))
        return

    agg = defaultdict(lambda: {
        "games": 0, "engine_pairs": 0, "optimal_pairs": 0, "gap": 0,
        "engine_solved": 0, "optimal_solved": 0, "unsound": 0,
    })
    for g in games:
        r = analyse_game(g)
        a = agg[(g["players"], g["movement"])]
        a["games"] += 1
        for k in ("engine_pairs", "optimal_pairs", "gap", "unsound"):
            a[k] += r[k]
        a["engine_solved"] += r["engine_solved"]
        a["optimal_solved"] += r["optimal_solved"]

    print(f"optimal watcher vs engine watcher — {len(games)} games")
    print(f"{'players':>7} {'moves':>6} {'engine-certs':>13} {'optimal-certs':>14} "
          f"{'gap':>6} {'engine-solved%':>15} {'optimal-solved%':>16} {'unsound':>8}")
    for (players, movement) in sorted(agg):
        a = agg[(players, movement)]
        gs = a["games"]
        print(f"{players:>7} {'on' if movement else 'off':>6} "
              f"{a['engine_pairs'] / gs:>13.1f} {a['optimal_pairs'] / gs:>14.1f} "
              f"{a['gap'] / gs:>6.1f} {100 * a['engine_solved'] / gs:>14.0f}% "
              f"{100 * a['optimal_solved'] / gs:>15.0f}% {a['unsound']:>8}")
    total_unsound = sum(a["unsound"] for a in agg.values())
    print("\nsoundness cross-check (engine certainties Z3 disagrees with):",
          total_unsound, "— MUST be 0" if total_unsound else "✓")


if __name__ == "__main__":
    main()
