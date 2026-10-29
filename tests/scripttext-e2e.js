// Текст сцены из PDF — без «лесенки»; номер «1-10» в одну строку; имя
// файла не показывается подписью кадра.
//
// Планшет 1280: сценарий с переносами на ширине листа показан склеенным
// абзацем — в поле, в свёрнутом виде, в КПП «Все сцены»; правка в поле
// сохраняет склеенный текст; номер «1-10» в списке стоит одной строкой;
// на ленте референсов «Screenshot ….png» не подписан, «точка А» подписана.
// Склейка проверяется и напрямую: реплики, ремарки, списки и абзацы
// из Word остаются как были. Телефон 390: то же в свёрнутом и
// развёрнутом тексте и в списке.
//
// Запуск:  node tests/scripttext-e2e.js
const fs = require('fs'), os = require('os'), path = require('path');
const { execSync, spawn } = require('child_process');
const ROOT = path.resolve(__dirname, '..');
const LIBS = process.env.CF_LIBS || path.join(os.tmpdir(), 'cineflow-libs');
const PORT = process.env.CF_PORT || '8176';
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

// Ровно то, что пришло из PDF на iPad: строки листа по 50–58 знаков.
const WRAPPED = [
  'Солнце очерчивает невысокие постройки военного аэродрома.',
  'Ветер полощет яркий вымпел на флагштоке. Вращается антенна',
  'радиовышки. Фигуры молодых курсантов раскручивают',
  'товарищей на лопингах - скрипучих круговых качелях.',
  'ГОЛОС',
  '(по-корейски)',
  '10. 9. 8. 7. 6. 5. 4...',
  'ГОЛОСА',
  '(по-корейски)',
  'Смотри, смотри! Летят!',
  'Все оборачиваются в сторону высокого холма за аэродромом.',
  'Курсанты спрыгивают с лопингов. Показывают',
  'руками в небо.'
].join('\n');
const FLAT = [
  'Солнце очерчивает невысокие постройки военного аэродрома. Ветер полощет яркий вымпел на флагштоке. Вращается антенна радиовышки. Фигуры молодых курсантов раскручивают товарищей на лопингах - скрипучих круговых качелях.',
  'ГОЛОС',
  '(по-корейски)',
  '10. 9. 8. 7. 6. 5. 4...',
  'ГОЛОСА',
  '(по-корейски)',
  'Смотри, смотри! Летят!',
  'Все оборачиваются в сторону высокого холма за аэродромом. Курсанты спрыгивают с лопингов. Показывают руками в небо.'
].join('\n');
const img = (a) => 'data:image/svg+xml;base64,' + Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="640" height="360"><rect width="640" height="360" fill="${a}"/></svg>`).toString('base64');
const SCENES = [
  { id: 's1', number: '1-10', title: 'НАТ. АЭРОДРОМ. ТРЕНИРОВОЧНАЯ ПЛОЩАДКА. ДЕНЬ', date: '2099-11-01', content: '', script: WRAPPED, gear: {}, lightGear: {}, lightSchemeId: null },
  { id: 's2', number: '2', title: 'НАТ. АЭРОДРОМ. ВПП. ДЕНЬ', date: '2099-11-01', content: '', script: '', gear: {}, lightGear: {}, lightSchemeId: null },
  { id: 's3', number: '1-12', title: 'НЕБО. ДЕНЬ', date: '2099-11-01', content: '', script: '', gear: {}, lightGear: {}, lightSchemeId: null }
];
const REFS = [
  { id: 'r1', url: img('#556'), label: 'Screenshot 2026-04-21 110215.png', tags: [], folder: '', sceneId: 's1', locationId: '' },
  { id: 'r2', url: img('#655'), label: 'точка А · с обрыва', file: 'IMG_1.jpg', tags: [], folder: '', sceneId: 's1', locationId: '' }
];

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
    await ctx.addInitScript(([sc, rf]) => {
      if (sessionStorage.getItem('__seeded')) return;
      sessionStorage.setItem('__seeded', '1');
      localStorage.setItem('cf_room', 'scripttext-room-test-0001');
      localStorage.setItem('cf_user_name', 'Тест');
      localStorage.setItem('cf_scene_mode', 'creative');
      localStorage.setItem('cf_scenes', JSON.stringify(sc));
      localStorage.setItem('cf_references', JSON.stringify(rf));
    }, [SCENES, REFS]);
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
  // Высота колонки номера в строке: одна строка текста — меньше 26 точек.
  const numH = (page, id) => page.evaluate((id) => { const row = document.querySelector(`[data-cf="scene-row"][data-id="${id}"]`); const sp = row && row.querySelector('span'); const r = sp && sp.getBoundingClientRect(); return r ? { h: r.height, w: r.width, t: sp.textContent } : null; }, id);
  const sceneOf = (page, id) => page.evaluate((id) => (JSON.parse(localStorage.getItem('cf_scenes') || '[]').find(x => x.id === id) || null), id);

  console.log('Планшет 1280');
  {
    const { page, errs, ctx } = await mk({ width: 1280, height: 900 });
    const n1 = await numH(page, 's1'), n3 = await numH(page, 's3');
    ok('номера «1-10» и «1-12» в списке — одной строкой', n1 && n3 && n1.h < 26 && n3.h < 26 && n1.t === '1-10', JSON.stringify([n1, n3]));
    await tap(page, '[data-cf="scene-row"][data-id="s1"]', 'строка #1-10');
    await page.waitForTimeout(1000);
    const rec = await sceneOf(page, 's1');
    ok('при открытии сцены склеенный текст лёг В ЗАПИСЬ (один раз)', rec && rec.script === FLAT, JSON.stringify(rec && rec.script).slice(0, 120));
    const field = await page.evaluate(() => { const t = document.querySelector('[data-cf="scene-script"]'); return t ? t.value : null; });
    ok('в поле текст склеен в абзацы, реплики и ремарки на своих строках', field === FLAT, JSON.stringify(field).slice(0, 200));
    // Сравниваем с ТЕМ ЖЕ источником в ТОМ ЖЕ поле, а не с «13 строк»:
    // строк у склеенного текста столько, сколько даёт ширина колонки
    // и кегль, и после подъёма шкалы (29.10.2026) их стало 14 при
    // прежних 13 у источника — лесенка при этом никуда не вернулась.
    const lines = await page.evaluate((raw) => {
      const t = document.querySelector('[data-cf="scene-script"]'); if (!t) return null;
      const lh = parseFloat(getComputedStyle(t).fontSize) * 1.7;
      const c = t.cloneNode(false); c.removeAttribute('data-cf'); c.style.height = 'auto'; c.style.position = 'absolute'; c.style.visibility = 'hidden';
      c.style.width = t.getBoundingClientRect().width + 'px'; c.value = raw; t.parentElement.appendChild(c);
      const rawLines = Math.round(c.scrollHeight / lh); c.remove();
      return { now: Math.round(t.getBoundingClientRect().height / lh), raw: rawLines };
    }, WRAPPED);
    ok('лесенки нет: склеенный текст в поле ниже, чем тот же источник с переносами листа', !!lines && lines.now > 0 && lines.now < lines.raw, JSON.stringify(lines));
    await tap(page, '[data-cf="scene-text-fold"]', '«свернуть»');
    const shut = await page.evaluate(() => { const d = document.querySelector('[data-cf="scene-script-shut"]'); return d ? d.textContent : null; });
    ok('свёрнутый вид — тот же склеенный текст', shut === FLAT);
    await tap(page, '[data-cf="scene-script-shut"]', 'свёрнутый текст');
    // правка в поле сохраняет склеенный текст
    const t = page.locator('[data-cf="scene-script"]');
    await t.click(); await page.keyboard.press('Control+End'); await page.keyboard.type(' X');
    await page.waitForTimeout(1000);
    const saved = await sceneOf(page, 's1');
    ok('после правки в записи лежит склеенный текст с правкой, пробел не съеден', saved && saved.script === FLAT + ' X', JSON.stringify(saved && saved.script).slice(-60));
    // Разорвать строку перед словом со строчной буквы — можно: пока курсор в поле, склейка не вмешивается.
    await page.keyboard.press('Enter'); await page.keyboard.type('новая строка');
    await page.waitForTimeout(1000);
    const split = await sceneOf(page, 's1');
    ok('разрыв строки перед строчной буквой при наборе остаётся', split && split.script.endsWith(' X\nновая строка'), JSON.stringify(split && split.script).slice(-40));
    await page.keyboard.press('Shift+Home'); await page.keyboard.press('Backspace'); await page.keyboard.press('Backspace');
    await page.waitForTimeout(1000);
    ok('убрали добавленное — запись прежняя', (await sceneOf(page, 's1')).script === FLAT + ' X', JSON.stringify((await sceneOf(page, 's1')).script).slice(-40));
    ok('другие сцены не тронуты', (await sceneOf(page, 's2')).script === '');
    // подписи референсов
    const caps = await page.evaluate(() => [...document.querySelectorAll('.cf-overlay')].map(e => e.textContent.trim()).filter(Boolean));
    ok('«Screenshot ….png» на карточке не подписан, «точка А» подписана', !caps.some(c => /\.png$/i.test(c)) && caps.includes('точка А · с обрыва'), JSON.stringify(caps));
    // КПП «Все сцены»
    await page.evaluate(() => { const b = [...document.querySelectorAll('header button')].find(x => /КПП/i.test((x.textContent || '') + (x.title || ''))); b && b.click(); });
    await page.waitForTimeout(700);
    await page.evaluate(() => { const b = [...document.querySelectorAll('button')].find(x => /^Все сцены$/.test((x.textContent || '').trim())); b && b.click(); });
    await page.waitForTimeout(700);
    await page.evaluate(() => { const b = [...document.querySelectorAll('button')].find(x => /текст сцены/i.test(x.textContent || '') && !/КПП/.test(x.textContent || '')); b && b.click(); });
    await page.waitForTimeout(500);
    const quote = await page.evaluate(() => { const q = document.querySelector('.cf-quote'); return q ? q.textContent : null; });
    ok('КПП «Все сцены» показывает склеенный текст', quote === FLAT + ' X', JSON.stringify(quote).slice(0, 120));
    // склейка напрямую: что обязано остаться как было
    const u = (txt) => page.evaluate((x) => window.__cfUnwrap(x), txt);
    ok('список короткими строками не склеивается', await u('Свет:\nHMI через окно\nпанели сверху') === 'Свет:\nHMI через окно\nпанели сверху');
    const shots = 'Общий план двора, камера на кране опускается.\nСредний план Ивана у окна, панорама влево.\nКрупный план рук на столе, статика.';
    ok('список кадров — по фразе на строке с точками — не склеивается', await u(shots) === shots, JSON.stringify(await u(shots)));
    const typed = Array.from({ length: 6 }, (_, i) => `Строка ${i + 1}. Она стоит у окна и смотрит во двор.`).join('\n');
    ok('набранные руками фразы одной длины не склеиваются', await u(typed) === typed);
    ok('перенос внутри абзаца Word (короткие строки) остаётся', await u('Сноска\nпосле переноса') === 'Сноска\nпосле переноса');
    const dlg = 'ИВАН\nЯ же говорил тебе, что нельзя так\nделать, это опасно.\nИван отворачивается и смотрит в окно, за которым\nидёт дождь.';
    ok('реплика в узкой колонке склеивается, имя героя — нет', await u(dlg) === 'ИВАН\nЯ же говорил тебе, что нельзя так делать, это опасно.\nИван отворачивается и смотрит в окно, за которым идёт дождь.', JSON.stringify(await u(dlg)));
    const long = 'Он долго смотрит на неё и не говорит ни слова, а потом разворачивается и уходит по коридору, не оглядываясь, к лифту в конце этажа.\nОна остаётся стоять у окна, за которым идёт дождь.';
    ok('абзацы из Word одной строкой каждый — не склеиваются', await u(long) === long);
    const two = WRAPPED.split('\n').slice(0, 4).join('\n') + '\n\n' + WRAPPED.split('\n').slice(10).join('\n');
    ok('пустая строка между абзацами сохраняется, каждый абзац склеен', await u(two) === FLAT.split('\n')[0] + '\n\n' + FLAT.split('\n')[7]);
    ok('текст без переносов не меняется', await u('Одна строка.') === 'Одна строка.');
    ok('без ошибок на планшете', errs.length === 0, errs.join(' | '));
    await ctx.close();
  }

  console.log('Телефон 390');
  {
    const { page, errs, ctx } = await mk({ width: 390, height: 844 });
    const n1 = await numH(page, 's1');
    ok('на телефоне номер «1-10» одной строкой', n1 && n1.h < 26 && /1-10$/.test(n1.t), JSON.stringify(n1));
    await tap(page, '[data-cf="scene-row"][data-id="s1"]', 'строка #1-10');
    const clamp = await page.evaluate(() => { const b = [...document.querySelectorAll('button')].find(x => /развернуть →/.test(x.textContent || '')); const p = b && b.previousElementSibling; return p ? p.textContent : null; });
    ok('свёрнутый текст на телефоне склеен', clamp === FLAT, JSON.stringify(clamp).slice(0, 120));
    await page.evaluate(() => { const b = [...document.querySelectorAll('button')].find(x => /развернуть →/.test(x.textContent || '')); b && b.click(); });
    await page.waitForTimeout(400);
    const field = await page.evaluate(() => { const t = document.querySelector('[data-cf="phone-scene-script"]'); return t ? t.value : null; });
    ok('развёрнутое поле на телефоне — склеенный текст', field === FLAT);
    const caps = await page.evaluate(() => [...document.querySelectorAll('.cf-overlay')].map(e => e.textContent.trim()).filter(Boolean));
    ok('на телефоне имя файла тоже не подписано', !caps.some(c => /\.png$/i.test(c)), JSON.stringify(caps));
    ok('без ошибок на телефоне', errs.length === 0, errs.join(' | '));
    await ctx.close();
  }

  await browser.close(); server.kill();
  console.log(bad ? `\n${bad} проверок не прошло` : '\nВсё прошло');
  process.exit(bad ? 1 : 0);
})().catch(e => { console.error(e); server.kill(); process.exit(1); });
