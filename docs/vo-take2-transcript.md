# VO — take 2, transcribed and cleaned

*Transcription of `baskerville vo 2.mp3` (4:15), segmented back to the
beats and lightly corrected. This is **your spoken words**, not my
written script — the intent is that this reads more naturally for you to
work from. Only ASR errors and obvious stumbles were fixed; phrasing is
left as you said it.*

**ASR fixes applied:** "Pluto"/"Cludo" → Cluedo · "Minecraft" → Mycroft ·
"who suggests SWAT" → who suggests what · "Captain Peacock" → **Mrs.**
Peacock *(flagging in case you did mean a joke)* · "it has hands you" →
it hands you · "less cards" → fewer cards.

**Covers B1–B12.** Section 6 (antecedents + packages) is omitted, as you
asked. Section 5 (Mycroft) is included verbatim so you have it, but you
said you want to rewrite it — see the note under it.

---

### B1 · Game — the seventh presence
Here's a single game of Cluedo. Six players, accompanied by a seventh
presence at the table who never sees even one card. It only hears the
public talk — who suggests what, who passes, who shows. We're watching
its notebook.

### B2 · the notebook fills
With every pass, every show, a fact lands. It doesn't guess, it just
records. But if we watch the clock —

### B3 · solves first
— one move before a player wins, the watcher's notebook is already
complete. Mrs. Peacock, the Knife, the Lounge. So the onlooker who never
touched a card, and never saw a card, gets there first — in this case,
by a single turn.

### B4 · how often it wins
How often does it win outright? Well, it scales with the table. With
three players it almost never does — about one game in thirty. But every
extra player means more suggestions, more passes, more shows — and the
players themselves have fewer cards to begin with. So there's more
hidden information bleeding into the open. At six players, it cracks the
full envelope in nearly a quarter of cases.

### B5 · the point
The point, in a way, isn't that it beats the players. At a real table,
someone usually wins first. The point is that it extracts any certainty
at all from pure metadata, without any card ever in its hand. The more
the table talks, the more it learns.

### B6 · Baskerville — the disjunction floats
Now here's the same game from the watcher's side. Early on, player D
shows player A a card. Our spy can't see it, but it can note one thing:
D now must hold one of the three cards just named — Mrs. White, the
Wrench, or the Billiard Room. That sits there, waiting.

### B7 · it waits
And it sits for fifty-odd moves, while other facts quietly accumulate.

### B8 · it resolves (E61)
Until, on one event, it suddenly resolves. The card which D showed, all
those turns ago, must have been Mrs. White. And so also — White was
never in the envelope, so she isn't the murderer.

### B9 · Baskerville the library
Nothing in this watcher knows the word Cluedo, and it never learned the
rules of the game. Underneath it is Baskerville — a small library that
records every fact, paired with the reason why that fact holds. And it
grinds one rule set forward until nothing new can be learned. Point it
at any conclusion and ask it why, and it hands you the chain it stood
on, all the way down to what was actually seen. So for Cluedo, or
Sudoku, or scheduling a meeting — it's the same kernel, three rules and
a page of code each.

---

### B10–B12 · Mycroft  — *you want to rewrite this*
There's a second way, older and opposite in temperament. Baskerville
does the legwork, one fact at a time. Mycroft does none. It hands the
whole problem to a solver, called Z3, and asks a single question: is
there any world consistent with all the facts we have here?

How many worlds? Well, at the deal with six players, there are 44
trillion legal ways the cards could lie. Far too many to draw, so our
visualisation starts at the moment when the surviving worlds fit on a
screen. Z3 shows every one of them — the totality, not a sample — and
each pass and show that appears in the game collapses it, until you
arrive at a single world.

Two moments fall out for free. The instant every surviving world agrees
on the envelope — that's the earliest anyone could know — and the moment
that Baskerville's forward rules reach the same answer. In this game they
happen to coincide, but the rules and Z3 leave nothing on the table.

> **Note for the rewrite:** this take predates the *step-backward* idea we
> worked up — it doesn't yet cover **solid column = that card's owner is
> already known** (the Kitchen still solid at 67 billion worlds), or
> **red column = it's in the envelope** (the three red columns agreeing
> at E102). Those are in the beat sheet as B10–B13 if you want to fold
> them into your rewrite. When you record the Mycroft take, that's the
> extra material to hit.
