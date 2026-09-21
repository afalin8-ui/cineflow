// Два гнезда галереи: референсы отдельно, фото со скаута отдельно.
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
      for (const [f, re] of [['react.js',/react@18\/umd\/react\.production/],['react-dom.js',/react-dom@18/],['babel.js',/babel\.min\.js/],['tailwind.js',/cdn\.tailwindcss/]])
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
    await page.waitForFunction(() => window.__CF_APP_OK, { timeout: 180000 });
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

  // ---- НОУТБУК
  const { page: p, errs } = await mk(1440, 900);
  const a = await p.evaluate(seg);
  ok('по умолчанию гнездо «Референсы» — скаут не показан',
     a.cards === 4 && /Референсы · 4/.test(a.seg.join(' ')) && /Со скаута · 6/.test(a.seg.join(' ')), JSON.stringify(a));
  const folders = await p.evaluate(() => [...document.querySelectorAll('aside, div')].length && [...document.querySelectorAll('button')]
    .filter(b => /Квартира на Горской|Двор школы/.test(b.textContent||'')).map(b => b.textContent.trim()));
  ok('папки скаута не мешаются в референсах', folders.length === 0, folders.join(' | '));
  const b = await p.evaluate(async () => {
    [...document.querySelectorAll('.cf-seg button')].find(x => /Со скаута/.test(x.textContent||'')).click();
    await new Promise(r => setTimeout(r, 600));
    return { cards: document.querySelectorAll('.cf-ref-card').length,
             locs: [...document.querySelectorAll('button')].filter(x => /Квартира на Горской · |Двор школы/.test(x.textContent||'')).map(x => x.textContent.trim()).slice(0, 4),
             head: (document.querySelector('.cf-eyebrow') || {}).textContent };
  });
  ok('в гнезде скаута — только фото объектов', b.cards === 6, JSON.stringify({ cards: b.cards }));
  ok('вместо папок — объекты со счётчиком', b.locs.some(x => /Квартира на Горской/.test(x)) && b.locs.some(x => /Двор школы/.test(x)), b.locs.join(' | '));
  const c = await p.evaluate(async () => {
    const btn = [...document.querySelectorAll('button')].find(x => /^Двор школы/.test((x.textContent||'').trim()));
    const r = btn.getBoundingClientRect();
    const hit = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
    btn.click();
    await new Promise(r2 => setTimeout(r2, 600));
    return { cards: document.querySelectorAll('.cf-ref-card').length, hits: !!(hit && (hit === btn || btn.contains(hit))),
             upload: [...document.querySelectorAll('button, label')].map(x => x.textContent.trim()).find(t => /Загрузить в /.test(t)) };
  });
  ok('нажатие по объекту попадает и фильтрует', c.hits && c.cards === 2, JSON.stringify(c));
  ok('загрузка адресована выбранному объекту', /Двор школы/.test(c.upload || ''), c.upload || 'кнопки нет');
  const d = await p.evaluate(async () => {
    localStorage.setItem('cf_gal_scope', 'scout');
    [...document.querySelectorAll('.cf-seg button')].find(x => /Референсы/.test(x.textContent||'')).click();
    await new Promise(r => setTimeout(r, 500));
    return { cards: document.querySelectorAll('.cf-ref-card').length, saved: localStorage.getItem('cf_gal_scope') };
  });
  ok('возврат в референсы и выбор помнится', d.cards === 4 && d.saved === 'refs', JSON.stringify(d));

  // ---- ТЕЛЕФОН: гнёзда и лента объектов
  const { page: ph } = await mk(390, 844);
  const e = await ph.evaluate(async () => {
    const s = [...document.querySelectorAll('.cf-seg button')];
    const r = s[1].getBoundingClientRect();
    const hit = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
    s[1].click();
    await new Promise(x => setTimeout(x, 600));
    return { hits: !!(hit && (hit === s[1] || s[1].contains(hit))), cards: document.querySelectorAll('.cf-ref-card').length,
             chips: [...document.querySelectorAll('.cf-chip')].map(x => x.textContent.trim()).filter(t => /Горской|школы|Все объекты/.test(t)) };
  });
  ok('телефон: переключатель нажимается, лента объектов на месте',
     e.hits && e.cards === 6 && e.chips.length >= 2, JSON.stringify(e));
  if (errs.length) ok('без ошибок в консоли', false, errs.join(' | '));
  console.log(bad ? `\nПЛОХО: ${bad}` : '\nВсё сошлось');
  await browser.close(); server.kill(); process.exit(bad ? 1 : 0);
})().catch(e => { console.error(e); server.kill(); process.exit(1); });
