// Стандартный комплект света — один на проект, у сцены только доборы.
//
// Планшет 1280: панель «Свет» → блок «Стандартный комплект» в покое текстом
// («Не задан…») → нажатие открывает поле → набранное ложится в cf_light_base
// → в покое снова текст, список сцены подписан «Доборы в этой сцене» → КПП
// «По сменам» показывает комплект один раз сверху, итоги — «Доборы света».
// Телефон 390: шторка «Свет» показывает тот же комплект. Гость по ссылке:
// комплект виден, нажатие поля не открывает.
//
// Запуск:  node tests/lightbase-e2e.js
const fs = require('fs'), os = require('os'), path = require('path');
const { execSync, spawn } = require('child_process');
const ROOT = path.resolve(__dirname, '..');
const LIBS = process.env.CF_LIBS || path.join(os.tmpdir(), 'cineflow-libs');
const PORT = process.env.CF_PORT || '8168';
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

const KIT = '2× SkyPanel S60, 4× Astera Titan\nфлаги, рамы 4×4, штативы';
const SCENES = [
  { id: 's1', number: '1', title: 'ИНТ. КУХНЯ — ДЕНЬ', date: '2099-11-01', content: '', gear: {}, lightGear: { m18: 1 }, lightSchemeId: null },
  { id: 's2', number: '2', title: 'НАТ. ДВОР — ДЕНЬ', date: '2099-11-01', content: '', gear: {}, lightGear: {}, lightSchemeId: null }
];
const LIGHT = { m18: { label: 'ARRI M18' } };

(async () => {
  await new Promise(r => setTimeout(r, 1200));
  const browser = await playwright.chromium.launch({
    executablePath: process.env.CF_CHROME || '/opt/pw-browsers/chromium', args: ['--no-sandbox'] });
  const mk = async (viewport, url = 'index.html', seedKit = '') => {
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
    await ctx.addInitScript(([sc, lt, kit]) => {
      if (sessionStorage.getItem('__seeded')) return;
      sessionStorage.setItem('__seeded', '1');
      localStorage.setItem('cf_room', 'lightbase-room-test-0001');
      localStorage.setItem('cf_user_name', 'Тест');
      localStorage.setItem('cf_scene_mode', 'creative');
      localStorage.setItem('cf_scenes', JSON.stringify(sc));
      localStorage.setItem('cf_lightgeartypes', JSON.stringify(lt));
      if (kit) localStorage.setItem('cf_light_base', kit);
    }, [SCENES, LIGHT, seedKit]);
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
    await page.waitForTimeout(300);
    return hit;
  };

  console.log('Планшет 1280');
  {
    const { page, errs, ctx } = await mk({ width: 1280, height: 900 });
    await tap(page, 'button[title="Свет"]', 'вкладка «Свет»');
    const rest = await page.evaluate(() => { const t = document.querySelector('[data-cf="light-base-text"]'); return t ? t.textContent : null; });
    const noField = await page.evaluate(() => !document.querySelector('[data-cf="light-base-input"]'));
    ok('комплект в покое — текст «Не задан…», без поля', rest && /Не задан/.test(rest) && noField, rest);
    await tap(page, '[data-cf="light-base-text"]', 'строка комплекта');
    const field = await page.evaluate(() => { const a = document.activeElement; return !!a && a.dataset.cf === 'light-base-input'; });
    ok('нажатие открыло поле и поставило курсор', field);
    await page.keyboard.type(KIT.split('\n')[0]);
    await page.keyboard.press('Enter');
    await page.keyboard.type(KIT.split('\n')[1]);
    await page.waitForTimeout(300);
    const saved = await page.evaluate(() => localStorage.getItem('cf_light_base'));
    ok('комплект лёг на устройство', saved === KIT, JSON.stringify(saved));
    const head = await page.evaluate(() => { const h = document.querySelector('[data-cf="light-extras-head"]'); return h ? h.textContent : null; });
    ok('список сцены подписан «Доборы в этой сцене»', head === 'Доборы в этой сцене', head);
    await page.mouse.click(640, 120); await page.waitForTimeout(400);
    const rest2 = await page.evaluate(() => { const t = document.querySelector('[data-cf="light-base-text"]'); return { text: t && t.textContent, field: !!document.querySelector('[data-cf="light-base-input"]') }; });
    ok('ушли из поля — снова текст, в две строки как набрано', rest2.text === KIT && !rest2.field, JSON.stringify(rest2));
    // другая сцена видит тот же комплект
    await tap(page, '[data-cf="scene-row"][data-id="s2"]', 'строка #2');
    const other = await page.evaluate(() => { const t = document.querySelector('[data-cf="light-base-text"]'); return { text: t && t.textContent, empty: document.body.textContent.includes('едет только стандартный комплект') }; });
    ok('у сцены без доборов тот же комплект и честное «едет только стандартный комплект»', other.text === KIT && other.empty, JSON.stringify(other));
    // КПП
    await page.evaluate(() => { const b = [...document.querySelectorAll('header button')].find(x => /КПП/i.test((x.textContent || '') + (x.title || ''))); b && b.click(); });
    await page.waitForTimeout(900);
    // Смотрим в сам раздел смены, а не в body: в body лежит и исходник
    // приложения, и любое слово из кода там «найдётся».
    const kpp = await page.evaluate(() => { const k = document.querySelector('[data-cf="kpp-light-base"]'); const t = [...document.querySelectorAll('.cf-shift')].map(x => x.textContent).join(' ');
      return { once: document.querySelectorAll('[data-cf="kpp-light-base"]').length, text: k && k.textContent, extras: /Доборы света/.test(t), row: /доборы:\s*ARRI M18/.test(t), old: /Итого свет/.test(t) }; });
    ok('КПП: комплект один раз сверху, итоги и строки сцен — «доборы»', kpp.once === 1 && kpp.text && kpp.text.includes('SkyPanel S60') && kpp.extras && kpp.row && !kpp.old, JSON.stringify(kpp));
    ok('без ошибок на планшете', errs.length === 0, errs.join(' | '));
    await ctx.close();
  }

  console.log('Телефон 390');
  {
    const { page, errs, ctx } = await mk({ width: 390, height: 844 }, 'index.html', KIT);
    await tap(page, '[data-cf="scene-row"][data-id="s1"]', 'строка #1');
    await tap(page, '.cf-tile:has-text("Свет")', 'плитка «Свет»');
    const ph = await page.evaluate(() => { const sh = document.querySelector('.cf-sheet'); const t = sh && sh.querySelector('[data-cf="light-base-text"]');
      return { text: t && t.textContent, head: !!(sh && sh.querySelector('[data-cf="light-extras-head"]')) }; });
    ok('в шторке «Свет» тот же комплект и подпись «Доборы»', ph.text === KIT && ph.head, JSON.stringify(ph));
    ok('без ошибок на телефоне', errs.length === 0, errs.join(' | '));
    await ctx.close();
  }

  console.log('Гость по ссылке');
  {
    const { page, errs, ctx } = await mk({ width: 1280, height: 900 }, 'index.html?view=all&room=lightbase-room-test-0001', KIT);
    await tap(page, 'button[title="Свет"]', 'вкладка «Свет» у гостя');
    const g0 = await page.evaluate(() => { const t = document.querySelector('[data-cf="light-base-text"]'); return t && t.textContent; });
    await tap(page, '[data-cf="light-base-text"]', 'строка комплекта у гостя');
    const g1 = await page.evaluate(() => ({ field: !!document.querySelector('[data-cf="light-base-input"]'), text: (document.querySelector('[data-cf="light-base-text"]') || {}).textContent }));
    ok('гость видит комплект, а поле у него не открывается', g0 === KIT && !g1.field && g1.text === KIT, JSON.stringify(g1));
    ok('без ошибок у гостя', errs.length === 0, errs.join(' | '));
    await ctx.close();
  }

  await browser.close(); server.kill();
  console.log(bad ? `\n${bad} проверок не прошло` : '\nВсё прошло');
  process.exit(bad ? 1 : 0);
})().catch(e => { console.error(e); server.kill(); process.exit(1); });
