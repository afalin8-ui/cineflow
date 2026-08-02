/* Service worker игры. Область — папка /game/, поэтому он не пересекается
   с service worker'ом CineFlow, который живёт в корне репозитория.
   Задача простая: игра целиком лежит рядом (three.js вшит в vendor/),
   так что после первого запуска она работает без интернета. */

const VERSION = 'capella-v25';
const CACHE = VERSION;

const SHELL = [
  './',
  './index.html',
  './style.css',
  './manifest.webmanifest',
  './icon.svg',
  './vendor/three.module.min.js',
  './vendor/GLTFLoader.js',
  './vendor/BufferGeometryUtils.js',
  './vendor/EffectComposer.js',
  './vendor/Pass.js',
  './vendor/RenderPass.js',
  './vendor/ShaderPass.js',
  './vendor/MaskPass.js',
  './vendor/UnrealBloomPass.js',
  './vendor/OutputPass.js',
  './vendor/CopyShader.js',
  './vendor/LuminosityHighPassShader.js',
  './vendor/OutputShader.js',
  './js/main.js',
  './js/assets.js',
  './js/noise.js',
  './js/textures.js',
  './js/engine.js',
  './js/data.js',
  './js/models.js',
  './js/space.js',
  './js/ground.js',
  './js/galaxy.js',
];

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    await Promise.allSettled(SHELL.map(async url => {
      try {
        const res = await fetch(url, { cache: 'reload' });
        if (res && res.ok) await cache.put(url, res);
      } catch (e) { /* доберём во время работы */ }
    }));
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter(k => k.startsWith('capella-') && k !== CACHE).map(k => caches.delete(k)));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', event => {
  const req = event.request;
  if (req.method !== 'GET') return;
  let url;
  try { url = new URL(req.url); } catch (e) { return; }
  if (url.origin !== self.location.origin) return;

  // Страница и модули: сначала сеть (чтобы приезжали обновления),
  // без связи — из кэша.
  event.respondWith((async () => {
    try {
      const fresh = await fetch(req, { cache: 'no-cache' });
      if (fresh && fresh.ok) {
        const cache = await caches.open(CACHE);
        cache.put(req, fresh.clone());
      }
      return fresh;
    } catch (e) {
      const hit = await caches.match(req);
      if (hit) return hit;
      if (req.mode === 'navigate') {
        const idx = await caches.match('./index.html');
        if (idx) return idx;
      }
      return Response.error();
    }
  })());
});
