/*
 * Собирает папку cinelight-repo/ — готовое содержимое отдельного репозитория
 * CineLight: пульт, мост, запускалка, конвертер библиотеки, проект приложения
 * для iPad и заметки.
 *
 * Запуск:  node cinelight-export.js
 * (на Windows проще двойным щелчком по cinelight-export.bat)
 *
 * Файлы копируются побайтно — .bat остаётся в CRLF и CP866, как требует cmd.exe.
 */

const fs = require('fs');
const path = require('path');

const SRC = __dirname;
const OUT = path.join(SRC, 'cinelight-repo');

// откуда → куда внутри нового репозитория
const FILES = [
  ['cinelight.html', 'cinelight.html'],
  ['cinelight-bridge.js', 'cinelight-bridge.js'],
  ['cinelight-bridge.bat', 'cinelight-bridge.bat'],
  ['tools-build-fixture-library.js', 'tools-build-fixture-library.js'],
  ['.gitattributes', '.gitattributes'],

  ['app/package.json', 'app/package.json'],
  ['app/capacitor.config.json', 'app/capacitor.config.json'],
  ['app/prepare-www.js', 'app/prepare-www.js'],
  ['app/README.md', 'app/README.md'],

  // сборка iPad-приложения обязана лежать именно по этому пути
  ['app/github-workflow-ios.yml', '.github/workflows/ios.yml'],

  // заметки, написанные специально для отдельного репозитория
  ['cinelight-newrepo/README.md', 'README.md'],
  ['cinelight-newrepo/CLAUDE.md', 'CLAUDE.md'],
  ['cinelight-newrepo/gitignore.txt', '.gitignore'],
];

function rmrf(p) {
  if (fs.existsSync(p)) fs.rmSync(p, { recursive: true, force: true });
}

function copy(from, to) {
  const src = path.join(SRC, from);
  if (!fs.existsSync(src)) throw new Error('не найден файл ' + from);
  const dst = path.join(OUT, to);
  fs.mkdirSync(path.dirname(dst), { recursive: true });
  fs.copyFileSync(src, dst);           // побайтно, без «поправок» переводов строк
  return fs.statSync(dst).size;
}

rmrf(OUT);
fs.mkdirSync(OUT, { recursive: true });

let total = 0;
for (const [from, to] of FILES) {
  const size = copy(from, to);
  total += size;
  console.log('  ' + to.padEnd(38) + (size / 1024).toFixed(1).padStart(8) + ' КБ');
}

// проверка: .bat должен остаться windows-овским
const bat = fs.readFileSync(path.join(OUT, 'cinelight-bridge.bat'));
if (!bat.includes(Buffer.from('\r\n'))) throw new Error('cinelight-bridge.bat потерял переводы строк Windows');

console.log('');
console.log('Готово: ' + FILES.length + ' файлов, ' + (total / 1024 / 1024).toFixed(2) + ' МБ');
console.log('Папка: ' + OUT);
console.log('');
console.log('Что дальше — два способа, любой на выбор.');
console.log('');
console.log('СПОСОБ 1 (без командной строки)');
console.log('  Открыть пустой репозиторий cinelight на github.com,');
console.log('  нажать «uploading an existing file» и перетащить туда');
console.log('  СОДЕРЖИМОЕ папки cinelight-repo (не саму папку).');
console.log('  Windows прячет папку .github — включите показ скрытых файлов,');
console.log('  иначе сборка приложения для iPad не переедет.');
console.log('');
console.log('СПОСОБ 2 (если установлен git)');
console.log('  cd "' + OUT + '"');
console.log('  git init -b main');
console.log('  git add .');
console.log('  git commit -m "CineLight"');
console.log('  git remote add origin https://github.com/afalin8-ui/cinelight');
console.log('  git push -u origin main');
