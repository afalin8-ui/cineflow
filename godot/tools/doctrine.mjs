#!/usr/bin/env node
/* ПРОВЕРКА ЧИСЕЛ ДОКТРИНЫ — godot/data/doctrine.json.

   Запуск из корня репозитория:
     node godot/tools/doctrine.mjs --check   — проверить файл и напечатать
                                               таблицу батареи по кланам;
                                               код выхода 1 — нашлась беда
     node godot/tools/doctrine.mjs           — то же самое (без --check
                                               ничего не пишется: файл
                                               правят руками)
     node godot/tools/doctrine.mjs --check --doctrine=путь
                                             — проверить другой файл
                                               (так проверки откатом
                                               подсовывают испорченную копию)

   Что проверяется (часть 09, 0.1; план, G0 п. 2):
   - у каждого числа есть why и раздел части 09, и такой раздел есть;
   - числа живут только внутри записей (v, was): число без why — беда;
   - ссылки — только на существующие кланы, id кораблей, классы целей
     и ключи оружия выгрузки space_data.json; ref — на существующую запись;
   - порядок порогов: мёртвая зона < «путь чист» < «пояс восстановлен»
     (0,4 < 0,45 < 0,5), батарея не короче мёртвой зоны;
   - узлы кораблей сходятся с оружием выгрузки и числом установок батареи;
   - каждая строка приложения 09 закрыта записью;
   - таблица батареи по кланам, посчитанная ТОЙ ЖЕ формулой, что data.js
     (Math.round и toFixed), совпадает с таблицей 09, 1.3, — и печатается. */

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const argv = process.argv.slice(2);
const opt = name => {
  const a = argv.find(x => x.startsWith(`--${name}=`));
  return a ? a.slice(name.length + 3) : null;
};
const DOCTRINE = path.resolve(ROOT, opt('doctrine') || 'godot/data/doctrine.json');
const SPACE = path.resolve(ROOT, opt('space') || 'godot/data/space_data.json');
const SPEC = path.resolve(ROOT, opt('spec') || 'godot/spec/09-doctrine.md');


function readJson(file) {
  const text = readFileSync(file, 'utf8');
  try {
    return JSON.parse(text);
  } catch (e) {
    // Node пишет «at position N» — переводим в строку файла: «где» важнее «что»
    const m = /position (\d+)/.exec(e.message);
    const line = m ? text.slice(0, Number(m[1])).split('\n').length : '?';
    console.error(`doctrine: ${path.relative(ROOT, file)}, строка ${line}: файл не читается как JSON (${e.message})`);
    process.exit(1);
  }
}


function check(doc, space, spec, say = () => {}) {
  const problems = [];
  const bad = msg => problems.push(msg);
  // ── разделы части 09: «## 5.» и «### 5.2» ──
  const sections = new Set();
  for (const m of spec.matchAll(/^#{2,3} (\d+(?:\.\d+)?)[. ]/gm)) sections.add(m[1]);

  // ── что есть в выгрузке ──
  const factionIds = space.faction_ids;
  const dmgClasses = Object.keys(space.space_dmg.heavy);
  const weaponKeys = Object.keys(space.space_dmg);
  const shipById = {};                 // id → описание (у всех кланов одинаковый набор полей)
  for (const f of factionIds) for (const s of space.ships[f]) if (!shipById[s.id]) shipById[s.id] = s;
  shipById.station = space.station;
  const ROLE_OF = { heavy: 'main', missile: 'missile', light: 'light' };

  // ── обход записей ──
  const ENTRY_KEYS = new Set(['v', 'ref', 'rule', 'why', 'sec', 'row', 'was']);
  const entries = {};                  // путь → запись
  function walk(node, at) {
    for (const [k, v] of Object.entries(node)) {
      const p = at ? `${at}.${k}` : k;
      if (k.startsWith('_')) {
        if (typeof v !== 'string') bad(`${p}: поле с «_» — только для пояснений словами`);
        continue;
      }
      if (v === null || typeof v !== 'object' || Array.isArray(v)) {
        bad(`${p}: ${JSON.stringify(v)} лежит вне записи — у числа нет why и раздела`);
        continue;
      }
      if ('why' in v) { entries[p] = v; continue; }
      if ('v' in v || 'ref' in v || 'rule' in v) { bad(`${p}: запись без why`); continue; }
      walk(v, p);
    }
  }
  walk(doc, '');

  const numbersIn = x => typeof x === 'number' ? [x]
    : Array.isArray(x) ? x.flatMap(numbersIn)
    : (x && typeof x === 'object') ? Object.values(x).flatMap(numbersIn) : [];

  for (const [p, e] of Object.entries(entries)) {
    for (const k of Object.keys(e)) if (!ENTRY_KEYS.has(k)) bad(`${p}: поле «${k}» неизвестно (бывают ${[...ENTRY_KEYS].join(', ')})`);
    if (typeof e.why !== 'string' || e.why.trim().length < 10) bad(`${p}: why пустое или в пару слов — напиши, почему такое число`);
    if (typeof e.sec !== 'string' || !sections.has(e.sec)) bad(`${p}: раздел «${e.sec}» — такого раздела в части 09 нет`);
    const kinds = ['v', 'ref', 'rule'].filter(k => k in e);
    if (kinds.length !== 1) bad(`${p}: значение задаётся ровно одним из v, ref, rule (сейчас: ${kinds.join(', ') || 'ничего'})`);
    if ('v' in e && numbersIn(e.v).length === 0 && !p.startsWith('nodes')) bad(`${p}: в v нет ни одного числа`);
    for (const n of numbersIn(e.v ?? null).concat(numbersIn(e.was ?? null))) if (!Number.isFinite(n)) bad(`${p}: число ${n} не конечно`);
    if ('ref' in e && !(e.ref in entries)) bad(`${p}: ref «${e.ref}» — такой записи нет`);
    if ('rule' in e && typeof e.rule !== 'string') bad(`${p}: rule — правило словами`);
  }

  const num = p => {
    const e = entries[p];
    if (!e) { bad(`нет записи ${p}`); return NaN; }
    if ('ref' in e) return num(e.ref);
    if (typeof e.v !== 'number') { bad(`${p}: ждали одно число`); return NaN; }
    return e.v;
  };
  const map = p => {
    const e = entries[p];
    if (!e || !e.v || typeof e.v !== 'object' || Array.isArray(e.v)) { bad(`${p}: ждали таблицу`); return {}; }
    return e.v;
  };
  const sameKeys = (p, got, want) => {
    const g = [...got].sort().join(','), w = [...want].sort().join(',');
    if (g !== w) bad(`${p}: ключи [${g}], а должны быть [${w}]`);
  };

  // ── ссылки на выгрузку ──
  const clan = map('clan');
  sameKeys('clan', Object.keys(clan), factionIds);
  for (const [f, m] of Object.entries(clan)) {
    sameKeys(`clan.${f}`, Object.keys(m), ['gunMod', 'cdMod']);
    for (const k of ['gunMod', 'cdMod']) if (!(m[k] > 0)) bad(`clan.${f}.${k}: ждали положительное число`);
  }
  sameKeys('ecm.main_slow', Object.keys(map('ecm.main_slow')), ['default', ...factionIds.filter(f => f in map('ecm.main_slow'))]);
  for (const k of Object.keys(map('ecm.main_slow'))) if (k !== 'default' && !factionIds.includes(k)) bad(`ecm.main_slow.${k}: нет такого клана`);
  sameKeys('space_dmg.sec', Object.keys(map('space_dmg.sec')), dmgClasses);
  if (weaponKeys.includes('sec')) bad('space_dmg.sec: в выгрузке уже есть строка sec — правка доктрины её затёрла бы');
  if (typeof space.space_dmg.pd?.torpedo !== 'number') bad('space_dmg.pd_torpedo: в выгрузке нет space_dmg.pd.torpedo');
  for (const f of factionIds) {
    const b = space.strike[f]?.bomber;
    if (!b || !b.torpedo || typeof b.missileSpeed !== 'number') bad(`torp.speed: у бомбардировщика ${f} нет торпеды со скоростью`);
  }

  const mounts = map('sec.mounts');
  const heavyIds = Object.keys(shipById).filter(id => (shipById[id].guns || []).some(g => g.type === 'heavy'));
  sameKeys('sec.mounts', Object.keys(mounts), heavyIds);
  for (const [id, n] of Object.entries(mounts)) if (!Number.isInteger(n) || n < 1) bad(`sec.mounts.${id}: число установок — целое от 1`);

  // ── узлы кораблей ──
  const nodes = map('nodes');
  sameKeys('nodes', Object.keys(nodes), Object.keys(shipById));
  const AFFECTS = new Set(['thrust', 'turn', 'max_speed', 'hyper']);
  for (const [id, list] of Object.entries(nodes)) {
    const s = shipById[id];
    if (!s) continue;
    const want = new Set();
    const guns = s.guns || [];
    for (const [type, role] of Object.entries(ROLE_OF)) guns.filter(g => g.type === type).forEach((_, i) => want.add(`${role}_${i}`));
    for (let i = 0; i < (mounts[id] || 0); i++) want.add(`sec_${i}`);
    if (s.pd) want.add('pd');
    if (s.ecm) want.add('ecm');
    if (s.hangar) want.add('hangar');
    if (s.maxSpeed > 0) want.add('engines');
    want.add('hull');
    sameKeys(`nodes.${id}`, Object.keys(list), [...want]);
    for (const [n, d] of Object.entries(list)) {
      if (typeof d.model !== 'string' || !d.model) bad(`nodes.${id}.${n}: нет имени узла в сцене (model)`);
      if (d.part === 'weapon') {
        const [role, idx] = n.split('_');
        if (d.weapon !== role) bad(`nodes.${id}.${n}: weapon «${d.weapon}», а по имени — ${role}`);
        if (idx !== undefined && d.index !== Number(idx)) bad(`nodes.${id}.${n}: index ${d.index}, а по имени — ${idx}`);
      } else if (d.part === 'engines') {
        for (const a of d.affects || []) if (!AFFECTS.has(a)) bad(`nodes.${id}.${n}: неизвестное «${a}»`);
      } else if (d.part !== 'system' && d.part !== 'sides') bad(`nodes.${id}.${n}: part «${d.part}» неизвестен`);
    }
  }

  // ── порядок порогов ──
  const dead = num('main.dead_k'), clear = num('belt.clear_k'), backOff = num('belt.back_off_k');
  const work = num('belt.work_k'), far = num('belt.far_k'), secK = num('sec.range_k');
  if (!(dead < clear && clear < backOff)) bad(`порядок порогов: ждали мёртвая зона < путь чист < пояс восстановлен, а ${dead} / ${clear} / ${backOff}`);
  if (!(secK >= dead)) bad(`sec.range_k ${secK} короче мёртвой зоны ${dead}: кольцо, где тяжёлый не бьёт ничем`);
  if (!(dead < work && work < far && far <= 1)) bad(`пояс: ждали мёртвая зона < рабочая точка < «дальше пояса» ≤ 1, а ${dead} / ${work} / ${far}`);
  if (num('camera.dist_min') >= num('camera.dist_max')) bad('camera: ближний предел не меньше дальнего');
  if (num('camera.far') <= num('camera.dist_max') * 1.27) bad('camera.far: дальняя плоскость ближе дальнего края стола в кадре (1,27 × dist_max)');

  // ── строки приложения 09 ──
  const app = spec.slice(spec.indexOf('## Приложение'));
  if (app.length < 100) bad('в части 09 не нашлось «## Приложение»');
  const covered = new Set(Object.keys(entries));
  for (const e of Object.values(entries)) if (e.row) covered.add(e.row);
  let rows = 0;
  for (const line of app.split('\n')) {
    if (!line.startsWith('| `')) continue;
    const cell = line.split('|')[1];
    const keys = [...cell.matchAll(/`([^`]+)`/g)].map(m => m[1]);
    const first = keys[0];
    const prefix = first.includes('.') ? first.slice(0, first.indexOf('.') + 1) : '';
    for (const k of keys) {
      const full = k.includes('.') ? k : prefix + k;
      rows++;
      if (!covered.has(full)) bad(`приложение 09: «${full}» не закрыт ни одной записью doctrine.json`);
    }
  }
  if (rows < 40) bad(`приложение 09: прочитано ключей ${rows} — таблица не разобралась`);

  // ── ЗНАЧЕНИЯ строк приложения 09 против записей (хвост G0: опечатка в числе
  //    обязана краснеть, а не только пропавший ключ) ──
  // Числа ячейки «число» по порядку против чисел записей строки по порядку (ключи —
  // как в ячейке «ключ», записи — в порядке файла; ref разворачивается). Числа
  // в «(было …)» — против поля was. Знак не сравниваем: «−440» в таблице — это
  // «440 позади» в записи. Слова с числами, которые не значения записей, — в CELL_WORDS,
  // у каждого причина.
  const CELL_WORDS = {
    'retreat.no_forward': [['составляющая к противнику — 0', 'составляющая к противнику — нет'],
      'ноль — правило «вперёд не отходить», а не число записи'],
    'leash.frigate_ai': [['(корветы — 240)', ''],
      'поводок корветов 240 — из выгрузки (space_stances.guard.leash), не запись доктрины'],
    'ai.air': [['max(1, мест/2)', 'мест × 0,5, но не меньше 1'],
      '«мест/2» — это множитель 0,5 (ai.air_bomber_slots_k) и нижний предел 1'],
    'air.bomber_flank': [['и `L`', 'и `1 L`'], 'вторая точка — на целой L (1,0)'],
  };
  const NUM_RE = /\d+(?:,\d+)?/g;
  const nums = t => [...t.matchAll(NUM_RE)].map(m => Number(m[0].replace(',', '.')));
  const valuesOf = e => 'ref' in e ? [num(e.ref)] : numbersIn(e.v ?? null);
  const fmt = a => '[' + a.join(', ') + ']';
  let valueRows = 0;
  for (const line of app.split('\n')) {
    if (!line.startsWith('| `')) continue;
    const cells = line.split('|').map(x => x.trim());
    const keys = [...cells[1].matchAll(/`([^`]+)`/g)].map(m => m[1]);
    const prefix = keys[0].includes('.') ? keys[0].slice(0, keys[0].indexOf('.') + 1) : '';
    const full = keys.map(k => k.includes('.') ? k : prefix + k);
    let cell = cells[2];
    const fix = CELL_WORDS[full[0]];
    if (fix) {
      if (!cell.includes(fix[0][0])) bad(`приложение 09, ${full[0]}: в ячейке нет «${fix[0][0]}» — правило CELL_WORDS устарело (${fix[1]})`);
      cell = cell.replace(fix[0][0], fix[0][1]);
    }
    const wasText = [...cell.matchAll(/было[^)]*/g)].map(m => m[0]).join(' ');
    const nowText = cell.replace(/было[^)]*/g, ' ');
    const want = nums(nowText), wantWas = nums(wasText);
    const list = [];
    for (const k of full) for (const [p, e] of Object.entries(entries)) if (p === k || e.row === k) if (!list.includes(e)) list.push(e);
    if (!list.length) continue;            // пропавший ключ — уже беда выше
    const got = list.flatMap(valuesOf).map(Math.abs);
    const gotWas = list.flatMap(e => numbersIn(e.was ?? null)).map(Math.abs);
    valueRows++;
    const same = (a, b) => a.length === b.length && a.every((x, i) => Math.abs(x - b[i]) < 1e-9);
    if (!same(got, want)) bad(`значение: ${full.join(' / ')} — в doctrine.json ${fmt(got)}, а в приложении 09 «${cells[2]}» → ${fmt(want)}`);
    if (!same(gotWas, wantWas)) bad(`значение «было»: ${full.join(' / ')} — в doctrine.json was ${fmt(gotWas)}, а в приложении 09 ${fmt(wantWas)}`);
  }
  if (valueRows < 40) bad(`приложение 09: сверено значений строк ${valueRows} — таблица не разобралась`);

  // ── батарея по кланам: формула data.js (Math.round, toFixed) ──
  const base = { dmg: num('sec.dmg'), cd: num('sec.cd') };
  const NAME = { cruiser: 'крейсер', sinho: '«Синхо»', capital: 'флагман' };
  const table = [];
  for (const f of factionIds) {
    for (const s of space.ships[f]) {
      if (!(s.id in mounts)) continue;
      const m = clan[f];
      const dmg = Math.round(base.dmg * m.gunMod);
      const cd = Number((base.cd * m.cdMod).toFixed(2));
      const R = s.guns.find(g => g.type === 'heavy').range;
      const dps = mounts[s.id] * dmg / cd;
      table.push({ f, id: s.id, n: mounts[s.id], dmg, cd, range: Math.round(secK * R), dps: Math.round(dps * 10) / 10 });
    }
  }
  // сверка с таблицей «Итог по кланам» части 09, 1.3
  const CLAN_RU = { 'Тройден': 'troyden', 'Плэктор': 'plektor', 'Рииз': 'reez', 'Девиан': 'devian' };
  const SHIP_RU = { 'крейсер': 'cruiser', '«Синхо»': 'sinho', 'флагман': 'capital' };
  const s13 = spec.slice(spec.indexOf('**Итог по кланам**'), spec.indexOf('**Почему такие числа'));
  let specRows = 0;
  for (const line of s13.split('\n')) {
    const c = line.split('|').map(x => x.trim());
    if (c.length < 6 || !(c[1] in CLAN_RU)) continue;
    const ships = c[2].split(' / ').map(x => SHIP_RU[x]);
    const dps = c[4].split(' / ').map(x => Number(x.replace(',', '.')));
    ships.forEach((id, i) => {
      specRows++;
      const got = table.find(t => t.f === CLAN_RU[c[1]] && t.id === id);
      if (!got) bad(`батарея ${c[1]} ${c[2]}: в doctrine.json такой нет`);
      else if (Math.abs(got.dps - dps[i]) > 1e-9) bad(`батарея ${c[1]} ${id}: ${got.dps} урона в секунду, а в 09, 1.3 — ${dps[i]}`);
    });
  }
  if (specRows < 9) bad(`09, 1.3: прочитано строк батареи ${specRows} из 9 — таблица не разобралась`);

  say('Батарея по кланам (09, 1.3; формула data.js: round(24 × gunMod), toFixed(2)(2,5 × cdMod)):');
  for (const t of table) {
    say(`  ${t.f.padEnd(8)} ${t.id.padEnd(8)} ${t.n} × ${String(t.dmg).padStart(2)} / ${String(t.cd).padEnd(4)} / ${t.range}  → ${t.dps.toFixed(1)} урона в секунду`);
  }
  const st = Math.round(secK * space.station.guns[0].range);
  say(`  станция  (без множителей клана) ${mounts.station} × ${base.dmg} / ${base.cd} / ${st}  → ${(mounts.station * base.dmg / base.cd).toFixed(1)} урона в секунду`);

  return { problems, entries: Object.keys(entries).length, rows };
}

/* Проверка откатом (план, раздел 1): каждая проверка обязана краснеть
   на испорченной копии. Портим копию в памяти и ждём своё слово в отчёте. */
function selftest() {
  const clone = x => JSON.parse(JSON.stringify(x));
  const cases = [
    ['число без why', d => { delete d.main.escort_weight.why; }, 'запись без why'],
    ['число вне записи', d => { d.main.stray = 3; }, 'лежит вне записи'],
    ['раздела нет в 09', d => { d.main.dead_k.sec = '1.99'; }, 'такого раздела'],
    ['ref в пустоту', d => { d.belt.back_on_k.ref = 'main.nope'; }, 'такой записи нет'],
    ['чужой клан', d => { d.clan.v.zorg = { gunMod: 1, cdMod: 1 }; }, 'clan: ключи'],
    ['нет id корабля', d => { d.sec.mounts.v.dreadnought = 2; }, 'sec.mounts: ключи'],
    ['класс цели', d => { d.space_dmg.sec.v.planet = 1; }, 'space_dmg.sec: ключи'],
    ['порядок 0,4 < 0,45 < 0,5', d => { d.belt.clear_k.v = 0.55; }, 'порядок порогов'],
    ['строка приложения', d => { delete d.air.patrol_k; }, 'air.patrol_k'],
    ['таблица батареи', d => { d.clan.v.troyden.gunMod = 1.2; }, 'батарея Тройден'],
    ['узлы и батарея', d => { delete d.nodes.v.cruiser.sec_1; }, 'nodes.cruiser'],
    // хвост G0: прежняя проверка ловила только пропавший КЛЮЧ, опечатку в числе — нет
    ['опечатка в числе', d => { d.belt.far_k.v = 0.93; }, 'значение: belt.far_k'],
    ['опечатка в таблице', d => { d.sec.mounts.v.cruiser = 3; }, 'значение: sec.mounts'],
    ['опечатка в ref', d => { d.main.dead_k.v = 0.41; }, 'значение: belt.back_on'],
    ['опечатка в «было»', d => { d.torp.speed.was = 80; }, 'значение «было»: torp.speed'],
    ['число из нескольких записей', d => { d.retreat.futile_gain.v = 25; }, 'значение: retreat.futile'],
  ];
  let fails = 0;
  const clean = check(doc, space, spec);
  if (clean.problems.length) { console.error('selftest: чистый файл уже с бедами:', clean.problems); process.exit(1); }
  for (const [name, spoil, word] of cases) {
    const d = clone(doc);
    spoil(d);
    const r = check(d, space, spec);
    const hit = r.problems.some(p => p.includes(word));
    if (!hit) { fails++; console.error(`selftest: «${name}» не покраснело (ждали «${word}»): ${JSON.stringify(r.problems)}`); }
    else console.log(`selftest: «${name}» — краснеет`);
  }
  console.log(`RESULT checks=${cases.length + 1} fails=${fails}`);
  process.exit(fails ? 1 : 0);
}

const doc = readJson(DOCTRINE);
const space = readJson(SPACE);
const spec = readFileSync(SPEC, 'utf8');

if (argv.includes('--selftest')) selftest();

const { problems, entries: nEntries, rows } = check(doc, space, spec, s => console.log(s));
if (problems.length) {
  console.error(`\ndoctrine: ${problems.length} ${problems.length === 1 ? 'беда' : 'бед'} в ${path.relative(ROOT, DOCTRINE)}:`);
  for (const p of problems) console.error('  - ' + p);
  process.exit(1);
}
console.log(`\ndoctrine: ${nEntries} записей, ${rows} ключей приложения 09 закрыты, ссылки на выгрузку целы`);
