// РЕЖИМЫ ЭКРАНА СЦЕНЫ НА ТЕЛЕФОНЕ. Жалоба: «отвалились режимы».
// По записи экрана: режим выбирали в «Ещё», стоя на СПИСКЕ сцен. Кружок
// переезжал, шторка закрывалась, а на экране оставался тот же список —
// режим меняет вид ОТКРЫТОЙ сцены, а открыта она не была. Теперь выбор
// режима со списка открывает сцену в этом режиме: выбранную, если она
// в показанной смене, иначе первую сцену смены. Всё — нажатием.
// Запуск:  node tests/scenemode-e2e.js
const path = require('path'), fs = require('fs'), os = require('os');
const { execSync, spawn } = require('child_process');
const ROOT = path.resolve(__dirname, '..');
const LIBS = process.env.CF_LIBS || path.join(os.tmpdir(), 'cineflow-libs');
const PORT = process.env.CF_PORT || '8166';
let playwright;
try { playwright = require('playwright'); }
catch (e) { playwright = require(execSync('npm root -g').toString().trim() + '/playwright'); }
const { FAKE_CLOUD } = require('./fake-cloud.js');
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

const day = (n) => { const d = new Date(); d.setDate(d.getDate() + n); return d.toISOString().slice(0, 10); };
const seed = {
  scenes: {
    s1: { id: 's1', number: '1', title: 'ИНТ. КАБИНЕТ — ДЕНЬ', content: 'кабинет', date: day(-5) },
    s6: { id: 's6', number: '6', title: 'НАТ. АЭРОДРОМ. РУЛЕЖКА — ДЕНЬ', content: 'рулежка', date: day(3) },
    s7: { id: 's7', number: '7', title: 'НАТ. АЭРОДРОМ. НЕБО — ДЕНЬ', content: 'небо', date: day(3) }
  },
  storyboard: { f1: { id: 'f1', sceneId: 's6', frameNum: '6.1', description: 'общий' } }
};

(async () => {
  await new Promise(r => setTimeout(r, 1000));
  const browser = await playwright.chromium.launch({ executablePath: '/opt/pw-browsers/chromium', args: ['--no-sandbox'] });
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true, serviceWorkers: 'block' });
  await ctx.route('**/*', route => {
    const u = route.request().url();
    if (/firestore|firebase|googleapis|gstatic|nominatim/.test(u)) return route.abort();
    for (const [f, re] of [['react.js', /react@18[.0-9]*\/umd\/react\.production/], ['react-dom.js', /react-dom@18/], ['babel.js', /babel\.min\.js/], ['tailwind.js', /cdn\.tailwindcss/]])
      if (re.test(u)) return route.fulfill({ body: fs.readFileSync(path.join(LIBS, f)), contentType: 'application/javascript' });
    route.continue();
  });
  await ctx.addInitScript(FAKE_CLOUD, seed);
  await ctx.addInitScript(() => { localStorage.setItem('cf_room', 'scenemode-room-1234'); localStorage.setItem('cf_user_name', 'Тест'); });
  const page = await ctx.newPage();
  const errs = [];
  page.on('pageerror', e => errs.push(String(e).slice(0, 200)));
  await page.goto(`http://127.0.0.1:${PORT}/index.html`);
  await page.waitForFunction(() => window.__CF_APP_OK && document.querySelector('header'), null, { timeout: 120000 });
  await page.waitForTimeout(2000);

  // Нажатие по середине элемента, и только если попадаем именно в него.
  const tap = async (sel) => {
    const pt = await page.evaluate((s) => {
      const el = document.querySelector(s); if (!el) return null;
      const r = el.getBoundingClientRect(), x = r.left + r.width / 2, y = r.top + r.height / 2;
      const t = document.elementFromPoint(x, y);
      return t && el.contains(t) ? [x, y] : 'mimo';
    }, sel);
    if (!Array.isArray(pt)) return pt || 'нет';
    await page.touchscreen.tap(pt[0], pt[1]); await page.waitForTimeout(700);
    return 'ok';
  };
  const screen = () => page.evaluate(() => {
    const m = document.querySelector('main');
    return { mode: localStorage.getItem('cf_scene_mode'), text: (m ? m.innerText : document.body.innerText).replace(/\s+/g, ' ').slice(0, 120),
             back: [...document.querySelectorAll('header button')].some(b => /‹ Сцены/.test(b.textContent)) };
  });

  // 1. Со списка: «Ещё» → «Съёмка».
  ok('«Ещё» открывается', (await tap('.cf-tabbar button:last-child')) === 'ok');
  const hint = await page.evaluate(() => { const e = document.querySelector('[data-cf="mode-opens"]'); return e ? e.textContent : ''; });
  ok('в «Ещё» сказано, какую сцену откроет режим (первую ближайшей смены)', /#6/.test(hint), hint);
  ok('строка «Съёмка» нажимается', (await tap('[data-cf="more-mode-shoot"]')) === 'ok');
  let s = await screen();
  ok('выбор режима со списка ОТКРЫЛ сцену', s.back, s.text.slice(0, 60));
  ok('и открыл её в «Съёмке»', s.mode === 'shoot' && /Съёмка/.test(s.text) && /СЦ 6/.test(s.text), s.text.slice(0, 60));

  // 2. Внутри сцены: шапка переключает режимы.
  for (const [lbl, re] of [['Презент', /СЦЕНА 6/], ['Творч', /Текст сцены/], ['Съёмка', /снято/]]) {
    const hit = await page.evaluate((l) => {
      const b = [...document.querySelectorAll('header .cf-seg button')].find(x => x.textContent.trim() === l);
      if (!b) return null; b.setAttribute('data-t', l); return true;
    }, lbl);
    const r = hit ? await tap(`header .cf-seg button[data-t="${lbl}"]`) : 'нет';
    s = await screen();
    ok(`в шапке «${lbl}» нажимается и меняет экран`, r === 'ok' && re.test(s.text), r + ' · ' + s.text.slice(0, 50));
  }

  // 3. Изнутри сцены «Ещё» режим меняет, а сцену не подменяет.
  await tap('header button[title="Ещё"]');
  await tap('[data-cf="more-mode-present"]');
  s = await screen();
  ok('«Ещё» внутри сцены: та же сцена в новом режиме', s.mode === 'present' && /СЦЕНА 6/.test(s.text), s.text.slice(0, 50));

  // 4. Назад к списку, выбрали другую сцену, вернулись — «Ещё» откроет ЕЁ.
  await page.evaluate(() => [...document.querySelectorAll('header button')].find(b => /‹ Сцены/.test(b.textContent)).setAttribute('data-t', 'back'));
  await tap('header button[data-t="back"]');
  await page.evaluate(() => { const b = [...document.querySelectorAll('.cf-pill, button')].find(x => x.textContent.trim() === 'Все'); if (b) b.setAttribute('data-t', 'all'); });
  await tap('[data-t="all"]');
  await page.evaluate(() => { const e = [...document.querySelectorAll('span')].find(x => x.children.length === 0 && /^КАБИНЕТ/.test(x.textContent.trim())); if (e) e.setAttribute('data-t', 'cab'); });
  const cab = await tap('[data-t="cab"]'); ok('сцена 1 видна в списке «Все» и нажимается', cab === 'ok', cab + ' · ' + (await screen()).text.slice(0, 80));
  await page.evaluate(() => [...document.querySelectorAll('header button')].find(b => /‹ Сцены/.test(b.textContent)).setAttribute('data-t', 'back'));
  await tap('header button[data-t="back"]');
  await tap('.cf-tabbar button:last-child');
  await tap('[data-cf="more-mode-creative"]');
  s = await screen();
  ok('на списке «Все» режим открывает выбранную сцену, а не первую смены', s.back && s.mode === 'creative' && /СЦ 1/.test(s.text), s.text.slice(0, 50));

  ok('без ошибок на странице', errs.length === 0, errs.slice(0, 3).join(' | '));
  await browser.close(); server.kill();
  console.log(bad ? `\n${bad} провал(ов)` : '\nвсё прошло');
  process.exit(bad ? 1 : 0);
})();
