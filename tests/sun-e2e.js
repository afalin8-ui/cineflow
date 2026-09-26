// Раскладка дня по свету: сумерки, восход, золотой час, день, закат —
// в «Сценах» (панель сцены, шторка на телефоне) и в «Объектах»,
// и она же строкой в отчёте по объекту. Подписи «по часам устройства»
// там больше нет.
// Проверяется в браузере, а не чтением кода: счёт живёт в JS, полоса —
// в вёрстке, и сходятся они только на экране. Счёт проверяется на
// крайних случаях: обычный день, белые ночи, полярный день и ночь.
const fs = require('fs'), os = require('os'), path = require('path');
const { execSync, spawn } = require('child_process');
const ROOT = path.resolve(__dirname, '..'), LIBS = process.env.CF_LIBS || path.join(os.tmpdir(), 'cineflow-libs'), PORT = '8154';
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
const seed = {
  cf_scenes: [{ id: 'sc1', number: '1', title: 'НАТ. ДВОР — ДЕНЬ', content: '', script: '', date: '2026-10-01', boardId: '' }],
  cf_locations: [{ id: 'loc1', name: 'Двор на Горской', address: 'Москва', coords: '55.7558, 37.6173', sceneIds: ['sc1'], order: 1 }]
};
(async () => {
  await new Promise(r => setTimeout(r, 1000));
  const browser = await playwright.chromium.launch({ executablePath: '/opt/pw-browsers/chromium', args: ['--no-sandbox'] });
  const mk = async (w, h) => {
    // Часовой пояс задан ЯВНО: раскладка показывается по местным часам,
    // и без этого числа в проверке зависели бы от того, где стоит стенд.
    const ctx = await browser.newContext({ viewport: { width: w, height: h }, isMobile: w < 768, hasTouch: true,
                                           serviceWorkers: 'block', timezoneId: 'Europe/Moscow' });
    await ctx.route('**/*', route => {
      const u = route.request().url();
      // Настоящий Firebase ЗАБЛОКИРОВАН: иначе стенд писал бы в проект пользователя.
      if (/firestore|firebase|googleapis|gstatic|nominatim/.test(u)) return route.abort();
      for (const [f, re] of [['react.js', /react@18\/umd\/react\.production/], ['react-dom.js', /react-dom@18/], ['babel.js', /babel\.min\.js/], ['tailwind.js', /cdn\.tailwindcss/]])
        if (re.test(u)) return route.fulfill({ body: fs.readFileSync(path.join(LIBS, f)), contentType: 'application/javascript' });
      route.continue();
    });
    await ctx.addInitScript(s => {
      localStorage.setItem('cf_room', 'sun-room'); localStorage.setItem('cf_user_name', 'Тест');
      localStorage.setItem('cf_scene_mode', 'creative');
      for (const k in s) localStorage.setItem(k, JSON.stringify(s[k]));
      window.print = () => { const a = document.getElementById('print-area'); window.__printHTML = a ? a.innerText : ''; };
    }, seed);
    const page = await ctx.newPage();
    const errs = [];
    page.on('pageerror', e => errs.push(String(e).slice(0, 200)));
    await page.goto(`http://127.0.0.1:${PORT}/index.html`);
    await page.waitForFunction(() => window.__CF_APP_OK, { timeout: 180000 });
    await page.waitForTimeout(1200);
    return { page, errs };
  };
  // Только ВИДИМЫЕ: соседние экраны прячутся классом, а не убираются
  // из разметки, и раскладка сцены лежит там же, пока открыт объект.
  const rowsOf = (pg) => pg.evaluate(() => [...document.querySelectorAll('[data-cf="sun-day"]')].filter(d => d.offsetParent).map(d => ({
    rows: [...d.querySelectorAll('[data-cf="sun-row"]')].map(r => r.innerText.replace(/\s+/g, ' ').trim()),
    note: (d.querySelector('p') || {}).innerText || '',
    strip: d.firstElementChild.children.length, w: Math.round(d.getBoundingClientRect().width)
  })));

  // ---- СЧЁТ
  const { page: p, errs } = await mk(1194, 834);
  const calc = await p.evaluate(() => {
    const show = (lat, lon, day) => {
      const t = sunTimes(lat, lon, day), rows = sunDayRows(t);
      return { rows: rows.map(r => r.event ? `${r.event} ${hhmm(r.at)}` : `${SUN_BANDS[r.band].name} ${sunRowTime(r)}`),
               order: rows.flatMap(r => r.event ? [+r.at] : [r.from ? +r.from : null, r.to ? +r.to : null]).filter(x => x != null),
               rise: hhmm(t.sun.rise), set: hhmm(t.sun.set) };
    };
    return { msk: show(55.7558, 37.6173, '2026-10-01'), white: show(59.94, 30.31, '2026-06-21'),
             pday: show(68.97, 33.08, '2026-06-21'), pnight: show(68.97, 33.08, '2026-12-21') };
  });
  const mono = (a) => a.every((x, i) => !i || x >= a[i - 1]);
  const m = calc.msk;
  ok('обычный день: 13 строк от ночи до ночи', m.rows.length === 13 && /^Ночь до/.test(m.rows[0]) && /^Ночь с/.test(m.rows[12]), m.rows.join(' | '));
  ok('обычный день: порядок сумерки → восход → золотой час → день → закат → сумерки',
     /^Астрономические/.test(m.rows[1]) && /^Навигационные/.test(m.rows[2]) && /^Гражданские/.test(m.rows[3]) &&
     /^Восход/.test(m.rows[4]) && /^Золотой час/.test(m.rows[5]) && /^День/.test(m.rows[6]) && /^Золотой час/.test(m.rows[7]) &&
     /^Закат/.test(m.rows[8]) && /^Гражданские/.test(m.rows[9]) && /^Навигационные/.test(m.rows[10]) && /^Астрономические/.test(m.rows[11]));
  ok('обычный день: время идёт только вперёд', mono(m.order));
  ok('восход и закат совпадают с прежним счётом', m.rows[4] === `Восход ${m.rise}` && m.rows[8] === `Закат ${m.set}`, `${m.rows[4]} / ${m.rows[8]}`);
  ok('белые ночи: ночи и астрономических сумерек нет', !calc.white.rows.some(r => /^Ночь|^Астроном/.test(r)) && /^Навигационные сумерки до/.test(calc.white.rows[0]) && mono(calc.white.order), calc.white.rows.join(' | '));
  ok('полярный день: солнце не садится', !calc.pday.rows.some(r => /Восход|Закат|сумерки/.test(r)), calc.pday.rows.join(' | '));
  ok('полярная ночь: солнце не встаёт, днём гражданские сумерки', !calc.pnight.rows.some(r => /Восход|День|Золотой/.test(r)) && calc.pnight.rows.some(r => /Гражданские/.test(r)), calc.pnight.rows.join(' | '));

  // ---- СЦЕНЫ: панель «Объект и солнце»
  await p.evaluate(async () => {
    document.querySelector('button[title="Объект и солнце"]').click();
    await new Promise(r => setTimeout(r, 500));
  });
  const sc = await rowsOf(p);
  const scText = await p.evaluate(() => document.body.innerText);
  ok('сцена: раскладка в панели, 13 строк и полоса суток', sc.length === 1 && sc[0].rows.length === 13 && sc[0].strip >= 11, JSON.stringify(sc.map(x => x.rows.length + '/' + x.strip)));
  ok('сцена: названия и время не обрезаны', await p.evaluate(() => [...document.querySelectorAll('[data-cf="sun-row"]')].every(r => r.scrollWidth <= r.clientWidth + 1)));
  ok('подписи про часы устройства нет', !/часам этого устройства|интернет не нужен/.test(scText));
  ok('без ошибок на планшете', errs.length === 0, errs.join(' | '));

  // ---- ОБЪЕКТЫ
  await p.evaluate(async () => {
    const b = [...document.querySelectorAll('header button')].find(x => /Объект/i.test((x.textContent || '') + (x.title || '')));
    b.click(); await new Promise(r => setTimeout(r, 900));
  });
  const lo = await rowsOf(p);
  const loText = await p.evaluate(() => document.body.innerText);
  ok('объект: раскладка на карточке «Солнце»', lo.length === 1 && lo[0].rows.length === 13, JSON.stringify(lo.map(x => x.rows.length)));
  ok('объект: день смены в заголовке, без «Дуга — на день смены» и «интернет не нужен»',
     /Солнце · 01\.10\.2026/.test(loText) && !/Дуга — на день смены|интернет не нужен/.test(loText));

  // ---- ОТЧЁТ ПО ОБЪЕКТУ: та же раскладка строкой
  await p.evaluate(async () => {
    window.__printHTML = '';
    document.querySelector('button[title="Отчёт, удалить объект"]').click();
    await new Promise(r => setTimeout(r, 300));
    [...document.querySelectorAll('button')].find(x => /Экспорт объекта в PDF/.test(x.textContent || '')).click();
  });
  await p.waitForFunction(() => window.__printHTML !== '', { timeout: 20000 }).catch(() => {});
  const pr = await p.evaluate(() => window.__printHTML || '');
  ok('отчёт: сумерки, восход, день и закат', /01\.10\.2026: ночь до .*астрономические сумерки .*восход \d\d:\d\d.*день .*закат \d\d:\d\d.*ночь с/.test(pr),
     (pr.match(/Солнце:[^\n]*/) || [''])[0].slice(0, 200));

  // ---- ТЕЛЕФОН: шторка «Объект» у сцены
  const { page: q, errs: e2 } = await mk(390, 844);
  await q.evaluate(async () => {
    [...document.querySelectorAll('button')].find(b => /ДВОР/.test(b.textContent)).click();
    await new Promise(r => setTimeout(r, 800));
    [...document.querySelectorAll('button.cf-tile')].find(b => /Горской|Объект/.test(b.textContent)).click();
    await new Promise(r => setTimeout(r, 800));
  });
  const ph = await rowsOf(q);
  ok('телефон: раскладка в шторке, 13 строк, влезает в ширину', ph.length === 1 && ph[0].rows.length === 13 && ph[0].w <= 390,
     JSON.stringify(ph.map(x => x.rows.length + ' / ' + x.w)));
  ok('телефон: строки не обрезаны', await q.evaluate(() => [...document.querySelectorAll('[data-cf="sun-row"]')].every(r => r.scrollWidth <= r.clientWidth + 1)));
  ok('без ошибок на телефоне', e2.length === 0, e2.join(' | '));

  await browser.close(); server.kill();
  console.log(bad ? `\n${bad} FAIL` : '\nвсё ок');
  process.exit(bad ? 1 : 0);
})().catch(e => { console.error(e); server.kill(); process.exit(1); });
