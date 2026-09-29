// Шкала по способу ввода: на ноутбуке с сенсорным экраном (Flow X13)
// интерфейс крупный от пальца и пера и плотный от мыши и тачпада. iPad
// и телефон это не задевает — там крупный всегда, компьютер без касания —
// плотный всегда. Проверяется в браузере: «сменилась ли шкала» — это
// вычисленный размер цели, а «дошло ли нажатие» — открылось ли меню.
const fs = require('fs'), os = require('os'), path = require('path');
const { execSync, spawn } = require('child_process');
const ROOT = path.resolve(__dirname, '..'), LIBS = process.env.CF_LIBS || path.join(os.tmpdir(), 'cineflow-libs'), PORT = '8163';
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
const IPAD_UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15';

(async () => {
  await new Promise(r => setTimeout(r, 1000));
  const browser = await playwright.chromium.launch({ executablePath: '/opt/pw-browsers/chromium', args: ['--no-sandbox'] });
  const mk = async (opts, init = {}) => {
    const { platform, ...copts } = opts;
    const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, serviceWorkers: 'block', ...copts });
    await ctx.route('**/*', route => {
      const u = route.request().url();
      if (/firestore|firebase|googleapis|gstatic|nominatim/.test(u)) return route.abort();
      for (const [f, re] of [['react.js', /react@18\/umd\/react\.production/], ['react-dom.js', /react-dom@18/], ['babel.js', /babel\.min\.js/], ['tailwind.js', /cdn\.tailwindcss/]])
        if (re.test(u)) return route.fulfill({ body: fs.readFileSync(path.join(LIBS, f)), contentType: 'application/javascript' });
      route.continue();
    });
    // Safari на iPad представляется Маком: платформа MacIntel плюс касание
    if (opts.platform) await ctx.addInitScript(pl => { Object.defineProperty(Navigator.prototype, 'platform', { get: () => pl });
      Object.defineProperty(Navigator.prototype, 'maxTouchPoints', { get: () => 5 }); }, opts.platform);
    await ctx.addInitScript(s => {
      if (sessionStorage.getItem('seeded')) return;
      sessionStorage.setItem('seeded', '1');
      localStorage.setItem('cf_room', 'scale-room'); localStorage.setItem('cf_user_name', 'Тест');
      for (const k in s) localStorage.setItem(k, s[k]);
    }, init);
    const page = await ctx.newPage();
    const errs = [];
    page.on('pageerror', e => errs.push(String(e).slice(0, 200)));
    await page.goto(`http://127.0.0.1:${PORT}/index.html`);
    await page.waitForFunction(() => window.__CF_APP_OK, { timeout: 180000 });
    await page.waitForTimeout(1000);
    return { ctx, page, errs };
  };
  const state = (p) => p.evaluate(() => ({
    touch: document.documentElement.classList.contains('cf-touch'),
    tap: getComputedStyle(document.documentElement).getPropertyValue('--tap').trim(),
    last: localStorage.getItem('cf_input_last'),
  }));
  const swipeMouse = async (p) => {
    await p.mouse.move(700, 450);
    await p.mouse.move(820, 480, { steps: 12 });
    await p.waitForTimeout(150);
  };
  const tapTouch = async (p, x = 1400, y = 860) => { await p.touchscreen.tap(x, y); await p.waitForTimeout(500); };
  const openProject = async (p) => {
    await p.evaluate(() => document.querySelector('button[title^="Проект, доступ"]').click());
    await p.waitForTimeout(300);
    await p.evaluate(() => [...document.querySelectorAll('button')].find(b => b.textContent.trim() === 'Проект').click());
    await p.waitForTimeout(500);
  };
  const pickScale = (p, label) => p.evaluate((t) => {
    const b = [...document.querySelectorAll('[data-cf="input-scale"] button')].find(x => x.textContent === t);
    b.click(); return !!b;
  }, label);

  // ---- НОУТБУК С СЕНСОРНЫМ ЭКРАНОМ (как Flow X13): Linux, касание есть
  {
    const { ctx, page: p, errs } = await mk({ hasTouch: true }, { cf_input_last: 'mouse' });
    let s = await state(p);
    ok('ноутбук: запуск после мыши — плотная шкала', !s.touch && s.tap === '34px', JSON.stringify(s));
    await tapTouch(p);
    s = await state(p);
    ok('коснулись пальцем — шкала крупная', s.touch && s.tap === '44px' && s.last === 'touch', JSON.stringify(s));
    await p.mouse.move(700, 450); await p.mouse.move(704, 451);
    await p.waitForTimeout(150);
    s = await state(p);
    ok('дрожь тачпада в пару точек шкалу не меняет', s.touch, JSON.stringify(s));
    await swipeMouse(p);
    s = await state(p);
    ok('повели тачпадом — снова плотная', !s.touch && s.tap === '34px' && s.last === 'mouse', JSON.stringify(s));
    await tapTouch(p);
    await p.mouse.wheel(0, 120); await p.waitForTimeout(150);
    s = await state(p);
    ok('прокрутка тачпадом — тоже плотная', !s.touch, JSON.stringify(s));

    // Нажатие, которым шкала и сменилась, обязано дойти до своей кнопки
    const r = await p.evaluate(() => { const b = document.querySelector('button[title^="Проект, доступ"]').getBoundingClientRect(); return { x: b.x + b.width / 2, y: b.y + b.height / 2 }; });
    await p.touchscreen.tap(r.x, r.y);
    await p.waitForTimeout(600);
    const menuOpen = await p.evaluate(() => [...document.querySelectorAll('button')].some(b => b.textContent.trim() === 'Проект' && b.offsetParent));
    s = await state(p);
    ok('касание, сменившее шкалу, открыло меню, в которое целили', menuOpen && s.touch, JSON.stringify({ menuOpen, ...s }));
    await p.keyboard.press('Escape');

    await p.reload(); await p.waitForFunction(() => window.__CF_APP_OK, { timeout: 180000 }); await p.waitForTimeout(800);
    s = await state(p);
    ok('после перезапуска — та шкала, которой работали последней', s.touch, JSON.stringify(s));

    await openProject(p);
    const row = await p.evaluate(() => { const r = document.querySelector('[data-cf="input-scale"]'); return r ? r.textContent : null; });
    ok('в «Проекте» есть «Размер интерфейса» с состоянием', !!row && /Сейчас крупный/.test(row), row);
    await pickScale(p, 'Плотный'); await p.waitForTimeout(200);
    // Касаемся внутри окна (по подписи строки): нажатие по фону окно закрыло бы
    const lab = await p.evaluate(() => { const r = document.querySelector('[data-cf="input-scale"] .min-w-0').getBoundingClientRect(); return { x: r.x + 20, y: r.y + 8 }; });
    await tapTouch(p, lab.x, lab.y);
    s = await state(p);
    ok('«Плотный» держится и после касания', !s.touch && s.tap === '34px', JSON.stringify(s));
    await pickScale(p, 'Крупный'); await p.waitForTimeout(200);
    await swipeMouse(p);
    s = await state(p);
    ok('«Крупный» держится и после мыши', s.touch && s.tap === '44px', JSON.stringify(s));
    await pickScale(p, 'Авто'); await p.waitForTimeout(200);
    await swipeMouse(p);
    s = await state(p);
    const pref = await p.evaluate(() => localStorage.getItem('cf_input_scale'));
    ok('«Авто» возвращает автоматику и запоминается', !s.touch && pref === 'auto', JSON.stringify({ pref, ...s }));
    await p.keyboard.press('Escape'); await p.waitForTimeout(300);

    // «Откуда взять фото»: на ноутбуке выбирать не из чего — окно файла сразу
    await tapTouch(p);
    await p.evaluate(() => [...document.querySelectorAll('.cf-tabbar button, header button')].find(x => /Галерея/i.test((x.textContent || '') + (x.title || ''))).click());
    await p.waitForTimeout(900);
    const chooser = p.waitForEvent('filechooser', { timeout: 3000 }).then(() => true, () => false);
    const rb = await p.evaluate(() => { const b = [...document.querySelectorAll('button')].find(x => /Загрузить референсы/.test(x.textContent) && x.offsetParent); if (!b) return null; const r = b.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 }; });
    if (rb) await p.mouse.click(rb.x, rb.y);
    const got = await chooser;
    const sheet = await p.evaluate(() => [...document.querySelectorAll('button, [role="menuitem"]')].some(x => /Фотоплёнка/.test(x.textContent) && x.offsetParent));
    ok('ноутбук: «Загрузить» открывает окно файла сразу, без списка', !!rb && got && !sheet, JSON.stringify({ button: !!rb, chooser: got, sheet }));
    ok('ноутбук: без ошибок на странице', !errs.length, errs.join(' | '));
    await ctx.close();
  }

  // ---- ПЕРВЫЙ ЗАПУСК на ноутбуке: выбора ещё нет — спрашиваем главный указатель
  {
    const { ctx, page: p } = await mk({ hasTouch: true });
    const s = await state(p);
    const coarse = await p.evaluate(() => matchMedia('(pointer: coarse)').matches);
    ok('первый запуск: шкала по главному указателю', s.touch === coarse, JSON.stringify({ coarse, ...s }));
    await ctx.close();
  }

  // ---- iPad с трекпадом: крупный всегда
  {
    const { ctx, page: p, errs } = await mk({ hasTouch: true, userAgent: IPAD_UA, platform: 'MacIntel', viewport: { width: 1194, height: 834 } }, { cf_input_last: 'mouse' });
    await swipeMouse(p);
    let s = await state(p);
    ok('iPad: мышь/трекпад шкалу не сжимают', s.touch && s.tap === '44px', JSON.stringify(s));
    await openProject(p);
    const row = await p.evaluate(() => { const r = document.querySelector('[data-cf="input-scale"]'); return r ? r.textContent : null; });
    ok('iPad: в «Проекте» «Авто» значит крупный', !!row && /держат в руках/.test(row), row);
    ok('iPad: без ошибок', !errs.length, errs.join(' | '));
    await ctx.close();
  }

  // ---- iPhone: крупный всегда, и «+» в галерее спрашивает, откуда брать
  {
    const dev = playwright.devices['iPhone 13'];
    const { ctx, page: p, errs } = await mk({ ...dev, serviceWorkers: 'block' }, { cf_input_last: 'mouse' });
    let s = await state(p);
    ok('iPhone: шкала крупная', s.touch && s.tap === '44px', JSON.stringify(s));
    await p.evaluate(() => [...document.querySelectorAll('.cf-tabbar button')].find(x => /Галерея/i.test(x.textContent)).click());
    await p.waitForTimeout(900);
    const plus = await p.evaluate(() => { const b = document.querySelector('button[title^="Добавить фото или видео"]'); if (!b) return null; const r = b.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 }; });
    if (plus) await p.touchscreen.tap(plus.x, plus.y);
    await p.waitForTimeout(600);
    const sheet = await p.evaluate(() => [...document.querySelectorAll('button, [role="menuitem"]')].some(x => /Фотоплёнка/.test(x.textContent) && x.offsetParent));
    ok('iPhone: «+» открывает шторку «Откуда взять фото»', !!plus && sheet, JSON.stringify({ plus: !!plus, sheet }));
    ok('iPhone: без ошибок', !errs.length, errs.join(' | '));
    await ctx.close();
  }

  // ---- Компьютер без сенсорного экрана: плотный, выбора нет
  {
    const { ctx, page: p } = await mk({ hasTouch: false }, { cf_input_last: 'touch' });
    const s = await state(p);
    ok('без касания: плотная шкала, что бы ни было записано', !s.touch && s.tap === '34px', JSON.stringify(s));
    await openProject(p);
    const row = await p.evaluate(() => !!document.querySelector('[data-cf="input-scale"]'));
    ok('без касания: переключателя в «Проекте» нет', !row);
    await ctx.close();
  }

  await browser.close(); server.kill();
  console.log(bad ? `\n${bad} проверок не прошло` : '\nвсё прошло');
  process.exit(bad ? 1 : 0);
})().catch(e => { console.error(e); server.kill(); process.exit(1); });
