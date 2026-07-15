// Smoke for the header SeedControl + TransportBar and the ControlPanel
// (players/board): seed commits on Enter, reroll randomises, table-shape
// changes re-deal immediately with the committed seed.
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
  seed: document.querySelector('.seed-control input').value,
  players: document.querySelector('.controls select').value,
  board: document.querySelector('.controls input[type=checkbox]').checked,
  url: location.search,
  posLabel: document.querySelector('.position')?.textContent ?? '',
}));

const s0 = await state();
check('seed field (header) shows URL seed', s0.seed === '42', s0.seed);
check('players select shows URL players', s0.players === '4', s0.players);

// --- type a seed and press Enter: commits without any Deal button
await page.click('.seed-control input', { clickCount: 3 });
await page.type('.seed-control input', '156372');
await page.keyboard.press('Enter');
await sleep(400);
const s1 = await state();
check('Enter commits the typed seed (URL)', s1.url.includes('seed=156372'), s1.url);
check('seed field keeps the committed seed', s1.seed === '156372', s1.seed);

// --- players change re-deals at once with the committed seed
await page.select('.controls select', '6');
await sleep(400);
const s2 = await state();
check('players change re-deals (URL players=6)', s2.url.includes('players=6'), s2.url);
check('players change keeps the committed seed', s2.url.includes('seed=156372'), s2.url);

// --- board toggle re-deals with moves=1
await page.evaluate(() => {
  document.querySelector('.controls input[type=checkbox]').click();
});
await sleep(400);
const s3 = await state();
check('board toggle re-deals (URL moves=1)', s3.url.includes('moves=1'), s3.url);
check('board checkbox reflects state', s3.board === true);

// --- reroll rolls a fresh seed and writes it back into the field
await page.click('.seed-control .reroll');
await sleep(400);
const s4 = await state();
check('reroll rolls a new seed', s4.seed !== '156372' && /^\d+$/.test(s4.seed), s4.seed);
check('rerolled seed reaches the URL', s4.url.includes(`seed=${s4.seed}`), s4.url);
check('reroll keeps players and board', s4.url.includes('players=6') && s4.url.includes('moves=1'), s4.url);

// --- transport: step moves the position label, jump reaches the end
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
