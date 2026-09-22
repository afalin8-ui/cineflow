// Голосовая заметка: гайд и заметки с выезда.
//
// Проверять это чтением кода бесполезно: путь идёт через микрофон,
// MediaRecorder, Web Audio и запрос к ИИ, и каждое звено у браузеров
// СВОЁ. Safari пишет mp4/aac, Chrome — webm/opus, а модель принимает
// не всё подряд — поэтому записанное мы сами переводим в wav 16 кГц
// моно. Если это звено сломается, ошибки не будет: кнопка просто
// скажет «не удалось расшифровать», и виноватым будет выглядеть ИИ.
//
// Микрофон настоящий — Chromium запускается с синтетическим
// устройством, то есть MediaRecorder пишет по-настоящему, и wav
// собирается из настоящего звука. Подделан только ИИ: перехват
// смотрит, что ушло (audio/wav и непустые данные), и отвечает текстом.
//
// Что гоняем: в гайде кнопка есть → нажатие пишет, вторая
// останавливает → в запрос ушёл wav → текст дописался в конец гайда,
// и гайд развернулся → в заметках с выезда голосом рождается заметка
// у объекта → без связи запись не начинается и об этом сказано →
// у гостя по ссылке кнопки нет вовсе.
//
// Запуск:  node tests/voice-e2e.js
const fs = require('fs'), os = require('os'), path = require('path');
const { execSync, spawn } = require('child_process');
const ROOT = path.resolve(__dirname, '..');
const LIBS = process.env.CF_LIBS || path.join(os.tmpdir(), 'cineflow-libs');
const PORT = process.env.CF_PORT || '8151';
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
const SAID = 'Ставим кей на журавль, тень не глубже трёх стопов.';

(async () => {
  await new Promise(r => setTimeout(r, 1200));
  const browser = await playwright.chromium.launch({
    executablePath: process.env.CF_CHROME || '/opt/pw-browsers/chromium',
    // Микрофон синтетический, разрешение выдаётся само: настоящий
    // getUserMedia, настоящая запись, настоящий wav.
    args: ['--no-sandbox', '--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream']
  });
  const mk = async (query) => {
    const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 }, serviceWorkers: 'block',
                                           permissions: ['microphone'] });
    await ctx.route('**/*', route => {
      const u = route.request().url();
      // Настоящий Firebase ЗАБЛОКИРОВАН: иначе стенд писал бы в проект пользователя.
      if (/firestore|firebase|googleapis\.com\/(identitytoolkit|securetoken)|gstatic/.test(u)) return route.abort();
      for (const [f, re] of [['react.js', /react@18\/umd\/react\.production/], ['react-dom.js', /react-dom@18/],
                             ['babel.js', /babel\.min\.js/], ['tailwind.js', /cdn\.tailwindcss/]])
        if (re.test(u)) return route.fulfill({ body: fs.readFileSync(path.join(LIBS, f)), contentType: 'application/javascript' });
      route.continue();
    });
    // Поддельный ИИ: смотрим, ЧТО ушло, и отвечаем текстом.
    await ctx.route(/generativelanguage\.googleapis\.com/, async (route) => {
      let body = {};
      try { body = JSON.parse(route.request().postData() || '{}'); } catch (e) {}
      const part = ((body.contents || [])[0] || {}).parts || [];
      const inline = (part.find(x => x.inline_data) || {}).inline_data || {};
      const seen = { mime: inline.mime_type || '', kb: Math.round((inline.data || '').length * 0.75 / 1024),
                     sys: ((body.systemInstruction || {}).parts || [{}])[0].text || '' };
      await route.fulfill({ contentType: 'application/json',
        headers: { 'x-cf-seen': Buffer.from(JSON.stringify(seen)).toString('base64') },
        body: JSON.stringify({ candidates: [{ content: { parts: [{ text: '  ' + SAID + '\n' }] } }] }) });
    });
    await ctx.addInitScript(() => {
      localStorage.setItem('cf_room', 'voice-room');
      localStorage.setItem('cf_user_name', 'Тест');
      localStorage.setItem('cf_gemini_key', 'AIza-test-key');
      localStorage.setItem('cf_docs', JSON.stringify([{ id: 'doc-1', title: 'Гайд по свету', content: 'ЭКСПОЗИЦИЯ' }]));
      localStorage.setItem('cf_locations', JSON.stringify([{ id: 'loc-1', name: 'Двор школы', address: '', coords: '55.75, 37.61',
                                                             description: '', sceneIds: [], order: 1 }]));
      localStorage.setItem('cf_stickies', '[]');
    });
    const page = await ctx.newPage();
    const errs = [];
    const seen = [];
    page.on('pageerror', e => errs.push(String(e).slice(0, 200)));
    page.on('response', r => { const h = r.headers()['x-cf-seen']; if (h) seen.push(JSON.parse(Buffer.from(h, 'base64').toString())); });
    await page.goto(`http://127.0.0.1:${PORT}/index.html${query || ''}`);
    await page.waitForFunction(() => window.__CF_APP_OK, { timeout: 180000 });
    await page.waitForTimeout(900);
    return { page, errs, seen, ctx };
  };
  const goDocs = (page) => page.evaluate(async () => {
    const b = [...document.querySelectorAll('.cf-tabbar button, header button')].find(x => /Эксплик/i.test((x.textContent || '') + (x.title || '')));
    if (b) b.click();
    await new Promise(r => setTimeout(r, 800));
  });

  // ---- ГАЙД
  const { page, errs, seen } = await mk();
  await goDocs(page);
  const has = await page.evaluate(() => {
    const b = document.querySelector('[data-cf="voice-start"]');
    if (!b) return { there: false };
    const r = b.getBoundingClientRect();
    const hit = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
    return { there: true, hits: !!(hit && (hit === b || b.contains(hit))), h: Math.round(r.height) };
  });
  ok('в гайде есть кнопка «Надиктовать» и в неё попадает нажатие', has.there && has.hits, JSON.stringify(has));
  await page.click('[data-cf="voice-start"]');
  await page.waitForSelector('[data-cf="voice-stop"]', { timeout: 15000 });
  const recLabel = await page.textContent('[data-cf="voice-stop"]');
  ok('пошла запись, на кнопке время', /Стоп/.test(recLabel || ''), (recLabel || '').trim());
  await page.waitForTimeout(2200);
  await page.click('[data-cf="voice-stop"]');
  await page.waitForFunction((txt) => {
    const d = JSON.parse(localStorage.getItem('cf_docs') || '[]')[0] || {};
    return String(d.content || '').includes(txt.slice(0, 20));
  }, SAID, { timeout: 60000 }).catch(() => {});
  const doc = await page.evaluate(() => JSON.parse(localStorage.getItem('cf_docs') || '[]')[0] || {});
  ok('надиктованное дописалось В КОНЕЦ гайда, прежний текст цел',
     /ЭКСПОЗИЦИЯ/.test(doc.content || '') && (doc.content || '').trim().endsWith('стопов.'), JSON.stringify((doc.content || '').slice(0, 80)));
  const ask = seen[seen.length - 1] || {};
  ok('в ИИ ушёл настоящий wav, а не пустышка', ask.mime === 'audio/wav' && ask.kb > 10, JSON.stringify(ask.mime) + ' ' + ask.kb + ' КБ');
  ok('и просьба НЕ переводить язык', /НЕ переводи/.test(ask.sys || ''), (ask.sys || '').slice(0, 40));
  const opened = await page.evaluate(() => {
    const ta = document.querySelector('textarea.cf-doc-body');
    return ta ? ta.scrollHeight - ta.clientHeight <= 4 : false;
  });
  ok('гайд развернулся — видно, что записалось', opened);

  // ---- БЕЗ СВЯЗИ запись не начинается
  const offline = await page.evaluate(async () => {
    Object.defineProperty(navigator, 'onLine', { configurable: true, get: () => false });
    document.querySelector('[data-cf="voice-start"]').click();
    await new Promise(r => setTimeout(r, 600));
    const rec = !!document.querySelector('[data-cf="voice-stop"]');
    const toast = document.body.innerText.match(/Нет связи[^\n]*/);
    Object.defineProperty(navigator, 'onLine', { configurable: true, get: () => true });
    return { rec, said: toast ? toast[0] : '' };
  });
  ok('без связи запись не начинается и об этом сказано', !offline.rec && /расшифровать/.test(offline.said), JSON.stringify(offline));

  // ---- ЗАМЕТКИ С ВЫЕЗДА
  const scout = await page.evaluate(async () => {
    const tab = [...document.querySelectorAll('header button, .cf-tabbar button')].find(x => /Скаут/i.test((x.textContent || '') + (x.title || '')));
    if (tab) tab.click();
    await new Promise(r => setTimeout(r, 1200));
    // В «Плане» своя кнопка заметок, в «Камере» своя — берём ту,
    // что на экране: стенд открывает план.
    const notes = [...document.querySelectorAll('[data-cf="scout-notes-plan"], [data-cf="scout-notes-open"]')].find(x => x.offsetParent);
    if (notes) notes.click();
    await new Promise(r => setTimeout(r, 600));
    const b = [...document.querySelectorAll('[data-cf="voice-start"]')].find(x => x.offsetParent);
    if (!b) return { there: false };
    const r = b.getBoundingClientRect();
    const hit = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
    b.click();
    return { there: true, hits: !!(hit && (hit === b || b.contains(hit))) };
  });
  ok('в заметках с выезда кнопка есть и нажимается', scout.there && scout.hits, JSON.stringify(scout));
  if (scout.there) {
    await page.waitForSelector('[data-cf="voice-stop"]:visible', { timeout: 15000 });
    await page.waitForTimeout(2000);
    await page.click('[data-cf="voice-stop"]:visible');
    await page.waitForFunction((txt) => (JSON.parse(localStorage.getItem('cf_stickies') || '[]'))
      .some(s => String(s.text || '').includes(txt.slice(0, 20))), SAID, { timeout: 60000 }).catch(() => {});
    const st = await page.evaluate(() => JSON.parse(localStorage.getItem('cf_stickies') || '[]'));
    ok('заметка родилась сразу со словами и привязана к объекту',
       st.length === 1 && /журавль/.test(st[0].text || '') && st[0].locationId === 'loc-1', JSON.stringify(st.map(x => [x.locationId, (x.text || '').slice(0, 24)])));
  }

  // ---- ГОСТЬ ПО ССЫЛКЕ
  const { page: guest } = await mk('?view=all&room=voice-room');
  await goDocs(guest);
  const guestBtn = await guest.evaluate(() => {
    const b = [...document.querySelectorAll('[data-cf="voice-start"]')][0];
    if (!b) return 'нет вовсе';
    return getComputedStyle(b).display === 'none' ? 'скрыта' : 'ВИДНА';
  });
  ok('у гостя по ссылке кнопки нет', guestBtn !== 'ВИДНА', guestBtn);

  if (errs.length) ok('без ошибок в консоли', false, errs.join(' | '));
  console.log(bad ? `\nПЛОХО: ${bad}` : '\nВсё сошлось');
  await browser.close(); server.kill(); process.exit(bad ? 1 : 0);
})().catch(e => { console.error(e); server.kill(); process.exit(1); });
