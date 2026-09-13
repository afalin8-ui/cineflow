// Что происходит, когда проект ПЕРЕРОС память устройства. Путь важный
// и до сих пор не проверялся ничем: ломается он молча, а последствия
// видит человек на площадке.
//
// Что гоняем: подменяем localStorage.setItem так, чтобы запись
// референсов С КАРТИНКАМИ отвергалась, а без них проходила (настоящий
// предел браузера в стенде не воспроизвести — он разный, и «набить
// балласта» получается через раз), и смотрим:
//   · полоска появляется и НЕ превращается в овал во весь экран;
//   · она говорит ОДИН раз насовсем, а не при каждом открытии —
//     у большого проекта это состояние постоянное, и повторять его
//     значит встречать человека одной и той же новостью вечно;
//   · постоянное место у этой новости — меню «Проект», и там написано
//     верное: копия обновляется БЕЗ фотографий, а не «не обновляется»;
//   · проект снова влез целиком — флаг снят, и будущее переполнение
//     опять новость.
//
// Запуск:  node tests/storage-e2e.js
// Нужны: node 18+, playwright, Chromium (CF_CHROME), python3, curl.
const path = require('path'), fs = require('fs'), os = require('os');
const { execSync, spawn } = require('child_process');
const ROOT = '/home/user/cineflow';
const LIBS = process.env.CF_LIBS || path.join(os.tmpdir(), 'cineflow-libs');
const PORT = process.env.CF_PORT || '8105';
let playwright;
try { playwright = require('playwright'); }
catch (e) { playwright = require(execSync('npm root -g').toString().trim() + '/playwright'); }
const server = spawn('python3', ['-m','http.server',PORT,'--bind','127.0.0.1'], { cwd: ROOT, stdio: 'ignore' });
let bad = 0;
const ok = (n, c, d) => { console.log((c ? '  ok  ' : '  FAIL') + ' ' + n + (d ? ' — ' + d : '')); if (!c) bad++; };
(async () => {
  await new Promise(r => setTimeout(r, 1200));
  const browser = await playwright.chromium.launch({ executablePath: process.env.CF_CHROME || '/opt/pw-browsers/chromium', args: ['--no-sandbox'] });
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });
  await ctx.route('**/*', (route) => {
    const u = route.request().url();
    if (/firestore|firebase|googleapis|gstatic|nominatim/.test(u)) return route.abort();
    for (const [f, re] of [['react.js',/react@18\/umd\/react\.production/],['react-dom.js',/react-dom@18/],['babel.js',/babel\.min\.js/],['tailwind.js',/cdn\.tailwindcss/]])
      if (re.test(u)) return route.fulfill({ body: fs.readFileSync(path.join(LIBS, f)), contentType: 'application/javascript' });
    route.continue();
  });
  // Забиваем localStorage почти под завязку — так, чтобы проект целиком
  // уже не влезал, а урезанный влезал.
  // Переполнение изображаем НАДЁЖНО: подменяем setItem так, чтобы
  // запись референсов С КАРТИНКАМИ отвергалась, а без них проходила.
  // Настоящий предел браузера в стенде не воспроизвести — он разный,
  // и «набить балласта» получается через раз.
  await ctx.addInitScript(() => {
    localStorage.setItem('cf_room', 'quota-room');
    localStorage.setItem('cf_user_name', 'Тест');
    localStorage.setItem('cf_references', JSON.stringify([
      { id: 'r1', url: 'data:image/jpeg;base64,' + 'A'.repeat(60 * 1024), label: 'кадр', tags: ['скаут'], folder: 'ДВОР' }
    ]));
    const real = localStorage.setItem.bind(localStorage);
    localStorage.setItem = function (k, v) {
      if (k === 'cf_references' && String(v).length > 20000) {
        const err = new Error('QuotaExceededError'); err.name = 'QuotaExceededError'; throw err;
      }
      return real(k, v);
    };
  });

  const page = await ctx.newPage();
  page.on('pageerror', e => console.log('PAGEERROR', e.message));
  await page.goto(`http://127.0.0.1:${PORT}/index.html`);
  await page.waitForFunction(() => window.__CF_APP_OK, { timeout: 90000 });
  await page.waitForTimeout(1500);

  const toastText = () => page.evaluate(() => {
    const t = document.querySelector('[data-cf="toast"]');
    return t ? t.innerText.trim() : '';
  });
  await page.waitForTimeout(2000);
  const shape = await page.evaluate(() => {
    const t = document.querySelector('[data-cf="toast"]');
    if (!t) return null;
    const r = t.getBoundingClientRect();
    return { w: Math.round(r.width), h: Math.round(r.height), radius: getComputedStyle(t).borderRadius,
             text: t.innerText.trim().slice(0, 60), vw: window.innerWidth };
  });
  if (shape) {
    ok('полоска не шире экрана', shape.w <= shape.vw * 0.93 + 2, `${shape.w} из ${shape.vw}`);
    ok('и не превращается в овал', !/9999|50%/.test(shape.radius), shape.radius);
  } else {
    ok('полоска о переполнении показалась', false, 'её нет — подмена setItem не сработала');
  }
  const flag1 = await page.evaluate(() => localStorage.getItem('cf_light_warned'));
  console.log('  ..  флаг после первого раза:', flag1);

  // Перезапуск: полоска НЕ должна появиться снова
  const page2 = await ctx.newPage();
  await page2.goto(`http://127.0.0.1:${PORT}/index.html`);
  await page2.waitForFunction(() => window.__CF_APP_OK, { timeout: 90000 });
  await page2.waitForTimeout(2500);
  const again = await page2.evaluate(() => {
    const t = document.querySelector('[data-cf="toast"]');
    return t ? t.innerText.trim() : '';
  });
  ok('при следующем открытии полоска НЕ возвращается', !/помещаются|кончилось место/.test(again), again || '(тихо)');
  // И ЧТО СОСТОЯНИЕ НАПИСАНО ТАМ, КУДА ОТПРАВЛЯЕМ. Полоска говорит
  // один раз, а постоянное место у этой новости — меню «Проект».
  const inProject = await page2.evaluate(async () => {
    const more = [...document.querySelectorAll('.cf-tabbar button')].find(b => /Ещё/.test(b.textContent));
    if (more) { more.click(); await new Promise(r => setTimeout(r, 600)); }
    const proj = [...document.querySelectorAll('button')].find(b => b.textContent.trim() === 'Проект');
    if (!proj) return { err: 'кнопки «Проект» нет' };
    proj.click();
    await new Promise(r => setTimeout(r, 800));
    const box = document.querySelector('[data-cf="storage-info"]');
    return { text: box ? box.innerText.replace(/\s+/g, ' ').trim() : '(нет блока)' };
  });
  ok('состояние написано в меню «Проект»',
     /без них|БЕЗ них/.test(inProject.text || ''), (inProject.text || inProject.err || '').slice(0, 130));

  // ВЛЕЗЛО СНОВА — флаг снимается, и будущее переполнение опять новость.
  const ctx2 = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });
  await ctx2.route('**/*', (route) => {
    const u = route.request().url();
    if (/firestore|firebase|googleapis|gstatic|nominatim/.test(u)) return route.abort();
    for (const [f, re] of [['react.js',/react@18\/umd\/react\.production/],['react-dom.js',/react-dom@18/],['babel.js',/babel\.min\.js/],['tailwind.js',/cdn\.tailwindcss/]])
      if (re.test(u)) return route.fulfill({ body: fs.readFileSync(path.join(LIBS, f)), contentType: 'application/javascript' });
    route.continue();
  });
  await ctx2.addInitScript(() => {
    localStorage.setItem('cf_room', 'quota-room');
    localStorage.setItem('cf_user_name', 'Тест');
    localStorage.setItem('cf_light_warned', '1');   // как будто раньше не влезало
    localStorage.setItem('cf_references', JSON.stringify([{ id: 'r1', url: 'x', label: '', tags: [], folder: '' }]));
  });
  const page3 = await ctx2.newPage();
  await page3.goto(`http://127.0.0.1:${PORT}/index.html`);
  await page3.waitForFunction(() => window.__CF_APP_OK, { timeout: 90000 });
  await page3.waitForTimeout(2500);
  const cleared = await page3.evaluate(() => localStorage.getItem('cf_light_warned'));
  ok('проект снова влез целиком — флаг снят, будущее переполнение опять новость',
     cleared === null, String(cleared));

  await browser.close(); server.kill();
  console.log(bad ? `\n${bad} проверок не прошло` : '\nВсё прошло');
  process.exit(bad ? 1 : 0);
})().catch(e => { console.error(e); server.kill(); process.exit(1); });
