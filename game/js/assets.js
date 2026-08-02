/* ВНЕШНИЕ МОДЕЛИ.

   По умолчанию корабли и техника собираются из примитивов (models.js).
   Но если положить готовую модель в game/models/ и вписать её в
   game/models/manifest.json — игра возьмёт её вместо процедурной.

   Формат: .glb (glTF binary) с вшитыми текстурами. Именно так отдают
   Prism / Meshy / Tripo и любой экспорт из Blender.

   Сжатие геометрии понимаем оба ходовых: Draco (его кладёт Blender
   при экспорте с галочкой «Compression») и meshopt (его кладут
   генераторы вроде Tripo). Без этих декодеров такие файлы просто
   не открывались — а это добрая половина всего, что скачивается
   в интернете, и заметить причину по картинке нельзя: модель молча
   не появляется.

   Игра сама приводит модель к нужному размеру и ставит на неё точки
   оружия, ПВО и двигателей, так что от модели требуется только
   корпус. Если модель повёрнута не туда — правится в манифесте,
   не в коде. */

import { THREE } from './engine.js';
import { GLTFLoader } from '../vendor/GLTFLoader.js';
import { DRACOLoader } from '../vendor/DRACOLoader.js';
import { MeshoptDecoder } from '../vendor/meshopt_decoder.module.js';

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
  loader.setMeshoptDecoder(MeshoptDecoder);
  const draco = new DRACOLoader();
  draco.setDecoderPath(new URL('../vendor/draco/', import.meta.url).href);
  loader.setDRACOLoader(draco);
  let ok = 0;
  await Promise.all(entries.map(async ([key, spec]) => {
    const cfg = typeof spec === 'string' ? { file: spec } : spec;
    if (!cfg || !cfg.file) return;
    try {
      const gltf = await loader.loadAsync(new URL(cfg.file, BASE).href);
      library.set(key, prepare(gltf.scene, cfg));
      ok++;
    } catch (e) {
      /* Сообщение важнее самой ошибки: чаще всего это либо не тот
         формат, либо текстуры лежат отдельным файлом рядом, а не
         внутри .glb. */
      const hint = /basisu|ktx/i.test(e.message || '')
        ? 'текстуры сжаты в KTX2 — пересохрани модель с обычными PNG/JPG'
        : /Unexpected|JSON|magic/i.test(e.message || '')
          ? 'файл не похож на .glb — проверь, что это именно glTF binary'
          : 'проверь, что файл лежит в game/models/ и путь в манифесте верный';
      console.warn(`Модель «${key}» не загрузилась (${cfg.file}): ${e.message}. ${hint}`);
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

/* ─────────────────────────────────────────────────────────────
   ТЕКСТУРЫ ПЛАНЕТ.

   Планеты — не модели, а картинки: равнопрямоугольная развёртка
   (соотношение ровно 2:1). Кладёшь в game/planets/ и вписываешь
   в game/planets/manifest.json — игра возьмёт их вместо
   процедурных. Обязательна только карта цвета; облака, ночные огни
   и рельеф — по желанию. Ключ в манифесте — либо биом (одна картинка
   на все такие миры), либо имя конкретной планеты. Промты для
   генератора и разбор формата — в game/planets/README.md.
   ───────────────────────────────────────────────────────────── */

const PLANET_BASE = new URL('../planets/', import.meta.url);
// ключ (биом или имя планеты) → {map, cloudMap, emissiveMap, normalMap}
const planetLib = new Map();

export async function loadPlanetTextures() {
  let manifest;
  try {
    const res = await fetch(new URL('manifest.json', PLANET_BASE), { cache: 'no-cache' });
    if (!res.ok) return 0;
    manifest = await res.json();
  } catch (e) { return 0; }

  const entries = Object.entries(manifest.planets || {});
  if (!entries.length) return 0;
  const loader = new THREE.TextureLoader();

  const load = (file, srgb) => new Promise(resolve => {
    loader.load(new URL(file, PLANET_BASE).href, t => {
      if (srgb) t.colorSpace = THREE.SRGBColorSpace;
      t.wrapS = THREE.RepeatWrapping;
      t.wrapT = THREE.ClampToEdgeWrapping;
      t.anisotropy = 8;
      resolve(t);
    }, undefined, () => resolve(null));
  });

  let ok = 0;
  await Promise.all(entries.map(async ([key, spec]) => {
    const cfg = typeof spec === 'string' ? { map: spec } : spec;
    if (!cfg || !cfg.map) return;
    const set = {};
    set.map = await load(cfg.map, true);
    if (!set.map) { console.warn(`Планета «${key}»: не открылась карта ${cfg.map}`); return; }
    if (cfg.clouds) set.cloudMap = await load(cfg.clouds, true);
    if (cfg.lights) set.emissiveMap = await load(cfg.lights, true);
    if (cfg.normal) set.normalMap = await load(cfg.normal, false);
    if (cfg.atmo) set.atmo = parseInt(String(cfg.atmo).replace('#', ''), 16);
    if (cfg.atmoPower !== undefined) set.atmoPower = cfg.atmoPower;
    // Карту бликов строим сами: тёмные синие пиксели считаем водой.
    // Так от художника нужна одна картинка, а блик на океане всё равно есть.
    set.roughnessMap = cfg.water === false ? null : waterRoughness(set.map);
    planetLib.set(key, set);
    ok++;
  }));
  return ok;
}

/* Ищем воду по цвету: синева заметно сильнее красного, и пиксель
   тёмный. Такие места делаем зеркальными, остальное — матовым. */
function waterRoughness(tex) {
  const img = tex.image;
  if (!img || !img.width) return null;
  const W = Math.min(1024, img.width), H = Math.round(W / 2);
  const cv = document.createElement('canvas');
  cv.width = W; cv.height = H;
  const ctx = cv.getContext('2d', { willReadFrequently: true });
  ctx.drawImage(img, 0, 0, W, H);
  const d = ctx.getImageData(0, 0, W, H);
  const px = d.data;
  for (let i = 0; i < W * H; i++) {
    const o = i * 4;
    const r = px[o], g = px[o + 1], b = px[o + 2];
    const lum = (r + g + b) / 3;
    const blue = b - Math.max(r, g);
    const water = blue > 12 && lum < 130;
    const v = water ? 30 : 220;
    px[o] = px[o + 1] = px[o + 2] = v; px[o + 3] = 255;
  }
  ctx.putImageData(d, 0, 0);
  const t = new THREE.CanvasTexture(cv);
  t.wrapS = THREE.RepeatWrapping;
  t.wrapT = THREE.ClampToEdgeWrapping;
  return t;
}

export function customPlanet(key) {
  return key ? planetLib.get(key) || null : null;
}
export function planetCount() { return planetLib.size; }

