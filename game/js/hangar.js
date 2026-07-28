/* АНГАР — просмотр моделей.

   Сюда заходят, когда положили свою .glb в game/models/. Экран
   показывает выбранный корабль на поворотном столе, даёт покрутить
   и подобрать разворот с масштабом, и тут же печатает готовую
   строчку для manifest.json — её остаётся скопировать.

   Если для слота своей модели нет, показывается процедурная:
   так видно, что именно ты заменяешь. */

import {
  THREE, TacticalCamera, Controls, starfield, disposeScene, IS_TOUCH, clamp,
} from './engine.js';
import { buildShip, buildStrike, buildGroundUnit, buildStructure, buildNebula } from './models.js';
import { nebulaTexture } from './textures.js';
import { hasCustom } from './assets.js';
import {
  FACTIONS, FACTION_IDS, SHIPS, STRIKE, STRIKE_ROLES, GROUND_BUILDINGS, GROUND_UNITS,
} from './data.js';

export function createHangar(ctx) {
  const { viewport, hudRoot } = ctx;

  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0x05070d);
  scene.add(buildNebula(900, 21));
  // Отражения: металл должен что-то отражать, иначе он чёрный
  scene.environment = viewport.environmentFrom(nebulaTexture(21));
  scene.environmentIntensity = 2.6;
  scene.add(starfield(900, 700));

  // Свет как в фотостудии: ключ, заполняющий и контровой
  scene.add(new THREE.AmbientLight(0x8a96b0, 1.2));
  const key = new THREE.DirectionalLight(0xfff0dd, 4.2);
  key.position.set(60, 55, 45);
  scene.add(key);
  const fill = new THREE.DirectionalLight(0x7fa8d8, 1.8);
  fill.position.set(-70, 20, 30);
  scene.add(fill);
  const rim = new THREE.DirectionalLight(0xffd9a8, 2.8);
  rim.position.set(0, 25, -80);
  scene.add(rim);

  const tcam = new TacticalCamera({
    dist: 120, minDist: 12, maxDist: 500, pitch: 0.32, yaw: 0.7, far: 4000,
  });
  viewport.setBloom({ strength: 0.55, radius: 0.5, threshold: 0.85, exposure: 1.05 });

  const stand = new THREE.Group();
  scene.add(stand);

  const state = {
    faction: 'troyden', kind: 'ship', id: 'capital',
    rot: [0, 0, 0], scale: 1, spin: true, current: null,
  };

  // ── что вообще можно посмотреть
  function slots() {
    const out = [];
    for (const d of SHIPS[state.faction]) out.push({ kind: 'ship', id: d.id, name: d.name });
    for (const r of ['interceptor', 'fighter', 'bomber']) {
      out.push({ kind: 'strike', id: r, name: STRIKE[state.faction][r].name + ' · ' + STRIKE_ROLES[r].label });
    }
    for (const id of ['worker', 'rifle', 'rocket', 'tank', 'aa', 'arty', 'jet']) {
      out.push({ kind: 'ground', id, name: GROUND_UNITS[state.faction][id].name });
    }
    for (const id of ['hq', 'barracks', 'factory', 'airfield', 'turret', 'sam']) {
      out.push({ kind: 'building', id, name: GROUND_BUILDINGS[id].name });
    }
    return out;
  }

  function rebuild() {
    while (stand.children.length) stand.remove(stand.children[0]);
    const f = FACTIONS[state.faction];
    let obj = null;
    if (state.kind === 'ship') {
      const def = SHIPS[state.faction].find(d => d.id === state.id) || SHIPS[state.faction][0];
      obj = buildShip(def, f);
    } else if (state.kind === 'strike') {
      obj = buildStrike(state.id, f);
    } else if (state.kind === 'ground') {
      obj = buildGroundUnit(GROUND_UNITS[state.faction][state.id], f);
    } else {
      obj = buildStructure(GROUND_BUILDINGS[state.id], f);
    }
    stand.add(obj);
    state.current = obj;

    // Подгоняем камеру под габарит, чтобы модель всегда была в кадре
    const box = new THREE.Box3().setFromObject(obj);
    const size = box.getSize(new THREE.Vector3());
    const c = box.getCenter(new THREE.Vector3());
    stand.position.set(-c.x, -c.y, -c.z);
    const longest = Math.max(size.x, size.y, size.z) || 1;
    tcam.dist = clamp(longest * 2.4, 12, 500);
    tcam.target.set(0, 0, 0);
    state.size = size;
    refreshPanel();
  }

  // ── интерфейс
  const hud = document.createElement('div');
  hud.className = 'hud hud-hangar';
  hud.innerHTML = `
    <div class="topbar">
      <div class="title">Ангар · просмотр моделей</div>
      <div class="speedctl">
        <button data-role="spin">Вращение</button>
        <button data-role="back" class="primary">Назад</button>
      </div>
    </div>
    <div class="hangar-left">
      <div class="form-row"><label>Клан</label><select data-role="faction"></select></div>
      <div class="form-row"><label>Что смотрим</label><select data-role="slot"></select></div>
      <div class="hangar-status" data-role="status"></div>
    </div>
    <div class="hangar-right">
      <div class="hangar-block">
        <h4>Разворот</h4>
        <div class="hangar-btns">
          <button data-rot="x">X +90°</button>
          <button data-rot="y">Y +90°</button>
          <button data-rot="z">Z +90°</button>
          <button data-rot="0">Сброс</button>
        </div>
      </div>
      <div class="hangar-block">
        <h4>Масштаб</h4>
        <div class="hangar-btns">
          <button data-scale="-">−10%</button>
          <button data-scale="+">+10%</button>
          <button data-scale="1">1.0</button>
        </div>
      </div>
      <div class="hangar-block">
        <h4>Строка для manifest.json</h4>
        <pre class="hangar-code" data-role="code"></pre>
        <button data-role="copy">Скопировать</button>
      </div>
    </div>
    <div class="hint">${IS_TOUCH
      ? 'Тянуть — повернуть · щипок — приближение'
      : 'Alt+ЛКМ или средняя кнопка — повернуть · колесо — приближение'}</div>
  `;
  hudRoot.appendChild(hud);
  const $ = r => hud.querySelector(`[data-role="${r}"]`);

  const facSel = $('faction');
  facSel.innerHTML = FACTION_IDS.map(f => `<option value="${f}">${FACTIONS[f].name}</option>`).join('');
  facSel.value = state.faction;

  const slotSel = $('slot');
  function fillSlots() {
    slotSel.innerHTML = slots()
      .map(s => `<option value="${s.kind}:${s.id}">${s.name}</option>`).join('');
    slotSel.value = `${state.kind}:${state.id}`;
  }
  fillSlots();

  facSel.onchange = () => { state.faction = facSel.value; fillSlots(); rebuild(); };
  slotSel.onchange = () => {
    const [k, i] = slotSel.value.split(':');
    state.kind = k; state.id = i;
    rebuild();
  };

  hud.querySelectorAll('[data-rot]').forEach(b => {
    b.onclick = () => {
      const a = b.dataset.rot;
      if (a === '0') state.rot = [0, 0, 0];
      else {
        const i = { x: 0, y: 1, z: 2 }[a];
        state.rot[i] = (state.rot[i] + 90) % 360;
      }
      refreshPanel();
    };
  });
  hud.querySelectorAll('[data-scale]').forEach(b => {
    b.onclick = () => {
      const a = b.dataset.scale;
      if (a === '1') state.scale = 1;
      else state.scale = +(state.scale * (a === '+' ? 1.1 : 1 / 1.1)).toFixed(3);
      refreshPanel();
    };
  });
  $('spin').onclick = () => {
    state.spin = !state.spin;
    $('spin').classList.toggle('on', state.spin);
  };
  $('spin').classList.add('on');
  $('back').onclick = () => ctx.goMenu();
  $('copy').onclick = async () => {
    try {
      await navigator.clipboard.writeText($('code').textContent);
      $('copy').textContent = 'Скопировано';
      setTimeout(() => { $('copy').textContent = 'Скопировать'; }, 1600);
    } catch (e) {
      $('copy').textContent = 'Не вышло — выдели вручную';
    }
  };

  function refreshPanel() {
    const key = `${state.kind}:${state.faction}:${state.id}`;
    const custom = hasCustom(`${state.kind}`, state.faction) ||
                   (state.current && state.current.userData.custom);
    const sz = state.size || new THREE.Vector3();
    $('status').innerHTML = custom
      ? `<b class="ok">Своя модель подключена</b>
         <div>Габарит в игре: ${sz.x.toFixed(1)} × ${sz.y.toFixed(1)} × ${sz.z.toFixed(1)}</div>`
      : `<b class="warn">Своей модели нет — показана процедурная</b>
         <div>Положи .glb в <code>game/models/</code> и добавь строку справа.</div>
         <div>Габарит в игре: ${sz.x.toFixed(1)} × ${sz.y.toFixed(1)} × ${sz.z.toFixed(1)}</div>`;

    const rot = state.rot;
    const parts = [`"file": "${state.faction}_${state.id}.glb"`];
    if (rot[0] || rot[1] || rot[2]) parts.push(`"rotate": [${rot[0]}, ${rot[1]}, ${rot[2]}]`);
    if (state.scale !== 1) parts.push(`"scale": ${state.scale}`);
    if (state.kind === 'ground' || state.kind === 'building') parts.push('"groundLevel": true');
    $('code').textContent = `"${key}": { ${parts.join(', ')} }`;

    // применяем разворот к тому, что стоит на столе, чтобы видеть результат
    if (state.current) {
      state.current.rotation.set(
        THREE.MathUtils.degToRad(rot[0]),
        THREE.MathUtils.degToRad(rot[1]),
        THREE.MathUtils.degToRad(rot[2]));
    }
  }

  const controls = new Controls(viewport.canvas, tcam, {
    pickMeshes: () => [],
    planeY: () => 0,
    onTap() { state.spin = !state.spin; $('spin').classList.toggle('on', state.spin); },
  });

  rebuild();

  function update(dt) {
    if (state.spin) tcam.yaw += dt * 0.35;
    tcam.update(dt);
  }

  function dispose() {
    tcam.dispose();
    controls.dispose();
    hud.remove();
    disposeScene(scene);
  }

  return { scene, camera: tcam.cam, update, dispose, state };
}
