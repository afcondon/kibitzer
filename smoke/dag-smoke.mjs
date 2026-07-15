// The grid's three layouts: table ⇄ skyline ⇄ orbits. Checks the morph
// moves marks, chrome/axis/ring guides fade correctly, the radial sim
// holds facts on their depth rings with envelope certainties at the
// bullseye, and scrubbing works inside every layout.
import { createRequire } from 'module';
const require = createRequire('/Users/afc/node_modules/');
const puppeteer = require('puppeteer-core');
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
function check(n, c, d = '') { console.log(`${c ? 'PASS' : 'FAIL'}  ${n}${d ? '  — ' + d : ''}`); if (!c) process.exitCode = 1; }
const browser = await puppeteer.launch({ executablePath: CHROME, headless: 'new' });
const page = await browser.newPage();
await page.setViewport({ width: 1440, height: 900 });
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
await page.goto('http://localhost:3026/?seed=42&players=4', { waitUntil: 'networkidle0' });
await sleep(300);
await page.evaluate(() => [...document.querySelectorAll('.tabs .tab')].find(b => b.textContent === 'Cascade').click());
await sleep(400);
await page.evaluate(() => [...document.querySelectorAll('.view-btn')].find(b => b.textContent === 'Grid').click());
await sleep(500);
await page.evaluate(() => [...document.querySelectorAll('.transport-btn')].find(b => b.textContent === '⏭').click());
await sleep(1200);

const clickLayout = (label) => page.evaluate((l) => {
  [...document.querySelectorAll('.view-btn')].find(b => b.textContent === l).click();
}, label);

const snap = () => page.evaluate(() => {
  const marks = [...document.querySelectorAll('#cascade-marks g')];
  const first = marks[0]?.querySelector('circle,text');
  const chrome = document.querySelector('#cascade-chrome g');
  return {
    marks: marks.length,
    firstPos: first ? [first.getAttribute('cx') ?? first.getAttribute('x'), first.getAttribute('cy') ?? first.getAttribute('y')].join(',') : '',
    chromeOpacity: chrome?.getAttribute('opacity'),
    axisLines: document.querySelectorAll('#cascade-dagaxis g').length,
    rings: document.querySelectorAll('#cascade-rings circle').length,
    ringsOpacity: parseFloat(document.querySelector('#cascade-rings circle')?.getAttribute('opacity') ?? '0'),
    edges: document.querySelectorAll('#cascade-edges g').length,
  };
});

const table = await snap();
check('table view: marks == 51', table.marks === 51, `got ${table.marks}`);
check('table view: chrome opaque', parseFloat(table.chromeOpacity) === 1, table.chromeOpacity);
check('table view: ring guides invisible', table.ringsOpacity < 0.05, `${table.ringsOpacity}`);

// --- skyline
await clickLayout('Skyline');
await sleep(1200); // morph completes (~550ms)
const sky = await snap();
check('skyline: marks survive', sky.marks === 51, `got ${sky.marks}`);
check('skyline: marks moved', sky.firstPos !== table.firstPos, `${table.firstPos} -> ${sky.firstPos}`);
check('skyline: chrome faded out', parseFloat(sky.chromeOpacity) < 0.05, sky.chromeOpacity);
check('skyline: axis levels present', sky.axisLines >= 2, `got ${sky.axisLines}`);
check('skyline: edges raised', sky.edges > 5, `got ${sky.edges}`);

// --- orbits (radial sim)
await clickLayout('Orbits');
await sleep(3000); // morph + sim settle
const orb = await snap();
check('orbits: marks survive', orb.marks === 51, `got ${orb.marks}`);
check('orbits: marks moved again', orb.firstPos !== sky.firstPos, `${sky.firstPos} -> ${orb.firstPos}`);
check('orbits: ring guides visible', orb.ringsOpacity > 0.4, `${orb.ringsOpacity}`);
check('orbits: ring guide per level + bullseye', orb.rings === orb.axisLines + 1,
  `rings ${orb.rings} vs levels ${orb.axisLines}`);

// physics: everything holds inside the outer ring
const radial = await page.evaluate(() => {
  const cx = 380, cy = 350;
  const dist = (el) => Math.hypot(parseFloat(el.getAttribute('cx')) - cx, parseFloat(el.getAttribute('cy')) - cy);
  const all = [...document.querySelectorAll('#cascade-marks circle')].map(dist);
  const guides = [...document.querySelectorAll('#cascade-rings circle')].map(c => parseFloat(c.getAttribute('r')));
  return { maxDist: Math.max(...all), outer: Math.max(...guides) };
});
check('orbits: dots inside the outer ring', radial.maxDist < radial.outer + 25,
  `max ${radial.maxDist.toFixed(0)} vs outer ${radial.outer}`);

// scrub while in orbits: population follows, then repopulates
await page.evaluate(() => [...document.querySelectorAll('.transport-btn')].find(b => b.textContent === '⏮').click());
await sleep(900);
const start = await snap();
check('orbits scrub-to-start: 0 marks', start.marks === 0, `got ${start.marks}`);
await page.evaluate(() => [...document.querySelectorAll('.transport-btn')].find(b => b.textContent === '⏭').click());
await sleep(2000);
const refill = await snap();
check('orbits scrub-to-end: marks return', refill.marks === 51, `got ${refill.marks}`);

// --- straight back to the table (radial → table morph, no stop at skyline)
await clickLayout('Table');
await sleep(1400);
const back = await snap();
check('morph back: chrome restored', parseFloat(back.chromeOpacity) === 1, back.chromeOpacity);
check('morph back: positions restored', back.firstPos === table.firstPos, `${back.firstPos}`);
check('morph back: ring guides gone', back.ringsOpacity < 0.05, `${back.ringsOpacity}`);
check('no page errors', errors.length === 0, errors.slice(0, 2).join('|'));

// --- bullseye physics needs a solved game: seed 33 six players
await page.goto('http://localhost:3026/?seed=33&players=6', { waitUntil: 'networkidle0' });
await sleep(300);
await page.evaluate(() => [...document.querySelectorAll('.tabs .tab')].find(b => b.textContent === 'Cascade').click());
await sleep(400);
await page.evaluate(() => [...document.querySelectorAll('.view-btn')].find(b => b.textContent === 'Grid').click());
await sleep(500);
await page.evaluate(() => [...document.querySelectorAll('.transport-btn')].find(b => b.textContent === '⏭').click());
await sleep(900);
await clickLayout('Orbits');
await sleep(3500); // dense game; let the sim settle properly
const bullseye = await page.evaluate(() => {
  const cx = 380, cy = 350;
  const dist = (el) => Math.hypot(parseFloat(el.getAttribute('cx')) - cx, parseFloat(el.getAttribute('cy')) - cy);
  return [...document.querySelectorAll('#cascade-marks circle')]
    .filter(d => d.getAttribute('fill') === '#d92b2b').map(dist);
});
check('solved game: 3 envelope certainties at the bullseye',
  bullseye.length === 3 && bullseye.every(d => d < 45),
  `distances ${bullseye.map(d => d.toFixed(0)).join(',') || 'none'}`);

// screenshots: settled orbits on the deep game
await page.screenshot({ path: 'orbits-full.png' });
await browser.close();
console.log(process.exitCode ? 'LAYOUTS SMOKE FAILED' : 'LAYOUTS SMOKE OK');
