# VO — take 3 (free, unscripted), transcribed and cleaned

*Transcription of `baskerville vo 3 free.mp3` (6:29) — you talking through
the site with no script. ASR errors fixed (Cluedo, Mycroft, "dealt",
etc.); your phrasing left alone. Grouped into the natural sections your
delivery fell into.*

---

### Frame — what this is
So I built this little simulation of the game Cluedo in order to
demonstrate two small new libraries, both of which are concerned with
doing deduction.

### Game — the watcher, the mechanic, the result
In this first screen we can see the game has been dealt out. There's an
envelope with three hidden cards. And there's this hidden watcher — this
imaginary spy who's watching — which is our deduction machine. As we step
through the moves the players make, the watcher is recording facts.

The most basic facts are when somebody passes: you know they don't have
any of the three cards in the suggestion. But there are things you can
deduce once you've accumulated enough information. If somebody has shown
a card at some point, they had one of the three cards in the suggestion.
If we can later rule out two of those cards, then we know what the third
was — and so forth. It forms a chain of deduction.

And in fact, using the first of these libraries — Baskerville — as the
watcher, we're able to beat the players some of the time. So the idea is
not that the watcher can beat the players all of the time. That's very
determined by how well the players play, and these players are playing
very randomly, rather stupidly. But also the number of players affects
it: if you have more players, they all start with less information, and
they're also making more suggestions — basically circulating more facts.
So the watcher watches this go by, and eventually, in this particular
example, it's able to solve the thing before any player is.

### Baskerville pane — the two visualisations
Now if we go to the Baskerville second pane, instead of seeing the table
we see two visualisations, showing us the starting position. On the
left-hand side we have what the watcher knows — which is that anybody
could have any card, and there could be any cards in the envelope. But as
we progress, we can eliminate cards; we visualise that by the cards
becoming translucent, less opaque. And eventually we start to discover
who actually has what cards — which immediately means we can remove those
possibilities from the other players. And if we've removed a card from
all players, then we know it's in the envelope.

On the right-hand side we see the deductions and their reasons. If you
hover over a deduction, you'll see something like "F does not hold the
Wrench" — and you can see why you know that. Gradually, as you step
through the game, you build up a big picture, and you can see the logic
directly displayed. So you get to the end, and in this case it's a total
solution: we know exactly what cards every player holds, and we know what
cards are in the envelope — because one determines the other.

### Mycroft — the SMT solver, and the collapse
Now there's another way of approaching this, which is not so easily
interrogated for reasons: to use an SMT solver, such as Z3. That's what
my other library, Mycroft, does — it wraps up the Z3 solver.

Here in this third screen, every single line represents a possible
solution. When you start a game of Cluedo there are 44 trillion
possibilities — we can't reasonably draw that in a browser — so we start
part-way through, where there are only 536 possible solutions left. As
you step forward, deduction by deduction, the number of possibilities
dramatically reduces, and eventually it comes to be determined: you know
exactly who has what. And when there are three red columns — three cards
in the envelope which are known — that's your solution.

Now, interestingly, you can go back to the beginning in this
visualisation. And although you can't draw 44 trillion possibilities, you
can show some things. What we do is show that, at a certain point, it's
already known who holds a certain card — because every line in that
column is one single colour. So we can colour that column by the colour
of the player who holds it.

### Close — the two libraries compared
So the two libraries both arrive at solutions. Z3 is deterministic: it
runs for a while, crunches on the available data, and spits out a
solution if there is one. Baskerville works forward, little by little,
adding facts to the pile — but with the significant difference that it
can tell you *how* it deduced something. Which can be useful if, for
example, you're trying to understand a build system, or a university
course-scheduling system, or a logistics engine.
