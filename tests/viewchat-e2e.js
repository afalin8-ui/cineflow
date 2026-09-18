// ССЫЛКА-ПРОСМОТР С ЧАТОМ: смотреть всё, писать — только в чат.
//
// Почему проверяется в браузере, а не чтением кода: дверь наружу тут
// одна-единственная (`syncDoc`), и «открыта ли она ровно на одну
// коллекцию» на глаз не видно. Поэтому облако ПОДДЕЛЬНОЕ и ведёт
// журнал: после всех нажатий в нём обязаны лежать только сообщения
// чата (и имя гостя), а сцен, досок и каталогов — ни одного.
// Настоящий Firebase ЗАБЛОКИРОВАН: иначе проверка писала бы в живой
// проект пользователя.
//
// Второе, чего не видно в коде: поле чата в просмотре НЕ НАЖИМАЛОСЬ.
// Правило `body.cf-readonly input { pointer-events: none }` гасит
// указатель у всех полей разом, и поле оставалось мёртвым, хотя
// печатать в него уже было разрешено. Поэтому попадание проверяется
// `elementFromPoint`, а не «есть ли элемент».
//
// Запуск:  node tests/viewchat-e2e.js
const path = require('path'), fs = require('fs'), os = require('os');
const { execSync, spawn } = require('child_process');
const ROOT = '/home/user/cineflow';
const LIBS = process.env.CF_LIBS || path.join(os.tmpdir(), 'cineflow-libs');
const PORT = process.env.CF_PORT || '8111';
const ROOM = 'viewchat-test';
let playwright;
try { playwright = require('playwright'); }
catch (e) { playwright = require(execSync('npm root -g').toString().trim() + '/playwright'); }
const server = spawn('python3', ['-m', 'http.server', PORT, '--bind', '127.0.0.1'], { cwd: ROOT, stdio: 'ignore' });
let bad = 0;
const ok = (n, c, d) => { console.log((c ? '  ok  ' : '  FAIL') + ' ' + n + (d ? ' — ' + d : '')); if (!c) bad++; };

// Поддельное облако — общее для всех проверок (tests/fake-cloud.js):
// вторая копия разъехалась бы с первой при первой же правке.
const { FAKE_CLOUD } = require('./fake-cloud.js');

// Настоящее нажатие: браузер бьёт в ту точку экрана, куда попал бы палец.
const hits = (sel) => {
  const el = document.querySelector(sel);
  if (!el) return { found: false };
  const r = el.getBoundingClientRect();
  const t = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
  return { found: true, box: [Math.round(r.width), Math.round(r.height)], hit: !!t && (el === t || el.contains(t) || t.contains(el)) };
};

// React слушает нативный сеттер, а не присваивание `el.value`.
// Аргумент у evaluate ОДИН, поэтому пара приезжает массивом: с двумя
// параметрами селектор склеивался с текстом в один список селекторов,
// поле находилось, а в значение ложилось «undefined» — и проверка
// падала не там, где сломано.
const typeInto = ([sel, text]) => {
  const el = document.querySelector(sel);
  if (!el) return false;
  const set = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
  el.focus(); set.call(el, text);
  el.dispatchEvent(new Event('input', { bubbles: true }));
  return true;
};

(async () => {
  await new Promise(r => setTimeout(r, 1200));
  const browser = await playwright.chromium.launch({ executablePath: process.env.CF_CHROME || '/opt/pw-browsers/chromium', args: ['--no-sandbox'] });

  const mkCtx = async (w, h, name) => {
    // Service worker БЛОКИРУЕМ: он перехватывает запросы мимо подмены
    // библиотек, лезет за ними в настоящий интернет и на втором заходе
    // страница остаётся без React — пустой экран без единой ошибки.
    const ctx = await browser.newContext({ viewport: { width: w, height: h }, isMobile: w < 768, hasTouch: true, serviceWorkers: 'block' });
    await ctx.route('**/*', (route) => {
      const u = route.request().url();
      // Настоящий Firebase и карты не пускаем ВООБЩЕ: подделка стоит
      // на его месте, а живой проект трогать нельзя.
      if (/firestore|firebase|googleapis|gstatic|nominatim/.test(u)) return route.abort();
      for (const [f, re] of [['react.js', /react@18\/umd\/react\.production/], ['react-dom.js', /react-dom@18/],
                             ['babel.js', /babel\.min\.js/], ['tailwind.js', /cdn\.tailwindcss/]])
        if (re.test(u)) return route.fulfill({ body: fs.readFileSync(path.join(LIBS, f)), contentType: 'application/javascript' });
      route.continue();
    });
    await ctx.addInitScript(FAKE_CLOUD, {});
    if (name) await ctx.addInitScript(`localStorage.setItem('cf_user_name', ${JSON.stringify(name)}); localStorage.setItem('cf_user_role', 'Режиссер');`);
    return ctx;
  };
  const open = async (page, q) => {
    await page.goto(`http://127.0.0.1:${PORT}/index.html${q}`);
    await page.waitForFunction(() => window.__CF_APP_OK, null, { timeout: 120000 });
    await page.waitForTimeout(1500);
  };

  // ---------- 1. ОБЫЧНАЯ ССЫЛКА-ПРОСМОТР: чата нет
  const ctxA = await mkCtx(1440, 900, 'Марина');
  const pa = await ctxA.newPage();
  await open(pa, `?view=all&room=${ROOM}`);
  const noChat = await pa.evaluate(() => ({
    btn: !!document.querySelector('[title="Чат группы"]'),
    vis: (() => { const b = document.querySelector('[title="Чат группы"]'); return b ? getComputedStyle(b).display : 'нет'; })(),
    badge: !!([...document.querySelectorAll('button')].find(b => /Просмотр/.test(b.textContent)))
  }));
  ok('без ?chat=1 кнопки чата у гостя нет', noChat.vis === 'none' || !noChat.btn, JSON.stringify(noChat));
  ok('бейдж «Просмотр» на месте', noChat.badge);

  // ---------- 2. ССЫЛКА С ЧАТОМ: пишем
  await open(pa, `?view=all&room=${ROOM}&chat=1`);
  const seeded = await pa.evaluate(() => (window.__cfWrites || []).map(w => w.coll));
  ok('пустая комната у гостя НЕ засевается', seeded.length === 0, JSON.stringify(seeded));

  const chatBtn = await pa.evaluate(hits, '[title="Чат группы"]');
  ok('кнопка чата видна и нажимается', chatBtn.found && chatBtn.hit, JSON.stringify(chatBtn));

  await pa.click('[title="Чат группы"]');
  await pa.waitForTimeout(600);
  const field = await pa.evaluate(hits, '.cf-chat-drawer input[type="text"]');
  ok('поле чата нажимается пальцем (не гаснет под cf-readonly)', field.found && field.hit, JSON.stringify(field));

  const typed = await pa.evaluate(typeInto, ['.cf-chat-drawer input[type="text"]', 'Свет во второй сцене нравится']);
  ok('в поле чата печатается', typed);
  await pa.press('.cf-chat-drawer input[type="text"]', 'Enter');
  await pa.waitForTimeout(700);

  const sent = await pa.evaluate(() => ({
    writes: (window.__cfWrites || []).map(w => w.coll),
    inCloud: Object.values((window.__cfStore || {}).messages || {}).map(m => m.text),
    onScreen: [...document.querySelectorAll('.cf-chat-drawer div')].some(d => d.textContent === 'Свет во второй сцене нравится'),
    who: Object.values((window.__cfStore || {}).messages || {}).map(m => m.senderName + ' · ' + m.senderRole)
  }));
  ok('сообщение уехало в облако', sent.inCloud.indexOf('Свет во второй сцене нравится') >= 0, JSON.stringify(sent.inCloud));
  ok('оно подписано именем и ролью', /Марина · Режиссер/.test(sent.who.join()), JSON.stringify(sent.who));
  ok('появилось в переписке на экране', sent.onScreen);
  ok('наружу ушёл ТОЛЬКО чат', sent.writes.every(c => c === 'messages'), JSON.stringify(sent.writes));

  // ---------- 3. ВСЁ ОСТАЛЬНОЕ ПО-ПРЕЖНЕМУ ЗАПЕРТО
  const locked = await pa.evaluate(() => {
    const out = {};
    // Кнопок правки нет
    out.edit = [...document.querySelectorAll('.cf-edit-only')].filter(e => getComputedStyle(e).display !== 'none').length;
    // Поле проекта не принимает ввод: beforeinput отменяется
    const f = [...document.querySelectorAll('textarea, input[type="text"]')]
      .find(e => !e.closest('.cf-chat-drawer') && !e.hasAttribute('data-ro-ok'));
    if (f) {
      const ev = new InputEvent('beforeinput', { bubbles: true, cancelable: true, data: 'x', inputType: 'insertText' });
      f.dispatchEvent(ev);
      out.blocked = ev.defaultPrevented;
      out.tap = getComputedStyle(f).pointerEvents;
    } else out.blocked = 'полей проекта на экране нет';
    return out;
  });
  ok('кнопки правки у гостя спрятаны', locked.edit === 0, 'видимых cf-edit-only: ' + locked.edit);
  ok('поля проекта по-прежнему не принимают ввод', locked.blocked === true || typeof locked.blocked === 'string', JSON.stringify(locked));

  // Выделяем всё, жмём по экрану — и смотрим, что в облако так ничего
  // и не уехало, кроме чата.
  await pa.evaluate(() => { document.querySelectorAll('button').forEach(b => { if (!/Чат|Просмотр/.test(b.title + b.textContent)) try { b.click(); } catch (e) {} }); });
  await pa.waitForTimeout(1200);
  const after = await pa.evaluate(() => (window.__cfWrites || []).map(w => w.coll + (w.del ? ':удаление' : '')));
  ok('после нажатия всего подряд наружу ушёл только чат', after.every(c => c === 'messages'), JSON.stringify([...new Set(after)]));

  // ---------- 4. ТЕЛЕФОН, ГОСТЬ БЕЗ ИМЕНИ
  const ctxB = await mkCtx(390, 844, null);
  const pb = await ctxB.newPage();
  await open(pb, `?view=all&room=${ROOM}&chat=1`);
  const noModal = await pb.evaluate(() => !!document.querySelector('input[placeholder="Иван Иванов"]'));
  ok('имя само не спрашивается — человек пришёл смотреть', !noModal);

  const more = await pb.evaluate(() => {
    const b = [...document.querySelectorAll('.cf-tabbar button')].find(x => /Ещё/.test(x.textContent));
    if (!b) return { err: 'нет кнопки «Ещё»' };
    b.click(); return { ok: true };
  });
  await pb.waitForTimeout(500);
  const chatRow = await pb.evaluate(() => {
    const b = [...document.querySelectorAll('.cf-sheet button')].find(x => /Чат/.test(x.textContent));
    if (!b) return { found: false };
    const r = b.getBoundingClientRect();
    const t = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
    return { found: true, hit: !!t && (b === t || b.contains(t)), h: Math.round(r.height) };
  });
  ok('с телефона до чата есть путь («Ещё» → «Чат»)', chatRow.found && chatRow.hit, JSON.stringify({ more, chatRow }));

  await pb.evaluate(() => [...document.querySelectorAll('.cf-sheet button')].find(x => /Чат/.test(x.textContent)).click());
  await pb.waitForTimeout(700);
  const ask = await pb.evaluate(() => {
    const b = [...document.querySelectorAll('.cf-chat-drawer button')].find(x => /Представиться/.test(x.textContent));
    if (!b) return { found: false };
    const r = b.getBoundingClientRect();
    const t = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
    return { found: true, hit: !!t && (b === t || b.contains(t)) };
  });
  ok('без имени вместо поля стоит «Представиться, чтобы писать»', ask.found && ask.hit, JSON.stringify(ask));

  await pb.evaluate(() => [...document.querySelectorAll('.cf-chat-drawer button')].find(x => /Представиться/.test(x.textContent)).click());
  await pb.waitForTimeout(600);
  const nameField = await pb.evaluate(hits, 'input[placeholder="Иван Иванов"]');
  ok('поле имени нажимается и в режиме просмотра', nameField.found && nameField.hit, JSON.stringify(nameField));
  const escape = await pb.evaluate(() => [...document.querySelectorAll('button')].some(b => /Не сейчас/.test(b.textContent)));
  ok('из окна имени есть выход', escape);

  await pb.evaluate(typeInto, ['input[placeholder="Иван Иванов"]', 'Пётр Гость']);
  await pb.evaluate(() => [...document.querySelectorAll('button')].find(b => /Продолжить/.test(b.textContent)).click());
  await pb.waitForTimeout(900);
  const pinStep = await pb.evaluate(() => !!document.querySelector('input[name="cf-profile-pin"]'));
  ok('имя защищается PIN-ом — ветка входа та же, что у группы', pinStep);
  if (pinStep) {
    await pb.evaluate(() => {
      const el = document.querySelector('input[name="cf-profile-pin"]');
      const set = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
      el.focus(); set.call(el, '4815'); el.dispatchEvent(new Event('input', { bubbles: true }));
    });
    await pb.evaluate(() => [...document.querySelectorAll('button')].find(b => /Создать и продолжить/.test(b.textContent)).click());
    await pb.waitForTimeout(900);
  }
  const canWrite = await pb.evaluate(hits, '.cf-chat-drawer input[type="text"]');
  ok('после знакомства поле чата на месте', canWrite.found && canWrite.hit, JSON.stringify(canWrite));
  await pb.evaluate(typeInto, ['.cf-chat-drawer input[type="text"]', 'Спасибо, посмотрел']);
  await pb.press('.cf-chat-drawer input[type="text"]', 'Enter');
  await pb.waitForTimeout(700);
  const phoneSent = await pb.evaluate(() => ({
    colls: [...new Set((window.__cfWrites || []).map(w => w.coll))],
    texts: Object.values((window.__cfStore || {}).messages || {}).map(m => m.text)
  }));
  ok('с телефона сообщение уехало', phoneSent.texts.indexOf('Спасибо, посмотрел') >= 0, JSON.stringify(phoneSent.texts));
  ok('наружу — только чат и имя гостя', phoneSent.colls.every(c => c === 'messages' || c === 'userPins'), JSON.stringify(phoneSent.colls));

  // ---------- 5. У ХОЗЯИНА ПРОЕКТА: ссылку выдаёт окно «Доступ»
  const ctxC = await browser.newContext({ viewport: { width: 1440, height: 900 }, serviceWorkers: 'block',
                                          permissions: ['clipboard-read', 'clipboard-write'] });
  await ctxC.route('**/*', (route) => {
    const u = route.request().url();
    if (/firestore|firebase|googleapis|gstatic|nominatim/.test(u)) return route.abort();
    for (const [f, re] of [['react.js', /react@18\/umd\/react\.production/], ['react-dom.js', /react-dom@18/],
                           ['babel.js', /babel\.min\.js/], ['tailwind.js', /cdn\.tailwindcss/]])
      if (re.test(u)) return route.fulfill({ body: fs.readFileSync(path.join(LIBS, f)), contentType: 'application/javascript' });
    route.continue();
  });
  await ctxC.addInitScript(FAKE_CLOUD, {});
  await ctxC.addInitScript(`localStorage.setItem('cf_user_name', 'Хозяин'); localStorage.setItem('cf_user_role', 'Оператор-постановщик');`);
  const pc = await ctxC.newPage();
  await open(pc, `?room=${ROOM}`);
  const openShare = async () => pc.evaluate(async () => {
    const m = [...document.querySelectorAll('button')].find(b => b.textContent.trim() === '···');
    if (m) { m.click(); await new Promise(r => setTimeout(r, 300)); }
    const s = [...document.querySelectorAll('button')].find(b => /Доступ/.test(b.textContent));
    if (!s) return false;
    s.click(); await new Promise(r => setTimeout(r, 500));
    return true;
  });
  ok('окно «Доступ» открывается', await openShare());
  const copyRow = async (label) => {
    await pc.evaluate((lbl) => {
      const row = [...document.querySelectorAll('div')].find(d => {
        const s = d.querySelector(':scope > span');
        return s && s.textContent.trim() === lbl && d.querySelector(':scope > button');
      });
      row.querySelector(':scope > button').click();
    }, label);
    await pc.waitForTimeout(400);
    return pc.evaluate(() => navigator.clipboard.readText());
  };
  const plainLink = await copyRow('Весь проект');
  ok('по умолчанию ссылка просмотра БЕЗ чата', /view=all/.test(plainLink) && !/chat=1/.test(plainLink), plainLink);
  await pc.evaluate(() => {
    const cb = [...document.querySelectorAll('input[type="checkbox"]')]
      .find(c => /Разрешить писать в чат/.test((c.closest('label') || {}).textContent || ''));
    cb.click();
  });
  await pc.waitForTimeout(300);
  const chatLink = await copyRow('Весь проект');
  ok('с галочкой ссылка несёт chat=1', /view=all/.test(chatLink) && /chat=1/.test(chatLink) && /room=/.test(chatLink), chatLink);

  // Хозяин по-прежнему пишет в чат обычным путём
  await pc.keyboard.press('Escape');
  await pc.waitForTimeout(300);
  await pc.click('[title="Чат группы"]');
  await pc.waitForTimeout(500);
  await pc.evaluate(typeInto, ['.cf-chat-drawer input[type="text"]', 'Проверка связи']);
  await pc.press('.cf-chat-drawer input[type="text"]', 'Enter');
  await pc.waitForTimeout(700);
  const ownerSent = await pc.evaluate(() => Object.values((window.__cfStore || {}).messages || {}).map(m => m.text));
  ok('у хозяина проекта чат работает как работал', ownerSent.indexOf('Проверка связи') >= 0, JSON.stringify(ownerSent));

  await browser.close();
  server.kill();
  console.log(bad ? `\n${bad} провал(ов)` : '\nвсё сошлось');
  process.exit(bad ? 1 : 0);
})().catch(e => { console.error(e); server.kill(); process.exit(1); });
