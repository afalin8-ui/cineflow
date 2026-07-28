/* ВНЕШНИЕ МОДЕЛИ.

   По умолчанию корабли и техника собираются из примитивов (models.js).
   Но если положить готовую модель в game/models/ и вписать её в
   game/models/manifest.json — игра возьмёт её вместо процедурной.

   Формат: .glb (glTF binary) с вшитыми текстурами. Именно так отдают
   Prism / Meshy / Tripo и любой экспорт из Blender.

   Игра сама приводит модель к нужному размеру и ставит на неё точки
   оружия, ПВО и двигателей, так что от модели требуется только
   корпус. Если модель повёрнута не туда — правится в манифесте,
   не в коде. */

import { THREE } from './engine.js';
import { GLTFLoader } from '../vendor/GLTFLoader.js';

const BASE = new URL('../models/', import.meta.url);
const library = new Map();     // ключ → подготовленная THREE.Group
let manifest = null;

// Ключи, которые понимает игра:
//   ship:<клан>:<escort|cruiser|carrier|capital|station>
//   strike:<клан>:<interceptor|fighter|bomber>
//   ground:<клан>:<worker|rifle|rocket|tank|aa|arty|jet>
//   building:<клан>:<hq|barracks|factory|airfield|turret|sam>
// Вместо клана можно написать any — модель пойдёт всем трём кланам.

export async function loadModelLibrary() {
  try {
    const res = await fetch(new URL('manifest.json', BASE), { cache: 'no-cache' });
    if (!res.ok) return 0;
    manifest = await res.json();
  } catch (e) {
    return 0;   // манифеста нет — работаем на примитивах, это норма
  }
  const entries = Object.entries(manifest.models || {});
  if (!entries.length) return 0;

  const loader = new GLTFLoader();
  let ok = 0;
  await Promise.all(entries.map(async ([key, spec]) => {
    const cfg = typeof spec === 'string' ? { file: spec } : spec;
    if (!cfg || !cfg.file) return;
    try {
      const gltf = await loader.loadAsync(new URL(cfg.file, BASE).href);
      library.set(key, prepare(gltf.scene, cfg));
      ok++;
    } catch (e) {
      console.warn(`Модель «${key}» не загрузилась (${cfg.file}):`, e.message);
    }
  }));
  return ok;
}

// Приводим загруженную модель к общему знаменателю: центр в нуле,
// нос в −Z, длина 1. Дальше игра просто масштабирует её под класс.
function prepare(root, cfg) {
  const holder = new THREE.Group();
  const inner = new THREE.Group();
  holder.add(inner);
  inner.add(root);

  // Разворот из манифеста — в градусах, чтобы правилось руками
  const r = cfg.rotate || [0, 0, 0];
  root.rotation.set(
    THREE.MathUtils.degToRad(r[0]),
    THREE.MathUtils.degToRad(r[1]),
    THREE.MathUtils.degToRad(r[2]),
  );
  root.updateMatrixWorld(true);

  const box = new THREE.Box3().setFromObject(root);
  const size = box.getSize(new THREE.Vector3());
  const center = box.getCenter(new THREE.Vector3());
  root.position.sub(center);
  if (cfg.groundLevel) root.position.y += size.y / 2;   // здания стоят на земле

  const longest = Math.max(size.x, size.y, size.z) || 1;
  const k = (cfg.scale || 1) / longest;
  inner.scale.setScalar(k);

  holder.userData.extent = size.clone().multiplyScalar(k);
  holder.userData.custom = true;

  root.traverse(o => {
    if (!o.isMesh) return;
    o.frustumCulled = true;
    // Клоны делят геометрию и материалы с оригиналом, поэтому помечаем их
    // общими — иначе уборка сцены после боя убьёт модель для всех боёв.
    if (o.geometry) o.geometry.userData.shared = true;
    if (o.material) {
      const mats = Array.isArray(o.material) ? o.material : [o.material];
      for (const m of mats) {
        m.userData.shared = true;
        if (m.map) m.map.colorSpace = THREE.SRGBColorSpace;
        m.side = THREE.FrontSide;
      }
    }
  });
  return holder;
}

export function hasCustom(key, faction) {
  return !!(library.get(`${key}:${faction}`) || library.get(`${key}:any`));
}

// Возвращает готовый к вставке клон или null
export function customModel(kind, faction, id) {
  const src = library.get(`${kind}:${faction}:${id}`) || library.get(`${kind}:any:${id}`);
  if (!src) return null;
  const g = src.clone(true);
  g.userData.extent = src.userData.extent.clone();
  g.userData.custom = true;
  return g;
}

export function modelCount() { return library.size; }
