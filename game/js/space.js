/* КОСМИЧЕСКИЙ БОЙ — по правилам Homeplanet.

   Инерция. У корабля есть вектор скорости; двигатель даёт ускорение,
   а не скорость. Линкор разгоняется и тормозит по нескольку секунд,
   и всё это время летит туда, куда его несёт. Разворот корпуса от
   вектора не зависит — корабль скользит боком, держа цель в прицеле.

   Главный калибр. Раз в 9–17 секунд, зато сносит цель почти целиком.
   Перед выстрелом видна накачка. По истребителям не наводится вообще.

   ПВО работает само и только по мелочи. Авианосец почти безоружен,
   его сила — три типа машин: перехватчик против авиации, истребитель
   по всему средне, бомбардировщик против крупных кораблей. */

import {
  THREE, TacticalCamera, Controls, Fx, starfield, screenOf, ringMesh,
  clamp, lerp, rnd, disposeScene, IS_TOUCH, createMinimap, effectHit,
} from './engine.js';
import {
  buildShip, buildStrike, buildTorpedo, buildPlanet, buildNebula, buildHyperVortex, buildEcmDome,
  planetRings, visualLength,
} from './models.js';
import { nebulaTexture } from './textures.js';
import {
  FACTIONS, STRIKE, STRIKE_ROLES, SPACE_DMG, SQUAD_SIZE_OF, STATION, STEALTH, HYPER,
  ECM, ECM_OF, ORBITAL_DEFENCE_OF, SPACE_STANCES, SPACE_STANCE_IDS, SPACE_MOVE,
  dmgMult, shipDef, diffOf,
} from './data.js';
import { sound } from './audio.js';

const UP = new THREE.Vector3(0, 1, 0);
const ALT_UP = new THREE.Vector3(0, 0, 1);
const ZERO = new THREE.Vector3();
const _m4 = new THREE.Matrix4();
const _q = new THREE.Quaternion();
const _v = new THREE.Vector3();
const _v2 = new THREE.Vector3();
const _v3 = new THREE.Vector3();

/* СВОЙ И ЧУЖОЙ — ЖЁСТКАЯ ПАРА ЦВЕТОВ, НЕ ЗАВИСЯЩАЯ ОТ КЛАНА (C43).
   Цвета кланов близки (Тройден и Рииз оба бирюзовые), а в быстром бою
   можно взять один клан за обе стороны — модели тогда одинаковы, и по
   цвету клана своих от чужих не отличить вовсе. Поэтому подписи,
   полоски прочности, кольца выделения и наведения, купола РЭБ и
   миникарта красятся по СТОРОНЕ: свои — мятные, чужие — красные.
   Цвет клана остался акцентом: точка в шапке и отделка корпуса. */
const MINE_CSS = '#8fffc8', FOE_CSS = '#ff6b5a';
const MINE_DIM = '#5ce0a0', FOE_DIM = '#e05a4a';
const MINE_HEX = 0x8fffc8, FOE_HEX = 0xff6b5a;

// Окружность единичного радиуса в плоскости боя — кольца выделения и наведения
const CIRCLE_GEO = (() => {
  const pts = [];
  for (let i = 0; i < 96; i++) { const a = i / 96 * Math.PI * 2; pts.push(Math.cos(a), 0, Math.sin(a)); }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pts, 3));
  g.userData.shared = true;
  return g;
})();
function circleLine(color, opacity) {
  const l = new THREE.LineLoop(CIRCLE_GEO, new THREE.LineBasicMaterial({
    color, transparent: true, opacity, depthWrite: false, toneMapped: false,
  }));
  l.renderOrder = 5;
  l.frustumCulled = false;
  return l;
}

function quatFromDir(dir, out) {
  const up = Math.abs(dir.y) > 0.985 ? ALT_UP : UP;
  _m4.lookAt(ZERO, dir, up);
  return (out || _q).setFromRotationMatrix(_m4);
}

const FIELD = 2600;   // половина размера поля боя

export function createSpaceBattle(ctx, config) {
  const { viewport, hudRoot } = ctx;
  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0x03050a);

  const tcam = new TacticalCamera({
    // Стартовая точка и расстояние — в конце createSpaceBattle (C76)
    dist: 1100, maxDist: 3400, minDist: 45, pitch: 0.52, yaw: 0,
    bounds: { x: FIELD, z: FIELD, y: 600 }, far: 9000, allowY: true,
    // Буквы здесь — приказы (A — атака с ходу, S — стоп): камера на
    // стрелках, у края экрана и на средней кнопке (C50)
    wasd: false, edge: true,
  });

  /* Свет по референсам: холодный сине-фиолетовый объём и тёплый
     ключ сбоку. Корабль в таком свете читается силуэтом с горячей
     кромкой, а не серой коробкой, равномерно залитой со всех
     сторон. Заливки мало нарочно: иначе теневая сторона планеты
     начинает светиться. */
  scene.add(new THREE.AmbientLight(0x3d4a72, 0.42));
  const key = new THREE.DirectionalLight(0xffdcb0, 3.2);
  key.position.set(-500, 400, -300);
  scene.add(key);
  const fill = new THREE.DirectionalLight(0x5a4d9a, 0.75);
  fill.position.set(400, -250, 500);
  scene.add(fill);
  // Свет «со стороны зрителя»: без него корпуса на теневой стороне
  // превращаются в чёрные силуэты и корабль перестаёт читаться.
  const headlight = new THREE.DirectionalLight(0xdfe8ff, 0.85);
  scene.add(headlight);

  scene.add(buildNebula(5200, config.nebulaSeed || 11));
  // Отражения: металл должен что-то отражать, иначе он чёрный
  scene.environment = viewport.environmentFrom(nebulaTexture(config.nebulaSeed || 11));
  scene.environmentIntensity = 1.6;
  scene.add(starfield(4800, 4600));

  // Планета под ногами — бой идёт на её орбите
  // Планета под ногами — бой идёт на её орбите
  const planet = buildPlanet(config.biome || 'rock', 1150, config.planetSeed || 1, config.system);
  planet.position.set(340, -1560, -420);
  // Направление на звезду: от него зависит терминатор и венец атмосферы
  planet.userData.setSun(key.position.clone().normalize());
  scene.add(planet);

  /* Кольцо есть НЕ У ВСЕХ миров: в самом Homeplanet окольцована одна
     планета на систему, и именно поэтому она запоминается. Признак
     приходит с карты (`rings` у системы в data.js). Полоса тонкая,
     тёмная и почти с ребра — не золотая арка во весь экран. */
  if (config.rings) {
    const rings = planetRings(1150 * 1.35, 1150 * 1.95, config.planetSeed || 1);
    rings.position.copy(planet.position);
    rings.rotation.set(-Math.PI / 2 + 0.13, 0, 0.1);
    scene.add(rings);
  }

  viewport.setBloom({ strength: 0.72, radius: 0.55, threshold: 0.85, exposure: 0.92 });
  const fx = new Fx(scene);
  fx.setCamera(tcam.cam);

  /* ── ДАВЛЕНИЕ ЗЕМЛИ ──────────────────────────────────────
     Если у защитника на планете стоит противоорбитальное орудие, оно
     бьёт снизу вверх с постоянным периодом. Таймер виден в шапке:
     атакующий может рассчитать заход, но выжидать не выйдет.

     Стреляет орудие ВСЕГДА по атакующему — это оборона планеты,
     а не оружие поля боя. Поэтому в обороне игрока оно помогает. */
  const GUN_ORIGIN = new THREE.Vector3(340, -1180, -420);   // макушка планеты

  function gunTargets() {
    return state.ships.filter(e => !e.dead && !e.hyper && e.side === state.gun.side);
  }

  function updateGroundGun(dt) {
    const g = state.gun;
    if (!g) return;
    const list = gunTargets();
    if (!list.length) return;

    // предупреждение: наводка загорается заранее, от неё можно уйти
    if (!g.warned && state.time >= g.next - g.def.warn) {
      g.warned = true;
      g.aim = list[Math.floor(rnd(0, list.length))].pos.clone();
      toast(`Планета наводит: ${g.def.name}`);
      if (g.side === state.playerSide) sound.ui('warn');
      fx.ring(g.aim, 6, g.def.kind === 'nuke' ? g.def.radius : 60, g.def.color, g.def.warn);
    }
    if (state.time < g.next) return;

    fireGroundGun(g, list);
    g.next = state.time + g.def.period;
    g.warned = false;
    g.aim = null;
  }

  function fireGroundGun(g, list) {
    const d = g.def;
    const shoot = (to, w) => fx.laser(GUN_ORIGIN, to, { color: d.color, width: w, life: 0.8 });

    if (d.kind === 'beam') {
      // Ионный луч: один корабль, много урона и мёртвые двигатели
      const t = nearestTo(g.aim, list) || list[0];
      shoot(t.pos, 3.2);
      sound.at('laser', t.pos);
      damage(t, d.dmg, 'heavy', 'planet');
      t.ionUntil = state.time + d.disable;
      toast(`${d.name}: ${t.name} обездвижен`);

    } else if (d.kind === 'nuke') {
      // Ядерная: площадь по месту наводки — кто ушёл, тот цел
      const at = g.aim || list[0].pos;
      shoot(at, 5);
      fx.explosion(at, d.radius * 0.5, d.color);
      sound.at('boom', at, 2);
      let hit = 0;
      for (const e of list) {
        const dist = e.pos.distanceTo(at);
        if (dist > d.radius) continue;
        damage(e, d.dmg * (1 - dist / d.radius), 'heavy', 'planet');
        hit++;
      }
      toast(hit ? `${d.name}: накрыто кораблей — ${hit}` : `${d.name}: мимо`);

    } else if (d.kind === 'blind') {
      // РЭБ снизу: весь флот слепнет, наведение сбито
      for (const e of list) { e.blindUntil = state.time + d.blind; fx.ring(e.pos, 4, 26, d.color, 0.6); }
      if (g.side === state.playerSide) state.blindUntil = state.time + d.blind;
      toast(`${d.name}: флот ослеплён на ${d.blind} с`);

    } else if (d.kind === 'emp') {
      // ЭМИ-капсулы: липнут к крупным, глушат ангары
      const big = list.filter(e => e.def.hangar || e.cls === 'capital');
      const targets = big.length ? big : list;
      for (const e of targets.slice(0, 2)) {
        shoot(e.pos, 2.2);
        e.sabotageUntil = state.time + d.sabotage;
        fx.ring(e.pos, 3, 20, d.color, 0.7);
      }
      toast(`${d.name}: ангары заглушены на ${d.sabotage} с`);
    }
  }

  function nearestTo(pos, list) {
    if (!pos) return null;
    let best = null, bd = Infinity;
    for (const e of list) {
      const dd = e.pos.distanceSquared ? e.pos.distanceSquared(pos) : e.pos.distanceTo(pos);
      if (dd < bd) { bd = dd; best = e; }
    }
    return best;
  }

  const vortexes = [];   // {obj, ship, mode, t, life, radius}

  function openVortex(pos, dir, radius, mode) {
    const obj = buildHyperVortex(radius);
    obj.position.copy(pos);
    obj.quaternion.copy(quatFromDir(dir));
    scene.add(obj);
    const v = { obj, mode, t: 0, life: mode === 'out' ? 2.6 : 3.2, radius };
    vortexes.push(v);
    return v;
  }

  function updateVortexes(dt, rawT) {
    for (let i = vortexes.length - 1; i >= 0; i--) {
      const v = vortexes[i];
      v.t += dt;
      const k = v.t / v.life;
      // раскрылась — подержалась — схлопнулась
      const open = k < 0.25 ? k / 0.25 : k > 0.75 ? Math.max(0, (1 - k) / 0.25) : 1;
      v.obj.userData.update(rawT, open);
      if (v.follow && !v.follow.dead) {
        v.obj.position.copy(v.follow.pos).addScaledVector(v.follow.dir, v.radius * 1.6);
        v.obj.quaternion.copy(v.follow.obj.quaternion);
      }
      if (k >= 1) {
        scene.remove(v.obj);
        v.obj.traverse(o => { if (o.material && o.material.dispose) o.material.dispose(); });
        vortexes.splice(i, 1);
      }
    }
  }

  const state = {
    ships: [], craft: [], proj: [], squads: [],
    time: 0, speed: 1, paused: false,
    playerSide: config.playerSide || 'attacker',
    selection: [],
    jumped: { attacker: [], defender: [] },   // ушедшие в гипер — они уцелели
    reserve: {
      attacker: (config.attacker.reserve || []).map(x => ({ ...x })),
      defender: (config.defender.reserve || []).map(x => ({ ...x })),
    },
    reinforceAt: { attacker: 0, defender: 0 },
    /* Дальний гипер: корабли из своих систем в нескольких
       прыжках. Каждый вызов летит своё время и приходит
       отдельно — их может быть несколько в воздухе разом. */
    far: (config.farReserve || []).map(x => ({ ...x, called: 0 })),
    conceded: null,     // чей носитель ушёл в гипер — та сторона бой проиграла
    retreat: { attacker: false, defender: false },   // кто отходит всем флотом
    gun: null,          // противоорбитальное орудие защитника, см. ниже
    blindUntil: 0,      // до какого времени флот игрока ослеплён помехами снизу
    /* Итоги боя: сколько кораблей каждого вида вышло в бой (n), урон
       авиации по ролям (air) и планеты (planet) — для экрана итогов */
    stats: {
      n: { attacker: {}, defender: {} },
      air: { attacker: {}, defender: {} },
      sqLost: { attacker: 0, defender: 0 }, sqUp: { attacker: 0, defender: 0 },
      planet: 0, firstHit: 0, firstGun: 0,
    },
  };
  const sides = {
    attacker: { faction: FACTIONS[config.attacker.faction], id: 'attacker', sign: 1 },
    defender: { faction: FACTIONS[config.defender.faction], id: 'defender', sign: -1 },
  };
  const enemyOf = s => (s === 'attacker' ? 'defender' : 'attacker');

  /* Орудие защитника заводим здесь, а не рядом с его логикой выше:
     объявления функций поднимаются, а `const state` — нет, и обращение
     к нему раньше строки объявления валит модуль целиком. */
  if (config.groundGun) {
    const gdef = ORBITAL_DEFENCE_OF(config.groundGun);
    state.gun = {
      def: gdef, side: 'attacker',   // цель орудия — всегда атакующий флот
      next: gdef.period * 0.7,       // первый залп раньше, чтобы обозначить себя
      warned: false, aim: null,
    };
  }
  /* Сложность висит только на стороне ИИ: игрок на «Кошмаре»
     ничего не теряет, противник приобретает. */
  const DIFF = diffOf(config.difficulty);
  const aiMul = side => (side === state.playerSide ? 1 : DIFF.aim);

  const myFaction = sides[state.playerSide].faction;

  let uid = 1;
  const nameN = { attacker: {}, defender: {} };
  const ROMAN = ['', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X'];
  const roman = n => (n <= 10 ? ROMAN[n] : 'X' + roman(n - 10));

  // ── СОЗДАНИЕ ─────────────────────────────────────────────

  function spawnShip(sideId, def, pos) {
    const side = sides[sideId];
    const obj = buildShip(def, side.faction);
    /* Длина корпуса на экране — по ней кольцо выделения, подпись над
       кораблём и «близко ли он к камере» (C78, C111). Радиус класса
       для этого не годится: процедурный корпус вдвое-вчетверо длиннее
       радиуса, а у приезжей модели своя форма. */
    const len = visualLength(obj) || def.radius * 6;
    obj.position.copy(pos);
    scene.add(obj);

    const dir = new THREE.Vector3(0, 0, side.sign > 0 ? -1 : 1);
    /* Имя — с номером, если такой корабль у этой стороны уже есть (P5):
       у класса одно имя на весь клан, и в ленте «Уничтожен крейсер
       «Рэш»» трижды читалось как один корабль, погибший трижды */
    const nn = nameN[sideId];
    nn[def.id] = (nn[def.id] || 0) + 1;
    const e = {
      uid: uid++, kind: 'ship', side: sideId, faction: side.faction, def,
      name: def.name + (nn[def.id] > 1 ? ' ' + roman(nn[def.id]) : ''),
      obj, pos: obj.position, dir, vel: new THREE.Vector3(),
      hp: def.hp, maxHp: def.hp, armor: def.armor, cls: def.cls,
      radius: def.radius, len, dead: false,
      /* Полуразмер КОРПУСА на экране (C87): по нему расталкиваются корабли,
         свои и чужие, и строится строй приказа. Радиус класса для этого
         мал — модель в полтора-четыре раза крупнее, и строй слипался
         в одну плиту, а флоты проходили сквозь друг друга */
      hull: Math.max(def.radius * 1.6, len * 0.36),
      moveTo: null, target: null, forced: null, retarget: rnd(0, 1),
      /* Тактика (C26): hold — держать, guard — охрана (по умолчанию),
         hunt — охота. anchor — точка «Охраны», guardOf — охраняемый
         корабль (тогда точка едет за ним со сдвигом guardOff) */
      stance: def.station ? 'hold' : 'guard', anchor: pos.clone(), guardOf: null, guardOff: null,
      groupSpeed: 0, arriveT: 0,
      dealt: 0, kills: 0,       // для итогов боя: сколько урона нанёс и кого добил
      guns: (def.guns || []).map((g, i) => ({ def: g, idx: i, cd: rnd(0, g.cd), chargeFx: 0 })),
      pdCd: def.pd ? new Array(def.pd.count).fill(0).map(() => rnd(0, 0.4)) : [],
      hangar: null, station: !!def.station, thrustNow: 0,
      stealth: !!def.stealth, revealUntil: 0, exposed: false,
      /* Где корабль видели последний раз (P5): по этой точке ИИ ищет
         скрытых. Выход из гипера видят все — отсюда начальная точка */
      seenPos: pos.clone(), seenAt: state.time,
      hyper: null,          // {left, total} пока копится переход
      fled: false,
      ecm: def.ecm ? { mode: 'jam', power: 0 } : null,
    };
    if (e.ecm) {
      const E = ECM_OF(side.faction.id);
      const dome = buildEcmDome(E.radius, side.faction.color, E.height);
      dome.visible = false;
      scene.add(dome);
      e.dome = dome;
    }
    obj.userData.entity = e;
    obj.quaternion.copy(quatFromDir(dir));
    if (def.hangar) e.hangar = { bays: def.hangar, free: def.hangar, rebuild: [], launched: [] };
    state.ships.push(e);
    const n = state.stats.n[sideId];
    n[def.id] = (n[def.id] || 0) + 1;
    return e;
  }

  function spawnFleet(sideId, list, baseZ, station) {
    const side = sides[sideId];
    const rows = [];
    for (const item of list || []) {
      const def = item.id === 'station' ? STATION : shipDef(side.faction.id, item.id);
      if (!def) continue;
      for (let n = 0; n < item.count; n++) rows.push(def);
    }
    rows.sort((a, b) => (b.radius || 0) - (a.radius || 0));
    const cols = Math.ceil(Math.sqrt(rows.length)) + 1;
    rows.forEach((def, i) => {
      const col = i % cols, row = Math.floor(i / cols);
      const x = (col - (cols - 1) / 2) * 76 + rnd(-10, 10);
      const back = def.cls === 'carrier' ? 90 : 0;
      const z = baseZ + side.sign * (row * 72 + back) + rnd(-12, 12);
      const y = rnd(-35, 35) + (def.cls === 'carrier' ? 30 : 0);
      spawnShip(sideId, def, new THREE.Vector3(x, y, z));
    });
    if (station) spawnShip(sideId, STATION, new THREE.Vector3(rnd(-70, 70), 40, baseZ + side.sign * 190));
  }

  /* Флоты разводим далеко: между ними почти два километра игровых
     единиц, дальше главного калибра. Это и есть время на тактику —
     успеть построиться, поднять авиацию, развернуть помехи. */
  spawnFleet('attacker', config.attacker.ships, 950, false);
  spawnFleet('defender', config.defender.ships, -950, config.defender.station);

  /* Свой флот НЕ трогаем: он стоит там, где вышел из гипера, и ждёт
     приказа. Это и даёт время осмотреться, перестроиться и решить,
     чем заходить. Противник тем временем идёт навстречу, но не до
     упора, а на рубеж — иначе он проскакивает сквозь строй. */
  for (const s of state.ships) {
    if (s.station || s.side === state.playerSide) continue;
    const line = s.pos.z > 0 ? 420 : -420;
    s.moveTo = new THREE.Vector3(s.pos.x * 0.7, s.pos.y * 0.7, line);
  }

  // ── АВИАЦИЯ ──────────────────────────────────────────────

  function launchSquadron(carrier, role) {
    if (!carrier.hangar || carrier.hangar.free <= 0 || carrier.dead) return false;
    // ЭМИ-капсулы с планеты: ангары заглушены, авиация не выходит
    if (carrier.sabotageUntil && state.time < carrier.sabotageUntil) return false;
    carrier.hangar.free--;
    const def = STRIKE[carrier.faction.id][role];
    /* У звена есть класс, но НЕТ прочности: прочность у машин. Класс
       нужен, чтобы таблица урона знала, что главный калибр по звену
       не наводится (C14), — без него множитель выходил единицей. */
    const squad = {
      uid: uid++, kind: 'squad', cls: 'strike', side: carrier.side, faction: carrier.faction,
      role, def, home: carrier, craft: [], dead: false, recall: false,
      target: null, pos: new THREE.Vector3().copy(carrier.pos), moveTo: null,
    };
    const bay = carrier.obj.userData.bay || ZERO;
    const origin = bay.clone().applyQuaternion(carrier.obj.quaternion).add(carrier.pos);
    const size = SQUAD_SIZE_OF(carrier.faction.id);
    squad.size = size;
    for (let i = 0; i < size; i++) {
      const obj = buildStrike(role, carrier.faction);
      obj.position.copy(origin).add(new THREE.Vector3(rnd(-9, 9), rnd(-6, 6), rnd(-9, 9)));
      scene.add(obj);
      const c = {
        uid: uid++, kind: 'craft', side: carrier.side, faction: carrier.faction, def,
        cls: 'strike', role, squad, obj, pos: obj.position,
        dir: carrier.dir.clone(), vel: carrier.vel.clone(),
        hp: def.hp, maxHp: def.hp, armor: def.armor,
        dead: false, cd: rnd(0, def.cd), target: null, phase: 'out',
        breakUntil: 0, radius: 2.6, slot: i,
        ammo: def.ammo || 0, reloads: def.reloads || 0, reloading: 0,
        revealUntil: 0, exposed: false,
      };
      obj.userData.entity = c;
      obj.quaternion.copy(carrier.obj.quaternion);
      squad.craft.push(c);
      state.craft.push(c);
      fx.flash(obj.position, 5, 0xffd0a0, 0.3);
    }
    state.squads.push(squad);
    carrier.hangar.launched.push(squad);
    state.stats.sqUp[squad.side]++;
    return true;
  }

  /* Звено выбито — место в ангаре вернётся через 26 с (машины строят
     заново). Звено СЕЛО — место уже вернула посадка, и второго таймера
     быть не должно: иначе через 26 с звеньев в воздухе больше, чем
     ангаров (C99). */
  function killSquad(squad, landed) {
    if (squad.dead) return;
    squad.dead = true;
    const carrier = squad.home;
    if (!landed && carrier && !carrier.dead && carrier.hangar) carrier.hangar.rebuild.push(state.time + 26);
    if (!landed) {
      state.stats.sqLost[squad.side]++;
      const what = `звено ${ROLE_GEN[squad.role]} ${squad.def.name}`;
      /* «наше» / «вражеское» — словом, а не только глаголом (P5): в
         зеркальном бою имена у сторон одни и те же */
      if (squad.side === state.playerSide) feed(`Потеряно наше ${what}`, 'bad');
      else feed(`Сбито вражеское ${what}`, 'good');
    }
    if (state.selection.includes(squad)) {
      state.selection = state.selection.filter(s => s !== squad);
      state.selDirty = true;
    }
  }

  /* Звено без носителя (тот погиб или ушёл в гипер) ищет другой свой
     носитель, на который можно сесть. Нет такого — звено остаётся
     без дома, и об этом говорится ОДИН раз (C8).
     Сесть можно только на СВОБОДНОЕ место, и занимает его звено сразу,
     как при пуске: посадка потом вернёт это место (free + 1). Раньше
     чужое звено место не занимало, а посадка его всё равно
     «возвращала» — носитель на четыре ангара держал в воздухе восемь
     звеньев, ровно то, что чинил C99. */
  function rehome(squad) {
    let best = null, bd = Infinity;
    for (const s of state.ships) {
      if (s.dead || s.hyper || s.side !== squad.side || !s.hangar || s.hangar.free <= 0) continue;
      const d = s.pos.distanceToSquared(squad.pos);
      if (d < bd) { bd = d; best = s; }
    }
    if (best) {
      best.hangar.free--;
      best.hangar.launched.push(squad);
    }
    squad.home = best;
    return best;
  }

  /* Пуск ракеты авиацией. Ракета летит физически: её можно сбить
     зенитками, а с заданной вероятностью она уходит мимо — тогда
     наведение просто отключается и снаряд проходит стороной. */
  function fireMissile(c, t) {
    const def = c.def;
    const miss = Math.random() < (def.missChance || 0);
    const p = spawnProjectile(c, t, def.dmg, def.weapon,
                              def.missileSpeed || 120, def.missileHp || 24);
    if (miss) {
      p.target = null;      // головка не захватила — уйдёт мимо
      p.dir.add(_v.set(rnd(-1, 1), rnd(-0.5, 0.5), rnd(-1, 1)).multiplyScalar(0.28)).normalize();
      p.life = 3.5;
    }
    fx.flash(_v.copy(c.pos).addScaledVector(c.dir, 3), 2.6, 0xffd0a0, 0.16);
    sound.at('missile', c.pos);
    c.ammo--;
    c.revealUntil = state.time + STEALTH.revealFor;
    return p;
  }

  function spawnProjectile(owner, target, dmg, weapon, speed, hp) {
    const obj = buildTorpedo(weapon === 'torp' ? 0xffb060 : 0xff7a5a);
    const muz = (owner.obj.userData.muzzles || [ZERO])[0];
    obj.position.copy(muz).applyQuaternion(owner.obj.quaternion).add(owner.pos);
    scene.add(obj);
    const p = {
      uid: uid++, kind: 'proj', cls: 'torpedo', side: owner.side, faction: owner.faction,
      obj, pos: obj.position, target, dmg, weapon, speed, owner,
      hp, maxHp: hp, armor: 0, dead: false, life: 16, radius: 1.8,
      dir: new THREE.Vector3().subVectors(target.pos, owner.pos).normalize(),
    };
    obj.userData.entity = p;
    state.proj.push(p);
    return p;
  }

  // ── РАДИОЭЛЕКТРОННАЯ БОРЬБА ──────────────────────────────
  // Купол глушения ломает противнику наведение внутри своего радиуса.
  // Свой защитный купол это глушение отменяет — отсюда и дуэль РЭБ.

  const _fields = [];
  function updateEcm(dt) {
    _fields.length = 0;
    for (const e of state.ships) {
      if (!e.ecm || e.dead) continue;
      const want = (e.ecm.mode === 'off' || e.hyper) ? 0 : 1;
      const E = ECM_OF(e.faction.id);
      e.ecm.power += (want - e.ecm.power) * Math.min(1, dt / E.spinUp * 2.5);
      if (e.ecm.power > 0.05) {
        const emit = e.obj.userData.emitter;
        const ey = emit ? emit.y * 1.25 : -e.radius;
        _fields.push({
          pos: new THREE.Vector3(e.pos.x, e.pos.y + ey, e.pos.z),
          side: e.side, mode: e.ecm.mode, prof: E, src: e,
        });
      }
    }
  }
  /* Купола рисуются КАЖДЫЙ кадр, и на паузе тоже: выделил корабль РЭБ
     на паузе — плотная картинка его поля должна появиться сразу, а не
     после «Продолжить». Мощность считает updateEcm (только в ходе боя). */
  function updateDomes() {
    /* Плотная картинка — когда выбраны именно корабли РЭБ (или курсор
       на нём): при «Весь флот» четыре полных купола Плэктора снова
       заливали бы полэкрана */
    const onlyEcm = state.selection.length > 0 && state.selection.every(x => x.ecm);
    for (const e of state.ships) {
      if (!e.dome || e.dead) continue;
      /* Купол скрытого противника не рисуется: висящий над пустотой
         цилиндр выдавал невидимый флот Рииза (C67). Глушит он при
         этом по-прежнему — помехи от невидимки и есть его сила. */
      e.dome.visible = e.ecm.power > 0.02 && !(e.side !== state.playerSide && hidden(e));
      // прогрев: плотный купол в первых кадрах, под заставкой (P5)
      if (warmFrames > 0 && !hidden(e)) {
        e.dome.visible = true;
        e.dome.position.copy(e.pos);
        e.dome.userData.set(state.time, 0.001, MINE_HEX, 0, true);
        continue;
      }
      if (!e.dome.visible) continue;
      // Блин лежит в плоскости боя, а не крутится вместе с корпусом
      const emit = e.obj.userData.emitter;
      const ey = emit ? emit.y * 1.25 : -e.radius;
      e.dome.position.set(e.pos.x, e.pos.y + ey, e.pos.z);
      /* В покое от купола остаётся ОДНО тонкое кольцо — граница поля
         на плоскости боя; сетка, стенки и луч — только у выделенного
         (когда выбраны одни РЭБ) или наведённого корабля (часть C111). Цилиндры с кольцами
         шириной в пол-экрана перекрывали собой сами корабли. Цвет —
         по стороне, а не по клану: чьё это поле, видно и в зеркальном
         бою (C43). */
      const full = hoverEnt === e || (onlyEcm && state.selection.includes(e));
      e.dome.userData.set(state.time, e.ecm.power * 0.55,
        e.ecm.mode === 'shield' ? 0xcfe8ff : e.side === state.playerSide ? MINE_HEX : FOE_HEX, -ey, full);
    }
  }

  /* Поле — блин: по горизонтали круг, по вертикали тонкий слой.
     Поднявшись над ним или нырнув под него, из помех можно выйти.
     Радиус берём из профиля клана: у Девиана блин заметно шире. */
  function inField(f, pos) {
    const E = f.prof || ECM;
    if (Math.abs(pos.y - f.pos.y) > E.height * 1.6) return false;
    const dx = pos.x - f.pos.x, dz = pos.z - f.pos.z;
    return dx * dx + dz * dz < E.radius * E.radius;
  }
  /* Возвращает профиль глушащего поля, а не просто «да/нет»: от того,
     чей это блин, зависит и дальность, на которой наведение всё же
     работает, и насколько просядет ПВО. У Девиана оба числа злее. */
  function jamProfile(pos, side) {
    let hit = null;
    for (const f of _fields) {
      if (f.mode !== 'jam' || f.side === side) continue;
      if (inField(f, pos)) { hit = f.prof || ECM; break; }
    }
    if (!hit) return null;
    for (const f of _fields) {
      if (f.mode !== 'shield' || f.side !== side) continue;
      if (inField(f, pos)) return null;      // свой щит снял чужие помехи
    }
    return hit;
  }
  const jammed = (pos, side) => jamProfile(pos, side) !== null;

  // ── СКРЫТНОСТЬ ───────────────────────────────────────────
  // Юнит Рииза невидим, пока молчит. Выстрелил — виден пять секунд.
  // Подошёл вплотную чужой корвет — виден, даже если молчит.

  function reveal(e) {
    if (e && e.stealth) e.revealUntil = state.time + STEALTH.revealFor;
  }

  function hidden(e) {
    return !!e.stealth && state.time >= e.revealUntil && !e.exposed && !e.hyper;
  }

  function updateExposure() {
    for (const e of state.ships) {
      if (!e.stealth || e.dead) continue;
      e.exposed = false;
      const foe = enemyOf(e.side);
      for (const s of state.ships) {
        if (s.dead || s.side !== foe) continue;
        // корвет — разведчик, видит скрытых почти вдвое дальше
        if (jammed(s.pos, s.side)) continue;   // ослеплённый помехами не обнаружит
        const r = s.def.id === 'corvette' ? STEALTH.detectRange * 1.9 : STEALTH.detectRange;
        if (s.pos.distanceToSquared(e.pos) < r * r) { e.exposed = true; break; }
      }
    }
    // Последнее место, где корабль видели (P5): по нему ИИ ищет скрытых
    for (const e of state.ships) {
      if (!e.dead && !hidden(e)) { e.seenPos.copy(e.pos); e.seenAt = state.time; }
    }
    for (const c of state.craft) {
      if (!c.def.stealth || c.dead) continue;
      c.exposed = false;
      const foe = enemyOf(c.side);
      for (const s of state.ships) {
        if (s.dead || s.side !== foe) continue;
        const r = (s.def.pd ? s.def.pd.range : 100) * 0.9;
        if (s.pos.distanceToSquared(c.pos) < r * r) { c.exposed = true; break; }
      }
    }
  }

  function craftHidden(c) {
    return !!c.def.stealth && state.time >= (c.revealUntil || 0) && !c.exposed;
  }

  // ── ГИПЕРПРОСТРАНСТВО ────────────────────────────────────

  function beginJump(e) {
    if (e.dead || e.hyper || e.station) return false;
    const total = (e.def.hyperCharge || 8) * HYPER.jumpCharge;
    e.hyper = { left: total, total, vortex: null };
    e.moveTo = null;
    e.forced = null;
    return true;
  }

  function completeJump(e) {
    e.fled = true;
    e.dead = true;
    if (e.hyper && e.hyper.vortex) e.hyper.vortex.follow = null;
    /* Росчерк по курсу — то, ради чего гипер вообще смотрится:
       корабль не исчезает, а вытягивается в нитку и уходит. Луч
       узкий и длинный, гаснет за треть секунды. */
    const away = _v.copy(e.pos).addScaledVector(e.dir, e.radius * 90);
    fx.beam(e.pos, away, { color: 0xbfe0ff, width: e.radius * 0.5, life: 0.32 });
    fx.beam(e.pos, away, { color: 0xffffff, width: e.radius * 0.16, life: 0.24 });
    fx.ring(e.pos, e.radius * 2, e.radius * 22, 0x9fd0ff, 0.7);
    fx.flash(e.pos, e.radius * 4, 0xdfefff, 0.5);
    fx.sparks(e.pos, 10, 0xcfe6ff, e.radius * 6, false);
    sound.at('hyper', e.pos);
    scene.remove(e.obj);
    removeDome(e);
    state.jumped[e.side].push(e.def.id);
    // Чужой ушёл — его уже не добить; свой при отходе — и так видно
    if (e.side !== state.playerSide && !state.retreat[e.side]) feed(`Противник: ${shortName(e)} ушёл в гипер`, 'warn');
    if (state.selection.includes(e)) {
      state.selection = state.selection.filter(x => x !== e);
      state.selDirty = true;
    }
    /* Уход носителя = флот остался без авиации: бой проигран, и за
       носителем уходит весь флот. Уходит ЧЕСТНО — накачкой гипера,
       под огнём; бой кончится, когда уйдут или погибнут все (C17). */
    if (e.cls === 'carrier' && !state.conceded) {
      state.conceded = e.side;
      orderRetreat(e.side);
      toast(e.side === state.playerSide ? 'Носитель ушёл в гипер — флот отходит следом'
                                        : 'Носитель противника ушёл — его флот отходит');
    }
  }

  /* ── ОТХОД.
     Раньше «Отход» кончал бой сразу, и домой возвращались все живые —
     проигрышный бой ничего не стоил. Теперь это гипер всего флота:
     каждый корабль копит переход и всё это время беззащитен. Спасены
     только успевшие уйти. Резерв, что ещё не вышел, в бой уже не идёт
     и целым возвращается домой. */
  function orderRetreat(side) {
    if (state.retreat[side]) return 0;
    state.retreat[side] = true;
    state.reinforceAt[side] = 0;
    let n = 0;
    for (const s of state.ships) if (!s.dead && s.side === side && beginJump(s)) n++;
    return n;
  }
  function cancelRetreat(side) {
    if (!state.retreat[side] || state.conceded === side) return;
    state.retreat[side] = false;
    for (const s of state.ships) if (!s.dead && s.side === side && s.hyper) s.hyper = null;
  }

  // Купол РЭБ — отдельный объект сцены: уходит вместе с кораблём (C66)
  function removeDome(e) {
    if (!e.dome) return;
    scene.remove(e.dome);
    disposeScene(e.dome);
    e.dome = null;
  }

  function updateHyper(e, dt) {
    e.hyper.left -= dt;
    const k = 1 - e.hyper.left / e.hyper.total;

    // Накачка: кольца затягиваются к корпусу
    if (!e.hyperFx || state.time - e.hyperFx > 0.3) {
      e.hyperFx = state.time;
      fx.ring(e.pos, e.radius * (4 - k * 2.6), e.radius * 1.6, 0x9fd0ff, 0.5);
    }
    // За пару секунд до перехода перед носом раскрывается воронка
    if (!e.hyper.vortex && e.hyper.left < 2.4) {
      const v = openVortex(
        _v.copy(e.pos).addScaledVector(e.dir, e.radius * 1.6),
        e.dir.clone(), e.radius * 2.2, 'out');
      v.follow = e;
      e.hyper.vortex = v;
    }
    // Корабль втягивается в воронку: разгон по курсу
    if (e.hyper.left < 2.0) {
      e.vel.addScaledVector(e.dir, e.def.thrust * 2.2 * dt);
      e.pos.addScaledVector(e.vel, dt);
      // Разгон в гипер: факел вытягивается в несколько корпусов
      for (const en of e.obj.userData.engines || []) {
        en.scale.set(1.3, 1.3, 1.6 + (2.0 - e.hyper.left) * 3.2);
      }
    }
    if (e.hyper.left <= 0) completeJump(e);
  }

  function callReinforcements(side) {
    if (!state.reserve[side] || !state.reserve[side].length) return false;
    if (state.reinforceAt[side] || state.retreat[side]) return false;
    state.reinforceAt[side] = state.time + HYPER.reinforceDelay;
    return true;
  }

  /* ── ДАЛЬНИЙ ГИПЕР ───────────────────────────────────────
     Обычное подкрепление — это то, что не поместилось в первую волну
     и уже висит на подходе. Дальний гипер — другое: он тянет корабли
     из соседних систем, и пока они летят, их родной мир стоит пустым.
     Поэтому и время полёта честное: сорок пять секунд за прыжок. */
  function callFar(entry) {
    if (entry.called) return false;
    if (state.retreat[state.playerSide]) { toast('Флот отходит — подмогу не зовём'); return false; }
    entry.called = state.time + entry.delay;
    toast(`${entry.name}: флот идёт на помощь, ${Math.round(entry.delay)} с`);
    refreshFar();
    return true;
  }

  function updateFar() {
    for (const e of state.far) {
      if (!e.called || e.called > state.time || e.done) continue;
      // Флот уже отходит: подмога разворачивается и остаётся дома
      if (state.retreat[state.playerSide]) continue;
      e.done = true;
      arrivedFeed(dropIn(state.playerSide, e.ships));
      toast(`${e.name}: подмога вышла из гипера`);
      refreshFar();
    }
  }

  function arriveReinforcements(side) {
    const list = state.reserve[side];
    state.reserve[side] = [];
    state.reinforceAt[side] = 0;
    const got = dropIn(side, list);
    if (side === state.playerSide) arrivedFeed(got);
    toast(side === state.playerSide ? 'Подкрепление вышло из гипера'
                                    : 'Противник получил подкрепление');
  }

  /* Выход из гипера: общий для обычных подкреплений и для дальнего
     гипера. Корабли вываливаются с края поля на скорости, воронка
     раскрывается позади — торможение здесь не эффект, а физика. */
  function dropIn(side, list) {
    const sign = sides[side].sign;
    const baseZ = sign * 1200;
    let i = 0;
    const got = [];
    for (const item of list) {
      const def = shipDef(sides[side].faction.id, item.id);
      if (!def) continue;
      for (let n = 0; n < item.count; n++, i++) {
        const pos = new THREE.Vector3((i % 5 - 2) * 90 + rnd(-15, 15), rnd(-40, 40),
                                      baseZ + sign * Math.floor(i / 5) * 80);
        const sh = spawnShip(side, def, pos);
        got.push(sh);
        // Воронка раскрывается позади корабля — он из неё вылетает
        const back = new THREE.Vector3(0, 0, sign > 0 ? 1 : -1);
        openVortex(pos.clone().addScaledVector(back, def.radius * 2.2),
                   back.clone().negate(), def.radius * 2.4, 'in');
        // Выходит на большой скорости и гасит её маршевыми — видно по соплам
        sh.vel.set(0, 0, -sign * def.maxSpeed * 2.6);
        sh.exitUntil = state.time + 6;
        sh.moveTo = new THREE.Vector3(pos.x * 0.4, 0, sign * 120);
        fx.flash(pos, def.radius * 5, 0xdfefff, 0.6);
        // Нитка позади: корабль будто вытянулся из точки выхода
        fx.beam(pos.clone().addScaledVector(back, def.radius * 70), pos,
          { color: 0xbfe0ff, width: def.radius * 0.4, life: 0.3 });
        fx.ring(pos, def.radius * 1.5, def.radius * 12, 0x9fd0ff, 0.6);
        sound.at('hyperIn', pos);
      }
    }
    fx.shake = Math.min(1, fx.shake + 0.3);
    return got;
  }

  /* Прибывшее подкрепление — строкой в ленте, по которой его можно
     сразу взять (P5): оно ни в один отряд не входит, и пока игрок
     командовал отрядами, пять кораблей резерва стояли на «Охране»
     в стороне от боя. Щелчок по строке или N — выбрать прибывших */
  function arrivedFeed(list) {
    if (!list || !list.length) return;
    state.arrived = list;
    state.arrivedAt = state.time;
    state.arrivedSeen = false;
    // прежняя строка о прибывших больше не кликается: она выбрала бы новых
    for (const d of feedBox.children) if (d.classList.contains('act')) {
      d.classList.remove('act'); d.onclick = null; d.title = ''; d._life = FEED_LIFE;
    }
    feed(`Прибыло подкрепление: ${list.length} ${plural(list.length, 'корабль', 'корабля', 'кораблей')} — не в отрядах · щелчок или N — выбрать`,
      'good', selectArrived);
  }
  function selectArrived() {
    if (!state.arrived) { toast('Подкрепление ещё не прибыло'); return; }
    const list = state.arrived.filter(e => !e.dead && !e.fled);
    if (!list.length) { toast('Прибывших кораблей не осталось'); return; }
    state.selection = list;
    state.arrivedSeen = true;      // кнопка в шапке снова про резерв
    focusOn(list);
    sound.ui('select');
    refreshSel();
  }
  const plural = (n, one, few, many) => {
    const a = n % 100, b = n % 10;
    return a > 10 && a < 20 ? many : b === 1 ? one : b >= 2 && b <= 4 ? few : many;
  };

  // ── УРОН ─────────────────────────────────────────────────

  /* src — кто стрелял: корабль, машина, снаряд (у него owner) или
     'planet'. По нему считаются итоги боя (кто больше всех нанёс урона
     и кого добил), тревога «под огнём» и строчки ленты событий. */
  function damage(target, amount, weapon, src) {
    /* Цель без собственной прочности (звено целиком — у него прочность
       у машин) урона не принимает: раньше это давало hp = NaN, звено
       становилось бессмертным, а флот стрелял в пустоту (C14) */
    if (!target || target.dead || typeof target.hp !== 'number') return;
    if (!(amount > 0)) return;
    const mult = dmgMult(SPACE_DMG, weapon, target.cls);
    if (mult <= 0) return;
    const before = target.hp;
    target.hp -= amount * mult * (1 - (target.armor || 0));
    const dealt = before - Math.max(0, target.hp);
    const who = src && src.kind === 'proj' ? src.owner : src;
    credit(who, dealt);
    if (target.kind === 'ship') underFire(target);
    if (target.hp <= 0) destroy(target, who);
  }
  function credit(who, dealt) {
    if (!who || !(dealt > 0)) return;
    if (!state.stats.firstHit && who !== 'planet') state.stats.firstHit = state.time;
    if (who === 'planet') { state.stats.planet += dealt; return; }
    if (who.kind === 'ship') { who.dealt += dealt; return; }
    if (who.kind === 'craft') {
      const a = state.stats.air[who.side];
      const k = who.role;
      if (!a[k]) a[k] = { name: who.def.name, dealt: 0, kills: 0 };
      a[k].dealt += dealt;
    }
  }
  /* Тревога «наш корабль под огнём» — у крупных своих (флагман,
     крейсер, носитель, станция), не чаще раза в 25 с на корабль: бой за
     кадром иначе легко пропустить, а треск тревоги на каждое попадание
     быстро перестают слышать */
  function underFire(t) {
    if (t.side !== state.playerSide || (t.cls !== 'capital' && t.cls !== 'carrier')) return;
    if (state.time - (t.alarmAt || -99) < 25) { t.alarmAt = Math.max(t.alarmAt, state.time - 15); return; }
    t.alarmAt = state.time;
    feed(`${t.station ? 'Наша' : 'Наш'} ${shortName(t)} под огнём`, 'warn');
    sound.ui('alarm');
  }

  function destroy(e, by) {
    if (e.dead) return;
    e.dead = true;
    const size = e.kind === 'ship' ? e.radius * 1.6 : e.kind === 'craft' ? 5 : 4;
    /* В невесомости обломки не падают (gravity 0), а большой корабль
       не взрывается разом: у него рвутся отсеки один за другим —
       отсюда цепочка вторичных вспышек. */
    fx.explosion(e.pos, size, e.kind === 'ship' ? 0xffa050 : 0xffc070, {
      gravity: 0, chain: e.kind === 'ship' ? Math.round(e.radius / 7) : 0,
    });
    if (e.kind === 'ship') {
      fx.shake = Math.min(1, fx.shake + e.radius / 40);
      fx.ring(e.pos, size * 0.5, size * 4.5, 0xffb070, 0.7);
      fx.debris(e.pos, Math.round(e.radius * 0.6), 0x7a6a56, e.radius * 3, 0);
      for (let i = 0; i < 3; i++) {
        fx.flash(_v.copy(e.pos).add(_v2.set(rnd(-1, 1), rnd(-1, 1), rnd(-1, 1)).multiplyScalar(e.radius)),
          e.radius, 0xff8040, 0.8);
      }
      if (e.hangar) for (const sq of e.hangar.launched) if (!sq.dead) sq.home = null;
      removeDome(e);
      // Кто добил — для итогов; лента и звук — всем видно и слышно
      if (by && by.kind === 'ship') by.kills++;
      else if (by && by.kind === 'craft') { const a = state.stats.air[by.side][by.role]; if (a) a.kills++; }
      sound.at('boom', e.pos, e.radius / 12);
      /* Свой или чужой — словом и цветом, а не одним глаголом (P5): в
         зеркальном бою «Потерян корвет «Гроссер»» и «Уничтожен корвет
         «Гроссер»» различались только им */
      const nm = lowFirst(e.name);
      if (e.side === state.playerSide) {
        feed(e.station ? `Потеряна наша ${nm}` : `Потерян наш ${nm}`, 'bad');
        sound.ui('lost');
      } else feed(e.station ? `Уничтожена вражеская ${nm}` : `Уничтожен вражеский ${nm}`, 'good');
    } else if (e.kind === 'craft') sound.at('pop', e.pos);
    scene.remove(e.obj);
    if (e.kind === 'craft' && e.squad) {
      e.squad.craft = e.squad.craft.filter(c => c !== e);
      if (!e.squad.craft.length) killSquad(e.squad);
    }
    if (state.selection.includes(e)) {
      state.selection = state.selection.filter(s => s !== e);
      state.selDirty = true;     // панель — в этом же кадре, а не через треть секунды
    }
  }
  const ROLE_GEN = { interceptor: 'перехватчиков', fighter: 'истребителей', bomber: 'бомбардировщиков' };
  const cap = t => t.charAt(0).toUpperCase() + t.slice(1);
  const lowFirst = t => t.charAt(0).toLowerCase() + t.slice(1);
  // «Крейсер «Рэш» II» → «Рэш» II: собственное имя с номером
  const shortName = e => { const n = e.name || e.def.name; return n.includes('«') ? n.slice(n.indexOf('«')) : n; };

  // ── ПОИСК ЦЕЛЕЙ ──────────────────────────────────────────

  // Скрыт ли от глаз противника: корабль, машина или звено целиком
  function unseen(e) {
    if (!e) return false;
    if (e.kind === 'ship') return hidden(e);
    if (e.kind === 'craft') return craftHidden(e);
    if (e.kind === 'squad') return !e.craft.some(c => !c.dead && !craftHidden(c));
    return false;
  }

  /* Цель, по которой можно стрелять. Приказ «атаковать звено» — это
     приказ бить его МАШИНЫ (C14): у звена нет прочности, и урон по
     нему раньше уходил в NaN. Берём ближайшую живую видимую машину;
     скрытое не берём вовсе — приказ не переживает маскировку (C18). */
  function liveTarget(from, t) {
    if (!t || t.dead) return null;
    if (t.kind !== 'squad') return unseen(t) ? null : t;
    let best = null, bd = Infinity;
    for (const c of t.craft) {
      if (c.dead || craftHidden(c)) continue;
      const d = c.pos.distanceToSquared(from.pos);
      if (d < bd) { bd = d; best = c; }
    }
    return best;
  }

  function nearest(from, list, maxDist, filter) {
    let best = null, bd = maxDist * maxDist;
    for (const e of list) {
      if (e.dead || (filter && !filter(e))) continue;
      if (e.kind === 'ship' && hidden(e)) continue;
      if (e.kind === 'craft' && craftHidden(e)) continue;
      const d = e.pos.distanceToSquared(from);
      if (d < bd) { bd = d; best = e; }
    }
    return best;
  }

  /* Цель — по тактике корабля (C26). reach — во сколько дальностей
     главного калибра искать: «Держать» — 1,0 (только то, до чего
     орудие достаёт с места), «Охрана» — 1,3 и не дальше поводка от
     своей точки (иначе «охрана» уходила бы за каждым, кого заметила),
     «Охота» — 1,8, а рядом пусто — ближайший видимый враг на всём поле:
     охота сама ищет цели. Раньше 1,8 было у всех, и «Стоп» держал
     корабль секунду — дальше он сам находил цель и шёл к ней. */
  const leashOf = e => Math.max(SPACE_STANCES.guard.leash, (e.guns[0] ? e.guns[0].def.range : 300) * 0.4);
  function shipAcquire(e, reach) {
    const foe = enemyOf(e.side);
    const gun = e.guns[0];
    if (!gun) return null;
    const st = SPACE_STANCES[e.stance] || SPACE_STANCES.guard;
    if (!reach) reach = st.reach;
    const range = gun.def.range;
    // «Охрана» без приказа идти ищет только вокруг своей точки
    const fence = e.stance === 'guard' && !e.station && !e.moveTo && !e.amove ? leashOf(e) + range : 0;
    let best = null, bestScore = -Infinity, near = null, nd = Infinity;
    for (const s of state.ships) {
      if (s.dead || s.side !== foe || hidden(s)) continue;
      const m = dmgMult(SPACE_DMG, gun.def.type, s.cls);
      if (m <= 0) continue;
      const d = s.pos.distanceTo(e.pos);
      if (d < nd) { nd = d; near = s; }
      if (d > range * reach) continue;
      if (fence && s.pos.distanceTo(e.anchor) > fence) continue;
      const score = m * 1000 - d + (1 - s.hp / s.maxHp) * 400 + (s.cls === 'carrier' ? 250 : 0);
      if (score > bestScore) { bestScore = score; best = s; }
    }
    if (!best && e.stance === 'hunt' && !e.station) return near;
    return best;
  }

  /* ── ПОД ЧУЖИМ КУПОЛОМ РЭБ наведение работает только ближе lockRange
     (170, у Девиана 102). Фокус огня и «Охрана» вели тяжёлый корабль на
     0,68 дальности — 530 для главного калибра — и он стоял там, молча:
     замер — 25 с, ноль урона, а панель всё писала «фокус огня». Теперь
     корабль под помехами бьёт то, до чего достаёт, и первым — сам
     глушитель: его гибель снимает помехи со всех. Глушитель дальше —
     к нему идут «Охота», фокус огня и атака с ходу, «Охрана» — если он
     в пределах её поводка; «Держать» с места не сходит. Цель «под
     помехами» — временная (`jamShot`): кончились помехи — корабль
     возвращается к своей цели и своей дальности */
  function jamPick(e) {
    const gun = e.guns[0];
    if (!gun || !e.jam) return null;
    const foe = enemyOf(e.side), lock = e.jam.lockRange;
    const roam = !e.station && (e.forced || e.amove || e.stance === 'hunt' || e.stance === 'guard');
    let best = null, bs = -Infinity;
    for (const f of _fields) {
      if (f.mode !== 'jam' || f.side === e.side || !f.src || f.src.dead || hidden(f.src) || !inField(f, e.pos)) continue;
      const s = f.src;
      if (dmgMult(SPACE_DMG, gun.def.type, s.cls) <= 0) continue;
      const d = s.pos.distanceTo(e.pos);
      if (d > lock && !roam) continue;
      // «Охрана» к глушителю идёт, только если дотянется, не сходя с поводка
      if (d > lock && !e.forced && !e.amove && e.stance === 'guard' &&
          s.pos.distanceTo(e.anchor) > leashOf(e) + lock * 0.8) continue;
      const sc = 3000 - d;
      if (sc > bs) { bs = sc; best = s; }
    }
    for (const s of state.ships) {
      if (s.dead || s.side !== foe || hidden(s)) continue;
      const m = dmgMult(SPACE_DMG, gun.def.type, s.cls);
      if (m <= 0) continue;
      const d = s.pos.distanceTo(e.pos);
      if (d > lock) continue;
      const sc = m * 1000 - d;
      if (sc > bs) { bs = sc; best = s; }
    }
    return best;
  }

  function craftAcquire(c) {
    const foe = enemyOf(c.side);
    if (c.role === 'interceptor') {
      return nearest(c.pos, state.craft, 1000, e => e.side === foe)
          || nearest(c.pos, state.proj, 800, e => e.side === foe)
          || nearest(c.pos, state.ships, 1000, e => e.side === foe && e.cls === 'escort');
    }
    if (c.role === 'bomber') {
      return nearest(c.pos, state.ships, 2600, e => e.side === foe && e.cls !== 'escort')
          || nearest(c.pos, state.ships, 2600, e => e.side === foe);
    }
    return nearest(c.pos, state.craft, 800, e => e.side === foe)
        || nearest(c.pos, state.ships, 1300, e => e.side === foe && e.cls === 'escort')
        || nearest(c.pos, state.ships, 1800, e => e.side === foe);
  }

  // ── ФИЗИКА ───────────────────────────────────────────────

  // Разворот корпуса. От вектора скорости не зависит — в этом вся соль.
  function face(e, dir, dt, turnRate) {
    if (e.ionized) return;      // маневровые тоже выжжены
    if (!dir || dir.lengthSq() < 1e-8) return;
    _v3.copy(dir).normalize();
    quatFromDir(_v3, _q);
    e.obj.quaternion.slerp(_q, clamp(turnRate * dt, 0, 1));
    e.dir.set(0, 0, -1).applyQuaternion(e.obj.quaternion);
  }

  // Тяга: доводим вектор скорости до желаемого. Двигатель работает
  // в полную силу только по курсу — вбок толкают слабые маневровые.
  function thrustTo(e, desiredVel, dt, thrust, rev = 0.3) {
    // Выжженные ионным лучом двигатели не тянут вовсе: корабль
    // продолжает лететь по инерции, но управлять им нечем
    if (e.ionized) { e.thrustNow = 0; return; }
    _v.subVectors(desiredVel, e.vel);
    const need = _v.length();
    if (need < 1e-4) { e.thrustNow = 0; return; }
    _v.divideScalar(need);
    const align = Math.max(0, e.dir.dot(_v));
    // против носа — только rev тяги: у корабля это SPACE_MOVE.reverse
    const power = thrust * (rev + (1 - rev) * align);
    const step = Math.min(need, power * dt);
    e.vel.addScaledVector(_v, step);
    e.thrustNow = step / Math.max(1e-4, thrust * dt);
  }

  function integrate(e, dt) {
    e.pos.addScaledVector(e.vel, dt);
    // мягкие границы поля боя — отражаем обратно
    for (const ax of ['x', 'z']) {
      if (e.pos[ax] > FIELD) { e.pos[ax] = FIELD; if (e.vel[ax] > 0) e.vel[ax] *= -0.3; }
      if (e.pos[ax] < -FIELD) { e.pos[ax] = -FIELD; if (e.vel[ax] < 0) e.vel[ax] *= -0.3; }
    }
    if (e.pos.y > 500) { e.pos.y = 500; if (e.vel.y > 0) e.vel.y *= -0.3; }
    if (e.pos.y < -500) { e.pos.y = -500; if (e.vel.y < 0) e.vel.y *= -0.3; }
  }

  /* ── ПРИБЫТИЕ (C70). Скорость, с которой ещё можно встать за dist:
     тормозной путь v²/2a, где a — ОБРАТНАЯ тяга (SPACE_MOVE.reverse),
     а не полная: корабль тормозит, глядя на точку, то есть против
     своего носа. Раньше тормозной путь брался от полной тяги, а тормозил
     корабль на 30% — и каждый класс проскакивал точку на 80–97 единиц.
     Запас 0,75 — на разворот и дискретный шаг; у самой точки скорость
     пропорциональна расстоянию, чтобы корабль не дрожал вокруг неё. */
  const REV = SPACE_MOVE.reverse;
  const UPDOWN = 180;       // шаг «Выше/Ниже»: столько выводит из-под купола помех
  function arriveSpeed(e, dist, vmax) {
    if (dist <= 0) return 0;
    const aB = e.def.thrust * REV * 0.85;
    return Math.min(vmax, Math.sqrt(2 * aB * dist), dist * 1.5);
  }
  function arrive(e, goal, vmax) {
    _v.subVectors(goal, e.pos);
    const d = _v.length();
    if (d < 0.5) return ZERO;
    return _v.multiplyScalar(arriveSpeed(e, d, vmax) / d).clone();
  }
  /* Подход к цели на рабочую дистанцию (0,68 дальности) — для фокуса
     огня, атаки с ходу и «Охоты». Широкая мёртвая зона: попал в неё —
     стоишь и стреляешь. Облетать по дуге позволено только эскорту,
     у которого это его манера боя; крейсер, носитель и флагман держат
     линию. Раньше корабль болтало: чуть далеко — полный вперёд, чуть
     близко — полный назад, и на экране это читалось роем, а не флотом */
  function approach(e, t, range0, vmax) {
    const def = e.def;
    /* По авиации бьёт ПВО, а не главный калибр — к машине подходим на
       дальность зениток (C14): с 0,68 дальности орудия их не достать */
    const want = t.kind === 'craft' ? Math.min(range0 * 0.68, def.pd ? def.pd.range * 0.7 : range0 * 0.5)
      : e.jam ? e.jam.lockRange * 0.8 : range0 * 0.68;     // под помехами наводится только вблизи
    _v.subVectors(t.pos, e.pos);
    const d = _v.length() || 1;
    _v.divideScalar(d);
    if (d > want * 1.08) return _v.multiplyScalar(arriveSpeed(e, d - want, vmax || def.maxSpeed)).clone();
    if (d < want * 0.55) return _v.multiplyScalar(-def.maxSpeed * 0.5).clone();
    if (def.cls === 'escort') return _v3.crossVectors(_v, UP).normalize().multiplyScalar(def.maxSpeed * 0.45).clone();
    return ZERO;
  }
  /* «Охрана» с целью: встать на рабочую дистанцию от неё, но не дальше
     поводка от своей точки. Цель ушла за поводок — бьём, пока достаём,
     а догонять не идём; кончилась цель — назад, к точке (см. updateShip) */
  function guardStation(e, t, range0) {
    const want = e.jam && t.kind === 'ship' ? e.jam.lockRange * 0.8 : range0 * 0.68;
    _v.subVectors(e.pos, t.pos);
    const d = _v.length() || 1;
    const r = d > want * 1.08 || d < want * 0.55 ? want : d;
    _v3.copy(t.pos).addScaledVector(_v, r / d);
    _v2.subVectors(_v3, e.anchor);
    const L = leashOf(e);
    if (_v2.length() > L) _v3.copy(e.anchor).addScaledVector(_v2, L / _v2.length());
    return _v3.distanceTo(e.pos) < 10 ? ZERO : arrive(e, _v3, e.def.maxSpeed);
  }

  // ── КОРАБЛИ ──────────────────────────────────────────────

  function updateShip(e, dt) {
    // Переход в гипер: корабль замирает, копит энергию и беззащитен
    if (e.hyper) { updateHyper(e, dt); return; }
    /* Ионный луч с планеты выжигает двигатели: корабль не тянет и не
       поворачивает, только висит по инерции и огрызается орудиями.
       Это и делает противоорбитальную оборону страшной — обездвиженный
       крейсер ловит следующий залп уже гарантированно. */
    e.ionized = e.ionUntil && state.time < e.ionUntil;
    // Линкор с повреждениями больше 80% уходит сам, не спрашивая
    if (e.def.flee && e.hp / e.maxHp < (e.def.flee || HYPER.fleeThreshold) && !e.station) {
      if (beginJump(e)) fleeNote(e);
      if (e.side === state.playerSide) toast(`${e.name}: повреждения критические, уходим в гипер`);
      return;
    }
    e.retarget -= dt;
    // Цель ушла в маскировку — стрелять не по чему, приказ снят (C18)
    if (e.target && (e.target.dead || unseen(e.target))) e.target = null;
    /* Фокус огня держится, пока цель жива и видна. Кончилась — «Охрана»
       остаётся там, куда дошла: приказ атаковать переносит участок
       вперёд, а не возвращает корабль за полполя на прежнюю точку */
    if (e.forced && (e.forced.dead || unseen(e.forced))) {
      e.forced = null;
      if (!e.guardOf) e.anchor.copy(e.pos);
    }
    // Под чужими помехами (см. jamPick): дальность наведения — lockRange
    e.jam = e.guns.length ? jamProfile(e.pos, e.side) : null;
    // jamShot — временная цель «под помехами»; цель сменили приказом — она уже не та
    if (e.jamShot && e.jamShot !== e.target) e.jamShot = null;
    if (!e.target || e.retarget <= 0 || (e.forced && e.target !== e.forced && e.forced.kind !== 'squad' && !e.jamShot)) {
      e.target = liveTarget(e, e.forced) || shipAcquire(e);
      e.jamShot = null;
      e.retarget = rnd(0.8, 1.6);
    }
    if (e.jamShot && !e.jam) {        // вышли из-под купола или глушитель сбит — к своей цели
      e.jamShot = null;
      e.target = liveTarget(e, e.forced) || shipAcquire(e);
    }
    if (e.jam && !e.jamShot && (!e.target ||
        (e.target.kind === 'ship' && e.target.pos.distanceTo(e.pos) > e.jam.lockRange))) {
      const j = jamPick(e);
      if (j) { e.target = j; e.jamShot = j; }
    }
    // Свои под помехами — одной строкой в ленте, не чаще раза в 25 с
    if (e.jam && e.side === state.playerSide && !e.station && state.time - jamFeedAt > 25 &&
        e.target && e.target.kind === 'ship' && e.target.pos.distanceTo(e.pos) > e.jam.lockRange) {
      jamFeedAt = state.time;
      feed(`Наш ${shortName(e)} под помехами РЭБ — бьёт только вблизи`, 'warn');
    }

    const def = e.def;

    if (!e.station) {
      // ── куда хотим лететь
      let desiredVel = null;
      const range0 = e.guns[0] ? e.guns[0].def.range : 300;
      // В строю приказа — со скоростью самого медленного (C70)
      const vmax = e.groupSpeed || def.maxSpeed;
      // Охраняемый корабль погиб или ушёл — сторожим то место, где стоим
      if (e.guardOf && (e.guardOf.dead || e.guardOf.hyper)) { e.guardOf = null; e.anchor.copy(e.pos); }
      if (e.guardOf) e.anchor.copy(e.guardOf.pos).add(e.guardOff);
      /* Атака с ходу (A): идёт к точке, но встречного в 1,3 дальности
         не пропускает — останавливается и бьёт, а кончился враг —
         идёт дальше. Обычный приказ «идти» стреляет на ходу и не
         задерживается. */
      const fighting = e.amove && e.target && !e.target.dead &&
        e.pos.distanceTo(e.target.pos) < range0 * 1.3;
      const goal = e.moveTo || (e.amove && !fighting ? e.amove : null);
      if (goal) {
        desiredVel = arrive(e, goal, vmax);
        const d = e.pos.distanceTo(goal), v = e.vel.length();
        /* Пришёл — стоит у точки, и точка становится его участком. Соседи
           по строю могут не пустить ровно в неё: «рядом и стоит» две с
           половиной секунды — тоже приход, иначе приказ висел бы вечно */
        e.arriveT = d < 60 && v < 4 ? e.arriveT + dt : 0;
        if ((d < 8 && v < 3) || e.arriveT > 2.5) {
          if (!e.guardOf) e.anchor.copy(goal);
          if (e.moveTo) e.moveTo = null; else e.amove = null;
          e.groupSpeed = 0; e.arriveT = 0;
        }
      } else if (e.target && (e.forced || fighting || e.stance === 'hunt')) {
        desiredVel = approach(e, e.target, range0, vmax);
      } else if (e.target && e.stance === 'guard') {
        desiredVel = guardStation(e, e.target, range0);
      } else if ((e.stance === 'guard' || (e.stance === 'hunt' && !e.guns.length)) && e.pos.distanceTo(e.anchor) > 12) {
        // безоружному «Охота» — та же «Охрана»: охотиться ему нечем (P5)
        desiredVel = arrive(e, e.anchor, vmax);   // целей нет — назад, на свой участок
      } else {
        /* «Держать» и пустой участок: стоим. С целью — доворачиваем
           корпус и бьём (стрельба ниже, как всегда) */
        desiredVel = ZERO;
      }

      /* РАСТАЛКИВАНИЕ — своих и ЧУЖИХ (C87, C59), по размеру корпуса
         на экране, а не по радиусу класса. Раньше расталкивались только
         свои и по радиусу класса, а модель в полтора-четыре раза больше:
         флоты проходили друг сквозь друга (замер — минимальная дистанция
         9–60 при радиусах 12–22), и бой выглядел двумя клубками, которые
         слиплись. Чужому — чуть больше места и сильнее толчок */
      for (const o of state.ships) {
        if (o === e || o.dead) continue;
        const foe = o.side !== e.side;
        const dd = o.pos.distanceTo(e.pos);
        const min = (o.hull + e.hull) * (foe ? 1.15 : 1.0);
        if (dd < min && dd > 0.01) {
          _v2.subVectors(e.pos, o.pos).divideScalar(dd).multiplyScalar((min - dd) / min * def.maxSpeed * (foe ? 1.1 : 0.8));
          desiredVel = (desiredVel === ZERO ? _v2.clone() : desiredVel.clone().add(_v2));
        }
      }

      /* ДРИФТ. С выключенными гасителями инерции корабль не правит
         вектор скорости вовсе — он скользит по нему, как есть, зато
         корпус разворачивается свободно. Смысл в том, чтобы уходить
         от одного противника, продолжая расстреливать другого: курс
         и прицел перестают быть одним и тем же. Цена — потеря
         управления: остановиться или свернуть, не включив гасители
         обратно, нельзя. */
      if (!e.drift) {
        thrustTo(e, desiredVel, dt, def.thrust, REV);
        /* Сразу после выхода из гипера скорость НЕ режем: корабль влетает
           на двух с половиной своих скоростях и гасит их маршевыми — это
           и видно по соплам. Раньше её срезало в следующем кадре (C87) */
        if (e.vel.length() > def.maxSpeed * 1.25 && !(e.exitUntil > state.time)) e.vel.setLength(def.maxSpeed * 1.25);
      } else {
        e.thrustNow = 0;
      }

      // ── куда смотрим: цель важнее курса
      let look = null;
      if (e.drift && e.target) {
        // в дрифте корпус всегда на цели, куда бы корабль ни летел
        look = _v2.subVectors(e.target.pos, e.pos);
      } else if (e.target && e.pos.distanceTo(e.target.pos) < (e.guns[0] ? e.guns[0].def.range : 400) * 1.5) {
        look = _v2.subVectors(e.target.pos, e.pos);
      } else if (desiredVel && desiredVel.lengthSq() > 1) {
        look = _v2.copy(desiredVel);
      } else if (e.vel.lengthSq() > 1) {
        look = _v2.copy(e.vel);
      }
      face(e, look, dt, def.turn);
      integrate(e, dt);

      /* Факел ВЫТЯГИВАЕТСЯ с тягой, а не раздувается во все стороны:
         длина по оси сопла (местная Z), ширина почти не меняется.
         Плюс мелкая дрожь — ровное пламя выглядит нарисованным. */
      const thr = e.thrustNow;
      const flick = 1 + Math.sin(state.time * 26 + e.uid) * 0.07;
      const wide = 0.72 + thr * 0.30;
      const long = (0.55 + thr * 1.5) * flick;
      for (const en of e.obj.userData.engines || []) {
        const k = clamp(dt * 6, 0, 1);
        en.scale.set(lerp(en.scale.x, wide, k), lerp(en.scale.y, wide, k),
                     lerp(en.scale.z, long, k));
      }
    } else if (e.target) {
      face(e, _v2.subVectors(e.target.pos, e.pos), dt, def.turn);
    }

    // ── главный калибр
    for (const g of e.guns) {
      g.cd -= dt;
      const t = e.target;
      if (!t || t.dead) continue;
      const d = e.pos.distanceTo(t.pos);
      if (d > g.def.range) continue;
      if (dmgMult(SPACE_DMG, g.def.type, t.cls) <= 0) continue;
      _v.subVectors(t.pos, e.pos).divideScalar(d || 1);
      if (e.dir.dot(_v) < (e.station ? -0.3 : 0.25)) continue;   // башня не довернулась
      // Помехи: под чужим куполом наведение работает только вблизи
      if (e.jam && d > e.jam.lockRange) continue;
      // РЭБ-излучатель с планеты слепит так же, как чужой купол
      if (e.blindUntil && state.time < e.blindUntil && d > ECM.lockRange) continue;

      if (g.def.charge && g.cd <= g.def.charge && g.cd > 0) {
        if (state.time - g.chargeFx > 0.09) {
          g.chargeFx = state.time;
          fx.flash(muzzleWorld(e, g.idx), e.radius * (1 - g.cd / g.def.charge) * 1.7 + 2, 0xfff0d0, 0.14);
        }
      }
      if (g.cd > 0) continue;
      g.cd = g.def.cd;
      reveal(e);           // выстрел срывает маскировку
      fireMainGun(e, g, t);
    }

    // ── ПВО: само, без приказов, только по мелочи
    if (def.pd) {
      const pd = def.pd;
      const foe = enemyOf(e.side);
      for (let i = 0; i < e.pdCd.length; i++) {
        e.pdCd[i] -= dt;
        if (e.pdCd[i] > 0) continue;
        const t = nearest(e.pos, state.proj, pd.range, x => x.side === foe)
               || nearest(e.pos, state.craft, pd.range, x => x.side === foe);
        if (!t) { e.pdCd[i] = 0.2; continue; }
        e.pdCd[i] = pd.cd * rnd(0.85, 1.2);
        const jamPd = jamProfile(e.pos, e.side);
        const pdMult = jamPd ? jamPd.pdPenalty : 1;
        reveal(e);
        /* Зенитный огонь — длинный росчерк, а не мгновенная нитка.
           На референсах именно эти трассы держат кадр: десятки
           длинных линий, идущих через полэкрана. Мгновенная линия
           во всю дистанцию читается подсветкой цели, а короткая
           искра теряется. */
        const from = pdWorld(e, i);
        const col = e.side === state.playerSide ? 0x8fe0ff : 0xffb45a;
        fx.shot(from, t.pos, { color: col, width: 0.55, len: 46, speed: 780 });
        fx.muzzle(from, _v.subVectors(t.pos, from).normalize(), 1.4, col);
        sound.at('pd', from);
        damage(t, pd.dmg * pdMult, 'pd', e);
      }
    }
  }

  function muzzleWorld(e, idx) {
    const list = e.obj.userData.muzzles || [ZERO];
    return list[Math.min(idx, list.length - 1)].clone().applyQuaternion(e.obj.quaternion).add(e.pos);
  }
  function pdWorld(e, idx) {
    const list = e.obj.userData.pdPoints || [ZERO];
    return list[idx % list.length].clone().applyQuaternion(e.obj.quaternion).add(e.pos);
  }

  function fireMainGun(e, g, t) {
    if (!e.firedAt) e.firedAt = state.time;   // замер темпа: когда корабль вступил в бой
    const from = muzzleWorld(e, g.idx);
    const color = e.side === state.playerSide ? 0x7fd8ff : 0xff8f5a;
    if (g.def.type === 'missile') {
      for (let i = 0; i < (g.def.salvo || 1); i++) {
        const p = spawnProjectile(e, t, g.def.dmg * aiMul(e.side), 'missile', 130, 26);
        p.dir.add(_v.set(rnd(-1, 1), rnd(-1, 1), rnd(-1, 1)).multiplyScalar(g.def.spread || 0.05)).normalize();
        p.wobble = rnd(0, 6.28);
      }
      // Старт ракет: пламя из труб и клубы отработанного топлива
      sound.at('missile', from);
      fx.muzzle(from, _v.subVectors(t.pos, from).normalize(), e.radius * 0.7, 0xffd0a0);
      fx.sparks(from, 6, 0xffc890, 30, false);
      for (let i = 0; i < 3; i++) fx.puff(from, e.radius * 0.3, 0x9a9186, 0.6);
      return;
    }
    /* Главный калибр — лазер: белое ядро в цветном ореоле, ударное
       кольцо на цели, послесвечение канала и брызги обломков
       НАВСТРЕЧУ выстрелу. Обломки, летящие обратно к стрелявшему, —
       мелочь, по которой попадание читается как удар по броне,
       а не как подсветка цели. */
    const w = 0.9 + e.radius * 0.07;
    // Главный калибр звучит тяжёлым лучом, орудия эскорта — сухим хлопком
    if (g.def.type === 'heavy') {
      sound.at('laser', from); sound.at('hit', t.pos);
      // Первый залп главного калибра — конец сближения (замер темпа, C70)
      if (!state.stats.firstGun && t.kind === 'ship') state.stats.firstGun = state.time;
    } else sound.at('light', from);
    fx.laser(from, t.pos, { color, width: w, life: 0.5 });
    fx.delay(0.06, () => fx.beam(from, t.pos, { color, width: w * 0.7, life: 0.45 }));
    fx.sparks(t.pos, 8, 0xfff0c0, 34, false);
    _v.subVectors(from, t.pos).normalize();
    // Одним вызовом, а не четырьмя по одной: так пул может их проредить
    fx.debris(_v2.copy(t.pos).addScaledVector(_v, 2), 4, 0x8a7a66, 26, 0);
    fx.shake = Math.min(1, fx.shake + 0.14);
    damage(t, g.def.dmg * aiMul(e.side), g.def.type, e);
  }

  // ── АВИАЦИЯ ──────────────────────────────────────────────

  function flyToward(c, aimPoint, dt, throttle) {
    _v.subVectors(aimPoint, c.pos);
    const d = _v.length() || 1;
    _v.divideScalar(d);
    face(c, _v, dt, c.def.turn);
    // истребитель тянет туда, куда смотрит нос — это и даёт вираж
    _v2.copy(c.dir).multiplyScalar(c.def.maxSpeed * throttle);
    thrustTo(c, _v2, dt, c.def.thrust);
    if (c.vel.length() > c.def.maxSpeed * 1.15) c.vel.setLength(c.def.maxSpeed * 1.15);
    integrate(c, dt);
  }

  /* Машина без ракет и без носителя уходит к своему краю поля и там
     пропадает из боя: висеть пустой над схваткой ей незачем, а мельтешить
     в ростере — тем более. Предел по времени — чтобы не застряла. */
  function leaveField(c, dt) {
    c.leaveT = (c.leaveT || 0) + dt;
    const sign = sides[c.side].sign;
    flyToward(c, _v3.set(c.pos.x, c.pos.y, sign * (FIELD + 400)), dt, 1);
    if (Math.abs(c.pos.z) < FIELD - 40 && c.leaveT < 25) return;
    c.dead = true;
    scene.remove(c.obj);
    const squad = c.squad;
    if (!squad) return;
    squad.craft = squad.craft.filter(x => x !== c);
    if (!squad.craft.length) killSquad(squad, true);
  }

  function updateCraft(c, dt) {
    const squad = c.squad;
    if (c.target && (c.target.dead || unseen(c.target))) c.target = null;

    /* Инверсионный след. На референсах именно эти тонкие дуги
       превращают точки истребителей в живой рой: без следа звено
       читается как несколько мушек, со следом — как маневр.
       Кладём по времени, а не по кадрам: на ускорении след должен
       быть той же густоты. */
    if (!craftHidden(c)) {
      /* Реже и мельче, чем хочется: сплошная белая нитка за каждой
         машиной забивает кадр и съедает бюджет спрайтов, а нужен
         намёк на манёвр. */
      c.trailAt = (c.trailAt || 0) - dt;
      if (c.trailAt <= 0) {
        c.trailAt = 0.16;
        // пул занят или машина далеко от камеры — след не кладём (C44)
        if (fx.trailOk(c.pos)) {
          const back = _v.copy(c.pos).addScaledVector(c.dir, -3.2);
          const warm = c.side === state.playerSide ? 0x8fc8ef : 0xdfae7e;
          fx.puff(back, 0.85, warm, 0.34);
        }
      }
    }

    // Пустая машина без носителя уходит из боя к своему краю поля
    if (c.leaving) { leaveField(c, dt); return; }

    // ── боезапас: пусто → перезарядка прямо в космосе, пока есть запас
    if (c.def.weaponKind === 'missile') {
      if (c.reloading > 0) {
        c.reloading -= dt;
        if (c.reloading <= 0) {
          c.ammo = c.def.ammo;
          fx.flash(c.pos, 4, 0x9fe8ff, 0.3);
        } else {
          // на перезарядке машина выходит из боя и держится в стороне
          const away = (squad && squad.home && !squad.home.dead) ? squad.home.pos : ZERO;
          flyToward(c, away, dt, 0.8);
          return;
        }
      } else if (c.ammo <= 0) {
        if (c.reloads > 0) {
          c.reloads--;
          c.reloading = c.def.reloadTime;
          if (c.slot === 0 && squad && squad.side === state.playerSide) {
            toast(`${c.def.name}: перезарядка, осталось ${c.reloads} комплектов`);
          }
          return;
        }
        // запас кончился — только на носитель
        if (squad && !squad.recall) {
          squad.recall = true;
          /* Сказать ОДИН раз на звено. Раньше у звена без носителя флаг
             возврата каждый кадр ставился и тут же снимался, и с ним
             каждый кадр — новое сообщение: сотни в секунду (C8). */
          if (squad.side === state.playerSide && !squad.toldEmpty) {
            squad.toldEmpty = true;
            toast(`${c.def.name}: ракеты кончились, звено уходит на носитель`);
          }
        }
      }
    }

    if (squad && squad.recall) {
      let home = squad.home;
      if (!home || home.dead) home = rehome(squad);
      if (home) {
        if (c.pos.distanceTo(home.pos) < home.radius * 2.4) {
          c.dead = true;
          scene.remove(c.obj);
          squad.craft = squad.craft.filter(x => x !== c);
          if (!squad.craft.length) {
            home.hangar.free = Math.min(home.hangar.bays, home.hangar.free + 1);
            killSquad(squad, true);
            if (squad.side === state.playerSide) toast('Звено село, ангар свободен');
          }
          return;
        }
        flyToward(c, home.pos, dt, 1);
        return;
      }
      // Садиться некуда: носителей у этой стороны не осталось
      squad.recall = false;
      const empty = c.def.weaponKind === 'missile' && c.ammo <= 0 && !(c.reloads > 0);
      if (empty) {
        c.leaving = true;
        if (squad.side === state.playerSide && !squad.toldLeave) {
          squad.toldLeave = true;
          toast(`${c.def.name}: ракет нет, садиться некуда — машины выходят из боя`);
        }
        return;
      }
      if (squad.side === state.playerSide && !squad.toldNoHome) {
        squad.toldNoHome = true;
        const any = state.ships.some(s => !s.dead && !s.hyper && s.side === squad.side && s.hangar);
        toast(`${c.def.name}: садиться некуда — ${any ? 'все ангары заняты' : 'носителей не осталось'}`);
      }
    }

    if (!c.target) c.target = liveTarget(c, squad && squad.target) || craftAcquire(c);

    if (!c.target) {
      if (squad && squad.moveTo) { flyToward(c, squad.moveTo, dt, 0.9); return; }
      const anchor = (squad && squad.home && !squad.home.dead) ? squad.home.pos : ZERO;
      _v3.copy(anchor).add(_v.set(
        Math.sin(state.time * 0.35 + c.slot) * 130, Math.cos(state.time * 0.3 + c.slot) * 40,
        Math.cos(state.time * 0.35 + c.slot) * 130));
      flyToward(c, _v3, dt, 0.7);
      return;
    }

    const t = c.target;
    const d = c.pos.distanceTo(t.pos);
    const wr = c.def.range;

    if (c.role === 'bomber') {
      // заход — пуск торпед — отворот — новый заход
      if (c.phase === 'break') {
        if (state.time > c.breakUntil) c.phase = 'out';
        else {
          _v3.subVectors(c.pos, t.pos).setLength(400).add(c.pos).add(_v.set(0, 90, 0));
          flyToward(c, _v3, dt, 1);
          return;
        }
      }
      flyToward(c, t.pos, dt, 1);
      c.cd -= dt;
      if (d < wr && c.cd <= 0 && c.ammo > 0) {
        c.cd = c.def.cd;
        fireMissile(c, t);
        c.phase = 'break';
        c.breakUntil = state.time + rnd(3.0, 4.2);
      }
      if (d < (t.radius || 10) + 30) { c.phase = 'break'; c.breakUntil = state.time + 3; }
      return;
    }

    // собачья свалка: заходим, стреляем, проскакиваем, разворачиваемся
    const desired = t.kind === 'ship' ? Math.min(wr * 0.8, (t.radius || 8) + 34) : wr * 0.6;
    if (d < desired * 0.75) {
      _v3.subVectors(c.pos, t.pos).normalize().multiplyScalar(260).add(c.pos);
      _v3.x += Math.sin(state.time + c.slot * 2) * 60;
      _v3.y += Math.cos(state.time * 0.8 + c.slot) * 40;
    } else {
      _v3.copy(t.pos);
      _v3.x += Math.sin(state.time * 1.3 + c.slot * 1.7) * 20;
      _v3.y += Math.cos(state.time * 1.1 + c.slot * 2.3) * 16;
    }
    flyToward(c, _v3, dt, 1);

    c.cd -= dt;
    if (d <= wr && c.cd <= 0) {
      _v2.subVectors(t.pos, c.pos).divideScalar(d || 1);
      if (c.dir.dot(_v2) > 0.7) {
        c.cd = c.def.cd;
        if (c.def.weaponKind === 'missile') {
          if (c.ammo > 0) fireMissile(c, t);
        } else {
          // перехватчик — пушки: очередями, без боезапаса
          c.revealUntil = state.time + STEALTH.revealFor;
          fx.tracer(_v.copy(c.pos).addScaledVector(c.dir, 4), t.pos,
            c.side === state.playerSide ? 0x9fe0ff : 0xffb070, 0.09, 0.2);
          sound.at('gun', c.pos);
          damage(t, c.def.dmg * aiMul(c.side), c.def.weapon, c);
          if (t.dead) fx.explosion(t.pos, t.kind === 'craft' ? 4 : 6, 0xffc070);
        }
      }
    }
  }

  function updateProjectile(p, dt) {
    p.life -= dt;
    if (p.life <= 0) { destroy(p); return; }
    if (p.target && p.target.dead) p.target = null;
    // Под куполом помех головка самонаведения слепнет — снаряд идёт прямо
    if (p.target && ECM.missileBlind && jammed(p.pos, p.side)) p.blind = true;
    if (p.target && !p.blind) {
      _v.subVectors(p.target.pos, p.pos).normalize();
      p.dir.lerp(_v, clamp((p.weapon === 'torp' ? 1.1 : 1.8) * dt, 0, 1)).normalize();
    }
    p.pos.addScaledVector(p.dir, p.speed * dt);
    p.obj.quaternion.copy(quatFromDir(p.dir));
    /* Дымный след. Кладём его по времени, а не каждый кадр: на
       четырёхкратной скорости кадров мало, а на однократной их
       много, и в обоих случаях след должен быть одинаковой
       густоты. */
    p.trailAt = (p.trailAt || 0) - dt;
    if (p.trailAt <= 0) {
      p.trailAt = 0.035;
      /* След ракеты — около восемнадцати спрайтов на ракету, главный
         пожиратель пула. При занятом пуле и вдали от камеры его нет,
         зато взрывы и лучи не обрываются (C44) */
      if (fx.trailOk(p.pos)) {
        const back = _v.copy(p.pos).addScaledVector(p.dir, -3);
        fx.puff(back, p.weapon === 'torp' ? 2.2 : 1.4, 0x8d8479, 0.5);
        fx.flash(back, p.weapon === 'torp' ? 2.6 : 1.7, 0xffb060, 0.12);
      }
    }
    if (p.wobble !== undefined) {
      p.wobble += dt * 9;
      p.pos.y += Math.sin(p.wobble) * 6 * dt;
    }
    if (p.target && p.pos.distanceTo(p.target.pos) < (p.target.radius || 8) + 5) {
      fx.explosion(p.pos, p.weapon === 'torp' ? 12 : 8, 0xffb060);
      sound.at('hit', p.pos);
      damage(p.target, p.dmg, p.weapon, p.owner);
      destroy(p);
    }
  }

  // ── ИИ ПО РОЛЯМ (C59) ────────────────────────────────────
  /* Раньше ИИ раз в 4–7 с отправлял 70% флота в случайную точку ±170
     у центра флота игрока, а 45% кораблей навсегда получали приказ бить
     носитель: два клубка слипались, и всё решалось за полминуты свалки.
     Теперь у каждого корабля своя работа:
     — тяжёлые (крейсеры, флагманы) держат ЛИНИЮ на 0,7 дальности от
       цели и бьют одну общую — фокус огня (доля — по сложности, focus);
     — фрегаты охраняют носитель (зонт ПВО), корветы перехватывают
       чужие звенья у своего флота, а без звеньев держат завесу перед
       линией тяжёлых;
     — носитель держится за линией, РЭБ — рядом с тяжёлыми;
     — побитые (меньше 30%) отходят за линию, совсем разбитые тяжёлые
       (меньше 18%) уходят в гипер — они уцелеют для кампании;
     — флот, потерявший больше двух третей силы и проигрывающий, уходит
       весь: добивать последнего беглеца по всему полю не интересно;
     — под наведённой ядерной ракетой с планеты корабли расходятся.
     Сложность действует как прежде: tempo — как часто ИИ думает, aim —
     урон, плюс focus. */
  const ai = { side: enemyOf(state.playerSide), next: 3 * DIFF.tempo, focus: null, hp0: 0, dodged: -1,
    seen: 0, search: null, toldSearch: -99, hadHeavy: false };
  const aiRole = s => (s.station ? 'station' : s.cls === 'carrier' ? 'carrier' : s.ecm ? 'ecm'
    : s.cls === 'capital' ? 'heavy' : s.def.id === 'frigate' ? 'frigate' : 'corvette');
  // доля «своих» по uid, а не случайная: решение не скачет от тика к тику
  const share = s => ((s.uid * 0.6180339) % 1);

  function aiDodge() {
    const g = state.gun;
    if (!g || g.side !== ai.side || !g.warned || !g.aim || g.def.kind !== 'nuke' || ai.dodged === g.next) return;
    ai.dodged = g.next;
    for (const s of state.ships) {
      if (s.dead || s.side !== ai.side || s.station || s.hyper) continue;
      const R = g.def.radius + s.hull + 60;
      if (s.pos.distanceTo(g.aim) > R) continue;
      _v.subVectors(s.pos, g.aim).setY(0);
      if (_v.lengthSq() < 1) _v.set(rnd(-1, 1), 0, rnd(-1, 1));
      s.moveTo = g.aim.clone().add(_v.normalize().multiplyScalar(R + 30)).setY(s.pos.y);
      s.groupSpeed = 0;
    }
  }

  function updateAI(dt) {
    aiDodge();
    ai.next -= dt;
    if (ai.next > 0) return;
    ai.next = rnd(2.5, 4) * DIFF.tempo;
    const all = state.ships.filter(s => !s.dead && s.side === ai.side);
    const mine = all.filter(s => !s.hyper);
    /* ИИ видит только то, что видно: скрытые корабли Рииза для него
       не существуют, пока не выстрелят или не подойдут вплотную.
       Раньше он прицельно добивал невидимый носитель игрока (C18). */
    const foes = state.ships.filter(s => !s.dead && s.side !== ai.side && !hidden(s));
    if (!mine.length || state.retreat[ai.side]) return;

    // РЭБ: если нас глушат — переключаем свои корабли на прикрытие
    const myEcm = mine.filter(s => s.ecm);
    if (myEcm.length) {
      const underJam = mine.some(s => jammed(s.pos, s.side));
      for (const s of myEcm) s.ecm.mode = underJam ? 'shield' : 'jam';
    }

    const enemyCraft = state.craft.filter(c => c.side !== ai.side && !craftHidden(c)).length;
    const myCraft = state.craft.filter(c => c.side === ai.side).length;
    for (const s of mine) {
      if (!s.hangar || s.hangar.free <= 0) continue;
      let role = 'fighter';
      if (enemyCraft > myCraft + 4) role = 'interceptor';
      else if (foes.some(f => f.cls !== 'escort')) role = 'bomber';
      launchSquadron(s, role);
    }
    /* Никого не видно, а противник на орбите есть — значит, он скрыт:
       ищем там, где его видели последний раз (P5). Раньше ИИ просто
       держал строй, и бой с Риизом, у которого остался молчащий
       невидимый корабль, не кончался никогда: 360 игровых секунд флот
       Девиана стоял в полутора тысячах от носителя и не искал его */
    if (!foes.length) { aiSearch(mine); return; }
    ai.seen = state.time;
    if (ai.search) endSearch(mine);

    /* Отход всем флотом: силы меньше трети от начальной и противник
       сильнее вдвое — или не осталось ни одного целого корабля с орудиями
       (одни побитые за линией: замер показал бой, вставший на десять
       минут, где обе стороны держались позади). Резерв, если он ещё
       в пути, сначала дожидаемся */
    const hpOf = list => list.reduce((a, s) => a + Math.max(0, s.hp), 0);
    const myHp = hpOf(all), foeHp = hpOf(state.ships.filter(s => !s.dead && s.side !== ai.side));
    ai.hp0 = Math.max(ai.hp0, myHp);
    const armed = mine.filter(s => !s.station && s.guns.length);
    const broken = armed.length > 0 && armed.every(s => s.hp / s.maxHp < 0.3);
    if (((myHp < ai.hp0 * 0.33 && myHp * 2 < foeHp) || broken) && !state.reinforceAt[ai.side] &&
        mine.some(s => !s.station)) {
      if (orderRetreat(ai.side)) feedFoeRetreat();
      return;
    }

    const free = mine.filter(s => !s.station);
    const heavies = free.filter(s => aiRole(s) === 'heavy');
    const center = list => { const c = new THREE.Vector3(); for (const s of list) c.add(s.pos); return c.divideScalar(Math.max(1, list.length)); };
    const F = center(foes);

    /* Тяжёлых не осталось, а у противника они есть, и мы не сильнее —
       уходим всем флотом (P5). Без тяжёлых строй ИИ терял опору: носители
       и эскорт отходили «за линию» от СОБСТВЕННОГО центра, каждый тик ещё
       на 440–760 дальше, и игрок полминуты гнался за ними через всё поле,
       не сделав ни выстрела (замер «толкового» боя: с 220-й по 262-ю
       секунду прочность обеих сторон не менялась). Отход виден: лента
       и «⇢ гипер» у каждого, а копящий гипер беззащитен */
    if (heavies.length) ai.hadHeavy = true;
    const foeHeavy = foes.some(f => f.cls === 'capital' && f.guns.length);
    if (ai.hadHeavy && !heavies.length && foeHeavy && myHp < foeHp &&
        !state.reinforceAt[ai.side] && free.length) {
      if (orderRetreat(ai.side)) feedFoeRetreat();
      return;
    }
    /* Точка отсчёта строя — тяжёлые В СТРОЮ (не побитые, которые сами
       уходят «за линию»). Нет таких — считаем от противника, а не от
       самих себя: «отойти на 560 от своего центра» каждый тик отодвигало
       этот центр, и побитые уходили к краю поля */
    const line = heavies.filter(s => s.hp / s.maxHp >= 0.3);
    let C;
    if (line.length) C = center(line);
    else {
      const own = center(free.length ? free : mine);
      const back = _v2.subVectors(own, F).setY(0);
      if (back.lengthSq() < 1) back.set(0, 0, sides[ai.side].sign);
      back.normalize();
      const reach = Math.max(300, ...heavies.map(s => (s.guns[0] ? s.guns[0].def.range : 300)));
      C = F.clone().addScaledVector(back, Math.max(500, reach * 0.68));
      C.y = own.y;
    }
    const axis = _v3.subVectors(F, C).setY(0);
    if (axis.lengthSq() < 1) axis.set(0, 0, -sides[ai.side].sign);
    axis.normalize();
    const ax = axis.clone(), side = new THREE.Vector3(-ax.z, 0, ax.x);
    const spot = (back, lat, y = 0) => C.clone().addScaledVector(ax, back).addScaledVector(side, lat).setY(C.y + y);

    /* Общая цель тяжёлых — та, чья гибель быстрее всего снимает чужой
       огонь: угроза цели (её урон в секунду; у РЭБ — купол, у носителя —
       авиация), умноженная на то, как глубоко в неё входит главный
       калибр (множитель по классу и броня), и делённая на остаток
       прочности. Раненая и мягкая — охотнее, бронированная — в свой
       черёд. Держим прежнюю, пока жива, видна и не убежала: метание
       огня от цели к цели и есть то, что отличает толпу от флота.
       Замер зеркального боя: ИИ, бивший «самое ценное» (флагман,
       носитель), наносил втрое меньше урона, чем автовыбор игрока */
    const maxR = Math.max(300, ...heavies.map(s => s.guns[0] ? s.guns[0].def.range : 300));
    const threat = f => f.guns.reduce((a, g) => a + g.def.dmg * (g.def.salvo || 1) / g.def.cd, 0) +
      (f.hangar ? 40 : 0) + (f.ecm && f.ecm.power > 0.5 ? 120 : f.ecm ? 40 : 0);
    const focusScore = f => {
      const d = f.pos.distanceTo(C);
      const sc = threat(f) * dmgMult(SPACE_DMG, 'heavy', f.cls) * (1 - (f.armor || 0)) / Math.max(1, f.hp);
      return d > maxR * 1.3 ? sc * 0.3 : sc;
    };
    if (!ai.focus || ai.focus.dead || hidden(ai.focus) || ai.focus.pos.distanceTo(C) > maxR * 1.8 ||
        focusScore(ai.focus) * 1.6 < Math.max(...foes.map(focusScore))) {
      let best = null, bs = -Infinity;
      for (const f of foes) {
        const sc = focusScore(f);
        if (sc > bs) { bs = sc; best = f; }
      }
      ai.focus = best;
    }
    const slowHeavy = heavies.length > 1 ? Math.min(...heavies.map(s => s.def.maxSpeed)) : 0;
    // Встать в охранение корабля ward — кольцом вокруг него, на n-м месте
    const escort = (s, ward, n) => {
      if (!ward || ward === s) { s.guardOf = null; s.anchor.copy(spot(80, (share(s) - 0.5) * 300)); return; }
      if (s.guardOf === ward) return;
      const a = n * 2.1 + 0.5;
      s.guardOf = ward;
      s.guardOff = new THREE.Vector3(Math.cos(a), 0, Math.sin(a)).multiplyScalar(ward.hull + s.hull + 60);
    };

    const carriers = free.filter(s => aiRole(s) === 'carrier');
    /* Тяжёлых нет вовсе — эскорт сам становится ударной силой: идёт
       бить, а не стоит «при тяжёлых», которых нет (P5). Иначе флот
       без тяжёлых, но сильнее игрока, стоял поодаль и кормил его ПВО
       звеньями бомбардировщиков — минутами без единого выстрела */
    const leaderless = !heavies.length;
    const threats = state.squads.filter(q => !q.dead && q.side !== ai.side && !unseen(q) &&
      free.some(s => s.pos.distanceTo(q.pos) < 750));
    let fi = 0, ci = 0, vi = 0;
    const corv = free.filter(s => aiRole(s) === 'corvette');
    for (const s of free) {
      const r = aiRole(s), hp = s.hp / s.maxHp;
      s.stance = 'guard';
      if (s.moveTo && ai.dodged === (state.gun && state.gun.next)) continue;   // уходит из-под ракеты
      // Совсем разбитый тяжёлый — в гипер: уцелеет для кампании
      if (r === 'heavy' && hp < 0.18) { if (beginJump(s)) fleeNote(s); continue; }
      // Побитый — за линию: бьёт оттуда, что подойдёт, но вперёд не лезет
      if (hp < 0.3 && r !== 'carrier') {
        s.forced = null; s.guardOf = null; s.groupSpeed = 0;
        s.anchor.copy(spot(-560, (share(s) - 0.5) * 300));
        continue;
      }
      if (r === 'heavy') {
        s.guardOf = null;
        s.groupSpeed = slowHeavy;
        if (ai.focus && share(s) < DIFF.focus) s.forced = ai.focus;
        else if (s.forced && s.forced.kind !== 'ship') s.forced = null;
        s.stance = 'hunt';                 // своя цель — ближайшая, линия — на 0,7 её дальности
      } else if (r === 'carrier') {
        const close = foes.some(f => f.pos.distanceTo(s.pos) < 520);
        s.anchor.copy(spot(close ? -760 : -440, (ci++ - (carriers.length - 1) / 2) * 260, 30));
      } else if (r === 'ecm') {
        /* Купол глушит тех, кто ПОД НИМ, — то есть чужих. Стоя у своих
           тяжёлых, он не накрывал никого: противник держится на 0,7
           дальности, а купол в 420. Поэтому РЭБ — впереди линии, и купол
           ложится на строй игрока (замер зеркального боя: РЭБ над
           чужим строем решает исход — без него та же атака проигрывает) */
        s.anchor.copy(spot(330, (share(s) - 0.5) * 260));
      } else if (leaderless && (r === 'frigate' || (r === 'corvette' && !threats.length))) {
        s.guardOf = null;
        if (ai.focus && share(s) < DIFF.focus) s.forced = ai.focus;
        else if (s.forced && s.forced.kind !== 'ship') s.forced = null;
        s.stance = 'hunt';
      } else if (r === 'frigate') {
        /* Фрегаты — зенитный зонт: один у носителя, остальные у тяжёлых
           (по ним бьют бомбардировщики). Флот держится КУЧНО: замер
           зеркального боя — раскладка «завеса впереди, зонт сзади»
           проигрывала толпе по частям */
        const ward = fi === 0 && carriers.length ? carriers[0]
          : heavies.length ? heavies[fi % heavies.length] : carriers[0] || null;
        escort(s, ward, fi++);
        s.forced = null;
      } else {           // корвет: перехват звеньев, иначе — при тяжёлых
        const q = threats.length ? threats.reduce((b, t) => (t.pos.distanceTo(s.pos) < b.pos.distanceTo(s.pos) ? t : b)) : null;
        if (q && share(s) < 0.7) { s.guardOf = null; s.forced = q; s.anchor.copy(s.pos); }
        else {
          if (s.forced && s.forced.kind === 'squad') s.forced = null;
          if (heavies.length) escort(s, heavies[vi % heavies.length], vi + 3);
          else { s.guardOf = null; s.anchor.copy(spot(120, (vi - (corv.length - 1) / 2) * 110)); }
          vi++;
        }
      }
    }
  }

  /* ── ПОИСК СКРЫТЫХ (P5). Все, кого противник не видит, — скрыты
     (Рииз). Через SEARCH_AFTER секунд без единого видимого врага флот ИИ
     идёт туда, где скрытого видели последний раз (`seenPos`: выход из
     гипера, последний выстрел), развернувшись цепью поперёк хода — так
     полоса, которую он «прочёсывает», шире, — а пусто там — расходящимися
     точками вокруг неё. Вскрывает скрытого обычное правило: чужой корабль
     ближе detectRange, корвет — почти вдвое дальше. Увидел — обычный бой */
  const SEARCH_AFTER = 10;
  function aiSearch(mine) {
    const lost = state.ships.filter(s => !s.dead && !s.hyper && s.side !== ai.side && hidden(s));
    if (!lost.length || state.time - ai.seen < SEARCH_AFTER) return;
    const free = mine.filter(s => !s.station);
    if (!free.length) return;
    const C = new THREE.Vector3();
    for (const s of free) C.add(s.pos);
    C.divideScalar(free.length);
    /* Кого ищем, того и ищем дальше, пока не увидели кого-то свежее.
       Иначе двоих, которых видели в один миг (оба вышли из гипера и
       молчат), «ближний» менялся по ходу флота, поиск всякий раз
       начинался с нуля у точки выхода, и бой не кончался вовсе */
    let S = ai.search;
    let tgt = S ? lost.find(s => s.uid === S.uid) : null;
    if (tgt && lost.some(s => s.seenAt > tgt.seenAt + 0.5)) tgt = null;
    if (!tgt) {
      // Свежее всех видели — того и ищем; поровну — ближнего
      tgt = lost[0];
      for (const s of lost) {
        if (s.seenAt > tgt.seenAt + 0.5 || (Math.abs(s.seenAt - tgt.seenAt) <= 0.5 &&
            s.seenPos.distanceTo(C) < tgt.seenPos.distanceTo(C))) tgt = s;
      }
    }
    const fresh = t => ({ uid: t.uid, seenAt: t.seenAt, pos: t.seenPos.clone(), step: 0,
      t: state.time, cycle: S ? S.cycle : 0 });
    if (!S || S.uid !== tgt.uid || tgt.seenAt > S.seenAt + 0.5) {
      S = ai.search = fresh(tgt);
      if (tgt.side === state.playerSide && state.time - ai.toldSearch > 45) {
        ai.toldSearch = state.time;
        feed('Противник ищет наши скрытые корабли — там, где их видели последний раз', 'warn');
      }
    } else if (C.distanceTo(S.pos) < 260 || state.time - S.t > 45) {
      if (S.step >= 7) {
        /* Виток спирали пройден впустую. Следующий — повёрнутый и со
           сдвигом по радиусу: повтор тех же семи точек не найдёт того,
           кто стоит между ними. Скрыт не один — следующий виток у точки
           другого, иначе второго не искали бы никогда */
        const others = lost.filter(s => s.uid !== tgt.uid).sort((a, b) => a.uid - b.uid);
        const next = others.find(s => s.uid > tgt.uid) || others[0];
        if (next) tgt = next;
        S = ai.search = fresh(tgt);
        S.cycle++;
      } else {
        // На месте пусто — следующая точка по раскручивающейся спирали
        S.step++;
        S.t = state.time;
      }
      const a = S.step * 2.4 + tgt.uid + S.cycle * 1.3;
      const r = S.step ? 220 + 240 * S.step + (S.cycle % 2) * 120 : 0;
      S.pos.copy(tgt.seenPos).add(_v.set(Math.cos(a) * r, 0, Math.sin(a) * r));
      S.pos.x = clamp(S.pos.x, -FIELD * 0.9, FIELD * 0.9);
      S.pos.z = clamp(S.pos.z, -FIELD * 0.9, FIELD * 0.9);
    }
    const ax = _v2.subVectors(S.pos, C).setY(0);
    if (ax.lengthSq() < 1) ax.set(0, 0, -sides[ai.side].sign);
    ax.normalize();
    const lat = new THREE.Vector3(-ax.z, 0, ax.x);
    free.forEach((s, i) => {
      const off = (i - (free.length - 1) / 2) * 150;
      const p = S.pos.clone().addScaledVector(lat, off).addScaledVector(ax, s.cls === 'carrier' ? -320 : 0);
      p.y = S.pos.y + ((i % 3) - 1) * 40;
      s.amove = p;
      s.aiSearch = true;
      s.stance = 'hunt';
      s.forced = null; s.guardOf = null; s.groupSpeed = 0;
    });
  }
  function endSearch(mine) {
    ai.search = null;
    for (const s of mine) if (s.aiSearch) { s.aiSearch = false; s.amove = null; s.anchor.copy(s.pos); }
  }

  /* Противник уходит — это должно быть ВИДНО, и должно быть понятно, чем
     ответить: копящий гипер беззащитен, но «Охрана» за ним не пойдёт */
  function feedFoeRetreat() {
    feed('Противник отходит: копит гипер — добить: «Охота» (T) или ПКМ по кораблю', 'warn');
  }
  function fleeNote(e) {
    if (e.side === state.playerSide || state.retreat[e.side] || e.fleeTold) return;
    e.fleeTold = true;
    feed(`Противник: ${shortName(e)} копит гипер — добить, пока не ушёл`, 'warn');
  }

  /* ── БОЙ ОБЯЗАН КОНЧАТЬСЯ (P5). Сторона, которой нечем нанести урон —
     ни орудий, ни авиации в воздухе, ни ангара, из которого её поднять, —
     уводит уцелевших в гипер сама. Раньше у Рииза оставался один
     безоружный невидимый носитель или РЭБ: он не стреляет, его не видят,
     и итога не было никогда. Игроку — предупреждение в ленте и
     TOOTHLESS_GRACE секунд: можно вызвать резерв (B) — тогда отход
     не нужен. Уходит сторона обычным отходом: копит гипер под огнём */
  const TOOTHLESS_GRACE = 12;
  const teeth = { attacker: -1, defender: -1 };
  const craftArmed = c => !c.dead && !c.leaving &&
    (c.def.weaponKind !== 'missile' || c.ammo > 0 || c.reloads > 0 || c.reloading > 0);
  function canHurt(side) {
    for (const s of state.ships) {
      if (s.dead || s.side !== side || s.hyper) continue;
      if (s.guns.length) return true;
      if (s.hangar && (s.hangar.free > 0 || s.hangar.rebuild.length || s.hangar.launched.some(q => !q.dead))) return true;
    }
    for (const c of state.craft) if (c.side === side && craftArmed(c)) return true;
    if (state.reinforceAt[side]) return true;                       // резерв уже в пути
    if (side === state.playerSide && state.far.some(e => e.called && !e.done)) return true;
    return false;
  }
  function checkTeeth() {
    for (const side of ['attacker', 'defender']) {
      if (state.retreat[side] || !state.ships.some(s => !s.dead && !s.hyper && s.side === side)) { teeth[side] = -1; continue; }
      if (canHurt(side)) { teeth[side] = -1; continue; }
      const P = side === state.playerSide;
      const spare = (state.reserve[side] || []).reduce((a, x) => a + x.count, 0);
      if (teeth[side] < 0) {
        teeth[side] = state.time;
        // ИИ сперва зовёт резерв, если он есть, — тогда уходить незачем
        if (!P && spare && callReinforcements(side)) { teeth[side] = -1; continue; }
        if (P) {
          feed(`Флоту нечем бить: ни орудий, ни авиации — через ${TOOTHLESS_GRACE} с уцелевшие уйдут в гипер` +
            (spare ? ' · B — вызвать резерв' : ''), 'bad');
          sound.ui('warn');
        }
      }
      if (state.time - teeth[side] < (P ? TOOTHLESS_GRACE : 2)) continue;
      teeth[side] = -1;
      if (!orderRetreat(side)) continue;
      feed(P ? 'Нечем бить — уцелевшие уходят в гипер' : 'Противнику нечем бить — его флот уходит в гипер', P ? 'bad' : 'good');
    }
  }

  // ── HUD ──────────────────────────────────────────────────
  const hud = document.createElement('div');
  hud.className = 'hud hud-space';
  /* Подписи кораблей — ПЕРВЫМ слоем: панели, шапка и кнопки лежат
     поверх них. Стоя последними, подписи вражеского клубка закрывали
     кнопки скорости и паузы (C78). */
  hud.innerHTML = `
    <div class="markers" data-role="markers"></div>

    <div class="topbar">
      <button class="menu-btn" data-role="menu" title="Меню · Esc" aria-label="Меню">☰</button>
      <div class="strength">
        <div class="ss-row"><i class="dot" data-side="attacker"></i><span class="ss-who" data-role="atk-who"></span><b data-role="atk-name"></b>
          <span class="bar"><i data-role="atk-bar"></i></span><em data-role="atk-num"></em></div>
        <div class="ss-row"><i class="dot" data-side="defender"></i><span class="ss-who" data-role="def-who"></span><b data-role="def-name"></b>
          <span class="bar"><i data-role="def-bar"></i></span><em data-role="def-num"></em></div>
      </div>
      <div class="title" data-role="banner"></div>
      <div class="gunclock" data-role="gunclock" hidden>
        <b data-role="gun-name"></b><span data-role="gun-time"></span></div>
      <div class="speedctl">
        <button data-speed="0" aria-label="Пауза" title="Пауза · Пробел">❚❚</button>
        <button data-speed="1" class="on" title="Обычная скорость">1×</button>
        <button data-speed="2" title="Вдвое быстрее">2×</button>
        <button data-speed="4" title="Вчетверо быстрее">4×</button>
        <button data-role="reinforce" title="Вызвать второй эшелон из гипера · B"><span data-role="reinf-t"></span><kbd class="hk">B</kbd></button>
        <button data-role="retreat" class="danger danger-gap" title="Весь флот копит гипер и уходит — спросит подтверждение">Отход</button>
      </div>
    </div>

    <div class="sidebar">
      <button data-q="all" title="Весь флот · F2">Весь<br>флот</button>
      <button data-q="capital">Линкоры</button>
      <button data-q="carrier">Авиа-<br>носцы</button>
      <button data-q="escort">Эскорт</button>
      <button data-q="squads">Авиация</button>
      <button data-role="boxmode">Рамка</button>
    </div>

    <div class="roster" data-role="roster"></div>

    <div class="botpanel">
      <div class="sel-info" data-role="sel"></div>
      <div class="sel-actions" data-role="acts"></div>
    </div>
    <div class="act-tip" data-role="tip" hidden></div>

    <div class="hint" data-role="hint"></div>
    <div class="endcard" data-role="end" style="display:none"></div>
  `;
  hudRoot.appendChild(hud);
  const $ = r => hud.querySelector(`[data-role="${r}"]`);
  const markers = $('markers');
  /* Состояние ввода — здесь, ДО первой отрисовки панелей: ростер
     читает отряды уже при сборке (const не всплывает). */
  const groups = {};        // отряды 1…9: цифра → список кораблей и звеньев
  let hoverEnt = null;      // что под курсором (C74)
  let pending = null;       // 'amove' — нажата A, ждём щелчка (C50)

  // Короткие сообщения по центру: гипер, подкрепления, критические попадания
  const toastBox = document.createElement('div');
  toastBox.className = 'toasts';
  hud.appendChild(toastBox);

  /* ЛЕНТА СОБЫТИЙ — слева над ростером: кто погиб, чьё звено сбито, кто
     под огнём, кто ушёл в гипер. Три-четыре строки, гаснут сами. Без неё
     гибель корабля за кадром проходила молча, и игрок не понимал, почему
     проиграл. Полоски по центру (toast) — ответы на действия игрока,
     а лента — то, что случилось в бою само. Место — там, где первые
     секунды висит подсказка по управлению: первое событие её убирает */
  const feedBox = document.createElement('div');
  feedBox.className = 'feed';
  hud.appendChild(feedBox);
  const FEED_MAX = 4;
  /* Строка гаснет по ИГРОВОМУ времени (6 с), но не раньше чем через 3 с
     настоящих: на паузе лента стоит — по ней и разбираются, что
     случилось, — а на 4× строка не мелькает за полторы секунды. Раньше
     гасил setTimeout: на паузе событие уходило непрочитанным, а
     проверка ленты в стенде краснела на медленной машине */
  const FEED_LIFE = 6, FEED_WALL = 3;
  /* Строка, по которой щёлкают (подкрепление — выбрать прибывших), живёт
     дольше и из переполненной ленты уходит ПОСЛЕДНЕЙ: после имён с номерами
     строки о гибели больше не склеиваются, и в свалке четыре новые строки
     приходят за пять секунд — «Прибыло подкрепление… N — выбрать» жила
     1–4 секунды, а N объяснена только в ней */
  const FEED_ACT_LIFE = 12;
  let jamFeedAt = -99;     // «под помехами» — не чаще раза в 25 с
  let hintOut = false;
  state.feedLog = [];
  function feed(text, kind, onClick) {
    state.feedLog.push([+state.time.toFixed(1), text]);
    if (state.feedLog.length > 80) state.feedLog.shift();
    const h = $('hint');
    if (h && h.style.display !== 'none') h.style.display = 'none';
    /* Одинаковые строки склеиваются («×3»), как полоски: у звеньев одного
       рода имена повторяются, и четыре строки «Сбито звено
       бомбардировщиков «Шерман»» занимали всю ленту */
    let d = [...feedBox.children].find(x => x._text === text && !x._gone);
    if (d) d.textContent = `${text} ×${++d._n}`;
    else {
      d = document.createElement('div');
      d.className = 'feed-line ' + (kind || '');
      d.textContent = text;
      d._text = text; d._n = 1;
    }
    if (onClick) { d.classList.add('act'); d.onclick = onClick; d.title = 'Выбрать'; }
    d._at = state.time; d._wall = performance.now();
    d._life = onClick ? FEED_ACT_LIFE : FEED_LIFE;
    feedBox.appendChild(d);          // склеенная строка встаёт вниз, к свежим
    // Переполнение: уходит самая старая строка, по которой НЕ щёлкают
    while (feedBox.children.length > FEED_MAX) {
      const kids = [...feedBox.children];
      (kids.find(x => !x.classList.contains('act')) || kids[0]).remove();
    }
  }
  function fadeFeed() {
    const now = performance.now();
    for (const d of [...feedBox.children]) {
      if (d._gone) { if (now > d._gone) d.remove(); continue; }
      if (state.time - d._at >= (d._life || FEED_LIFE) && now - d._wall >= FEED_WALL * 1000) {
        d.classList.add('out');
        d._gone = now + 900;        // столько идёт угасание в CSS
      }
    }
  }
  sound.setListener(tcam.cam);
  /* Одинаковые сообщения склеиваются в одно с числом («×3»), а на экране
     их не больше четырёх: лавина плашек с размытием фона роняла кадры
     до слайд-шоу и закрывала бой (C8). */
  const TOAST_MAX = 4;
  /* Журнал полосок — для стенда, как feedLog: сама полоска живёт по
     настоящему времени (2,6 с), и под программным рендером на загруженной
     машине два кадра идут дольше — проверка «полоска есть» не заставала
     её, хотя она была */
  state.toastLog = state.toastLog || [];
  function toast(text) {
    const log = state.toastLog || (state.toastLog = []);
    log.push([+(state.time || 0).toFixed(1), text]);
    if (log.length > 80) log.shift();
    for (const d of toastBox.children) {
      if (d._text !== text || d.classList.contains('out')) continue;
      d._n++;
      d.textContent = `${text} ×${d._n}`;
      clearTimeout(d._t1); clearTimeout(d._t2);
      d._t1 = setTimeout(() => d.classList.add('out'), 2600);
      d._t2 = setTimeout(() => d.remove(), 3400);
      return;
    }
    const d = document.createElement('div');
    d.className = 'toast';
    d.textContent = text;
    d._text = text; d._n = 1;
    toastBox.appendChild(d);
    d._t1 = setTimeout(() => d.classList.add('out'), 2600);
    d._t2 = setTimeout(() => d.remove(), 3400);
    while (toastBox.children.length > TOAST_MAX) {
      const old = toastBox.firstChild;
      clearTimeout(old._t1); clearTimeout(old._t2);
      old.remove();
    }
  }

  /* Панель дальнего гипера: список своих систем в пределах трёх
     прыжков. Показываем сразу время подлёта — решение «звать или
     нет» упирается именно в него. */
  /* Миникарта боя на орбите. Поле теперь больше двух с половиной
     тысяч единиц в сторону — без схемы половина флота оказывается
     за экраном и о ней просто забываешь. Скрытые корабли Рииза
     на неё не попадают: маскировка должна работать и здесь. */
  /* ЛКМ и протяжка — камера туда, ПКМ — приказ в точку (C73): так
     флот отправляют на другой край поля, не листая к нему камеру. */
  const minimap = createMinimap(hud, FIELD, {
    onGo(x, z) {
      tcam.focus(new THREE.Vector3(x, tcam.target.y, z));
      tcam.clampTarget();
      tcam.apply(0, true);
    },
    onOrder(x, z) {
      const w = new THREE.Vector3(x, 0, z);
      if (pending === 'amove') { pending = null; amoveSelected(w); return; }
      if (issueOrder(null, w)) toast('Приказ по миникарте: флот идёт в точку');
    },
  });

  function drawMinimap(dt) {
    const dots = [];
    for (const e of state.ships) {
      if (e.dead) continue;
      if (e.side !== state.playerSide && hidden(e)) continue;
      const mine = e.side === state.playerSide;
      dots.push({ x: e.pos.x, z: e.pos.z,
        r: e.cls === 'capital' || e.cls === 'carrier' ? 5 : 3,
        color: mine ? MINE_CSS : FOE_CSS });
    }
    for (const sq of state.squads) {
      if (sq.dead) continue;
      // Скрытое звено противника не выдаём и здесь (C18)
      if (sq.side !== state.playerSide && unseen(sq)) continue;
      dots.push({ x: sq.pos.x, z: sq.pos.z, r: 2,
        color: sq.side === state.playerSide ? MINE_DIM : FOE_DIM });
    }
    // Рамка обзора — трапеция углов экрана, а не квадрат: камера
    // наклонена и повёрнута, и квадрат после облёта врал (C73)
    minimap.draw(dt, dots, () => ({ pts: controls.viewQuad(0, FIELD * 3) }));
  }

  const farBox = document.createElement('div');
  farBox.className = 'farbar';
  hud.appendChild(farBox);

  function refreshFar() {
    if (!state.far.length) { farBox.hidden = true; return; }
    farBox.innerHTML = '<div class="farhead">Дальний гипер</div>';
    for (const e of state.far) {
      const b = document.createElement('button');
      const left = e.called ? Math.max(0, Math.ceil(e.called - state.time)) : 0;
      b.className = 'far-btn' + (e.done ? ' done' : e.called ? ' flying' : '');
      b.innerHTML = `<b>${e.name}</b><small>${
        e.done ? 'на месте'
        : e.called ? `в пути · ${left} с`
        : `${fleetCount(e.ships)} кор. · ${e.hops} пр. · ${Math.round(e.delay)} с`}</small>`;
      b.disabled = !!e.called;
      b.onclick = () => callFar(e);
      farBox.appendChild(b);
    }
  }
  const fleetCount = list => (list || []).reduce((a, x) => a + x.count, 0);
  refreshFar();

  /* Полоса силы — цветом СТОРОНЫ (свои / противник), точка рядом —
     цветом клана: в зеркальном бою кланы одинаковы, а стороны нет (C43) */
  hud.querySelectorAll('.dot').forEach(d => { d.style.background = sides[d.dataset.side].faction.colorCss; });
  for (const sd of ['attacker', 'defender']) {
    $(sd === 'attacker' ? 'atk-bar' : 'def-bar').style.background = sd === state.playerSide ? MINE_CSS : FOE_CSS;
  }
  $('atk-name').textContent = sides.attacker.faction.tag;
  $('def-name').textContent = sides.defender.faction.tag;
  /* «Мы» и «Противник» словами (P5): в зеркальном бою «ТРД / ТРД»
     какая строка наша, говорил только цвет полоски */
  for (const sd of ['attacker', 'defender']) {
    const w = $(sd === 'attacker' ? 'atk-who' : 'def-who');
    w.textContent = sd === state.playerSide ? 'Мы' : 'Противник';
    w.classList.add(sd === state.playerSide ? 'mine' : 'foe');
  }
  $('banner').textContent = config.title || 'Бой на орбите';
  if (state.gun) {
    $('gunclock').hidden = false;
    $('gun-name').textContent = state.gun.def.short;
    $('gunclock').title = state.gun.def.desc;
  }
  $('hint').innerHTML = IS_TOUCH
    ? 'Касание по своему кораблю — выбрать · по врагу — атаковать · по пустоте — идти · тянуть — двигать карту · щипок — приближение · долгое нажатие — рамка'
    : 'ПКМ — приказ · средняя кнопка — карта · A — атака с ходу · S — стоп · H, Y, T — держать, охрана, охота · Esc — меню';

  hud.querySelectorAll('[data-speed]').forEach(b => {
    b.onclick = () => {
      const v = +b.dataset.speed;
      state.paused = v === 0;
      if (v) state.speed = v;
      hud.querySelectorAll('[data-speed]').forEach(x => x.classList.toggle('on', +x.dataset.speed === v));
    };
  });
  /* Дрифт включается на выделенные корабли — кнопкой в панели команд
     и клавишей D. Подсветка кнопки считается ИЗ ВЫДЕЛЕНИЯ (C136) при
     каждом обновлении панели: раньше кнопка жила в шапке и класс «on»
     ставился только нажатием — «Дрифт» горел при «Весь флот», хотя
     дрифтовал один корвет, давно ушедший в гипер. */
  function toggleDrift() {
    const mine = state.selection.filter(e => !e.dead && e.kind === 'ship' && e.side === state.playerSide && !e.station);
    if (!mine.length) { toast('Сначала выбери корабли'); return; }
    const on = !mine.every(e => e.drift);
    for (const e of mine) {
      e.drift = on;
      if (on) fx.ring(e.pos, e.radius * 1.5, e.radius * 5, 0xffc27a, 0.5);
    }
    sound.ui('order');
    toast(on ? 'Гасители инерции отключены: корабль скользит по вектору'
             : 'Гасители инерции включены');
    refreshSel();
  }

  /* «Отход» — гипер ВСЕГО флота с накачкой, а не мгновенный выход из
     боя (C17). Второе нажатие отменяет отход, пока носитель не ушёл.
     Начало отхода — через подтверждение (C34): кнопка стоит в одной
     полосе с кнопками скорости, и промах мимо «4×» проигрывал бой.
     Защитнику сказано прямо, что орбита останется за противником. */
  /* Вопрос ставит бой на паузу, пока висит: окно гасит все клавиши,
     Пробел в том числе, и без паузы флот гиб бы, пока игрок читает
     три предложения. После ответа скорость та же, что была. */
  function ask(opts, fn) {
    if (!ctx.confirm) { fn(); return; }
    const was = state.paused;
    state.paused = true;
    ctx.confirm({ ...opts, onClose: () => { state.paused = was; } }, fn);
  }
  const retreatBtn = $('retreat');
  function askRetreat() {
    if (ended) return;
    const P = state.playerSide;
    if (state.retreat[P]) { toast('Флот уже отходит'); return; }
    ask({
      title: P === 'defender' ? 'Отход — сдать орбиту?' : 'Отход из боя?',
      text: 'Весь флот копит гипер и всё это время беззащитен. Домой вернутся только те, кто успеет уйти' +
        (P === 'defender' ? '; орбита останется за противником.' : '; бой будет проигран.') +
        ' Пока носитель не ушёл, отход можно отменить той же кнопкой.',
      yes: 'Отходить', no: 'Остаться в бою',
    }, () => {
      if (ended || state.retreat[P]) return;
      const n = orderRetreat(P);
      const t = Math.max(0, ...state.ships.filter(s => !s.dead && s.side === P && s.hyper).map(s => s.hyper.left));
      toast(n ? `Отход: флот копит гипер, ${Math.ceil(t)} с — всё это время беззащитен`
              : 'Отход: уходить некому');
      refreshRetreat();
      refreshSel();
    });
  }
  retreatBtn.onclick = () => {
    if (ended) return;
    const P = state.playerSide;
    if (!state.retreat[P]) { askRetreat(); return; }
    if (state.conceded === P) { toast('Носитель ушёл — отход уже не отменить'); return; }
    cancelRetreat(P);
    toast('Отход отменён — флот остаётся в бою');
    refreshRetreat();
    refreshSel();
  };
  function refreshRetreat() {
    const on = !!state.retreat[state.playerSide];
    const txt = on ? (state.conceded === state.playerSide ? 'Отходим…' : 'Отменить отход') : 'Отход';
    if (retreatBtn.textContent !== txt) retreatBtn.textContent = txt;
    retreatBtn.classList.toggle('on', on);
  }

  const reinfBtn = $('reinforce');
  const reinfTxt = $('reinf-t');
  const reinfKbd = reinfBtn.querySelector('kbd');
  const myReserve = () => state.reserve[state.playerSide];
  /* Прибывшие и не выбранные — та же кнопка, только с N (P5): строка
     в ленте уходит за секунды, а кнопка в шапке стоит, пока прибывших
     не выбрали (N, кнопкой или строкой), но не дольше минуты боя */
  const ARRIVED_HINT = 60;
  function arrivedLeft() {
    if (!state.arrived || state.arrivedSeen || state.time - state.arrivedAt > ARRIVED_HINT) return 0;
    return state.arrived.filter(e => !e.dead && !e.fled).length;
  }
  function refreshReinforce() {
    const n = (myReserve() || []).reduce((a, x) => a + x.count, 0);
    const pending = state.reinforceAt[state.playerSide];
    let txt, off = true, arr = 0;
    // флот отходит: резерв в бой уже не идёт и вернётся домой целым
    if (state.retreat[state.playerSide]) txt = n ? `Резерв дома (${n})` : 'Резерва нет';
    else if (pending) txt = `Гипер ${Math.max(0, Math.ceil(pending - state.time))} с`;
    else if (n) { txt = `Подкрепление (${n})`; off = false; }
    else if ((arr = arrivedLeft())) { txt = `Прибывшие (${arr})`; off = false; }
    else txt = 'Резерва нет';
    // кнопка обновляется каждый кадр — трогаем DOM, только если что-то поменялось
    if (reinfTxt.textContent !== txt) reinfTxt.textContent = txt;
    if (reinfBtn.disabled !== off) reinfBtn.disabled = off;
    const mode = arr ? 'arr' : 'res';
    if (reinfBtn.dataset.mode !== mode) {
      reinfBtn.dataset.mode = mode;
      if (reinfKbd) reinfKbd.textContent = arr ? 'N' : 'B';
      reinfBtn.title = arr ? 'Прибывшее подкрепление — ни в одном отряде. Выбрать · N'
                           : 'Вызвать второй эшелон из гипера · B';
      reinfBtn.classList.toggle('nudge', !!arr);
    }
  }
  reinfBtn.onclick = () => {
    if (reinfBtn.disabled) return;
    if (reinfBtn.dataset.mode === 'arr') { selectArrived(); refreshReinforce(); return; }
    if (callReinforcements(state.playerSide)) {
      toast('Резерв вызван — выход из гипера через полминуты');
      reinfBtn.classList.remove('nudge');
      refreshReinforce();
    }
  };
  /* Резерв сам не придёт (C15: второй эшелон — до 40% флота), а кнопка
     в шапке среди скоростей незаметна: замер «Сражения» — без неё бой
     проигран при любых приказах (18 из 18). Поэтому при первом залпе
     главного калибра, если резерв ещё в гипере, — строка в ленте
     и кнопка начинает светиться. Один раз за бой */
  let reserveHinted = false;
  function hintReserve() {
    if (reserveHinted || !state.stats.firstGun) return;
    reserveHinted = true;
    const n = (myReserve() || []).reduce((a, x) => a + x.count, 0);
    if (!n || state.reinforceAt[state.playerSide] || state.retreat[state.playerSide]) return;
    feed(`Резерв (${n}) ещё в гипере: «Подкрепление» или B — выйдет через полминуты`, 'warn');
    reinfBtn.classList.add('nudge');
  }
  refreshReinforce();

  $('menu').onclick = () => openPause();

  hud.querySelectorAll('[data-q]').forEach(b => {
    b.onclick = () => {
      const q = b.dataset.q;
      if (q === 'squads') {
        state.selection = state.squads.filter(s => !s.dead && s.side === state.playerSide);
      } else {
        state.selection = state.ships.filter(s => !s.dead && s.side === state.playerSide && !s.station &&
          (q === 'all' || s.cls === q));
      }
      if (state.selection.length) focusOn(state.selection);
      refreshSel();
    };
  });
  const boxBtn = $('boxmode');
  boxBtn.onclick = () => controls.setBoxMode(!controls.boxMode);

  function focusOn(list) {
    const c = new THREE.Vector3();
    let n = 0;
    for (const e of list) { c.add(e.pos); n++; }
    if (n) tcam.focus(c.divideScalar(n));
  }

  /* ── ПОДПИСИ НАД КОРАБЛЯМИ (C78).
     Имя и полоска были у КАЖДОГО корабля, и над вражеским флотом
     стояла сплошная каша из двадцати «Исса», закрывавшая и сами
     корабли, и кнопки шапки. Теперь имя — только у выделенных, под
     курсором и у тех, кто близко к камере (корпус на экране крупнее
     NEAR_PX); остальным — значок класса цвета стороны, а полоска
     прочности — если корабль ранен. Имя, легшее на уже стоящее,
     становится значком (разводим по важности: под курсором, выделен,
     крупнее на экране). Выше шапки подписей нет вовсе. */
  const markerPool = [];
  /* Где на экране стоят подписи (C29). Сами метки прозрачны для
     указателя — иначе они заслоняли бы поле, — поэтому попадание по
     подписи считаем здесь: игрок целится в название врага, а раньше
     такой ПКМ уходил мимо модели и отправлял флот в упор к противнику. */
  const labelHits = [];
  const NEAR_PX = 26;          // полудлина корпуса на экране, с которой корабль «близко»
  const iconOf = e => (e.station ? 'station' : e.def.id === 'corvette' ? 'corvette'
    : e.def.id === 'frigate' ? 'frigate' : e.def.id === 'ecm' ? 'ecm'
    : e.cls === 'carrier' ? 'carrier' : e.def.id === 'cruiser' ? 'cruiser' : 'capital');
  /* Габарит значка на экране — ширина и высота из style.css
     (`.mk-ico[data-k]`); ромб флагмана — квадрат 10 × 0,82, повёрнутый,
     по диагонали 11,6. От них считаем, где значок стоит, чтобы он не лёг
     на имя соседа. Замер разметки: буквы имени — от 17 до 5 точек над
     низом метки, полоска — от 3 до 0, значок — на 3 выше полоски */
  const ICON_BOX = { capital: [11.6, 11.6], cruiser: [10, 9], carrier: [13, 6], ecm: [9, 9],
    frigate: [7, 7], corvette: [5, 5], station: [11, 11], squad: [9, 6] };
  const NAME_UP = 18;          // имя с полоской: от низа метки до верха букв
  /* Ширина имени — по самому тексту тем же шрифтом (канва, с кэшем):
     мерить разметку на каждый кадр значило бы пересчитывать раскладку
     страницы десятки раз в секунду */
  const nameWidth = new Map();
  let measureCtx = null, nameFont = '';
  function textWidth(t) {
    let w = nameWidth.get(t);
    if (w === undefined) {
      if (!measureCtx) {
        measureCtx = document.createElement('canvas').getContext('2d');
        nameFont = getComputedStyle(markerEl(0)._nm).font || '10px sans-serif';
      }
      measureCtx.font = nameFont;
      w = measureCtx.measureText(t).width;
      if (nameWidth.size > 500) nameWidth.clear();
      nameWidth.set(t, w);
    }
    return w;
  }
  let topEdge = 60;            // низ шапки: выше подписи не рисуем
  const measureTop = () => {
    const tb = hud.querySelector('.topbar');
    if (tb) topEdge = tb.getBoundingClientRect().bottom - viewport.canvas.getBoundingClientRect().top;
  };
  addEventListener('resize', measureTop);
  const markerItems = [];
  function markerEl(i) {
    let d = markerPool[i];
    if (!d) {
      d = document.createElement('div');
      d.className = 'marker';
      d.innerHTML = '<i class="mk-ico"></i><span class="mk-name"></span><span class="mk-bar"><i></i></span>';
      d._ico = d.firstChild; d._nm = d.children[1]; d._bar = d.lastChild; d._fill = d.lastChild.firstChild;
      markers.appendChild(d);
      markerPool[i] = d;
    }
    return d;
  }
  const setCls = (d, c) => { if (d._cls !== c) { d._cls = c; d.className = c; } };
  const setTxt = (el, t) => { if (el._t !== t) { el._t = t; el.textContent = t; } };
  function updateMarkers() {
    const w = viewport.w, h = viewport.h, cam = tcam.cam;
    const fpx = (h / 2) / Math.tan(cam.fov * Math.PI / 360);
    labelHits.length = 0;
    markerItems.length = 0;
    for (const s of state.ships) {
      if (s.dead) continue;
      const cloak = hidden(s);
      // Скрытый противник не рисуется вовсе — ни модель, ни метка
      s.obj.visible = !(cloak && s.side !== state.playerSide);
      if (cloak && s.side !== state.playerSide) continue;
      const p = screenOf(s.pos, cam, w, h);
      if (p.z > 1 || p.x < -90 || p.x > w + 90 || p.y < -50 || p.y > h + 50) continue;
      const rpx = s.len * 0.5 * fpx / Math.max(1, cam.position.distanceTo(s.pos));
      const sel = state.selection.includes(s), hov = hoverEnt === s;
      markerItems.push({ e: s, p, rpx, sel, hov, cloak, pri: (hov ? 4e6 : 0) + (sel ? 2e6 : 0) + rpx });
    }
    /* Скрытая машина противника не рисуется, как и скрытый корабль.
       Выбрать её нельзя (C18), и видимая, но не нажимаемая машина
       хуже обеих: игрок жмёт по ней ПКМ, а флот уходит в точку. */
    for (const c of state.craft) {
      if (!c.dead) c.obj.visible = !(c.side !== state.playerSide && craftHidden(c));
    }
    /* Звену — одна метка у центра масс: истребитель с пиксель размером,
       и без метки игрок не знает, что авиация вообще в бою. */
    for (const sq of state.squads) {
      if (sq.dead || !sq.craft.length) continue;
      const live = sq.craft.filter(c => !c.dead);
      if (!live.length) continue;
      if (sq.side !== state.playerSide && unseen(sq)) continue;
      _v.set(0, 0, 0);
      for (const c of live) _v.add(c.pos);
      _v.divideScalar(live.length);
      const p = screenOf(_v, cam, w, h);
      if (p.z > 1 || p.x < -90 || p.x > w + 90 || p.y < -50 || p.y > h + 50) continue;
      const sel = state.selection.includes(sq), hov = hoverEnt === sq;
      markerItems.push({ e: sq, p, rpx: 6, sel, hov, live, pri: (hov ? 4e6 : 0) + (sel ? 2e6 : 0) + 6 });
    }
    markerItems.sort((a, b) => b.pri - a.pri);
    const selN = state.selection.length;
    /* Ход первый — ИМЕНА. Значки раньше ставились в том же проходе по
       важности, и значок выделенного или крупного корабля ложился на
       уже стоящее имя соседа: «Нем●≡зида», «Севе● Клоз» (замер на
       «Генеральном» Плэктора — шесть значков на одном имени). Поэтому
       сперва решаем, у кого имя, и только потом ставим значки в обход */
    const names = [];
    for (const it of markerItems) {
      const e = it.e, p = it.p, squad = e.kind === 'squad';
      // Подпись — над корпусом, а не на нём: отступ растёт с размером на экране
      it.ay = p.y - Math.max(14, it.rpx * 0.55 + 6);
      it.hp = squad ? it.live.reduce((a, c) => a + c.hp / c.maxHp, 0) / it.live.length : e.hp / e.maxHp;
      if (squad) {
        const r = STRIKE_ROLES[e.role];
        it.text = it.sel || it.hov ? `${r.label} ×${it.live.length}` : `${r.short} ${it.live.length}`;
        it.k = 'squad';
      } else {
        it.text = shortName(e);
        it.k = iconOf(e);
      }
      let name = it.sel || it.hov || it.rpx >= NEAR_PX || squad;
      // Под шапкой имён нет (C78): не влезло — пусть будет значок
      if (name && it.ay - NAME_UP < topEdge) name = false;
      // «⇢ гипер» дописывается к имени — оно шире
      const hw = name ? Math.max(20, textWidth(it.text + (e.hyper ? ' ⇢ гипер' : '')) / 2) + 2 : 0;
      /* Разводим всех, кроме того, что под курсором, и единственного
         выделенного: при «Весь флот» имена выделенных ложились друг на
         друга так же, как раньше чужие */
      if (name && !it.hov && !(it.sel && selN === 1)) {
        for (const q of names) {
          if (Math.abs(q.x - p.x) < Math.max(86, q.hw + hw + 4) && Math.abs(q.y - it.ay) < 15) { name = false; break; }
        }
      }
      it.name = name;
      if (name) names.push({ x: p.x, y: it.ay, hw });
    }
    /* Ход второй — ЗНАЧКИ, в обход имён. Значок, легший на имя, едет
       к своему кораблю: под имя или над ним, что ближе к его месту, и
       не ниже самого корабля. Некуда — значка нет: корабль виден моделью
       и ловится щелчком по ней. Выше шапки значков тоже нет */
    for (const it of markerItems) {
      if (it.name) continue;
      const b = ICON_BOX[it.k], jump = !!it.e.hyper;
      it.bar = it.sel || it.hp < 0.995 || jump;
      // ширина: значок, полоска 22 под ним, «⇢» справа у уходящего в гипер
      const hw = Math.max(b[0] / 2, it.bar ? 11 : 0, jump ? 19 : 0);
      const up = b[1] + 4 + (it.bar ? 3 : 0);
      const near = names.filter(q => Math.abs(q.x - it.p.x) < q.hw + hw + 1);
      const free = y => y - up >= topEdge && !near.some(q => y > q.y - NAME_UP - 1 && y - up < q.y + 1);
      let ay = it.ay;
      if (!free(ay)) {
        ay = NaN;
        const cands = [];
        for (const q of near) cands.push(q.y + up + 2, q.y - NAME_UP - 2);
        cands.sort((a, c) => Math.abs(a - it.ay) - Math.abs(c - it.ay));
        for (const y of cands) if (y <= it.p.y + up / 2 + 2 && y >= it.ay - 30 && free(y)) { ay = y; break; }
      }
      it.ay = ay;
      it.up = up;
    }
    let i = 0;
    for (const it of markerItems) {
      if (Number.isNaN(it.ay)) continue;
      const e = it.e, p = it.p, ay = it.ay, name = it.name, mine = e.side === state.playerSide;
      const bar = name || it.bar;
      const d = markerEl(i++);
      d.style.display = 'flex';
      setCls(d, 'marker ' + (mine ? 'mine' : 'foe') + (name ? '' : ' mini') + (bar ? '' : ' nobar') +
        (it.sel ? ' sel' : '') + (it.hov ? ' hover' : '') + (it.cloak ? ' cloak' : '') + (e.hyper ? ' jump' : ''));
      d.style.transform = `translate(${(p.x - 48) | 0}px,${(ay - 34) | 0}px)`;
      setTxt(d._nm, it.text);
      if (d._ico.dataset.k !== it.k) d._ico.dataset.k = it.k;
      if (bar) d._fill.style.width = (clamp(it.hp, 0, 1) * 100) + '%';
      // Попадание по подписи: от неё до самого корабля — это его место
      labelHits.push(name
        ? { ent: e, x: p.x, hw: 48, y0: ay - 24, y1: Math.max(ay + 4, p.y), my: ay - 10 }
        : { ent: e, x: p.x, hw: 13, y0: ay - it.up - 4, y1: Math.max(ay + 4, p.y), my: ay - 6 });
    }
    for (; i < markerPool.length; i++) if (markerPool[i].style.display !== 'none') markerPool[i].style.display = 'none';
  }

  /* ── ПРИКАЗЫ ГЛАЗАМИ.

     Отданный приказ должен быть виден на поле, а не только в панели:
     кольцо в точке назначения и линия от корабля к ней. По ним сразу
     понятно, кто куда идёт и не промахнулся ли ты мимо точки. Линия
     атаки — красная и тянется к цели. */
  const orderMarks = [];
  const orderLines = [];
  function updateOrders() {
    let m = 0, l = 0;
    const line = (from, to, color) => {
      if (!orderLines[l]) {
        const g = new THREE.BufferGeometry();
        g.setAttribute('position', new THREE.BufferAttribute(new Float32Array(6), 3));
        const ln = new THREE.Line(g, new THREE.LineBasicMaterial({
          color, transparent: true, opacity: 0.5, toneMapped: false, depthWrite: false,
        }));
        ln.frustumCulled = false;
        scene.add(ln);
        orderLines[l] = ln;
      }
      const ln = orderLines[l++];
      ln.visible = true;
      ln.material.color.set(color);
      const a = ln.geometry.attributes.position.array;
      a[0] = from.x; a[1] = from.y; a[2] = from.z;
      a[3] = to.x; a[4] = to.y; a[5] = to.z;
      ln.geometry.attributes.position.needsUpdate = true;
    };
    for (const e of state.selection) {
      if (e.dead) continue;
      // Атака с ходу — оранжевым: точка та же, но по пути будет бой
      const dest = e.moveTo || e.amove;
      if (dest) {
        if (!orderMarks[m]) {
          const r = ringMesh(1, 0x8fffc8, 0.8, 0.08);
          r.renderOrder = 5;
          scene.add(r);
          orderMarks[m] = r;
        }
        const col = e.moveTo ? 0x8fffc8 : 0xffa860;
        const r = orderMarks[m++];
        r.visible = true;
        r.material.color.set(col);
        r.position.copy(dest);
        r.scale.setScalar(26 + Math.sin(state.time * 3) * 4);
        line(e.pos, dest, col);
      }
      const t = e.forced && !e.forced.dead ? e.forced : null;
      if (t) line(e.pos, t.pos, 0xff7a5a);
    }
    for (; m < orderMarks.length; m++) orderMarks[m].visible = false;
    for (; l < orderLines.length; l++) orderLines[l].visible = false;
  }

  // «Линейный крейсер «Ховард»» → «Ховард»: в узкой ячейке помещается
  // только собственное имя корабля

  /* ── РОСТЕР ФЛОТА.

     Полоска значков со всеми своими кораблями и звеньями — как
     в Empire at War. Она отвечает на вопрос, на который поле боя
     не отвечает никогда: «что у меня вообще есть и где оно».

     Корабли — ПО КЛАССУ, с числом («Корвет ×8», C77): по ячейке на
     корабль у Плэктора выходило 34 ячейки, около 2700 точек при
     ~1240 видимых, а полоса прокрутки была спрятана — половина флота
     была в ростере недоступна мышью. Щелчок по группе выбирает всех
     этого класса, следующий — по одному (камера к каждому), после
     последнего — снова всех. Shift — добавить к выделению. Полоса
     прочности — средняя, цвет — по самому раненому. Колесо листает
     ростер вбок, если он всё же длиннее экрана. */
  const rosterBox = $('roster');
  const rosterCells = new Map();
  const ROSTER_ORDER = { capital: 0, sinho: 1, cruiser: 2, carrier: 3, ecm: 4, frigate: 5, corvette: 6,
    interceptor: 10, fighter: 11, bomber: 12 };
  const classWord = e => (e.kind === 'squad' ? STRIKE_ROLES[e.role].label
    : (e.def.role || e.def.name).split(' · ')[0]);
  rosterBox.addEventListener('wheel', ev => {
    if (rosterBox.scrollWidth <= rosterBox.clientWidth + 1) return;
    ev.preventDefault();
    rosterBox.scrollLeft += ev.deltaY + ev.deltaX;
  }, { passive: false });
  function rosterGroups() {
    const P = state.playerSide;
    const by = new Map();
    const add = (k, e) => { if (!by.has(k)) by.set(k, []); by.get(k).push(e); };
    for (const s of state.ships) if (!s.dead && s.side === P && !s.station) add('s:' + s.def.id, s);
    for (const q of state.squads) if (!q.dead && q.side === P && q.craft.some(c => !c.dead)) add('q:' + q.role, q);
    return [...by.entries()].sort((a, b) => {
      const ka = ROSTER_ORDER[a[0].slice(2)] ?? 9, kb = ROSTER_ORDER[b[0].slice(2)] ?? 9;
      return ka - kb;
    });
  }
  function rosterClick(cell, ev) {
    const list = cell._list.filter(e => !e.dead);
    if (!list.length) return;
    const sel = state.selection.filter(e => !e.dead);
    const posOf = e => (e.kind === 'squad' ? (e.craft.find(c => !c.dead) || {}).pos : e.pos);
    if (ev && ev.shiftKey) {
      state.selection = [...new Set([...sel, ...list])];
      refreshSel();
      return;
    }
    const all = sel.length === list.length && list.every(e => sel.includes(e));
    const one = sel.length === 1 && list.includes(sel[0]);
    let pick;
    if (list.length > 1 && all) pick = [list[0]];
    else if (one && list.length > 1) {
      const i = list.indexOf(sel[0]);
      pick = i + 1 < list.length ? [list[i + 1]] : list.slice();
    } else pick = list.slice();
    state.selection = pick;
    if (pick.length === 1) {
      const p = posOf(pick[0]);
      if (p) tcam.focus(p.clone(), Math.min(tcam.dist, 420));
    } else focusOn(pick.map(e => ({ pos: posOf(e) || e.pos })));
    refreshSel();
  }
  function refreshRoster() {
    const seen = new Set();
    let at = 0;
    for (const [key, list] of rosterGroups()) {
      seen.add(key);
      let cell = rosterCells.get(key);
      if (!cell) {
        cell = document.createElement('button');
        cell.className = 'rcell';
        cell.innerHTML = '<span class="rtop"><b></b><em class="rgrp"></em></span><span class="rbar"><i></i></span>';
        cell._name = cell.querySelector('b');
        cell._bar = cell.querySelector('.rbar i');
        cell._grp = cell.querySelector('.rgrp');
        cell.onclick = ev => rosterClick(cell, ev);
        rosterCells.set(key, cell);
      }
      // Порядок ячеек держим по классу: новый класс встаёт на своё место
      if (rosterBox.children[at] !== cell) rosterBox.insertBefore(cell, rosterBox.children[at] || null);
      at++;
      cell._list = list;
      const isSquad = key[0] === 'q';
      const hps = list.map(e => (isSquad
        ? e.craft.filter(c => !c.dead).reduce((a, c) => a + c.hp / c.maxHp, 0) / Math.max(1, e.craft.filter(c => !c.dead).length)
        : e.hp / e.maxHp));
      const avg = hps.reduce((a, x) => a + x, 0) / hps.length;
      const worst = Math.min(...hps);
      const word = classWord(list[0]);
      const txt = list.length > 1 ? `${word} ×${list.length}` : word;
      if (cell._name.textContent !== txt) cell._name.textContent = txt;
      const tip = (list.length > 1 ? `${list.length} шт. · щелчок — все, ещё щелчок — по одному` : (list[0].name || list[0].def.name)) +
        ' · Shift — добавить к выбранным';
      const bar = cell._bar;
      bar.style.width = (clamp(avg, 0, 1) * 100) + '%';
      bar.style.background = worst > 0.55 ? MINE_CSS : worst > 0.25 ? '#e0a94e' : '#e05555';
      const sel = state.selection;
      cell.classList.toggle('on', list.some(e => sel.includes(e)));
      cell.classList.toggle('air', isSquad);
      /* В каких отрядах корабли класса — цифрами справа от имени. Отряд
         с ЧАСТЬЮ класса — с числом в скобках, «3(1)» (P5): «Носитель ×2 3»
         обещало, что тройка возьмёт оба носителя, а брала один */
      const parts = [], notes = [];
      for (const n of Object.keys(groups)) {
        const k = groups[n].filter(e => !e.dead && list.includes(e)).length;
        if (!k) continue;
        parts.push(k === list.length ? n : `${n}(${k})`);
        if (k < list.length) notes.push(`отряд ${n}: ${k} из ${list.length}`);
      }
      const g = parts.join(parts.some(x => x.length > 1) ? ' ' : '');
      const em = cell._grp;
      if (em.textContent !== g) em.textContent = g;
      const tip2 = notes.length ? tip + ' · ' + notes.join(', ') : tip;
      if (cell.title !== tip2) cell.title = tip2;
    }
    for (const [key, cell] of rosterCells) {
      if (!seen.has(key)) { cell.remove(); rosterCells.delete(key); }
    }
  }

  refreshRoster();   // ПОСЛЕ объявления rosterCells: const не всплывает

  let selTick = 0;

  // ── выделение: кольца и вектор скорости ─────────────────
  const selRings = [];
  const velLines = [];
  function updateSelVisuals() {
    let i = 0, j = 0;
    for (const e of state.selection) {
      if (e.dead) continue;
      const targets = e.kind === 'squad' ? e.craft : [e];
      for (const u of targets) {
        if (!selRings[i]) {
          const r = circleLine(MINE_HEX, 0.9);
          scene.add(r);
          selRings[i] = r;
        }
        const r = selRings[i++];
        r.visible = true;
        r.position.copy(u.pos);
        /* Кольцо — по длине корпуса, чуть шире его (C111): «радиус
           × 3,1» у приезжих моделей выходил кольцом в полтора-два
           корабля. Цвет — по стороне: выделенный враг (его можно
           выбрать, чтобы рассмотреть) обводится красным (C43). */
        r.scale.setScalar(e.kind === 'squad' ? 9 : ringR(u));
        r.material.color.set(e.side === state.playerSide ? MINE_HEX : FOE_HEX);
      }
      // вектор скорости — чтобы инерция была видна глазами
      if (e.kind === 'ship' && e.vel.lengthSq() > 1) {
        if (!velLines[j]) {
          const g = new THREE.BufferGeometry();
          g.setAttribute('position', new THREE.BufferAttribute(new Float32Array(6), 3));
          const l = new THREE.Line(g, new THREE.LineBasicMaterial({
            color: 0x8fffc8, transparent: true, opacity: 0.55, toneMapped: false, depthWrite: false,
          }));
          l.frustumCulled = false;
          scene.add(l);
          velLines[j] = l;
        }
        const l = velLines[j++];
        l.visible = true;
        const a = l.geometry.attributes.position;
        a.setXYZ(0, e.pos.x, e.pos.y, e.pos.z);
        a.setXYZ(1, e.pos.x + e.vel.x * 3, e.pos.y + e.vel.y * 3, e.pos.z + e.vel.z * 3);
        a.needsUpdate = true;
      }
    }
    for (; i < selRings.length; i++) selRings[i].visible = false;
    for (; j < velLines.length; j++) velLines[j].visible = false;

    /* Круг дальности главного калибра у выделенных своих (C59): без него
       не понять, достанет ли крейсер отсюда или его надо подвести, —
       а это и есть решение «держать здесь или идти». Тонкий и тусклый:
       при «Весь флот» кругов много, и они не должны заливать бой. Круг
       одного выделенного ярче. Поводок «Охраны» — тем же кругом у его
       точки, только когда выбран один корабль */
    let k = 0;
    const armed = state.selection.filter(e => e.kind === 'ship' && !e.dead && e.side === state.playerSide && e.guns.length);
    /* Кругов — не больше трёх (P5): при «Весь флот» у каждого был свой,
       и четырнадцать больших кругов сливались в паутину поверх половины
       экрана — тот же эффект, что раньше давали купола РЭБ. Выделено
       больше трёх — круг у главного (самый дальнобойный, потом самый
       крупный) и у того, что под курсором; больше восьми — только под
       курсором: тогда круг нужен как ответ на «а этот достанет?» */
    let own = armed;
    if (armed.length > 3) {
      const lead = armed.length <= 8 ? armed.reduce((b, e) => (e.guns[0].def.range > b.guns[0].def.range ||
        (e.guns[0].def.range === b.guns[0].def.range && e.radius > b.radius) ? e : b)) : null;
      own = [lead, armed.includes(hoverEnt) ? hoverEnt : null].filter((e, i, a) => e && a.indexOf(e) === i);
    }
    const op = own.length <= 1 ? 0.32 : 0.2;
    const ring = (pos, r, color, o) => {
      if (!rangeRings[k]) { const c = circleLine(MINE_HEX, 0.2); scene.add(c); rangeRings[k] = c; }
      const c = rangeRings[k++];
      c.visible = true;
      c.position.copy(pos);
      c.scale.setScalar(r);
      c.material.color.set(color);
      c.material.opacity = o;
    };
    for (const e of own) ring(e.pos, e.guns[0].def.range, 0x9fd8ff, op);
    if (armed.length === 1 && armed[0].stance === 'guard') ring(armed[0].anchor, leashOf(armed[0]), MINE_HEX, 0.16);
    for (; k < rangeRings.length; k++) rangeRings[k].visible = false;

    /* Кольцо под курсором (C74): тусклое, зелёное у своего, красное
       у врага. Выделенному оно не нужно — у него своё кольцо. */
    const he = hoverEnt && !hoverEnt.dead && !state.selection.includes(hoverEnt) ? hoverEnt : null;
    hoverRing.visible = !!he;
    if (he) {
      hoverRing.position.copy(he.pos);
      hoverRing.scale.setScalar(he.kind === 'squad' ? 18 : ringR(he) * 1.08);
      hoverRing.material.color.set(he.side === state.playerSide ? MINE_HEX : FOE_HEX);
    }
  }
  /* Кольцо выделения — ТОНКАЯ линия по длине корпуса (C111). Мягкое
     кольцо эффектов (ringMesh) толщиной в треть радиуса: на крупном
     корабле оно становилось светящимся блином шире самого корабля.
     Линия в одну точку читается одинаково на любом размере. */
  const ringR = e => Math.max(e.radius * 1.6, (e.len || e.radius * 6) * 0.55);
  const rangeRings = [];
  /* ПРОГРЕВ (P5). Первое «Весь флот» за бой давало кадр в 5,7 с кода
     (программный рендер): впервые на экране появлялись кольца, круги
     дальности и линии приказов — и видеокарта собирала их шейдер прямо
     посреди боя. Теперь те же материалы рисуются в первых кадрах, под
     заставкой «Подготовка боя» (она уходит после первого кадра нового
     экрана), а потом прячутся. Плотный купол РЭБ — так же (updateDomes) */
  let warmFrames = 3;
  const warm = new THREE.Group();
  {
    const c = circleLine(MINE_HEX, 0.2);
    c.scale.setScalar(40);
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(new Float32Array([0, 0, 0, 0, 0, 30]), 3));
    const ln = new THREE.Line(g, new THREE.LineBasicMaterial({
      color: 0x8fffc8, transparent: true, opacity: 0.5, toneMapped: false, depthWrite: false,
    }));
    const rm = ringMesh(1, 0x8fffc8, 0.8, 0.08);
    rm.scale.setScalar(26);
    rm.renderOrder = 5;
    for (const o of [c, ln, rm]) { o.frustumCulled = false; warm.add(o); }
    const own = state.ships.filter(x => x.side === state.playerSide);
    if (own.length) warm.position.copy(own[0].pos);
    scene.add(warm);
  }
  /* Прячем, а НЕ освобождаем: three.js выбрасывает собранный шейдер,
     когда освобождён последний материал с ним, — и первое «Весь флот»
     собирало его заново (замер: тот же рывок в 4 с, шейдеров 26 → 27).
     Спрятанная группа держит шейдеры до конца боя, освобождается
     вместе со сценой */
  function warmTick() {
    if (warmFrames <= 0 || --warmFrames > 0) return;
    warm.visible = false;
  }
  const hoverRing = circleLine(MINE_HEX, 0.45);
  hoverRing.visible = false;
  scene.add(hoverRing);

  // ── управление ──────────────────────────────────────────
  /* Скрытого противника не выбрать и не атаковать кликом (C18): ни
     лучом по модели, ни запасным поиском «ближайшего к точке экрана».
     Раньше клик наугад вскрывал невидимок Рииза. */
  const canPick = e => !e.dead && (e.side === state.playerSide || !unseen(e));
  function pickMeshes() {
    const m = [];
    for (const s of state.ships) if (canPick(s)) m.push(s.obj);
    for (const c of state.craft) if (canPick(c)) m.push(c.obj);
    return m;
  }

  /* Кого охранять по ПКМ: СВОЙ корабль только ПРЯМЫМ попаданием луча
     в корпус и не тот, что сам в выделении. Щедрая зона попадания
     (подпись до самого корпуса, «ближайший в 30 точках») заведена
     ради врага (C29), а с охраной она превращала самое частое действие
     боя — «подвинь флот чуть вперёд» — в «встаньте кольцом вокруг
     флагмана»: замер, «Весь флот», ПКМ на 25–70 точек впереди головного —
     охрана у семи, движения ни у кого. Курсор над таким кораблём —
     «охранять» (cur-guard), чтобы было видно, что сделает ПКМ */
  function wardAt(x, y) {
    const e = controls.pick(x, y);
    return e && e.kind === 'ship' && e.side === state.playerSide && !e.dead && !e.hyper &&
      !state.selection.includes(e) ? e : null;
  }

  function entityAt(x, y) {
    let ent = controls.pick(x, y);
    if (!ent) ent = labelAt(x, y);
    if (!ent) {
      /* Мелкую модель луч пропускает — ловим ближайшую по экрану.
         На мыши 30 точек (было 22, C29): курсор «на корабле» глазом —
         это скорее его силуэт с подписью, чем точка центра. */
      const cands = [...state.ships.filter(canPick), ...state.squads.filter(canPick)];
      ent = controls.pickNear(x, y, cands, tcam.cam, viewport.w, viewport.h, IS_TOUCH ? 46 : 30);
    }
    if (ent && ent.kind === 'craft') ent = ent.squad;
    return ent;
  }

  // Подпись под курсором — та, чья середина ближе (подписи соседей перекрываются)
  function labelAt(cx, cy) {
    const r = viewport.canvas.getBoundingClientRect();
    const x = cx - r.left, y = cy - r.top;
    let best = null, bd = Infinity;
    for (const hl of labelHits) {
      if (hl.ent.dead || !canPick(hl.ent)) continue;
      if (x < hl.x - hl.hw || x > hl.x + hl.hw || y < hl.y0 || y > hl.y1) continue;
      const d = Math.abs(x - hl.x) + Math.abs(y - hl.my) * 2;
      if (d < bd) { bd = d; best = hl.ent; }
    }
    return best;
  }

  function selectEntity(ent, additive) {
    if (!ent) { if (!additive) state.selection = []; refreshSel(); return; }
    if (ent.side === state.playerSide) sound.ui('select');
    if (ent.side !== state.playerSide) { state.selection = [ent]; refreshSel(); return; }
    if (additive) {
      state.selection = state.selection.includes(ent)
        ? state.selection.filter(x => x !== ent)
        : [...state.selection, ent];
    } else state.selection = [ent];
    refreshSel();
  }

  /* Двойной щелчок по своему кораблю — все такие же на экране (C50):
     того же типа у кораблей, той же роли у звеньев. */
  function selectSameType(ent, additive) {
    const w = viewport.w, h = viewport.h;
    const onScreen = e => {
      const p = screenOf(e.pos, tcam.cam, w, h);
      return p.z < 1 && p.x >= 0 && p.x <= w && p.y >= 0 && p.y <= h;
    };
    const P = state.playerSide;
    const list = ent.kind === 'squad'
      ? state.squads.filter(q => !q.dead && q.side === P && q.role === ent.role && q.craft.length && onScreen(q))
      : state.ships.filter(s => !s.dead && s.side === P && !s.station && s.def.id === ent.def.id && onScreen(s));
    if (!list.includes(ent)) list.push(ent);
    state.selection = additive ? [...new Set([...state.selection, ...list])] : list;
    refreshSel();
  }

  // Достаёт ли это оружие авиацию (у звена прочность у машин, класс strike)
  const hitsStrike = s => (s.kind === 'ship'
    ? s.guns.some(g => dmgMult(SPACE_DMG, g.def.type, 'strike') > 0)
    : dmgMult(SPACE_DMG, s.def.weapon, 'strike') > 0);

  const mineSelected = () => state.selection.filter(s => s.side === state.playerSide && !s.dead);

  function issueOrder(ent, world) {
    const mine = mineSelected();
    if (!mine.length) return false;
    if (ent && ent.side !== state.playerSide) {
      const air = ent.kind === 'squad';
      const goers = [];
      let held = 0, deaf = 0;
      for (const s of mine) {
        if (s.kind === 'ship') {
          if (s.station) { if (!air) { s.forced = ent; s.target = ent; } continue; }
          /* Носитель и РЭБ безоружны: по приказу «атаковать» они шли
             в упор и гибли первыми (C100). Теперь держатся, где стоят. */
          if (!s.guns.length) { held++; continue; }
          /* Главный калибр по авиации не наводится: раньше приказ на звено
             разворачивал весь флот стрелять в пустоту (C14). Такие корабли
             идут туда, где звено, — там по нему работает ПВО. */
          if (air && !hitsStrike(s)) { goers.push(s); continue; }
          /* Приказ атаковать (фокус огня) сильнее любой тактики и «с ходу»:
             идём добивать. Тактика остаётся — когда цель погибнет, корабль
             снова живёт по ней (C26) */
          s.forced = ent; s.target = liveTarget(s, ent); s.moveTo = null; s.amove = null; s.groupSpeed = 0;
        } else {
          if (air && !hitsStrike(s)) { deaf++; continue; }   // бомбардировщик по авиации не бьёт
          s.target = ent; s.recall = false; s.moveTo = null;
          // каждая машина сама выберет ближайшую из звена-цели
          for (const c of s.craft) c.target = null;
        }
      }
      if (goers.length) moveGroup(goers, ent.pos.clone());
      fx.flash(ent.pos, (ent.radius || 6) * 1.6, 0xff6b5a, 0.5);
      sound.ui('order');
      if (goers.length) toast('Главный калибр по авиации не наводится — корабли идут к звену, бьёт ПВО');
      if (held) toast('Носитель и РЭБ безоружны — держатся позади');
      if (deaf) toast('Бомбардировщики по авиации не стреляют');
      return true;
    }
    // ПКМ по своему кораблю — охранять его
    if (ent && ent.kind === 'ship' && guardShip(mine, ent)) {
      fx.flash(ent.pos, ent.hull * 0.8, 0x8fffc8, 0.5);
      sound.ui('order');
      toast(`Охраняют ${shortName(ent)}: держатся рядом и бьют подошедших`);
      return true;
    }
    if (!world) return false;
    moveGroup(mine, world);
    fx.flash(world, 16, 0x8fffc8, 0.6);
    sound.ui('order');
    state.selDirty = true;       // «чем занят» — сразу, а не через треть секунды
    return true;
  }

  /* ПКМ по СВОЕМУ кораблю — охранять его (C26): выделенные встают вокруг
     него кольцом, и их участок «Охраны» едет вместе с ним. Так эскорт
     прикрывает носитель — зенитки фрегатов закрывают его от
     бомбардировщиков. Звенья просто идут к нему. */
  function guardShip(mine, ward) {
    const ships = mine.filter(s => s.kind === 'ship' && !s.station && s !== ward);
    if (!ships.length) return false;
    ships.forEach((s, i) => {
      const a = (i / ships.length) * Math.PI * 2 + 0.4;
      const r = ward.hull + s.hull + 50;
      s.guardOf = ward;
      s.guardOff = new THREE.Vector3(Math.cos(a) * r, (i % 2 ? 1 : -1) * 18, Math.sin(a) * r);
      s.anchor.copy(ward.pos).add(s.guardOff);
      s.stance = 'guard';
      s.moveTo = null; s.amove = null; s.forced = null; s.target = null; s.drift = false; s.groupSpeed = 0;
    });
    const sq = mine.filter(s => s.kind === 'squad');
    if (sq.length) moveGroup(sq, ward.pos.clone());
    return true;
  }

  /* Тактика выделенным (C26): «Держать», «Охрана», «Охота». Участок
     «Охраны» и «Держать» — там, где корабль стоит сейчас.
     «Держать» — это ПРИКАЗ ВСТАТЬ, то же, что «Стоп»: снимает «идти»,
     «с ходу», фокус огня и дрифт (с выключенными гасителями корабль
     не встанет). Раньше H меняла только тактику, а приказ «идти»
     оставался: панель писала «идёт к точке», полоска — «стоят на
     месте», и корабль проходил ещё пять корпусов. «Охрана» и «Охота» —
     манера боя: начатый марш корабль доводит, а дальше живёт по ней */
  function setStance(list, id) {
    const ships = list.filter(s => s.kind === 'ship' && !s.dead && !s.station);
    if (!ships.length) return false;
    /* Безоружному (носитель, РЭБ) охотиться нечем: раньше T отправляла
       его «на охоту», и он стоял посреди врагов с подписью «охота · целей
       не видно» (P5). Теперь он идёт при флоте — охраняет главного из
       выделенных вооружённых; таких нет — держит свой участок */
    const armed = ships.filter(s => s.guns.length);
    const lead = id === 'hunt' && armed.length
      ? armed.reduce((b, s) => (s.radius > b.radius ? s : b)) : null;
    let wi = 0;
    for (const s of ships) {
      s.stance = id;
      s.guardOf = null;
      s.anchor.copy(s.pos);
      if (lead && !s.guns.length) {
        const a = wi++ * 2.3 + 2.6, r = lead.hull + s.hull + 70;
        s.guardOf = lead;
        s.guardOff = new THREE.Vector3(Math.cos(a) * r, 25, Math.sin(a) * r);
      }
      if (id !== 'hunt') s.target = null;
      if (id === 'hold') {
        s.moveTo = null; s.amove = null; s.forced = null;
        s.groupSpeed = 0; s.arriveT = 0; s.drift = false; s.jamShot = null;
      }
    }
    return true;
  }

  /* Приказ идти: строй квадратом вокруг точки. attack — атака с ходу
     (A): корабли идут к той же точке, но останавливаются на каждого
     встречного (см. updateShip); звенья и так бьют всё на пути. */
  function moveGroup(mine, world, attack) {
    const n = mine.length, cols = Math.ceil(Math.sqrt(n));
    /* Шаг строя — по самому крупному корпусу в группе (C87): с прежними
       90 единицами флагманы вставали друг в друга. Обычный приказ «идти»
       ведёт строй со скоростью самого медленного (C70): иначе корветы
       приходили первыми, одни. Атака с ходу — нет: замер показал, что
       строй по флагману вдвое затягивал сближение (половина флота
       вступала в бой на 45-й секунде вместо 25-й), а у атаки с ходу
       своя защита — каждый встаёт на первого встречного */
    const ships = mine.filter(s => s.kind === 'ship');
    const step = Math.max(90, Math.max(0, ...ships.map(s => s.hull)) * 2.1);
    const slow = ships.length > 1 && !attack ? Math.min(...ships.map(s => s.def.maxSpeed)) : 0;
    mine.forEach((s, i) => {
      const col = i % cols, row = Math.floor(i / cols);
      const dest = world.clone().add(_v.set((col - (cols - 1) / 2) * step, 0, (row - (cols - 1) / 2) * step));
      dest.y = s.kind === 'ship' ? s.pos.y : world.y;
      if (attack && s.kind === 'ship') { s.amove = dest; s.moveTo = null; }
      else { s.moveTo = dest; s.amove = null; }
      s.target = null;
      if (s.kind === 'ship') { s.guardOf = null; s.groupSpeed = slow; s.arriveT = 0; }
      /* Приказ идти сам включает гасители: иначе корабль продолжит
         скользить мимо точки, и приказ будет выглядеть как баг. */
      s.drift = false;
      if (s.kind === 'ship') s.forced = null;
      else { s.recall = false; for (const c of s.craft) c.target = null; }
    });
  }

  function amoveSelected(world) {
    const mine = mineSelected();
    if (!mine.length || !world) return false;
    moveGroup(mine, world, true);
    fx.flash(world, 16, 0xffa860, 0.6);
    sound.ui('order');
    return true;
  }

  /* ПКМ мимо врага, но рядом с ним — это приказ «идти», и флот уйдёт
     в упор к противнику (C29). Молча так делать нельзя: скажем, как
     атаковать. Не чаще раза в шесть секунд. */
  let nearMissAt = -99;
  function nearFoe(x, y, px) {
    const r = viewport.canvas.getBoundingClientRect();
    const P = state.playerSide;
    return state.ships.some(s => {
      if (s.dead || s.side === P || !canPick(s)) return false;
      const q = screenOf(s.pos, tcam.cam, viewport.w, viewport.h);
      return q.z < 1 && Math.hypot(q.x + r.left - x, q.y + r.top - y) < px;
    });
  }

  const controls = new Controls(viewport.canvas, tcam, {
    pickMeshes,
    canPick,
    planeY: () => 0,
    onBoxModeChange: on => boxBtn.classList.toggle('on', on),
    onTap({ x, y, shift, touch, double }) {
      const ent = entityAt(x, y);
      const world = controls.worldAt(x, y);
      // Нажата A: этот щелчок — точка или цель атаки с ходу
      if (pending === 'amove') {
        pending = null;
        if (ent && ent.side !== state.playerSide) issueOrder(ent, world);
        else amoveSelected(world);
        updateHover();
        return;
      }
      // На мыши касание — всегда выбор (приказы на ПКМ).
      // На пальце: свой корабль — выбор, всё прочее — приказ.
      if (!touch) {
        if (double && ent && ent.side === state.playerSide) { selectSameType(ent, shift); return; }
        selectEntity(ent, shift);
        return;
      }
      if (ent && ent.side === state.playerSide) { selectEntity(ent, shift); return; }
      if (state.selection.some(s => s.side === state.playerSide && !s.dead)) {
        if (issueOrder(ent, world)) return;
      }
      selectEntity(ent, shift);
    },
    onOrder({ x, y }) {
      pending = null;          // ПКМ во время «A» — обычный приказ
      const ent = entityAt(x, y);
      if (!ent && mineSelected().length && state.time - nearMissAt > 6 && nearFoe(x, y, 80)) {
        nearMissAt = state.time;
        toast('Мимо цели — флот идёт в точку. Атаковать: правой кнопкой по кораблю или его подписи');
      }
      // Свой корабль — «охранять», только если щёлкнули точно в него (wardAt)
      issueOrder(ent && ent.side !== state.playerSide ? ent : wardAt(x, y), controls.worldAt(x, y));
    },
    onBox(rect, additive) {
      pending = null;
      const w = viewport.w, h = viewport.h;
      const found = [];
      for (const s of state.ships) {
        if (s.dead || s.side !== state.playerSide || s.station) continue;
        const p = screenOf(s.pos, tcam.cam, w, h);
        if (p.z < 1 && p.x >= rect.x0 && p.x <= rect.x1 && p.y >= rect.y0 && p.y <= rect.y1) found.push(s);
      }
      for (const sq of state.squads) {
        if (sq.dead || sq.side !== state.playerSide || !sq.craft.length) continue;
        const p = screenOf(sq.pos, tcam.cam, w, h);
        if (p.z < 1 && p.x >= rect.x0 && p.x <= rect.x1 && p.y >= rect.y0 && p.y <= rect.y1) found.push(sq);
      }
      state.selection = additive ? [...new Set([...state.selection, ...found])] : found;
      refreshSel();
    },
  });

  /* ── НАВЕДЕНИЕ (C74). Что под курсором — десять раз в секунду, а не
     на каждое движение мыши: луч по моделям не бесплатен, а корабли
     уезжают из-под неподвижного курсора и сами. Курсор говорит, что
     сделает щелчок: рука — выбрать, прицел — атаковать, метка — идти. */
  let hoverTick = 0;
  function updateHover() {
    const hv = controls.hover;
    const P = state.playerSide;
    hoverEnt = hv.in && !controls.pointers.size && !ended ? entityAt(hv.x, hv.y) : null;
    const own = state.selection.some(s => s.side === P && !s.dead);
    let cur = null;
    if (pending === 'amove') cur = 'cur-attack';
    else if (hoverEnt && hoverEnt.side !== P) cur = own ? 'cur-attack' : 'cur-pick';
    else if (hoverEnt) cur = own && wardAt(hv.x, hv.y) ? 'cur-guard' : 'cur-pick';
    else if (own && hv.in && !ended) cur = 'cur-move';
    controls.setCursor(cur);
  }

  // ── панель выделения ────────────────────────────────────
  /* Чем корабль занят прямо сейчас. Без этой строки панель отвечала
     на вопрос «кто выбран», но не на «что он делает», а в бою важнее
     второе: игрок отдал приказ и хочет видеть, что тот принят. */
  function doingOf(e) {
    if (e.kind === 'squad') {
      const live = e.craft.filter(c => !c.dead);
      if (!live.length) return 'звено выбито';
      if (live.some(c => c.reloading > 0)) return 'перезаряжается';
      if (e.moveTo) return 'идёт к точке';
      if (live.some(c => c.target)) return 'атакует';
      return 'патрулирует';
    }
    if (e.hyper) return `уходит в гипер · ${Math.ceil(e.hyper.left)} с`;
    if (e.ionized) return 'двигатели выжжены';
    return shipDoing(e) + jamNote(e);
  }
  function shipDoing(e) {
    if (e.drift) return 'дрифт: тяга отключена';
    if (e.moveTo) {
      const d = Math.round(e.pos.distanceTo(e.moveTo));
      return `идёт к точке · ${d}`;
    }
    // под помехами цель называет jamNote — там и сказано, достаёт ли
    const t = !e.jam && e.target && !e.target.dead && e.target.def ? ` · бьёт ${shortName(e.target)}` : '';
    if (e.amove) return `идёт с боем · ${Math.round(e.pos.distanceTo(e.amove))}${t}`;
    if (e.forced && !e.forced.dead) return `фокус огня: ${shortName(e.forced)}`;
    // Безоружный на «Охоте» — при флоте: охотиться ему нечем (P5)
    if (!e.guns.length && e.stance !== 'hold') {
      return e.guardOf ? `безоружен — держится у ${shortName(e.guardOf)}` : 'безоружен — держится на участке';
    }
    const st = e.stance === 'hold' ? 'держит позицию'
      : e.stance === 'hunt' ? 'охота'
      : e.guardOf ? `охраняет ${shortName(e.guardOf)}` : 'охрана участка';
    if (e.jam) return st;
    if (t) return st + t;
    return e.stance === 'hunt' ? 'охота · целей не видно' : `${st} · ждёт`;
  }
  /* Под чужим куполом РЭБ — сказать прямо: раньше панель писала «фокус
     огня» над кораблём, который полминуты не мог выстрелить */
  function jamNote(e) {
    if (!e.jam || e.kind !== 'ship') return '';
    const t = e.target && !e.target.dead && e.target.kind === 'ship' ? e.target : null;
    const near = t && t.pos.distanceTo(e.pos) <= e.jam.lockRange;
    // «Держать» к глушителю не пойдёт — с места бьёт только вблизи
    const goes = !e.station && (e.forced || e.amove || e.stance !== 'hold');
    if (t && t.ecm && t.ecm.mode === 'jam' && (near || goes)) return ` · под помехами — ${near ? 'бьёт' : 'идёт бить'} глушитель ${shortName(t)}`;
    if (near) return ` · под помехами — бьёт ${shortName(t)} вблизи`;
    return ' · под помехами — бьёт только вблизи';
  }

  /* ── ПАНЕЛЬ ВЫДЕЛЕННОГО.
     Кнопки действий НЕ пересоздаются на каждом обновлении (C30). Раньше
     панель собиралась заново раз в треть секунды, и если пересборка
     приходилась на время нажатия, клик терялся: кнопка, на которой
     нажали, к отпусканию уже была выброшена. Теперь набор кнопок
     описывается списком, и разметка пересобирается, только когда
     сменился ключ — состав выделения или набор действий. Подписи,
     «недоступна» и обработчик обновляются на месте. */
  let actsKey = '';
  let actsEls = [];
  function setHtml(el, html) { if (el._html !== html) { el._html = html; el.innerHTML = html; } }
  function refreshSel() {
    const sel = $('sel'), acts = $('acts');
    const list = state.selection.filter(s => !s.dead);
    if (!list.length) {
      setHtml(sel, '<div class="sel-empty">Ничего не выбрано</div>');
      if (actsKey !== '') { actsKey = ''; actsEls = []; acts.innerHTML = ''; hideTip(); }
      acts.hidden = true;
      actsItems = [];
      return;
    }
    if (list.length === 1) {
      const e = list[0];
      if (e.kind === 'squad') {
        const role = STRIKE_ROLES[e.role];
        const size = e.size || e.craft.length;
        const ammo = e.craft.reduce((a, c) => a + (c.ammo || 0), 0);
        const rl = e.craft.reduce((a, c) => a + (c.reloads || 0), 0);
        const ammoTxt = e.def.weaponKind === 'missile'
          ? ` · ракет ${ammo} · запасных комплектов ${rl}` : ' · пушки';
        setHtml(sel, `<div class="sel-title">${e.def.name}</div>
          <div class="sel-sub">${role.label} · ${e.craft.length}/${size} машин${ammoTxt}</div>
          <div class="sel-doing">${doingOf(e)}</div>
          <div class="sel-desc">${role.hint}</div>`);
      } else {
        const spd = Math.round(e.vel.length());
        const foreign = e.side !== state.playerSide ? '<span class="tag foe">противник</span>' : '';
        setHtml(sel, `<div class="sel-title${e.side !== state.playerSide ? ' foe' : ''}">${e.name} ${foreign}</div>
          <div class="sel-sub">${e.def.role || ''} · скорость ${spd} · прочность ${Math.max(0, Math.round(e.hp))}/${e.maxHp}</div>
          <div class="sel-hpbar${e.side !== state.playerSide ? ' foe' : ''}"><i style="width:${clamp(e.hp / e.maxHp, 0, 1) * 100}%"></i></div>
          <div class="sel-doing">${doingOf(e)}</div>
          <div class="sel-desc">${e.def.desc || ''}</div>`);
      }
    } else {
      const by = {};
      for (const e of list) {
        const n = classWord(e);
        by[n] = (by[n] || 0) + 1;
      }
      setHtml(sel, `<div class="sel-title">Выделено: ${list.length}</div>
        <div class="sel-sub">${Object.entries(by).map(([n, c]) => `${n} ×${c}`).join(' · ')}</div>
        <div class="sel-doing">${doingOf(list[0])}</div>`);
    }

    /* ── ПАНЕЛЬ КОМАНД (C33). Сетка коротких кнопок, как командная
       карта RTS: на кнопке — короткое слово и буква клавиши, а описание
       ушло во всплывающую подсказку. Раньше это была одна строка кнопок
       с описанием внутри, шириной 1701 точку: на 1366 шесть из
       одиннадцати («Стоп», «Гипер», «Выше», «Ниже»…) были за краем
       экрана, а колесо их не прокручивало. Общие команды — первыми
       и всегда на тех же местах; особые (ангар, купол) — за ними.
       id задаёт место в ключе, остальное обновляется на месте (C30);
       key — клавиша (e.code), её буква стоит в углу кнопки (C50);
       cat — мелкая строка над словом (сколько мест в ангаре и т. п.). */
    const items = [];
    const KEYS = {
      amove: 'KeyA', stop: 'KeyS', hold: 'KeyH', guard: 'KeyY', hunt: 'KeyT', up: 'PageUp', down: 'PageDown', drift: 'KeyD',
      jump: 'KeyG', unjump: 'KeyG',
      'launch-interceptor': 'KeyZ', 'launch-fighter': 'KeyX', 'launch-bomber': 'KeyC',
      land: 'KeyV', 'ecm-jam': 'KeyJ', 'ecm-shield': 'KeyK', 'ecm-off': 'KeyL',
    };
    const addBtn = (id, label, hint, fn, o = {}) => items.push({
      id, label, hint, fn, disabled: !!o.disabled, key: KEYS[id], cat: o.cat || '', on: !!o.on, part: !!o.part,
    });

    const ships = list.filter(e => e.kind === 'ship' && e.side === state.playerSide && !e.station);
    const squads = list.filter(e => e.kind === 'squad' && e.side === state.playerSide);
    if (ships.length || squads.length) {
      addBtn('amove', 'Атака с ходу', 'Идут к точке и бьют всех встречных: нажми, затем щёлкни точку или цель',
        () => startAmove(), { cat: 'приказ' });
    }
    if (ships.length) {
      addBtn('stop', 'Стоп', 'Снять приказы и встать — дальше корабли держат позицию, как «Держать»', () => {
        setStance(ships, 'hold');     // «Держать» сама снимает приказы и дрифт
        // подтверждение — как у H (P5): «Стоп» — из самых частых приказов
        sound.ui('order');
        toast('Стоп: встают на месте и бьют только тех, до кого достают');
        refreshSel();
      }, { cat: 'приказ' });
      /* Тактики (C26): одна горит — та, что у всех выделенных; пунктиром —
         у части. Без них «Стоп» держал корабль секунду — дальше он сам
         находил цель и шёл на сближение, и линию было не удержать */
      for (const id of SPACE_STANCE_IDS) {
        const st = SPACE_STANCES[id];
        const n = ships.filter(s => s.stance === id).length;
        addBtn(id, st.name, st.hint, () => {
          // «Охрана» и «Охота» марш не прерывают — так и скажем
          const going = id !== 'hold' && ships.some(s => s.moveTo || s.amove);
          setStance(ships, id);
          sound.ui('order');
          // Безоружным на «Охоте» охотиться нечем: при флоте — держатся
          // у главного из вооружённых, без флота — на своём участке
          const unarmed = id === 'hunt' && ships.some(s => !s.guns.length);
          const armed = ships.some(s => s.guns.length);
          toast(`${st.name}${going ? ' — после прихода в точку' : ''}: ${st.hint.split('.')[0].toLowerCase()}` +
            (!unarmed ? '' : armed ? ' · безоружные держатся при флоте' : ' · безоружным охотиться нечем — держат участок'));
          refreshSel();
        }, { cat: 'тактика', on: n === ships.length, part: n > 0 && n < ships.length });
      }
      /* Шаг — 180, а не 120: блин помех ловит по высоте ±144 от излучателя
         (ECM.height × 1,6), и с прежних 120 корабль оставался под куполом,
         хотя подсказка обещала «выйти из купола» (замер стендом) */
      addBtn('up', 'Выше', `Поднять на ${UPDOWN} — выйти из купола помех или над строем`, () => {
        for (const s of ships) { s.moveTo = s.pos.clone().add(_v.set(0, UPDOWN, 0)); s.amove = null; s.guardOf = null; }
        sound.ui('order');
        toast(`Выше на ${UPDOWN}`);
        state.selDirty = true;
      }, { cat: 'высота' });
      addBtn('down', 'Ниже', `Опустить на ${UPDOWN} — выйти из купола помех снизу`, () => {
        for (const s of ships) { s.moveTo = s.pos.clone().add(_v.set(0, -UPDOWN, 0)); s.amove = null; s.guardOf = null; }
        sound.ui('order');
        toast(`Ниже на ${UPDOWN}`);
        state.selDirty = true;
      }, { cat: 'высота' });
      const driftN = ships.filter(s => s.drift).length;
      addBtn('drift', 'Дрифт', 'Гасители инерции: корабль скользит по вектору, корпус свободно наводится на цель. Приказ идти включает их обратно',
        toggleDrift, { cat: driftN && driftN < ships.length ? `${driftN} из ${ships.length}` : 'ход',
          on: driftN === ships.length, part: driftN > 0 && driftN < ships.length });
      const jumping = ships.filter(s => s.hyper);
      if (jumping.length) {
        // Носитель ушёл — бой проигран, отход уже не отменить
        if (state.conceded !== state.playerSide) {
          addBtn('unjump', 'Отменить гипер', 'Вернуться в бой', () => {
            for (const s of jumping) s.hyper = null;
            if (!state.ships.some(s => !s.dead && s.side === state.playerSide && s.hyper)) {
              state.retreat[state.playerSide] = false;
              refreshRetreat();
            }
            refreshSel();
          }, { cat: 'гипер', on: true });
        }
      } else {
        /* С носителем «Уйти в гипер» — это «Отход» всего флота: за
           ушедшим носителем уходят все, бой проигран. Поэтому тот же
           вопрос, что у «Отхода», и с кнопки, и с G (C34): буква стоит
           между F и H, и промах мимо «держать» молча проигрывал бой.
           Без носителя — сразу, но полоской: G ещё раз отменит. */
        const carrier = ships.some(s => s.cls === 'carrier');
        const go = () => {
          if (ended) return;
          const live = ships.filter(s => beginJump(s));
          if (!live.length) return;
          const t = Math.ceil(Math.max(...live.map(s => s.hyper.left)));
          toast(carrier ? `Авианосец копит гипер, ${t} с — за ним уйдёт весь флот · G — отменить`
                        : `Гипер через ${t} с, всё это время беззащитны · G — отменить`);
          refreshSel();
        };
        addBtn('jump', 'В гипер', carrier
          ? 'Носитель уходит — за ним отходит весь флот, бой проигран. Спросит подтверждение'
          : 'Копит переход и уходит из боя, всё это время беззащитен', () => {
          if (!carrier) { go(); return; }
          ask({
            title: 'Авианосец уходит — это отход',
            text: 'За ушедшим авианосцем в гипер уходит весь флот, и бой будет проигран: ' +
              'домой вернутся только те, кто успеет уйти. Пока авианосец копит переход, ' +
              'уход можно отменить — G или «Отменить гипер».',
            yes: 'Уйти в гипер', no: 'Остаться в бою',
          }, go);
        }, { cat: 'уйти' });
      }
    }

    const carriers = list.filter(e => e.kind === 'ship' && e.hangar && e.side === state.playerSide);
    if (carriers.length) {
      const free = carriers.reduce((a, c) => a + c.hangar.free, 0);
      for (const role of ['interceptor', 'fighter', 'bomber']) {
        const r = STRIKE_ROLES[role];
        addBtn('launch-' + role, r.label, `Поднять звено: ${r.hint}. Свободно мест в ангаре: ${free}`, () => {
          const c = carriers.find(x => !x.dead && x.hangar.free > 0);
          if (c) { launchSquadron(c, role); refreshSel(); }
        }, { disabled: free <= 0, cat: `ангар ${free}` });
      }
    }
    if (squads.length) addBtn('land', 'На посадку', 'Вернуть звено, освободить ангар', () => { for (const s of squads) s.recall = true; }, { cat: 'звено' });

    const ecms = list.filter(e => e.ecm && e.side === state.playerSide);
    if (ecms.length) {
      const cur = ecms[0].ecm.mode;
      addBtn('ecm-jam', 'Глушение', 'Купол помех: ломает чужое наведение внутри', () => {
        for (const e of ecms) e.ecm.mode = 'jam';
        toast('Купол помех развёрнут');
        refreshSel();
      }, { cat: 'купол', on: cur === 'jam' });
      addBtn('ecm-shield', 'Прикрытие', 'Купол защиты: снимает чужие помехи со своих', () => {
        for (const e of ecms) e.ecm.mode = 'shield';
        toast('Купол переключён на защиту');
        refreshSel();
      }, { cat: 'купол', on: cur === 'shield' });
      addBtn('ecm-off', 'Молчать', 'Выключить излучение', () => { for (const e of ecms) e.ecm.mode = 'off'; refreshSel(); },
        { cat: 'купол', on: cur === 'off' });
    }

    const key = list.map(e => e.uid).join(',') + '|' + items.map(i => i.id).join(',');
    if (key !== actsKey) {
      actsKey = key;
      acts.innerHTML = '';
      hideTip();
      actsEls = items.map((it, idx) => {
        const b = document.createElement('button');
        b.className = 'act';
        b.dataset.act = it.id;
        const cat = document.createElement('i');
        const lb = document.createElement('b');
        b.append(cat, lb);
        if (it.key) {
          const k = document.createElement('kbd');
          k.className = 'hk';
          k.textContent = keyName(it.key);
          b.appendChild(k);
        }
        // Подсказка — своя, сразу при наведении: штатный title ждёт
        // секунду и прячется, стоит шевельнуть мышью
        b.addEventListener('pointerenter', ev => { if (ev.pointerType === 'mouse') showTip(b, idx); });
        b.addEventListener('pointerleave', hideTip);
        b.addEventListener('pointerdown', hideTip);
        acts.appendChild(b);
        return { b, lb, cat };
      });
    }
    acts.hidden = !items.length;
    items.forEach((it, i) => {
      const el = actsEls[i];
      if (el.lb.textContent !== it.label) {
        el.lb.textContent = it.label;
        // «Бомбардировщик», «Отменить гипер» — мельче, чтобы влезли целиком
        el.b.classList.toggle('long', it.label.length > 12);
      }
      if (el.cat.textContent !== it.cat) el.cat.textContent = it.cat;
      if (el.b.disabled !== it.disabled) el.b.disabled = it.disabled;
      el.b.classList.toggle('on', it.on);
      el.b.classList.toggle('part', it.part);
      const aria = it.label + (it.key ? ` (${keyName(it.key)})` : '');
      if (el.b.getAttribute('aria-label') !== aria) el.b.setAttribute('aria-label', aria);
      el.b.onclick = it.fn;
    });
    actsItems = items;
    if (tipFor >= 0) showTip(actsEls[tipFor] && actsEls[tipFor].b, tipFor);
  }
  /* Всплывающая подсказка команды: название, клавиша, что делает.
     Стоит над кнопкой и не выходит за края экрана. */
  const tipEl = $('tip');
  let tipFor = -1;
  function showTip(b, idx) {
    const it = actsItems[idx];
    if (!b || !it || !b.isConnected) { hideTip(); return; }
    tipFor = idx;
    const html = `<b>${it.label}</b>${it.key ? `<kbd class="hk">${keyName(it.key)}</kbd>` : ''}` +
      `<span>${it.hint || ''}${it.disabled ? ' · сейчас недоступно' : ''}</span>`;
    if (tipEl._html !== html) { tipEl._html = html; tipEl.innerHTML = html; }
    tipEl.hidden = false;
    const r = b.getBoundingClientRect(), hr = hud.getBoundingClientRect();
    const tw = tipEl.offsetWidth, th = tipEl.offsetHeight;
    const x = clamp(r.left + r.width / 2 - tw / 2 - hr.left, 6, hr.width - tw - 6);
    tipEl.style.transform = `translate(${x | 0}px,${(r.top - hr.top - th - 8) | 0}px)`;
  }
  function hideTip() { tipFor = -1; if (tipEl) tipEl.hidden = true; }
  let actsItems = [];
  const keyName = code => code === 'PageUp' ? 'PgUp' : code === 'PageDown' ? 'PgDn' : code.replace(/^Key|^Digit/, '');
  refreshSel();

  /* ── ОТРЯДЫ 1…9 (C50). Ctrl+цифра или Shift+цифра — записать
     выбранное, цифра — выбрать, дважды подряд — камера к отряду.
     Shift — потому что в обычной вкладке Ctrl+1…8 браузер забирает
     себе (переключение вкладок) и до игры они не доходят; в полном
     экране (F11) их отдаёт игре Keyboard Lock. */
  let lastGroup = { n: null, t: 0 };
  function saveGroup(n) {
    const list = state.selection.filter(e => !e.dead && e.side === state.playerSide);
    if (!list.length) { toast(`Отряд ${n}: сначала выдели корабли, потом Ctrl или Shift + ${n}`); return; }
    groups[n] = list.slice();
    toast(`Отряд ${n}: ${list.length} · записан`);
    refreshRoster();
  }
  function recallGroup(n) {
    const list = (groups[n] || []).filter(e => !e.dead);
    groups[n] = list;
    if (!list.length) { toast(`Отряд ${n} пуст — выдели корабли и нажми Ctrl или Shift + ${n}`); return; }
    const now = performance.now();
    const again = lastGroup.n === n && now - lastGroup.t < 450;
    lastGroup = { n, t: now };
    state.selection = list.slice();
    if (again) focusOn(list);
    refreshSel();
  }

  function startAmove() {
    if (!mineSelected().length) { toast('Атака с ходу: сначала выбери свои корабли'); return; }
    pending = 'amove';
    toast('Атака с ходу: щёлкни точку или цель · Esc — отмена');
    updateHover();
  }

  /* ── МЕНЮ ПАУЗЫ (C35). Бой стоит, пока меню открыто, и после
     «Продолжить» скорость та же, что была. «Начать бой заново» — только
     в быстром бою: в кампании это был бы второй бросок кубика. */
  let pauseOpen = false;
  function openPause() {
    if (ended || pauseOpen || !ctx.pause) return;
    pauseOpen = true;
    const was = state.paused;
    state.paused = true;
    pending = null;
    ctx.pause({
      restart: !config.inCampaign && ctx.restartBattle ? () => ctx.restartBattle() : null,
      exitText: 'Бой не будет засчитан.',
      /* В кампании выйти посреди боя нельзя: она уже сохранена со
         следующим ходом, и выход был бы переигровкой (а оборона —
         пропавшей атакой ИИ). Выход — тот же «Отход» с вопросом. */
      leave: config.inCampaign ? {
        label: state.retreat[state.playerSide] ? 'Флот уже отходит' : 'Отход из боя…',
        note: 'Бой кампании доигрывается до конца: выйти можно отходом, и он засчитается. В главное меню — с карты системы.',
        fn: askRetreat,
      } : null,
      onClose: () => { pauseOpen = false; state.paused = was; },
    });
  }

  /* ── КЛАВИАТУРА (C50). Один обработчик на весь бой: Пробел — пауза,
     Esc — отменить по очереди (атаку с ходу, рамку, выбор), а когда
     отменять нечего — меню паузы; A/S/H — приказы; цифры — отряды;
     буквы действий выделенного — те, что написаны на кнопках. */
  function onKey(e) {
    if (e.target && /input|textarea|select/i.test(e.target.tagName)) return;
    /* После итоговой карточки бой окончен: Пробел снимал паузу, и под
       карточкой корабли продолжали гибнуть (C65) */
    if (ended) return;
    const code = e.code, mod = e.ctrlKey || e.metaKey;
    if (code === 'Space') {
      e.preventDefault();
      if (!e.repeat) hud.querySelector(`[data-speed="${state.paused ? state.speed : 0}"]`).click();
      return;
    }
    if (code === 'Escape') {
      e.preventDefault();
      /* Повтор удержанного Esc не отменяет и не открывает ничего: иначе
         повторы шли по очереди в меню паузы и сюда, меню мигало
         пятнадцать раз в секунду, а бой сам снимался с паузы. А держат
         Esc нарочно — так выходят из полного экрана с запертым Esc */
      if (e.repeat) return;
      if (pending) { pending = null; updateHover(); toast('Атака с ходу отменена'); return; }
      if (controls.boxMode) { controls.setBoxMode(false); return; }
      if (state.selection.length) { state.selection = []; refreshSel(); updateHover(); return; }
      openPause();
      return;
    }
    if (e.repeat) return;
    const dm = /^(?:Digit|Numpad)([1-9])$/.exec(code);
    if (dm) {
      e.preventDefault();
      if (mod || e.shiftKey) saveGroup(dm[1]); else recallGroup(dm[1]);
      return;
    }
    if (mod || e.altKey) return;        // Ctrl+буква — браузеру
    /* M — без звука и обратно: в бою звук выключают быстро (звонок,
       сосед), листать за этим в меню паузы — долго */
    if (code === 'KeyM') { toast(sound.toggleMute() ? 'Звук выключен · M — включить' : 'Звук включён · M — выключить'); return; }
    if (code === 'F2') { e.preventDefault(); hud.querySelector('[data-q="all"]').click(); return; }
    if (code === 'KeyA') { startAmove(); return; }
    if (code === 'KeyD') { toggleDrift(); return; }
    if (code === 'KeyB') { reinfBtn.click(); return; }
    if (code === 'KeyN') { selectArrived(); return; }
    const it = actsItems.find(x => x.key === code && x.fn);
    if (it) {
      e.preventDefault();
      if (it.disabled) toast(`${it.label.replace(/^⦿ /, '')}: сейчас недоступно`);
      else it.fn();
      return;
    }
    if (/^Key[SHYT]$/.test(code) && !mineSelected().some(s => s.kind === 'ship')) {
      toast('Сначала выбери свои корабли');
    }
  }
  addEventListener('keydown', onKey);

  // ── ЗАВЕРШЕНИЕ ───────────────────────────────────────────
  function survivors(side) {
    const out = {};
    for (const s of state.ships) {
      if (s.dead || s.side !== side || s.station) continue;
      out[s.def.id] = (out[s.def.id] || 0) + 1;
    }
    // ушедшие в гипер тоже уцелели — они вернутся в кампанию
    for (const id of state.jumped[side]) out[id] = (out[id] || 0) + 1;
    /* Второй эшелон, который так и не вызвали (или он ещё в пути), —
       тоже часть флота. Раньше он пропадал после боя бесследно (C15) */
    for (const x of state.reserve[side] || []) out[x.id] = (out[x.id] || 0) + x.count;
    return Object.entries(out).map(([id, count]) => ({ id, count }));
  }

  /* Сторона больше не держит орбиту: живых кораблей нет. Станция уйти
     не может — при отходе её бросают, и она в счёт не идёт. */
  function sideOut(side) {
    const live = state.ships.filter(s => !s.dead && s.side === side);
    return !live.length || (state.retreat[side] && live.every(s => s.station));
  }

  let ended = false;
  let outcome = null;
  function finish(result) {
    if (ended) return;
    ended = true;
    state.paused = true;
    pending = null;
    hoverEnt = null;
    controls.setCursor(null);
    /* Выживших снимаем В МОМЕНТ ИТОГА, а не по «Продолжить»: под
       карточкой бой стоит, но и снимок должен быть тем, что видел игрок
       (C65). Плюс корабли дальнего гипера, дошедшие до боя: кампания
       вычтет их из родных систем (C16). */
    outcome = {
      result, attacker: survivors('attacker'), defender: survivors('defender'),
      far: state.far.filter(e => e.done).map(e => ({ id: e.id, ships: e.ships.map(x => ({ ...x })) })),
    };
    const P = state.playerSide;
    const saved = state.jumped[P].length;
    const spare = (state.reserve[P] || []).reduce((a, x) => a + x.count, 0);
    // Потери — в таблице итогов; здесь то, что вернётся в кампанию
    const tally = [
      saved ? `Ушли в гипер: ${saved}` : '',
      spare ? `резерв в бой не вступал: ${spare}` : '',
    ].filter(Boolean).join(' · ');
    const win = result === 'victory';
    const card = $('end');
    card.style.display = 'flex';
    /* «Ещё раз» — тот же бой с нуля, только в быстром бою: в кампании это
       был бы второй бросок кубика (та же причина, по которой там нет
       «Начать бой заново» в меню паузы, P2) */
    const again = !config.inCampaign && ctx.restartBattle;
    card.innerHTML = `<div class="end-inner wide">
      <h2>${win ? 'Орбита за нами' : result === 'retreat' ? 'Отход' : 'Флот разбит'}</h2>
      <p>${win
        /* «Можно высаживать десант» — только в кампании: в быстром бою
           высадки нет, и обещать её нельзя (P5) */
        ? (config.inCampaign ? 'Противник в этой системе больше не контролирует пространство. Можно высаживать десант.'
          : 'Противник больше не контролирует орбиту: его флот уничтожен или ушёл.')
        : result === 'retreat'
          ? 'Флот вышел из боя. Домой вернутся только те, кто успел уйти в гипер.'
          : saved || spare
            ? `Орбита за противником. Домой вернутся только ${[saved ? 'ушедшие в гипер' : '', spare ? 'корабли резерва' : ''].filter(Boolean).join(' и ')}.`
            : 'Корабли потеряны. Орбита остаётся за противником.'}</p>
      ${endStats()}
      ${tally ? `<p class="end-tally">${tally[0].toUpperCase() + tally.slice(1)}.</p>` : ''}
      <div class="end-actions">
        ${again ? '<button class="btn" data-role="again" title="Тот же бой с самого начала">Ещё раз</button>' : ''}
        <button class="btn primary" data-role="cont">${config.inCampaign ? 'На карту' : 'В меню'}</button>
      </div></div>`;
    state.outcome = outcome;     // для автотестов: что уйдёт в кампанию
    card.querySelector('[data-role="cont"]').onclick = () => {
      config.onEnd && config.onEnd(outcome);
    };
    const ag = card.querySelector('[data-role="again"]');
    if (ag) ag.onclick = () => ctx.restartBattle();
  }

  /* ── ИТОГИ БОЯ: потери обеих сторон по видам кораблей, время боя,
     кто больше всех нанёс урона. Без них исход оставался загадкой:
     «Флот разбит» и одна кнопка, а почему — не понять, и улучшать в
     следующей попытке нечего. Время — игровое (на 4× бой короче на
     часах, но не в игре). */
  function endStats() {
    const P = state.playerSide, E = enemyOf(P), st = state.stats;
    const ORDER = ['capital', 'sinho', 'cruiser', 'carrier', 'ecm', 'frigate', 'corvette', 'station'];
    const ids = [...new Set([...Object.keys(st.n[P]), ...Object.keys(st.n[E])])]
      .sort((a, b) => ORDER.indexOf(a) - ORDER.indexOf(b));
    const word = id => {
      if (id === 'station') return 'Станция';
      const s = state.ships.find(x => x.def.id === id);
      return s ? classWord(s) : id;
    };
    const cell = (side, id) => {
      const n = st.n[side][id] || 0;
      if (!n) return '<td class="nil">—</td>';
      const list = state.ships.filter(s => s.side === side && s.def.id === id);
      const lost = list.filter(s => s.dead && !s.fled).length;
      const fled = list.filter(s => s.fled).length;
      return `<td><b class="${lost ? 'lost' : ''}">${lost}</b> из ${n}${fled ? ` <i title="ушли в гипер">⇢${fled}</i>` : ''}</td>`;
    };
    const rows = ids.map(id => `<tr><th>${word(id)}</th>${cell(P, id)}${cell(E, id)}</tr>`);
    if (st.sqUp[P] || st.sqUp[E]) {
      const sq = side => (st.sqUp[side] ? `<td><b class="${st.sqLost[side] ? 'lost' : ''}">${st.sqLost[side]}</b> из ${st.sqUp[side]}</td>` : '<td class="nil">—</td>');
      rows.push(`<tr><th>Звенья</th>${sq(P)}${sq(E)}</tr>`);
    }
    const k = n => (n >= 1000 ? `${(n / 1000).toFixed(1).replace('.', ',')} тыс.` : `${Math.round(n)}`);
    const best = side => {
      let b = null;
      for (const s of state.ships) {
        if (s.side !== side || !(s.dealt > 0)) continue;
        if (!b || s.dealt > b.dealt) b = { name: shortName(s), what: lowFirst(classWord(s)), dealt: s.dealt, kills: s.kills };
      }
      for (const [role, a] of Object.entries(st.air[side])) {
        if (!b || a.dealt > b.dealt) b = { name: a.name, what: ROLE_PL[role], dealt: a.dealt, kills: a.kills };
      }
      return b ? `${b.what} ${b.name} — ${k(b.dealt)} урона${b.kills ? `, добил ${b.kills}` : ''}` : 'никто не попал';
    };
    const mm = Math.floor(state.time / 60), ss = Math.floor(state.time % 60);
    return `<div class="end-stats">
      <div class="end-time">Бой длился ${mm}:${String(ss).padStart(2, '0')}</div>
      <table class="end-loss"><tr><th>Потери</th><th class="mine">Свои · ${sides[P].faction.short}</th><th class="foe">Противник · ${sides[E].faction.short}</th></tr>
        ${rows.join('')}</table>
      <div class="end-best"><b>Больше всех урона</b><span class="mine">у нас: ${best(P)}</span><span class="foe">у противника: ${best(E)}</span>
        ${st.planet > 0 ? `<span>с планеты по ${state.gun && state.gun.side === P ? 'нам' : 'противнику'}: ${k(st.planet)}</span>` : ''}</div>
    </div>`;
  }
  const ROLE_PL = { interceptor: 'перехватчики', fighter: 'истребители', bomber: 'бомбардировщики' };

  /* Бой кончается, когда одна из сторон ушла с орбиты: погибла или
     ушла в гипер вся. Отход — это не кнопка «конец боя», а накачка
     гипера под огнём; уход носителя отправляет в отход весь его флот
     (C17). */
  function checkEnd() {
    if (ended) return;
    const P = state.playerSide, E = enemyOf(P);
    const pOut = sideOut(P), eOut = sideOut(E);
    if (!pOut && !eOut) return;
    /* «Отход» — только когда флот действительно отходил: по кнопке, за
       ушедшим носителем или ушёл в гипер весь, не потеряв ни корабля.
       Флагман, ушедший сам при 20% прочности, пока остальных добивали, —
       это разгром, а не отход: раньше такой бой назывался «Отходом»
       почти всегда. На кампанию надпись не влияет — она в обоих случаях
       считает уцелевших одинаково. */
    if (pOut) {
      const lost = state.ships.some(s => s.dead && !s.fled && s.side === P && !s.station);
      finish(state.jumped[P].length && (state.retreat[P] || !lost) ? 'retreat' : 'defeat');
    } else finish('victory');
  }

  // ── ЦИКЛ ─────────────────────────────────────────────────
  /* Шаг самого боя — без камеры, подписей и панелей. Отдельно от update
     ради замеров: стенд гоняет бой шагами по 1/30 с (`simTest`), не рисуя
     ничего, и минута игрового времени проходит за секунды, а не за
     полчаса программного рендера. Логика при этом та же, что в игре. */
  function simStep(dt) {
    state.time += dt;
    updateEcm(dt);
    updateGroundGun(dt);
    updateFar();
    updateExposure();
    for (const sd of ['attacker', 'defender']) {
      const at = state.reinforceAt[sd];
      if (at && state.time >= at) arriveReinforcements(sd);
    }
    // ИИ тоже зовёт резерв, когда ему становится туго
    const aiSide = enemyOf(state.playerSide);
    if (state.reserve[aiSide] && state.reserve[aiSide].length && !state.reinforceAt[aiSide]) {
      const mine = state.ships.filter(x => !x.dead && x.side === aiSide).length;
      const foes = state.ships.filter(x => !x.dead && x.side !== aiSide).length;
      if (mine < foes) callReinforcements(aiSide);
    }
    updateAI(dt);
    for (const s of state.ships) if (!s.dead) updateShip(s, dt);
    for (const c of state.craft) if (!c.dead) updateCraft(c, dt);
    for (const p of state.proj) if (!p.dead) updateProjectile(p, dt);

    for (const s of state.ships) {
      if (s.dead || !s.hangar) continue;
      s.hangar.rebuild = s.hangar.rebuild.filter(t => {
        if (state.time >= t) { s.hangar.free = Math.min(s.hangar.bays, s.hangar.free + 1); return false; }
        return true;
      });
      s.hangar.launched = s.hangar.launched.filter(sq => !sq.dead);
    }
    state.craft = state.craft.filter(c => !c.dead);
    state.proj = state.proj.filter(p => !p.dead);
    for (const sq of state.squads) {
      if (sq.dead) continue;
      if (!sq.craft.length) { killSquad(sq); continue; }
      sq.pos.set(0, 0, 0);
      for (const c of sq.craft) sq.pos.add(c.pos);
      sq.pos.divideScalar(sq.craft.length);
      if (sq.target && (sq.target.dead || unseen(sq.target))) sq.target = null;
    }
    state.squads = state.squads.filter(s => !s.dead);
    checkTeeth();
    checkEnd();
  }

  /* КАМЕРА НЕ ВХОДИТ В КОРПУС (P5). Колесом можно было приблизиться
     внутрь корабля — на экране оставались огромные плоские грани.
     Ближний предел — не одно число на всех: камера стоит на луче от
     точки взгляда, и если этот луч на нынешнем расстоянии проходит
     через корпус (шар в 0,6 длины корабля), расстояние отодвигается
     к его краю. У корабля в центре это и есть «ближе нельзя», а
     мелкий корвет разрешает подъехать ближе, чем флагман */
  const _camDir = new THREE.Vector3(), _oc = new THREE.Vector3();
  function keepOutOfHulls() {
    const cp = Math.cos(tcam.pitch);
    _camDir.set(Math.sin(tcam.yaw) * cp, Math.sin(tcam.pitch), Math.cos(tcam.yaw) * cp);
    let d = tcam.dist;
    for (let pass = 0; pass < 2; pass++) {
      for (const s of state.ships) {
        if (s.dead || !s.obj.visible) continue;
        const R = Math.max(s.hull, (s.len || s.radius * 6) * 0.6);
        _oc.subVectors(tcam.target, s.pos);
        const b = _oc.dot(_camDir), c = _oc.lengthSq() - R * R;
        const disc = b * b - c;
        if (disc <= 0) continue;
        const q = Math.sqrt(disc), d0 = -b - q, d1 = -b + q;
        if (d > d0 && d < d1) d = d1;
      }
    }
    // Предел, а не новое расстояние: корабль ушёл — камера вернулась
    // туда, куда её поставил игрок
    tcam.floor = d > tcam.dist ? Math.min(d, tcam.maxDist) : 0;
  }

  function update(rawDt) {
    keepOutOfHulls();
    tcam.update(rawDt);
    // Миникарта рисуется и на паузе: на ней как раз и планируют
    drawMinimap(rawDt);
    // После итога бой стоит насовсем, что бы ни нажали (C65)
    const dt = (state.paused || ended) ? 0 : Math.min(rawDt, 0.05) * state.speed;
    if (dt > 0) simStep(dt);

    fx.update(rawDt);
    fadeFeed();
    // Подсказка по управлению гаснет через 16 ИГРОВЫХ секунд (P5)
    if (state.time > 16 && !hintOut) { hintOut = true; $('hint').classList.add('out'); }
    planet.rotation.y += rawDt * 0.004;
    if (planet.userData.clouds) planet.userData.clouds.rotation.y += rawDt * 0.0022;
    refreshReinforce();
    hintReserve();
    if (reinfBtn.disabled) reinfBtn.classList.remove('nudge');
    refreshRetreat();
    if (fx.shake > 0.001) {
      const s = fx.shake * 3.2;
      tcam.cam.position.x += rnd(-s, s);
      tcam.cam.position.y += rnd(-s, s);
    }

    updateVortexes(dt || rawDt * 0.001, state.time);
    headlight.position.copy(tcam.cam.position);
    hoverTick -= rawDt;
    if (hoverTick <= 0) { hoverTick = 0.1; updateHover(); }
    updateMarkers();
    updateDomes();
    updateSelVisuals();
    updateOrders();
    warmTick();
    /* Панель выделенного пересобираем раз в треть секунды: строка
       «что делает» должна жить, а каждый кадр перекладывать DOM
       незачем. */
    /* И при ПУСТОМ выделении тоже: destroy() и completeJump() сами
       вычищают погибшего из выделения, и проверка «выделен мёртвый»
       его уже не находит — панель застывала на погибшем корабле
       («прочность 4030/4030») с кнопками, которые ничего не делают.
       Пустое выделение обходится дёшево: setHtml и ключ без изменений
       DOM не трогают. */
    selTick -= rawDt;
    if (state.selDirty) { state.selDirty = false; refreshSel(); }
    if (selTick <= 0) { selTick = 0.34; refreshSel(); refreshRoster(); measureTop(); }

    let pa = 0, pd = 0, na = 0, nd = 0;
    for (const s of state.ships) {
      if (s.dead) continue;
      if (s.side === 'attacker') { pa += s.hp; na++; } else { pd += s.hp; nd++; }
    }
    const max = Math.max(1, pa + pd);
    const ab = $('atk-bar'), db = $('def-bar');
    ab.style.width = (pa / max * 100) + '%';
    db.style.width = (pd / max * 100) + '%';
    $('atk-num').textContent = na;
    $('def-num').textContent = nd;

    // Часы давления земли: сколько осталось до залпа с планеты
    if (state.gun) {
      const left = Math.max(0, state.gun.next - state.time);
      const el = $('gunclock');
      $('gun-time').textContent = left < 1 ? 'залп' : Math.ceil(left) + ' с';
      el.classList.toggle('warn', left <= state.gun.def.warn);
    }

    /* Выделенный противник ушёл в маскировку — снимаем выделение:
       иначе панель продолжала бы показывать его прочность (C18) */
    if (state.selection.some(s => s.dead || (s.side !== state.playerSide && unseen(s)))) {
      state.selection = state.selection.filter(s => !s.dead && (s.side === state.playerSide || !unseen(s)));
      refreshSel();
    }
  }

  function dispose() {
    /* Купола и воронки НЕ снимаем со сцены до disposeScene: снятые, они
       не попадали в обход, и их геометрия с материалами не освобождалась
       (C66) */
    removeEventListener('keydown', onKey);
    removeEventListener('resize', measureTop);
    sound.setListener(null);
    tcam.dispose();
    controls.dispose();
    hud.remove();
    disposeScene(scene);
  }

  /* СТАРТОВАЯ КАМЕРА (C76): свой флот в середине кадра, противник —
     у верхнего края, то есть сразу видно и «что у меня», и «откуда
     идут». Раньше точка взгляда стояла на 330 единиц впереди флота
     с расстояния 1250 (а «ближе, 780» в конструкторе этим перебивалось):
     флот лежал в нижней трети, и на 1366×768 его хвост уходил под
     ростер и панель команд — щелчок попадал в плашку, а не в корабль.
     Замер на «Генеральном» Плэктора (34 корабля) при точке на 60
     впереди центра флота и расстоянии 1100: свои — 0,45…0,64 высоты
     на 1366 и 1920, противник — 0,11…0,15, ни один свой не под HUD. */
  tcam.yaw = state.playerSide === 'attacker' ? 0 : Math.PI;
  {
    /* Обороняется одна станция (ИИ напал на систему, где флота нет,
       а станция есть) — смотрим на неё. Без этого центр оставался в
       середине поля, станция проецировалась на 11 800 точек ниже экрана,
       и единственное своё на орбите было не найти, кроме как миникартой */
    let own = state.ships.filter(s => s.side === state.playerSide && !s.station);
    if (!own.length) own = state.ships.filter(s => s.side === state.playerSide);
    const c = new THREE.Vector3();
    for (const s of own) c.add(s.pos);
    if (own.length) c.divideScalar(own.length);
    c.y = 0;
    c.z += (sides[state.playerSide].sign > 0 ? -1 : 1) * 60;
    tcam.focus(c, 1100);
  }
  tcam.apply(1, true);

  // Состояние боя наружу — по нему автотесты проверяют скрытность,
  // гипер и боезапас. На игру не влияет, читать можно из консоли.
  /* Наружу — для автотестов: свести флоты в упор, навести камеру,
     отправить корабль в гипер. Всё это в бою делается руками и
     минутами, а проверять эффекты надо кадрами. */
  if (typeof window !== 'undefined') {
    window.__sp = state;
    state.camTest = (x, y, z, dist) => {
      tcam.focus(new THREE.Vector3(x, y, z), dist);
      tcam.apply(1, true);
    };
    state.closeInTest = (gap = 260) => {
      const a = state.ships.filter(s => !s.dead && s.side === 'attacker');
      const d = state.ships.filter(s => !s.dead && s.side === 'defender');
      // участок «Охраны» — туда же: иначе корабли бросили бы бой и ушли к прежней точке
      a.forEach((s, i) => { s.pos.set((i % 4 - 1.5) * 60, rnd(-20, 20), gap / 2); s.moveTo = null; s.anchor.copy(s.pos); s.guardOf = null; });
      d.forEach((s, i) => { s.pos.set((i % 4 - 1.5) * 60, rnd(-20, 20), -gap / 2); s.moveTo = null; s.anchor.copy(s.pos); s.guardOf = null; });
      return { attacker: a.length, defender: d.length };
    };
    state.jumpTest = () => {
      const s = state.ships.find(x => !x.dead && x.side === state.playerSide && !x.hyper);
      if (s) beginJump(s);
      return s ? s.def.name : null;
    };
    // Где корабль на экране — автотест кликает по нему настоящей мышью
    state.screenTest = e => {
      const r = viewport.canvas.getBoundingClientRect();
      const p = screenOf(e.pos, tcam.cam, viewport.w, viewport.h);
      return { x: r.left + p.x, y: r.top + p.y, z: p.z };
    };
    // Мир в точке экрана — куда должен лечь приказ правой кнопкой
    state.worldTest = (x, y) => controls.worldAt(x, y);
    /* Что ловит луч в точке экрана (C29): `pick` — кого выберет игра,
       `first` — самое первое попадание луча, хоть бы и по свечению
       соседа (им стенд убеждается, что подстроенная ловушка настоящая),
       `cam` — где стоит камера. */
    state.pickTest = (x, y) => {
      const ent = controls.pick(x, y);
      const hits = controls.ray.intersectObjects(pickMeshes(), true);
      const h = hits[0];
      let o = h && h.object;
      while (o && !o.userData.entity) o = o.parent;
      const c = tcam.cam.position;
      return {
        pick: ent ? ent.uid : null,
        first: h ? { uid: o && o.userData.entity.uid, effect: effectHit(h.object), type: h.object.type } : null,
        cam: { x: c.x, y: c.y, z: c.z },
      };
    };
    // Камера: куда смотрит и где стоит — проверять протяжку, край, колесо
    state.camInfo = () => ({
      x: tcam.target.x, y: tcam.target.y, z: tcam.target.z, dist: tcam.dist,
      sdist: tcam.sdist, yaw: tcam.yaw, pitch: tcam.pitch,
      sx: tcam.smooth.x, sz: tcam.smooth.z,
    });
    // Что под курсором и какой курсор (C74), ждёт ли «A» щелчка
    state.inputTest = () => ({
      hover: hoverEnt ? hoverEnt.uid : null, cursor: controls._cur, pending,
      groups: Object.fromEntries(Object.entries(groups).map(([k, v]) => [k, v.map(e => e.uid)])),
    });
    // Приказ выделенным — тот же, что даёт ПКМ (цель или точка мира)
    state.orderTest = (ent, world) => issueOrder(ent, world || null);
    // Уничтожить корабль сразу — проверять, что остаётся после гибели
    state.killTest = e => destroy(e);
    state.retreatTest = side => orderRetreat(side || state.playerSide);
    // Поднять звено с носителя — как кнопка, но и у противника (C99)
    state.launchTest = (c, role) => launchSquadron(c, role || 'interceptor');
    // Пул эффектов: сколько занято (busy) — мерить, не переполнен ли
    state.fxTest = () => fx;
    /* Прогнать бой без отрисовки: sec игровых секунд шагами dt, каждые
       every секунд — cb(state) (так стенд «играет» за человека). Замер
       темпа, торможения и длины боя — этим, а не кадрами SwiftShader */
    state.simTest = (sec, dt = 1 / 30, every = 0, cb = null) => {
      const t1 = state.time + sec;
      let next = state.time + every;
      while (!ended && state.time < t1) {
        simStep(dt);
        fx.update(dt);
        if (cb && every && state.time >= next) { next += every; cb(state); }
      }
      return { time: state.time, ended };
    };
    // Атака с ходу выделенными — то же, что A и щелчок
    state.amoveTest = world => amoveSelected(world);
    // Вызвать резерв — то же, что B
    state.reinforceTest = () => callReinforcements(state.playerSide);
    // Тактика кораблям — то же, что кнопки «Держать» / «Охрана» / «Охота»
    state.stanceTest = (list, id) => setStance(list, id);
    // Сколько кругов дальности видно у выделенных
    state.rangeTest = () => rangeRings.filter(r => r.visible).length;
    // Строка «чем занят» из панели выделенного — для корабля e
    state.doingTest = e => doingOf(e);
    // Сколько шейдеров собрано (P5: первое «Весь флот» не собирает новых)
    state.programsTest = names => {
      const l = viewport.renderer.info.programs || [];
      return names ? l.map(p => `${p.name}|${p.cacheKey}`) : l.length;
    };
    // Где камера (P5: колесом нельзя въехать в корпус)
    state.camPosTest = () => tcam.cam.position.clone();
    // Может ли сторона нанести урон (P5)
    state.canHurtTest = side => canHurt(side || state.playerSide);
    // Строка в ленту — как событие боя (P5: кликабельная уходит последней)
    state.feedTest = (text, kind) => feed(text, kind);
  }
  return { scene, camera: tcam.cam, update, dispose, state };
}

// ─────────────────────────────────────────────────────────────
// БЫСТРЫЙ РАСЧЁТ — когда бой играть не хочется
// ─────────────────────────────────────────────────────────────

export function autoResolveSpace(attacker, defender) {
  // bonus — фора ИИ по сложности, чтобы автобой не обходил её стороной
  const power = (side, station) => {
    let dps = 0, hp = 0, air = 0, pd = 0;
    for (const item of side.ships || []) {
      const def = shipDef(side.faction, item.id);
      if (!def) continue;
      hp += def.hp * item.count / (1 - def.armor);
      for (const g of def.guns || []) dps += (g.dmg * (g.salvo || 1)) / g.cd * item.count;
      if (def.pd) pd += def.pd.dmg / def.pd.cd * def.pd.count * item.count;
      if (def.hangar) air += def.hangar * item.count;
    }
    if (station) {
      hp += STATION.hp / (1 - STATION.armor);
      dps += STATION.guns[0].dmg / STATION.guns[0].cd;
      pd += 60;
    }
    const b = side.bonus || 1;
    return { dps: dps * b, hp: hp * b, air, pd };
  };
  const A = power(attacker, false), D = power(defender, defender.station);
  const aDps = A.dps + Math.max(0, A.air * 130 - D.pd * 1.6);
  const dDps = D.dps + Math.max(0, D.air * 130 - A.pd * 1.6);
  const aTime = D.hp / Math.max(1, aDps);
  const dTime = A.hp / Math.max(1, dDps);
  const attackerWins = aTime < dTime;
  const ratio = attackerWins ? aTime / Math.max(0.01, dTime) : dTime / Math.max(0.01, aTime);
  const keep = 1 - clamp(ratio, 0.1, 0.95);

  const trim = side => {
    const out = [];
    for (const item of side.ships || []) {
      const n = Math.round(item.count * keep);
      if (n > 0) out.push({ id: item.id, count: n });
    }
    return out;
  };
  return {
    result: attackerWins ? 'attacker' : 'defender',
    attacker: attackerWins ? trim(attacker) : [],
    defender: attackerWins ? [] : trim(defender),
  };
}
