/* Модели: собираем корабли, технику и здания из примитивов.
   Никаких внешних файлов — всё коробки, цилиндры и конусы.
   У каждой фракции свой силуэт:
     sleek  (Директорат) — вытянутый, гранёный, аккуратный
     heavy  (Гегемония)  — плиты, блоки, ничего лишнего
     scrap  (Синдикат)   — несимметричный, из подручного хлама  */

import { THREE, rnd, GLOW_TEX } from './engine.js';
import { customModel } from './assets.js';
import { planetTextures, nebulaTexture } from './textures.js';

const matCache = new Map();
/* ── ОБШИВКА КОРАБЛЕЙ.
   Плоский цвет — главная причина, по которой корабль из примитивов
   выглядит макетом: у настоящей брони есть швы, заклёпки, потёртости
   и грязь. Один скан металла (ambientCG, CC0), натянутый на все
   детали корпуса, снимает эту проблему разом: силуэт остаётся
   прежним, а поверхность перестаёт быть заливкой.

   Тайлим мелко и на всё сразу — UV у примитивов простые, и рисунок
   ложится по-разному на разные грани, что как раз и нужно. */

const TEX_BASE = new URL('../textures/', import.meta.url);
let HULL_TEX = null;
function hullMaps() {
  if (HULL_TEX) return HULL_TEX;
  const L = new THREE.TextureLoader();
  const get = (f, srgb, rep) => {
    const t = L.load(new URL(f, TEX_BASE).href);
    if (srgb) t.colorSpace = THREE.SRGBColorSpace;
    t.wrapS = t.wrapT = THREE.RepeatWrapping;
    t.repeat.set(rep, rep);
    t.anisotropy = 8;
    return t;
  };
  HULL_TEX = { map: get('hull_diff.jpg', true, 3), nor: get('hull_nor.jpg', false, 3) };
  return HULL_TEX;
}

function mat(color, opts = {}) {
  const key = color + '|' + JSON.stringify(opts);
  let m = matCache.get(key);
  if (!m) {
    const skin = opts.skin ? hullMaps() : null;
    m = new THREE.MeshStandardMaterial({
      color, roughness: opts.rough ?? 0.7, metalness: opts.metal ?? 0.35,
      emissive: opts.emissive ?? 0x000000, emissiveIntensity: opts.ei ?? 1,
      transparent: !!opts.transparent, opacity: opts.opacity ?? 1,
      flatShading: opts.flat !== false,
      map: skin ? skin.map : null,
      normalMap: skin ? skin.nor : null,
      normalScale: skin ? new THREE.Vector2(0.8, 0.8) : undefined,
    });
    m.userData.shared = true;
    matCache.set(key, m);
  }
  return m;
}
function glowMat(color) {
  const key = 'glow' + color;
  let m = matCache.get(key);
  if (!m) {
    m = new THREE.MeshBasicMaterial({ color, toneMapped: false });
    m.userData.shared = true;
    matCache.set(key, m);
  }
  return m;
}

const BOX = new THREE.BoxGeometry(1, 1, 1);
const CYL = new THREE.CylinderGeometry(1, 1, 1, 10);
const CONE = new THREE.ConeGeometry(1, 1, 8);
const SPH = new THREE.SphereGeometry(1, 12, 8);
for (const g of [BOX, CYL, CONE, SPH]) g.userData.shared = true;

function box(w, h, d, m, x = 0, y = 0, z = 0) {
  const o = new THREE.Mesh(BOX, m); o.scale.set(w, h, d); o.position.set(x, y, z); return o;
}
function cyl(r, h, m, x = 0, y = 0, z = 0) {
  const o = new THREE.Mesh(CYL, m); o.scale.set(r, h, r); o.position.set(x, y, z); return o;
}
function cone(r, h, m, x = 0, y = 0, z = 0) {
  const o = new THREE.Mesh(CONE, m); o.scale.set(r, h, r); o.position.set(x, y, z); return o;
}
function sph(r, m, x = 0, y = 0, z = 0) {
  const o = new THREE.Mesh(SPH, m); o.scale.setScalar(r); o.position.set(x, y, z); return o;
}

// Светящаяся точка (двигатель, огонёк). Sprite всегда развёрнут к камере,
// поэтому сопло видно с любого ракурса.
function glowSprite(size, color) {
  const m = new THREE.SpriteMaterial({
    map: GLOW_TEX, color, transparent: true, blending: THREE.AdditiveBlending,
    depthWrite: false, toneMapped: false,
  });
  const s = new THREE.Sprite(m);
  s.scale.setScalar(size);
  return s;
}

// ─────────────────────────────────────────────────────────────
// ВНЕШНИЕ МОДЕЛИ
// Если для юнита положена своя .glb (см. assets.js и models/README),
// берём её, приводим к нужной длине и сами навешиваем точки оружия,
// ПВО и двигателей — по габаритам модели. От художника требуется
// только корпус, всё остальное игра расставит.
// ─────────────────────────────────────────────────────────────

function fitCustom(kind, faction, id, targetLength, opts = {}) {
  const g = customModel(kind, faction.id, id);
  if (!g) return null;
  const inner = g.children[0];
  inner.scale.multiplyScalar(targetLength);
  const ext = g.userData.extent.multiplyScalar(targetLength);
  g.userData.ext = ext;
  if (opts.groundLevel) {
    // модель уже поднята так, что низ на нуле — ничего не двигаем
  }
  return g;
}

function shipHardpoints(g, def) {
  const ext = g.userData.ext;
  const halfL = ext.z / 2 || def.radius * 1.8;
  const halfW = ext.x / 2 || def.radius;
  const top = ext.y * 0.35;
  const muzzles = [];
  const guns = (def.guns || []).length || 1;
  for (let i = 0; i < guns; i++) {
    muzzles.push(new THREE.Vector3(0, top, -halfL * (0.95 - i * 0.22)));
  }
  const pdPoints = [];
  const n = def.pd ? def.pd.count : 3;
  for (let i = 0; i < n; i++) {
    const side = i % 2 ? 1 : -1;
    const t = n > 1 ? Math.floor(i / 2) / Math.max(1, Math.ceil(n / 2) - 1 || 1) : 0.5;
    pdPoints.push(new THREE.Vector3(side * halfW * 0.85, top * 0.6, (-0.4 + t * 0.8) * halfL));
  }
  const engines = [];
  const en = def.cls === 'escort' ? 2 : 3;
  // Размер факела берём от габарита самой модели, а не от радиуса класса:
  // иначе на вытянутом корпусе сопла раздуваются в шары размером с корабль.
  const flame = Math.max(1, Math.min(ext.x, ext.y) * 0.30);
  for (let i = 0; i < en; i++) {
    const x = (i - (en - 1) / 2) * halfW * 0.5;
    const sp = glowSprite(flame * 1.5, 0xff7a26);
    sp.position.set(x, 0, halfL * 1.02);
    g.add(sp);
    engines.push(sp);
    const core = glowSprite(flame * 0.65, 0xffe2b0);
    core.position.set(x, 0, halfL * 0.98);
    g.add(core);
    engines.push(core);
  }
  g.userData.muzzles = muzzles;
  g.userData.pdPoints = pdPoints;
  g.userData.engines = engines;
  g.userData.bay = new THREE.Vector3(0, -ext.y * 0.2, -halfL * 0.9);
  return g;
}

// ─────────────────────────────────────────────────────────────
// КОСМИЧЕСКИЕ КОРАБЛИ
// Нос корабля смотрит в -Z (как камера three.js).
// group.userData: muzzles[] — точки главного калибра,
//                 pdPoints[] — точки ПВО, engines[] — сопла,
//                 bay — точка вылета авиации.
// ─────────────────────────────────────────────────────────────

export function buildShip(def, faction) {
  const custom = fitCustom('ship', faction, def.id, def.radius * 3.6);
  if (custom) return shipHardpoints(custom, def);

  const g = new THREE.Group();
  const style = faction.style;

  /* Силуэт по референсу из Homeplanet: широкий плоский корпус,
     собранный из слоёв плит, ярусная надстройка ближе к корме,
     мостик с подсвеченными окнами и два маршевых сопла с
     фиолетовым выхлопом. Палитра — сталь с бордовыми панелями. */
  const hullColor = style === 'stealth' ? 0x6a6a80 : style === 'scrap' ? 0x8d8676
                  : style === 'wedge' ? 0x9aa8a4 : 0xa9b2bd;
  const deckColor = style === 'stealth' ? 0x3c3448 : style === 'scrap' ? 0x6d5a44
                  : style === 'wedge' ? 0x5f7a72 : 0x7a4a44;   // бордовые панели
  const darkColor = style === 'stealth' ? 0x23232e : 0x3f444c;

  const hull = mat(hullColor, { rough: 0.6, metal: 0.5, skin: true });
  const deck = mat(deckColor, { rough: 0.7, metal: 0.35, skin: true });
  const dark = mat(darkColor, { rough: 0.85, metal: 0.3, skin: true });
  const trim = mat(faction.color, { rough: 0.35, metal: 0.4, emissive: faction.color, ei: 1.1 });
  const glass = mat(0xffe8b0, { rough: 0.2, metal: 0.1, emissive: 0xffcc70, ei: 2.2 });

  const R = def.radius;
  const L = R * (def.cls === 'escort' ? 3.4 : def.cls === 'carrier' ? 3.2 : 3.6);
  const muzzles = [], pdPoints = [], engines = [];

  /* Маршевое сопло: раструб, раскалённое добела горло и рыжий факел.
     Два слоя свечения — так факел читается как пламя, а не как
     цветная клякса. */
  const addEngine = (x, y, z, size) => {
    g.add(cyl(size * 0.42, size * 0.7, dark, x, y, z).rotateX(Math.PI / 2));
    g.add(cyl(size * 0.30, size * 0.2, mat(0x30231a, { rough: 0.9 }), x, y, z + size * 0.3).rotateX(Math.PI / 2));
    const flame = glowSprite(size * 1.7, 0xff7a26);        // рыжий факел
    flame.position.set(x, y, z + size * 0.75);
    g.add(flame);
    const core = glowSprite(size * 0.75, 0xffe2b0);        // белое горло
    core.position.set(x, y, z + size * 0.4);
    g.add(core);
    engines.push(flame);
    engines.push(core);
  };

  /* Компоновка двигателей у классов разная — это заметно в силуэте:
     у корветов и носителей разнесены по краям, у крейсеров собраны
     в пакет по центру, у флагмана два разнесённых блока по два. */
  const engineBlock = (kind, W, z, size) => {
    if (kind === 'spread') {
      addEngine(-W * 0.78, -R * 0.06, z, size);
      addEngine(W * 0.78, -R * 0.06, z, size);
    } else if (kind === 'cluster') {
      addEngine(-W * 0.20, -R * 0.05, z, size);
      addEngine(W * 0.20, -R * 0.05, z, size);
      addEngine(0, R * 0.18, z - size * 0.15, size * 0.8);
    } else if (kind === 'quad') {
      for (const sx of [-1, 1]) {
        addEngine(sx * W * 0.75, -R * 0.1, z, size);
        addEngine(sx * W * 0.42, R * 0.16, z - size * 0.2, size * 0.8);
      }
    } else {
      addEngine(-W * 0.34, 0, z, size);
      addEngine(W * 0.34, 0, z, size);
    }
  };

  // Слоёная плита корпуса: основа силуэта
  const slab = (w, h, d, x, y, z, m) => {
    g.add(box(w, h, d, m || hull, x, y, z));
    g.add(box(w * 0.99, h * 0.32, d * 0.55, deck, x, y + h * 0.5, z));
  };

  // Боковые «крылья» из наложенных пластин
  const wings = (count, w, d, y0, z0, step) => {
    for (const side of [-1, 1]) {
      for (let i = 0; i < count; i++) {
        const k = 1 - i * 0.18;
        g.add(box(w * k, R * 0.12, d * k, i % 2 ? deck : hull,
                  side * (R * 0.7 + w * 0.45), y0 - i * R * 0.14, z0 + i * step));
      }
    }
  };

  // Ярусная надстройка с мостиком
  const tower = (baseW, z) => {
    for (let i = 0; i < 3; i++) {
      const w = baseW * (1 - i * 0.24);
      g.add(box(w, R * 0.34, w * 0.9, i === 1 ? deck : hull, 0, R * (0.45 + i * 0.34), z + i * R * 0.18));
    }
    g.add(box(baseW * 0.42, R * 0.16, baseW * 0.3, glass, 0, R * 0.62, z - baseW * 0.34));
    g.add(cyl(R * 0.05, R * 0.9, dark, 0, R * 1.75, z + R * 0.4));
    g.add(box(baseW * 0.8, R * 0.07, R * 0.16, trim, 0, R * 0.63, z));
  };

  if (def.cls === 'escort' && !def.ecm) {
    const W = R * 1.5;
    slab(W, R * 0.42, L, 0, 0, 0);
    g.add(cone(W * 0.34, R * 1.5, hull, 0, 0, -L * 0.5 - R * 0.6).rotateX(-Math.PI / 2));
    wings(2, R * 1.0, L * 0.35, R * 0.02, L * 0.06, R * 0.12);
    g.add(box(W * 0.45, R * 0.4, L * 0.3, deck, 0, R * 0.34, L * 0.12));
    g.add(box(W * 0.2, R * 0.12, R * 0.3, glass, 0, R * 0.5, -L * 0.02));
    g.add(box(W * 1.02, R * 0.08, R * 0.22, trim, 0, R * 0.16, -L * 0.12));
    engineBlock('spread', W * 0.55, L * 0.5, R * 0.85);
    muzzles.push(new THREE.Vector3(0, R * 0.3, -L * 0.55));
    pdPoints.push(new THREE.Vector3(-W * 0.6, R * 0.16, 0), new THREE.Vector3(W * 0.6, R * 0.16, 0),
                  new THREE.Vector3(0, -R * 0.24, L * 0.2));
  } else if (def.ecm) {
    // Корабль РЭБ: излучатель-блин снизу и мачты сверху
    const W = R * 1.2;
    slab(W, R * 0.5, L * 0.85, 0, 0, 0);
    g.add(cone(W * 0.35, R * 1.1, hull, 0, 0, -L * 0.42 - R * 0.4).rotateX(-Math.PI / 2));
    const emitter = cyl(R * 1.5, R * 0.22, deck, 0, -R * 0.55, R * 0.1);
    g.add(emitter);
    g.add(cyl(R * 1.05, R * 0.12, trim, 0, -R * 0.72, R * 0.1));
    g.add(cyl(R * 0.22, R * 0.6, dark, 0, -R * 0.3, R * 0.1));
    for (let i = 0; i < 3; i++) {
      g.add(cyl(R * 0.06, R * 1.6, dark, (i - 1) * R * 0.5, R * 1.0, L * 0.05));
      g.add(sph(R * 0.13, trim, (i - 1) * R * 0.5, R * 1.8, L * 0.05));
    }
    g.add(box(W * 0.5, R * 0.3, L * 0.25, deck, 0, R * 0.38, L * 0.2));
    g.add(box(W * 0.22, R * 0.12, R * 0.26, glass, 0, R * 0.52, L * 0.08));
    engineBlock('cluster', W * 0.5, L * 0.44, R * 0.8);
    pdPoints.push(new THREE.Vector3(-W * 0.6, R * 0.2, L * 0.15),
                  new THREE.Vector3(W * 0.6, R * 0.2, L * 0.15));
    g.userData.emitter = new THREE.Vector3(0, -R * 0.75, R * 0.1);
  } else if (def.cls === 'carrier') {
    // Носитель: широкая слоёная палуба с зевом ангара в носу
    const W = R * 2.0;
    slab(W, R * 0.5, L, 0, 0, 0);
    g.add(box(W * 0.5, R * 0.62, L * 0.86, dark, 0, R * 0.06, 0));
    g.add(box(W * 0.36, R * 0.8, R * 1.0, dark, 0, R * 0.08, -L * 0.5 + R * 0.35));
    const bay = glowSprite(R * 1.3, 0xffc27a);
    bay.position.set(0, R * 0.08, -L * 0.5 + R * 0.25);
    g.add(bay);
    wings(3, R * 1.3, L * 0.5, -R * 0.05, L * 0.18, R * 0.16);
    tower(R * 1.0, L * 0.26);
    for (let i = -2; i <= 2; i++) g.add(box(W * 1.0, R * 0.07, R * 0.13, trim, 0, R * 0.27, i * L * 0.15));
    engineBlock('spread', W * 0.45, L * 0.52, R * 1.0);
    pdPoints.push(
      new THREE.Vector3(-W * 0.52, R * 0.34, -L * 0.24), new THREE.Vector3(W * 0.52, R * 0.34, -L * 0.24),
      new THREE.Vector3(-W * 0.52, R * 0.34, L * 0.24), new THREE.Vector3(W * 0.52, R * 0.34, L * 0.24),
      new THREE.Vector3(0, -R * 0.34, 0));
    g.userData.bay = new THREE.Vector3(0, R * 0.08, -L * 0.55);
  } else if (def.station) {
    const ring = new THREE.Mesh(new THREE.TorusGeometry(R * 1.2, R * 0.22, 8, 20), hull);
    ring.rotation.x = Math.PI / 2;
    g.add(ring);
    g.add(cyl(R * 0.5, R * 1.6, hull, 0, 0, 0));
    g.add(sph(R * 0.62, dark, 0, 0, 0));
    for (let i = 0; i < 4; i++) {
      const a = i * Math.PI / 2 + Math.PI / 4;
      g.add(box(R * 0.9, R * 0.2, R * 0.2, trim, Math.cos(a) * R * 0.85, 0, Math.sin(a) * R * 0.85));
    }
    for (let i = 0; i < 8; i++) {
      const a = i * Math.PI / 4;
      pdPoints.push(new THREE.Vector3(Math.cos(a) * R * 1.2, 0, Math.sin(a) * R * 1.2));
    }
    muzzles.push(new THREE.Vector3(0, R * 0.8, 0));
    g.userData.bay = new THREE.Vector3(0, -R * 0.7, 0);
  } else {
    // Крейсер и флагман: стрельчатый слоёный корпус с ярусной кормой
    const W = R * (def.id === 'capital' ? 1.5 : 1.2);
    slab(W, R * 0.55, L, 0, 0, 0);
    slab(W * 0.66, R * 0.4, L * 0.72, 0, R * 0.46, L * 0.06);
    g.add(cone(W * 0.4, R * 2.0, hull, 0, 0, -L * 0.5 - R * 0.7).rotateX(-Math.PI / 2));
    wings(def.id === 'capital' ? 4 : 3, R * 1.25, L * 0.46, R * 0.0, L * 0.1, R * 0.15);
    tower(W * 0.62, L * 0.2);

    // нижние подвесные плиты — как на референсе под брюхом
    for (let i = 0; i < 3; i++) {
      g.add(box(W * (0.9 - i * 0.16), R * 0.14, L * 0.2, i % 2 ? deck : hull,
                0, -R * (0.42 + i * 0.16), L * (0.12 + i * 0.16)));
    }
    if (style === 'stealth') {
      for (const side of [-1, 1]) {
        const fin = box(W * 0.42, R * 0.1, L * 0.42, hull, side * W * 0.72, R * 0.14, L * 0.04);
        fin.rotation.z = side * 0.55;
        g.add(fin);
      }
    }
    const turretCount = def.id === 'capital' ? 2 : 1;
    for (let i = 0; i < turretCount; i++) {
      const z = -L * (0.3 - i * 0.2);
      const t = new THREE.Group();
      t.add(cyl(R * 0.34, R * 0.26, dark, 0, 0, 0));
      t.add(box(R * 0.42, R * 0.3, R * 0.85, deck, 0, R * 0.15, -R * 0.3));
      t.add(cyl(R * 0.09, R * 1.5, dark, 0, R * 0.16, -R * 0.85).rotateX(Math.PI / 2));
      t.add(cyl(R * 0.11, R * 0.2, trim, 0, R * 0.16, -R * 1.5).rotateX(Math.PI / 2));
      t.position.set(0, R * 0.72, z);
      g.add(t);
      muzzles.push(new THREE.Vector3(0, R * 0.88, z - R * 1.6));
    }
    const n = def.pd ? def.pd.count : 3;
    for (let i = 0; i < n; i++) {
      const side = i % 2 ? 1 : -1;
      const rows = Math.max(1, Math.ceil(n / 2) - 1) || 1;
      const z = (-0.35 + (Math.floor(i / 2) / rows) * 0.7) * L;
      const zz = isFinite(z) ? z : 0;
      pdPoints.push(new THREE.Vector3(side * W * 0.58, R * 0.28, zz));
      g.add(box(R * 0.14, R * 0.14, R * 0.26, dark, side * W * 0.58, R * 0.38, zz));
    }
    engineBlock(def.id === 'capital' ? 'quad' : 'cluster', W, L * 0.5, R * 1.0);
  }

  g.userData.muzzles = muzzles.length ? muzzles : [new THREE.Vector3(0, 0, -L * 0.5)];
  g.userData.pdPoints = pdPoints.length ? pdPoints : [new THREE.Vector3(0, 0, 0)];
  g.userData.engines = engines;
  if (!g.userData.bay) g.userData.bay = new THREE.Vector3(0, -R * 0.4, 0);

  // Крупнее на четверть: с тактической камеры силуэт должен читаться.
  // Точки оружия масштабируем следом, иначе выстрелы полетят мимо корпуса.
  const K = 1.25;
  g.scale.multiplyScalar(K);
  for (const list of [g.userData.muzzles, g.userData.pdPoints]) {
    for (const v of list) v.multiplyScalar(K);
  }
  g.userData.bay.multiplyScalar(K);
  if (g.userData.emitter) g.userData.emitter.multiplyScalar(K);
  return g;
}

// Малая авиация: три силуэта по ролям
export function buildStrike(role, faction) {
  const custom = fitCustom('strike', faction, role, 5.5);
  if (custom) {
    const ext = custom.userData.ext;
    const sp = glowSprite(1.0, 0xff8a3a);
    sp.position.set(0, 0, ext.z / 2 * 0.95);
    custom.add(sp);
    custom.userData.engines = [sp];
    return custom;
  }

  const g = new THREE.Group();
  const hull = mat(0x9aa2ad, { rough: 0.6, metal: 0.5 });
  const dark = mat(0x33373d, { rough: 0.8 });
  const trim = mat(faction.color, { emissive: faction.color, ei: 0.4 });
  if (role === 'interceptor') {
    g.add(box(0.3, 0.28, 2.0, hull));
    g.add(box(2.1, 0.1, 0.42, trim, 0, 0, 0.2));       // длинное тонкое крыло
    g.add(cone(0.2, 0.7, hull, 0, 0, -1.2).rotateX(-Math.PI / 2));
    g.add(box(0.12, 0.5, 0.4, dark, 0, 0.3, 0.85));
  } else if (role === 'fighter') {
    g.add(box(0.45, 0.35, 1.8, hull));
    g.add(box(1.5, 0.12, 0.7, hull, 0, -0.02, 0.1));
    g.add(box(1.55, 0.08, 0.2, trim, 0, 0.06, -0.1));
    g.add(cone(0.26, 0.6, dark, 0, 0, -1.05).rotateX(-Math.PI / 2));
    g.add(box(0.14, 0.42, 0.36, dark, 0, 0.3, 0.7));
  } else {
    g.add(box(0.75, 0.6, 2.2, hull));                   // толстый бомбер
    g.add(box(2.0, 0.14, 0.9, hull, 0, -0.05, 0.25));
    g.add(box(0.5, 0.35, 0.6, dark, 0, -0.35, -0.2));   // торпедный отсек
    g.add(box(0.32, 0.32, 0.9, trim, 0, 0.36, 0.1));
    g.add(box(0.16, 0.45, 0.4, dark, 0, 0.42, 0.95));
  }
  const e = glowSprite(0.95, 0xff8a3a);
  e.position.set(0, 0, 1.05);
  g.add(e);
  g.userData.engines = [e];
  g.scale.setScalar(1.7);
  return g;
}

export function buildTorpedo(color = 0xffb060) {
  const g = new THREE.Group();
  g.add(cyl(0.22, 1.4, mat(0x9a9a9a, { metal: 0.6 })).rotateX(Math.PI / 2));
  const s = glowSprite(2.4, color);
  s.position.z = 0.8;
  g.add(s);
  return g;
}

// ─────────────────────────────────────────────────────────────
// НАЗЕМНАЯ ТЕХНИКА
// Юниты смотрят в -Z, стоят на y = 0.
// ─────────────────────────────────────────────────────────────

const GROUND_LENGTH = {
  worker: 7.5, rifle: 4.5, rocket: 4.5, tank: 8.5, aa: 7.5, arty: 9.5, jet: 11,
};

export function buildGroundUnit(def, faction) {
  const custom = fitCustom('ground', faction, def.id, GROUND_LENGTH[def.id] || 8, { groundLevel: true });
  if (custom) {
    const ext = custom.userData.ext;
    custom.userData.muzzles = [new THREE.Vector3(0, ext.y * 0.6, -ext.z * 0.5)];
    if (def.air) {
      const sp = glowSprite(1.6, 0xff8a3a);
      sp.position.set(0, 0, ext.z * 0.48);
      custom.add(sp);
      custom.userData.engines = [sp];
    }
    return custom;
  }

  const g = new THREE.Group();
  const style = faction.style;
  const bodyColor = style === 'heavy' ? 0x6e5f4c : style === 'scrap' ? 0x6b6450 : 0x5d6b6e;
  const body = mat(bodyColor, { rough: 0.85, metal: 0.2 });
  const dark = mat(0x2f2c28, { rough: 0.9, metal: 0.1 });
  const trim = mat(faction.color, { emissive: faction.color, ei: 0.2, rough: 0.6 });
  const muzzles = [];

  switch (def.id) {
    case 'worker': {
      g.add(box(2.4, 1.3, 4.2, body, 0, 1.1, 0));
      g.add(box(2.0, 1.2, 1.6, dark, 0, 1.9, -1.2));
      g.add(box(2.6, 0.4, 0.5, trim, 0, 1.75, 1.9));
      wheels(g, dark, 1.3, 0.55, [-1.3, 0, 1.3]);
      break;
    }
    case 'rifle': case 'rocket': {
      // Отделение — три фигурки, чтобы читалось как пехота
      const isRocket = def.id === 'rocket';
      for (let i = 0; i < 3; i++) {
        const p = new THREE.Group();
        const c = i === 0 ? trim : body;
        p.add(box(0.62, 1.0, 0.44, c, 0, 0.9, 0));
        p.add(sph(0.32, dark, 0, 1.65, 0));
        p.add(box(0.14, 0.14, isRocket ? 1.5 : 1.0, dark, 0.34, 1.05, -0.4));
        p.position.set((i - 1) * 1.15, 0, (i % 2) * 0.9 - 0.3);
        p.rotation.y = rnd(-0.25, 0.25);
        g.add(p);
      }
      g.scale.setScalar(1.15);
      muzzles.push(new THREE.Vector3(0, 1.3, -0.9));
      break;
    }
    case 'tank': {
      const light = style === 'scrap';
      const w = light ? 2.4 : 3.2, l = light ? 4.4 : 5.4;
      g.add(box(w, 1.0, l, body, 0, 0.95, 0));
      g.add(box(w * 1.12, 0.7, l * 0.92, dark, 0, 0.55, 0));  // гусеницы/днище
      const tur = new THREE.Group();
      tur.add(box(w * 0.72, 0.85, l * 0.5, body, 0, 0, 0));
      tur.add(box(w * 0.3, 0.28, 0.7, trim, 0, 0.5, 0.4));
      tur.add(cyl(0.19, l * 0.62, dark, 0, 0.05, -l * 0.42).rotateX(Math.PI / 2));
      tur.position.set(0, 1.85, style === 'heavy' ? 0.3 : 0.1);
      g.add(tur);
      g.userData.turret = tur;
      muzzles.push(new THREE.Vector3(0, 1.9, -l * 0.78));
      if (style === 'heavy') g.add(box(w * 1.05, 0.3, 1.0, dark, 0, 1.6, -l * 0.42));
      if (light) wheels(g, dark, 1.25, 0.6, [-1.4, 1.4]);
      break;
    }
    case 'aa': {
      g.add(box(2.8, 1.0, 4.4, body, 0, 1.0, 0));
      const tur = new THREE.Group();
      tur.add(cyl(1.0, 0.7, dark, 0, 0, 0));
      tur.add(box(0.5, 0.6, 1.6, trim, -0.5, 0.35, -0.3));
      tur.add(box(0.5, 0.6, 1.6, trim, 0.5, 0.35, -0.3));
      tur.position.set(0, 1.8, 0.2);
      tur.rotation.x = -0.25;
      g.add(tur);
      g.userData.turret = tur;
      muzzles.push(new THREE.Vector3(0, 2.4, -1.6));
      wheels(g, dark, 1.45, 0.6, [-1.5, 0, 1.5]);
      break;
    }
    case 'arty': {
      g.add(box(3.0, 1.1, 5.6, body, 0, 1.0, 0));
      g.add(box(3.3, 0.7, 5.0, dark, 0, 0.5, 0));
      const tur = new THREE.Group();
      if (style === 'heavy') {
        for (let i = 0; i < 3; i++)
          tur.add(box(0.5, 0.5, 3.4, dark, (i - 1) * 0.7, 0.3 + i * 0.02, -0.8));
        tur.add(box(2.6, 0.3, 0.6, trim, 0, 0.65, 0.4));
      } else {
        tur.add(box(1.5, 0.8, 1.4, body, 0, 0, 0.4));
        tur.add(cyl(0.24, 4.6, dark, 0, 0.45, -2.0).rotateX(Math.PI / 2));
        tur.add(box(1.6, 0.2, 0.5, trim, 0, 0.85, 0.4));
      }
      tur.position.set(0, 1.9, 0.6);
      tur.rotation.x = -0.18;
      g.add(tur);
      g.userData.turret = tur;
      muzzles.push(new THREE.Vector3(0, 2.5, -3.4));
      break;
    }
    case 'jet': {
      g.add(box(1.1, 0.9, 6.4, body, 0, 0, 0));
      g.add(cone(0.55, 1.8, body, 0, 0, -3.8).rotateX(-Math.PI / 2));
      g.add(box(7.0, 0.22, 1.7, body, 0, -0.1, 0.4));
      g.add(box(7.2, 0.12, 0.4, trim, 0, 0.02, 0.1));
      g.add(box(2.4, 0.18, 1.0, body, 0, 0.1, 2.7));
      g.add(box(0.2, 1.1, 1.0, dark, 0, 0.7, 2.7));
      g.add(box(0.9, 0.7, 1.4, dark, 0, 0.35, -1.4));
      for (const s of [-1, 1]) g.add(cyl(0.42, 2.2, dark, s * 1.6, -0.3, 0.9).rotateX(Math.PI / 2));
      const e1 = glowSprite(2.0, 0xff8a3a); e1.position.set(-1.6, -0.3, 2.1); g.add(e1);
      const e2 = glowSprite(2.0, 0xff8a3a); e2.position.set(1.6, -0.3, 2.1); g.add(e2);
      g.userData.engines = [e1, e2];
      muzzles.push(new THREE.Vector3(0, -0.4, -2.0));
      break;
    }
    case 'scout': {
      // Лёгкая разведмашина: маленькая, на колёсах, с тарелкой и антенной
      g.add(box(1.9, 0.8, 3.4, body, 0, 0.95, 0));
      g.add(box(1.5, 0.7, 1.3, dark, 0, 1.6, -0.4));
      g.add(box(1.7, 0.16, 0.4, trim, 0, 1.35, 1.5));
      g.add(cyl(0.05, 2.6, dark, 0.7, 2.3, 0.9));                 // антенна
      const dish = cyl(0.62, 0.12, trim, -0.55, 2.1, 0.5);
      dish.rotation.z = 0.5;
      g.add(dish);
      g.add(box(0.1, 0.1, 0.9, dark, 0, 1.9, -1.1));              // пулемёт
      wheels(g, dark, 1.05, 0.5, [-1.1, 1.1]);
      muzzles.push(new THREE.Vector3(0, 1.9, -1.7));
      break;
    }
    case 'ifv': {
      // БМП: корпус ниже танкового, башенка с автопушкой
      g.add(box(2.6, 0.9, 4.6, body, 0, 0.95, 0));
      g.add(box(2.9, 0.6, 4.2, dark, 0, 0.5, 0));
      g.add(box(2.2, 0.5, 1.4, body, 0, 1.6, 1.2));               // скос кормы
      const tur = new THREE.Group();
      tur.add(box(1.4, 0.6, 1.5, body, 0, 0, 0));
      tur.add(box(0.5, 0.22, 0.6, trim, 0, 0.35, 0.3));
      tur.add(cyl(0.1, 3.0, dark, 0, 0.1, -1.5).rotateX(Math.PI / 2));
      tur.position.set(0, 1.7, -0.3);
      g.add(tur);
      g.userData.turret = tur;
      muzzles.push(new THREE.Vector3(0, 1.8, -2.6));
      wheels(g, dark, 1.35, 0.5, [-1.5, 0, 1.5]);
      break;
    }
    case 'eng': {
      // Ремонтники: двое с ящиком инструмента, без оружия
      for (let i = 0; i < 2; i++) {
        const p = new THREE.Group();
        p.add(box(0.62, 1.0, 0.44, i === 0 ? trim : body, 0, 0.9, 0));
        p.add(sph(0.32, dark, 0, 1.65, 0));
        p.add(box(0.5, 0.36, 0.34, dark, 0.5, 0.75, 0.1));        // ящик
        p.position.set((i - 0.5) * 1.3, 0, (i % 2) * 0.7 - 0.2);
        p.rotation.y = rnd(-0.25, 0.25);
        g.add(p);
      }
      g.scale.setScalar(1.15);
      break;
    }
    case 'sniper': {
      // Один стрелок с длинным стволом — силуэт нарочно тоньше отделения
      const p = new THREE.Group();
      p.add(box(0.55, 0.95, 0.4, body, 0, 0.85, 0));
      p.add(sph(0.3, dark, 0, 1.55, 0));
      p.add(box(0.1, 0.1, 2.1, dark, 0.26, 1.0, -0.8));
      p.add(box(0.16, 0.16, 0.3, trim, 0.26, 1.16, -0.5));        // прицел
      g.add(p);
      g.scale.setScalar(1.2);
      muzzles.push(new THREE.Vector3(0.3, 1.2, -1.9));
      break;
    }
    case 'mlrs': {
      // РСЗО: шасси плюс поворотный пакет направляющих
      g.add(box(2.8, 1.0, 5.2, body, 0, 1.0, 0));
      g.add(box(2.4, 0.9, 1.5, dark, 0, 1.9, 1.6));               // кабина
      const tur = new THREE.Group();
      for (let r = 0; r < 2; r++) {
        for (let i = 0; i < 4; i++) {
          tur.add(cyl(0.2, 3.2, dark, (i - 1.5) * 0.5, r * 0.45, -0.4).rotateX(Math.PI / 2));
        }
      }
      tur.add(box(2.4, 0.22, 0.6, trim, 0, -0.35, 0.9));
      tur.position.set(0, 1.9, -0.6);
      tur.rotation.x = -0.32;                                     // задрано в небо
      g.add(tur);
      g.userData.turret = tur;
      muzzles.push(new THREE.Vector3(0, 2.9, -2.4));
      break;
    }
    case 'heli': {
      // Вертолёт: фюзеляж, несущий винт, хвостовая балка, блоки НУРС
      g.add(box(1.5, 1.4, 4.6, body, 0, 0, 0));
      g.add(sph(0.85, dark, 0, 0.1, -1.9));                       // кабина
      g.add(box(0.5, 0.5, 3.2, body, 0, 0.25, 2.9));              // балка
      g.add(box(0.16, 1.3, 0.8, body, 0, 0.8, 4.2));              // киль
      for (const s of [-1, 1]) {
        g.add(box(0.3, 0.2, 1.6, body, s * 1.1, -0.3, -0.2));     // пилон
        g.add(cyl(0.34, 1.5, dark, s * 1.5, -0.35, -0.2).rotateX(Math.PI / 2));
      }
      const rotor = new THREE.Group();
      rotor.add(cyl(0.16, 0.5, dark, 0, 0, 0));
      for (let i = 0; i < 4; i++) {
        const b = box(0.22, 0.06, 6.4, dark, 0, 0.25, 0);
        b.rotation.y = (i / 4) * Math.PI * 2;
        rotor.add(b);
      }
      rotor.position.set(0, 1.0, -0.2);
      g.add(rotor);
      g.userData.rotor = rotor;
      const tail = cyl(0.05, 1.6, dark, 0.2, 0.9, 4.2);
      tail.rotation.z = Math.PI / 2;
      g.add(tail);
      const e = glowSprite(1.3, 0xff8a3a);
      e.position.set(0, 0.4, 1.9);
      g.add(e);
      g.userData.engines = [e];
      muzzles.push(new THREE.Vector3(0, -0.35, -1.6));
      break;
    }
    default:
      g.add(box(2, 2, 2, body, 0, 1, 0));
  }
  g.userData.muzzles = muzzles.length ? muzzles : [new THREE.Vector3(0, 1.5, -1.5)];
  // Общий укрупняющий множитель: на карте техника должна читаться
  // с обычной высоты камеры, а не выглядеть точками.
  g.scale.multiplyScalar(1.5);
  for (const m of g.userData.muzzles) m.multiplyScalar(1.5);
  return g;
}

function wheels(g, m, dx, r, zs) {
  for (const z of zs) for (const s of [-1, 1]) {
    const w = cyl(r, 0.45, m, s * dx, r, z);
    w.rotation.z = Math.PI / 2;
    g.add(w);
  }
}

// ─────────────────────────────────────────────────────────────
// ЗДАНИЯ
// ─────────────────────────────────────────────────────────────

export function buildStructure(def, faction) {
  const custom = fitCustom('building', faction, def.id, def.size * 1.5, { groundLevel: true });
  if (custom) {
    const ext = custom.userData.ext;
    custom.userData.muzzles = [new THREE.Vector3(0, ext.y * 0.85, -ext.z * 0.5)];
    return custom;
  }

  const g = new THREE.Group();
  const style = faction.style;
  const wall = mat(style === 'heavy' ? 0x6a5c4a : style === 'scrap' ? 0x6b6350 : 0x5b6569, { rough: 0.9, metal: 0.15 });
  const dark = mat(0x2e2b27, { rough: 0.95 });
  const trim = mat(faction.color, { emissive: faction.color, ei: 0.3, rough: 0.6 });
  const S = def.size;
  const muzzles = [];

  switch (def.id) {
    case 'hq': {
      // Самое высокое здание на карте — штаб видно отовсюду
      g.add(box(S * 1.05, 2.4, S * 1.05, dark, 0, 1.2, 0));
      g.add(box(S * 0.82, 7.0, S * 0.82, wall, 0, 5.6, 0));
      g.add(box(S * 0.9, 0.6, S * 0.9, dark, 0, 9.4, 0));
      g.add(box(S * 0.46, 6.0, S * 0.46, wall, 0, 12.6, 0));
      g.add(box(S * 0.54, 0.7, S * 0.54, trim, 0, 15.9, 0));
      g.add(cyl(0.35, 7.0, dark, 0, 19.5, 0));
      g.add(sph(0.9, trim, 0, 23.2, 0));
      for (const s of [-1, 1]) g.add(box(0.7, 5.8, S * 0.86, trim, s * S * 0.42, 5.6, 0));
      g.add(box(S * 0.35, 3.2, 0.5, dark, 0, 3.8, S * 0.43));
      break;
    }
    case 'barracks': {
      g.add(box(S * 1.4, 0.6, S, dark, 0, 0.3, 0));
      g.add(box(S * 1.25, 3.4, S * 0.85, wall, 0, 2.0, 0));
      g.add(box(S * 1.3, 0.5, S * 0.9, dark, 0, 3.9, 0));
      g.add(box(S * 1.34, 0.34, S * 0.28, trim, 0, 4.1, 0));
      g.add(box(1.8, 2.4, 0.4, dark, 0, 1.5, S * 0.44));
      for (let i = -1; i <= 1; i++) g.add(box(0.35, 1.0, 0.2, trim, i * 2.0, 2.6, S * 0.44));
      g.add(cyl(0.25, 3.0, dark, -S * 0.5, 5.2, -S * 0.3));
      break;
    }
    case 'factory': {
      g.add(box(S * 1.5, 0.6, S * 1.1, dark, 0, 0.3, 0));
      g.add(box(S * 1.35, 4.4, S, wall, 0, 2.6, 0));
      for (let i = 0; i < 3; i++) g.add(cyl(0.7, 2.4, dark, (i - 1) * S * 0.35, 6.0, -S * 0.25));
      g.add(box(S * 1.4, 0.4, S * 1.05, dark, 0, 4.9, 0));
      g.add(box(S * 1.44, 0.26, S * 0.3, trim, 0, 5.2, 0));
      g.add(box(S * 0.7, 3.0, 0.5, dark, 0, 1.6, S * 0.52));  // ворота
      g.add(box(S * 0.72, 0.3, 0.6, trim, 0, 3.2, S * 0.52));
      break;
    }
    case 'airfield': {
      g.add(box(S * 1.6, 0.4, S * 0.9, dark, 0, 0.2, 0));      // полоса
      for (let i = -2; i <= 2; i++) g.add(box(1.6, 0.06, 0.35, trim, i * S * 0.28, 0.42, 0));
      g.add(box(S * 0.5, 3.2, S * 0.45, wall, -S * 0.62, 1.8, -S * 0.55));
      g.add(box(S * 0.34, 1.2, S * 0.34, trim, -S * 0.62, 4.0, -S * 0.55));
      g.add(box(S * 0.9, 2.6, S * 0.4, wall, S * 0.3, 1.5, -S * 0.6));
      break;
    }
    case 'turret': case 'sam': {
      g.add(cyl(S * 0.55, 1.4, dark, 0, 0.7, 0));
      g.add(cyl(S * 0.38, 2.2, wall, 0, 2.2, 0));
      const tur = new THREE.Group();
      if (def.id === 'turret') {
        tur.add(box(S * 0.5, 0.8, S * 0.6, wall));
        tur.add(cyl(0.2, S * 1.3, dark, 0, 0.1, -S * 0.7).rotateX(Math.PI / 2));
        muzzles.push(new THREE.Vector3(0, 3.6, -S * 1.4));
      } else {
        tur.add(box(S * 0.55, 0.5, S * 0.55, wall));
        for (const s of [-1, 1]) for (const r of [0, 1])
          tur.add(box(0.28, 0.28, S * 0.9, trim, s * S * 0.18, 0.35 + r * 0.32, 0));
        tur.rotation.x = -0.35;
        muzzles.push(new THREE.Vector3(0, 4.2, -S * 0.5));
      }
      tur.position.y = 3.5;
      g.add(tur);
      g.userData.turret = tur;
      g.add(box(S * 0.2, 0.6, S * 0.2, trim, 0, 1.6, S * 0.4));
      break;
    }
    default:
      g.add(box(S, 3, S, wall, 0, 1.5, 0));
  }
  g.userData.muzzles = muzzles.length ? muzzles : [new THREE.Vector3(0, 3, 0)];
  return g;
}

/* ДЕКОР ЛАНДШАФТА.
   Немного растительности и обломков по биому: без них карта читается
   как пустая заливка, сколько полигонов в ней ни держи. */

const CONE_S = new THREE.ConeGeometry(1, 1, 7);
const ICO = new THREE.IcosahedronGeometry(1, 0);
const DODEC = new THREE.DodecahedronGeometry(1, 0);
for (const g of [CONE_S, ICO, DODEC]) g.userData.shared = true;

export function buildProp(biome, rng) {
  const g = new THREE.Group();
  const r = rng || Math.random;
  if (biome === 'green') {
    const trunk = mat(0x4a3a28, { rough: 1, metal: 0 });
    const leaf = mat(r() < 0.5 ? 0x35592f : 0x2c4a2a, { rough: 1, metal: 0 });
    const h = 3 + r() * 3;
    g.add(cyl(0.35, h, trunk, 0, h / 2, 0));
    for (let i = 0; i < 3; i++) {
      const c = new THREE.Mesh(CONE_S, leaf);
      const sz = 2.6 - i * 0.55;
      c.scale.set(sz, sz * 1.5, sz);
      c.position.y = h * 0.75 + i * 1.5;
      c.rotation.y = r() * 3;
      g.add(c);
    }
  } else if (biome === 'ice') {
    const ice = mat(0xa8cade, { rough: 0.35, metal: 0.1 });
    for (let i = 0; i < 3; i++) {
      const c = new THREE.Mesh(CONE_S, ice);
      const sz = 1 + r() * 2;
      c.scale.set(sz * 0.6, sz * 3.2, sz * 0.6);
      c.position.set(r() * 3 - 1.5, sz * 1.5, r() * 3 - 1.5);
      c.rotation.z = (r() - 0.5) * 0.5;
      g.add(c);
    }
  } else if (biome === 'desert') {
    const dry = mat(0x8a6f45, { rough: 1, metal: 0 });
    const n = 2 + (r() * 3 | 0);
    for (let i = 0; i < n; i++) {
      const b = new THREE.Mesh(DODEC, dry);
      const sz = 0.8 + r() * 1.8;
      b.scale.set(sz * 1.6, sz * 0.5, sz * 1.4);
      b.position.set(r() * 6 - 3, sz * 0.25, r() * 6 - 3);
      b.rotation.y = r() * 3;
      g.add(b);
    }
  } else if (biome === 'city') {
    const wall = mat(0x6a675f, { rough: 1, metal: 0.05 });
    const n = 2 + (r() * 3 | 0);
    for (let i = 0; i < n; i++) {
      const h = 1.5 + r() * 5;
      const b = box(1 + r() * 3, h, 0.8 + r() * 1.2, wall,
                    r() * 8 - 4, h / 2, r() * 8 - 4);
      b.rotation.y = r() * 3;
      g.add(b);
    }
  } else {
    const st = mat(0x7a6a58, { rough: 1, metal: 0 });
    for (let i = 0; i < 3; i++) {
      const b = new THREE.Mesh(ICO, st);
      const sz = 1.2 + r() * 3;
      b.scale.set(sz, sz * (0.6 + r() * 0.7), sz);
      b.position.set(r() * 5 - 2.5, sz * 0.4, r() * 5 - 2.5);
      b.rotation.set(r() * 3, r() * 3, r() * 3);
      g.add(b);
    }
  }
  return g;
}

/* ВОДА на наземных картах.
   Плоскость с двумя бегущими волнами: у берега прозрачная и с пеной,
   на глубине тёмная и зеркальная. Глубину шейдер берёт из карты,
   запечённой из рельефа, — поэтому линия прибоя повторяет берег. */

const WATER_VERT = `
varying vec2 vUv; varying vec3 vP; varying vec3 vW;
void main() {
  vUv = uv;
  vec4 wp = modelMatrix * vec4(position, 1.0);
  vW = wp.xyz;
  vP = (modelViewMatrix * vec4(position, 1.0)).xyz;
  gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
}`;

const WATER_FRAG = `
uniform sampler2D uDepth;
uniform vec3 uShallow; uniform vec3 uDeep; uniform vec3 uSun;
uniform float uTime;
varying vec2 vUv; varying vec3 vP; varying vec3 vW;

void main() {
  float depth = texture2D(uDepth, vUv).r;      // 0 — берег, 1 — глубоко

  // две бегущие волны крест-накрест дают рябь без текстуры
  float w1 = sin(vW.x * 0.16 + uTime * 1.1) * cos(vW.z * 0.13 - uTime * 0.8);
  float w2 = sin((vW.x + vW.z) * 0.09 - uTime * 0.6);
  vec3 n = normalize(vec3(w1 * 0.16 + w2 * 0.1, 1.0, w2 * 0.16 - w1 * 0.1));

  vec3 V = normalize(cameraPosition - vW);
  float fres = pow(1.0 - max(0.0, dot(n, V)), 3.0);

  // Глубина нормирована по самой глубокой точке карты, поэтому
  // цвет набирает силу быстро: у берега прозрачная бирюза,
  // на середине — тёмная толща.
  vec3 col = mix(uShallow, uDeep, smoothstep(0.02, 0.32, depth));
  col = mix(col, vec3(0.34, 0.48, 0.60), fres * 0.24);

  // солнечная дорожка
  vec3 H = normalize(normalize(uSun) + V);
  float spec = pow(max(0.0, dot(n, H)), 90.0);
  col += vec3(1.0, 0.94, 0.82) * spec * 1.5;

  // пена узкой полосой у самой кромки, дышит вместе с волной
  float edge = 1.0 - smoothstep(0.0, 0.022, depth);
  float foam = edge * (0.45 + 0.55 * sin(uTime * 1.8 + vW.x * 0.5 + vW.z * 0.4));
  col = mix(col, vec3(0.80, 0.88, 0.92), foam * 0.40);

  // У кромки вода прозрачная — сквозь неё виден грунт, и берег
  // читается как отмель, а не как обрезанный по линейке край.
  float alpha = clamp(0.22 + depth * 3.2 + fres * 0.35 + foam * 0.25, 0.0, 0.95);
  gl_FragColor = vec4(col, alpha);
}`;

export function buildWater(size, level, depthCanvas, tint) {
  const geo = new THREE.PlaneGeometry(size * 2, size * 2, 1, 1);
  geo.rotateX(-Math.PI / 2);
  const depth = new THREE.CanvasTexture(depthCanvas);
  depth.wrapS = depth.wrapT = THREE.ClampToEdgeWrapping;
  const mat = new THREE.ShaderMaterial({
    uniforms: {
      uDepth: { value: depth },
      uShallow: { value: new THREE.Color(tint && tint.shallow || 0x2f7f96) },
      uDeep: { value: new THREE.Color(tint && tint.deep || 0x0a2436) },
      uSun: { value: new THREE.Vector3(0.6, 0.7, 0.4).normalize() },
      uTime: { value: 0 },
    },
    vertexShader: WATER_VERT, fragmentShader: WATER_FRAG,
    transparent: true, depthWrite: false, side: THREE.DoubleSide,
  });
  const m = new THREE.Mesh(geo, mat);
  m.position.y = level;
  m.renderOrder = 2;
  m.userData.tick = t => { mat.uniforms.uTime.value = t; };
  m.userData.setSun = v => mat.uniforms.uSun.value.copy(v).normalize();
  return m;
}

/* ── ТРАВА И КУСТЫ ИНСТАНСАМИ.

   Ландшафт без подлеска читается как раскрашенная сетка, но
   насыпать десять тысяч отдельных мешей нельзя — каждый стоит
   отдельного вызова отрисовки, и планшет ляжет. InstancedMesh рисует
   всю траву за один вызов: геометрия одна, у каждого экземпляра своя
   матрица. Десять тысяч кустиков стоят столько же, сколько один.

   Сама травинка — два скрещённых прямоугольника с прозрачностью:
   с любой стороны видно плоскость, а не ребро. Прозрачность через
   alphaTest, а не blending, — тогда трава пишется в буфер глубины
   и не сортируется каждый кадр. */

function grassBlade() {
  const g = new THREE.BufferGeometry();
  const w = 0.5, h = 1.0;
  const quad = (ax, az) => [
    -w * ax, 0, -w * az,  w * ax, 0, w * az,  w * ax, h, w * az,
    -w * ax, 0, -w * az,  w * ax, h, w * az, -w * ax, h, -w * az,
  ];
  const pos = [...quad(1, 0), ...quad(0, 1)];
  const uvq = [0, 0, 1, 0, 1, 1, 0, 0, 1, 1, 0, 1];
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute([...uvq, ...uvq], 2));
  // нормаль вверх: трава ловит свет как поверхность, а не как стенка
  const n = new Array(12).fill(0).flatMap(() => [0, 1, 0]);
  g.setAttribute('normal', new THREE.Float32BufferAttribute(n, 3));
  return g;
}

let GRASS_TEX = null;
function grassTexture() {
  if (GRASS_TEX) return GRASS_TEX;
  const S = 64;
  const cv = document.createElement('canvas');
  cv.width = cv.height = S;
  const c = cv.getContext('2d');
  c.clearRect(0, 0, S, S);
  // пучок из нескольких сужающихся кверху лезвий
  for (let i = 0; i < 7; i++) {
    const x = S * (0.15 + Math.random() * 0.7);
    const top = S * (0.05 + Math.random() * 0.35);
    const lean = (Math.random() - 0.5) * S * 0.28;
    const wide = S * (0.035 + Math.random() * 0.03);
    const g = c.createLinearGradient(0, S, 0, top);
    g.addColorStop(0, 'rgba(70,86,44,1)');
    g.addColorStop(1, 'rgba(150,176,96,1)');
    c.fillStyle = g;
    c.beginPath();
    c.moveTo(x - wide, S);
    c.lineTo(x + wide, S);
    c.lineTo(x + lean, top);
    c.closePath();
    c.fill();
  }
  GRASS_TEX = new THREE.CanvasTexture(cv);
  GRASS_TEX.colorSpace = THREE.SRGBColorSpace;
  return GRASS_TEX;
}

/* Ковёр травы. sample(x, z) должен вернуть {y, ok} — высоту рельефа
   и можно ли туда сажать (не вода, не площадка базы). */
export function buildGrass(count, extent, sample, tint) {
  const geo = grassBlade();
  const mat = new THREE.MeshLambertMaterial({
    map: grassTexture(), color: tint || 0xffffff,
    transparent: false, alphaTest: 0.45, side: THREE.DoubleSide,
  });
  const mesh = new THREE.InstancedMesh(geo, mat, count);
  mesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
  const m = new THREE.Matrix4();
  const q = new THREE.Quaternion();
  const up = new THREE.Vector3(0, 1, 0);
  const scl = new THREE.Vector3();
  const pos = new THREE.Vector3();
  /* Сажаем купами, а не равномерной сеткой. Равномерная засыпка
     читается как шум по всему полю; куртинами трава выглядит живой,
     а между ними остаётся открытая земля, по которой видно рельеф. */
  let n = 0;
  for (let tries = 0; tries < count && n < count; tries++) {
    const cx = (Math.random() - 0.5) * extent * 2;
    const cz = (Math.random() - 0.5) * extent * 2;
    if (!sample(cx, cz)) continue;
    const inClump = 4 + (Math.random() * 7 | 0);
    const spread = 3 + Math.random() * 7;
    for (let k = 0; k < inClump && n < count; k++) {
      const x = cx + (Math.random() - 0.5) * spread * 2;
      const z = cz + (Math.random() - 0.5) * spread * 2;
      const s = sample(x, z);
      if (!s || !s.ok) continue;
      const h = 2.2 + Math.random() * 2.8;
      pos.set(x, s.y, z);
      q.setFromAxisAngle(up, Math.random() * Math.PI);
      scl.set(h * (0.7 + Math.random() * 0.6), h, h);
      m.compose(pos, q, scl);
      mesh.setMatrixAt(n++, m);
    }
  }
  mesh.count = n;
  mesh.instanceMatrix.needsUpdate = true;
  mesh.castShadow = false;
  mesh.frustumCulled = false;
  return mesh;
}

/* ── ЛИСТВА КАРТАМИ.
   Сплошной конус — это силуэт ёлки из восьмидесятых: у него нет ни
   просветов, ни рваного края, и в любом ракурсе он остаётся конусом.
   Настоящие игровые деревья делают иначе: несколько плоскостей с
   вырезанной по прозрачности листвой, поставленных крест-накрест.
   Крона получается рыхлой, сквозь неё видно небо, а стоит она
   столько же, сколько две плоскости. */

let LEAF_TEX = null;
function leafTexture() {
  if (LEAF_TEX) return LEAF_TEX;
  const S = 128;
  const cv = document.createElement('canvas');
  cv.width = cv.height = S;
  const c = cv.getContext('2d');
  c.clearRect(0, 0, S, S);
  // куст из полусотни листьев: к краю мельче и реже — рваный контур
  for (let i = 0; i < 90; i++) {
    const a = Math.random() * Math.PI * 2;
    const r = Math.pow(Math.random(), 0.62) * S * 0.46;
    const x = S / 2 + Math.cos(a) * r;
    const y = S / 2 + Math.sin(a) * r * 0.85;
    const size = S * (0.10 - r / S * 0.055) * (0.7 + Math.random() * 0.6);
    if (size < 1) continue;
    const shade = 42 + Math.random() * 58 - (r / S) * 26;
    c.fillStyle = `rgb(${Math.round(shade * 0.55)},${Math.round(shade * 1.5)},${Math.round(shade * 0.6)})`;
    c.save();
    c.translate(x, y);
    c.rotate(Math.random() * Math.PI);
    c.beginPath();
    c.ellipse(0, 0, size, size * 0.55, 0, 0, Math.PI * 2);
    c.fill();
    c.restore();
  }
  LEAF_TEX = new THREE.CanvasTexture(cv);
  LEAF_TEX.colorSpace = THREE.SRGBColorSpace;
  return LEAF_TEX;
}

// Крона: три плоскости крест-накрест, развёрнутые веером
function leafCardGeo() {
  const g = new THREE.BufferGeometry();
  const pos = [], uv = [], nrm = [];
  for (let k = 0; k < 3; k++) {
    const a = (k / 3) * Math.PI;
    const cx = Math.cos(a), cz = Math.sin(a);
    const quad = [
      [-cx, -1, -cz], [cx, -1, cz], [cx, 1, cz],
      [-cx, -1, -cz], [cx, 1, cz], [-cx, 1, -cz],
    ];
    for (const [x, y, z] of quad) { pos.push(x, y, z); nrm.push(0, 1, 0); }
    uv.push(0, 0, 1, 0, 1, 1, 0, 0, 1, 1, 0, 1);
  }
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  g.setAttribute('normal', new THREE.Float32BufferAttribute(nrm, 3));
  return g;
}

/* Деревья тем же приёмом: одна геометрия ствола и одна кроны на всю
   карту. Разнообразие даём наклоном, поворотом и размером — этого
   достаточно, чтобы лес не выглядел строем клонов. */
export function buildTreeField(count, extent, sample, biome) {
  const g = new THREE.Group();
  if (biome === 'ice' || biome === 'rock' || biome === 'city') return g;

  const trunkGeo = new THREE.CylinderGeometry(0.13, 0.26, 1, 6);
  trunkGeo.translate(0, 0.5, 0);
  const leafGeo = leafCardGeo();

  const desert = biome === 'desert';
  const trunkMat = new THREE.MeshLambertMaterial({ color: desert ? 0x6a5436 : 0x4a3a28 });
  const leafMat = new THREE.MeshLambertMaterial({
    map: leafTexture(), color: desert ? 0xb8b070 : 0xcfe8b0,
    alphaTest: 0.4, side: THREE.DoubleSide,
  });

  const trunks = new THREE.InstancedMesh(trunkGeo, trunkMat, count);
  const leaves = new THREE.InstancedMesh(leafGeo, leafMat, count * 3);

  const m = new THREE.Matrix4(), q = new THREE.Quaternion();
  const pos = new THREE.Vector3(), scl = new THREE.Vector3();
  const up = new THREE.Vector3(0, 1, 0);
  let n = 0, l = 0;
  for (let i = 0; i < count * 4 && n < count; i++) {
    const x = (Math.random() - 0.5) * extent * 2;
    const z = (Math.random() - 0.5) * extent * 2;
    const s = sample(x, z);
    if (!s || !s.ok) continue;
    const h = (desert ? 3.5 : 6) + Math.random() * (desert ? 2 : 6);
    const lean = (Math.random() - 0.5) * 0.14;
    q.setFromEuler(new THREE.Euler(lean, Math.random() * Math.PI * 2, lean * 0.6));

    pos.set(x, s.y, z);
    scl.set(h * 0.24, h, h * 0.24);
    m.compose(pos, q, scl);
    trunks.setMatrixAt(n, m);

    /* Крона — два-три пятна листвы вразнобой, а не один симметричный
       конус: смещаем их по горизонтали и меняем размер, тогда дерево
       читается как дерево с любой стороны. */
    const layers = desert ? 2 : 3;
    for (let k = 0; k < layers && l < leaves.count; k++) {
      const cw = h * (desert ? 0.34 : 0.30) * (1 - k * 0.18);
      const off = h * 0.09;
      pos.set(x + (Math.random() - 0.5) * off,
              s.y + h * (desert ? 0.72 : 0.6) + k * h * 0.14,
              z + (Math.random() - 0.5) * off);
      scl.set(cw, cw * (0.72 + Math.random() * 0.3), cw);
      q.setFromAxisAngle(up, Math.random() * Math.PI);
      m.compose(pos, q, scl);
      leaves.setMatrixAt(l++, m);
    }
    n++;
  }
  trunks.count = n; leaves.count = l;
  trunks.instanceMatrix.needsUpdate = true;
  leaves.instanceMatrix.needsUpdate = true;
  trunks.frustumCulled = leaves.frustumCulled = false;
  g.add(trunks, leaves);
  return g;
}

/* ── СЛЕДЫ ГУСЕНИЦ.

   Техника, проезжающая по чистому полю и не оставляющая ничего, —
   один из главных признаков, что поле не настоящее. Отпечатки живут
   в общем пуле: кольцевой буфер на несколько сотен, самый старый
   затирается новым. Один InstancedMesh на все следы, прозрачность
   у каждого своя — она приезжает отдельным атрибутом и гасится
   со временем, поэтому колея зарастает, а не исчезает разом. */

let TRACK_TEX = null;
function trackTexture() {
  if (TRACK_TEX) return TRACK_TEX;
  const S = 64;
  const cv = document.createElement('canvas');
  cv.width = cv.height = S;
  const c = cv.getContext('2d');
  c.clearRect(0, 0, S, S);
  // две колеи с поперечными грунтозацепами
  for (const cx of [S * 0.27, S * 0.73]) {
    c.fillStyle = 'rgba(255,255,255,0.5)';
    c.fillRect(cx - S * 0.11, 0, S * 0.22, S);
    c.fillStyle = 'rgba(255,255,255,0.95)';
    for (let y = 0; y < S; y += 7) {
      c.fillRect(cx - S * 0.13, y, S * 0.26, 3.4);
    }
  }
  TRACK_TEX = new THREE.CanvasTexture(cv);
  return TRACK_TEX;
}

export function buildTrackField(max = 420) {
  const geo = new THREE.PlaneGeometry(1, 1);
  geo.rotateX(-Math.PI / 2);
  const fade = new Float32Array(max);
  geo.setAttribute('aFade', new THREE.InstancedBufferAttribute(fade, 1));

  const mat = new THREE.MeshBasicMaterial({
    map: trackTexture(), color: 0x241c14,
    transparent: true, depthWrite: false, toneMapped: true,
  });
  mat.onBeforeCompile = sh => {
    sh.vertexShader = sh.vertexShader
      .replace('#include <common>', '#include <common>\nattribute float aFade;\nvarying float vFade;')
      .replace('#include <begin_vertex>', '#include <begin_vertex>\nvFade = aFade;');
    sh.fragmentShader = sh.fragmentShader
      .replace('#include <common>', '#include <common>\nvarying float vFade;')
      .replace('#include <map_fragment>', '#include <map_fragment>\ndiffuseColor.a *= vFade;');
  };

  const mesh = new THREE.InstancedMesh(geo, mat, max);
  mesh.frustumCulled = false;
  mesh.renderOrder = 1;          // поверх грунта, но под юнитами
  mesh.count = max;
  const m = new THREE.Matrix4(), q = new THREE.Quaternion();
  const p = new THREE.Vector3(), sc = new THREE.Vector3();
  const up = new THREE.Vector3(0, 1, 0);
  // все отпечатки начинают невидимыми
  for (let i = 0; i < max; i++) {
    m.compose(p.set(0, -9999, 0), q.identity(), sc.set(1, 1, 1));
    mesh.setMatrixAt(i, m);
  }
  mesh.instanceMatrix.needsUpdate = true;

  let head = 0;
  const life = new Float32Array(max);

  return {
    mesh,
    /* Положить отпечаток. y уже приподнят над рельефом: вровень
       с землёй он мерцает, борясь с ней за пиксели буфера глубины. */
    drop(x, y, z, heading, width, len) {
      const i = head; head = (head + 1) % max;
      p.set(x, y + 0.22, z);
      q.setFromAxisAngle(up, heading);
      sc.set(width, 1, len);
      m.compose(p, q, sc);
      mesh.setMatrixAt(i, m);
      life[i] = 1;
      fade[i] = 0.85;
      mesh.instanceMatrix.needsUpdate = true;
      geo.attributes.aFade.needsUpdate = true;
    },
    tick(dt) {
      let dirty = false;
      for (let i = 0; i < max; i++) {
        if (life[i] <= 0) continue;
        life[i] -= dt / 26;                // колея живёт около полминуты
        fade[i] = Math.max(0, life[i]) * 0.85;
        dirty = true;
      }
      if (dirty) geo.attributes.aFade.needsUpdate = true;
    },
  };
}

// Поле снабжения на наземной карте
export function buildSupplyField() {
  const g = new THREE.Group();
  const crate = mat(0xb8a05a, { rough: 0.8, metal: 0.2, emissive: 0x3a2f10, ei: 0.6 });
  const dark = mat(0x3a352c, { rough: 0.95 });
  g.add(cyl(7, 0.4, dark, 0, 0.2, 0));
  for (let i = 0; i < 7; i++) {
    const a = (i / 7) * Math.PI * 2, r = 3.2;
    const b = box(1.8, 1.4, 1.8, crate, Math.cos(a) * r, 0.9, Math.sin(a) * r);
    b.rotation.y = a;
    g.add(b);
  }
  g.add(box(2.4, 2.0, 2.4, crate, 0, 1.2, 0));
  return g;
}

// ─────────────────────────────────────────────────────────────
// ПЛАНЕТЫ
// Поверхность, облака и атмосферный ободок. Текстуры процедурные
// (textures.js), считаются один раз на биом и кладутся в кэш.
// ─────────────────────────────────────────────────────────────

/* КУПОЛ РЭБ.
   Сфера помех: сетка меридианов, бегущая рябь и подсветка по краю.
   Режим глушения — цвет клана, защитный — холодный белый. */

const DOME_VERT = `
varying vec3 vN; varying vec3 vP; varying vec2 vUv;
void main() {
  vN = normalize(normalMatrix * normal);
  vP = (modelViewMatrix * vec4(position, 1.0)).xyz;
  vUv = uv;
  gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
}`;

const DOME_FRAG = `
uniform vec3 uColor; uniform float uTime; uniform float uPower;
varying vec3 vN; varying vec3 vP; varying vec2 vUv;
void main() {
  // ободок по касательной — купол читается как оболочка, а не как шар
  // Купол должен читаться как граница, а не как молочная стена:
  // почти вся яркость уходит в тонкий ободок по касательной.
  float rim = pow(1.0 - abs(dot(normalize(vN), normalize(-vP))), 4.0);
  float grid = max(
    smoothstep(0.985, 1.0, abs(sin(vUv.x * 62.831))),
    smoothstep(0.990, 1.0, abs(sin(vUv.y * 37.699))));
  float wave = smoothstep(0.14, 0.0, abs(fract(vUv.y * 2.0 - uTime * 0.35) - 0.5));
  /* Поле должно ЧИТАТЬСЯ, а не закрывать бой. Почти вся яркость —
     в тонкой кромке по касательной; сетка и бегущая волна оставлены
     на уровне намёка. Раньше эти числа были втрое выше, и купол
     перекрывал собой всё, что под ним происходило. */
  float a = (rim * 0.11 + grid * 0.035 + wave * 0.015) * uPower;
  gl_FragColor = vec4(uColor * (0.7 + wave * 0.4), a);
}`;

/* Поле помех — плоский блин в плоскости боя, а не шар: сразу видно,
   кто под ним, а кто уже вышел. Излучатель — на брюхе корабля,
   от него вниз идёт луч, раскрывающий блин. */
export function buildEcmDome(radius, color, height) {
  const g = new THREE.Group();
  const h = height || radius * 0.22;

  // Обод блина: открытый цилиндр
  const mkMat = () => new THREE.ShaderMaterial({
    uniforms: {
      uColor: { value: new THREE.Color(color) },
      uTime: { value: 0 }, uPower: { value: 0 },
    },
    vertexShader: DOME_VERT, fragmentShader: DOME_FRAG,
    transparent: true, depthWrite: false, side: THREE.DoubleSide,
    blending: THREE.AdditiveBlending, toneMapped: true,
  });

  const edgeMat = mkMat();
  const edge = new THREE.Mesh(new THREE.CylinderGeometry(1, 1, 1, 72, 1, true), edgeMat);
  edge.scale.set(radius, h, radius);
  g.add(edge);

  // Плоскости блина: сверху и снизу, почти прозрачные
  const faceMat = mkMat();
  const faceGeo = new THREE.RingGeometry(0.12, 1, 72, 1);
  faceGeo.rotateX(-Math.PI / 2);
  for (const sy of [-1, 1]) {
    const f = new THREE.Mesh(faceGeo, faceMat);
    f.scale.set(radius, 1, radius);
    f.position.y = sy * h * 0.5;
    g.add(f);
  }

  // Яркий контур по краю — граница поля читается мгновенно
  const rimGeo = new THREE.TorusGeometry(1, 0.006, 6, 96);
  rimGeo.rotateX(Math.PI / 2);
  const rimMat = new THREE.MeshBasicMaterial({
    color, transparent: true, opacity: 0.45,
    blending: THREE.AdditiveBlending, depthWrite: false, toneMapped: true,
  });
  const rims = [];
  for (const sy of [-1, 1]) {
    const r = new THREE.Mesh(rimGeo, rimMat);
    r.scale.set(radius, radius, radius);
    r.position.y = sy * h * 0.5;
    g.add(r);
    rims.push(r);
  }

  // Луч от излучателя вниз к плоскости блина
  const beamGeo = new THREE.CylinderGeometry(1, 1, 1, 12, 1, true);
  const beamMat = new THREE.MeshBasicMaterial({
    color, transparent: true, opacity: 0.22,
    blending: THREE.AdditiveBlending, depthWrite: false, toneMapped: true,
  });
  const beam = new THREE.Mesh(beamGeo, beamMat);
  g.add(beam);

  g.renderOrder = 3;
  g.userData.set = (t, power, col, emitY) => {
    // Плоскости блина светятся вчетверо слабее обода: именно они
    // раньше заливали молоком всё, что происходило под полем.
    for (const [m, k] of [[edgeMat, 1], [faceMat, 0.25]]) {
      m.uniforms.uTime.value = t;
      m.uniforms.uPower.value = power * k;
      if (col !== undefined) m.uniforms.uColor.value.set(col);
    }
    if (col !== undefined) { rimMat.color.set(col); beamMat.color.set(col); }
    rimMat.opacity = power * 0.55;
    const k = 0.25 + power * 0.75;          // блин раскрывается от точки
    edge.scale.set(radius * k, h, radius * k);
    for (const r of rims) r.scale.set(radius * k, radius * k, radius * k);
    // луч от излучателя до плоскости поля
    const ey = emitY === undefined ? 0 : emitY;
    beam.scale.set(radius * 0.035, Math.max(0.001, Math.abs(ey)), radius * 0.035);
    beam.position.y = ey * 0.5;
    beamMat.opacity = power * 0.45;
  };
  return g;
}

/* ГИПЕРВОРОНКА.
   Вращающийся раструб с бегущими внутрь кольцами и переливами от
   синего к фиолетовому. Открывается перед кораблём, который уходит,
   и перед тем, который выходит из гипера. */

const VORTEX_VERT = `
varying vec2 vUv;
void main() {
  vUv = uv;
  gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
}`;

const VORTEX_FRAG = `
uniform float uTime;
uniform float uOpen;
varying vec2 vUv;

void main() {
  // Кольца бегут вглубь воронки
  float rings = fract(vUv.y * 4.0 - uTime * 1.6);
  float band = smoothstep(0.0, 0.35, rings) * smoothstep(1.0, 0.62, rings);

  // Переливы: оттенок гуляет по окружности и во времени
  float hue = vUv.x * 3.0 + uTime * 0.7 + vUv.y * 1.4;
  vec3 cold = vec3(0.24, 0.55, 1.00);
  vec3 warm = vec3(0.62, 0.42, 1.00);
  vec3 tint = mix(cold, warm, 0.5 + 0.5 * sin(hue * 3.14159));
  tint = mix(tint, vec3(0.80, 0.95, 1.0), pow(vUv.y, 3.0));

  // Горловина ярче устья, края растворяются
  float depth = pow(vUv.y, 1.6);
  float a = (0.20 + band * 0.85) * depth * uOpen;
  a *= smoothstep(0.0, 0.12, vUv.y);

  gl_FragColor = vec4(tint * (1.2 + band * 1.6), a);
}`;

export function buildHyperVortex(radius) {
  const g = new THREE.Group();
  // раструб: широкое устье у корабля, узкая горловина вдали
  const geo = new THREE.CylinderGeometry(radius * 0.18, radius, radius * 3.4, 40, 10, true);
  geo.rotateX(-Math.PI / 2);       // ось вдоль −Z, горловина в −Z
  geo.translate(0, 0, -radius * 1.7);
  const mat = new THREE.ShaderMaterial({
    uniforms: { uTime: { value: 0 }, uOpen: { value: 0 } },
    vertexShader: VORTEX_VERT, fragmentShader: VORTEX_FRAG,
    transparent: true, depthWrite: false, side: THREE.BackSide,
    blending: THREE.AdditiveBlending, toneMapped: false,
  });
  const tube = new THREE.Mesh(geo, mat);
  g.add(tube);

  // светящееся ядро в горловине
  const core = glowSprite(radius * 1.4, 0x9fd8ff);
  core.position.z = -radius * 3.2;
  g.add(core);

  // кольцо на устье
  const ringGeo = new THREE.RingGeometry(radius * 0.92, radius * 1.12, 48);
  const ring = new THREE.Mesh(ringGeo, new THREE.MeshBasicMaterial({
    color: 0xaee0ff, transparent: true, opacity: 0.9, side: THREE.DoubleSide,
    blending: THREE.AdditiveBlending, depthWrite: false, toneMapped: false,
  }));
  g.add(ring);

  g.userData.update = (t, open) => {
    mat.uniforms.uTime.value = t;
    mat.uniforms.uOpen.value = open;
    tube.rotation.z = t * 1.1;
    ring.rotation.z = -t * 0.8;
    ring.material.opacity = open * 0.9;
    ring.scale.setScalar(0.6 + open * 0.4);
    core.scale.setScalar(radius * (0.6 + open * 1.2));
    core.material.opacity = open;
  };
  return g;
}

/* Атмосфера. Ободок по касательной, но яркость зависит от того,
   с какой стороны звезда: на освещённом крае — плотный голубой венец,
   на теневом — почти ничего. Это и даёт узнаваемый вид планеты
   из космоса, а не «шарик с каёмкой». */

const ATMO_VERT = `
varying vec3 vN; varying vec3 vP; varying vec3 vWN;
void main() {
  vN = normalize(normalMatrix * normal);
  vWN = normalize(mat3(modelMatrix) * normal);
  vP = (modelViewMatrix * vec4(position, 1.0)).xyz;
  gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
}`;

const ATMO_FRAG = `
uniform vec3 uColor; uniform float uPower; uniform vec3 uSun;
varying vec3 vN; varying vec3 vP; varying vec3 vWN;
void main() {
  float rim = pow(1.0 - abs(dot(normalize(vN), normalize(-vP))), 3.0);
  float sun = max(0.0, dot(normalize(vWN), normalize(uSun)));
  // рассеяние вперёд: у терминатора венец горячее
  float glow = rim * (0.12 + pow(sun, 0.7) * 1.9);
  vec3 tint = mix(uColor * 0.7, uColor + vec3(0.25, 0.18, 0.10), pow(sun, 2.0));
  gl_FragColor = vec4(tint, clamp(glow * uPower, 0.0, 1.0));
}`;

function sphereGeo(segments) {
  const g = new THREE.SphereGeometry(1, segments, Math.round(segments / 2));
  g.userData.shared = true;
  return g;
}
const GEO_HI = sphereGeo(96);
const GEO_MID = sphereGeo(48);
const GEO_LO = sphereGeo(24);

export function buildPlanet(biome, radius, seed, id) {
  // Крупная развёртка только той планете, что во весь экран в бою;
  // мирам на карте системы хватает мелкой, и экран не подвисает
  const tex = planetTextures(biome, seed === undefined ? 1 : seed, id || null,
    radius > 400 ? 2 : radius > 20 ? 1 : 0);
  const g = new THREE.Group();
  const geo = radius > 400 ? GEO_HI : radius > 40 ? GEO_MID : GEO_LO;

  const surface = new THREE.MeshStandardMaterial({
    map: tex.map,
    normalMap: tex.normalMap,
    normalScale: new THREE.Vector2(1.1, 1.1),
    roughnessMap: tex.roughnessMap,
    roughness: 1, metalness: 0.05,
    // Освещённая сторона иначе выбивается в белое: чуть притемняем
    color: 0xc8c4bc,
    emissiveMap: tex.emissiveMap || null,
    emissive: tex.emissiveMap ? 0xffffff : 0x000000,
    emissiveIntensity: tex.emissiveMap ? 1.4 : 0,
    envMapIntensity: 0.35,
  });
  const sphere = new THREE.Mesh(geo, surface);
  sphere.scale.setScalar(radius);
  g.add(sphere);

  // Облака отдельной оболочкой — вращаются сами и ловят свет у терминатора
  const clouds = new THREE.Mesh(geo, new THREE.MeshStandardMaterial({
    map: tex.cloudMap, transparent: true, opacity: 0.9,
    roughness: 0.95, metalness: 0, depthWrite: false, envMapIntensity: 0.2,
  }));
  clouds.scale.setScalar(radius * 1.012);
  g.add(clouds);

  const atmoMat = new THREE.ShaderMaterial({
    uniforms: {
      uColor: { value: new THREE.Color(tex.atmo) },
      uPower: { value: tex.atmoPower * 7.5 },
      uSun: { value: new THREE.Vector3(-1, 0.5, -0.4).normalize() },
    },
    vertexShader: ATMO_VERT, fragmentShader: ATMO_FRAG,
    side: THREE.BackSide, transparent: true, depthWrite: false,
    blending: THREE.AdditiveBlending,
  });
  const atmo = new THREE.Mesh(geo, atmoMat);
  atmo.scale.setScalar(radius * 1.055);
  g.add(atmo);

  g.userData.sphere = sphere;
  g.userData.clouds = clouds;
  // Сцена сообщает планете, где звезда — от этого зависит венец
  g.userData.setSun = v => atmoMat.uniforms.uSun.value.copy(v).normalize();
  return g;
}

// Фон космоса: туманность на дальней сфере. Ставится в scene.background
// нельзя — там нужен куб, поэтому это просто очень большая сфера.
export function buildNebula(radius = 5200, seed = 11) {
  // toneMapped обязателен: иначе яркие точки фона проскакивают мимо
  // тональной компрессии и свечение превращает их в белые пятна.
  const m = new THREE.MeshBasicMaterial({
    map: nebulaTexture(seed), side: THREE.BackSide,
    depthWrite: false, toneMapped: true, fog: false,
  });
  const mesh = new THREE.Mesh(GEO_MID, m);
  mesh.scale.setScalar(radius);
  mesh.frustumCulled = false;
  mesh.renderOrder = -1000;
  return mesh;
}

export { mat, glowMat, glowSprite, box, cyl, cone, sph };
