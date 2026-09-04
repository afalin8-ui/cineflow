// Сквозная проверка видео-референсов в Chromium (Playwright).
// Что делает: поднимает приложение локально, БЛОКИРУЕТ Firebase (иначе тест
// писал бы в настоящий проект), подменяет Dropbox поддельным сервером
// (с одним нарочно потерянным ответом на кусок), записывает тестовый ролик
// прямо в браузере и гоняет весь путь: узнавание файла → постер → кодек →
// отправка кусками → карточка с меткой в галерее → полноэкранный просмотр
// с плеером и кнопкой «Стоп-кадр» → совместимая копия (MediaRecorder).
//
// Запуск:  node tests/video-e2e.js
// Нужны: node 18+, playwright (глобальный или локальный), Chromium
// (путь в CF_CHROME, по умолчанию /opt/pw-browsers/chromium), python3
// для статического сервера и curl для библиотек с CDN (кладутся в tmp).
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execSync, spawn } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const LIBS = process.env.CF_LIBS || path.join(os.tmpdir(), 'cineflow-libs');
const PORT = process.env.CF_PORT || '8093';
const CHROME = process.env.CF_CHROME || '/opt/pw-browsers/chromium';
let playwright;
try { playwright = require('playwright'); }
catch (e) { playwright = require(execSync('npm root -g').toString().trim() + '/playwright'); }

const LIB_URLS = {
  'react.js': 'https://unpkg.com/react@18/umd/react.production.min.js',
  'react-dom.js': 'https://unpkg.com/react-dom@18/umd/react-dom.production.min.js',
  'babel.js': 'https://unpkg.com/@babel/standalone/babel.min.js',
  'tailwind.js': 'https://cdn.tailwindcss.com',
  'xlsx.js': 'https://cdnjs.cloudflare.com/ajax/libs/xlsx/0.18.5/xlsx.full.min.js'
};
fs.mkdirSync(LIBS, { recursive: true });
for (const [f, u] of Object.entries(LIB_URLS)) {
  const p = path.join(LIBS, f);
  if (!fs.existsSync(p) || fs.statSync(p).size < 1000) execSync(`curl -sSL -o "${p}" "${u}"`);
}

const server = spawn('python3', ['-m', 'http.server', PORT, '--bind', '127.0.0.1'], { cwd: ROOT, stdio: 'ignore' });
const log = (...a) => console.log(...a);
let failed = 0;
const expect = (name, ok, info) => { log((ok ? '  ok  ' : '  FAIL') + ' ' + name + (info ? ' — ' + info : '')); if (!ok) failed++; };

(async () => {
  await new Promise(r => setTimeout(r, 800));
  const browser = await playwright.chromium.launch({ executablePath: CHROME, args: ['--no-sandbox', '--autoplay-policy=no-user-gesture-required'] });
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  await ctx.addInitScript(() => {
    localStorage.setItem('cf_user_name', 'Тест');
    localStorage.setItem('cf_user_role', 'Оператор');
    localStorage.setItem('cf_room', 'e2e-video-test-room');
    localStorage.setItem('cf_cloud', JSON.stringify({ provider: 'dropbox', token: 'test-token', expires: Date.now() + 36e5, appKey: 'k', folder: 'CineFlow' }));
    localStorage.setItem('cf_share_keys', '0');
    localStorage.setItem('cf_hevc_hint', '1');
  });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push('PAGEERROR ' + String(e).slice(0, 300)));
  await page.route(/gstatic\.com\/firebasejs/, r => r.abort());
  await page.route(/googleapis\.com/, r => r.abort());
  const lib = (re, file) => page.route(re, r => r.fulfill({ path: path.join(LIBS, file), contentType: 'application/javascript' }));
  await lib(/unpkg\.com\/react@18\/umd\/react\.production/, 'react.js');
  await lib(/unpkg\.com\/react-dom@18/, 'react-dom.js');
  await lib(/unpkg\.com\/@babel\/standalone/, 'babel.js');
  await lib(/cdn\.tailwindcss\.com/, 'tailwind.js');
  await lib(/cdnjs\.cloudflare\.com\/ajax\/libs\/xlsx/, 'xlsx.js');

  // Поддельный Dropbox: сессия кусками, один раз «ответ потерялся» (409 incorrect_offset)
  const dbx = { calls: [], sessionBytes: 0, once409: true };
  await page.route(/dropboxapi\.com/, async (route) => {
    const req = route.request(); const url = req.url();
    const arg = req.headers()['dropbox-api-arg'] || '';
    const body = req.postDataBuffer(); const len = body ? body.length : 0;
    dbx.calls.push({ url, len });
    const json = (o, status = 200) => route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(o) });
    if (url.endsWith('/files/upload')) return json({ path_lower: '/cineflow/' + JSON.parse(arg).path.split('/').pop() });
    if (url.endsWith('/upload_session/start')) { dbx.sessionBytes = len; return json({ session_id: 'sess-1' }); }
    if (url.endsWith('/upload_session/append_v2')) {
      const a = JSON.parse(arg);
      if (a.cursor.offset !== dbx.sessionBytes) return json({ error_summary: 'incorrect_offset', error: { '.tag': 'incorrect_offset', correct_offset: dbx.sessionBytes } }, 409);
      dbx.sessionBytes += len;
      if (dbx.once409) { dbx.once409 = false; return json({ error_summary: 'incorrect_offset', error: { '.tag': 'incorrect_offset', correct_offset: dbx.sessionBytes } }, 409); }
      return json({});
    }
    if (url.endsWith('/upload_session/finish')) { const a = JSON.parse(arg); if (a.cursor.offset !== dbx.sessionBytes) return json({ error_summary: 'bad offset' }, 409); return json({ path_lower: a.commit.path.toLowerCase() }); }
    if (url.endsWith('/create_shared_link_with_settings')) { const a = JSON.parse(req.postData()); return json({ url: 'https://www.dropbox.com/scl/fi/abc/' + a.path.split('/').pop() + '?rlkey=r&dl=0' }); }
    return json({}, 404);
  });

  await page.goto(`http://127.0.0.1:${PORT}/index.html`, { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => window.__CF_APP_OK === 1, null, { timeout: 180000 });
  await page.waitForTimeout(2000);
  log('Приложение собралось');

  const unit = await page.evaluate(async () => {
    const mk = (name, type) => new File([new Uint8Array([1, 2, 3])], name, { type });
    const box = (type, payload) => { const b = new Uint8Array(8 + payload.length); new DataView(b.buffer).setUint32(0, b.length); for (let i = 0; i < 4; i++) b[4 + i] = type.charCodeAt(i); b.set(payload, 8); return b; };
    const cat = (...xs) => { const o = new Uint8Array(xs.reduce((s, x) => s + x.length, 0)); let p = 0; xs.forEach(x => { o.set(x, p); p += x.length; }); return o; };
    const str4 = (s) => new Uint8Array([...s].map(c => c.charCodeAt(0)));
    const stsd = box('stsd', cat(new Uint8Array([0, 0, 0, 0, 0, 0, 0, 1]), box('hvc1', new Uint8Array(70))));
    const hdlr = box('hdlr', cat(new Uint8Array(8), str4('vide'), new Uint8Array(13)));
    const moov = box('moov', box('trak', box('mdia', cat(hdlr, box('minf', box('stbl', stsd))))));
    const mp4 = new File([cat(box('ftyp', cat(str4('qt  '), new Uint8Array(4))), box('mdat', new Uint8Array(5000)), moov)], 'clip.mov', { type: 'video/quicktime' });
    return {
      isVideo: [isVideoFile(mk('a.MOV', '')), isVideoFile(mk('a.mp4', 'video/mp4')), isVideoFile(mk('a.jpg', 'image/jpeg'))],
      isImage: [isImageFile(mk('a.heic', '')), isImageFile(mk('a.mov', 'video/quicktime'))],
      fmtDur: [fmtDur(42), fmtDur(725), fmtDur(3790)],
      cloudName: [cloudFileName('r', 'clip.MOV'), cloudFileName('r', 'Вставлено', 'video/quicktime'), cloudFileName('r', 'x', '')],
      codec: await mp4CodecOf(mp4),
      blankLen: blankPoster('x.mov', 16 / 9).length
    };
  });
  expect('isVideoFile по типу и расширению', JSON.stringify(unit.isVideo) === '[true,true,false]', JSON.stringify(unit.isVideo));
  expect('isImageFile', JSON.stringify(unit.isImage) === '[true,false]');
  expect('fmtDur', JSON.stringify(unit.fmtDur) === '["0:42","12:05","1:03:10"]', JSON.stringify(unit.fmtDur));
  expect('cloudFileName с расширением по типу', JSON.stringify(unit.cloudName) === '["r.mov","r.mov","r.jpg"]', JSON.stringify(unit.cloudName));
  expect('mp4CodecOf читает hvc1 из stsd', unit.codec && unit.codec.video === 'hvc1', JSON.stringify(unit.codec));
  expect('blankPoster рисуется', unit.blankLen > 3000, String(unit.blankLen));

  // Тестовый ролик пишется в самом браузере
  const clip = await page.evaluate(async () => {
    const cv = document.createElement('canvas'); cv.width = 640; cv.height = 360; const g = cv.getContext('2d');
    const stream = cv.captureStream(25);
    const ac = new AudioContext(); const osc = ac.createOscillator(); const dest = ac.createMediaStreamDestination(); osc.connect(dest); osc.start();
    dest.stream.getAudioTracks().forEach(t => stream.addTrack(t));
    const rec = new MediaRecorder(stream, { mimeType: 'video/webm;codecs=vp8,opus' });
    const chunks = []; rec.ondataavailable = e => chunks.push(e.data);
    const done = new Promise(res => rec.onstop = res);
    rec.start(200);
    const t0 = performance.now();
    await new Promise(res => { const tick = () => { const t = (performance.now() - t0) / 1000; g.fillStyle = `hsl(${(t * 120) % 360},70%,45%)`; g.fillRect(0, 0, 640, 360); g.fillStyle = '#fff'; g.font = '48px sans-serif'; g.fillText(t.toFixed(1), 40, 200); if (t < 2.6) requestAnimationFrame(tick); else res(); }; tick(); });
    rec.stop(); await done; osc.stop(); ac.close();
    const blob = new Blob(chunks, { type: 'video/webm' });
    window.__clip = new File([blob], 'clip.webm', { type: 'video/webm' });
    return await new Promise(res => { const r = new FileReader(); r.onloadend = () => res(r.result.split(',')[1]); r.readAsDataURL(blob); });
  });

  const assets = await page.evaluate(async () => {
    const a = await makeVideoAssets(window.__clip);
    let proxy = null, perr = '';
    try { const p = await makeVideoProxy(window.__clip, {}); proxy = { size: p.blob.size, mime: p.mime, silent: p.silent }; } catch (e) { perr = String(e && e.message || e); }
    return { posterOk: /^data:image\/jpeg/.test(a.url), dur: a.dur, ar: a.ar, proxy, perr };
  });
  expect('постер снимается из файла', assets.posterOk);
  expect('длительность и пропорция известны', assets.dur > 2 && Math.abs(assets.ar - 1.778) < 0.01, JSON.stringify([assets.dur, assets.ar]));
  expect('совместимая копия собирается', assets.proxy && assets.proxy.size > 10000, assets.perr || JSON.stringify(assets.proxy));

  const up = await page.evaluate(async () => {
    const cfg = JSON.parse(localStorage.getItem('cf_cloud'));
    const ticks = [];
    const r = await dropboxUpload(cfg, new File([new Uint8Array(40 * 1024 * 1024)], 'big.mp4', { type: 'video/mp4' }), 'ref-big.mp4', (s, t) => ticks.push([s, t]));
    return { r, ticks };
  });
  const appends = dbx.calls.filter(c => c.url.endsWith('append_v2')).length;
  expect('Dropbox кусками: сессия, повтор после потерянного ответа, финиш', /raw=1/.test(up.r.full) && appends >= 3 && up.ticks[up.ticks.length - 1][0] === 40 * 1024 * 1024, JSON.stringify({ appends, last: up.ticks[up.ticks.length - 1] }));

  // Сквозной путь через галерею
  await page.click('button[title="Галерея"]');
  await page.waitForTimeout(600);
  const input = (await page.$$('input[type=file][accept*="video"]'))[0];
  expect('плитка выбора принимает видео', !!input);
  await input.setInputFiles({ name: 'clip.webm', mimeType: 'video/webm', buffer: Buffer.from(clip, 'base64') });
  await page.waitForTimeout(6000);
  const saved = await page.evaluate(() => JSON.parse(localStorage.getItem('cf_references') || '[]').filter(r => r.video)[0] || null);
  expect('карточка видео записана с постером, тегом и ссылкой', saved && /^data:image\/jpeg/.test(saved.url) && saved.tags.includes('видео') && /raw=1/.test(saved.full), saved ? JSON.stringify({ dur: saved.dur, size: saved.size, full: saved.full }) : 'нет записи');
  const badge = await page.evaluate(() => Array.from(document.querySelectorAll('.cf-ref-card span')).map(s => s.textContent).find(t => /^▶ \d/.test(t)));
  expect('метка ▶ на карточке галереи', !!badge, badge);
  await (await page.$('.cf-ref-card img')).click();
  await page.waitForTimeout(1500);
  const lb = await page.evaluate(() => { const v = document.querySelector('video'); return { hasVideo: !!v, src: v ? (v.currentSrc || v.getAttribute('src') || '') : '', controls: v ? v.controls : null, playsInline: v ? v.playsInline : null, still: !!Array.from(document.querySelectorAll('button')).find(b => /Стоп-кадр/.test(b.textContent)) }; });
  expect('в просмотре штатный плеер с адресом из облака', lb.hasVideo && lb.controls && lb.playsInline && /raw=1/.test(lb.src), JSON.stringify(lb));
  expect('кнопка «Стоп-кадр» на месте', lb.still);
  expect('ошибок страницы нет', errors.length === 0, errors.join(' | '));

  await browser.close();
  server.kill();
  log(failed ? `\nПРОВАЛОВ: ${failed}` : '\nВсё прошло');
  process.exit(failed ? 1 : 0);
})().catch(e => { console.error('Тест упал:', e); server.kill(); process.exit(1); });
