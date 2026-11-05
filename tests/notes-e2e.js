// Заметки: свёрстанный текст в покое, поле с кнопками по нажатию.
//
// Проверяется в браузере и НАЖАТИЕМ (elementFromPoint + настоящая мышь),
// а не чтением кода: кнопки разметки обязаны не отнимать курсор у поля,
// иначе правка ляжет не в ту строку, а заметно это только при нажатии.
//
// Что гоняем: старый гайд (заголовок прописными, списки) свёрстан;
// разметка (# · -# · [ ] · ** · ссылки) свёрстана; нажатие по абзацу
// открывает поле с курсором В ЭТОМ абзаце; кнопки «Заголовок», «мелкий»,
// «Галочки», «Ж» правят строку под курсором и снимаются повторно;
// Enter продолжает список, пустой пункт его кончает; «Ссылка» и [[ —
// выбор сцены, в покое ссылка ведёт в сцену; галочка в покое ставится
// одним нажатием; адрес javascript: ссылкой не становится; печать
// понимает новую разметку; переименование «гайд» → «заметка»; гость
// по ссылке только читает (ссылки работают, правки нет); телефон 390.
//
// Запуск:  node tests/notes-e2e.js
const fs = require('fs'), os = require('os'), path = require('path');
const { execSync, spawn } = require('child_process');
const ROOT = path.resolve(__dirname, '..');
const LIBS = process.env.CF_LIBS || path.join(os.tmpdir(), 'cineflow-libs');
const PORT = process.env.CF_PORT || '8147';
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
  const p = path.join(LIBS, f);
  if (!fs.existsSync(p) || fs.statSync(p).size < 1000) execSync(`curl -sSL -o "${p}" "${u}"`);
}
const server = spawn('python3', ['-m', 'http.server', PORT, '--bind', '127.0.0.1'], { cwd: ROOT, stdio: 'ignore' });
let bad = 0;
const ok = (n, c, d) => { console.log((c ? '  ok  ' : '  FAIL') + ' ' + n + (d ? ' — ' + d : '')); if (!c) bad++; };

const OLD = ['СВЕТ НА ИНТЕРЬЕРАХ', '', 'Ключ ставим по лицу.', '', '- ND 0.6 на окна;', '- практики 2700K.'].join('\n');
const NOTE = [
  'Кадры посчитаны по монтажу.',
  '',
  '# 1й бой',
  '-# всего кадров',
  '21',
  '-# кран',
  '12',
  '',
  '[ ] взять флаги',
  '[x] заказать кран',
  '',
  'Смотри [#2 · КУХНЯ](cf:scene/sc2), сайт https://example.com и [плохо](javascript:alert(1)).',
  '',
  'Последний абзац **жирно**.'
].join('\n');

(async () => {
  await new Promise(r => setTimeout(r, 1200));
  const browser = await playwright.chromium.launch({ executablePath: process.env.CF_CHROME || '/opt/pw-browsers/chromium', args: ['--no-sandbox'] });
  const mk = async (opts = {}) => {
    const ctx = await browser.newContext({ viewport: opts.vp || { width: 1280, height: 900 }, serviceWorkers: 'block', hasTouch: !!opts.touch, isMobile: !!opts.touch });
    await ctx.route('**/*', route => {
      const u = route.request().url();
      // Настоящий Firebase ЗАБЛОКИРОВАН: иначе стенд писал бы в проект пользователя.
      if (/firestore|firebase|googleapis|gstatic|nominatim/.test(u)) return route.abort();
      for (const [f, re] of [['react.js', /react@18[.0-9]*\/umd\/react\.production/], ['react-dom.js', /react-dom@18/],
                             ['babel.js', /babel\.min\.js/], ['tailwind.js', /cdn\.tailwindcss/]])
        if (re.test(u)) return route.fulfill({ body: fs.readFileSync(path.join(LIBS, f)), contentType: 'application/javascript' });
      route.continue();
    });
    await ctx.addInitScript(([note, old]) => {
      if (sessionStorage.getItem('__seeded')) return;
      sessionStorage.setItem('__seeded', '1');
      localStorage.setItem('cf_room', 'notes-room-test-0001');
      localStorage.setItem('cf_user_name', 'Тест');
      localStorage.setItem('cf_docs', JSON.stringify([
        { id: 'doc-1', title: 'Подсчёт кадров', content: note },
        { id: 'doc-2', title: 'Старый гайд', content: old },
        { id: 'doc-3', title: 'Длинная', content: Array.from({ length: 60 }, (_, i) => `Строка номер ${i + 1}.`).join('\n\n') }]));
      localStorage.setItem('cf_scenes', JSON.stringify([
        { id: 'sc1', number: '1', title: 'ИНТ. КАБИНА — ДЕНЬ', content: '', gear: {}, lightGear: {} },
        { id: 'sc2', number: '2', title: 'ИНТ. КУХНЯ — ВЕЧЕР', content: 'Экспликация кухни', gear: {}, lightGear: {} }]));
      localStorage.setItem('cf_locations', JSON.stringify([{ id: 'loc-1', name: 'Квартира на Горской', sceneIds: ['sc2'], order: 1 }]));
      window.print = () => { const a = document.getElementById('print-area'); window.__printHTML = a ? a.innerHTML : ''; };
    }, [NOTE, OLD]);
    const page = await ctx.newPage();
    const errs = [];
    page.on('pageerror', e => errs.push(String(e).slice(0, 200)));
    await page.goto(`http://127.0.0.1:${PORT}/index.html${opts.q || ''}`);
    await page.waitForFunction(() => window.__CF_APP_OK, { timeout: 180000 });
    await page.waitForTimeout(900);
    return { ctx, page, errs };
  };
  const goDocs = (page) => page.evaluate(async () => {
    const b = [...document.querySelectorAll('.cf-tabbar button, header button, .cf-sheet button')].find(x => /Эксплик/i.test((x.textContent || '') + (x.title || '')));
    if (b) b.click();
    await new Promise(r => setTimeout(r, 700));
  });
  // Нажатие по центру элемента НАСТОЯЩЕЙ мышью, и сперва — попадает ли
  // туда сам элемент, а не что-то поверх него.
  const press = async (page, fn, name) => {
    const r = await page.evaluate((src) => {
      const el = (new Function('return (' + src + ')()'))();
      if (!el) return null;
      el.scrollIntoView({ block: 'center' });
      const b = el.getBoundingClientRect();
      const x = b.left + Math.min(b.width / 2, 12), y = b.top + b.height / 2;
      const hit = document.elementFromPoint(x, y);
      return { x, y, hits: !!hit && (hit === el || el.contains(hit)) };
    }, fn.toString());
    if (!r) { ok(`${name}: есть на экране`, false); return false; }
    if (!r.hits) ok(`${name}: нажатие попадает`, false);
    await page.mouse.click(r.x, r.y);
    await page.waitForTimeout(250);
    return r.hits;
  };
  const content = (page, id = 'doc-1') => page.evaluate((i) => (JSON.parse(localStorage.getItem('cf_docs') || '[]').find(d => d.id === i) || {}).content || '', id);
  const flush = (page) => page.waitForTimeout(900);   // местная копия пишется с задержкой 700 мс
  const taState = (page) => page.evaluate(() => {
    const t = document.querySelector('[data-cf="note-input"]');
    return t ? { v: t.value, s: t.selectionStart, e: t.selectionEnd, focus: document.activeElement === t } : null;
  });

  // ================= ПЛАНШЕТ / КОМПЬЮТЕР =================
  const { page, errs } = await mk();
  await goDocs(page);
  const names = await page.evaluate(() => document.body.innerText);
  ok('список называется «Заметки», кнопка «Новая заметка»', /Заметки/.test(names) && /Новая заметка/.test(names) && !/Операторские гайды|Создать гайд/.test(names));

  const view = await page.evaluate(() => {
    const v = document.querySelector('[data-cf="note-view"]');
    if (!v) return null;
    const h = v.querySelector('.cf-md-h1'), s = v.querySelector('.cf-md-s'), p = v.querySelector('.cf-md-p');
    const fs2 = (el) => el ? parseFloat(getComputedStyle(el).fontSize) : 0;
    return {
      h: h && h.textContent, hfs: fs2(h), sfs: fs2(s), pfs: fs2(p), s: s && s.textContent,
      boxes: v.querySelectorAll('[data-cf="note-check"]').length, done: v.querySelectorAll('[data-cf="note-check"][aria-pressed="true"]').length,
      ref: (v.querySelector('[data-cf="note-ref"]') || {}).textContent,
      ext: [...v.querySelectorAll('a.cf-md-a')].map(a => a.getAttribute('href') + '|' + a.target),
      js: [...v.querySelectorAll('a')].some(a => /javascript/i.test(a.getAttribute('href') || '')),
      bold: (v.querySelector('strong') || {}).textContent, raw: /\[x\]|^# |-#|\*\*/m.test(v.innerText),
      ta: !!document.querySelector('[data-cf="note-input"]')
    };
  });
  ok('в покое — свёрстанный текст, а не поле', view && !view.ta && !view.raw, JSON.stringify(view && { ta: view.ta, raw: view.raw }));
  ok('заголовок крупнее текста, «мелкий» мельче', view && view.h === '1й бой' && view.hfs > view.pfs && view.sfs < view.pfs, view && `${view.hfs}/${view.pfs}/${view.sfs}`);
  ok('галочки: две, одна отмечена', view && view.boxes === 2 && view.done === 1);
  ok('ссылка на сцену показывает ЖИВОЕ имя', view && view.ref === '#2 · ИНТ. КУХНЯ — ВЕЧЕР', view && view.ref);
  ok('сайт — ссылкой в новой вкладке, javascript: — нет', view && view.ext.length === 1 && /^https:\/\/example\.com\|_blank$/.test(view.ext[0]) && !view.js, view && view.ext.join(','));
  ok('**жирно** — жирным', view && view.bold === 'жирно');

  // Галочка в покое — одним нажатием, без поля.
  await press(page, () => document.querySelector('[data-cf="note-check"]'), 'галочка');
  await flush(page);
  ok('галочка ставится в покое и пишется в текст', /\[x\] взять флаги/.test(await content(page)) && !(await taState(page)));

  // Нажатие по абзацу — поле с курсором В ЭТОМ абзаце.
  await press(page, () => [...document.querySelectorAll('[data-cf="note-view"] .cf-md-p')].find(p => /Последний/.test(p.textContent)), 'последний абзац');
  let st = await taState(page);
  const lastLine = NOTE.split('\n').length - 1;
  ok('нажатие по абзацу открывает поле, курсор в этом абзаце', st && st.focus && st.v.slice(0, st.s).split('\n').length - 1 === lastLine, st && `строка ${st.v.slice(0, st.s).split('\n').length - 1} из ${lastLine}`);
  ok('кнопки разметки видны', await page.evaluate(() => !!document.querySelector('[data-cf="note-bar"] [data-tool="h1"]')));

  // «Заголовок» на строке под курсором, повторно — снимает.
  const tool = (k) => () => document.querySelector(`[data-cf="note-bar"] [data-tool="${k}"]`);
  await press(page, new Function(`return document.querySelector('[data-cf="note-bar"] [data-tool="h1"]')`), '«Заголовок»');
  st = await taState(page);
  ok('«Заголовок» ставит «# » строке под курсором, курсор не ушёл', st && st.focus && /\n# Последний абзац \*\*жирно\*\*\.$/.test(st.v), st && JSON.stringify(st.v.slice(-40)));
  await press(page, new Function(`return document.querySelector('[data-cf="note-bar"] [data-tool="h1"]')`), '«Заголовок» ещё раз');
  st = await taState(page);
  ok('повторное нажатие снимает заголовок', st && /\nПоследний абзац \*\*жирно\*\*\.$/.test(st.v));
  await press(page, new Function(`return document.querySelector('[data-cf="note-bar"] [data-tool="s"]')`), '«мелкий»');
  st = await taState(page);
  ok('«мелкий» ставит «-# »', st && /\n-# Последний абзац/.test(st.v));
  await press(page, new Function(`return document.querySelector('[data-cf="note-bar"] [data-tool="cl"]')`), '«Галочки»');
  st = await taState(page);
  ok('«Галочки» меняет вид строки на «[ ] »', st && /\n\[ \] Последний абзац/.test(st.v) && !/-# Последний/.test(st.v));
  await press(page, new Function(`return document.querySelector('[data-cf="note-bar"] [data-tool="p"]')`), '«Текст»');
  st = await taState(page);
  ok('«Текст» возвращает обычную строку', st && /\nПоследний абзац \*\*жирно\*\*\.$/.test(st.v));

  // «Ж» по выделенному слову.
  await page.evaluate(() => { const t = document.querySelector('[data-cf="note-input"]'); const i = t.value.indexOf('Кадры'); t.focus(); t.setSelectionRange(i, i + 5); });
  await press(page, new Function(`return document.querySelector('[data-cf="note-bar"] [data-tool="**"]')`), '«Ж»');
  st = await taState(page);
  ok('«Ж» оборачивает выделенное в **', st && st.v.startsWith('**Кадры** посчитаны'), st && st.v.slice(0, 22));

  // Enter продолжает список, пустой пункт его кончает.
  await page.evaluate(() => { const t = document.querySelector('[data-cf="note-input"]'); t.focus(); t.setSelectionRange(t.value.length, t.value.length); });
  await page.keyboard.press('Enter'); await page.keyboard.press('Enter');
  await page.keyboard.type('- раз'); await page.keyboard.press('Enter'); await page.keyboard.type('два');
  await page.keyboard.press('Enter'); await page.keyboard.press('Enter'); await page.keyboard.type('после');
  st = await taState(page);
  ok('Enter продолжает список, пустой пункт его кончает', st && /\n- раз\n- два\nпосле$/.test(st.v), st && JSON.stringify(st.v.slice(-25)));

  // Ссылка кнопкой: выбор сцены поиском.
  await page.keyboard.press('Enter'); await page.keyboard.type('Объект: ');
  await press(page, new Function(`return document.querySelector('[data-cf="note-bar"] [data-tool="link"]')`), '«Ссылка»');
  const pickOpen = await page.evaluate(() => !!document.querySelector('[data-cf="note-pick"]') && document.activeElement && document.activeElement.classList.contains('cf-md-pick-q'));
  ok('«Ссылка» открывает выбор с полем поиска', pickOpen);
  await page.keyboard.type('Горск');
  await press(page, () => [...document.querySelectorAll('.cf-md-pick-row')].find(b => /Горской/.test(b.textContent)), 'объект в выборе');
  st = await taState(page);
  ok('ссылка на объект легла по id, курсор вернулся в поле', st && /Объект: \[Квартира на Горской\]\(cf:loc\/loc-1\)$/.test(st.v) && st.focus, st && JSON.stringify(st.v.slice(-50)));
  // [[ — тот же выбор.
  await page.keyboard.type(' и [[');
  ok('[[ открывает выбор ссылки', await page.evaluate(() => !!document.querySelector('[data-cf="note-pick"]')));
  await page.keyboard.type('каб'); await page.keyboard.press('Enter');
  await page.waitForTimeout(300);
  st = await taState(page);
  ok('[[ + Enter вставляет первую найденную сцену вместо [[', st && /и \[#1 · ИНТ\. КАБИНА — ДЕНЬ\]\(cf:scene\/sc1\)$/.test(st.v) && !/\[\[/.test(st.v), st && JSON.stringify(st.v.slice(-50)));

  // «Готово» — снова свёрстанный текст, записано в проект.
  await press(page, () => document.querySelector('[data-cf="note-done"]'), '«Готово»');
  await flush(page);
  const after = await page.evaluate(() => ({ ta: !!document.querySelector('[data-cf="note-input"]'), refs: [...document.querySelectorAll('[data-cf="note-ref"]')].map(b => b.textContent) }));
  ok('«Готово» возвращает свёрстанный вид, ссылки — живыми именами', !after.ta && after.refs.includes('Квартира на Горской') && after.refs.includes('#1 · ИНТ. КАБИНА — ДЕНЬ'), after.refs.join(' | '));
  ok('текст записан в проект', /cf:loc\/loc-1/.test(await content(page)));

  // Старый гайд: прописной заголовок и список — без единой правки.
  await press(page, () => [...document.querySelectorAll('button')].find(b => b.textContent.trim() === 'Старый гайд'), 'старый гайд в списке');
  const old = await page.evaluate(() => { const v = document.querySelector('[data-cf="note-view"]'); return v && { h: (v.querySelector('.cf-md-h') || {}).textContent, li: v.querySelectorAll('.cf-md-ul li').length }; });
  ok('старый гайд открывается свёрстанным как был', old && old.h === 'СВЕТ НА ИНТЕРЬЕРАХ' && old.li === 2, JSON.stringify(old));
  ok('и его текст не тронут', (await content(page, 'doc-2')) === OLD);
  await press(page, () => [...document.querySelectorAll('button')].find(b => b.textContent.trim() === 'Длинная'), 'длинная заметка в списке');
  const longClip = await page.evaluate(() => document.querySelector('[data-cf="note-view"]').classList.contains('cf-md-clip'));
  await press(page, () => document.querySelector('[data-cf="note-open"]'), '«развернуть»');
  const longOpen = await page.evaluate(() => { const v = document.querySelector('[data-cf="note-view"]'); return !v.classList.contains('cf-md-clip') && /свернуть/.test(document.querySelector('[data-cf="note-open"]').textContent); });
  ok('длинная срезана, «развернуть» раскрывает целиком', longClip && longOpen, `${longClip} ${longOpen}`);
  await press(page, () => [...document.querySelectorAll('button')].find(b => b.textContent.trim() === 'Старый гайд'), 'снова старый гайд');
  ok('короткая заметка не срезана и без «развернуть»', await page.evaluate(() => !document.querySelector('[data-cf="note-view"]').classList.contains('cf-md-clip') && !document.querySelector('[data-cf="note-open"]')));

  // Печать новой разметки.
  await press(page, () => [...document.querySelectorAll('button')].find(b => b.textContent.trim() === 'Подсчёт кадров'), 'заметка в списке');
  await page.evaluate(async () => { const p = [...document.querySelectorAll('button')].find(x => /Печать и экспорт/.test(x.textContent || '')); if (p) p.click(); await new Promise(r => setTimeout(r, 300)); window.__printHTML = ''; document.querySelector('button[title^="Печать: "]').click(); });
  await page.waitForFunction(() => window.__printHTML !== '', { timeout: 20000 }).catch(() => {});
  const ph = await page.evaluate(() => window.__printHTML || '');
  ok('печать: заголовок, мелкий текст, галочки, ссылка подписью', /print-h1">1й бой/.test(ph) && /print-small">всего кадров/.test(ph) && /☑ /.test(ph) && /print-ref">Квартира на Горской/.test(ph) && !/cf:loc|\[x\]|-# /.test(ph) && /print-eyebrow">Заметка</.test(ph));

  // Ссылка в покое ведёт в сцену.
  await press(page, () => [...document.querySelectorAll('[data-cf="note-ref"]')].find(b => /КУХНЯ/.test(b.textContent)), 'ссылка на сцену');
  await page.waitForTimeout(500);
  const went = await page.evaluate(() => {
    const v = document.querySelector('[data-cf="note-view"]');
    const shown = (el) => !!el && el.getClientRects().length > 0;
    return !shown(v) && [...document.querySelectorAll('textarea')].some(t => shown(t) && t.value === 'Экспликация кухни');
  });
  ok('ссылка на сцену открывает эту сцену', went);
  if (errs.length) ok('без ошибок в консоли (планшет)', false, errs.join(' | '));

  // ================= ГОСТЬ ПО ССЫЛКЕ =================
  {
    const g = await mk({ q: '?view=all&room=notes-room-test-0001' });
    await goDocs(g.page);
    const r = await g.page.evaluate(() => {
      const v = document.querySelector('[data-cf="note-view"]');
      const p = v && v.querySelector('.cf-md-p'); if (p) p.click();
      const box = v && v.querySelector('[data-cf="note-check"]');
      return { view: !!v, ta: !!document.querySelector('[data-cf="note-input"]'), boxOff: !!box && box.disabled, ref: !!(v && v.querySelector('[data-cf="note-ref"]:not(:disabled)')) };
    });
    ok('гость: текст свёрстан, нажатие поле не открывает, галочки не нажимаются, ссылки живые', r.view && !r.ta && r.boxOff && r.ref, JSON.stringify(r));
    if (g.errs.length) ok('без ошибок в консоли (гость)', false, g.errs.join(' | '));
    await g.ctx.close();
  }

  // ================= ТЕЛЕФОН =================
  {
    const t = await mk({ vp: { width: 390, height: 844 }, touch: true });
    await t.page.evaluate(async () => {
      const more = document.querySelector('.cf-tabbar button:last-child'); if (more) more.click();
      await new Promise(r => setTimeout(r, 500));
      const b = [...document.querySelectorAll('.cf-sheet button')].find(x => /Эксплик/i.test(x.textContent || '')); if (b) b.click();
      await new Promise(r => setTimeout(r, 600));
      const d = [...document.querySelectorAll('button')].find(x => x.textContent.trim() === 'Подсчёт кадров'); if (d) d.click();
      await new Promise(r => setTimeout(r, 600));
    });
    const back = await t.page.evaluate(() => [...document.querySelectorAll('button')].some(b => /‹ Заметки/.test(b.textContent)));
    ok('телефон: «‹ Заметки» в шапке', back);
    const tp = await t.page.evaluate(() => { const p = [...document.querySelectorAll('[data-cf="note-view"] .cf-md-p')].pop(); const b = p.getBoundingClientRect(); p.scrollIntoView({ block: 'center' }); const c = p.getBoundingClientRect(); return { x: c.left + 10, y: c.top + c.height / 2 }; });
    await t.page.touchscreen.tap(tp.x, tp.y);
    await t.page.waitForTimeout(400);
    const ph2 = await t.page.evaluate(() => {
      const bar = document.querySelector('[data-cf="note-bar"]'), done = document.querySelector('[data-cf="note-done"]');
      const r = bar && bar.getBoundingClientRect(), d = done && done.getBoundingClientRect();
      const hit = d && document.elementFromPoint(d.left + d.width / 2, d.top + d.height / 2);
      return { bar: !!bar, inScreen: !!r && r.right <= 391 && r.left >= -1, done: !!hit && (hit === done || done.contains(hit)), ta: !!document.querySelector('[data-cf="note-input"]'),
               tool: (() => { const h = document.querySelector('[data-cf="note-bar"] [data-tool="h1"]'); if (!h) return 0; return Math.round(h.getBoundingClientRect().height); })() };
    });
    ok('телефон: касание открывает поле, кнопки в экране, «Готово» нажимается', ph2.ta && ph2.bar && ph2.inScreen && ph2.done && ph2.tool >= 36, JSON.stringify(ph2));
    if (t.errs.length) ok('без ошибок в консоли (телефон)', false, t.errs.join(' | '));
    await t.ctx.close();
  }

  console.log(bad ? `\nПЛОХО: ${bad}` : '\nВсё сошлось');
  await browser.close(); server.kill(); process.exit(bad ? 1 : 0);
})().catch(e => { console.error(e); server.kill(); process.exit(1); });
