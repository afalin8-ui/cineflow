#!/usr/bin/env node
/*
 * Готовит содержимое приложения: кладёт пульт в www/ вместе с библиотеками,
 * чтобы внутри приложения он работал полностью без интернета.
 *
 * Запуск:  node prepare-www.js
 * Зависимостей нет — нужен только Node.js.
 */
const fs = require('fs');
const path = require('path');
const https = require('https');

const ROOT = path.join(__dirname, '..');
const WWW = path.join(__dirname, 'www');
const VENDOR_OUT = path.join(WWW, 'vendor');

/* Те же библиотеки, что подменяет мост, — держим списки одинаковыми. */
const VENDOR = [
    { file: 'react.js', url: 'https://unpkg.com/react@18/umd/react.production.min.js' },
    { file: 'react-dom.js', url: 'https://unpkg.com/react-dom@18/umd/react-dom.production.min.js' },
    { file: 'babel.js', url: 'https://unpkg.com/@babel/standalone/babel.min.js' },
    { file: 'tailwind.js', url: 'https://cdn.tailwindcss.com' }
];

function download(url, dest, cb, hops) {
    if ((hops || 0) > 5) return cb(new Error('слишком много перенаправлений'));
    https.get(url, { headers: { 'User-Agent': 'CineLight-Build' } }, r => {
        if (r.statusCode >= 300 && r.statusCode < 400 && r.headers.location) {
            r.resume();
            let next;
            try { next = new URL(r.headers.location, url).toString(); }
            catch (e) { return cb(new Error('плохой адрес перенаправления')); }
            return download(next, dest, cb, (hops || 0) + 1);
        }
        if (r.statusCode !== 200) { r.resume(); return cb(new Error('код ' + r.statusCode)); }
        const chunks = [];
        r.on('data', c => chunks.push(c));
        r.on('end', () => {
            try { fs.writeFileSync(dest, Buffer.concat(chunks)); cb(null); }
            catch (e) { cb(e); }
        });
    }).on('error', cb);
}

function copyOrFetch(v, cb) {
    const dest = path.join(VENDOR_OUT, v.file);
    // если мост уже качал их раньше — просто берём оттуда, без интернета
    const cached = path.join(ROOT, 'cinelight-vendor', v.file);
    try {
        if (fs.statSync(cached).size > 1000) {
            fs.copyFileSync(cached, dest);
            console.log('  взято из cinelight-vendor: ' + v.file);
            return cb(null);
        }
    } catch (e) {}
    download(v.url, dest, err => {
        console.log(err ? '  НЕ СКАЧАЛОСЬ: ' + v.file + ' — ' + err.message : '  скачано: ' + v.file);
        cb(err);
    });
}

const src = path.join(ROOT, 'cinelight.html');
if (!fs.existsSync(src)) {
    console.error('Не найден cinelight.html рядом с папкой app/. Запускайте из репозитория целиком.');
    process.exit(1);
}

fs.mkdirSync(VENDOR_OUT, { recursive: true });

let left = VENDOR.length, bad = false;
VENDOR.forEach(v => copyOrFetch(v, err => {
    if (err) bad = true;
    if (--left > 0) return;
    if (bad) {
        console.error('\nНе все библиотеки собраны — приложение не будет работать без интернета.');
        process.exit(1);
    }
    // подменяем ссылки на локальные файлы и убираем шрифты из сети
    let html = fs.readFileSync(src, 'utf8');
    VENDOR.forEach(v => { html = html.split(v.url).join('vendor/' + v.file); });
    html = html.replace(/<link[^>]*fonts\.(googleapis|gstatic)\.com[^>]*>/g, '');
    fs.writeFileSync(path.join(WWW, 'index.html'), html);
    const size = fs.statSync(path.join(WWW, 'index.html')).size;
    console.log('\nГотово: www/index.html (' + Math.round(size / 1024) + ' КБ) + www/vendor/');
    console.log('Дальше:  npx cap sync ios');
}));
