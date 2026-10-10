#!/usr/bin/env node
/* ВЫГРУЗКА КОРАБЛЕЙ three.js В .glb «ПОД GODOT» (часть 08, приложение П.3; план G0, п. 5).

   Запуск из корня репозитория:
     node godot/tools/export_ships.mjs            — пишет godot/view/ships/*.glb,
                                                    godot/view/ships/tex/*.jpg
                                                    и godot/data/ship_models.json
     node godot/tools/export_ships.mjs --check    — без браузера: файлы на месте,
                                                    узлы закрывают doctrine.json → nodes,
                                                    длина в ±20% от model_len, исходники
                                                    игры не менялись после выгрузки
     node godot/tools/export_ships.mjs --selftest — испорченные копии обязаны краснеть

   Нужны Playwright и Chromium (как у tests/game-e2e.js). Корабль строит САМА игра —
   buildShip(def, faction, true) из game/js/models.js; здесь он только раскладывается:
   1. панели-инстансы развёрнуты в обычную геометрию, всё — в координатах корабля
      с масштабом K = 1,65;
   2. меши сливаются по материалу ВНУТРИ УЗЛА, а не по всему кораблю (08, 7.2 п. 8;
      архитектура, 2.8 и 5.2): корпус `hull`; башня `turret_i` (у дула — `muzzle_i`);
      блок двигателей `engines` с точками `engine_*`; `pd_*`; установки батареи
      `aux_*`; излучатель РЭБ `emitter`; ангар `bay`; ракетный пакет «Синхо»
      `launcher_0`. Имена — из doctrine.json → nodes: узел, которого там нет у корабля,
      или узел из списка, которого нет в модели, — отказ выгрузки;
   3. нормали плоские (геометрия без индексов + computeVertexNormals: флага flatShading
      в glTF нет, ловушка 08-25); эффекты (факелы, спрайты, сложение) сняты — их строит
      вид сам;
   4. картинки обшивки в файл НЕ кладутся: скан и нормали одни на все корабли, они
      лежат один раз в view/ships/tex/, и вид ставит их на материалы с именем `skin_*`
      (view/ship_visual.gd). Иначе каждый .glb вёз бы свою копию, а Godot при импорте
      распаковывал бы их отдельно на каждый корабль.
   Чего в процедурной модели НЕТ и что добавлено здесь: установки батареи (`aux_*` —
   её в three.js нет вовсе, 08, 7.2 п. 6), ракетный пакет «Синхо» и башня станции.
   Добавлено скромно и внутри силуэта — длина модели не меняется (проверка ниже).

   Определение «где что» (какой меш — двигатель, какой — ПВО) завязано на то, как
   buildShip строит корабль. Поменяли models.js — выгрузка обязана упасть со словами,
   а не разложить молча: каждое правило считает, сколько нашло, и сверяет с ожидаемым. */

import { readFileSync, writeFileSync, mkdirSync, existsSync, statSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { execSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const SHIPS_DIR = path.join(ROOT, 'godot', 'view', 'ships');
const TEX_DIR = path.join(SHIPS_DIR, 'tex');
const OUT_JSON = path.join(ROOT, 'godot', 'data', 'ship_models.json');
const DOCTRINE = path.join(ROOT, 'godot', 'data', 'doctrine.json');
const SPACE = path.join(ROOT, 'godot', 'data', 'space_data.json');
const FACTIONS_OUT = ['troyden', 'plektor'];          // кланы среза; остальные — тем же скриптом
const SOURCES = ['game/js/models.js', 'game/js/data.js', 'game/textures/hull_diff.jpg', 'game/textures/hull_nor.jpg'];
const LEN_TOL = 0.2;                                    // ±20% от model_len (C88; план G0)

const args = new Set(process.argv.slice(2));
const fail = msg => { console.error('export_ships: ' + msg); process.exit(2); };
const hash = f => createHash('sha256').update(readFileSync(path.join(ROOT, f))).digest('hex').slice(0, 16);

/* ── проверка готового (без браузера) ──────────────────────────────── */

// узел из doctrine.json (model: 'engine_*', 'turret_0', 'hull'…) есть в списке узлов модели
function hasModelNode(names, model) {
  if (model.endsWith('*')) return names.some(n => n.startsWith(model.slice(0, -1)) && /^\d+$/.test(n.slice(model.length - 1)));
  return names.includes(model);
}

function check(models, doctrine, space, { files = true, sources = true } = {}) {
  const bad = [];
  const nodes = doctrine.nodes && doctrine.nodes.v;
  if (!nodes) return ['doctrine.json: нет nodes.v'];
  for (const fac of FACTIONS_OUT) {
    const ids = space.ships[fac].map(s => s.id).concat(['station']);
    for (const id of ids) {
      const m = models.ships && models.ships[fac] && models.ships[fac][id];
      if (!m) { bad.push(`${fac}.${id}: модели нет в ship_models.json`); continue; }
      if (files && !existsSync(path.join(ROOT, 'godot', m.file.replace('res://', '')))) bad.push(`${fac}.${id}: нет файла ${m.file}`);
      const want = id === 'station' ? space.model_len.station : space.model_len.ship[id];
      if (!(Math.abs(m.len - want) <= want * LEN_TOL)) bad.push(`${fac}.${id}: длина модели ${m.len} вне ±20% от model_len ${want}`);
      if (!(m.width > 0 && m.height > 0)) bad.push(`${fac}.${id}: нет ширины или высоты`);
      const names = Object.keys(m.nodes || {});
      const spec = nodes[id];
      if (!spec) { bad.push(`${fac}.${id}: в doctrine.json → nodes нет корабля`); continue; }
      for (const [key, n] of Object.entries(spec)) {
        if (!hasModelNode(names, n.model)) bad.push(`${fac}.${id}: узел «${key}» (${n.model}) не найден в модели`);
      }
      for (const [name, n] of Object.entries(m.nodes || {})) {
        if (!Array.isArray(n.pos) || n.pos.length !== 3 || n.pos.some(v => typeof v !== 'number')) bad.push(`${fac}.${id}.${name}: нет положения`);
      }
    }
    for (const role of Object.keys(space.model_len.strike)) {
      const c = models.strike && models.strike[fac] && models.strike[fac][role];
      if (!c) { bad.push(`${fac}.strike.${role}: модели машины нет`); continue; }
      if (files && !existsSync(path.join(ROOT, 'godot', c.file.replace('res://', '')))) bad.push(`${fac}.strike.${role}: нет файла ${c.file}`);
      const want = space.model_len.strike[role];
      if (!(Math.abs(c.len - want) <= want * LEN_TOL)) bad.push(`${fac}.strike.${role}: длина ${c.len} вне ±20% от ${want}`);
    }
  }
  if (sources) {
    for (const f of SOURCES) {
      const was = models._meta && models._meta.sources && models._meta.sources[f];
      if (was !== hash(f)) bad.push(`${f} поменялся после выгрузки — запусти node godot/tools/export_ships.mjs`);
    }
  }
  return bad;
}

function readJson(f) { return JSON.parse(readFileSync(f, 'utf8')); }

if (args.has('--check') || args.has('--selftest')) {
  const doctrine = readJson(DOCTRINE), space = readJson(SPACE);
  if (!existsSync(OUT_JSON)) fail('нет godot/data/ship_models.json — запусти выгрузку');
  const models = readJson(OUT_JSON);
  if (args.has('--check')) {
    const bad = check(models, doctrine, space);
    if (bad.length) { for (const b of bad) console.error('  ' + b); fail(`беды: ${bad.length}`); }
    let n = 0;
    for (const fac of FACTIONS_OUT) n += Object.keys(models.ships[fac]).length;
    console.log(`export_ships --check: моделей кораблей ${n}, узлы закрывают doctrine.json → nodes, длины в ±20%`);
  }
  if (args.has('--selftest')) {
    // каждая порча обязана дать беду; иначе проверка ничего не охраняет
    const spoil = [
      ['узел пропал', m => { delete m.ships.plektor.capital.nodes.turret_1; }, 'turret_1'],
      ['точек ПВО нет', m => { for (const k of Object.keys(m.ships.troyden.cruiser.nodes)) if (k.startsWith('pd_')) delete m.ships.troyden.cruiser.nodes[k]; }, 'pd_*'],
      ['длина вдвое', m => { m.ships.troyden.frigate.len *= 2; }, 'длина модели'],
      ['машина короче', m => { m.strike.plektor.bomber.len *= 0.5; }, 'strike.bomber'],
      ['исходник поменялся', m => { m._meta.sources['game/js/models.js'] = '0000'; }, 'models.js'],
      ['РЭБ без излучателя', m => { delete m.ships.troyden.ecm.nodes.emitter; }, 'emitter'],
    ];
    let red = 0;
    for (const [what, f, mark] of spoil) {
      const copy = JSON.parse(JSON.stringify(models));
      f(copy);
      const bad = check(copy, doctrine, space, { files: false });
      if (bad.some(b => b.includes(mark))) red++;
      else console.error(`  откат «${what}» НЕ покраснел (ждали «${mark}»): ${bad.join('; ') || 'бед нет'}`);
    }
    if (red !== spoil.length) fail(`selftest: покраснело ${red} из ${spoil.length}`);
    console.log(`export_ships --selftest: испорченных копий ${spoil.length}, покраснели все`);
  }
  process.exit(0);
}

/* ── выгрузка (браузер) ─────────────────────────────────────────────── */

const require = createRequire(import.meta.url);
let playwright;
try { playwright = require('playwright'); } catch (e) {
  try { playwright = require(execSync('npm root -g').toString().trim() + '/playwright'); } catch (e2) {
    playwright = require('/opt/node-tools/node_modules/playwright');
  }
}

const doctrine = readJson(DOCTRINE);
const space = readJson(SPACE);
const ORIGIN = 'http://capella.local';
const MIME = { '.js': 'text/javascript', '.mjs': 'text/javascript', '.jpg': 'image/jpeg', '.png': 'image/png', '.json': 'application/json', '.html': 'text/html' };

const PAGE = `<!doctype html><meta charset="utf-8"><body><script type="module">
import * as THREE from '/game/vendor/three.module.min.js';
import { GLTFExporter } from '/godot/tools/vendor/three/GLTFExporter.js';
import { mergeGeometries } from '/game/vendor/BufferGeometryUtils.js';
import { buildShip, buildStrike, visualLength } from '/game/js/models.js';
import { FACTIONS, SHIPS, STATION } from '/game/js/data.js';
window.__x = { THREE, GLTFExporter, mergeGeometries, buildShip, buildStrike, visualLength, FACTIONS, SHIPS, STATION };
</script>`;

const browser = await playwright.chromium.launch({
  executablePath: existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined,
  args: ['--no-sandbox', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'],
});
const ctx = await browser.newContext({ viewport: { width: 640, height: 480 }, serviceWorkers: 'block' });
const page = await ctx.newPage();
const logs = [];
page.on('console', m => { if (m.type() === 'error' || m.type() === 'warning') logs.push(m.type() + ': ' + m.text()); });
page.on('pageerror', e => logs.push('pageerror: ' + e.message));
await page.route(ORIGIN + '/**', async r => {
  const u = new URL(r.request().url());
  if (u.pathname === '/__export/index.html') return r.fulfill({ contentType: 'text/html; charset=utf-8', body: PAGE });
  const file = path.join(ROOT, decodeURIComponent(u.pathname));
  if (!file.startsWith(ROOT) || !existsSync(file) || !statSync(file).isFile()) return r.fulfill({ status: 404, body: 'нет ' + u.pathname });
  let body = readFileSync(file);
  // модуль three на странице обязан быть ОДИН с моделями игры (П.1)
  if (u.pathname.startsWith('/godot/tools/vendor/three/')) {
    body = body.toString('utf8')
      .replace(/from 'three';/g, "from '/game/vendor/three.module.min.js';")
      .replace("'./../utils/TextureUtils.js'", "'/godot/tools/vendor/three/TextureUtils.js'");
  }
  return r.fulfill({ status: 200, contentType: MIME[path.extname(file)] || 'application/octet-stream', body });
});
await page.goto(ORIGIN + '/__export/index.html');
await page.waitForFunction(() => !!window.__x, null, { timeout: 60000 });

/* Всё, что делается в странице, — одной функцией: строит, раскладывает по узлам,
   выгружает. Отдаёт base64 файла и обмер. */
const exportInPage = async ([kind, fac, id, specNames]) => {
  const { THREE, GLTFExporter, mergeGeometries, buildShip, buildStrike, visualLength, FACTIONS, SHIPS, STATION } = window.__x;
  const faction = FACTIONS[fac];
  const problems = [];
  const r3 = v => +v.toFixed(3);
  const arr3 = v => [r3(v.x), r3(v.y), r3(v.z)];
  const isFx = o => {
    if (o.isSprite) return true;
    for (let p = o; p; p = p.parent) if (p.userData && p.userData.noPick) return true;
    const m = o.material;
    return !!m && !Array.isArray(m) && m.blending === THREE.AdditiveBlending;
  };

  let def, g, R, L, W;
  if (kind === 'ship') {
    def = id === 'station' ? STATION : SHIPS[fac].find(s => s.id === id);
    g = buildShip(def, faction, true);
    R = def.radius;
    L = R * (def.cls === 'escort' ? 3.4 : def.cls === 'carrier' ? 3.2 : 3.6);
    W = R * (def.id === 'capital' ? 1.5 : 1.2);
  } else {
    g = buildStrike(id, faction, true);
  }
  g.position.set(0, 0, 0);
  g.quaternion.identity();
  g.updateMatrixWorld(true);
  const K = g.scale.x;
  const visual = visualLength(g);
  const ud = g.userData;
  const assign = new Map();                    // меш → имя узла
  const eps = (R || 1) * 1e-4;
  const near = (a, b) => Math.abs(a - b) <= eps;
  const direct = g.children.filter(o => o.isMesh && !isFx(o));
  const extra = [];                            // добавленные здесь меши: [меш, узел]

  // материалы корабля, которыми рисуются добавленные установки
  const findMat = pred => { let found = null; g.traverse(o => { if (!found && o.isMesh && !isFx(o) && !Array.isArray(o.material) && pred(o.material, o)) found = o.material; }); return found; };
  const darkMat = kind === 'ship' ? (findMat((m, o) => o.geometry.type === 'SphereGeometry' && m.map) || findMat((m, o) => o.geometry.type === 'CylinderGeometry' && m.map)) : null;
  const trimMat = kind === 'ship' ? findMat(m => m.emissive && m.emissive.getHex() === new THREE.Color(faction.color).getHex() && m.emissiveIntensity === 1.1) : null;
  const BOXG = new THREE.BoxGeometry(1, 1, 1), CYLG = new THREE.CylinderGeometry(1, 1, 1, 10);
  const add = (geo, mat, node, sx, sy, sz, x, y, z, rotX = 0, host = g) => {
    const m = new THREE.Mesh(geo, mat);
    m.scale.set(sx, sy, sz); m.position.set(x, y, z); m.rotation.x = rotX;
    host.add(m); extra.push([m, node]);
    return m;
  };

  const points = [];                           // [имя, родитель, Vector3 в координатах корабля (с K), extras]
  const pivots = new Map();                    // узел с геометрией → опорная точка (с K)
  pivots.set('hull', new THREE.Vector3());

  if (kind === 'ship') {
    // башни главного калибра: группы внутри корабля (не факелы)
    const turrets = g.children.filter(o => o.isGroup && !o.userData.noPick);
    turrets.forEach((t, i) => {
      t.traverse(o => { if (o.isMesh) assign.set(o, `turret_${i}`); });
      pivots.set(`turret_${i}`, t.position.clone().multiplyScalar(K));
    });
    // двигатели: у каждого факела перед ним два цилиндра — раструб и горло (addEngine)
    const engs = ud.engines || [];
    let engMeshes = 0;
    const engPos = [];
    engs.forEach((e, k) => {
      const ix = g.children.indexOf(e);
      for (const j of [ix - 1, ix - 2]) {
        const m = g.children[j];
        if (m && m.isMesh && m.geometry.type === 'CylinderGeometry' && near(m.position.x, e.position.x) && near(m.position.y, e.position.y) && !assign.has(m)) {
          assign.set(m, 'engines'); engMeshes++;
        }
      }
      const wp = e.position.clone().multiplyScalar(K);
      engPos.push(wp);
      const size = e.children[0].scale.x / 0.9 * K;
      points.push([`engine_${k}`, 'engines', wp, { size: r3(size) }]);
    });
    if (engMeshes !== engs.length * 2) problems.push(`двигателей ${engs.length}, а цилиндров при них ${engMeshes} (ждали ${engs.length * 2})`);
    if (engs.length) {
      const c = new THREE.Vector3();
      for (const p of engPos) c.add(p);
      pivots.set('engines', c.multiplyScalar(1 / engPos.length));
    }
    // ПВО: у крейсера, флагмана и «Синхо» над каждой точкой — коробка 0,14 R (на 0,1 R выше)
    const pd = ud.pdPoints || [];
    let pdMeshes = 0;
    const capitalBranch = def.cls === 'capital' && !def.station;
    pd.forEach((p, i) => {
      const lp = p.clone().multiplyScalar(1 / K);
      points.push([`pd_${i}`, null, p.clone(), null]);
      if (!capitalBranch) return;
      for (const m of direct) {
        if (assign.has(m) || m.geometry.type !== 'BoxGeometry') continue;
        if (near(m.position.x, lp.x) && near(m.position.z, lp.z) && near(m.position.y, lp.y + R * 0.1) && near(m.scale.x, R * 0.14)) {
          assign.set(m, `pd_${i}`); pivots.set(`pd_${i}`, p.clone()); pdMeshes++; break;
        }
      }
    });
    if (capitalBranch && pdMeshes !== pd.length) problems.push(`точек ПВО ${pd.length}, а коробок при них ${pdMeshes}`);
    // излучатель РЭБ: три цилиндра по оси под днищем (blin + кольцо + шток)
    if (def.ecm) {
      let n = 0;
      for (const m of direct) {
        if (!assign.has(m) && m.geometry.type === 'CylinderGeometry' && near(m.position.x, 0) && near(m.position.z, R * 0.1) && m.position.y < -R * 0.2) { assign.set(m, 'emitter'); n++; }
      }
      if (n !== 3) problems.push(`у РЭБ в излучателе ${n} цилиндров, ждали 3`);
      pivots.set('emitter', ud.emitter.clone());
    }
    // ангар носителя: тёмный короб зева в носу
    if (def.cls === 'carrier') {
      let n = 0;
      for (const m of direct) {
        if (!assign.has(m) && m.geometry.type === 'BoxGeometry' && near(m.position.x, 0) && near(m.position.y, R * 0.08) && near(m.position.z, -L * 0.5 + R * 0.35)) { assign.set(m, 'bay'); n++; }
      }
      if (n !== 1) problems.push(`у носителя зев ангара найден ${n} раз, ждали 1`);
      pivots.set('bay', ud.bay.clone());
    }
    // --- добавлено здесь: установки батареи, ракетный пакет «Синхо», башня станции ---
    const want = specNames;   // имена узлов из doctrine.json для этого корабля
    const auxN = want.filter(n => /^aux_\d+$/.test(n)).length;
    let auxPts = [];
    if (def.station) {
      // на кольце сверху, между точками ПВО (они через π/4 начиная с 0)
      const rr = R * 1.2;
      auxPts = [0, 1, 2, 3].map(k => { const a = Math.PI / 8 + k * Math.PI / 2; return [rr * Math.cos(a), R * 0.27, rr * Math.sin(a)]; });
    } else if (auxN === 2) {
      auxPts = [[-W * 0.46, R * 0.41, 0], [W * 0.46, R * 0.41, 0]];
    } else if (auxN >= 3) {
      auxPts = [[-W * 0.46, R * 0.41, -L * 0.17], [W * 0.46, R * 0.41, -L * 0.17], [-W * 0.46, R * 0.41, L * 0.17], [W * 0.46, R * 0.41, L * 0.17]].slice(0, auxN);
    }
    auxPts.slice(0, auxN).forEach(([x, y, z], i) => {
      const node = `aux_${i}`;
      // у станции ствол вдоль кольца (по касательной), иначе он торчал бы за обод
      const mount = new THREE.Group();
      mount.position.set(x, y, z);
      if (def.station) mount.rotation.y = Math.PI - Math.atan2(z, x);
      g.add(mount);
      add(BOXG, darkMat, node, R * 0.22, R * 0.1, R * 0.3, 0, 0, 0, 0, mount);
      add(BOXG, trimMat, node, R * 0.22, R * 0.02, R * 0.06, 0, R * 0.06, R * 0.06, 0, mount);
      add(CYLG, darkMat, node, R * 0.03, R * 0.4, R * 0.03, 0, R * 0.02, -R * 0.3, Math.PI / 2, mount);
      pivots.set(node, new THREE.Vector3(x, y, z).multiplyScalar(K));
    });
    if (auxPts.length < auxN) problems.push(`установок батареи в данных ${auxN}, а мест под них ${auxPts.length}`);
    if (want.includes('launcher_0')) {
      const [x, y, z] = [0, R * 0.824, -L * 0.08];
      add(BOXG, darkMat, 'launcher_0', R * 0.5, R * 0.2, R * 0.4, x, y, z);
      for (const sx of [-1, 1]) for (const sz of [-1, 1]) add(CYLG, trimMat, 'launcher_0', R * 0.07, R * 0.06, R * 0.07, x + sx * R * 0.12, y + R * 0.11, z + sz * R * 0.1);
      pivots.set('launcher_0', new THREE.Vector3(x, y, z).multiplyScalar(K));
      points.push(['missile_0', 'launcher_0', new THREE.Vector3(x, y + R * 0.14, z).multiplyScalar(K), null]);
    }
    if (def.station) {
      // башня главного калибра станции: та же, что у крейсера, в 0,6 размера, на вершине стержня
      const s = 0.6, py = R * 0.8 + R * 0.26 * s * 0.5;
      add(CYLG, darkMat, 'turret_0', R * 0.34 * s, R * 0.26 * s, R * 0.34 * s, 0, py, 0);
      add(BOXG, darkMat, 'turret_0', R * 0.42 * s, R * 0.3 * s, R * 0.85 * s, 0, py + R * 0.15 * s, -R * 0.3 * s);
      add(CYLG, darkMat, 'turret_0', R * 0.09 * s, R * 1.5 * s, R * 0.09 * s, 0, py + R * 0.16 * s, -R * 0.85 * s, Math.PI / 2);
      add(CYLG, trimMat, 'turret_0', R * 0.11 * s, R * 0.2 * s, R * 0.11 * s, 0, py + R * 0.16 * s, -R * 1.5 * s, Math.PI / 2);
      pivots.set('turret_0', new THREE.Vector3(0, py, 0).multiplyScalar(K));
      points.push(['muzzle_0', 'turret_0', new THREE.Vector3(0, py + R * 0.16 * s, -R * 1.6 * s).multiplyScalar(K), null]);
      points.push(['bay', null, ud.bay.clone(), null]);
    } else {
      // дула: у башен — внутри башни, у лёгких — на корпусе
      (ud.muzzles || []).forEach((p, i) => {
        if (turrets.length) { if (i < turrets.length) points.push([`muzzle_${i}`, `turret_${i}`, p.clone(), null]); }
        else if (want.includes('muzzle_0') && i === 0) points.push(['muzzle_0', null, p.clone(), null]);
      });
      if (!pivots.has('bay')) points.push(['bay', null, ud.bay.clone(), null]);
      if (def.ecm && !pivots.has('emitter')) points.push(['emitter', null, ud.emitter.clone(), null]);
    }
    g.updateMatrixWorld(true);
  } else {
    (ud.engines || []).forEach((e, k) => points.push([`engine_${k}`, null, e.position.clone().multiplyScalar(K), { size: r3(0.62 * K) }]));
  }
  for (const [m, node] of extra) assign.set(m, node);

  // всё, что не нашлось, — корпус (вместе с обшивкой-инстансами)
  const parts = new Map();                     // узел → Map(материал → [геометрия])
  const mi = new THREE.Matrix4(), m4 = new THREE.Matrix4();
  const prep = (geo, mtx, pivot) => {
    let gg = geo.index ? geo.toNonIndexed() : geo.clone();
    for (const k of Object.keys(gg.attributes)) if (!['position', 'normal', 'uv'].includes(k)) gg.deleteAttribute(k);
    gg.applyMatrix4(mtx);
    gg.translate(-pivot.x, -pivot.y, -pivot.z);
    // вырожденные треугольники (вершина конуса, шов цилиндра) — прочь: нормали у них нет
    const pa = gg.attributes.position, ua = gg.attributes.uv;
    const keep = [];
    const A = new THREE.Vector3(), B = new THREE.Vector3(), C = new THREE.Vector3();
    for (let t = 0; t < pa.count; t += 3) {
      A.fromBufferAttribute(pa, t); B.fromBufferAttribute(pa, t + 1); C.fromBufferAttribute(pa, t + 2);
      if (B.sub(A).cross(C.sub(A)).lengthSq() > 1e-12) keep.push(t);
    }
    if (keep.length * 3 !== pa.count) {
      const np = new Float32Array(keep.length * 9), nu = ua ? new Float32Array(keep.length * 6) : null;
      keep.forEach((t, k) => {
        for (let v = 0; v < 3; v++) {
          for (let c = 0; c < 3; c++) np[k * 9 + v * 3 + c] = pa.getComponent(t + v, c);
          if (nu) for (let c = 0; c < 2; c++) nu[k * 6 + v * 2 + c] = ua.getComponent(t + v, c);
        }
      });
      const ng = new THREE.BufferGeometry();
      ng.setAttribute('position', new THREE.BufferAttribute(np, 3));
      if (nu) ng.setAttribute('uv', new THREE.BufferAttribute(nu, 2));
      gg = ng;
    }
    gg.computeVertexNormals();               // у неиндексированной — нормаль грани
    return gg;
  };
  const push = (node, mat, geo) => {
    if (!parts.has(node)) parts.set(node, new Map());
    const byMat = parts.get(node);
    if (!byMat.has(mat)) byMat.set(mat, []);
    byMat.get(mat).push(geo);
  };
  g.traverse(o => {
    if (!o.isMesh || isFx(o)) return;
    const node = assign.get(o) || 'hull';
    if (!pivots.has(node)) problems.push(`у узла ${node} нет опорной точки`);
    const pv = pivots.get(node) || new THREE.Vector3();
    if (o.isInstancedMesh) {
      for (let i = 0; i < o.count; i++) { o.getMatrixAt(i, mi); push(node, o.material, prep(o.geometry, m4.multiplyMatrices(o.matrixWorld, mi), pv)); }
    } else push(node, o.material, prep(o.geometry, o.matrixWorld, pv));
  });

  // материалы — копии без картинок: скан и нормали ставит вид (view/ship_visual.gd)
  const matCopies = new Map();
  const hex = c => c.getHexString();
  const copyMat = m => {
    if (matCopies.has(m)) return matCopies.get(m);
    const c = m.clone();
    const skin = !!m.map;
    const glow = m.emissive && m.emissive.getHex() !== 0;
    c.name = (skin ? 'skin_' : glow ? 'glow_' : 'mat_') + hex(m.color) + (glow ? '_e' + hex(m.emissive) + '_i' + Math.round(m.emissiveIntensity * 100) : '');
    c.map = null; c.normalMap = null; c.userData = {};
    matCopies.set(m, c);
    return c;
  };

  const root = new THREE.Group();
  root.name = kind === 'ship' ? `ship_${fac}_${id}` : `craft_${fac}_${id}`;
  const objs = new Map();
  const nodesOut = {};
  const box = new THREE.Box3(), tmp = new THREE.Box3();
  let tris = 0, surfaces = 0;
  // узлы с геометрией — в порядке: корпус, башни, двигатели, ПВО, батарея, РЭБ, ангар, ракеты
  const order = name => {
    const pre = ['hull', 'turret_', 'engines', 'pd_', 'aux_', 'emitter', 'bay', 'launcher_'].findIndex(p => name === p || name.startsWith(p));
    return pre * 100 + (parseInt(name.split('_').pop(), 10) || 0);
  };
  for (const node of [...parts.keys()].sort((a, b) => order(a) - order(b))) {
    const byMat = parts.get(node);
    const geos = [], mats = [];
    let ntris = 0;
    for (const [m, list] of byMat) {
      const merged = mergeGeometries(list, false);
      if (!merged) { problems.push(`${node}: не слилось (${m.type})`); continue; }
      geos.push(merged); mats.push(copyMat(m));
      ntris += merged.attributes.position.count / 3;
    }
    const all = mergeGeometries(geos, true);
    const mesh = new THREE.Mesh(all, mats);
    mesh.name = node;
    const pv = pivots.get(node);
    mesh.position.copy(pv);
    root.add(mesh);
    objs.set(node, mesh);
    all.computeBoundingBox();
    tmp.copy(all.boundingBox).translate(pv);
    box.union(tmp);
    tris += ntris; surfaces += mats.length;
    nodesOut[node] = { pos: arr3(pv), surfaces: mats.length, tris: ntris };
  }
  // точки: пустые узлы; у точки внутри узла (дуло в башне, сопло в блоке) — координаты от его опоры
  for (const [name, parent, p, extras] of points) {
    if (objs.has(name)) { if (extras) objs.get(name).userData = extras; continue; }
    const o = new THREE.Object3D();
    o.name = name;
    const par = parent && objs.get(parent);
    if (parent && !par) {
      // родитель без геометрии (блок двигателей у машины) — пустой узел на месте
      const holder = new THREE.Object3D();
      holder.name = parent;
      const pv = pivots.get(parent) || new THREE.Vector3();
      holder.position.copy(pv);
      root.add(holder); objs.set(parent, holder);
      nodesOut[parent] = { pos: arr3(pv), surfaces: 0, tris: 0 };
    }
    const host = parent ? objs.get(parent) : root;
    o.position.copy(p).sub(parent ? host.position : new THREE.Vector3());
    if (extras) o.userData = extras;
    host.add(o);
    objs.set(name, o);
    nodesOut[name] = { pos: arr3(p), parent: parent || null, ...(extras || {}) };
  }
  const size = box.getSize(new THREE.Vector3());
  root.userData = { kind, faction: fac, id, K: r3(K), len: r3(Math.max(size.x, size.z)) };

  const buf = await new GLTFExporter().parseAsync(root, { binary: true });
  const b = new Uint8Array(buf);
  let s = '';
  for (let k = 0; k < b.length; k += 0x8000) s += String.fromCharCode.apply(null, b.subarray(k, k + 0x8000));
  return {
    b64: btoa(s), problems, visual: r3(visual),
    len: r3(Math.max(size.x, size.z)), len_z: r3(size.z), width: r3(size.x), height: r3(size.y),
    aabb: [arr3(box.min), arr3(box.max)], tris: Math.round(tris), surfaces, nodes: nodesOut,
    materials: [...matCopies.values()].map(m => m.name),
  };
};

// скан обшивки, перекрашенный игрой (C42): берём ровно ту канву, что кладёт на корабли detailMap
const skinJpeg = async () => page.evaluate(async () => {
  const { buildShip, SHIPS, FACTIONS } = window.__x;
  const g = buildShip(SHIPS.troyden[0], FACTIONS.troyden, true);
  const get = () => { let img = null; g.traverse(o => { const m = o.isMesh && o.material; if (!img && m && m.isMeshStandardMaterial && m.normalMap && m.map && m.map.image instanceof HTMLCanvasElement) img = m.map.image; }); return img; };
  for (let i = 0; i < 300 && !get(); i++) await new Promise(r => setTimeout(r, 100));
  const cv = get();
  if (!cv || cv.width < 512) return null;
  return cv.toDataURL('image/jpeg', 0.92).split(',')[1];
});

mkdirSync(TEX_DIR, { recursive: true });
const skin = await skinJpeg();
if (!skin) fail('скан обшивки не загрузился (detailMap не подменил картинку канвой)');
writeFileSync(path.join(TEX_DIR, 'hull_diff.jpg'), Buffer.from(skin, 'base64'));
writeFileSync(path.join(TEX_DIR, 'hull_nor.jpg'), readFileSync(path.join(ROOT, 'game/textures/hull_nor.jpg')));

const nodesSpec = doctrine.nodes.v;
const out = { ships: {}, strike: {} };
const table = [];
const allProblems = [];
for (const fac of FACTIONS_OUT) {
  out.ships[fac] = {};
  out.strike[fac] = {};
  const ids = space.ships[fac].map(s => s.id).concat(['station']);
  for (const id of ids) {
    const spec = nodesSpec[id];
    if (!spec) fail(`в doctrine.json → nodes нет корабля ${id}`);
    const specNames = Object.values(spec).map(n => n.model);
    const r = await page.evaluate(exportInPage, ['ship', fac, id, specNames]);
    for (const p of r.problems) allProblems.push(`${fac}.${id}: ${p}`);
    const file = `${fac}_${id}.glb`;
    writeFileSync(path.join(SHIPS_DIR, file), Buffer.from(r.b64, 'base64'));
    const want = id === 'station' ? space.model_len.station : space.model_len.ship[id];
    // добавленные установки обязаны лечь внутри силуэта: длина — та же, что у игры
    if (Math.abs(r.len - r.visual) > 0.01 * r.visual) allProblems.push(`${fac}.${id}: длина выгрузки ${r.len} разошлась с длиной игры ${r.visual} — добавленное вылезло за силуэт`);
    if (Math.abs(r.visual - want) > 0.005 * want) allProblems.push(`${fac}.${id}: длина игры ${r.visual} не равна model_len ${want} — перемерь export_data.mjs --measure-len`);
    const names = Object.keys(r.nodes);
    for (const [key, n] of Object.entries(spec)) if (!hasModelNode(names, n.model)) allProblems.push(`${fac}.${id}: нет узла «${key}» (${n.model})`);
    // узлы оружия и систем в модели, которых нет в данных корабля, — тоже беда (данные врут)
    for (const nm of names) {
      if (/^(turret|aux|launcher)_\d+$/.test(nm) && !specNames.includes(nm)) allProblems.push(`${fac}.${id}: узел ${nm} есть в модели, но не в doctrine.json`);
      if ((nm === 'emitter' && !specNames.includes('emitter'))) allProblems.push(`${fac}.${id}: излучатель без узла в данных`);
    }
    out.ships[fac][id] = {
      file: `res://view/ships/${file}`, len: r.len, len_z: r.len_z, width: r.width, height: r.height,
      aabb: r.aabb, tris: r.tris, surfaces: r.surfaces, bytes: Buffer.byteLength(r.b64, 'base64'),
      materials: r.materials, nodes: r.nodes,
    };
    table.push(`${fac.padEnd(8)} ${id.padEnd(9)} длина ${String(r.len).padStart(7)} (игра ${r.visual}, model_len ${want})  ширина ${String(r.width).padStart(6)}  треугольников ${String(r.tris).padStart(5)}  поверхностей ${String(r.surfaces).padStart(2)}  узлов с геометрией ${Object.values(r.nodes).filter(n => n.surfaces).length}`);
  }
  for (const role of Object.keys(space.model_len.strike)) {
    const r = await page.evaluate(exportInPage, ['strike', fac, role, []]);
    for (const p of r.problems) allProblems.push(`${fac}.strike.${role}: ${p}`);
    const file = `${fac}_strike_${role}.glb`;
    writeFileSync(path.join(SHIPS_DIR, file), Buffer.from(r.b64, 'base64'));
    const want = space.model_len.strike[role];
    if (Math.abs(r.visual - want) > 0.005 * want) allProblems.push(`${fac}.strike.${role}: длина игры ${r.visual} не равна model_len ${want}`);
    out.strike[fac][role] = { file: `res://view/ships/${file}`, len: r.len, width: r.width, height: r.height, tris: r.tris, surfaces: r.surfaces, nodes: r.nodes };
    table.push(`${fac.padEnd(8)} ${role.padEnd(11)} длина ${String(r.len).padStart(7)} (model_len ${want})  треугольников ${r.tris}  поверхностей ${r.surfaces}`);
  }
}
await browser.close();

let commit = null;
try { commit = execSync('git rev-parse --short HEAD', { cwd: ROOT, stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim(); } catch (e) { /* без git — без номера */ }
const json = {
  _meta: {
    what: 'Модели кораблей «Капеллы» для Godot: файлы .glb, обмер и узлы. Выгрузка, руками не править.',
    generated_by: 'godot/tools/export_ships.mjs',
    spec: 'godot/spec/08-visuals.md, приложение П.3; godot/spec/plan.md, G0 п. 5',
    commit,
    sources: Object.fromEntries(SOURCES.map(f => [f, hash(f)])),
    how: 'len = max(x, z) рамки всей геометрии (без эффектов) — то же правило, что visualLength игры; ' +
         'width — по x, height — по y, len_z — по z (нос к −z). pos узла — в координатах корабля; ' +
         'у точки с parent — тоже в координатах корабля, в .glb она лежит внутри узла-родителя. ' +
         'Узлы с surfaces > 0 — с геометрией (один меш, поверхность на материал), остальные — точки.',
    skin: { albedo: 'res://view/ships/tex/hull_diff.jpg', normal: 'res://view/ships/tex/hull_nor.jpg', uv_scale: 3, normal_scale: 0.8, materials: 'имя начинается с skin_' },
  },
  ships: out.ships,
  strike: out.strike,
};
writeFileSync(OUT_JSON, JSON.stringify(json, null, 1) + '\n');
for (const l of table) console.log(l);
if (logs.length) console.log('браузер:\n  ' + logs.slice(0, 20).join('\n  '));
if (allProblems.length) { for (const p of allProblems) console.error('  ' + p); fail(`беды выгрузки: ${allProblems.length}`); }
const bad = check(json, doctrine, space);
if (bad.length) { for (const b of bad) console.error('  ' + b); fail('проверка выгрузки не прошла'); }
console.log(`export_ships: ${table.length} моделей → godot/view/ships, обмер → godot/data/ship_models.json`);
