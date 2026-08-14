/* CineFlow Prep — service worker.
   Задача: приложение должно открываться и работать без интернета.
   Сам код (React, Firebase SDK, Tailwind и т.д.) грузится с CDN,
   поэтому без кэша офлайн не открылась бы даже пустая страница.

   ВАЖНО: запросы самого Firestore/Auth здесь НЕ трогаются — у них
   свой офлайн-механизм (IndexedDB + очередь правок). Если их
   перехватывать или кэшировать, живая синхронизация сломается. */

const VERSION = 'cineflow-v5';
const APP_CACHE = VERSION + '-app';
const LIB_CACHE = VERSION + '-lib';
const FONT_CACHE = VERSION + '-font';

// Оболочка приложения (относительные пути — работает и на localhost,
// и в подпапке вида /cineflow/ на GitHub Pages)
const APP_SHELL = ['./', './index.html', './manifest.webmanifest', './icon.svg'];

// Библиотеки с CDN. Ссылки версионные и неизменяемые, поэтому кэшируем
// их «навсегда» и отдаём из кэша не спрашивая сеть.
const LIBS = [
  'https://cdn.tailwindcss.com',
  'https://unpkg.com/react@18/umd/react.production.min.js',
  'https://unpkg.com/react-dom@18/umd/react-dom.production.min.js',
  'https://unpkg.com/@babel/standalone/babel.min.js',
  'https://cdnjs.cloudflare.com/ajax/libs/xlsx/0.18.5/xlsx.full.min.js',
  'https://www.gstatic.com/firebasejs/10.8.0/firebase-app-compat.js',
  'https://www.gstatic.com/firebasejs/10.8.0/firebase-auth-compat.js',
  'https://www.gstatic.com/firebasejs/10.8.0/firebase-firestore-compat.js'
];

// Хосты, которые нельзя перехватывать (живой трафик Firebase)
const BYPASS_HOSTS = [
  'firestore.googleapis.com',
  'identitytoolkit.googleapis.com',
  'securetoken.googleapis.com',
  'firebaseinstallations.googleapis.com',
  'generativelanguage.googleapis.com' // запросы к Gemini тоже мимо кэша
];

// Кладём по одному: если какой-то CDN недоступен в момент установки,
// это не должно валить всю установку (в отличие от cache.addAll).
async function cacheAllSettled(cacheName, urls) {
  const cache = await caches.open(cacheName);
  await Promise.allSettled(urls.map(async url => {
    try {
      const res = await fetch(url, { cache: 'reload' });
      if (res && (res.ok || res.type === 'opaque')) { await cache.put(url, res); return; }
    } catch (e) { /* ниже пробуем no-cors */ }
    // Часть CDN (например cdn.tailwindcss.com) не отдаёт CORS-заголовки,
    // и обычный запрос отклоняется. Для тегов <script> без crossorigin
    // непрозрачного (opaque) ответа достаточно.
    try {
      const res = await fetch(new Request(url, { mode: 'no-cors', cache: 'reload' }));
      if (res) await cache.put(url, res);
    } catch (e) { /* пропускаем — доберём во время работы */ }
  }));
}

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    await cacheAllSettled(APP_CACHE, APP_SHELL);
    await cacheAllSettled(LIB_CACHE, LIBS);
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter(k => !k.startsWith(VERSION)).map(k => caches.delete(k)));
    await self.clients.claim();
  })());
});

// Позволяет странице попросить обновиться немедленно
self.addEventListener('message', event => {
  if (event.data === 'skip-waiting') self.skipWaiting();
});

self.addEventListener('fetch', event => {
  const req = event.request;
  if (req.method !== 'GET') return;

  let url;
  try { url = new URL(req.url); } catch (e) { return; }
  if (url.protocol !== 'http:' && url.protocol !== 'https:') return;
  if (BYPASS_HOSTS.some(h => url.hostname.endsWith(h))) return;

  // Папка /game/ — отдельное приложение («Капелла») со своим service
  // worker'ом. Не трогаем её вовсе: иначе навигация на игру подменит
  // в кэше './index.html' CineFlow на страницу игры.
  if (url.origin === self.location.origin && url.pathname.includes('/game/')) return;

  // Папка /proba/ — версия «на посмотреть» перед выкладыванием.
  // Не трогаем по той же причине, что и игру: обработчик навигации
  // ниже кладёт ЛЮБУЮ открытую страницу в кэш под именем './index.html',
  // и без этой строки проба подменила бы собой рабочее приложение
  // в офлайне.
  if (url.origin === self.location.origin && url.pathname.includes('/proba/')) return;

  // Сама страница: сначала сеть (чтобы приезжали обновления),
  // при отсутствии связи — версия из кэша.
  // cache:'reload' обязателен: иначе ответ может прийти из HTTP-кэша
  // браузера, и пользователь после обновления увидит старое приложение.
  if (req.mode === 'navigate') {
    event.respondWith((async () => {
      try {
        const fresh = await fetch(req.url, { cache: 'reload' });
        const cache = await caches.open(APP_CACHE);
        cache.put('./index.html', fresh.clone());
        return fresh;
      } catch (e) {
        const cache = await caches.open(APP_CACHE);
        return (await cache.match('./index.html')) || (await cache.match('./')) || Response.error();
      }
    })());
    return;
  }

  // index.html, запрошенный не как навигация (например проверка обновления):
  // тоже сначала сеть, иначе отдадим устаревшую копию.
  if (url.origin === self.location.origin && /\/index\.html$/.test(url.pathname)) {
    event.respondWith((async () => {
      try {
        const fresh = await fetch(req.url, { cache: 'reload' });
        const cache = await caches.open(APP_CACHE);
        cache.put('./index.html', fresh.clone());
        return fresh;
      } catch (e) {
        return (await caches.match('./index.html')) || Response.error();
      }
    })());
    return;
  }

  // Шрифты: отдаём из кэша сразу, в фоне обновляем.
  if (url.hostname === 'fonts.googleapis.com' || url.hostname === 'fonts.gstatic.com') {
    event.respondWith((async () => {
      const cache = await caches.open(FONT_CACHE);
      const hit = await cache.match(req);
      const network = fetch(req).then(res => {
        if (res && (res.ok || res.type === 'opaque')) cache.put(req, res.clone());
        return res;
      }).catch(() => null);
      return hit || (await network) || Response.error();
    })());
    return;
  }

  // Библиотеки и всё остальное: кэш вперёд, иначе сеть (и запоминаем).
  event.respondWith((async () => {
    const hit = await caches.match(req);
    if (hit) return hit;
    try {
      const res = await fetch(req);
      if (res && (res.ok || res.type === 'opaque')) {
        const isLib = LIBS.some(l => req.url.startsWith(l.split('?')[0]));
        const cache = await caches.open(isLib ? LIB_CACHE : APP_CACHE);
        cache.put(req, res.clone());
      }
      return res;
    } catch (e) {
      return Response.error();
    }
  })());
});
