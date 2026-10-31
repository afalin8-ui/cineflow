// Галерея: поиск строкой — несколько слов сужают подборку, теги дописываются
// в строку и вычёркиваются, подсказки по недописанному слову, телефон тоже.
const fs = require('fs'), os = require('os'), path = require('path');
const { execSync, spawn } = require('child_process');
const ROOT = path.resolve(__dirname, '..'), LIBS = path.join(os.tmpdir(), 'cineflow-libs'), PORT = '8151';
let playwright;
try { playwright = require('playwright'); } catch (e) { playwright = require(execSync('npm root -g').toString().trim() + '/playwright'); }
const LIB_URLS = {
  'react.js': 'https://unpkg.com/react@18.3.1/umd/react.production.min.js',
  'react-dom.js': 'https://unpkg.com/react-dom@18.3.1/umd/react-dom.production.min.js',
  'babel.js': 'https://unpkg.com/@babel/standalone@7.29.9/babel.min.js',
  'tailwind.js': 'https://cdn.tailwindcss.com/3.4.17'
};
fs.mkdirSync(LIBS, { recursive: true });
for (const [f, u] of Object.entries(LIB_URLS)) if (!fs.existsSync(path.join(LIBS, f))) execSync(`curl -sSL -o ${path.join(LIBS, f)} ${u}`);
const server = spawn('python3', ['-m', 'http.server', PORT, '--bind', '127.0.0.1'], { cwd: ROOT, stdio: 'ignore' });
let bad = 0;
const ok = (n, c, d) => { console.log((c ? '  ok  ' : '  FAIL') + ' ' + n + (d ? ' — ' + d : '')); if (!c) bad++; };
const PX = 'data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==';
(async () => {
  await new Promise(r => setTimeout(r, 1200));
  const browser = await playwright.chromium.launch({ executablePath: '/opt/pw-browsers/chromium', args: ['--no-sandbox'] });
  const mk = async (w, h) => {
    const ctx = await browser.newContext({ viewport: { width: w, height: h }, isMobile: w < 768, hasTouch: w < 900, serviceWorkers: 'block' });
    await ctx.route('**/*', route => {
      const u = route.request().url();
      if (/firestore|firebase|googleapis|gstatic|nominatim/.test(u)) return route.abort();
      for (const [f, re] of [['react.js', /react@18[.0-9]*\/umd\/react\.production/], ['react-dom.js', /react-dom@18/], ['babel.js', /babel\.min\.js/], ['tailwind.js', /cdn\.tailwindcss/]])
        if (re.test(u)) return route.fulfill({ body: fs.readFileSync(path.join(LIBS, f)), contentType: 'application/javascript' });
      route.continue();
    });
    await ctx.addInitScript((px) => {
      localStorage.setItem('cf_room', 'galsearch-room');
      localStorage.setItem('cf_user_name', 'Тест');
      localStorage.setItem('cf_gal_scope', 'refs');
      const T = [['пыль', 'ночь'], ['пыль', 'день'], ['ночь', 'контровой свет'], ['окно'], ['пыль', 'ночь', 'окно']];
      localStorage.setItem('cf_references', JSON.stringify(T.map((tags, i) => ({ id: 'r' + i, url: px, label: i === 3 ? 'Кухня ночью' : '', file: 'f' + i + '.jpg', tags, folder: '', sceneId: '', locationId: '' }))));
    }, PX);
    const page = await ctx.newPage();
    const errs = [];
    page.on('pageerror', e => errs.push(String(e).slice(0, 200)));
    await page.goto(`http://127.0.0.1:${PORT}/index.html`);
    await page.waitForFunction(() => window.__CF_APP_OK, { timeout: 180000 });
    await page.waitForTimeout(900);
    await page.evaluate(async () => {
      const b = [...document.querySelectorAll('.cf-tabbar button, header button')].find(x => /Галере/i.test((x.textContent || '') + (x.title || '')));
      if (b) b.click();
      await new Promise(r => setTimeout(r, 800));
    });
    return { page, errs };
  };
  const cards = p => p.evaluate(() => document.querySelectorAll('.cf-ref-card').length);
  const hits = (p, sel) => p.evaluate((sel) => { const el = document.querySelector(sel); if (!el) return 'нет'; const r = el.getBoundingClientRect();
    const t = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2); return !!t && (t === el || el.contains(t)); }, sel);
  const type = async (p, v) => { await p.fill('[data-cf="gallery-search"]', v); await p.waitForTimeout(250); };

  // ---- НОУТБУК
  const { page: p, errs } = await mk(1440, 900);
  ok('строка поиска видна над сеткой и попадает под мышь', await hits(p, '[data-cf="gallery-search"]') === true);
  ok('без поиска — все пять', await cards(p) === 5);
  await type(p, 'пыль');
  ok('одно слово — три кадра', await cards(p) === 3);
  await type(p, 'пыль ночь');
  ok('два слова через пробел — нужны оба', await cards(p) === 2);
  await type(p, 'пыль, ночь, окно');
  ok('три через запятую — один', await cards(p) === 1);
  await type(p, 'кухня');
  ok('ищет и по подписи', await cards(p) === 1);
  await type(p, 'кон');
  const hints = await p.$$eval('[data-cf="gallery-search-hints"] button', b => b.map(x => x.textContent));
  ok('подсказка по недописанному слову', hints.length === 1 && /контровой свет/.test(hints[0]), JSON.stringify(hints));
  await p.click('[data-cf="gallery-search-hints"] button');
  await p.waitForTimeout(250);
  const v1 = await p.inputValue('[data-cf="gallery-search"]');
  ok('подсказка дописывает тег целиком', v1 === 'контровой свет, ' && await cards(p) === 1, JSON.stringify(v1));
  await p.click('[data-cf="gallery-search-clear"]'); await p.waitForTimeout(250);
  ok('✕ очищает строку', await p.inputValue('[data-cf="gallery-search"]') === '' && await cards(p) === 5);
  // теги из колонки слева дописываются в строку
  const tagBtn = async (t) => { const h = await p.evaluateHandle((t) => [...document.querySelectorAll('button')].find(b => b.querySelector('.truncate') && b.querySelector('.truncate').textContent === t && b.offsetParent), t); await h.asElement().click(); await p.waitForTimeout(250); };
  await tagBtn('пыль'); await tagBtn('окно');
  const v2 = await p.inputValue('[data-cf="gallery-search"]');
  ok('теги из списка складываются в строку', v2 === 'пыль, окно' && await cards(p) === 1, JSON.stringify(v2));
  await tagBtn('пыль');
  const v3 = await p.inputValue('[data-cf="gallery-search"]');
  ok('повторное нажатие вычёркивает тег', v3 === 'окно' && await cards(p) === 2, JSON.stringify(v3));
  ok('ошибок нет', errs.length === 0, errs.join(' | '));

  // ---- ТЕЛЕФОН
  const { page: q, errs: e2 } = await mk(390, 844);
  ok('телефон: строка поиска есть и нажимается', await hits(q, '[data-cf="gallery-search"]') === true);
  await type(q, 'ночь пыль');
  ok('телефон: два слова сужают', await cards(q) === 2);
  ok('телефон: без горизонтальной прокрутки', await q.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
  ok('телефон: ошибок нет', e2.length === 0, e2.join(' | '));

  await browser.close(); server.kill();
  console.log(bad ? `\n${bad} не сошлось` : '\nВсё сошлось');
  process.exit(bad ? 1 : 0);
})().catch(e => { console.error(e); server.kill(); process.exit(1); });
