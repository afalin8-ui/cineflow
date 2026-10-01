// Печать в УСТАНОВЛЕННОМ приложении на телефоне: готовый PDF.
//
// Раньше там открывалось отдельное окно с разметкой листа, и на iPhone
// это пустая вкладка без адреса: «Поделиться» делится пустотой,
// «Напечатать» нет, сохранить нечего — с гайдом нельзя сделать НИЧЕГО.
// Теперь лист собирается в настоящий файл PDF, и окно «Готовый PDF»
// отдаёт его системному «Поделиться» (там «Напечатать», «Сохранить
// в Файлы», мессенджеры).
//
// Что гоняем, и всё НАЖАТИЕМ по экрану телефона 390 (elementFromPoint):
// «Экспликации» → «Печать и экспорт» → «Гайд» → окно с ходом сборки →
// «Поделиться» отдал файл PDF → файл открывается НАСТОЯЩИМ разборщиком
// (poppler: pdfinfo, pdftoppm), страниц столько, сколько текста, лист
// A4, страница не пустая, строки не разрезаны ножом (полоса на месте
// реза — фон, а не буквы) → тёмный лист тёмный и на полях → «Скачать»
// отдаёт тот же файл → окно закрывается → без «установленного» режима
// работает обычная печать, а не окно.
//
// Запуск:  node tests/printpdf-e2e.js
const fs = require('fs'), os = require('os'), path = require('path');
const { execSync, spawn } = require('child_process');
const ROOT = path.resolve(__dirname, '..');
const LIBS = process.env.CF_LIBS || path.join(os.tmpdir(), 'cineflow-libs');
const PORT = process.env.CF_PORT || '8137';
const TMP = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-printpdf-'));
let playwright;
try { playwright = require('playwright'); }
catch (e) { playwright = require(execSync('npm root -g').toString().trim() + '/playwright'); }
const LIB_URLS = {
  'react.js': 'https://unpkg.com/react@18/umd/react.production.min.js',
  'react-dom.js': 'https://unpkg.com/react-dom@18/umd/react-dom.production.min.js',
  'babel.js': 'https://cdn.jsdelivr.net/npm/@babel/standalone@7/babel.min.js',
  'tailwind.js': 'https://cdn.tailwindcss.com',
  'html2canvas-pro.js': 'https://cdn.jsdelivr.net/npm/html2canvas-pro@1.6.7/dist/html2canvas-pro.min.js'
};
fs.mkdirSync(LIBS, { recursive: true });
for (const [f, u] of Object.entries(LIB_URLS)) {
  const p = path.join(LIBS, f);
  if (!fs.existsSync(p) || fs.statSync(p).size < 1000) execSync(`curl -sSL -o "${p}" "${u}"`);
}
const server = spawn('python3', ['-m', 'http.server', PORT, '--bind', '127.0.0.1'], { cwd: ROOT, stdio: 'ignore' });
let bad = 0;
const ok = (n, c, d) => { console.log((c ? '  ok  ' : '  FAIL') + ' ' + n + (d ? ' — ' + d : '')); if (!c) bad++; };

// Длинный гайд: разделы, списки и абзацы на несколько страниц.
const GUIDE = [];
for (let k = 1; k <= 9; k++) {
  GUIDE.push(`РАЗДЕЛ ${k}. ЭКСПОЗИЦИЯ И СВЕТ`, '');
  GUIDE.push('Ключ ставим по лицу, тень держим не глубже трёх стопов, иначе на градации уйдёт в шум. ' +
             'Фон держим на два стопа ниже лица, практики в кадре — лампы 2700K, окна затягиваем ND 0.6.', '');
  GUIDE.push('Порядок замера:', '- замер по ключу, точка — скула героя;', '- контровой — по плечу, на стоп выше ключа;',
             '- фон — по самой светлой стене.', '');
  GUIDE.push('1. Проверить баланс белого по серой карте.', '2. Записать диафрагму в КПП.', '');
}
const GUIDE_TEXT = GUIDE.join('\n');

const setup = async (browser, { standalone, dark }) => {
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2,
                                         isMobile: true, hasTouch: true, serviceWorkers: 'block', acceptDownloads: true });
  await ctx.route('**/*', route => {
    const u = route.request().url();
    if (/firestore|firebase|googleapis|gstatic|nominatim/.test(u)) return route.abort();
    for (const [f, re] of [['react.js', /react@18\/umd\/react\.production/], ['react-dom.js', /react-dom@18/],
                           ['babel.js', /babel\.min\.js/], ['tailwind.js', /cdn\.tailwindcss/],
                           ['html2canvas-pro.js', /html2canvas-pro/]])
      if (re.test(u)) return route.fulfill({ body: fs.readFileSync(path.join(LIBS, f)), contentType: 'application/javascript' });
    route.continue();
  });
  await ctx.addInitScript(([body, standalone, dark]) => {
    // Окошко предпросмотра и скрытая вёрстка листа — тоже окна, но не наши.
    if (window !== window.top) return;
    localStorage.setItem('cf_room', 'pp-room');
    localStorage.setItem('cf_user_name', 'Тест');
    localStorage.setItem('cf_project_title', 'Северный свет');
    if (dark) localStorage.setItem('cf_print_theme', 'dark');
    localStorage.setItem('cf_docs', JSON.stringify([{ id: 'doc-1', title: 'Гайд по свету', content: body }]));
    localStorage.setItem('cf_scenes', JSON.stringify([{ id: 'scene-1', number: '1', title: 'ИНТ. КАБИНЕТ — ДЕНЬ',
      date: '2026-07-03', content: '', gear: {}, lightGear: {} }]));
    if (standalone) Object.defineProperty(navigator, 'standalone', { get: () => true });
    window.__printed = 0;
    window.print = () => { window.__printed++; };
    // Системный лист «Поделиться» подменён: запоминаем, ЧТО ему отдали.
    navigator.canShare = (d) => !!(d && d.files && d.files.length);
    navigator.share = (d) => { window.__shared = d.files[0]; return Promise.resolve(); };
    // Имя скачиваемого — по АТРИБУТУ: Chromium в стенде кириллицу
    // в имени загрузки не доносит и отдаёт «download».
    const click = HTMLAnchorElement.prototype.click;
    HTMLAnchorElement.prototype.click = function () { if (this.download) window.__dlName = this.download; return click.call(this); };
  }, [GUIDE_TEXT, standalone, dark]);
  const page = await ctx.newPage();
  const errs = [];
  // Окошко предпросмотра закрыто песочницей (sandbox=""), и заглушка
  // service worker'а, которую стенд вставляет в КАЖДОЕ окно, там падает.
  // Скриптов в окошке нет — это ошибка стенда, а не приложения.
  page.on('pageerror', e => { const m = String(e); if (!/serviceWorker.*sandboxed/.test(m)) errs.push(m.slice(0, 200)); });
  await page.goto(`http://127.0.0.1:${PORT}/index.html`);
  await page.waitForFunction(() => window.__CF_APP_OK, { timeout: 180000 });
  await page.waitForTimeout(800);
  return { ctx, page, errs };
};

// Нажатие по экрану, а не .click() из кода: проверяем, что палец попадает.
const tap = async (page, find, name) => {
  const pt = await page.evaluate((src) => {
    const el = (new Function('return ' + src))()();
    if (!el) return null;
    el.scrollIntoView({ block: 'center' });
    const r = el.getBoundingClientRect();
    const x = r.left + r.width / 2, y = r.top + r.height / 2;
    const hit = document.elementFromPoint(x, y);
    return { x, y, hit: !!hit && (hit === el || el.contains(hit)) };
  }, find.toString());
  ok(name + ': нажатие попадает', !!pt && pt.hit, pt ? '' : 'не найдено');
  if (pt) await page.touchscreen.tap(pt.x, pt.y);
  await page.waitForTimeout(400);
};

const toPrintPanel = async (page) => {
  await tap(page, () => [...document.querySelectorAll('.cf-tabbar button')].find(b => /Ещё/.test(b.textContent)), '«Ещё»');
  await tap(page, () => [...document.querySelectorAll('.cf-sheet button')].find(b => /Эксплик/.test(b.textContent)), '«Экспликации»');
  await tap(page, () => [...document.querySelectorAll('button')].find(b => /Печать и экспорт/.test(b.textContent)), '«Печать и экспорт»');
};

const pdfOf = async (page, key) => {
  const b64 = await page.evaluate(async (k) => {
    const f = window[k]; if (!f) return '';
    const u = new Uint8Array(await f.arrayBuffer());
    let s = ''; for (let i = 0; i < u.length; i += 0x8000) s += String.fromCharCode.apply(null, u.subarray(i, i + 0x8000));
    return btoa(s);
  }, key);
  return b64 ? Buffer.from(b64, 'base64') : null;
};

// Средняя яркость и разброс строки пикселей PPM — «есть ли тут буквы».
const ppm = (file) => {
  const b = fs.readFileSync(file);
  let i = 0, fields = [];
  while (fields.length < 4) {
    while (/\s/.test(String.fromCharCode(b[i]))) i++;
    let s = ''; while (!/\s/.test(String.fromCharCode(b[i]))) s += String.fromCharCode(b[i++]);
    fields.push(s);
  }
  i++;
  const [, w, h] = fields.map(Number);
  const px = b.subarray(i);
  const lum = (x, y) => { const o = (y * w + x) * 3; return (px[o] + px[o + 1] + px[o + 2]) / 3; };
  return { w, h, lum };
};

(async () => {
  await new Promise(r => setTimeout(r, 1200));
  const browser = await playwright.chromium.launch({ executablePath: process.env.CF_CHROME || '/opt/pw-browsers/chromium', args: ['--no-sandbox'] });

  // 1. Светлый лист, установленное приложение.
  {
    const { ctx, page, errs } = await setup(browser, { standalone: true, dark: false });
    await toPrintPanel(page);
    await tap(page, () => document.querySelector('button[title^="Печать: "]'), '«Гайд»');
    const opened = await page.waitForSelector('[data-cf="print-pdf"]', { timeout: 5000 }).then(() => true).catch(() => false);
    ok('окно «Готовый PDF» открылось сразу', opened);
    ok('обычная печать не звалась (в приложении она ничего не делает)', (await page.evaluate(() => window.__printed)) === 0);
    const ready = await page.waitForSelector('[data-cf="print-pdf-share"]', { timeout: 120000 }).then(() => true).catch(() => false);
    ok('PDF собрался', ready, await page.evaluate(() => (document.querySelector('[data-cf="print-pdf-status"]') || {}).textContent));
    await page.screenshot({ path: path.join(TMP, 'sheet.png') });   // посмотреть глазами
    const status = await page.evaluate(() => document.querySelector('[data-cf="print-pdf-status"]').textContent);
    ok('в окне названы файл и число страниц', /Гайд по свету\.pdf · \d+ страниц/.test(status), status);
    await tap(page, () => document.querySelector('[data-cf="print-pdf-share"]'), '«Поделиться»');
    const pdf = await pdfOf(page, '__shared');
    ok('«Поделиться» отдал файл PDF', !!pdf && pdf.slice(0, 5).toString() === '%PDF-', pdf ? pdf.length + ' байт' : 'пусто');
    if (pdf) {
      const f = path.join(TMP, 'light.pdf'); fs.writeFileSync(f, pdf);
      let info = '';
      try { info = execSync(`pdfinfo "${f}" 2>&1`).toString(); } catch (e) { info = String(e.stdout || e); }
      const pages = +((info.match(/Pages:\s+(\d+)/) || [])[1] || 0);
      ok('файл читается настоящим разборщиком', /Pages:/.test(info) && !/Syntax Error|Error/i.test(info), info.split('\n').slice(0, 3).join(' | '));
      ok('лист A4', /595\.28 x 841\.89/.test(info), (info.match(/Page size:.*/) || [''])[0]);
      ok('длинный гайд — несколько страниц', pages >= 3, String(pages));
      ok('название проекта в свойствах файла по-русски', /Title:\s+Гайд по свету/.test(info), (info.match(/Title:.*/) || [''])[0]);
      execSync(`pdftoppm -r 60 "${f}" "${path.join(TMP, 'l')}"`);
      const shots = fs.readdirSync(TMP).filter(n => /^l-\d+\.ppm$/.test(n)).sort();
      let empty = 0, cutThrough = 0;
      shots.forEach((n, idx) => {
        const { w, h, lum } = ppm(path.join(TMP, n));
        let dark = 0;
        for (let y = 0; y < h; y += 2) for (let x = 0; x < w; x += 2) if (lum(x, y) < 120) dark++;
        if (dark < 40) empty++;
        // Шов между страницами: последняя строка поля набора и первая
        // следующей страницы. Буквы на шве = строку разрезали ножом.
        if (idx < shots.length - 1) {
          const m = Math.round(h * 14 / 297), yb = h - m - 1;
          let ink = 0; for (let x = m; x < w - m; x++) if (lum(x, yb) < 140) ink++;
          if (ink > 3) cutThrough++;
        }
      });
      ok('ни одна страница не пустая', empty === 0, `${empty} из ${shots.length}`);
      ok('строки не разрезаны на шве страниц', cutThrough === 0, `${cutThrough} швов с буквами`);
      let text = ''; try { text = execSync(`pdftotext "${f}" - 2>/dev/null`).toString(); } catch (e) {}
      ok('файл без мусорной разметки (страница-картинка)', text.trim().length < 5);
    }
    // «Скачать» — тот же файл.
    const dl = page.waitForEvent('download', { timeout: 8000 }).catch(() => null);
    await tap(page, () => document.querySelector('[data-cf="print-pdf-save"]'), '«Скачать PDF»');
    const d = await dl;
    const head = d ? fs.readFileSync(await d.path()).slice(0, 5).toString() : '';
    const dlName = await page.evaluate(() => window.__dlName || '');
    ok('«Скачать» отдаёт тот же PDF с именем гайда', head === '%PDF-' && dlName === 'Гайд по свету.pdf', head + ' · ' + dlName);
    await tap(page, () => document.querySelector('[data-cf="print-pdf"]').parentElement.querySelector('.cf-modal-x'), 'крестик');
    ok('окно закрывается', !(await page.$('[data-cf="print-pdf"]')));
    if (errs.length) ok('без ошибок в консоли', false, errs.join(' | '));
    await ctx.close();
  }

  // 2. Тёмный лист.
  {
    const { ctx, page, errs } = await setup(browser, { standalone: true, dark: true });
    await toPrintPanel(page);
    await tap(page, () => document.querySelector('button[title^="Печать: "]'), '«Гайд» (тёмный)');
    await page.waitForSelector('[data-cf="print-pdf-share"]', { timeout: 120000 }).catch(() => {});
    await tap(page, () => document.querySelector('[data-cf="print-pdf-share"]'), '«Поделиться» (тёмный)');
    const pdf = await pdfOf(page, '__shared');
    if (pdf) {
      const f = path.join(TMP, 'dark.pdf'); fs.writeFileSync(f, pdf);
      execSync(`pdftoppm -r 40 -f 1 -l 1 "${f}" "${path.join(TMP, 'd')}"`);
      const n = fs.readdirSync(TMP).find(x => /^d-\d+\.ppm$/.test(x));
      const { w, h, lum } = ppm(path.join(TMP, n));
      ok('тёмный лист тёмный и на полях', lum(2, 2) < 40 && lum(w - 3, h - 3) < 40 && lum(w >> 1, h - 3) < 40,
         [lum(2, 2), lum(w - 3, h - 3)].map(Math.round).join(','));
    } else ok('тёмный: файл отдан', false);
    if (errs.length) ok('без ошибок в консоли (тёмный)', false, errs.join(' | '));
    await ctx.close();
  }

  // 3. Обычный браузер: печать как была, окна нет.
  {
    const { ctx, page, errs } = await setup(browser, { standalone: false, dark: false });
    await toPrintPanel(page);
    await tap(page, () => document.querySelector('button[title^="Печать: "]'), '«Гайд» (браузер)');
    await page.waitForFunction(() => window.__printed > 0, { timeout: 15000 }).catch(() => {});
    ok('в браузере зовётся обычная печать', (await page.evaluate(() => window.__printed)) === 1);
    ok('и окна PDF нет', !(await page.$('[data-cf="print-pdf"]')));
    if (errs.length) ok('без ошибок в консоли (браузер)', false, errs.join(' | '));
    await ctx.close();
  }

  console.log('файлы: ' + TMP);
  console.log(bad ? `\nПЛОХО: ${bad}` : '\nВсё сошлось');
  await browser.close(); server.kill(); process.exit(bad ? 1 : 0);
})().catch(e => { console.error(e); server.kill(); process.exit(1); });
