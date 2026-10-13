// ВХОД В КОМНАТУ ПО КОДУ («Доступ» → «Войти»).
// Жалоба: «вбил код, нажал Войти — ничего не происходит». Тихих путей
// было три: iPhone сам ставит заглавную первую букву (а «Room-…» — это
// другая, новая и пустая комната), код совпал с нынешним (выход без
// слова), в адресе стоит ?room= (он перебивает введённый код после
// перезагрузки). Проверяется в браузере с поддельным облаком: в нём
// «существуют» только комнаты из списка ниже, остальные пустые.
// Запуск:  node tests/room-e2e.js
const path = require('path'), fs = require('fs'), os = require('os');
const { execSync, spawn } = require('child_process');
const ROOT = path.resolve(__dirname, '..');
const LIBS = process.env.CF_LIBS || path.join(os.tmpdir(), 'cineflow-libs');
const PORT = process.env.CF_PORT || '8164';
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

// Поверх общего поддельного облака: какие комнаты в нём НЕ пустые.
// Подделка одна на все проверки и комнат не различает, поэтому здесь
// перехватывается только вопрос «есть ли что-нибудь в комнате X».
const ROOMS = (known) => {
  const fb = window.firebase, orig = fb.firestore;
  fb.firestore = () => {
    const db = orig();
    if (db.__wrapped) return db;
    const coll = db.collection;
    db.collection = (name) => {
      const c = coll(name);
      if (name !== 'artifacts') return c;
      return { ...c, doc: (code) => {
        const d = c.doc(code);
        return { ...d, collection: (n1) => { const pub = d.collection(n1); return { ...pub, doc: (n2) => {
          const data = pub.doc(n2);
          return { ...data, collection: (cn) => ({ ...data.collection(cn),
            limit: () => ({ get: () => { (window.__cfAsked = window.__cfAsked || []).push(code + '/' + cn);
              const full = known.includes(code);
              return Promise.resolve({ empty: !full, size: full ? 1 : 0, forEach: () => {}, docs: [] }); } }) }) };
        } }; } };
      } };
    };
    db.__wrapped = true;
    return db;
  };
};

(async () => {
  await new Promise(r => setTimeout(r, 1000));
  const browser = await playwright.chromium.launch({ executablePath: '/opt/pw-browsers/chromium', args: ['--no-sandbox'] });
  const ctx = await browser.newContext({ viewport: { width: 1194, height: 834 }, hasTouch: true, serviceWorkers: 'block' });
  await ctx.route('**/*', route => {
    const u = route.request().url();
    if (/firestore|firebase|googleapis|gstatic|nominatim/.test(u)) return route.abort();
    for (const [f, re] of [['react.js', /react@18[.0-9]*\/umd\/react\.production/], ['react-dom.js', /react-dom@18/], ['babel.js', /babel\.min\.js/], ['tailwind.js', /cdn\.tailwindcss/]])
      if (re.test(u)) return route.fulfill({ body: fs.readFileSync(path.join(LIBS, f)), contentType: 'application/javascript' });
    route.continue();
  });
  await ctx.addInitScript(FAKE_CLOUD, { scenes: { s1: { id: 's1', number: '1', title: 'СЦЕНА', content: '' } } });
  await ctx.addInitScript(ROOMS, ['room-old', 'room-abc123']);
  await ctx.addInitScript(() => {
    if (!sessionStorage.getItem('cf_room_test_init')) {
      sessionStorage.setItem('cf_room_test_init', '1');
      localStorage.setItem('cf_room', 'room-new0000'); localStorage.setItem('cf_user_name', 'Тест');
    }
  });
  const page = await ctx.newPage();
  const errs = [];
  page.on('pageerror', e => errs.push(String(e).slice(0, 200)));
  const load = async (q = '') => {
    await page.goto(`http://127.0.0.1:${PORT}/index.html${q}`);
    await page.waitForFunction(() => window.__CF_APP_OK && document.querySelector('header'), null, { timeout: 120000 });
    await page.waitForTimeout(800);
  };
  const openShare = () => page.evaluate(async () => {
    document.querySelector('[title="Проект, доступ, агент КПП"]').click();
    await new Promise(r => setTimeout(r, 200));
    const b = [...document.querySelectorAll('button')].find(x => x.textContent.trim() === 'Доступ');
    b.click();
    await new Promise(r => setTimeout(r, 300));
    return !!document.querySelector('[data-cf="room-input"]');
  });
  const type = (text) => page.evaluate((t) => {
    const el = document.querySelector('[data-cf="room-input"]');
    const set = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
    el.focus(); set.call(el, t); el.dispatchEvent(new Event('input', { bubbles: true }));
  }, text);
  const tapJoin = async () => {
    const r = await page.evaluate(() => { const b = document.querySelector('[data-cf="room-join"]').getBoundingClientRect(); return [b.left + b.width / 2, b.top + b.height / 2]; });
    await page.mouse.click(r[0], r[1]);
  };
  const room = () => page.evaluate(() => localStorage.getItem('cf_room'));
  const toast = () => page.evaluate(() => { const t = document.querySelector('[data-cf="toast"]'); return t ? t.textContent : ''; });

  await load();
  ok('открылось в новой пустой комнате (как после переустановки)', (await room()) === 'room-new0000');
  ok('окно «Доступ» с полем кода', await openShare());

  const attrs = await page.evaluate(() => { const el = document.querySelector('[data-cf="room-input"]');
    return { cap: el.getAttribute('autocapitalize'), cor: el.getAttribute('autocorrect'), spell: el.getAttribute('spellcheck') }; });
  ok('iPhone не ставит заглавную и не правит код автокоррекцией', attrs.cap === 'off' && attrs.cor === 'off' && attrs.spell === 'false', JSON.stringify(attrs));

  // Тот же код — не молчим.
  await type('room-new0000'); await tapJoin(); await page.waitForTimeout(300);
  ok('тот же код — полоска «Вы уже в этой комнате»', /уже в этой комнате/.test(await toast()), await toast());

  // Заглавная буква от iPhone: комнаты «Room-ABC123» нет, а «room-abc123» есть.
  await type('Room-ABC123');
  await Promise.all([page.waitForNavigation({ timeout: 20000 }).catch(() => null), tapJoin()]);
  await page.waitForFunction(() => window.__CF_APP_OK, null, { timeout: 120000 });
  ok('«Room-ABC123» приводит в существующую «room-abc123»', (await room()) === 'room-abc123', await room());

  // Опечатка: пустая комната — спрашиваем, а не уводим молча.
  await page.waitForTimeout(800);
  await openShare();
  await type('room-abc12'); await tapJoin();
  await page.waitForSelector('[data-cf="confirm-ok"]', { timeout: 15000 }).catch(() => {});
  const q = await page.evaluate(() => { const b = document.querySelector('[data-cf="confirm-ok"]'); return b ? b.closest('[role="dialog"]').textContent : ''; });
  ok('опечатка — окно «В комнате пусто», а не тихий переход', /пусто/.test(q) && /room-abc12/.test(q), q.slice(0, 80));
  ok('пока не подтвердили, комната прежняя', (await room()) === 'room-abc123');
  await Promise.all([page.waitForNavigation({ timeout: 20000 }).catch(() => null), page.click('[data-cf="confirm-ok"]')]);
  await page.waitForFunction(() => window.__CF_APP_OK, null, { timeout: 120000 });
  ok('«Войти всё равно» заводит новую комнату', (await room()) === 'room-abc12', await room());

  // ?room= в адресе (иконку поставили со ссылки-приглашения) не перебивает введённое.
  await load('?room=room-abc12');
  await openShare();
  await type('room-old');
  await page.evaluate(() => document.querySelector('[data-cf="room-input"]').dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true })));
  await page.waitForFunction(() => !location.search.includes('room='), null, { timeout: 20000 }).catch(() => {});
  await page.waitForFunction(() => window.__CF_APP_OK && document.querySelector('header'), null, { timeout: 120000 });
  await page.waitForTimeout(500);
  const url = page.url();
  ok('Enter в поле тоже входит, ?room= из адреса снят', !/room=/.test(url) && (await room()) === 'room-old', url + ' · ' + (await room()));

  ok('без ошибок на странице', errs.length === 0, errs.slice(0, 3).join(' | '));
  await browser.close(); server.kill();
  console.log(bad ? `\n${bad} провал(ов)` : '\nвсё прошло');
  process.exit(bad ? 1 : 0);
})();
