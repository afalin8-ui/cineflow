#!/usr/bin/env node
/* ВЫГРУЗКА ДАННЫХ БОЯ НА ОРБИТЕ ДЛЯ GODOT.

   Запуск из корня репозитория:
     node godot/tools/export_data.mjs          — пишет godot/data/space_data.json
     node godot/tools/export_data.mjs --md     — то же и печатает таблицы
                                                 для godot/spec/01-data.md
     node godot/tools/export_data.mjs --check  — ничего не пишет, только
                                                 сверяет файл на диске
                                                 с тем, что вышло бы сейчас
                                                 (код выхода 1 — устарел)

   Откуда числа. Всё, что лежит в game/js/data.js, берётся ИМПОРТОМ
   самого модуля — то есть ровно теми числами, что видит игра, после
   всех множителей кланов и округлений (SHIPS, STRIKE считаются при
   загрузке модуля). Производные функции (ECM_OF, SQUAD_SIZE_OF,
   ORBITAL_DEFENCE_OF, shipHasDrive) развёрнуты по кланам.

   Составы быстрого боя живут в main.js внутри обработчика меню, и
   импортировать main.js в node нельзя (он строит страницу). Поэтому
   объект `sizes` вырезается из ТЕКСТА main.js и вычисляется, а правила
   вокруг него (Плэктор ×2, Тройден ×0,7, резерв, станция) переписаны
   здесь — и каждое правило сверяется с исходником дословно. Поменяли
   main.js — выгрузка падает со словами «правило изменилось», а не
   выдаёт молча старое.

   Так же устроен блок `battle_constants`: числа, которые живут не
   в таблицах, а прямо в коде space.js (размер поля, расстановка флотов,
   формула корпуса, таймер ангара…). Каждое сверяется со строкой
   исходника, и в JSON уходит место, где она стоит сейчас (файл:строка). */

import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { execSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const OUT = path.join(ROOT, 'godot', 'data', 'space_data.json');
const SRC = {
  data: 'game/js/data.js',
  main: 'game/js/main.js',
  space: 'game/js/space.js',
};
const text = Object.fromEntries(Object.entries(SRC).map(([k, f]) => [k, readFileSync(path.join(ROOT, f), 'utf8')]));

const D = await import(pathToFileURL(path.join(ROOT, SRC.data)).href);

const args = new Set(process.argv.slice(2));
const fail = msg => { console.error('export_data: ' + msg); process.exit(2); };

/* Строка исходника обязана быть на месте. Отдаёт «файл:строка» —
   её и пишем рядом с числом, чтобы искать по коду было с чего начать. */
function where(key, snippet) {
  const src = text[key];
  const at = src.indexOf(snippet);
  if (at < 0) fail(`в ${SRC[key]} не нашлось «${snippet}» — правило в игре изменилось, поправь export_data.mjs`);
  if (src.indexOf(snippet, at + 1) >= 0) fail(`в ${SRC[key]} «${snippet}» встречается дважды — уточни образец`);
  return `${SRC[key]}:${src.slice(0, at).split('\n').length}`;
}

const clone = x => JSON.parse(JSON.stringify(x));
const hex = n => '#' + n.toString(16).padStart(6, '0');
/* Цвет в игре — целое 0xRRGGBB. Оставляем его как есть и кладём рядом
   строку «#rrggbb»: Color.html() в Godot читает её без пересчёта. */
function addHex(o) {
  if (Array.isArray(o)) { o.forEach(addHex); return o; }
  if (!o || typeof o !== 'object') return o;
  for (const k of Object.keys(o)) {
    const v = o[k];
    if (k === 'color' && typeof v === 'number') o.color_hex = hex(v);
    else addHex(v);
  }
  return o;
}

const F = D.FACTION_IDS;
const perFaction = fn => Object.fromEntries(F.map(f => [f, fn(f)]));

// ── кланы ────────────────────────────────────────────────────
const factions = perFaction(f => {
  const x = D.FACTIONS[f];
  return {
    id: x.id, name: x.name, short: x.short, tag: x.tag,
    color: x.color, colorCss: x.colorCss, style: x.style, doctrine: x.doctrine,
    motto: x.motto, desc: x.desc, perks: [...x.perks], weakness: x.weakness,
  };
});

// ── корабли: ровно SHIPS, плюс производные поля ──────────────
const ships = perFaction(f => D.SHIPS[f].map(s => ({
  ...clone(s),
  has_drive: D.shipHasDrive(s),                 // свой гиперпривод (кампания)
  hyper_time: (s.hyperCharge || 8) * D.HYPER.jumpCharge,   // сек накачки гипера в бою
})));

const strike = perFaction(f => clone(D.STRIKE[f]));
const station = { ...clone(D.STATION), hyper_time: null };

// ── составы быстрого боя (main.js, showSkirmish) ─────────────
const sizesSrc = (() => {
  const m = text.main.match(/const sizes = (\{[\s\S]*?\n  \});/);
  if (!m) fail('в main.js не нашлось `const sizes = {…};` — меню быстрого боя изменилось');
  return m[1];
})();
const sizes = Function(`"use strict"; return (${sizesSrc});`)();
const rules = {
  sizes: where('main', 'const sizes = {'),
  fleetOf: where('main', ".filter(([k, v]) => k !== 'regiments' && v > 0)"),
  scale: where('main', "const scaleFor = (f, list) => f === 'plektor'\n" +
    "    ? list.map(x => ({ ...x, count: Math.round(x.count * 2) }))\n" +
    "    : f === 'troyden' ? list.map(x => ({ ...x, count: Math.max(1, Math.round(x.count * 0.7)) })) : list;"),
  attacker: where('main', "attacker: { faction: mine, ships: scaleFor(mine, fleetOf(size)), reserve: scaleFor(mine, fleetOf('small')) },"),
  defender: where('main', "defender: { faction: foe, ships: scaleFor(foe, fleetOf(size)), station: size === 'big' },"),
  side: where('main', "playerSide: 'attacker', biome: 'klotho', title: 'Быстрый бой · орбита',"),
  gun: where('main', 'groundGun: foe,'),
  foeDefault: where('main', "el.querySelector('[data-f=\"foe\"]').value = 'plektor';"),
  sizeDefault: where('main', '<option value="mid" selected>Сражение</option>'),
};
// Порядок <option> в меню — порядок FACTION_IDS; первый и есть «Твой клан» по умолчанию
const SIZE_LABEL = { small: 'Стычка', mid: 'Сражение', big: 'Генеральное' };
for (const [k, lbl] of Object.entries(SIZE_LABEL)) where('main', `<option value="${k}"${k === 'mid' ? ' selected' : ''}>${lbl}</option>`);
const fleetOf = s => Object.entries(sizes[s]).filter(([k, v]) => k !== 'regiments' && v > 0).map(([id, count]) => ({ id, count }));
const scaleFor = (f, list) => f === 'plektor'
  ? list.map(x => ({ ...x, count: Math.round(x.count * 2) }))
  : f === 'troyden' ? list.map(x => ({ ...x, count: Math.max(1, Math.round(x.count * 0.7)) })) : list;

const shipOf = (f, id) => (id === 'station' ? D.STATION : D.shipDef(f, id));
function fleetSummary(f, list, withStation) {
  let n = 0, hp = 0, ehp = 0, dps = 0, pd = 0, bays = 0, cost = 0;
  const add = (d, c) => {
    n += c; hp += d.hp * c; ehp += d.hp / (1 - d.armor) * c; cost += (d.cost || 0) * c;
    for (const g of d.guns || []) dps += g.dmg * (g.salvo || 1) / g.cd * c;
    if (d.pd) pd += d.pd.dmg / d.pd.cd * d.pd.count * c;
    if (d.hangar) bays += d.hangar * c;
  };
  for (const it of list) add(shipOf(f, it.id), it.count);
  if (withStation) add(D.STATION, 1);
  const r = v => Math.round(v);
  return { ships: n, hp: r(hp), ehp: r(ehp), gun_dps: +dps.toFixed(1), pd_dps: +pd.toFixed(1), bays, cost: r(cost) };
}

const quick = {
  _src: rules,
  sizes: clone(sizes),
  size_ids: Object.keys(SIZE_LABEL),
  size_names: SIZE_LABEL,
  defaults: { mine: F[0], foe: 'plektor', size: 'mid', difficulty: 'normal' },
  player_side: 'attacker',
  biome: 'klotho',
  ground_gun: 'defender_faction',   // орудие планеты — клана ПРОТИВНИКА, бьёт по игроку
  station_on: ['big'],              // станция у защитника только в «Генеральном»
  scale: {
    plektor: { mul: 2, round: 'Math.round', min: 0 },
    troyden: { mul: 0.7, round: 'Math.round', min: 1 },
    reez: { mul: 1 }, devian: { mul: 1 },
    note: 'нулевые строки (capital: 0 в «Стычке») выбрасываются ДО множителя, поэтому min 1 их не возвращает',
  },
  fleets: Object.fromEntries(Object.keys(SIZE_LABEL).map(s => [s, perFaction(f => scaleFor(f, fleetOf(s)))])),
  reserve: perFaction(f => scaleFor(f, fleetOf('small'))),   // только у игрока (атакующего)
  summary: Object.fromEntries(Object.keys(SIZE_LABEL).map(s => [s, perFaction(f => ({
    attacker: fleetSummary(f, scaleFor(f, fleetOf(s)), false),
    defender: fleetSummary(f, scaleFor(f, fleetOf(s)), s === 'big'),
    reserve: fleetSummary(f, scaleFor(f, fleetOf('small')), false),
  }))])),
};

// ── числа из кода space.js, не из таблиц ──────────────────────
const C = (value, key, snippet, note) => ({ value, src: where(key, snippet), note });
const battle_constants = {
  field_half: C(2600, 'space', 'const FIELD = 2600;', 'половина стороны поля по x и z; корабль упирается в край и отражается с 0,3 скорости'),
  field_half_y: C(500, 'space', 'if (e.pos.y > 500) { e.pos.y = 500;', 'предел по высоте ±500'),
  deploy_z: C({ attacker: 950, defender: -950 }, 'space', "spawnFleet('attacker', config.attacker.ships, 950, false);", 'центр строя на старте; атакующий смотрит на −z'),
  deploy_cols: C('ceil(sqrt(n)) + 1', 'space', 'const cols = Math.ceil(Math.sqrt(rows.length)) + 1;', 'колонок в стартовой сетке; корабли отсортированы по radius по убыванию'),
  deploy_step_x: C(76, 'space', 'const x = (col - (cols - 1) / 2) * 76 + rnd(-10, 10);', 'шаг по x, разброс ±10'),
  deploy_step_z: C(72, 'space', 'const z = baseZ + side.sign * (row * 72 + back) + rnd(-12, 12);', 'шаг ряда назад от фронта, разброс ±12'),
  deploy_carrier_back: C(90, 'space', "const back = def.cls === 'carrier' ? 90 : 0;", 'носитель ещё на 90 глубже'),
  deploy_y: C({ jitter: 35, carrier_up: 30 }, 'space', "const y = rnd(-35, 35) + (def.cls === 'carrier' ? 30 : 0);", 'высота ±35, носитель на 30 выше'),
  deploy_station: C({ x_jitter: 70, y: 40, z_back: 190 }, 'space', 'if (station) spawnShip(sideId, STATION, new THREE.Vector3(rnd(-70, 70), 40, baseZ + side.sign * 190));', 'станция на 190 глубже центра строя защитника'),
  ai_opening_line_z: C(420, 'space', 'const line = s.pos.z > 0 ? 420 : -420;', 'ИИ на старте идёт на свой рубеж z=±420, x и y ×0,7; флот игрока стоит'),
  ai_opening_xy_k: C(0.7, 'space', 's.moveTo = new THREE.Vector3(s.pos.x * 0.7, s.pos.y * 0.7, line);'),
  len_fallback_k: C(6, 'space', 'const len = visualLength(obj) || def.radius * 6;', 'len = габарит модели max(x, z) без свечения; нет модели — radius × 6'),
  hull_formula: C({ radius_k: 1.6, len_k: 0.36 }, 'space', 'hull: Math.max(def.radius * 1.6, len * 0.36),', 'hull = max(1,6·radius; 0,36·len) — расталкивание и строй (C87)'),
  default_stance: C({ ship: 'guard', station: 'hold' }, 'space', "stance: def.station ? 'hold' : 'guard',"),
  name_numbering: C('roman', 'space', "const ROMAN = ['', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X'];", 'второй и далее корабль того же id у стороны — « II», « III»…; после X — «X» + следующий'),
  squad_rebuild: C(26, 'space', 'carrier.hangar.rebuild.push(state.time + 26);', 'сек до возврата места в ангар за ВЫБИТОЕ звено; севшее возвращает место сразу (C99)'),
  craft_radius: C(2.6, 'space', 'breakUntil: 0, radius: 2.6, slot: i,'),
  projectile: C({ life: 16, radius: 1.8, armor: 0, cls: 'torpedo' }, 'space', 'hp, maxHp: hp, armor: 0, dead: false, life: 16, radius: 1.8,', 'любая ракета/торпеда — цель класса torpedo для ПВО и перехватчиков'),
  missile_defaults: C({ speed: 120, hp: 24 }, 'space', 'def.missileSpeed || 120, def.missileHp || 24);', 'если у машины не задано (у всех ракетных задано)'),
  missile_miss_life: C(3.5, 'space', 'p.life = 3.5;', 'промахнувшаяся ракета живёт 3,5 с и летит без наведения'),
  ship_missile: C({ speed: 130, hp: 26 }, 'space', "const p = spawnProjectile(e, t, g.def.dmg * aiMul(e.side), 'missile', 130, 26);", 'ракетный пакет корабля («Синхо»): скорость и прочность каждой ракеты'),
  hyper_default_charge: C(8, 'space', 'const total = (e.def.hyperCharge || 8) * HYPER.jumpCharge;'),
  flee_rule: C('def.flee', 'space', 'if (e.def.flee && e.hp / e.maxHp < (e.def.flee || HYPER.fleeThreshold) && !e.station) {', 'сам уходит в гипер только корабль с полем flee; HYPER.fleeThreshold при этом не срабатывает никогда'),
  ecm_field_half_height_k: C(1.6, 'space', 'if (Math.abs(pos.y - f.pos.y) > E.height * 1.6) return false;', 'блин ловит по высоте ±height×1,6 от излучателя'),
  ecm_power_rate: C('dt / spinUp * 2.5', 'space', 'e.ecm.power += (want - e.ecm.power) * Math.min(1, dt / E.spinUp * 2.5);', 'мощность купола тянется к 0/1 экспонентой; поле действует при power > 0,05'),
  ecm_active_power: C(0.05, 'space', 'if (e.ecm.power > 0.05) {'),
  stealth_corvette_k: C(1.9, 'space', "const r = s.def.id === 'corvette' ? STEALTH.detectRange * 1.9 : STEALTH.detectRange;", 'корвет вскрывает скрытый корабль с 130 × 1,9 = 247'),
  stealth_craft_k: C({ k: 0.9, no_pd_range: 100 }, 'space', 'const r = (s.def.pd ? s.def.pd.range : 100) * 0.9;', 'скрытую МАШИНУ вскрывает корабль ближе 0,9 своей дальности ПВО'),
  blind_lock: C('ECM.lockRange', 'space', 'if (e.blindUntil && state.time < e.blindUntil && d > ECM.lockRange) continue;', 'ослеплённый с планеты бьёт только ближе 170 — базовый профиль, не клановый'),
  reinforce_drop: C({ base_z: 1200, per_row: 5, step_x: 90, step_z: 80, exit_speed_k: 2.6, exit_free_sec: 6, goto_x_k: 0.4, goto_z: 120 }, 'space', 'const baseZ = sign * 1200;', 'подкрепление выходит из гипера у своего края: 5 в ряд, скорость maxSpeed × 2,6, первые 6 с без ограничения скорости'),
  ground_gun_first: C(0.7, 'space', 'next: gdef.period * 0.7,', 'первый залп орудия планеты — на period × 0,7 с'),
  ground_gun_origin: C([340, -1180, -420], 'space', 'const GUN_ORIGIN = new THREE.Vector3(340, -1180, -420);'),
  emp_targets: C(2, 'space', 'for (const e of targets.slice(0, 2)) {', 'ЭМИ-капсулы — не больше двух целей: носители и все cls=capital, иначе любые'),
  updown_step: C(180, 'space', 'const UPDOWN = 180;', 'шаг «Выше/Ниже»'),
  brake_k: C(0.85, 'space', 'const aB = e.def.thrust * REV * 0.85;', 'торможение = thrust × SPACE_MOVE.reverse × 0,85'),
  ship_speed_cap_k: C(1.25, 'space', 'if (e.vel.length() > def.maxSpeed * 1.25 && !(e.exitUntil > state.time)) e.vel.setLength(def.maxSpeed * 1.25);'),
  craft_speed_cap_k: C(1.15, 'space', 'if (c.vel.length() > c.def.maxSpeed * 1.15) c.vel.setLength(c.def.maxSpeed * 1.15);'),
  ai_think: C({ first: '3 × tempo', every: 'rnd(2.5, 4) × tempo' }, 'space', 'ai.next = rnd(2.5, 4) * DIFF.tempo;', 'как часто думает ИИ, сек'),
  turret_arc: C({ ship: 0.25, station: -0.3 }, 'space', "if (e.dir.dot(_v) < (e.station ? -0.3 : 0.25)) continue;", 'стреляет, если cos угла между носом и целью не меньше этого'),
  pd_retarget: C({ idle: 0.2, cd_jitter: [0.85, 1.2] }, 'space', 'e.pdCd[i] = pd.cd * rnd(0.85, 1.2);', 'ствол ПВО без цели ждёт 0,2 с; после выстрела — cd × (0,85…1,2)'),
  sim_step: C({ max_frame: 0.05, speeds: [0, 1, 2, 4] }, 'space', 'const dt = (state.paused || ended) ? 0 : Math.min(rawDt, 0.05) * state.speed;',
    'шаг боя = min(кадр, 0,05) × скорость, ОДНИМ шагом (на 4× — до 0,2 с); стенд гоняет simStep по 1/30'),
  side_colors: C({ mine: '#8fffc8', foe: '#ff6b5a', mine_dim: '#5ce0a0', foe_dim: '#e05a4a' }, 'space', "const MINE_CSS = '#8fffc8', FOE_CSS = '#ff6b5a';",
    'свой/чужой — по стороне, не по клану (C43); цвет клана — только акцент'),
};
where('space', "const MINE_DIM = '#5ce0a0', FOE_DIM = '#e05a4a';");
where('space', '<button data-speed="4" title="Вчетверо быстрее">4×</button>');
where('space', "if (e.pos.y < -500) { e.pos.y = -500;");
where('space', "spawnFleet('defender', config.defender.ships, -950, config.defender.station);");
where('space', 'if (!t) { e.pdCd[i] = 0.2; continue; }');
where('space', 'next: 3 * DIFF.tempo,');
where('space', '(i % 5 - 2) * 90 + rnd(-15, 15)');
where('space', 'baseZ + sign * Math.floor(i / 5) * 80);');
where('space', 'sh.vel.set(0, 0, -sign * def.maxSpeed * 2.6);');
where('space', 'sh.exitUntil = state.time + 6;');
where('space', 'sh.moveTo = new THREE.Vector3(pos.x * 0.4, 0, sign * 120);');

/* ── ДЛИНА МОДЕЛИ (len) — не число из таблиц, а замер.
   В игре len = visualLength(модель): габарит max(x, z) без свечения
   и факелов (models.js). От него — hull (расталкивание, строй, C87),
   кольцо выделения и подпись (C78/C111). Своя .glb вписывается в длину
   процедурной того же слота (C88), поэтому для поведения важна именно
   длина процедурной. Она не зависит ни от клана, ни от случая (замер:
   шесть сборок подряд у каждого корабля каждого клана — одно число),
   а только от класса и radius. Модель в Godot надо масштабировать
   к этой длине, иначе разъедутся строй и расталкивание.
   Перемерить: node godot/tools/export_data.mjs --measure-len (нужны
   Playwright и Chromium, как у tests/game-e2e.js). */
const MODEL_LEN = {
  measured: '2026-10-10, коммит e8af7be, Chromium SwiftShader, buildShip(def, faction, true)',
  ship: { corvette: 41.99, frigate: 54.59, ecm: 55.36, cruiser: 112.86, carrier: 95.78, capital: 206.91, sinho: 169.29 },
  station: 121.84,
  strike: { interceptor: 13.52, fighter: 11.7, bomber: 11.7 },
};
for (const f of F) for (const s of D.SHIPS[f]) if (!(s.id in MODEL_LEN.ship)) fail(`нет замера длины модели для ${f}.${s.id} — запусти с --measure-len`);
const model_len = {
  _how: 'len = габарит модели max(x, z) без свечения (visualLength); hull = max(radius × 1.6, len × 0.36). ' +
        'Одинаков у всех кланов. Замер, не таблица: ' + MODEL_LEN.measured,
  ship: MODEL_LEN.ship, station: MODEL_LEN.station, strike: MODEL_LEN.strike,
  hull: Object.fromEntries(Object.entries(MODEL_LEN.ship).map(([id, len]) => {
    const r = D.SHIPS[F.find(f => D.shipDef(f, id))].find(s => s.id === id).radius;
    return [id, +Math.max(r * 1.6, len * 0.36).toFixed(2)];
  }).concat([['station', +Math.max(D.STATION.radius * 1.6, MODEL_LEN.station * 0.36).toFixed(2)]])),
};

// ── всё вместе ────────────────────────────────────────────────
const hash = f => createHash('sha256').update(readFileSync(path.join(ROOT, f))).digest('hex').slice(0, 16);
let commit = null;
try { commit = execSync('git rev-parse --short HEAD', { cwd: ROOT, stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim(); } catch (e) { /* без git — без номера */ }

const out = addHex({
  _meta: {
    what: 'Данные боя на орбите «Капеллы» для Godot. Числа — ровно те, что у игры на three.js.',
    generated_by: 'godot/tools/export_data.mjs',
    spec: 'godot/spec/01-data.md',
    commit,
    sources: Object.fromEntries(Object.values(SRC).map(f => [f, hash(f)])),
    units: {
      distance: 'единица мира (поле боя 5200 × 5200, высота ±500)',
      time: 'секунды игрового времени',
      speed: 'единиц в секунду',
      thrust: 'ускорение, единиц в секунду за секунду',
      turn: 'доля доворота за секунду: slerp(t = turn × dt, не больше 1)',
      armor: 'доля поглощённого урона 0…1 (урон × (1 − armor))',
      dmg: 'урон за выстрел (за одну ракету у salvo)',
      cd: 'перезарядка, сек',
      hp: 'прочность, единиц',
    },
  },
  faction_ids: [...F],
  factions,
  space_dmg: clone(D.SPACE_DMG),
  space_tough: D.SPACE_TOUGH,
  ships,
  station,
  strike,
  strike_roles: clone(D.STRIKE_ROLES),
  squad_size_default: D.SQUAD_SIZE,
  squad_size: perFaction(f => D.SQUAD_SIZE_OF(f)),
  stealth: clone(D.STEALTH),
  ecm_base: clone(D.ECM),
  ecm: perFaction(f => clone(D.ECM_OF(f))),
  hyper: clone(D.HYPER),
  hyper_own: [...D.HYPER_OWN],
  orbital_defence: perFaction(f => clone(D.ORBITAL_DEFENCE_OF(f))),
  difficulty_ids: [...D.DIFF_IDS],
  difficulty: clone(D.DIFFICULTY),
  space_stance_ids: [...D.SPACE_STANCE_IDS],
  space_stances: clone(D.SPACE_STANCES),
  space_move: clone(D.SPACE_MOVE),
  quick_battle: quick,
  battle_constants,
  model_len,
});

// ── самопроверка ──────────────────────────────────────────────
const json = JSON.stringify(out, null, 1) + '\n';
const back = JSON.parse(json);
for (const f of F) {
  if (!back.factions[f] || !back.ships[f] || !back.strike[f] || !back.ecm[f] || !back.orbital_defence[f])
    fail(`в выгрузке нет клана ${f}`);
  if (back.ships[f].length !== D.SHIPS[f].length) fail(`у ${f} потерялись корабли`);
}
// числа сверяем с модулем ещё раз, уже после круга через JSON
const same = (a, b, p) => {
  if (typeof a === 'number' || typeof b === 'number') { if (!Object.is(a, b)) fail(`${p}: ${a} ≠ ${b}`); return; }
  if (a && typeof a === 'object') for (const k of Object.keys(a)) same(a[k], b[k], `${p}.${k}`);
};
for (const f of F) { same(D.SHIPS[f], back.ships[f], `ships.${f}`); same(D.STRIKE[f], back.strike[f], `strike.${f}`); }
same(D.STATION, back.station, 'station');

if (args.has('--measure-len')) {
  const got = await measureLen();
  const diff = [];
  for (const [id, v] of Object.entries(got.ship)) if (MODEL_LEN.ship[id] !== v) diff.push(`${id}: ${MODEL_LEN.ship[id]} → ${v}`);
  if (MODEL_LEN.station !== got.station) diff.push(`station: ${MODEL_LEN.station} → ${got.station}`);
  for (const [id, v] of Object.entries(got.strike)) if (MODEL_LEN.strike[id] !== v) diff.push(`${id}: ${MODEL_LEN.strike[id]} → ${v}`);
  console.log(JSON.stringify(got, null, 1));
  if (got.varies.length) console.log('РАЗНЯТСЯ между кланами или сборками: ' + got.varies.join(', '));
  if (diff.length) { console.error('export_data: длины моделей изменились — перепиши MODEL_LEN:\n  ' + diff.join('\n  ')); process.exit(1); }
  console.log('export_data: длины моделей те же, что в MODEL_LEN');
  process.exit(0);
}

if (args.has('--check')) {
  const old = existsSync(OUT) ? readFileSync(OUT, 'utf8') : '';
  // commit не сравниваем: он меняется от каждого коммита, а числа — нет
  const norm = s => s.replace(/"commit": [^\n]*\n/, '');
  if (norm(old) !== norm(json)) { console.error('export_data: godot/data/space_data.json устарел — запусти без --check'); process.exit(1); }
  console.log('export_data: space_data.json совпадает с игрой');
  process.exit(0);
}

mkdirSync(path.dirname(OUT), { recursive: true });
writeFileSync(OUT, json);
console.log(`export_data: ${path.relative(ROOT, OUT)} — ${(json.length / 1024).toFixed(1)} КБ, кланы: ${F.join(', ')}, ` +
  `кораблей: ${F.map(f => `${f} ${D.SHIPS[f].length}`).join(', ')}`);

// ── таблицы для спецификации ──────────────────────────────────
if (args.has('--md')) {
  const row = c => `| ${c.join(' | ')} |`;
  const P = [];
  for (const f of F) {
    P.push(`\n#### ${D.FACTIONS[f].name}\n`);
    P.push(row(['id', 'имя', 'cls', 'tier', 'hp', 'armor', 'maxSpeed', 'thrust', 'turn', 'radius', 'cost', 'build', 'hyper', 'flee', 'орудия (тип dmg/cd/range…)', 'ПВО count×dmg/cd/range', 'ангар']));
    P.push(row(Array(17).fill('---')));
    for (const s of D.SHIPS[f]) {
      const guns = (s.guns || []).map(g => `${g.type} ${g.dmg}/${g.cd}/${g.range}` +
        (g.charge ? ` заряд ${g.charge}` : '') + (g.salvo ? ` ×${g.salvo} разброс ${g.spread}` : '')).join('; ') || '—';
      const pd = s.pd ? `${s.pd.count}×${s.pd.dmg}/${s.pd.cd}/${s.pd.range}` : '—';
      P.push(row([s.id, s.name, s.cls, s.tier, s.hp, s.armor, s.maxSpeed, s.thrust, s.turn, s.radius, s.cost, s.build,
        s.hyperCharge, s.flee || '—', guns, pd, s.hangar || '—']));
    }
  }
  P.push('\n#### Авиация\n');
  P.push(row(['клан', 'роль', 'имя', 'hp', 'armor', 'maxSpeed', 'thrust', 'turn', 'weapon', 'dmg', 'cd', 'range', 'ammo', 'reloads', 'reloadTime', 'miss', 'missileSpeed', 'missileHp', 'stealth']));
  P.push(row(Array(19).fill('---')));
  for (const f of F) for (const r of ['interceptor', 'fighter', 'bomber']) {
    const s = D.STRIKE[f][r];
    P.push(row([f, r, s.name, s.hp, s.armor, s.maxSpeed, s.thrust, s.turn, s.weapon, s.dmg, s.cd, s.range,
      s.ammo ?? '—', s.reloads ?? '—', s.reloadTime ?? '—', s.missChance ?? '—', s.missileSpeed ?? '—', s.missileHp ?? '—', s.stealth]));
  }
  P.push('\n#### Составы быстрого боя (после множителя клана)\n');
  P.push(row(['масштаб', 'клан', 'состав', 'кораблей', 'hp', 'hp/(1−armor)', 'урон орудий/с', 'ПВО/с', 'ангаров']));
  P.push(row(Array(9).fill('---')));
  for (const s of Object.keys(SIZE_LABEL)) for (const f of F) {
    const list = quick.fleets[s][f], sm = quick.summary[s][f].attacker;
    P.push(row([SIZE_LABEL[s], f, list.map(x => `${x.id} ${x.count}`).join(', '), sm.ships, sm.hp, sm.ehp, sm.gun_dps, sm.pd_dps, sm.bays]));
  }
  P.push('\n#### Резерв игрока (= «Стычка» своего клана)\n');
  for (const f of F) {
    const sm = quick.summary.small[f].reserve;
    P.push(`- ${f}: ${quick.reserve[f].map(x => `${x.id} ${x.count}`).join(', ')} — ${sm.ships} кораблей, hp ${sm.hp}`);
  }
  P.push('\n#### Выстрелов до гибели (Офицер, aim 1)\n');
  P.push(ttkTable('troyden', 'plektor'));
  P.push('');
  P.push(ttkTable('plektor', 'troyden'));
  console.log(P.join('\n'));
}

/* Выстрелов до гибели: оружие стрелка против кораблей цели, на «Офицере»
   (aim = 1). ceil(hp / (dmg × SPACE_DMG[оружие][cls] × (1 − armor))),
   у ракетного пакета — ракет. «—» — оружие эту цель не берёт вовсе. */
function ttkTable(fa, fb) {
  const row = c => `| ${c.join(' | ')} |`;
  const tg = D.SHIPS[fb].concat([D.STATION]);
  const out = [row([`${fa} → ${fb}`, ...tg.map(s => s.id)]), row(Array(tg.length + 1).fill('---'))];
  const shots = (dmg, w, t) => {
    const m = D.dmgMult(D.SPACE_DMG, w, t.cls);
    return m <= 0 ? '—' : Math.ceil(t.hp / (dmg * m * (1 - t.armor)));
  };
  for (const s of D.SHIPS[fa]) {
    if (!s.guns.length) continue;
    const g = s.guns[0];
    out.push(row([`${s.id} (${g.type} ${g.dmg})`, ...tg.map(t => shots(g.dmg, g.type, t))]));
    if (s.guns[1] && s.guns[1].type !== g.type) {
      const h = s.guns[1];
      out.push(row([`${s.id} (${h.type} ${h.dmg})`, ...tg.map(t => shots(h.dmg, h.type, t))]));
    }
  }
  for (const r of ['interceptor', 'fighter', 'bomber']) {
    const c = D.STRIKE[fa][r];
    out.push(row([`${r} (${c.weapon} ${+c.dmg.toFixed(2)})`, ...tg.map(t => shots(c.dmg, c.weapon, t))]));
  }
  return out.join('\n');
}

/* Замер длины процедурных моделей в настоящем браузере — тем же кодом
   models.js, что строит корабли в бою. */
async function measureLen() {
  const { spawn } = await import('node:child_process');
  const { createRequire } = await import('node:module');
  const req = createRequire(import.meta.url);
  let pw;
  try { pw = req('playwright'); } catch (e) { pw = req(execSync('npm root -g').toString().trim() + '/playwright'); }
  const port = +(process.env.EXPORT_PORT || 8391);
  const srv = spawn('python3', ['-I', '-m', 'http.server', String(port), '--bind', '127.0.0.1', '--directory', ROOT], { stdio: 'ignore' });
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  try {
    let up = false;
    for (let i = 0; i < 60 && !up; i++) {
      up = await fetch(`http://127.0.0.1:${port}/game/js/data.js`).then(r => r.ok, () => false);
      if (!up) await sleep(200);
    }
    if (!up) fail(`сервер на порту ${port} не поднялся (EXPORT_PORT — другой порт)`);
    const browser = await pw.chromium.launch({
      executablePath: process.env.CHROMIUM || '/opt/pw-browsers/chromium',
      args: ['--no-sandbox', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'],
    });
    try {
      const ctx = await browser.newContext({ viewport: { width: 800, height: 600 }, serviceWorkers: 'block' });
      const page = await ctx.newPage();
      await page.goto(`http://127.0.0.1:${port}/game/index.html`);
      await page.waitForFunction(() => window.__capellaUp, null, { timeout: 120000 });
      return await page.evaluate(async () => {
        const M = await import('/game/js/models.js');
        const D = await import('/game/js/data.js');
        const r2 = v => +v.toFixed(2);
        const got = { ship: {}, station: 0, strike: {}, varies: [] };
        const take = (key, build) => {
          const v = [];
          for (let i = 0; i < 3; i++) v.push(r2(M.visualLength(build())));
          if (new Set(v).size > 1) got.varies.push(key);
          return v[0];
        };
        for (const f of D.FACTION_IDS) {
          const fac = D.FACTIONS[f];
          for (const s of D.SHIPS[f]) {
            const v = take(`${f}.${s.id}`, () => M.buildShip(s, fac, true));
            if (got.ship[s.id] !== undefined && got.ship[s.id] !== v) got.varies.push(`${f}.${s.id}`);
            if (got.ship[s.id] === undefined) got.ship[s.id] = v;
          }
          for (const r of ['interceptor', 'fighter', 'bomber']) {
            const v = take(`${f}.${r}`, () => M.buildStrike(r, fac));
            if (got.strike[r] !== undefined && got.strike[r] !== v) got.varies.push(`${f}.${r}`);
            if (got.strike[r] === undefined) got.strike[r] = v;
          }
        }
        got.station = take('station', () => M.buildShip(D.STATION, D.FACTIONS.troyden, true));
        return got;
      });
    } finally { await browser.close(); }
  } finally { srv.kill(); }
}
