// Сборка живого редактора заметок (Tiptap) в ОДИН готовый файл для CineFlow.
//
// Сборщика у приложения нет и не будет: этот скрипт запускают ОДИН раз,
// когда меняют версию, а результат лежит в репозитории готовым — так же,
// как Excalidraw в vendor/excalidraw и three.js у игры. Tiptap раздаётся
// только модулями, обычным тегом <script> его не подключить; здесь он
// собирается в самостоятельный файл, который кладёт всё в window.CFTiptap.
//
// React сюда НЕ входит: редактор живёт в обычном узле страницы, и
// приложение управляет им через ссылку, а не через @tiptap/react.
//
// Запуск из корня репозитория:   node vendor/tiptap/build.mjs
// Меняешь версию — правь TIPTAP_FILE в index.html, VENDOR в sw.js
// и подними там VERSION: service worker отдаёт файл из кэша.
import { execSync } from 'child_process';
import fs from 'fs';
import os from 'os';
import path from 'path';
import { fileURLToPath, pathToFileURL } from 'url';

const VERSION = '3.33.0';
const here = path.dirname(fileURLToPath(import.meta.url));
const tmp = path.join(os.tmpdir(), 'cf-tiptap-build');
fs.mkdirSync(tmp, { recursive: true });
if (!fs.existsSync(path.join(tmp, 'package.json'))) fs.writeFileSync(path.join(tmp, 'package.json'), '{"private":true}');
const pk = ['core', 'starter-kit', 'extension-list', 'extensions', 'pm'].map(p => `@tiptap/${p}@${VERSION}`).join(' ');
execSync(`npm i --no-audit --no-fund ${pk} esbuild`, { cwd: tmp, stdio: 'inherit' });
const esbuild = await import(pathToFileURL(path.join(tmp, 'node_modules/esbuild/lib/main.js')).href);

fs.writeFileSync(path.join(tmp, 'entry.js'), `
export { Editor, Node, Mark, Extension, textblockTypeInputRule, mergeAttributes } from '@tiptap/core';
export { StarterKit } from '@tiptap/starter-kit';
export { TaskList, TaskItem } from '@tiptap/extension-list';
export { Placeholder } from '@tiptap/extensions';
`);
const out = path.join(here, `tiptap-${VERSION}.min.js`);
await esbuild.build({
  entryPoints: [path.join(tmp, 'entry.js')], bundle: true, minify: true, format: 'iife',
  globalName: 'CFTiptap', target: ['safari15', 'chrome100'], outfile: out, legalComments: 'none',
  absWorkingDir: tmp,
});
console.log('готово:', out, Math.round(fs.statSync(out).size / 1024), 'КБ');
