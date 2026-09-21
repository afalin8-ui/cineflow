// Ctrl+V: один кадр — одна карточка.
//
// Chrome кладёт вставленную картинку И в clipboardData.files, И в items,
// причём это РАЗНЫЕ объекты File: у файла из буфера своего времени нет,
// и lastModified каждому проставляется в момент создания — у второго он
// на миллисекунду больше. Пока это время входило в ключ проверки дублей,
// каждый Ctrl+V на компьютере клал в галерею ДВА одинаковых кадра.
// На iPad не видно вовсе: там files при вставке пуст, и потому «у меня
// всё нормально» ничего не значит — проверять надо обоими источниками.
//
// Стендом это ловится только так: настоящим событием paste с двумя
// разными File на одно изображение. Второй проверкой идёт обратное —
// две РАЗНЫЕ картинки обязаны лечь двумя карточками, иначе защита
// от дублей съедала бы нормальную пачку.
//
// Запуск:  node tests/paste-e2e.js
const fs = require('fs'), os = require('os'), path = require('path');
const { execSync, spawn } = require('child_process');
const ROOT = require('path').resolve(__dirname, '..'), LIBS = path.join(os.tmpdir(), 'cineflow-libs'), PORT = '8142';
let playwright;
try { playwright = require('playwright'); } catch (e) { playwright = require(execSync('npm root -g').toString().trim() + '/playwright'); }
const server = spawn('python3', ['-m','http.server',PORT,'--bind','127.0.0.1'], { cwd: ROOT, stdio: 'ignore' });
(async () => {
  await new Promise(r => setTimeout(r, 1200));
  const browser = await playwright.chromium.launch({ executablePath: '/opt/pw-browsers/chromium', args: ['--no-sandbox'] });
  const ctx = await browser.newContext({ viewport: {width: 1280, height: 900}, serviceWorkers: 'block' });
  await ctx.route('**/*', route => {
    const u = route.request().url();
    if (/firestore|firebase|googleapis|gstatic|nominatim/.test(u)) return route.abort();
    for (const [f, re] of [['react.js',/react@18\/umd\/react\.production/],['react-dom.js',/react-dom@18/],['babel.js',/babel\.min\.js/],['tailwind.js',/cdn\.tailwindcss/]])
      if (re.test(u)) return route.fulfill({ body: fs.readFileSync(path.join(LIBS, f)), contentType: 'application/javascript' });
    route.continue();
  });
  await ctx.addInitScript(() => {
    localStorage.setItem('cf_room', 'pst-room');
    localStorage.setItem('cf_user_name', 'Тест');
    localStorage.setItem('cf_references', '[]');
  });
  const page = await ctx.newPage();
  await page.goto(`http://127.0.0.1:${PORT}/index.html`);
  await page.waitForFunction(() => window.__CF_APP_OK, { timeout: 180000 });
  await page.waitForTimeout(900);
  await page.evaluate(async () => {
    const b = [...document.querySelectorAll('.cf-tabbar button, header button')].find(x => /Галере/i.test((x.textContent||'') + (x.title||'')));
    if (b) b.click();
    await new Promise(r => setTimeout(r, 700));
  });
  let bad = 0;
  const ok = (n, c, d) => { console.log((c ? '  ok  ' : '  FAIL') + ' ' + n + (d ? ' — ' + d : '')); if (!c) bad++; };
  const res = await page.evaluate(async () => {
    // Рисуем настоящий PNG, чтобы дошло до сжатия.
    const cv = document.createElement('canvas'); cv.width = 40; cv.height = 30;
    const g = cv.getContext('2d'); g.fillStyle = '#c33'; g.fillRect(0, 0, 40, 30);
    const blob = await new Promise(r => cv.toBlob(r, 'image/png'));
    const buf = await blob.arrayBuffer();
    // Два РАЗНЫХ объекта File с одним содержимым — ровно то, что отдаёт
    // Chrome: один в .files, другой из items.getAsFile().
    const a = new File([buf], 'image.png', { type: 'image/png', lastModified: 1000 });
    const b = new File([buf], 'image.png', { type: 'image/png', lastModified: 2000 });
    const dt = { files: [a], items: [{ kind: 'file', type: 'image/png', getAsFile: () => b }], getData: () => '' };
    const ev = new Event('paste', { bubbles: true });
    Object.defineProperty(ev, 'clipboardData', { value: dt });
    document.dispatchEvent(ev);
    await new Promise(r => setTimeout(r, 2500));
    return document.querySelectorAll('.cf-ref-card').length;
  });
  ok('один Ctrl+V — одна карточка', res === 1, 'карточек: ' + res);

  // Обратная проверка: пачка из двух РАЗНЫХ картинок ложится целиком.
  const res2 = await page.evaluate(async () => {
    const mk = async (w, h, color) => {
      const cv = document.createElement('canvas'); cv.width = w; cv.height = h;
      const g = cv.getContext('2d'); g.fillStyle = color; g.fillRect(0, 0, w, h);
      const blob = await new Promise(r => cv.toBlob(r, 'image/png'));
      return new File([await blob.arrayBuffer()], 'image.png', { type: 'image/png', lastModified: 1 });
    };
    const a = await mk(40, 30, '#3c3'), b = await mk(64, 48, '#33c');
    const dt = { files: [a, b], items: [{ kind: 'file', type: 'image/png', getAsFile: () => a },
                                        { kind: 'file', type: 'image/png', getAsFile: () => b }], getData: () => '' };
    const ev = new Event('paste', { bubbles: true });
    Object.defineProperty(ev, 'clipboardData', { value: dt });
    document.dispatchEvent(ev);
    await new Promise(r => setTimeout(r, 3000));
    return document.querySelectorAll('.cf-ref-card').length;
  });
  ok('две разные картинки — две карточки', res2 === 3, 'стало всего: ' + res2);
  console.log(bad ? `\nПЛОХО: ${bad}` : '\nВсё сошлось');
  await browser.close(); server.kill(); process.exit(bad ? 1 : 0);
})().catch(e => { console.error(e); server.kill(); process.exit(1); });
