// Режим сцен «Сценарий»: текст подряд с вёрсткой реплик, поле у каждой сцены,
// выделение фразы и заметка к ней у своей строки, перо на полях и по тексту,
// список сцен слева ведёт к сцене, гость только читает, телефон.
const fs = require('fs'), os = require('os'), path = require('path');
const { execSync, spawn } = require('child_process');
const ROOT = path.resolve(__dirname, '..'), LIBS = path.join(os.tmpdir(), 'cineflow-libs'), PORT = '8153';
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
  const mk = async (w, h, q = '') => {
    const ctx = await browser.newContext({ viewport: { width: w, height: h }, isMobile: w < 768, hasTouch: w < 900, serviceWorkers: 'block' });
    await ctx.route('**/*', route => {
      const u = route.request().url();
      if (/firestore|firebase|googleapis|gstatic|nominatim/.test(u)) return route.abort();
      for (const [f, re] of [['react.js', /react@18[.0-9]*\/umd\/react\.production/], ['react-dom.js', /react-dom@18/], ['babel.js', /babel\.min\.js/], ['tailwind.js', /cdn\.tailwindcss/]])
        if (re.test(u)) return route.fulfill({ body: fs.readFileSync(path.join(LIBS, f)), contentType: 'application/javascript' });
      route.continue();
    });
    await ctx.addInitScript(() => {
      if (sessionStorage.__seeded) return; sessionStorage.__seeded = 1;
      localStorage.setItem('cf_room', 'scriptview-room');
      localStorage.setItem('cf_user_name', 'Тест');
      localStorage.setItem('cf_scene_mode', 'script');
      const body = (n) => [
        'Тесная кухня. Над столом одна лампа с абажуром. За окном мигает вывеска аптеки, зелёным по стене.',
        '',
        'МИША',
        '(не поднимая головы)',
        'Это дедушкина рация? Она правда заговорила сегодня утром?',
        '',
        'Вера крутит ручку настройки. Тишина. Лампа чуть гудит. Сцена ' + n + '.',
        '',
        'СКЛЕЙКА:'].join('\n');
      const scenes = [];
      for (let i = 1; i <= 8; i++) scenes.push({ id: 'sc' + i, number: String(i), title: 'ИНТ. КУХНЯ — НОЧЬ ' + i, content: i === 2 ? 'Свет делает лампа, всё остальное — тень.' : '',
        script: body(i), date: '2026-11-0' + (i % 9), gear: i === 2 ? { steadicam: 1 } : {}, lightGear: {}, boardId: '' });
      localStorage.setItem('cf_scenes', JSON.stringify(scenes));
      localStorage.setItem('cf_storyboard', JSON.stringify([{ id: 'f1', sceneId: 'sc2', frameNum: '2.1', description: 'Общий', image: '' }, { id: 'f2', sceneId: 'sc2', frameNum: '2.2', description: 'Крупно', image: '' }]));
      localStorage.setItem('cf_stickies', JSON.stringify([{ id: 'n1', sceneId: 'sc2', boardId: 'board-main', text: 'Проверить вывеску', x: 0, y: 0, color: '#fef08a' }]));
    });
    const page = await ctx.newPage();
    const errs = [];
    page.on('pageerror', e => errs.push(String(e).slice(0, 200)));
    await page.goto(`http://127.0.0.1:${PORT}/index.html${q}`);
    await page.waitForFunction(() => window.__CF_APP_OK, { timeout: 180000 });
    await page.waitForTimeout(1200);
    return { page, errs, ctx };
  };
  const hits = (p, sel) => p.evaluate((sel) => { const el = document.querySelector(sel); if (!el) return 'нет'; const r = el.getBoundingClientRect();
    const t = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2); return !!t && (t === el || el.contains(t)); }, sel);
  const saved = (p, key) => p.evaluate((k) => JSON.parse(localStorage.getItem(k) || '[]'), key);
  const scene = async (p, id) => (await saved(p, 'cf_scenes')).find(s => s.id === id) || {};

  // ---- НОУТБУК
  const { page: p, errs } = await mk(1440, 900);
  ok('режим «Сценарий» в шапке и он включён', await p.evaluate(() => { const b = [...document.querySelectorAll('header .cf-seg button')].find(x => x.textContent === 'Сценарий'); return !!b && b.classList.contains('on'); }));
  ok('сценарий подряд — все восемь сцен', await p.$$eval('[data-sr]', a => a.length) === 8);
  const kinds = await p.$$eval('[data-sr="sc1"] [data-li]', a => a.map(x => x.className.replace('cf-sl-', '')).join(','));
  ok('вёрстка: описание, имя, ремарка, реплика, переход', kinds === 'a,g,c,p,d,g,a,g,t', kinds);
  const indent = await p.evaluate(() => { const c = document.querySelector('[data-sr="sc1"] .cf-sl-c'), a = document.querySelector('[data-sr="sc1"] .cf-sl-a');
    return parseFloat(getComputedStyle(c).paddingLeft) > 100 && parseFloat(getComputedStyle(a).paddingLeft) === 0; });
  ok('имя героя с отступом, описание — от края', indent);
  ok('поле сцены 2: раскадровка, экспликация, техника, заметка', await p.evaluate(() => {
    const m = document.querySelector('[data-sr="sc2"] [data-cf="script-margin"]');
    return !!m.querySelector('[data-cf="script-frames"]') && /лампа/.test(m.textContent) && /Стедикам/.test(m.textContent) && /Проверить вывеску/.test(m.querySelector('textarea').value);
  }));
  // список слева ведёт к сцене
  await p.click('[data-cf="scene-row"][data-id="sc6"]');
  await p.waitForTimeout(600);
  const near = await p.evaluate(() => { const r = document.querySelector('[data-sr="sc6"]').getBoundingClientRect(), m = document.querySelector('[data-cf="script-view"]').getBoundingClientRect(); return Math.round(r.top - m.top); });
  ok('нажатие по сцене в списке прокручивает сценарий к ней', near >= -5 && near < 120, String(near));

  // выделение фразы → заметка к фразе
  await p.evaluate(() => document.querySelector('[data-sr="sc2"]').scrollIntoView());
  await p.waitForTimeout(400);
  await p.evaluate(() => {
    const line = document.querySelector('[data-sr="sc2"] [data-li="0"]'), t = line.firstChild, s = t.textContent;
    const a = s.indexOf('За окном'), b = s.indexOf('стене.') + 6;
    const r = document.createRange(); r.setStart(t, a); r.setEnd(t, b);
    const sel = getSelection(); sel.removeAllRanges(); sel.addRange(r);
  });
  await p.waitForTimeout(500);
  ok('у выделенного текста — плашка «Заметка к фразе», и она нажимается', await hits(p, '[data-cf="script-note-hl"]') === true);
  await p.click('[data-cf="script-note-hl"]');
  await p.waitForTimeout(300);
  ok('появилось поле заметки к фразе', await hits(p, '[data-cf="script-draft"]') === true);
  await p.keyboard.type('Titan Tube зелёным за окно');
  await p.mouse.click(700, 60);
  await p.waitForTimeout(1500);
  const s2 = await scene(p, 'sc2');
  const mark = (s2.marks || [])[0] || {};
  ok('выделение записано в сцену с цитатой', mark.q === 'За окном мигает вывеска аптеки, зелёным по стене.', JSON.stringify(s2.marks));
  const st = (await saved(p, 'cf_stickies')).find(x => x.hl === mark.id);
  ok('заметка — обычный стикер сцены с меткой фразы', !!st && st.sceneId === 'sc2' && /Titan Tube/.test(st.text), JSON.stringify(st));
  const gap = await p.evaluate((id) => { const m = document.querySelector(`[data-sr="sc2"] mark[data-hl="${id}"]`), a = document.querySelector(`[data-for="${id}"]`);
    if (!m || !a) return 'нет'; return Math.round(a.getBoundingClientRect().top - m.getBoundingClientRect().top); }, mark.id);
  ok('заметка стоит на полях у своей строки (или сразу под блоком сцены)', typeof gap === 'number' && gap > -40, String(gap));
  // меню у выделения: «Снять» — заметка остаётся у сцены
  await p.click(`[data-sr="sc2"] mark[data-hl="${mark.id}"]`);
  await p.waitForTimeout(300);
  ok('нажатие по выделению открывает меню', await hits(p, '[data-cf="script-markpop"]') === true);
  await p.evaluate(() => [...document.querySelectorAll('[data-cf="script-markpop"] button')].find(b => b.textContent === 'Снять').click());
  await p.waitForTimeout(1500);
  const s2b = await scene(p, 'sc2'), st2 = (await saved(p, 'cf_stickies')).find(x => x.id === st.id);
  ok('«Снять» убирает выделение, заметка остаётся у сцены', !(s2b.marks || []).length && st2 && !st2.hl && st2.sceneId === 'sc2', JSON.stringify(st2));

  // перо: рукопись на полях и выделение по тексту
  await p.click('[data-cf="script-pen"]');
  await p.waitForTimeout(400);
  ok('перо включено: панель пера видна, поле свёрнуто', await hits(p, '[data-cf="script-pen-done"]') === true && await p.$('[data-sr="sc3"] canvas[data-ink]') !== null);
  await p.evaluate(() => document.querySelector('[data-sr="sc3"]').scrollIntoView());
  await p.waitForTimeout(400);
  const cb = await p.$eval('[data-sr="sc3"] canvas[data-ink]', c => { const r = c.getBoundingClientRect(); return { x: r.left, y: r.top, w: r.width, h: r.height }; });
  await p.mouse.move(cb.x + 30, cb.y + 140); await p.mouse.down();
  for (let i = 1; i <= 15; i++) await p.mouse.move(cb.x + 30 + i * 8, cb.y + 140 + Math.sin(i) * 8);
  await p.mouse.up();
  await p.waitForTimeout(300);
  const ln = await p.$eval('[data-sr="sc3"] [data-li="6"]', e => { const r = e.getBoundingClientRect(); return { x: r.left, y: r.top + 10 }; });
  await p.mouse.move(ln.x + 5, ln.y); await p.mouse.down(); await p.mouse.move(ln.x + 220, ln.y, { steps: 10 }); await p.mouse.up();
  await p.waitForTimeout(1500);
  const s3 = await scene(p, 'sc3'), ink = JSON.parse(s3.ink || '[]');
  ok('штрих пером записан в сцену у своей строки', ink.length === 1 && ink[0].pts.length > 5 && Number.isInteger(ink[0].li), s3.ink && s3.ink.slice(0, 80));
  ok('пером по тексту — фраза выделилась по словам', (s3.marks || []).length === 1 && /^Вера крутит/.test(s3.marks[0].q), JSON.stringify(s3.marks));
  await p.click('[data-cf="script-pen-done"]');
  await p.waitForTimeout(500);
  ok('после «Готово» рукопись видна карточкой «от руки»', await p.$$eval('[data-sr="sc3"] .cf-sr-inkcard canvas', a => a.length) === 1);
  // техника разворачивается в тот же список, что в панели
  await p.evaluate(() => document.querySelector('[data-sr="sc2"]').scrollIntoView());
  await p.waitForTimeout(300);
  await p.click('[data-sr="sc2"] [data-cf="script-gear"]');
  await p.waitForTimeout(300);
  ok('«Техника» разворачивается списком каталога', await p.$('[data-sr="sc2"] [data-cf="script-gear-open"]') !== null);
  // заголовок сцены ведёт на прежний экран сцены
  await p.click('[data-sr="sc4"] .cf-sr-head');
  await p.waitForTimeout(500);
  ok('нажатие по заголовку открывает экран сцены', await p.evaluate(() => !document.querySelector('[data-cf="script-view"]') && [...document.querySelectorAll('header .cf-seg button')].find(x => x.textContent === 'Творческий').classList.contains('on')));
  ok('ошибок нет', errs.length === 0, errs.join(' | '));

  // ---- 1280: шапка помещается
  const { page: w, errs: ew } = await mk(1280, 800);
  ok('1280: шапка без вылезания за край', await w.evaluate(() => { const h = document.querySelector('header'); return h.scrollWidth <= h.clientWidth + 1; }));

  // ---- ГОСТЬ ПО ССЫЛКЕ
  const { page: g, errs: eg } = await mk(1440, 900, '?view=all&room=scriptview-room');
  ok('гость: сценарий читается', await g.$$eval('[data-sr]', a => a.length) === 8);
  ok('гость: пера нет', await g.$('[data-cf="script-pen"]') === null);
  await g.evaluate(() => {
    const t = document.querySelector('[data-sr="sc1"] [data-li="0"]').firstChild;
    const r = document.createRange(); r.setStart(t, 0); r.setEnd(t, 12); getSelection().removeAllRanges(); getSelection().addRange(r);
  });
  await g.waitForTimeout(500);
  ok('гость: выделение текста не предлагает заметку', await g.$('[data-cf="script-selbar"]') === null);
  ok('гость: ошибок нет', eg.length === 0, eg.join(' | '));

  // ---- ТЕЛЕФОН
  const { page: m, errs: em } = await mk(390, 844);
  await m.click('.cf-tabbar button:last-child');
  await m.waitForTimeout(400);
  await m.click('[data-cf="more-mode-script"]');
  await m.waitForTimeout(800);
  ok('телефон: «Ещё» → «Сценарий» открывает сценарий', await m.$$eval('[data-sr]', a => a.length) === 8);
  ok('телефон: поле под текстом, без горизонтальной прокрутки', await m.evaluate(() => {
    const row = document.querySelector('[data-sr="sc2"]'), page = row.querySelector('.cf-sr-page'), mg = row.querySelector('[data-cf="script-margin"]');
    return mg.getBoundingClientRect().top >= page.getBoundingClientRect().bottom - 1 && document.documentElement.scrollWidth <= innerWidth;
  }));
  ok('телефон: ошибок нет', em.length === 0, em.join(' | '));

  await browser.close(); server.kill();
  console.log(bad ? `\n${bad} не сошлось` : '\nВсё сошлось');
  process.exit(bad ? 1 : 0);
})().catch(e => { console.error(e); server.kill(); process.exit(1); });
