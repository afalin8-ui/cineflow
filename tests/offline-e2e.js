// Запуск без интернета: service worker обязан открыть приложение из копии
// на устройстве, когда сеть МОЛЧИТ или ползёт, а не ждать её минуту.
// Совсем без сети отказ приходит сразу, и беды там не видно, — поэтому
// сервер здесь свой и умеет три вещи: отвечать, молчать (соединение есть,
// ответа нет — Wi-Fi без интернета, одна палка) и отдавать медленно.
// Плюс обратная проверка: правка приложения приезжает сразу, а не через
// запуск, иначе «быстро из кэша» означало бы «вечно старая версия».
const fs = require('fs'), os = require('os'), path = require('path'), http = require('http');
const { execSync } = require('child_process');
const ROOT = path.resolve(__dirname, '..'), LIBS = process.env.CF_LIBS || path.join(os.tmpdir(), 'cineflow-libs'), PORT = 8163;
let playwright;
try { playwright = require('playwright'); } catch (e) { playwright = require(execSync('npm root -g').toString().trim() + '/playwright'); }
const LIB_URLS = {
  'react.js': 'https://unpkg.com/react@18/umd/react.production.min.js',
  'react-dom.js': 'https://unpkg.com/react-dom@18/umd/react-dom.production.min.js',
  'babel.js': 'https://cdn.jsdelivr.net/npm/@babel/standalone@7/babel.min.js',
  'tailwind.js': 'https://cdn.tailwindcss.com'
};
fs.mkdirSync(LIBS, { recursive: true });
for (const [f, u] of Object.entries(LIB_URLS)) if (!fs.existsSync(path.join(LIBS, f))) execSync(`curl -sSL -o ${path.join(LIBS, f)} ${u}`);

let bad = 0;
const ok = (n, c, d) => { console.log((c ? '  ok  ' : '  FAIL') + ' ' + n + (d ? ' — ' + d : '')); if (!c) bad++; };

// ---- свой сервер: 'ok' · 'hang' · 'slow' · 'down'
let MODE = 'ok', PAGE_TAIL = '';
const hung = new Set();
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'application/javascript', '.json': 'application/json',
               '.svg': 'image/svg+xml', '.webmanifest': 'application/manifest+json', '.css': 'text/css' };
const pageBody = () => Buffer.concat([fs.readFileSync(path.join(ROOT, 'index.html')), Buffer.from(PAGE_TAIL)]);
const server = http.createServer((req, res) => {
  let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  if (p.endsWith('/')) p += 'index.html';
  if (process.env.CF_DEBUG) console.log('    req', MODE, p, req.headers['if-none-match'] || '');
  const isPage = p === '/index.html';
  if (MODE === 'down') return req.socket.destroy();          // как «нет сети»: отказ сразу
  if (isPage && MODE === 'hang') { hung.add(res); return; }  // соединение есть, ответа нет
  if (isPage) {
    const body = pageBody(), etag = '"' + require('crypto').createHash('md5').update(body).digest('hex') + '"';
    if (req.headers['if-none-match'] === etag) { res.writeHead(304, { etag }); return res.end(); }
    res.writeHead(200, { 'content-type': MIME['.html'], etag, 'cache-control': 'max-age=600' });
    if (MODE !== 'slow') return res.end(body);
    let i = 0;                                               // 200 КБ/с
    const tick = setInterval(() => {
      if (res.destroyed || i >= body.length) { clearInterval(tick); return res.end(); }
      res.write(body.subarray(i, i + 20000)); i += 20000;
    }, 100);
    return;
  }
  const f = path.join(ROOT, p);
  if (!f.startsWith(ROOT) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { 'content-type': MIME[path.extname(f)] || 'application/octet-stream' });
  res.end(fs.readFileSync(f));
}).listen(PORT, '127.0.0.1');
const setMode = m => { MODE = m; if (m !== 'hang') { hung.forEach(r => r.socket && r.socket.destroy()); hung.clear(); } };

(async () => {
  const browser = await playwright.chromium.launch({ executablePath: '/opt/pw-browsers/chromium', args: ['--no-sandbox'] });
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true, serviceWorkers: 'allow' });
  // Библиотеки — подменой; Firebase — пустой заглушкой (настоящий проект не трогаем).
  await ctx.route('**/*', route => {
    const u = route.request().url();
    if (u.startsWith(`http://127.0.0.1:${PORT}`)) return route.continue();
    for (const [f, re] of [['react.js', /react@18[.0-9]*\/umd\/react\.production/], ['react-dom.js', /react-dom@18/], ['babel.js', /babel\.min\.js/], ['tailwind.js', /cdn\.tailwindcss/]])
      if (re.test(u)) return route.fulfill({ body: fs.readFileSync(path.join(LIBS, f)), contentType: 'application/javascript', headers: { 'access-control-allow-origin': '*' } });
    route.fulfill({ body: '', contentType: 'application/javascript', headers: { 'access-control-allow-origin': '*' } });
  });
  await ctx.addInitScript(() => { localStorage.setItem('cf_room', 'offline-room'); localStorage.setItem('cf_user_name', 'Тест'); });
  let page = await ctx.newPage();
  const errs = [];
  const open = async (fresh) => {
    if (fresh) { const old = page; page = await ctx.newPage(); old.close().catch(() => {}); }
    page.on('pageerror', e => errs.push(String(e).slice(0, 200)));
    const t0 = Date.now();
    try {
      await page.goto(`http://127.0.0.1:${PORT}/`, { waitUntil: 'commit', timeout: 40000 });
      await page.waitForFunction(() => window.__CF_APP_OK && document.querySelector('header, .cf-tabbar'), null, { timeout: 40000 });
      return (Date.now() - t0) / 1000;
    } catch (e) { return Infinity; }
  };
  const s = t => isFinite(t) ? t.toFixed(1) + ' с' : 'не открылось за 40 с';

  const first = await open(false);
  ok('первый запуск со связью', isFinite(first), s(first));
  await page.waitForFunction(() => navigator.serviceWorker && navigator.serviceWorker.controller, null, { timeout: 30000 }).catch(() => {});
  await page.waitForTimeout(2500);
  const ctl = await page.evaluate(() => !!navigator.serviceWorker.controller);
  ok('service worker управляет страницей', ctl);

  const warm = await open(true);
  ok('повторный запуск со связью — быстро', warm < 2.5, s(warm));

  setMode('hang');
  const hang = await open(true);
  ok('сеть молчит — открывается из копии, а не висит', hang < 6, s(hang));

  setMode('down');
  const down = await open(true);
  ok('сети нет совсем — открывается сразу', down < 2.5, s(down));

  // Правка приложения приезжает при ПЕРВОМ же запуске со связью.
  setMode('ok');
  PAGE_TAIL = '\n<!-- cf-offline-test-v2 -->\n';
  const upd = await open(true);
  const fresh = await page.evaluate(() => new XMLSerializer().serializeToString(document).includes('cf-offline-test-v2'));
  ok('со связью приезжает свежая версия, а не копия', isFinite(upd) && fresh, s(upd));
  // И она же легла в копию: без сети открывается уже новая.
  setMode('down');
  await open(true);
  const kept = await page.evaluate(() => new XMLSerializer().serializeToString(document).includes('cf-offline-test-v2'));
  ok('свежая версия легла в копию на устройстве', kept);

  // Медленная связь (страница изменилась, 304 не будет): открываемся из копии,
  // а обновление не теряется: оно доезжает в фоне и открывается в следующий раз.
  setMode('slow');
  PAGE_TAIL = '\n<!-- cf-offline-test-v3 -->\n';
  const slow = await open(true);
  ok('медленная связь — не ждёт два мегабайта целиком', slow < 6, s(slow));
  const v3now = await page.evaluate(() => new XMLSerializer().serializeToString(document).includes('cf-offline-test-v3'));
  await page.waitForTimeout(13000);                         // страница доезжает за ~11 с
  setMode('down');
  await open(true);
  const v3next = await page.evaluate(() => new XMLSerializer().serializeToString(document).includes('cf-offline-test-v3'));
  ok('на медленной связи открылась копия, а обновление дописалось в фоне', !v3now && v3next, `сразу: ${v3now}, в следующий раз: ${v3next}`);

  ok('без ошибок на странице', errs.length === 0, errs.slice(0, 3).join(' | '));
  await browser.close(); server.close();
  console.log(bad ? `\n${bad} провал(ов)` : '\nвсё прошло');
  process.exit(bad ? 1 : 0);
})();
