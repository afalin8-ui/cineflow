// ПРОБНАЯ ДОСКА НА EXCALIDRAW: карточки проекта — его родные элементы,
// связи проекта целы, нарисованное лежит в облаке по элементу.
//
// Проверяется В БРАУЗЕРЕ и настоящей мышью: что карточку можно утащить,
// видно только тогда, когда её утащили. Облако ПОДДЕЛЬНОЕ (fake-cloud.js),
// настоящий Firebase заблокирован — живой проект трогать нельзя. В его
// журнале видно, ЧТО ушло наружу.
//
// Что гоняем:
//   карточки сцен, фото, стикера и кадра на доске, связи «к сцене»
//   → перенос фото мышью пишет место в САМУ запись референса
//   → нарисованный прямоугольник уезжает в облако отдельным элементом
//   → стрелка от стикера к сцене привязывает стикер к сцене
//   → стёртая связь отвязывает, стёртая карточка снимается с доски,
//     а сцена остаётся в проекте
//   → правка текста стикера ложится в запись стикера
//   → вставка картинки становится референсом на этой доске
//   → перезагрузка: всё на месте
//   → чужое устройство добавило и стёрло элемент — видно здесь
//   → ОБОРВАННАЯ СВЯЗЬ: пустой ответ «из кэша» не стирает нарисованное
//     и не шлёт в облако ни одного удаления
//   → режим просмотра: наружу не уходит ничего
//   → телефон: доска открывается, рисовать есть чем
//   → своя доска рядом по-прежнему на своём движке
//
// Запуск:  node tests/excboard-e2e.js
const path = require('path'), fs = require('fs'), os = require('os'), zlib = require('zlib');
const { execSync, spawn } = require('child_process');
const ROOT = path.resolve(__dirname, '..');
const LIBS = process.env.CF_LIBS || path.join(os.tmpdir(), 'cineflow-libs');
const PORT = process.env.CF_PORT || '8173';
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

// Картинка без внешних файлов: PNG одного цвета.
const png = (w, h, rgb) => {
  const T = []; for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; T[n] = c >>> 0; }
  const crc = (b) => { let c = 0xffffffff; for (const x of b) c = T[(c ^ x) & 255] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
  const chunk = (t, d) => { const l = Buffer.alloc(4); l.writeUInt32BE(d.length); const td = Buffer.concat([Buffer.from(t), d]); const c = Buffer.alloc(4); c.writeUInt32BE(crc(td)); return Buffer.concat([l, td, c]); };
  const ih = Buffer.alloc(13); ih.writeUInt32BE(w, 0); ih.writeUInt32BE(h, 4); ih[8] = 8; ih[9] = 2;
  const raw = Buffer.alloc((w * 3 + 1) * h);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) { const o = y * (w * 3 + 1) + 1 + x * 3; raw[o] = rgb[0]; raw[o + 1] = rgb[1]; raw[o + 2] = rgb[2]; }
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ih), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
};
const IMG = 'data:image/png;base64,' + png(90, 60, [200, 60, 40]).toString('base64');
const PASTE = png(64, 48, [40, 90, 200]).toString('base64');

const SEED = () => ({
  boards: { 'board-main': { id: 'board-main', title: 'Основная', order: 0 },
            bx1: { id: 'bx1', title: 'Excalidraw', order: 1, engine: 'excalidraw' } },
  scenes: {
    sc1: { id: 'sc1', number: '1', title: 'ИНТ. КВАРТИРА', content: 'Утро, свет из окна', boardId: 'bx1', x: 100, y: 100, gear: {}, lightGear: {} },
    sc2: { id: 'sc2', number: '2', title: 'НАТ. ДВОР', content: '', boardId: 'bx1', x: 700, y: 100, gear: {}, lightGear: {} },
    sc3: { id: 'sc3', number: '3', title: 'ИНТ. ПОДЪЕЗД', content: '', boardId: '', x: 0, y: 0, gear: {}, lightGear: {} }
  },
  references: { r1: { id: 'r1', url: IMG, boardId: 'bx1', x: 100, y: 420, w: 180, ar: 1.5, sceneId: 'sc1', tags: [], label: '' } },
  stickies: { st1: { id: 'st1', boardId: 'bx1', x: 420, y: 700, w: 224, h: 128, text: 'Свет из окна', color: '#fef08a', sceneId: '' } },
  storyboard: { f1: { id: 'f1', sceneId: 'sc2', frameNum: '2.1', description: 'общий план', image: IMG, boardId: 'bx1', x: 760, y: 420, w: 240 } }
});

(async () => {
  await new Promise(r => setTimeout(r, 1200));
  const browser = await playwright.chromium.launch({ executablePath: process.env.CF_CHROME || '/opt/pw-browsers/chromium', args: ['--no-sandbox'] });

  const mkCtx = async (w, h, seed, init) => {
    // Service worker БЛОКИРУЕМ: иначе на втором заходе он отдаёт запросы
    // мимо подмены библиотек, и страница остаётся без React.
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
      localStorage.setItem('cf_active_board', 'bx1');
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
    await page.waitForTimeout(700);
    // На доски — через строку модулей (на телефоне через «Ещё»).
    await page.evaluate(async () => {
      const tab = [...document.querySelectorAll('button')].find(x => x.title === 'Доски' || x.textContent.trim() === 'Доски');
      if (tab) tab.click();
      else {
        const more = [...document.querySelectorAll('.cf-tabbar button, header button')].find(x => /Ещё/.test(x.textContent));
        if (more) { more.click(); await new Promise(r => setTimeout(r, 400)); }
        const d = [...document.querySelectorAll('button')].find(x => x.textContent.trim() === 'Доски');
        if (d) d.click();
      }
    });
    await page.waitForTimeout(600);
    // Список досок приезжает из облака после старта: выбранная пробная
    // доска могла смениться основной. Жмём её вкладку.
    await page.evaluate(() => {
      const t = [...document.querySelectorAll('button')].find(b => /^Excalidraw\s*Ex$/.test(b.textContent.trim()));
      if (t) t.click();
    });
    await page.waitForFunction(() => window.__cfExc && window.__cfExc.api && window.__cfExc.boardId === 'bx1', { timeout: 60000 });
    await page.waitForTimeout(900);
    return { page, errs };
  };
  // Сцена Excalidraw глазами проверки.
  const els = (page) => page.evaluate(() => window.__cfExc.api.getSceneElementsIncludingDeleted().map(e => ({
    id: e.id, type: e.type, del: e.isDeleted, x: e.x, y: e.y, w: e.width, h: e.height, cd: e.customData || null,
    sb: e.startBinding && e.startBinding.elementId, eb: e.endBinding && e.endBinding.elementId, text: e.originalText || e.text || ''
  })));
  const live = (list) => list.filter(e => !e.del);
  // Точка экрана для точки доски.
  const scr = (page, x, y) => page.evaluate(([x, y]) => {
    const s = window.__cfExc.api.getAppState();
    return { x: (x + s.scrollX) * s.zoom.value + s.offsetLeft, y: (y + s.scrollY) * s.zoom.value + s.offsetTop };
  }, [x, y]);
  const store = (page, coll) => page.evaluate((c) => JSON.parse(JSON.stringify((window.__cfStore || {})[c] || {})), coll);
  const writes = (page) => page.evaluate(() => (window.__cfWrites || []).slice());
  const settle = (page, ms = 1300) => page.waitForTimeout(ms);
  const drag = async (page, a, b) => {
    await page.mouse.move(a.x, a.y); await page.mouse.down();
    await page.mouse.move((a.x + b.x) / 2, (a.y + b.y) / 2, { steps: 6 });
    await page.mouse.move(b.x, b.y, { steps: 6 }); await page.mouse.up();
  };
  const escape = async (page) => { await page.keyboard.press('Escape'); await page.waitForTimeout(150); };

  // ================= НОУТБУК =================
  const ctx = await mkCtx(1440, 900, SEED());
  const { page: p, errs } = await open(ctx);

  // --- 1. карточки и связи
  let E = live(await els(p));
  const has = (id) => E.some(e => e.id === id);
  ok('сцены, фото, стикер и кадр — родные элементы Excalidraw',
     has('sc1') && has('sc2') && has('r1') && has('st1') && has('f1') && !has('sc3'),
     E.filter(e => e.cd).map(e => e.id).join(' '));
  const lnk = E.find(e => e.id === 'lnk~r1');
  ok('связь «фото → сцена 1» нарисована и держится за обе карточки', !!lnk && lnk.sb === 'r1' && lnk.eb === 'sc1');
  ok('кадр 2.1 привязан к своей сцене', E.some(e => e.id === 'lnk~f1' && e.eb === 'sc2'));
  const title = E.find(e => e.id === 'sc1~t');
  ok('на карточке сцены — номер и название из записи', !!title && /#1\s+ИНТ\. КВАРТИРА/.test(title.text), title && title.text);
  ok('подпись кадра — номер из раскадровки', (E.find(e => e.id === 'f1~c') || {}).text === '2.1 · общий план');
  // Нажатие по карточке попадает в холст Excalidraw, а не в чужой слой.
  const hitCard = await p.evaluate(async () => {
    const s = window.__cfExc.api.getAppState();
    const x = (190 + s.scrollX) * s.zoom.value + s.offsetLeft, y = (480 + s.scrollY) * s.zoom.value + s.offsetTop;
    const el = document.elementFromPoint(x, y);
    return el && el.tagName + '.' + el.className;
  });
  ok('нажатие по фото попадает в холст Excalidraw', /CANVAS/.test(hitCard || '') && /interactive/.test(hitCard || ''), hitCard);

  // --- 2. перенос фото мышью → место в записи референса
  const a = await scr(p, 190, 480), b = await scr(p, 290, 560);
  await drag(p, a, b);
  await settle(p);
  let R = await store(p, 'references');
  ok('фото утащили мышью — место легло в запись референса', Math.abs(R.r1.x - 200) <= 2 && Math.abs(R.r1.y - 500) <= 2, `x=${R.r1.x} y=${R.r1.y}`);
  E = live(await els(p));
  const l2 = E.find(e => e.id === 'lnk~r1');
  ok('связь со сценой поехала следом', !!l2 && l2.x > 200, l2 && `x=${Math.round(l2.x)}`);
  await escape(p);

  // --- 3. рисуем прямоугольник → в облако отдельным элементом
  const w0 = (await writes(p)).length;
  await p.keyboard.press('2');
  const r0 = await scr(p, 1100, 700), r1 = await scr(p, 1250, 800);
  await drag(p, r0, r1);
  await escape(p);
  await p.keyboard.press('1');
  await settle(p);
  let B = await store(p, 'boardEls');
  const rects = Object.values(B).filter(d => d.b === 'bx1' && /"type":"rectangle"/.test(d.e));
  ok('нарисованный прямоугольник уехал в облако отдельным документом', rects.length === 1, `${rects.length} шт.`);
  const newWrites = (await writes(p)).slice(w0).map(x => x.coll);
  ok('карточки в облако нарисованным НЕ пишутся', !Object.values(B).some(d => /"customData":\{"cf"/.test(d.e)), newWrites.join(','));
  const rectId = rects[0] && JSON.parse(rects[0].e).id;

  // --- 4. стрелка от стикера к сцене 2 = привязать стикер к сцене
  const s0 = await scr(p, 530, 760), s1 = await scr(p, 840, 160);
  await p.keyboard.press('5');
  await drag(p, s0, s1);
  await escape(p);
  await p.keyboard.press('1');
  await settle(p, 1600);
  let ST = await store(p, 'stickies');
  E = await els(p);
  ok('стрелка от стикера к сцене привязала стикер к сцене', ST.st1 && ST.st1.sceneId === 'sc2', ST.st1 && ST.st1.sceneId);
  ok('вместо нарисованной стрелки — связь проекта', live(E).some(e => e.id === 'lnk~st1' && e.eb === 'sc2')
     && !live(E).some(e => e.type === 'arrow' && !e.cd), live(E).filter(e => e.type === 'arrow').map(e => e.id).join(' '));
  B = await store(p, 'boardEls');
  ok('эта стрелка в облако нарисованной не уехала', !Object.values(B).some(d => /"type":"arrow"/.test(d.e)));

  // --- 5. стёрли связь → отвязали; стёрли карточку сцены → сняли с доски
  await p.evaluate(() => {
    const a = window.__cfExc.api;
    a.updateScene({ appState: { selectedElementIds: { 'lnk~r1': true } } });
  });
  await p.keyboard.press('Delete');
  await settle(p);
  R = await store(p, 'references');
  ok('стёрли связь на доске — фото отвязано от сцены', R.r1.sceneId === '', JSON.stringify(R.r1.sceneId));
  await p.evaluate(() => window.__cfExc.api.updateScene({ appState: { selectedElementIds: { sc2: true } } }));
  await p.keyboard.press('Delete');
  await settle(p);
  let SC = await store(p, 'scenes');
  ok('стёрли сцену на доске — она снята с доски, но осталась в проекте', SC.sc2 && SC.sc2.boardId === '' && SC.sc2.title === 'НАТ. ДВОР', JSON.stringify(SC.sc2 && SC.sc2.boardId));
  E = await els(p);
  ok('её связи ушли с доски вместе с ней', !live(E).some(e => e.id === 'lnk~f1' || e.id === 'lnk~st1'));
  // «отменить» возвращает сцену на доску
  await p.keyboard.press('Control+z');
  await settle(p);
  SC = await store(p, 'scenes');
  ok('«отменить» вернуло сцену на доску', SC.sc2 && SC.sc2.boardId === 'bx1', JSON.stringify(SC.sc2 && SC.sc2.boardId));

  // --- 6. текст стикера правится на доске и ложится в запись
  const stc = await scr(p, 420 + 112, 700 + 64);
  await p.mouse.dblclick(stc.x, stc.y);
  await p.waitForTimeout(300);
  await p.keyboard.press('Control+a');
  await p.keyboard.type('Контровой свет');
  await escape(p);
  await settle(p);
  ST = await store(p, 'stickies');
  ok('текст стикера, набранный на доске, лёг в запись стикера', ST.st1 && ST.st1.text === 'Контровой свет', ST.st1 && ST.st1.text);

  // --- 7. правка подписи сцены на доске не держится: название — из записи
  const sct = await scr(p, 100 + 60, 100 + 12);
  await p.mouse.dblclick(sct.x, sct.y);
  await p.waitForTimeout(300);
  await p.keyboard.type(' ЛИШНЕЕ');
  await escape(p);
  await settle(p);
  E = live(await els(p));
  SC = await store(p, 'scenes');
  ok('подпись сцены вернулась к записи, а сама сцена не тронута', /#1\s+ИНТ\. КВАРТИРА/.test((E.find(e => e.id === 'sc1~t') || {}).text || '')
     && !/ЛИШНЕЕ/.test((E.find(e => e.id === 'sc1~t') || {}).text || '') && SC.sc1.title === 'ИНТ. КВАРТИРА');

  // --- 8. вставка картинки → референс на этой доске
  const before = Object.keys(await store(p, 'references')).length;
  await p.evaluate(async (b64) => {
    const bin = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
    const f = new File([bin], 'image.png', { type: 'image/png' });
    const dt = new DataTransfer(); dt.items.add(f);
    document.dispatchEvent(new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }));
  }, PASTE);
  await settle(p, 2500);
  R = await store(p, 'references');
  const added = Object.values(R).filter(r => r.id !== 'r1');
  ok('вставленная картинка стала референсом ЭТОЙ доски, одна', Object.keys(R).length === before + 1 && added[0] && added[0].boardId === 'bx1',
     added.map(r => r.boardId).join(','));
  E = live(await els(p));
  ok('и лежит на доске картинкой', added[0] && E.some(e => e.id === added[0].id && e.type === 'image'));
  ok('своего элемента-картинки Excalidraw не завёл', !E.some(e => e.type === 'image' && !e.cd));

  // --- 8б. «Положить на доску» и «Стикер» над доской — те же кнопки,
  // что у своей доски, и кладут в ВИДИМУЮ часть доски Excalidraw.
  const view = await p.evaluate(() => { const s = window.__cfExc.api.getAppState();
    return { x0: -s.scrollX, y0: -s.scrollY, x1: -s.scrollX + s.width / s.zoom.value, y1: -s.scrollY + s.height / s.zoom.value }; });
  const inView = (x, y) => x >= view.x0 - 5 && x <= view.x1 && y >= view.y0 - 5 && y <= view.y1;
  const picked = await p.evaluate(async () => {
    const b = [...document.querySelectorAll('button')].find(x => /^Положить на доску/.test(x.title || ''));
    b.click(); await new Promise(r => setTimeout(r, 400));
    const panel = document.querySelector('[data-cf="board-picker"]');
    const row = panel && [...panel.querySelectorAll('button')].find(x => /ИНТ\. ПОДЪЕЗД/.test(x.textContent));
    if (!row) return { err: 'нет строки сцены 3', panel: !!panel };
    const r = row.getBoundingClientRect(), hit = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
    row.click(); await new Promise(r2 => setTimeout(r2, 500));
    return { hit: !!hit && (hit === row || row.contains(hit)) };
  });
  await settle(p);
  SC = await store(p, 'scenes');
  E = live(await els(p));
  const sc3 = E.find(e => e.id === 'sc3');
  ok('«Положить на доску»: строка сцены в панели нажимается', picked.hit === true, JSON.stringify(picked));
  ok('сцена легла на доску Excalidraw и в видимую её часть', SC.sc3.boardId === 'bx1' && !!sc3 && inView(sc3.x, sc3.y), sc3 && `${Math.round(sc3.x)},${Math.round(sc3.y)} в ${JSON.stringify(view)}`);
  const nSt = Object.keys(await store(p, 'stickies')).length;
  await p.evaluate(() => [...document.querySelectorAll('button')].find(x => x.title === 'Стикер').click());
  await settle(p);
  ST = await store(p, 'stickies');
  const fresh = Object.values(ST).find(x => x.id !== 'st1');
  E = live(await els(p));
  const selIds = await p.evaluate(() => Object.keys(window.__cfExc.api.getAppState().selectedElementIds || {}));
  ok('«Стикер» над доской: новый стикер на доске, в видимой части и выделен',
     Object.keys(ST).length === nSt + 1 && fresh && fresh.boardId === 'bx1' && E.some(e => e.id === fresh.id) && inView(fresh.x, fresh.y) && selIds.includes(fresh.id),
     JSON.stringify({ fresh: fresh && [fresh.x, fresh.y], selIds }));

  // --- 9. второе устройство открывает ту же доску: всё из облака
  // (поддельное облако живёт в странице, поэтому «перезагрузка» — это
  // новый браузер, засеянный тем, что лежит в облаке сейчас: заодно
  // так видно, что на устройстве ничего своего не понадобилось).
  const cloudNow = await p.evaluate(() => JSON.parse(JSON.stringify(window.__cfStore)));
  const ctxB = await mkCtx(1440, 900, cloudNow);
  const { page: p2, errs: errs2 } = await open(ctxB);
  await p2.waitForTimeout(800);
  E = live(await els(p2));
  const rr = E.find(e => e.id === 'r1');
  ok('другое устройство: прямоугольник на месте', E.some(e => e.id === rectId));
  ok('другое устройство: фото там, куда утащили', rr && Math.abs(rr.x - 200) <= 2 && Math.abs(rr.y - 500) <= 2, rr && `${rr.x},${rr.y}`);
  ok('другое устройство: стикер со своим текстом и связью', E.some(e => e.id === 'st1~t' && e.text === 'Контровой свет') && E.some(e => e.id === 'lnk~st1'));
  ok('другое устройство: ни одной ошибки страницы', errs2.length === 0, errs2.join(' | '));
  await ctxB.close();

  // --- 10. чужое устройство добавило элемент и стёрло прямоугольник
  await p.evaluate((rectId) => {
    const st = window.__cfStore; st.boardEls = st.boardEls || {};
    const el = { id: 'remote-ellipse', type: 'ellipse', x: 1100, y: 300, width: 120, height: 80, angle: 0, strokeColor: '#1e1e1e',
      backgroundColor: 'transparent', fillStyle: 'solid', strokeWidth: 2, strokeStyle: 'solid', roughness: 1, opacity: 100,
      // Ключ порядка нарочно КРИВОЙ («b0» — такого ключа не бывает):
      // облако пишут разные устройства, и доска обязана это пережить.
      groupIds: [], frameId: null, index: 'b0', roundness: null, seed: 5, version: 3, versionNonce: 7, isDeleted: false,
      boundElements: null, updated: 1, link: null, locked: false };
    st.boardEls['bx1~remote-ellipse'] = { b: 'bx1', id: el.id, v: 3, e: JSON.stringify(el) };
    delete st.boardEls['bx1~' + rectId];
    window.__cfEmit('boardEls');
  }, rectId);
  await settle(p);
  E = live(await els(p));
  ok('элемент с другого устройства появился', E.some(e => e.id === 'remote-ellipse'));
  ok('стёртый на другом устройстве — исчез', !E.some(e => e.id === rectId));
  ok('в консоли ни одной ошибки страницы', errs.length === 0, errs.join(' | '));

  // --- 11. выгрузка картинкой
  const dl = p.waitForEvent('download', { timeout: 15000 }).catch(() => null);
  await p.evaluate(async () => {
    const m = [...document.querySelectorAll('button')].find(b => b.textContent.trim() === '···' && /Выгрузить/.test(b.title));
    m.click(); await new Promise(r => setTimeout(r, 300));
    [...document.querySelectorAll('.cf-menu button')].find(b => /PNG/.test(b.textContent)).click();
  });
  const d = await dl;
  let pngOk = false;
  if (d) { const f = await d.path(); const buf = fs.readFileSync(f); pngOk = buf.slice(1, 4).toString() === 'PNG' && buf.length > 2000; }
  ok('«Выгрузить PNG» отдаёт картинку доски', pngOk, d ? d.suggestedFilename() : 'нет загрузки');

  // --- 12. своя доска рядом по-прежнему своя
  await p.evaluate(() => { const t = [...document.querySelectorAll('button')].find(b => b.textContent.trim().startsWith('Основная')); t.click(); });
  await p.waitForTimeout(800);
  const own = await p.evaluate(() => ({ old: !!document.getElementById('whiteboard-canvas'), exc: !!document.querySelector('[data-cf="exc-board"]') }));
  ok('вкладка «Основная» открывает свою доску, а не Excalidraw', own.old && !own.exc, JSON.stringify(own));
  await ctx.close();

  // ================= ОБОРВАННАЯ СВЯЗЬ =================
  // Открыли без сети: облако отвечает «из кэша» и пусто, а на устройстве
  // лежит нарисованное, которое облако уже видело. Стирать его нельзя —
  // пустой ответ из кэша ничего не говорит о том, что есть на сервере.
  const seed2 = SEED();
  const known = { id: 'known-rect', type: 'rectangle', x: 1000, y: 200, width: 100, height: 60, angle: 0, strokeColor: '#1e1e1e',
    backgroundColor: 'transparent', fillStyle: 'solid', strokeWidth: 2, strokeStyle: 'solid', roughness: 1, opacity: 100, groupIds: [],
    frameId: null, index: 'a1', roundness: null, seed: 3, version: 4, versionNonce: 11, isDeleted: false, boundElements: null, updated: 1, link: null, locked: false };
  seed2.boardEls = { 'bx1~known-rect': { b: 'bx1', id: 'known-rect', v: 4, e: JSON.stringify(known) } };
  // Нарисованное без связи и ещё не уехавшее — да ещё с кривым ключом
  // порядка: Excalidraw на таком роняет загрузку всей сцены.
  const offline = { ...known, id: 'offline-line', x: 1000, y: 400, index: 'b1', version: 2, versionNonce: 5 };
  const ctx2 = await mkCtx(1440, 900, seed2, `
    localStorage.setItem('cf_xb_bx1', ${JSON.stringify(JSON.stringify({ els: [known, offline], known: { 'known-rect': 4 } }))});
    window.__cfCacheOnly.boardEls = true;
  `);
  const { page: q } = await open(ctx2);
  await q.waitForTimeout(800);
  let E2 = live(await els(q));
  const w2 = await writes(q);
  ok('без сети: нарисованное с устройства на месте', E2.some(e => e.id === 'known-rect'));
  ok('без сети: ни одного удаления в облако', !w2.some(x => x.coll === 'boardEls' && x.del), JSON.stringify(w2.filter(x => x.coll === 'boardEls')));
  // Связь вернулась — пришёл ответ сервера, а в нём элемент есть.
  await q.evaluate(() => { window.__cfCacheOnly.boardEls = false; window.__cfEmit('boardEls'); });
  await settle(q);
  E2 = live(await els(q));
  ok('связь вернулась — элемент на месте, облако цело', E2.some(e => e.id === 'known-rect') && !!(await store(q, 'boardEls'))['bx1~known-rect']);
  const up = (await store(q, 'boardEls'))['bx1~offline-line'];
  ok('нарисованное без связи (с кривым ключом) открылось и уехало в облако с исправным ключом',
     E2.some(e => e.id === 'offline-line') && up && JSON.parse(up.e).index !== 'b1', up ? JSON.parse(up.e).index : 'не уехало');
  // А теперь сервер ответил БЕЗ него — его стёрли на другом устройстве.
  await q.evaluate(() => { delete window.__cfStore.boardEls['bx1~known-rect']; window.__cfEmit('boardEls'); });
  await settle(q);
  ok('ответ сервера без элемента — стёрли на другом устройстве, ушёл и тут', !live(await els(q)).some(e => e.id === 'known-rect'));
  await ctx2.close();

  // ================= РЕЖИМ ПРОСМОТРА =================
  const ctx3 = await mkCtx(1440, 900, SEED());
  const { page: v } = await open(ctx3, '/index.html?view=board&board=bx1&room=x-room');
  const vw0 = (await writes(v)).length;
  const vm = await v.evaluate(() => window.__cfExc.api.getAppState().viewModeEnabled);
  ok('гостю доска открыта только для просмотра', vm === true);
  const va = await scr(v, 190, 480), vb = await scr(v, 400, 600);
  await drag(v, va, vb);
  await v.keyboard.press('Delete');
  await settle(v);
  ok('гость подвигал и нажал Delete — наружу не ушло ничего', (await writes(v)).length === vw0, JSON.stringify((await writes(v)).slice(vw0)));
  await ctx3.close();

  // ================= ТЕЛЕФОН =================
  const ctx4 = await mkCtx(390, 844, SEED());
  const { page: ph, errs: perr } = await open(ctx4);
  E = live(await els(ph));
  ok('телефон: доска открылась с карточками', E.some(e => e.id === 'sc1') && E.some(e => e.id === 'r1'));
  const tools = await ph.evaluate(() => {
    const t = document.querySelector('.excalidraw .App-toolbar, .excalidraw .mobile-misc-tools-container, .excalidraw .App-bottom-bar');
    if (!t) return null;
    const r = t.getBoundingClientRect();
    return { top: Math.round(r.top), bottom: Math.round(r.bottom), vh: window.innerHeight };
  });
  ok('телефон: панель инструментов на экране', !!tools && tools.bottom <= tools.vh + 1 && tools.top >= 0, JSON.stringify(tools));
  ok('телефон: ни одной ошибки страницы', perr.length === 0, perr.join(' | '));
  await ctx4.close();

  await browser.close();
  server.kill();
  console.log(bad ? `\n${bad} FAIL` : '\nвсё зелёное');
  process.exit(bad ? 1 : 0);
})().catch(e => { console.error(e); server.kill(); process.exit(1); });
