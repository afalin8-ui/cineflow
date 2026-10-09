// Игра «Капелла» (папка game/): сквозная проверка в браузере.
//
// Запуск:  node tests/game-e2e.js                 — всё (около четырёх минут)
//          node tests/game-e2e.js --only space    — только бой на орбите
//                                   (и shell | ground | campaign | update)
// Порт сервера — переменная CF_PORT (по умолчанию 8300); раздел update
// поднимает второй сервер на CF_PORT + 1.
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
//             идёт, «Продолжить»); медленный клик по кнопке действия
//             (C30); погибший выделенный корабль очищает панель;
//             посадка звеньев погибшего носителя не даёт другому больше
//             звеньев, чем ангаров (C99); скрытая машина не рисуется
//             (C18); ПКМ по вражескому звену — урон конечен, флот
//             стреляет (C14); бой доходит до итога и в меню.
//             Мышь и клавиатура (P2): камера, отряды, A/S/H, меню паузы,
//             справка из него не пропускает клавиши в бой, G с авианосцем
//             и «Отход» спрашивают и на это время ставят бой на паузу,
//             номер отряда в ростере не лежит на имени.
//             Экран боя (P3): стартовая камера (C76), масштаб .glb (C88),
//             панель команд в экране без прокрутки (C33/C75), подписи
//             не наложены (C78), ростер группами (C77), пустые полосы
//             прозрачны (C135), свой/чужой (C43), подсказка, «Дрифт» по
//             выделению (C136), купол РЭБ в покое (C111).
//  ground   — пока высадка ждёт модели, экран закрыт и подпись читается,
//             второй бой сквозь неё не начать; операция стартует без
//             ошибок; сбой → «В меню».
//  campaign — новая кампания открывает карту, не дожидаясь моделей
//             кораблей; «Конец хода» проходит; два настоящих боя
//             с «Отходом» мышью (C17): в атаке потери противника
//             остаются за ним, в обороне ушедшие в гипер возвращаются,
//             а флот противника уходит к себе (отход — из меню паузы:
//             «В главное меню» у боя кампании нет).
//  update   — выкладка доходит по F5 (C121): копия game/ на сервере
//             «как GitHub Pages» (max-age=600 + ETag), service worker
//             ВКЛЮЧЁН; правка main.js, модуля глубже и стилей приходит
//             с первого F5, без связи открывается уже новое.
//
// Модели (.glb) стенд держит «в пути», пока сам не отпустит (gate), —
// а не фиксированные секунды: иначе на медленной машине они доезжали
// бы раньше нажатия, и проверка падала бы без поломки в игре.
const { execSync, spawn } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
let playwright;
try { playwright = require('playwright'); } catch (e) { playwright = require(execSync('npm root -g').toString().trim() + '/playwright'); }

const ROOT = path.resolve(__dirname, '..');
const PORT = process.env.CF_PORT || '8300';
const BASE = `http://127.0.0.1:${PORT}/game/`;
const arg = process.argv.slice(2).join(' ');
const ONLY = (/--only[= ]+(\w+)/.exec(arg) || [])[1] || null;
// CF_SHOTS=<папка> — сложить туда снимки для глаза (ростер и т. п.)
const SHOTS = process.env.CF_SHOTS || null;
const want = g => !ONLY || ONLY === g;
if (ONLY && !['shell', 'space', 'ground', 'campaign', 'update'].includes(ONLY)) {
  console.error('--only: shell | space | ground | campaign | update'); process.exit(2);
}

let bad = 0;
const one = d => String(d).replace(/\s+/g, ' ').trim();
const ok = (n, c, d) => { console.log((c ? '  ok  ' : '  FAIL') + ' ' + n + (d ? ' — ' + one(d) : '')); if (!c) bad++; };
const info = (n, d) => console.log('  info ' + n + (d ? ' — ' + d : ''));
const T0 = Date.now();
const secs = () => ((Date.now() - T0) / 1000).toFixed(0) + ' с';

const server = spawn('python3', ['-m', 'http.server', PORT, '--bind', '127.0.0.1'], { cwd: ROOT, stdio: 'ignore' });

/* Сервер «как GitHub Pages» для раздела update: max-age=600 (столько
   Pages разрешает браузеру держать файл, не спрашивая), ETag и ответ
   304 на условный запрос. Обычный http.server заголовка max-age не
   шлёт, и беда C121 на нём не воспроизводится вовсе. В журнал пишется
   каждый запрос: по нему видно, дошёл ли F5 до сервера. */
const PAGES_PY = `
import http.server, os, sys
ROOT, LOG = sys.argv[2], open(sys.argv[3], 'a')
def tag(p):
    st = os.stat(p)
    return '"%x-%x"' % (int(st.st_mtime), st.st_size)
class H(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k): super().__init__(*a, directory=ROOT, **k)
    def end_headers(self):
        self.send_header('Cache-Control', 'max-age=600')
        p = self.translate_path(self.path)
        if os.path.isfile(p): self.send_header('ETag', tag(p))
        super().end_headers()
    def send_head(self):
        p = self.translate_path(self.path)
        if os.path.isfile(p) and self.headers.get('If-None-Match') == tag(p):
            self.send_response(304); self.end_headers(); return None
        return super().send_head()
    def log_message(self, fmt, *a): pass
    def log_request(self, code='-', size='-'):
        LOG.write('%s %s %s\\n' % (self.command, self.path, code)); LOG.flush()
http.server.ThreadingHTTPServer(('127.0.0.1', int(sys.argv[1])), H).serve_forever()
`;

// В странице до всех скриптов: счётчик кадров цикла и метка «видели
// экран подготовки» — он живёт доли секунды, и поймать его можно только
// наблюдателем, а не опросом.
const INIT = () => {
  window.__t = { prep: 0, prepText: [], bootFail: 0 };
  /* Сколько ПОВТОРОВ Escape дошло до страницы. Слушатель встаёт раньше
     игры (перехват на окне, первым), поэтому видит и те, что игра потом
     гасит. Без повторов проверка «удержанный Esc» была бы пустой. */
  window.__escRep = 0;
  addEventListener('keydown', e => { if (e.code === 'Escape' && e.repeat) window.__escRep++; }, true);
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

/* Удержание клавиши: второй и дальше keyboard.down той же клавиши
   Playwright шлёт с repeat: true — это автоповтор, как у человека,
   который держит Esc (так выходят из полного экрана с запертым Esc).
   probe меряется ПОСЛЕ КАЖДОГО нажатия (all), а не только в конце:
   мигание «открыл — закрыл — открыл» на нечётном числе нажатий
   кончается тем же, что и правильное поведение, и проверка по одному
   последнему замеру на копии до правки была зелёной. rep — сколько
   повторов Escape дошло до страницы. */
async function holdKey(page, code, n = 4, probe = null) {
  const r0 = await page.evaluate(() => window.__escRep || 0);
  const all = [];
  for (let i = 0; i < n; i++) {
    await page.keyboard.down(code);
    if (probe) all.push(await probe());
  }
  await page.keyboard.up(code);
  const r1 = await page.evaluate(() => window.__escRep || 0);
  return { probe: all[all.length - 1], all, rep: r1 - r0 };
}
// Ряд замеров одним флагом: «1011» — видно, мигало ли
const seq = (all, f) => all.map(x => (x[f] ? 1 : 0)).join('');

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
    // __frames — кадры игры вообще, и с заглушённой отрисовкой тоже
    window.__frames = 0;
    E.Viewport.prototype.render = function (s, c) {
      window.__frames++;
      if (window.__noRender) return;
      window.__renders++;
      return o.call(this, s, c);
    };
    window.__renderHooked = true;
  });
}
// Дождаться N кадров игры (не секунд: под программным рендером кадр долгий)
async function waitFrames(page, n) {
  const f0 = await page.evaluate(() => window.__frames);
  await page.waitForFunction(([a, k]) => window.__frames >= a + k, [f0, n], { timeout: 120000, polling: 50 });
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
  /* На порту обязан отвечать НАШ сервер. Если там остался сервер от
     прошлого прогона (другая папка, копия игры до правок), новый молча
     не поднимается, а стенд проверяет чужие файлы — так однажды
     проверялась копия «до правок» и краснела там, где всё починено. */
  const mine = fs.readFileSync(path.join(ROOT, 'game/js/space.js'), 'utf8');
  const served = await fetch(BASE + 'js/space.js').then(r => r.text(), () => '');
  if (served !== mine) {
    console.error(`На порту ${PORT} отвечает не эта папка (game/js/space.js другой или не отдаётся). ` +
      'Освободите порт или задайте другой: CF_PORT=…');
    server.kill(); process.exit(2);
  }
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

    /* F11 — свой полный экран, и Keyboard Lock запирает Escape вместе
       с цифрами: иначе в полном экране браузер забирает Esc себе, и
       каждая отмена в бою выбрасывала из полного экрана. Сам Chrome
       (выход по удержанию Esc) стенд проверить не может — только что
       игра просит запереть; замок и полный экран здесь подменены. */
    await page.evaluate(() => {
      window.__lock = null;
      Object.defineProperty(navigator, 'keyboard', { configurable: true,
        value: { lock: k => { window.__lock = k; return Promise.resolve(); }, unlock() {} } });
      document.documentElement.requestFullscreen = () => Promise.resolve();
    });
    await page.keyboard.press('F11');
    const locked = await page.waitForFunction(() => window.__lock, null, { timeout: 5000 }).then(h => h.jsonValue(), () => null);
    ok('F11: полный экран запирает Escape и цифры (Keyboard Lock)', !!locked && locked.includes('Escape') && locked.includes('Digit1'),
      JSON.stringify(locked));

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
    // Часы «Давления Земли» в шапке — только когда на планете есть орудие
    const gun = await page.evaluate(() => ({ gun: !!__sp.gun,
      shown: getComputedStyle(document.querySelector('[data-role="gunclock"]')).display !== 'none' }));
    ok('часы «Давления Земли» в шапке — только при орудии на планете', gun.gun === gun.shown, JSON.stringify(gun));

    /* P3 · стартовая камера (C76): свой флот на экране и не под панелями,
       противник тоже в кадре — видно, откуда идут. Мерить надо ДО любого
       движения камеры. */
    await page.waitForTimeout(800);
    const cam0 = await page.evaluate(() => {
      const P = __sp.playerSide, c = document.getElementById('view');
      const on = p => p.z < 1 && p.x >= 0 && p.y >= 0 && p.x <= innerWidth && p.y <= innerHeight;
      const own = __sp.ships.filter(s => !s.dead && s.side === P && !s.station).map(s => __sp.screenTest(s));
      const foe = __sp.ships.filter(s => !s.dead && s.side !== P).map(s => __sp.screenTest(s));
      const top = document.querySelector('.roster').getBoundingClientRect().top;
      return { own: own.length, onScreen: own.filter(on).length,
        under: own.filter(p => on(p) && document.elementFromPoint(p.x, p.y) !== c).length,
        lowest: Math.round(Math.max(...own.map(p => p.y))), rosterTop: Math.round(top),
        low: +(Math.max(...own.map(p => p.y)) / innerHeight).toFixed(2),
        foeOn: foe.filter(on).length, foe: foe.length };
    });
    /* Доля высоты, а не точки: вертикальный угол камеры один на любой
       размер окна, и та же доля на 1366×768 — это 0,66 от низа ростера
       (он там начинается на 0,69 высоты). До правки было 0,74 — хвост
       флота под ростером на ноутбуке. */
    ok('стартовая камера: свой флот весь в кадре и выше ростера даже на 1366×768, противник в кадре (C76)',
      cam0.onScreen === cam0.own && cam0.under === 0 && cam0.lowest < cam0.rosterTop && cam0.low < 0.66 && cam0.foeOn > 0, JSON.stringify(cam0));

    /* P3 · своя .glb того же масштаба, что процедурная того же слота
       (C88): строим процедурную тем же кодом и сравниваем габарит */
    const glbFit = await page.evaluate(async () => {
      const M = await import('/game/js/models.js');
      const out = [];
      for (const s of __sp.ships) {
        if (s.dead || !s.obj.userData.custom || out.some(o => o.id === s.def.id)) continue;
        const proc = M.visualLength(M.buildShip(s.def, s.faction, true));
        out.push({ id: s.def.id, glb: Math.round(s.len), proc: Math.round(proc), k: +(s.len / proc).toFixed(2) });
      }
      return out;
    }).catch(e => [{ err: e.message }]);
    ok('своя .glb одного масштаба с процедурной того же слота, ±20% (C88)',
      glbFit.length > 0 && glbFit.every(g => g.k > 0.8 && g.k < 1.2), JSON.stringify(glbFit));

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

    /* ── УПРАВЛЕНИЕ МЫШЬЮ И КЛАВИАТУРОЙ (пакет P2). Всё настоящей мышью
       и клавишами; камера проверяется по состоянию (camInfo), а не на
       глаз. Бой на паузе: камера и ввод работают и так. */
    const cam = () => page.evaluate(() => __sp.camInfo());
    const settle = async () => {   // сглаживание камеры дошло до цели
      await mute(page, true);
      await page.waitForFunction(() => { const c = __sp.camInfo(); return Math.abs(c.sdist - c.dist) < 1 && Math.hypot(c.sx - c.x, c.sz - c.z) < 1; },
        null, { timeout: 60000, polling: 50 }).catch(() => {});
      await mute(page, false);
    };
    const freeAt = (fx, fy) => page.evaluate(([fx, fy]) => {
      const c = document.getElementById('view');
      const x = Math.round(innerWidth * fx), y = Math.round(innerHeight * fy);
      return document.elementFromPoint(x, y) === c ? { x, y } : null;
    }, [fx, fy]);

    // ПКМ с протяжкой — поворот камеры, а не приказ
    await page.evaluate(() => { for (const s of __sp.selection) { s.moveTo = null; s.amove = null; } });
    let pt = await freeAt(0.5, 0.45) || await freeAt(0.42, 0.4);
    if (pt) {
      const c0 = await cam();
      await page.mouse.move(pt.x, pt.y);
      await page.mouse.down({ button: 'right' });
      for (let i = 1; i <= 8; i++) await page.mouse.move(pt.x + i * 15, pt.y + i * 2);
      await page.mouse.up({ button: 'right' });
      await waitFrames(page, 2);
      const st = await page.evaluate(() => ({ n: __sp.selection.length, ordered: __sp.selection.filter(s => s.moveTo || s.amove).length }));
      const c1 = await cam();
      ok('ПКМ, отпущенная после протяжки, приказ не отдаёт, а поворачивает камеру', st.n > 0 && st.ordered === 0 && Math.abs(c1.yaw - c0.yaw) > 0.2,
        `с приказом ${st.ordered} из ${st.n}, поворот ${(c1.yaw - c0.yaw).toFixed(2)} рад`);
    } else ok('для протяжки ПКМ нашлась точка поля', false);

    // Средняя кнопка — «схватить мир»: точка под курсором едет за ним
    pt = await freeAt(0.5, 0.42) || await freeAt(0.45, 0.35);
    if (pt) {
      await settle();
      const c0 = await cam();
      const w0 = await page.evaluate(([x, y]) => __sp.worldTest(x, y), [pt.x, pt.y]);
      await page.mouse.move(pt.x, pt.y);
      await page.mouse.down({ button: 'middle' });
      for (let i = 1; i <= 8; i++) await page.mouse.move(pt.x - i * 35, pt.y + i * 5);
      await page.mouse.up({ button: 'middle' });
      await settle();
      const c1 = await cam();
      const w1 = await page.evaluate(([x, y]) => __sp.worldTest(x, y), [pt.x - 280, pt.y + 40]);
      const moved = Math.hypot(c1.x - c0.x, c1.z - c0.z);
      const slip = w0 && w1 ? Math.hypot(w1.x - w0.x, w1.z - w0.z) : 1e9;
      ok('протяжка средней кнопкой сдвигает камеру, точка мира остаётся под курсором', moved > 50 && slip < 40,
        `камера сдвинулась на ${Math.round(moved)}, точка под курсором уехала на ${Math.round(slip)}`);
    } else ok('для протяжки средней кнопкой нашлась точка поля', false);

    // Колесо приближает к точке под курсором, а не к середине экрана (C131)
    pt = await freeAt(0.3, 0.45) || await freeAt(0.32, 0.38);
    if (pt) {
      await settle();
      const c0 = await cam();
      const w0 = await page.evaluate(([x, y]) => __sp.worldTest(x, y), [pt.x, pt.y]);
      await page.mouse.move(pt.x, pt.y);
      await page.mouse.wheel(0, -600);
      await settle();
      const c1 = await cam();
      const w1 = await page.evaluate(([x, y]) => __sp.worldTest(x, y), [pt.x, pt.y]);
      const slip = w0 && w1 ? Math.hypot(w1.x - w0.x, w1.z - w0.z) : 1e9;
      const centerShift = Math.hypot(c1.x - c0.x, c1.z - c0.z);
      ok('колесо приближает к точке под курсором', c1.dist < c0.dist * 0.8 && slip < 25 && centerShift > 40,
        `расстояние ${Math.round(c0.dist)} → ${Math.round(c1.dist)}, точка под курсором уехала на ${Math.round(slip)}, середина сдвинулась на ${Math.round(centerShift)}`);
      await page.mouse.wheel(0, 600);       // отъехать обратно
      await settle();
    } else ok('для колеса нашлась точка поля', false);

    // Курсор у края экрана двигает камеру; у середины — нет; над кнопкой у края — нет
    const edge = await page.evaluate(() => {
      const c = document.getElementById('view'), x = innerWidth - 3, y = Math.round(innerHeight * 0.3);
      return document.elementFromPoint(x, y) === c ? { x, y } : null;
    });
    if (edge) {
      await settle();
      const c0 = await cam();
      await page.mouse.move(edge.x - 40, edge.y);
      await page.mouse.move(edge.x, edge.y);
      await mute(page, true);
      await waitFrames(page, 20);
      await mute(page, false);
      const c1 = await cam();
      await page.mouse.move(960, 400);
      await waitFrames(page, 4);
      const c2 = await cam();
      await waitFrames(page, 10);
      const c3 = await cam();
      // вправо по экрану при yaw — это (cos yaw, −sin yaw)
      const along = (c1.x - c0.x) * Math.cos(c0.yaw) - (c1.z - c0.z) * Math.sin(c0.yaw);
      ok('курсор у края экрана двигает камеру в ту сторону', along > 30, `сдвиг вправо ${Math.round(along)}`);
      ok('курсор ушёл от края — камера стоит', Math.hypot(c3.x - c2.x, c3.z - c2.z) < 2, `за 10 кадров ${Math.hypot(c3.x - c2.x, c3.z - c2.z).toFixed(1)}`);
      // Кнопка скорости у верхнего края: под ней прокрутки нет
      const btn = await page.evaluate(() => {
        const b = document.querySelector('[data-speed="2"]').getBoundingClientRect();
        const x = Math.round(b.left + b.width / 2), y = Math.round(b.top + 1);
        const h = document.elementFromPoint(x, y);
        return { x, y, inEdge: y < 10, hit: !!h && !!h.closest('[data-speed="2"]') };
      });
      await page.mouse.move(btn.x, btn.y);
      const c4 = await cam();
      await waitFrames(page, 10);
      const c5 = await cam();
      ok('над кнопкой у края экрана карта не едет', btn.inEdge && btn.hit && Math.hypot(c5.x - c4.x, c5.z - c4.z) < 2,
        `кнопка в полосе края: ${btn.inEdge}, под курсором кнопка: ${btn.hit}, сдвиг ${Math.hypot(c5.x - c4.x, c5.z - c4.z).toFixed(1)}`);
      await page.mouse.move(960, 500);
    } else ok('у правого края экрана есть поле', false);

    // Отряды: Ctrl+1 и Shift+2 записывают, 1 и 2 возвращают выделение
    await tap(page, '[data-q="all"]');
    const gA = await page.evaluate(() => __sp.selection.map(e => e.uid).sort().join(','));
    await page.keyboard.press('Control+Digit1');
    await tap(page, '[data-q="escort"]');
    const gB = await page.evaluate(() => __sp.selection.map(e => e.uid).sort().join(','));
    await page.keyboard.press('Shift+Digit2');
    await page.keyboard.press('Escape');
    const emptied = await page.evaluate(() => __sp.selection.length === 0 && !document.querySelector('.screen.pause'));
    await page.keyboard.press('Digit1');
    const r1 = await page.evaluate(() => __sp.selection.map(e => e.uid).sort().join(','));
    await page.keyboard.press('Digit2');
    const r2 = await page.evaluate(() => __sp.selection.map(e => e.uid).sort().join(','));
    ok('Ctrl+1 и Shift+2 записывают отряды, 1 и 2 возвращают выделение', emptied && gA && gB && gA !== gB && r1 === gA && r2 === gB,
      `отряд 1: [${gA}] → [${r1}]; отряд 2: [${gB}] → [${r2}]`);
    // Камеру уводим от отряда: «Эскорт» выше сам навёл её на эти корабли
    await page.evaluate(() => __sp.camTest(-900, 0, 900, 1100));
    await settle();
    const before2 = await cam();
    await page.keyboard.press('Digit2');
    await page.keyboard.press('Digit2');      // дважды подряд, в пределах 0,45 с
    await settle();
    const after2 = await cam();
    const gc = await page.evaluate(() => { const l = __sp.selection; return { x: l.reduce((a, e) => a + e.pos.x, 0) / l.length, z: l.reduce((a, e) => a + e.pos.z, 0) / l.length }; });
    ok('цифра отряда дважды подряд — камера к отряду', Math.hypot(after2.x - gc.x, after2.z - gc.z) < 5,
      `камера была в ${Math.round(Math.hypot(before2.x - gc.x, before2.z - gc.z))} от отряда, стала в ${Math.round(Math.hypot(after2.x - gc.x, after2.z - gc.z))}`);

    // Наведение: над врагом при выделенных — прицел; ПКМ по ПОДПИСИ врага — атака (C29, C74)
    await tap(page, '[data-q="all"]');
    await page.evaluate(() => {
      const f = __sp.ships.filter(s => !s.dead && s.side !== __sp.playerSide && !s.station);
      const c = f.reduce((a, s) => ({ x: a.x + s.pos.x / f.length, z: a.z + s.pos.z / f.length }), { x: 0, z: 0 });
      __sp.camTest(c.x, 0, c.z, 700);
    });
    await waitFrames(page, 3);
    const foeAt = await page.evaluate(() => {
      const c = document.getElementById('view');
      const all = __sp.ships.filter(s => !s.dead).map(s => ({ s, p: __sp.screenTest(s) })).filter(o => o.p.z < 1);
      let best = null;
      for (const { s, p } of all) {
        if (s.side === __sp.playerSide || s.station) continue;
        if (p.x < 80 || p.x > innerWidth - 80 || p.y < 120 || p.y > innerHeight - 260) continue;
        const ly = p.y - 34;            // середина подписи над кораблём
        if (document.elementFromPoint(p.x, p.y) !== c || document.elementFromPoint(p.x, ly) !== c) continue;
        /* Луч в центр корабля обязан первым встретить ЕГО корпус: строй
           расставлен со случайным разбросом, и корабль, заслонённый
           соседом, честно не выбирается — проверка от этого мигала */
        if (__sp.pickTest(p.x, p.y).pick !== s.uid) continue;
        // подпись не должна лежать на чужой: соседей рядом нет
        const gap = Math.min(...all.filter(o => o.s !== s).map(o => Math.hypot((o.p.x - p.x) / 2, o.p.y - p.y)));
        if (!best || gap > best.gap) best = { uid: s.uid, x: p.x, y: p.y, ly, gap: Math.round(gap) };
      }
      return best && best.gap > 30 ? best : null;
    });
    if (foeAt) {
      await page.mouse.move(foeAt.x, foeAt.y);
      await waitFrames(page, 4);
      const hv = await page.evaluate(() => __sp.inputTest());
      ok('над врагом при выделенных курсор — прицел, враг подсвечен', hv.cursor === 'cur-attack' && hv.hover === foeAt.uid,
        `курсор ${hv.cursor}, под курсором ${hv.hover}, ждали ${foeAt.uid}`);
      await page.mouse.click(foeAt.x, foeAt.ly, { button: 'right' });
      await waitFrames(page, 1);
      const forced = await page.evaluate(uid => __sp.selection.filter(s => s.kind === 'ship' && s.forced && s.forced.uid === uid).length, foeAt.uid);
      ok('ПКМ по подписи врага — приказ атаковать его (C29)', forced > 0, `атакуют: ${forced}`);
    } else info('наведение и подпись', 'нет врага на экране вне панелей — пропущено');

    /* C29: свечение и факел соседа не перехватывают выбор. Луч упирался
       в прозрачные эффекты раньше корпуса, и ПКМ по фрегату у носа
       авианосца уводил флот бить авианосец. Ловушку ставим сами:
       малый вражеский корабль — за факелом большого (корма с факелом
       развёрнута к камере) и за зевом ангара носителя (нос вбок, курсор
       за носом, но на светящемся пятне). Стенд сначала убеждается, что
       первым луч встречает ЭФФЕКТ соседа (ловушка настоящая), и только
       потом — что наведение и ПКМ берут малый корабль. Позиции после
       проверки возвращаются. */
    await tap(page, '[data-q="all"]');
    for (const kind of ['plume', 'bay']) {
      const what = kind === 'plume' ? 'факел' : 'зев ангара';
      const tr = await page.evaluate(async kind => {
        const { THREE } = await import('/game/js/engine.js');
        const all = __sp.ships.filter(s => !s.dead);
        const foes = all.filter(s => !s.station && !s.hyper && s.side !== __sp.playerSide && s.obj.visible);
        const big = kind === 'bay'
          ? foes.find(s => s.def.cls === 'carrier' && s.obj.children.some(o => o.isSprite))
          : foes.filter(s => s.def.cls !== 'carrier' && (s.obj.userData.engines || []).length).sort((a, b) => b.radius - a.radius)[0];
        const small = foes.filter(s => s !== big && s.def.cls !== 'carrier').sort((a, b) => a.radius - b.radius)[0];
        if (!big || !small) return null;
        // Пустое место поля: ни одного корабля ближе 700
        let P = null;
        for (let r = 900; r <= 2200 && !P; r += 260) {
          for (let a = 0; a < 16 && !P; a++) {
            const x = Math.cos(a / 16 * Math.PI * 2) * r, z = Math.sin(a / 16 * Math.PI * 2) * r;
            if (all.every(s => Math.hypot(s.pos.x - x, s.pos.z - z) > 700)) P = new THREE.Vector3(x, 0, z);
          }
        }
        if (!P) return null;
        window.__trapSave = [big, small].map(s => ({ s, p: s.pos.clone(), q: s.obj.quaternion.clone(), d: s.dir.clone() }));
        __sp.camTest(P.x, 0, P.z, 380);
        const cam = __sp.pickTest(innerWidth / 2, innerHeight / 2).cam;
        const C = new THREE.Vector3(cam.x, cam.y, cam.z);
        const h = new THREE.Vector3(C.x - P.x, 0, C.z - P.z).normalize();   // к камере по горизонтали
        const side = new THREE.Vector3(-h.z, 0, h.x);                          // поперёк взгляда
        const place = (s, at, look) => {
          s.pos.copy(at);
          s.vel.set(0, 0, 0);
          s.obj.lookAt(look);                    // корма (+Z) смотрит на look
          s.dir.set(0, 0, -1).applyQuaternion(s.obj.quaternion);
          s.obj.updateMatrixWorld(true);
        };
        let Q;
        if (kind === 'plume') {
          place(big, P, P.clone().add(h));       // факел — к камере
          const mesh = big.obj.userData.engines[0].children.find(o => o.isMesh);
          Q = mesh.localToWorld(new THREE.Vector3(0, 0, 0.8));
        } else {
          place(big, P, P.clone().add(side));    // нос вбок
          const spr = big.obj.children.find(o => o.isSprite);
          const sc = spr.getWorldScale(new THREE.Vector3());
          Q = spr.getWorldPosition(new THREE.Vector3()).addScaledVector(big.dir, sc.x * 0.5 * 0.85);
        }
        /* Ловушку — в середину экрана: у флагмана факел длинный, и точка
           уезжала под нижнюю панель. Камера только сдвигается (поворот
           и расстояние те же), значит взгляд по горизонтали прежний */
        __sp.camTest(Q.x, Q.y, Q.z, 380);
        const c2 = __sp.pickTest(innerWidth / 2, innerHeight / 2).cam;
        C.set(c2.x, c2.y, c2.z);
        const ray = Q.clone().sub(C).normalize();
        const at = Q.clone().addScaledVector(ray, small.radius * 1.3);
        place(small, at, at.clone().add(side));  // малый — поперёк луча
        return { big: big.uid, bigDef: big.def.id, small: small.uid, smallDef: small.def.id };
      }, kind);
      if (!tr) { info(`C29: ${what} соседа`, 'нет нужной пары вражеских кораблей или пустого места — пропущено'); continue; }
      await waitFrames(page, 3);       // матрицы и подписи — по отрисованному кадру
      const at = await page.evaluate(uid => {
        const p = __sp.screenTest(__sp.ships.find(s => s.uid === uid));
        const x = Math.round(p.x), y = Math.round(p.y);
        return { x, y, onCanvas: document.elementFromPoint(x, y) === document.getElementById('view') };
      }, tr.small);
      const ray = await page.evaluate(([x, y]) => __sp.pickTest(x, y), [at.x, at.y]);
      await page.mouse.move(at.x, at.y);
      await waitFrames(page, 4);
      const hv = await page.evaluate(() => __sp.inputTest());
      await page.mouse.click(at.x, at.y, { button: 'right' });
      await waitFrames(page, 1);
      const f = await page.evaluate(([a, b]) => ({
        small: __sp.selection.filter(s => s.forced && s.forced.uid === a).length,
        big: __sp.selection.filter(s => s.forced && s.forced.uid === b).length }), [tr.small, tr.big]);
      ok(`C29: ловушка «${what} ${tr.bigDef} перед ${tr.smallDef}» настоящая — первым луч встречает эффект`,
        at.onCanvas && !!ray.first && ray.first.effect && ray.first.uid === tr.big,
        `на поле ${at.onCanvas}, первое попадание ${JSON.stringify(ray.first)}`);
      ok(`C29: курсор на ${tr.smallDef} за ${kind === 'plume' ? 'факелом' : 'зевом ангара'} ${tr.bigDef} — наведение и ПКМ берут его`,
        ray.pick === tr.small && hv.hover === tr.small && hv.cursor === 'cur-attack' && f.small > 0 && f.big === 0,
        `выбран ${ray.pick}, под курсором ${hv.hover} (ждали ${tr.small}), курсор ${hv.cursor}, атакуют малого ${f.small}, большого ${f.big}`);
      await page.evaluate(() => {
        for (const { s, p, q, d } of window.__trapSave) { s.pos.copy(p); s.obj.quaternion.copy(q); s.dir.copy(d); }
        for (const s of __sp.selection) { s.forced = null; s.target = null; s.moveTo = null; }
      });
    }

    // A, затем щелчок — атака с ходу; S — стоп; H — держать.
    // Щёлкаем по пустому полю: щелчок по врагу после A — это атака его
    pt = await page.evaluate(() => {
      const c = document.getElementById('view');
      const pts = __sp.ships.filter(s => !s.dead).map(s => __sp.screenTest(s)).filter(p => p.z < 1);
      for (const [fx, fy] of [[0.5, 0.4], [0.3, 0.35], [0.7, 0.35], [0.4, 0.6], [0.6, 0.6], [0.25, 0.55]]) {
        const x = Math.round(innerWidth * fx), y = Math.round(innerHeight * fy);
        if (document.elementFromPoint(x, y) !== c) continue;
        if (pts.every(p => Math.hypot(p.x - x, p.y - y) > 110)) return { x, y };
      }
      return null;
    });
    if (!pt) ok('для атаки с ходу нашлась пустая точка поля', false);
    if (pt) {
      await page.mouse.move(pt.x, pt.y);
      await page.keyboard.press('KeyA');
      await waitFrames(page, 2);
      const curA = await page.evaluate(() => __sp.inputTest().cursor);
      await page.mouse.click(pt.x, pt.y);
      await waitFrames(page, 1);
      const am = await page.evaluate(() => ({ n: __sp.selection.filter(s => s.kind === 'ship' && !s.station).length,
        a: __sp.selection.filter(s => s.amove).length, sel: __sp.selection.length }));
      ok('A, затем щелчок — атака с ходу у выделенных, выделение не сбито', curA === 'cur-attack' && am.a === am.n && am.n > 0,
        `курсор после A: ${curA}, с атакой с ходу ${am.a} из ${am.n}`);
      await page.keyboard.press('KeyS');
      const stopped = await page.evaluate(() => __sp.selection.filter(s => s.amove || s.moveTo || s.forced).length);
      await page.keyboard.press('KeyH');
      const held = await page.evaluate(() => __sp.selection.filter(s => s.kind === 'ship' && !s.station && s.hold).length);
      ok('S снимает приказы, H — держать позицию', stopped === 0 && held === am.n, `с приказами после S: ${stopped}; держат ${held} из ${am.n}`);
      await page.keyboard.press('KeyH');
    }

    // Esc, когда отменять нечего, — меню паузы, и бой стоит (C35)
    await tap(page, '[data-speed="1"]');
    await page.keyboard.press('Escape');       // снимает выделение
    await page.keyboard.press('Escape');       // отменять нечего — меню
    const pauseShown = await page.waitForSelector('.screen.pause', { timeout: 5000 }).then(() => true, () => false);
    const pt0 = await page.evaluate(() => __sp.time);
    await waitFrames(page, 8);
    const pt1 = await page.evaluate(() => __sp.time);
    ok('Esc открывает меню паузы, и бой стоит', pauseShown && pt1 === pt0, `меню: ${pauseShown}, время ${pt0.toFixed(2)} → ${pt1.toFixed(2)}`);
    await page.keyboard.press('Space');        // клавиши игры под меню молчат
    ok('Пробел под меню паузы бой не трогает', await page.evaluate(() => __sp.paused && !!document.querySelector('.screen.pause')));
    /* «Настройки» раскрываются по кнопке, а не висят всегда: правило
       класса `display: flex` перебивало атрибут hidden, и кнопка не
       делала ничего. Галочка прокрутки у края нажимается и помнится. */
    const setShown = () => page.evaluate(() => getComputedStyle(document.querySelector('.screen.pause [data-role="settings"]')).display !== 'none');
    const sh0 = await setShown();
    const sq = await tap(page, '.screen.pause [data-a="settings"]');
    const sh1 = await setShown();
    const eq = await tap(page, '.screen.pause [data-a="edge"]');
    const edgeOff = await page.evaluate(() => localStorage.getItem('capella_edge'));
    await tap(page, '.screen.pause [data-a="edge"]');
    const edgeOn = await page.evaluate(() => localStorage.getItem('capella_edge'));
    await tap(page, '.screen.pause [data-a="settings"]');
    const sh2 = await setShown();
    ok('«Настройки» в меню паузы раскрываются и прячутся, галочка «у края» нажимается',
      !sh0 && sq.ok && sh1 && eq.ok && edgeOff === '0' && edgeOn === '1' && !sh2,
      sq.why || eq.why || `видны до ${sh0}, после ${sh1}, после второго нажатия ${sh2}; у края: ${edgeOff} → ${edgeOn}`);
    r = await tap(page, '.screen.pause [data-a="resume"]');
    const resumed = await page.waitForFunction(t => !document.querySelector('.screen.pause') && __sp.time > t + 0.05, pt1, { timeout: 30000 }).then(() => true, () => false);
    ok('«Продолжить» закрывает меню, бой идёт', r.ok && resumed, r.why);
    r = await tap(page, '[data-role="menu"]');
    const viaBtn = await page.waitForSelector('.screen.pause', { timeout: 5000 }).then(() => true, () => false);
    await page.keyboard.press('Escape');
    ok('«☰» открывает меню, Escape закрывает', r.ok && viaBtn && await page.evaluate(() => !document.querySelector('.screen.pause')), r.why);

    /* Справка из меню паузы не пропускает клавиши в бой. Её листают
       Пробелом и PgDn, а под ней Пробел снимал паузу (бой шёл без
       игрока), PgDn уводил выделенные корабли «Ниже», G — в гипер,
       стрелки двигали камеру. Выделение есть, меню — кнопкой «☰». */
    await tap(page, '[data-q="all"]');
    await tap(page, '[data-role="menu"]');
    await page.waitForSelector('.screen.pause', { timeout: 5000 });
    const hq = await tap(page, '.screen.pause [data-a="help"]');
    const helpOpen = await page.waitForSelector('.screen.neuro', { timeout: 5000 }).then(() => true, () => false);
    const busy = () => page.evaluate(() => ({ t: __sp.time, paused: __sp.paused, c: __sp.camInfo(),
      mv: __sp.ships.filter(s => !s.dead && s.side === __sp.playerSide && (s.moveTo || s.hyper)).length,
      help: !!document.querySelector('.screen.neuro'), menu: !!document.querySelector('.screen.pause') }));
    const h0 = await busy();
    for (const k of ['Space', 'PageDown', 'KeyG', 'KeyS', 'ArrowLeft', 'Digit1']) await page.keyboard.press(k);
    await waitFrames(page, 6);
    const h1 = await busy();
    ok('справка из меню паузы: Пробел, PgDn, G, S, стрелки и цифры до боя не доходят',
      hq.ok && helpOpen && h1.paused && h1.t === h0.t && h1.mv === h0.mv && h1.c.x === h0.c.x && h1.c.z === h0.c.z && h1.help && h1.menu,
      hq.why || `пауза ${h1.paused}, время ${h0.t.toFixed(2)} → ${h1.t.toFixed(2)}, с приказом/гипером ${h0.mv} → ${h1.mv}, ` +
        `камера сдвинулась на ${Math.hypot(h1.c.x - h0.c.x, h1.c.z - h0.c.z).toFixed(1)}, справка ${h1.help}, меню ${h1.menu}`);
    await page.keyboard.press('Escape');
    const helpGone = await page.evaluate(() => !document.querySelector('.screen.neuro') && !!document.querySelector('.screen.pause'));
    await page.keyboard.press('Escape');
    ok('Escape закрывает справку, второй — меню, и бой идёт дальше', helpGone &&
      await page.waitForFunction(t => !document.querySelector('.screen.pause') && __sp.time > t, h1.t, { timeout: 30000 }).then(() => true, () => false));

    /* G с авианосцем — это отход всего флота: спрашивает, как «Отход»
       (C34), и пока висит вопрос, бой стоит. Без авианосца — сразу,
       с полоской, и G ещё раз отменяет. */
    const myHyper = () => page.evaluate(() => __sp.ships.filter(s => !s.dead && s.side === __sp.playerSide && s.hyper).length);
    await tap(page, '[data-q="carrier"]');
    if (await page.evaluate(() => __sp.selection.some(s => s.cls === 'carrier'))) {
      await page.keyboard.press('KeyG');
      const gAsk = await page.waitForSelector('.modal.confirm', { timeout: 5000 }).then(() => true, () => false);
      const g0 = await page.evaluate(() => ({ t: __sp.time, paused: __sp.paused }));
      await waitFrames(page, 6);
      const g1 = await page.evaluate(() => __sp.time);
      const gh = await myHyper();
      ok('G с авианосцем спрашивает подтверждение, бой на это время стоит', gAsk && gh === 0 && g0.paused && g1 === g0.t,
        `окно ${gAsk}, в гипере ${gh}, пауза ${g0.paused}, время ${g0.t.toFixed(2)} → ${g1.toFixed(2)}`);
      // Щелчок по тексту вопроса — не «Нет» (та же ловушка, что C2 у справки)
      const pAt = await page.evaluate(() => {
        const p = document.querySelector('.modal.confirm p');
        if (!p) return { x: 0, y: 0, hit: false, what: 'окна нет' };
        const b = p.getBoundingClientRect();
        const x = b.left + b.width / 2, y = b.top + b.height / 2, h = document.elementFromPoint(x, y);
        return { x, y, hit: h === p, what: h ? h.tagName + '.' + h.className : 'null' };
      });
      if (pAt.hit) await page.mouse.click(pAt.x, pAt.y);
      await page.waitForTimeout(300);
      ok('щелчок по тексту вопроса окно не закрывает', pAt.hit && await page.evaluate(() => !!document.querySelector('.modal.confirm')),
        `в точке щелчка ${pAt.what}`);
      r = await tap(page, '.modal.confirm [data-a="no"]');
      if (!gAsk) await page.evaluate(() => __sp.ships.forEach(s => { s.hyper = null; }));   // откат: G молча увёл флот
      await page.waitForTimeout(200);
      const gNo = await page.evaluate(() => ({ modal: !!document.querySelector('.modal.confirm'), paused: __sp.paused }));
      ok('«Остаться в бою»: гипера нет, бой снова идёт', r.ok && !gNo.modal && !gNo.paused && await myHyper() === 0, r.why || JSON.stringify(gNo));
    } else info('G с авианосцем', 'авианосца в своём флоте нет — пропущено');
    await tap(page, '[data-q="escort"]');
    await page.keyboard.press('KeyG');
    const e1 = await page.evaluate(() => ({ modal: !!document.querySelector('.modal.confirm'), n: __sp.selection.length,
      hyper: __sp.selection.filter(s => s.hyper).length, toast: [...document.querySelectorAll('.toast')].map(t => t.textContent).join(' | ') }));
    await page.keyboard.press('KeyG');
    const e2 = await myHyper();
    ok('G без авианосца — гипер сразу и полоска «G — отменить»; G ещё раз — отмена',
      !e1.modal && e1.n > 0 && e1.hyper === e1.n && /G — отменить/.test(e1.toast) && e2 === 0,
      `окно ${e1.modal}, в гипере ${e1.hyper} из ${e1.n}, после второго G ${e2}; полоски: ${e1.toast.slice(0, 120)}`);

    /* «Отход?» тоже ставит бой на паузу, пока висит: окно гасит все
       клавиши, Пробел в том числе, и бой шёл без игрока */
    r = await tap(page, '[data-role="retreat"]');
    const rAsk = await page.waitForSelector('.modal.confirm', { timeout: 5000 }).then(() => true, () => false);
    const rt0 = await page.evaluate(() => ({ t: __sp.time, paused: __sp.paused }));
    await waitFrames(page, 6);
    const rt1 = await page.evaluate(() => __sp.time);
    await page.keyboard.press('Escape');
    await page.waitForTimeout(200);
    const rBack = await page.evaluate(() => ({ modal: !!document.querySelector('.modal.confirm'), paused: __sp.paused, ret: __sp.retreat[__sp.playerSide] }));
    ok('«Отход?» ставит бой на паузу, Escape — «нет», скорость прежняя', r.ok && rAsk && rt0.paused && rt1 === rt0.t && !rBack.modal && !rBack.paused && !rBack.ret,
      r.why || `пауза под вопросом ${rt0.paused}, время ${rt0.t.toFixed(2)} → ${rt1.toFixed(2)}, после: ${JSON.stringify(rBack)}`);

    /* Удержанный Esc: действует только ПЕРВОЕ нажатие, повторы
       автоповтора молчат. Раньше повторы шли по очереди в меню паузы
       и в бой: меню мигало, бой сам снимался с паузы. А держат Esc
       нарочно — так выходят из полного экрана, где Esc заперт. Бой
       идёт на 1×, ничего не выделено. */
    {
      const st = () => page.evaluate(() => ({ menu: !!document.querySelector('.screen.pause'),
        ask: !!document.querySelector('.modal.confirm'), paused: __sp.paused, sel: __sp.selection.length,
        ret: !!__sp.retreat[__sp.playerSide] }));
      const qa = await tap(page, '[data-role="retreat"]');
      await page.waitForSelector('.modal.confirm', { timeout: 5000 }).catch(() => {});
      const k1 = await holdKey(page, 'Escape', 4, st);
      ok('удержанный Esc на «Отход?»: вопрос закрыт, меню не открылось, бой идёт',
        qa.ok && k1.rep >= 3 && k1.all.every(p => !p.ask && !p.menu && !p.paused && !p.ret),
        qa.why || `повторов ${k1.rep}; по нажатиям: меню ${seq(k1.all, 'menu')}, вопрос ${seq(k1.all, 'ask')}, пауза ${seq(k1.all, 'paused')}`);
      await tap(page, '[data-q="all"]');
      const k2 = await holdKey(page, 'Escape', 4, st);
      ok('удержанный Esc с выделением: выделение снято, меню не открылось',
        k2.rep >= 3 && k2.all.every(p => p.sel === 0 && !p.menu && !p.paused),
        `повторов ${k2.rep}; по нажатиям: меню ${seq(k2.all, 'menu')}, выделено ${k2.all.map(p => p.sel).join(',')}`);
      const k3 = await holdKey(page, 'Escape', 4, st);
      ok('удержанный Esc, отменять нечего: меню паузы открыто и бой стоит, пока держат',
        k3.rep >= 3 && k3.all.every(p => p.menu && p.paused), `повторов ${k3.rep}; по нажатиям: меню ${seq(k3.all, 'menu')}, пауза ${seq(k3.all, 'paused')}`);
      const k4 = await holdKey(page, 'Escape', 4, st);
      await page.waitForTimeout(200);
      const k5 = await st();
      ok('удержанный Esc в меню паузы: меню закрыто и снова не открылось, бой идёт',
        k4.rep >= 3 && k4.all.every(p => !p.menu && !p.paused) && !k5.menu && !k5.paused,
        `повторов ${k4.rep}; по нажатиям: меню ${seq(k4.all, 'menu')}, пауза ${seq(k4.all, 'paused')}; после ${JSON.stringify(k5)}`);
    }
    await tap(page, '[data-speed="0"]');

    // «Мёртвые» кнопки HUD: всё выделено — панель действий полна
    r = await tap(page, '[data-q="all"]');
    ok('«Весь флот» нажимается', r.ok, r.why);
    // Третий отряд — у части ячеек ростера будет «123»
    await page.keyboard.press('Shift+Digit3');
    await page.waitForTimeout(600);
    for (const [w, h] of [[1920, 1080], [1366, 768]]) {
      if (w !== 1920) { await page.setViewportSize({ width: w, height: h }); await page.waitForTimeout(800); }
      const s = await page.evaluate(SCAN);
      ok(`HUD ${w}×${h}: все видимые кнопки под мышью (${s.total} шт.)`, s.total > 10 && !s.dead.length, s.dead.join('; '));
      /* P3 · панель команд (C33, C75): при «Весь флот» ни одна кнопка не
         выходит за экран, не залезает под миникарту и выделенное, подписи
         не обрезаны — и всё это без прокрутки */
      const cmd = await page.evaluate(() => {
        const R = el => el.getBoundingClientRect();
        const hit = (a, b) => a.left < b.right - 0.5 && b.left < a.right - 0.5 && a.top < b.bottom - 0.5 && b.top < a.bottom - 0.5;
        const mm = R(document.querySelector('.minimap')), si = R(document.querySelector('.hud-space .sel-info'));
        const acts = [...document.querySelectorAll('#hud button.act')];
        const out = { n: acts.length, off: [], overMap: [], overSel: [], cut: [], scroll: false };
        for (const b of acts) {
          const r = R(b), t = b.querySelector('b').textContent;
          if (r.left < 0 || r.top < 0 || r.right > innerWidth || r.bottom > innerHeight) out.off.push(t);
          if (hit(r, mm)) out.overMap.push(t);
          if (hit(r, si)) out.overSel.push(t);
          const lb = b.querySelector('b');
          if (lb.scrollWidth > lb.clientWidth + 1) out.cut.push(t);
        }
        const box = document.querySelector('[data-role="acts"]');
        out.scroll = box.scrollWidth > box.clientWidth + 1 || box.scrollHeight > box.clientHeight + 1;
        return out;
      });
      ok(`панель команд ${w}×${h} при «Весь флот»: все ${cmd.n} кнопок в экране, не под миникартой и выделенным, подписи целиком, без прокрутки`,
        cmd.n >= 10 && !cmd.off.length && !cmd.overMap.length && !cmd.overSel.length && !cmd.cut.length && !cmd.scroll,
        `за краем: ${cmd.off.join(', ') || 'нет'}; под миникартой: ${cmd.overMap.join(', ') || 'нет'}; на выделенном: ${cmd.overSel.join(', ') || 'нет'}; обрезаны: ${cmd.cut.join(', ') || 'нет'}; прокрутка: ${cmd.scroll}`);
      // Подписи кораблей (C78): имена не лежат друг на друге и не залезают на шапку
      const lab = await page.evaluate(() => {
        const tb = document.querySelector('.topbar').getBoundingClientRect().bottom;
        const ms = [...document.querySelectorAll('.hud-space .marker')].filter(m => m.style.display !== 'none');
        const vis = el => getComputedStyle(el).display !== 'none' && el.getBoundingClientRect().height > 0;
        const names = ms.filter(m => !m.classList.contains('mini')).map(m => m.querySelector('.mk-name').getBoundingClientRect());
        let over = 0;
        for (let i = 0; i < names.length; i++) for (let j = i + 1; j < names.length; j++) {
          const a = names[i], b = names[j];
          if (a.left < b.right - 4 && b.left < a.right - 4 && a.top < b.bottom - 2 && b.top < a.bottom - 2) over++;
        }
        const onTop = ms.filter(m => [...m.children].some(c => vis(c) && c.getBoundingClientRect().top < tb)).length;
        return { shown: ms.length, names: names.length, over, onTop };
      });
      ok(`подписи ${w}×${h}: имена не наложены друг на друга и не на шапке (C78)`, lab.shown > 0 && !lab.over && !lab.onTop, JSON.stringify(lab));
      if (s.scrolled || s.off.length) info(`HUD ${w}×${h}`, `в прокрутке ${s.scrolled}, за краем экрана ${s.off.length}${s.off.length ? ': ' + s.off.join('; ') : ''}`);
      // Номер отряда в ячейке ростера не лежит на имени корабля
      const rg = await page.evaluate(() => {
        const out = { n: 0, long: 0, bad: [] };
        for (const c of document.querySelectorAll('.rcell')) {
          const g = c.querySelector('.rgrp');
          if (!g || !g.textContent) continue;
          out.n++;
          if (g.textContent.length >= 3) out.long++;
          const a = c.querySelector('b').getBoundingClientRect(), b = g.getBoundingClientRect(), cr = c.getBoundingClientRect();
          if (a.right > b.left + 0.5 || b.right > cr.right + 0.5 || b.top < cr.top) out.bad.push(c.querySelector('b').textContent + '+' + g.textContent);
        }
        return out;
      });
      ok(`ростер ${w}×${h}: номер отряда не лежит на имени корабля`, rg.n > 0 && rg.long > 0 && !rg.bad.length,
        `ячеек с отрядом ${rg.n}, из них «123» ${rg.long}; наложений: ${rg.bad.join(', ') || 'нет'}`);
      if (SHOTS) {
        const box = await page.evaluate(() => { const b = document.querySelector('.roster').getBoundingClientRect(); return { x: b.left, y: b.top - 4, width: Math.min(b.width, 900), height: b.height + 8 }; });
        await page.screenshot({ path: path.join(SHOTS, `roster-${w}.png`), clip: box });
      }
    }
    await page.setViewportSize({ width: 1920, height: 1080 });
    await page.waitForTimeout(500);

    /* P3 · ростер группами по классу (C77): ячеек меньше, чем кораблей;
       щелчок по группе — все, следующий — по одному, после последнего —
       снова все */
    const rg0 = await page.evaluate(() => ({
      cells: [...document.querySelectorAll('.rcell')].map(c => c.querySelector('b').textContent),
      ships: __sp.ships.filter(s => !s.dead && s.side === __sp.playerSide && !s.station).length,
    }));
    ok('ростер — группы по классу с числом (C77)', rg0.cells.length < rg0.ships && rg0.cells.some(t => /×\d/.test(t)),
      `${rg0.ships} кораблей → ячейки: ${rg0.cells.join(', ')}`);
    const multi = rg0.cells.findIndex(t => /×\d/.test(t));
    if (multi >= 0) {
      const cyc = [];
      for (let k = 0; k < 4; k++) {
        r = await tap(page, '.rcell', multi);
        cyc.push(await page.evaluate(() => __sp.selection.length + ':' + __sp.selection.map(e => e.uid).join(',')));
      }
      const n = +cyc[0].split(':')[0];
      ok('щелчок по группе ростера: все → по одному → снова все', r.ok && n > 1 && cyc[1].startsWith('1:') && cyc[2].startsWith('1:') &&
        cyc[1] !== cyc[2] && (n > 2 || cyc[3] === cyc[0]), cyc.join(' | '));
    }
    // C135: пустое место справа от ростера и название боя в шапке — это поле, а не панель
    const holes = await page.evaluate(() => {
      const c = document.getElementById('view');
      const ro = document.querySelector('.roster').getBoundingClientRect();
      const t = document.querySelector('.topbar .title').getBoundingClientRect();
      return [[ro.right + 40, ro.top + ro.height / 2], [t.left + t.width / 2, t.top + t.height / 2]]
        .map(([x, y]) => { const h = document.elementFromPoint(x, y); return h === c ? 'поле' : h.tagName + '.' + h.className; });
    });
    ok('пустая полоса рядом с ростером и название боя не глотают щелчок (C135)', holes.every(h => h === 'поле'), holes.join(' | '));
    /* C43: свои и чужие — разные цвета по СТОРОНЕ, а не по клану:
       подписи, полоски силы в шапке. Камера — так, чтобы в кадре были оба флота */
    await page.evaluate(() => {
      const all = __sp.ships.filter(s => !s.dead);
      const c = all.reduce((a, s) => ({ x: a.x + s.pos.x / all.length, z: a.z + s.pos.z / all.length }), { x: 0, z: 0 });
      __sp.camTest(c.x, 0, c.z, 2200);
    });
    await waitFrames(page, 3);
    const sideCol = await page.evaluate(() => {
      const rgb = c => (c.match(/\d+/g) || []).map(Number);
      const m = [...document.querySelectorAll('.hud-space .marker')].filter(x => x.style.display !== 'none');
      const mine = m.find(x => x.classList.contains('mine')), foe = m.find(x => x.classList.contains('foe'));
      const P = __sp.playerSide;
      const bar = sd => rgb(getComputedStyle(document.querySelector(`[data-role="${sd === 'attacker' ? 'atk' : 'def'}-bar"]`)).backgroundColor);
      return { mine: mine ? rgb(getComputedStyle(mine).color) : null, foe: foe ? rgb(getComputedStyle(foe).color) : null,
        myBar: bar(P), foeBar: bar(P === 'attacker' ? 'defender' : 'attacker') };
    });
    const greenish = c => c && c[1] > c[0] + 40, reddish = c => c && c[0] > c[1] + 60;
    ok('свои — зелёные, чужие — красные: подписи и полоски силы (C43)',
      greenish(sideCol.mine) && reddish(sideCol.foe) && greenish(sideCol.myBar) && reddish(sideCol.foeBar), JSON.stringify(sideCol));
    // Подсказка команды: сразу при наведении, с буквой клавиши, в пределах экрана
    await tap(page, '[data-q="all"]');
    const stopAt = await page.evaluate(() => { const r = document.querySelector('button.act[data-act="stop"]').getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; });
    await page.mouse.move(stopAt.x, stopAt.y);
    await page.waitForTimeout(300);
    const tip = await page.evaluate(() => {
      const t = document.querySelector('.act-tip'), r = t.getBoundingClientRect();
      return { shown: !t.hidden, text: t.textContent, inside: r.left >= 0 && r.top >= 0 && r.right <= innerWidth && r.bottom <= innerHeight };
    });
    ok('подсказка команды появляется при наведении, с клавишей и описанием, в экране', tip.shown && tip.inside && /Стоп\s*S/.test(tip.text) && tip.text.length > 12, JSON.stringify(tip));
    await page.mouse.move(900, 300);
    /* C136: «Дрифт» горит по выделению — включили у одного, выделили весь
       флот: кнопка «часть», а не «все» */
    const flag = await page.evaluate(() => [...document.querySelectorAll('.rcell')].findIndex(c => !/×/.test(c.querySelector('b').textContent)));
    if (flag >= 0) {
      await tap(page, '.rcell', flag);
      await page.keyboard.press('KeyD');
      const one = await page.evaluate(() => document.querySelector('button.act[data-act="drift"]').className);
      await tap(page, '[data-q="all"]');
      const all = await page.evaluate(() => document.querySelector('button.act[data-act="drift"]').className);
      await tap(page, '.rcell', flag);
      await page.keyboard.press('KeyD');
      const off = await page.evaluate(() => __sp.ships.filter(s => s.drift).length);
      ok('«Дрифт» подсвечен по выделению: у одного — горит, у всего флота — «часть» (C136)',
        /\bon\b/.test(one) && /\bpart\b/.test(all) && !/\bon\b/.test(all) && off === 0, `один: ${one}; весь флот: ${all}; дрейфуют после: ${off}`);
    }
    /* Купол РЭБ в покое — одно кольцо, плотная картинка — у выделенного
       (часть C111); и на паузе тоже */
    const ecmIdx = await page.evaluate(() => [...document.querySelectorAll('.rcell')].findIndex(c => /РЭБ/.test(c.textContent)));
    if (ecmIdx >= 0) {
      await page.keyboard.press('Escape');
      await waitFrames(page, 2);
      const rest = await page.evaluate(() => { const e = __sp.ships.find(s => !s.dead && s.ecm && s.side === __sp.playerSide); return e && e.dome.visible ? e.dome.children.filter(c => c.visible).length : -1; });
      await tap(page, '.rcell', ecmIdx);
      await waitFrames(page, 2);
      const full = await page.evaluate(() => { const e = __sp.ships.find(s => !s.dead && s.ecm && s.side === __sp.playerSide); return e && e.dome.visible ? e.dome.children.filter(c => c.visible).length : -1; });
      ok('купол РЭБ: в покое одно кольцо, у выделенного — весь купол (C111)', rest === 1 && full > 3, `видимых частей: в покое ${rest}, выделен ${full}`);
    }

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

    /* C30: медленный клик. Панель выделенного обновляется раз в треть
       секунды, и раньше она при этом пересоздавала кнопки: нажатие,
       пришедшееся на пересборку, терялось. Держим кнопку 150 мс и
       дожидаемся 9 кадров (9 × 0,05 с > 0,34 с) — пересборка за время
       нажатия была бы наверняка. */
    await tap(page, '[data-speed="0"]');
    r = await tap(page, '[data-q="carrier"]');
    ok('«Авианосцы» нажимается', r.ok, r.why);
    await waitFrames(page, 2);
    const launch = await page.evaluate(() => {
      const b = [...document.querySelectorAll('#hud button.act')].find(x => /Перехватчик/.test(x.textContent));
      if (!b) return null;
      b.scrollIntoView({ block: 'nearest', inline: 'nearest' });
      const q = b.getBoundingClientRect(), x = q.left + q.width / 2, y = q.top + q.height / 2;
      const h = document.elementFromPoint(x, y);
      window.__launchBtn = b;
      return { x, y, hit: !!h && (h === b || b.contains(h)), disabled: b.disabled,
        n: __sp.squads.filter(s => !s.dead && s.side === __sp.playerSide).length };
    });
    ok('кнопка «Перехватчик» есть и под мышью', !!launch && launch.hit && !launch.disabled, JSON.stringify(launch));
    if (launch) {
      await page.mouse.move(launch.x, launch.y);
      await page.mouse.down();
      await page.waitForTimeout(150);
      await waitFrames(page, 9);
      await page.mouse.up();
      await waitFrames(page, 1);
      const after = await page.evaluate(() => ({
        n: __sp.squads.filter(s => !s.dead && s.side === __sp.playerSide).length,
        same: window.__launchBtn.isConnected,
      }));
      ok('медленный клик (150 мс) по «Перехватчик» срабатывает', after.n === launch.n + 1,
        `звеньев ${launch.n} → ${after.n}, кнопка та же: ${after.same}`);
    }

    /* Панель выделенного не застывает на погибшем: destroy() сам
       вычищает корабль из выделения, и раньше панель так и показывала
       «прочность 4030/4030» с кнопками, которые ничего не делают. */
    const victim = await page.evaluate(() => {
      const s = __sp.ships.find(x => !x.dead && x.side === __sp.playerSide && x.cls === 'escort');
      if (!s) return null;
      __sp.selection = [s];
      window.__victim = s;
      return s.def.name;
    });
    if (victim) {
      await waitFrames(page, 9);
      const before = await page.evaluate(() => document.querySelector('[data-role="sel"]').innerText.split('\n')[0]);
      await page.evaluate(() => __sp.killTest(window.__victim));
      await waitFrames(page, 2);
      const after = await page.evaluate(() => ({
        text: document.querySelector('[data-role="sel"]').innerText.replace(/\s+/g, ' ').slice(0, 60),
        acts: document.querySelectorAll('[data-role="acts"] button.act').length,
      }));
      ok('выделенный корабль погиб — панель пустеет, кнопок нет', /Ничего не выбрано/.test(after.text) && after.acts === 0,
        `до: «${before}», после: «${after.text}», кнопок ${after.acts}`);
    }

    /* C99 + rehome: звенья погибшего носителя садятся на другой ТОЛЬКО
       на свободное место. Раньше чужое звено место не занимало, а
       посадка его «возвращала» — носитель на четыре ангара держал
       в воздухе восемь звеньев. Оба носителя поднимают всё, первый
       гибнет, его звенья и одно своё звено второго идут на посадку
       прямо над ним: «свободно + своих в воздухе + на постройке» обязано
       не превышать числа ангаров ни в одном кадре. */
    const rh = await page.evaluate(() => {
      const side = ['defender', 'attacker'].find(sd => __sp.ships.filter(s => !s.dead && s.side === sd && s.hangar).length >= 2);
      if (!side) return null;
      const [A, B] = __sp.ships.filter(s => !s.dead && s.side === side && s.hangar);
      for (const c of [A, B]) for (let i = 0; i < 12 && c.hangar.free > 0; i++) __sp.launchTest(c, 'interceptor');
      const orphans = A.hangar.launched.filter(q => !q.dead);
      const own = B.hangar.launched.filter(q => !q.dead);
      __sp.killTest(A);
      for (const q of [...orphans, own[0]]) {
        q.recall = true;
        for (const c of q.craft) c.pos.set(B.pos.x + 4, B.pos.y, B.pos.z + 4);
      }
      /* Своё звено B — первым в очереди кадра: оно садится и освобождает
         место, и сироты в том же кадре пробуют его занять. Иначе они
         обновляются раньше, видят полный ангар и уходят обратно в бой,
         а место между кадрами забирает ИИ новым звеном */
      __sp.craft.sort((x, y) => (x.squad === own[0] ? 0 : 1) - (y.squad === own[0] ? 0 : 1));
      const count = () => B.hangar.free + B.hangar.rebuild.length
        + B.hangar.launched.filter(q => !q.dead && q.home === B).length;
      window.__rh = { B, orphans, worst: count(), samples: 0 };
      window.__rhIv = setInterval(() => {
        const r = window.__rh; r.samples++; r.worst = Math.max(r.worst, count());
      }, 5);
      return { side, bays: B.hangar.bays, orphans: orphans.length, own: own.length };
    });
    ok('для проверки посадки нашлись два носителя с поднятыми звеньями', !!rh && rh.orphans > 0 && rh.own > 0, JSON.stringify(rh));
    if (rh && rh.orphans > 0) {
      await mute(page, true);
      await tap(page, '[data-speed="1"]');
      await waitFrames(page, 24);
      await tap(page, '[data-speed="0"]');
      await mute(page, false);
      const got = await page.evaluate(() => {
        clearInterval(window.__rhIv);
        const r = window.__rh, B = r.B;
        return {
          worst: r.worst, bays: B.hangar.bays, samples: r.samples,
          landedHere: r.orphans.filter(q => q.dead && q.home === B).length,
        };
      });
      ok('посадка чужих звеньев не даёт носителю больше звеньев, чем ангаров (C99)', got.worst <= got.bays,
        `свободно + в воздухе + на постройке — до ${got.worst} при ${got.bays} ангарах (замеров ${got.samples})`);
      ok('звено погибшего носителя село на освободившееся место', got.landedHere > 0, `село на второй носитель: ${got.landedHere}`);
    }

    /* C18: скрытая машина противника не рисуется (как и скрытый
       корабль) — видимая, но не нажимаемая была ловушкой: ПКМ по ней
       уводил флот в точку. Маскировку даём одной машине на месте. */
    const cloak = await page.evaluate(() => {
      const c = __sp.craft.find(x => !x.dead && x.side !== __sp.playerSide);
      if (!c) return null;
      window.__cloakDef = c.def;
      c.def = { ...c.def, stealth: true };
      c.revealUntil = 0; c.exposed = false;
      window.__cloak = c;
      return c.def.name;
    });
    if (cloak) {
      await waitFrames(page, 2);
      const vis = await page.evaluate(() => {
        const c = window.__cloak, v = c.obj.visible;
        c.def = window.__cloakDef;
        return v;
      });
      ok('скрытая машина противника не рисуется (C18)', vis === false, `${cloak}: visible = ${vis}`);
    }

    /* C14: приказ атаковать вражеское ЗВЕНО. У звена нет прочности —
       раньше урон по нему уходил в NaN, звено становилось бессмертным,
       а весь флот стрелял главным калибром в пустоту. Звено ставим
       в чистое место поля, бьём настоящей ПКМ по его подписи и смотрим,
       что урон конечен, а флот стреляет по кораблям. */
    await page.evaluate(() => {
      __sp.closeInTest(320);
      for (const s of __sp.ships) { s.forced = null; s.target = null; }
    });
    await mute(page, true);
    await tap(page, '[data-speed="4"]');
    const foeSq = await page.waitForFunction(() => __sp.squads.some(s => !s.dead && s.side !== __sp.playerSide && s.craft.length >= 3),
      null, { timeout: 180000, polling: 200 }).then(() => true, () => false);
    await tap(page, '[data-speed="0"]');
    await mute(page, false);
    ok('противник поднял звено', foeSq);
    if (foeSq) {
      const spot = await page.evaluate(async () => {
        const P = __sp.playerSide;
        const sq = __sp.squads.find(s => !s.dead && s.side !== P && s.craft.length >= 3);
        window.__foeSq = sq;
        __sp.selection = [...__sp.ships.filter(s => !s.dead && s.side === P && !s.station),
          ...__sp.squads.filter(s => !s.dead && s.side === P)];
        const view = document.getElementById('view');
        for (const [x, z] of [[420, 0], [-420, 0], [600, 40], [-600, 40], [300, -60]]) {
          for (const [i, c] of sq.craft.entries()) c.pos.set(x + (i % 3) * 3, 0, z + Math.floor(i / 3) * 3);
          sq.pos.set(x + 3, 0, z + 1.5);
          __sp.camTest(x * 0.5, 0, 0, 900);
          await new Promise(r => { const f = window.__frames; const iv = setInterval(() => { if (window.__frames > f + 1) { clearInterval(iv); r(); } }, 30); });
          const p = __sp.screenTest(sq);
          if (p.z > 1 || p.x < 60 || p.y < 60 || p.x > innerWidth - 60 || p.y > innerHeight - 60) continue;
          if (document.elementFromPoint(p.x, p.y) !== view) continue;
          const gap = Math.min(...__sp.ships.filter(s => !s.dead).map(s => { const q = __sp.screenTest(s); return Math.hypot(q.x - p.x, q.y - p.y); }));
          if (gap < 60) continue;
          return { x: p.x, y: p.y, gap: Math.round(gap), name: sq.def.name };
        }
        return null;
      });
      ok('звено противника стоит отдельно на экране', !!spot, spot ? `${spot.name}, до кораблей ${spot.gap} точек` : 'не нашлось места');
      if (spot) {
        await page.mouse.click(spot.x, spot.y, { button: 'right' });
        await waitFrames(page, 1);
        const took = await page.evaluate(() => {
          const P = __sp.playerSide, sq = window.__foeSq;
          const mine = __sp.ships.filter(s => !s.dead && s.side === P && !s.station);
          return {
            forced: mine.filter(s => s.forced === sq).length,
            squads: __sp.squads.filter(s => !s.dead && s.side === P && s.target === sq).length,
            badTarget: __sp.ships.filter(s => s.target && s.target.kind === 'squad').length,
            hp: __sp.ships.filter(s => !s.dead && s.side !== P).reduce((a, s) => a + s.hp, 0),
          };
        });
        ok('ПКМ по звену — приказ принят, цель кораблей — машины, а не звено', (took.forced > 0 || took.squads > 0) && took.badTarget === 0,
          `на звено: кораблей ${took.forced}, своих звеньев ${took.squads}; кораблей с целью «звено» ${took.badTarget}`);
        await mute(page, true);
        await tap(page, '[data-speed="4"]');
        const t0 = await page.evaluate(() => __sp.time);
        await page.waitForFunction(t => __sp.time >= t + 8, t0, { timeout: 180000, polling: 200 }).catch(() => {});
        await tap(page, '[data-speed="0"]');
        await mute(page, false);
        const res = await page.evaluate(() => {
          const P = __sp.playerSide;
          const all = [...__sp.ships, ...__sp.craft, ...__sp.squads, window.__foeSq, ...window.__foeSq.craft];
          return {
            nan: all.filter(e => e.hp !== undefined && !Number.isFinite(e.hp)).length,
            hp: __sp.ships.filter(s => !s.dead && s.side !== P).reduce((a, s) => a + s.hp, 0),
            dt: __sp.time,
          };
        });
        ok('урон по звену конечен: ни у кого прочность не NaN', res.nan === 0, `NaN у ${res.nan}`);
        ok('после приказа на звено флот стреляет по кораблям', res.hp < took.hp - 1,
          `прочность противника ${Math.round(took.hp)} → ${Math.round(res.hp)} за ${(res.dt - t0).toFixed(1)} игровых с`);
      }
    }
    await clean('медленный клик и приказ на звено');

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

    // Esc, когда отменять нечего, — меню паузы, бой стоит (C35); «Сдаться» — через подтверждение (C34)
    if (started) {
      await page.evaluate(() => { __gr.selection = []; __gr.placing = null; });
      await page.keyboard.press('Escape');
      const gp = await page.waitForSelector('.screen.pause', { timeout: 5000 }).then(() => true, () => false);
      const gpaused = await page.evaluate(() => __gr.paused);
      await page.keyboard.press('Escape');
      const gback = await page.evaluate(() => !document.querySelector('.screen.pause') && !__gr.paused);
      ok('земля: Esc — меню паузы, бой стоит; Esc ещё раз — дальше', gp && gpaused && gback, `меню ${gp}, пауза ${gpaused}, вернулись ${gback}`);
      // Удержанный Esc — одно нажатие: меню не мигает, бой не снимается с паузы сам
      const gs = () => page.evaluate(() => ({ menu: !!document.querySelector('.screen.pause'), paused: __gr.paused }));
      const gk1 = await holdKey(page, 'Escape', 4, gs);
      const gk2 = await holdKey(page, 'Escape', 4, gs);
      ok('земля: удержанный Esc — меню открыто и бой стоит; удержанный ещё раз — меню закрыто, бой идёт',
        gk1.rep >= 3 && gk2.rep >= 3 && gk1.all.every(p => p.menu && p.paused) && gk2.all.every(p => !p.menu && !p.paused),
        `повторов ${gk1.rep}/${gk2.rep}; по нажатиям: меню ${seq(gk1.all, 'menu')} → ${seq(gk2.all, 'menu')}, пауза ${seq(gk1.all, 'paused')} → ${seq(gk2.all, 'paused')}`);
      // Справка из меню: Пробел ею листают, бой под ней стоит
      await hookRender(page);
      await page.keyboard.press('Escape');
      await page.waitForSelector('.screen.pause', { timeout: 5000 });
      const gh = await tap(page, '.screen.pause [data-a="help"]');
      await page.waitForSelector('.screen.neuro', { timeout: 5000 }).catch(() => {});
      const gt0 = await page.evaluate(() => __gr.time);
      await page.keyboard.press('Space');
      await page.keyboard.press('PageDown');
      await waitFrames(page, 4);
      const gst = await page.evaluate(() => ({ t: __gr.time, paused: __gr.paused, help: !!document.querySelector('.screen.neuro') }));
      await page.keyboard.press('Escape');
      await page.keyboard.press('Escape');
      ok('земля: справка из меню — Пробел и PgDn бой не трогают', gh.ok && gst.paused && gst.t === gt0 && gst.help,
        gh.why || `пауза ${gst.paused}, время ${gt0.toFixed(2)} → ${gst.t.toFixed(2)}, справка ${gst.help}`);
      const q = await tap(page, '[data-role="retreat"]');
      const asked = await page.waitForSelector('.modal.confirm', { timeout: 5000 }).then(() => true, () => false);
      const askPaused = await page.evaluate(() => __gr.paused);
      const q2 = await tap(page, '.modal.confirm [data-a="no"]');
      await page.waitForTimeout(300);
      const still = await page.evaluate(() => !document.querySelector('.modal.confirm') && !__gr.paused &&
        getComputedStyle(document.querySelector('.endcard')).display === 'none');
      ok('земля: «Сдаться» спрашивает (бой на это время стоит), «Продолжить бой» — бой идёт', q.ok && asked && askPaused && q2.ok && still,
        q.why || q2.why || `пауза под вопросом ${askPaused}`);
    }

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
    /* C28: кнопка после щелчка не держит фокус — Пробел и Enter её
       не нажимают. Раньше они пропускали ещё два хода. */
    await page.evaluate(() => document.querySelectorAll('.modal').forEach(m => m.remove()));
    const tA = await page.evaluate(() => +document.querySelector('[data-role="turn"]').textContent);
    const focused = await page.evaluate(() => document.activeElement && document.activeElement.tagName);
    await page.keyboard.press('Space');
    await page.keyboard.press('Enter');
    await page.waitForTimeout(800);
    const tB = await page.evaluate(() => +document.querySelector('[data-role="turn"]').textContent);
    ok('после щелчка «Конец хода» Пробел и Enter ход не пропускают (C28)', tA === tB && focused !== 'BUTTON',
      `ход ${tA} → ${tB}, в фокусе ${focused}`);

    /* C27 и C38: ЛКМ по соседнему миру только выбирает его — флот
       остаётся дома; Escape снимает выбор, и снова виден блок
       технологий; Escape без выбора — меню паузы. */
    const g27 = await page.evaluate(async () => {
      const G = await import('/game/js/galaxy.js');
      document.querySelectorAll('.modal').forEach(m => m.remove());
      const c = __gal.camp, my = c.playerFaction;
      const home = Object.keys(c.systems).find(id => c.systems[id].owner === my);
      Object.assign(c.systems[home], { moved: false, siege: null, fleet: [{ id: 'corvette', count: 2 }] });
      __gal.selectTest(home);
      const view = document.getElementById('view');
      for (const nb of G.neighborsOf(home)) {
        const p = __gal.screenTest(nb);
        if (p.z < 1 && document.elementFromPoint(p.x, p.y) === view) return { home, nb, x: p.x, y: p.y };
      }
      return { home, nb: null };
    });
    if (g27.nb) {
      await page.mouse.click(g27.x, g27.y);
      await page.waitForTimeout(400);
      const st = await page.evaluate(h => ({ sel: __gal.state.selected, moved: !!__gal.camp.systems[h].moved,
        fleet: __gal.camp.systems[h].fleet.reduce((a, x) => a + x.count, 0), modal: !!document.querySelector('.modal') }), g27.home);
      ok('карта: ЛКМ по соседнему миру выбирает его, флот остаётся дома (C27)', st.sel === g27.nb && !st.moved && st.fleet === 2 && !st.modal,
        JSON.stringify(st));
      /* Escape держат: действует первое нажатие, повторы молчат — иначе
         «снять выбор» тут же открывало меню, а меню мигало */
      const cs = () => page.evaluate(() => ({ sel: __gal.state.selected, tech: !!document.querySelector('.tech-block'),
        menu: !!document.querySelector('.screen.pause') }));
      const ck1 = await holdKey(page, 'Escape', 4, cs);
      ok('карта: Escape снимает выбор, технологии снова видны (C38); удержанный — меню не открывает',
        ck1.rep >= 3 && ck1.all.every(p => p.sel === null && p.tech && !p.menu),
        `повторов ${ck1.rep}; по нажатиям: меню ${seq(ck1.all, 'menu')}, ${JSON.stringify(ck1.probe)}`);
      const ck2 = await holdKey(page, 'Escape', 4, cs);
      const ck3 = await holdKey(page, 'Escape', 4, cs);
      await page.waitForTimeout(200);
      ok('карта: Escape без выбора — меню паузы, Escape — закрыть; удержанный не мигает',
        ck2.all.every(p => p.menu) && ck3.all.every(p => !p.menu) && await page.evaluate(() => !document.querySelector('.screen.pause')),
        `по нажатиям: меню ${seq(ck2.all, 'menu')} → ${seq(ck3.all, 'menu')}`);
    } else info('карта: ЛКМ по соседу', 'сосед не виден на поле — пропущено');
    await clean('кампания');

    /* Исход боя на орбите доходит до кампании ЧЕСТНО (C17). Раньше
       отход в атаке оставлял противнику все сбитые им корабли, а в
       обороне ушедшие в гипер корабли игрока пропадали, и флот
       нападавшего записывался в НАШУ систему — то есть числился нашим.
       Два настоящих боя: «Отход» нажимается мышью, итог догоняется
       без отрисовки, после «Продолжить» сверяется карта. */
    const n = f => (f || []).reduce((a, x) => a + x.count, 0);
    // Состав флота строкой: не только сколько, но и КТО — счёт совпадает и у чужого флота
    const key = f => (f || []).filter(x => x.count > 0).map(x => x.id + '×' + x.count).sort().join(' ');
    const fight = async (what, kill, viaMenu) => {
      await page.waitForSelector('.modal [data-a="fight"]', { state: 'visible', timeout: 15000 });
      let q = await tap(page, '.modal [data-a="fight"]');
      ok(`${what}: «${what === 'оборона' ? 'Принять бой' : 'В бой'}» нажимается`, q.ok, q.why);
      await page.waitForFunction(() => window.__sp && __sp.time > 0, null, { timeout: 150000 });
      await settled();
      await tap(page, '[data-speed="0"]');
      const killed = await page.evaluate(k => {
        const foes = __sp.ships.filter(s => !s.dead && s.side !== __sp.playerSide && !s.station);
        for (const s of foes.slice(0, k)) __sp.killTest(s);
        return Math.min(k, foes.length);
      }, kill);
      if (viaMenu) {
        /* В бою кампании «В главное меню» нет: кампания уже сохранена
           со следующим ходом, и выход посреди боя был бы переигровкой.
           Выход — отходом из меню паузы, и он засчитывается. */
        q = await tap(page, '[data-role="menu"]');
        await page.waitForSelector('.screen.pause', { timeout: 5000 }).catch(() => {});
        const pm = await page.evaluate(() => ({
          menu: !!document.querySelector('.screen.pause [data-a="menu"]'),
          restart: !!document.querySelector('.screen.pause [data-a="restart"]'),
          leave: !!document.querySelector('.screen.pause [data-a="leave"]'),
          note: (document.querySelector('.screen.pause [data-role="leave-note"]') || {}).textContent || '' }));
        ok(`${what}: в меню паузы боя кампании нет «В главное меню» и «Начать заново» — выход отходом`,
          q.ok && !pm.menu && !pm.restart && pm.leave && /отход/.test(pm.note), q.why || JSON.stringify(pm));
        if (SHOTS) { await page.waitForTimeout(600); await page.screenshot({ path: path.join(SHOTS, 'pause-campaign.png') }); }
        q = await tap(page, '.screen.pause [data-a="leave"]');
        if (SHOTS) {
          await page.waitForSelector('.modal.confirm', { timeout: 5000 }).catch(() => {});
          await page.screenshot({ path: path.join(SHOTS, 'retreat-ask.png') });
        }
      } else q = await tap(page, '[data-role="retreat"]');
      // C34: отход — только через подтверждение
      const asked = await page.waitForSelector('.modal.confirm [data-a="yes"]', { state: 'visible', timeout: 5000 }).then(() => true, () => false);
      const early = await page.evaluate(() => __sp.retreat[__sp.playerSide]);
      const q2 = await tap(page, '.modal.confirm [data-a="yes"]');
      const going = await page.evaluate(() => __sp.retreat[__sp.playerSide]);
      ok(`${what}: «Отход» спрашивает подтверждение, после «Отходить» флот копит гипер`, q.ok && asked && !early && q2.ok && going,
        q.why || q2.why || `окно: ${asked}, отход до подтверждения: ${early}`);
      await mute(page, true);
      await tap(page, '[data-speed="4"]');
      const done = await page.waitForFunction(() => {
        const e = document.querySelector('.endcard'); return e && e.style.display === 'flex';
      }, null, { timeout: 180000, polling: 300 }).then(() => true, () => false);
      await mute(page, false);
      const res = await page.evaluate(() => ({ o: __sp.outcome, card: document.querySelector('.endcard').innerText.replace(/\s+/g, ' ') }));
      ok(`${what}: бой кончился отходом`, done && res.o && res.o.result === 'retreat', res.card.slice(0, 90));
      q = await tap(page, '.endcard [data-role="cont"]');
      ok(`${what}: «Продолжить» нажимается`, q.ok, q.why);
      await page.waitForFunction(() => document.querySelector('[data-role="endturn"]'), null, { timeout: 60000 });
      await settled();
      return { ...res, killed };
    };

    // Атака с отходом: сбитые противником корабли за ним и остаются
    const atk = await page.evaluate(async () => {
      const G = await import('/game/js/galaxy.js');
      const D = await import('/game/js/data.js');
      document.querySelectorAll('.modal').forEach(m => m.remove());
      const c = __gal.camp, my = c.playerFaction;
      const ai = D.FACTION_IDS.find(f => f !== my);
      const home = Object.keys(c.systems).find(id => c.systems[id].owner === my);
      const to = G.neighborsOf(home)[0];
      Object.assign(c.systems[home], { moved: false, siege: null,
        fleet: [{ id: 'corvette', count: 2 }, { id: 'frigate', count: 2 }, { id: 'cruiser', count: 1 }] });
      Object.assign(c.systems[to], { owner: ai, regiments: 1, buildings: [], siege: null,
        fleet: [{ id: 'corvette', count: 3 }, { id: 'frigate', count: 2 }] });
      window.__sp = null;
      __gal.refreshAll();
      __gal.moveTest(home, to);
      return { home, to, ai };
    });
    const a = await fight('атака', 2);
    const aMap = await page.evaluate(([h, t]) => ({ home: __gal.camp.systems[h].fleet, to: __gal.camp.systems[t].fleet }), [atk.home, atk.to]);
    ok('атака, отход: потери противника остались за ним (C17)', key(aMap.to) === key(a.o.defender) && n(aMap.to) <= 5 - a.killed,
      `у противника было 5, сбито ${a.killed}; в итоге боя ${n(a.o.defender)}, на карте ${n(aMap.to)}`);
    ok('атака, отход: домой вернулись только уцелевшие', key(aMap.home) === key(a.o.attacker),
      `в итоге боя ${key(a.o.attacker)}; дома ${key(aMap.home) || 'пусто'}`);
    await clean('атака с отходом');

    // Оборона с отходом: противнику высаживать некого — планета наша,
    // его флот уходит домой, наши ушедшие в гипер возвращаются
    await page.evaluate(([home, src, ai]) => {
      document.querySelectorAll('.modal').forEach(m => m.remove());
      const c = __gal.camp;
      Object.assign(c.systems[home], { regiments: 1, siege: null,
        fleet: [{ id: 'corvette', count: 2 }, { id: 'frigate', count: 2 }] });
      Object.assign(c.systems[src], { owner: ai, regiments: 0,
        fleet: [{ id: 'cruiser', count: 2 }, { id: 'frigate', count: 3 }] });
      window.__sp = null;
      __gal.refreshAll();
      __gal.defenceTest(ai, src, home);
    }, [atk.home, atk.to, atk.ai]);
    const d = await fight('оборона', 1, true);
    const dMap = await page.evaluate(([h, s]) => ({
      owner: __gal.camp.systems[h].owner, my: __gal.camp.playerFaction,
      home: __gal.camp.systems[h].fleet, src: __gal.camp.systems[s].fleet,
    }), [atk.home, atk.to]);
    ok('оборона, отход: ушедшие в гипер вернулись в свою систему, чужих в ней нет (C17)',
      dMap.owner === dMap.my && n(d.o.defender) > 0 && key(dMap.home) === key(d.o.defender),
      `ушли в гипер: ${key(d.o.defender)}; в системе: ${key(dMap.home) || 'пусто'}; хозяин ${dMap.owner}`);
    ok('оборона, отход: флот противника ушёл туда, откуда пришёл', key(dMap.src) === key(d.o.attacker),
      `у противника в итоге боя: ${key(d.o.attacker)}; в его системе: ${key(dMap.src) || 'пусто'}`);
    await clean('оборона с отходом');
  };

  // ─────────────────────────── ОБНОВЛЕНИЯ ПО F5 (C121)
  /* Игрок, у которого игра открыта, после выкладки жмёт F5 — и обязан
     получить новое. Раньше Chromium брал модули и стили из кэша ПАМЯТИ
     вкладки, не спрашивая service worker вовсе, пока копия «свежая» по
     заголовку max-age=600: F5, второй F5 и переход через about:blank
     давали старый main.js десять минут. Здесь service worker ВКЛЮЧЁН —
     проверяется именно он, на копии game/ во временной папке. */
  const update = async () => {
    console.log('\nОбновления по F5 (service worker включён)  [' + secs() + ']');
    await page.goto('about:blank');   // две игры разом не рисуют
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'capella-e2e-'));
    const www = path.join(dir, 'www');
    fs.cpSync(path.join(ROOT, 'game'), path.join(www, 'game'), { recursive: true });
    fs.writeFileSync(path.join(dir, 'pages.py'), PAGES_PY);
    const log = path.join(dir, 'server.log');
    const port = String(+PORT + 1);
    const srv = spawn('python3', [path.join(dir, 'pages.py'), port, www, log], { stdio: 'ignore' });
    const URL5 = `http://127.0.0.1:${port}/game/`;
    let c5 = null;
    try {
      let up = false;
      for (let i = 0; i < 60 && !up; i++) {
        up = await fetch(URL5).then(r => r.ok, () => false);
        if (!up) await new Promise(r => setTimeout(r, 100));
      }
      if (!up) { ok('сервер «как GitHub Pages» поднялся на порту ' + port, false); return; }
      c5 = await browser.newContext({ viewport: { width: 1366, height: 768 } });   // service worker разрешён
      const p = await c5.newPage();
      const errs = [];
      p.on('pageerror', e => errs.push(String(e.message)));
      const label = async () => {
        await p.waitForSelector('[data-a="skirmish"]', { state: 'visible', timeout: 60000 });
        return p.evaluate(() => document.querySelector('[data-a="skirmish"]').textContent.trim());
      };
      await p.goto(URL5);
      await label();
      const ctl = await p.waitForFunction(() => !!navigator.serviceWorker.controller, null, { timeout: 30000 }).then(() => true, () => false);
      ok('service worker игры взял страницу', ctl);
      await p.reload();   // теперь и модули идут через service worker
      const before = await label();

      // «Выкладка»: сам main.js, модуль глубже по графу и стили. Время
      // файла сдвигаем вперёд — так меняется и ETag, и Last-Modified.
      const edit = (rel, fn) => {
        const f = path.join(www, rel);
        fs.writeFileSync(f, fn(fs.readFileSync(f, 'utf8')));
        const t = Date.now() / 1000 + 120;
        fs.utimesSync(f, t, t);
      };
      edit('game/js/main.js', x => x.replace('data-a="skirmish">Быстрый бой</button>', 'data-a="skirmish">Быстрый бой · НОВОЕ</button>'));
      edit('game/js/engine.js', x => x + "\nglobalThis.__e2eFresh = 'engine';\n");
      edit('game/style.css', x => x + '\nbody { outline-color: rgb(1, 2, 3); }\n');
      fs.appendFileSync(log, '--- выкладка ---\n');

      await p.reload();   // F5
      const after = await label();
      const fresh = await p.evaluate(() => ({
        engine: globalThis.__e2eFresh === 'engine',
        css: getComputedStyle(document.body).outlineColor === 'rgb(1, 2, 3)',
      }));
      const asked = fs.readFileSync(log, 'utf8').split('--- выкладка ---')[1].split('\n').filter(l => /\/js\/main\.js/.test(l)).length;
      ok('F5 после выкладки привозит новый main.js', !/НОВОЕ/.test(before) && /НОВОЕ/.test(after),
        `на кнопке «${after}», запросов main.js к серверу после выкладки: ${asked}`);
      ok('…и новый модуль глубже по графу, и новые стили', fresh.engine && fresh.css,
        `engine.js новый: ${fresh.engine}, style.css новый: ${fresh.css}`);

      await c5.setOffline(true);
      await p.reload();
      const off = await label().catch(() => '');
      ok('без связи открывается уже новая версия', /НОВОЕ/.test(off), off || 'меню без связи не открылось');
      await c5.setOffline(false);
      ok('обновления: без ошибок страницы', !errs.length, errs.slice(0, 3).join(' | '));
    } finally {
      if (c5) await c5.close().catch(() => {});
      srv.kill();
      fs.rmSync(dir, { recursive: true, force: true });
    }
  };

  for (const [g, fn] of [['shell', shell], ['space', space], ['ground', ground], ['campaign', campaign], ['update', update]]) {
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
