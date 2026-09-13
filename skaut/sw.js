/* Заглушка вместо service worker'а тестовой папки /skaut/.
   Скаут уехал в рабочее приложение, копия «на посмотреть» больше не нужна.
   Файл оставлен НАМЕРЕННО: у того, кто открывал копию, её service worker
   уже установлен, и удаление файла его бы не сняло — он продолжал бы
   отдавать старую сборку из кэша, молча и без единой ошибки. Эта версия
   снимает себя сама и стирает ТОЛЬКО свои кэши: кэши рабочего приложения
   начинаются иначе, и снести их значило бы отобрать у него офлайн. */
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter(k => k.startsWith('cineflow-skaut') || k === 'cf-app-build-skaut')
                          .map(k => caches.delete(k)));
    await self.registration.unregister();
    const wins = await self.clients.matchAll({ type: 'window' });
    wins.forEach(c => { try { c.navigate(c.url); } catch (e) {} });
  })());
});
