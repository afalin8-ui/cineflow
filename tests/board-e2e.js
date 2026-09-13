// Полоса вкладок досок и её меню «···».
//
// Почему проверяется именно нажатием: меню под ПРОКРУЧИВАЕМОЙ строкой
// срезается целиком — у контейнера с `overflow-x: auto` второй оси тоже
// достаётся `auto`, — и строки меню при этом ЕСТЬ в разметке, а нажатие
// уходит мимо. «Есть ли элемент» тут не значит ничего, нужен
// elementFromPoint.
//
// Что гоняем: на телефоне трёх кнопок действий в полосе нет (390 точек
// заняты досками и схемами, а безымянные значки там ничего не говорят),
// они переехали в «···» строками с названиями, каждая нажимается
// и правда работает; на планшете остались под рукой.
//
// Запуск:  node tests/board-e2e.js
const path = require('path'), fs = require('fs'), os = require('os');
const { execSync, spawn } = require('child_process');
const ROOT = '/home/user/cineflow';
const LIBS = process.env.CF_LIBS || path.join(os.tmpdir(), 'cineflow-libs');
const PORT = process.env.CF_PORT || '8107';
let playwright;
try { playwright = require('playwright'); }
catch (e) { playwright = require(execSync('npm root -g').toString().trim() + '/playwright'); }
const server = spawn('python3', ['-m','http.server',PORT,'--bind','127.0.0.1'], { cwd: ROOT, stdio: 'ignore' });
let bad = 0;
const ok = (n, c, d) => { console.log((c ? '  ok  ' : '  FAIL') + ' ' + n + (d ? ' — ' + d : '')); if (!c) bad++; };
(async () => {
  await new Promise(r => setTimeout(r, 1200));
  const browser = await playwright.chromium.launch({ executablePath: process.env.CF_CHROME || '/opt/pw-browsers/chromium', args: ['--no-sandbox'] });
  const mk = async (w, h) => {
    const ctx = await browser.newContext({ viewport: { width: w, height: h }, isMobile: w < 768, hasTouch: true });
    await ctx.route('**/*', (route) => {
      const u = route.request().url();
      if (/firestore|firebase|googleapis|gstatic|nominatim/.test(u)) return route.abort();
      for (const [f, re] of [['react.js',/react@18\/umd\/react\.production/],['react-dom.js',/react-dom@18/],['babel.js',/babel\.min\.js/],['tailwind.js',/cdn\.tailwindcss/]])
        if (re.test(u)) return route.fulfill({ body: fs.readFileSync(path.join(LIBS, f)), contentType: 'application/javascript' });
      route.continue();
    });
    await ctx.addInitScript(() => {
      localStorage.setItem('cf_room', 'bb-room');
      localStorage.setItem('cf_user_name', 'Тест');
      localStorage.setItem('cf_boards', JSON.stringify(
        Array.from({ length: 8 }, (_, i) => ({ id: 'b' + i, title: 'Доска номер ' + (i + 1), order: i }))));
      localStorage.setItem('cf_lightschemes', JSON.stringify([{ id: 'ls1', title: 'Схема света', elements: [], drawData: '' }]));
    });
    const page = await ctx.newPage();
    await page.goto(`http://127.0.0.1:${PORT}/index.html`);
    await page.waitForFunction(() => window.__CF_APP_OK, { timeout: 90000 });
    await page.waitForTimeout(1200);
    await page.evaluate(async () => {
      const b = [...document.querySelectorAll('.cf-tabbar button, header button')]
        .find(x => /Ещё/.test(x.textContent));
      if (b) { b.click(); await new Promise(r => setTimeout(r, 500)); }
      const d = [...document.querySelectorAll('button')].find(x => x.textContent.trim() === 'Доски');
      if (d) d.click();
      await new Promise(r => setTimeout(r, 900));
    });
    return page;
  };

  // ---- ТЕЛЕФОН
  const ph = await mk(390, 844);
  // Кнопки ищем ПО ПОДСКАЗКЕ, а не по месту в дереве: разметку правят,
  // а подсказка — то, что обещано человеку.
  const acts = () => ({
    put: !!document.querySelector('[title^="Положить на доску"]'),
    sticky: !!document.querySelector('[title="Стикер"]'),
    ref: !!document.querySelector('[title="Новый референс"]')
  });
  const strip = await ph.evaluate(acts);
  ok('в полосе вкладок на телефоне этих трёх кнопок нет',
     !strip.put && !strip.sticky && !strip.ref, JSON.stringify(strip));
  const rows = await ph.evaluate(async () => {
    const menu = [...document.querySelectorAll('button')].find(b => b.textContent.trim() === '···');
    menu.click();
    await new Promise(r => setTimeout(r, 400));
    const m = document.querySelector('.cf-menu');
    if (!m) return { err: 'меню не открылось' };
    const items = [...m.querySelectorAll('button')];
    const hit = items.map(b => {
      const r = b.getBoundingClientRect();
      const t = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
      return { text: b.textContent.trim(), ok: !!t && (t === b || b.contains(t)),
               inScreen: r.left >= 0 && r.right <= window.innerWidth && r.top >= 0 && r.bottom <= window.innerHeight };
    });
    return { items: hit };
  });
  if (rows.err) ok('меню «···» открылось', false, rows.err);
  else {
    ok('в меню появились «Положить на доску», «Стикер», «Референс»',
       rows.items.some(i => /Положить/.test(i.text)) && rows.items.some(i => /стикер/i.test(i.text)) &&
       rows.items.some(i => /референс/i.test(i.text)), rows.items.map(i => i.text).join(' · '));
    ok('каждая строка меню НАЖИМАЕТСЯ (не срезана полосой)',
       rows.items.every(i => i.ok), rows.items.filter(i => !i.ok).map(i => i.text).join(' · ') || 'все');
    ok('и ни одна не уехала за край экрана',
       rows.items.every(i => i.inScreen), rows.items.filter(i => !i.inScreen).map(i => i.text).join(' · ') || 'все внутри');
  }
  // Действие правда работает
  const acted = await ph.evaluate(async () => {
    const before = JSON.parse(localStorage.getItem('cf_stickies') || '[]').length;
    const b = [...document.querySelectorAll('.cf-menu button')].find(x => /Новый стикер/.test(x.textContent));
    if (!b) return { err: 'строки «Новый стикер» нет' };
    b.click();
    await new Promise(r => setTimeout(r, 900));
    return { before, after: JSON.parse(localStorage.getItem('cf_stickies') || '[]').length };
  });
  ok('строка «Новый стикер» правда заводит стикер',
     acted.after === acted.before + 1, JSON.stringify(acted));

  // ---- ПЛАНШЕТ: иконки остаются на месте
  const tab = await mk(1194, 834);
  const tabStrip = await tab.evaluate(acts);
  ok('на планшете все три остались в полосе под рукой',
     tabStrip.put && tabStrip.sticky && tabStrip.ref, JSON.stringify(tabStrip));

  await browser.close(); server.kill();
  console.log(bad ? `\n${bad} проверок не прошло` : '\nВсё прошло');
  process.exit(bad ? 1 : 0);
})().catch(e => { console.error(e); server.kill(); process.exit(1); });
