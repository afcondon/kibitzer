# Kibitzer — video beat sheet (hybrid cut, VO-first)

*The working cut: **take 3's unscripted spine and first-person voice**
(see [`vo-take3-free-transcript.md`](vo-take3-free-transcript.md)), with
the **metadata-privacy hook** kept and the **hard facts** spliced back in
from the scripted version. Read the **> VO** blocks; the `SHOT`/`ACTION`
notes are for driving the app. Method is still VO-first: record these,
send the audio, I retime the self-driver (`video/capture-driver.js`) to
your read.*

**Master state:** seed **768896**, six players, no board
(`http://localhost:3026/?seed=768896&players=6`). Every per-event claim
is ground-truth-verified (see [`demo-script.md`](demo-script.md) App. A).

**On-screen flow (simpler than before):** trailer → ① Game (frame, hook,
mechanic, result, scaling) → ② Baskerville (the two views + the E61 chain)
→ ③ Mycroft (collapse forward, then backward) → the two-libraries close,
held on Mycroft → a **silent** end-card of the four packages (④ About
colophon). No narration over the antecedents — that beat is gone.

**Voice:** first person, unhurried, yours. The facts to *not* fudge are
bolded in the notes: **Mrs. Peacock / the Knife / the Lounge**, **one
move** before the win, **~a quarter** at six players, **44 trillion**
exactly, **536** first shown, the **Kitchen still solid at 67 billion**,
**three red columns** = the envelope.

---

## 0 · Opening credits — the trailer  (~37 s, no VO)

`SHOT` The trailer (`video/opening.html`) plays start to finish, silent
(or light score). Ends held on the **kibitzer.** wordmark, the red iris
as the full stop. VO begins on the cut to the app.

---

## 1 · The frame, and the watcher  (① Game, at the deal)

`SHOT` Cut to **① Game**, seed 768896, at the deal: the table and the
envelope on the left, the empty notebook on the right.

> **VO (B1):** I built this little simulation of Cluedo to show off two
> small libraries — both of them about deduction. Here's a game, freshly
> dealt: six players, and three cards sealed in the envelope. And there's
> a seventh presence at the table — an imaginary spy, our deduction
> machine — that never sees a single card.

> **VO (B2):** All it ever gets is the public talk: who suggests what,
> who passes, who shows a card to whom. That's *metadata* — the same kind
> of exhaust you leave with your phone records, or an encrypted
> messenger's delivery receipts. The content stays private; the metadata
> gives you away. Let's see what it can do with just that.

---

## 2 · The mechanic, the result, the scaling  (① Game, stepping)

`ACTION` Step the timeline: brisk through the opening and midgame (the
grid fills, the event stack climbs), then slow to the finish.

> **VO (B3):** As the players move, the watcher writes down facts. The
> simplest: when someone passes, they hold none of the three cards just
> suggested. But once you've gathered enough, you can *deduce*. If someone
> showed a card, they held one of those three — and if two of them get
> ruled out elsewhere, you know the third. It forms a chain.

`ACTION` Hold the instant the notebook completes (after **E102**), one
event before the winning accusation at E103.

> **VO (B4):** It never guesses — it only writes down what's forced. And
> watch the clock: one move before a player stands up to win, the
> watcher's notebook is already complete. Mrs. Peacock, the Knife, the
> Lounge. The onlooker who never touched a card got there first — by a
> single turn.

> **VO (B5):** The idea isn't that it beats the players — at a real table
> someone usually wins first, and it depends how well they play; these
> are playing pretty randomly. But the number of players matters. More
> players each start with fewer cards and make more suggestions — more
> facts circulating, more leaking into the open. With three players it
> almost never solves, about one game in thirty; at six, it cracks the
> whole envelope in nearly a quarter of them. The more the table talks,
> the more the silent watcher learns.

---

## 3 · The watcher's side  (② Baskerville)

`SHOT` Cut to **② Baskerville**, seed 768896, at the start — the
possibilities intact on the left, the empty derivation orbit on the right.

> **VO (B6):** Here's the same game from the watcher's side — two views
> instead of the table. On the left, everything still possible: at the
> start, anyone could hold any card, and any three could be in the
> envelope. As the game goes, possibilities fade out; and the moment a
> card's owner is pinned down, it drops out of everyone else's hands — and
> if it's ruled out of *every* hand, it must be in the envelope.

> **VO (B7):** On the right are the deductions themselves, each with its
> reason. Hover any one — "F does not hold the Wrench" — and you can see
> exactly why it's known.

`ACTION` Step the discovery stepper to the early D-shows-A event; the
three candidates lift into orbit around D. Then one press → jump to
**E61**, where they collapse onto D and the callout names the fact.

> **VO (B8):** Here's a chain playing out. Early on, D shows A a card — I
> can't see it, but I know D holds one of these three: Mrs. White, the
> Wrench, or the Billiard Room. It floats there, unresolved, for fifty-odd
> moves — until the others quietly rule out the other two, and it snaps
> shut: the card was Mrs. White. And for free, White was never in the
> envelope — so she's not the murderer.

`ACTION` Step to the end (the fully-derived orbit).

> **VO (B9):** Step to the end, and in this game it's a total solution —
> every card in every hand, and the three in the envelope, because one
> determines the other.

---

## 4 · The other way  (③ Mycroft)

`SHOT` Cut to **③ Mycroft**, seed 768896. It opens at **E71** — the first
moment few enough worlds remain to draw them all: 536 rows, each a
complete world; a handful of columns already a single colour.

> **VO (B10):** There's a completely different way to do this — one that
> isn't so easily asked for its reasons: hand the whole problem to an SMT
> solver, Z3, and just ask "is there any world still consistent with
> everything we've seen?" That's what my other library, Mycroft, does —
> it wraps Z3.

> **VO (B11):** Every line here is one possible solution — one complete
> world. At the deal there are forty-four trillion of them, exactly; you
> can't draw that in a browser, so we join once few enough remain to fit
> on screen — five hundred and thirty-six. Step forward, deduction by
> deduction, and the space collapses, fast. And when three columns turn
> *red* — the three cards known to be in the envelope — that's your
> solution.

`ACTION` **Step backward** — scrubber to E46 (≈ 2.6 M worlds; three solid
columns), then to **E18** (≈ 67 billion; one solid column — the Kitchen).
The grid dissolves to the big number; the pinned columns stay solid.

> **VO (B12):** And here's the nice part — you can run it backward. You
> still can't draw forty-four trillion worlds, but you can show something:
> that at some point a card's owner is already fixed — because every line
> in its column is a single colour. So we paint that column the player's
> colour. Look — the Kitchen's column is solid even *here*, with
> sixty-seven billion worlds still in play. That fact was locked long
> before the space was ever small enough to see.

`ACTION` Step forward through the deductions to the solved state at
**E102** (one world; all 21 columns solid, three of them red).

---

## 5 · The two libraries  (close, held on ③ Mycroft → silent end-card)

`SHOT` Hold on the solved Mycroft frame (one world; three red columns).

> **VO (B13):** So both libraries reach the same answer, very differently.
> Z3 is deterministic — it crunches the whole pile of facts at once and
> pronounces a solution, if one exists. Baskerville works forward, a fact
> at a time — but with the one real difference that it can tell you *how*
> it knew. Which is the whole point when what you care about isn't just
> the answer, but the reasoning: a build system, a course-scheduling
> system, a logistics engine.

`SHOT` **No VO.** Cut to **④ About**, the ink end-card — hold on the four
packages (`baskerville-core`, `mycroft`, `baskerville-mycroft`,
`mycroft-z3-wasm`) with the eye above them. Optional light score; fade.

---

## Capture notes (mine)

- Driven per the `ACTION` lines: transport is the floating control block;
  the discovery stepper is `Deduction ›`; Mycroft is the same-origin
  iframe (scrubber for the backward jumps, `Deduction ›` forward).
- The scaling (B5) rides over the Game view — no cut to a stats table.
- VO-first: send the audio (or per-segment durations B1–B13) and I retime
  the driver's `T{}` block; the silent end-card just holds.

## Your side

1. Record B1–B13 at a natural pace (ideally clicking through the site as
   you go — your beats will attach to what's on screen). Beat-by-beat or
   clear pauses so I can split the audio.
2. Send me the file → I transcribe (mini `:3200`), retime the driver.
3. Screen-record one clean pass of `KDEMO.play()` + a clean pass of the
   trailer; I hand you the ffmpeg assembly.

## Deferred / optional B-roll (v2)

- Specimen renders of `Baskerville.Kernel` / `Rule` / `Explain`; the
  Meeting terminal; Sudoku `explain.html`; the `worlds-gap.html` inset
  (seed 42) for a "when they *don't* coincide" beat.
- The antecedents material (JTMS/ATMS lineage) — lives on the About page
  as text; kept out of the VO by choice.
