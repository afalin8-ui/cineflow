/* Модели: собираем корабли, технику и здания из примитивов.
   Никаких внешних файлов — всё коробки, цилиндры и конусы.
   У каждой фракции свой силуэт:
     sleek  (Директорат) — вытянутый, гранёный, аккуратный
     heavy  (Гегемония)  — плиты, блоки, ничего лишнего
     scrap  (Синдикат)   — несимметричный, из подручного хлама  */

import { THREE, rnd, GLOW_TEX } from './engine.js';
import { customModel } from './assets.js';

const matCache = new Map();
function mat(color, opts = {}) {
  const key = color + '|' + JSON.stringify(opts);
  let m = matCache.get(key);
  if (!m) {
    m = new THREE.MeshStandardMaterial({
      color, roughness: opts.rough ?? 0.7, metalness: opts.metal ?? 0.35,
      emissive: opts.emissive ?? 0x000000, emissiveIntensity: opts.ei ?? 1,
      transparent: !!opts.transparent, opacity: opts.opacity ?? 1,
      flatShading: opts.flat !== false,
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
  for (let i = 0; i < en; i++) {
    const x = (i - (en - 1) / 2) * halfW * 0.55;
    const sp = glowSprite(def.radius * 1.1, 0x7fd4ff);
    sp.position.set(x, 0, halfL * 0.98);
    g.add(sp);
    engines.push(sp);
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
  const hullColor = style === 'heavy' ? 0x6b625a : style === 'scrap' ? 0x6a6358 : 0x8d94a0;
  const darkColor = style === 'heavy' ? 0x3b342f : style === 'scrap' ? 0x39342d : 0x454b55;
  const hull = mat(hullColor, { rough: 0.75, metal: 0.4 });
  const dark = mat(darkColor, { rough: 0.85, metal: 0.3 });
  const trim = mat(faction.color, { rough: 0.5, metal: 0.5, emissive: faction.color, ei: 0.25 });

  const R = def.radius;
  const L = R * (def.cls === 'escort' ? 3.4 : def.cls === 'carrier' ? 3.0 : 3.6);
  const muzzles = [], pdPoints = [], engines = [];

  const addEngine = (x, y, z, size) => {
    const s = glowSprite(size, 0x7fd4ff);
    s.position.set(x, y, z);
    g.add(s);
    engines.push(s);
    g.add(cyl(size * 0.28, size * 0.5, dark, x, y, z - size * 0.25).rotateX(Math.PI / 2));
  };

  if (def.cls === 'escort') {
    // Узкий клин с двумя мотогондолами
    const body = box(R * 0.7, R * 0.5, L, hull, 0, 0, 0);
    g.add(body);
    g.add(cone(R * 0.42, R * 1.5, hull, 0, 0, -L * 0.5 - R * 0.55).rotateX(-Math.PI / 2));
    g.add(box(R * 1.9, R * 0.16, R * 0.9, dark, 0, 0, L * 0.05));
    g.add(box(R * 0.34, R * 0.34, R * 1.1, trim, 0, R * 0.3, -L * 0.1));
    if (style === 'scrap') g.add(box(R * 0.5, R * 0.4, R * 0.8, dark, R * 0.6, R * 0.25, L * 0.15));
    addEngine(-R * 0.45, 0, L * 0.52, R * 1.1);
    addEngine(R * 0.45, 0, L * 0.52, R * 1.1);
    muzzles.push(new THREE.Vector3(0, R * 0.32, -L * 0.55));
    pdPoints.push(new THREE.Vector3(-R * 0.8, R * 0.2, 0), new THREE.Vector3(R * 0.8, R * 0.2, 0),
                  new THREE.Vector3(0, -R * 0.3, L * 0.2));
  } else if (def.cls === 'carrier') {
    // Плоская широкая палуба с ангарной щелью
    const W = R * 1.9;
    g.add(box(W, R * 0.55, L, hull));
    g.add(box(W * 0.55, R * 0.62, L * 0.9, dark, 0, R * 0.05, 0));   // тёмная полоса палубы
    g.add(box(W * 0.34, R * 0.75, R * 0.9, dark, 0, R * 0.1, -L * 0.5 + R * 0.3)); // зев ангара
    const bayLight = glowSprite(R * 1.1, 0xffc27a);
    bayLight.position.set(0, R * 0.1, -L * 0.5 + R * 0.2);
    g.add(bayLight);
    // надстройка
    g.add(box(R * 0.5, R * 0.9, R * 1.6, hull, W * 0.42, R * 0.6, L * 0.2));
    g.add(box(R * 0.34, R * 0.34, R * 0.34, trim, W * 0.42, R * 1.15, L * 0.2));
    // «рёбра» палубы
    for (let i = -2; i <= 2; i++) g.add(box(W * 1.02, R * 0.1, R * 0.14, trim, 0, R * 0.3, i * L * 0.16));
    if (style === 'heavy') g.add(box(W * 1.15, R * 0.3, R * 1.2, dark, 0, -R * 0.2, L * 0.3));
    if (style === 'scrap') {
      g.add(cyl(R * 0.4, R * 1.4, dark, -W * 0.45, R * 0.5, L * 0.1));
      g.add(box(R * 0.7, R * 0.5, R * 0.7, dark, -W * 0.3, R * 0.6, -L * 0.2));
    }
    addEngine(-W * 0.32, 0, L * 0.54, R * 1.3);
    addEngine(0, 0, L * 0.54, R * 1.1);
    addEngine(W * 0.32, 0, L * 0.54, R * 1.3);
    pdPoints.push(
      new THREE.Vector3(-W * 0.5, R * 0.4, -L * 0.25), new THREE.Vector3(W * 0.5, R * 0.4, -L * 0.25),
      new THREE.Vector3(-W * 0.5, R * 0.4, L * 0.25), new THREE.Vector3(W * 0.5, R * 0.4, L * 0.25),
    );
    g.userData.bay = new THREE.Vector3(0, R * 0.1, -L * 0.55);
  } else if (def.station) {
    // Орбитальная крепость: кольцо + ядро
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
    // Крейсер / линкор: длинный корпус, хребет, башни
    const W = R * (style === 'heavy' ? 1.1 : 0.85);
    g.add(box(W, R * 0.7, L, hull));
    g.add(box(W * 0.75, R * 0.95, L * 0.55, hull, 0, R * 0.35, L * 0.1)); // надстройка
    if (style === 'heavy') {
      g.add(box(W * 1.25, R * 0.34, L * 0.7, dark, 0, 0, 0));       // броневой пояс
      g.add(box(W * 0.8, R * 0.5, R * 1.2, dark, 0, R * 0.7, L * 0.2));
    } else if (style === 'sleek') {
      g.add(box(W * 1.7, R * 0.14, L * 0.42, hull, 0, 0, L * 0.08)); // крылья-радиаторы
      g.add(box(W * 1.75, R * 0.08, R * 0.3, trim, 0, R * 0.02, L * 0.08));
    } else {
      g.add(cyl(R * 0.3, L * 0.7, dark, W * 0.6, R * 0.1, L * 0.05));
      g.add(box(W * 0.6, R * 0.5, R * 1.4, dark, -W * 0.55, R * 0.3, -L * 0.1));
    }
    // нос
    g.add(cone(W * 0.52, R * 2.0, hull, 0, 0, -L * 0.5 - R * 0.7).rotateX(-Math.PI / 2));
    // орудийные башни
    const turretCount = def.id === 'capital' ? 2 : 1;
    for (let i = 0; i < turretCount; i++) {
      const z = -L * (0.3 - i * 0.22);
      const t = new THREE.Group();
      t.add(cyl(R * 0.38, R * 0.3, dark, 0, 0, 0));
      t.add(box(R * 0.44, R * 0.3, R * 0.9, trim, 0, R * 0.16, -R * 0.35));
      t.add(cyl(R * 0.1, R * 1.5, dark, 0, R * 0.16, -R * 0.9).rotateX(Math.PI / 2));
      t.position.set(0, R * 0.4, z);
      g.add(t);
      muzzles.push(new THREE.Vector3(0, R * 0.55, z - R * 1.5));
    }
    // ПВО по бортам
    const n = def.pd ? def.pd.count : 3;
    for (let i = 0; i < n; i++) {
      const side = i % 2 ? 1 : -1;
      const z = (-0.35 + (Math.floor(i / 2) / Math.max(1, Math.ceil(n / 2) - 1 || 1)) * 0.7) * L;
      pdPoints.push(new THREE.Vector3(side * W * 0.6, R * 0.3, isFinite(z) ? z : 0));
      g.add(box(R * 0.16, R * 0.16, R * 0.3, dark, side * W * 0.6, R * 0.42, isFinite(z) ? z : 0));
    }
    const en = def.cls === 'capital' && def.id === 'capital' ? 3 : 2;
    for (let i = 0; i < en; i++) {
      const x = en === 3 ? (i - 1) * W * 0.42 : (i - 0.5) * W * 0.7;
      addEngine(x, 0, L * 0.52, R * 1.25);
    }
  }

  g.userData.muzzles = muzzles.length ? muzzles : [new THREE.Vector3(0, 0, -L * 0.5)];
  g.userData.pdPoints = pdPoints.length ? pdPoints : [new THREE.Vector3(0, 0, 0)];
  g.userData.engines = engines;
  if (!g.userData.bay) g.userData.bay = new THREE.Vector3(0, -R * 0.4, 0);
  return g;
}

// Малая авиация: три силуэта по ролям
export function buildStrike(role, faction) {
  const custom = fitCustom('strike', faction, role, 5.5);
  if (custom) {
    const ext = custom.userData.ext;
    const sp = glowSprite(1.0, 0x8fd8ff);
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
  const e = glowSprite(0.9, 0x8fd8ff);
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
      const sp = glowSprite(1.6, 0x8fd8ff);
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
      const e1 = glowSprite(2.0, 0x8fd8ff); e1.position.set(-1.6, -0.3, 2.1); g.add(e1);
      const e2 = glowSprite(2.0, 0x8fd8ff); e2.position.set(1.6, -0.3, 2.1); g.add(e2);
      g.userData.engines = [e1, e2];
      muzzles.push(new THREE.Vector3(0, -0.4, -2.0));
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
// ПЛАНЕТЫ (галактическая карта)
// ─────────────────────────────────────────────────────────────

const PLANET_GEO = new THREE.SphereGeometry(1, 28, 20);
PLANET_GEO.userData.shared = true;

export function buildPlanet(biome, radius) {
  const colors = {
    city:   [0x4b5560, 0x76839a],
    green:  [0x3f6b46, 0x6f9a5c],
    rock:   [0x6b5744, 0x8a7358],
    ice:    [0x8fa8b8, 0xd6e6ef],
    desert: [0xa08858, 0xc8ab72],
  }[biome] || [0x66707a, 0x8a95a0];

  const g = new THREE.Group();
  const surface = new THREE.MeshStandardMaterial({
    color: colors[0], roughness: 0.95, metalness: 0.05, flatShading: true,
  });
  const sphere = new THREE.Mesh(PLANET_GEO, surface);
  sphere.scale.setScalar(radius);
  g.add(sphere);

  // «Континенты» — несколько плоских пятен на поверхности
  const patch = new THREE.MeshStandardMaterial({ color: colors[1], roughness: 0.9, flatShading: true });
  for (let i = 0; i < 6; i++) {
    const p = new THREE.Mesh(PLANET_GEO, patch);
    const s = radius * rnd(0.25, 0.5);
    p.scale.set(s, s * 0.35, s);
    const u = rnd(-1, 1), a = rnd(0, Math.PI * 2), k = Math.sqrt(1 - u * u);
    p.position.set(Math.cos(a) * k, u, Math.sin(a) * k).multiplyScalar(radius * 0.94);
    p.lookAt(0, 0, 0);
    p.rotateX(Math.PI / 2);
    g.add(p);
  }
  // Атмосфера
  const atmo = new THREE.Mesh(PLANET_GEO, new THREE.MeshBasicMaterial({
    color: biome === 'ice' ? 0x9fd0ff : biome === 'desert' ? 0xffcf90 : 0x8fc4ff,
    transparent: true, opacity: 0.13, side: THREE.BackSide, depthWrite: false, toneMapped: false,
  }));
  atmo.scale.setScalar(radius * 1.12);
  g.add(atmo);
  g.userData.sphere = sphere;
  return g;
}

export { mat, glowMat, glowSprite, box, cyl, cone, sph };
