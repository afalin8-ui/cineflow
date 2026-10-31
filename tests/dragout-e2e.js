// Перетаскивание картинок НАРУЖУ: <img> тащится, несёт DownloadURL с именем файла
// и оригиналом из Dropbox, своя картинка обратно в галерею не загружается,
// в режиме «Выбрать» не тащится, в просмотре — тащится, пока кадр не приближен.
const fs = require('fs'), os = require('os'), path = require('path');
const { execSync, spawn } = require('child_process');
const ROOT = path.resolve(__dirname, '..'), LIBS = path.join(os.tmpdir(), 'cineflow-libs'), PORT = '8152';
let playwright;
try { playwright = require('playwright'); } catch (e) { playwright = require(execSync('npm root -g').toString().trim() + '/playwright'); }
const LIB_URLS = {
  'react.js': 'https://unpkg.com/react@18.3.1/umd/react.production.min.js',
  'react-dom.js': 'https://unpkg.com/react-dom@18.3.1/umd/react-dom.production.min.js',
  'babel.js': 'https://unpkg.com/@babel/standalone@7.29.9/babel.min.js',
  'tailwind.js': 'https://cdn.tailwindcss.com/3.4.17'
};
fs.mkdirSync(LIBS, { recursive: true });
for (const [f, u] of Object.entries(LIB_URLS)) if (!fs.existsSync(path.join(LIBS, f))) execSync(`curl -sSL -o ${path.join(LIBS, f)} ${u}`);
const server = spawn('python3', ['-m', 'http.server', PORT, '--bind', '127.0.0.1'], { cwd: ROOT, stdio: 'ignore' });
let bad = 0;
const ok = (n, c, d) => { console.log((c ? '  ok  ' : '  FAIL') + ' ' + n + (d ? ' — ' + d : '')); if (!c) bad++; };
const PX = 'data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==';
(async () => {
  await new Promise(r => setTimeout(r, 1200));
  const browser = await playwright.chromium.launch({ executablePath: '/opt/pw-browsers/chromium', args: ['--no-sandbox'] });
  const mk = async (w, h) => {
    const ctx = await browser.newContext({ viewport: { width: w, height: h }, isMobile: w < 768, hasTouch: w < 900, serviceWorkers: 'block' });
    await ctx.route('**/*', route => {
      const u = route.request().url();
      if (/firestore|firebase|googleapis|gstatic|nominatim/.test(u)) return route.abort();
      for (const [f, re] of [['react.js', /react@18[.0-9]*\/umd\/react\.production/], ['react-dom.js', /react-dom@18/], ['babel.js', /babel\.min\.js/], ['tailwind.js', /cdn\.tailwindcss/]])
        if (re.test(u)) return route.fulfill({ body: fs.readFileSync(path.join(LIBS, f)), contentType: 'application/javascript' });
      route.continue();
    });
    await ctx.addInitScript((px) => {
      localStorage.setItem('cf_room', 'dragout-room');
      localStorage.setItem('cf_user_name', 'Тест');
      localStorage.setItem('cf_gal_scope', 'refs');
      localStorage.setItem('cf_references', JSON.stringify([
        { id: 'r0', url: px, label: '', file: 'Кухня: ночь.png', tags: [], folder: '', sceneId: '', locationId: '' },
        { id: 'r1', url: px, label: '', file: 'IMG_4821.HEIC', tags: [], folder: '', sceneId: '', locationId: '',
          full: 'https://www.dropbox.com/scl/fi/abc/r1.heic?rlkey=x&raw=1', cloud: { provider: 'dropbox', path: '/CineFlow/r1.heic' } },
        { id: 'r2', url: px, label: '', file: 'clip.mov', tags: [], folder: '', sceneId: '', locationId: '', video: true },
        { id: 'r3', url: px, label: '', file: 'двор.jpg', tags: ['скаут'], folder: 'Двор', sceneId: '', locationId: 'loc-1' }]));
      localStorage.setItem('cf_locations', JSON.stringify([{ id: 'loc-1', name: 'Двор', address: '', coords: '', description: '', sceneIds: [], order: 1 }]));
    }, PX);
    const page = await ctx.newPage();
    const errs = [];
    page.on('pageerror', e => errs.push(String(e).slice(0, 200)));
    await page.goto(`http://127.0.0.1:${PORT}/index.html`);
    await page.waitForFunction(() => window.__CF_APP_OK, { timeout: 180000 });
    await page.waitForTimeout(900);
    await page.evaluate(async () => {
      const b = [...document.querySelectorAll('.cf-tabbar button, header button')].find(x => /Галере/i.test((x.textContent || '') + (x.title || '')));
      if (b) b.click();
      await new Promise(r => setTimeout(r, 800));
    });
    return { page, errs };
  };
  const cards = p => p.evaluate(() => document.querySelectorAll('.cf-ref-card').length);
  // dragstart руками: настоящий DataTransfer, смотрим, что положено
  const startDrag = (p, sel, i = 0) => p.evaluate(([sel, i]) => {
    const el = document.querySelectorAll(sel)[i]; if (!el) return null;
    const dt = new DataTransfer();
    el.dispatchEvent(new DragEvent('dragstart', { bubbles: true, cancelable: true, dataTransfer: dt }));
    window.__dt = dt;
    return { draggable: el.draggable, types: [...dt.types], dl: dt.getData('DownloadURL').slice(0, 120) };
  }, [sel, i]);
  const endDrag = (p, sel, i = 0) => p.evaluate(([sel, i]) => { const el = document.querySelectorAll(sel)[i]; el && el.dispatchEvent(new DragEvent('dragend', { bubbles: true, dataTransfer: window.__dt })); }, [sel, i]);

  const { page: p, errs } = await mk(1440, 900);
  const imgs = await p.$$eval('[data-cf="ref-img"]', a => a.map(x => x.draggable));
  ok('в галерее фото тащатся, ролик — нет', JSON.stringify(imgs) === '[true,true,false]', JSON.stringify(imgs));
  const d0 = await startDrag(p, '[data-cf="ref-img"]', 0);
  ok('DownloadURL: тип, имя без двоеточия и картинка', d0 && /^image\/gif:Кухня  ночь\.gif:data:image\/gif/.test(d0.dl) && d0.types.includes('application/x-cineflow-ref'), JSON.stringify(d0));
  // своя картинка, брошенная обратно в галерею, не загружается
  const before = await cards(p);
  await p.evaluate(() => {
    const zone = document.querySelector('[data-cf="ref-img"]').closest('.overflow-y-auto');
    const over = new DragEvent('dragover', { bubbles: true, cancelable: true, dataTransfer: window.__dt });
    zone.dispatchEvent(over); window.__overPrevented = over.defaultPrevented;
    zone.dispatchEvent(new DragEvent('drop', { bubbles: true, cancelable: true, dataTransfer: window.__dt }));
  });
  await p.waitForTimeout(800);
  ok('своя картинка обратно в галерею не принимается', await cards(p) === before && !(await p.evaluate(() => window.__overPrevented)));
  await endDrag(p, '[data-cf="ref-img"]', 0);
  const d1 = await startDrag(p, '[data-cf="ref-img"]', 1);
  ok('из Dropbox — оригинал по ссылке с dl=1 и расширением файла', d1 && /^image\/heic:IMG_4821\.heic:https:\/\/www\.dropbox\.com\/.*dl=1/.test(d1.dl) && !/raw=1/.test(d1.dl), d1 && d1.dl);
  await endDrag(p, '[data-cf="ref-img"]', 1);
  // а чужой файл после конца перетаскивания принимается как раньше
  const back = await p.evaluate(() => {
    const zone = document.querySelector('[data-cf="ref-img"]').closest('.overflow-y-auto');
    const dt = new DataTransfer(); dt.items.add(new File([new Uint8Array([1, 2, 3])], 'x.png', { type: 'image/png' }));
    const over = new DragEvent('dragover', { bubbles: true, cancelable: true, dataTransfer: dt });
    zone.dispatchEvent(over); return over.defaultPrevented;
  });
  ok('чужой файл после перетаскивания по-прежнему принимается', back === true);
  // режим «Выбрать» — не тащится
  await p.evaluate(() => [...document.querySelectorAll('button')].find(b => b.textContent.trim() === 'Выбрать' && b.classList.contains('cf-chip') && b.offsetParent).click());
  await p.waitForTimeout(300);
  ok('в режиме «Выбрать» фото не тащится', (await p.$$eval('[data-cf="ref-img"]', a => a.map(x => x.draggable))).every(v => !v));
  await p.evaluate(() => [...document.querySelectorAll('button')].find(b => b.textContent.trim() === 'Готово' && b.classList.contains('cf-chip') && b.offsetParent).click());
  await p.waitForTimeout(300);
  // просмотр
  await p.click('[data-cf="ref-img"] >> nth=0');
  await p.waitForTimeout(600);
  ok('в просмотре кадр тащится', await p.$eval('[data-cf="lb-img"]', x => x.draggable).catch(() => 'нет') === true);
  await p.keyboard.press('Escape'); await p.waitForTimeout(400);
  // фото со скаута в объекте
  await p.evaluate(() => { const b = [...document.querySelectorAll('header button')].find(x => /Объект/i.test((x.textContent || '') + (x.title || ''))); b && b.click(); });
  await p.waitForTimeout(800);
  ok('фото объекта тащится', await p.$eval('[data-cf="loc-photo"]', x => x.draggable).catch(() => 'нет') === true);
  ok('ошибок нет', errs.length === 0, errs.join(' | '));

  await browser.close(); server.kill();
  console.log(bad ? `\n${bad} не сошлось` : '\nВсё сошлось');
  process.exit(bad ? 1 : 0);
})().catch(e => { console.error(e); server.kill(); process.exit(1); });
