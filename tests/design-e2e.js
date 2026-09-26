// Разгрузка интерфейса: читаемый список сцен, номер кадра поверх картинки,
// текст сцены без коробки и сворачивается, заметки линейкой вместо цветной
// плашки и выбранное без оранжевой заливки.
// Проверяется замером в браузере, а не чтением кода: «обрезано ли название»
// и «попадает ли нажатие в номер» видно только в готовой вёрстке.
const fs = require('fs'), os = require('os'), path = require('path');
const { execSync, spawn } = require('child_process');
const ROOT = path.resolve(__dirname, '..'), LIBS = process.env.CF_LIBS || path.join(os.tmpdir(), 'cineflow-libs'), PORT = '8152';
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
const server = spawn('python3', ['-m', 'http.server', PORT, '--bind', '127.0.0.1'], { cwd: ROOT, stdio: 'ignore' });
let bad = 0;
const ok = (n, c, d) => { console.log((c ? '  ok  ' : '  FAIL') + ' ' + n + (d ? ' — ' + d : '')); if (!c) bad++; };
const img = (a, b) => 'data:image/svg+xml;base64,' + Buffer.from(
  `<svg xmlns="http://www.w3.org/2000/svg" width="640" height="360"><rect width="640" height="360" fill="${a}"/><rect y="200" width="640" height="160" fill="${b}"/></svg>`).toString('base64');
const TITLES = ['ИНТ. КВАРТИРА НА ГОРСКОЙ — УТРО', 'НАТ. ДВОР ШКОЛЫ У ГАРАЖЕЙ — ДЕНЬ', 'ИНТ. МАШИНА — НОЧЬ', 'СЦЕНА У ОКНА'];
const seed = { cf_scenes: [], cf_storyboard: [], cf_references: [], cf_stickies: [
  { id: 'n1', text: 'Свет из окна — держать контровой', color: '#ffc9c9', sceneId: 'sc1', boardId: '', x: 0, y: 0 },
  { id: 'n2', text: 'Проверить розетки', sceneId: 'sc1', boardId: '', x: 0, y: 0 }] };
const LONG = Array.from({ length: 14 }, (_, i) => `Строка ${i + 1}. Она стоит у окна и смотрит во двор.`).join('\n');
TITLES.forEach((t, i) => {
  const id = 'sc' + (i + 1);
  seed.cf_scenes.push({ id, number: String(i + 1), title: t, content: 'экспликация', script: i ? 'Она стоит у окна.' : LONG, date: '2026-10-01', boardId: '' });
  for (let k = 0; k < 2; k++) seed.cf_storyboard.push({ id: `f${i}-${k}`, sceneId: id, frameNum: `${i + 1}.${k + 1}`, lens: k ? '50' : '', description: 'Общий план', image: img('#c0703a', '#223') });
  seed.cf_references.push({ id: 'r' + i, url: img('#7ea56b', '#111'), label: '', file: `r${i}.jpg`, tags: ['свет'], folder: '', sceneId: id, locationId: '' });
});
(async () => {
  await new Promise(r => setTimeout(r, 1000));
  const browser = await playwright.chromium.launch({ executablePath: '/opt/pw-browsers/chromium', args: ['--no-sandbox'] });
  const mk = async (w, h) => {
    const ctx = await browser.newContext({ viewport: { width: w, height: h }, isMobile: w < 768, hasTouch: true, serviceWorkers: 'block' });
    await ctx.route('**/*', route => {
      const u = route.request().url();
      if (/firestore|firebase|googleapis|gstatic|nominatim/.test(u)) return route.abort();
      for (const [f, re] of [['react.js', /react@18\/umd\/react\.production/], ['react-dom.js', /react-dom@18/], ['babel.js', /babel\.min\.js/], ['tailwind.js', /cdn\.tailwindcss/]])
        if (re.test(u)) return route.fulfill({ body: fs.readFileSync(path.join(LIBS, f)), contentType: 'application/javascript' });
      route.continue();
    });
    await ctx.addInitScript(s => {
      localStorage.setItem('cf_room', 'design-room'); localStorage.setItem('cf_user_name', 'Тест');
      localStorage.setItem('cf_scene_mode', 'creative');
      for (const k in s) localStorage.setItem(k, JSON.stringify(s[k]));
    }, seed);
    const page = await ctx.newPage();
    const errs = [];
    page.on('pageerror', e => errs.push(String(e).slice(0, 200)));
    await page.goto(`http://127.0.0.1:${PORT}/index.html`);
    await page.waitForFunction(() => window.__CF_APP_OK, { timeout: 180000 });
    await page.waitForTimeout(1200);
    return { page, errs };
  };
  const go = (p, re) => p.evaluate(async (src) => {
    const b = [...document.querySelectorAll('.cf-tabbar button, header button')].find(x => new RegExp(src, 'i').test((x.textContent || '') + (x.title || '')));
    if (b) b.click();
    await new Promise(r => setTimeout(r, 900));
    return !!b;
  }, re);
  const ACCENT = 'rgb(217, 119, 87)';

  // ---- ПЛАНШЕТ
  const { page: p, errs } = await mk(1194, 834);
  const list = await p.evaluate(() => [...document.querySelectorAll('.cf-scene-row')].map(r => {
    const t = r.children[1];
    return { text: t.textContent, full: t.getAttribute('title'), cut: t.scrollHeight > t.clientHeight + 1 || t.scrollWidth > t.clientWidth + 1 };
  }));
  ok('список сцен: названия видны целиком, без многоточия', list.length === 4 && list.every(x => !x.cut), JSON.stringify(list.map(x => x.text + (x.cut ? ' [обрезано]' : ''))));
  ok('«ИНТ./НАТ.» в начале не повторяет значок', list.slice(0, 3).every(x => !/^(ИНТ|НАТ)/.test(x.text)) && /КВАРТИРА НА ГОРСКОЙ/.test(list[0].text), list.map(x => x.text).join(' | '));
  ok('название без места остаётся как было («СЦЕНА У ОКНА»)', list[3] && list[3].text === 'СЦЕНА У ОКНА', list[3] && list[3].text);
  ok('подсказка несёт полное название', list[0] && list[0].full === TITLES[0]);

  const fr = await p.evaluate(() => {
    const n = document.querySelector('[data-cf="frame-num"]');
    const im = n && n.parentElement.querySelector('img');
    const a = n.getBoundingClientRect(), b = im.getBoundingClientRect();
    const hit = document.elementFromPoint(a.left + a.width / 2, a.top + a.height / 2);
    return { inside: a.left >= b.left && a.right <= b.right && a.top >= b.top && a.bottom <= b.bottom, hit: !!hit && n.contains(hit),
             w: Math.round(b.width), text: n.textContent };
  });
  ok('номер кадра лежит поверх картинки', fr.inside && fr.text === '1.1', JSON.stringify(fr));
  ok('кадр крупнее прежних 202 точек', fr.w >= 260, fr.w + ' точек');
  ok('нажатие попадает в номер', fr.hit);
  const lens = await p.evaluate(() => [...document.querySelectorAll('[data-cf="frame-num"]')][1].textContent);
  ok('оптика тоже поверх кадра', lens === '1.250', lens);
  const ed = await p.evaluate(async () => {
    const n = document.querySelector('[data-cf="frame-num"]'); n.click();
    await new Promise(r => setTimeout(r, 300));
    const a = document.activeElement;
    return { tag: a && a.tagName, v: a && a.value };
  });
  ok('нажатие по номеру открывает правку номера', ed.tag === 'INPUT' && ed.v === '1.1', JSON.stringify(ed));

  const tx = await p.evaluate(() => {
    const t = document.querySelector('[data-cf="scene-script"]'), cs = getComputedStyle(t), box = getComputedStyle(t.parentElement);
    return { left: cs.borderLeftWidth, top: cs.borderTopWidth, resize: cs.resize, bg: box.backgroundColor, grow: t.scrollHeight <= t.clientHeight + 2 };
  });
  ok('текст сцены отбит линейкой слева, без коробки', tx.left === '2px' && tx.top === '0px' && tx.resize === 'none' && /rgba\(0, 0, 0, 0\)|transparent/.test(tx.bg), JSON.stringify(tx));
  ok('высота текста — по содержимому, без своей прокрутки', tx.grow);

  // Лёжа текст развёрнут; кнопкой сворачивается до четырёх строк, выбор помнится.
  const fold = async (pg) => pg.evaluate(async () => {
    const b = document.querySelector('[data-cf="scene-text-fold"]');
    const r = b.getBoundingClientRect(), hit = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
    const before = (document.querySelector('[data-cf="scene-script"]') || document.querySelector('[data-cf="scene-script-shut"]')).getBoundingClientRect().height;
    const label = b.textContent;
    b.click(); await new Promise(r => setTimeout(r, 300));
    const shut = document.querySelector('[data-cf="scene-script-shut"]');
    return { hit: !!hit && b.contains(hit), label, before: Math.round(before),
             after: shut ? Math.round(shut.getBoundingClientRect().height) : null, shut: !!shut,
             lines: shut ? Math.round(shut.getBoundingClientRect().height / parseFloat(getComputedStyle(shut).lineHeight)) : 0,
             saved: localStorage.getItem('cf_scene_text') };
  });
  const f1 = await fold(p);
  ok('лёжа текст развёрнут, «свернуть» под пальцем', f1.hit && /свернуть/.test(f1.label), JSON.stringify(f1));
  ok('свёрнутый текст — четыре строки и заметно ниже', f1.shut && f1.lines === 4 && f1.after < f1.before / 2, `${f1.before} → ${f1.after}, строк ${f1.lines}`);
  ok('выбор запомнен для этого положения', /"landscape":true/.test(f1.saved || ''), f1.saved);
  const f2 = await p.evaluate(async () => {
    document.querySelector('[data-cf="scene-script-shut"]').click(); await new Promise(r => setTimeout(r, 300));
    return { open: !!document.querySelector('[data-cf="scene-script"]'), label: document.querySelector('[data-cf="scene-text-fold"]').textContent };
  });
  ok('нажатие по свёрнутому тексту разворачивает его', f2.open && /свернуть/.test(f2.label), JSON.stringify(f2));

  // Заметка — текст с линейкой цвета стикера, без цветной плашки.
  const nt = await p.evaluate(() => [...document.querySelectorAll('[data-cf="scene-note"]')].map(n => {
    const c = getComputedStyle(n), t = n.querySelector('textarea'), tc = getComputedStyle(t);
    return { bg: c.backgroundColor, rule: c.borderLeftWidth + ' ' + c.borderLeftColor, top: c.borderTopWidth, weight: tc.fontWeight, color: tc.color, cut: t.scrollHeight > t.clientHeight + 2 };
  }));
  ok('заметки сцены на месте', nt.length === 2, JSON.stringify(nt));
  ok('заметка без цветной плашки и рамки-коробки', nt.every(n => /rgba\(0, 0, 0, 0\)/.test(n.bg) && n.top === '0px'), JSON.stringify(nt.map(n => n.bg + ' ' + n.top)));
  ok('цвет стикера — в линейке слева', nt[0] && nt[0].rule === '3px rgb(255, 201, 201)' && nt[1].rule === '3px rgb(254, 240, 138)', nt.map(n => n.rule).join(' | '));
  ok('текст заметки обычный, светлый, не жирный чёрный', nt.every(n => +n.weight < 600 && n.color !== 'rgb(26, 25, 24)'), JSON.stringify(nt.map(n => n.weight + ' ' + n.color)));
  ok('текст заметки виден целиком, без своей прокрутки', nt.every(n => !n.cut));
  const nh = await p.evaluate(async () => {
    const n = document.querySelector('[data-cf="scene-note"]'), t = n.querySelector('textarea');
    const rest = { rule: Math.round(n.getBoundingClientRect().height), line: parseFloat(getComputedStyle(t).lineHeight) };
    t.focus(); await new Promise(r => setTimeout(r, 200));
    const dots = n.querySelectorAll('button[title="Цвет заметки"]').length;
    t.blur(); await new Promise(r => setTimeout(r, 400));
    return { ...rest, dots, after: n.querySelectorAll('button[title="Цвет заметки"]').length };
  });
  ok('в покое линейка по высоте текста, без пустой строки под ним', nh.rule <= nh.line + 8, JSON.stringify(nh));
  ok('палитра — только пока курсор в заметке', nh.dots === 6 && nh.after === 0, JSON.stringify(nh));

  await go(p, 'КПП');
  const seg = await p.evaluate(() => {
    const b = [...document.querySelectorAll('button')].find(x => x.textContent.trim() === 'По сменам');
    return getComputedStyle(b).backgroundColor;
  });
  ok('КПП: выбранный вид — не оранжевая заливка', seg !== ACCENT && !/rgba?\(1[5-9]\d, [5-9]\d, [3-6]\d/.test(seg), seg);
  const shift = await p.evaluate(() => { const s = document.querySelector('.cf-shift'); const c = getComputedStyle(s); return c.borderTopWidth + ' ' + c.backgroundColor; });
  ok('КПП: смена без рамки-коробки', /^0px rgba\(0, 0, 0, 0\)/.test(shift), shift);

  await go(p, 'Галере');
  const gal = await p.evaluate(() => {
    const all = [...document.querySelectorAll('button')].find(x => /^Все\s*\d/.test(x.textContent.trim()));
    const card = document.querySelector('.cf-ref-card');
    return { folder: all && getComputedStyle(all).backgroundColor, card: card && getComputedStyle(card).borderTopColor };
  });
  ok('галерея: выбранная папка — не оранжевая заливка', gal.folder && gal.folder !== ACCENT, gal.folder);
  ok('галерея: у карточки нет рамки в покое', gal.card === 'rgba(0, 0, 0, 0)', gal.card);
  ok('без ошибок на планшете', errs.length === 0, errs.join(' | '));

  // ---- ПЛАНШЕТ СТОЯ: текст свёрнут без всякого выбора, до референсов не листать
  const { page: v, errs: e3 } = await mk(834, 1194);
  const pv = await v.evaluate(() => {
    const shut = document.querySelector('[data-cf="scene-script-shut"]'), b = document.querySelector('[data-cf="scene-text-fold"]');
    return { shut: !!shut, open: !!document.querySelector('[data-cf="scene-script"]'), label: b && b.textContent,
             h: shut ? Math.round(shut.getBoundingClientRect().height) : null };
  });
  ok('стоя текст сцены свёрнут сразу', pv.shut && !pv.open && /развернуть/.test(pv.label || ''), JSON.stringify(pv));
  const pv2 = await v.evaluate(async () => {
    document.querySelector('[data-cf="scene-text-fold"]').click(); await new Promise(r => setTimeout(r, 300));
    return { open: !!document.querySelector('[data-cf="scene-script"]'), saved: localStorage.getItem('cf_scene_text') };
  });
  ok('стоя разворачивается, и это помнится отдельно', pv2.open && /"portrait":false/.test(pv2.saved || ''), JSON.stringify(pv2));
  ok('без ошибок на планшете стоя', e3.length === 0, e3.join(' | '));

  // ---- ТЕЛЕФОН
  const { page: q, errs: e2 } = await mk(390, 844);
  const ph = await q.evaluate(() => {
    const pill = document.querySelector('.cf-pill.on');
    const row = [...document.querySelectorAll('button')].find(b => /КВАРТИРА НА ГОРСКОЙ/.test(b.textContent));
    return { pill: pill && getComputedStyle(pill).backgroundColor, row: row && row.textContent };
  });
  ok('телефон: выбранный фильтр — не оранжевая заливка', ph.pill && ph.pill !== ACCENT, ph.pill);
  ok('телефон: «2 кадра», а не «2 кадр.»', /2 кадра/.test(ph.row || '') && !/кадр\./.test(ph.row || ''), ph.row);
  const pf = await q.evaluate(async () => {
    [...document.querySelectorAll('button')].find(b => /КВАРТИРА НА ГОРСКОЙ/.test(b.textContent)).click();
    await new Promise(r => setTimeout(r, 900));
    const n = document.querySelector('[data-cf="frame-num"]');
    if (!n) return null;
    const im = n.parentElement.querySelector('img'), a = n.getBoundingClientRect(), b = im.getBoundingClientRect();
    return { inside: a.left >= b.left && a.right <= b.right && a.top >= b.top && a.bottom <= b.bottom, text: n.textContent };
  });
  ok('телефон: номер кадра поверх картинки', pf && pf.inside && pf.text === '1.1', JSON.stringify(pf));
  ok('без ошибок на телефоне', e2.length === 0, e2.join(' | '));

  await browser.close(); server.kill();
  console.log(bad ? `\n${bad} FAIL` : '\nвсё ок');
  process.exit(bad ? 1 : 0);
})().catch(e => { console.error(e); server.kill(); process.exit(1); });
