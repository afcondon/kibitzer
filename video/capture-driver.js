/* ============================================================================
   KIBITZER — capture driver
   ----------------------------------------------------------------------------
   Drives the live app deterministically through the video beat sheet
   (docs/video-beat-sheet.md, beats B1–B13) so the screen recording is one
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
  // Timed to VO take 4 (docs/vo-take4-final.md) — word-proportional
  // per-beat lengths; fine sync is nudged in the edit.
  const T = {
    holdAfterCut:   1000,  // let a page settle before narration lands
    // 1 · Game — frame + hook (at the deal)
    b1:            30000,  // "I built this… six players… a seventh presence."
    b2:            34000,  // the metadata-privacy hook
    // 2 · Game — mechanic (rides the fill), result, scaling
    gameFillFrom:      1,  // brisk fill starts here
    gameFillStep:    270,  // ms per event through the midgame (~25s, covers B3)
    gameSlowFrom:     95,  // slow right down from here to the finish
    gameSlowStep:    900,  // ~6s to the solve
    b4Hold:        20000,  // hold on the completed notebook (the payoff)
    b5:            44000,  // scaling — held on the Game view
    // 3 · Baskerville — the two views + the E61 chain
    b6:            39000,  // the left view — possibilities fade as we step
    b7:            14000,  // the right view (deductions + why)
    b8Hold:        36000,  // the E61 chain (hangs, then resolves)
    b9:            14000,  // total solution (End)
    // 4 · Mycroft — collapse forward, then backward
    b10:           26000,  // frame — Mycroft wraps Z3, every line a world
    mycFwdStep:     2900,  // dn pace for the forward collapse (13 × ≈ 38s)
    b11Hold:        3000,  // rest on solved (3 red columns)
    b12:           39000,  // backward — E46 then E18 (Kitchen solid at ~67B)
    // 5 · the two-libraries close, then the silent end-card
    b13Hold:       33000,  // held on the solved Mycroft frame
    outroHold:      9000,  // the four packages (④ About colophon), no VO
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

    // ---- 1 · Game: frame + the metadata hook (at the deal) -----------------
    await sleep(T.holdAfterCut);
    await sleep(T.b1 + T.b2);

    // ---- 2 · Game: mechanic (over the fill), result, scaling ---------------
    let p = T.gameFillFrom;
    for (; p < T.gameSlowFrom; p++) { press('fwd'); await sleep(T.gameFillStep); }  // brisk fill (B3)
    for (; !/^E102/.test(posText()); ) {               // slow run to the solve
      press('fwd'); await sleep(T.gameSlowStep);
      if (/^—/.test(posText()) || p++ > 130) break;    // safety
    }
    await sleep(T.b4Hold);                             // B4: hold on the complete notebook
    await sleep(T.b5);                                 // B5: scaling, still on the Game view

    // ---- 3 · Baskerville: the two views + the E61 chain --------------------
    goTab(1); await sleep(T.holdAfterCut); press('start'); await sleep(400);
    // B6: slowly step forward so possibilities visibly fade while described
    for (let i = 0; i < 8; i++) { press('fwd'); await sleep(T.b6 / 8); }
    await sleep(T.b7);                                 // B7 right view / hover-why (hold)
    stepDeductionUntil('E61'); await sleep(T.b8Hold);  // B8: the chain resolves at E61
    press('end'); await sleep(T.b9);                   // B9: total solution

    // ---- 4 · Mycroft: collapse forward, then backward ---------------------
    goTab(2); await waitIframe(); await sleep(T.holdAfterCut);
    await sleep(T.b10);                                // B10 frame, at E71 (536 worlds)
    for (let i = 0; i < 13; i++) { iclick('dn'); await sleep(T.mycFwdStep); }  // B11 forward collapse
    iclick('be'); await sleep(T.b11Hold);             // land on solved (3 red columns)
    iScrub(47); await sleep(T.b12 * 0.4);             // B12 backward — E46 (~2.6M, 3 solid)
    iScrub(19); await sleep(T.b12 * 0.6);             // …to E18 (~67B, 1 solid: the Kitchen)

    // ---- 5 · the two-libraries close, held on the solved frame ------------
    iScrub(103); await sleep(T.b13Hold);              // back to solved; B13 close

    // ---- silent end-card: the four packages (④ About colophon) -----------
    goTab(3); await sleep(T.holdAfterCut);
    scrollToText('The libraries');
    await sleep(T.outroHold);

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
