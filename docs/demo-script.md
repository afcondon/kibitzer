# Kibitzer — demo film script (draft)

*~7 minutes. Working draft for print-and-annotate. Locked demo seed:
**768896, 6 players, no board**. Every per-event beat below is
ground-truth-verified against the compiled engine (see Appendix A).*

**Premise (one line):** an onlooker at a game of Cluedo who never sees a
single card can, from the public metadata alone, deduce the murder —
often before the players do. And the little library that lets it do that
generically is the real subject.

**Pipeline:** scripted browser capture (Kibitzer on :3026) · Specimen
renders of the published libraries · terminal + static-page captures for
the examples · typographic academic cards · assembled in ffmpeg (iMovie
optional polish). Narration voice: TBD.

---

## ACT 1 — The kibitzer

**Scene.** *Stylised setup animation: Cluedo pieces placed, the deck
dealt out to six players and three cards sealed into the envelope.*
*(App-work note: this deal animation likely needs building — it is not
in the app today.)*

> **narrator:**
> Imagine a game of Cluedo — *Clue*, in the States — with an onlooker at
> the table. You're moving your piece, making your suggestions, seeing
> the cards your rivals show you. If you're good, you're keeping track
> of not just who *has* a card, but who *hasn't*. Eventually someone —
> maybe you — names all three cards in the envelope, and wins.
>
> But what if the onlooker — the card-counter, the *kibitzer* — could do
> better, from the public information alone? Who suggested what. Who
> passed. Who showed a card. They never see a single card. And yet — in
> nearly a quarter of six-player games, the silent watcher pins all
> three cards in the envelope. And every single time it does, it gets
> there *before* the winning accusation. *(Measured: 23.5% of 1,000
> games — see Appendix B.)*
>
> This is the power of metadata. But it takes more than *recording* the
> metadata. It takes a deductive engine to unpack the hidden information
> leaking out of it.

**Scene.** *Cut to the Kibitzer app, Game tab, seed 768896. Step through
the plays — speed up through the middle game, then slow right down for
the final moves. Watch the watcher's notebook fill, and watch the clock.*

> **narrator (over the finish):**
> One move *before* a player stands up to make the winning accusation,
> the watcher's notebook is already complete. The onlooker who never
> touched a card got there first — by a single turn.

*(Verified: player B wins by correct accusation at E103; the watcher
pins the full three-card solution one event earlier, after E102.)*

---

## INTERLUDE — How often, and when

**Scene.** *A clean data card: the players × board grid animating in — a
small-multiples strip of collapse curves, or a simple climbing bar per
table size. (Numbers: Appendix B.)*

> **narrator:**
> How often does the silent watcher win? It depends entirely on the
> table. With three players it almost never does — about one game in
> thirty. But every extra player means more suggestions, more passes,
> more shows — and more hidden information bleeding into the open. At six
> players it cracks the full envelope in nearly a quarter of them — and
> every single time it does, it gets there before the winning
> accusation. More eyes, more talk — more surveillance.

**Scene.** *The board toggles ON; the curves flatten, the win bars drop.*

> **narrator:**
> Add the board — make a player walk to a room before they're allowed to
> name it — and the leak narrows. The games run *longer*, but the
> watcher does *worse*: its success drops by about a quarter — from
> 23.5% to 17.7%. Movement is noise; the gossip is the signal.

*(Measured, 1,000 games per configuration — see Appendix B.)*

---

## ACT 2 — The spy's-eye view (the Cascade)

**Scene.** *Switch to the Cascade tab, same game. Now we replay it from
the watcher's point of view — passes, shows, and the possibility "packs".*

The opening moves (verbatim from the seed):

```
E1  A suggests Mrs. White with the Wrench in the Billiard Room.
E2  B passes — holding none of the three.
E3  C passes — holding none of the three.
E4  D shows A a card. (Face-down. The watcher cannot see it.)
```

> **narrator:**
> When B passes on a suggestion, the kibitzer learns *three* facts at
> once: B holds none of those three cards. C passes — three more.
>
> Then D shows A a card. Our spy can't see what it is. But they can note
> something: D holds *one* of those three cards — Mrs. White, the Wrench,
> or the Billiard Room. A disjunction, floated into orbit, waiting.

**Scene.** *The three candidate cards lift into the derivation "orbit"
around D — an unresolved possibility.*

> **narrator:**
> And there it sits, for fifty-odd moves — until the rest of the table
> quietly closes every other door. One of those three cards turns up in
> another player's hand. The third is shown to belong to nobody. And on
> the very next event —

**Scene.** *At E61, the possibility circles for Mrs. White all collapse
onto D. A new fact crystallises.*

> **narrator:**
> — the kibitzer knows, with certainty, that the card D showed, all
> those turns ago, was **Mrs. White**. And with it, one more fact for
> free: Mrs. White was never in the envelope. She isn't the murderer.

*(Verified: immediately after E61 the watcher first derives both "D
holds Mrs. White" and "Mrs. White not in the envelope".)*

> **narrator:**
> This game is not typical. But in this one, by the time the last card is
> shown, the watcher who saw nothing knows *everything* — the three cards
> in the envelope, and every card in every player's hand.

*(Verified: 147 facts = every one of the 21 cards located across all six
hands plus the envelope.)*

---

## ACT 3 — Baskerville (the library)

**Scene.** *Hard cut back to one derivation-feed line from the game,
alone on screen: "D holds Mrs. White — because B, C, E and F cannot, and
the envelope does not." The word "Cluedo" is nowhere in it.*

> **narrator:**
> Here's the thing about that watcher. Nothing in it knows the word
> "Cluedo." It never learned the rules of the game. It learned *how to
> hold a reason.*

**Scene.** *Pull back to a Specimen render of `Baskerville.Kernel`,
typeset, scrolling gently.*

> **narrator:**
> Underneath is Baskerville — a small PureScript library with one idea.
> Most engines record *what* they believe. Baskerville records every
> fact **paired with the reason it holds** — facts as proof terms, wired
> into a hash-consed derivation graph — and grinds one rule set forward,
> monotonically, until nothing new can be learned.
>
> Because every fact carries its justification, you can point at *any*
> conclusion and ask it **why** — and get the chain it stood on, all the
> way down to what was actually observed. In the truth-maintenance
> tradition this was bookkeeping, kept for cleanup. Baskerville promotes
> it to the product. **The explanation *is* the deliverable.**

**Scene.** *Quick three-up montage: (1) the Meeting terminal transcript —
five people, twenty slots, one survivor, the "why every other slot died"
lines highlighted; (2) the Sudoku `explain.html` page scrolling — pencil
marks with their derivations; (3) back to the Cluedo feed.*

> **narrator:**
> Give it the rules of scheduling a meeting, and the one surviving slot
> arrives carrying the reason every *other* slot died. Give it Sudoku,
> and every eliminated pencil-mark is a fact that remembers why it's
> gone. Cluedo, Sudoku, a meeting, a build graph — the same kernel, with
> three rules and a page of client code each.

**Scene.** *Specimen render of `Baskerville.Rule` / `Baskerville.Explain`,
the `axiomsBehind` signature framed.*

> **narrator:**
> It's on the registry now, in four small pieces. But forward-deriving
> every fact is only *one* way to answer these questions. There's
> another — older, and completely different in temperament.

---

## ACT 4 — Mycroft (SMT / z3)

**Scene.** *Title card: "Mycroft." Small, beneath: "he does no legwork —
you bring him the facts, and he pronounces."*

> **narrator:**
> The second library is called Mycroft — after Sherlock's cleverer,
> sedentary brother. Baskerville does the legwork, walking the
> derivation forward one fact at a time. Mycroft doesn't move. You hand
> the whole problem to a solver — z3 — and ask a single question: **is
> there any world consistent with everything we've seen?**

**Scene.** *The worlds visualizer (`worlds.html`). Open on the headline
number, then the log-paper collapse curve.*

> **narrator:**
> How many worlds? At the deal, with six players, there are **forty-four
> trillion** legal ways the cards could lie —
> *44,460,928,512,000*, exactly. Far too many to draw. So the picture
> starts on log paper — billions, trillions — and estimates the space
> shrinking. Then, the moment the survivors are few enough to fit on a
> screen, z3 enumerates *every one of them* — the totality, not a
> sample — and each pass and each show you saw collapses it further,
> down the decades, until a single world is left standing.

**Scene.** *The two markers on the collapse strip light up: the point
where all surviving worlds agree on the envelope, and — earlier or later
— the point Baskerville's forward rules reached the same answer.*

> **narrator:**
> Two moments fall out of the same picture for free. The instant every
> surviving world agrees on the envelope — that's the earliest anyone
> *could* know: the solver's verdict. And on the same strip, the moment
> Baskerville's forward rules caught up. The gap between them has a name.

**Scene.** *The bridge — split screen. Left: a Baskerville fact with its
`axiomsBehind`. Right: the same conclusion as a z3 **unsat core** over
the named observations. A seam animates between them.*

> **narrator:**
> A third small library sits z3 *behind* Baskerville's own seam — and
> uses the solver as a **measuring instrument for the rules themselves.**
> Is the engine **sound** — does it ever derive a fact that isn't truly
> forced? Where is the **gap** — facts that were logically inevitable
> that the forward rules never reached? z3 answers the first; that
> distance on the strip is the second. And its **unsat core** — the
> minimal set of observations that force a conclusion — is the exact
> mirror of Baskerville's *"which facts did this stand on."* One proves
> *why*, in human terms. The other certifies *that* — and keeps the
> first honest. It runs against a native z3, or entirely in the browser,
> compiled to WebAssembly.

**Scene.** *Antecedents montage — brief typographic cards: "Doyle · JTMS
· 1979" → "de Kleer · ATMS · 1986" → the dismemberment: "the labels →
Answer Set Programming" · "the backtracking → CDCL, inside every SAT/SMT
solver" · "the ATMS labels → provenance semirings." Land on one line.*

> **narrator:**
> None of this is new. The truth-maintenance systems of the eighties
> were taken apart, and their organs transplanted — the search into
> z3's engine, the labels into logic programming, the provenance into
> databases. Every successor kept the machinery and buried the
> explanations as plumbing.
>
> The derivation graph — the written-up reason, as the thing you
> actually ship — is the piece still lying on the table.

**Scene.** *Outro card: the four registry packages and repo links —
`baskerville-core · mycroft · baskerville-mycroft · mycroft-z3-wasm`.*

> **narrator:**
> *to be continued.*

---

## Appendix A — verified ground truth (seed 768896, 6 players, no board)

Run directly against the compiled engine (`Kibitzer.Game.simulate` +
`Infer.knowledgeTimeline`). All claims above check out:

| Beat | Reality |
|---|---|
| Opening E1–E4 (A suggests White/Wrench/Billiard; B, C pass; D shows) | verbatim |
| E61 → watcher deduces "D holds Mrs. White" **and** "White not in envelope" | confirmed (snapshot after E61) |
| Full break — watcher ends knowing every card | 147 facts = 21 cards × (6 hands + envelope) |
| Envelope solved "by Event 102" | full 3-card solution first known after E102 |
| "Solved before the players" | player B accuses correctly at E103; watcher solves after E102 — a **one-event** photo finish (hence the Act-1 reword) |
| Envelope identity | Mrs. Peacock · Knife · Lounge (so "White is not the murderer" holds) |

## Appendix B — the numbers (measured, not asserted)

**N = 1,000 seeds per configuration** (seeds 1–1000), vs random-legal
players, watcher sees zero cards. `solved%` = watcher pins all three
envelope cards by game end. `beat%` = watcher pins them using only
events **before** the winning accusation. *(They come out identical in
every configuration — see the footnote — so the watcher, whenever it
solves at all, always gets there first.)*

| players | board | solved % (= beat %) | mean events | mean facts | env-pinned /3 |
|---:|:---:|---:|---:|---:|---:|
| 3 | off | 3.1 | 75.4 | 51.1 | 1.0 |
| 3 | on | 2.9 | 97.0 | 41.9 | 1.0 |
| 4 | off | 8.7 | 84.4 | 75.9 | 1.3 |
| 4 | on | 8.0 | 110.2 | 66.9 | 1.2 |
| 5 | off | 15.1 | 94.9 | 100.8 | 1.6 |
| 5 | on | 13.2 | 121.8 | 93.5 | 1.4 |
| **6** | **off** | **23.5** | 103.2 | 124.0 | **1.8** |
| 6 | on | 17.7 | 128.5 | 115.3 | 1.6 |

Three readings the Interlude scene sells:

1. **More players ⇒ a far stronger watcher.** Solved rate climbs 3.1 % →
   8.7 % → 15.1 % → **23.5 %** from 3 to 6 players (no board) — a roughly
   eightfold jump. More suggestions, passes and shows = more leaked
   metadata. (z = −13.4, p < 0.0001.)
2. **The board protects the players — modestly.** Movement drops the
   six-player rate from **23.5 % to 17.7 %** — about a quarter fewer, and
   statistically real (z = 3.21, p = 0.0013), but *not* the halving the
   earlier small samples suggested. Games run *longer* yet leak *less*:
   movement is noise, the gossip is signal.
3. **Even when it doesn't fully solve, it's guessing well.** Average
   envelope cards pinned rises to **1.8 of 3** at six players — the
   "educated guess before any player is certain."

**Footnote — 95% Wilson CIs (n = 1000/config):** 3p 3.1 [2.2, 4.4] ·
4p 8.7 [7.1, 10.6] · 5p 15.1 [13.0, 17.5] · **6p 23.5 [21.0, 26.2]**
(no board); 6p-board 17.7 [15.5, 20.2]. Two-proportion z-tests:
board effect @6p z = 3.21, p = 1.3×10⁻³; player-count effect (3p vs 6p,
no board) z = −13.4, p < 10⁻⁴. `beat% == solved%` in all eight cells:
the winning accusation never *teaches* the watcher the solution — it had
it, or it didn't. Note the earlier committed README table (100 seeds)
read 28% at 6-off; that and a remembered "31%" are small-sample high
estimates — 23.5% [21.0, 26.2] is the settled value. *(The move to the
generic Baskerville solver did not change any of this: the golden
acceptance test is green and the current engine reproduces the pre-port
100-seed table to the decimal.)*

Seed-search verdict: across 300 six-player seeds, only two had both a
long resolution orbit and a comfortable winning margin, and both were
weaker than 768896 (no full break). 768896 stays locked.

## Appendix C — asset checklist

- [ ] Act 1 deal animation (**likely new app work**)
- [ ] Kibitzer Game-tab capture, seed 768896 (speed-ramp to the finish)
- [ ] Kibitzer Cascade-tab capture, seed 768896 (orbit → E61 collapse)
- [ ] Specimen renders: `Baskerville.Kernel`, `Baskerville.Rule`,
      `Baskerville.Explain` (regenerate the book; already exists at
      `code-typography/specimen/docs/baskerville/`)
- [ ] Meeting terminal capture (`spago run -p baskerville-meeting`)
- [ ] Sudoku `explain.html` (generate: `... -p baskerville-sudoku -- page`)
- [ ] `worlds.html` collapse capture — **decide**: keep seed 33 (the
      canonical 1,238-world render) or regenerate for 768896 (same 44 T
      headline; needs the `smt/` Python+z3 sidecar)
- [ ] Antecedents cards (from `purescript-baskerville/docs/antecedents.md`)
- [ ] Outro card with the four registry links

## Appendix D — known app-work blocker

The example CLI (`spago run -p kibitzer-example -- <seed>`) currently
hangs on every invocation: `curate` (`example/src/Skylines.purs:69`) is a
top-level CAF that runs 200 games at module-import time, and
`Example.Main` transitively imports it. Fix: thunk `curate` (or move the
pool inside `runSkylines`/`runOrbits`). This also restores the app's own
`stats` mode. The frontend is unaffected.
