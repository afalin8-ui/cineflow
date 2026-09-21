// Печать гайда: документ, а не простыня.
//
// Проверять это чтением кода бесполезно по двум причинам, и обе уже
// стоили ошибок. Первая: разбор текста на заголовки, списки и абзацы
// живёт в JS, а как он ляжет на лист — в CSS, и сойтись они обязаны
// в браузере. Вторая, важнее: печатных правил у нас ДВА МЕСТА —
// `@media print` в самом приложении и `PRINT_PAGE_CSS` для отдельной
// страницы печати на iPad, — и расходятся они молча. Так и вышло
// с маркерами списка: на отдельной странице они рисовались, а в самом
// приложении preflight Tailwind снимает у ul/ol и маркер, и отступ,
// и список печатался голыми строками. Ошибок при этом нет никаких,
// а увидит это тот, кому гайд уже отправили.
//
// Что гоняем: гайд разбирается (заголовок · маркированный список ·
// нумерованный · абзацы) и НИ ОДНА строка не пропадает; шапка
// (надзаголовок · название · линейка · мета) одна у всех экспортов;
// печатные стили действуют в самом приложении, с маркерами и шириной
// строки около восьмидесяти знаков.
//
// Запуск:  node tests/docprint-e2e.js
const fs = require('fs'), os = require('os'), path = require('path');
const { execSync, spawn } = require('child_process');
const ROOT = path.resolve(__dirname, '..');
const LIBS = process.env.CF_LIBS || path.join(os.tmpdir(), 'cineflow-libs');
const PORT = process.env.CF_PORT || '8136';
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
  const p = path.join(LIBS, f);
  if (!fs.existsSync(p) || fs.statSync(p).size < 1000) execSync(`curl -sSL -o "${p}" "${u}"`);
}
const server = spawn('python3', ['-m', 'http.server', PORT, '--bind', '127.0.0.1'], { cwd: ROOT, stdio: 'ignore' });
let bad = 0;
const ok = (n, c, d) => { console.log((c ? '  ok  ' : '  FAIL') + ' ' + n + (d ? ' — ' + d : '')); if (!c) bad++; };

// Обычный гайд: разделы прописными, подводка с двоеточием, оба вида
// списков и абзац в две строки.
const GUIDE = [
  'ЭКСПОЗИЦИЯ И ЗАМЕР', '',
  'Ключ ставим по лицу, тень держим не глубже трёх стопов.',
  'Иначе на градации уйдёт в шум.', '',
  'Порядок замера:',
  '- замер по ключу, точка — скула героя;',
  '- фон держим на два стопа ниже лица.', '',
  'СВЕТ НА ИНТЕРЬЕРАХ', '',
  '1. Окна затягиваем ND 0.6.',
  '2. Практики в кадре — лампы 2700K.', '',
  'ЭТО ВАЖНО.'
].join('\n');

(async () => {
  await new Promise(r => setTimeout(r, 1200));
  const browser = await playwright.chromium.launch({ executablePath: process.env.CF_CHROME || '/opt/pw-browsers/chromium', args: ['--no-sandbox'] });
  // Service worker БЛОКИРУЕМ: иначе на втором заходе он отдаёт запросы
  // мимо подмены библиотек и лезет за ними в интернет — страница
  // остаётся без React, пустая и без единой ошибки.
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 }, serviceWorkers: 'block' });
  await ctx.route('**/*', route => {
    const u = route.request().url();
    // Настоящий Firebase ЗАБЛОКИРОВАН: иначе стенд писал бы в проект пользователя.
    if (/firestore|firebase|googleapis|gstatic|nominatim/.test(u)) return route.abort();
    for (const [f, re] of [['react.js', /react@18\/umd\/react\.production/], ['react-dom.js', /react-dom@18/],
                           ['babel.js', /babel\.min\.js/], ['tailwind.js', /cdn\.tailwindcss/]])
      if (re.test(u)) return route.fulfill({ body: fs.readFileSync(path.join(LIBS, f)), contentType: 'application/javascript' });
    route.continue();
  });
  await ctx.addInitScript((body) => {
    localStorage.setItem('cf_room', 'dp-room');
    localStorage.setItem('cf_user_name', 'Тест');
    localStorage.setItem('cf_docs', JSON.stringify([{ id: 'doc-1', title: 'Гайд по свету', content: body }]));
    localStorage.setItem('cf_scenes', JSON.stringify([{ id: 'scene-1', number: '12А', title: 'ИНТ. КАБИНЕТ — ДЕНЬ',
      date: '2026-07-03', content: 'Герой входит и садится у окна.', gear: {}, lightGear: {} }]));
    localStorage.setItem('cf_crew', JSON.stringify([{ id: 'cr-1', name: 'А. Фалин', role: 'Оператор-постановщик', phone: '+7 900 000-00-00' }]));
    // Печать перехватываем и забираем разметку ПРЯМО В ОБРАБОТЧИКЕ:
    // сразу после window.print приложение опустошает #print-area —
    // собирается он только под печать и в памяти не висит.
    window.print = () => { const a = document.getElementById('print-area'); window.__printHTML = a ? a.innerHTML : ''; };
  }, GUIDE);
  const page = await ctx.newPage();
  const errs = [];
  page.on('pageerror', e => errs.push(String(e).slice(0, 200)));
  await page.goto(`http://127.0.0.1:${PORT}/index.html`);
  await page.waitForFunction(() => window.__CF_APP_OK, { timeout: 180000 });
  await page.waitForTimeout(1000);

  // Идём тем же путём, что человек: «Экспликации» → «Печать и экспорт».
  await page.evaluate(async () => {
    const b = [...document.querySelectorAll('button')].find(x => /Эксплик/i.test((x.textContent || '') + (x.title || '')));
    if (b) b.click();
    await new Promise(r => setTimeout(r, 700));
    const p = [...document.querySelectorAll('button')].find(x => /Печать и экспорт/.test(x.textContent || ''));
    if (p) p.click();
    await new Promise(r => setTimeout(r, 400));
  });
  const printBy = async (sel) => {
    await page.evaluate(() => { window.__printHTML = ''; });
    // Кнопку печати гайда ищем ПО ПОДСКАЗКЕ: по тексту «Гайд…» первой
    // попадается одноимённая строка списка слева, и нажатие уходит в неё.
    await page.evaluate((s) => { const el = document.querySelector(s) || [...document.querySelectorAll('button')].find(b => new RegExp(s).test(b.textContent || '')); el.click(); }, sel);
    await page.waitForFunction(() => window.__printHTML !== '', { timeout: 20000 }).catch(() => {});
    return page.evaluate(() => window.__printHTML || '');
  };

  const doc = await printBy('button[title^="Печать: "]');
  ok('гайд: шапка документа собралась',
     /class="print-head"/.test(doc) && /print-eyebrow/.test(doc) && /print-title/.test(doc) && /print-meta/.test(doc));
  ok('гайд: заголовки разделов, оба списка и абзацы',
     (doc.match(/print-h"/g) || []).length === 2 && /<ul class="print-list"/.test(doc) && /<ol class="print-list"/.test(doc)
     && (doc.match(/print-p"/g) || []).length >= 3,
     `h:${(doc.match(/print-h"/g) || []).length} p:${(doc.match(/print-p"/g) || []).length}`);
  // «ЭТО ВАЖНО.» — прописными, но с точкой: это фраза, а не заголовок.
  ok('строка с точкой заголовком не считается', !/print-h">ЭТО ВАЖНО\./.test(doc));
  const lost = GUIDE.split('\n').map(l => l.replace(/^\s*[-–—•*+]\s+|^\s*\d{1,2}[.)]\s+/, '').trim())
                    .filter(Boolean).filter(l => !doc.includes(l));
  ok('ни одна строка гайда не пропала', lost.length === 0, lost.join(' | '));

  const gear = await printBy('Список техники');
  ok('техника: та же шапка', /class="print-head"/.test(gear) && /Список техники/.test(gear) && /Техника и свет/.test(gear));
  const full = await printBy('Весь план');
  ok('весь план: та же шапка, содержимое цело',
     /class="print-head"/.test(full) && /План подготовки/.test(full) && /12А/.test(full) && /А\. Фалин/.test(full));

  // ГЛАВНОЕ: стили действуют в САМОМ приложении, а не только на
  // отдельной странице печати. Замер идёт ВНУТРИ window.print —
  // сразу после него печатать уже нечего.
  await page.emulateMedia({ media: 'print' });
  await page.evaluate(() => {
    window.print = () => {
      const q = (s) => document.querySelector('#print-area ' + s);
      const fs2 = (el) => el ? Math.round(parseFloat(getComputedStyle(el).fontSize)) : 0;
      const d = q('.print-doc'), li = q('.print-list li');
      window.__m = { title: fs2(q('.print-title')), head: fs2(q('.print-h')), body: fs2(q('.print-p')),
                     w: d ? Math.round(d.getBoundingClientRect().width) : 0,
                     marker: li ? getComputedStyle(li.parentElement).listStyleType : '',
                     rule: q('.print-head') ? getComputedStyle(q('.print-head')).borderBottomWidth : '' };
    };
  });
  await page.evaluate(() => { document.querySelector('button[title^="Печать: "]').click(); });
  await page.waitForTimeout(1500);
  const m = await page.evaluate(() => window.__m || {});
  ok('в приложении: заголовок крупнее текста, линейка на месте',
     m.title >= 26 && m.head > m.body && m.body >= 14 && m.rule === '1px', JSON.stringify(m));
  ok('в приложении: у списка есть маркер (preflight его снимает)', m.marker === 'disc', m.marker);
  ok('строка не во всю ширину листа — около восьмидесяти знаков', m.w > 400 && m.w < 700, String(m.w));

  if (errs.length) ok('без ошибок в консоли', false, errs.join(' | '));
  console.log(bad ? `\nПЛОХО: ${bad}` : '\nВсё сошлось');
  await browser.close(); server.kill(); process.exit(bad ? 1 : 0);
})().catch(e => { console.error(e); server.kill(); process.exit(1); });
