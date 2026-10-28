// Скопировать настройки из другой сцены (техника · свет · схема · дата · объект).
//
// Планшет 1280: сцена #2 → «···» → «Скопировать настройки из сцены…» → в окне
// сначала сцены ТОГО ЖЕ объекта, остальные за «Показать остальные» → выбор #1
// показывает, что поедет, галочками (дата снята, пустое выключено) →
// «Скопировать» заменяет технику, свет и схему у #2 → полоска «Вернуть»
// возвращает прежнее → из сцены ДРУГОГО объекта предлагается и объект
// (снят, у сцены свой объект есть), у сцены без объекта — включён.
// Телефон 390: та же строка в «Ещё». Гость по ссылке: «···» спрятан.
//
// Запуск:  node tests/scenecopy-e2e.js
const fs = require('fs'), os = require('os'), path = require('path');
const { execSync, spawn } = require('child_process');
const ROOT = path.resolve(__dirname, '..');
const LIBS = process.env.CF_LIBS || path.join(os.tmpdir(), 'cineflow-libs');
const PORT = process.env.CF_PORT || '8169';
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
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

const SCENES = [
  { id: 's1', number: '1', title: 'ИНТ. КУХНЯ — ДЕНЬ', date: '2099-11-01', content: '', gear: { alexa: 1, zoom: 1 }, lightGear: { m18: 2, sky: 1 }, lightSchemeId: 'ls1' },
  { id: 's2', number: '2', title: 'ИНТ. КУХНЯ — ВЕЧЕР', date: '', content: '', gear: {}, lightGear: {}, lightSchemeId: null },
  { id: 's3', number: '3', title: 'НАТ. ДВОР — ДЕНЬ', date: '2099-11-05', content: '', gear: { red: 1 }, lightGear: {}, lightSchemeId: null },
  { id: 's4', number: '4', title: 'ИНТ. ЛИФТ — НОЧЬ', date: '', content: '', gear: {}, lightGear: {}, lightSchemeId: null }
];
const LOCS = [
  { id: 'l1', name: 'Квартира на Горской', address: '', coords: '', description: '', sceneIds: ['s1', 's2'], lightSchemeId: '', order: 1 },
  { id: 'l2', name: 'Двор школы', address: '', coords: '', description: '', sceneIds: ['s3'], lightSchemeId: '', order: 2 }
];
const SCHEMES = [{ id: 'ls1', title: 'Кухня день', elements: [], drawData: '' }];
const GEAR = { alexa: { label: 'ALEXA 35' }, zoom: { label: 'Zoom 24-290' }, red: { label: 'RED Komodo' } };
const LIGHT = { m18: { label: 'ARRI M18' }, sky: { label: 'SkyPanel S60' } };

(async () => {
  await new Promise(r => setTimeout(r, 1200));
  const browser = await playwright.chromium.launch({
    executablePath: process.env.CF_CHROME || '/opt/pw-browsers/chromium', args: ['--no-sandbox'] });
  const mk = async (viewport, url = 'index.html') => {
    const phone = viewport.width < 500;
    const ctx = await browser.newContext({ viewport, serviceWorkers: 'block', hasTouch: phone, isMobile: phone,
      userAgent: phone ? 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1' : undefined });
    await ctx.route('**/*', route => {
      const u = route.request().url();
      if (/firestore|firebase|googleapis\.com\/(identitytoolkit|securetoken)|gstatic/.test(u)) return route.abort();
      for (const [f, re] of [['react.js', /react@18[.0-9]*\/umd\/react\.production/], ['react-dom.js', /react-dom@18/],
                             ['babel.js', /babel\.min\.js/], ['tailwind.js', /cdn\.tailwindcss/]])
        if (re.test(u)) return route.fulfill({ body: fs.readFileSync(path.join(LIBS, f)), contentType: 'application/javascript',
                                               headers: { 'Access-Control-Allow-Origin': '*' } });
      route.continue();
    });
    await ctx.addInitScript(([sc, lc, sh, g, lt]) => {
      if (sessionStorage.getItem('__seeded')) return;
      sessionStorage.setItem('__seeded', '1');
      localStorage.setItem('cf_room', 'scenecopy-room-test-0001');
      localStorage.setItem('cf_user_name', 'Тест');
      localStorage.setItem('cf_scene_mode', 'creative');
      localStorage.setItem('cf_scenes', JSON.stringify(sc));
      localStorage.setItem('cf_locations', JSON.stringify(lc));
      localStorage.setItem('cf_lightschemes', JSON.stringify(sh));
      localStorage.setItem('cf_geartypes', JSON.stringify(g));
      localStorage.setItem('cf_lightgeartypes', JSON.stringify(lt));
    }, [SCENES, LOCS, SCHEMES, GEAR, LIGHT]);
    const page = await ctx.newPage();
    const errs = [];
    page.on('pageerror', e => errs.push(String(e).slice(0, 200)));
    await page.goto(`http://127.0.0.1:${PORT}/${url}`);
    await page.waitForFunction(() => window.__CF_APP_OK, { timeout: 180000 });
    await page.waitForTimeout(900);
    return { page, errs, ctx };
  };
  const tap = async (page, sel, label) => {
    const el = page.locator(sel).first();
    await el.scrollIntoViewIfNeeded().catch(() => {});
    const b = await el.boundingBox();
    if (!b) { ok(label + ': есть на экране', false); return false; }
    const h = await el.elementHandle();
    const x = b.x + b.width / 2, y = b.y + b.height / 2;
    const hit = await page.evaluate(([t, x, y]) => { const e = document.elementFromPoint(x, y); return !!(e && (t === e || t.contains(e))); }, [h, x, y]);
    ok(label + ': нажатие попадает', hit);
    await page.mouse.click(x, y);
    await page.waitForTimeout(350);
    return hit;
  };
  const sceneOf = (page, id) => page.evaluate((id) => (JSON.parse(localStorage.getItem('cf_scenes') || '[]').find(x => x.id === id) || null), id);
  const locOf = (page, id) => page.evaluate((id) => (JSON.parse(localStorage.getItem('cf_locations') || '[]').find(x => x.id === id) || null), id);
  // Местная копия пишется с задержкой 700 мс.
  const settle = (page) => page.waitForTimeout(1000);
  const boxes = (page) => page.evaluate(() => {
    const o = {};
    ['gear', 'light', 'scheme', 'date', 'loc'].forEach(k => { const e = document.querySelector(`[data-cf="copy-${k}"]`); o[k] = e ? { on: e.checked, off: e.disabled } : null; });
    return o;
  });
  const rows = (page) => page.evaluate(() => [...document.querySelectorAll('[data-cf="copy-src"]')].map(e => e.dataset.id));

  console.log('Планшет 1280');
  {
    const { page, errs, ctx } = await mk({ width: 1280, height: 900 });
    await tap(page, '[data-cf="scene-row"][data-id="s2"]', 'строка #2');
    await tap(page, '[data-cf="scene-menu"]', '«···» сцены');
    await tap(page, '[data-cf="scene-copy"]', 'строка «Скопировать настройки из сцены…»');
    const head = await page.evaluate(() => { const h = document.querySelector('[data-cf="copy-head"]'); return h ? h.textContent : null; });
    ok('окно: сначала сцены того же объекта', head === 'На том же объекте · Квартира на Горской', head);
    ok('в списке только #1 — соседка по объекту', same(await rows(page), ['s1']), JSON.stringify(await rows(page)));
    const more = await page.evaluate(() => { const b = document.querySelector('[data-cf="copy-all"]'); return b ? b.textContent.trim() : null; });
    ok('остальные — за «Показать остальные сцены · 2»', more === 'Показать остальные сцены · 2', more);
    const goBefore = await page.evaluate(() => { const b = document.querySelector('[data-cf="copy-go"]'); return b && b.disabled && b.textContent; });
    ok('пока сцена не выбрана, кнопка не нажимается', /Выберите сцену/.test(goBefore || ''), goBefore);
    await tap(page, '[data-cf="copy-src"][data-id="s1"]', 'сцена #1 в списке');
    const bx = await boxes(page);
    ok('что поедет: техника, свет, схема включены; дата снята; объекта нет (он тот же)',
       bx.gear && bx.gear.on && bx.light && bx.light.on && bx.scheme && bx.scheme.on && bx.date && !bx.date.on && !bx.date.off && bx.loc === null, JSON.stringify(bx));
    const what = await page.evaluate(() => document.querySelector('[data-cf="copy-what"]').textContent);
    ok('у каждой галочки написано, что именно поедет', /ALEXA 35 × 1 · Zoom 24-290 × 1/.test(what) && /ARRI M18 × 2 · SkyPanel S60 × 1/.test(what) && /Кухня день/.test(what) && /01\.11\.2099/.test(what), what);
    await tap(page, '[data-cf="copy-go"]', '«Скопировать из #1»');
    await settle(page);
    const s2 = await sceneOf(page, 's2');
    ok('у #2 техника, свет и схема как у #1, дата не тронута',
       s2 && same(s2.gear, { alexa: 1, zoom: 1 }) && same(s2.lightGear, { m18: 2, sky: 1 }) && same(s2.lightOwn, { m18: 2, sky: 1 }) && s2.lightSchemeId === 'ls1' && s2.date === '',
       JSON.stringify(s2 && { gear: s2.gear, lightGear: s2.lightGear, lightOwn: s2.lightOwn, scheme: s2.lightSchemeId, date: s2.date }));
    const s1 = await sceneOf(page, 's1');
    ok('источник #1 не изменился', s1 && same(s1.gear, { alexa: 1, zoom: 1 }) && same(s1.lightGear, { m18: 2, sky: 1 }) && s1.lightSchemeId === 'ls1');
    const closed = await page.evaluate(() => !document.querySelector('[data-cf="copy-list"]'));
    ok('окно закрылось', closed);
    const bar = await page.evaluate(() => { const b = document.querySelector('[data-cf="undo-restore"]'); return b ? b.parentElement.textContent : null; });
    ok('полоска «Вернуть» называет, что скопировано', /В сцену #2 скопировано из #1: техника, свет, схема «Кухня день»/.test(bar || ''), bar);
    const two = await page.evaluate(() => document.querySelectorAll('[data-cf="toast"]').length);
    ok('второй полоски-уведомления нет — она ложилась поверх «Вернуть»', two === 0);
    const rail = await page.evaluate(() => !!document.querySelector('button[title^="Схема света · Кухня день"]'));
    ok('в рельсе сцены появилась её схема света', rail);
    await tap(page, '[data-cf="undo-restore"]', '«Вернуть»');
    await settle(page);
    const s2b = await sceneOf(page, 's2');
    ok('«Вернуть» вернуло #2 прежнюю — пустую', s2b && same(s2b.gear, {}) && same(s2b.lightGear, {}) && !s2b.lightSchemeId, JSON.stringify(s2b && { gear: s2b.gear, lightGear: s2b.lightGear, scheme: s2b.lightSchemeId }));
    const rail2 = await page.evaluate(() => !!document.querySelector('button[title^="Схема света · Кухня день"]'));
    ok('схема из рельса ушла', !rail2);

    // Из сцены ДРУГОГО объекта: предлагается и объект, выключенный.
    await tap(page, '[data-cf="scene-menu"]', '«···» сцены ещё раз');
    await tap(page, '[data-cf="scene-copy"]', 'строка копирования ещё раз');
    await tap(page, '[data-cf="copy-all"]', '«Показать остальные сцены»');
    ok('после «показать» в списке все три', same(await rows(page), ['s1', 's3', 's4']), JSON.stringify(await rows(page)));
    await tap(page, '[data-cf="copy-src"][data-id="s3"]', 'сцена #3 (другой объект)');
    const bx3 = await boxes(page);
    ok('из #3: техника включена, пустые свет и схема выключены и не нажимаются, дата снята, объект предложен и снят',
       bx3.gear && bx3.gear.on && bx3.light && !bx3.light.on && bx3.light.off && bx3.scheme && !bx3.scheme.on && bx3.scheme.off && bx3.date && !bx3.date.on && bx3.loc && !bx3.loc.on && !bx3.loc.off, JSON.stringify(bx3));
    const what3 = await page.evaluate(() => document.querySelector('[data-cf="copy-what"]').textContent);
    ok('пустое так и названо — «нечего копировать»', /пусто — нечего копировать/.test(what3) && /не выбрана — нечего копировать/.test(what3) && /Двор школы/.test(what3), what3);
    await tap(page, '[data-cf="copy-loc"]', 'галочка «Объект»');
    await tap(page, '[data-cf="copy-date"]', 'галочка «Дата смены»');
    await tap(page, '[data-cf="copy-go"]', '«Скопировать из #3»');
    await settle(page);
    const s2c = await sceneOf(page, 's2'); const l2 = await locOf(page, 'l2');
    ok('у #2 техника и дата из #3, свет не тронут, и сцена приписана ко «Двору школы»',
       s2c && same(s2c.gear, { red: 1 }) && s2c.date === '2099-11-05' && same(s2c.lightGear, {}) && l2 && l2.sceneIds.includes('s2'),
       JSON.stringify({ gear: s2c && s2c.gear, date: s2c && s2c.date, l2: l2 && l2.sceneIds }));
    const bar3 = await page.evaluate(() => { const b = document.querySelector('[data-cf="undo-restore"]'); return b ? b.parentElement.textContent : null; });
    ok('полоска называет, что поехало, включая объект', /из #3: техника, дата смены, объект «Двор школы»/.test(bar3 || ''), bar3);
    await tap(page, '[data-cf="undo-restore"]', '«Вернуть» после объекта');
    await settle(page);
    const l2b = await locOf(page, 'l2'); const s2d = await sceneOf(page, 's2');
    ok('«Вернуть» сняло сцену с объекта и вернуло дату', l2b && same(l2b.sceneIds, ['s3']) && s2d && s2d.date === '' && same(s2d.gear, {}), JSON.stringify({ l2: l2b && l2b.sceneIds, date: s2d && s2d.date }));

    // Сцена БЕЗ объекта: список без деления, объект источника включён сразу.
    await tap(page, '[data-cf="scene-row"][data-id="s4"]', 'строка #4');
    await tap(page, '[data-cf="scene-menu"]', '«···» сцены #4');
    await tap(page, '[data-cf="scene-copy"]', 'строка копирования у #4');
    const head4 = await page.evaluate(() => document.querySelector('[data-cf="copy-head"]').textContent);
    const all4 = await page.evaluate(() => !document.querySelector('[data-cf="copy-all"]'));
    ok('у сцены без объекта — просто «Из какой сцены» и все сцены разом', head4 === 'Из какой сцены' && all4 && same(await rows(page), ['s1', 's2', 's3']), head4 + ' ' + JSON.stringify(await rows(page)));
    await tap(page, '[data-cf="copy-src"][data-id="s1"]', 'сцена #1 для #4');
    const bx4 = await boxes(page);
    ok('объект «Квартира на Горской» предложен и включён — у #4 своего нет', bx4.loc && bx4.loc.on, JSON.stringify(bx4));
    await tap(page, '[data-cf="copy-go"]', '«Скопировать из #1» в #4');
    await settle(page);
    const l1 = await locOf(page, 'l1'); const s4 = await sceneOf(page, 's4');
    ok('#4 приписана к квартире и получила технику', l1 && l1.sceneIds.includes('s4') && s4 && same(s4.gear, { alexa: 1, zoom: 1 }), JSON.stringify({ l1: l1 && l1.sceneIds, gear: s4 && s4.gear }));
    ok('без ошибок на планшете', errs.length === 0, errs.join(' | '));
    await ctx.close();
  }

  console.log('Телефон 390');
  {
    const { page, errs, ctx } = await mk({ width: 390, height: 844 });
    // Телефон по умолчанию показывает ближайшую смену, а у #2 даты нет.
    await tap(page, '.cf-pill:has-text("Все")', 'фильтр «Все»');
    await tap(page, '[data-cf="scene-row"][data-id="s2"]', 'строка #2');
    await tap(page, '.cf-tab:has-text("Ещё")', 'вкладка «Ещё»');
    await tap(page, '[data-cf="more-scene-copy"]', 'строка «Скопировать настройки из сцены…» в «Ещё»');
    ok('шторка ушла, окно открылось', await page.evaluate(() => !document.querySelector('.cf-sheet') && !!document.querySelector('[data-cf="copy-list"]')));
    await tap(page, '[data-cf="copy-src"][data-id="s1"]', 'сцена #1 в списке');
    await tap(page, '[data-cf="copy-go"]', '«Скопировать из #1»');
    await settle(page);
    const s2 = await sceneOf(page, 's2');
    ok('на телефоне у #2 техника, свет и схема из #1', s2 && same(s2.gear, { alexa: 1, zoom: 1 }) && same(s2.lightGear, { m18: 2, sky: 1 }) && s2.lightSchemeId === 'ls1', JSON.stringify(s2 && { gear: s2.gear, lightGear: s2.lightGear, scheme: s2.lightSchemeId }));
    const undo = await page.evaluate(() => { const b = document.querySelector('[data-cf="undo-restore"]'); if (!b) return null; const r = b.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2, h: innerHeight }; });
    ok('полоска «Вернуть» на телефоне стоит выше таб-бара и полосы соседних сцен', undo && undo.y < undo.h - 49 - 44 && undo.y > 0, JSON.stringify(undo));
    const navHit = await page.evaluate(() => { const n = document.querySelector('[data-cf="scene-next"]'); const r = n.getBoundingClientRect(); const e = document.elementFromPoint(r.x + r.width - 20, r.y + r.height / 2); return !!(e && n.contains(e)); });
    ok('«следующая сцена» под полоской не закрыта', navHit);
    const barText = await page.evaluate(() => { const b = document.querySelector('[data-cf="undo-restore"]'); const sp = b.parentElement.querySelector('span'); const r = sp.getBoundingClientRect(); return { t: sp.textContent, h: r.height, w: r.width, right: r.right, bx: b.getBoundingClientRect().x }; });
    ok('текст полоски на телефоне в две строки, во всю ширину и не заезжает на «Вернуть»', barText.h > 30 && barText.h < 60 && barText.w > 180 && barText.right <= barText.bx + 1, JSON.stringify(barText));
    ok('без ошибок на телефоне', errs.length === 0, errs.join(' | '));
    await ctx.close();
  }

  console.log('Гость по ссылке');
  {
    const { page, errs, ctx } = await mk({ width: 1280, height: 900 }, 'index.html?view=all&room=scenecopy-room-test-0001');
    await tap(page, '[data-cf="scene-row"][data-id="s2"]', 'строка #2 у гостя');
    const hidden = await page.evaluate(() => { const b = document.querySelector('[data-cf="scene-menu"]'); return !b || !b.offsetParent; });
    ok('у гостя «···» сцены спрятан — копировать нечем', hidden);
    ok('без ошибок у гостя', errs.length === 0, errs.join(' | '));
    await ctx.close();
  }

  await browser.close(); server.kill();
  console.log(bad ? `\n${bad} проверок не прошло` : '\nВсё прошло');
  process.exit(bad ? 1 : 0);
})().catch(e => { console.error(e); server.kill(); process.exit(1); });
