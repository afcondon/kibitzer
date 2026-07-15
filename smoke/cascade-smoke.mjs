// Smoke test for the Cascade tab against the Bosun-served frontend.
import { createRequire } from 'module';
const require = createRequire('/Users/afc/node_modules/');
const puppeteer = require('puppeteer-core');

const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const URL = 'http://localhost:3026/?seed=42&players=4';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function check(name, cond, detail = '') {
  const flag = cond ? 'PASS' : 'FAIL';
  console.log(`${flag}  ${name}${detail ? '  — ' + detail : ''}`);
  if (!cond) process.exitCode = 1;
}

const browser = await puppeteer.launch({ executablePath: CHROME, headless: 'new' });
const page = await browser.newPage();
const consoleErrors = [];
page.on('console', (m) => { if (m.type() === 'error') consoleErrors.push(m.text()); });
page.on('pageerror', (e) => consoleErrors.push(String(e)));

await page.goto(URL, { waitUntil: 'networkidle0' });
await sleep(400);

// --- switch to the Cascade tab
await page.evaluate(() => {
  const btn = [...document.querySelectorAll('.tabs .tab')].find((b) => b.textContent === 'Cascade');
  btn.click();
});
await sleep(400);
// orbits are the grid's default layout — this smoke tests the table
await page.evaluate(() => {
  [...document.querySelectorAll('.view-btn')].find((b) => b.textContent === 'Table').click();
});
await sleep(900);

const chrome0 = await page.evaluate(() => ({
  svg: !!document.querySelector('#cascade-svg'),
  labels: document.querySelectorAll('#cascade-chrome text').length,
  markGroups: document.querySelectorAll('#cascade-marks g').length,
  stripBars: document.querySelectorAll('#cascade-strip rect').length,
  railText: document.querySelector('#cascade-rail text')?.textContent ?? '',
}));
check('SVG chrome present', chrome0.svg);
check('chrome text nodes = 21 labels + 5 headers', chrome0.labels === 26, `got ${chrome0.labels}`);
check('no marks at position 0', chrome0.markGroups === 0, `got ${chrome0.markGroups}`);
check('strip has one bar per position', chrome0.stripBars > 50, `got ${chrome0.stripBars}`);
check('rail shows pre-deal text', chrome0.railText.includes('Before the deal'), chrome0.railText);

// --- jump to end (instant, > animation cap)
await page.evaluate(() => {
  [...document.querySelectorAll('.transport-btn')].find((b) => b.textContent === '⏭').click();
});
await sleep(800);
const end = await page.evaluate(() => ({
  markGroups: document.querySelectorAll('#cascade-marks g').length,
  factCounter: document.querySelector('.stat.accent .stat-number')?.textContent
    ?? document.querySelectorAll('.stat-number')[1]?.textContent,
  edges: document.querySelectorAll('#cascade-edges line').length,
  currentBar: document.querySelectorAll('#cascade-strip rect').length,
}));
check('marks at end == facts inferred counter', String(end.markGroups) === end.factCounter,
  `marks ${end.markGroups} vs counter ${end.factCounter}`);
check('wiring on by default: settled edges visible', end.edges > 5, `got ${end.edges}`);

// --- wiring toggle hides the settled hairlines
const clickWiring = () => page.evaluate(() => {
  [...document.querySelectorAll('.cascade-toolbar label.toggle')]
    .find((l) => l.textContent.includes('wiring'))
    .querySelector('input').click();
});
await clickWiring();
await sleep(400);
const wired = await page.evaluate(() => document.querySelectorAll('#cascade-edges g').length);
check('wiring toggle off hides settled edges', wired === 0, `got ${wired}`);
await clickWiring();
await sleep(200);

// --- jump to start: everything must clear, no orphaned exits
await page.evaluate(() => {
  [...document.querySelectorAll('.transport-btn')].find((b) => b.textContent === '⏮').click();
});
await sleep(800);
const start = await page.evaluate(() => ({
  markGroups: document.querySelectorAll('#cascade-marks g').length,
  edges: document.querySelectorAll('#cascade-edges line').length,
}));
check('back to start clears marks', start.markGroups === 0, `got ${start.markGroups}`);
check('back to start clears edges', start.edges === 0, `got ${start.edges}`);

// --- step forward a few events, let the animation run
for (let i = 0; i < 8; i++) {
  await page.evaluate(() => {
    [...document.querySelectorAll('.transport-btn')].find((b) => b.textContent === '▶▶').click();
  });
  await sleep(120);
}
await sleep(2500); // let all enters land
const stepped = await page.evaluate(() => {
  const marks = [...document.querySelectorAll('#cascade-marks g')];
  const opacities = marks.map((g) =>
    parseFloat(g.querySelector('circle,text')?.getAttribute('opacity') ?? '1'));
  return {
    markGroups: marks.length,
    factCounter: document.querySelectorAll('.stat-number')[1]?.textContent,
    allLanded: opacities.every((o) => o > 0.7),
    brackets: document.querySelectorAll('#cascade-brackets g').length,
    rail: document.querySelector('#cascade-rail text')?.textContent ?? '',
  };
});
check('marks after 8 steps == counter', String(stepped.markGroups) === stepped.factCounter,
  `marks ${stepped.markGroups} vs counter ${stepped.factCounter}`);
check('all enter animations completed (opacity settled)', stepped.allLanded);
console.log(`INFO  rail: "${stepped.rail}", brackets: ${stepped.brackets}`);

// --- scrub back 3 (exits should fade then vanish)
for (let i = 0; i < 3; i++) {
  await page.evaluate(() => {
    [...document.querySelectorAll('.transport-btn')].find((b) => b.textContent === '◀').click();
  });
  await sleep(100);
}
await sleep(1500);
const back = await page.evaluate(() => ({
  markGroups: document.querySelectorAll('#cascade-marks g').length,
  factCounter: document.querySelectorAll('.stat-number')[1]?.textContent,
}));
check('scrub back removes exited marks', String(back.markGroups) === back.factCounter,
  `marks ${back.markGroups} vs counter ${back.factCounter}`);

// --- click a strip bar scrubs there
await page.evaluate(() => {
  const bars = document.querySelectorAll('#cascade-strip rect');
  bars[Math.floor(bars.length / 2)].dispatchEvent(new MouseEvent('click', { bubbles: true }));
});
await sleep(2500);
const clicked = await page.evaluate(() => ({
  markGroups: document.querySelectorAll('#cascade-marks g').length,
  factCounter: document.querySelectorAll('.stat-number')[1]?.textContent,
}));
check('strip click scrubs (marks == counter)', String(clicked.markGroups) === clicked.factCounter,
  `marks ${clicked.markGroups} vs counter ${clicked.factCounter}`);

// --- tab away and back: chrome rebuilt once, no duplication
await page.evaluate(() => {
  [...document.querySelectorAll('.tabs .tab')].find((b) => b.textContent === 'Game').click();
});
await sleep(300);
await page.evaluate(() => {
  [...document.querySelectorAll('.tabs .tab')].find((b) => b.textContent === 'Cascade').click();
});
await sleep(700);
// a remount resets the layout to orbits; return to the table
await page.evaluate(() => {
  [...document.querySelectorAll('.view-btn')].find((b) => b.textContent === 'Table').click();
});
await sleep(900);
const back2 = await page.evaluate(() => ({
  svgs: document.querySelectorAll('#cascade-svg').length,
  labels: document.querySelectorAll('#cascade-chrome text').length,
  markGroups: document.querySelectorAll('#cascade-marks g').length,
  factCounter: document.querySelectorAll('.stat-number')[1]?.textContent,
}));
check('tab roundtrip: exactly one SVG', back2.svgs === 1, `got ${back2.svgs}`);
check('tab roundtrip: chrome not duplicated', back2.labels === 26, `got ${back2.labels}`);
check('tab roundtrip: marks == counter', String(back2.markGroups) === back2.factCounter,
  `marks ${back2.markGroups} vs counter ${back2.factCounter}`);

// --- screenshot mid-game with wiring on for eyeballing
await page.setViewport({ width: 1200, height: 900 });
await page.screenshot({ path: process.env.SHOT || 'cascade-mid.png' });

check('no console errors', consoleErrors.length === 0, consoleErrors.slice(0, 3).join(' | '));

await browser.close();
console.log(process.exitCode ? 'SMOKE FAILED' : 'SMOKE OK');
