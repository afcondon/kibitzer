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

const snap = () => page.evaluate(() => {
  const marks = [...document.querySelectorAll('#cascade-marks g')];
  const first = marks[0]?.querySelector('circle,text');
  const chrome = document.querySelector('#cascade-chrome g');
  return {
    marks: marks.length,
    firstPos: first ? [first.getAttribute('cx') ?? first.getAttribute('x'), first.getAttribute('cy') ?? first.getAttribute('y')].join(',') : '',
    chromeOpacity: chrome?.getAttribute('opacity'),
    axisLines: document.querySelectorAll('#cascade-dagaxis g').length,
    edges: document.querySelectorAll('#cascade-edges g').length,
  };
});

const table = await snap();
check('table view: marks == 51', table.marks === 51, `got ${table.marks}`);
check('table view: chrome opaque', parseFloat(table.chromeOpacity) === 1, table.chromeOpacity);

// toggle DAG (second toggle in grid legend)
await page.evaluate(() => [...document.querySelectorAll('.cascade-toolbar .toggle input')].at(-1).click());
await sleep(1200); // morph completes (~550ms)
const dag = await snap();
check('DAG view: marks survive', dag.marks === 51, `got ${dag.marks}`);
check('DAG view: marks moved', dag.firstPos !== table.firstPos, `${table.firstPos} -> ${dag.firstPos}`);
check('DAG view: chrome faded out', parseFloat(dag.chromeOpacity) < 0.05, dag.chromeOpacity);
check('DAG view: axis levels present', dag.axisLines >= 2, `got ${dag.axisLines}`);
check('DAG view: edges raised', dag.edges > 5, `got ${dag.edges}`);

// scrub while in DAG view: marks land at DAG homes
await page.evaluate(() => [...document.querySelectorAll('.transport-btn')].find(b => b.textContent === '⏮').click());
await sleep(900);
const start = await snap();
check('DAG view scrub-to-start: 0 marks', start.marks === 0, `got ${start.marks}`);

// morph back
await page.evaluate(() => [...document.querySelectorAll('.transport-btn')].find(b => b.textContent === '⏭').click());
await sleep(1200);
await page.evaluate(() => [...document.querySelectorAll('.cascade-toolbar .toggle input')].at(-1).click());
await sleep(1200);
const back = await snap();
check('morph back: chrome restored', parseFloat(back.chromeOpacity) === 1, back.chromeOpacity);
check('morph back: positions restored', back.firstPos === table.firstPos, `${back.firstPos}`);
check('no page errors', errors.length === 0, errors.slice(0, 2).join('|'));

// screenshots: mid-morph + full DAG
await page.evaluate(() => [...document.querySelectorAll('.cascade-toolbar .toggle input')].at(-1).click());
await sleep(260);
await page.screenshot({ path: 'dag-midmorph.png' });
await sleep(1000);
await page.screenshot({ path: 'dag-full.png' });
await browser.close();
console.log(process.exitCode ? 'DAG SMOKE FAILED' : 'DAG SMOKE OK');
