// СКАЧАТЬ ФОТОГРАФИИ ОБЪЕКТОВ ОДНИМ АРХИВОМ — в том числе по ссылке
// «только просмотр».
//
// Почему в браузере, а не чтением кода: архив мы собираем СВОИМИ силами,
// без библиотеки, и «похоже на zip» ничего не значит — файл либо
// открывается распаковщиком с верными контрольными суммами, либо это
// мусор, и узнает об этом тот, кому архив уже отправили. Поэтому
// скачанный файл тут же разбирает настоящий распаковщик (python
// zipfile, он же проверяет CRC каждой записи).
//
// Настоящий Firebase ЗАБЛОКИРОВАН, вместо него поддельное облако
// с журналом записей: в режиме просмотра наружу не должно уйти ничего.
// «Оригинал в облаке» изображает перехваченный адрес, отдающий заведомо
// большой файл, — так видно, что в архив лёг ОРИГИНАЛ, а не превью.
//
// Запуск:  node tests/loczip-e2e.js
const path = require('path'), fs = require('fs'), os = require('os');
const { execSync, spawn } = require('child_process');
const { FAKE_CLOUD } = require('./fake-cloud.js');
const ROOT = '/home/user/cineflow';
const LIBS = process.env.CF_LIBS || path.join(os.tmpdir(), 'cineflow-libs');
const PORT = process.env.CF_PORT || '8112';
const ROOM = 'loczip-test';
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-zip-'));
let playwright;
try { playwright = require('playwright'); }
catch (e) { playwright = require(execSync('npm root -g').toString().trim() + '/playwright'); }
const server = spawn('python3', ['-m', 'http.server', PORT, '--bind', '127.0.0.1'], { cwd: ROOT, stdio: 'ignore' });
let bad = 0;
const ok = (n, c, d) => { console.log((c ? '  ok  ' : '  FAIL') + ' ' + n + (d ? ' — ' + d : '')); if (!c) bad++; };

// Крошечный настоящий jpeg 1×1: превью в проекте.
const TINY = '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0a'
           + 'HBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAABAAAAAAAA'
           + 'AAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q==';
const PREVIEW = 'data:image/jpeg;base64,' + TINY;
const PREVIEW_BYTES = Buffer.from(TINY, 'base64').length;
const BIG = 50000;                                   // «оригинал из облака»
const CLOUD_OK = 'https://www.dropbox.com/scl/fi/aaa/snimok.jpg?raw=1';
const CLOUD_DEAD = 'https://www.dropbox.com/scl/fi/bbb/net.jpg?raw=1';

// Что УЖЕ лежит в комнате. Объект с косой чертой в названии — нарочно:
// такое имя нельзя класть в путь архива как есть.
const SEED = {
  locations: {
    'loc-1': { id: 'loc-1', name: 'Квартира на Горской', sceneIds: [], order: 0 },
    'loc-2': { id: 'loc-2', name: 'Двор школы / гараж', sceneIds: [], order: 1 }
  },
  references: {
    'ref-1': { id: 'ref-1', locationId: 'loc-1', url: PREVIEW, file: 'IMG_4821.jpg', tags: ['скаут'] },
    'ref-2': { id: 'ref-2', locationId: 'loc-1', url: PREVIEW, file: 'IMG_4822.jpg', tags: ['скаут'],
               full: CLOUD_OK, cloud: { provider: 'dropbox', path: '/CineFlow/ref-2.jpg' } },
    'ref-3': { id: 'ref-3', locationId: 'loc-1', url: PREVIEW, file: 'IMG_4823.mov', video: true, dur: 42,
               full: CLOUD_OK, cloud: { provider: 'dropbox', path: '/CineFlow/ref-3.mov' } },
    'ref-4': { id: 'ref-4', locationId: 'loc-2', url: PREVIEW, file: 'Двор утро.jpg', tags: ['скаут'] },
    'ref-5': { id: 'ref-5', locationId: 'loc-2', url: PREVIEW, file: 'Гараж.jpg', tags: ['скаут'],
               full: CLOUD_DEAD, cloud: { provider: 'dropbox', path: '/CineFlow/ref-5.jpg' } },
    // Кадр БЕЗ объекта: в архив объектов попасть не должен.
    'ref-6': { id: 'ref-6', locationId: '', url: PREVIEW, file: 'Посторонний.jpg' }
  }
};

// Разбираем скачанное настоящим распаковщиком: он же проверит CRC
// каждой записи. Скрипт кладём файлом, а не в `python3 -c`: перенос
// строки через оболочку приезжает буквальными двумя знаками.
const PY = path.join(OUT, 'readzip.py');
fs.writeFileSync(PY, [
  'import json, sys, zipfile',
  'z = zipfile.ZipFile(sys.argv[1])',
  'print(json.dumps({"bad": z.testzip(),',
  '  "items": [{"name": i.filename, "size": i.file_size} for i in z.infolist()]}, ensure_ascii=False))'
].join('\n'));
const readZip = (file) => JSON.parse(execSync(`python3 ${PY} ${file}`).toString());

(async () => {
  await new Promise(r => setTimeout(r, 1200));
  const browser = await playwright.chromium.launch({ executablePath: process.env.CF_CHROME || '/opt/pw-browsers/chromium', args: ['--no-sandbox'] });

  const mkCtx = async (w, h) => {
    const ctx = await browser.newContext({ viewport: { width: w, height: h }, isMobile: w < 768, hasTouch: true,
                                           serviceWorkers: 'block', acceptDownloads: true });
    await ctx.route('**/*', (route) => {
      const u = route.request().url();
      // «Оригинал в облаке»: один адрес отдаёт большой файл, второй мёртв —
      // на нём и проверяется откат к превью.
      if (u === CLOUD_OK) return route.fulfill({ status: 200, contentType: 'image/jpeg', body: Buffer.alloc(BIG, 7) });
      if (u === CLOUD_DEAD) return route.fulfill({ status: 404, body: 'нет такого файла' });
      if (/firestore|firebase|googleapis|gstatic|nominatim|dropbox|yandex/.test(u)) return route.abort();
      for (const [f, re] of [['react.js', /react@18\/umd\/react\.production/], ['react-dom.js', /react-dom@18/],
                             ['babel.js', /babel\.min\.js/], ['tailwind.js', /cdn\.tailwindcss/]])
        if (re.test(u)) return route.fulfill({ body: fs.readFileSync(path.join(LIBS, f)), contentType: 'application/javascript' });
      route.continue();
    });
    await ctx.addInitScript(FAKE_CLOUD, SEED);
    // Запоминаем, под каким именем приложение отдаёт файл.
    await ctx.addInitScript(() => {
      window.__cfDownloads = [];
      const real = HTMLAnchorElement.prototype.click;
      HTMLAnchorElement.prototype.click = function () {
        if (this.download) window.__cfDownloads.push(this.download);
        return real.apply(this, arguments);
      };
    });
    return ctx;
  };
  const open = async (page, q) => {
    await page.goto(`http://127.0.0.1:${PORT}/index.html${q}`);
    await page.waitForFunction(() => window.__CF_APP_OK, null, { timeout: 120000 });
    await page.waitForTimeout(1800);
  };
  // Кнопку ищем по подсказке и проверяем НАСТОЯЩИМ попаданием: в режиме
  // просмотра половина органов управления спрятана, и «элемент есть»
  // тут не значит «до него можно дотянуться».
  const hits = (text) => {
    const b = [...document.querySelectorAll('button')].find(x => new RegExp(text).test(x.textContent));
    if (!b) return { found: false };
    const r = b.getBoundingClientRect();
    const t = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
    return { found: true, hit: !!t && (b === t || b.contains(t)), label: b.textContent.trim() };
  };

  // ---------- 1. ГОСТЬ ПО ССЫЛКЕ «ОБЪЕКТЫ»
  const ctx = await mkCtx(1440, 900);
  const p = await ctx.newPage();
  await open(p, `?view=locations&room=${ROOM}`);

  const btn = await p.evaluate(hits, 'Все фото архивом');
  ok('кнопка архива видна гостю и нажимается', btn.found && btn.hit, JSON.stringify(btn));
  ok('на кнопке число фотографий (без ролика и без чужих кадров)',
     /· 4$/.test((btn.label || '').trim()), btn.label);

  const dl = p.waitForEvent('download', { timeout: 120000 });
  await p.evaluate(() => [...document.querySelectorAll('button')].find(x => /Все фото архивом/.test(x.textContent)).click());
  const file = path.join(OUT, 'all.zip');
  await (await dl).saveAs(file);
  ok('архив скачался', fs.existsSync(file) && fs.statSync(file).size > 0, fs.existsSync(file) ? fs.statSync(file).size + ' байт' : 'нет файла');

  const z = readZip(file);
  ok('распаковщик открыл архив, контрольные суммы сошлись', z.bad === null, 'битая запись: ' + z.bad);
  const names = z.items.map(i => i.name).sort();
  ok('в архиве 4 фотографии: ролик и чужой кадр не вошли', z.items.length === 4, JSON.stringify(names));
  ok('кириллица в путях цела', names.some(n => n.indexOf('Двор утро') >= 0), JSON.stringify(names));
  ok('фото разложены по папкам объектов', names.every(n => /^(Квартира на Горской|Двор школы гараж)\//.test(n)), JSON.stringify(names));
  ok('косая черта в названии объекта не развалила путь',
     names.some(n => n.startsWith('Двор школы гараж/')) && !names.some(n => n.indexOf('школы/гараж') >= 0), JSON.stringify(names));
  const byName = Object.fromEntries(z.items.map(i => [i.name, i.size]));
  const orig = Object.entries(byName).find(([n]) => n.indexOf('IMG_4822') >= 0);
  ok('оригинал из облака лёг в архив целиком, а не превью', orig && orig[1] === BIG, JSON.stringify(orig));
  const fallback = Object.entries(byName).find(([n]) => n.indexOf('Гараж') >= 0);
  ok('облако не ответило — молча взяли превью', fallback && fallback[1] === PREVIEW_BYTES, JSON.stringify(fallback));

  // Полоску берём ПО МЕТКЕ, а не поиском текста по всем элементам:
  // иначе совпадает контейнер, и в проверку приезжает половина экрана.
  const said = await p.evaluate(() => (document.querySelector('[data-cf="toast"]') || {}).textContent || '');
  ok('полоска называет исход: сколько, откуда и чего нет', /фотограф/.test(said) && /ролик/.test(said), said);

  const wrote = await p.evaluate(() => (window.__cfWrites || []).map(w => w.coll));
  ok('в режиме просмотра наружу по-прежнему не ушло ничего', wrote.length === 0, JSON.stringify(wrote));

  // ---------- 2. ОДИН ОБЪЕКТ ИЗ «···»
  const picked = await p.evaluate(() => {
    const row = [...document.querySelectorAll('.cf-row')].find(r => /Двор школы/.test(r.textContent));
    if (!row) return 'строки объекта нет';
    row.click();
    return '';
  });
  await p.waitForTimeout(800);
  // «···» на странице не одно (есть у сцены, у панелей), поэтому берём
  // ПО ПОДСКАЗКЕ — она и есть то, что обещано человеку.
  const opened = await p.evaluate(() => {
    const b = document.querySelector('[title="Отчёт, удалить объект"]');
    if (!b) return 'кнопки «···» объекта нет';
    b.click();
    return '';
  });
  await p.waitForTimeout(500);
  ok('объект открылся и его «···» нашлось', !picked && !opened, picked + opened);
  const row = await p.evaluate(hits, 'Скачать фото объекта');
  ok('в «···» объекта есть своя строка и она нажимается', row.found && row.hit, JSON.stringify(row));

  const dl2 = p.waitForEvent('download', { timeout: 120000 });
  await p.evaluate(() => [...document.querySelectorAll('button')].find(x => /Скачать фото объекта/.test(x.textContent)).click());
  const file2 = path.join(OUT, 'one.zip');
  await (await dl2).saveAs(file2);
  const z2 = readZip(file2);
  ok('архив одного объекта несёт только его фото', z2.bad === null && z2.items.length === 2
     && z2.items.every(i => i.name.startsWith('Двор школы гараж/')), JSON.stringify(z2.items.map(i => i.name)));
  // Имя проверяем по АТРИБУТУ, который поставило приложение, а не по
  // suggestedFilename: этот Chromium имя с кириллицей до загрузки
  // не доносит вовсе и отдаёт «download» (с латинским именем доносит).
  // Safari, ради которого имя и делается человеческим, доносит — так же
  // работают имена файлов-снимков, они в проекте давно.
  const nm2 = await p.evaluate(() => (window.__cfDownloads || []).slice(-1)[0] || '');
  ok('имя файла называет объект', /Двор школы гараж/.test(nm2), nm2);

  // ---------- 3. ТЕЛЕФОН: кнопка на первом же экране
  const ctxP = await mkCtx(390, 844);
  const pp = await ctxP.newPage();
  await open(pp, `?view=locations&room=${ROOM}`);
  const phone = await pp.evaluate(hits, 'Все фото архивом');
  ok('с телефона кнопка архива на месте и попадает под палец', phone.found && phone.hit, JSON.stringify(phone));

  // ---------- 4. У ХОЗЯИНА ПРОЕКТА ТО ЖЕ САМОЕ
  const ctxO = await mkCtx(1440, 900);
  // Имя обязательно: без него первый запуск показывает окно «как вас
  // зовут» ВМЕСТО приложения, и проверка искала бы кнопку за ним.
  await ctxO.addInitScript(`localStorage.setItem('cf_user_name', 'Хозяин'); localStorage.setItem('cf_user_role', 'Оператор-постановщик');`);
  const po = await ctxO.newPage();
  await open(po, `?room=${ROOM}`);
  // У неактивной вкладки в шапке текста НЕТ, только значок, — жмём
  // по подсказке.
  await po.evaluate(() => { const b = document.querySelector('.cf-navtab[title="Объекты"]'); if (b) b.click(); });
  await po.waitForTimeout(1000);
  const own = await po.evaluate(hits, 'Все фото архивом');
  ok('у хозяина проекта кнопка тоже есть', own.found && own.hit, JSON.stringify(own));

  await browser.close();
  server.kill();
  console.log(bad ? `\n${bad} провал(ов)` : '\nвсё сошлось');
  process.exit(bad ? 1 : 0);
})().catch(e => { console.error(e); server.kill(); process.exit(1); });
