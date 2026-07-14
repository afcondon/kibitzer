// Smoke for the ControlPanel + TransportBar components after the
// componentization refactor: draft seed, deal, random, players, board.
import { createRequire } from 'module';
const require = createRequire('/Users/afc/node_modules/');
const puppeteer = require('puppeteer-core');

const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const URL0 = 'http://localhost:3026/?seed=42&players=4';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function check(name, cond, detail = '') {
  console.log(`${cond ? 'PASS' : 'FAIL'}  ${name}${detail ? '  — ' + detail : ''}`);
  if (!cond) process.exitCode = 1;
}

const browser = await puppeteer.launch({ executablePath: CHROME, headless: 'new' });
const page = await browser.newPage();
const consoleErrors = [];
page.on('console', (m) => { if (m.type() === 'error') consoleErrors.push(m.text()); });
page.on('pageerror', (e) => consoleErrors.push(String(e)));

await page.goto(URL0, { waitUntil: 'networkidle0' });
await sleep(400);

const state = () => page.evaluate(() => ({
  seed: document.querySelector('.controls input[type=text]').value,
  players: document.querySelector('.controls select').value,
  board: document.querySelector('.controls input[type=checkbox]').checked,
  url: location.search,
  events: document.querySelectorAll('.terminal li').length
    || document.querySelectorAll('.term-line').length,
  posLabel: document.querySelector('.position')?.textContent ?? '',
}));

const s0 = await state();
check('seed field shows URL seed', s0.seed === '42', s0.seed);
check('players select shows URL players', s0.players === '4', s0.players);

// --- type a draft seed, then Deal
await page.evaluate(() => {
  const input = document.querySelector('.controls input[type=text]');
  const setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
  setter.call(input, '156372');
  input.dispatchEvent(new Event('input', { bubbles: true }));
});
await page.evaluate(() => {
  [...document.querySelectorAll('.controls button')].find((b) => b.textContent === 'Deal').click();
});
await sleep(400);
const s1 = await state();
check('deal with typed seed updates URL', s1.url.includes('seed=156372'), s1.url);
check('seed field keeps typed seed', s1.seed === '156372', s1.seed);

// --- players change re-deals at once, carrying the seed
await page.select('.controls select', '6');
await sleep(400);
const s2 = await state();
check('players change re-deals (URL players=6)', s2.url.includes('players=6'), s2.url);
check('players change keeps seed', s2.url.includes('seed=156372'), s2.url);

// --- board toggle re-deals with moves=1
await page.evaluate(() => {
  document.querySelector('.controls input[type=checkbox]').click();
});
await sleep(400);
const s3 = await state();
check('board toggle re-deals (URL moves=1)', s3.url.includes('moves=1'), s3.url);
check('board checkbox reflects state', s3.board === true);

// --- random rolls a fresh seed and writes it back into the field
await page.evaluate(() => {
  [...document.querySelectorAll('.controls button')].find((b) => b.textContent === 'Random').click();
});
await sleep(400);
const s4 = await state();
check('random rolls a new seed', s4.seed !== '156372' && /^\d+$/.test(s4.seed), s4.seed);
check('random seed reaches the URL', s4.url.includes(`seed=${s4.seed}`), s4.url);
check('random keeps players and board', s4.url.includes('players=6') && s4.url.includes('moves=1'), s4.url);

// --- transport: play toggles, step moves the position label
await page.evaluate(() => {
  [...document.querySelectorAll('.transport-btn')].find((b) => b.textContent === '▶▶').click();
});
await sleep(200);
const s5 = await state();
check('step forward moves position', s5.posLabel.startsWith('E0'), s5.posLabel);
await page.evaluate(() => {
  [...document.querySelectorAll('.transport-btn')].find((b) => b.textContent === '⏭').click();
});
await sleep(200);
const s6 = await state();
check('jump to end', !s6.posLabel.startsWith('—') && !s6.posLabel.startsWith('E0 '), s6.posLabel);

check('no console errors', consoleErrors.length === 0, consoleErrors.slice(0, 3).join(' | '));
await browser.close();
console.log(process.exitCode ? 'CONTROLS SMOKE FAILED' : 'CONTROLS SMOKE OK');
