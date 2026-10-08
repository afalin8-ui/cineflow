// Игра «Капелла» (папка game/): сквозная проверка в браузере.
//
// Запуск:  node tests/game-e2e.js                 — всё (около двух с половиной минут)
//          node tests/game-e2e.js --only space    — только бой на орбите
//                                   (и shell | ground | campaign)
// Порт сервера — переменная CF_PORT (по умолчанию 8300).
//
// Гоняется после КАЖДОЙ правки игры. Проверяет не код, а то, что видит
// игрок: кнопки нажимаются настоящей мышью, и перед нажатием проверяется
// elementFromPoint — попадает ли точка именно в кнопку, а не в панель
// поверх неё. «Элемент есть в разметке» не значит ничего: так справка
// годами не закрывалась (C2).
//
// Рендер программный (SwiftShader): кадр идёт сотни миллисекунд, и
// игровое время течёт медленно. Поэтому ждём УСЛОВИЙ, а не секунд,
// а на время долгого ожидания (бой до итога) отрисовку глушим.
//
//  shell    — меню без ошибок и сразу; «Ангар» только с ?dev=1;
//             справка закрывается кнопкой, Escape и щелчком по фону;
//             счётчик кадров (F3 и галочка); без WebGL — слова, а не
//             чёрный экран; ошибки расширений браузера не прячут игру
//             и не открывают окно сбоя.
//  space    — «Быстрый бой» → «Бой на орбите»: «Подготовка боя» видна
//             и ждёт модели; корабли есть; выделение кликом и рамкой;
//             приказ правой кнопкой; «мёртвые» кнопки HUD на 1920×1080
//             и 1366×768; сбой в кадре не замораживает игру (отрисовка
//             идёт, «Продолжить»); бой доходит до итога и в меню.
//  ground   — пока высадка ждёт модели, экран закрыт и подпись читается,
//             второй бой сквозь неё не начать; операция стартует без
//             ошибок; сбой → «В меню».
//  campaign — новая кампания открывает карту, не дожидаясь моделей
//             кораблей; «Конец хода» проходит.
//
// Модели (.glb) стенд держит «в пути», пока сам не отпустит (gate), —
// а не фиксированные секунды: иначе на медленной машине они доезжали
// бы раньше нажатия, и проверка падала бы без поломки в игре.
const { execSync, spawn } = require('child_process');
const path = require('path');
let playwright;
try { playwright = require('playwright'); } catch (e) { playwright = require(execSync('npm root -g').toString().trim() + '/playwright'); }

const ROOT = path.resolve(__dirname, '..');
const PORT = process.env.CF_PORT || '8300';
const BASE = `http://127.0.0.1:${PORT}/game/`;
const arg = process.argv.slice(2).join(' ');
const ONLY = (/--only[= ]+(\w+)/.exec(arg) || [])[1] || null;
const want = g => !ONLY || ONLY === g;
if (ONLY && !['shell', 'space', 'ground', 'campaign'].includes(ONLY)) {
  console.error('--only: shell | space | ground | campaign'); process.exit(2);
}

let bad = 0;
const one = d => String(d).replace(/\s+/g, ' ').trim();
const ok = (n, c, d) => { console.log((c ? '  ok  ' : '  FAIL') + ' ' + n + (d ? ' — ' + one(d) : '')); if (!c) bad++; };
const info = (n, d) => console.log('  info ' + n + (d ? ' — ' + d : ''));
const T0 = Date.now();
const secs = () => ((Date.now() - T0) / 1000).toFixed(0) + ' с';

const server = spawn('python3', ['-m', 'http.server', PORT, '--bind', '127.0.0.1'], { cwd: ROOT, stdio: 'ignore' });

// В странице до всех скриптов: счётчик кадров цикла и метка «видели
// экран подготовки» — он живёт доли секунды, и поймать его можно только
// наблюдателем, а не опросом.
const INIT = () => {
  window.__t = { prep: 0, prepText: [], bootFail: 0 };
  new MutationObserver(list => {
    for (const m of list) {
      const c = m.target.classList;
      if (m.type === 'attributes') { if (m.target.id === 'boot' && c.contains('fail')) window.__t.bootFail++; continue; }
      if (c && (c.contains('prep-sub') || m.target.dataset.role === 'sub')) window.__t.prepText.push(m.target.textContent);
      for (const n of m.addedNodes) if (n.classList && n.classList.contains('prep')) window.__t.prep++;
    }
  }).observe(document, { childList: true, subtree: true, attributes: true, attributeFilter: ['class'] });
};

// Модели «в пути», пока стенд их не отпустит. Запасной предел — чтобы
// забытый gate не держал страницу вечно; упавший раздел отпускает свои
// gate в общем цикле (openGates), иначе следующий ждал бы модели минуту.
const openGates = new Set();
function holdModels(page) {
  let release;
  const gate = new Promise(r => { release = r; });
  const handler = async route => {
    await Promise.race([gate, new Promise(r => setTimeout(r, 60000))]);
    route.continue().catch(() => {});
  };
  const g = {
    on: () => { openGates.add(g); return page.route('**/models/*.glb', handler); },
    off: async () => { openGates.delete(g); release(); await page.unroute('**/models/*.glb', handler).catch(() => {}); },
  };
  return g;
}

// Нажатие туда, куда нажал бы человек: центр видимого элемента, и
// проверка, что в этой точке лежит именно он.
async function tap(page, sel, idx = 0) {
  const r = await page.evaluate(([s, i]) => {
    const el = [...document.querySelectorAll(s)].filter(e => e.offsetParent || e.getClientRects().length)[i];
    if (!el) return null;
    const b = el.getBoundingClientRect(), x = b.left + b.width / 2, y = b.top + b.height / 2;
    const hit = document.elementFromPoint(x, y);
    return { x, y, hit: !!hit && (el === hit || el.contains(hit)), what: hit ? hit.tagName + '.' + hit.className : 'null' };
  }, [sel, idx]);
  if (!r) return { ok: false, why: 'нет элемента ' + sel };
  await page.mouse.click(r.x, r.y);
  return { ok: r.hit, why: r.hit ? '' : 'в точке нажатия ' + r.what };
}

// Отрисовка под присмотром: счётчик НАСТОЯЩИХ отрисовок (__renders) и
// выключатель (__noRender) — ожидание итога боя под программным рендером
// иначе тянется минутами. Подменяем метод того же модуля, которым
// пользуется игра (карта модулей одна на страницу). Считать надо именно
// отрисовки, а не вызовы requestAnimationFrame: опрос waitForFunction
// у Playwright сам зовёт rAF страницы, и счётчик rAF рос бы и при
// мёртвом цикле игры.
async function hookRender(page) {
  await page.evaluate(async () => {
    if (window.__renderHooked) return;
    const E = await import('/game/js/engine.js');
    const o = E.Viewport.prototype.render;
    window.__renders = 0;
    E.Viewport.prototype.render = function (s, c) {
      if (window.__noRender) return;
      window.__renders++;
      return o.call(this, s, c);
    };
    window.__renderHooked = true;
  });
}
async function mute(page, on) {
  await hookRender(page);
  await page.evaluate(on => { window.__noRender = on; }, on);
}

// Сканер «мёртвых» кнопок: центр каждой видимой кнопки HUD обязан
// попадать в неё же. Кнопка внутри прокручиваемой полосы, ушедшая за
// её край, до проверки подкручивается в поле зрения — так до неё
// доберётся и человек; сколько таких, пишется строкой info (C33).
const SCAN = () => {
  const out = { total: 0, dead: [], off: [], scrolled: 0 };
  const name = b => (b.getAttribute('aria-label') || b.textContent || b.dataset.role || '').trim().replace(/\s+/g, ' ').slice(0, 28);
  const scroller = el => {
    for (let p = el.parentElement; p && p !== document.body; p = p.parentElement) {
      const cs = getComputedStyle(p);
      if ((/(auto|scroll)/.test(cs.overflowX) && p.scrollWidth > p.clientWidth + 1) ||
          (/(auto|scroll)/.test(cs.overflowY) && p.scrollHeight > p.clientHeight + 1)) return p;
    }
    return null;
  };
  for (const b of document.querySelectorAll('#hud button')) {
    if (!b.offsetParent) continue;
    const cs = getComputedStyle(b);
    if (cs.visibility === 'hidden' || +cs.opacity === 0) continue;
    let r = b.getBoundingClientRect();
    if (r.width < 2 || r.height < 2) continue;
    out.total++;
    const sc = scroller(b);
    let keep = null;
    if (sc) {
      const sr = sc.getBoundingClientRect();
      const cx = r.left + r.width / 2, cy = r.top + r.height / 2;
      if (cx < sr.left || cx > sr.right || cy < sr.top || cy > sr.bottom) {
        keep = [sc.scrollLeft, sc.scrollTop];
        sc.scrollLeft += cx - (sr.left + sr.width / 2);
        sc.scrollTop += cy - (sr.top + sr.height / 2);
        r = b.getBoundingClientRect();
        out.scrolled++;
      }
    }
    const x = r.left + r.width / 2, y = r.top + r.height / 2;
    if (x < 0 || y < 0 || x >= innerWidth || y >= innerHeight) out.off.push(name(b) + ` @${Math.round(x)},${Math.round(y)}`);
    else {
      const h = document.elementFromPoint(x, y);
      if (!(h === b || b.contains(h))) out.dead.push(name(b) + ' → ' + (h ? h.tagName + '.' + h.className : 'null'));
    }
    if (keep) { sc.scrollLeft = keep[0]; sc.scrollTop = keep[1]; }
  }
  return out;
};

(async () => {
  await new Promise(r => setTimeout(r, 800));
  const browser = await playwright.chromium.launch({
    executablePath: '/opt/pw-browsers/chromium',
    args: ['--no-sandbox', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'],
  });
  // serviceWorkers: 'block' обязателен: иначе на втором заходе страница
  // берёт файлы из кэша service worker'а, и проверяется не то, что лежит
  // на диске.
  const ctx = await browser.newContext({ viewport: { width: 1920, height: 1080 }, serviceWorkers: 'block' });
  await ctx.addInitScript(INIT);
  const page = await ctx.newPage();
  const pageErrors = [], crashLogs = [];
  page.on('pageerror', e => pageErrors.push(String(e.stack || e.message).slice(0, 400)));
  page.on('console', m => { if (m.type() === 'error' && /Сбой в игре/.test(m.text())) crashLogs.push(m.text().slice(0, 300)); });
  const crashOpen = () => page.evaluate(() => !!document.querySelector('.crash'));
  const clean = async (what) => {
    const c = await crashOpen();
    ok(what + ': без ошибок страницы и без окна сбоя', !pageErrors.length && !crashLogs.length && !c,
      [...pageErrors, ...crashLogs].slice(0, 3).join(' | ') + (c ? ' | открыто окно сбоя' : ''));
    pageErrors.length = 0; crashLogs.length = 0;
  };

  const toMenu = async () => {
    const t = Date.now();
    await page.goto(BASE);
    await page.waitForSelector('[data-a="skirmish"]', { state: 'visible', timeout: 60000 });
    return Date.now() - t;
  };
  const menuVisible = () => page.waitForSelector('[data-a="skirmish"]', { state: 'visible', timeout: 90000 });
  // Заставка «Подготовка…» уходит после первого кадра нового экрана —
  // до этого она по праву забирает нажатия себе
  const settled = () => page.waitForFunction(() => !document.querySelector('.prep:not(.out)'), null, { timeout: 60000 });

  // ─────────────────────────── ОБОЛОЧКА
  const shell = async () => {
    console.log('\nОболочка: меню, справка, счётчик кадров, без WebGL  [' + secs() + ']');
    const ms = await toMenu();
    ok('меню открылось', true, `за ${(ms / 1000).toFixed(1)} с (программный рендер)`);
    ok('экран загрузки ушёл', await page.waitForFunction(() => {
      const b = document.getElementById('boot'); return !b || getComputedStyle(b).display === 'none';
    }, null, { timeout: 5000 }).then(() => true, () => false));
    ok('«Ангар» в меню игрока не показывается', await page.evaluate(() => !document.querySelector('[data-a="hangar"]')));
    await clean('меню');

    // Справка: три способа закрыть
    const open = async () => { const r = await tap(page, '[data-a="neuro"]'); await page.waitForSelector('.screen.neuro', { timeout: 5000 }); return r; };
    const closed = () => page.waitForFunction(() => !document.querySelector('.screen.neuro'), null, { timeout: 5000 }).then(() => true, () => false);
    let r = await open();
    ok('справка открывается нажатием', r.ok, r.why);
    r = await tap(page, '.neuro-head [data-a="close"]');
    ok('справка: кнопка «Закрыть» под мышью', r.ok, r.why);
    ok('справка: «Закрыть» закрывает', await closed());
    await open();
    await page.keyboard.press('Escape');
    ok('справка: Escape закрывает', await closed());
    await open();
    await page.mouse.click(20, 20);   // поля вокруг панели — это фон
    await page.waitForTimeout(300);
    const stillAfterInside = await page.evaluate(() => !!document.querySelector('.screen.neuro'));
    ok('справка: щелчок по фону закрывает', !stillAfterInside);
    await open();
    await tap(page, '.neuro-head h2');
    await page.waitForTimeout(300);
    ok('справка: щелчок по самой панели НЕ закрывает', await page.evaluate(() => !!document.querySelector('.screen.neuro')));
    await page.keyboard.press('Escape');
    await closed();

    // Счётчик кадров
    await page.keyboard.press('F3');
    const fpsShown = await page.waitForFunction(() => {
      const m = document.querySelector('.fpsmeter');
      return m && !m.hidden && /к\/с/.test(m.textContent) && /вызовы [1-9]/.test(m.textContent);
    }, null, { timeout: 30000 }).then(() => true, () => false);
    ok('F3 включает счётчик кадров с вызовами отрисовки', fpsShown,
      await page.evaluate(() => (document.querySelector('.fpsmeter') || {}).textContent || 'нет счётчика'));
    await page.keyboard.press('F3');
    ok('F3 выключает счётчик', await page.evaluate(() => { const m = document.querySelector('.fpsmeter'); return !m || m.hidden; }));
    r = await tap(page, '[data-a="fps"]');
    const stored = await page.evaluate(() => localStorage.getItem('capella_fps'));
    ok('галочка в меню включает счётчик и запоминает выбор', r.ok && stored === '1' &&
      await page.evaluate(() => !document.querySelector('.fpsmeter').hidden), r.why || 'localStorage=' + stored);
    await tap(page, '[data-a="fps"]');
    ok('галочка выключает и запоминает', await page.evaluate(() => localStorage.getItem('capella_fps') === '0' && document.querySelector('.fpsmeter').hidden));
    await clean('справка и счётчик');

    // С ?dev=1 «Ангар» есть
    await page.goto(BASE + '?dev=1');
    await page.waitForSelector('[data-a="skirmish"]', { state: 'visible', timeout: 60000 });
    ok('с ?dev=1 «Ангар» в меню есть', await page.evaluate(() => !!document.querySelector('[data-a="hangar"]')));
    r = await tap(page, '[data-a="hangar"]');
    ok('«Ангар» открывается', r.ok && await page.waitForSelector('.hud-hangar', { state: 'visible', timeout: 60000 }).then(() => true, () => false), r.why);
    await clean('ангар');

    /* Дальше — отдельные страницы. Меню на основной глушим: две игры,
       рисующие программным рендером разом, отнимают друг у друга
       процессор так, что соседняя страница не догружается и за 30 с. */
    await page.goto('about:blank');
    // Без WebGL: отдельная страница, где видеокарта «отказала»
    const c2 = await browser.newContext({ viewport: { width: 1366, height: 768 }, serviceWorkers: 'block' });
    await c2.addInitScript(() => {
      const o = HTMLCanvasElement.prototype.getContext;
      HTMLCanvasElement.prototype.getContext = function (k, ...a) { return /webgl/i.test(k) ? null : o.call(this, k, ...a); };
    });
    const p2 = await c2.newPage();
    const e2 = [];
    p2.on('pageerror', e => e2.push(String(e.message)));
    await p2.goto(BASE);
    await p2.waitForTimeout(2500);
    const t2 = await p2.evaluate(() => {
      const b = document.getElementById('boot');
      return b && getComputedStyle(b).display !== 'none' ? b.innerText : '';
    });
    ok('без WebGL — объяснение словами, а не чёрный экран', /WebGL/.test(t2) && /Аппаратное ускорение/.test(t2), t2.slice(0, 80));
    ok('без WebGL — без ошибок страницы', !e2.length, e2.join(' | '));
    await c2.close();

    /* Расширение браузера бросает ошибки в мире страницы: до запуска
       игры, сразу после и уже в меню, плюс отказ обещания. Имя файла у
       таких ошибок — адрес самой игры (…/game/). Раньше они навсегда
       прятали игру за «не загрузилась» и открывали окно сбоя над меню. */
    const c3 = await browser.newContext({ viewport: { width: 1366, height: 768 }, serviceWorkers: 'block' });
    await c3.addInitScript(INIT);
    await c3.addInitScript(() => {
      window.__ext = 0;
      const inject = code => {
        const root = document.head || document.documentElement;
        if (!root) { setTimeout(() => inject(code), 5); return; }
        const s = document.createElement('script'); s.textContent = code; root.appendChild(s);
      };
      const boom = 'window.__ext++; throw new Error("расширение: cannot read x")';
      inject(`setTimeout(function(){ ${boom} }, 0)`);
      document.addEventListener('DOMContentLoaded', () => inject(`setTimeout(function(){ ${boom} }, 30)`));
      setTimeout(() => inject(`setTimeout(function(){ ${boom} }, 30); window.__ext++; Promise.reject('нечто'); window.__ext++; Promise.reject(new Error('расширение: обещание'))`), 200);
    });
    const p3 = await c3.newPage();
    const e3 = [];
    p3.on('pageerror', e => e3.push(String(e.message)));
    await p3.goto(BASE);
    const menu3 = await p3.waitForSelector('[data-a="skirmish"]', { state: 'visible', timeout: 60000 }).then(() => true, () => false);
    // и ещё одна — уже в меню
    await p3.evaluate(() => { const s = document.createElement('script'); s.textContent = 'setTimeout(function(){ window.__ext++; throw new Error("расширение: в меню") }, 10)'; document.body.appendChild(s); });
    await p3.waitForFunction(() => window.__ext >= 6, null, { timeout: 10000 }).catch(() => {});
    await p3.waitForTimeout(700);
    const st3 = await p3.evaluate(() => {
      const b = document.querySelector('[data-a="skirmish"]').getBoundingClientRect();
      const h = document.elementFromPoint(b.left + b.width / 2, b.top + b.height / 2);
      return { ext: window.__ext, bootFail: window.__t.bootFail, crash: !!document.querySelector('.crash'),
        hit: !!h && !!h.closest('[data-a="skirmish"]'), what: h ? h.tagName + '#' + h.id + '.' + h.className : 'null' };
    });
    ok('ошибки расширения браузера не прячут игру: меню нажимается', menu3 && st3.hit && st3.ext >= 6 && !st3.bootFail,
      `ошибок расширения ${st3.ext}, заставка «не загрузилась»: ${st3.bootFail}, под кнопкой ${st3.what}`);
    ok('ошибки расширения не открывают окно сбоя', !st3.crash);
    await c3.close();

    /* «Не загрузилась» не окончательно: если игра всё-таки поднялась,
       заставка уходит (окончательно только «нет WebGL»). */
    const c4 = await browser.newContext({ viewport: { width: 1366, height: 768 }, serviceWorkers: 'block' });
    // Тревога ДО запуска игры: как только index.html завёл __bootFail
    await c4.addInitScript(() => {
      const iv = setInterval(() => {
        if (!window.__bootFail) return;
        clearInterval(iv);
        window.__bootFail('load', 'ПРОВЕРКА: ложная тревога');
        window.__failedEarly = !window.__capellaUp && document.getElementById('boot').classList.contains('fail');
      }, 1);
    });
    const p4 = await c4.newPage();
    await p4.goto(BASE);
    const up4 = await p4.waitForFunction(() => {
      const b = document.querySelector('[data-a="skirmish"]'); if (!b) return false;
      const r = b.getBoundingClientRect(), h = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
      return !!h && !!h.closest('[data-a="skirmish"]');
    }, null, { timeout: 60000, polling: 250 }).then(() => true, () => false);
    ok('«не загрузилась» снимается, когда игра всё-таки поднялась', up4 && await p4.evaluate(() => window.__failedEarly === true),
      up4 ? '' : await p4.evaluate(() => document.getElementById('boot').innerText.slice(0, 80)));
    await c4.close();
  };

  // ─────────────────────────── БОЙ НА ОРБИТЕ
  const space = async () => {
    console.log('\nБой на орбите  [' + secs() + ']');
    /* Модели «в пути», пока стенд не увидит, что заставка об этом
       сказала: бой обязан их дождаться, а не собраться на процедурных
       (C40). */
    const glb = holdModels(page);
    await glb.on();
    await toMenu();
    await page.evaluate(() => { window.__t.prep = 0; window.__t.prepText = []; });
    let r = await tap(page, '[data-a="skirmish"]');
    ok('«Быстрый бой» нажимается', r.ok, r.why);
    await page.waitForSelector('[data-a="space"]', { state: 'visible' });
    r = await tap(page, '[data-a="space"]');
    ok('«Бой на орбите» нажимается', r.ok, r.why);
    const t = Date.now();
    const waited = await page.waitForFunction(() => window.__t.prepText.find(x => /Загружаю модели/.test(x)),
      null, { timeout: 30000, polling: 100 }).then(h => h.jsonValue(), () => '');
    ok('пока модели едут, заставка говорит об этом', !!waited, waited);
    ok('перед боем показан экран «Подготовка боя»', await page.evaluate(() => window.__t.prep > 0));
    await glb.off();
    await page.waitForFunction(() => window.__sp && window.__sp.time > 0, null, { timeout: 150000 });
    await settled();
    const custom = await page.evaluate(() => {
      const c = __sp.ships.find(s => s.faction.id === 'troyden' && s.def.id === 'cruiser');
      return c ? !!c.obj.userData.custom : null;
    });
    ok('крейсер Тройдена — внешняя модель (дождались, файл открылся)', custom === true, String(custom));
    const fleet = await page.evaluate(() => ({
      mine: __sp.ships.filter(s => !s.dead && s.side === __sp.playerSide).length,
      foe: __sp.ships.filter(s => !s.dead && s.side !== __sp.playerSide).length,
    }));
    ok('бой стартовал, корабли обеих сторон на месте', fleet.mine > 0 && fleet.foe > 0,
      `${fleet.mine} против ${fleet.foe}, сборка ${((Date.now() - t) / 1000).toFixed(1)} с`);
    await clean('старт боя');

    await hookRender(page);

    // Пауза — кнопкой, как человек; дальше корабли стоят, и клики честные
    r = await tap(page, '[data-speed="0"]');
    ok('пауза нажимается', r.ok && await page.evaluate(() => __sp.paused), r.why);
    await page.waitForTimeout(400);

    // Выделение кликом: свой корабль, который на экране, не под панелью
    // и стоит ОСОБНЯКОМ — строй расставлен со случайным разбросом, и в
    // точке, где один корабль заслонён другим, честно выбирается ближний
    const pick = await page.evaluate(() => {
      const c = document.getElementById('view');
      const all = __sp.ships.filter(s => !s.dead && !s.station).map(s => ({ s, p: __sp.screenTest(s) }))
        .filter(o => o.p.z < 1);
      const cands = [];
      for (const { s, p } of all) {
        if (s.side !== __sp.playerSide) continue;
        if (p.x < 40 || p.y < 40 || p.x > innerWidth - 40 || p.y > innerHeight - 40) continue;
        if (document.elementFromPoint(p.x, p.y) !== c) continue;
        const gap = Math.min(...all.filter(o => o.s !== s).map(o => Math.hypot(o.p.x - p.x, o.p.y - p.y)));
        cands.push({ uid: s.uid, x: p.x, y: p.y, name: s.def.name, gap: Math.round(gap) });
      }
      cands.sort((a, b) => b.gap - a.gap);
      return cands[0] || null;
    });
    ok('свой корабль виден на экране не под панелью', !!pick, pick ? `${pick.name}, до соседа ${pick.gap} точек` : 'ни одного');
    if (pick) {
      await page.mouse.click(pick.x, pick.y);
      await page.waitForTimeout(300);
      const sel = await page.evaluate(() => __sp.selection.map(e => e.uid));
      // соседей в 30 точках нет — обязан выделиться именно он;
      // иначе — хотя бы один свой корабль под курсором
      const exact = pick.gap >= 30;
      ok('клик по кораблю выделяет его', sel.length === 1 && (!exact || sel[0] === pick.uid),
        JSON.stringify(sel) + (exact ? '' : ' (рядом соседи — проверено мягко)'));
    }

    // Рамкой: всё своё, что на экране
    await page.keyboard.press('Escape');
    const box = await page.evaluate(() => {
      const c = document.getElementById('view');
      const pts = __sp.ships.filter(s => !s.dead && s.side === __sp.playerSide && !s.station)
        .map(s => ({ uid: s.uid, ...__sp.screenTest(s) })).filter(p => p.z < 1 && p.x > 0 && p.y > 0 && p.x < innerWidth && p.y < innerHeight);
      if (pts.length < 2) return null;
      const pad = 36;
      const x0 = Math.max(4, Math.min(...pts.map(p => p.x)) - pad), y0 = Math.max(4, Math.min(...pts.map(p => p.y)) - pad);
      const x1 = Math.min(innerWidth - 4, Math.max(...pts.map(p => p.x)) + pad), y1 = Math.min(innerHeight - 4, Math.max(...pts.map(p => p.y)) + pad);
      return { x0, y0, x1, y1, n: pts.length, startOnCanvas: document.elementFromPoint(x0, y0) === c };
    });
    ok('для рамки есть хотя бы два своих корабля на экране', !!box && box.startOnCanvas, box ? `кораблей ${box.n}, начало рамки на поле: ${box.startOnCanvas}` : 'нет');
    if (box) {
      await page.mouse.move(box.x0, box.y0);
      await page.mouse.down();
      for (let i = 1; i <= 6; i++) await page.mouse.move(box.x0 + (box.x1 - box.x0) * i / 6, box.y0 + (box.y1 - box.y0) * i / 6);
      await page.mouse.up();
      await page.waitForTimeout(300);
      const n = await page.evaluate(() => __sp.selection.length);
      ok('рамка выделяет все свои корабли в ней', n === box.n, `выделено ${n} из ${box.n}`);
    }

    // Приказ правой кнопкой: точка на пустом поле
    const tgt = await page.evaluate(() => {
      const c = document.getElementById('view');
      for (const [fx, fy] of [[0.5, 0.42], [0.4, 0.38], [0.6, 0.38], [0.5, 0.3], [0.35, 0.5]]) {
        const x = innerWidth * fx, y = innerHeight * fy;
        if (document.elementFromPoint(x, y) !== c) continue;
        const w = __sp.worldTest(x, y);
        if (w) return { x, y, wx: w.x, wz: w.z };
      }
      return null;
    });
    if (!tgt) ok('для приказа нашлась пустая точка поля', false);
    else {
      const before = await page.evaluate(() => __sp.selection.map(s => s.moveTo && s.moveTo.clone()));
      await page.mouse.click(tgt.x, tgt.y, { button: 'right' });
      await page.waitForTimeout(300);
      const res = await page.evaluate(([wx, wz]) => {
        const sel = __sp.selection.filter(s => !s.dead);
        const withDest = sel.filter(s => s.moveTo);
        if (!withDest.length) return { n: sel.length, got: 0 };
        let cx = 0, cz = 0;
        for (const s of withDest) { cx += s.moveTo.x; cz += s.moveTo.z; }
        cx /= withDest.length; cz /= withDest.length;
        return { n: sel.length, got: withDest.length, miss: Math.round(Math.hypot(cx - wx, cz - wz)) };
      }, [tgt.wx, tgt.wz]);
      ok('ПКМ по полю — все выделенные получают точку движения', res.n > 0 && res.got === res.n && before.every(b => !b),
        `${res.got} из ${res.n}`);
      ok('точка движения — там, куда щёлкнули', res.miss !== undefined && res.miss < 200, `промах центра строя ${res.miss}`);
    }

    // «Мёртвые» кнопки HUD: всё выделено — панель действий полна
    r = await tap(page, '[data-q="all"]');
    ok('«Весь флот» нажимается', r.ok, r.why);
    await page.waitForTimeout(600);
    for (const [w, h] of [[1920, 1080], [1366, 768]]) {
      if (w !== 1920) { await page.setViewportSize({ width: w, height: h }); await page.waitForTimeout(800); }
      const s = await page.evaluate(SCAN);
      ok(`HUD ${w}×${h}: все видимые кнопки под мышью (${s.total} шт.)`, s.total > 10 && !s.dead.length, s.dead.join('; '));
      if (s.scrolled || s.off.length) info(`HUD ${w}×${h}`, `в прокрутке ${s.scrolled}, за краем экрана ${s.off.length}${s.off.length ? ': ' + s.off.join('; ') : ''}`);
    }
    await page.setViewportSize({ width: 1920, height: 1080 });
    await page.waitForTimeout(500);

    // Сбой в кадре: одноразовое исключение внутри update боя
    await tap(page, '[data-speed="1"]');
    await page.evaluate(() => {
      const saved = __sp.reserve;
      let thrown = false;
      Object.defineProperty(__sp, 'reserve', {
        configurable: true,
        get() { if (!thrown) { thrown = true; throw new Error('ПРОВЕРКА: искусственный сбой в кадре'); } return saved; },
        set(v) { /* не меняется */ },
      });
    });
    const shown = await page.waitForSelector('.crash', { timeout: 30000 }).then(() => true, () => false);
    const crashText = await page.evaluate(() => (document.querySelector('.crash pre') || {}).textContent || '');
    ok('сбой в кадре: окно с текстом ошибки', shown && /ПРОВЕРКА/.test(crashText), crashText.split('\n')[0]);
    const a = await page.evaluate(() => ({ n: window.__renders, time: __sp.time }));
    const going = await page.waitForFunction(n => window.__renders >= n, a.n + 3, { timeout: 30000, polling: 250 }).then(() => true, () => false);
    const b = await page.evaluate(() => ({ n: window.__renders, time: __sp.time }));
    ok('сбой в кадре: отрисовка идёт дальше', going, `отрисовок с открытым окном: ${b.n - a.n}`);
    ok('пока окно открыто, бой стоит', b.time === a.time, `игровое время ${a.time.toFixed(2)} → ${b.time.toFixed(2)}`);
    r = await tap(page, '.crash [data-a="go"]');
    ok('«Продолжить» нажимается', r.ok, r.why);
    const goes = await page.waitForFunction(t0 => !document.querySelector('.crash') && __sp.time > t0 + 0.05, b.time, { timeout: 30000 }).then(() => true, () => false);
    ok('после «Продолжить» окно закрыто, бой идёт', goes);
    crashLogs.length = 0;

    // До итога: флоты в упор, противник на последнем издыхании, 4×, без отрисовки
    r = await tap(page, '[data-speed="4"]');
    ok('4× нажимается', r.ok, r.why);
    await page.evaluate(() => {
      __sp.closeInTest(300);
      for (const s of __sp.ships) if (s.side !== __sp.playerSide) s.hp = Math.min(s.hp, 1);
    });
    await mute(page, true);
    const ended = await page.waitForFunction(() => {
      const e = document.querySelector('.endcard'); return e && e.style.display === 'flex';
    }, null, { timeout: 180000, polling: 500 }).then(() => true, () => false);
    await mute(page, false);
    const endText = await page.evaluate(() => (document.querySelector('.endcard') || {}).innerText || '');
    ok('бой доходит до итоговой карточки', ended && /Орбита за нами/.test(endText), endText.slice(0, 60) || 'нет карточки, игровое время ' +
      await page.evaluate(() => __sp.time.toFixed(1)));
    if (ended) {
      r = await tap(page, '.endcard [data-role="cont"]');
      ok('«Продолжить» на итоговой карточке нажимается', r.ok, r.why);
      ok('после боя — снова меню', await menuVisible().then(() => true, () => false));
    }
    await clean('бой на орбите');
  };

  // ─────────────────────────── ЗЕМЛЯ
  const ground = async () => {
    console.log('\nНаземная операция  [' + secs() + ']');
    /* Высадка, пока модели в пути: нырок обязан закрыть экран целиком и
       ловить указатель, а подпись — читаться. Раньше облака уезжали за
       1,6 с, тёмная подпись лежала на тёмном меню, а меню под ней
       нажималось: можно было начать бой на орбите поверх ожидания. */
    const glb = holdModels(page);
    await glb.on();
    await toMenu();
    const btn = await page.evaluate(() => {
      const b = document.querySelector('[data-a="skirmish"]').getBoundingClientRect();
      return { x: b.left + b.width / 2, y: b.top + b.height / 2 };
    });
    await tap(page, '[data-a="skirmish"]');
    await page.waitForSelector('[data-a="ground"]', { state: 'visible' });
    const r = await tap(page, '[data-a="ground"]');
    ok('«Наземная операция» нажимается', r.ok, r.why);
    const waiting = await page.waitForFunction(() => {
      const d = document.querySelector('.dive');
      return d && /Загружаю модели/.test(d.textContent);
    }, null, { timeout: 30000, polling: 100 }).then(() => true, () => false);
    ok('высадка ждёт модели и говорит об этом', waiting,
      await page.evaluate(() => (document.querySelector('.dive') || {}).textContent || 'нет нырка'));
    await page.waitForTimeout(2500);   // облака успели бы уехать — не должны
    const cover = await page.evaluate(({ x, y }) => {
      const inDive = (px, py) => { const h = document.elementFromPoint(px, py); return { ok: !!h && !!h.closest('.dive'), what: h ? h.tagName + '.' + h.className : 'null' }; };
      // Читаемость: контраст подписи и её плашки (WCAG), плашка почти непрозрачна
      const rgb = c => (c.match(/[\d.]+/g) || []).map(Number);
      const lum = ([r, g, b]) => { const f = v => (v /= 255) <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b); };
      const lab = document.querySelector('.dive .dive-label');
      const fg = lab && lab.querySelector('span') ? rgb(getComputedStyle(lab.querySelector('span')).color) : [0, 0, 0];
      const bg = lab ? rgb(getComputedStyle(lab).backgroundColor) : [0, 0, 0, 0];
      const L1 = lum(fg), L2 = lum(bg.slice(0, 3));
      return { btn: inDive(x, y), mid: inDive(innerWidth / 2, innerHeight / 2), corner: inDive(30, 30),
        contrast: (Math.max(L1, L2) + 0.05) / (Math.min(L1, L2) + 0.05), alpha: bg.length > 3 ? bg[3] : 1,
        frozen: [...document.querySelectorAll('.dive > i')].filter(i => getComputedStyle(i).animationPlayState === 'paused').length === 3 };
    }, btn);
    ok('пока высадка ждёт, прежний экран закрыт и не нажимается', cover.btn.ok && cover.mid.ok && cover.corner.ok,
      `под «Быстрым боем»: ${cover.btn.what}, в центре: ${cover.mid.what}, в углу: ${cover.corner.what}`);
    ok('облака замерли в плотной точке', cover.frozen);
    ok('подпись ожидания читается', cover.contrast >= 7 && cover.alpha >= 0.85,
      `контраст ${cover.contrast.toFixed(1)}, плашка непрозрачна на ${cover.alpha}`);
    await page.mouse.click(btn.x, btn.y);   // как человек, который заждался
    await page.waitForTimeout(600);
    ok('нажатие сквозь ожидание не открывает меню боя', await page.evaluate(() => !document.querySelector('[data-a="space"]')));
    await glb.off();
    const started = await page.waitForFunction(() => window.__gr && window.__gr.time > 0 && window.__gr.units && window.__gr.units.length > 0,
      null, { timeout: 150000 }).then(() => true, () => false);
    ok('после ожидания собран ровно один бой — наземный', started && await page.evaluate(() => !window.__sp));
    ok('наземная операция стартовала, юниты есть', started,
      started ? await page.evaluate(() => `юнитов ${__gr.units.length}, построек ${(__gr.buildings || []).length}`) : '');
    await clean('наземная операция');

    // Сбой при отрисовке → «В меню»
    await page.evaluate(() => {
      const c = document.getElementById('view');
      const o = c.getBoundingClientRect;
      let thrown = false;
      c.getBoundingClientRect = function () {
        if (!thrown) { thrown = true; throw new Error('ПРОВЕРКА: искусственный сбой отрисовки'); }
        return o.call(this);
      };
    });
    const shown = await page.waitForSelector('.crash', { timeout: 30000 }).then(() => true, () => false);
    ok('сбой при отрисовке: окно сбоя', shown);
    const m = await tap(page, '.crash [data-a="menu"]');
    ok('«В меню» нажимается', m.ok, m.why);
    ok('«В меню» выводит в главное меню', await menuVisible().then(() => true, () => false) &&
      await page.evaluate(() => !document.querySelector('.crash')));
    crashLogs.length = 0;
    await clean('после выхода в меню');
  };

  // ─────────────────────────── КАМПАНИЯ
  const campaign = async () => {
    console.log('\nКампания  [' + secs() + ']');
    // Карте модели кораблей не нужны: она не ждёт их, даже если они в пути
    const glb = holdModels(page);
    await glb.on();
    await toMenu();
    await page.evaluate(() => { localStorage.removeItem('capella_save_v1'); window.__t.prepText = []; });
    let r = await tap(page, '[data-a="new"]');
    ok('«Новая кампания» нажимается', r.ok, r.why);
    await page.waitForSelector('.fcard', { state: 'visible' });
    r = await tap(page, '.fcard');
    ok('карточка клана нажимается', r.ok, r.why);
    const open = await page.waitForFunction(() => window.__gal && document.querySelector('[data-role="endturn"]'),
      null, { timeout: 120000 }).then(() => true, () => false);
    ok('карта системы открылась', open);
    const sub = await page.evaluate(() => [...new Set(window.__t.prepText.filter(Boolean))].slice(0, 2).join(' | ').slice(0, 160));
    ok('карта открылась, не дожидаясь моделей кораблей (они ещё в пути)', open && !/модел/i.test(sub), sub);
    await glb.off();
    if (!open) return;
    await settled();
    const turn0 = await page.evaluate(() => +document.querySelector('[data-role="turn"]').textContent);
    r = await tap(page, '[data-role="endturn"]');
    ok('«Конец хода» под мышью', r.ok, r.why);
    const next = await page.waitForFunction(t => +document.querySelector('[data-role="turn"]').textContent === t + 1, turn0,
      { timeout: 30000 }).then(() => true, () => false);
    ok('ход сменился', next, `ход ${turn0} → ${await page.evaluate(() => document.querySelector('[data-role="turn"]').textContent)}`);
    await page.waitForTimeout(500);
    await clean('кампания');
  };

  for (const [g, fn] of [['shell', shell], ['space', space], ['ground', ground], ['campaign', campaign]]) {
    if (!want(g)) continue;
    try { await fn(); } catch (e) {
      ok(`раздел «${g}» дошёл до конца`, false, String(e.message || e).split('\n')[0].slice(0, 200));
      await page.setViewportSize({ width: 1920, height: 1080 }).catch(() => {});
      for (const gate of [...openGates]) await gate.off();
    }
  }

  await browser.close();
  server.kill();
  console.log(bad ? `\n${bad} FAIL  [${secs()}]` : `\nвсё ок  [${secs()}]`);
  process.exit(Math.min(bad, 100));
})().catch(e => { console.error(e); server.kill(); process.exit(1); });
