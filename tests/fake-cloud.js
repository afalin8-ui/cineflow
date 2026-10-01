// ПОДДЕЛЬНОЕ ОБЛАКО ДЛЯ СТЕНДА — ОДНО НА ВСЕ ПРОВЕРКИ.
//
// Настоящий Firebase в проверках ЗАБЛОКИРОВАН: иначе стенд писал бы
// в живой проект пользователя. Вместо него это — ровно то, чем
// пользуется приложение: коллекции комнаты, подписки и запись
// документа. Всё, что уезжает наружу, ложится в журнал `__cfWrites`:
// «открыта ли дверь ровно на одну коллекцию» на глаз не видно.
//
// Вторую копию заводить нельзя: она разошлась бы с первой при первой
// же правке, и половина проверок стала бы зелёной при сломанном коде.
//
// Ставится так:  await ctx.addInitScript(FAKE_CLOUD, seed)
// где seed — что УЖЕ лежит в комнате: {коллекция: {id: документ}}.
// Непустая коллекция на первом ответе означает «комната не новая»,
// и приложение её не засевает — то есть данные видны ровно те,
// что положили здесь.
const FAKE_CLOUD = (seed) => {
  // КОМНАТЫ. Коллекции первой комнаты, к которой обратилось приложение,
  // лежат под своими именами (так засеивают и читают все проверки), а
  // любой другой комнаты — под «комната|коллекция». Нужно переезду.
  // `sessionStorage.__cfPersist = '1'` сохраняет облако между
  // перезагрузками страницы — иначе переход в новую комнату нечем
  // проверить: подделка заводилась бы заново из засева.
  const persist = (() => { try { return sessionStorage.getItem('__cfPersist') === '1'; } catch (e) { return false; } })();
  let kept = null;
  try { kept = persist ? JSON.parse(sessionStorage.getItem('__cfStore') || 'null') : null; } catch (e) {}
  const store = kept ? kept.store : JSON.parse(JSON.stringify(seed || {})), subs = {}, dsubs = {};
  let room0 = kept ? kept.room0 : null;
  const save = () => { if (persist) try { sessionStorage.setItem('__cfStore', JSON.stringify({ store, room0 })); } catch (e) {} };
  const keyOf = (room, name) => {
    if (room == null) return name;
    if (room0 == null) { room0 = room; save(); }
    return room === room0 ? name : room + '|' + name;
  };
  window.__cfStore = store;
  window.__cfWrites = [];
  const clone = (v) => JSON.parse(JSON.stringify(v));
  // Запрос `where(поле, '==', значение)` — им доска Excalidraw читает
  // свои элементы. `__cfCacheOnly[коллекция]` изображает оборванную связь:
  // ответ приходит «из кэша устройства» и пустой, как у только что
  // открытого без сети приложения.
  window.__cfCacheOnly = {};
  // `orderBy(поле, 'desc').limit(n)` — им приложение берёт хвост чата.
  const snapOf = (coll, filter, ord) => {
    const cacheOnly = !!window.__cfCacheOnly[coll];
    const obj = cacheOnly ? {} : (store[coll] || {});
    let ids = Object.keys(obj).filter(id => !filter || (obj[id] && obj[id][filter.f] === filter.v));
    if (ord && ord.f) {
      ids = ids.filter(id => obj[id] && obj[id][ord.f] !== undefined)
               .sort((a, b) => (obj[a][ord.f] < obj[b][ord.f] ? -1 : 1) * (ord.dir === 'desc' ? -1 : 1));
    }
    if (ord && ord.n) ids = ids.slice(0, ord.n);
    return {
      empty: ids.length === 0, size: ids.length,
      metadata: { fromCache: cacheOnly, hasPendingWrites: false },
      forEach: (f) => ids.forEach(id => f({ id, data: () => obj[id] })),
      docChanges: () => ids.map(id => ({ type: 'added', doc: { id, data: () => obj[id] } }))
    };
  };
  const dsnap = (coll, id) => ({ id, exists: !!((store[coll] || {})[id]), data: () => (store[coll] || {})[id] });
  const emit = (coll, id) => {
    (subs[coll] || []).forEach(fn => { try { fn(); } catch (e) {} });
    ((dsubs[coll] || {})[id] || []).forEach(cb => { try { cb(dsnap(coll, id)); } catch (e) {} });
  };
  const put = (coll, id, data) => {
    window.__cfWrites.push({ coll, id });
    (store[coll] = store[coll] || {})[id] = clone(data);
    save();
    emit(coll, id);
  };
  const docRef = (coll, id, room) => ({
    id,
    get: () => Promise.resolve(dsnap(coll, id)),
    set: (data) => { put(coll, id, data); return Promise.resolve(); },
    update: (data) => { put(coll, id, data); return Promise.resolve(); },
    delete: () => { window.__cfWrites.push({ coll, id, del: true }); if (store[coll]) delete store[coll][id]; save(); emit(coll, id); return Promise.resolve(); },
    onSnapshot: (cb) => {
      const m = dsubs[coll] = dsubs[coll] || {}; (m[id] = m[id] || []).push(cb);
      setTimeout(() => { try { cb(dsnap(coll, id)); } catch (e) {} }, 30);
      return () => {};
    },
    collection: (name) => collRef(name, coll === 'artifacts' ? id : room)
  });
  const query = (name, filter, ord) => ({
    get: () => Promise.resolve(snapOf(name, filter, ord)),
    orderBy: (f, dir) => query(name, filter, { ...(ord || {}), f, dir }),
    limit: (n) => query(name, filter, { ...(ord || {}), n }),
    onSnapshot: (cb) => {
      const fn = () => cb(snapOf(name, filter, ord));
      (subs[name] = subs[name] || []).push(fn);
      setTimeout(() => { try { fn(); } catch (e) {} }, 30);
      return () => { subs[name] = (subs[name] || []).filter(x => x !== fn); };
    }
  });
  const collRef = (name, room) => {
    // Служебные звенья пути (artifacts → комната → public → data) — не
    // коллекции проекта, их имена в ключ не идут.
    const k = (name === 'artifacts' || name === 'public') ? name : keyOf(room, name);
    return {
      doc: (id) => docRef(k, id, room),
      ...query(k, null),
      where: (f, op, v) => query(k, { f, v })
    };
  };
  window.__cfEmit = (coll) => emit(coll, '');
  const db = {
    collection: (name) => collRef(name),
    settings: () => {},
    enablePersistence: () => Promise.resolve(),
    waitForPendingWrites: () => Promise.resolve(),
    disableNetwork: () => Promise.resolve(),
    enableNetwork: () => Promise.resolve(),
    terminate: () => Promise.resolve(),
    clearPersistence: () => Promise.resolve(),
    batch: () => {
      const ops = [];
      return { set: (r, d) => ops.push(() => r.set(d)), delete: (r) => ops.push(() => r.delete()),
               commit: () => { ops.forEach(f => f()); return Promise.resolve(); } };
    }
  };
  const user = { uid: 'guest-anon' };
  const fb = {
    apps: [],
    initializeApp: () => { fb.apps.push({}); },
    firestore: () => db,
    auth: () => ({
      currentUser: user,
      signInAnonymously: () => Promise.resolve({ user }),
      onAuthStateChanged: (cb) => { setTimeout(() => cb(user), 10); return () => {}; }
    })
  };
  window.firebase = fb;
};

module.exports = { FAKE_CLOUD };
