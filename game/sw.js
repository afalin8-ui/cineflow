/* Service worker игры. Область — папка /game/, поэтому он не пересекается
   с service worker'ом CineFlow, который живёт в корне репозитория.
   Задача простая: игра целиком лежит рядом (three.js вшит в vendor/),
   так что после первого запуска она работает без интернета.

   ОБНОВЛЕНИЯ (C121). Все свои файлы — страница, модули, модели —
   берутся «сначала сеть» с cache: 'no-cache': браузер спрашивает
   сервер «не поменялось ли» (ответ 304 стоит копейки), а не отдаёт
   копию из своего кэша, которую GitHub Pages разрешает держать
   10 минут.
   Этого МАЛО, и ответ странице уходит с заголовком Cache-Control:
   no-cache (revalidating). Chromium держит модули и стили в кэше
   ПАМЯТИ вкладки и на F5 берёт их оттуда, не спрашивая service
   worker вовсе, пока копия «свежая» по её заголовку — а он у GitHub
   Pages max-age=600. Замер: после выкладки F5, второй F5 и переход
   через about:blank давали СТАРЫЙ main.js, в журнале сервера его
   запросов не было ни одного; новое приходило только в новой вкладке
   или через десять минут. С заголовком no-cache правка приходит на
   первом же F5.
   VERSION поднимать всё равно надо: он перезаливает офлайн-набор
   SHELL и чистит старый кэш, а смена самого service worker'а заодно
   сбрасывает кэш памяти, накопленный при прежнем. */

const VERSION = 'capella-v31';
const CACHE = VERSION;

/* Ответ странице — с перепроверкой (см. шапку). Ответ после
   перенаправления не трогаем: у модуля по адресу ответа считаются его
   import'ы, а у собранного заново ответа адреса нет вовсе. */
function revalidating(res) {
  if (!res || !res.ok || res.type !== 'basic' || res.redirected) return res;
  const h = new Headers(res.headers);
  h.set('Cache-Control', 'no-cache');
  return new Response(res.body, { status: res.status, statusText: res.statusText, headers: h });
}

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
  './js/hangar.js',
  './vendor/DRACOLoader.js',
  './vendor/meshopt_decoder.module.js',
  // Внешние модели и сканы обшивки и грунта: без них офлайн корабли
  // и земля собирались бы на заглушках
  './models/manifest.json',
  './models/troyden_cruiser.glb',
  './models/troyden_corvette.glb',
  './planets/manifest.json',
  './textures/hull_diff.jpg', './textures/hull_nor.jpg',
  './textures/grass_diff.jpg', './textures/grass_nor.jpg',
  './textures/dirt_diff.jpg', './textures/dirt_nor.jpg',
  './textures/cliff_diff.jpg', './textures/cliff_nor.jpg',
  './textures/rock_diff.jpg', './textures/rock_nor.jpg',
  './textures/sand_diff.jpg', './textures/sand_nor.jpg',
  './textures/snow_diff.jpg', './textures/snow_nor.jpg',
];

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    await Promise.allSettled(SHELL.map(async url => {
      try {
        // no-cache, а не reload: файл, только что скачанный страницей,
        // перепроверяется ответом 304, а не качается второй раз
        const res = await fetch(url, { cache: 'no-cache' });
        if (res && res.ok) await cache.put(url, revalidating(res));
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
      const fresh = revalidating(await fetch(req, { cache: 'no-cache' }));
      if (fresh && fresh.ok && !fresh.redirected) {
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
