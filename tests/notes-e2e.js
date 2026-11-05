// Заметки: живой редактор (Tiptap), запасной редактор со знаками и
// свёрстанный вид у гостя.
//
// Проверяется в браузере и НАЖАТИЕМ (elementFromPoint + настоящая мышь),
// а не чтением кода: кнопки обязаны не отнимать курсор у текста, иначе
// правка ляжет не туда, а заметно это только при нажатии.
//
// Что гоняем. Живой редактор: заметка свёрстана сразу (заголовок,
// мелкий текст, галочки, ссылки живыми именами, javascript: — не
// ссылка); кнопок в покое нет; галочка ставится одним нажатием;
// нажатие по абзацу ставит курсор В НЕГО и показывает кнопки; каждая
// кнопка меняет вид строки и пишет те же знаки в текст; знаки при наборе
// («# », «- », «[ ] ») сами становятся оформлением; «Ж»; ссылка кнопкой
// и через [[; «→ имя» у ссылки под курсором; прописная строка в новой
// заметке заголовком не становится; в покое ссылка ведёт в сцену; старый
// гайд открывается как был; длинная — «развернуть»; печать. Затем:
// гость только читает, телефон 390, и без файла редактора — прежний
// редактор со знаками.
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
      if (opts.noLive && /vendor\/tiptap/.test(u)) return route.abort();
      // Настоящий Firebase ЗАБЛОКИРОВАН: иначе стенд писал бы в проект пользователя.
      if (/firestore|firebase|googleapis|gstatic|nominatim/.test(u)) return route.abort();
      for (const [f, re] of [['react.js', /react@18[.0-9]*\/umd\/react\.production/], ['react-dom.js', /react-dom@18/],
                             ['babel.js', /babel\.min\.js/], ['tailwind.js', /cdn\.tailwindcss/]])
        if (re.test(u)) return route.fulfill({ body: fs.readFileSync(path.join(LIBS, f)), contentType: 'application/javascript' });
      route.continue();
    });
    await ctx.addInitScript(([note, old]) => {
      // Печать перехватываем на КАЖДОМ заходе (и после перезагрузки).
      window.print = () => { const a = document.getElementById('print-area'); window.__printHTML = a ? a.innerHTML : ''; };
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

  // ================= ЖИВОЙ РЕДАКТОР =================
  const { page, errs } = await mk();
  await goDocs(page);
  await page.waitForSelector('[data-cf="note-live"]', { timeout: 20000 }).catch(() => {});
  const names = await page.evaluate(() => document.body.innerText);
  ok('список называется «Заметки», кнопка «Новая заметка»', /Заметки/.test(names) && /Новая заметка/.test(names) && !/Операторские гайды|Создать гайд/.test(names));
  const pm = () => '[data-cf="note-live"]';
  const view = await page.evaluate((sel) => {
    const v = document.querySelector(sel);
    if (!v) return null;
    const h = v.querySelector('h1'), s = v.querySelector('p.cf-md-s'), p = v.querySelector('p:not(.cf-md-s)');
    const fs2 = (el) => el ? parseFloat(getComputedStyle(el).fontSize) : 0;
    return {
      h: h && h.textContent, hfs: fs2(h), sfs: fs2(s), pfs: fs2(p),
      boxes: v.querySelectorAll('ul[data-type="taskList"] > li').length, done: v.querySelectorAll('li[data-checked="true"]').length,
      refs: [...v.querySelectorAll('a[href^="cf:"]')].map(a => a.textContent),
      ext: [...v.querySelectorAll('a[href^="http"]')].map(a => a.getAttribute('href')),
      js: [...v.querySelectorAll('a')].some(a => /javascript|плохо/i.test((a.getAttribute('href') || '') + a.textContent)),
      bold: (v.querySelector('strong') || {}).textContent, raw: /\[x\]|-#|\*\*/.test(v.innerText),
      bar: !!document.querySelector('[data-cf="note-bar"]'), ta: !!document.querySelector('[data-cf="note-input"]')
    };
  }, pm());
  ok('заметка открыта живым редактором и свёрстана, знаков не видно', view && !view.ta && !view.raw, JSON.stringify(view && { ta: view.ta, raw: view.raw }));
  ok('полоса кнопок видна сразу, «Готово» — только во время правки', view && view.bar && !(await page.evaluate(() => !!document.querySelector('[data-cf="note-done"]'))));
  const tb = await page.evaluate(() => { const b = document.querySelector('[data-cf="note-bar"]'); const r = b.getBoundingClientRect(); const kids = [...b.querySelectorAll('button')]; return { inside: kids.every(k => { const q = k.getBoundingClientRect(); return q.right <= r.right + 1 && q.left >= r.left - 1; }), style: (document.querySelector('[data-cf="note-style"]') || {}).textContent }; });
  ok('все кнопки полосы в её рамке (ничего не уехало вбок), вид строки подписан словами', tb.inside && /Обычный текст/.test(tb.style || ''), JSON.stringify(tb));
  ok('заголовок крупнее текста, «мелкий» мельче', view && view.h === '1й бой' && view.hfs > view.pfs && view.sfs < view.pfs, view && `${view.hfs}/${view.pfs}/${view.sfs}`);
  ok('галочки: две, одна отмечена', view && view.boxes === 2 && view.done === 1);
  ok('ссылка на сцену — ЖИВЫМ именем', view && view.refs[0] === '#2 · ИНТ. КУХНЯ — ВЕЧЕР', view && view.refs.join('|'));
  ok('сайт — ссылкой, javascript: — нет', view && view.ext.length === 1 && view.ext[0] === 'https://example.com' && !view.js, view && view.ext.join(','));
  ok('**жирно** — жирным', view && view.bold === 'жирно');

  await press(page, () => document.querySelector('[data-cf="note-live"] ul[data-type="taskList"] > li input'), 'галочка');
  await flush(page);
  ok('галочка ставится одним нажатием и пишется в текст', /\[x\] взять флаги/.test(await content(page)));

  // Нажатие по абзацу — курсор в нём и кнопки.
  await press(page, () => [...document.querySelectorAll('[data-cf="note-live"] p')].find(p => /Последний/.test(p.textContent)), 'последний абзац');
  const caret = await page.evaluate(() => { const s = getSelection(); const n = s.anchorNode; return { inP: !!n && /Последний/.test((n.nodeType === 3 ? n.parentElement : n).closest('p')?.textContent || ''), done: !!document.querySelector('[data-cf="note-done"]') }; });
  ok('нажатие по абзацу ставит курсор в него, появляется «Готово»', caret.inP && caret.done, JSON.stringify(caret));
  const btn = (k) => new Function(`return document.querySelector('[data-cf="note-bar"] [data-tool="${k}"]')`);
  // Вид строки — в выпадающем списке «Обычный текст ▾», списки и галочки — значками.
  const STYLE = ['p', 'h1', 'h2', 'h3', 's', 'q'];
  const step = async (k, re, name) => {
    if (STYLE.includes(k)) {
      await press(page, () => document.querySelector('[data-cf="note-style"]'), name + ' (открыть список)');
      await press(page, new Function(`return document.querySelector('[data-cf="note-style-menu"] [data-tool="${k}"]')`), name);
    } else await press(page, btn(k), name);
    await flush(page); const c = await content(page); ok(name, re.test(c), JSON.stringify(c.slice(-45)));
  };
  const mk2 = await page.evaluate(async () => { document.querySelector('[data-cf="note-style"]').dispatchEvent(new MouseEvent('click', { bubbles: true })); await new Promise(r => setTimeout(r, 100)); const m = document.querySelector('[data-cf="note-style-menu"]'); const t = m ? m.innerText : ''; document.querySelector('[data-cf="note-style"]').dispatchEvent(new MouseEvent('click', { bubbles: true })); return t; });
  ok('в списке видов подписаны знаки # ## ###', /Заголовок\s*#\s/.test(mk2) && /##/.test(mk2) && /###/.test(mk2), JSON.stringify(mk2));
  await step('h1', /\n# Последний абзац \*\*жирно\*\*\.$/, '«Заголовок» — строка стала заголовком, в тексте «# »');
  const isH = await page.evaluate(() => [...document.querySelectorAll('[data-cf="note-live"] h1')].some(h => /Последний/.test(h.textContent)));
  ok('и на экране это заголовок, без знаков', isH);
  await step('h1', /\nПоследний абзац \*\*жирно\*\*\.$/, 'повторный выбор снимает заголовок');
  await step('h3', /\n### Последний абзац/, '«Заголовок 3» — «### »');
  await step('p', /\nПоследний абзац \*\*жирно\*\*\.$/, '«Обычный текст» возвращает строку');
  await step('s', /\n-# Последний абзац/, '«мелкий» — в тексте «-# »');
  await step('cl', /\n\[ \] Последний абзац/, '«Галочки» — в тексте «[ ] »');
  await step('p', /\nПоследний абзац \*\*жирно\*\*\.$/, '«Текст» снимает список');
  await step('ul', /\n- Последний абзац/, '«• Список»');
  await step('ul', /\nПоследний абзац/, 'и снимается повторно');

  // Знаки при наборе становятся оформлением.
  await page.keyboard.press('End');
  await page.keyboard.press('Enter');
  await page.keyboard.type('### Мелкий раздел'); await page.keyboard.press('Enter');
  await page.keyboard.type('# Новый раздел'); await page.keyboard.press('Enter');
  await page.keyboard.type('- раз'); await page.keyboard.press('Enter'); await page.keyboard.type('два');
  await page.keyboard.press('Enter'); await page.keyboard.press('Enter');
  await page.keyboard.type('[ ] проверить'); await page.keyboard.press('Enter'); await page.keyboard.press('Enter');
  await page.keyboard.type('ИНТ КУХНЯ'); await page.keyboard.press('Enter');
  await page.keyboard.type('Объект: ');
  await flush(page);
  let c = await content(page);
  ok('«# », «- », «[ ] » при наборе становятся заголовком, списком, галочкой', /\n### Мелкий раздел\n\n# Новый раздел\n\n- раз\n- два\n\n\[ \] проверить\n\nИНТ КУХНЯ/.test(c), JSON.stringify(c.slice(-80)));
  const shown = await page.evaluate(() => { const v = document.querySelector('[data-cf="note-live"]'); return { h: [...v.querySelectorAll('h1')].some(h => h.textContent === 'Новый раздел') && [...v.querySelectorAll('h3')].some(h => h.textContent === 'Мелкий раздел'), li: [...v.querySelectorAll('ul:not([data-type]) li')].map(l => l.textContent).join(','), raw: /^# |^- раз/m.test(v.innerText) }; });
  ok('и на экране — без знаков', shown.h && shown.li === 'раз,два' && !shown.raw, JSON.stringify(shown));

  // Ссылка кнопкой.
  await press(page, btn('link'), '«Ссылка»');
  ok('«Ссылка» открывает выбор с полем поиска', await page.evaluate(() => !!document.querySelector('[data-cf="note-pick"]') && document.activeElement.classList.contains('cf-md-pick-q')));
  await page.keyboard.type('Горск');
  await press(page, () => [...document.querySelectorAll('.cf-md-pick-row')].find(b => /Горской/.test(b.textContent)), 'объект в выборе');
  await page.keyboard.type('и ');
  await flush(page);
  c = await content(page);
  ok('ссылка на объект легла по id, набор продолжился после неё', /Объект: \[Квартира на Горской\]\(cf:loc\/loc-1\) и $/.test(c), JSON.stringify(c.slice(-55)));
  // [[ — тот же выбор.
  await page.keyboard.type('[[');
  ok('[[ открывает выбор ссылки', await page.evaluate(() => !!document.querySelector('[data-cf="note-pick"]')));
  await page.keyboard.type('каб'); await page.keyboard.press('Enter');
  await flush(page);
  c = await content(page);
  ok('[[ + Enter — ссылка на первую найденную сцену, [[ убраны', /и \[#1 · ИНТ\. КАБИНА — ДЕНЬ\]\(cf:scene\/sc1\)/.test(c) && !/\[\[/.test(c), JSON.stringify(c.slice(-60)));
  // Курсор в ссылке — «→ имя» рядом с «Готово».
  // По СЕРЕДИНЕ ссылки: у самого её начала курсор стоит ещё перед ней.
  const lc = await page.evaluate(() => { const a = document.querySelector('[data-cf="note-live"] a[href="cf:loc/loc-1"]'); a.scrollIntoView({ block: 'center' }); const r = a.getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; });
  await page.mouse.click(lc.x, lc.y); await page.waitForTimeout(300);
  const lo = await page.evaluate(() => { const b = document.querySelector('[data-cf="note-link-open"]'); return { b: !!b, t: b && b.textContent, still: !!document.querySelector('[data-cf="note-done"]') }; });
  ok('нажатие по ссылке во время правки не уводит, а показывает «→ имя»', lo.b && /Квартира на Горской/.test(lo.t) && lo.still, JSON.stringify(lo));

  // «Ж» по выделенному слову (двойной щелчок выделяет слово).
  const kw = await page.evaluate(() => { const p = [...document.querySelectorAll('[data-cf="note-live"] p')].find(x => /^Кадры/.test(x.textContent)); p.scrollIntoView({ block: 'center' }); const r = document.createRange(); r.setStart(p.firstChild, 0); r.setEnd(p.firstChild, 5); const b = r.getBoundingClientRect(); return { x: b.left + b.width / 2, y: b.top + b.height / 2 }; });
  await page.mouse.dblclick(kw.x, kw.y);
  await page.waitForTimeout(200);
  await press(page, btn('**'), '«Ж»');
  await flush(page);
  ok('«Ж» делает выделенное жирным', (await content(page)).startsWith('**Кадры** посчитаны'), (await content(page)).slice(0, 22));

  await press(page, () => document.querySelector('[data-cf="note-done"]'), '«Готово»');
  ok('«Готово» выходит из правки', await page.evaluate(() => !document.querySelector('[data-cf="note-done"]') && !document.activeElement.closest('[data-cf="note-live"]')));
  const rec = await page.evaluate(() => JSON.parse(localStorage.getItem('cf_docs')).find(d => d.id === 'doc-1'));
  ok('у заметки из живого редактора стоит метка md', rec && rec.md === 1);

  // Перезагрузка: прописная строка осталась строкой, заметка та же.
  await page.reload();
  await page.waitForFunction(() => window.__CF_APP_OK, { timeout: 180000 });
  await page.waitForTimeout(700);
  await goDocs(page);
  await page.waitForSelector('[data-cf="note-live"]', { timeout: 20000 }).catch(() => {});
  const re2 = await page.evaluate(() => { const v = document.querySelector('[data-cf="note-live"]'); return { kh: [...v.querySelectorAll('h1,h2,h3')].some(h => h.textContent === 'ИНТ КУХНЯ'), kp: [...v.querySelectorAll('p')].some(p => p.textContent === 'ИНТ КУХНЯ'), refs: [...v.querySelectorAll('a[href^="cf:"]')].length }; });
  ok('после перезагрузки прописная строка — строка, а не заголовок; ссылки на месте', !re2.kh && re2.kp && re2.refs === 3, JSON.stringify(re2));
  const before = await content(page);
  await page.waitForTimeout(600);
  ok('открытие заметки её текст не переписывает', (await content(page)) === before);

  // Старый гайд: открылся как был, текст не тронут.
  await press(page, () => [...document.querySelectorAll('button')].find(b => b.textContent.trim() === 'Старый гайд'), 'старый гайд в списке');
  await page.waitForTimeout(400);
  const old = await page.evaluate(() => { const v = document.querySelector('[data-cf="note-live"]'); return v && { h: (v.querySelector('h2') || {}).textContent, li: v.querySelectorAll('ul li').length }; });
  ok('старый гайд открывается свёрстанным как был', old && old.h === 'СВЕТ НА ИНТЕРЬЕРАХ' && old.li === 2, JSON.stringify(old));
  await flush(page);
  ok('и его текст не тронут', (await content(page, 'doc-2')) === OLD);
  const crewNote = await page.evaluate(() => /Состав съёмочной группы/.test(document.querySelector('[data-cf="note"]').closest('.flex-1').innerText));
  await press(page, () => document.querySelector('[data-cf="crew-open"]'), '«Состав группы» в списке');
  const crewPanel = await page.evaluate(() => { const p = document.querySelector('[data-cf="crew-panel"]'); return { p: !!p, note: !!document.querySelector('[data-cf="note"]'), add: !!(p && /Добавить участника/.test(p.innerText)) }; });
  ok('состав группы — свой пункт в списке, а не таблица под каждой заметкой', !crewNote && crewPanel.p && !crewPanel.note && crewPanel.add, JSON.stringify({ crewNote, ...crewPanel }));
  await press(page, () => [...document.querySelectorAll('button')].find(b => b.textContent.trim() === 'Старый гайд'), 'снова старый гайд');
  await page.waitForTimeout(300);
  ok('короткая заметка не срезана и без «развернуть»', await page.evaluate(() => !document.querySelector('[data-cf="note-view"]').classList.contains('cf-md-clip') && !document.querySelector('[data-cf="note-open"]')));
  await press(page, () => [...document.querySelectorAll('button')].find(b => b.textContent.trim() === 'Длинная'), 'длинная заметка в списке');
  await page.waitForTimeout(400);
  const longClip = await page.evaluate(() => document.querySelector('[data-cf="note-view"]').classList.contains('cf-md-clip'));
  await press(page, () => document.querySelector('[data-cf="note-open"]'), '«развернуть»');
  const longOpen = await page.evaluate(() => !document.querySelector('[data-cf="note-view"]').classList.contains('cf-md-clip'));
  ok('длинная срезана, «развернуть» раскрывает целиком', longClip && longOpen, `${longClip} ${longOpen}`);

  // Печать.
  await press(page, () => [...document.querySelectorAll('button')].find(b => b.textContent.trim() === 'Подсчёт кадров'), 'заметка в списке');
  await page.evaluate(async () => { const p = [...document.querySelectorAll('button')].find(x => /Печать и экспорт/.test(x.textContent || '')); if (p) p.click(); await new Promise(r => setTimeout(r, 300)); window.__printHTML = ''; document.querySelector('button[title^="Печать: "]').click(); });
  await page.waitForFunction(() => window.__printHTML !== '', { timeout: 20000 }).catch(() => {});
  const ph = await page.evaluate(() => window.__printHTML || '');
  ok('печать: заголовок, мелкий текст, галочки, ссылка подписью; прописная строка — абзац',
     /print-h1">1й бой/.test(ph) && /print-small">всего кадров/.test(ph) && /☑ /.test(ph) && /print-ref">Квартира на Горской/.test(ph) && !/cf:loc|\[x\]|-# /.test(ph) && /print-eyebrow">Заметка</.test(ph) && /print-p">ИНТ КУХНЯ/.test(ph));

  // В покое ссылка ведёт в сцену одним нажатием.
  await press(page, () => [...document.querySelectorAll('[data-cf="note-live"] a[href^="cf:scene"]')].find(a => /КУХНЯ/.test(a.textContent)), 'ссылка на сцену');
  await page.waitForTimeout(500);
  const went = await page.evaluate(() => {
    const v = document.querySelector('[data-cf="note-live"]');
    const shown = (el) => !!el && el.getClientRects().length > 0;
    return !shown(v) && [...document.querySelectorAll('textarea')].some(t => shown(t) && t.value === 'Экспликация кухни');
  });
  ok('в покое ссылка на сцену открывает эту сцену', went);
  if (errs.length) ok('без ошибок в консоли (живой редактор)', false, errs.join(' | '));
  await page.context().close();

  // ================= БЕЗ ФАЙЛА РЕДАКТОРА — прежний со знаками =================
  {
    const f = await mk({ noLive: true });
    await goDocs(f.page);
    await f.page.waitForTimeout(800);
    await press(f.page, () => [...document.querySelectorAll('[data-cf="note-view"] .cf-md-p')].find(p => /Последний/.test(p.textContent)), 'абзац (запасной)');
    const st = await f.page.evaluate(() => { const t = document.querySelector('[data-cf="note-input"]'); return t && { focus: document.activeElement === t, line: t.value.slice(0, t.selectionStart).split('\n').length - 1 }; });
    ok('без файла редактора: нажатие открывает поле со знаками, курсор в абзаце', st && st.focus && st.line === NOTE.split('\n').length - 1, JSON.stringify(st));
    await press(f.page, () => document.querySelector('[data-cf="note-bar"] [data-tool="h1"]'), '«Заголовок» (запасной)');
    const v = await f.page.evaluate(() => document.querySelector('[data-cf="note-input"]').value);
    ok('и кнопки там работают', /\n# Последний абзац/.test(v));
    await f.page.keyboard.type(' ещё');
    ok('буквы после кнопки ложатся на место', /\n# Последний абзац \*\*жирно\*\*\. ещё$/.test(await f.page.evaluate(() => document.querySelector('[data-cf="note-input"]').value)));
    if (f.errs.length) ok('без ошибок в консоли (запасной)', false, f.errs.join(' | '));
    await f.ctx.close();
  }

  // ================= ГОСТЬ ПО ССЫЛКЕ =================
  {
    const g = await mk({ q: '?view=all&room=notes-room-test-0001' });
    await goDocs(g.page);
    const r = await g.page.evaluate(() => {
      const v = document.querySelector('[data-cf="note-view"]');
      const p = v && v.querySelector('.cf-md-p'); if (p) p.click();
      const box = v && v.querySelector('[data-cf="note-check"]');
      return { view: !!v, ta: document.activeElement && !!document.activeElement.closest('[data-cf="note-live"]'), boxOff: !!box && box.disabled, ref: !!(v && v.querySelector('[data-cf="note-ref"]:not(:disabled)')) };
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
    await t.page.waitForSelector('[data-cf="note-live"]', { timeout: 20000 }).catch(() => {});
    const tp = await t.page.evaluate(() => { const p = [...document.querySelectorAll('[data-cf="note-live"] p')].pop(); p.scrollIntoView({ block: 'center' }); const c = p.getBoundingClientRect(); return { x: c.left + 10, y: c.top + c.height / 2 }; });
    await t.page.touchscreen.tap(tp.x, tp.y);
    await t.page.waitForTimeout(400);
    const ph2 = await t.page.evaluate(() => {
      const bar = document.querySelector('[data-cf="note-bar"]'), done = document.querySelector('[data-cf="note-done"]');
      const r = bar && bar.getBoundingClientRect(), d = done && done.getBoundingClientRect();
      const hit = d && document.elementFromPoint(d.left + d.width / 2, d.top + d.height / 2);
      return { bar: !!bar, inScreen: !!r && r.right <= 391 && r.left >= -1, done: !!hit && (hit === done || done.contains(hit)), ta: document.activeElement && !!document.activeElement.closest('[data-cf="note-live"]'),
               tool: (() => { const h = document.querySelector('[data-cf="note-style"]'); if (!h) return 0; return Math.round(h.getBoundingClientRect().height); })() };
    });
    ok('телефон: касание ставит курсор в текст, кнопки в экране, «Готово» нажимается', ph2.ta && ph2.bar && ph2.inScreen && ph2.done && ph2.tool >= 36, JSON.stringify(ph2));
    if (t.errs.length) ok('без ошибок в консоли (телефон)', false, t.errs.join(' | '));
    await t.ctx.close();
  }

  console.log(bad ? `\nПЛОХО: ${bad}` : '\nВсё сошлось');
  await browser.close(); server.kill(); process.exit(bad ? 1 : 0);
})().catch(e => { console.error(e); server.kill(); process.exit(1); });
