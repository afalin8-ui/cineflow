// СВЕЖАЯ УСТАНОВКА В БОЛЬШОЙ КОМНАТЕ НЕ ЗАСЕВАЕТ ЕЁ ЗАГОТОВКОЙ.
// Случилось у пользователя: переустановил иконку, вошёл в свою комнату
// (139 сцен, 797 фото), облако ещё не ответило, библиотека отдала пустую
// копию с устройства — и приложение, приняв её за новую комнату, записало
// поверх сцены 1, гайда 1 и каталога света свои примеры.
// Поддельное облако изображает это `__cfCacheOnly`: пока флаг стоит,
// ответ приходит «из кэша» и пустой, хотя в комнате всё есть.
// Запуск:  node tests/seed-e2e.js
const path = require('path'), fs = require('fs'), os = require('os');
const { execSync, spawn } = require('child_process');
const ROOT = path.resolve(__dirname, '..');
const LIBS = process.env.CF_LIBS || path.join(os.tmpdir(), 'cineflow-libs');
const PORT = process.env.CF_PORT || '8165';
let playwright;
try { playwright = require('playwright'); }
catch (e) { playwright = require(execSync('npm root -g').toString().trim() + '/playwright'); }
const { FAKE_CLOUD } = require('./fake-cloud.js');
const server = spawn('python3', ['-m', 'http.server', PORT, '--bind', '127.0.0.1'], { cwd: ROOT, stdio: 'ignore' });
let bad = 0;
const ok = (n, c, d) => { console.log((c ? '  ok  ' : '  FAIL') + ' ' + n + (d ? ' — ' + d : '')); if (!c) bad++; };

const ROOM = {
  scenes: { 'scene-1': { id: 'scene-1', number: '1', title: 'МОЯ ПЕРВАЯ СЦЕНА', content: 'моя экспликация' },
            's2': { id: 's2', number: '2', title: 'ВТОРАЯ', content: '' } },
  docs: { 'doc-1': { id: 'doc-1', title: 'Мой гайд', content: 'мой текст' } },
  lightGearTypes: { arri600: { name: 'Мой Arri 600' } },
  references: { r1: { id: 'r1', url: '', label: 'кадр', tags: [], folder: '', sceneId: 'scene-1' } }
};
const SLOW = ['scenes', 'docs', 'lightGearTypes', 'gearTypes', 'boards', 'crew', 'stickies', 'locations', 'storyboard', 'references', 'projectFiles', 'lightSchemes'];

(async () => {
  await new Promise(r => setTimeout(r, 1000));
  const browser = await playwright.chromium.launch({ executablePath: '/opt/pw-browsers/chromium', args: ['--no-sandbox'] });
  const mk = async (seed, slow) => {
    const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true, serviceWorkers: 'block' });
    await ctx.route('**/*', route => {
      const u = route.request().url();
      if (/firestore|firebase|googleapis|gstatic|nominatim/.test(u)) return route.abort();
      for (const [f, re] of [['react.js', /react@18\/umd\/react\.production/], ['react-dom.js', /react-dom@18/], ['babel.js', /babel\.min\.js/], ['tailwind.js', /cdn\.tailwindcss/]])
        if (re.test(u)) return route.fulfill({ body: fs.readFileSync(path.join(LIBS, f)), contentType: 'application/javascript' });
      route.continue();
    });
    await ctx.addInitScript(FAKE_CLOUD, seed);
    // Свежая установка: на устройстве только комната и имя, проекта нет.
    await ctx.addInitScript(([s]) => {
      s.forEach(c => { window.__cfCacheOnly[c] = true; });
      localStorage.setItem('cf_room', 'cineflow-room-3'); localStorage.setItem('cf_user_name', 'Тест');
    }, [slow]);
    const page = await ctx.newPage();
    const errs = [];
    page.on('pageerror', e => errs.push(String(e).slice(0, 200)));
    await page.goto(`http://127.0.0.1:${PORT}/index.html`);
    await page.waitForFunction(() => window.__CF_APP_OK && document.querySelector('header'), null, { timeout: 120000 });
    await page.waitForTimeout(2500);
    return { page, errs };
  };
  const writes = (p) => p.evaluate(() => window.__cfWrites.map(w => w.coll + '/' + w.id));

  // ---- 1. Облако медлит, копия на устройстве пуста.
  const { page: p, errs } = await mk(ROOM, SLOW);
  const w1 = await writes(p);
  ok('пока облако не ответило — в комнату НЕ записано ничего', w1.length === 0, w1.join(', '));
  const banner = await p.evaluate(() => { const b = document.querySelector('[data-cf="cloud-loading"]'); return b ? b.textContent : ''; });
  ok('видна полоска «Загружаю проект из облака»', /Загружаю проект/.test(banner), banner.slice(0, 60));

  // Облако ответило.
  await p.evaluate((s) => { window.__cfCacheOnly = {}; s.forEach(c => window.__cfEmit(c)); }, SLOW);
  await p.waitForTimeout(1500);
  const after = await p.evaluate(() => ({
    titles: [...document.querySelectorAll('body *')].some(e => e.children.length === 0 && /МОЯ ПЕРВАЯ СЦЕНА/.test(e.textContent)),
    banner: !!document.querySelector('[data-cf="cloud-loading"]'),
    store: window.__cfStore.scenes['scene-1'].title + ' · ' + window.__cfStore.docs['doc-1'].title + ' · ' + window.__cfStore.lightGearTypes.arri600.name,
    refs: JSON.parse(localStorage.getItem('cf_references') || '[]').length
  }));
  // Коллекции, которых в комнате нет вовсе (техника, доски), облако само
  // назвало пустыми — туда заготовка ложится законно. Чужого — ни строки.
  const w2 = (await writes(p)).filter(w => Object.keys(ROOM).includes(w.split('/')[0]));
  ok('после ответа облака на экране МОИ сцены', after.titles);
  ok('полоска ушла', !after.banner);
  ok('сцена 1, гайд 1 и каталог света в облаке — свои, а не примеры', after.store === 'МОЯ ПЕРВАЯ СЦЕНА · Мой гайд · Мой Arri 600', after.store);
  ok('и после ответа облака в то, что в комнате было, не записано ничего', w2.length === 0, w2.join(', '));
  await p.waitForTimeout(1500);
  const refs = await p.evaluate(() => JSON.parse(localStorage.getItem('cf_references') || '[]').length);
  ok('фото подтянулись после сцен', refs === 1, refs + ' шт.');
  ok('без ошибок на странице', errs.length === 0, errs.slice(0, 3).join(' | '));

  // ---- 2. Новая пустая комната — облако само говорит «пусто», заготовка ложится как раньше.
  const { page: q, errs: e2 } = await mk({}, []);
  await q.waitForTimeout(1000);
  const w3 = await writes(q);
  ok('новая пустая комната засевается заготовкой', w3.includes('scenes/scene-1') && w3.includes('docs/doc-1'), w3.slice(0, 8).join(', '));
  const nb = await q.evaluate(() => !!document.querySelector('[data-cf="cloud-loading"]'));
  ok('в новой комнате полоски загрузки нет', !nb);
  ok('без ошибок в новой комнате', e2.length === 0, e2.slice(0, 3).join(' | '));

  await browser.close(); server.kill();
  console.log(bad ? `\n${bad} провал(ов)` : '\nвсё прошло');
  process.exit(bad ? 1 : 0);
})();
