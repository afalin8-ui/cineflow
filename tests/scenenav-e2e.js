// Соседние сцены на телефоне: полоса «‹ предыдущая · N из M · следующая ›»
// над таб-баром, чтобы не бегать к списку за каждой сценой.
//
// Гоняем на телефоне (390) НАСТОЯЩИМ нажатием (elementFromPoint обязан
// попасть в кнопку): открыли #2 из смены → полоса «#1 ‹ · 2 из 3 · › #3»
// → «следующая» открывает #3, стрелка вперёд гаснет → «предыдущая» дважды
// — #1, стрелка назад гаснет → в «Съёмке» полоса на месте, переход
// сбрасывает прокрутку → под фильтром «Все» за #3 идёт #4 → на планшете
// полосы нет → у гостя по ссылке она есть и работает.
//
// Запуск:  node tests/scenenav-e2e.js
const fs = require('fs'), os = require('os'), path = require('path');
const { execSync, spawn } = require('child_process');
const ROOT = path.resolve(__dirname, '..');
const LIBS = process.env.CF_LIBS || path.join(os.tmpdir(), 'cineflow-libs');
const PORT = process.env.CF_PORT || '8167';
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
for (const [f, u] of Object.entries(LIB_URLS)) {
  const q = path.join(LIBS, f);
  if (!fs.existsSync(q) || fs.statSync(q).size < 1000) execSync(`curl -sSL -o "${q}" "${u}"`);
}
const server = spawn('python3', ['-m', 'http.server', PORT, '--bind', '127.0.0.1'], { cwd: ROOT, stdio: 'ignore' });
let bad = 0;
const ok = (n, c, d) => { console.log((c ? '  ok  ' : '  FAIL') + ' ' + n + (d ? ' — ' + d : '')); if (!c) bad++; };

// Две смены: 1–3 в первую, 4–5 во вторую. Сегодняшний день в стенде раньше
// обеих, поэтому «Смена 1» — ближайшая, и список телефона показывает 1–3.
const SCENES = [
  ['s1', '1', 'ИНТ. КУХНЯ — ДЕНЬ', '2099-11-01'],
  ['s2', '2', 'НАТ. ДВОР ШКОЛЫ У ГАРАЖЕЙ — ДЕНЬ', '2099-11-01'],
  ['s3', '3', 'ИНТ. ЛИФТ — НОЧЬ', '2099-11-01'],
  ['s4', '4', 'НАТ. МОСТ — ВЕЧЕР', '2099-11-05'],
  ['s5', '5', 'ИНТ. ГАРАЖ — НОЧЬ', '2099-11-05']
].map(([id, number, title, date]) => ({ id, number, title, date, content: '', gear: {}, lightGear: {}, lightSchemeId: null }));
// Много кадров — чтобы «Съёмка» прокручивалась и было что сбрасывать.
const FRAMES = [];
for (const sc of SCENES) for (let k = 1; k <= 14; k++) FRAMES.push({ id: `${sc.id}-f${k}`, sceneId: sc.id, frameNum: `${sc.number}.${k}`, description: `Кадр ${k}: общий план, панорама`, image: '' });

(async () => {
  await new Promise(r => setTimeout(r, 1200));
  const browser = await playwright.chromium.launch({
    executablePath: process.env.CF_CHROME || '/opt/pw-browsers/chromium', args: ['--no-sandbox'] });
  const mk = async (viewport, url = 'index.html') => {
    const phone = viewport.width < 500;
    // Телефон представляется iPhone: шкала касания (цель 44) включается по
    // самому устройству, а стенд иначе мерил бы ноутбучную (36).
    const ctx = await browser.newContext({ viewport, serviceWorkers: 'block', hasTouch: phone, isMobile: phone,
      userAgent: phone ? 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1' : undefined });
    await ctx.route('**/*', route => {
      const u = route.request().url();
      if (/firestore|firebase|googleapis\.com\/(identitytoolkit|securetoken)|gstatic/.test(u)) return route.abort();
      for (const [f, re] of [['react.js', /react@18[.0-9]*\/umd\/react\.production/], ['react-dom.js', /react-dom@18/],
                             ['babel.js', /babel\.min\.js/], ['tailwind.js', /cdn\.tailwindcss/]])
        if (re.test(u)) return route.fulfill({ body: fs.readFileSync(path.join(LIBS, f)), contentType: 'application/javascript',
                                               headers: { 'Access-Control-Allow-Origin': '*' } });
      route.continue();
    });
    await ctx.addInitScript(([sc, fr]) => {
      if (sessionStorage.getItem('__seeded')) return;
      sessionStorage.setItem('__seeded', '1');
      localStorage.setItem('cf_room', 'scenenav-room-test-0001');
      localStorage.setItem('cf_user_name', 'Тест');
      localStorage.setItem('cf_scene_mode', 'creative');
      localStorage.setItem('cf_scenes', JSON.stringify(sc));
      localStorage.setItem('cf_storyboard', JSON.stringify(fr));
    }, [SCENES, FRAMES]);
    const page = await ctx.newPage();
    const errs = [];
    page.on('pageerror', e => errs.push(String(e).slice(0, 200)));
    await page.goto(`http://127.0.0.1:${PORT}/${url}`);
    await page.waitForFunction(() => window.__CF_APP_OK, { timeout: 180000 });
    await page.waitForTimeout(900);
    return { page, errs, ctx };
  };
  // Нажатие по-настоящему: середина элемента обязана попадать в него самого.
  const tap = async (page, sel, label) => {
    const el = page.locator(sel).first();
    const b = await el.boundingBox();
    if (!b) { ok(label + ': есть на экране', false); return false; }
    const h = await el.elementHandle();
    const x = b.x + b.width / 2, y = b.y + b.height / 2;
    const hit = await page.evaluate(([t, x, y]) => { const e = document.elementFromPoint(x, y); return !!(e && (t === e || t.contains(e))); }, [h, x, y]);
    ok(label + ': нажатие попадает', hit);
    await page.mouse.click(x, y);
    await page.waitForTimeout(300);
    return hit;
  };
  const rows = (page) => page.$$eval('[data-cf="scene-row"]', els => els.map(e => e.dataset.id));
  const nav = (page) => page.evaluate(() => {
    const n = document.querySelector('[data-cf="scene-nav"]');
    if (!n) return null;
    const p = n.querySelector('[data-cf="scene-prev"]'), x = n.querySelector('[data-cf="scene-next"]');
    const m = document.querySelector('[data-cf="phone-scene-main"]');
    return { prev: p.textContent.trim(), prevOff: p.disabled, next: x.textContent.trim(), nextOff: x.disabled,
             pos: n.querySelector('[data-cf="scene-nav-pos"]').textContent, scene: (m && m.textContent.match(/СЦ(?:ЕНА)? (\d+)/) || [])[1],
             h: Math.round(n.getBoundingClientRect().height), bottom: Math.round(n.getBoundingClientRect().bottom),
             tabTop: Math.round(document.querySelector('.cf-tabbar').getBoundingClientRect().top) };
  });

  console.log('Телефон 390');
  {
    const { page, errs, ctx } = await mk({ width: 390, height: 844 });
    const shown = await rows(page);
    ok('список под сменой: 1–3', shown.join(',') === 's1,s2,s3', shown.join(','));
    ok('на списке полосы нет', !(await nav(page)));
    await tap(page, '[data-cf="scene-row"][data-id="s2"]', 'строка #2');
    let n = await nav(page);
    ok('открылась #2, полоса «#1 ‹ · 2 из 3 · › #3»', n && n.scene === '2' && /#1/.test(n.prev) && /#3/.test(n.next) && n.pos === '2 из 3' && !n.prevOff && !n.nextOff, JSON.stringify(n));
    ok('полоса стоит вплотную над таб-баром, высотой под палец', n && n.bottom === n.tabTop && n.h >= 44, n && `${n.h} точек, низ ${n.bottom}, таб-бар ${n.tabTop}`);
    ok('название соседа без «ИНТ.», с номером', n && /#3\s*ЛИФТ/.test(n.next) && !/ИНТ/.test(n.next), n && n.next);
    await tap(page, '[data-cf="scene-next"]', '«следующая»');
    n = await nav(page);
    ok('следующая — #3, вперёд дальше некуда', n && n.scene === '3' && n.pos === '3 из 3' && n.nextOff && /#2/.test(n.prev), JSON.stringify(n));
    await tap(page, '[data-cf="scene-prev"]', '«предыдущая»');
    await tap(page, '[data-cf="scene-prev"]', '«предыдущая» ещё раз');
    n = await nav(page);
    ok('дважды назад — #1, назад дальше некуда', n && n.scene === '1' && n.pos === '1 из 3' && n.prevOff && /#2/.test(n.next), JSON.stringify(n));
    const stuck = await page.evaluate(() => { const b = document.querySelector('[data-cf="scene-prev"]'); const r = b.getBoundingClientRect(); const e = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2); return !!e; });
    ok('погасшая стрелка на месте, полоса не прыгает', stuck);

    // «Съёмка»: полоса на месте, переход сбрасывает прокрутку
    await tap(page, 'header .cf-seg button:has-text("Съёмка")', 'режим «Съёмка»');
    const sc = await page.evaluate(async () => {
      const m = document.querySelector('[data-cf="phone-scene-main"]');
      m.scrollTop = 99999; await new Promise(r => setTimeout(r, 100));
      return { can: m.scrollHeight > m.clientHeight + 50, top: m.scrollTop, nav: !!document.querySelector('[data-cf="scene-nav"]') };
    });
    ok('в «Съёмке» полоса на месте, список кадров прокручивается', sc.nav && sc.can && sc.top > 100, JSON.stringify(sc));
    await tap(page, '[data-cf="scene-next"]', '«следующая» в «Съёмке»');
    const after = await page.evaluate(() => ({ top: document.querySelector('[data-cf="phone-scene-main"]').scrollTop, t: document.querySelector('[data-cf="phone-scene-main"]').textContent.slice(0, 60) }));
    n = await nav(page);
    ok('следующая сцена открылась с начала, а не с середины', after.top === 0 && n && n.scene === '2', JSON.stringify({ ...after, scene: n && n.scene }));

    // Фильтр «Все»: порядок — как в списке
    await tap(page, 'header button:has-text("‹ Сцены")', '«‹ Сцены»');
    await tap(page, '.cf-pill:has-text("Все")', 'фильтр «Все»');
    ok('под «Все» пять строк', (await rows(page)).length === 5);
    await tap(page, '[data-cf="scene-row"][data-id="s3"]', 'строка #3');
    n = await nav(page);
    ok('под «Все» за #3 идёт #4 из другой смены, «3 из 5»', n && /#4/.test(n.next) && n.pos === '3 из 5', JSON.stringify(n));
    ok('без ошибок на странице', errs.length === 0, errs.join(' | '));
    await ctx.close();
  }

  console.log('Планшет 1280');
  {
    const { page, ctx } = await mk({ width: 1280, height: 900 });
    ok('на планшете полосы нет — список сцен и так рядом', !(await page.$('[data-cf="scene-nav"]')));
    await ctx.close();
  }

  console.log('Гость по ссылке, телефон');
  {
    const { page, errs, ctx } = await mk({ width: 390, height: 844 }, 'index.html?view=all&room=scenenav-room-test-0001');
    await tap(page, '[data-cf="scene-row"][data-id="s1"]', 'строка #1 у гостя');
    let n = await nav(page);
    ok('у гостя полоса есть', !!n && n.scene === '1', JSON.stringify(n));
    await tap(page, '[data-cf="scene-next"]', '«следующая» у гостя');
    n = await nav(page);
    ok('и листает', n && n.scene === '2', JSON.stringify(n));
    ok('без ошибок у гостя', errs.length === 0, errs.join(' | '));
    await ctx.close();
  }

  await browser.close(); server.kill();
  console.log(bad ? `\n${bad} проверок не прошло` : '\nВсё прошло');
  process.exit(bad ? 1 : 0);
})().catch(e => { console.error(e); server.kill(); process.exit(1); });
