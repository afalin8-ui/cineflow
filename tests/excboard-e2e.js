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
//   → ФОТО: цвет на экране ровно тот, что в файле (холст не выворачивается),
//     уменьшение без ряби (полосы в одну точку становятся ровным серым),
//     пропорция из самого файла и записывается в референс, кадр
//     раскадровки обрезается по рамке проекта, а не растягивается
//   → доска, нарисованная при прежней выворачивающей теме, переводит
//     свои цвета один раз и метит себя
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
  const px = typeof rgb === 'function' ? rgb : () => rgb;
  const T = []; for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; T[n] = c >>> 0; }
  const crc = (b) => { let c = 0xffffffff; for (const x of b) c = T[(c ^ x) & 255] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
  const chunk = (t, d) => { const l = Buffer.alloc(4); l.writeUInt32BE(d.length); const td = Buffer.concat([Buffer.from(t), d]); const c = Buffer.alloc(4); c.writeUInt32BE(crc(td)); return Buffer.concat([l, td, c]); };
  const ih = Buffer.alloc(13); ih.writeUInt32BE(w, 0); ih.writeUInt32BE(h, 4); ih[8] = 8; ih[9] = 2;
  const raw = Buffer.alloc((w * 3 + 1) * h);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) { const o = y * (w * 3 + 1) + 1 + x * 3, c = px(x, y); raw[o] = c[0]; raw[o + 1] = c[1]; raw[o + 2] = c[2]; }
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ih), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
};
const IMG = 'data:image/png;base64,' + png(90, 60, [200, 60, 40]).toString('base64');
const PASTE = png(64, 48, [40, 90, 200]).toString('base64');
// Вертикальные полосы в ОДНУ точку, чёрная-белая. Честное уменьшение
// сливает их в ровный серый; грубое (выборка без усреднения) даёт рябь —
// её и меряем разбросом яркости. Пропорция 3:2, а записи о ней нет.
const STRIPES = 'data:image/png;base64,' + png(1200, 800, (x) => x % 2 ? [255, 255, 255] : [0, 0, 0]).toString('base64');

const SEED = () => ({
  boards: { 'board-main': { id: 'board-main', title: 'Основная', order: 0 },
            bx1: { id: 'bx1', title: 'Excalidraw', order: 1, engine: 'excalidraw', xc: 1 } },
  scenes: {
    sc1: { id: 'sc1', number: '1', title: 'ИНТ. КВАРТИРА', content: 'Утро, свет из окна', boardId: 'bx1', x: 100, y: 100, gear: {}, lightGear: {} },
    sc2: { id: 'sc2', number: '2', title: 'НАТ. ДВОР', content: '', boardId: 'bx1', x: 700, y: 100, gear: {}, lightGear: {} },
    sc3: { id: 'sc3', number: '3', title: 'ИНТ. ПОДЪЕЗД', content: '', boardId: '', x: 0, y: 0, gear: {}, lightGear: {} }
  },
  references: { r1: { id: 'r1', url: IMG, boardId: 'bx1', x: 100, y: 420, w: 180, ar: 1.5, sceneId: 'sc1', tags: [], label: '' },
                r2: { id: 'r2', url: STRIPES, boardId: 'bx1', x: 1100, y: 420, w: 200, sceneId: '', tags: [], label: '' },
                // Ролик: постер в url, сам файл «в облаке».
                rv: { id: 'rv', url: IMG, video: true, dur: 42, full: 'https://example.invalid/clip.mp4', boardId: 'bx1', x: 100, y: 1000, w: 180, ar: 1.5,
                      sceneId: '', tags: ['видео'], label: '' } },
  stickies: { st1: { id: 'st1', boardId: 'bx1', x: 420, y: 700, w: 224, h: 128, text: 'Свет из окна', color: '#fef08a', sceneId: '' } },
  storyboard: { f1: { id: 'f1', sceneId: 'sc2', frameNum: '2.1', description: 'общий план', image: IMG, boardId: 'bx1', x: 760, y: 420, w: 240, shot: true } }
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
  const ctx = await mkCtx(1440, 900, SEED(), `localStorage.setItem('cf_gemini_key', 'AIza-test-key');`);
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

  // --- 1б. фото
  // Цвет — по СНИМКУ ЭКРАНА, а не по холсту: выворачивал фильтр именно
  // экранный слой.
  const pxAt = async (page, x, y) => {
    const q = await scr(page, x, y);
    const buf = await page.screenshot({ clip: { x: Math.round(q.x), y: Math.round(q.y), width: 1, height: 1 } });
    return page.evaluate(async (b64) => {
      const img = new Image(); img.src = 'data:image/png;base64,' + b64; await img.decode();
      const c = document.createElement('canvas'); c.width = c.height = 1;
      const x = c.getContext('2d'); x.drawImage(img, 0, 0); return [...x.getImageData(0, 0, 1, 1).data].slice(0, 3);
    }, buf.toString('base64'));
  };
  const red = await pxAt(p, 190, 480);
  ok('цвет фото на экране — как в файле (200, 60, 40)', red.every((v, i) => Math.abs(v - [200, 60, 40][i]) <= 2), red.join(','));
  const filt = await p.evaluate(() => getComputedStyle(document.querySelector('.excalidraw__canvas.static')).filter);
  ok('холст ничем не выворачивается', filt === 'none', filt);
  const ripple = await p.evaluate(() => {
    const e = window.__cfExc.api.getSceneElements().find(x => x.id === 'r2');
    const s = window.__cfExc.api.getAppState(), z = s.zoom.value, dpr = window.devicePixelRatio;
    const cv = document.querySelector('.excalidraw__canvas.static');
    const x0 = Math.round(((e.x + s.scrollX) * z + 8) * dpr), y0 = Math.round(((e.y + s.scrollY) * z + 8) * dpr);
    const w = Math.round((e.width * z - 16) * dpr), h = Math.round((e.height * z - 16) * dpr);
    const d = cv.getContext('2d').getImageData(x0, y0, w, h).data;
    let n = 0, sum = 0, sq = 0;
    for (let i = 0; i < d.length; i += 4) { const l = (d[i] + d[i + 1] + d[i + 2]) / 3; n++; sum += l; sq += l * l; }
    const mean = sum / n;
    return { mean: Math.round(mean), sd: Math.round(Math.sqrt(sq / n - mean * mean) * 10) / 10, w, h };
  });
  ok('уменьшение фото без ряби: полосы в одну точку слились в ровный серый', ripple.sd < 12 && ripple.mean > 90 && ripple.mean < 170, JSON.stringify(ripple));
  E = live(await els(p));
  const r2 = E.find(e => e.id === 'r2');
  ok('пропорция фото — из самого файла (3:2), а не 16:9', r2 && Math.abs(r2.w / r2.h - 1.5) < 0.02, r2 && `${r2.w}×${r2.h}`);
  await settle(p, 900);
  ok('и записана в референс — её увидят старая доска и печать', Math.abs(((await store(p, 'references')).r2 || {}).ar - 1.5) < 0.01,
     JSON.stringify(((await store(p, 'references')).r2 || {}).ar));
  const fr = await p.evaluate(() => { const e = window.__cfExc.api.getSceneElements().find(x => x.id === 'f1');
    return e && { w: e.width, h: e.height, crop: e.crop }; });
  ok('кадр раскадровки обрезан по рамке проекта, а не растянут', fr && fr.crop && Math.abs(fr.crop.width / fr.crop.height - fr.w / fr.h) < 0.02,
     JSON.stringify(fr));

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

  // --- 7. правка подписи сцены на доске не держится: название — из записи.
  // Двойное нажатие по сцене теперь ОТКРЫВАЕТ её (раздел 11б), поэтому
  // до подписи добираемся штатным путём Excalidraw: выделил — Enter.
  const sct = await scr(p, 100 + 60, 100 + 12);
  await p.mouse.click(sct.x, sct.y);
  await p.waitForTimeout(200);
  await p.keyboard.press('Enter');
  await p.waitForTimeout(300);
  const editing = await p.evaluate(() => { const t = window.__cfExc.api.getAppState().editingTextElement; return t && t.id; });
  ok('Enter по выделенной сцене открыл её подпись для правки (проверка ниже не пустая)', editing === 'sc1~t', String(editing));
  await p.keyboard.press('End');
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

  // --- 11б. открыть с доски: двойное по фото — во весь экран, кнопка
  // у выделенной сцены — сама сцена. Проверяется НАЖАТИЕМ: кнопка лежит
  // поверх холста Excalidraw, и «есть ли элемент» тут не значит ничего.
  await escape(p); await escape(p);
  let R1 = live(await els(p)).find(e => e.id === 'r1');
  const r1c = await scr(p, R1.x + R1.w / 2, R1.y + R1.h / 2);
  await p.mouse.move(r1c.x, r1c.y); await p.mouse.dblclick(r1c.x, r1c.y);
  await p.waitForTimeout(600);
  const lb = await p.evaluate(() => {
    const box = document.querySelector('[class*="z-[350]"]');
    const img = box && [...box.querySelectorAll('img')].find(i => i.getBoundingClientRect().width > 50);
    return { open: !!box, img: !!img, crop: window.__cfExc.api.getAppState().croppingElementId || null };
  });
  ok('двойное нажатие по фото на доске открыло его во весь экран', lb.open && lb.img, JSON.stringify(lb));
  ok('и Excalidraw при этом не включил обрезку картинки', !lb.crop, String(lb.crop));
  // Стрелка листает кадры — а фото под просмотром выделено первым
  // нажатием, и доска сдвинула бы его, дойди до неё клавиша.
  await p.keyboard.press('ArrowRight'); await p.waitForTimeout(300);
  const R1b = live(await els(p)).find(e => e.id === 'r1');
  ok('стрелка в просмотре не сдвинула фото на доске под ним', Math.abs(R1b.x - R1.x) < 0.5 && Math.abs(R1b.y - R1.y) < 0.5, `${R1.x}→${R1b.x}`);
  await p.keyboard.press('Escape'); await p.waitForTimeout(400);
  ok('Escape закрыл просмотр и вернул на доску', await p.evaluate(() => { const h = document.querySelector('[data-cf="exc-board"]');
    return !document.querySelector('[class*="z-[350]"]') && !!h && h.getBoundingClientRect().width > 0; }));
  // Одно нажатие по сцене — выделение, над ней кнопка «Открыть сцену».
  const S1 = live(await els(p)).find(e => e.id === 'sc1');
  // Правый край карточки: левый её край закрыт панелью свойств Excalidraw,
  // пока выделено фото.
  const s1c = await scr(p, S1.x + S1.w - 40, S1.y + S1.h - 20);
  await p.mouse.click(s1c.x, s1c.y);
  await p.waitForTimeout(500);
  const btn = await p.evaluate(() => {
    const b = document.querySelector('[data-cf="exc-open"]');
    if (!b) return null;
    const r = b.getBoundingClientRect(), cx = r.left + r.width / 2, cy = r.top + r.height / 2;
    const hit = document.elementFromPoint(cx, cy);
    return { x: cx, y: cy, w: Math.round(r.width), h: Math.round(r.height), hit: !!hit && (hit === b || b.contains(hit)), text: b.textContent.trim() };
  });
  ok('у выделенной сцены — кнопка «Открыть сцену», и нажатие попадает в неё', !!btn && btn.hit && /сцену/.test(btn.text), JSON.stringify(btn));
  if (btn) { await p.mouse.click(btn.x, btn.y); await p.waitForTimeout(700); }
  // Доска при уходе на другой экран не выгружается, а прячется — смотрим
  // на её размер, а не на то, есть ли она в разметке.
  const opened = await p.evaluate(() => { const h = document.querySelector('[data-cf="exc-board"]');
    return { board: !!h && h.getBoundingClientRect().width > 0,
      title: [...document.querySelectorAll('input, textarea, h1, h2')].some(e => e.getBoundingClientRect().width > 0 && /ИНТ\. КВАРТИРА/.test(e.value || e.textContent || '')) }; });
  ok('кнопка открыла саму сцену', !opened.board && opened.title, JSON.stringify(opened));
  // Обратно на доску тем же путём, что и человек.
  await p.evaluate(() => { const t = [...document.querySelectorAll('button')].find(x => x.title === 'Доски'); if (t) t.click(); });
  await p.waitForTimeout(500);
  await p.evaluate(() => { const t = [...document.querySelectorAll('button')].find(b => /^Excalidraw\s*Ex$/.test(b.textContent.trim())); if (t) t.click(); });
  await p.waitForFunction(() => window.__cfExc && window.__cfExc.api && window.__cfExc.boardId === 'bx1', { timeout: 30000 });
  await p.waitForTimeout(600);

  // --- 11в. мини-карта: всё содержимое и рамка «где я»; нажатие по
  // середине карты ставит в середину экрана середину содержимого.
  await escape(p);
  await p.evaluate(() => { const a = window.__cfExc.api; a.updateScene({ appState: { selectedElementIds: {} } });
    a.scrollToContent(a.getSceneElements(), { fitToContent: true, animate: false }); });
  await p.waitForTimeout(300);
  await p.evaluate(() => { const a = window.__cfExc.api, s = a.getAppState();
    a.updateScene({ appState: { zoom: { value: 2 }, scrollX: s.scrollX - 150, scrollY: s.scrollY - 80 } }); });
  await p.waitForTimeout(500);
  const mini = await p.evaluate(() => {
    const c = document.querySelector('[data-cf="exc-mini-map"]'); if (!c) return null;
    const r = c.getBoundingClientRect(), d = c.getContext('2d').getImageData(0, 0, c.width, c.height).data;
    let n = 0, orange = 0; for (let i = 0; i < d.length; i += 4) { if (d[i + 3] > 0) n++; if (d[i] > 190 && d[i + 1] > 90 && d[i + 1] < 140 && d[i + 2] < 110 && d[i + 3] > 150) orange++; }
    const cx = r.left + r.width / 2, cy = r.top + r.height / 2, h = document.elementFromPoint(cx, cy);
    const help = document.querySelector('.excalidraw .help-icon');
    const hr = help && help.getBoundingClientRect(), hh = hr && document.elementFromPoint(hr.left + hr.width / 2, hr.top + hr.height / 2);
    return { cx, cy, w: Math.round(r.width), painted: n, orange, hit: h === c, helpFree: !help || (!!hh && help.contains(hh)) };
  });
  ok('мини-карта на доске, на ней видно содержимое и сцены своим цветом', !!mini && mini.painted > 300 && mini.orange > 20, JSON.stringify(mini));
  ok('мини-карта нажимается и не закрывает «?» самого Excalidraw', !!mini && mini.hit && mini.helpFree, JSON.stringify(mini));
  const contentMid = await p.evaluate(() => {
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    window.__cfExc.api.getSceneElements().forEach(e => {
      if (e.customData && e.customData.cf === 'link') return;
      let b = { x: e.x, y: e.y, w: e.width, h: e.height };
      if (Array.isArray(e.points) && e.points.length) { const xs = e.points.map(q => q[0]), ys = e.points.map(q => q[1]);
        b = { x: e.x + Math.min(...xs), y: e.y + Math.min(...ys), w: Math.max(...xs) - Math.min(...xs), h: Math.max(...ys) - Math.min(...ys) }; }
      x0 = Math.min(x0, b.x); y0 = Math.min(y0, b.y); x1 = Math.max(x1, b.x + b.w); y1 = Math.max(y1, b.y + b.h);
    });
    return { x: (x0 + x1) / 2, y: (y0 + y1) / 2 };
  });
  if (mini) { await p.mouse.click(mini.cx, mini.cy); await p.waitForTimeout(400); }
  const viewMid = await p.evaluate(() => { const s = window.__cfExc.api.getAppState(), z = s.zoom.value;
    return { x: s.width / (2 * z) - s.scrollX, y: s.height / (2 * z) - s.scrollY, sel: Object.keys(s.selectedElementIds).length }; });
  ok('нажатие по середине карты привело доску к середине содержимого', Math.abs(viewMid.x - contentMid.x) < 12 && Math.abs(viewMid.y - contentMid.y) < 12 && viewMid.sel === 0,
     `${Math.round(viewMid.x)},${Math.round(viewMid.y)} против ${Math.round(contentMid.x)},${Math.round(contentMid.y)}, выделено ${viewMid.sel}`);
  await p.evaluate(() => { const b = [...document.querySelectorAll('[data-cf="exc-mini"] button')].find(x => /Свернуть/.test(x.title)); if (b) b.click(); });
  await p.waitForTimeout(300);
  const folded = await p.evaluate(() => ({ map: !!document.querySelector('[data-cf="exc-mini-map"]'), btn: !!document.querySelector('[data-cf="exc-mini-open"]') }));
  await p.evaluate(() => { const b = document.querySelector('[data-cf="exc-mini-open"]'); if (b) b.click(); });
  await p.waitForTimeout(300);
  ok('карта сворачивается в кнопку и разворачивается обратно', !folded.map && folded.btn && await p.evaluate(() => !!document.querySelector('[data-cf="exc-mini-map"]')), JSON.stringify(folded));

  // --- 11г. рукопись в текст: пишем пером, выделяем рамкой, ручка
  // «Рукопись в текст» — поддельный ИИ смотрит, ЧТО ушло, и отвечает.
  let ocrSeen = null;
  await p.route(/generativelanguage\.googleapis\.com/, async (route) => {
    let body = {}; try { body = JSON.parse(route.request().postData() || '{}'); } catch (e) {}
    const part = (((body.contents || [])[0] || {}).parts || []).find(x => x.inline_data) || {};
    ocrSeen = { mime: (part.inline_data || {}).mime_type || '', data: (part.inline_data || {}).data || '' };
    await route.fulfill({ contentType: 'application/json',
      body: JSON.stringify({ candidates: [{ content: { parts: [{ text: 'Контровой слева\nдиммер на 40' }] } }] }) });
  });
  const nDocs0 = Object.keys(await store(p, 'docs')).length;
  await p.evaluate(() => { const a = window.__cfExc.api, s = a.getAppState(), z = 1;
    a.updateScene({ appState: { zoom: { value: z }, scrollX: s.width / 2 - 1650, scrollY: s.height / 2 - 200, selectedElementIds: {} } });
    a.setActiveTool({ type: 'freedraw' }); });
  await p.waitForTimeout(300);
  for (const [ax, ay, bx, by] of [[1560, 170, 1620, 230], [1640, 230, 1680, 170], [1700, 170, 1760, 230]]) {
    const A = await scr(p, ax, ay), B = await scr(p, bx, by);
    await p.mouse.move(A.x, A.y); await p.mouse.down();
    for (let i = 1; i <= 12; i++) await p.mouse.move(A.x + (B.x - A.x) * i / 12, A.y + (B.y - A.y) * i / 12 + Math.sin(i) * 6);
    await p.mouse.up(); await p.waitForTimeout(80);
  }
  await p.evaluate(() => window.__cfExc.api.setActiveTool({ type: 'selection' }));
  const Q0 = await scr(p, 1530, 140), Q1 = await scr(p, 1790, 260);
  await drag(p, Q0, Q1);
  await p.waitForTimeout(400);
  const ob = await p.evaluate(() => {
    const b = document.querySelector('[data-cf="exc-open"]'); if (!b) return null;
    const r = b.getBoundingClientRect(), x = r.left + r.width / 2, y = r.top + r.height / 2, h = document.elementFromPoint(x, y);
    return { x, y, text: b.textContent.trim(), hit: !!h && (h === b || b.contains(h)),
             sel: window.__cfExc.api.getAppState().selectedElementIds && Object.keys(window.__cfExc.api.getAppState().selectedElementIds).length };
  });
  ok('выделили написанное пером — над ним ручка «Рукопись в текст», и она нажимается', !!ob && /Рукопись в текст/.test(ob.text) && ob.hit && ob.sel >= 3, JSON.stringify(ob));
  if (ob) await p.mouse.click(ob.x, ob.y);
  await p.waitForFunction(() => [...document.querySelectorAll('[role="dialog"]')].some(d => /Рукопись прочитана/.test(d.textContent)), { timeout: 15000 }).catch(() => {});
  const ocrPix = ocrSeen && ocrSeen.data ? await p.evaluate(async (b64) => {
    const img = new Image(); img.src = 'data:image/png;base64,' + b64; await img.decode();
    const c = document.createElement('canvas'); c.width = img.naturalWidth; c.height = img.naturalHeight;
    const x = c.getContext('2d'); x.drawImage(img, 0, 0); const d = x.getImageData(0, 0, c.width, c.height).data;
    let white = 0, dark = 0, n = d.length / 4; for (let i = 0; i < d.length; i += 4) { if (d[i] > 240 && d[i + 1] > 240 && d[i + 2] > 240) white++; if (d[i] < 60 && d[i + 1] < 60 && d[i + 2] < 60) dark++; }
    return { w: c.width, h: c.height, white: +(white / n).toFixed(3), dark: +(dark / n).toFixed(3) };
  }, ocrSeen.data) : null;
  ok('ИИ получил рукопись чёрным по белому — и больше ничего', !!ocrSeen && ocrSeen.mime === 'image/png' && ocrPix && ocrPix.white > 0.7 && ocrPix.dark > 0.01,
     JSON.stringify({ mime: ocrSeen && ocrSeen.mime, px: ocrPix }));
  const dlgText = await p.evaluate(() => { const t = [...document.querySelectorAll('[role="dialog"] textarea')][0]; return t ? t.value : null; });
  ok('расшифровка показана в окне до того, как лечь в гайд', dlgText === 'Контровой слева\nдиммер на 40', JSON.stringify(dlgText));
  await p.evaluate(() => { const b = [...document.querySelectorAll('[role="dialog"] button')].find(x => /Новым гайдом/.test(x.textContent)); if (b) b.click(); });
  await settle(p, 1500);
  const D = await store(p, 'docs'), nd = Object.values(D).find(d => d.title === 'Контровой слева');
  E = live(await els(p));
  ok('«Новым гайдом на доску» — гайд лёг на ЭТУ доску под рукописью', Object.keys(D).length === nDocs0 + 1 && !!nd && nd.boardId === 'bx1' && nd.y > 230 && E.some(e => e.id === nd.id),
     nd ? `${nd.title} · ${nd.boardId} · ${Math.round(nd.x)},${Math.round(nd.y)}` : 'нет гайда');
  await p.unroute(/generativelanguage\.googleapis\.com/);

  // --- 11д. «Связь» в два нажатия: кнопка на панели доски, полоска
  // называет режим; гайд → овал даёт привязанную стрелку, фото → сцена —
  // привязку к сцене (правило доски), Escape выходит из режима.
  await escape(p);
  await p.evaluate(() => { const a = window.__cfExc.api; a.updateScene({ appState: { selectedElementIds: {} } });
    a.scrollToContent(a.getSceneElements(), { fitToContent: true, animate: false }); });
  await p.waitForTimeout(400);
  const lt = await p.evaluate(() => { const b = document.querySelector('[data-cf="exc-link-tool"]'); if (!b) return null;
    const r = b.getBoundingClientRect(), x = r.left + r.width / 2, y = r.top + r.height / 2, h = document.elementFromPoint(x, y);
    return { x, y, hit: !!h && (h === b || b.contains(h)) }; });
  ok('кнопка «Связь» на панели доски нажимается', !!lt && lt.hit, JSON.stringify(lt));
  if (lt) await p.mouse.click(lt.x, lt.y);
  await p.waitForTimeout(300);
  const bar0 = await p.evaluate(() => { const b = document.querySelector('[data-cf="exc-linkbar"]'); return b ? b.textContent : ''; });
  ok('полоска называет режим', /нажмите на первую/.test(bar0), bar0);
  const center = async (id) => { const e = live(await els(p)).find(x => x.id === id); return e ? scr(p, e.x + e.w / 2, e.y + e.h / 2) : null; };
  const docId = nd && nd.id;
  const c1 = docId && await center(docId), c2 = await center('remote-ellipse');
  if (c1 && c2) { await p.mouse.click(c1.x, c1.y); await p.waitForTimeout(250); }
  const bar1 = await p.evaluate(() => { const b = document.querySelector('[data-cf="exc-linkbar"]'); return b ? b.textContent : ''; });
  const pickA = await p.evaluate(() => ({ frame: !!document.querySelector('[data-cf="exc-link-a"]'), sel: Object.keys(window.__cfExc.api.getAppState().selectedElementIds).length }));
  ok('первое выбранное обведено рамкой, а не выделением (панель свойств не выезжает)', pickA.frame && pickA.sel === 0, JSON.stringify(pickA));
  if (c1 && c2) { await p.mouse.click(c2.x, c2.y); }
  await settle(p);
  let LN = live(await els(p)).filter(e => e.type === 'arrow' && e.sb === docId && e.eb === 'remote-ellipse');
  const LB = await store(p, 'boardEls');
  ok('гайд → овал: стрелка привязана к обоим и уехала в облако', !!c1 && !!c2 && /на второе/.test(bar1) && LN.length === 1 && !!LB['bx1~' + (LN[0] || {}).id],
     JSON.stringify({ bar1, n: LN.length, cloud: !!LB['bx1~' + (LN[0] || {}).id] }));
  const ellBound = await p.evaluate(() => (window.__cfExc.api.getSceneElements().find(e => e.id === 'remote-ellipse').boundElements || []).map(b => b.id));
  ok('и овал знает о своей стрелке (поедет за ним)', LN[0] && ellBound.includes(LN[0].id), JSON.stringify(ellBound));
  const cr = await center('r2'), cs = await center('sc1');
  if (cr && cs) { await p.mouse.click(cr.x, cr.y); await p.waitForTimeout(250); await p.mouse.click(cs.x, cs.y); }
  await settle(p);
  R = await store(p, 'references');
  ok('фото → сцена: это привязка к сцене, а не нарисованная стрелка', R.r2 && R.r2.sceneId === 'sc1' && live(await els(p)).some(e => e.id === 'lnk~r2'), JSON.stringify(R.r2 && R.r2.sceneId));
  await p.keyboard.press('Escape'); await p.waitForTimeout(300);
  ok('Escape выходит из режима «Связь»', await p.evaluate(() => !document.querySelector('[data-cf="exc-linkbar"]') && !document.querySelector('[data-cf="exc-link-tool"].on')));
  const selAfter = await p.evaluate(() => { const a = window.__cfExc.api, e = a.getSceneElements().find(x => x.id === 'st1'); return !!e; });
  ok('после выхода доска снова своя: нажатие выделяет, а не связывает', selAfter);

  // --- 11е. ролик: на постере метка «▶ 0:42», она часть карточки
  // (одна группа, внутри постера), двойное нажатие открывает плеер.
  await escape(p);
  const V = await p.evaluate(() => { const all = window.__cfExc.api.getSceneElements();
    const m = all.find(e => e.id === 'rv'), t = all.find(e => e.id === 'rv~v'), b = all.find(e => e.id === 'rv~vb');
    return m && t && b && { text: t.originalText || t.text, g: [m.groupIds, t.groupIds, b.groupIds].map(x => x.join()),
      inside: t.x >= m.x && t.x + t.width <= m.x + m.width && t.y >= m.y && t.y + t.height <= m.y + m.height,
      order: all.indexOf(b) < all.indexOf(t) && all.indexOf(m) < all.indexOf(b), mx: m.x, my: m.y, mw: m.width, mh: m.height }; });
  ok('у ролика на постере метка «▶ 0:42» на плашке, одной группой с постером', !!V && V.text === '▶ 0:42' && V.inside && V.order && new Set(V.g).size === 1 && V.g[0] === 'g~rv',
     JSON.stringify(V));
  ok('метка ролика не считается копией карточки: в облако не ушла, ролик на доске', !Object.keys(await store(p, 'boardEls')).some(k => /rv~/.test(k))
     && (await store(p, 'references')).rv.boardId === 'bx1');
  if (V) {
    await p.evaluate(([x, y]) => { const a = window.__cfExc.api, s = a.getAppState(); a.updateScene({ appState: { zoom: { value: 1 }, scrollX: s.width / 2 - x, scrollY: s.height / 2 - y } }); }, [V.mx + V.mw / 2, V.my + V.mh / 2]);
    await p.waitForTimeout(300);
    const vc = await scr(p, V.mx + V.mw / 2, V.my + V.mh / 3);
    await p.mouse.dblclick(vc.x, vc.y); await p.waitForTimeout(700);
  }
  ok('двойное нажатие по ролику открывает плеер', await p.evaluate(() => { const b = document.querySelector('[class*="z-[350]"]'); return !!b && !!b.querySelector('video'); }));
  await p.keyboard.press('Escape'); await p.waitForTimeout(300);

  // --- 11ж. копия кадра раскадровки: новый кадр той же сцены со своим
  // номером и без «снято ✓», картинка и описание — с собой. Копия рамки
  // и подписи в облако не уходит: карточку строит новая запись.
  const toastText = (page) => page.evaluate(() => { const t = document.querySelector('[data-cf="toast"]'); return t ? t.textContent : ''; });
  // Пересборок до сих пор было множество (перенос, связи, правки из облака) —
  // и ни одна не имела права выдать себя за перестановку слоёв.
  ok('пересборки доски не записывают порядок слоёв сами', (await store(p, 'boards')).bx1.zo === undefined, JSON.stringify((await store(p, 'boards')).bx1.zo));
  const frameAt = async () => p.evaluate(() => { const e = window.__cfExc.api.getSceneElements().find(x => x.id === 'f1'); return e && { x: e.x, y: e.y, w: e.width, h: e.height }; });
  let F1 = await frameAt();
  await p.evaluate(([x, y]) => { const a = window.__cfExc.api, s = a.getAppState(); a.updateScene({ appState: { zoom: { value: 1 }, scrollX: s.width / 2 - x, scrollY: s.height / 2 - y } }); }, [F1.x + F1.w / 2, F1.y + F1.h / 2]);
  await p.waitForTimeout(300);
  const sb0 = Object.keys(await store(p, 'storyboard')).length;
  let fc = await scr(p, F1.x + F1.w * 0.75, F1.y + F1.h / 2);
  await p.mouse.click(fc.x, fc.y); await p.waitForTimeout(250);
  await p.keyboard.press('Control+d');
  await settle(p);
  let SB = await store(p, 'storyboard');
  const cp1 = Object.values(SB).find(f => f.id !== 'f1' && f.frameNum === '2.2');
  ok('Ctrl+D по кадру — новый кадр той же сцены с номером 2.2, без «снято ✓», с картинкой и описанием',
     Object.keys(SB).length === sb0 + 1 && !!cp1 && cp1.sceneId === 'sc2' && cp1.boardId === 'bx1' && !cp1.shot && cp1.image === SB.f1.image && cp1.description === 'общий план' && SB.f1.shot === true,
     JSON.stringify(Object.values(SB).map(f => [f.id, f.frameNum, f.shot, f.boardId])));
  E = live(await els(p));
  ok('копия лежит на доске своей карточкой с подписью «2.2 · общий план»', !!cp1 && E.some(e => e.id === cp1.id) && (E.find(e => e.id === cp1.id + '~c') || {}).text === '2.2 · общий план',
     JSON.stringify(E.filter(e => e.cd && e.cd.cf === 'frame').map(e => [e.id, e.text])));
  ok('лишних копий рамки на доске не осталось', E.filter(e => e.cd && e.cd.cf === 'frame' && !/^(f1|sb-)/.test(e.id)).length === 0);
  ok('в облако копия рамки нарисованным не ушла', !Object.values(await store(p, 'boardEls')).some(d => /"cf":"frame"/.test(d.e || '')));
  ok('полоска говорит, какой номер у копии и что она в раскадровке сцены', /Копия кадра — 2\.2/.test(await toastText(p)), await toastText(p));
  // Перетаскивание с Alt — тоже копия.
  await escape(p);
  // Хватаем исходник за край, который копия (сдвинутая на 10) не накрывает.
  F1 = await frameAt();
  fc = await scr(p, F1.x + 4, F1.y + F1.h / 2);
  await p.keyboard.down('Alt');
  await drag(p, fc, { x: fc.x, y: fc.y + F1.h + 80 });
  await p.keyboard.up('Alt');
  await settle(p);
  SB = await store(p, 'storyboard');
  const cp2 = Object.values(SB).find(f => f.frameNum === '2.3');
  ok('перетаскивание с Alt — ещё один кадр, 2.3', Object.keys(SB).length === sb0 + 2 && !!cp2 && cp2.sceneId === 'sc2',
     JSON.stringify(Object.values(SB).map(f => [f.id, f.frameNum, Math.round(f.x), Math.round(f.y)])));
  const nums = [SB.f1, cp2].filter(Boolean).map(f => [f.frameNum, Math.round(f.y)]);
  ok('копия — там, куда утащили, а исходный кадр остался на месте', !!cp2 && Math.abs(SB.f1.y - F1.y) <= 2 && cp2.y > F1.y + F1.h, JSON.stringify(nums));
  E = live(await els(p));
  const onBd = (id) => E.find(e => e.id === id);
  ok('и на доске так же: 2.1 на прежнем месте, 2.3 под рукой, лишних рамок нет', !!cp2 && Math.abs(onBd('f1').y - F1.y) <= 2 && !!onBd(cp2.id) && Math.abs(onBd(cp2.id).y - cp2.y) <= 2
     && E.filter(e => e.cd && e.cd.cf === 'frame' && e.cd.part === 'box').length === 3,
     JSON.stringify(E.filter(e => e.cd && e.cd.cf === 'frame').map(e => [e.id, Math.round(e.y), e.text])));
  await escape(p);

  // --- 11з. порядок слоёв карточек помнится: подняли кадр над соседним —
  // он остаётся сверху и после пересборки, и на другом устройстве, и
  // чужая перестановка приезжает сюда. Пишется ОДНОЙ записью доски.
  const order = (page, ids) => page.evaluate((ids) => { const all = window.__cfExc.api.getSceneElements().map(e => e.id); return ids.map(id => all.indexOf(id)); }, ids);
  const cpA = cp1 && cp1.id;
  let ord = await order(p, ['f1', cpA]);
  ok('до перестановки копия 2.2 лежит над кадром 2.1', ord[0] >= 0 && ord[1] > ord[0], JSON.stringify(ord));
  F1 = await frameAt();
  fc = await scr(p, F1.x + 4, F1.y + F1.h / 2);
  await p.mouse.click(fc.x, fc.y); await p.waitForTimeout(250);
  const wBoards0 = (await writes(p)).filter(w => w.coll === 'boards').length;
  const wSb0 = (await writes(p)).filter(w => w.coll === 'storyboard').length;
  await p.keyboard.press('Control+Shift+BracketRight');
  await settle(p);
  ord = await order(p, ['f1', cpA]);
  const zo1 = (await store(p, 'boards')).bx1.zo || [];
  ok('«на передний план»: кадр 2.1 над копией, и порядок лёг в запись доски', ord[0] > ord[1] && zo1.indexOf('f1') > zo1.indexOf(cpA) && zo1.indexOf(cpA) >= 0,
     JSON.stringify({ ord, zo1 }));
  const wB = (await writes(p)).filter(w => w.coll === 'boards').length - wBoards0;
  const wS = (await writes(p)).filter(w => w.coll === 'storyboard').length - wSb0;
  ok('перестановка стоит одной записи доски, записи кадров не тронуты', wB === 1 && wS === 0, `доска ${wB}, кадры ${wS}`);
  await escape(p);
  // Пересборка: утащили стикер (запись поменялась — доска пересобрана).
  const S1b = (live(await els(p))).find(e => e.id === 'st1');
  if (S1b) { const sa = await scr(p, S1b.x + S1b.w - 20, S1b.y + 20); await drag(p, sa, { x: sa.x + 40, y: sa.y + 30 }); await settle(p); await escape(p); }
  ord = await order(p, ['f1', cpA]);
  ok('после пересборки кадр 2.1 по-прежнему сверху', ord[0] > ord[1], JSON.stringify(ord));
  const zoCloud = await p.evaluate(() => JSON.parse(JSON.stringify(window.__cfStore)));
  const ctxZ = await mkCtx(1440, 900, zoCloud);
  const { page: pz, errs: errsZ } = await open(ctxZ);
  ord = await order(pz, ['f1', cpA]);
  ok('другое устройство: кадр 2.1 тоже сверху', ord[0] >= 0 && ord[0] > ord[1], JSON.stringify(ord));
  ok('другое устройство: ни одной ошибки страницы', errsZ.length === 0, errsZ.join(' | '));
  await ctxZ.close();
  // Чужая перестановка: другое устройство опустило 2.1 под копию.
  await p.evaluate(([a]) => { const b = window.__cfStore.boards.bx1; const z = b.zo.filter(x => x !== 'f1'); z.splice(z.indexOf(a), 0, 'f1'); b.zo = z; window.__cfEmit('boards'); }, [cpA]);
  await settle(p, 900);
  ord = await order(p, ['f1', cpA]);
  ok('чужая перестановка приезжает: 2.1 снова под копией', ord[0] >= 0 && ord[0] < ord[1], JSON.stringify(ord));

  // --- 12. своя доска рядом по-прежнему своя
  await p.evaluate(() => { const t = [...document.querySelectorAll('button')].find(b => b.textContent.trim().startsWith('Основная')); t.click(); });
  await p.waitForTimeout(800);
  const own = await p.evaluate(() => ({ old: !!document.getElementById('whiteboard-canvas'), exc: !!document.querySelector('[data-cf="exc-board"]') }));
  ok('вкладка «Основная» открывает свою доску, а не Excalidraw', own.old && !own.exc, JSON.stringify(own));
  await ctx.close();

  // ================= ПЕРЕВОД СТАРОЙ ДОСКИ =================
  // Старая доска с фигурами, подписью внутри фигуры, группой, стрелками
  // к фигуре и к КАРТОЧКЕ, текстом и штрихами пера. «Перевести на
  // Excalidraw» обязано перенести всё это родными элементами, не тронуть
  // прежние данные доски, и «Вернуть прежнюю доску» — вернуть её как была.
  const seed6 = SEED();
  seed6.scenes.sc9 = { id: 'sc9', number: '9', title: 'ИНТ. СТУДИЯ', content: '', boardId: 'board-main', x: 900, y: 400, gear: {}, lightGear: {} };
  seed6.stickies.st9 = { id: 'st9', boardId: 'board-main', x: 900, y: 120, w: 200, h: 120, text: 'Контра', color: '#fef08a', sceneId: '' };
  const OLD_SHAPES = [
    { id: 'shA', k: 'rect', x: 100, y: 100, w: 200, h: 120, sc: '#d97757', bg: '#34d399', sw: 2, sd: 'dashed', fs: 'solid', rd: 1, ro: 1, op: 1, g: 'grp1', sd8: 123 },
    { id: 'shL', k: 'text', ct: 'shA', tx: 'Камера А', fz: 20, sc: '#f0eee6', x: 0, y: 0, w: 10, h: 10 },
    { id: 'shB', k: 'ellipse', x: 500, y: 100, w: 160, h: 100, sc: '#38bdf8', bg: 'transparent', sw: 4, sd: 'solid', fs: 'solid', rd: 1, ro: 0, op: 0.6, g: 'grp1', sd8: 7 },
    { id: 'shC', k: 'arrow', x: 300, y: 160, w: 200, h: 0, sc: '#fbbf24', bg: 'transparent', sw: 2, sd: 'solid', fs: 'solid', rd: 1, ro: 1, op: 1, a1: 'none', a2: 'arrow', rt: 'curved', b1: 'shA', b2: 'shB', sd8: 9 },
    { id: 'shD', k: 'arrow', x: 660, y: 150, w: 240, h: 30, sc: '#fb7185', bg: 'transparent', sw: 2, sd: 'solid', fs: 'solid', rd: 1, ro: 0, op: 1, a1: 'none', a2: 'arrow', b1: 'shB', b2: 'st9', sd8: 11 },
    { id: 'shF', k: 'arrow', x: 1000, y: 240, w: 0, h: 160, sc: '#f0eee6', bg: 'transparent', sw: 1, sd: 'solid', fs: 'solid', rd: 1, ro: 0, op: 1, a1: 'none', a2: 'arrow', b1: 'st9', b2: 'sc9', sd8: 12 },
    { id: 'shT', k: 'text', x: 100, y: 400, w: 220, h: 60, tx: 'Свет с окна слева, контровой сзади', fz: 20, sc: '#f0eee6' },
    { id: 'shE', k: 'line', x: 100, y: 600, w: 300, h: 0, sc: '#f0eee6', bg: 'transparent', sw: 1, sd: 'dotted', fs: 'solid', rd: 1, ro: 0, op: 1, a1: 'none', a2: 'none', sd8: 13 },
    // Линия с наконечником: старая доска рисует его и у линии.
    { id: 'shG', k: 'line', x: 100, y: 640, w: 300, h: 0, sc: '#f0eee6', bg: 'transparent', sw: 1, sd: 'solid', fs: 'solid', rd: 1, ro: 0, op: 1, a1: 'none', a2: 'arrow', sd8: 14 },
    // Текст по центру своей рамки.
    { id: 'shM', k: 'text', x: 500, y: 400, w: 300, h: 30, tx: 'Середина', fz: 20, sc: '#f0eee6', ta: 'center' }
  ];
  const OLD_INK = [
    { id: 'kx1', t: 'pen', c: '#fbbf24', w: 4, p: [100, 700, 0.5, 150, 720, 0.6, 200, 700, 0.7, 260, 730, 0.5] },
    { id: 'kx2', t: 'marker', c: '#fb7185', w: 10, p: [400, 700, 0.5, 480, 690, 0.5, 560, 710, 0.5] }
  ];
  seed6.canvas = { 'shape-board-main': { shapes: JSON.stringify(OLD_SHAPES) }, 'ink-board-main': { strokes: JSON.stringify(OLD_INK) } };
  const ctx6 = await mkCtx(1440, 900, seed6, `localStorage.setItem('cf_active_board', 'board-main');`);
  const c6 = await ctx6.newPage();
  const cerr = [];
  c6.on('pageerror', e => cerr.push(String(e).slice(0, 300)));
  await c6.goto(`http://127.0.0.1:${PORT}/index.html`);
  await c6.waitForFunction(() => window.__CF_APP_OK, { timeout: 180000 });
  await c6.waitForTimeout(700);
  const toBoards = (pg, tab) => pg.evaluate(async (tab) => {
    const d = [...document.querySelectorAll('button')].find(x => x.title === 'Доски'); if (d) d.click();
    await new Promise(r => setTimeout(r, 500));
    const t = [...document.querySelectorAll('button')].find(b => b.textContent.trim().startsWith(tab)); if (t) t.click();
  }, tab);
  await toBoards(c6, 'Основная');
  await c6.waitForTimeout(1500);
  ok('перевод: старая доска открыта своей', await c6.evaluate(() => !!document.getElementById('whiteboard-canvas') && !document.querySelector('[data-cf="exc-board"]')));
  // Строка меню — настоящим нажатием: меню под строкой вкладок, и
  // «есть ли элемент» тут не значит ничего (см. «Доски» в CLAUDE.md).
  const menuHit = async (pg, cf) => {
    await pg.evaluate(() => [...document.querySelectorAll('button')].find(b => b.textContent.trim() === '···' && /Выгрузить/.test(b.title)).click());
    await pg.waitForTimeout(300);
    const r = await pg.evaluate((cf) => { const b = document.querySelector(`[data-cf="${cf}"]`); if (!b) return null;
      const q = b.getBoundingClientRect(), x = q.left + q.width / 2, y = q.top + q.height / 2, h = document.elementFromPoint(x, y);
      return { x, y, hit: !!h && (h === b || b.contains(h)) }; }, cf);
    if (r && r.hit) await pg.mouse.click(r.x, r.y);
    await pg.waitForTimeout(400);
    return r;
  };
  const mh = await menuHit(c6, 'board-to-exc');
  ok('перевод: строка «Перевести на Excalidraw» в «···» нажимается', !!mh && mh.hit, JSON.stringify(mh));
  const dlg = await c6.evaluate(() => { const b = document.querySelector('[data-cf="confirm-ok"]'); const box = b && b.closest('[role="dialog"]');
    return b && { label: b.textContent.trim(), red: /bg-red/.test(b.className), trash: !!(box && box.querySelector('.bg-red-500\\/20')), text: box ? box.textContent : '' }; });
  ok('перевод: спрашивает спокойно — без корзины и красной кнопки, и говорит, что прежняя не стирается',
     !!dlg && dlg.label === 'Перевести' && !dlg.red && !dlg.trash && /не стирается/.test(dlg.text) && /9 фигур/.test(dlg.text) && /2 штриха/.test(dlg.text), dlg && dlg.text.slice(0, 200));
  await c6.click('[data-cf="confirm-ok"]');
  await c6.waitForFunction(() => window.__cfExc && window.__cfExc.api && window.__cfExc.boardId === 'board-main', { timeout: 60000 }).catch(() => {});
  await settle(c6, 2500);
  let C = live(await els(c6));
  const X = await c6.evaluate(() => Object.fromEntries(window.__cfExc.api.getSceneElements().filter(e => /^o~/.test(e.id)).map(e => [e.id, {
    type: e.type, x: Math.round(e.x), y: Math.round(e.y), w: Math.round(e.width), h: Math.round(e.height), sc: e.strokeColor, bg: e.backgroundColor,
    ss: e.strokeStyle, sw: e.strokeWidth, op: e.opacity, g: e.groupIds, rd: e.roundness, text: e.originalText || e.text, cid: e.containerId,
    sb: e.startBinding && e.startBinding.elementId, eb: e.endBinding && e.endBinding.elementId, ah: e.endArrowhead, n: e.points && e.points.length,
    pr: e.pressures && e.pressures.length, be: (e.boundElements || []).map(b => b.id), cd: e.customData }])));
  ok('перевод: доска открылась в Excalidraw', await c6.evaluate(() => window.__cfExc && window.__cfExc.boardId === 'board-main'));
  const A = X['o~shA'] || {};
  ok('прямоугольник: место, цвет, пунктир, полупрозрачная заливка', A.type === 'rectangle' && A.x === 100 && A.y === 100 && A.w === 200 && A.h === 120
     && A.sc === '#d97757' && A.ss === 'dashed' && A.bg === '#34d39938', JSON.stringify(A));
  ok('подпись внутри фигуры стала её подписью', (X['o~shA~l'] || {}).text === 'Камера А' && X['o~shA~l'].cid === 'o~shA' && A.be.includes('o~shA~l'), JSON.stringify(X['o~shA~l']));
  ok('овал: толщина и прозрачность', (X['o~shB'] || {}).type === 'ellipse' && X['o~shB'].sw === 4 && X['o~shB'].op === 60, JSON.stringify(X['o~shB']));
  ok('группа сохранилась', JSON.stringify(A.g) === '["o~grp1"]' && JSON.stringify((X['o~shB'] || {}).g) === '["o~grp1"]');
  const Cc = X['o~shC'] || {};
  ok('стрелка между фигурами держится за обе и осталась дугой', Cc.type === 'arrow' && Cc.sb === 'o~shA' && Cc.eb === 'o~shB' && Cc.ah === 'arrow' && Cc.n === 3 && (Cc.rd || {}).type === 2
     && A.be.includes('o~shC') && (X['o~shB'] || {}).be.includes('o~shC'), JSON.stringify(Cc));
  ok('стрелка к карточке держится за карточку', (X['o~shD'] || {}).eb === 'st9' && (C.find(e => e.id === 'st9') ? true : false), JSON.stringify(X['o~shD']));
  const ST6 = await store(c6, 'stickies');
  ok('стрелка «стикер → сцена» осталась рисунком: запись стикера не тронута', (X['o~shF'] || {}).eb === 'sc9' && ST6.st9.sceneId === '', JSON.stringify({ a: X['o~shF'], sid: ST6.st9.sceneId }));
  ok('текст перенесён с переносом строк', (X['o~shT'] || {}).type === 'text' && /Свет с окна слева,?\s*\n?\s*контровой сзади/.test(X['o~shT'].text) && /\n/.test(X['o~shT'].text), JSON.stringify(X['o~shT'] && X['o~shT'].text));
  ok('линия пунктиром — линией', (X['o~shE'] || {}).type === 'line' && X['o~shE'].ss === 'dotted');
  ok('линия с наконечником — стрелкой с наконечником', (X['o~shG'] || {}).type === 'arrow' && X['o~shG'].ah === 'arrow', JSON.stringify(X['o~shG']));
  const M = X['o~shM'] || {};
  ok('текст по центру стоит по центру своей прежней рамки', Math.abs(M.x + M.w / 2 - 650) <= 12, JSON.stringify(M));
  ok('штрихи пера — свободным рисунком со своим нажимом и цветом', (X['o~kx1'] || {}).type === 'freedraw' && X['o~kx1'].n === 4 && X['o~kx1'].pr === 4 && X['o~kx1'].sc === '#fbbf24'
     && (X['o~kx2'] || {}).op === 32, JSON.stringify({ k1: X['o~kx1'], k2: X['o~kx2'] && X['o~kx2'].op }));
  ok('карточки старой доски на своих местах', !!C.find(e => e.id === 'st9' && Math.round(e.x) === 900) && !!C.find(e => e.id === 'sc9'));
  const B6 = await store(c6, 'boards'), E6 = await store(c6, 'boardEls'), K6 = await store(c6, 'canvas');
  ok('доска помечена: Excalidraw, переведена со своей', B6['board-main'].engine === 'excalidraw' && B6['board-main'].from === 'own' && B6['board-main'].xc === 1, JSON.stringify(B6['board-main']));
  const nOld = Object.keys(X).length;
  ok('всё переведённое уехало в облако отдельными документами', Object.keys(E6).filter(k => /^board-main~o~/.test(k)).length === nOld, `${Object.keys(E6).filter(k => /^board-main~o~/.test(k)).length} из ${nOld}`);
  ok('прежние данные доски в облаке не тронуты', K6['shape-board-main'].shapes === JSON.stringify(OLD_SHAPES) && K6['ink-board-main'].strokes === JSON.stringify(OLD_INK));
  ok('перевод: ни одной ошибки страницы', cerr.length === 0, cerr.join(' | '));
  // Другое устройство открывает ту же доску: всё из облака.
  const ctx7 = await mkCtx(1440, 900, await c6.evaluate(() => JSON.parse(JSON.stringify(window.__cfStore))), `localStorage.setItem('cf_active_board', 'board-main');`);
  const c7 = await ctx7.newPage();
  await c7.goto(`http://127.0.0.1:${PORT}/index.html`);
  await c7.waitForFunction(() => window.__CF_APP_OK, { timeout: 180000 });
  await c7.waitForTimeout(700);
  await toBoards(c7, 'Основная');
  await c7.waitForFunction(() => window.__cfExc && window.__cfExc.api && window.__cfExc.boardId === 'board-main', { timeout: 60000 }).catch(() => {});
  await settle(c7, 2000);
  const X7 = live(await els(c7)).filter(e => /^o~/.test(e.id));
  ok('другое устройство: переведённая доска та же', X7.length === nOld && X7.some(e => e.id === 'o~shC' && e.sb === 'o~shA'), `${X7.length} из ${nOld}`);
  ok('другое устройство: второй раз ничего не переводит', !(await writes(c7)).some(w => w.coll === 'boardEls'));
  await ctx7.close();
  // Обратно.
  const mb = await menuHit(c6, 'board-from-exc');
  ok('«Вернуть прежнюю доску» в «···» нажимается', !!mb && mb.hit, JSON.stringify(mb));
  await c6.click('[data-cf="confirm-ok"]');
  await settle(c6, 1500);
  const back = await c6.evaluate(() => { const w = document.getElementById('whiteboard-canvas'); return { own: !!w && w.getBoundingClientRect().width > 0, exc: !!document.querySelector('[data-cf="exc-board"]') }; });
  ok('вернули — открылась прежняя доска', back.own && !back.exc && (await store(c6, 'boards'))['board-main'].engine === '', JSON.stringify(back));
  const K6b = await store(c6, 'canvas');
  ok('и её фигуры и рисунок на месте', K6b['shape-board-main'].shapes === JSON.stringify(OLD_SHAPES) && K6b['ink-board-main'].strokes === JSON.stringify(OLD_INK));
  // Снова перевели — ничего не задвоилось.
  await menuHit(c6, 'board-to-exc');
  await c6.click('[data-cf="confirm-ok"]');
  await c6.waitForFunction(() => window.__cfExc && window.__cfExc.api && window.__cfExc.boardId === 'board-main', { timeout: 60000 }).catch(() => {});
  await settle(c6, 2500);
  const again6 = live(await els(c6)).filter(e => /^o~/.test(e.id));
  ok('перевели снова — ничего не задвоилось', again6.length === nOld && new Set(again6.map(e => e.id)).size === nOld, `${again6.length} из ${nOld}`);
  ok('ни одной ошибки страницы', cerr.length === 0, cerr.join(' | '));
  await ctx6.close();

  // ================= ПУСТАЯ ДОСКА: ШАБЛОНЫ =================
  // Те же три шаблона, что у своей доски. Видны, пока доска пуста и
  // в руке стрелка; взяли карандаш или что-то нарисовали — уходят.
  const seed8 = SEED();
  Object.values(seed8.scenes).forEach(x => { x.boardId = ''; });
  Object.values(seed8.references).forEach(x => { x.boardId = ''; });
  Object.values(seed8.stickies).forEach(x => { x.boardId = 'board-main'; });
  Object.values(seed8.storyboard).forEach(x => { x.boardId = ''; });
  const ctx8 = await mkCtx(1440, 900, seed8);
  const { page: t8, errs: terr } = await open(ctx8);
  await t8.waitForTimeout(600);
  const tpl = () => t8.evaluate(() => { const b = document.querySelector('[data-cf="board-templates"]'); if (!b) return null;
    const cards = [...b.querySelectorAll('.cf-tpl')].map(c => { const r = c.getBoundingClientRect(), h = document.elementFromPoint(r.left + r.width / 2, r.top + 20);
      return { t: c.textContent.slice(0, 20), hit: !!h && c.contains(h) }; });
    return cards; });
  const T0 = await tpl();
  ok('пустая доска Excalidraw: три шаблона, и каждый нажимается', !!T0 && T0.length === 3 && T0.every(c => c.hit), JSON.stringify(T0));
  await t8.evaluate(() => window.__cfExc.api.setActiveTool({ type: 'freedraw' }));
  await t8.waitForTimeout(300);
  const T1 = await tpl();
  await t8.evaluate(() => window.__cfExc.api.setActiveTool({ type: 'selection' }));
  await t8.waitForTimeout(300);
  const T2 = await tpl();
  ok('взяли карандаш — шаблоны ушли, вернули стрелку — снова тут', T1 === null && !!T2, JSON.stringify({ T1: !!T1, T2: !!T2 }));
  await t8.evaluate(() => window.__cfExc.api.setActiveTool({ type: 'rectangle' }));
  const g1 = { x: 300, y: 700 }, g2 = { x: 420, y: 780 };
  await drag(t8, g1, g2);
  await t8.evaluate(() => window.__cfExc.api.setActiveTool({ type: 'selection' }));
  await t8.waitForTimeout(400);
  ok('нарисовали — шаблоны не возвращаются', (await tpl()) === null);
  await t8.keyboard.press('Control+z'); await t8.waitForTimeout(500);
  ok('отменили нарисованное — доска снова пуста, шаблоны снова тут', !!(await tpl()));
  await t8.evaluate(() => { const c = [...document.querySelectorAll('[data-cf="board-templates"] .cf-tpl')].find(x => /Раскадровка/.test(x.textContent)); c.click(); });
  await settle(t8, 2000);
  const SC8 = await store(t8, 'scenes'), FR8 = await store(t8, 'storyboard');
  const onB = Object.values(SC8).filter(x => x.boardId === 'bx1'), frB = Object.values(FR8).filter(x => x.boardId === 'bx1');
  const E8 = live(await els(t8));
  ok('«Раскадровка» положила сцену и её кадры на эту доску Excalidraw', onB.length === 1 && frB.length >= 1 && E8.some(e => e.id === onB[0].id) && frB.every(f => E8.some(e => e.id === f.id)),
     JSON.stringify({ scenes: onB.map(x => x.id), frames: frB.length }));
  ok('и шаблоны ушли, а карточки видно на экране', (await tpl()) === null && await t8.evaluate((id) => { const a = window.__cfExc.api, s = a.getAppState(), e = a.getSceneElements().find(x => x.id === id);
    const x = (e.x + s.scrollX) * s.zoom.value, y = (e.y + s.scrollY) * s.zoom.value; return x >= 0 && y >= 0 && x < s.width && y < s.height; }, onB[0] && onB[0].id));
  ok('пустая доска: ни одной ошибки страницы', terr.length === 0, terr.join(' | '));
  await ctx8.close();
  // Гость на пустой доске шаблонов не видит: они кладут на доску записи.
  const ctx9 = await mkCtx(1440, 900, seed8);
  const { page: g9 } = await open(ctx9, '/index.html?view=board&board=bx1&room=x-room');
  await g9.waitForTimeout(600);
  ok('гостю по ссылке шаблоны не показываются', await g9.evaluate(() => !document.querySelector('[data-cf="board-templates"]')));
  await ctx9.close();

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

  // ================= ПРЕЖНЯЯ ТЁМНАЯ ТЕМА =================
  // Доска, нарисованная, пока холст выворачивался фильтром, хранит цвета
  // «до фильтра»: чёрный карандаш на экране был светлым. Обязана перевести
  // их один раз тем же счётом и пометить себя.
  const oldToDirect = (c) => {
    const h = c.slice(1), iv = (i) => 0.93 - 0.86 * (parseInt(h.slice(i, i + 2), 16) / 255);
    const R = iv(0), G = iv(2), B = iv(4), cl = (v) => Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16).padStart(2, '0');
    return '#' + cl(-0.574 * R + 1.430 * G + 0.144 * B) + cl(0.426 * R + 0.430 * G + 0.144 * B) + cl(0.426 * R + 1.430 * G - 0.856 * B);
  };
  const seed5 = SEED();
  delete seed5.boards.bx1.xc;
  const oldEl = { ...known, id: 'old-rect', strokeColor: '#1e1e1e', backgroundColor: '#ffc9c9', index: 'a3', updated: 5 };
  seed5.boardEls = { 'bx1~old-rect': { b: 'bx1', id: 'old-rect', v: 4, e: JSON.stringify(oldEl) } };
  const ctx5 = await mkCtx(1440, 900, seed5);
  const { page: o, errs: oerr } = await open(ctx5);
  await settle(o, 1500);
  const oe = (await els(o)).find(e => e.id === 'old-rect');
  const oc = await o.evaluate(() => { const e = window.__cfExc.api.getSceneElements().find(x => x.id === 'old-rect');
    return e && { s: e.strokeColor, b: e.backgroundColor, m: e.customData }; });
  ok('старый чёрный карандаш стал тем светлым, каким был на экране', oc && oc.s === oldToDirect('#1e1e1e') && oc.b === oldToDirect('#ffc9c9'), JSON.stringify(oc));
  const cloudOld = ((await store(o, 'boardEls'))['bx1~old-rect'] || {}).e || '';
  ok('перевод уехал в облако, доска помечена', /"cfc":1/.test(cloudOld) && (await store(o, 'boards')).bx1.xc === 1);
  // Сцена со стикером, нарисованная УЖЕ после перевода, не трогается:
  // повторный заход на ту же доску ничего не переводит второй раз.
  const again = await o.evaluate(() => window.__cfExc.api.getSceneElements().find(x => x.id === 'old-rect').strokeColor);
  ok('второй раз не переводится', again === oldToDirect('#1e1e1e'), again);
  ok('ни одной ошибки страницы', oerr.length === 0, oerr.join(' | '));
  await ctx5.close();

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
  // «Связь» на телефоне — строкой в «···» (панели значков там нет).
  const rowL = await ph.evaluate(async () => {
    [...document.querySelectorAll('button')].find(b => b.textContent.trim() === '···' && /Выгрузить/.test(b.title)).click();
    await new Promise(r => setTimeout(r, 300));
    const b = document.querySelector('[data-cf="exc-link-row"]'); if (!b) return null;
    const r = b.getBoundingClientRect(), x = r.left + r.width / 2, y = r.top + r.height / 2, h = document.elementFromPoint(x, y);
    return { x, y, hit: !!h && (h === b || b.contains(h)) };
  });
  if (rowL && rowL.hit) await ph.mouse.click(rowL.x, rowL.y);
  await ph.waitForTimeout(300);
  const barP = await ph.evaluate(() => { const b = document.querySelector('[data-cf="exc-linkbar"]'); if (!b) return null;
    const r = b.getBoundingClientRect(), g = [...b.querySelectorAll('button')].find(x => /Готово/.test(x.textContent)), gr = g && g.getBoundingClientRect();
    const h = gr && document.elementFromPoint(gr.left + gr.width / 2, gr.top + gr.height / 2);
    return { l: Math.round(r.left), r: Math.round(r.right), vw: window.innerWidth, done: !!h && g.contains(h) }; });
  ok('телефон: «Связать две карточки» в «···», полоска режима в ширину экрана и «Готово» нажимается',
     !!rowL && rowL.hit && !!barP && barP.l >= 0 && barP.r <= barP.vw && barP.done, JSON.stringify({ rowL, barP }));
  await ph.evaluate(() => { const g = [...document.querySelectorAll('[data-cf="exc-linkbar"] button')].find(x => /Готово/.test(x.textContent)); if (g) g.click(); });
  await ph.waitForTimeout(300);
  // Карту — ДО двойного касания: открытый просмотр фото лёг бы поверх.
  // Сравниваем с самими панелями Excalidraw, а не с их контейнером
  // App-bottom-bar: тот прозрачный и тянется почти во всю высоту.
  const pm = await ph.evaluate(() => {
    const m = document.querySelector('[data-cf="exc-mini"]'); if (!m) return null;
    const r = m.getBoundingClientRect(), h = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
    const bars = [...document.querySelectorAll('.excalidraw .App-toolbar, .excalidraw .mobile-misc-tools-container')]
      .map(b => b.getBoundingClientRect()).filter(b => b.width && b.height);
    const cross = bars.some(b => !(b.right <= r.left || b.left >= r.right || b.bottom <= r.top || b.top >= r.bottom));
    return { top: Math.round(r.top), bottom: Math.round(r.bottom), vh: window.innerHeight, hit: !!h && m.contains(h), cross };
  });
  ok('телефон: карта на экране, нажимается и не наезжает на панели Excalidraw', !!pm && pm.hit && !pm.cross && pm.bottom <= pm.vh, JSON.stringify(pm));
  // Пальцем браузер о двойном касании не сообщает — считаем сами.
  const pr = live(await els(ph)).find(e => e.id === 'r1');
  const prc = await scr(ph, pr.x + pr.w / 2, pr.y + pr.h / 2);
  const onCanvas = await ph.evaluate(([x, y]) => { const h = document.elementFromPoint(x, y); return !!h && h.tagName === 'CANVAS'; }, [prc.x, prc.y]);
  await ph.touchscreen.tap(prc.x, prc.y); await ph.waitForTimeout(120); await ph.touchscreen.tap(prc.x, prc.y);
  await ph.waitForTimeout(600);
  ok('телефон: двойное касание по фото открыло его во весь экран', onCanvas && await ph.evaluate(() => !!document.querySelector('[class*="z-[350]"]')), `фото под пальцем: ${onCanvas}`);
  ok('телефон: ни одной ошибки страницы', perr.length === 0, perr.join(' | '));
  await ctx4.close();

  await browser.close();
  server.kill();
  console.log(bad ? `\n${bad} FAIL` : '\nвсё зелёное');
  process.exit(bad ? 1 : 0);
})().catch(e => { console.error(e); server.kill(); process.exit(1); });
