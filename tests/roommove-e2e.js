// Переезд проекта в новую закрытую комнату — и хвост чата.
//
// Зачем переезд: код комнаты — единственный замок, а у старых проектов
// он слабый («cineflow-room-3» записан в самом коде приложения, а код
// лежит в открытом репозитории). Переезд копирует весь проект в комнату
// с длинным случайным кодом, сверяет копию и ставит в старой метку
// «переехал»; старая копия стирается отдельным шагом.
//
// Что гоняем (облако ПОДДЕЛЬНОЕ, с комнатами и памятью между
// перезагрузками — настоящий проект трогать нельзя):
//   чат грузится хвостом в 300 сообщений и говорит об этом →
//   «Доступ» → «Перевезти» → окно с ходом → новая комната: каждая
//   коллекция скопирована ровно, код длинный, ссылка с ним →
//   в старой метка «переехал», старая не тронута → «Перейти» → приложение
//   в новой комнате, проект на месте, полоски нет → «Стереть старую» →
//   старая пуста, метка осталась → открыть старый код: полоска
//   «проект переехал» → без связи переезд не начинается и ничего не пишет.
//
// Запуск:  node tests/roommove-e2e.js
const fs = require('fs'), os = require('os'), path = require('path');
const { execSync, spawn } = require('child_process');
const ROOT = path.resolve(__dirname, '..');
const LIBS = process.env.CF_LIBS || path.join(os.tmpdir(), 'cineflow-libs');
const PORT = process.env.CF_PORT || '8138';
const OLD = 'cineflow-room-3';
let playwright;
try { playwright = require('playwright'); }
catch (e) { playwright = require(execSync('npm root -g').toString().trim() + '/playwright'); }
const { FAKE_CLOUD } = require('./fake-cloud.js');
const LIB_URLS = {
  'react.js': 'https://unpkg.com/react@18.3.1/umd/react.production.min.js',
  'react-dom.js': 'https://unpkg.com/react-dom@18.3.1/umd/react-dom.production.min.js',
  'babel.js': 'https://unpkg.com/@babel/standalone@7.29.9/babel.min.js',
  'tailwind.js': 'https://cdn.tailwindcss.com/3.4.17'
};
fs.mkdirSync(LIBS, { recursive: true });
for (const [f, u] of Object.entries(LIB_URLS)) {
  const p = path.join(LIBS, f);
  if (!fs.existsSync(p) || fs.statSync(p).size < 1000) execSync(`curl -sSL -o "${p}" "${u}"`);
}
const server = spawn('python3', ['-m', 'http.server', PORT, '--bind', '127.0.0.1'], { cwd: ROOT, stdio: 'ignore' });
let bad = 0;
const ok = (n, c, d) => { console.log((c ? '  ok  ' : '  FAIL') + ' ' + n + (d ? ' — ' + d : '')); if (!c) bad++; };

// Комната с настоящим составом: сцены, фото, рисунок, ключи, 350 сообщений.
const seed = () => {
  const s = { scenes: {}, references: {}, messages: {}, canvas: {}, settings: {}, boardEls: {}, boards: {}, docs: {} };
  for (let i = 1; i <= 3; i++) s.scenes['sc-' + i] = { id: 'sc-' + i, number: String(i), title: 'СЦЕНА ПЕРЕЕЗДА ' + i, content: '', gear: {}, lightGear: {} };
  for (let i = 1; i <= 25; i++) s.references['ref-' + i] = { id: 'ref-' + i, url: 'data:image/jpeg;base64,' + 'A'.repeat(4000), tags: ['свет'] };
  const t0 = 1750000000000;
  for (let i = 1; i <= 350; i++) s.messages['msg-' + i] = { id: 'msg-' + i, text: 'сообщение ' + i, senderId: 'u-x', senderName: 'Оля', senderRole: 'Режиссер', timestamp: t0 + i * 1000 };
  s.canvas['ink-board-main'] = { strokes: '[]' };
  s.settings.keys = { gemini: 'ключ', savedAt: 1 };
  s.settings.project = { title: 'Северный свет', savedAt: 1 };
  s.boardEls['board-main~e1'] = { b: 'board-main', e: '{}' };
  s.boards['board-main'] = { id: 'board-main', title: 'Основная', order: 0 };
  s.docs['doc-1'] = { id: 'doc-1', title: 'Гайд', content: 'текст' };
  return s;
};

(async () => {
  await new Promise(r => setTimeout(r, 1200));
  const browser = await playwright.chromium.launch({ executablePath: process.env.CF_CHROME || '/opt/pw-browsers/chromium', args: ['--no-sandbox'] });
  const mk = async (offline) => {
    const ctx = await browser.newContext({ viewport: { width: 1280, height: 860 }, serviceWorkers: 'block' });
    await ctx.route('**/*', route => {
      const u = route.request().url();
      if (/firestore|firebase|googleapis|gstatic|nominatim/.test(u)) return route.abort();
      for (const [f, re] of [['react.js', /react@18[.0-9]*\/umd\/react\.production/], ['react-dom.js', /react-dom@18/],
                             ['babel.js', /babel\.min\.js/], ['tailwind.js', /cdn\.tailwindcss/]])
        if (re.test(u)) return route.fulfill({ body: fs.readFileSync(path.join(LIBS, f)), contentType: 'application/javascript' });
      route.continue();
    });
    await ctx.addInitScript(([old]) => {
      sessionStorage.setItem('__cfPersist', '1');
      if (!localStorage.getItem('cf_room')) localStorage.setItem('cf_room', old);
      localStorage.setItem('cf_user_name', 'Тест');
      localStorage.setItem('cf_user_role', 'Оператор');
    }, [OLD]);
    await ctx.addInitScript(FAKE_CLOUD, seed());
    if (offline) await ctx.addInitScript(() => { window.__cfCacheOnly = new Proxy({}, { get: () => true, set: () => true }); });
    const page = await ctx.newPage();
    const errs = [];
    page.on('pageerror', e => errs.push(String(e).slice(0, 200)));
    return { ctx, page, errs };
  };
  const boot = async (page) => {
    await page.waitForFunction(() => window.__CF_APP_OK, { timeout: 180000 });
    await page.waitForTimeout(1200);
  };
  const click = async (page, find, name) => {
    const pt = await page.evaluate((src) => {
      const el = (new Function('return ' + src))()();
      if (!el) return null;
      el.scrollIntoView({ block: 'center' });
      const r = el.getBoundingClientRect();
      const x = r.left + r.width / 2, y = r.top + r.height / 2, hit = document.elementFromPoint(x, y);
      return { x, y, hit: !!hit && (hit === el || el.contains(hit)) };
    }, find.toString());
    ok(name + ': нажатие попадает', !!pt && pt.hit, pt ? '' : 'не найдено');
    if (pt) await page.mouse.click(pt.x, pt.y);
    await page.waitForTimeout(500);
  };
  const openShare = async (page) => {
    await click(page, () => document.querySelector('button[title="Проект, доступ, агент КПП"]'), '«···»');
    await click(page, () => [...document.querySelectorAll('.cf-menu button')].find(b => /Доступ/.test(b.textContent)), '«Доступ»');
  };
  const store = (page) => page.evaluate(() => window.__cfStore);
  const count = (st, key) => Object.keys(st[key] || {}).length;

  {
    const { ctx, page, errs } = await mk(false);
    await page.goto(`http://127.0.0.1:${PORT}/index.html`);
    await boot(page);

    // Хвост чата.
    await click(page, () => document.querySelector('button[title="Чат группы"]'), 'чат');
    const chat = await page.evaluate(() => ({
      note: /Показаны последние 300/.test(document.body.innerText),
      first: document.body.innerText.includes('сообщение 51\n') || /сообщение 51(?!\d)/.test(document.body.innerText),
      early: /сообщение 50(?!\d)/.test(document.body.innerText),
      last: /сообщение 350(?!\d)/.test(document.body.innerText)
    }));
    ok('чат: загружен хвост — последнее есть, старше трёхсот нет', chat.last && chat.first && !chat.early, JSON.stringify(chat));
    ok('чат: сказано, что показаны последние 300', chat.note);
    await click(page, () => document.querySelector('button[title="Чат группы"]'), 'чат закрыть');

    const before = await store(page);
    await openShare(page);
    await click(page, () => document.querySelector('[data-cf="room-move"]'), '«Перевезти проект»');
    await click(page, () => document.querySelector('[data-cf="confirm-ok"]'), 'подтверждение');
    const done = await page.waitForSelector('[data-cf="room-move-go"]', { timeout: 30000 }).then(() => true).catch(() => false);
    const status = await page.evaluate(() => (document.querySelector('[data-cf="room-move-status"]') || {}).textContent || '');
    ok('переезд закончился и копия сверена', done, status);
    const st = await store(page);
    const newKeys = Object.keys(st).filter(k => k.includes('|'));
    const newRoom = newKeys.length ? newKeys[0].split('|')[0] : '';
    ok('код новой комнаты длинный и случайный', /^room-[a-z0-9]{16}$/.test(newRoom), newRoom);
    const COLLS = ['scenes', 'references', 'messages', 'canvas', 'boardEls', 'boards', 'docs', 'settings'];
    const same = COLLS.filter(c => count(st, newRoom + '|' + c) !== count(before, c) - (c === 'settings' && before.settings.moved ? 1 : 0));
    ok('каждая коллекция скопирована ровно (и все 350 сообщений, не только хвост)', same.length === 0 && count(st, newRoom + '|messages') === 350,
       same.map(c => `${c}: ${count(st, newRoom + '|' + c)}/${count(before, c)}`).join(', ') || 'сообщений ' + count(st, newRoom + '|messages'));
    ok('фото скопировано целиком', (st[newRoom + '|references'] || {})['ref-7'] && st[newRoom + '|references']['ref-7'].url === before.references['ref-7'].url);
    ok('в старой комнате метка «переехал», данные не тронуты',
       !!(st.settings || {}).moved && count(st, 'scenes') === 3 && count(st, 'messages') === 350);
    const link = await page.evaluate(() => (document.querySelector('[data-cf="room-move-link"]') || {}).textContent || '');
    ok('новая ссылка несёт новый код', link.includes('?room=' + newRoom), link);

    // Переход.
    await click(page, () => document.querySelector('[data-cf="room-move-go"]'), '«Перейти в новую комнату»');
    await page.waitForLoadState('load');
    await boot(page);
    const after = await page.evaluate(() => ({
      room: localStorage.getItem('cf_room'), prev: localStorage.getItem('cf_prev_room'),
      banner: !!document.querySelector('[data-cf="room-moved"]'),
      scene: /СЦЕНА ПЕРЕЕЗДА 2|ПЕРЕЕЗДА 2/.test(document.body.innerText)
    }));
    ok('приложение в новой комнате, старая запомнена', after.room === newRoom && after.prev === OLD, JSON.stringify(after));
    ok('проект на месте, полоски «переехал» нет', after.scene && !after.banner, JSON.stringify(after));

    // Стереть старую.
    await openShare(page);
    await click(page, () => document.querySelector('[data-cf="room-wipe"]'), '«Стереть старую комнату»');
    await click(page, () => document.querySelector('[data-cf="confirm-ok"]'), 'подтверждение стирания');
    await page.waitForFunction(() => !localStorage.getItem('cf_prev_room'), { timeout: 20000 }).catch(() => {});
    const st2 = await store(page);
    const leftOld = ['scenes', 'references', 'messages', 'canvas', 'boardEls', 'boards', 'docs'].reduce((a, c) => a + count(st2, OLD + '|' + c) + count(st2, c), 0);
    // После перезагрузки «первой» комнатой подделки осталась старая: её
    // коллекции лежат под своими именами, новая — под «код|».
    const oldSettings = Object.keys(st2.settings || {});
    ok('старая комната стёрта, осталась только метка «переехал»', leftOld === 0 && oldSettings.length === 1 && oldSettings[0] === 'moved',
       `записей ${leftOld}, settings: ${oldSettings.join(',')}`);
    ok('новая комната цела', count(st2, newRoom + '|scenes') === 3 && count(st2, newRoom + '|messages') === 350);

    // Кто остался на старом коде — видит полоску.
    await page.evaluate((old) => { localStorage.setItem('cf_room', old); }, OLD);
    await page.goto(`http://127.0.0.1:${PORT}/index.html`);
    await boot(page);
    const ban = await page.evaluate(() => {
      const b = document.querySelector('[data-cf="room-moved"]');
      return b ? b.textContent : '';
    });
    await page.waitForTimeout(1500);
    const st3 = await store(page);
    const refilled = ['scenes', 'references', 'docs', 'boards'].reduce((a, c) => a + count(st3, c), 0);
    ok('устройство со старым кодом НЕ засеяло стёртую комнату своей копией', refilled === 0, `записей ${refilled}`);
    ok('на старом коде видна полоска «проект переехал», без нового кода', /переехал/.test(ban) && !/room-/.test(ban), ban);
    if (errs.length) ok('без ошибок в консоли', false, errs.join(' | '));
    await ctx.close();
  }

  // Без связи — переезд не начинается и ничего не пишет.
  {
    const { ctx, page, errs } = await mk(true);
    await page.goto(`http://127.0.0.1:${PORT}/index.html`);
    await boot(page);
    const w0 = await page.evaluate(() => window.__cfWrites.length);
    await openShare(page);
    await click(page, () => document.querySelector('[data-cf="room-move"]'), '«Перевезти» без связи');
    await click(page, () => document.querySelector('[data-cf="confirm-ok"]'), 'подтверждение без связи');
    await page.waitForTimeout(1500);
    const s = await page.evaluate(() => (document.querySelector('[data-cf="room-move-status"]') || {}).textContent || '');
    const writes = await page.evaluate((n) => window.__cfWrites.slice(n).filter(w => /\|/.test(w.coll) || w.id === 'moved').length, w0);
    ok('без связи: честный отказ, старая не тронута', /связь|не ответило|не отдало/.test(s) && /не тронута/.test(s), s);
    ok('без связи: ни одной записи в новую комнату и метки нет', writes === 0, String(writes));
    if (errs.length) ok('без ошибок в консоли (без связи)', false, errs.join(' | '));
    await ctx.close();
  }

  console.log(bad ? `\nПЛОХО: ${bad}` : '\nВсё сошлось');
  await browser.close(); server.kill(); process.exit(bad ? 1 : 0);
})().catch(e => { console.error(e); server.kill(); process.exit(1); });
