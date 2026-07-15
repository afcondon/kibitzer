import { createRequire } from 'module';
const require = createRequire('/Users/afc/node_modules/');
const puppeteer = require('puppeteer-core');
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
function check(name, cond, detail = '') {
  console.log(`${cond ? 'PASS' : 'FAIL'}  ${name}${detail ? '  — ' + detail : ''}`);
  if (!cond) process.exitCode = 1;
}
const browser = await puppeteer.launch({ executablePath: CHROME, headless: 'new' });
const page = await browser.newPage();
await page.setViewport({ width: 1200, height: 950 });
const errors = [];
page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
page.on('pageerror', (e) => errors.push(String(e)));
await page.goto('http://localhost:3026/?seed=156372&players=6', { waitUntil: 'networkidle0' });
await sleep(300);
await page.evaluate(() => [...document.querySelectorAll('.tabs .tab')].find(b => b.textContent === 'Cascade').click());
await sleep(2500); // let the initial sim settle

const t0 = await page.evaluate(() => ({
  svg: !!document.querySelector('#packs-svg'),
  bubbles: document.querySelectorAll('#packs-bubbles circle').length,
  envelopeRect: !!document.querySelector('#packs-chrome rect'),
  seatLabels: [...document.querySelectorAll('#packs-chrome text')].map(t => t.textContent).join(''),
}));
check('packs SVG present', t0.svg);
check('7 packs × 21 cards = 147 bubbles at position 0', t0.bubbles === 147, `got ${t0.bubbles}`);
check('envelope rect present', t0.envelopeRect);
check('seat labels A–F + envelope label', t0.seatLabels.includes('A') && t0.seatLabels.includes('F') && t0.seatLabels.includes('THE ENVELOPE'), t0.seatLabels);

// jump to end: watcher solves this one — envelope should hold exactly 3 accent-ringed bubbles
await page.evaluate(() => [...document.querySelectorAll('.transport-btn')].find(b => b.textContent === '⏭').click());
await sleep(4500); // sim reheat + convergences settle

const t1 = await page.evaluate(() => {
  const bubbles = [...document.querySelectorAll('#packs-bubbles circle')];
  const accentRinged = bubbles.filter(c => c.getAttribute('stroke') === '#d92b2b');
  const inkRinged = bubbles.filter(c => c.getAttribute('stroke') === '#141414');
  return {
    total: bubbles.length,
    accentRinged: accentRinged.length,
    inkRinged: inkRinged.length,
    verdict: [...document.querySelectorAll('#cascade-rail text')].map(t => t.textContent).at(-1),
  };
});
check('envelope ends with exactly 3 located cards', t1.accentRinged === 3, `got ${t1.accentRinged}`);
check('verdict line present', (t1.verdict || '').includes('The watcher has it'), t1.verdict);
console.log(`INFO  end-state: ${t1.total} bubbles, ${t1.inkRinged} located in hands`);

// scrub to start: full 147 restored
await page.evaluate(() => [...document.querySelectorAll('.transport-btn')].find(b => b.textContent === '⏮').click());
await sleep(3500);
const t2 = await page.evaluate(() => document.querySelectorAll('#packs-bubbles circle').length);
check('scrub to start restores 147 possibilities', t2 === 147, `got ${t2}`);

// step through some early events; check orbits appear when a disjunction is live
let sawOrbit = false;
for (let i = 0; i < 20; i++) {
  await page.evaluate(() => [...document.querySelectorAll('.transport-btn')].find(b => b.textContent === '▶▶').click());
  await sleep(150);
  const orbits = await page.evaluate(() => document.querySelectorAll('#packs-orbits circle').length);
  if (orbits > 0) { sawOrbit = true; break; }
}
check('orbit guide appears once a disjunction is live', sawOrbit);
await sleep(2500);
const t3 = await page.evaluate(() => ({
  bubbles: document.querySelectorAll('#packs-bubbles circle').length,
  titles: document.querySelectorAll('#packs-bubbles title').length,
}));
console.log(`INFO  after 20 events: ${t3.bubbles} bubbles, ${t3.titles} tooltips`);
check('tooltips on bubbles', t3.titles > 100, `got ${t3.titles}`);

// both views coexist on the cross-referenced page
const both = await page.evaluate(() => ({
  packs: document.querySelectorAll('#packs-svg').length,
  grid: document.querySelectorAll('#cascade-svg').length,
}));
check('packs and orbits coexist, one SVG each', both.packs === 1 && both.grid === 1, JSON.stringify(both));

// cross-reference: hovering a confirmed bubble dims the rest and lights orbit marks
await page.evaluate(() => [...document.querySelectorAll('.transport-btn')].find(b => b.textContent === '⏭').click());
await sleep(4000);
const target = await page.evaluate(() => {
  const el = [...document.querySelectorAll('#packs-bubbles circle')]
    .find(c => c.getAttribute('stroke') === '#141414');
  if (!el) return null;
  const r = el.getBoundingClientRect();
  return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
});
check('found a located bubble to hover', !!target);
if (target) {
  await page.mouse.move(target.x, target.y);
  await sleep(600);
  const hovered = await page.evaluate(() => ({
    accentBubbles: [...document.querySelectorAll('#packs-bubbles circle')]
      .filter(c => c.getAttribute('stroke') === '#d92b2b').length,
    dimmedBubbles: [...document.querySelectorAll('#packs-bubbles circle')]
      .filter(c => parseFloat(c.getAttribute('opacity')) < 0.25).length,
    litMarks: document.querySelectorAll('#cascade-marks g').length > 0
      && [...document.querySelectorAll('#cascade-marks circle')]
        .some(c => c.getAttribute('stroke') === '#d92b2b' && c.getAttribute('fill') === 'none'),
  }));
  check('hover: implicated bubble accent-ringed', hovered.accentBubbles >= 1, `got ${hovered.accentBubbles}`);
  check('hover: the rest of the packs recede', hovered.dimmedBubbles > 5, `got ${hovered.dimmedBubbles}`);
  check('hover: orbit marks halo across the page', hovered.litMarks);
  await page.mouse.move(5, 5);
  await sleep(500);
  const restored = await page.evaluate(() =>
    [...document.querySelectorAll('#packs-bubbles circle')]
      .filter(c => parseFloat(c.getAttribute('opacity')) < 0.25).length);
  check('unhover restores the packs', restored < 5, `still dimmed: ${restored}`);
}

check('no console errors', errors.length === 0, errors.slice(0, 3).join(' | '));
await page.screenshot({ path: 'packs-early.png' });
await browser.close();
console.log(process.exitCode ? 'PACKS SMOKE FAILED' : 'PACKS SMOKE OK');
