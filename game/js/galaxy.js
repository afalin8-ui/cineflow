/* КАРТА СИСТЕМЫ КАПЕЛЛА — стратегический слой кампании.

   Пошагово: сначала ходит игрок, потом кланы-соперники. За ход можно
   строить на своих мирах и один раз двинуть каждый флот по маршруту.
   Вход в чужую систему — бой на орбите; выиграл орбиту — можешь
   высаживать полки, и тогда начинается наземная операция. */

import {
  THREE, TacticalCamera, Controls, Fx, starfield, screenOf,
  clamp, rnd, disposeScene, IS_TOUCH,
} from './engine.js';
import { buildPlanet, buildNebula } from './models.js';
import { nebulaTexture } from './textures.js';
import {
  FACTIONS, FACTION_IDS, GALAXY_MAP, PLANET_BUILDINGS, REGIMENT_COST,
  SHIPS, shipDef, STATION,
  TECH_LEVELS, MAX_TECH, RESEARCH_PER_LAB, RESEARCH_BASE, supportFrom, EXTERMINATUS,
  shipHasDrive, BREAKER,
} from './data.js';

const NEUTRAL = { colorCss: '#6f6b63', tag: '—', name: 'Ничей мир', short: 'ничей' };

// ─────────────────────────────────────────────────────────────
// СОСТОЯНИЕ КАМПАНИИ (оно же сохранение)
// ─────────────────────────────────────────────────────────────

export function newCampaign(playerFaction) {
  const systems = {};
  for (const s of GALAXY_MAP.systems) {
    systems[s.id] = {
      id: s.id, owner: null, buildings: [], fleet: [], regiments: 0, moved: false,
      // блокада: {faction, fleet} — чужой флот на орбите без боя
      siege: null,
      gateJammed: 0,     // до какого хода врата заглушены взломщиком
      breakers: 0,       // взломщики, готовые к вылету
    };
  }
  for (const s of GALAXY_MAP.systems) {
    if (!s.start) continue;
    const st = systems[s.id];
    st.owner = s.start;
    st.buildings = ['shipyard', 'garrison', 'mine'];
    st.regiments = 4;
    st.fleet = [
      { id: 'corvette', count: 2 }, { id: 'frigate', count: 2 },
      { id: 'ecm', count: 1 }, { id: 'cruiser', count: 1 }, { id: 'carrier', count: 1 },
    ];
    if (s.station) st.buildings.push('station');
  }
  // Клото — родина Тройден, но её держит Рииз: с неё и начинается война
  systems.klotho.owner = 'reez';
  systems.klotho.buildings = ['garrison', 'mine'];
  systems.klotho.regiments = 5;
  systems.klotho.fleet = [
    { id: 'corvette', count: 2 }, { id: 'frigate', count: 1 }, { id: 'cruiser', count: 1 },
  ];

  const credits = {};
  const research = {};
  const tech = {};
  for (const f of FACTION_IDS) { credits[f] = 2200; research[f] = 0; tech[f] = 1; }

  return {
    version: 2,
    playerFaction,
    turn: 1,
    credits,
    research,          // накопленные очки науки, тратятся на уровень
    tech,              // уровень технологий клана, 1..MAX_TECH
    systems,
    log: [{ turn: 1, text: 'Флот клана Тройден уходит с Клото. Приказ — закрепиться и вернуть родной мир.' }],
  };
}

export function neighborsOf(id) {
  const out = [];
  for (const [a, b] of GALAXY_MAP.links) {
    if (a === id) out.push(b);
    else if (b === id) out.push(a);
  }
  return out;
}

export function fleetSize(fleet) {
  return (fleet || []).reduce((a, f) => a + f.count, 0);
}

export function fleetValue(faction, fleet) {
  let v = 0;
  for (const f of fleet || []) {
    const d = shipDef(faction, f.id);
    if (d) v += d.hp * f.count;
  }
  return v;
}

export function mergeFleets(a, b) {
  const map = new Map();
  for (const f of [...(a || []), ...(b || [])]) map.set(f.id, (map.get(f.id) || 0) + f.count);
  return [...map.entries()].map(([id, count]) => ({ id, count }));
}

export function incomeOf(camp, faction) {
  let sum = 0;
  for (const def of GALAXY_MAP.systems) {
    const st = camp.systems[def.id];
    if (st.owner !== faction) continue;
    /* Планета после тотальной бомбардировки почти ничего не приносит:
       это и есть цена Экстерминатуса, и платится она до конца
       кампании, а не один ход. */
    /* Блокада обнуляет доход целиком: пока на орбите чужой флот,
       с планеты ничего не вывезти, сколько бы рудников на ней ни
       стояло. Это и делает флот инструментом давления, а не только
       тараном. */
    if (st.siege) continue;
    const base = def.income + (st.buildings.includes('mine') ? 120 : 0);
    sum += st.scorched ? Math.round(base * EXTERMINATUS.ecoPenalty) : base;
  }
  return sum;
}

/* Наука. В отличие от кредитов её дают только научные центры —
   планета сама по себе почти ничего не приносит. Поэтому расширение
   кормит флот, а вкладываться в технологии приходится отдельно. */
export function researchOf(camp, faction) {
  let labs = 0;
  for (const def of GALAXY_MAP.systems) {
    const st = camp.systems[def.id];
    if (st.owner === faction && st.buildings.includes('lab')) labs++;
  }
  return labs ? labs * RESEARCH_PER_LAB + RESEARCH_BASE : RESEARCH_BASE;
}

export function techOf(camp, faction) {
  return (camp.tech && camp.tech[faction]) || 1;
}

// Сколько науки до следующего уровня. null — дальше некуда
export function nextTechCost(camp, faction) {
  const lvl = techOf(camp, faction);
  return lvl >= MAX_TECH ? null : TECH_LEVELS[lvl].cost;
}

/* Доступна ли техника уровня tier. Старые сохранения без поля tech
   считаем первым уровнем, а технику без поля tier — доступной всегда. */
export function techAllows(camp, faction, tier) {
  return !tier || tier <= techOf(camp, faction);
}

/* Можно ли увести флот из системы. Большим кораблям врата не нужны —
   у них свой привод; всем остальным нужны работающие врата на месте
   старта. Заглушенные взломщиком врата не работают ни у кого. */
export function jumpCheck(camp, fromId, faction) {
  const st = camp.systems[fromId];
  const heavy = [], light = [];
  for (const item of st.fleet || []) {
    const d = shipDef(faction, item.id);
    (shipHasDrive(d) ? heavy : light).push(item);
  }
  const gate = st.buildings.includes('warpgate');
  const jammed = (st.gateJammed || 0) > camp.turn;
  if (!light.length) return { ok: true, heavy, light: [] };
  if (gate && !jammed) return { ok: true, heavy, light };
  return {
    ok: false, heavy, light,
    reason: jammed
      ? 'Врата заглушены взломщиком: лёгкие корабли заперты в системе'
      : 'Без гиперворот из системы уйдут только флагманы и носители',
  };
}

export function ownedCount(camp, faction) {
  return GALAXY_MAP.systems.filter(s => camp.systems[s.id].owner === faction).length;
}

// ─────────────────────────────────────────────────────────────
// ЭКРАН КАРТЫ
// ─────────────────────────────────────────────────────────────

export function createGalaxy(ctx, camp) {
  const { viewport, hudRoot } = ctx;
  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0x05070d);

  const tcam = new TacticalCamera({
    dist: 210, minDist: 70, maxDist: 420, pitch: 0.75, yaw: 0.15,
    bounds: { x: 130, z: 130 }, far: 4000,
  });

  // Карта должна читаться целиком: заливка + мягкий ключ сверху,
  // а звезда системы добавляет тёплый блик ближним мирам.
  scene.add(new THREE.AmbientLight(0x8a9ab8, 2.2));
  const key = new THREE.DirectionalLight(0xffeccf, 2.0);
  key.position.set(60, 120, 90);
  scene.add(key);
  const rim = new THREE.DirectionalLight(0x6090d0, 1.1);
  rim.position.set(-90, 30, -70);
  scene.add(rim);
  const star = new THREE.PointLight(0xffd9a0, 2.6, 700, 1.4);
  star.position.set(0, 40, -20);
  scene.add(star);
  scene.add(buildNebula(2600, 7));
  // Отражения: металл должен что-то отражать, иначе он чёрный
  scene.environment = viewport.environmentFrom(nebulaTexture(7));
  scene.environmentIntensity = 0.7;
  scene.add(starfield(2600, 1500));

  viewport.setBloom({ strength: 0.7, radius: 0.6, threshold: 0.7, exposure: 1.0 });
  const fx = new Fx(scene);
  fx.setCamera(tcam.cam);

  // ── узлы карты
  const nodes = {};
  const SCALE = 1.6;
  for (const def of GALAXY_MAP.systems) {
    const radius = 3.0 + def.slots * 0.45;
    const g = buildPlanet(def.biome, radius, 1, def.id);
    g.position.set(def.pos[0] * SCALE * 0.55, def.pos[1] * SCALE * 0.42, def.pos[2] * SCALE * 0.55);
    // солнце считаем уже от итоговой позиции мира, иначе венец смотрит не туда
    g.userData.setSun(star.position.clone().sub(g.position).normalize());
    scene.add(g);

    // кольцо принадлежности
    const ringGeo = new THREE.TorusGeometry(radius * 1.65, radius * 0.09, 6, 32);
    const ring = new THREE.Mesh(ringGeo, new THREE.MeshBasicMaterial({
      color: 0x6f6b63, transparent: true, opacity: 0.9, toneMapped: false,
    }));
    ring.rotation.x = Math.PI / 2;
    g.add(ring);

    // подсветка доступного хода
    const hlGeo = new THREE.TorusGeometry(radius * 2.15, radius * 0.06, 6, 32);
    const hl = new THREE.Mesh(hlGeo, new THREE.MeshBasicMaterial({
      color: 0x8fffc8, transparent: true, opacity: 0.9, toneMapped: false,
    }));
    hl.rotation.x = Math.PI / 2;
    hl.visible = false;
    g.add(hl);

    const node = { def, obj: g, pos: g.position, ring, hl, radius, kind: 'system', dead: false };
    g.userData.entity = node;
    nodes[def.id] = node;
  }

  // ── маршруты
  const laneMat = new THREE.LineBasicMaterial({
    color: 0x39485e, transparent: true, opacity: 0.75, toneMapped: false,
  });
  const laneGroup = new THREE.Group();
  scene.add(laneGroup);
  for (const [a, b] of GALAXY_MAP.links) {
    const pa = nodes[a].pos, pb = nodes[b].pos;
    const g = new THREE.BufferGeometry().setFromPoints([pa.clone(), pb.clone()]);
    laneGroup.add(new THREE.Line(g, laneMat));
  }

  const state = { selected: null, busy: false };

  // ── HUD
  const hud = document.createElement('div');
  hud.className = 'hud hud-galaxy';
  hud.innerHTML = `
    <div class="topbar">
      <div class="res">
        <span class="credits" data-role="credits">0</span><small data-role="income"></small>
      </div>
      <div class="res science">
        <span class="sci" data-role="science">0</span><small data-role="sciflow"></small>
      </div>
      <div class="title">Система Капелла · ход <span data-role="turn">1</span></div>
      <div class="speedctl">
        <button data-role="neuro">Нейроинтерфейс</button>
        <button data-role="endturn" class="primary">Конец хода</button>
      </div>
    </div>
    <div class="scoreline" data-role="score"></div>
    <div class="markers" data-role="markers"></div>
    <div class="galaxy-panel" data-role="panel"></div>
    <div class="hint">${IS_TOUCH
      ? 'Касание по миру — выбрать · тянуть — вращать карту · щипок — приближение'
      : 'ЛКМ — выбрать мир · тянуть — рамка/облёт (Alt) · колесо — приближение · WASD — карта'}</div>
    <div class="endcard" data-role="end" style="display:none"></div>
  `;
  hudRoot.appendChild(hud);
  const $ = r => hud.querySelector(`[data-role="${r}"]`);

  $('endturn').onclick = () => endTurn();
  $('neuro').onclick = () => ctx.showNeuro && ctx.showNeuro();

  // ── маркеры названий
  const markers = $('markers');
  const markerEls = {};
  for (const def of GALAXY_MAP.systems) {
    const d = document.createElement('div');
    d.className = 'gal-marker';
    d.innerHTML = `<b>${def.name}</b><span class="gm-info"></span>`;
    markers.appendChild(d);
    markerEls[def.id] = d;
  }

  function ownerOf(id) {
    const o = camp.systems[id].owner;
    return o ? FACTIONS[o] : NEUTRAL;
  }

  function refreshMap() {
    for (const def of GALAXY_MAP.systems) {
      const st = camp.systems[def.id];
      const f = ownerOf(def.id);
      nodes[def.id].ring.material.color.set(f.colorCss);
      nodes[def.id].ring.material.opacity = st.owner ? 0.95 : 0.4;
    }
    // подсветка доступных перелётов
    const sel = state.selected;
    const canMove = sel && camp.systems[sel].owner === camp.playerFaction &&
      fleetSize(camp.systems[sel].fleet) > 0 && !camp.systems[sel].moved;
    const reach = canMove ? neighborsOf(sel) : [];
    for (const id in nodes) nodes[id].hl.visible = reach.includes(id);
  }

  function updateMarkers() {
    const w = viewport.w, h = viewport.h;
    for (const def of GALAXY_MAP.systems) {
      const n = nodes[def.id], st = camp.systems[def.id];
      const p = screenOf(n.pos, tcam.cam, w, h);
      const el = markerEls[def.id];
      if (p.z > 1) { el.style.display = 'none'; continue; }
      el.style.display = 'block';
      el.style.transform = `translate(${(p.x - 60) | 0}px,${(p.y + n.radius * 3 + 6) | 0}px)`;
      const f = ownerOf(def.id);
      el.style.color = f.colorCss;
      const ships = fleetSize(st.fleet);
      el.lastChild.textContent = `${f.tag}${ships ? ' · ⬢' + ships : ''}${st.regiments ? ' · ▮' + st.regiments : ''}`;
      el.classList.toggle('sel', state.selected === def.id);
      el.classList.toggle('mine', st.owner === camp.playerFaction);
    }
  }

  /* ── ТЕХНОЛОГИИ.
     Живут не на планете, а у клана целиком, поэтому блок показываем,
     когда ни один мир не выбран: это «общий экран развития». */
  function techBlock() {
    const my = camp.playerFaction;
    const lvl = techOf(camp, my);
    const box = document.createElement('div');
    box.className = 'gp-block tech-block';

    const cost = nextTechCost(camp, my);
    const have = Math.floor(camp.research[my] || 0);
    const cur = TECH_LEVELS[lvl - 1];

    let html = `<h4>Технологии · уровень ${lvl} из ${MAX_TECH}</h4>`;
    html += `<div class="tech-now"><b>${cur.name}</b><br><small>${cur.unlocks}</small></div>`;
    html += `<div class="gp-line">Наука: ${have}${cost !== null ? ` из ${cost}` : ''} ·
             +${researchOf(camp, my)} за ход</div>`;

    if (cost !== null) {
      const next = TECH_LEVELS[lvl];
      const pct = Math.min(100, Math.round(have / cost * 100));
      html += `<div class="tech-bar"><i style="width:${pct}%"></i></div>`;
      html += `<div class="tech-next"><b>Дальше: ${next.name}</b><br>
               <small>${next.unlocks}</small></div>`;
    } else {
      html += '<div class="tech-next"><b>Всё изучено</b></div>';
    }
    box.innerHTML = html;

    if (cost !== null) {
      const b = document.createElement('button');
      b.className = 'act';
      const enough = have >= cost;
      b.innerHTML = `<b>Изучить: ${TECH_LEVELS[lvl].name}</b><small>${
        enough ? `${cost} очков науки` : `не хватает ${cost - have} очков`}</small>`;
      b.disabled = !enough;
      b.onclick = () => {
        if (camp.research[my] < cost) return;
        camp.research[my] -= cost;
        camp.tech[my] = lvl + 1;
        logLine(`Изучен ${lvl + 1}-й уровень технологий: ${TECH_LEVELS[lvl].name}.`);
        refreshAll();
      };
      box.appendChild(b);
    }

    const hint = document.createElement('div');
    hint.className = 'act-note';
    hint.textContent = 'Науку дают только научные центры на своих планетах. ' +
      'Кредиты — сами планеты и рудники на них.';
    box.appendChild(hint);
    return box;
  }

  // ── панель мира
  function renderPanel() {
    const panel = $('panel');
    const id = state.selected;
    if (!id) {
      panel.innerHTML = `<div class="gp-empty">
        <h3>Система Капелла</h3>
        <p>Выбери мир, чтобы посмотреть его состояние. Свои миры строят и
        снаряжают флот, чужие — берут штурмом.</p></div>`;
      panel.appendChild(techBlock());
      return;
    }
    const def = GALAXY_MAP.systems.find(s => s.id === id);
    const st = camp.systems[id];
    const f = ownerOf(id);
    const mine = st.owner === camp.playerFaction;
    const my = camp.playerFaction;

    let html = `<div class="gp-head" style="border-color:${f.colorCss}">
      <h3>${def.name}</h3>
      <div class="gp-owner" style="color:${f.colorCss}">${st.owner ? f.name : 'Ничей мир'}</div>
      <div class="gp-line">Доход ${def.income}${st.buildings.includes('mine') ? ' + 120' : ''} кр/ход · мест под постройки: ${def.slots}</div>
      ${st.scorched ? '<div class="gp-line scorched">Экологическая катастрофа: доход шестая часть</div>' : ''}
      ${st.siege ? `<div class="gp-line sieged">Блокада: ${FACTIONS[st.siege.faction].short} держит орбиту,
        доход обнулён</div>` : ''}
      ${(st.gateJammed || 0) > camp.turn
        ? `<div class="gp-line sieged">Врата заглушены до ${st.gateJammed} хода</div>` : ''}
      ${st.breakers > 0 ? `<div class="gp-line">Взломщиков наготове: ${st.breakers}</div>` : ''}
    </div>`;

    const fleetTxt = st.fleet.length
      ? st.fleet.map(x => {
          const d = shipDef(st.owner || my, x.id);
          return `${d ? d.name : x.id} ×${x.count}`;
        }).join('<br>')
      : '<i>пусто</i>';
    html += `<div class="gp-block"><h4>Флот на орбите</h4><div class="gp-list">${fleetTxt}</div></div>`;
    html += `<div class="gp-block"><h4>Наземные полки</h4><div class="gp-list">${st.regiments || '<i>нет</i>'}</div></div>`;

    const bnames = st.buildings.map(b => PLANET_BUILDINGS[b] ? PLANET_BUILDINGS[b].name : b);
    html += `<div class="gp-block"><h4>Постройки</h4><div class="gp-list">${bnames.join(', ') || '<i>нет</i>'}</div></div>`;

    panel.innerHTML = html;

    const actions = document.createElement('div');
    actions.className = 'gp-actions';
    panel.appendChild(actions);

    const btn = (label, sub, fn, disabled, cls) => {
      const b = document.createElement('button');
      b.className = 'act' + (cls ? ' ' + cls : '');
      b.innerHTML = `<b>${label}</b>${sub ? `<small>${sub}</small>` : ''}`;
      b.disabled = !!disabled;
      b.onclick = fn;
      actions.appendChild(b);
      return b;
    };

    /* Блокада. Свой флот, стоящий над чужим миром, может пойти на
       штурм в любой ход. Владелец блокированной планеты — наоборот,
       обязан её снимать, иначе останется без денег. */
    if (st.siege && st.siege.faction === my) {
      btn('Начать штурм', 'Флот с орбиты идёт в бой', () => {
        const keep = st.siege;
        st.siege = null;
        // штурм ведёт стоявший флот: подкладываем его как атакующий
        startSiegeAssault(id, keep);
      });
      const note = document.createElement('div');
      note.className = 'act-note';
      note.textContent = 'Пока блокада стоит, планета не приносит владельцу ничего.';
      actions.appendChild(note);
    } else if (st.siege && st.owner === my) {
      const note = document.createElement('div');
      note.className = 'act-note';
      note.textContent = `Орбиту держит ${FACTIONS[st.siege.faction].short}. `
        + 'Доход мира обнулён, пока блокада не снята: подведи флот из соседней системы.';
      actions.appendChild(note);
    }

    if (mine) {
      // постройки
      for (const key of ['mine', 'lab', 'shipyard', 'garrison', 'warpgate', 'aogun', 'station']) {
        if (st.buildings.includes(key)) continue;
        const p = PLANET_BUILDINGS[key];
        const noSlot = st.buildings.length >= def.slots;
        btn(p.name, `${p.cost} кр · ${p.desc}`, () => {
          if (camp.credits[my] < p.cost || noSlot) return;
          camp.credits[my] -= p.cost;
          st.buildings.push(key);
          logLine(`${def.name}: построена ${p.name.toLowerCase()}.`);
          refreshAll();
        }, camp.credits[my] < p.cost || noSlot);
      }
      // корабли
      if (st.buildings.includes('shipyard')) {
        const sep = document.createElement('div');
        sep.className = 'gp-sep';
        sep.textContent = 'Верфь';
        actions.appendChild(sep);
        for (const d of SHIPS[my]) {
          // Не открытые технологиями корабли показываем, но серыми —
          // так видно, ради чего копить науку
          const locked = !techAllows(camp, my, d.tier);
          const sub = locked
            ? `нужен ${d.tier}-й уровень технологий`
            : `${d.cost} кр · ${d.role}`;
          btn(d.name, sub, () => {
            if (locked || camp.credits[my] < d.cost) return;
            camp.credits[my] -= d.cost;
            const cur = st.fleet.find(x => x.id === d.id);
            if (cur) cur.count++; else st.fleet.push({ id: d.id, count: 1 });
            refreshAll();
          }, locked || camp.credits[my] < d.cost, locked ? 'locked' : '');
        }
      }
      // взломщик строится на верфи и ждёт своего часа
      if (st.buildings.includes('shipyard')) {
        const sep = document.createElement('div');
        sep.className = 'gp-sep';
        sep.textContent = 'Диверсия';
        actions.appendChild(sep);
        btn(BREAKER.name, `${BREAKER.cost} кр · ${BREAKER.desc}`, () => {
          if (camp.credits[my] < BREAKER.cost) return;
          camp.credits[my] -= BREAKER.cost;
          st.breakers = (st.breakers || 0) + 1;
          refreshAll();
        }, camp.credits[my] < BREAKER.cost);

        if (st.breakers > 0) {
          /* Цель — любая соседняя чужая система с вратами. Глушим их
             и теряем взломщика: он уходит в один конец. */
          for (const nid of neighborsOf(id)) {
            const n = camp.systems[nid];
            if (!n.owner || n.owner === my) continue;
            if (!n.buildings.includes('warpgate')) continue;
            const nd = GALAXY_MAP.systems.find(x => x.id === nid);
            const already = (n.gateJammed || 0) > camp.turn;
            btn(`Заглушить врата · ${nd.name}`,
              already ? 'уже заглушены' : `${BREAKER.jamTurns} хода · взломщик гибнет`, () => {
                if (st.breakers <= 0 || already) return;
                st.breakers--;
                n.gateJammed = camp.turn + BREAKER.jamTurns;
                logLine(`${nd.name}: гиперворота заглушены на ${BREAKER.jamTurns} хода.`);
                refreshAll();
              }, already);
          }
        }
      }

      if (st.buildings.includes('garrison')) {
        const sep = document.createElement('div');
        sep.className = 'gp-sep';
        sep.textContent = 'Гарнизон';
        actions.appendChild(sep);
        btn('Набрать полк', `${REGIMENT_COST} кр · высаживается с флотом`, () => {
          if (camp.credits[my] < REGIMENT_COST) return;
          camp.credits[my] -= REGIMENT_COST;
          st.regiments++;
          refreshAll();
        }, camp.credits[my] < REGIMENT_COST);
      }
      if (fleetSize(st.fleet) && !st.moved) {
        const note = document.createElement('div');
        note.className = 'act-note';
        note.textContent = 'Флот готов к переходу: коснись подсвеченного мира на карте.';
        actions.appendChild(note);
      } else if (st.moved) {
        const note = document.createElement('div');
        note.className = 'act-note';
        note.textContent = 'Флот уже совершил переход в этом ходу.';
        actions.appendChild(note);
      }
    } else {
      const note = document.createElement('div');
      note.className = 'act-note';
      note.textContent = st.owner
        ? 'Чужой мир. Подведи флот из соседней системы, чтобы начать бой на орбите.'
        : 'Ничей мир. Займи его флотом — сопротивления не будет.';
      actions.appendChild(note);
    }
  }

  /* Короткое окно с объяснением. Нужно именно объяснение, а не отказ
     молчком: правило про врата неочевидно, и без подсказки игрок
     решит, что игра съела ему флот. */
  function notify(title, text) {
    const m = document.createElement('div');
    m.className = 'modal';
    m.innerHTML = `<div class="modal-inner"><h3>${title}</h3><p>${text}</p>
      <div class="modal-actions"><button class="btn primary" data-a="ok">Понятно</button></div></div>`;
    hudRoot.appendChild(m);
    m.querySelector('[data-a="ok"]').onclick = () => m.remove();
  }

  function logLine(text) {
    camp.log.push({ turn: camp.turn, text });
    if (camp.log.length > 60) camp.log.shift();
  }

  function refreshAll() {
    refreshMap();
    renderPanel();
    const my = camp.playerFaction;
    $('credits').textContent = Math.floor(camp.credits[my]);
    $('income').textContent = `+${incomeOf(camp, my)} за ход`;
    $('science').textContent = Math.floor(camp.research[my] || 0);
    const nc = nextTechCost(camp, my);
    $('sciflow').textContent = nc === null
      ? `+${researchOf(camp, my)} · всё изучено`
      : `+${researchOf(camp, my)} · ур. ${techOf(camp, my)} из ${MAX_TECH}`;
    $('turn').textContent = camp.turn;
    $('score').innerHTML = FACTION_IDS.map(f => {
      const n = ownedCount(camp, f);
      return `<span style="color:${FACTIONS[f].colorCss}">${FACTIONS[f].short}: ${n}</span>`;
    }).join('<span class="sep">·</span>');
  }

  // ── ПЕРЕХОД ФЛОТА ────────────────────────────────────────
  function tryMoveFleet(fromId, toId) {
    const from = camp.systems[fromId], to = camp.systems[toId];
    const my = camp.playerFaction;
    if (from.owner !== my || from.moved || !fleetSize(from.fleet)) return;
    if (!neighborsOf(fromId).includes(toId)) return;

    /* Гиперпрыжок. Без врат из системы уйдут только флагманы и
       носители — у них свой привод. Остальные остаются на месте,
       и об этом надо сказать прямо, иначе игрок решит, что игра
       съела половину его флота. */
    const jump = jumpCheck(camp, fromId, my);
    if (!jump.ok && !jump.heavy.length) {
      notify('Прыжок невозможен', jump.reason
        + '. Построй врата на этой планете или веди сюда тяжёлые корабли.');
      return;
    }
    const goes = jump.ok ? from.fleet : jump.heavy;
    const stays = jump.ok ? [] : jump.light;
    if (!jump.ok) {
      logLine(`${GALAXY_MAP.systems.find(s => s.id === fromId).name}: ` +
        `без врат ушли только тяжёлые корабли, лёгкие остались.`);
    }

    // свой или ничей мир — просто перелёт
    if (to.owner === my || to.owner === null) {
      to.fleet = mergeFleets(to.fleet, goes);
      const regs = from.regiments;
      from.fleet = stays;
      from.moved = true;
      if (to.owner === null) {
        to.owner = my;
        to.regiments += Math.min(1, regs);
        from.regiments = Math.max(0, regs - 1);
        logLine(`${GALAXY_MAP.systems.find(s => s.id === toId).name}: система занята без боя.`);
      }
      state.selected = toId;
      refreshAll();
      return;
    }
    // враг — предлагаем выбор: штурмовать сейчас или встать блокадой
    offerBattle(fromId, toId);
  }

  /* Штурм с блокады. Отличается от обычной атаки только тем, что
     атакующий флот берётся не из соседней системы, а из самой
     блокады — он уже стоит на орбите. */
  function startSiegeAssault(toId, siege) {
    const to = camp.systems[toId];
    const toDef = GALAXY_MAP.systems.find(s => s.id === toId);
    const my = camp.playerFaction;
    const attacker = { faction: my, ships: siege.fleet.map(x => ({ ...x })), reserve: [] };
    const defender = {
      faction: to.owner, ships: to.fleet.map(x => ({ ...x })),
      station: to.buildings.includes('station'),
    };
    const apply = res => {
      if (res.result === 'victory' || res.result === 'attacker') {
        to.fleet = res.attacker || [];
        to.owner = my;               // орбита и мир переходят разом:
        to.regiments = 0;            // блокада уже выморила гарнизон
        logLine(`${toDef.name}: блокада перешла в штурм, мир взят.`);
      } else {
        logLine(`${toDef.name}: штурм с блокады отбит, флот потерян.`);
        to.fleet = res.defender || to.fleet;
      }
      state.selected = toId;
      refreshAll();
      checkVictory();
    };
    ctx.startSpaceBattle({
      attacker, defender, playerSide: 'attacker', biome: toDef.biome,
      system: toDef.id,
      groundGun: to.buildings.includes('aogun') ? to.owner : null,
      title: `Штурм с блокады · ${toDef.name}`,
      onEnd: apply,
    });
  }

  function offerBattle(fromId, toId) {
    const from = camp.systems[fromId], to = camp.systems[toId];
    const my = camp.playerFaction;
    const toDef = GALAXY_MAP.systems.find(s => s.id === toId);
    const modal = document.createElement('div');
    modal.className = 'modal';
    modal.innerHTML = `<div class="modal-inner">
      <h3>Атака на ${toDef.name}</h3>
      <p>На орбите: ${fleetSize(to.fleet)} кораблей клана ${FACTIONS[to.owner].short}${
        to.buildings.includes('station') ? ' и орбитальная станция' : ''}.
      Наземных полков у противника: ${to.regiments}.</p>
      <p>Твой флот: ${fleetSize(from.fleet)} кораблей, полков к высадке: ${from.regiments}.</p>
      <p class="gp-line">Можно не штурмовать, а встать на орбите: пока флот
      висит над планетой, она не приносит владельцу ни кредита. Но и твой
      флот всё это время занят.</p>
      <div class="modal-actions">
        <button class="btn primary" data-a="fight">В бой</button>
        <button class="btn" data-a="siege">Встать блокадой</button>
        <button class="btn" data-a="auto">Быстрый расчёт</button>
        <button class="btn ghost" data-a="cancel">Отмена</button>
      </div></div>`;
    hudRoot.appendChild(modal);
    modal.querySelector('[data-a="cancel"]').onclick = () => modal.remove();
    modal.querySelector('[data-a="siege"]').onclick = () => {
      modal.remove();
      to.siege = { faction: my, fleet: from.fleet.map(x => ({ ...x })) };
      from.fleet = [];
      from.moved = true;
      logLine(`${toDef.name}: блокада. Планета отрезана от снабжения.`);
      state.selected = toId;
      refreshAll();
    };
    modal.querySelector('[data-a="fight"]').onclick = () => { modal.remove(); startSpace(fromId, toId, false); };
    modal.querySelector('[data-a="auto"]').onclick = () => { modal.remove(); startSpace(fromId, toId, true); };
  }

  function startSpace(fromId, toId, auto) {
    const from = camp.systems[fromId], to = camp.systems[toId];
    const my = camp.playerFaction;
    const toDef = GALAXY_MAP.systems.find(s => s.id === toId);
    from.moved = true;

    const attacker = { faction: my, ships: from.fleet.map(x => ({ ...x })) };
    const defender = {
      faction: to.owner, ships: to.fleet.map(x => ({ ...x })),
      station: to.buildings.includes('station'),
    };

    const apply = res => {
      if (res.result === 'victory' || res.result === 'attacker') {
        from.fleet = [];
        to.fleet = res.attacker || [];
        logLine(`${toDef.name}: орбита очищена.`);
        // высадка
        if (from.regiments > 0) {
          offerInvasion(fromId, toId);
        } else {
          const m = document.createElement('div');
          m.className = 'modal';
          m.innerHTML = `<div class="modal-inner"><h3>Орбита за нами</h3>
            <p>Но высаживать некого: полков в этой системе нет. Планета
            остаётся за противником, пока не подвезёшь десант.</p>
            <div class="modal-actions"><button class="btn primary" data-a="ok">Понятно</button></div></div>`;
          hudRoot.appendChild(m);
          m.querySelector('[data-a="ok"]').onclick = () => { m.remove(); refreshAll(); };
        }
      } else if (res.result === 'retreat') {
        logLine(`${toDef.name}: флот отошёл, не приняв бой до конца.`);
        from.fleet = res.attacker && res.attacker.length ? res.attacker : from.fleet;
      } else {
        from.fleet = [];
        to.fleet = res.defender || to.fleet;
        logLine(`${toDef.name}: наш флот разбит.`);
      }
      state.selected = toId;
      refreshAll();
      checkVictory();
    };

    if (auto) {
      ctx.autoSpace(attacker, defender, apply);
    } else {
      ctx.startSpaceBattle({
        attacker, defender, playerSide: 'attacker', biome: toDef.biome,
        system: toDef.id,
        // Противоорбитальное орудие защитника вмешивается в бой снизу
        groundGun: to.buildings.includes('aogun') ? to.owner : null,
        title: `Бой на орбите · ${toDef.name}`,
        onEnd: apply,
      });
    }
  }

  function offerInvasion(fromId, toId) {
    const from = camp.systems[fromId], to = camp.systems[toId];
    const toDef = GALAXY_MAP.systems.find(s => s.id === toId);
    const m = document.createElement('div');
    m.className = 'modal';
    m.innerHTML = `<div class="modal-inner">
      <h3>Высадка на ${toDef.name}</h3>
      <p>Готово к высадке полков: ${from.regiments}. У противника на планете: ${to.regiments}
      ${to.buildings.includes('garrison') ? 'и укреплённый гарнизон' : ''}.</p>
      <p>В наземной операции обе стороны разворачивают базы: снабжение,
      казармы, завод. Победа — уничтожить всё, что у противника есть на планете.</p>
      <div class="modal-actions">
        <button class="btn primary" data-a="fight">Высаживаться</button>
        <button class="btn" data-a="auto">Быстрый расчёт</button>
        <button class="btn ghost" data-a="wait">Подождать</button>
      </div></div>`;
    hudRoot.appendChild(m);
    const close = () => m.remove();
    m.querySelector('[data-a="wait"]').onclick = () => { close(); refreshAll(); };

    const apply = res => {
      if (res.scorched && !to.scorched) {
        to.scorched = true;
        logLine(`${toDef.name}: экологическая катастрофа. Доход мира упал почти до нуля.`);
      }
      if (res.result === 'victory' || res.result === 'attacker') {
        to.owner = camp.playerFaction;
        to.regiments = Math.max(1, res.regiments || 1);
        from.regiments = 0;
        to.buildings = to.buildings.filter(b => b !== 'station');
        logLine(`${toDef.name}: планета взята.`);
      } else {
        from.regiments = 0;
        to.regiments = Math.max(1, res.regiments || 1);
        logLine(`${toDef.name}: десант уничтожен.`);
      }
      state.selected = toId;
      refreshAll();
      checkVictory();
    };

    m.querySelector('[data-a="auto"]').onclick = () => {
      close();
      ctx.autoGround(
        { faction: camp.playerFaction, regiments: from.regiments },
        { faction: to.owner, regiments: to.regiments, turrets: to.buildings.includes('garrison') },
        apply);
    };
    m.querySelector('[data-a="fight"]').onclick = () => {
      close();
      ctx.startGroundBattle({
        player: {
          faction: camp.playerFaction, regiments: from.regiments, credits: 3000,
          tech: techOf(camp, camp.playerFaction),
        },
        /* Что уцелело на орбите, то и поддерживает десант с неба.
           Флот после победы стоит уже в системе-цели. */
        orbit: supportFrom(camp.playerFaction, to.fleet),
        enemy: {
          faction: to.owner, regiments: to.regiments, credits: 3000,
          turrets: to.buildings.includes('garrison'),
          tech: techOf(camp, to.owner),
        },
        biome: toDef.biome,
        title: `Наземная операция · ${toDef.name}`,
        onEnd: apply,
      });
    };
  }

  // ── ХОД ИИ ───────────────────────────────────────────────
  function endTurn() {
    if (state.busy) return;
    const my = camp.playerFaction;
    // доход и наука всем
    for (const f of FACTION_IDS) {
      camp.credits[f] += incomeOf(camp, f);
      camp.research[f] = (camp.research[f] || 0) + researchOf(camp, f);
    }

    for (const f of FACTION_IDS) {
      if (f === my) continue;
      aiTurn(f);
    }
    for (const id in camp.systems) camp.systems[id].moved = false;
    camp.turn++;
    refreshAll();
    checkVictory();
    ctx.save && ctx.save();
  }

  function aiTurn(f) {
    const owned = GALAXY_MAP.systems.filter(s => camp.systems[s.id].owner === f);
    if (!owned.length) return;

    // 1. Строим. Научный центр ставим сразу после рудника: без него
    //    ИИ навсегда застрянет на корветах, пока игрок водит флагманы
    for (const def of owned) {
      const st = camp.systems[def.id];
      if (st.buildings.length >= def.slots) continue;
      const wish = ['shipyard', 'garrison', 'warpgate', 'mine', 'lab', 'aogun', 'station']
        .find(b => !st.buildings.includes(b));
      if (!wish) continue;
      const cost = PLANET_BUILDINGS[wish].cost;
      if (camp.credits[f] >= cost) { camp.credits[f] -= cost; st.buildings.push(wish); }
    }
    // 1б. Копится наука — сразу поднимаем уровень
    for (;;) {
      const cost = nextTechCost(camp, f);
      if (cost === null || (camp.research[f] || 0) < cost) break;
      camp.research[f] -= cost;
      camp.tech[f] = techOf(camp, f) + 1;
    }
    // 2. Клепаем корабли и полки на верфях
    for (const def of owned) {
      const st = camp.systems[def.id];
      if (st.buildings.includes('shipyard')) {
        const list = SHIPS[f].filter(d => techAllows(camp, f, d.tier));
        for (let i = 0; i < 3 && list.length; i++) {
          const d = list[Math.floor(rnd(0, list.length))];
          if (camp.credits[f] < d.cost) break;
          camp.credits[f] -= d.cost;
          const cur = st.fleet.find(x => x.id === d.id);
          if (cur) cur.count++; else st.fleet.push({ id: d.id, count: 1 });
        }
      }
      if (st.buildings.includes('garrison') && camp.credits[f] >= REGIMENT_COST && st.regiments < 8) {
        camp.credits[f] -= REGIMENT_COST;
        st.regiments++;
      }
    }
    // 3. Наступаем
    for (const def of owned) {
      const st = camp.systems[def.id];
      if (st.moved || fleetSize(st.fleet) < 3) continue;
      const targets = neighborsOf(def.id)
        .map(id => ({ id, st: camp.systems[id] }))
        .filter(t => t.st.owner !== f)
        .sort((a, b) => fleetValue(a.st.owner || f, a.st.fleet) - fleetValue(b.st.owner || f, b.st.fleet));
      if (!targets.length) continue;
      const t = targets[0];
      const mineVal = fleetValue(f, st.fleet);
      const theirVal = fleetValue(t.st.owner || f, t.st.fleet) + (t.st.buildings.includes('station') ? 6000 : 0);
      if (t.st.owner === null) {
        t.st.owner = f;
        t.st.fleet = mergeFleets(t.st.fleet, st.fleet);
        t.st.regiments += Math.min(1, st.regiments);
        st.regiments = Math.max(0, st.regiments - 1);
        st.fleet = [];
        st.moved = true;
        continue;
      }
      if (mineVal < theirVal * 1.25) continue;
      st.moved = true;

      // Игрока атакуют — даём сыграть оборону
      if (t.st.owner === camp.playerFaction) {
        queueDefence(f, def.id, t.id);
        return;
      }
      // ИИ против ИИ — считаем быстро
      ctx.autoSpace(
        { faction: f, ships: st.fleet.map(x => ({ ...x })) },
        { faction: t.st.owner, ships: t.st.fleet.map(x => ({ ...x })), station: t.st.buildings.includes('station') },
        res => {
          if (res.result === 'attacker') {
            t.st.fleet = res.attacker;
            st.fleet = [];
            if (st.regiments > t.st.regiments) {
              t.st.owner = f;
              t.st.regiments = Math.max(1, st.regiments - t.st.regiments);
              st.regiments = 0;
              t.st.buildings = t.st.buildings.filter(b => b !== 'station');
            }
          } else {
            st.fleet = [];
            t.st.fleet = res.defender;
          }
        });
    }
  }

  // Атака ИИ на мир игрока — показываем предложение обороняться
  function queueDefence(aiFaction, fromId, toId) {
    const from = camp.systems[fromId], to = camp.systems[toId];
    const toDef = GALAXY_MAP.systems.find(s => s.id === toId);
    state.busy = true;
    const m = document.createElement('div');
    m.className = 'modal';
    m.innerHTML = `<div class="modal-inner alarm">
      <h3>Тревога: ${toDef.name}</h3>
      <p>Клан ${FACTIONS[aiFaction].short} вошёл в систему. На орбите противника:
      ${fleetSize(from.fleet)} кораблей. Наших: ${fleetSize(to.fleet)}
      ${to.buildings.includes('station') ? '+ орбитальная станция' : ''}.</p>
      <div class="modal-actions">
        <button class="btn primary" data-a="fight">Принять бой</button>
        <button class="btn" data-a="auto">Доверить командирам</button>
      </div></div>`;
    hudRoot.appendChild(m);

    const apply = res => {
      const attackerWon = res.result === 'attacker' || res.result === 'defeat';
      if (attackerWon) {
        from.fleet = [];
        to.fleet = res.attacker || [];
        if (from.regiments > to.regiments) {
          to.owner = aiFaction;
          to.regiments = Math.max(1, from.regiments - to.regiments);
          from.regiments = 0;
          to.buildings = to.buildings.filter(b => b !== 'station');
          logLine(`${toDef.name}: система потеряна.`);
        } else {
          logLine(`${toDef.name}: орбита потеряна, планета удержана.`);
        }
      } else {
        from.fleet = [];
        to.fleet = res.defender || to.fleet;
        logLine(`${toDef.name}: атака отбита.`);
      }
      state.busy = false;
      refreshAll();
      checkVictory();
    };

    m.querySelector('[data-a="auto"]').onclick = () => {
      m.remove();
      ctx.autoSpace(
        { faction: aiFaction, ships: from.fleet.map(x => ({ ...x })) },
        { faction: to.owner, ships: to.fleet.map(x => ({ ...x })), station: to.buildings.includes('station') },
        apply);
    };
    m.querySelector('[data-a="fight"]').onclick = () => {
      m.remove();
      ctx.startSpaceBattle({
        attacker: { faction: aiFaction, ships: from.fleet.map(x => ({ ...x })) },
        defender: {
          faction: to.owner, ships: to.fleet.map(x => ({ ...x })),
          station: to.buildings.includes('station'),
        },
        playerSide: 'defender',
        biome: toDef.biome,
        system: toDef.id,
        groundGun: to.buildings.includes('aogun') ? to.owner : null,
        title: `Оборона · ${toDef.name}`,
        onEnd: r => apply({
          result: r.result === 'victory' ? 'defender' : 'attacker',
          attacker: r.attacker, defender: r.defender,
        }),
      });
    };
  }

  function checkVictory() {
    const my = camp.playerFaction;
    const mineN = ownedCount(camp, my);
    const total = GALAXY_MAP.systems.length;
    if (mineN === 0) return showEnd(false);
    if (mineN === total) return showEnd(true);
  }

  function showEnd(win) {
    const card = $('end');
    card.style.display = 'flex';
    card.innerHTML = `<div class="end-inner">
      <h2>${win ? 'Капелла наша' : 'Клан рассеян'}</h2>
      <p>${win
        ? 'Вся система под контролем клана. Изгнание закончилось — Клото снова дома.'
        : 'Последний мир потерян. Тем, кто уцелел, остались только гиперворота.'}</p>
      <button class="btn primary" data-role="again">В главное меню</button></div>`;
    card.querySelector('[data-role="again"]').onclick = () => ctx.goMenu();
  }

  // ── управление ───────────────────────────────────────────
  const controls = new Controls(viewport.canvas, tcam, {
    pickMeshes: () => Object.values(nodes).map(n => n.obj),
    planeY: () => 0,
    onTap({ x, y }) {
      if (state.busy) return;
      let ent = controls.pick(x, y);
      if (!ent) {
        ent = controls.pickNear(x, y, Object.values(nodes), tcam.cam, viewport.w, viewport.h, IS_TOUCH ? 52 : 30);
      }
      if (!ent) return;
      const id = ent.def.id;
      const sel = state.selected;
      if (sel && sel !== id) {
        const st = camp.systems[sel];
        if (st.owner === camp.playerFaction && !st.moved && fleetSize(st.fleet) && neighborsOf(sel).includes(id)) {
          tryMoveFleet(sel, id);
          return;
        }
      }
      state.selected = id;
      fx.flash(ent.pos, ent.radius * 2.4, 0x8fffc8, 0.4);
      refreshAll();
    },
    onOrder({ x, y }) {
      const ent = controls.pick(x, y);
      if (ent && state.selected) tryMoveFleet(state.selected, ent.def.id);
    },
  });

  refreshAll();

  function update(dt) {
    tcam.update(dt);
    fx.update(dt);
    const t = performance.now() * 0.001;
    for (const id in nodes) {
      const n = nodes[id];
      n.obj.rotation.y += dt * 0.05;
      if (n.hl.visible) n.hl.material.opacity = 0.55 + Math.sin(t * 3) * 0.35;
    }
    updateMarkers();
  }

  function dispose() {
    tcam.dispose();
    controls.dispose();
    hud.remove();
    disposeScene(scene);
  }

  return { scene, camera: tcam.cam, update, dispose, state, refreshAll };
}
