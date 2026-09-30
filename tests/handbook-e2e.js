// Справочник: приборы с фотометрией производителей.
// Проверяется в браузере, а не чтением кода: данные лежат блоком JSON
// в самой странице, счёт экспозиции — в JS, раскладка — в вёрстке,
// и сходятся они только на экране. Проверяются:
//  - данные: блок читается, у каждого прибора источник, замеры
//    с расстоянием падают;
//  - счёт: освещённость между замерами и за ними, диафрагма по формуле
//    экспонометра (C = 250), «где получится T4» сходится с обратным счётом;
//  - планшет: вкладка в шапке, список, фильтр по бренду, поиск,
//    таблица замеров, строка режима нажимается (elementFromPoint),
//    «в каталог света проекта» кладёт прибор в каталог;
//  - телефон 390: путь «Ещё» → «Справочник», два экрана, без
//    горизонтальной прокрутки страницы;
//  - ссылка-просмотр ?view=handbook: вкладка одна, кнопки правки нет,
//    а ползунок расстояния (это чтение) под пальцем.
const fs = require('fs'), os = require('os'), path = require('path');
const { execSync, spawn } = require('child_process');
const ROOT = path.resolve(__dirname, '..'), LIBS = process.env.CF_LIBS || path.join(os.tmpdir(), 'cineflow-libs'), PORT = '8161';
let playwright;
try { playwright = require('playwright'); } catch (e) { playwright = require(execSync('npm root -g').toString().trim() + '/playwright'); }
const LIB_URLS = {
  'react.js': 'https://unpkg.com/react@18/umd/react.production.min.js',
  'react-dom.js': 'https://unpkg.com/react-dom@18/umd/react-dom.production.min.js',
  'babel.js': 'https://cdn.jsdelivr.net/npm/@babel/standalone@7/babel.min.js',
  'tailwind.js': 'https://cdn.tailwindcss.com'
};
fs.mkdirSync(LIBS, { recursive: true });
for (const [f, u] of Object.entries(LIB_URLS)) if (!fs.existsSync(path.join(LIBS, f))) execSync(`curl -sSL -o ${path.join(LIBS, f)} ${u}`);
const server = spawn('python3', ['-m', 'http.server', PORT, '--bind', '127.0.0.1'], { cwd: ROOT, stdio: 'ignore' });
let bad = 0;
const ok = (n, c, d) => { console.log((c ? '  ok  ' : '  FAIL') + ' ' + n + (d ? ' — ' + d : '')); if (!c) bad++; };
const SRC = JSON.parse(fs.readFileSync(path.join(ROOT, 'handbook', 'fixtures.json'), 'utf8'));

(async () => {
  await new Promise(r => setTimeout(r, 1000));
  const browser = await playwright.chromium.launch({ executablePath: '/opt/pw-browsers/chromium', args: ['--no-sandbox'] });
  const mk = async (w, h, query = '') => {
    const ctx = await browser.newContext({ viewport: { width: w, height: h }, isMobile: w < 768, hasTouch: true, serviceWorkers: 'block' });
    await ctx.route('**/*', route => {
      const u = route.request().url();
      // Настоящий Firebase ЗАБЛОКИРОВАН: иначе стенд писал бы в проект пользователя.
      if (/firestore|firebase|googleapis|gstatic/.test(u)) return route.abort();
      for (const [f, re] of [['react.js', /react@18\/umd\/react\.production/], ['react-dom.js', /react-dom@18/], ['babel.js', /babel\.min\.js/], ['tailwind.js', /cdn\.tailwindcss/]])
        if (re.test(u)) return route.fulfill({ body: fs.readFileSync(path.join(LIBS, f)), contentType: 'application/javascript' });
      route.continue();
    });
    await ctx.addInitScript(() => {
      localStorage.setItem('cf_room', 'hb-room'); localStorage.setItem('cf_user_name', 'Тест');
    });
    const page = await ctx.newPage();
    const errs = [];
    page.on('pageerror', e => errs.push(String(e).slice(0, 200)));
    await page.goto(`http://127.0.0.1:${PORT}/index.html${query}`);
    await page.waitForFunction(() => window.__CF_APP_OK, { timeout: 180000 });
    await page.waitForTimeout(1000);
    return { page, errs, ctx };
  };
  // Нажатие туда, куда нажал бы палец: центр элемента, и проверка, что
  // в этой точке лежит именно он (а не панель поверх).
  const tap = async (pg, sel, idx = 0) => {
    const r = await pg.evaluate(([s, i]) => {
      const el = [...document.querySelectorAll(s)].filter(e => e.offsetParent)[i];
      if (!el) return null;
      el.scrollIntoView({ block: 'center' });
      const b = el.getBoundingClientRect(), x = b.left + b.width / 2, y = b.top + b.height / 2;
      const hit = document.elementFromPoint(x, y);
      return { x, y, hit: !!hit && (el === hit || el.contains(hit)) };
    }, [sel, idx]);
    if (!r) return false;
    await pg.mouse.click(r.x, r.y);
    await pg.waitForTimeout(350);
    return r.hit;
  };

  // ---- ДАННЫЕ И СЧЁТ
  const { page: p, errs } = await mk(1194, 834);
  const data = await p.evaluate(() => hbFixtures().map(f => ({ brand: f.brand, name: f.name, url: f.url, rows: f.photometry.length })));
  ok('блок данных читается, приборов столько же, сколько в handbook/fixtures.json', data.length === SRC.length && data.length > 0, `${data.length} / ${SRC.length}`);
  ok('у каждого прибора ссылка на источник', data.every(f => /^https:\/\//.test(f.url || '')));
  const withPh = SRC.filter(f => (f.photometry || []).length);
  ok('есть приборы с фотометрией', withPh.length > 0, `${withPh.length}`);
  const calc = await p.evaluate(() => {
    const pts = [[1, 40000], [4, 2500]];
    const mid = hbLuxAt(pts, 2);                     // в логарифмах: 40000·(1/2)^2 = 10000
    const far = hbLuxAt(pts, 8);                     // обратные квадраты: 2500/4
    const near = hbLuxAt(pts, 0.5);                  // 40000·4
    const exact = hbLuxAt(pts, 4);
    const n = hbStop(1000, 800, 48);                 // √(1000·800/48/250) = 8,16
    const labels = [hbStopLabel(4), hbStopLabel(4 * Math.pow(2, 1 / 6)), hbStopLabel(2.8 * Math.pow(2, 2 / 6)), hbStopLabel(0.5), hbStopLabel(200)];
    const d4 = hbDistFor(pts, 4, 800, 48), back = hbStop(hbLuxAt(pts, d4), 800, 48);
    return { mid, far, near, exact, n, labels, d4, back };
  });
  ok('между замерами — закон обратных квадратов в логарифмах', Math.abs(calc.mid - 10000) < 1, String(calc.mid));
  ok('за замерами — обратные квадраты от крайней точки', Math.abs(calc.far - 625) < 1e-6 && Math.abs(calc.near - 160000) < 1e-6, `${calc.far} / ${calc.near}`);
  ok('в точке замера — ровно замер', calc.exact === 2500);
  ok('диафрагма по экспонометру C = 250: 1000 лк, ISO 800, 1/48 → 8,16', Math.abs(calc.n - 8.165) < 0.01, String(calc.n));
  ok('подписи диафрагмы по третям', JSON.stringify(calc.labels) === JSON.stringify(['T4', 'T4 +1/3', 'T2,8 +2/3', 'темнее T1', 'ярче T64']), JSON.stringify(calc.labels));
  ok('«где получится T4» сходится с обратным счётом', Math.abs(calc.back - 4) < 0.01, `${calc.d4} м → T${calc.back}`);

  // ---- ПЛАНШЕТ
  ok('вкладка «Справочник» в шапке нажимается', await tap(p, 'header button[title="Справочник"]'));
  const rows0 = await p.evaluate(() => document.querySelectorAll('[data-cf="hb-row"]').length);
  ok('список: все приборы', rows0 === SRC.length, `${rows0}`);
  const brands = [...new Set(SRC.map(f => f.brand))];
  const b0 = brands[0], nb0 = SRC.filter(f => f.brand === b0).length;
  await p.evaluate((b) => [...document.querySelectorAll('[data-cf="hb-list"] button.cf-chip')].find(x => x.textContent === b).click(), b0);
  await p.waitForTimeout(200);
  ok(`фильтр по бренду ${b0}`, await p.evaluate(() => document.querySelectorAll('[data-cf="hb-row"]').length) === nb0);
  await p.evaluate(() => [...document.querySelectorAll('[data-cf="hb-list"] button.cf-chip')].find(x => x.textContent === 'Все').click());
  // Число в списке — самый яркий режим на 3 м, и режим подписан под ним:
  // у XT26 это 20° рефлектор (193 100 лк), а не «прибор вообще».
  const xt = await p.evaluate(() => { const r = [...document.querySelectorAll('[data-cf="hb-row"]')].find(r => /Electro Storm XT26/.test(r.innerText)); return r ? r.querySelector('[data-cf="hb-peak"]').innerText.replace(/\s+/g, ' ') : ''; });
  ok('в списке у числа подписан режим и дистанция', /193 100 лк 20° · 3 м/.test(xt), xt);
  const target = withPh[withPh.length - 1];
  await p.fill('[data-cf="hb-search"]', target.name);
  await p.waitForTimeout(200);
  const found = await p.evaluate(() => [...document.querySelectorAll('[data-cf="hb-row"]')].map(r => r.innerText));
  ok('поиск по названию находит прибор', found.some(t => t.includes(target.name)), `${found.length}`);
  const idx = found.findIndex(t => t.includes(target.name));
  ok('строка прибора нажимается', await tap(p, '[data-cf="hb-row"]', idx));
  const card = await p.evaluate(() => ({
    h: (document.querySelector('[data-cf="hb-card"] h1') || {}).innerText,
    modes: document.querySelectorAll('[data-cf="hb-mode"]').length,
    stop: (document.querySelector('[data-cf="hb-stop"]') || {}).innerText,
    where: (document.querySelector('[data-cf="hb-where"]') || {}).innerText || '',
    src: (document.querySelector('[data-cf="hb-source"]') || {}).href
  }));
  ok('карточка: название, замеры, диафрагма, «где получится», источник',
     card.h === target.name && card.modes === target.photometry.length && /^T|темнее|ярче/.test(card.stop || '') && /T4/.test(card.where) && card.src === target.url,
     JSON.stringify(card));
  // Таблица в точности как у производителя: первое число первой строки.
  const first = target.photometry[0].pts.slice().sort((a, b) => a[0] - b[0])[0];
  const cell = await p.evaluate(() => [...document.querySelectorAll('[data-cf="hb-mode"]')[0].querySelectorAll('td')].slice(1).map(t => t.innerText).find(t => t !== '·'));
  ok('в таблице число производителя', cell && cell.replace(/\s/g, '') === String(Math.round(first[1])), `${cell} / ${first[1]}`);
  if (target.photometry.length > 1) {
    ok('вторая строка режима нажимается', await tap(p, '[data-cf="hb-mode"]', 1));
    ok('экспозиция считает по выбранной строке', await p.evaluate((m) => document.querySelector('[data-cf="hb-calc"]').innerText.includes(m), target.photometry[1].mod));
  }
  ok('«в каталог света проекта» нажимается', await tap(p, '[data-cf="hb-add"]'));
  await p.waitForTimeout(900);
  const cat = await p.evaluate(() => { try { return JSON.parse(localStorage.getItem('cf_lightgeartypes') || '{}'); } catch (e) { return {}; } });
  ok('прибор лёг в каталог света', Object.values(cat).some(g => g.label === (target.name.toLowerCase().startsWith(target.brand.toLowerCase() + " ") ? target.name : `${target.brand} ${target.name}`)), JSON.stringify(Object.values(cat).map(g => g.label)));
  ok('кнопка говорит, что уже в каталоге', /Уже в каталоге/.test(await p.evaluate(() => document.querySelector('[data-cf="hb-add"]').innerText)));
  ok('без ошибок на планшете', errs.length === 0, errs.join(' | '));

  // ---- ТЕЛЕФОН
  const { page: ph, errs: errs2 } = await mk(390, 844);
  await ph.evaluate(() => [...document.querySelectorAll('nav.cf-tabbar button')].find(b => /Ещё/.test(b.innerText)).click());
  await ph.waitForTimeout(400);
  ok('телефон: «Справочник» в «Ещё» нажимается', await tap(ph, '.cf-sheet button', await ph.evaluate(() => [...document.querySelectorAll('.cf-sheet button')].filter(e => e.offsetParent).findIndex(b => /Справочник/.test(b.innerText)))));
  const pl = await ph.evaluate(() => ({ rows: document.querySelectorAll('[data-cf="hb-row"]').length, w: Math.round(document.querySelector('[data-cf="hb-list"]').getBoundingClientRect().width), card: !!document.querySelector('[data-cf="hb-card"]') }));
  ok('телефон: список во всю ширину, карточки нет', pl.rows === SRC.length && pl.w === 390 && !pl.card, JSON.stringify(pl));
  const pIdx = await ph.evaluate((n) => [...document.querySelectorAll('[data-cf="hb-row"]')].findIndex(r => r.innerText.includes(n)), target.name);
  ok('телефон: прибор нажимается', await tap(ph, '[data-cf="hb-row"]', pIdx));
  const pc = await ph.evaluate(() => ({ card: !!document.querySelector('[data-cf="hb-card"]'), list: !!document.querySelector('[data-cf="hb-list"]'),
                                        sw: document.documentElement.scrollWidth, back: [...document.querySelectorAll('header button')].some(b => /‹ Справочник/.test(b.innerText)) }));
  ok('телефон: карточка во весь экран, «‹ Справочник» в шапке, страница не шире экрана', pc.card && !pc.list && pc.back && pc.sw <= 390, JSON.stringify(pc));
  const tableScroll = await ph.evaluate(() => { const t = document.querySelector('[data-cf="hb-table"]'); return t ? t.parentElement.scrollWidth >= t.parentElement.clientWidth : true; });
  ok('телефон: широкая таблица прокручивается сама, а не страница', tableScroll);
  await ph.evaluate(() => [...document.querySelectorAll('header button')].find(b => /‹ Справочник/.test(b.innerText)).click());
  await ph.waitForTimeout(300);
  ok('телефон: «‹ Справочник» возвращает к списку', await ph.evaluate(() => !!document.querySelector('[data-cf="hb-list"]') && !document.querySelector('[data-cf="hb-card"]')));
  ok('без ошибок на телефоне', errs2.length === 0, errs2.join(' | '));

  // ---- ПРОСМОТР ПО ССЫЛКЕ
  const { page: pv, errs: errs3 } = await mk(1194, 834, '?view=handbook&room=hb-room');
  const v = await pv.evaluate(() => ({
    tabs: [...document.querySelectorAll('header nav .cf-navtab')].filter(e => e.offsetParent).map(e => e.title),
    add: [...document.querySelectorAll('[data-cf="hb-add"]')].filter(e => e.offsetParent).length,
    rows: document.querySelectorAll('[data-cf="hb-row"]').length
  }));
  ok('просмотр: одна вкладка «Справочник», список на месте', v.tabs.length === 1 && v.tabs[0] === 'Справочник' && v.rows === SRC.length, JSON.stringify(v));
  ok('просмотр: кнопки «в каталог» нет', v.add === 0);
  const vIdx = await pv.evaluate((n) => [...document.querySelectorAll('[data-cf="hb-row"]')].findIndex(r => r.innerText.includes(n)), target.name);
  await tap(pv, '[data-cf="hb-row"]', vIdx);
  ok('просмотр: ползунок расстояния под пальцем', await tap(pv, '[data-cf="hb-dist"]'));
  ok('просмотр: поиск принимает ввод', await pv.evaluate(() => { const el = document.querySelector('[data-cf="hb-search"]'); const b = el.getBoundingClientRect(); const h = document.elementFromPoint(b.left + 10, b.top + b.height / 2); return h === el; }));
  ok('без ошибок в просмотре', errs3.length === 0, errs3.join(' | '));

  await browser.close(); server.kill();
  console.log(bad ? `\n${bad} FAIL` : '\nвсё ок');
  process.exit(bad ? 1 : 0);
})().catch(e => { console.error(e); server.kill(); process.exit(1); });
