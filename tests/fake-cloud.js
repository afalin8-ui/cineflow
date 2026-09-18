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
  const store = JSON.parse(JSON.stringify(seed || {})), subs = {}, dsubs = {};
  window.__cfStore = store;
  window.__cfWrites = [];
  const clone = (v) => JSON.parse(JSON.stringify(v));
  const snapOf = (coll) => {
    const obj = store[coll] || {}; const ids = Object.keys(obj);
    return {
      empty: ids.length === 0, size: ids.length,
      forEach: (f) => ids.forEach(id => f({ id, data: () => obj[id] })),
      docChanges: () => ids.map(id => ({ type: 'added', doc: { id, data: () => obj[id] } }))
    };
  };
  const dsnap = (coll, id) => ({ id, exists: !!((store[coll] || {})[id]), data: () => (store[coll] || {})[id] });
  const emit = (coll, id) => {
    (subs[coll] || []).forEach(cb => { try { cb(snapOf(coll)); } catch (e) {} });
    ((dsubs[coll] || {})[id] || []).forEach(cb => { try { cb(dsnap(coll, id)); } catch (e) {} });
  };
  const put = (coll, id, data) => {
    window.__cfWrites.push({ coll, id });
    (store[coll] = store[coll] || {})[id] = clone(data);
    emit(coll, id);
  };
  const docRef = (coll, id) => ({
    id,
    get: () => Promise.resolve(dsnap(coll, id)),
    set: (data) => { put(coll, id, data); return Promise.resolve(); },
    update: (data) => { put(coll, id, data); return Promise.resolve(); },
    delete: () => { window.__cfWrites.push({ coll, id, del: true }); if (store[coll]) delete store[coll][id]; emit(coll, id); return Promise.resolve(); },
    onSnapshot: (cb) => {
      const m = dsubs[coll] = dsubs[coll] || {}; (m[id] = m[id] || []).push(cb);
      setTimeout(() => { try { cb(dsnap(coll, id)); } catch (e) {} }, 30);
      return () => {};
    },
    collection: (name) => collRef(name)
  });
  const collRef = (name) => ({
    doc: (id) => docRef(name, id),
    get: () => Promise.resolve(snapOf(name)),
    onSnapshot: (cb) => {
      (subs[name] = subs[name] || []).push(cb);
      setTimeout(() => { try { cb(snapOf(name)); } catch (e) {} }, 30);
      return () => {};
    }
  });
  const db = {
    collection: collRef,
    settings: () => {},
    enablePersistence: () => Promise.resolve(),
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
