// Несколько сцен под удаление: режим «Выбрать» в списке сцен.
//
// Гоняем на планшете (1280) и телефоне (390), всё НАСТОЯЩИМ нажатием
// (elementFromPoint обязан попасть в кнопку): «Выбрать» → нажатие по
// строке выделяет, а не открывает → «Удалить 2 сцены» → одно окно
// подтверждения → сцены ушли → «Вернуть» вернул обе с датами →
// на телефоне «Выделить все» берёт ТОЛЬКО показанное фильтром смены,
// сцены другой смены не трогаются → у гостя по ссылке «Выбрать» нет.
//
// Запуск:  node tests/scenesel-e2e.js
const fs = require('fs'), os = require('os'), path = require('path');
const { execSync, spawn } = require('child_process');
const ROOT = path.resolve(__dirname, '..');
const LIBS = process.env.CF_LIBS || path.join(os.tmpdir(), 'cineflow-libs');
const PORT = process.env.CF_PORT || '8164';
let playwright;
try { playwright = require('playwright'); }
catch (e) { playwright = require(execSync('npm root -g').toString().trim() + '/playwright'); }
const LIB_URLS = {
  'react.js': 'https://unpkg.com/react@18/umd/react.production.min.js',
  'react-dom.js': 'https://unpkg.com/react-dom@18/umd/react-dom.production.min.js',
  'babel.js': 'https://cdn.jsdelivr.net/npm/@babel/standalone@7/babel.min.js',
  'tailwind.js': 'https://cdn.tailwindcss.com'
};
fs.mkdirSync(LIBS, { recursive: true });
for (const [f, u] of Object.entries(LIB_URLS)) {
  const q = path.join(LIBS, f);
  if (!fs.existsSync(q) || fs.statSync(q).size < 1000) execSync(`curl -sSL -o "${q}" "${u}"`);
}
const server = spawn('python3', ['-m', 'http.server', PORT, '--bind', '127.0.0.1'], { cwd: ROOT, stdio: 'ignore' });
let bad = 0;
const ok = (n, c, d) => { console.log((c ? '  ok  ' : '  FAIL') + ' ' + n + (d ? ' — ' + d : '')); if (!c) bad++; };

const SCENES = [
  ['s1', '1', 'ИНТ. КУХНЯ — ДЕНЬ', '2026-11-01'],
  ['s2', '2', 'НАТ. ДВОР — ДЕНЬ', '2026-11-01'],
  ['s3', '3', 'ИНТ. ЛИФТ — НОЧЬ', '2026-11-01'],
  ['s4', '4', 'НАТ. МОСТ — ВЕЧЕР', '2026-11-05'],
  ['s5', '5', 'ИНТ. ГАРАЖ — НОЧЬ', '2026-11-05']
].map(([id, number, title, date]) => ({ id, number, title, date, content: '', gear: { cam: 1 }, lightGear: {}, lightSchemeId: null }));

(async () => {
  await new Promise(r => setTimeout(r, 1200));
  const browser = await playwright.chromium.launch({
    executablePath: process.env.CF_CHROME || '/opt/pw-browsers/chromium', args: ['--no-sandbox'] });
  const mk = async (viewport, url = 'index.html') => {
    const ctx = await browser.newContext({ viewport, serviceWorkers: 'block', hasTouch: viewport.width < 500 });
    await ctx.route('**/*', route => {
      const u = route.request().url();
      if (/firestore|firebase|googleapis\.com\/(identitytoolkit|securetoken)|gstatic/.test(u)) return route.abort();
      for (const [f, re] of [['react.js', /react@18[.0-9]*\/umd\/react\.production/], ['react-dom.js', /react-dom@18/],
                             ['babel.js', /babel\.min\.js/], ['tailwind.js', /cdn\.tailwindcss/]])
        if (re.test(u)) return route.fulfill({ body: fs.readFileSync(path.join(LIBS, f)), contentType: 'application/javascript',
                                               headers: { 'Access-Control-Allow-Origin': '*' } });
      route.continue();
    });
    await ctx.addInitScript((sc) => {
      if (sessionStorage.getItem('__seeded')) return;
      sessionStorage.setItem('__seeded', '1');
      localStorage.setItem('cf_room', 'scenesel-room-test-0001');
      localStorage.setItem('cf_user_name', 'Тест');
      localStorage.setItem('cf_scenes', JSON.stringify(sc));
    }, SCENES);
    const page = await ctx.newPage();
    const errs = [];
    page.on('pageerror', e => errs.push(String(e).slice(0, 200)));
    await page.goto(`http://127.0.0.1:${PORT}/${url}`);
    await page.waitForFunction(() => window.__CF_APP_OK, { timeout: 180000 });
    await page.waitForTimeout(900);
    return { page, errs, ctx };
  };
  // Нажатие по-настоящему: точка — середина элемента, и она обязана
  // попадать в него самого, а не в то, что лежит сверху.
  const tap = async (page, sel, label) => {
    const el = page.locator(sel).first();
    const b = await el.boundingBox();
    if (!b) { ok(label + ': есть на экране', false); return false; }
    const x = b.x + b.width / 2, y = b.y + b.height / 2;
    const hit = await page.evaluate(([s, x, y]) => { const e = document.elementFromPoint(x, y), t = document.querySelector(s); return !!(e && t && (t === e || t.contains(e))); }, [sel, x, y]);
    ok(label + ': нажатие попадает', hit);
    await page.mouse.click(x, y);
    await page.waitForTimeout(250);
    return hit;
  };
  const rows = (page) => page.$$eval('[data-cf="scene-row"]', els => els.map(e => e.dataset.id));

  // ---------- ПЛАНШЕТ ----------
  console.log('Планшет 1280');
  {
    const { page, errs, ctx } = await mk({ width: 1280, height: 900 });
    ok('в списке пять сцен', (await rows(page)).length === 5, (await rows(page)).join(','));
    await tap(page, '[data-cf="scene-sel"]', '«Выбрать»');
    ok('у строк появились кружки', (await page.$$('[data-cf="scene-sel-mark"]')).length === 5);
    await tap(page, '[data-cf="scene-row"][data-id="s2"]', 'строка #2');
    await tap(page, '[data-cf="scene-row"][data-id="s3"]', 'строка #3');
    const del = await page.textContent('[data-cf="scene-sel-delete"]');
    ok('кнопка говорит «Удалить 2 сцены»', /Удалить 2 сцены/.test(del), del);
    await tap(page, '[data-cf="scene-sel-delete"]', '«Удалить»');
    const title = await page.textContent('[role="dialog"]').catch(() => '');
    ok('одно окно «Удалить 2 сцены?»', /Удалить 2 сцены\?/.test(title || ''), (title || '').slice(0, 80));
    await tap(page, '[data-cf="confirm-ok"]', 'подтверждение');
    await page.waitForTimeout(400);
    const left = await rows(page);
    ok('остались 1, 4, 5', left.join(',') === 's1,s4,s5', left.join(','));
    ok('режим выбора выключился', !(await page.$('[data-cf="scene-sel-mark"]')));
    ok('полоска «Удалено 2 сцены»', await page.isVisible('text=Удалено 2 сцены'));
    await tap(page, '[data-cf="undo-restore"]', '«Вернуть»');
    await page.waitForTimeout(400);
    const back = await rows(page);
    ok('обе вернулись', back.join(',') === 's1,s2,s3,s4,s5', back.join(','));
    await page.waitForTimeout(900);
    const s3b = await page.evaluate(() => (JSON.parse(localStorage.getItem('cf_scenes') || '[]').find(x => x.id === 's3') || {}));
    ok('вернулась с датой и техникой', s3b.date === '2026-11-01' && s3b.gear && s3b.gear.cam === 1, JSON.stringify(s3b).slice(0, 120));
    // «Все» и «Готово»
    await tap(page, '[data-cf="scene-sel"]', '«Выбрать» снова');
    await tap(page, '[data-cf="scene-sel-all"]', '«Все»');
    ok('«Все» выделил пять', /Удалить 5 сцен/.test(await page.textContent('[data-cf="scene-sel-delete"]')));
    await tap(page, '[data-cf="scene-sel-done"]', '«Готово»');
    ok('«Готово» ничего не удалил', (await rows(page)).length === 5);
    ok('без ошибок на странице', errs.length === 0, errs.join(' | '));
    await ctx.close();
  }

  // ---------- ТЕЛЕФОН ----------
  console.log('Телефон 390');
  {
    const { page, errs, ctx } = await mk({ width: 390, height: 844 });
    const shown = await rows(page);
    ok('фильтр смены показывает смену', shown.length >= 2 && shown.length < 5, shown.join(','));
    await tap(page, '[data-cf="scene-sel"]', '«Выбрать» в шапке');
    await tap(page, '[data-cf="scene-sel-all"]', '«Выделить все»');
    const t = await page.textContent('[data-cf="scene-sel-delete"]');
    ok('выделено только показанное', new RegExp(`Удалить ${shown.length} `).test(t), t);
    await tap(page, '[data-cf="scene-sel-delete"]', '«Удалить» на телефоне');
    await tap(page, '[data-cf="confirm-ok"]', 'подтверждение');
    await page.waitForTimeout(500);
    await page.waitForTimeout(900);
    const all2 = await page.evaluate(() => JSON.parse(localStorage.getItem('cf_scenes') || '[]').map(x => x.id));
    const expect = SCENES.map(x => x.id).filter(id => !shown.includes(id));
    ok('сцены другой смены целы', all2.sort().join(',') === expect.sort().join(','), all2.join(','));
    ok('без ошибок на странице', errs.length === 0, errs.join(' | '));
    await ctx.close();
  }

  // ---------- ГОСТЬ ----------
  console.log('Просмотр по ссылке');
  {
    const { page, ctx } = await mk({ width: 1280, height: 900 }, 'index.html?view=all&room=scenesel-room-test-0001');
    ok('«Выбрать» гостю не показан', !(await page.isVisible('[data-cf="scene-sel"]')));
    await ctx.close();
  }

  await browser.close(); server.kill();
  console.log(bad ? `\n${bad} проверок не прошло` : '\nВсё прошло');
  process.exit(bad ? 1 : 0);
})().catch(e => { console.error(e); server.kill(); process.exit(1); });
