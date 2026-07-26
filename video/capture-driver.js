/* ============================================================================
   KIBITZER — capture driver
   ----------------------------------------------------------------------------
   Drives the live app deterministically through the video beat sheet
   (docs/video-beat-sheet.md, beats B1–B14) so the screen recording is one
   clean pass. Paste into the browser console on
   http://localhost:3026/?seed=768896&players=6  then run:  KDEMO.play()

   VO-FIRST: the T{} block below is the only thing to retime. Each key is a
   dwell or pace in milliseconds; set them from the measured VO segment
   durations once the narration is recorded. `KDEMO.speed` scales everything
   (2 = half speed, for rehearsal).

   Hooks (verified): tabs = nav.tabs button.tab [Game,Baskerville,Mycroft,About];
   float = .controls-float button [reroll,Play,‹Back,Forward›,‹Prev,Next›,Start,End];
   Mycroft is an iframe (same-origin) with its own buttons b0/bb/bp/bf/be, dp/dn.
   ========================================================================== */
window.KDEMO = (() => {
  // ---- retime these to the VO (milliseconds) --------------------------------
  const T = {
    holdAfterCut:   1200,  // let a page settle before narration lands
    b1:             9000,  // "Here's a single game… watch its notebook."
    gameFillStep:    280,  // pace of the brisk fill (ms per event)
    gameFillFrom:      1,  // start fast-fill at this position
    gameSlowFrom:     95,  // slow right down from here to the finish
    gameSlowStep:    850,
    b3Hold:         9000,  // hold on the completed notebook (the payoff)
    b4:            14000,  // the scaling numbers (About)
    b5:            12000,
    b6:            13000,  // Baskerville: the disjunction floats
    b7:             6000,  // "and there it sits…"
    b8Hold:        10000,  // hold on the E61 collapse + callout
    b9:            20000,  // the library idea (About)
    b10:            9000,  // Mycroft intro (does no legwork)
    b11:           12000,  // first enumerable frame — E71, 536 worlds; solid = known
    backStep:       5000,  // hold at E46 (~2.6M worlds, 3 solid columns)
    b12:           10000,  // hold at E18 (~67B worlds, 1 solid — the Kitchen)
    mycroftStep:    1600,  // dwell between forward deduction jumps (columns lock; red = envelope)
    b13Hold:       12000,  // hold on the solved state (E102: 21 solid, 3 red)
    b14:           18000,  // antecedents
    b15Hold:       10000,  // the four packages
  };

  let speed = 1;
  const sleep = ms => new Promise(r => setTimeout(r, ms * speed));

  const tabs  = () => [...document.querySelectorAll('nav.tabs button.tab')];
  const fbtns = () => [...document.querySelectorAll('.controls-float button')];
  const F = { play: 1, back: 2, fwd: 3, prevDed: 4, nextDed: 5, start: 6, end: 7 };

  const goTab = i => { tabs()[i]?.click(); };
  const press = k => { fbtns()[F[k]]?.click(); };

  // position readout (e.g. "E61 / E103" or "— / E103") for logging/guards
  const posText = () =>
    (document.querySelector('.controls-float')?.textContent.match(/E?\d+ ?\/ ?E\d+|— ?\/ ?E\d+/) || [''])[0];

  // ---- Mycroft iframe -------------------------------------------------------
  const iframe = () => document.querySelector('iframe.worlds-frame');
  const idoc   = () => iframe()?.contentDocument;
  const iclick = id => idoc()?.getElementById(id)?.click();
  const iScrub = pos => { const s = idoc()?.getElementById('scrub'); if (s) { s.value = pos; s.dispatchEvent(new Event('input', { bubbles: true })); } };
  async function waitIframe() {
    for (let i = 0; i < 60; i++) {
      if (idoc()?.getElementById('dn')) return true;
      await sleep(100);
    }
    return false;
  }

  // ---- beats -----------------------------------------------------------------
  async function reset() { location.hash = ''; goTab(0); await sleep(200); press('start'); await sleep(400); }

  async function play() {
    console.log('[KDEMO] start');
    await reset();

    // ---- 1 · Game: the watcher solves first (B1–B3) ------------------------
    await sleep(T.holdAfterCut);
    await sleep(T.b1);                                  // B1 intro over the empty notebook
    // B2: brisk fill, then slow to the finish
    let p = T.gameFillFrom;
    for (; p < T.gameSlowFrom; p++) { press('fwd'); await sleep(T.gameFillStep); }
    for (; !/^E102/.test(posText()); ) {               // slow run to the solve (after E102)
      press('fwd'); await sleep(T.gameSlowStep);
      if (/^—/.test(posText())) break;                 // safety
      if (p++ > 130) break;
    }
    await sleep(T.b3Hold);                              // B3: hold on the complete notebook

    // ---- 2 · The numbers (B4–B5) — About stats table -----------------------
    goTab(3); await sleep(T.holdAfterCut);
    scrollToText('How often the silent watcher wins');
    await sleep(T.b4);
    scrollToText('The point isn');                      // the eye call-out beat
    await sleep(T.b5);

    // ---- 3 · Baskerville: the E61 deduction (B6–B8) ------------------------
    goTab(1); await sleep(T.holdAfterCut); press('start'); await sleep(400);
    press('nextDed'); await sleep(T.b6);               // first real deduction (the disjunction is live)
    await sleep(T.b7);                                 // B7 "and there it sits…"
    stepDeductionUntil('E61');                          // land squarely on E61
    await sleep(T.b8Hold);                              // hold on the collapse + callout

    // ---- 4 · Baskerville the library (B9) — About --------------------------
    goTab(3); await sleep(T.holdAfterCut);
    scrollToText('Two libraries, two temperaments');
    await sleep(T.b9);

    // ---- 5 · Mycroft: the whole space (B10–B13) ----------------------------
    // opens at E71 (first enumerable, 536 worlds, ~8 columns already solid)
    goTab(2); await waitIframe(); await sleep(T.holdAfterCut);
    await sleep(T.b10 + T.b11);                        // B10–B11 intro + "solid = known"
    iScrub(47); await sleep(T.backStep);               // B12: step back — E46 (~2.6M, 3 solid)
    iScrub(19); await sleep(T.b12);                    // further back — E18 (~67B, 1 solid: Kitchen)
    // B13: forward through the collapse — columns lock, envelope columns go red
    for (let i = 0; i < 16; i++) { iclick('dn'); await sleep(T.mycroftStep); }
    iclick('be'); await sleep(600);                    // land on solved (E102: 21 solid, 3 red)
    await sleep(T.b13Hold);

    // ---- 6 · Antecedents + packages (B14–B15) — About ----------------------
    goTab(3); await sleep(T.holdAfterCut);
    scrollToText('Antecedents');
    await sleep(T.b14);
    scrollToText('The libraries');                      // the ink end-card
    await sleep(T.b15Hold);

    console.log('[KDEMO] done');
  }

  // walk the deduction stepper until the readout shows the target event
  function stepDeductionUntil(evt, max = 30) {
    let n = 0;
    while (!posText().startsWith(evt) && n++ < max) press('nextDed');
  }

  function scrollToText(txt) {
    const el = [...document.querySelectorAll('.prose h2, .prose .feature-title')]
      .find(h => h.textContent.trim().toLowerCase().startsWith(txt.toLowerCase()));
    (el || document.querySelector('.prose'))?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }

  return { play, reset, goTab, press, iclick, posText, T, get speed() { return speed; }, set speed(v) { speed = v; } };
})();
console.log('KDEMO ready — run KDEMO.play()  (KDEMO.speed = 2 for a slow rehearsal)');
