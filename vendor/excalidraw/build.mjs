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
  outfile: path.join(here, `excalidraw-${VERSION}.min.js`), plugins: [globals],
  define: { 'process.env.NODE_ENV': '"production"' },
  banner: { js: `/* Excalidraw ${VERSION} (MIT, excalidraw.com) — собрано vendor/excalidraw/build.mjs для CineFlow; React берётся из window.React */` },
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
