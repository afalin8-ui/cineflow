// Сборка Excalidraw в ОДИН готовый файл для CineFlow.
//
// У CineFlow нет сборщика, и приложение остаётся без него: этот скрипт
// запускают ОДИН раз, когда меняют версию Excalidraw, а результат лежит
// в репозитории готовым — так же, как three.js у игры в game/vendor.
// Excalidraw 0.18 раздаётся только модулями с десятком зависимостей,
// обычным тегом <script> его не подключить; здесь он собирается в
// самостоятельный файл, который кладёт всё в window.ExcalidrawLib.
//
// React НЕ вшивается: берётся тот же window.React, на котором работает
// приложение. Два React на странице — это «Invalid hook call» и белый
// экран. Mermaid (диаграммы из текста) отрезан заглушкой: он весит
// больше трёх мегабайт, а нужен одной редкой кнопке.
//
// Запуск из корня репозитория:   node vendor/excalidraw/build.mjs
// Нужны node и npm; всё скачивается во временную папку, репозиторий
// не засоряется.
import { execSync } from 'child_process';
import fs from 'fs';
import os from 'os';
import path from 'path';
import { fileURLToPath, pathToFileURL } from 'url';

const VERSION = '0.18.1';
// Метка НАШИХ правок поверх Excalidraw (см. PATCHES ниже). Входит в имя
// файла: service worker отдаёт библиотеку из кэша не спрашивая сеть, и под
// прежним именем на iPad так и осталась бы старая сборка. Меняешь PATCHES —
// поднимай метку, правь EXC_FILE в index.html и VENDOR в sw.js.
const CF_BUILD = 'cf2';
const here = path.dirname(fileURLToPath(import.meta.url));
const tmp = path.join(os.tmpdir(), 'cf-excalidraw-build');
fs.mkdirSync(tmp, { recursive: true });
if (!fs.existsSync(path.join(tmp, 'package.json'))) fs.writeFileSync(path.join(tmp, 'package.json'), '{"private":true}');
execSync(`npm i --no-audit --no-fund @excalidraw/excalidraw@${VERSION} react@18 react-dom@18 esbuild`, { cwd: tmp, stdio: 'inherit' });
const esbuild = await import(pathToFileURL(path.join(tmp, 'node_modules/esbuild/lib/main.js')).href);

const shims = {
  'react': 'module.exports = window.React;',
  'react-dom': 'module.exports = window.ReactDOM;',
  'react-dom/client': 'module.exports = window.ReactDOM;',
  // Классический createElement вместо нового jsx-runtime: в UMD-сборке
  // React 18 модуля jsx-runtime нет вовсе. children лежат в props,
  // createElement берёт их оттуда сам.
  'react/jsx-runtime': `const R = window.React;
    function jsx(t, p, k) { const c = Object.assign({}, p); if (k !== undefined) c.key = k; return R.createElement(t, c); }
    module.exports = { jsx, jsxs: jsx, Fragment: R.Fragment };`,
  'mermaid': 'module.exports = { parseMermaidToExcalidraw: async () => { throw new Error("mermaid off"); } };',
};
// ПРАВКИ ПОВЕРХ EXCALIDRAW. Каждая ищется в сжатом коде и обязана найтись
// РОВНО столько раз, сколько указано: не нашлась (вышла новая версия, код
// переименовали) — сборка падает, а не выходит молча без правки.
const PATCHES = [
  // 1. Фотография уменьшается до карточки ГРУБО: drawImage по умолчанию
  //    берёт «низкое» сглаживание, и снимок в 1280 точек, сжатый в карточку
  //    на 360, выходит зернистым. Браузерная <img> так не делает — отсюда
  //    «на доске Excalidraw фото хуже, чем на старой». Просим «высокое».
  { name: 'сглаживание фото', re: /;([\w$]+)\.drawImage\(([\w$]+),([\w$]+),([\w$]+),([\w$]+),([\w$]+),0,0,([\w$]+)\.width,\7\.height\)/g,
    to: ';$1.imageSmoothingQuality="high";$1.drawImage($2,$3,$4,$5,$6,0,0,$7.width,$7.height)', n: 1 },
  // 2–3. Тёмная тема Excalidraw — это фильтр «вывернуть цвета» на холсте,
  //    а фотографии он выворачивает обратно, неточно: насыщенный цвет через
  //    два поворота оттенка не проходит в принципе (промежуточные значения
  //    обрезаются). Замер: (200, 60, 40) показывался как (187, 82, 60).
  //    Холст больше НЕ выворачиваем: оформление остаётся тёмным, а на
  //    холсте рисуется ровно то, что лежит в элементе (фон холста тёмный,
  //    см. ExcBoard). CSS-половина — `--theme-filter: none` в index.html.
  { name: 'фильтр холста', str: '"invert(93%) hue-rotate(180deg)"', to: '"none"', n: 1 },
  { name: 'фильтр фото', str: '"invert(100%) hue-rotate(180deg) saturate(1.25)"', to: '"none"', n: 1 },
  // 4. Раз холст не выворачивается, «чёрный» карандаш обязан быть светлым:
  //    раньше он и был светлым на экране — через тот же фильтр. Меняем
  //    местами чёрный и белый: первый цвет палитры — светлый, а тёмный
  //    остаётся для письма поверх светлых стикеров.
  { name: 'чёрный и белый', str: 'black:"#1e1e1e",white:"#ffffff"', to: 'black:"#f0eee6",white:"#1e1e1e"', n: 1 },
  // 5. Быстрые цвета обводки — светлые ступени (2 из 0…4), а не тёмные (4):
  //    на тёмном холсте тёмно-синий не читается. Ровно так они и выглядели
  //    в прежней тёмной теме.
  { name: 'ступень обводки', re: /=5,([\w$]+)=5,([\w$]+)=4,([\w$]+)=4,([\w$]+)=1,([\w$]+)=\[0,2,4,6,8\]/g,
    to: '=5,$1=5,$2=4,$3=2,$4=1,$5=[0,2,4,6,8]', n: 1 },
  // 6. Быстрые заливки — тёмные оттенки вместо пастели: светлая надпись
  //    на розовом не читается. В прежней тёмной теме пастель и выглядела
  //    тёмной — фильтр выворачивал и её.
  { name: 'заливки', re: /=\[([\w$]+)\.transparent,\1\.red\[([\w$]+)\],\1\.green\[\2\],\1\.blue\[\2\],\1\.yellow\[\2\]\]/g,
    to: '=[$1.transparent,"#4a2c28","#27402c","#22354d","#4a3f1e"]', n: 1 },
];
const patcher = {
  name: 'cf-patches',
  setup(b) {
    const hits = PATCHES.map(() => 0);
    b.onLoad({ filter: /[\\/]@excalidraw[\\/]excalidraw[\\/]dist[\\/]prod[\\/].*\.js$/ }, a => {
      let src = fs.readFileSync(a.path, 'utf8');
      PATCHES.forEach((p, i) => {
        if (p.str) { const parts = src.split(p.str); hits[i] += parts.length - 1; src = parts.join(p.to); }
        else src = src.replace(p.re, (...m) => { hits[i]++; return m[0].replace(new RegExp(p.re.source), p.to); });
      });
      return { contents: src, loader: 'js' };
    });
    b.onEnd(() => {
      const bad = PATCHES.filter((p, i) => hits[i] !== p.n).map((p, i) => `${p.name}: ${hits[PATCHES.indexOf(p)]} вместо ${p.n}`);
      if (bad.length) throw new Error('правки поверх Excalidraw не сошлись: ' + bad.join('; '));
      console.log('правки:', PATCHES.map((p, i) => `${p.name} ×${hits[i]}`).join(', '));
    });
  },
};
const globals = {
  name: 'cf-globals',
  setup(b) {
    b.onResolve({ filter: /^@excalidraw\/mermaid-to-excalidraw$/ }, () => ({ path: 'mermaid', namespace: 'cf' }));
    b.onResolve({ filter: /^(react|react-dom|react-dom\/client|react\/jsx-runtime)$/ }, a => ({ path: a.path, namespace: 'cf' }));
    b.onLoad({ filter: /.*/, namespace: 'cf' }, a => ({ contents: shims[a.path], loader: 'js' }));
  },
};
fs.writeFileSync(path.join(tmp, 'entry.js'), "export * from '@excalidraw/excalidraw';\n");
await esbuild.build({
  entryPoints: [path.join(tmp, 'entry.js')], absWorkingDir: tmp,
  bundle: true, format: 'iife', globalName: 'ExcalidrawLib', minify: true, target: 'es2020',
  outfile: path.join(here, `excalidraw-${VERSION}-${CF_BUILD}.min.js`), plugins: [globals, patcher],
  define: { 'process.env.NODE_ENV': '"production"' },
  banner: { js: `/* Excalidraw ${VERSION} (MIT, excalidraw.com) + правки CineFlow ${CF_BUILD} — собрано vendor/excalidraw/build.mjs; React берётся из window.React */` },
  logLevel: 'warning',
});
const dist = path.join(tmp, 'node_modules/@excalidraw/excalidraw/dist/prod');
fs.copyFileSync(path.join(dist, 'index.css'), path.join(here, `excalidraw-${VERSION}.css`));
// Шрифты — рядом с файлом стилей: он ссылается на ./fonts/… Китайский
// Xiaolai (13 МБ) не берём — без него иероглифы уйдут в системный шрифт.
fs.rmSync(path.join(here, 'fonts'), { recursive: true, force: true });
fs.cpSync(path.join(dist, 'fonts'), path.join(here, 'fonts'), {
  recursive: true, filter: src => !src.includes(`${path.sep}Xiaolai`),
});
console.log('готово:', fs.readdirSync(here).join(', '));
