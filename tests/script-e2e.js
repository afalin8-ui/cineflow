// Сценарий из PDF и Word: «Агент КПП» → «Выбрать сценарий».
//
// Файлы настоящие: .docx собирает python-docx, PDF — reportlab с
// кириллическим шрифтом (заголовок сцены в нём лежит ДВУМЯ кусками,
// как у программ вёрстки сценариев: склеить строку обязаны мы). Плюс
// скан без текста и старый .doc — они обязаны не молчать, а сказать,
// что делать. pdf.js берётся с CDN, как в приложении.
//
// Гоняем: файл выбран → окно «Загрузить текст сценария?» нашло три
// сцены → после «Подтвердить» сцены лежат с номерами, названиями и
// текстом (кириллица, «&», «12А», перенос строки в абзаце Word) →
// скан и .doc дают полоску с объяснением, сцен не прибавилось.
//
// Запуск:  node tests/script-e2e.js
const fs = require('fs'), os = require('os'), path = require('path');
const { execSync, spawn } = require('child_process');
const ROOT = path.resolve(__dirname, '..');
const LIBS = process.env.CF_LIBS || path.join(os.tmpdir(), 'cineflow-libs');
const FIX = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-script-'));
const PORT = process.env.CF_PORT || '8163';
let playwright;
try { playwright = require('playwright'); }
catch (e) { playwright = require(execSync('npm root -g').toString().trim() + '/playwright'); }
const LIB_URLS = {
  'react.js': 'https://unpkg.com/react@18/umd/react.production.min.js',
  'react-dom.js': 'https://unpkg.com/react-dom@18/umd/react-dom.production.min.js',
  'babel.js': 'https://cdn.jsdelivr.net/npm/@babel/standalone@7/babel.min.js',
  'tailwind.js': 'https://cdn.tailwindcss.com',
  'pdf.js': 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js',
  'pdf.worker.js': 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js'
};
fs.mkdirSync(LIBS, { recursive: true });
for (const [f, u] of Object.entries(LIB_URLS)) {
  const q = path.join(LIBS, f);
  if (!fs.existsSync(q) || fs.statSync(q).size < 1000) execSync(`curl -sSL -o "${q}" "${u}"`);
}
execSync(`python3 "${path.join(__dirname, 'script-fixtures.py')}" "${FIX}"`);
const server = spawn('python3', ['-m', 'http.server', PORT, '--bind', '127.0.0.1'], { cwd: ROOT, stdio: 'ignore' });
let bad = 0;
const ok = (n, c, d) => { console.log((c ? '  ok  ' : '  FAIL') + ' ' + n + (d ? ' — ' + d : '')); if (!c) bad++; };

(async () => {
  await new Promise(r => setTimeout(r, 1200));
  const browser = await playwright.chromium.launch({
    executablePath: process.env.CF_CHROME || '/opt/pw-browsers/chromium', args: ['--no-sandbox'] });
  const mk = async () => {
    const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 }, serviceWorkers: 'block' });
    await ctx.route('**/*', route => {
      const u = route.request().url();
      // Настоящий Firebase ЗАБЛОКИРОВАН: иначе стенд писал бы в проект пользователя.
      if (/firestore|firebase|googleapis\.com\/(identitytoolkit|securetoken)|gstatic/.test(u)) return route.abort();
      for (const [f, re] of [['react.js', /react@18[.0-9]*\/umd\/react\.production/], ['react-dom.js', /react-dom@18/],
                             ['babel.js', /babel\.min\.js/], ['tailwind.js', /cdn\.tailwindcss/],
                             ['pdf.worker.js', /pdf\.worker\.min\.js/], ['pdf.js', /pdf\.js\/[\d.]+\/pdf\.min\.js/]])
        if (re.test(u)) return route.fulfill({ body: fs.readFileSync(path.join(LIBS, f)), contentType: 'application/javascript',
                                               headers: { 'Access-Control-Allow-Origin': '*' } });
      route.continue();
    });
    await ctx.addInitScript(() => {
      localStorage.setItem('cf_room', 'script-room-test-0001');
      localStorage.setItem('cf_user_name', 'Тест');
      localStorage.setItem('cf_scenes', JSON.stringify([{ id: 'scene-x', number: '1', title: '', content: 'своя экспликация',
                                                          date: '', gear: {}, lightGear: {}, lightSchemeId: null }]));
    });
    const page = await ctx.newPage();
    const errs = [];
    page.on('pageerror', e => errs.push(String(e).slice(0, 200)));
    await page.goto(`http://127.0.0.1:${PORT}/index.html`);
    await page.waitForFunction(() => window.__CF_APP_OK, { timeout: 180000 });
    await page.waitForTimeout(900);
    return { page, errs, ctx };
  };
  const pick = async (page, file) => {
    await page.click('button[title="Проект, доступ, агент КПП"]');
    await page.click('button:has-text("Агент КПП")');
    const inp = page.locator('input[type=file][accept*=".docx"]');
    ok('поле выбора сценария принимает PDF и Word', await inp.count() === 1 &&
       /\.pdf/.test(await inp.getAttribute('accept')), await inp.getAttribute('accept'));
    await inp.setInputFiles(path.join(FIX, file));
  };
  const scenes = (page) => page.evaluate(() => JSON.parse(localStorage.getItem('cf_scenes') || '[]'));
  const { page, errs } = await mk();

  for (const file of ['scenario.docx', 'scenario.pdf']) {
    // Каждый файл — с чистого листа: вторая загрузка легла бы в те же номера.
    await page.evaluate(() => localStorage.setItem('cf_scenes', JSON.stringify([{ id: 'scene-x', number: '1', title: '',
      content: 'своя экспликация', date: '', gear: {}, lightGear: {}, lightSchemeId: null }])));
    await page.reload(); await page.waitForFunction(() => window.__CF_APP_OK, { timeout: 180000 }); await page.waitForTimeout(700);
    await pick(page, file);
    const okBtn = page.locator('[data-cf="confirm-ok"]');
    await okBtn.waitFor({ timeout: 30000 }).catch(() => {});
    const msg = await page.locator('[role="dialog"]').last().innerText().catch(() => '');
    ok(`${file}: найдено три сцены, одна ляжет в существующую`, /Найдено сцен: 3/.test(msg) && /по номеру: 1/.test(msg),
       msg.replace(/\s+/g, ' ').slice(0, 160));
    await okBtn.click().catch(() => {});
    await page.waitForTimeout(1200);
    // Окно обязано закрыться: раньше оно оставалось (обращение к снятой
    // функции после записи), и второе «Подтвердить» заводило сцены заново.
    ok(`${file}: окно закрылось после «Подтвердить»`, await page.locator('[data-cf="confirm-ok"]').count() === 0);
    const list = await scenes(page);
    const by = n => list.find(s => s.number === n) || {};
    ok(`${file}: сцена 1 получила название и текст, экспликация цела`,
       /КВАРТИРА 5А/.test(by('1').title) && /Анна стоит у окна\.\nАННА\nОн не придёт\./.test(by('1').script || '') &&
       by('1').content === 'своя экспликация', JSON.stringify(by('1')).slice(0, 200));
    ok(`${file}: «&» и кириллица на месте`, /Фонари & тени/.test(by('2').script || ''), JSON.stringify(by('2').script));
    ok(`${file}: «12А» найдена как номер`, /КОРИДОР/.test(by('12А').title || ''), JSON.stringify(list.map(s => s.number)));
    if (file.endsWith('.docx'))
      ok('docx: перенос строки внутри абзаца стал переносом', /Сноска\nпосле переноса/.test(by('12А').script || ''), JSON.stringify(by('12А').script));
    else
      ok('pdf: номер страницы не попал ни в заголовок, ни в текст сцены',
         !/\d\.$/.test(by('1').title) && list.every(s => !/^\s*\d+\.?\s*$/m.test(s.script || '')), JSON.stringify(list.map(s => s.script)));
  }

  for (const [file, re] of [['scan.pdf', /скан/], ['old.doc', /старый формат Word/]]) {
    const before = (await scenes(page)).length;
    await pick(page, file);
    const t = await page.waitForFunction((src) => {
      const el = [...document.querySelectorAll('div,span,p')].find(x => new RegExp(src).test(x.textContent || '') && x.children.length < 3);
      return el ? el.textContent : null;
    }, re.source, { timeout: 20000 }).then(h => h.jsonValue()).catch(() => '');
    ok(`${file}: сказано, в чём дело`, re.test(t || ''), (t || '').slice(0, 120));
    ok(`${file}: сцен не прибавилось`, (await scenes(page)).length === before);
    await page.waitForTimeout(500);
  }
  ok('без ошибок на странице', !errs.length, errs.join(' | '));
  await browser.close(); server.kill();
  fs.rmSync(FIX, { recursive: true, force: true });
  console.log(bad ? `\n${bad} FAIL` : '\nвсё ok');
  process.exit(bad ? 1 : 0);
})().catch(e => { console.error(e); server.kill(); process.exit(1); });
