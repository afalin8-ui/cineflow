// Не врёт ли картинка, пройдя через загрузку в приложение.
//
// Всё, что кладут в проект, пересобирается: картинка распаковывается,
// уменьшается и пересохраняется в jpeg. На этом пути молча портятся
// три вещи, и все три замечает не тот, кто грузил, а тот, кому потом
// отправили отчёт:
//   1. ЦВЕТ — если где-то потеряется профиль или канва окажется
//      в другом пространстве, терракота станет кирпичом;
//   2. ПРОЗРАЧНОСТЬ — jpeg её не умеет, и без белой подложки
//      прозрачный фон становится ЧЁРНЫМ;
//   3. ПОВОРОТ — фотография с телефона снята «боком», а как её
//      держали, написано в EXIF; не примени его — кадр ляжет на бок.
// Ошибок ни в одном случае нет, поэтому читать код бесполезно:
// проверяется это только замером пикселей после настоящей загрузки.
//
// Запуск:  node tests/color-e2e.js
const fs = require('fs'), os = require('os'), path = require('path');
const { execSync, spawn } = require('child_process');
const ROOT = path.resolve(__dirname, '..');
const LIBS = process.env.CF_LIBS || path.join(os.tmpdir(), 'cineflow-libs');
const PORT = process.env.CF_PORT || '8146';
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
(async () => {
  await new Promise(r => setTimeout(r, 1200));
  const browser = await playwright.chromium.launch({ executablePath: process.env.CF_CHROME || '/opt/pw-browsers/chromium', args: ['--no-sandbox'] });
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 }, serviceWorkers: 'block' });
  await ctx.route('**/*', route => {
    const u = route.request().url();
    if (/firestore|firebase|googleapis|gstatic|nominatim/.test(u)) return route.abort();
    for (const [f, re] of [['react.js', /react@18\/umd\/react\.production/], ['react-dom.js', /react-dom@18/],
                           ['babel.js', /babel\.min\.js/], ['tailwind.js', /cdn\.tailwindcss/]])
      if (re.test(u)) return route.fulfill({ body: fs.readFileSync(path.join(LIBS, f)), contentType: 'application/javascript' });
    route.continue();
  });
  await ctx.addInitScript(() => {
    localStorage.setItem('cf_room', 'color-room');
    localStorage.setItem('cf_user_name', 'Тест');
    localStorage.setItem('cf_references', '[]');
  });
  const page = await ctx.newPage();
  const errs = [];
  page.on('pageerror', e => errs.push(String(e).slice(0, 200)));
  await page.goto(`http://127.0.0.1:${PORT}/index.html`);
  await page.waitForFunction(() => window.__CF_APP_OK, { timeout: 180000 });
  await page.waitForTimeout(900);
  await page.evaluate(async () => {
    const b = [...document.querySelectorAll('.cf-tabbar button, header button')].find(x => /Галере/i.test((x.textContent || '') + (x.title || '')));
    if (b) b.click();
    await new Promise(r => setTimeout(r, 700));
  });

  // Общая дверь: кладём файл настоящим событием вставки и забираем
  // то, что легло в проект.
  const put = async (make, name) => page.evaluate(async ([src, nm]) => {
    const file = await (new Function('return ' + src))()(nm);
    const dt = { files: [file], items: [], getData: () => '' };
    const ev = new Event('paste', { bubbles: true });
    Object.defineProperty(ev, 'clipboardData', { value: dt });
    document.dispatchEvent(ev);
    await new Promise(r => setTimeout(r, 3500));
    const refs = JSON.parse(localStorage.getItem('cf_references') || '[]');
    const ref = refs.find(r => (r.file || '') === nm);
    if (!ref) return { err: 'кадр не лёг' };
    const img = new Image();
    await new Promise(r => { img.onload = r; img.onerror = r; img.src = ref.url; });
    const cv = document.createElement('canvas'); cv.width = img.naturalWidth; cv.height = img.naturalHeight;
    const g = cv.getContext('2d', { willReadFrequently: true }); g.drawImage(img, 0, 0);
    const at = (fx, fy) => { const d = g.getImageData(Math.round(fx * img.naturalWidth), Math.round(fy * img.naturalHeight), 1, 1).data; return [d[0], d[1], d[2], d[3]]; };
    return { w: img.naturalWidth, h: img.naturalHeight, at: [at(.125, .25), at(.375, .25), at(.625, .25), at(.875, .25),
                                                              at(.125, .75), at(.375, .75), at(.625, .75), at(.875, .75)],
             corner: { lt: at(.02, .04), rt: at(.97, .04) } };
  }, [make, name]);

  // ---- 1. ЦВЕТ: восемь плашек, среди них терракота приложения
  const COLORS = [[217,119,87],[122,157,107],[70,130,180],[224,172,142],[128,128,128],[255,0,0],[0,0,0],[255,255,255]];
  const mkColors = `(nm) => (async () => {
    const C = ${JSON.stringify(COLORS)};
    const cv = document.createElement('canvas'); cv.width = 800; cv.height = 400;
    const g = cv.getContext('2d');
    C.forEach((c, i) => { g.fillStyle = 'rgb(' + c.join(',') + ')'; g.fillRect((i % 4) * 200, Math.floor(i / 4) * 200, 200, 200); });
    const b = await new Promise(r => cv.toBlob(r, 'image/png'));
    return new File([await b.arrayBuffer()], nm, { type: 'image/png', lastModified: 1 });
  })()`;
  const col = await put(mkColors, 'colors.png');
  const worst = col.err ? 999 : Math.max(...col.at.map((g, i) => Math.max(Math.abs(g[0]-COLORS[i][0]), Math.abs(g[1]-COLORS[i][1]), Math.abs(g[2]-COLORS[i][2]))));
  ok('цвет держится (отклонение ≤ 4 из 255)', worst <= 4, 'худшее: ' + worst);

  // ---- 2. ПРОЗРАЧНОСТЬ: jpeg её не умеет, фон обязан стать БЕЛЫМ, не чёрным
  const mkAlpha = `(nm) => (async () => {
    const cv = document.createElement('canvas'); cv.width = 400; cv.height = 200;
    const g = cv.getContext('2d');
    g.clearRect(0, 0, 400, 200);
    g.fillStyle = '#d97757'; g.fillRect(150, 60, 100, 80);
    const b = await new Promise(r => cv.toBlob(r, 'image/png'));
    return new File([await b.arrayBuffer()], nm, { type: 'image/png', lastModified: 2 });
  })()`;
  const alpha = await put(mkAlpha, 'alpha.png');
  const bgPix = alpha.err ? [0,0,0] : alpha.at[0];
  ok('прозрачный фон стал белым, а не чёрным', bgPix[0] > 240 && bgPix[1] > 240 && bgPix[2] > 240, String(bgPix.slice(0, 3)));

  // ---- 3. ПОВОРОТ: EXIF Orientation = 6 («держали вертикально»)
  const mkTurn = `(nm) => (async () => {
    const cv = document.createElement('canvas'); cv.width = 800; cv.height = 400;
    const g = cv.getContext('2d');
    g.fillStyle = '#c33'; g.fillRect(0, 0, 800, 400);
    g.fillStyle = '#3c3'; g.fillRect(0, 0, 120, 60);
    const b = await new Promise(r => cv.toBlob(r, 'image/jpeg', 0.92));
    const raw = new Uint8Array(await b.arrayBuffer());
    const app1 = [0xFF,0xE1,0x00,0x22, 0x45,0x78,0x69,0x66,0x00,0x00,
                  0x49,0x49, 0x2A,0x00, 0x08,0x00,0x00,0x00,
                  0x01,0x00, 0x12,0x01, 0x03,0x00, 0x01,0x00,0x00,0x00, 0x06,0x00,0x00,0x00,
                  0x00,0x00,0x00,0x00];
    const out = new Uint8Array(raw.length + app1.length);
    out.set(raw.subarray(0, 2), 0); out.set(app1, 2); out.set(raw.subarray(2), 2 + app1.length);
    return new File([out], nm, { type: 'image/jpeg', lastModified: 3 });
  })()`;
  const turn = await put(mkTurn, 'turn.jpg');
  ok('снимок «боком» развёрнут по EXIF', !turn.err && turn.h > turn.w, turn.err || `${turn.w}x${turn.h}`);
  const rt = turn.err ? [0,0,0] : turn.corner.rt;
  ok('развёрнут в ту сторону (метка ушла вправо вверх)', rt[1] > 150 && rt[0] < 120, String(rt.slice(0, 3)));

  if (errs.length) ok('без ошибок в консоли', false, errs.join(' | '));
  console.log(bad ? `\nПЛОХО: ${bad}` : '\nВсё сошлось');
  await browser.close(); server.kill(); process.exit(bad ? 1 : 0);
})().catch(e => { console.error(e); server.kill(); process.exit(1); });
