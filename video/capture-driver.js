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
  const T = {
    holdAfterCut:   1200,  // let a page settle before narration lands
    // 1 · Game — frame + hook (at the deal)
    b1:            11000,  // "I built this… six players… a seventh presence."
    b2:            12000,  // the metadata-privacy hook
    // 2 · Game — mechanic (rides the fill), result, scaling
    gameFillFrom:      1,  // brisk fill starts here
    gameFillStep:    260,  // ms per event through the midgame (covers B3)
    gameSlowFrom:     95,  // slow right down from here to the finish
    gameSlowStep:    850,
    b4Hold:         9000,  // hold on the completed notebook (the payoff)
    b5:            16000,  // scaling — held on the Game view
    // 3 · Baskerville — the two views + the E61 chain
    b6:            13000,  // the left view (possibilities), at the start
    b7:             8000,  // the right view (deductions + why)
    b8Hold:        11000,  // the E61 collapse + callout
    b9:             8000,  // total solution (End)
    // 4 · Mycroft — collapse forward, then backward
    b10:           11000,  // frame — Mycroft wraps Z3, every line a world
    mycFwdStep:     1400,  // dn pace for the forward collapse
    b11Hold:        8000,  // hold on solved (3 red columns)
    b12:           13000,  // backward at E18 (Kitchen solid at ~67B)
    // 5 · the two-libraries close, then the silent end-card
    b13Hold:       17000,  // held on the solved Mycroft frame
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
    await sleep(T.b6 + T.b7);                          // B6 left view (possibilities), B7 right view / why
    stepDeductionUntil('E61'); await sleep(T.b8Hold);  // B8: the collapse + callout
    press('end'); await sleep(T.b9);                   // B9: total solution

    // ---- 4 · Mycroft: collapse forward, then backward ---------------------
    goTab(2); await waitIframe(); await sleep(T.holdAfterCut);
    await sleep(T.b10);                                // B10 frame, at E71 (536 worlds)
    for (let i = 0; i < 13; i++) { iclick('dn'); await sleep(T.mycFwdStep); }  // B11 forward collapse
    iclick('be'); await sleep(T.b11Hold);             // land on solved (3 red columns)
    iScrub(19); await sleep(T.b12);                   // B12 backward — E18 (Kitchen solid at ~67B)

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
