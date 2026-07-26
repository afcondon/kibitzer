# VO — take 4 (the working track)

*Transcription of `baskerville vo 4.mp3` (6:42, edited, retakes removed —
all beats, close to the hybrid script). ASR fixes applied (Cluedo, Z3,
kibitzer, watcher, murderer, course-scheduling, "cracks the whole
envelope open"); your phrasing otherwise untouched. This is the track the
capture driver is now timed against.*

Per-beat lengths are word-proportional estimates (total 402 s / 1037
words ≈ 0.39 s/word) — good enough to hang the shots on; final sync is
nudged in the edit.

| beat | ~secs | on screen |
|---|---:|---|
| B1 frame | 30 | ① Game, at the deal |
| B2 metadata hook | 34 | ① Game, at the deal |
| B3 mechanic | 32 | ① Game, brisk fill |
| B4 result | 20 | ① Game, notebook complete |
| B5 scaling | 44 | ① Game (held) |
| B6 left view | 39 | ② Baskerville, possibilities fading |
| B7 right view / why | 14 | ② Baskerville |
| B8 the E61 chain | 36 | ② Baskerville → E61 |
| B9 total solution | 14 | ② Baskerville, End |
| B10 Mycroft frame | 26 | ③ Mycroft, at E71 |
| B11 collapse → red | 38 | ③ Mycroft, forward to solved |
| B12 backward | 39 | ③ Mycroft → E18 (Kitchen @ 67 B) |
| B13 close | 33 | held on solved; then silent packages card |

---

### B1 · frame
Here we have a little simulation of Cluedo that I built in order to show
off two small libraries that I've written. Both of them are concerned
with deduction. So here on this first screen we see a game freshly dealt
out: there are six players, and there's three cards sealed in the
envelope. And there's a seventh presence at the table — an imaginary spy,
which is in fact our deduction machine — and it never sees a single card.

### B2 · the metadata hook
All it ever gets is the public talk: who suggests what, and who passes,
and who shows a card to whom. So it doesn't see *what* card is shown, but
it knows that somebody has shown a card — and so that's metadata. The
same kind of stuff we hear about with our phone records, or what an
encrypted messenger's delivery receipt has. So the content of the game
stays private, and the metadata is what the kibitzer — the spy — is
reading. So let's see what it can do with that.

### B3 · the mechanic
As the players move, the spy writes down facts. The simplest facts are:
somebody passes, then they hold none of the three cards that were just
suggested. But once you've got enough, you can deduce that if somebody
showed a card they held one of those three — and if two of them get ruled
out elsewhere later on, then you know what the third one was. So there's
a chain of deduction. It never guesses; it's only writing down what it's
seeing.

### B4 · the result
And if you watch the timeline, one move before a player stands up to win,
the watcher's notebook is already complete. Mrs. Peacock, the Knife, the
Lounge. So we have an onlooker who never touched a card, never saw a
card, and they get there first — in this case by a single turn.

### B5 · the scaling
The idea isn't that it beats the players. At a real table somebody
usually wins first, and it depends how well they play — these are playing
pretty randomly. And the number of players matters: with more players,
each one starts with fewer cards, and they have to make more suggestions;
there's more facts circulating, which is a kind of leaking of information
through the metadata. With three players the watcher will never — well,
almost never — solve the game, about one game in thirty. But at six
players it cracks the whole envelope open in about a quarter of the
games. And the more conversation there is, the more it learns.

### B6 · the left view
We move on to the second screen here, Baskerville. And here's the same
game from the watcher's side, so we have two views instead of the table.
On the left, everything is still possible at the start: anyone could hold
any card, and any three could be in the envelope — so we have these
groups, each group has all of the cards. As the game goes on,
possibilities fade out, and the moment a card's owner is pinned down it
drops out of everyone else's hands; and if it's ruled out of every hand,
it must be in the envelope.

### B7 · the right view / why
On the right are the deductions themselves, each with its reason. You can
hover any one of them — for example, "F does not hold the Wrench" — and
you can see why that is known.

### B8 · the chain (E61)
Here's how a chain plays out. Early on, D shows A a card. The watcher
doesn't see it, but it knows D holds one of these three: Mrs. White, the
Wrench, or the Billiard Room — these were the cards of the suggestion. So
that fact hangs there, unresolved, for fifty-odd moves, until certain
other facts quietly rule out two of the cards, and then we know that the
card was in fact Mrs. White. And we know that Mrs. White was never in the
envelope, so she's not the murderer.

### B9 · the total solution
Step to the end of the game, and in this game it's a total solution:
every card in every hand, and the three in the envelope, because one
determines the other. That's not always the case.

### B10 · Mycroft
On the third pane, for the library Mycroft, we have a completely
different way to do this. And this one isn't so easily asked for its
reasons. Instead you're handing the whole problem to an SMT solver, Z3,
and it's just giving you back a solution if there is one. Now, there may
be more than one solution. Every line here is one possible solution, one
complete world.

### B11 · the collapse
At the deal there are 44 trillion of them, and you can't draw that in a
browser. But when we get few enough to remain on the screen — in this
case 536 — we have a single line for each one, and the colour determines
who has it, or whether it's known or unknown. And if we step forward
deduction by deduction, the space collapses, and eventually three of the
columns turn solid red — and that means those three cards are, in all
cases, the ones that are in the envelope, and that means we have our
solution.

### B12 · backward
So although we can't draw 44 trillion possibilities for the starting
point, we can go backwards from the point we started out here, and we can
see that columns eventually become a single colour — because in all
possible configurations that are left, those cards are held by one
particular player, or they're in the envelope. And so we paint that
column with the player's colour when we know it. In this example the
Kitchen's column is solid even here, with 67 billion worlds still in
play. So that fact was locked in long before the space was ever small
enough to see.

### B13 · the two libraries (close)
So both libraries reach the same answer, very differently. Z3 is
deterministic: it crunches the whole pile of facts at once and pronounces
a solution, if one exists. Baskerville is working forward, accumulating
facts — but it has this real difference, that it can tell you *how* it
knew something, which sometimes is important. So if you're building a
build system, or a course-scheduling system, or a logistics engine,
sometimes you actually need to interrogate why something couldn't be
done, or why a solution couldn't be found.

*(Then the silent end-card: the four packages.)*
