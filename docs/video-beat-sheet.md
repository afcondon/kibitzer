# Kibitzer — video beat sheet (VO-first capture spec)

*Companion to [`demo-script.md`](demo-script.md). This is the
capture-ready cut: the words to read, top to bottom, each mapped to the
on-screen action I drive. Method: **VO-first** — you record the bold VO
lines; I time a self-playing capture of the app to your actual segment
durations; we assemble in ffmpeg with the trailer as opening credits.*

**Master state:** seed **768896**, six players, no board
(`http://localhost:3026/?seed=768896&players=6`). Every per-event claim
below is ground-truth-verified (see `demo-script.md` Appendix A).

**Assets this cut uses (all in hand):** the trailer
(`video/opening.html`), and the four app pages — ① Game, ② Baskerville,
③ Mycroft, ④ About. The richer Act-3 montage (Specimen renders, the
Meeting terminal, Sudoku `explain.html`) is **deferred to a v2** — noted
at the end as optional B-roll.

**How to read this:** read only the **> VO** blocks, at a natural,
unhurried pace, with a beat of silence between segments. Ignore the
`ACTION`/`SHOT` notes — those are mine. One clean take per segment is
ideal (we can splice); flubs are fine, just pause and redo the line.

---

## 0 · Opening credits — the trailer  (~37 s, no VO)

`SHOT` The trailer plays start to finish (silent, or with light score —
your call). It ends held on the **kibitzer.** wordmark, the red iris as
the full stop, "A DEDUCTION FROM METADATA" beneath.

*No narration over the trailer — it carries the premise kinetically. VO
begins on the cut to the app. (If you'd rather narrate over it, segment
B1 can be moved to play across the deal animation instead — tell me and
I'll re-time.)*

---

## 1 · The watcher solves first  (① Game)

`SHOT` Hard cut from the wordmark to the app, **① Game**, seed 768896,
at the deal (position 0): ground truth on the left, the empty notebook
on the right, counters at 0 / 0.

> **VO (B1):** Here's a single game of Cluedo. Six players — and a
> seventh presence at the table that never sees one card. It only hears
> the public talk: who suggests what, who passes, who shows. Watch its
> notebook.

`ACTION` Begin stepping the timeline. Speed-ramp: brisk through the
opening and midgame (the grid fills, the event stack climbs), then slow
right down for the final moves.

> **VO (B2):** Every pass, every show, lands as fact. It never guesses.
> And watch the clock —

`ACTION` Step to the finish. Hold the instant the notebook completes
(after E102), one event before the winning accusation at E103.

> **VO (B3):** One move before a player stands up to win, the watcher's
> notebook is already complete. Peacock, the Knife, the Lounge. The
> onlooker who never touched a card got there first — by a single turn.

---

## 2 · How often, and how it scales  (④ About — the numbers)

`SHOT` Cut to **④ About**, scrolled to *How often the silent watcher
wins* — the scaling table (3 → 6 players) in view.

> **VO (B4):** How often does it win outright? It scales with the table.
> Three players, and it almost never does — about one game in thirty.
> But every extra player means more suggestions, more passes, more
> shows: more hidden information bleeding into the open. At six players,
> it cracks the full envelope in nearly a quarter of them.

> **VO (B5):** The point isn't that it beats the players — at a real
> table someone usually wins first. The point is that it extracts *any*
> certainty at all, from pure metadata, no card ever in its hand. The
> more the table talks, the more it learns.

---

## 3 · The spy's-eye view  (② Baskerville)

`SHOT` Cut to **② Baskerville**, seed 768896, at the start (the packs
intact on the left, the empty derivation orbit on the right).

> **VO (B6):** Here's the same game from the watcher's side. Early on,
> player D shows player A a card. Our spy can't see it — but it can note
> one thing: D holds *one* of the three cards just named. Mrs. White,
> the Wrench, or the Billiard Room. A disjunction, floated into orbit,
> waiting.

`ACTION` Step the discovery stepper forward to the D-shows event; the
three candidate possibilities lift into orbit around D.

> **VO (B7):** And there it sits — for fifty-odd moves — while the rest
> of the table quietly closes every other door.

`ACTION` One press of the discovery stepper → jump to **E61**: the
Mrs. White possibilities collapse onto D, the premise hairlines light,
the callout names the new fact.

> **VO (B8):** Until, on one event, it resolves. The card D showed, all
> those turns ago, was Mrs. White. And for free, one more fact: White
> was never in the envelope. She isn't the murderer.

---

## 4 · Baskerville — the library  (② Baskerville + ④ About)

`SHOT` Hold on a single lit derivation in the orbit — a fact with its
premises. Then cut to **④ About**, *Two libraries, two temperaments*.

> **VO (B9):** Nothing in this watcher knows the word "Cluedo." It never
> learned the rules of the game — it learned how to hold a reason.
> Underneath is Baskerville: a small library that records every fact
> paired with the reason it holds, and grinds one rule set forward until
> nothing new can be learned. Point at any conclusion and ask it *why*,
> and it hands you the chain it stood on, all the way down to what was
> actually seen. Cluedo, Sudoku, a meeting to schedule — the same
> kernel, three rules and a page of code each.

---

## 5 · Mycroft — the whole space at once  (③ Mycroft)

`SHOT` Cut to **③ Mycroft**, seed 768896. It opens at **E71** — the
first moment few enough worlds remain to draw them all: 536 rows, each a
complete world; a handful of columns already a single colour.

> **VO (B10):** There's a second way, older and opposite in temperament.
> Baskerville does the legwork, one fact at a time. Mycroft does none —
> it hands the whole problem to a solver, Z3, and asks a single
> question: is there any world still consistent with everything seen?

> **VO (B11):** How many worlds? At the deal, forty-four trillion — far
> too many to draw. This is the first moment few enough remain to show
> them all: five hundred and thirty-six. Every row is one complete world
> still standing. And look — several columns are already a single colour.
> That card's owner is the same in every surviving world. It's already
> known.

`ACTION` **Step backward** — jump the scrubber to E46 (≈ 2.6 million
worlds; three solid columns), then to **E18** (≈ 67 billion; a single
solid column — the Kitchen). The grid dissolves to the big number; the
pinned columns stay solid full-height.

> **VO (B12):** And that isn't the space being small. Step back — to a
> point where sixty-seven *billion* worlds still remain — and the
> Kitchen's column is still solid. One card, fixed, across sixty-seven
> billion possibilities. A column turning solid is the space settling a
> fact — however vast it still is.

`ACTION` **Step forward** through the deductions (the `Deduction ›`
button in the pane) from E18 down the decades — columns lock one by one,
the three envelope columns turn **red** — landing on the solved state at
**E102** (one world; all 21 columns solid, three of them red).

> **VO (B13):** Now forward. Each pass and show collapses the space, and
> the columns lock, one by one. And when a column turns *red* — that card
> is in the envelope. Watch the three red columns. When they agree —
> here, at E102 — the space itself has named the murderer: Peacock, the
> Knife, the Lounge. The same answer Baskerville reached, at the very
> same event. The forward rules left nothing on the table.

---

## 6 · The argument, and the packages  (④ About — colophon)

`SHOT` Cut to **④ About**, the *Antecedents* section, then scroll to the
ink end-card — the four packages.

> **VO (B14):** None of this is new. The truth-maintenance systems of the
> eighties were taken apart, their machinery transplanted — the search
> into Z3's engine, the labels into logic programming, the provenance
> into databases. Every successor kept the machinery and buried the
> explanations as plumbing. The written-up reason — the thing you
> actually ship — is the piece still lying on the table. That's what
> Baskerville picks up.

`SHOT` Hold on the ink end-card: `baskerville-core`, `mycroft`,
`baskerville-mycroft`, `mycroft-z3-wasm`, the eye above them.

> **VO (B15):** Four small pieces, on the registry now. Baskerville, to
> hold the reason. Mycroft, to certify it. To be continued.

---

## Capture notes (mine)

- I drive the app deterministically per the `ACTION` lines; the transport
  is the floating control block (Play / Event / Deduction / Start / End),
  the discovery stepper is `Deduction ›`.
- Window: I'll standardise the browser size before the take so framing is
  consistent across cuts.
- VO-first: send me the recorded audio (or just the per-segment
  durations B1–B14) and I'll build a self-playing timeline whose holds
  and speed-ramps match your read, so the screen recording is one clean
  pass.

## Your side (the record + capture)

1. Record VO: read B1–B14 at a natural pace, silence between segments.
   Quiet room, pop filter if you have one; one clean take per segment.
2. Send me the audio. I finalise the capture timing to it.
3. Screen-record the app once as it self-plays (QuickTime or ffmpeg
   avfoundation — full-res, 60 fps if you can), plus a clean capture of
   the trailer.
4. I hand you the ffmpeg assembly (trailer → app, VO laid under,
   cross-fades, titles) — or you assemble in iMovie against the beat IDs.

## Deferred to v2 (optional B-roll, assets not yet made)

- Specimen renders of `Baskerville.Kernel` / `Rule` / `Explain`
  (regenerate the book at `code-typography/specimen/docs/baskerville/`).
- The Meeting terminal transcript (`spago run -p baskerville-meeting`).
- Sudoku `explain.html` (`... -p baskerville-sudoku -- page`).
- The `worlds-gap.html` inset (seed 42 — a visible completeness gap) for
  a "when they *don't* coincide" beat after B12.
