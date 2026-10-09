/* КОСМИЧЕСКИЙ БОЙ — по правилам Homeplanet.

   Инерция. У корабля есть вектор скорости; двигатель даёт ускорение,
   а не скорость. Линкор разгоняется полминуты и столько же тормозит,
   и всё это время летит туда, куда его несёт. Разворот корпуса от
   вектора не зависит — корабль скользит боком, держа цель в прицеле.

   Главный калибр. Раз в 9–17 секунд, зато сносит цель почти целиком.
   Перед выстрелом видна накачка. По истребителям не наводится вообще.

   ПВО работает само и только по мелочи. Авианосец почти безоружен,
   его сила — три типа машин: перехватчик против авиации, истребитель
   по всему средне, бомбардировщик против крупных кораблей. */

import {
  THREE, TacticalCamera, Controls, Fx, starfield, screenOf, ringMesh,
  clamp, lerp, rnd, disposeScene, IS_TOUCH, createMinimap,
} from './engine.js';
import {
  buildShip, buildStrike, buildTorpedo, buildPlanet, buildNebula, buildHyperVortex, buildEcmDome,
  planetRings,
} from './models.js';
import { nebulaTexture } from './textures.js';
import {
  FACTIONS, STRIKE, STRIKE_ROLES, SPACE_DMG, SQUAD_SIZE_OF, STATION, STEALTH, HYPER,
  ECM, ECM_OF, ORBITAL_DEFENCE_OF,
  dmgMult, shipDef, diffOf,
} from './data.js';

const UP = new THREE.Vector3(0, 1, 0);
const ALT_UP = new THREE.Vector3(0, 0, 1);
const ZERO = new THREE.Vector3();
const _m4 = new THREE.Matrix4();
const _q = new THREE.Quaternion();
const _v = new THREE.Vector3();
const _v2 = new THREE.Vector3();
const _v3 = new THREE.Vector3();

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
    // Ближе к бою: с полутора тысяч единиц флот читался россыпью точек
    dist: 780, maxDist: 3400, minDist: 45, pitch: 0.52, yaw: 0,
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
      damage(t, d.dmg, 'heavy');
      t.ionUntil = state.time + d.disable;
      toast(`${d.name}: ${t.def.name} обездвижен`);

    } else if (d.kind === 'nuke') {
      // Ядерная: площадь по месту наводки — кто ушёл, тот цел
      const at = g.aim || list[0].pos;
      shoot(at, 5);
      fx.explosion(at, d.radius * 0.5, d.color);
      let hit = 0;
      for (const e of list) {
        const dist = e.pos.distanceTo(at);
        if (dist > d.radius) continue;
        damage(e, d.dmg * (1 - dist / d.radius), 'heavy');
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

  // ── СОЗДАНИЕ ─────────────────────────────────────────────

  function spawnShip(sideId, def, pos) {
    const side = sides[sideId];
    const obj = buildShip(def, side.faction);
    obj.position.copy(pos);
    scene.add(obj);

    const dir = new THREE.Vector3(0, 0, side.sign > 0 ? -1 : 1);
    const e = {
      uid: uid++, kind: 'ship', side: sideId, faction: side.faction, def,
      obj, pos: obj.position, dir, vel: new THREE.Vector3(),
      hp: def.hp, maxHp: def.hp, armor: def.armor, cls: def.cls,
      radius: def.radius, dead: false,
      moveTo: null, target: null, forced: null, retarget: rnd(0, 1),
      guns: (def.guns || []).map((g, i) => ({ def: g, idx: i, cd: rnd(0, g.cd), chargeFx: 0 })),
      pdCd: def.pd ? new Array(def.pd.count).fill(0).map(() => rnd(0, 0.4)) : [],
      hangar: null, station: !!def.station, thrustNow: 0,
      stealth: !!def.stealth, revealUntil: 0, exposed: false,
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
      obj, pos: obj.position, target, dmg, weapon, speed,
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
          side: e.side, mode: e.ecm.mode, prof: E,
        });
      }
      if (e.dome) {
        /* Купол скрытого противника не рисуется: висящий над пустотой
           цилиндр выдавал невидимый флот Рииза (C67). Глушит он при
           этом по-прежнему — помехи от невидимки и есть его сила. */
        e.dome.visible = e.ecm.power > 0.02 && !(e.side !== state.playerSide && hidden(e));
        // Блин лежит в плоскости боя, а не крутится вместе с корпусом
        const emit = e.obj.userData.emitter;
        const ey = emit ? emit.y * 1.25 : -e.radius;
        e.dome.position.set(e.pos.x, e.pos.y + ey, e.pos.z);
        e.dome.userData.set(state.time, e.ecm.power * 0.55,
          e.ecm.mode === 'shield' ? 0xcfe8ff : e.faction.color, -ey);
      }
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
    scene.remove(e.obj);
    removeDome(e);
    state.jumped[e.side].push(e.def.id);
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
      dropIn(state.playerSide, e.ships);
      toast(`${e.name}: подмога вышла из гипера`);
      refreshFar();
    }
  }

  function arriveReinforcements(side) {
    const list = state.reserve[side];
    state.reserve[side] = [];
    state.reinforceAt[side] = 0;
    dropIn(side, list);
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
    for (const item of list) {
      const def = shipDef(sides[side].faction.id, item.id);
      if (!def) continue;
      for (let n = 0; n < item.count; n++, i++) {
        const pos = new THREE.Vector3((i % 5 - 2) * 90 + rnd(-15, 15), rnd(-40, 40),
                                      baseZ + sign * Math.floor(i / 5) * 80);
        const sh = spawnShip(side, def, pos);
        // Воронка раскрывается позади корабля — он из неё вылетает
        const back = new THREE.Vector3(0, 0, sign > 0 ? 1 : -1);
        openVortex(pos.clone().addScaledVector(back, def.radius * 2.2),
                   back.clone().negate(), def.radius * 2.4, 'in');
        // Выходит на большой скорости и гасит её маршевыми — видно по соплам
        sh.vel.set(0, 0, -sign * def.maxSpeed * 2.6);
        sh.moveTo = new THREE.Vector3(pos.x * 0.4, 0, sign * 120);
        fx.flash(pos, def.radius * 5, 0xdfefff, 0.6);
        // Нитка позади: корабль будто вытянулся из точки выхода
        fx.beam(pos.clone().addScaledVector(back, def.radius * 70), pos,
          { color: 0xbfe0ff, width: def.radius * 0.4, life: 0.3 });
        fx.ring(pos, def.radius * 1.5, def.radius * 12, 0x9fd0ff, 0.6);
      }
    }
    fx.shake = Math.min(1, fx.shake + 0.3);
  }

  // ── УРОН ─────────────────────────────────────────────────

  function damage(target, amount, weapon) {
    /* Цель без собственной прочности (звено целиком — у него прочность
       у машин) урона не принимает: раньше это давало hp = NaN, звено
       становилось бессмертным, а флот стрелял в пустоту (C14) */
    if (!target || target.dead || typeof target.hp !== 'number') return;
    if (!(amount > 0)) return;
    const mult = dmgMult(SPACE_DMG, weapon, target.cls);
    if (mult <= 0) return;
    target.hp -= amount * mult * (1 - (target.armor || 0));
    if (target.hp <= 0) destroy(target);
  }

  function destroy(e) {
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
    }
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

  /* reach — во сколько дальностей главного калибра искать цель. Обычно
     1,8: корабль замечает врага загодя и идёт на сближение. «Держать
     позицию» (H) берёт только то, до чего орудие достаёт с места (1,0),
     иначе удержания не выйдет: найденную вдали цель он бы догонял. */
  function shipAcquire(e, reach = 1.8) {
    const foe = enemyOf(e.side);
    const gun = e.guns[0];
    if (!gun) return null;
    const range = gun.def.range;
    let best = null, bestScore = -Infinity;
    for (const s of state.ships) {
      if (s.dead || s.side !== foe || hidden(s)) continue;
      const d = s.pos.distanceTo(e.pos);
      if (d > range * reach) continue;
      const m = dmgMult(SPACE_DMG, gun.def.type, s.cls);
      if (m <= 0) continue;
      const score = m * 1000 - d + (1 - s.hp / s.maxHp) * 400 + (s.cls === 'carrier' ? 250 : 0);
      if (score > bestScore) { bestScore = score; best = s; }
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
  function thrustTo(e, desiredVel, dt, thrust) {
    // Выжженные ионным лучом двигатели не тянут вовсе: корабль
    // продолжает лететь по инерции, но управлять им нечем
    if (e.ionized) { e.thrustNow = 0; return; }
    _v.subVectors(desiredVel, e.vel);
    const need = _v.length();
    if (need < 1e-4) { e.thrustNow = 0; return; }
    _v.divideScalar(need);
    const align = Math.max(0, e.dir.dot(_v));
    const power = thrust * (0.3 + 0.7 * align);
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
      beginJump(e);
      if (e.side === state.playerSide) toast(`${e.def.name}: повреждения критические, уходим в гипер`);
      return;
    }
    e.retarget -= dt;
    // Цель ушла в маскировку — стрелять не по чему, приказ снят (C18)
    if (e.target && (e.target.dead || unseen(e.target))) e.target = null;
    if (e.forced && (e.forced.dead || unseen(e.forced))) e.forced = null;
    if (!e.target || e.retarget <= 0) {
      e.target = liveTarget(e, e.forced) || shipAcquire(e, e.hold ? 1.0 : 1.8);
      e.retarget = rnd(0.8, 1.6);
    }

    const def = e.def;

    if (!e.station) {
      // ── куда хотим лететь
      let desiredVel = null;
      const range0 = e.guns[0] ? e.guns[0].def.range : 300;
      /* Атака с ходу (A): идёт к точке, но встречного в 1,3 дальности
         не пропускает — останавливается и бьёт, а кончился враг —
         идёт дальше. Обычный приказ «идти» стреляет на ходу и не
         задерживается. */
      const fighting = e.amove && e.target && !e.target.dead &&
        e.pos.distanceTo(e.target.pos) < range0 * 1.3;
      const goal = e.moveTo || (e.amove && !fighting ? e.amove : null);
      if (goal) {
        _v.subVectors(goal, e.pos);
        const d = _v.length();
        if (d < 45) {
          if (e.moveTo) e.moveTo = null; else e.amove = null;
          desiredVel = ZERO;
        } else {
          // тормозной путь: v²/2a. Подходя к точке, гасим скорость заранее
          const brake = Math.sqrt(Math.max(0, 2 * def.thrust * Math.max(0, d - 40)));
          desiredVel = _v.divideScalar(d).multiplyScalar(Math.min(def.maxSpeed, brake)).clone();
        }
      } else if (e.target && e.hold && e.forced !== e.target) {
        /* «Держать позицию» (H): не преследует, только доворачивает
           корпус на цель — стрельба ниже, как всегда */
        desiredVel = ZERO;
      } else if (e.target) {
        /* Подход к цели. Раньше корабль болтало: чуть далеко — полный
           вперёд, чуть близко — полный назад, между ними — облёт
           боком. На экране это читалось как рой мечущихся точек,
           а не как флот.

           Теперь у дистанции широкая мёртвая зона: попал в неё —
           стоишь и стреляешь. Облетать по дуге позволено только
           эскорту, у которого это его манера боя; крейсер, носитель
           и флагман держат линию. */
        const d = e.pos.distanceTo(e.target.pos);
        const want = (e.guns[0] ? e.guns[0].def.range : 300) * 0.68;
        _v.subVectors(e.target.pos, e.pos);
        const dist = _v.length() || 1;
        _v.divideScalar(dist);
        const light = def.cls === 'escort';
        if (d > want * 1.08) {
          // подходим, но не влетаем: гасим ход заранее
          const brake = Math.sqrt(Math.max(0, 2 * def.thrust * (d - want)));
          desiredVel = _v.clone().multiplyScalar(Math.min(def.maxSpeed, brake));
        } else if (d < want * 0.55) {
          desiredVel = _v.clone().multiplyScalar(-def.maxSpeed * 0.5);
        } else if (light) {
          desiredVel = _v3.crossVectors(_v, UP).normalize().multiplyScalar(def.maxSpeed * 0.45).clone();
        } else {
          desiredVel = ZERO;      // дистанция та, что нужна: стоим и работаем
        }
      } else {
        desiredVel = ZERO;    // система стабилизации гасит дрейф
      }

      // расталкивание своих
      for (const o of state.ships) {
        if (o === e || o.dead || o.side !== e.side) continue;
        const dd = o.pos.distanceTo(e.pos);
        const min = (o.radius + e.radius) * 2.4;
        if (dd < min && dd > 0.01) {
          _v2.subVectors(e.pos, o.pos).divideScalar(dd).multiplyScalar((min - dd) / min * def.maxSpeed * 0.8);
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
        thrustTo(e, desiredVel, dt, def.thrust);
        if (e.vel.length() > def.maxSpeed * 1.25) e.vel.setLength(def.maxSpeed * 1.25);
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
      const jam = jamProfile(e.pos, e.side);
      if (jam && d > jam.lockRange) continue;
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
        damage(t, pd.dmg * pdMult, 'pd');
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
    const from = muzzleWorld(e, g.idx);
    const color = e.side === state.playerSide ? 0x7fd8ff : 0xff8f5a;
    if (g.def.type === 'missile') {
      for (let i = 0; i < (g.def.salvo || 1); i++) {
        const p = spawnProjectile(e, t, g.def.dmg * aiMul(e.side), 'missile', 130, 26);
        p.dir.add(_v.set(rnd(-1, 1), rnd(-1, 1), rnd(-1, 1)).multiplyScalar(g.def.spread || 0.05)).normalize();
        p.wobble = rnd(0, 6.28);
      }
      // Старт ракет: пламя из труб и клубы отработанного топлива
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
    fx.laser(from, t.pos, { color, width: w, life: 0.5 });
    fx.delay(0.06, () => fx.beam(from, t.pos, { color, width: w * 0.7, life: 0.45 }));
    fx.sparks(t.pos, 8, 0xfff0c0, 34, false);
    _v.subVectors(from, t.pos).normalize();
    // Одним вызовом, а не четырьмя по одной: так пул может их проредить
    fx.debris(_v2.copy(t.pos).addScaledVector(_v, 2), 4, 0x8a7a66, 26, 0);
    fx.shake = Math.min(1, fx.shake + 0.14);
    damage(t, g.def.dmg * aiMul(e.side), g.def.type);
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
          damage(t, c.def.dmg * aiMul(c.side), c.def.weapon);
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
      damage(p.target, p.dmg, p.weapon);
      destroy(p);
    }
  }

  // ── ИИ ───────────────────────────────────────────────────
  const ai = { side: enemyOf(state.playerSide), next: 3 * DIFF.tempo };
  function updateAI(dt) {
    ai.next -= dt;
    if (ai.next > 0) return;
    ai.next = rnd(4, 7) * DIFF.tempo;
    const mine = state.ships.filter(s => !s.dead && s.side === ai.side);
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
    if (!foes.length) return;     // никого не видно — держим строй

    const centerFoe = new THREE.Vector3();
    for (const f of foes) centerFoe.add(f.pos);
    centerFoe.divideScalar(foes.length);
    for (const s of mine) {
      if (s.station) continue;
      if (s.cls === 'carrier') {
        _v.subVectors(s.pos, centerFoe).normalize().multiplyScalar(700);
        s.moveTo = centerFoe.clone().add(_v);
      } else if (Math.random() < 0.7) {
        s.moveTo = centerFoe.clone().add(new THREE.Vector3(rnd(-170, 170), rnd(-70, 70), rnd(-170, 170)));
      }
    }
    const juicy = foes.find(f => f.cls === 'carrier') || foes.find(f => f.cls === 'capital');
    // Безоружным (носитель, РЭБ) приказ «атаковать» — это путь в упор (C100)
    if (juicy) for (const s of mine) if (s.guns.length && Math.random() < 0.45) s.forced = juicy;
  }

  // ── HUD ──────────────────────────────────────────────────
  const hud = document.createElement('div');
  hud.className = 'hud hud-space';
  hud.innerHTML = `
    <div class="topbar">
      <button class="menu-btn" data-role="menu" title="Меню · Esc" aria-label="Меню">☰</button>
      <div class="strength">
        <div class="ss-row"><i class="dot" data-side="attacker"></i><b data-role="atk-name"></b>
          <span class="bar"><i data-role="atk-bar"></i></span><em data-role="atk-num"></em></div>
        <div class="ss-row"><i class="dot" data-side="defender"></i><b data-role="def-name"></b>
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
        <button data-role="drift" title="Гасители инерции у выделенных: корабль скользит по вектору, корпус свободно наводится · D"><span data-role="drift-t">Дрифт</span><kbd class="hk">D</kbd></button>
        <button data-role="reinforce" title="Вызвать второй эшелон из гипера · B"><span data-role="reinf-t"></span><kbd class="hk">B</kbd></button>
        <button data-role="retreat" class="danger danger-gap" title="Весь флот копит гипер и уходит — спросит подтверждение">Отход</button>
      </div>
    </div>

    <div class="markers" data-role="markers"></div>

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
  /* Одинаковые сообщения склеиваются в одно с числом («×3»), а на экране
     их не больше четырёх: лавина плашек с размытием фона роняла кадры
     до слайд-шоу и закрывала бой (C8). */
  const TOAST_MAX = 4;
  function toast(text) {
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
        color: mine ? '#8fffc8' : '#ff6b5a' });
    }
    for (const sq of state.squads) {
      if (sq.dead) continue;
      // Скрытое звено противника не выдаём и здесь (C18)
      if (sq.side !== state.playerSide && unseen(sq)) continue;
      dots.push({ x: sq.pos.x, z: sq.pos.z, r: 2,
        color: sq.side === state.playerSide ? '#5ce0a0' : '#e05a4a' });
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

  hud.querySelectorAll('.dot').forEach(d => { d.style.background = sides[d.dataset.side].faction.colorCss; });
  $('atk-name').textContent = sides.attacker.faction.tag;
  $('def-name').textContent = sides.defender.faction.tag;
  $('banner').textContent = config.title || 'Бой на орбите';
  if (state.gun) {
    $('gunclock').hidden = false;
    $('gun-name').textContent = state.gun.def.short;
    $('gunclock').title = state.gun.def.desc;
  }
  $('hint').innerHTML = IS_TOUCH
    ? 'Касание по своему кораблю — выбрать · по врагу — атаковать · по пустоте — идти · тянуть — двигать карту · щипок — приближение · долгое нажатие — рамка'
    : 'ПКМ — приказ · средняя кнопка — карта · A — атака с ходу · S — стоп · H — держать · Esc — меню';

  hud.querySelectorAll('[data-speed]').forEach(b => {
    b.onclick = () => {
      const v = +b.dataset.speed;
      state.paused = v === 0;
      if (v) state.speed = v;
      hud.querySelectorAll('[data-speed]').forEach(x => x.classList.toggle('on', +x.dataset.speed === v));
    };
  });
  /* Дрифт включается на выделенные корабли — кнопкой и клавишей D */
  function toggleDrift() {
    const mine = state.selection.filter(e => !e.dead && e.side === state.playerSide && !e.station);
    if (!mine.length) { toast('Сначала выбери корабли'); return; }
    const on = !mine.every(e => e.drift);
    for (const e of mine) {
      e.drift = on;
      if (on) fx.ring(e.pos, e.radius * 1.5, e.radius * 5, 0xffc27a, 0.5);
    }
    $('drift').classList.toggle('on', on);
    toast(on ? 'Гасители инерции отключены: корабль скользит по вектору'
             : 'Гасители инерции включены');
  }
  $('drift').onclick = toggleDrift;

  /* «Отход» — гипер ВСЕГО флота с накачкой, а не мгновенный выход из
     боя (C17). Второе нажатие отменяет отход, пока носитель не ушёл.
     Начало отхода — через подтверждение (C34): кнопка стоит в одной
     полосе с кнопками скорости, и промах мимо «4×» проигрывал бой.
     Защитнику сказано прямо, что орбита останется за противником. */
  const retreatBtn = $('retreat');
  retreatBtn.onclick = () => {
    if (ended) return;
    const P = state.playerSide;
    if (state.retreat[P]) {
      if (state.conceded === P) { toast('Носитель ушёл — отход уже не отменить'); return; }
      cancelRetreat(P);
      toast('Отход отменён — флот остаётся в бою');
      refreshRetreat();
      refreshSel();
      return;
    }
    const doIt = () => {
      if (ended || state.retreat[P]) return;
      const n = orderRetreat(P);
      const t = Math.max(0, ...state.ships.filter(s => !s.dead && s.side === P && s.hyper).map(s => s.hyper.left));
      toast(n ? `Отход: флот копит гипер, ${Math.ceil(t)} с — всё это время беззащитен`
              : 'Отход: уходить некому');
      refreshRetreat();
      refreshSel();
    };
    if (!ctx.confirm) { doIt(); return; }
    ctx.confirm({
      title: P === 'defender' ? 'Отход — сдать орбиту?' : 'Отход из боя?',
      text: 'Весь флот копит гипер и всё это время беззащитен. Домой вернутся только те, кто успеет уйти' +
        (P === 'defender' ? '; орбита останется за противником.' : '; бой будет проигран.') +
        ' Пока носитель не ушёл, отход можно отменить той же кнопкой.',
      yes: 'Отходить', no: 'Остаться в бою',
    }, doIt);
  };
  function refreshRetreat() {
    const on = !!state.retreat[state.playerSide];
    const txt = on ? (state.conceded === state.playerSide ? 'Отходим…' : 'Отменить отход') : 'Отход';
    if (retreatBtn.textContent !== txt) retreatBtn.textContent = txt;
    retreatBtn.classList.toggle('on', on);
  }

  const reinfBtn = $('reinforce');
  const reinfTxt = $('reinf-t');
  const myReserve = () => state.reserve[state.playerSide];
  function refreshReinforce() {
    const n = (myReserve() || []).reduce((a, x) => a + x.count, 0);
    const pending = state.reinforceAt[state.playerSide];
    let txt, off = true;
    // флот отходит: резерв в бой уже не идёт и вернётся домой целым
    if (state.retreat[state.playerSide]) txt = n ? `Резерв дома (${n})` : 'Резерва нет';
    else if (pending) txt = `Гипер ${Math.max(0, Math.ceil(pending - state.time))} с`;
    else if (!n) txt = 'Резерва нет';
    else { txt = `Подкрепление (${n})`; off = false; }
    // кнопка обновляется каждый кадр — трогаем DOM, только если что-то поменялось
    if (reinfTxt.textContent !== txt) reinfTxt.textContent = txt;
    if (reinfBtn.disabled !== off) reinfBtn.disabled = off;
  }
  reinfBtn.onclick = () => {
    if (reinfBtn.disabled) return;
    if (callReinforcements(state.playerSide)) {
      toast('Резерв вызван — выход из гипера через полминуты');
      refreshReinforce();
    }
  };
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

  // маркеры кораблей поверх канваса
  const markerPool = [];
  /* Где на экране стоят подписи (C29). Сами метки прозрачны для
     указателя — иначе они заслоняли бы поле, — поэтому попадание по
     подписи считаем здесь: игрок целится в название врага, а раньше
     такой ПКМ уходил мимо модели и отправлял флот в упор к противнику. */
  const labelHits = [];
  function updateMarkers() {
    const w = viewport.w, h = viewport.h;
    let i = 0;
    labelHits.length = 0;
    for (const s of state.ships) {
      if (s.dead) continue;
      let d = markerPool[i];
      if (!d) {
        d = document.createElement('div');
        d.className = 'marker';
        d.innerHTML = '<span class="mk-name"></span><span class="mk-bar"><i></i></span>';
        markers.appendChild(d);
        markerPool[i] = d;
      }
      i++;
      const cloak = hidden(s);
      // Скрытый противник не рисуется вовсе — ни модель, ни метка
      s.obj.visible = !(cloak && s.side !== state.playerSide);
      if (cloak && s.side !== state.playerSide) { d.style.display = 'none'; continue; }
      const p = screenOf(s.pos, tcam.cam, w, h);
      if (p.z > 1 || p.x < -90 || p.x > w + 90 || p.y < -50 || p.y > h + 50) { d.style.display = 'none'; continue; }
      d.style.display = 'block';
      d.classList.toggle('cloak', cloak);
      d.classList.toggle('jump', !!s.hyper);
      d.style.transform = `translate(${(p.x - 48) | 0}px,${(p.y - 44) | 0}px)`;
      labelHits.push({ ent: s, x: p.x, y: p.y - 44 });
      d.classList.toggle('hover', hoverEnt === s);
      d.classList.toggle('foe-hover', hoverEnt === s && s.side !== state.playerSide);
      const hp = clamp(s.hp / s.maxHp, 0, 1);
      const bar = d.lastChild.firstChild;
      bar.style.width = (hp * 100) + '%';
      bar.style.background = hp > 0.55 ? s.faction.colorCss : hp > 0.25 ? '#e0a94e' : '#e05555';
      const nm = s.def.name;
      d.firstChild.textContent = nm.includes('«') ? nm.slice(nm.indexOf('«')) : nm;
      d.classList.toggle('mine', s.side === state.playerSide);
      d.classList.toggle('sel', state.selection.includes(s));
    }
    /* Скрытая машина противника не рисуется, как и скрытый корабль.
       Выбрать её нельзя (C18), и видимая, но не нажимаемая машина
       хуже обеих: игрок жмёт по ней ПКМ, а флот уходит в точку. */
    for (const c of state.craft) {
      if (!c.dead) c.obj.visible = !(c.side !== state.playerSide && craftHidden(c));
    }
    /* Подписи звеньям. Истребитель — точка размером с пиксель, и без
       метки игрок просто не знает, что авиация вообще в бою. Метка
       одна на звено, у центра масс: пять отдельных было бы месивом. */
    for (const sq of state.squads) {
      if (sq.dead || !sq.craft.length) continue;
      const live = sq.craft.filter(c => !c.dead);
      if (!live.length) continue;
      if (sq.side !== state.playerSide && unseen(sq)) continue;
      _v.set(0, 0, 0);
      for (const c of live) _v.add(c.pos);
      _v.divideScalar(live.length);
      let d = markerPool[i];
      if (!d) {
        d = document.createElement('div');
        d.className = 'marker';
        d.innerHTML = '<span class="mk-name"></span><span class="mk-bar"><i></i></span>';
        markers.appendChild(d);
        markerPool[i] = d;
      }
      i++;
      const p = screenOf(_v, tcam.cam, w, h);
      if (p.z > 1 || p.x < -90 || p.x > w + 90 || p.y < -50 || p.y > h + 50) { d.style.display = 'none'; continue; }
      d.style.display = 'block';
      d.classList.remove('cloak', 'jump');
      d.style.transform = `translate(${(p.x - 48) | 0}px,${(p.y - 40) | 0}px)`;
      labelHits.push({ ent: sq, x: p.x, y: p.y - 40 });
      d.classList.toggle('hover', hoverEnt === sq);
      d.classList.toggle('foe-hover', hoverEnt === sq && sq.side !== state.playerSide);
      d.firstChild.textContent = `${STRIKE_ROLES[sq.role].label} ×${live.length}`;
      const bar = d.lastChild.firstChild;
      const hp = live.reduce((a, c) => a + c.hp / c.maxHp, 0) / live.length;
      bar.style.width = (clamp(hp, 0, 1) * 100) + '%';
      bar.style.background = sq.faction.colorCss;
      d.classList.toggle('mine', sq.side === state.playerSide);
      d.classList.toggle('sel', state.selection.includes(sq));
    }
    for (; i < markerPool.length; i++) markerPool[i].style.display = 'none';
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
  const short = nm => (nm.includes('«') ? nm.slice(nm.indexOf('«') + 1, -1) : nm);

  /* ── РОСТЕР ФЛОТА.

     Полоска значков со всеми своими кораблями и звеньями — как
     в Empire at War. Она отвечает на вопрос, на который поле боя
     не отвечает никогда: «что у меня вообще есть и где оно».
     Касание выбирает корабль и переносит к нему камеру; полоска
     прочности показывает, кому уже плохо. */
  const rosterBox = $('roster');
  const rosterCells = new Map();
  function refreshRoster() {
    const mine = [
      ...state.ships.filter(s => !s.dead && s.side === state.playerSide && !s.station),
      ...state.squads.filter(q => !q.dead && q.side === state.playerSide && q.craft.some(c => !c.dead)),
    ];
    const seen = new Set();
    for (const e of mine) {
      seen.add(e.uid);
      let cell = rosterCells.get(e.uid);
      if (!cell) {
        cell = document.createElement('button');
        cell.className = 'rcell';
        cell.innerHTML = '<b></b><span class="rbar"><i></i></span><em class="rgrp"></em>';
        cell.onclick = () => {
          state.selection = [e];
          const p = e.kind === 'squad'
            ? (e.craft.find(c => !c.dead) || {}).pos : e.pos;
          if (p) tcam.focus(p.clone(), Math.min(tcam.dist, 420));
          refreshSel();
        };
        rosterBox.appendChild(cell);
        rosterCells.set(e.uid, cell);
      }
      const isSquad = e.kind === 'squad';
      const live = isSquad ? e.craft.filter(c => !c.dead) : null;
      const hp = isSquad
        ? live.reduce((a, c) => a + c.hp / c.maxHp, 0) / Math.max(1, live.length)
        : e.hp / e.maxHp;
      cell.firstChild.textContent = isSquad
        ? `${STRIKE_ROLES[e.role].short || STRIKE_ROLES[e.role].label} ${live.length}`
        : short(e.def.name);
      const bar = cell.children[1].firstChild;
      bar.style.width = (clamp(hp, 0, 1) * 100) + '%';
      bar.style.background = hp > 0.55 ? '#8fffc8' : hp > 0.25 ? '#e0a94e' : '#e05555';
      cell.classList.toggle('on', state.selection.includes(e));
      cell.classList.toggle('air', isSquad);
      // В каких отрядах корабль — цифрой в углу ячейки
      const g = Object.keys(groups).filter(n => groups[n].includes(e)).join('');
      const em = cell.lastChild;
      if (em.textContent !== g) em.textContent = g;
    }
    for (const [uid, cell] of rosterCells) {
      if (!seen.has(uid)) { cell.remove(); rosterCells.delete(uid); }
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
          const r = ringMesh(1, 0x8fffc8, 0.85, 0.07);
          r.renderOrder = 5;
          scene.add(r);
          selRings[i] = r;
        }
        const r = selRings[i++];
        r.visible = true;
        r.position.copy(u.pos);
        // корпуса стали крупнее — кольцо выделения тоже, иначе оно
        // прячется внутри силуэта
        r.scale.setScalar(e.kind === 'squad' ? 14 : u.radius * 3.1);
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

    /* Кольцо под курсором (C74): тусклое, зелёное у своего, красное
       у врага. Выделенному оно не нужно — у него своё кольцо. */
    const he = hoverEnt && !hoverEnt.dead && !state.selection.includes(hoverEnt) ? hoverEnt : null;
    hoverRing.visible = !!he;
    if (he) {
      const at = he.kind === 'squad' ? he.pos : he.pos;
      hoverRing.position.copy(at);
      hoverRing.scale.setScalar(he.kind === 'squad' ? 16 : he.radius * 3.3);
      hoverRing.material.color.set(he.side === state.playerSide ? 0x8fffc8 : 0xff6b5a);
    }
  }
  const hoverRing = ringMesh(1, 0x8fffc8, 0.45, 0.07);
  hoverRing.renderOrder = 5;
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
      if (x < hl.x - 48 || x > hl.x + 48 || y < hl.y - 3 || y > hl.y + 24) continue;
      const d = Math.abs(x - hl.x) + Math.abs(y - (hl.y + 10)) * 2;
      if (d < bd) { bd = d; best = hl.ent; }
    }
    return best;
  }

  function selectEntity(ent, additive) {
    if (!ent) { if (!additive) state.selection = []; refreshSel(); return; }
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
          // Приказ атаковать сильнее «держать» и «с ходу»: идём добивать
          s.forced = ent; s.target = liveTarget(s, ent); s.moveTo = null; s.amove = null; s.hold = false;
        } else {
          if (air && !hitsStrike(s)) { deaf++; continue; }   // бомбардировщик по авиации не бьёт
          s.target = ent; s.recall = false; s.moveTo = null;
          // каждая машина сама выберет ближайшую из звена-цели
          for (const c of s.craft) c.target = null;
        }
      }
      if (goers.length) moveGroup(goers, ent.pos.clone());
      fx.flash(ent.pos, (ent.radius || 6) * 1.6, 0xff6b5a, 0.5);
      if (goers.length) toast('Главный калибр по авиации не наводится — корабли идут к звену, бьёт ПВО');
      if (held) toast('Носитель и РЭБ безоружны — держатся позади');
      if (deaf) toast('Бомбардировщики по авиации не стреляют');
      return true;
    }
    if (!world) return false;
    moveGroup(mine, world);
    fx.flash(world, 16, 0x8fffc8, 0.6);
    return true;
  }

  /* Приказ идти: строй квадратом вокруг точки. attack — атака с ходу
     (A): корабли идут к той же точке, но останавливаются на каждого
     встречного (см. updateShip); звенья и так бьют всё на пути. */
  function moveGroup(mine, world, attack) {
    const n = mine.length, cols = Math.ceil(Math.sqrt(n));
    mine.forEach((s, i) => {
      const col = i % cols, row = Math.floor(i / cols);
      const dest = world.clone().add(_v.set((col - (cols - 1) / 2) * 90, 0, (row - (cols - 1) / 2) * 90));
      dest.y = s.kind === 'ship' ? s.pos.y : world.y;
      if (attack && s.kind === 'ship') { s.amove = dest; s.moveTo = null; }
      else { s.moveTo = dest; s.amove = null; }
      s.target = null;
      s.hold = false;
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
      issueOrder(ent, controls.worldAt(x, y));
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
    else if (hoverEnt) cur = hoverEnt.side !== P && own ? 'cur-attack' : 'cur-pick';
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
    if (e.drift) return 'дрифт: тяга отключена';
    if (e.moveTo) {
      const d = Math.round(e.pos.distanceTo(e.moveTo));
      return `идёт к точке · ${d}`;
    }
    if (e.amove) {
      const d = Math.round(e.pos.distanceTo(e.amove));
      const t = e.target && !e.target.dead && e.target.def ? ` · бьёт «${short(e.target.def.name)}»` : '';
      return `идёт с боем · ${d}${t}`;
    }
    if (e.forced && !e.forced.dead) return `атакует «${short(e.forced.def.name)}»`;
    const hold = e.hold ? 'держит позицию · ' : '';
    if (e.target && !e.target.dead) return `${hold}бьёт по «${short(e.target.def.name)}»`;
    return e.hold ? 'держит позицию — не преследует' : 'ждёт приказа';
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
      if (actsKey !== '') { actsKey = ''; actsEls = []; acts.innerHTML = ''; }
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
        setHtml(sel, `<div class="sel-title">${e.def.name} ${foreign}</div>
          <div class="sel-sub">${e.def.role || ''} · скорость ${spd} · прочность ${Math.max(0, Math.round(e.hp))}/${e.maxHp}</div>
          <div class="sel-hpbar"><i style="width:${clamp(e.hp / e.maxHp, 0, 1) * 100}%"></i></div>
          <div class="sel-doing">${doingOf(e)}</div>
          <div class="sel-desc">${e.def.desc || ''}</div>`);
      }
    } else {
      const by = {};
      for (const e of list) {
        const n = e.kind === 'squad' ? STRIKE_ROLES[e.role].label : e.def.name;
        by[n] = (by[n] || 0) + 1;
      }
      setHtml(sel, `<div class="sel-title">Выделено: ${list.length}</div>
        <div class="sel-sub">${Object.entries(by).map(([n, c]) => `${n} ×${c}`).join(' · ')}</div>
        <div class="sel-doing">${doingOf(list[0])}</div>`);
    }

    /* Описание кнопок: id задаёт место в ключе, остальное обновляется на
       месте. key — клавиша (e.code), её буква стоит в углу кнопки (C50). */
    const items = [];
    const KEYS = {
      'launch-interceptor': 'KeyZ', 'launch-fighter': 'KeyX', 'launch-bomber': 'KeyC',
      land: 'KeyV', 'ecm-jam': 'KeyJ', 'ecm-shield': 'KeyK', 'ecm-off': 'KeyL',
      jump: 'KeyG', unjump: 'KeyG', stop: 'KeyS', hold: 'KeyH', up: 'PageUp', down: 'PageDown',
    };
    const addBtn = (id, label, hint, fn, disabled) => items.push({ id, label, hint, fn, disabled: !!disabled, key: KEYS[id] });
    const addNote = (id, text) => items.push({ id, note: text });

    const carriers = list.filter(e => e.kind === 'ship' && e.hangar && e.side === state.playerSide);
    if (carriers.length) {
      const free = carriers.reduce((a, c) => a + c.hangar.free, 0);
      for (const role of ['interceptor', 'fighter', 'bomber']) {
        const r = STRIKE_ROLES[role];
        addBtn('launch-' + role, r.label, r.hint, () => {
          const c = carriers.find(x => !x.dead && x.hangar.free > 0);
          if (c) { launchSquadron(c, role); refreshSel(); }
        }, free <= 0);
      }
      addNote('bays', `Мест в ангаре: ${free}`);
    }
    const squads = list.filter(e => e.kind === 'squad' && e.side === state.playerSide);
    if (squads.length) addBtn('land', 'На посадку', 'Вернуть звено, освободить ангар', () => { for (const s of squads) s.recall = true; });

    const ecms = list.filter(e => e.ecm && e.side === state.playerSide);
    if (ecms.length) {
      const cur = ecms[0].ecm.mode;
      addBtn('ecm-jam', (cur === 'jam' ? '⦿ ' : '') + 'Глушение',
        'Ломает чужое наведение в куполе', () => {
          for (const e of ecms) e.ecm.mode = 'jam';
          toast('Купол помех развёрнут');
          refreshSel();
        });
      addBtn('ecm-shield', (cur === 'shield' ? '⦿ ' : '') + 'Прикрытие',
        'Снимает чужие помехи со своих', () => {
          for (const e of ecms) e.ecm.mode = 'shield';
          toast('Купол переключён на защиту');
          refreshSel();
        });
      addBtn('ecm-off', (cur === 'off' ? '⦿ ' : '') + 'Молчать',
        'Выключить излучение', () => { for (const e of ecms) e.ecm.mode = 'off'; refreshSel(); });
    }

    const ships = list.filter(e => e.kind === 'ship' && e.side === state.playerSide && !e.station);
    if (ships.length) {
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
          });
        }
      } else {
        const carrier = ships.some(s => s.cls === 'carrier');
        addBtn('jump', 'Уйти в гипер', carrier
          ? 'Носитель уходит — за ним отходит весь флот, бой проигран'
          : 'Копит переход, всё это время беззащитен', () => {
          for (const s of ships) beginJump(s);
          refreshSel();
        });
      }
      addBtn('stop', 'Стоп', 'Снять все приказы, погасить ход', () => {
        for (const s of ships) { s.moveTo = null; s.amove = null; s.target = null; s.forced = null; s.hold = false; }
        refreshSel();
      });
      /* «Держать позицию» (H): стоять и бить только то, до чего орудие
         достаёт с места. Без неё «Стоп» держал корабль секунду — дальше
         он сам находил цель и шёл на сближение (C26). */
      const allHold = ships.every(s => s.hold);
      addBtn('hold', (allHold ? '⦿ ' : '') + 'Держать', 'Стоять на месте, не преследовать', () => {
        const on = !ships.every(s => s.hold);
        for (const s of ships) {
          s.hold = on;
          if (on) { s.moveTo = null; s.amove = null; s.forced = null; s.target = null; }
        }
        toast(on ? 'Держать позицию: стоят и бьют только тех, до кого достают' : 'Корабли снова сами идут на сближение');
        refreshSel();
      });
      addBtn('up', 'Выше', 'Поднять на 120', () => { for (const s of ships) { s.moveTo = s.pos.clone().add(_v.set(0, 120, 0)); s.amove = null; s.hold = false; } });
      addBtn('down', 'Ниже', 'Опустить на 120', () => { for (const s of ships) { s.moveTo = s.pos.clone().add(_v.set(0, -120, 0)); s.amove = null; s.hold = false; } });
    }

    const key = list.map(e => e.uid).join(',') + '|' + items.map(i => i.id).join(',');
    if (key !== actsKey) {
      actsKey = key;
      acts.innerHTML = '';
      actsEls = items.map(it => {
        if (it.note !== undefined) {
          const d = document.createElement('div');
          d.className = 'act-note';
          acts.appendChild(d);
          return { d };
        }
        const b = document.createElement('button');
        b.className = 'act';
        b.dataset.act = it.id;
        const lb = document.createElement('b');
        const sm = document.createElement('small');
        b.append(lb, sm);
        if (it.key) {
          const k = document.createElement('kbd');
          k.className = 'hk';
          k.textContent = keyName(it.key);
          b.appendChild(k);
        }
        acts.appendChild(b);
        return { b, lb, sm };
      });
    }
    items.forEach((it, i) => {
      const el = actsEls[i];
      if (it.note !== undefined) {
        if (el.d.textContent !== it.note) el.d.textContent = it.note;
        return;
      }
      if (el.lb.textContent !== it.label) el.lb.textContent = it.label;
      const hint = it.hint || '';
      if (el.sm.textContent !== hint) el.sm.textContent = hint;
      el.sm.hidden = !hint;
      if (el.b.disabled !== it.disabled) el.b.disabled = it.disabled;
      const title = hint + (it.key ? ` · ${keyName(it.key)}` : '');
      if (el.b.title !== title) el.b.title = title;
      el.b.onclick = it.fn;
    });
    actsItems = items;
  }
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
      exitText: config.inCampaign
        ? 'Бой не будет засчитан: кампания продолжится с последнего сохранения.'
        : 'Бой не будет засчитан.',
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
    if (code === 'F2') { e.preventDefault(); hud.querySelector('[data-q="all"]').click(); return; }
    if (code === 'KeyA') { startAmove(); return; }
    if (code === 'KeyD') { toggleDrift(); return; }
    if (code === 'KeyB') { reinfBtn.click(); return; }
    const it = actsItems.find(x => x.key === code && x.fn);
    if (it) {
      e.preventDefault();
      if (it.disabled) toast(`${it.label.replace(/^⦿ /, '')}: сейчас недоступно`);
      else it.fn();
      return;
    }
    if ((code === 'KeyS' || code === 'KeyH') && !mineSelected().some(s => s.kind === 'ship')) {
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
    const lost = state.ships.filter(s => s.dead && !s.fled && s.side === P && !s.station).length;
    const spare = (state.reserve[P] || []).reduce((a, x) => a + x.count, 0);
    const tally = [
      saved ? `Ушли в гипер: ${saved}` : '',
      lost ? `потеряно: ${lost}` : '',
      spare ? `резерв в бой не вступал: ${spare}` : '',
    ].filter(Boolean).join(' · ');
    const win = result === 'victory';
    const card = $('end');
    card.style.display = 'flex';
    card.innerHTML = `<div class="end-inner">
      <h2>${win ? 'Орбита за нами' : result === 'retreat' ? 'Отход' : 'Флот разбит'}</h2>
      <p>${win
        ? 'Противник в этой системе больше не контролирует пространство. Можно высаживать десант.'
        : result === 'retreat'
          ? 'Флот вышел из боя. Домой вернутся только те, кто успел уйти в гипер.'
          : saved || spare
            ? `Орбита за противником. Домой вернутся только ${[saved ? 'ушедшие в гипер' : '', spare ? 'корабли резерва' : ''].filter(Boolean).join(' и ')}.`
            : 'Корабли потеряны. Орбита остаётся за противником.'}</p>
      ${tally ? `<p class="end-tally">${tally[0].toUpperCase() + tally.slice(1)}.</p>` : ''}
      <button class="btn primary" data-role="cont">Продолжить</button></div>`;
    state.outcome = outcome;     // для автотестов: что уйдёт в кампанию
    card.querySelector('[data-role="cont"]').onclick = () => {
      config.onEnd && config.onEnd(outcome);
    };
  }

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
  function update(rawDt) {
    tcam.update(rawDt);
    // Миникарта рисуется и на паузе: на ней как раз и планируют
    drawMinimap(rawDt);
    // После итога бой стоит насовсем, что бы ни нажали (C65)
    const dt = (state.paused || ended) ? 0 : Math.min(rawDt, 0.05) * state.speed;
    if (dt > 0) {
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
      checkEnd();
    }

    fx.update(rawDt);
    planet.rotation.y += rawDt * 0.004;
    if (planet.userData.clouds) planet.userData.clouds.rotation.y += rawDt * 0.0022;
    refreshReinforce();
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
    updateSelVisuals();
    updateOrders();
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
    if (selTick <= 0) { selTick = 0.34; refreshSel(); refreshRoster(); }

    let pa = 0, pd = 0, na = 0, nd = 0;
    for (const s of state.ships) {
      if (s.dead) continue;
      if (s.side === 'attacker') { pa += s.hp; na++; } else { pd += s.hp; nd++; }
    }
    const max = Math.max(1, pa + pd);
    const ab = $('atk-bar'), db = $('def-bar');
    ab.style.width = (pa / max * 100) + '%';
    ab.style.background = sides.attacker.faction.colorCss;
    db.style.width = (pd / max * 100) + '%';
    db.style.background = sides.defender.faction.colorCss;
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
    tcam.dispose();
    controls.dispose();
    hud.remove();
    disposeScene(scene);
  }

  // Стартовая камера: свой флот в нижней трети кадра, противник — в верхней.
  // Точка взгляда смещена вперёд, за спину своим, иначе корабли уезжают
  // под нижнюю панель интерфейса.
  tcam.yaw = state.playerSide === 'attacker' ? 0 : Math.PI;
  /* Камера садится над своим флотом, а не посередине поля: флоты
     теперь стоят далеко, и вид из центра показал бы пустоту.
     Точку смещаем вперёд по курсу — свои корабли должны оказаться
     в нижней трети экрана, а не под панелью интерфейса. */
  tcam.focus(new THREE.Vector3(0, 0, state.playerSide === 'attacker' ? 620 : -620), 1250);
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
      a.forEach((s, i) => { s.pos.set((i % 4 - 1.5) * 60, rnd(-20, 20), gap / 2); s.moveTo = null; });
      d.forEach((s, i) => { s.pos.set((i % 4 - 1.5) * 60, rnd(-20, 20), -gap / 2); s.moveTo = null; });
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
