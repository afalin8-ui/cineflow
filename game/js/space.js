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
  clamp, lerp, rnd, disposeScene, IS_TOUCH,
} from './engine.js';
import { buildShip, buildStrike, buildTorpedo, buildPlanet } from './models.js';
import {
  FACTIONS, STRIKE, STRIKE_ROLES, SPACE_DMG, SQUAD_SIZE, STATION, dmgMult, shipDef,
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

const FIELD = 1700;   // половина размера поля боя

export function createSpaceBattle(ctx, config) {
  const { viewport, hudRoot } = ctx;
  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0x04060b);
  scene.fog = new THREE.Fog(0x04060b, 2400, 6000);

  const tcam = new TacticalCamera({
    dist: 980, maxDist: 2400, minDist: 60, pitch: 0.52, yaw: 0,
    bounds: { x: FIELD, z: FIELD, y: 600 }, far: 9000, allowY: true,
  });

  scene.add(new THREE.AmbientLight(0x5a6a86, 1.15));
  const key = new THREE.DirectionalLight(0xffe8cf, 2.6);
  key.position.set(-500, 400, -300);
  scene.add(key);
  const fill = new THREE.DirectionalLight(0x4d7bb8, 1.15);
  fill.position.set(400, -250, 500);
  scene.add(fill);

  scene.add(starfield(2800, 4600));

  // Планета под ногами — бой идёт на её орбите
  const planet = buildPlanet(config.biome || 'rock', 1150);
  planet.position.set(340, -1560, -420);
  scene.add(planet);

  const fx = new Fx(scene);

  const state = {
    ships: [], craft: [], proj: [], squads: [],
    time: 0, speed: 1, paused: false,
    playerSide: config.playerSide || 'attacker',
    selection: [],
  };
  const sides = {
    attacker: { faction: FACTIONS[config.attacker.faction], id: 'attacker', sign: 1 },
    defender: { faction: FACTIONS[config.defender.faction], id: 'defender', sign: -1 },
  };
  const enemyOf = s => (s === 'attacker' ? 'defender' : 'attacker');
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
    };
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

  spawnFleet('attacker', config.attacker.ships, 330, false);
  spawnFleet('defender', config.defender.ships, -330, config.defender.station);

  // Стартовый приказ обеим сторонам — сходиться. Иначе бой начинается
  // с того, что оба флота неподвижно смотрят друг на друга.
  for (const s of state.ships) {
    if (s.station) continue;
    s.moveTo = new THREE.Vector3(s.pos.x * 0.5, s.pos.y * 0.5, s.pos.z > 0 ? 150 : -150);
  }

  // ── АВИАЦИЯ ──────────────────────────────────────────────

  function launchSquadron(carrier, role) {
    if (!carrier.hangar || carrier.hangar.free <= 0 || carrier.dead) return false;
    carrier.hangar.free--;
    const def = STRIKE[carrier.faction.id][role];
    const squad = {
      uid: uid++, kind: 'squad', side: carrier.side, faction: carrier.faction,
      role, def, home: carrier, craft: [], dead: false, recall: false,
      target: null, pos: new THREE.Vector3().copy(carrier.pos), moveTo: null,
    };
    const bay = carrier.obj.userData.bay || ZERO;
    const origin = bay.clone().applyQuaternion(carrier.obj.quaternion).add(carrier.pos);
    for (let i = 0; i < SQUAD_SIZE; i++) {
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

  function killSquad(squad) {
    if (squad.dead) return;
    squad.dead = true;
    const carrier = squad.home;
    if (carrier && !carrier.dead && carrier.hangar) carrier.hangar.rebuild.push(state.time + 26);
    state.selection = state.selection.filter(s => s !== squad);
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

  // ── УРОН ─────────────────────────────────────────────────

  function damage(target, amount, weapon) {
    if (!target || target.dead) return;
    const mult = dmgMult(SPACE_DMG, weapon, target.cls);
    if (mult <= 0) return;
    target.hp -= amount * mult * (1 - (target.armor || 0));
    if (target.hp <= 0) destroy(target);
  }

  function destroy(e) {
    if (e.dead) return;
    e.dead = true;
    const size = e.kind === 'ship' ? e.radius * 1.6 : e.kind === 'craft' ? 5 : 4;
    fx.explosion(e.pos, size, e.kind === 'ship' ? 0xffa050 : 0xffc070);
    if (e.kind === 'ship') {
      fx.shake = Math.min(1, fx.shake + e.radius / 40);
      for (let i = 0; i < 3; i++) {
        fx.flash(_v.copy(e.pos).add(_v2.set(rnd(-1, 1), rnd(-1, 1), rnd(-1, 1)).multiplyScalar(e.radius)),
          e.radius, 0xff8040, 0.8);
      }
      if (e.hangar) for (const sq of e.hangar.launched) if (!sq.dead) sq.home = null;
    }
    scene.remove(e.obj);
    if (e.kind === 'craft' && e.squad) {
      e.squad.craft = e.squad.craft.filter(c => c !== e);
      if (!e.squad.craft.length) killSquad(e.squad);
    }
    state.selection = state.selection.filter(s => s !== e);
  }

  // ── ПОИСК ЦЕЛЕЙ ──────────────────────────────────────────

  function nearest(from, list, maxDist, filter) {
    let best = null, bd = maxDist * maxDist;
    for (const e of list) {
      if (e.dead || (filter && !filter(e))) continue;
      const d = e.pos.distanceToSquared(from);
      if (d < bd) { bd = d; best = e; }
    }
    return best;
  }

  function shipAcquire(e) {
    const foe = enemyOf(e.side);
    const gun = e.guns[0];
    if (!gun) return null;
    const range = gun.def.range;
    let best = null, bestScore = -Infinity;
    for (const s of state.ships) {
      if (s.dead || s.side !== foe) continue;
      const d = s.pos.distanceTo(e.pos);
      if (d > range * 1.8) continue;
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
    if (!dir || dir.lengthSq() < 1e-8) return;
    _v3.copy(dir).normalize();
    quatFromDir(_v3, _q);
    e.obj.quaternion.slerp(_q, clamp(turnRate * dt, 0, 1));
    e.dir.set(0, 0, -1).applyQuaternion(e.obj.quaternion);
  }

  // Тяга: доводим вектор скорости до желаемого. Двигатель работает
  // в полную силу только по курсу — вбок толкают слабые маневровые.
  function thrustTo(e, desiredVel, dt, thrust) {
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
    e.retarget -= dt;
    if (e.target && e.target.dead) e.target = null;
    if (e.forced && e.forced.dead) e.forced = null;
    if (!e.target || e.retarget <= 0) {
      e.target = e.forced || shipAcquire(e);
      e.retarget = rnd(0.8, 1.6);
    }

    const def = e.def;

    if (!e.station) {
      // ── куда хотим лететь
      let desiredVel = null;
      if (e.moveTo) {
        _v.subVectors(e.moveTo, e.pos);
        const d = _v.length();
        if (d < 45) {
          e.moveTo = null;
          desiredVel = ZERO;
        } else {
          // тормозной путь: v²/2a. Подходя к точке, гасим скорость заранее
          const brake = Math.sqrt(Math.max(0, 2 * def.thrust * Math.max(0, d - 40)));
          desiredVel = _v.divideScalar(d).multiplyScalar(Math.min(def.maxSpeed, brake)).clone();
        }
      } else if (e.target) {
        const d = e.pos.distanceTo(e.target.pos);
        const want = (e.guns[0] ? e.guns[0].def.range : 300) * 0.68;
        _v.subVectors(e.target.pos, e.pos);
        const dist = _v.length() || 1;
        _v.divideScalar(dist);
        if (d > want) desiredVel = _v.clone().multiplyScalar(def.maxSpeed);
        else if (d < want * 0.5) desiredVel = _v.clone().multiplyScalar(-def.maxSpeed * 0.7);
        else desiredVel = _v3.crossVectors(_v, UP).normalize().multiplyScalar(def.maxSpeed * 0.55).clone();
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

      thrustTo(e, desiredVel, dt, def.thrust);
      if (e.vel.length() > def.maxSpeed * 1.25) e.vel.setLength(def.maxSpeed * 1.25);

      // ── куда смотрим: цель важнее курса
      let look = null;
      if (e.target && e.pos.distanceTo(e.target.pos) < (e.guns[0] ? e.guns[0].def.range : 400) * 1.5) {
        look = _v2.subVectors(e.target.pos, e.pos);
      } else if (desiredVel && desiredVel.lengthSq() > 1) {
        look = _v2.copy(desiredVel);
      } else if (e.vel.lengthSq() > 1) {
        look = _v2.copy(e.vel);
      }
      face(e, look, dt, def.turn);
      integrate(e, dt);

      const glow = 0.55 + e.thrustNow * 0.9;
      for (const en of e.obj.userData.engines || []) {
        en.scale.setScalar(lerp(en.scale.x, def.radius * glow, clamp(dt * 5, 0, 1)));
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

      if (g.def.charge && g.cd <= g.def.charge && g.cd > 0) {
        if (state.time - g.chargeFx > 0.09) {
          g.chargeFx = state.time;
          fx.flash(muzzleWorld(e, g.idx), e.radius * (1 - g.cd / g.def.charge) * 1.7 + 2, 0xfff0d0, 0.14);
        }
      }
      if (g.cd > 0) continue;
      g.cd = g.def.cd;
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
        fx.tracer(pdWorld(e, i), t.pos, e.side === state.playerSide ? 0x9fe8ff : 0xffc07a, 0.1, 0.24);
        damage(t, pd.dmg, 'pd');
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
        const p = spawnProjectile(e, t, g.def.dmg, 'missile', 130, 26);
        p.dir.add(_v.set(rnd(-1, 1), rnd(-1, 1), rnd(-1, 1)).multiplyScalar(g.def.spread || 0.05)).normalize();
        p.wobble = rnd(0, 6.28);
      }
      fx.flash(from, e.radius * 0.8, 0xffd0a0, 0.2);
      return;
    }
    fx.beam(from, t.pos, { color, width: 1.2 + e.radius * 0.09, life: 0.42 });
    fx.flash(from, e.radius * 1.1, 0xffffff, 0.2);
    fx.flash(t.pos, e.radius * 0.9, color, 0.35);
    fx.shake = Math.min(1, fx.shake + 0.12);
    damage(t, g.def.dmg, g.def.type);
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

  function updateCraft(c, dt) {
    const squad = c.squad;
    if (c.target && c.target.dead) c.target = null;

    if (squad && squad.recall) {
      const home = squad.home;
      if (home && !home.dead) {
        if (c.pos.distanceTo(home.pos) < home.radius * 2.4) {
          c.dead = true;
          scene.remove(c.obj);
          squad.craft = squad.craft.filter(x => x !== c);
          if (!squad.craft.length) {
            home.hangar.free = Math.min(home.hangar.bays, home.hangar.free + 1);
            killSquad(squad);
          }
          return;
        }
        flyToward(c, home.pos, dt, 1);
        return;
      }
      squad.recall = false;
    }

    if (!c.target) c.target = (squad && squad.target && !squad.target.dead) ? squad.target : craftAcquire(c);

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
      if (d < wr && c.cd <= 0) {
        c.cd = c.def.cd;
        spawnProjectile(c, t, c.def.dmg, 'torp', 78, 34);
        fx.flash(c.pos, 3, 0xffd0a0, 0.18);
        c.phase = 'break';
        c.breakUntil = state.time + rnd(3.4, 4.6);
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
        fx.tracer(_v.copy(c.pos).addScaledVector(c.dir, 4), t.pos,
          c.side === state.playerSide ? 0x9fe0ff : 0xffb070, 0.09, 0.2);
        damage(t, c.def.dmg, c.def.weapon);
        if (t.dead) fx.explosion(t.pos, t.kind === 'craft' ? 4 : 6, 0xffc070);
      }
    }
  }

  function updateProjectile(p, dt) {
    p.life -= dt;
    if (p.life <= 0) { destroy(p); return; }
    if (p.target && p.target.dead) p.target = null;
    if (p.target) {
      _v.subVectors(p.target.pos, p.pos).normalize();
      p.dir.lerp(_v, clamp((p.weapon === 'torp' ? 1.1 : 1.8) * dt, 0, 1)).normalize();
    }
    p.pos.addScaledVector(p.dir, p.speed * dt);
    p.obj.quaternion.copy(quatFromDir(p.dir));
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
  const ai = { side: enemyOf(state.playerSide), next: 3 };
  function updateAI(dt) {
    ai.next -= dt;
    if (ai.next > 0) return;
    ai.next = rnd(4, 7);
    const mine = state.ships.filter(s => !s.dead && s.side === ai.side);
    const foes = state.ships.filter(s => !s.dead && s.side !== ai.side);
    if (!foes.length || !mine.length) return;

    const enemyCraft = state.craft.filter(c => c.side !== ai.side).length;
    const myCraft = state.craft.filter(c => c.side === ai.side).length;
    for (const s of mine) {
      if (!s.hangar || s.hangar.free <= 0) continue;
      let role = 'fighter';
      if (enemyCraft > myCraft + 4) role = 'interceptor';
      else if (foes.some(f => f.cls !== 'escort')) role = 'bomber';
      launchSquadron(s, role);
    }

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
    if (juicy) for (const s of mine) if (Math.random() < 0.45) s.forced = juicy;
  }

  // ── HUD ──────────────────────────────────────────────────
  const hud = document.createElement('div');
  hud.className = 'hud hud-space';
  hud.innerHTML = `
    <div class="topbar">
      <div class="strength">
        <div class="ss-row"><i class="dot" data-side="attacker"></i><b data-role="atk-name"></b>
          <span class="bar"><i data-role="atk-bar"></i></span><em data-role="atk-num"></em></div>
        <div class="ss-row"><i class="dot" data-side="defender"></i><b data-role="def-name"></b>
          <span class="bar"><i data-role="def-bar"></i></span><em data-role="def-num"></em></div>
      </div>
      <div class="title" data-role="banner"></div>
      <div class="speedctl">
        <button data-speed="0" aria-label="Пауза">❚❚</button>
        <button data-speed="1" class="on">1×</button>
        <button data-speed="2">2×</button>
        <button data-speed="4">4×</button>
        <button data-role="retreat" class="danger">Отход</button>
      </div>
    </div>

    <div class="markers" data-role="markers"></div>

    <div class="sidebar">
      <button data-q="all">Весь<br>флот</button>
      <button data-q="capital">Линкоры</button>
      <button data-q="carrier">Авиа-<br>носцы</button>
      <button data-q="escort">Эскорт</button>
      <button data-q="squads">Авиация</button>
      <button data-role="boxmode">Рамка</button>
    </div>

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

  hud.querySelectorAll('.dot').forEach(d => { d.style.background = sides[d.dataset.side].faction.colorCss; });
  $('atk-name').textContent = sides.attacker.faction.tag;
  $('def-name').textContent = sides.defender.faction.tag;
  $('banner').textContent = config.title || 'Бой на орбите';
  $('hint').innerHTML = IS_TOUCH
    ? 'Касание по своему кораблю — выбрать · по врагу — атаковать · по пустоте — идти · тянуть — двигать карту · щипок — приближение · долгое нажатие — рамка'
    : 'ЛКМ — выбрать, рамкой — группу · ПКМ — приказ · колесо — приближение · Alt+ЛКМ или средняя кнопка — облёт · WASD — карта · R/F — выше/ниже';

  hud.querySelectorAll('[data-speed]').forEach(b => {
    b.onclick = () => {
      const v = +b.dataset.speed;
      state.paused = v === 0;
      if (v) state.speed = v;
      hud.querySelectorAll('[data-speed]').forEach(x => x.classList.toggle('on', +x.dataset.speed === v));
    };
  });
  $('retreat').onclick = () => finish(state.playerSide === 'attacker' ? 'retreat' : 'defeat');

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
  function updateMarkers() {
    const w = viewport.w, h = viewport.h;
    let i = 0;
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
      const p = screenOf(s.pos, tcam.cam, w, h);
      if (p.z > 1 || p.x < -90 || p.x > w + 90 || p.y < -50 || p.y > h + 50) { d.style.display = 'none'; continue; }
      d.style.display = 'block';
      d.style.transform = `translate(${(p.x - 48) | 0}px,${(p.y - 44) | 0}px)`;
      const hp = clamp(s.hp / s.maxHp, 0, 1);
      const bar = d.lastChild.firstChild;
      bar.style.width = (hp * 100) + '%';
      bar.style.background = hp > 0.55 ? s.faction.colorCss : hp > 0.25 ? '#e0a94e' : '#e05555';
      const nm = s.def.name;
      d.firstChild.textContent = nm.includes('«') ? nm.slice(nm.indexOf('«')) : nm;
      d.classList.toggle('mine', s.side === state.playerSide);
      d.classList.toggle('sel', state.selection.includes(s));
    }
    for (; i < markerPool.length; i++) markerPool[i].style.display = 'none';
  }

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
        r.scale.setScalar(e.kind === 'squad' ? 8 : u.radius * 2.3);
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
  }

  // ── управление ──────────────────────────────────────────
  function pickMeshes() {
    const m = [];
    for (const s of state.ships) if (!s.dead) m.push(s.obj);
    for (const c of state.craft) if (!c.dead) m.push(c.obj);
    return m;
  }

  function entityAt(x, y) {
    let ent = controls.pick(x, y);
    if (!ent) {
      // палец промахивается мимо мелких моделей — ловим по экрану
      const cands = [...state.ships.filter(s => !s.dead), ...state.squads.filter(s => !s.dead)];
      ent = controls.pickNear(x, y, cands, tcam.cam, viewport.w, viewport.h, IS_TOUCH ? 46 : 22);
    }
    if (ent && ent.kind === 'craft') ent = ent.squad;
    return ent;
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

  function issueOrder(ent, world) {
    const mine = state.selection.filter(s => s.side === state.playerSide && !s.dead);
    if (!mine.length) return false;
    if (ent && ent.side !== state.playerSide) {
      for (const s of mine) {
        if (s.kind === 'ship') { s.forced = ent; s.target = ent; s.moveTo = null; }
        else { s.target = ent; s.recall = false; s.moveTo = null; for (const c of s.craft) c.target = ent; }
      }
      fx.flash(ent.pos, (ent.radius || 6) * 1.6, 0xff6b5a, 0.5);
      return true;
    }
    if (!world) return false;
    const n = mine.length, cols = Math.ceil(Math.sqrt(n));
    mine.forEach((s, i) => {
      const col = i % cols, row = Math.floor(i / cols);
      const dest = world.clone().add(_v.set((col - (cols - 1) / 2) * 90, 0, (row - (cols - 1) / 2) * 90));
      dest.y = s.kind === 'ship' ? s.pos.y : world.y;
      s.moveTo = dest;
      s.target = null;
      if (s.kind === 'ship') s.forced = null;
      else { s.recall = false; for (const c of s.craft) c.target = null; }
    });
    fx.flash(world, 16, 0x8fffc8, 0.6);
    return true;
  }

  const controls = new Controls(viewport.canvas, tcam, {
    pickMeshes,
    planeY: () => 0,
    onBoxModeChange: on => boxBtn.classList.toggle('on', on),
    onTap({ x, y, shift, touch }) {
      const ent = entityAt(x, y);
      const world = controls.worldAt(x, y);
      // На мыши касание — всегда выбор (приказы на ПКМ).
      // На пальце: свой корабль — выбор, всё прочее — приказ.
      if (!touch) { selectEntity(ent, shift); return; }
      if (ent && ent.side === state.playerSide) { selectEntity(ent, shift); return; }
      if (state.selection.some(s => s.side === state.playerSide && !s.dead)) {
        if (issueOrder(ent, world)) return;
      }
      selectEntity(ent, shift);
    },
    onOrder({ x, y }) {
      const ent = entityAt(x, y);
      issueOrder(ent, controls.worldAt(x, y));
    },
    onBox(rect, additive) {
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

  // ── панель выделения ────────────────────────────────────
  function refreshSel() {
    const sel = $('sel'), acts = $('acts');
    const list = state.selection.filter(s => !s.dead);
    if (!list.length) {
      sel.innerHTML = '<div class="sel-empty">Ничего не выбрано</div>';
      acts.innerHTML = '';
      return;
    }
    if (list.length === 1) {
      const e = list[0];
      if (e.kind === 'squad') {
        const role = STRIKE_ROLES[e.role];
        sel.innerHTML = `<div class="sel-title">${e.def.name}</div>
          <div class="sel-sub">${role.label} · ${e.craft.length}/${SQUAD_SIZE} машин</div>
          <div class="sel-desc">${role.hint}</div>`;
      } else {
        const spd = Math.round(e.vel.length());
        const foreign = e.side !== state.playerSide ? '<span class="tag foe">противник</span>' : '';
        sel.innerHTML = `<div class="sel-title">${e.def.name} ${foreign}</div>
          <div class="sel-sub">${e.def.role || ''} · скорость ${spd} · прочность ${Math.max(0, Math.round(e.hp))}/${e.maxHp}</div>
          <div class="sel-hpbar"><i style="width:${clamp(e.hp / e.maxHp, 0, 1) * 100}%"></i></div>
          <div class="sel-desc">${e.def.desc || ''}</div>`;
      }
    } else {
      const by = {};
      for (const e of list) {
        const n = e.kind === 'squad' ? STRIKE_ROLES[e.role].label : e.def.name;
        by[n] = (by[n] || 0) + 1;
      }
      sel.innerHTML = `<div class="sel-title">Выделено: ${list.length}</div>
        <div class="sel-sub">${Object.entries(by).map(([n, c]) => `${n} ×${c}`).join(' · ')}</div>`;
    }

    acts.innerHTML = '';
    const addBtn = (label, hint, fn, disabled) => {
      const b = document.createElement('button');
      b.className = 'act';
      b.innerHTML = `<b>${label}</b>${hint ? `<small>${hint}</small>` : ''}`;
      b.disabled = !!disabled;
      b.onclick = fn;
      acts.appendChild(b);
      return b;
    };

    const carriers = list.filter(e => e.kind === 'ship' && e.hangar && e.side === state.playerSide);
    if (carriers.length) {
      const free = carriers.reduce((a, c) => a + c.hangar.free, 0);
      for (const role of ['interceptor', 'fighter', 'bomber']) {
        const r = STRIKE_ROLES[role];
        addBtn(r.label, r.hint, () => {
          const c = carriers.find(x => x.hangar.free > 0);
          if (c) { launchSquadron(c, role); refreshSel(); }
        }, free <= 0);
      }
      const note = document.createElement('div');
      note.className = 'act-note';
      note.textContent = `Мест в ангаре: ${free}`;
      acts.appendChild(note);
    }
    const squads = list.filter(e => e.kind === 'squad' && e.side === state.playerSide);
    if (squads.length) addBtn('На посадку', 'Вернуть звено, освободить ангар', () => { for (const s of squads) s.recall = true; });

    const ships = list.filter(e => e.kind === 'ship' && e.side === state.playerSide && !e.station);
    if (ships.length) {
      addBtn('Стоп', 'Погасить скорость', () => { for (const s of ships) { s.moveTo = null; s.target = null; s.forced = null; } });
      addBtn('Выше', 'Поднять на 120', () => { for (const s of ships) s.moveTo = s.pos.clone().add(_v.set(0, 120, 0)); });
      addBtn('Ниже', 'Опустить на 120', () => { for (const s of ships) s.moveTo = s.pos.clone().add(_v.set(0, -120, 0)); });
    }
  }
  refreshSel();

  function onKey(e) {
    if (e.target && /input|textarea/i.test(e.target.tagName)) return;
    if (e.code === 'Space') { e.preventDefault(); hud.querySelector(`[data-speed="${state.paused ? state.speed : 0}"]`).click(); }
    if (e.code === 'Escape') { state.selection = []; refreshSel(); }
  }
  addEventListener('keydown', onKey);

  // ── ЗАВЕРШЕНИЕ ───────────────────────────────────────────
  function survivors(side) {
    const out = {};
    for (const s of state.ships) {
      if (s.dead || s.side !== side || s.station) continue;
      out[s.def.id] = (out[s.def.id] || 0) + 1;
    }
    return Object.entries(out).map(([id, count]) => ({ id, count }));
  }

  let ended = false;
  function finish(result) {
    if (ended) return;
    ended = true;
    state.paused = true;
    const win = result === 'victory';
    const card = $('end');
    card.style.display = 'flex';
    card.innerHTML = `<div class="end-inner">
      <h2>${win ? 'Орбита за нами' : result === 'retreat' ? 'Отход' : 'Флот разбит'}</h2>
      <p>${win
        ? 'Противник в этой системе больше не контролирует пространство. Можно высаживать десант.'
        : result === 'retreat'
          ? 'Флот вышел из боя. Уцелевшие корабли возвращаются в точку старта.'
          : 'Корабли потеряны. Система остаётся за противником.'}</p>
      <button class="btn primary" data-role="cont">Продолжить</button></div>`;
    card.querySelector('[data-role="cont"]').onclick = () => {
      config.onEnd && config.onEnd({ result, attacker: survivors('attacker'), defender: survivors('defender') });
    };
  }

  function checkEnd() {
    if (ended) return;
    const a = state.ships.some(s => !s.dead && s.side === 'attacker');
    const d = state.ships.some(s => !s.dead && s.side === 'defender');
    if (!a && !d) finish('defeat');
    else if (!a) finish(state.playerSide === 'attacker' ? 'defeat' : 'victory');
    else if (!d) finish(state.playerSide === 'defender' ? 'defeat' : 'victory');
  }

  // ── ЦИКЛ ─────────────────────────────────────────────────
  function update(rawDt) {
    tcam.update(rawDt);
    const dt = state.paused ? 0 : Math.min(rawDt, 0.05) * state.speed;
    if (dt > 0) {
      state.time += dt;
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
        if (sq.target && sq.target.dead) sq.target = null;
      }
      state.squads = state.squads.filter(s => !s.dead);
      checkEnd();
    }

    fx.update(rawDt);
    planet.rotation.y += rawDt * 0.006;
    if (fx.shake > 0.001) {
      const s = fx.shake * 3.2;
      tcam.cam.position.x += rnd(-s, s);
      tcam.cam.position.y += rnd(-s, s);
    }

    updateMarkers();
    updateSelVisuals();

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

    if (state.selection.some(s => s.dead)) {
      state.selection = state.selection.filter(s => !s.dead);
      refreshSel();
    }
  }

  function dispose() {
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
  tcam.focus(new THREE.Vector3(0, 0, state.playerSide === 'attacker' ? 110 : -110), 980);
  tcam.apply(1, true);

  return { scene, camera: tcam.cam, update, dispose, state };
}

// ─────────────────────────────────────────────────────────────
// БЫСТРЫЙ РАСЧЁТ — когда бой играть не хочется
// ─────────────────────────────────────────────────────────────

export function autoResolveSpace(attacker, defender) {
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
    return { dps, hp, air, pd };
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
