// Галерея — только референсы (одно гнездо), фото объектов — сеткой в «Объектах».
const fs = require('fs'), os = require('os'), path = require('path');
const { execSync, spawn } = require('child_process');
const ROOT = require('path').resolve(__dirname, '..'), LIBS = path.join(os.tmpdir(), 'cineflow-libs'), PORT = '8141';
let playwright;
try { playwright = require('playwright'); } catch (e) { playwright = require(execSync('npm root -g').toString().trim() + '/playwright'); }
const server = spawn('python3', ['-m','http.server',PORT,'--bind','127.0.0.1'], { cwd: ROOT, stdio: 'ignore' });
let bad = 0;
const ok = (n, c, d) => { console.log((c ? '  ok  ' : '  FAIL') + ' ' + n + (d ? ' — ' + d : '')); if (!c) bad++; };
const PX = 'data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==';
(async () => {
  await new Promise(r => setTimeout(r, 1200));
  const browser = await playwright.chromium.launch({ executablePath: '/opt/pw-browsers/chromium', args: ['--no-sandbox'] });
  const mk = async (w, h) => {
    const ctx = await browser.newContext({ viewport: {width: w, height: h}, isMobile: w < 768, hasTouch: w < 900, serviceWorkers: 'block' });
    await ctx.route('**/*', route => {
      const u = route.request().url();
      if (/firestore|firebase|googleapis|gstatic|nominatim/.test(u)) return route.abort();
      for (const [f, re] of [['react.js',/react@18[.0-9]*\/umd\/react\.production/],['react-dom.js',/react-dom@18/],['babel.js',/babel\.min\.js/],['tailwind.js',/cdn\.tailwindcss/]])
        if (re.test(u)) return route.fulfill({ body: fs.readFileSync(path.join(LIBS, f)), contentType: 'application/javascript' });
      route.continue();
    });
    await ctx.addInitScript((px) => {
      localStorage.setItem('cf_room', 'gal-room');
      localStorage.setItem('cf_user_name', 'Тест');
      localStorage.removeItem('cf_gal_scope');
      const refs = [];
      for (let i = 0; i < 4; i++) refs.push({ id: 'r' + i, url: px, label: 'реф ' + i, file: 'ref' + i + '.jpg', tags: ['свет'], folder: i < 2 ? 'Свет' : '', sceneId: '', locationId: '' });
      for (let i = 0; i < 6; i++) refs.push({ id: 's' + i, url: px, label: '', file: 'sc' + i + '.jpg', tags: ['скаут'], folder: i < 4 ? 'Квартира на Горской' : 'Двор школы',
                                              sceneId: '', locationId: i < 4 ? 'loc-1' : 'loc-2' });
      localStorage.setItem('cf_references', JSON.stringify(refs));
      localStorage.setItem('cf_locations', JSON.stringify([
        { id: 'loc-1', name: 'Квартира на Горской', address: '', coords: '', description: '', sceneIds: [], order: 1 },
        { id: 'loc-2', name: 'Двор школы', address: '', coords: '', description: '', sceneIds: [], order: 2 }]));
    }, PX);
    const page = await ctx.newPage();
    const errs = [];
    page.on('pageerror', e => errs.push(String(e).slice(0, 200)));
    await page.goto(`http://127.0.0.1:${PORT}/index.html`);
    await page.waitForFunction(() => window.__CF_APP_OK, null, { timeout: 180000 });
    await page.waitForTimeout(900);
    await page.evaluate(async () => {
      const b = [...document.querySelectorAll('.cf-tabbar button, header button')].find(x => /Галере/i.test((x.textContent||'') + (x.title||'')));
      if (b) b.click();
      await new Promise(r => setTimeout(r, 800));
    });
    return { page, errs };
  };
  const seg = () => ({
    seg: [...document.querySelectorAll('.cf-seg button')].map(b => b.textContent.trim()),
    cards: document.querySelectorAll('.cf-ref-card').length,
    count: (document.querySelector('.cf-meta') || {}).textContent
  });

  // ---- НОУТБУК. С ноября 2026 гнездо ОДНО — референсы; фото объектов
  // живут в «Объектах» (см. CLAUDE.md, «Раскладка как у iPhone Duo»).
  const { page: p, errs } = await mk(1440, 900);
  const a = await p.evaluate(seg);
  ok('в галерее только референсы, без переключателя гнёзд',
     a.cards === 4 && !/Со скаута/.test(a.seg.join(' ')), JSON.stringify(a));
  const folders = await p.evaluate(() => [...document.querySelectorAll('button')]
    .filter(b => /Квартира на Горской|Двор школы/.test(b.textContent||'')).map(b => b.textContent.trim()));
  ok('папки объектов не мешаются в галерее', folders.length === 0, folders.join(' | '));
  const st = await p.evaluate(() => { const s = document.querySelector('.cf-galsearch'); return s ? getComputedStyle(s).position : ''; });
  ok('строка поиска липкая', st === 'sticky', st);
  const lb = await p.evaluate(async () => {
    const img = document.querySelector('.cf-ref-card img');
    const box = img.closest('.cursor-pointer') || img;
    const r = box.getBoundingClientRect();
    const hit = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
    box.click();
    await new Promise(x => setTimeout(x, 600));
    const pin = document.querySelector('[data-cf="lb-pin"]');
    return { hits: !!(hit && (hit === box || box.contains(hit))), open: !!pin,
             quiet: pin ? getComputedStyle(pin.parentElement).opacity === '0' : null };
  });
  ok('касание по фото сразу открывает его на весь экран', lb.hits && lb.open, JSON.stringify(lb));
  ok('в просмотре в покое управление спрятано', lb.quiet === true, JSON.stringify(lb));
  await p.keyboard.press('Escape'); await p.waitForTimeout(300);
  const lo = await p.evaluate(async () => {
    const b = document.querySelector('[data-cf="nav-locations"]'); b && b.click();
    await new Promise(x => setTimeout(x, 700));
    const g = document.querySelector('[data-cf="loc-grid"]');
    return { grid: !!g, photos: document.querySelectorAll('[data-cf="loc-photo"]').length, scroll: g ? getComputedStyle(g).overflowX : '' };
  });
  ok('фото объекта — сеткой, без прокрутки вбок', lo.grid && lo.photos === 4 && lo.scroll !== 'auto', JSON.stringify(lo));

  // ---- ТЕЛЕФОН: тоже одно гнездо
  const { page: ph } = await mk(390, 844);
  const e = await ph.evaluate(() => ({ cards: document.querySelectorAll('.cf-ref-card').length,
    seg: [...document.querySelectorAll('.cf-seg button')].map(b => b.textContent.trim()).join(' ') }));
  ok('телефон: только референсы, гнёзд нет', e.cards === 4 && !/Со скаута/.test(e.seg), JSON.stringify(e));
  if (errs.length) ok('без ошибок в консоли', false, errs.join(' | '));
  console.log(bad ? `\nПЛОХО: ${bad}` : '\nВсё сошлось');
  await browser.close(); server.kill(); process.exit(bad ? 1 : 0);
})().catch(e => { console.error(e); server.kill(); process.exit(1); });
