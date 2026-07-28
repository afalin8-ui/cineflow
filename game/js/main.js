/* КАПЕЛЛА: ГАЛАКТИЧЕСКИЙ ФРОНТ — точка входа.
   Здесь: главное меню, выбор клана, переключение экранов
   (карта → бой на орбите → наземная операция), сохранение
   и справочник нейроинтерфейса. */

import { THREE, Viewport, TacticalCamera, starfield, IS_TOUCH, rnd, disposeScene } from './engine.js';
import { createGalaxy, newCampaign, ownedCount } from './galaxy.js';
import { createSpaceBattle, autoResolveSpace } from './space.js';
import { createGroundBattle, autoResolveGround } from './ground.js';
import { buildPlanet, buildNebula } from './models.js';
import { loadModelLibrary, modelCount } from './assets.js';
import {
  FACTIONS, FACTION_IDS, NEURO_BRIEF, SHIPS, STRIKE, STRIKE_ROLES,
  GROUND_UNITS, GROUND_BUILDINGS, GALAXY_MAP,
} from './data.js';

const SAVE_KEY = 'capella_save_v1';
const canvas = document.getElementById('view');
const hudRoot = document.getElementById('hud');
const viewport = new Viewport(canvas);

let mode = null;         // текущий экран: {scene, camera, update, dispose}
let campaign = null;     // состояние кампании

// ─────────────────────────────────────────────────────────────
// СОХРАНЕНИЕ
// ─────────────────────────────────────────────────────────────

function save() {
  if (!campaign) return;
  try { localStorage.setItem(SAVE_KEY, JSON.stringify(campaign)); } catch (e) { /* приватный режим */ }
}
function loadSave() {
  try {
    const raw = localStorage.getItem(SAVE_KEY);
    if (!raw) return null;
    const c = JSON.parse(raw);
    return (c && c.systems && c.playerFaction) ? c : null;
  } catch (e) { return null; }
}
function dropSave() {
  try { localStorage.removeItem(SAVE_KEY); } catch (e) { /* ничего */ }
}

// ─────────────────────────────────────────────────────────────
// ПЕРЕКЛЮЧЕНИЕ ЭКРАНОВ
// ─────────────────────────────────────────────────────────────

function setMode(factory) {
  if (mode) { mode.dispose(); mode = null; }
  hudRoot.innerHTML = '';
  mode = factory();
}

const ctx = {
  viewport, hudRoot,
  save,
  goMenu: () => showMenu(),
  showNeuro: () => showNeuro(),
  startSpaceBattle(cfg) {
    setMode(() => createSpaceBattle(ctx, {
      ...cfg,
      onEnd: res => { cfg.onEnd && cfg.onEnd(res); backToGalaxy(); },
    }));
  },
  startGroundBattle(cfg) {
    setMode(() => createGroundBattle(ctx, {
      ...cfg,
      onEnd: res => { cfg.onEnd && cfg.onEnd(res); backToGalaxy(); },
    }));
  },
  autoSpace(attacker, defender, cb) {
    const res = autoResolveSpace(attacker, defender);
    showAutoResult(
      res.result === 'attacker' ? 'Орбита взята' : 'Атака отбита',
      res.result === 'attacker'
        ? `Флот клана ${FACTIONS[attacker.faction].short} остался хозяином орбиты.`
        : `Флот клана ${FACTIONS[defender.faction].short} удержал позицию.`,
      () => cb(res));
  },
  autoGround(attacker, defender, cb) {
    const res = autoResolveGround(attacker, defender);
    showAutoResult(
      res.result === 'attacker' ? 'Планета взята' : 'Десант отбит',
      res.result === 'attacker'
        ? 'Наземные силы противника разбиты, планета переходит под контроль.'
        : 'Высадка захлебнулась. Планета осталась за обороняющимися.',
      () => cb(res));
  },
};

function backToGalaxy() {
  save();
  setMode(() => createGalaxy(ctx, campaign));
}

function showAutoResult(title, text, cb) {
  const m = document.createElement('div');
  m.className = 'modal';
  m.innerHTML = `<div class="modal-inner"><h3>${title}</h3><p>${text}</p>
    <div class="modal-actions"><button class="btn primary" data-a="ok">Дальше</button></div></div>`;
  hudRoot.appendChild(m);
  m.querySelector('[data-a="ok"]').onclick = () => { m.remove(); cb(); };
}

// ─────────────────────────────────────────────────────────────
// ФОН МЕНЮ: звёзды и планета
// ─────────────────────────────────────────────────────────────

function createBackdrop() {
  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0x05070d);
  const tcam = new TacticalCamera({ dist: 150, pitch: 0.2, yaw: 0.4, far: 6000 });
  viewport.setBloom({ strength: 0.75, radius: 0.65, threshold: 0.75, exposure: 1.05 });
  scene.add(new THREE.AmbientLight(0x7a8aa8, 1.6));
  const key = new THREE.DirectionalLight(0xffe0bb, 3.0);
  key.position.set(-160, 90, 120);
  scene.add(key);
  scene.add(buildNebula(3200, 21));
  scene.add(starfield(2800, 1900));
  const planet = buildPlanet('green', 60);
  planet.position.set(70, -22, -40);
  scene.add(planet);
  const moon = buildPlanet('rock', 12);
  moon.position.set(-80, 26, 30);
  scene.add(moon);
  return {
    scene, camera: tcam.cam,
    update(dt) {
      tcam.yaw += dt * 0.012;
      tcam.apply(dt, true);
      planet.rotation.y += dt * 0.02;
      moon.rotation.y -= dt * 0.05;
    },
    dispose() { tcam.dispose(); disposeScene(scene); },
  };
}

// ─────────────────────────────────────────────────────────────
// ГЛАВНОЕ МЕНЮ
// ─────────────────────────────────────────────────────────────

function showMenu() {
  setMode(() => {
    const bd = createBackdrop();
    const el = document.createElement('div');
    el.className = 'screen menu';
    const has = loadSave();
    el.innerHTML = `
      <div class="menu-inner">
        <header>
          <div class="eyebrow">Система Капелла · двадцать семь кланов · один дом</div>
          <h1>Галактический<br>фронт</h1>
          <p class="lead">Стратегия по мотивам Homeplanet и Empire at War.
          Карта системы, бой на орбите по честной инерции и наземная
          операция с базой и снабжением.</p>
        </header>
        <div class="menu-actions">
          ${has ? '<button class="btn primary big" data-a="continue">Продолжить кампанию</button>' : ''}
          <button class="btn ${has ? '' : 'primary '}big" data-a="new">Новая кампания</button>
          <button class="btn big" data-a="skirmish">Быстрый бой</button>
          <button class="btn ghost big" data-a="neuro">Нейроинтерфейс</button>
        </div>
        ${has ? `<div class="menu-note">Сохранение: ход ${has.turn}, клан
          ${FACTIONS[has.playerFaction].short}, миров под контролем —
          ${ownedCount(has, has.playerFaction)}.</div>` : ''}
      </div>`;
    hudRoot.appendChild(el);

    el.querySelector('[data-a="new"]').onclick = () => showFactionPick();
    el.querySelector('[data-a="skirmish"]').onclick = () => showSkirmish();
    el.querySelector('[data-a="neuro"]').onclick = () => showNeuro();
    const cont = el.querySelector('[data-a="continue"]');
    if (cont) cont.onclick = () => { campaign = loadSave(); backToGalaxy(); };

    return {
      scene: bd.scene, camera: bd.camera,
      update: dt => bd.update(dt),
      dispose() { bd.dispose(); el.remove(); },
    };
  });
}

// ─────────────────────────────────────────────────────────────
// ВЫБОР КЛАНА
// ─────────────────────────────────────────────────────────────

function showFactionPick() {
  const el = document.createElement('div');
  el.className = 'screen picker';
  el.innerHTML = `
    <div class="picker-inner">
      <h2>Выбери клан</h2>
      <div class="cards">
        ${FACTION_IDS.map(id => {
          const f = FACTIONS[id];
          return `<button class="fcard" data-f="${id}" style="--fc:${f.colorCss}">
            <div class="fc-tag">${f.tag}</div>
            <h3>${f.name}</h3>
            <div class="fc-motto">«${f.motto}»</div>
            <p>${f.desc}</p>
            <ul>${f.perks.map(p => `<li>${p}</li>`).join('')}</ul>
            <div class="fc-weak">Слабость: ${f.weakness}</div>
          </button>`;
        }).join('')}
      </div>
      <div class="picker-actions"><button class="btn ghost" data-a="back">Назад</button></div>
    </div>`;
  hudRoot.appendChild(el);
  el.querySelector('[data-a="back"]').onclick = () => el.remove();
  el.querySelectorAll('.fcard').forEach(b => {
    b.onclick = () => {
      campaign = newCampaign(b.dataset.f);
      dropSave();
      save();
      el.remove();
      backToGalaxy();
    };
  });
}

// ─────────────────────────────────────────────────────────────
// БЫСТРЫЙ БОЙ
// ─────────────────────────────────────────────────────────────

function showSkirmish() {
  const el = document.createElement('div');
  el.className = 'screen picker';
  const opt = id => `<option value="${id}">${FACTIONS[id].name}</option>`;
  el.innerHTML = `
    <div class="picker-inner narrow">
      <h2>Быстрый бой</h2>
      <p class="lead">Один бой без кампании — чтобы разобраться в управлении.</p>
      <div class="form-row"><label>Твой клан</label>
        <select data-f="mine">${FACTION_IDS.map(opt).join('')}</select></div>
      <div class="form-row"><label>Противник</label>
        <select data-f="foe">${FACTION_IDS.map(opt).join('')}</select></div>
      <div class="form-row"><label>Масштаб</label>
        <select data-f="size">
          <option value="small">Стычка</option>
          <option value="mid" selected>Сражение</option>
          <option value="big">Генеральное</option>
        </select></div>
      <div class="picker-actions">
        <button class="btn primary" data-a="space">Бой на орбите</button>
        <button class="btn primary" data-a="ground">Наземная операция</button>
        <button class="btn ghost" data-a="back">Назад</button>
      </div>
    </div>`;
  hudRoot.appendChild(el);
  const sel = k => el.querySelector(`[data-f="${k}"]`).value;
  el.querySelector('[data-f="foe"]').value = 'plektor';
  el.querySelector('[data-a="back"]').onclick = () => el.remove();

  const sizes = {
    small: { corvette: 2, frigate: 2, ecm: 1, cruiser: 1, carrier: 1, capital: 0, regiments: 2 },
    mid:   { corvette: 3, frigate: 3, ecm: 1, cruiser: 2, carrier: 1, capital: 1, regiments: 4 },
    big:   { corvette: 4, frigate: 4, ecm: 2, cruiser: 3, carrier: 2, capital: 2, regiments: 6 },
  };
  const fleetOf = s => Object.entries(sizes[s])
    .filter(([k, v]) => k !== 'regiments' && v > 0)
    .map(([id, count]) => ({ id, count }));
  // Плэктор воюет числом: тех же кораблей у него вдвое больше
  const scaleFor = (f, list) => f === 'plektor'
    ? list.map(x => ({ ...x, count: Math.round(x.count * 2) }))
    : f === 'troyden' ? list.map(x => ({ ...x, count: Math.max(1, Math.round(x.count * 0.7)) })) : list;

  el.querySelector('[data-a="space"]').onclick = () => {
    const mine = sel('mine'), foe = sel('foe'), size = sel('size');
    el.remove();
    campaign = null;
    setMode(() => createSpaceBattle(ctx, {
      attacker: { faction: mine, ships: scaleFor(mine, fleetOf(size)), reserve: scaleFor(mine, fleetOf('small')) },
      defender: { faction: foe, ships: scaleFor(foe, fleetOf(size)), station: size === 'big' },
      playerSide: 'attacker', biome: 'rock', title: 'Быстрый бой · орбита',
      onEnd: () => showMenu(),
    }));
  };
  el.querySelector('[data-a="ground"]').onclick = () => {
    const mine = sel('mine'), foe = sel('foe'), size = sel('size');
    el.remove();
    campaign = null;
    setMode(() => createGroundBattle(ctx, {
      player: { faction: mine, regiments: sizes[size].regiments, credits: 4000 },
      enemy: { faction: foe, regiments: sizes[size].regiments, credits: 4000, turrets: size !== 'small' },
      biome: 'green', title: 'Быстрый бой · планета',
      onEnd: () => showMenu(),
    }));
  };
}

// ─────────────────────────────────────────────────────────────
// НЕЙРОИНТЕРФЕЙС — справочник
// ─────────────────────────────────────────────────────────────

function showNeuro() {
  const el = document.createElement('div');
  el.className = 'screen neuro';
  const tabs = ['Правила', 'Флот', 'Авиация', 'Земля', 'Управление'];
  el.innerHTML = `
    <div class="neuro-inner">
      <div class="neuro-head">
        <h2>Нейроинтерфейс</h2>
        <button class="btn ghost" data-a="close">Закрыть</button>
      </div>
      <div class="neuro-tabs">${tabs.map((t, i) =>
        `<button data-tab="${i}"${i === 0 ? ' class="on"' : ''}>${t}</button>`).join('')}</div>
      <div class="neuro-body" data-role="body"></div>
    </div>`;
  hudRoot.appendChild(el);
  el.querySelector('[data-a="close"]').onclick = () => el.remove();

  const body = el.querySelector('[data-role="body"]');
  const render = i => {
    if (i === 0) {
      body.innerHTML = NEURO_BRIEF.map(b =>
        `<section><h3>${b.title}</h3><p>${b.text}</p></section>`).join('');
    } else if (i === 1) {
      body.innerHTML = FACTION_IDS.map(f => `
        <section><h3 style="color:${FACTIONS[f].colorCss}">${FACTIONS[f].name}</h3>
        <table class="stats"><tr><th>Корабль</th><th>Прочн.</th><th>Броня</th>
        <th>Скорость</th><th>Тяга</th><th>Цена</th></tr>
        ${SHIPS[f].map(s => `<tr><td>${s.name}<em>${s.role}</em></td><td>${s.hp}</td>
          <td>${Math.round(s.armor * 100)}%</td><td>${s.maxSpeed}</td>
          <td>${s.thrust}</td><td>${s.cost}</td></tr>`).join('')}
        </table></section>`).join('');
    } else if (i === 2) {
      body.innerHTML = `
        <section><h3>Три роли</h3>
        <p>${Object.values(STRIKE_ROLES).map(r => `<b>${r.label}</b> — ${r.hint}.`).join('<br>')}</p>
        <p>Звено — пять машин. Авианосец поднимает звено из свободного места
        в ангаре; сбитое звено восстанавливается через полминуты.</p></section>
        ${FACTION_IDS.map(f => `<section><h3 style="color:${FACTIONS[f].colorCss}">${FACTIONS[f].short}</h3>
        <table class="stats"><tr><th>Машина</th><th>Прочн.</th><th>Скорость</th><th>Урон</th><th>Дальность</th></tr>
        ${Object.values(STRIKE[f]).map(s => `<tr><td>${STRIKE_ROLES[s.role].label} ${s.name}</td>
          <td>${s.hp}</td><td>${s.maxSpeed}</td><td>${Math.round(s.dmg)}</td><td>${s.range}</td></tr>`).join('')}
        </table></section>`).join('')}`;
    } else if (i === 3) {
      body.innerHTML = `
        <section><h3>Постройки</h3><table class="stats">
        <tr><th>Здание</th><th>Цена</th><th>Прочн.</th><th>Что даёт</th></tr>
        ${Object.values(GROUND_BUILDINGS).map(b => `<tr><td>${b.name}</td><td>${b.cost}</td>
          <td>${b.hp}</td><td>${b.desc}</td></tr>`).join('')}
        </table></section>
        ${FACTION_IDS.map(f => `<section><h3 style="color:${FACTIONS[f].colorCss}">${FACTIONS[f].short}</h3>
        <table class="stats"><tr><th>Юнит</th><th>Цена</th><th>Прочн.</th><th>Скорость</th><th>Дальность</th></tr>
        ${Object.values(GROUND_UNITS[f]).map(u => `<tr><td>${u.name}<em>${u.desc}</em></td><td>${u.cost}</td>
          <td>${u.hp}</td><td>${u.speed}</td><td>${u.weapon ? u.weapon.range : '—'}</td></tr>`).join('')}
        </table></section>`).join('')}`;
    } else {
      body.innerHTML = `
        <section><h3>Планшет</h3><p>
        Касание по своему кораблю или юниту — выбрать. Когда что-то выбрано:
        касание по врагу — атаковать, касание по пустому месту — идти туда.
        Тянуть одним пальцем — двигать карту. Щипок — приближение, поворот
        двух пальцев — облёт. Долгое нажатие и потянуть — рамка выделения
        (или кнопка «Рамка» справа).</p></section>
        <section><h3>Компьютер</h3><p>
        Левая кнопка — выбрать, с протяжкой — рамка. Правая — приказ.
        Колесо — приближение. Alt+ЛКМ или средняя кнопка — облёт.
        WASD или стрелки — двигать карту, Q/E — поворот, R/F — выше/ниже
        в космосе. Пробел — пауза, Escape — снять выделение.</p></section>
        <section><h3>Кнопки справа</h3><p>
        Быстрый выбор целых групп: весь флот, только линкоры, только
        авианосцы, вся авиация. На земле — все войска, техника, пехота,
        сборщики. Это самый быстрый способ управлять с планшета.</p></section>`;
    }
  };
  render(0);
  el.querySelectorAll('[data-tab]').forEach(b => {
    b.onclick = () => {
      el.querySelectorAll('[data-tab]').forEach(x => x.classList.remove('on'));
      b.classList.add('on');
      render(+b.dataset.tab);
      body.scrollTop = 0;
    };
  });
}

// ─────────────────────────────────────────────────────────────
// ЦИКЛ
// ─────────────────────────────────────────────────────────────

let last = performance.now();
function frame(now) {
  const dt = Math.min(0.05, (now - last) / 1000) || 0.016;
  last = now;
  if (mode) {
    mode.update(dt);
    viewport.render(mode.scene, mode.camera);
  }
  requestAnimationFrame(frame);
}

// Не даём странице скроллиться и зумиться на планшете
document.addEventListener('gesturestart', e => e.preventDefault());
document.addEventListener('touchmove', e => {
  if (e.target === canvas) e.preventDefault();
}, { passive: false });

// Сначала пробуем подтянуть внешние модели (game/models/manifest.json).
// Нет манифеста — молча работаем на процедурных, игра от этого не зависит.
loadModelLibrary()
  .then(n => { if (n) console.info(`Загружено внешних моделей: ${n} из ${modelCount()}`); })
  .catch(() => {})
  .finally(() => showMenu());

requestAnimationFrame(frame);

// Автосохранение при уходе со страницы
addEventListener('visibilitychange', () => { if (document.hidden) save(); });
addEventListener('pagehide', save);
