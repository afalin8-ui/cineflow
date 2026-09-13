// Сквозная проверка модуля «Скаут» в Chromium (Playwright).
// Что делает: поднимает приложение локально, БЛОКИРУЕТ Firebase (иначе тест
// писал бы в настоящий проект), даёт поддельную камеру и поддельный компас
// и гоняет весь путь: счёт солнца и угла обзора → вид «План» с компасом
// и ползунком времени → вид «Камера» с дугой, рамкой объектива и состоянием
// «объектив шире, чем камера может показать» → подкрутку по солнцу →
// снимок, который ложится к объекту с подписью → телефонную раскладку
// (Скаут в таб-баре, Чат в «Ещё») → режим просмотра.
//
// Запуск:  node tests/scout-e2e.js
// Нужны: node 18+, playwright, Chromium (CF_CHROME, по умолчанию
// /opt/pw-browsers/chromium), python3 для статического сервера, curl.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execSync, spawn } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const LIBS = process.env.CF_LIBS || path.join(os.tmpdir(), 'cineflow-libs');
const PORT = process.env.CF_PORT || '8097';
const CHROME = process.env.CF_CHROME || '/opt/pw-browsers/chromium';
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
const log = (...a) => console.log(...a);
let failed = 0;
const expect = (name, ok, info) => { log((ok ? '  ok  ' : '  FAIL') + ' ' + name + (info ? ' — ' + info : '')); if (!ok) failed++; };
const near = (a, b, eps) => Math.abs(a - b) <= eps;

// Объект с координатами Москвы и сцена со сменой — чтобы «План» было чем
// наполнить, а день смены откуда взять.
const SEED_LOC = { id: 'loc-t1', name: 'ДВОР ШКОЛЫ', address: 'Москва', coords: '55.75580, 37.61730',
                   description: '', sceneIds: ['scene-1'], lightSchemeId: '', order: 1 };

const mkPage = async (ctx, query) => {
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push('PAGEERROR ' + String(e).slice(0, 400)));
  page.on('console', m => { if (m.type() === 'error') errors.push('CONSOLE ' + m.text().slice(0, 200)); });
  await page.route(/gstatic\.com\/firebasejs/, r => r.abort());
  await page.route(/googleapis\.com/, r => r.abort());
  await page.route(/nominatim\.openstreetmap\.org/, r => r.fulfill({
    contentType: 'application/json',
    body: JSON.stringify({ display_name: 'Тестовая улица, 1, Москва', address: { road: 'Тестовая улица', house_number: '1' } })
  }));
  const lib = (re, file) => page.route(re, r => r.fulfill({ path: path.join(LIBS, file), contentType: 'application/javascript' }));
  await lib(/unpkg\.com\/react@18\/umd\/react\.production/, 'react.js');
  await lib(/unpkg\.com\/react-dom@18/, 'react-dom.js');
  await lib(/(unpkg\.com|cdn\.jsdelivr\.net)\/.*babel/, 'babel.js');
  await lib(/cdn\.tailwindcss\.com/, 'tailwind.js');
  await page.goto(`http://127.0.0.1:${PORT}/index.html${query || ''}`, { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => window.__CF_APP_OK === 1, null, { timeout: 180000 });
  await page.waitForTimeout(1500);
  return { page, errors };
};

// Поддельный компас: Chromium не знает webkitCompassHeading, зато понимает
// стандартное событие с absolute — наш код для него и держит вторую ветку.
const aimAt = (page, az, beta, gamma) => page.evaluate(([az, beta, gamma]) => {
  for (let i = 0; i < 3; i++) {
    window.dispatchEvent(new DeviceOrientationEvent('deviceorientation', {
      absolute: true, alpha: (360 - az) % 360, beta, gamma
    }));
  }
}, [az, beta, gamma]);

(async () => {
  await new Promise(r => setTimeout(r, 800));
  const browser = await playwright.chromium.launch({
    executablePath: CHROME,
    args: ['--no-sandbox', '--use-fake-device-for-media-stream', '--use-fake-ui-for-media-stream',
           '--autoplay-policy=no-user-gesture-required']
  });
  const ctx = await browser.newContext({
    viewport: { width: 1280, height: 900 },
    permissions: ['geolocation', 'camera'],
    geolocation: { latitude: 55.7558, longitude: 37.6173 }
  });
  await ctx.addInitScript(([loc]) => {
    localStorage.setItem('cf_user_name', 'Тест Оператор');
    localStorage.setItem('cf_room', 'e2e-scout-test-room');
    localStorage.setItem('cf_locations', JSON.stringify([loc]));
    localStorage.setItem('cf_scenes', JSON.stringify([{ id: 'scene-1', number: '1', title: 'ИНТ. ДВОР', content: '', date: '2026-06-29', x: 0, y: 0 }]));
  }, [SEED_LOC]);

  // ---------------------------------------------------------------- 1. СЧЁТ
  log('\n1. Счёт: угол обзора, проекция, дуга');
  const { page, errors } = await mkPage(ctx);
  const unit = await page.evaluate(() => {
    const s35 = SCOUT_SENSORS.find(x => x.id === 's35');
    const a35 = SCOUT_SENSORS.find(x => x.id === 'alexa35');
    return {
      // Открытые числа: 24.89 мм на 50 мм = 27.9°; 2*atan(18/26) = 69.4°
      fov50: frameHFov(s35, 1.85, 50, 1),
      fov50wide: frameHFov(a35, 2.39, 50, 1),
      // Анаморф 2× на 50 мм: площадка на сенсоре 1.195 (почти квадрат),
      // ширина 22.96 мм, по горизонтали объектив ведёт себя как 25 мм —
      // 2*atan(22.96/50) = 49.3°
      anam: frameHFov(a35, 2.39, 50, 2),
      // Пропорция НАРИСОВАННОЙ рамки обязана равняться пропорции кадра:
      // считаем вертикальный угол независимо, от высоты площадки.
      anamAspect: (() => {
        const K = 2, F = 50, sa = 2.39 / K;
        const w = Math.min(a35.w, a35.h * sa), h = w / sa;
        const hf = frameHFov(a35, 2.39, F, K) * Math.PI / 180;
        const vf = 2 * Math.atan(h / (2 * F));
        return Math.tan(hf / 2) / Math.tan(vf / 2);
      })(),
      sphAspect: (() => {
        const F = 35, sa = 2.39;
        const w = Math.min(a35.w, a35.h * sa), h = w / sa;
        const hf = frameHFov(a35, 2.39, F, 1) * Math.PI / 180;
        const vf = 2 * Math.atan(h / (2 * F));
        return Math.tan(hf / 2) / Math.tan(vf / 2);
      })(),
      // Проекция: смотрим ровно на солнце — центр
      centre: projectSky(120, 20, 120, 20, 0, 69.4, 1.5),
      // На правом краю кадра
      edge: projectSky(120 + 69.4 / 2, 0, 120, 0, 0, 69.4, 1.5),
      behind: projectSky(300, 0, 120, 0, 0, 69.4, 1.5),
      // Крен 90°: сдвиг вправо становится сдвигом по вертикали
      rolled: projectSky(135, 0, 120, 0, 90, 60, 1),
      arcLen: sunArc(55.7558, 37.6173, '2026-06-29').length,
      arcNoon: (() => { const a = sunArc(55.7558, 37.6173, '2026-06-29'); return a[Math.round(a.length / 2)].alt; })(),
      // Эквивалентное фокусное считается ПО ДИАГОНАЛИ 35-мм кадра, а не
      // по его ширине. Сверка с числами Apple: у iPhone 13 Pro Max (26 мм)
      // videoFieldOfView равен 67,1°, а заявленные «20°» у 120-мм теле —
      // это диагональ.
      halfs: [halfFrame(3 / 2), halfFrame(4 / 3), halfFrame(16 / 9)],
      apple26: camFov(26, 4 / 3),
      apple120diag: 2 * Math.atan(43.267 / 2 / 120) / SUN_RAD,
      fov16x9: camFov(26, 16 / 9),
      // Таблица устройств обязана быть внутренне непротиворечивой
      cams: PHONE_CAMS.map(d => ({ id: d.id, n: d.lens.length,
              bad: d.lens.filter(l => !(l[1] >= 10 && l[1] <= 400)).length,
              main: (d.lens.find(l => l[0] === '1×') || [])[1],
              uw: d.lens.some(l => l[1] < 20) })),
      mainEq: { ipad: mainEqOf('ipad'), iph: mainEqOf('iph'), ipro: mainEqOf('ipro'), none: mainEqOf('') },
      azd: [azDelta(10, 350), azDelta(350, 10), azDelta(100, 100)],
      metres: Math.round(metersBetween({ lat: 55.7558, lon: 37.6173 }, { lat: 55.7568, lon: 37.6173 })),
      plurs: [plur(1, 'кадр', 'кадра', 'кадров'), plur(3, 'кадр', 'кадра', 'кадров'), plur(11, 'кадр', 'кадра', 'кадров')]
    };
  });
  expect('50 мм на Super 35 даёт 27.9°', near(unit.fov50, 27.9, 0.3), unit.fov50.toFixed(2) + '°');
  expect('анаморф 2× на 50 мм даёт 49.3° по горизонтали', near(unit.anam, 49.3, 0.2), unit.anam.toFixed(2) + '°');
  expect('у анаморфной рамки пропорция кадра — 2.39, а не пропорция площадки',
         near(unit.anamAspect, 2.39, 0.01), unit.anamAspect.toFixed(3));
  expect('у сферической рамки та же пропорция 2.39', near(unit.sphAspect, 2.39, 0.01), unit.sphAspect.toFixed(3));
  expect('смотрим на солнце — оно в центре', near(unit.centre.x, 0.5, 1e-6) && near(unit.centre.y, 0.5, 1e-6));
  expect('солнце на краю обзора — у края кадра', near(unit.edge.x, 1, 1e-6), 'x=' + unit.edge.x.toFixed(4));
  expect('солнце за спиной не рисуется', unit.behind === null);
  expect('крен 90° переводит сдвиг вправо в сдвиг вверх',
         near(unit.rolled.x, 0.5, 1e-6) && unit.rolled.y > 0.6, JSON.stringify(unit.rolled));
  expect('дуга дня — 145 точек по 10 минут', unit.arcLen === 145, String(unit.arcLen));
  // 12:00 по часам стенда (UTC) — это не полдень в Москве: настоящий
  // верхний проход около 09:30 UTC. Проверяем именно то, что считаем.
  expect('29 июня в Москве в 12:00 UTC солнце около 47°', near(unit.arcNoon, 47, 3), unit.arcNoon.toFixed(1) + '°');
  expect('разница азимутов по кратчайшей стороне', unit.azd[0] === 20 && unit.azd[1] === -20 && unit.azd[2] === 0, JSON.stringify(unit.azd));
  expect('расстояние по земле: 0.001° широты ≈ 111 м', near(unit.metres, 111, 2), unit.metres + ' м');
  expect('полуширина кадра считается от диагонали: 18.00 / 17.31 / 18.86',
         near(unit.halfs[0], 18, 0.01) && near(unit.halfs[1], 17.307, 0.01) && near(unit.halfs[2], 18.855, 0.01),
         unit.halfs.map(h => h.toFixed(3)).join(' / '));
  expect('26 мм на кадре 4:3 дают 67.3° — Apple отдаёт 67.1°', near(unit.apple26, 67.3, 0.3), unit.apple26.toFixed(1) + '°');
  expect('120 мм по диагонали дают 20.4° — Apple пишет «20°»', near(unit.apple120diag, 20.4, 0.3), unit.apple120diag.toFixed(1) + '°');
  expect('та же камера на 16:9 шире: 71.9°', near(unit.fov16x9, 71.9, 0.3), unit.fov16x9.toFixed(1) + '°');
  expect('во всех наборах камер фокусные в разумных пределах',
         unit.cams.every(c => c.bad === 0), JSON.stringify(unit.cams.filter(c => c.bad).map(c => c.id)));
  expect('у каждого набора есть основная камера «1×»',
         unit.cams.every(c => c.main > 0), JSON.stringify(unit.cams.map(c => c.id + ':' + c.main)));
  expect('основная камера набора и его фокусное — одно решение',
         unit.mainEq.ipad === 30 && unit.mainEq.iph === 26 && unit.mainEq.ipro === 24 && unit.mainEq.none === 26,
         JSON.stringify(unit.mainEq));
  // У 16e, 17e и Air СВЕРХШИРОКОЙ НЕТ ВОВСЕ. Стой они в одном наборе
  // с обычным iPhone, человек видел бы кнопку «0,5×», которой у его
  // телефона не существует, — и рамка была бы вдвое шире снимаемого.
  expect('набор без сверхширокой (16e · 17e · Air) заведён',
         unit.cams.some(c => c.id === 'ie'), unit.cams.map(c => c.id).join(' · '));
  expect('в нём ровно 1× и 2×, и сверхширокой нет',
         (unit.cams.find(c => c.id === 'ie') || {}).uw === false &&
         (unit.cams.find(c => c.id === 'ie') || {}).n === 2,
         JSON.stringify(unit.cams.find(c => c.id === 'ie')));
  expect('у обычного iPhone сверхширокая осталась',
         (unit.cams.find(c => c.id === 'iph') || {}).uw === true);
  expect('plur виден скауту (он объявлен выше AppCore)',
         unit.plurs[0] === 'кадр' && unit.plurs[1] === 'кадра' && unit.plurs[2] === 'кадров', JSON.stringify(unit.plurs));

  // ------------------------------------------------------- 2. ВИД «ПЛАН»
  log('\n2. Вид «План» — без камеры и без разрешений');
  // Неактивные вкладки шапки — ТОЛЬКО значок, подпись лежит в title.
  // Искать по тексту нельзя: /Скаут/ поймает «Скаутинг» — режим экрана
  // сцены, который стоит в разметке выше.
  await page.click('button[title="Скаут"]');
  await page.waitForTimeout(900);
  const plan = await page.evaluate(() => {
    const root = document.querySelector('[data-cf="scout"]');
    const txt = root ? root.innerText : '';
    const rose = document.querySelector('[data-cf="scout-rose"]');
    const tb = document.querySelector('[data-cf="scout-timebar"]');
    return {
      onScout: /Восход|Закат|Полдень/.test(txt),
      hasRose: !!rose,
      arcPath: rose ? [...rose.querySelectorAll('path')].filter(p => (p.getAttribute('d') || '').length > 80).length : 0,
      hasTimeBar: !!tb,
      polyPts: tb ? tb.querySelector('polyline').getAttribute('points').split(' ').length : 0,
      sunrise: (txt.match(/Восход\s+(\d\d:\d\d)/) || [])[1],
      sunset: (txt.match(/Закат\s+(\d\d:\d\d)/) || [])[1],
      shift: /День смены/.test(txt),
      words: /Светит с|Солнца нет|за горизонтом/.test(txt)
    };
  });
  expect('экран скаута открылся', plan.onScout);
  expect('компас нарисован', plan.hasRose);
  expect('дуга солнца на компасе есть', plan.arcPath >= 1, plan.arcPath + ' кривых');
  expect('ползунок времени — это график высоты', plan.hasTimeBar && plan.polyPts === 145, plan.polyPts + ' точек');
  expect('восход и закат посчитаны', !!plan.sunrise && !!plan.sunset, `${plan.sunrise} — ${plan.sunset}`);
  expect('день взят из смены связанной сцены', plan.shift);
  expect('солнце сказано словами', plan.words);

  // Ползунок: тянем в 6 утра и проверяем, что время и высота поехали
  const scrub = await page.evaluate(async () => {
    const svg = document.querySelector('[data-cf="scout-timebar"]');
    const r = svg.getBoundingClientRect();
    const at = (f) => {
      const x = r.left + r.width * f, y = r.top + r.height / 2;
      svg.dispatchEvent(new PointerEvent('pointerdown', { clientX: x, clientY: y, bubbles: true, pointerId: 1, buttons: 1 }));
      svg.dispatchEvent(new PointerEvent('pointerup', { clientX: x, clientY: y, bubbles: true, pointerId: 1 }));
    };
    at(6 / 24);
    await new Promise(r2 => setTimeout(r2, 350));
    // Часы читаем ИМЕННО у ползунка, а не по всей странице: на ней есть
    // и восход, и закат, и любая из этих строк прошла бы проверку.
    const clock = svg.parentElement.innerText.match(/\b(\d\d:\d\d)\b/);
    return { clock: clock && clock[1], hadNow: /сейчас/.test(svg.parentElement.innerText) };
  });
  expect('тянем ползунок на 6 утра — часы показали 06:00', /^06:0\d$/.test(scrub.clock || ''), scrub.clock);
  expect('появилась кнопка «сейчас» — вернуться к живому времени', scrub.hadNow);

  // ----------------------------------------------------- 3. ВИД «КАМЕРА»
  log('\n3. Вид «Камера» — визир и дуга поверх кадра');
  await page.evaluate(() => {
    const b = [...document.querySelectorAll('.cf-seg button')].find(x => x.textContent.trim() === 'Камера');
    if (b) b.click();
  });
  await page.waitForTimeout(400);
  await page.evaluate(() => {
    const b = [...document.querySelectorAll('button')].find(x => /Включить камеру/.test(x.textContent));
    if (b) b.click();
  });
  await page.waitForTimeout(2500);
  await aimAt(page, 180, 90, 0);          // смотрим на юг, горизонтально
  await page.waitForTimeout(400);
  const ar = await page.evaluate(() => {
    const v = document.querySelector('[data-cf="scout-cam"] video');
    const svg = document.querySelector('[data-cf="scout-ar"]');
    const polys = svg ? [...svg.querySelectorAll('polyline')] : [];
    return {
      video: !!v && v.videoWidth > 0 && !v.paused,
      vw: v ? v.videoWidth : 0, vh: v ? v.videoHeight : 0,
      objectFit: v ? getComputedStyle(v).objectFit : '',
      overlay: !!svg,
      polylines: polys.length,
      frame: !!svg && !!svg.querySelector('[data-cf="scout-frame"]'),
      frameW: svg && svg.querySelector('[data-cf="scout-frame"]')
              ? +svg.querySelector('[data-cf="scout-frame"]').getAttribute('width') : 0,
      svgW: svg ? +svg.getAttribute('viewBox').split(' ')[2] : 0,
      stamp: (document.querySelector('[data-cf="scout-stamp"]') || {}).innerText || ''
    };
  });
  expect('камера отдала кадр', ar.video, `${ar.vw}×${ar.vh}`);
  expect('кадр показан БЕЗ обрезки (contain) — иначе накладка уедет', ar.objectFit === 'contain', ar.objectFit);
  expect('накладка лежит ровно по кадру', ar.overlay && ar.svgW > 0, 'ширина ' + ar.svgW);
  expect('дуга солнца нарисована', ar.polylines >= 1, ar.polylines + ' линий');
  expect('рамка объектива есть', ar.frame, `ширина ${Math.round(ar.frameW)} из ${Math.round(ar.svgW)}`);
  expect('рамка уже кадра — 35 мм на Super 35 это ~58% ширины',
         ar.frameW > ar.svgW * 0.45 && ar.frameW < ar.svgW * 0.7, (ar.frameW / ar.svgW * 100).toFixed(0) + '%');
  expect('подпись «где, когда, кем, чем» на кадре',
         /ДВОР ШКОЛЫ/.test(ar.stamp) && /мм/.test(ar.stamp) && /Тест Оператор/.test(ar.stamp) && /азимут/.test(ar.stamp),
         ar.stamp.slice(0, 120));

  // Ночная часть дуги — пунктиром. Смотреть надо НА СЕВЕР: в Москве в конце
  // июня солнце уходит под горизонт неглубоко и как раз с северной стороны,
  // а на юге в кадре только дневная часть.
  await aimAt(page, 0, 90, 0);
  await page.waitForTimeout(400);
  const night = await page.evaluate(() => {
    const svg = document.querySelector('[data-cf="scout-ar"]');
    const polys = [...svg.querySelectorAll('polyline')];
    return { dashed: polys.filter(p => p.getAttribute('stroke-dasharray')).length, total: polys.length };
  });
  expect('ночная часть дуги нарисована пунктиром', night.dashed >= 1, `${night.dashed} пунктирных из ${night.total}`);

  // Указатель «солнце вон там»: мы как раз отвернулись на север
  const pointer = await page.evaluate(() => {
    const root = document.querySelector('[data-cf="scout"]');
    return (root.innerText.match(/солнце\s+\d+°\s*→|←\s*солнце\s+\d+°/) || [])[0] || '';
  });
  expect('отвернулись — появился указатель, куда повернуться', !!pointer, pointer);
  await aimAt(page, 180, 90, 0);
  await page.waitForTimeout(300);

  // Рамка обязана СЖИМАТЬСЯ с ростом фокусного и упираться в «шире не покажу»
  const setLens = (mm) => page.evaluate(async (mm) => {
    const cur = () => parseInt((([...document.querySelectorAll('button')]
      .find(b => /^\d+ мм/.test(b.textContent)) || {}).textContent || '0').match(/(\d+) мм/)[1], 10);
    for (let i = 0; i < 30 && cur() !== mm; i++) {
      const b = document.querySelector(cur() < mm ? '[data-cf="scout-lens-plus"]' : '[data-cf="scout-lens-minus"]');
      b.click();
      await new Promise(r => setTimeout(r, 80));
    }
    await new Promise(r => setTimeout(r, 250));
    const svg = document.querySelector('[data-cf="scout-ar"]');
    const f = svg.querySelector('[data-cf="scout-frame"]');
    return { lens: cur(), w: f ? +f.getAttribute('width') : 0,
             wide: !!(f && f.getAttribute('data-wide')),
             arrows: svg.querySelectorAll('[data-cf="scout-wide-arrow"]').length,
             svgW: +svg.getAttribute('viewBox').split(' ')[2] };
  }, mm);
  const r100 = await setLens(100), r35 = await setLens(35), r12 = await setLens(12);
  expect('100 мм даёт рамку уже, чем 35 мм', r100.lens === 100 && r35.lens === 35 && r100.w < r35.w,
         `${Math.round(r100.w)} против ${Math.round(r35.w)} точек`);
  expect('12 мм ШИРЕ камеры — рамка пунктиром и стрелки наружу',
         r12.lens === 12 && r12.wide && r12.arrows >= 2, `пунктир=${r12.wide}, стрелок=${r12.arrows}`);
  await setLens(35);

  // ------------------------------------- 3б. КАДР ЗАНИМАЕТ ЭКРАН ЦЕЛИКОМ
  // Мерило числовое: сколько точек высоты досталось кадру против высоты
  // всего экрана. На глаз «вроде видно» и при полосе в сотню точек.
  log('\n3б. В камере кадр — во весь экран, и выход из неё нарисован всегда');
  const fill = await page.evaluate(() => {
    const root = document.querySelector('[data-cf="scout"]');
    const cam = document.querySelector('[data-cf="scout-cam"]');
    const hdr = document.querySelector('header');
    const back = document.querySelector('[data-cf="scout-back"]');
    const chip = document.querySelector('[data-cf="scout-place"]');
    const bar = document.querySelector('[data-cf="scout-bar"]');
    const r = root.getBoundingClientRect(), c = cam.getBoundingClientRect();
    // Нижняя полоса обязана ЛЕЖАТЬ ПОВЕРХ кадра, а не под ним.
    const over = bar ? bar.getBoundingClientRect() : null;
    const hit = (el) => {
      if (!el) return false;
      const b = el.getBoundingClientRect();
      const t = document.elementFromPoint(b.left + b.width / 2, b.top + b.height / 2);
      return !!t && (t === el || el.contains(t));
    };
    return {
      camH: Math.round(c.height), rootH: Math.round(r.height), winH: window.innerHeight,
      header: !!hdr, seg: document.querySelectorAll('[data-cf="scout"] .cf-seg').length,
      dateInFlow: document.querySelectorAll('[data-cf="scout"] input[type="date"]').length,
      timebar: document.querySelectorAll('[data-cf="scout-timebar"]').length,
      backHit: hit(back), chipHit: hit(chip),
      barOverlays: !!over && over.bottom > c.bottom - 2 && over.top > c.top,
      mode: root.getAttribute('data-mode')
    };
  });
  expect('в камере шапки модуля нет — ни переключателя, ни поля даты в потоке',
         fill.seg === 0 && fill.dateInFlow === 0, `сегментов ${fill.seg}, дат ${fill.dateInFlow}`);
  expect('шкала дня в потоке не стоит — она по нажатию на часы',
         fill.timebar === 0, String(fill.timebar));
  expect('общая шапка приложения в камере убрана', !fill.header);
  expect('кадр занял ВСЮ высоту модуля', fill.camH >= fill.rootH - 2,
         `${fill.camH} из ${fill.rootH}`);
  expect('кадру досталось больше 90% окна', fill.camH > fill.winH * 0.9,
         `${fill.camH} из ${fill.winH}`);
  expect('нижняя полоса лежит ПОВЕРХ кадра, а не под ним', fill.barOverlays);
  expect('нажатие попадает в «‹ План» — из камеры есть выход', fill.backHit);
  expect('нажатие попадает в чип объекта', fill.chipHit);

  // ------------------------------------------------ 4. ПОДКРУТКА ПО СОЛНЦУ
  log('\n4. Подкрутка компаса по настоящему солнцу');
  await aimAt(page, 180, 90, 0);
  await page.waitForTimeout(300);
  // Задираем устройство на высоту солнца: подкрутка правит АЗИМУТ (там и
  // живёт ошибка магнитометра), а высоту даёт акселерометр по силе тяжести,
  // и она надёжна. Не задрав, солнце просто вне кадра по вертикали.
  // Сбрасываем отмотку и ставим сегодняшний день: в разделе 2 мы увели
  // ползунок на 6 утра дня смены, и целиться в солнце ДРУГОГО дня
  // бессмысленно — проверка мерила бы не то, что показывает экран.
  // В КАМЕРЕ шапки модуля нет: кадр занимает экран целиком, а объект
  // и день живут в шторке за чипом в углу, «сейчас» — в шкале дня,
  // которая открывается часами в нижней полосе.
  await page.evaluate(async () => {
    const clock = document.querySelector('[data-cf="scout-clock"]');
    if (clock) {
      clock.click();
      await new Promise(r => setTimeout(r, 300));
      const now = [...document.querySelectorAll('[data-cf="scout"] button')].find(b => b.textContent.trim() === 'сейчас');
      if (now) now.click();
      await new Promise(r => setTimeout(r, 200));
      clock.click();                                  // шкалу убираем — она закрывает кадр
      await new Promise(r => setTimeout(r, 200));
    }
    document.querySelector('[data-cf="scout-place"]').click();
    await new Promise(r => setTimeout(r, 400));
    const d = document.querySelector('input[type="date"]');
    const set = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
    set.call(d, new Date().toISOString().slice(0, 10));
    d.dispatchEvent(new Event('input', { bubbles: true }));
    d.dispatchEvent(new Event('change', { bubbles: true }));
    await new Promise(r => setTimeout(r, 300));
    document.querySelector('[data-cf="scout-place-ok"]').click();
    await new Promise(r => setTimeout(r, 400));
  });
  await page.waitForTimeout(500);
  const sunAlt = await page.evaluate(() => {
    const p = sunPosition(55.7558, 37.6173, new Date());
    return { alt: p.alt, az: p.az };
  });
  await aimAt(page, 200, 90 + sunAlt.alt, 0);
  await page.waitForTimeout(400);
  const calib = await page.evaluate(async () => {
    const btn = [...document.querySelectorAll('button')].find(b => b.textContent.trim() === 'по солнцу');
    if (!btn) return { err: 'кнопки «по солнцу» нет' };
    btn.click();
    await new Promise(r => setTimeout(r, 350));
    const svg = document.querySelector('[data-cf="scout-ar"]');
    const pe = getComputedStyle(svg).pointerEvents;
    const r = svg.getBoundingClientRect();
    // Тычем РОВНО в центр: значит «солнце прямо передо мной», и поправка
    // обязана стать такой, чтобы наш азимут сравнялся с азимутом солнца.
    const x = r.left + r.width / 2, y = r.top + r.height / 2;
    const el = document.elementFromPoint(x, y);
    const hitsOverlay = el === svg || svg.contains(el);
    svg.dispatchEvent(new PointerEvent('pointerdown', { clientX: x, clientY: y, bubbles: true, pointerId: 7 }));
    await new Promise(r2 => setTimeout(r2, 500));
    const root = document.querySelector('[data-cf="scout"]');
    const offBtn = [...root.querySelectorAll('button')].find(b => /^[+-]?\d+°$/.test(b.textContent.trim()));
    return { pe, hitsOverlay, hitTag: el ? el.tagName + (el.getAttribute('data-cf') || '') : 'нет',
             toast: /подкручен/i.test(document.body.innerText),
             off: offBtn ? offBtn.textContent.trim() : '' };
  });
  expect('в режиме подкрутки накладка принимает нажатия',
         calib.pe === 'auto' && calib.hitsOverlay, `pointer-events=${calib.pe}, под пальцем ${calib.hitTag}`);
  expect('подкрутка применилась и о ней сказано полоской', calib.toast);
  expect('поправка показана кнопкой — её видно и можно снять', !!calib.off, calib.off);
  // После подкрутки солнце обязано оказаться в центре кадра
  const centred = await page.evaluate(() => {
    const svg = document.querySelector('[data-cf="scout-ar"]');
    const vb = svg.getAttribute('viewBox').split(' ').map(Number);
    const disc = [...svg.querySelectorAll('circle')].filter(c => +c.getAttribute('r') === 8)[0];
    return disc ? { dx: Math.abs(+disc.getAttribute('cx') - vb[2] / 2), w: vb[2] } : null;
  });
  expect('солнце встало в центр кадра', centred && centred.dx < centred.w * 0.03,
         centred ? `сдвиг ${centred.dx.toFixed(1)} точек из ${centred.w}` : 'солнца в кадре нет');

  // -------------------------------------------- 4б. ПРЕСЕТЫ КАМЕР УСТРОЙСТВ
  log('\n4б. Пресеты камер устройств');
  const presets = await page.evaluate(async () => {
    const wait = (ms) => new Promise(r => setTimeout(r, ms));
    const frameW = () => {
      const f = document.querySelector('[data-cf="scout-frame"]');
      return f ? +f.getAttribute('width') : 0;
    };
    document.querySelector('[data-cf="scout-setup"]').click();
    await wait(450);
    const devBtns = [...document.querySelectorAll('[data-cf="scout-device"]')].map(b => b.dataset.dev);
    // Обычный iPhone: основная 26 мм
    document.querySelector('[data-cf="scout-device"][data-dev="iph"]').click();
    await wait(350);
    const lensesIphone = [...document.querySelectorAll('[data-cf="scout-lenspreset"]')].map(b => +b.dataset.eq);
    const eqIphone = (document.body.innerText.match(/(\d+(?:\.\d+)?) мм\s+\d+/) || [])[1];
    // iPhone Pro: основная 24 мм, и объективов больше
    document.querySelector('[data-cf="scout-device"][data-dev="ipro"]').click();
    await wait(350);
    const lensesPro = [...document.querySelectorAll('[data-cf="scout-lenspreset"]')].map(b => +b.dataset.eq);
    // Переключаемся на сверхширокую — рамка обязана заметно вырасти
    document.querySelector('[data-cf="scout-setup"]').click();   // закрыть, чтобы увидеть кадр
    await wait(300);
    const wMain = frameW();
    document.querySelector('[data-cf="scout-setup"]').click();
    await wait(400);
    document.querySelector('[data-cf="scout-lenspreset"][data-eq="13"]').click();
    await wait(300);
    document.querySelector('[data-cf="scout-setup"]').click();
    await wait(350);
    const wUw = frameW();
    // Подгонка: шаг в полмиллиметра
    document.querySelector('[data-cf="scout-setup"]').click();
    await wait(400);
    const before = +(localStorage.getItem('cf_scout_deveq'));
    document.querySelector('[data-cf="scout-eq-plus"]').click();
    await wait(300);
    const after = +(localStorage.getItem('cf_scout_deveq'));
    // Возвращаем основную камеру, чтобы дальше снимок был как раньше
    document.querySelector('[data-cf="scout-lenspreset"][data-eq="24"]').click();
    await wait(250);
    document.querySelector('[data-cf="scout-setup"]').click();
    await wait(300);
    return { devBtns, lensesIphone, lensesPro, wMain, wUw, before, after,
             eqmap: JSON.parse(localStorage.getItem('cf_scout_eqmap') || '{}'),
             device: localStorage.getItem('cf_scout_device'),
             deveq: +(localStorage.getItem('cf_scout_deveq')) };
  });
  expect('устройства на выбор есть', presets.devBtns.length >= 6, presets.devBtns.join(' · '));
  expect('у обычного iPhone основная 26 мм, у Pro — 24 мм',
         presets.lensesIphone.includes(26) && presets.lensesPro.includes(24) && !presets.lensesPro.includes(26),
         `обычный ${presets.lensesIphone.join('/')} · Pro ${presets.lensesPro.join('/')}`);
  expect('у Pro объективов больше', presets.lensesPro.length > presets.lensesIphone.length,
         `${presets.lensesPro.length} против ${presets.lensesIphone.length}`);
  expect('сверхширокая ДЕЛАЕТ рамку заметно меньше — обзор-то шире',
         presets.wUw > 0 && presets.wMain > 0 && presets.wUw < presets.wMain * 0.75,
         `${Math.round(presets.wMain)} -> ${Math.round(presets.wUw)} точек`);
  expect('подгонка шагает на полмиллиметра', near(presets.after - presets.before, 0.5, 0.01),
         `${presets.before} -> ${presets.after} мм`);
  expect('выбор устройства запомнился', presets.device === 'ipro', presets.device);
  expect('угол запомнился за этой камерой', Object.values(presets.eqmap).length >= 1,
         JSON.stringify(presets.eqmap));

  // ------------------------------------------------------------ 5. СНИМОК
  log('\n5. Снимок ложится к объекту с подписью');
  const shot = await page.evaluate(async () => {
    const before = JSON.parse(localStorage.getItem('cf_references') || '[]').length;
    const b = document.querySelector('[data-cf="scout-shoot"]');
    if (!b) return { err: 'кнопки «Снять» нет' };
    const r = b.getBoundingClientRect();
    const hit = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
    const hits = hit === b || b.contains(hit);
    b.click();
    for (let i = 0; i < 60 && JSON.parse(localStorage.getItem('cf_references') || '[]').length === before; i++) {
      await new Promise(r2 => setTimeout(r2, 200));
    }
    const refs = JSON.parse(localStorage.getItem('cf_references') || '[]');
    return { hits, before, after: refs.length, last: refs[refs.length - 1] || null };
  });
  expect('нажатие попадает в кнопку «Снять»', shot.hits);
  expect('кадр добавился в проект', shot.after === shot.before + 1, `${shot.before} → ${shot.after}`);
  const L = shot.last || {};
  expect('кадр привязан к объекту', L.locationId === 'loc-t1', L.locationId);
  expect('кадр получил тег «скаут»', (L.tags || []).includes('скаут'), JSON.stringify(L.tags));
  expect('кадр лёг в папку с именем объекта', L.folder === 'ДВОР ШКОЛЫ', L.folder);
  expect('картинка настоящая', /^data:image\/jpeg/.test(L.url || ''), (L.url || '').slice(0, 24));
  const sh = L.shot || {};
  expect('подпись «чем снято» в записи', sh.lens > 0 && sh.sw > 0 && sh.ratio > 0, JSON.stringify({ lens: sh.lens, sw: sh.sw, ratio: sh.ratio }));
  expect('подпись «где снято» в записи', near(sh.lat, 55.7558, 0.01) && near(sh.lon, 37.6173, 0.01) && sh.az !== null,
         `${sh.lat}, ${sh.lon}, азимут ${sh.az}°`);
  expect('подпись «когда снято» в записи', !!sh.when && !isNaN(new Date(sh.when)), sh.when);
  expect('подпись «кем снято» в записи', sh.who === 'Тест Оператор', sh.who);
  expect('название объекта в подписи', sh.place === 'ДВОР ШКОЛЫ', sh.place);

  // ------------------------------------------------------------ 6. ЗАМЕТКИ
  log('\n6. Заметки на ходу ложатся к объекту');
  const noteOpen = await page.evaluate(async () => {
    const open = [...document.querySelectorAll('[data-cf="scout"] button')].find(b => /^☰/.test(b.textContent.trim()));
    if (!open) return 'нет кнопки заметок';
    open.click();
    await new Promise(r => setTimeout(r, 500));
    if (!document.querySelector('[data-cf="scout-notes"]')) return 'окно заметок не открылось';
    // Метка обязательна: «+ заметка» есть и на экране сцены, и по тексту
    // проверка хватала ЕГО — заметка уходила сцене, а не объекту.
    const add = document.querySelector('[data-cf="scout-note-add"]');
    if (!add) return 'нет кнопки «+ заметка»';
    add.click();
    await new Promise(r => setTimeout(r, 500));
    return document.querySelectorAll('[data-cf="scout-note"]').length ? 'ок' : 'поля заметки не появилось';
  });
  expect('окно заметок открылось и поле появилось', noteOpen === 'ок', noteOpen);
  // Набираем НАСТОЯЩИМ вводом: присвоение .value напрямую React не замечает,
  // у него свой сторож значения на узле.
  const NOTE = 'Питание от щитка у калитки, подъезд с грунтовки';
  if (noteOpen === 'ок') await page.fill('[data-cf="scout-note"]', NOTE);
  await page.waitForTimeout(1200);
  const notes = await page.evaluate(() => {
    const st = JSON.parse(localStorage.getItem('cf_stickies') || '[]');
    return { mine: st.filter(x => x.locationId === 'loc-t1'), all: st.length };
  });
  expect('заметка заведена и привязана к объекту', (notes.mine || []).length === 1,
         `своих ${(notes.mine || []).length} из ${notes.all}`);
  expect('текст заметки сохранён', ((notes.mine[0] || {}).text || '') === NOTE, (notes.mine[0] || {}).text);
  expect('заметка лежит и на доске (boardId есть)', !!(notes.mine[0] || {}).boardId, (notes.mine[0] || {}).boardId);
  // ЧТО ЗАМЕТКА ЗАПИСАНА, ДОЛЖНО БЫТЬ ВИДНО. Пишется она на каждую букву,
  // но подтверждения этому не было ниоткуда: окно закрывалось молча.
  const noteOk = await page.evaluate(async () => {
    const ok = document.querySelector('[data-cf="scout-note-ok"]');
    if (!ok) return { err: 'кнопки «Готово» нет' };
    const b = ok.getBoundingClientRect();
    const t = document.elementFromPoint(b.left + b.width / 2, b.top + b.height / 2);
    const hit = !!t && (t === ok || ok.contains(t));
    ok.click();
    await new Promise(r => setTimeout(r, 500));
    return {
      hit, closed: !document.querySelector('[data-cf="scout-notes"]'),
      said: (() => {
        const t = [...document.querySelectorAll('div')].find(d => /z-\[400\]/.test(d.className || ''));
        return t ? t.innerText.trim() : '';
      })()
    };
  });
  expect('нажатие попадает в «Готово»', noteOk.hit === true, JSON.stringify(noteOk));
  expect('«Готово» закрывает окно заметок', noteOk.closed === true, JSON.stringify(noteOk));
  expect('и ГОВОРИТ, что записано и куда',
         /\d+ заметк\S* в объекте/.test(noteOk.said || ''), noteOk.said || '(молчит)');

  // ------------------------------------------------------------ 7. ТЕЛЕФОН
  log('\n7. Телефон 390: Скаут в таб-баре, Чат в «Ещё»');
  const phone = await ctx.newPage();
  await phone.close();
  const pctx = await browser.newContext({
    viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true,
    deviceScaleFactor: 3, permissions: ['geolocation', 'camera'],
    geolocation: { latitude: 55.7558, longitude: 37.6173 }
  });
  await pctx.addInitScript(([loc]) => {
    localStorage.setItem('cf_user_name', 'Тест Оператор');
    localStorage.setItem('cf_room', 'e2e-scout-test-room');
    localStorage.setItem('cf_locations', JSON.stringify([loc]));
  }, [SEED_LOC]);
  const { page: ph, errors: phErr } = await mkPage(pctx);
  const tabs = await ph.evaluate(() => {
    const bar = document.querySelector('.cf-tabbar');
    const btns = bar ? [...bar.querySelectorAll('button')] : [];
    return { labels: btns.map(b => b.textContent.trim()), count: btns.length,
             h: bar ? Math.round(bar.getBoundingClientRect().height) : 0 };
  });
  expect('в таб-баре пять вкладок', tabs.count === 5, tabs.labels.join(' · '));
  expect('«Скаут» в таб-баре', tabs.labels.some(l => /Скаут/.test(l)), tabs.labels.join(' · '));
  expect('«Чат» из таб-бара ушёл', !tabs.labels.some(l => /^Чат/.test(l)));
  const more = await ph.evaluate(async () => {
    const b = [...document.querySelectorAll('.cf-tabbar button')].find(x => /Ещё/.test(x.textContent));
    b.click();
    await new Promise(r => setTimeout(r, 500));
    const sheet = document.querySelector('.cf-sheet');
    const rows = sheet ? [...sheet.querySelectorAll('button')].map(x => x.textContent.trim()) : [];
    const chat = sheet ? [...sheet.querySelectorAll('button')].find(x => /^Чат/.test(x.textContent.trim())) : null;
    let hits = false;
    if (chat) { const r = chat.getBoundingClientRect();
                const el = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
                hits = el === chat || chat.contains(el); }
    return { rows, hasChat: !!chat, hits };
  });
  expect('«Чат» есть в «Ещё» — другого пути к нему с телефона нет', more.hasChat, more.rows.slice(0, 8).join(' · '));
  expect('нажатие попадает именно в строку «Чат»', more.hits);
  expect('«Скаут» в «Ещё» не дублируется', !more.rows.some(r => /^Скаут$/.test(r)), more.rows.join(' · '));
  await ph.keyboard.press('Escape');
  const phScout = await ph.evaluate(async () => {
    const b = [...document.querySelectorAll('.cf-tabbar button')].find(x => /Скаут/.test(x.textContent));
    b.click();
    await new Promise(r => setTimeout(r, 900));
    const seg = [...document.querySelectorAll('[data-cf="scout"] .cf-seg button')].map(x => x.textContent.trim());
    // Ничего не должно уезжать за правый край: 390 точек это мало
    // Смотрим ТОЛЬКО внутри скаута: чат-шторка и окна проекта лежат
    // за краем экрана намеренно, и ловить их тут значило бы ругаться
    // на исправную разметку.
    const root = document.querySelector('[data-cf="scout"]');
    const over = [...root.querySelectorAll('button, select, input, svg')]
      .filter(e => { const r = e.getBoundingClientRect(); return r.width > 0 && (r.right > 391 || r.left < -1); })
      .map(e => (e.textContent || e.tagName).trim().slice(0, 22) + ' @' + Math.round(e.getBoundingClientRect().right));
    const tb = document.querySelector('.cf-tabbar').getBoundingClientRect();
    const hidden = [...root.querySelectorAll('button, select, input')]
      .filter(e => { const r = e.getBoundingClientRect(); return r.height > 0 && r.top < tb.top && r.bottom > tb.top + 2; }).length;
    return { seg, over, tabTop: Math.round(tb.top), hidden, txt: /Восход|Закат/.test(root.innerText) };
  });
  expect('на телефоне скаут открылся и посчитал солнце', phScout.txt);
  expect('переключатель «План / Камера» на месте', phScout.seg.join('/') === 'План/Камера', phScout.seg.join('/'));
  expect('ничего не уезжает за края экрана 390', phScout.over.length === 0, phScout.over.join(' | '));
  expect('ничего не залезло под таб-бар', phScout.hidden === 0, String(phScout.hidden));

  // ГОРИЗОНТАЛЬНОЕ ПОЛОЖЕНИЕ ТЕЛЕФОНА — то, ради чего переделка. Раньше
  // шапка приложения, шапка модуля, полоса визира и шкала дня съедали
  // около 200 точек из 390, и кадру оставалось меньше сотни — «ничего
  // не видно». Мерим числом: сколько досталось кадру и вернулась ли
  // навигация после «‹ План».
  await ph.setViewportSize({ width: 844, height: 390 });
  await ph.waitForTimeout(600);
  const land = await ph.evaluate(async () => {
    const b = [...document.querySelectorAll('[data-cf="scout"] .cf-seg button')].find(x => x.textContent.trim() === 'Камера');
    if (b) b.click();
    await new Promise(r => setTimeout(r, 700));
    const cam = document.querySelector('[data-cf="scout-cam"]');
    const c = cam ? cam.getBoundingClientRect() : { height: 0 };
    const back = document.querySelector('[data-cf="scout-back"]');
    const bb = back ? back.getBoundingClientRect() : null;
    const hit = bb && (() => { const t = document.elementFromPoint(bb.left + bb.width / 2, bb.top + bb.height / 2);
                               return !!t && (t === back || back.contains(t)); })();
    const out = {
      camH: Math.round(c.height), winH: window.innerHeight,
      tabbar: document.querySelectorAll('.cf-tabbar').length,
      header: document.querySelectorAll('header').length,
      backHit: !!hit
    };
    if (back) { back.click(); await new Promise(r => setTimeout(r, 700)); }
    out.tabbarBack = document.querySelectorAll('.cf-tabbar').length;
    out.headerBack = document.querySelectorAll('header').length;
    return out;
  });
  expect('в горизонтальном телефоне кадру досталось больше 90% высоты',
         land.camH > land.winH * 0.9, `${land.camH} из ${land.winH}`);
  // 844 точки в ширину — это уже НЕ телефонная раскладка (порог 768),
  // таб-бара там нет и без камеры. Смотрим на шапку: в камере её быть
  // не должно, а «‹ План» обязан её вернуть.
  expect('в камере шапки нет — экран отдан кадру', land.header === 0, String(land.header));
  expect('нажатие попадает в «‹ План» и в горизонтальном положении', land.backHit);
  expect('«‹ План» возвращает навигацию', land.headerBack === 1, String(land.headerBack));
  await ph.setViewportSize({ width: 390, height: 844 });
  await ph.waitForTimeout(500);

  // А вот В ПОРТРЕТЕ таб-бар есть, и в камере он тоже обязан уйти:
  // это ещё полсотни точек, отнятых у кадра.
  const port = await ph.evaluate(async () => {
    const b = [...document.querySelectorAll('[data-cf="scout"] .cf-seg button')].find(x => x.textContent.trim() === 'Камера');
    if (b) b.click();
    await new Promise(r => setTimeout(r, 700));
    const cam = document.querySelector('[data-cf="scout-cam"]');
    const out = {
      camH: Math.round((cam ? cam.getBoundingClientRect() : { height: 0 }).height),
      winH: window.innerHeight,
      tabbar: document.querySelectorAll('.cf-tabbar').length,
      header: document.querySelectorAll('header').length
    };
    const back = document.querySelector('[data-cf="scout-back"]');
    if (back) { back.click(); await new Promise(r => setTimeout(r, 700)); }
    out.tabbarBack = document.querySelectorAll('.cf-tabbar').length;
    out.headerBack = document.querySelectorAll('header').length;
    return out;
  });
  expect('в портрете камера тоже убирает таб-бар и шапку',
         port.tabbar === 0 && port.header === 0, `таб-баров ${port.tabbar}, шапок ${port.header}`);
  expect('и кадру достаётся весь экран', port.camH > port.winH * 0.9, `${port.camH} из ${port.winH}`);
  expect('«‹ План» возвращает и таб-бар, и шапку',
         port.tabbarBack === 1 && port.headerBack === 1,
         `таб-баров ${port.tabbarBack}, шапок ${port.headerBack}`);

  // --------------------------------------------------- 8. РЕЖИМ ПРОСМОТРА
  log('\n8. Режим просмотра: гость смотрит, но не правит');
  // ОТДЕЛЬНЫЙ контекст: в общем остался бы наш cf_scout_mode от страницы
  // выше, и проверка «гость открывает план» ничего бы не значила.
  const roctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  await roctx.addInitScript(([loc]) => {
    localStorage.setItem('cf_room', 'e2e-scout-test-room');
    localStorage.setItem('cf_locations', JSON.stringify([loc]));
    localStorage.setItem('cf_scout_mode', 'ar');   // нарочно: гость его не выбирал
  }, [SEED_LOC]);
  const { page: ro, errors: roErr } = await mkPage(roctx, '?view=scout&room=e2e-scout-test-room');
  await ro.waitForTimeout(800);
  const guest = await ro.evaluate(() => {
    const root = document.querySelector('[data-cf="scout"]');
    const vis = (sel) => [...(root || document).querySelectorAll(sel)]
      .filter(b => { const s = getComputedStyle(b); return s.display !== 'none' && s.visibility !== 'hidden'; }).length;
    const navLabels = [...document.querySelectorAll('.cf-navtab, header button')].map(b => b.getAttribute('title') || b.textContent.trim());
    return {
      tabs: navLabels.filter(Boolean),
      shoot: vis('[data-cf="scout-shoot"]'),
      here: [...(root || document).querySelectorAll('button')].filter(b => /Я здесь/.test(b.textContent))
              .filter(b => getComputedStyle(b).display !== 'none').length,
      sun: root ? /Восход|Закат|Полдень|Светит/.test(root.innerText) : false,
      seg: root ? [...root.querySelectorAll('.cf-seg button')].map(b => b.textContent.trim()) : [],
      locs: JSON.parse(localStorage.getItem('cf_locations') || '[]').length,
      firstCoords: (JSON.parse(localStorage.getItem('cf_locations') || '[]')[0] || {}).coords || '',
      hasRoot: !!root,
      head: root ? root.innerText.slice(0, 140).replace(/\n/g, ' | ') : ''
    };
  });
  expect('гостю по ссылке видна только страница скаута',
         !guest.tabs.some(t => /КПП|Экспликации|Доски/.test(t)), guest.tabs.join(' · '));
  expect('солнце гость ВИДИТ — ради этого ссылку и открывают', guest.sun,
         `объектов ${guest.locs}, координаты «${guest.firstCoords}», экран: ${guest.head}`);
  expect('кнопка «Снять» у гостя спрятана', guest.shoot === 0, String(guest.shoot));
  expect('кнопка «Я здесь» у гостя спрятана', guest.here === 0, String(guest.here));
  expect('переключатель видов гостю оставлен', guest.seg.join('/') === 'План/Камера', guest.seg.join('/'));
  expect('гость открывается на «Плане», а не с просьбой дать камеру',
         !/Включить камеру/.test(guest.head), guest.head.slice(0, 80));

  // Заметка Babel про размер файла — это note, а не ошибка: он её печатает
  // в console.error на любом файле крупнее 500 КБ, и наш заведомо крупнее.
  const allErr = [...errors, ...phErr, ...roErr]
    .filter(e => !/firestore|firebase|googleapis|net::ERR|deoptimised the styling/i.test(e));
  expect('ни одной ошибки на странице', allErr.length === 0, allErr.slice(0, 3).join(' ;; '));

  await browser.close();
  server.kill();
  log(failed ? `\n${failed} проверок не прошло` : '\nВсё прошло');
  process.exit(failed ? 1 : 0);
})().catch(e => { console.error(e); server.kill(); process.exit(1); });
