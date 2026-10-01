// СХЕМЫ СВЕТА НА EXCALIDRAW и ПЕРЕВОД ВСЕГО ПРОЕКТА РАЗОМ.
//
// Схема света открывается в той же полосе, что и доски, — холстом
// Excalidraw. Старая схема (фигуры с подписями приборов и растровый
// рисунок кистью) переводится при первом открытии, ничего не теряя:
// фигуры становятся родными элементами, растр — запертой подложкой,
// прежние данные записи целы, «Вернуть прежнюю схему» работает.
// Проверяется в браузере, облако поддельное (fake-cloud.js), живой
// Firebase заблокирован.
//
// ВСЁ РАЗОМ («Перевести всё на Excalidraw» в «···» доски): схемы —
// сразу в облако, доски — обходом, и каждая переводится только ПОСЛЕ
// того, как её рисунок пришёл с сервера. Проверяется на доске, которую
// на этом устройстве не открывали ни разу: её фигуры и штрихи есть
// ТОЛЬКО в облаке, и перевод обязан их дождаться.
//
// Запуск:  node tests/excmigrate-e2e.js
const path = require('path'), fs = require('fs'), os = require('os'), zlib = require('zlib');
const { execSync, spawn } = require('child_process');
const ROOT = path.resolve(__dirname, '..');
const LIBS = process.env.CF_LIBS || path.join(os.tmpdir(), 'cineflow-libs');
const PORT = process.env.CF_PORT || '8174';
const SHOTS = process.env.CF_SHOTS || '';
const { FAKE_CLOUD } = require('./fake-cloud.js');
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
for (const [f, u] of Object.entries(LIB_URLS)) if (!fs.existsSync(path.join(LIBS, f))) execSync(`curl -sSL -o ${path.join(LIBS, f)} ${u}`);
const server = spawn('python3', ['-m', 'http.server', PORT, '--bind', '127.0.0.1'], { cwd: ROOT, stdio: 'ignore' });
let bad = 0;
const ok = (n, c, d) => { console.log((c ? '  ok  ' : '  FAIL') + ' ' + n + (d ? ' — ' + d : '')); if (!c) bad++; };

// PNG без внешних файлов; rgba — с прозрачностью (так рисовал старый
// редактор схемы: штрихи кисти на прозрачном листе).
const png = (w, h, px, alpha) => {
  const T = []; for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; T[n] = c >>> 0; }
  const crc = (b) => { let c = 0xffffffff; for (const x of b) c = T[(c ^ x) & 255] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
  const chunk = (t, d) => { const l = Buffer.alloc(4); l.writeUInt32BE(d.length); const td = Buffer.concat([Buffer.from(t), d]); const c = Buffer.alloc(4); c.writeUInt32BE(crc(td)); return Buffer.concat([l, td, c]); };
  const n = alpha ? 4 : 3;
  const ih = Buffer.alloc(13); ih.writeUInt32BE(w, 0); ih.writeUInt32BE(h, 4); ih[8] = 8; ih[9] = alpha ? 6 : 2;
  const raw = Buffer.alloc((w * n + 1) * h);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) { const o = y * (w * n + 1) + 1 + x * n, c = px(x, y); for (let k = 0; k < n; k++) raw[o + k] = c[k]; }
  return 'data:image/png;base64,' + Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ih), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]).toString('base64');
};
// Растр старой схемы: прозрачный лист 160×90 с голубой полосой кисти
// поперёк середины (на холсте он растянут на 1600×900).
const RASTER = png(160, 90, (x, y) => (y >= 40 && y < 50) ? [60, 140, 255, 255] : [0, 0, 0, 0], true);
const OLDPREV = png(16, 9, () => [10, 200, 10]);

const OLD_ELEMENTS = [
  { id: 'e1', type: 'rect', x: 100, y: 100, w: 120, h: 80, color: '#facc15', text: '', label: 'SkyPanel S60' },
  { id: 'e2', type: 'circle', x: 400, y: 100, w: 100, h: 100, color: '#f87171', text: '', label: '' },
  { id: 'e3', type: 'triangle', x: 700, y: 100, w: 160, h: 140, color: '#34d399', text: '', label: 'Актёр' },
  { id: 'e4', type: 'star', x: 1000, y: 100, w: 120, h: 120, color: '#60a5fa', text: '', label: '' },
  { id: 'e5', type: 'arrow', x: 100, y: 500, w: 200, h: 120, color: '#ffffff', text: '', label: '' },
  { id: 'e6', type: 'text', x: 600, y: 600, w: 200, h: 50, color: '#facc15', text: 'Окно', label: '' },
  { id: 'e7', type: 'diamond', x: 1000, y: 500, w: 100, h: 100, color: '#facc15', text: '', label: 'Камера' }
];

const SEED = () => ({
  boards: { 'board-main': { id: 'board-main', title: 'Основная', order: 0 } },
  scenes: { sc1: { id: 'sc1', number: '1', title: 'ИНТ. КВАРТИРА', content: '', boardId: '', x: 0, y: 0, gear: {}, lightGear: {}, lightSchemeId: 'ls1' } },
  lightSchemes: {
    ls1: { id: 'ls1', title: 'Схема кухни', elements: OLD_ELEMENTS, drawData: RASTER, preview: OLDPREV }
  }
});

(async () => {
  await new Promise(r => setTimeout(r, 1200));
  const browser = await playwright.chromium.launch({ executablePath: process.env.CF_CHROME || '/opt/pw-browsers/chromium', args: ['--no-sandbox'] });
  const mkCtx = async (w, h, seed, init) => {
    const ctx = await browser.newContext({ viewport: { width: w, height: h }, isMobile: w < 768, hasTouch: w < 768, serviceWorkers: 'block' });
    await ctx.route('**/*', (route) => {
      const u = route.request().url();
      if (/firestore|firebase|googleapis|gstatic|nominatim/.test(u)) return route.abort();
      for (const [f, re] of [['react.js', /react@18\/umd\/react\.production/], ['react-dom.js', /react-dom@18/],
                             ['babel.js', /babel\.min\.js/], ['tailwind.js', /cdn\.tailwindcss/]])
        if (re.test(u)) return route.fulfill({ body: fs.readFileSync(path.join(LIBS, f)), contentType: 'application/javascript' });
      route.continue();
    });
    await ctx.addInitScript(FAKE_CLOUD, seed);
    await ctx.addInitScript(() => {
      localStorage.setItem('cf_room', 'x-room'); localStorage.setItem('cf_user_name', 'Тест');
      localStorage.setItem('cf_active_board', 'board-main');
    });
    if (init) await ctx.addInitScript(init);
    return ctx;
  };
  const open = async (ctx, url = '/index.html') => {
    const page = await ctx.newPage();
    const errs = [];
    page.on('pageerror', e => errs.push(String(e).slice(0, 300)));
    await page.goto(`http://127.0.0.1:${PORT}${url}`);
    await page.waitForFunction(() => window.__CF_APP_OK, { timeout: 180000 });
    await page.waitForTimeout(900);
    return { page, errs };
  };
  const goBoards = (page) => page.evaluate(async () => {
    const tab = [...document.querySelectorAll('button')].find(x => x.title === 'Доски' || x.textContent.trim() === 'Доски');
    if (tab) tab.click();
    else {
      const more = [...document.querySelectorAll('.cf-tabbar button, header button')].find(x => /Ещё/.test(x.textContent));
      if (more) { more.click(); await new Promise(r => setTimeout(r, 400)); }
      const d = [...document.querySelectorAll('button')].find(x => x.textContent.trim() === 'Доски');
      if (d) d.click();
    }
  });
  // Нажать НАСТОЯЩЕЙ мышью и убедиться, что в точке — именно оно.
  const press = async (page, sel) => {
    const r = await page.evaluate((sel) => {
      const el = typeof sel === 'string' ? document.querySelector(sel) : null;
      if (!el) return null;
      const b = el.getBoundingClientRect(), x = b.left + b.width / 2, y = b.top + b.height / 2;
      const top = document.elementFromPoint(x, y);
      return { x, y, hit: !!top && (top === el || el.contains(top)) };
    }, sel);
    if (r && r.hit) await page.mouse.click(r.x, r.y);
    return r;
  };
  const store = (page, coll) => page.evaluate((c) => JSON.parse(JSON.stringify((window.__cfStore || {})[c] || {})), coll);
  const writes = (page) => page.evaluate(() => (window.__cfWrites || []).slice());
  const els = (page) => page.evaluate(() => window.__cfExc.api.getSceneElementsIncludingDeleted().map(e => ({
    id: e.id, type: e.type, del: e.isDeleted, x: e.x, y: e.y, w: e.width, h: e.height, cd: e.customData || null, locked: !!e.locked,
    bg: e.backgroundColor, sc: e.strokeColor, g: e.groupIds, text: e.originalText || e.text || '', ta: e.textAlign, pts: e.points ? e.points.length : 0
  })));
  const live = (l) => l.filter(e => !e.del);
  const scr = (page, x, y) => page.evaluate(([x, y]) => {
    const s = window.__cfExc.api.getAppState();
    return { x: (x + s.scrollX) * s.zoom.value + s.offsetLeft, y: (y + s.scrollY) * s.zoom.value + s.offsetTop };
  }, [x, y]);
  const pixel = async (page, x, y) => {
    const buf = await page.screenshot({ clip: { x: Math.round(x) - 1, y: Math.round(y) - 1, width: 3, height: 3 } });
    const { PNG } = (() => { try { return require('pngjs'); } catch (e) { return {}; } })();
    return buf;
  };
  const shot = async (page, name) => { if (SHOTS) await page.screenshot({ path: path.join(SHOTS, name + '.png') }); };

  // ================= НОУТБУК: старая схема → Excalidraw =================
  const ctx = await mkCtx(1440, 900, SEED());
  const { page: p, errs } = await open(ctx);
  await goBoards(p);
  await p.waitForTimeout(600);
  const tab = await press(p, '[data-cf="scheme-tab"]');
  ok('вкладка схемы в полосе досок нажимается', !!tab && tab.hit, JSON.stringify(tab));
  await p.waitForFunction(() => window.__cfExc && window.__cfExc.api && window.__cfExc.boardId === 'ls1', { timeout: 60000 }).catch(() => {});
  await p.waitForTimeout(1500);
  const LS = (await store(p, 'lightSchemes')).ls1 || {};
  ok('схема переведена: движок Excalidraw, прежние фигуры, рисунок и картинка в записи целы',
     LS.engine === 'excalidraw' && LS.from === 'own' && (LS.elements || []).length === 7 && LS.drawData === RASTER, JSON.stringify({ engine: LS.engine, from: LS.from, n: (LS.elements || []).length }));
  const BE = Object.values(await store(p, 'boardEls')).filter(d => d.b === 'ls1');
  ok('элементы схемы — в облаке по одному, с ключами порядка (7 фигур + 3 подписи)', BE.length === 10 && BE.every(d => JSON.parse(d.e).index),
     String(BE.length));
  let E = live(await els(p));
  const byId = (id) => E.find(e => e.id === id);
  ok('прямоугольник с цветом и подписью «SkyPanel S60» одной группой', byId('s~e1') && byId('s~e1').type === 'rectangle' && byId('s~e1').bg === '#facc15'
     && byId('s~e1~l') && byId('s~e1~l').text === 'SkyPanel S60' && byId('s~e1').g.join() === byId('s~e1~l').g.join() && byId('s~e1').g.length === 1);
  const l1 = byId('s~e1~l'), r1 = byId('s~e1');
  ok('подпись прибора по центру под фигурой', l1 && r1 && Math.abs((l1.x + l1.w / 2) - (r1.x + r1.w / 2)) < 2 && l1.y >= r1.y + r1.h,
     l1 && r1 && `${Math.round(l1.x + l1.w / 2)} vs ${r1.x + r1.w / 2}`);
  ok('круг, ромб — родными фигурами; треугольник и звезда — замкнутыми линиями; стрелка; текст',
     byId('s~e2').type === 'ellipse' && byId('s~e7').type === 'diamond' && byId('s~e3').type === 'line' && byId('s~e3').pts === 4
     && byId('s~e4').type === 'line' && byId('s~e4').pts === 11 && byId('s~e5').type === 'arrow' && byId('s~e6').type === 'text' && byId('s~e6').text === 'Окно');
  const bgEl = byId('ls1~bg');
  ok('старый рисунок кистью — запертой подложкой 1600×900 под всем', !!bgEl && bgEl.type === 'image' && bgEl.locked && bgEl.w === 1600 && bgEl.h === 900
     && E.findIndex(e => e.id === 'ls1~bg') === 0, JSON.stringify(bgEl && { t: bgEl.type, l: bgEl.locked, w: bgEl.w, h: bgEl.h }));
  ok('подложка в облако нарисованным не ушла', !BE.some(d => d.id === 'ls1~bg'));
  ok('вкладка схемы подсвечена, вкладка доски — нет', await p.evaluate(() => {
    const t = document.querySelector('[data-cf="scheme-tab"]'), b = [...document.querySelectorAll('button')].find(x => x.textContent.trim() === 'Основная');
    return t.style.borderBottom.includes('2px solid') && !t.style.borderBottom.includes('transparent') && b && b.style.borderBottom.includes('transparent');
  }));
  await shot(p, 'scheme-converted');

  // --- прибор из списка: группа посреди видимого, выделена, в облако ---
  const ft = await press(p, '[data-cf="fixture-tool"]');
  ok('кнопка «Прибор» нажимается', !!ft && ft.hit);
  await p.waitForTimeout(250);
  const rowSpot = await press(p, '[data-cf="fixture-menu"] [data-fx="spot"]');
  ok('строка «Прожектор» в списке нажимается', !!rowSpot && rowSpot.hit, JSON.stringify(rowSpot));
  await p.waitForTimeout(400);
  const S1 = await p.evaluate(() => { const a = window.__cfExc.api, app = a.getAppState();
    const fx = a.getSceneElements().filter(e => e.customData && e.customData.fx === 'spot');
    return { n: fx.length, g: [...new Set(fx.map(e => e.groupIds.join()))], sel: fx.every(e => app.selectedElementIds[e.id]),
             types: fx.map(e => e.type).sort().join(','), cd: fx.some(e => e.customData.cf) }; });
  ok('прожектор — группа из корпуса, конуса и подписи, сразу выделен, не карточка', S1.n === 3 && S1.g.length === 1 && S1.sel && S1.types === 'line,rectangle,text' && !S1.cd, JSON.stringify(S1));
  await shot(p, 'scheme-spot');
  await p.mouse.click(700, 760); await p.waitForTimeout(2600);
  const BE2 = Object.values(await store(p, 'boardEls')).filter(d => d.b === 'ls1');
  ok('прибор ушёл в облако тремя элементами', BE2.filter(d => /"fx":"spot"/.test(d.e)).length === 3, String(BE2.length));
  const LS2 = (await store(p, 'lightSchemes')).ls1;
  ok('картинка схемы пересобрана с холста (у сцены и в печати — новая)', LS2.preview && LS2.preview !== OLDPREV && /^data:image\/jpeg/.test(LS2.preview),
     (LS2.preview || '').slice(0, 30));
  const pv = await p.evaluate((u) => new Promise(r => { const i = new Image(); i.onload = () => r({ w: i.naturalWidth, h: i.naturalHeight }); i.onerror = () => r(null); i.src = u; }), LS2.preview);
  ok('картинка схемы читается и не крохотная', !!pv && pv.w >= 800, JSON.stringify(pv));

  // --- все знаки по очереди: каждый ложится группой ---
  const allFx = await p.evaluate(() => { const out = {}; ['spot','panel','camera','actor','flag','bounce','frame','window','sun'].forEach(k => {
    const before = window.__cfExc.api.getSceneElements().length; const okk = window.__cfExc.insertFixture(k);
    out[k] = okk ? window.__cfExc.api.getSceneElements().length - before : -1; }); return out; });
  ok('все девять знаков ложатся на схему', Object.values(allFx).every(n => n >= 2), JSON.stringify(allFx));
  await p.evaluate(() => { const a = window.__cfExc.api; a.scrollToContent(a.getSceneElements(), { fitToContent: true }); });
  await p.waitForTimeout(400);
  await shot(p, 'scheme-all-fixtures');
  await p.keyboard.press('Control+z'); await p.waitForTimeout(300);

  // --- картинку на схему не кладут, и об этом сказано ---
  const nRefs0 = Object.keys(await store(p, 'references')).length;
  await p.evaluate(() => { const dt = new DataTransfer(); const b = atob('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');
    const u = new Uint8Array(b.length); for (let i = 0; i < b.length; i++) u[i] = b.charCodeAt(i);
    dt.items.add(new File([u], 'p.png', { type: 'image/png' })); document.querySelector('.excalidraw').dispatchEvent(new ClipboardEvent('paste', { clipboardData: dt, bubbles: true })); });
  await p.waitForTimeout(600);
  ok('вставка картинки на схему не заводит референс и говорит, почему', Object.keys(await store(p, 'references')).length === nRefs0
     && /не кладутся/.test(await p.evaluate(() => (document.querySelector('[data-cf="toast"]') || {}).textContent || '')));

  // --- доска рядом — своя; схема закрылась ---
  await p.evaluate(() => { const b = [...document.querySelectorAll('button')].find(x => x.textContent.trim() === 'Основная'); b.click(); });
  await p.waitForTimeout(700);
  ok('вкладка доски открывает доску, а не схему', await p.evaluate(() => !!document.getElementById('whiteboard-canvas') && !document.querySelector('[data-cf="exc-board"]')));

  // --- со сцены: «Открыть» у схемы света ведёт прямо на холст ---
  await p.evaluate(() => { const t = [...document.querySelectorAll('button')].find(x => x.title === 'Сцены' || x.textContent.trim() === 'Сцены'); t && t.click(); });
  await p.waitForTimeout(700);
  await p.evaluate(() => { const b = [...document.querySelectorAll('button')].find(x => /Свет/.test(x.title || '') && x.closest('.cf-tools, [class*="rail"], aside, div')); });
  const lb = await p.evaluate(() => { const b = [...document.querySelectorAll('button.cf-tool')].find(x => /^Схема света/.test(x.title || '')); if (!b) return null;
    const r = b.getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; });
  if (lb) await p.mouse.click(lb.x, lb.y);
  await p.waitForFunction(() => window.__cfExc && window.__cfExc.api && window.__cfExc.boardId === 'ls1' && document.querySelector('[data-cf="exc-board"]').getBoundingClientRect().width > 0, { timeout: 30000 }).catch(() => {});
  ok('значок схемы света у сцены открывает её холст на «Досках»', !!lb && await p.evaluate(() => window.__cfExc.boardId === 'ls1' && document.querySelector('[data-cf="exc-board"]').getBoundingClientRect().width > 0));
  await p.waitForTimeout(800);
  E = live(await els(p));
  const nSpot = E.filter(e => e.cd && e.cd.fx === 'spot').length;
  ok('после переоткрытия на схеме всё: перевод, подложка и прожекторы', !!E.find(e => e.id === 's~e1') && !!E.find(e => e.id === 'ls1~bg') && nSpot >= 3, String(nSpot));

  // --- «Вернуть прежнюю схему»: прежний редактор, прежняя картинка ---
  await press(p, 'button[title^="Выгрузить доску"]');
  await p.waitForTimeout(250);
  const rv = await press(p, '[data-cf="scheme-from-exc"]');
  ok('строка «Вернуть прежнюю схему» в «···» нажимается', !!rv && rv.hit);
  await p.waitForTimeout(300);
  await press(p, '[data-cf="confirm-ok"]');
  await p.waitForTimeout(1200);
  const LS3 = (await store(p, 'lightSchemes')).ls1;
  ok('схема вернулась в прежний редактор, нарисованное на Excalidraw цело', LS3.engine === '' && Object.values(await store(p, 'boardEls')).filter(d => d.b === 'ls1').length >= 13
     && await p.evaluate(() => [...document.querySelectorAll('span')].some(s => s.textContent.trim() === 'Схема света' && s.closest('.fixed'))));
  ok('картинка схемы снова прежняя (её собрал прежний редактор)', LS3.preview && LS3.preview !== LS2.preview && /^data:image\/jpeg/.test(LS3.preview));
  await p.evaluate(() => { const b = [...document.querySelectorAll('button')].find(x => x.textContent.trim() === 'Закрыть'); b && b.click(); });
  await p.waitForTimeout(400);
  // Снова на Excalidraw: прибор, поставленный там, не задвоился и не пропал.
  await press(p, '[data-cf="scheme-tab"]');
  await p.waitForFunction(() => window.__cfExc && window.__cfExc.api && window.__cfExc.boardId === 'ls1', { timeout: 30000 }).catch(() => {});
  await p.waitForTimeout(1500);
  E = live(await els(p));
  const dupS = E.filter(e => e.id === 's~e1').length;
  ok('перевели снова — ничего не задвоилось, прибор с Excalidraw на месте', dupS === 1 && E.filter(e => e.cd && e.cd.fx === 'spot').length === nSpot
     && (await store(p, 'lightSchemes')).ls1.engine === 'excalidraw', `s~e1 ×${dupS}`);

  // --- «+ схема»: новая сразу на Excalidraw и открыта ---
  const nS0 = Object.keys(await store(p, 'lightSchemes')).length;
  await p.evaluate(() => { const b = [...document.querySelectorAll('button')].find(x => x.title === 'Новая схема света'); b.click(); });
  await p.waitForTimeout(1500);
  const LSn = Object.values(await store(p, 'lightSchemes')).find(x => x.id !== 'ls1');
  ok('«+ схема» заводит схему на Excalidraw и открывает её холст', Object.keys(await store(p, 'lightSchemes')).length === nS0 + 1 && LSn && LSn.engine === 'excalidraw'
     && await p.evaluate((id) => window.__cfExc.boardId === id, LSn && LSn.id));
  ok('ноутбук: ни одной ошибки страницы', errs.length === 0, errs.join(' | '));
  await ctx.close();

  // ================= ПРИБОР НА СХЕМЕ → СВЕТ СЦЕНЫ =================
  // Сцена 1 и сцена 2 со схемой «кухни», сцена 3 — без. У сцены 1 руками
  // вписано SkyPanel ×2. Правило «не меньше, чем на схеме»: нарисовали
  // один — у сцены 1 так и останется 2 (это те же), у сцены 2 станет 1.
  const seedL = () => {
    const sd = SEED();
    sd.lightGearTypes = { arri600: { label: 'ARRI Skypanel 600' } };
    sd.scenes.sc1.lightGear = { arri600: 2 };
    sd.scenes.sc2 = { id: 'sc2', number: '2', title: 'ИНТ. КУХНЯ — НОЧЬ', content: '', boardId: '', x: 0, y: 0, gear: {}, lightGear: {}, lightSchemeId: 'ls1' };
    sd.scenes.sc3 = { id: 'sc3', number: '3', title: 'НАТ. ДВОР', content: '', boardId: '', x: 0, y: 0, gear: {}, lightGear: { arri600: 1 }, lightSchemeId: '' };
    return sd;
  };
  const ctxL = await mkCtx(1440, 900, seedL());
  const { page: L, errs: errsL } = await open(ctxL);
  await goBoards(L); await L.waitForTimeout(500);
  await press(L, '[data-cf="scheme-tab"]');
  await L.waitForFunction(() => window.__cfExc && window.__cfExc.api && window.__cfExc.boardId === 'ls1', { timeout: 60000 }).catch(() => {});
  await L.waitForTimeout(1500);
  const pickL = async (sel, search) => {
    await press(L, '[data-cf="fixture-tool"]'); await L.waitForTimeout(250);
    if (search) {
      await L.focus('[data-cf="fixture-search"]');
      await L.keyboard.type(search, { delay: 15 });
      await L.waitForTimeout(250);
    }
    const r = await press(L, sel);
    await L.waitForTimeout(400);
    await L.mouse.click(700, 780); await L.waitForTimeout(1600);
    return r;
  };
  const scL = async (id) => (await store(L, 'scenes'))[id];
  const toastL = () => L.evaluate(() => (document.querySelector('[data-cf="toast"]') || {}).textContent || '');
  const rL1 = await pickL('[data-fx="dev-arri600"]');
  ok('в списке «Прибор» — приборы проекта, и строка нажимается', !!rL1 && rL1.hit, JSON.stringify(rL1));
  let SL1 = await scL('sc1'), SL2 = await scL('sc2'), SL3 = await scL('sc3');
  ok('SkyPanel на схеме: у сцены 2 появился ×1, у сцены 1 так и осталось ×2 (те же)', SL2.lightGear.arri600 === 1 && SL1.lightGear.arri600 === 2 && SL1.lightOwn.arri600 === 2
     && SL1.schemeGear.arri600 === 1, JSON.stringify({ s1: SL1.lightGear, s2: SL2.lightGear }));
  ok('сцена без этой схемы не тронута', JSON.stringify(SL3.lightGear) === JSON.stringify({ arri600: 1 }) && !SL3.schemeGear);
  ok('схема помнит свои приборы', JSON.stringify((await store(L, 'lightSchemes')).ls1.gear) === JSON.stringify({ arri600: 1 }));
  ok('полоска говорит, куда лёг прибор', /ARRI Skypanel 600 — в свете сцен #1, #2/.test(await toastL()), await toastL());
  await pickL('[data-fx="dev-arri600"]'); await pickL('[data-fx="dev-arri600"]');
  SL1 = await scL('sc1'); SL2 = await scL('sc2');
  ok('три SkyPanel на схеме — у обеих сцен ×3', SL1.lightGear.arri600 === 3 && SL2.lightGear.arri600 === 3, JSON.stringify({ s1: SL1.lightGear, s2: SL2.lightGear }));
  // Из справочника: ложится и в каталог, и в свет, знак — по виду прибора.
  const rL2 = await pickL('[data-fx^="hb-"]', 'ls 600d pro');
  const LT = await store(L, 'lightGearTypes');
  SL1 = await scL('sc1');
  ok('прибор из справочника: в каталоге, в свете сцены ×1', !!rL2 && rL2.hit && LT.aputure_ls_600d_pro && LT.aputure_ls_600d_pro.label === 'Aputure LS 600d Pro'
     && SL1.lightGear.aputure_ls_600d_pro === 1, JSON.stringify({ hit: rL2 && rL2.hit, cat: Object.keys(LT), lg: SL1.lightGear }));
  await pickL('[data-fx^="hb-"]', 'titan tube');
  const signsL = await L.evaluate(() => { const out = {}; window.__cfExc.api.getSceneElements().forEach(e => { const c = e.customData; if (c && c.dev && c.main) out[c.dev] = c.fx; }); return out; });
  ok('знак — по виду прибора: моноблок прожектором, трубка трубкой, панель панелью', signsL.aputure_ls_600d_pro === 'spot' && signsL.astera_titan_tube === 'tube' && signsL.arri600 === 'panel',
     JSON.stringify(signsL));
  const lblL = await L.evaluate(() => window.__cfExc.api.getSceneElements().some(e => e.type === 'text' && e.customData && e.customData.dev === 'astera_titan_tube' && (e.originalText || e.text) === 'Astera Titan Tube'));
  ok('подпись знака — название модели', lblL);
  await pickL('[data-fx="dev-new"]', 'Фонарь Петрович');
  SL1 = await scL('sc1');
  ok('своего прибора нигде нет — «+ новый прибор»: в каталоге и в свете', (await store(L, 'lightGearTypes'))['фонарь_петрович'] && SL1.lightGear['фонарь_петрович'] === 1, JSON.stringify(SL1.lightGear));
  // Убрали один SkyPanel со схемы — у сцен стало ×2.
  await L.evaluate(() => { const a = window.__cfExc.api;
    const one = a.getSceneElements().find(e => e.customData && e.customData.dev === 'arri600' && e.customData.main);
    const g = one.groupIds[0];
    a.updateScene({ elements: a.getSceneElementsIncludingDeleted().map(e => e.groupIds && e.groupIds.includes(g) ? { ...e, isDeleted: true, version: e.version + 1, versionNonce: e.versionNonce + 1 } : e),
                    captureUpdate: window.ExcalidrawLib.CaptureUpdateAction.IMMEDIATELY }); });
  await L.waitForTimeout(1800);
  SL1 = await scL('sc1'); SL2 = await scL('sc2');
  ok('убрали SkyPanel со схемы — у сцен ×2 (у сцены 1 вписанные руками 2)', SL1.lightGear.arri600 === 2 && SL2.lightGear.arri600 === 2, JSON.stringify({ s1: SL1.lightGear, s2: SL2.lightGear }));

  // --- в панели «Свет» сцены: пометка «на схеме», «−» ниже схемы не уводит ---
  await L.evaluate(() => { const t = [...document.querySelectorAll('button')].find(x => x.title === 'Сцены' || x.textContent.trim() === 'Сцены'); t && t.click(); });
  await L.waitForTimeout(600);
  await L.evaluate(() => { const r = [...document.querySelectorAll('button, div[role="button"], li')].find(x => /КВАРТИРА/.test(x.textContent || '') && x.offsetParent && x.textContent.length < 80); r && r.click(); });
  await L.waitForTimeout(500);
  await press(L, 'button[title="Свет"]'); await L.waitForTimeout(500);
  const marksL = await L.evaluate(() => [...document.querySelectorAll('[data-cf="gear-on-scheme"]')].filter(x => x.offsetParent).map(x => x.textContent));
  ok('в свете сцены у приборов со схемы — «на схеме ×N»', marksL.includes('на схеме ×2') && marksL.includes('на схеме ×1'), JSON.stringify(marksL));
  const minusL = await L.evaluate(() => { const row = [...document.querySelectorAll('input')].find(i => i.value === 'Aputure LS 600d Pro' && i.offsetParent);
    const b = row && [...row.parentElement.querySelectorAll('button')].find(x => x.textContent.trim() === '−'); if (!b) return null;
    const r = b.getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; });
  if (minusL) await L.mouse.click(minusL.x, minusL.y);
  await L.waitForTimeout(500);
  SL1 = await scL('sc1');
  ok('«−» у прибора со схемы не уводит ниже нарисованного и говорит почему', !!minusL && SL1.lightGear.aputure_ls_600d_pro === 1 && /уберите прибор со схемы/.test(await toastL()), await toastL());
  // Отвязали схему у сцены — её приборы ушли, вписанное руками осталось.
  await L.evaluate(() => { const sel = [...document.querySelectorAll('select')].find(x => x.offsetParent && [...x.options].some(o => o.value === 'ls1'));
    const set = Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, 'value').set; set.call(sel, ''); sel.dispatchEvent(new Event('change', { bubbles: true })); });
  await L.waitForTimeout(600);
  SL1 = await scL('sc1');
  ok('схему у сцены сняли — в свете осталось вписанное руками', JSON.stringify(SL1.lightGear) === JSON.stringify({ arri600: 2 }), JSON.stringify(SL1.lightGear));
  await L.evaluate(() => { const sel = [...document.querySelectorAll('select')].find(x => x.offsetParent && [...x.options].some(o => o.value === 'ls1'));
    const set = Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, 'value').set; set.call(sel, 'ls1'); sel.dispatchEvent(new Event('change', { bubbles: true })); });
  await L.waitForTimeout(600);
  SL1 = await scL('sc1');
  ok('выбрали схему снова — её приборы вернулись', SL1.lightGear.arri600 === 2 && SL1.lightGear.aputure_ls_600d_pro === 1 && SL1.lightGear.astera_titan_tube === 1 && SL1.lightGear['фонарь_петрович'] === 1,
     JSON.stringify(SL1.lightGear));
  ok('свет со схемы — в КПП и печати тем же списком (lightGear у записи сцены)', !!SL1.lightGear.astera_titan_tube);
  ok('свет сцены: ни одной ошибки страницы', errsL.length === 0, errsL.join(' | '));
  const cloudL = await L.evaluate(() => JSON.parse(JSON.stringify(window.__cfStore)));
  await ctxL.close();

  // Другое устройство открыло схему и ничего не правило — свет сцен
  // не трогается (пересчёт только после своей правки и ответа облака).
  const ctxL2 = await mkCtx(1440, 900, cloudL);
  const { page: L2 } = await open(ctxL2);
  await goBoards(L2); await L2.waitForTimeout(500);
  await press(L2, '[data-cf="scheme-tab"]');
  await L2.waitForFunction(() => window.__cfExc && window.__cfExc.api && window.__cfExc.boardId === 'ls1', { timeout: 60000 }).catch(() => {});
  await L2.waitForTimeout(2500);
  ok('другое устройство: открыло схему — свет сцен не переписан', (await writes(L2)).filter(w => w.coll === 'scenes').length === 0,
     JSON.stringify((await writes(L2)).filter(w => w.coll === 'scenes')));
  await ctxL2.close();

  // ================= ГОСТЬ ПО ССЫЛКЕ =================
  // Схема на Excalidraw — смотреть можно, перекладывать нельзя; старая
  // схема гостем не переводится, а открывается прежним редактором.
  const seedG = SEED();
  seedG.lightSchemes.ls3 = { id: 'ls3', title: 'Готовая', elements: [], drawData: '', engine: 'excalidraw', xc: 1 };
  seedG.boardEls = { 'ls3~g1': { b: 'ls3', id: 'g1', v: 1, e: JSON.stringify({ id: 'g1', type: 'rectangle', x: 100, y: 100, width: 120, height: 80, angle: 0,
    strokeColor: '#facc15', backgroundColor: 'transparent', fillStyle: 'solid', strokeWidth: 2, strokeStyle: 'solid', roughness: 0, opacity: 100, groupIds: [], frameId: null,
    index: 'a1', roundness: null, seed: 1, version: 1, versionNonce: 1, isDeleted: false, boundElements: null, updated: 1, link: null, locked: false }) } };
  const ctxG = await mkCtx(1440, 900, seedG);
  const { page: g, errs: errsG } = await open(ctxG, '/index.html?view=board&room=x-room');
  await g.waitForTimeout(600);
  const gTabs = await g.evaluate(() => [...document.querySelectorAll('[data-cf="scheme-tab"]')].map(b => b.textContent.trim()));
  await g.evaluate(() => { const b = [...document.querySelectorAll('[data-cf="scheme-tab"]')].find(x => /Готовая/.test(x.textContent)); b && b.click(); });
  await g.waitForFunction(() => window.__cfExc && window.__cfExc.api && window.__cfExc.boardId === 'ls3', { timeout: 60000 }).catch(() => {});
  await g.waitForTimeout(1200);
  const gv = await g.evaluate(() => ({ view: window.__cfExc.api.getAppState().viewModeEnabled, has: window.__cfExc.api.getSceneElements().some(e => e.id === 'g1'),
    fx: !!document.querySelector('[data-cf="fixture-tool"]') && getComputedStyle(document.querySelector('[data-cf="fixture-tool"]')).display !== 'none' }));
  ok('гость: схема на Excalidraw открывается для просмотра, «Прибора» нет', gTabs.length === 2 && gv.view && gv.has && !gv.fx, JSON.stringify({ gTabs, gv }));
  await g.evaluate(() => { const b = [...document.querySelectorAll('[data-cf="scheme-tab"]')].find(x => /кухни/.test(x.textContent)); b && b.click(); });
  await g.waitForTimeout(1200);
  ok('гость: старая схема не переводится, а открывается прежним редактором', (await store(g, 'lightSchemes')).ls1.engine === undefined
     && await g.evaluate(() => [...document.querySelectorAll('span')].some(s => s.textContent.trim() === 'Схема света' && s.closest('.fixed'))));
  ok('гость: наружу не ушло ничего', (await writes(g)).length === 0, JSON.stringify((await writes(g)).slice(0, 4)));
  ok('гость: ни одной ошибки страницы', errsG.length === 0, errsG.join(' | '));
  await ctxG.close();

  // ================= ТЕЛЕФОН =================
  const ctxP = await mkCtx(390, 844, SEED());
  const { page: ph, errs: errsP } = await open(ctxP);
  await goBoards(ph); await ph.waitForTimeout(600);
  await ph.evaluate(() => { const b = document.querySelector('[data-cf="scheme-tab"]'); b.scrollIntoView({ inline: 'center' }); });
  await ph.waitForTimeout(200);
  const pt = await press(ph, '[data-cf="scheme-tab"]');
  await ph.waitForFunction(() => window.__cfExc && window.__cfExc.api && window.__cfExc.boardId === 'ls1', { timeout: 60000 }).catch(() => {});
  await ph.waitForTimeout(1200);
  ok('телефон: вкладка схемы нажимается и открывает её холст', !!pt && pt.hit && await ph.evaluate(() => window.__cfExc.boardId === 'ls1'));
  const pf = await press(ph, '[data-cf="fixture-tool"]');
  await ph.waitForTimeout(300);
  const pr = await press(ph, '[data-cf="fixture-menu"] [data-fx="camera"]');
  await ph.waitForTimeout(500);
  ok('телефон: «Прибор» и строка «Камера» нажимаются, камера на схеме', !!pf && pf.hit && !!pr && pr.hit
     && await ph.evaluate(() => window.__cfExc.api.getSceneElements().filter(e => e.customData && e.customData.fx === 'camera').length === 4), JSON.stringify({ pf, pr }));
  await shot(ph, 'scheme-phone');
  ok('телефон: ни одной ошибки страницы', errsP.length === 0, errsP.join(' | '));
  await ctxP.close();

  // ================= ВСЁ РАЗОМ =================
  // Две старые доски: основная и «Доска 2», которую тут не открывали, —
  // её фигуры, стрелка к стикеру и штрих лежат ТОЛЬКО в облаке. Плюс две
  // старые схемы и доска, уже стоящая на Excalidraw.
  const shapesMain = [{ id: 'm1', k: 'rect', x: 100, y: 100, w: 160, h: 90, sc: '#d97757', bg: 'transparent', sw: 2, sd: 'solid', ro: 0, op: 1 }];
  const shapesB2 = [
    { id: 'b1', k: 'ellipse', x: 600, y: 100, w: 140, h: 100, sc: '#60a5fa', bg: 'transparent', sw: 2, sd: 'solid', ro: 0, op: 1 },
    { id: 'b2', k: 'arrow', x: 740, y: 150, w: 200, h: 120, sc: '#f0eee6', sw: 2, sd: 'solid', ro: 0, op: 1, a2: 'arrow', b1: 'b1', b2: 'stB', rt: 'straight' },
    { id: 'b3', k: 'text', x: 600, y: 400, w: 240, h: 30, tx: 'Свет из окна', fz: 20, ta: 'left', sc: '#f0eee6', op: 1 }
  ];
  const inkB2 = [{ id: 'k1', c: '#facc15', w: 4, p: [300, 500, 0.5, 340, 520, 0.5, 380, 540, 0.5, 420, 560, 0.5] }];
  const seedM = () => {
    const sd = SEED();
    sd.boards = { 'board-main': { id: 'board-main', title: 'Основная', order: 0 },
                  'board-b2': { id: 'board-b2', title: 'Доска 2', order: 1 },
                  bx9: { id: 'bx9', title: 'Уже Ex', order: 2, engine: 'excalidraw', xc: 1 } };
    sd.stickies = { stB: { id: 'stB', boardId: 'board-b2', x: 1000, y: 300, w: 224, h: 128, text: 'Контра', color: '#fef08a', sceneId: '' } };
    sd.canvas = { 'shape-board-main': { shapes: JSON.stringify(shapesMain), lastDrawBy: 'other' },
                  'shape-board-b2': { shapes: JSON.stringify(shapesB2), lastDrawBy: 'other' },
                  'ink-board-b2': { strokes: JSON.stringify(inkB2), n: 1, v: 1, lastDrawBy: 'other' } };
    sd.lightSchemes.ls2 = { id: 'ls2', title: 'Схема двора', elements: [{ id: 'q1', type: 'circle', x: 10, y: 10, w: 50, h: 50, color: '#f87171', label: 'HMI' }], drawData: '', preview: OLDPREV };
    return sd;
  };
  const ctxM = await mkCtx(1440, 900, seedM());
  const { page: m, errs: errsM } = await open(ctxM);
  await goBoards(m); await m.waitForTimeout(800);
  await press(m, 'button[title^="Выгрузить доску"]'); await m.waitForTimeout(250);
  const rowTxt = await m.evaluate(() => (document.querySelector('[data-cf="migrate-all"]') || {}).textContent || '');
  const row = await press(m, '[data-cf="migrate-all"]');
  ok('строка «Перевести всё на Excalidraw · 4» в «···» нажимается', !!row && row.hit && /Перевести всё на Excalidraw · 4/.test(rowTxt), rowTxt + ' ' + JSON.stringify(row));
  await m.waitForTimeout(300);
  ok('спрашивает спокойно и называет, что переведёт', /2 доски и 2 схемы света/.test(await m.evaluate(() => [...document.querySelectorAll('[role="dialog"]')].map(d => d.textContent).join(' '))));
  await press(m, '[data-cf="confirm-ok"]');
  await m.waitForTimeout(300);
  ok('пока идёт перевод, экран закрыт полосой с «Остановить»', await m.evaluate(() => !!document.querySelector('[data-cf="migrate-bar"]') && !!document.querySelector('[data-cf="migrate-stop"]')));
  await m.waitForFunction(() => !document.querySelector('[data-cf="migrate-bar"]'), { timeout: 150000 }).catch(() => {});
  await m.waitForTimeout(2500);
  const BM = await store(m, 'boards'), SM = await store(m, 'lightSchemes'), EM = await store(m, 'boardEls');
  ok('все старые доски на Excalidraw и помечены «переведена», готовая не тронута',
     BM['board-main'].engine === 'excalidraw' && BM['board-main'].from === 'own' && BM['board-b2'].engine === 'excalidraw' && BM['board-b2'].from === 'own' && !BM.bx9.from,
     JSON.stringify(Object.values(BM).map(b => [b.id, b.engine, b.from])));
  ok('обе схемы на Excalidraw', SM.ls1.engine === 'excalidraw' && SM.ls2.engine === 'excalidraw');
  const onB = (b) => Object.values(EM).filter(d => d.b === b).map(d => JSON.parse(d.e));
  const eb2 = onB('board-b2');
  ok('доска, которую тут не открывали, переведена ИЗ ОБЛАКА целиком: овал, стрелка, текст и штрих',
     ['o~b1', 'o~b2', 'o~b3', 'o~k1'].every(id => eb2.some(e => e.id === id)), eb2.map(e => e.id).join(','));
  const arr = eb2.find(e => e.id === 'o~b2');
  ok('стрелка держится за овал и за стикер-карточку', !!arr && arr.startBinding && arr.startBinding.elementId === 'o~b1' && arr.endBinding && arr.endBinding.elementId === 'stB',
     JSON.stringify(arr && [arr.startBinding, arr.endBinding]));
  ok('основная доска переведена', onB('board-main').some(e => e.id === 'o~m1'));
  ok('схема двора: прибор с подписью «HMI»', onB('ls2').some(e => e.id === 's~q1') && onB('ls2').some(e => e.id === 's~q1~l'));
  const CM = await store(m, 'canvas');
  ok('прежние данные досок в облаке не тронуты', CM['shape-board-b2'].shapes === JSON.stringify(shapesB2) && CM['ink-board-b2'].strokes === JSON.stringify(inkB2));
  ok('вернулись на доску, с которой начинали', await m.evaluate(() => window.__cfExc && window.__cfExc.boardId === 'board-main'));
  const tM = await m.evaluate(() => (document.querySelector('[data-cf="toast"]') || {}).textContent || '');
  ok('полоска называет исход: 4 из 4', /На Excalidraw: 4 из 4/.test(tM), tM);
  await press(m, 'button[title^="Выгрузить доску"]'); await m.waitForTimeout(250);
  ok('переводить больше нечего — строки нет', await m.evaluate(() => !document.querySelector('[data-cf="migrate-all"]')));
  await press(m, 'button[title^="Выгрузить доску"]'); await m.waitForTimeout(200);
  // «+» заводит доску сразу на Excalidraw.
  await press(m, '[data-cf="board-new"]'); await m.waitForTimeout(1200);
  const nbNew = Object.values(await store(m, 'boards')).find(b => !['board-main', 'board-b2', 'bx9'].includes(b.id));
  ok('«+» заводит новую доску на Excalidraw', !!nbNew && nbNew.engine === 'excalidraw' && nbNew.xc === 1, JSON.stringify(nbNew));
  ok('отдельной кнопки «+ Excalidraw» больше нет', await m.evaluate(() => ![...document.querySelectorAll('button')].some(b => b.textContent.trim() === '+ Excalidraw')));
  ok('перевод всего: ни одной ошибки страницы', errsM.length === 0, errsM.join(' | '));
  const cloudM = await m.evaluate(() => JSON.parse(JSON.stringify(window.__cfStore)));
  await ctxM.close();

  // Второе устройство: всё уже на Excalidraw, само ничего не переводит.
  const ctxN = await mkCtx(1440, 900, cloudM);
  const { page: q, errs: errsN } = await open(ctxN);
  await goBoards(q); await q.waitForTimeout(500);
  await q.evaluate(() => { const b = [...document.querySelectorAll('button')].find(x => x.textContent.trim().startsWith('Доска 2')); b && b.click(); });
  await q.waitForFunction(() => window.__cfExc && window.__cfExc.api && window.__cfExc.boardId === 'board-b2', { timeout: 60000 }).catch(() => {});
  await q.waitForTimeout(1500);
  const Eq = live(await els(q));
  ok('другое устройство: «Доска 2» на Excalidraw со всем переведённым, без задвоений',
     ['o~b1', 'o~b2', 'o~b3', 'o~k1'].every(id => Eq.filter(e => e.id === id).length === 1) && !!Eq.find(e => e.id === 'stB'), Eq.map(e => e.id).join(','));
  ok('другое устройство: ни одной записи досок от одного открытия', (await writes(q)).filter(w => w.coll === 'boardEls' || w.coll === 'boards').length === 0,
     JSON.stringify((await writes(q)).slice(0, 5)));
  ok('другое устройство: ни одной ошибки страницы', errsN.length === 0, errsN.join(' | '));
  await ctxN.close();

  // МЕДЛЕННОЕ ОБЛАКО: рисунок досок приходит через 2,5 секунды. Перевод
  // обязан его дождаться — иначе «Доска 2» переехала бы пустой.
  const ctxD = await mkCtx(1440, 900, seedM(), `window.__cfDocDelay = { canvas: 2500 };`);
  const { page: dp } = await open(ctxD);
  await goBoards(dp); await dp.waitForTimeout(800);
  await press(dp, 'button[title^="Выгрузить доску"]'); await dp.waitForTimeout(250);
  await press(dp, '[data-cf="migrate-all"]'); await dp.waitForTimeout(250);
  await press(dp, '[data-cf="confirm-ok"]');
  await dp.waitForTimeout(500);
  await dp.waitForFunction(() => !document.querySelector('[data-cf="migrate-bar"]'), { timeout: 150000 }).catch(() => {});
  await dp.waitForTimeout(2500);
  const eD = Object.values(await store(dp, 'boardEls')).filter(d => d.b === 'board-b2').map(d => JSON.parse(d.e).id);
  ok('медленное облако: перевод дождался рисунка — на «Доске 2» всё', ['o~b1', 'o~b2', 'o~b3', 'o~k1'].every(id => eD.includes(id)), eD.join(','));
  await ctxD.close();

  // «Остановить» сразу: перевелось меньше, и полоска это говорит.
  const ctxS = await mkCtx(1440, 900, seedM());
  const { page: sp } = await open(ctxS);
  await goBoards(sp); await sp.waitForTimeout(800);
  await press(sp, 'button[title^="Выгрузить доску"]'); await sp.waitForTimeout(250);
  await press(sp, '[data-cf="migrate-all"]'); await sp.waitForTimeout(250);
  await press(sp, '[data-cf="confirm-ok"]');
  await sp.waitForFunction(() => !!document.querySelector('[data-cf="migrate-stop"]'), { timeout: 10000 }).catch(() => {});
  await press(sp, '[data-cf="migrate-stop"]');
  await sp.waitForFunction(() => !document.querySelector('[data-cf="migrate-bar"]'), { timeout: 60000 }).catch(() => {});
  await sp.waitForTimeout(500);
  const tS = await sp.evaluate(() => (document.querySelector('[data-cf="toast"]') || {}).textContent || '');
  const BS = await store(sp, 'boards');
  ok('«Остановить» прерывает обход и говорит, сколько успели', /Перевод остановлен/.test(tS) && !(BS['board-main'].engine === 'excalidraw' && BS['board-b2'].engine === 'excalidraw'), tS);
  await ctxS.close();

  console.log(bad ? `\n${bad} FAIL` : '\nвсё зелёное');
  await browser.close(); server.kill();
  process.exit(bad ? 1 : 0);
})().catch(e => { console.error(e); server.kill(); process.exit(1); });
