/* КАПЕЛЛА: ГАЛАКТИЧЕСКИЙ ФРОНТ — точка входа.
   Здесь: главное меню, выбор клана, переключение экранов
   (карта → бой на орбите → наземная операция), сохранение
   и справочник нейроинтерфейса. */

import { THREE, Viewport, TacticalCamera, starfield, IS_TOUCH, rnd, disposeScene, prefs, setPref } from './engine.js';
import { createGalaxy, newCampaign, ownedCount } from './galaxy.js';
import { createSpaceBattle, autoResolveSpace } from './space.js';
import { createGroundBattle, autoResolveGround } from './ground.js';
import { buildPlanet, buildNebula } from './models.js';
import { loadModelLibrary, modelCount, loadPlanetTextures, planetCount } from './assets.js';
import { createHangar } from './hangar.js';
import {
  FACTIONS, FACTION_IDS, NEURO_BRIEF, SHIPS, STRIKE, STRIKE_ROLES,
  GROUND_UNITS, GROUND_BUILDINGS, GALAXY_MAP, DIFFICULTY, DIFF_IDS, diffOf,
} from './data.js';

const SAVE_KEY = 'capella_save_v1';
const FPS_KEY = 'capella_fps';
// Инструменты разработчика (Ангар) — только по адресу с ?dev=1 (C134)
const DEV = /[?&]dev=1(&|$)/.test(location.search);
const canvas = document.getElementById('view');
const hudRoot = document.getElementById('hud');
const stage = document.getElementById('stage');

/* Без WebGL игре рисовать нечем. Раньше рендерер создавался молча,
   падал на первой строке, и человек видел чёрный экран без единого
   слова. Проверка «есть ли WebGL» стоит ещё в index.html, до модулей;
   здесь — вторая линия, если видеокарта отказала уже при создании. */
let viewport = null;
if (!window.__noWebGL) {
  try { viewport = new Viewport(canvas); } catch (e) {
    console.error('WebGL не создался:', e);
    if (window.__bootFail) window.__bootFail('webgl', e && e.message);
  }
}

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
    if (!c || !c.systems || !c.playerFaction) return null;
    // Сохранения до появления науки: дописываем поля, чтобы старая
    // кампания открылась, а не упала на первом же обращении к tech
    if (!c.research || !c.tech) {
      c.research = c.research || {};
      c.tech = c.tech || {};
      for (const f of FACTION_IDS) {
        if (c.research[f] === undefined) c.research[f] = 0;
        if (c.tech[f] === undefined) c.tech[f] = 1;
      }
      c.version = 2;
    }
    return c;
  } catch (e) { return null; }
}
function dropSave() {
  try { localStorage.removeItem(SAVE_KEY); } catch (e) { /* ничего */ }
}

// ─────────────────────────────────────────────────────────────
// ПЕРЕКЛЮЧЕНИЕ ЭКРАНОВ
// ─────────────────────────────────────────────────────────────

function setMode(factory) {
  if (mode) {
    try { mode.dispose(); } catch (e) { console.warn('Экран не убрался до конца:', e); }
    mode = null;
  }
  hudRoot.innerHTML = '';
  /* Исключение при сборке экрана раньше оставляло пустую сцену и
     вечную тишину: прежний экран уже убран, новый не собрался.
     Теперь — то же окно сбоя, что и в кадре, с выходом в меню. */
  try { mode = factory(); } catch (e) { mode = null; showCrash(e); }
}

/* ── ПОДГОТОВКА ЭКРАНА (C40, C93).
   Бой собирается на главном потоке секунды: текстуры планеты и
   туманности, сотни мешей, компиляция шейдеров. Раньше всё это время
   экран просто стоял, и игрок жал кнопку ещё раз или решал, что игра
   зависла. Теперь сначала показываем «Подготовка боя…», даём кадру
   ОТРИСОВАТЬСЯ (два requestAnimationFrame), и только потом начинаем
   тяжёлую работу. Полоска анимируется через transform — такие
   анимации браузер крутит сам и при занятом главном потоке.

   Ждём только ТО, что нужно этому экрану (need): бою на орбите —
   модели и картинки планет, высадке и Ангару — модели, карте — одни
   планеты. Раньше карта ждала модели кораблей, которых на ней нет:
   на медленной связи — 25 секунд заставки ни за что. */
const PREP_WAIT_MAX = 40000;
const nextPaint = () => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
/* Один флаг на заставку и на нырок: пока один экран собирается, второй
   не начинается. Без общего флага нажатие сквозь ожидание высадки
   запускало бой на орбите, и игра собирала две сцены подряд. */
let prepBusy = false;
// Что ждёт каждый экран: карте корабли не нужны, только планеты
const NEED_SPACE = { models: true, planets: true };
const NEED_MAP = { planets: true };

// Что из нужного экрану ещё в пути: 'models' | 'planets' | null
function waitingFor(need) {
  if (need.models && !modelsReady) return 'models';
  if (need.planets && !planetsReady) return 'planets';
  return null;
}

/* Ждать нужное, показывая в label, что именно едет. Без нужды — сразу.
   Долгое ожидание без объяснения читается как зависание, поэтому
   после 8 секунд дописываем, что будет, если не доедет. */
function waitAssets(need, label) {
  const list = [];
  if (need.models && !modelsReady) list.push(modelsPromise);
  if (need.planets && !planetsReady) list.push(planetsPromise);
  if (!list.length) return Promise.resolve();
  const t0 = performance.now();
  const show = () => {
    const what = waitingFor(need);
    if (!what) return;
    const waited = (performance.now() - t0) / 1000;
    label.textContent = (what === 'models'
      ? (assetProgress.total ? `Загружаю модели · ${assetProgress.done} из ${assetProgress.total}` : 'Загружаю модели…')
      : 'Загружаю картинки планет…') +
      (waited > 8 ? ` · связь медленная, ${Math.round(waited)} с. Не доедут — начнём ${
        what === 'models' ? 'на простых моделях' : 'с нарисованными игрой планетами'}` : '');
  };
  show();
  const tick = setInterval(show, 250);
  return Promise.race([Promise.all(list), new Promise(r => setTimeout(r, PREP_WAIT_MAX))])
    .then(() => { clearInterval(tick); label.textContent = ''; });
}

function prepThen(title, work, need = {}) {
  if (prepBusy) return;            // второй клик по «В бой» — не второй бой
  prepBusy = true;
  const el = document.createElement('div');
  el.className = 'prep';
  el.innerHTML = `<div class="prep-inner"><div class="prep-title"></div>
    <div class="prep-sub" data-role="sub"></div><div class="prep-bar"><i></i></div></div>`;
  el.querySelector('.prep-title').textContent = title;
  stage.appendChild(el);
  waitAssets(need, el.querySelector('[data-role="sub"]')).then(async () => {
    await nextPaint();
    try { work(); } finally {
      prepBusy = false;
      /* Убираем заставку только после ПЕРВОГО кадра нового экрана:
         в нём компилируются шейдеры, и это ещё секунда-другая, в которую
         иначе был бы виден застывший кадр прежнего экрана. */
      nextPaint().then(() => {
        el.classList.add('out');
        setTimeout(() => el.remove(), 400);
      });
    }
  });
}

/* Последний бой на орбите — его фабрика. По ней «Начать бой заново»
   из меню паузы собирает тот же бой с нуля: конфиг боя не меняется
   по ходу (резерв и дальний гипер копируются при сборке). */
let lastSpace = null;
function runSpace(factory) {
  lastSpace = factory;
  prepThen('Подготовка боя…', () => setMode(factory), NEED_SPACE);
}

const ctx = {
  viewport, hudRoot,
  save,
  goMenu: () => showMenu(),
  showNeuro: tab => showNeuro(tab),
  pause: opts => showPause(opts),
  confirm: (opts, onYes) => confirmBox(opts, onYes),
  restartBattle: () => { if (lastSpace) runSpace(lastSpace); },
  startSpaceBattle(cfg) {
    runSpace(() => createSpaceBattle(ctx, {
      ...cfg,
      inCampaign: true,
      onEnd: res => { cfg.onEnd && cfg.onEnd(res); backToGalaxy(); },
    }));
  },
  startGroundBattle(cfg) {
    /* Высадка идёт «нырком» сквозь облака, а не сменой экрана.
       Смысл приёма в том, что густой туман закрывает не переход,
       а ЗАГРУЗКУ: пока экран заволочён, собирается наземная сцена —
       рельеф, вода, тысячи травинок. Игрок видит спуск, а не
       ожидание. Модели нырок дожидается сам, под облаками. */
    dive(() => setMode(() => createGroundBattle(ctx, {
      ...cfg,
      inCampaign: true,
      onEnd: res => { cfg.onEnd && cfg.onEnd(res); backToGalaxy(); },
    })));
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

/* ── НЫРОК СКВОЗЬ ОБЛАКА.
   Три слоя облаков едут вниз с разной скоростью — так получается
   ощущение падения, а не просто затемнения. Сцену меняем в самой
   плотной точке, когда экран закрыт целиком: смена мгновенная, но
   увидеть её нельзя.

   Слои разной скорости важнее их вида: параллакс и есть то, что
   читается как движение вниз.

   С первого кадра нырок ЛОВИТ указатель, а в плотной точке облака
   замирают (hold), пока под ними собирается сцена: анимация transform
   идёт и при занятом главном потоке, и раньше облака успевали уехать
   вниз, открыв застывший прежний экран. Если модели ещё в пути, экран
   под облаками темнеет (wait), а посередине — плашка «Загружаю
   модели · N из M». Раньше в это время облака уходили, подпись
   тёмным по тёмному меню не читалась, а меню под ней нажималось —
   и можно было запустить второй бой поверх ожидания первого. */
function dive(swap) {
  if (prepBusy) return;
  prepBusy = true;
  const el = document.createElement('div');
  el.className = 'dive';
  el.innerHTML = `<i class="c1"></i><i class="c2"></i><i class="c3"></i>
    <div class="dive-label"><b data-role="title">Высадка…</b><span data-role="sub"></span><div class="prep-bar"><i></i></div></div>`;
  hudRoot.appendChild(el);
  requestAnimationFrame(() => el.classList.add('in'));

  setTimeout(async () => {
    el.classList.add('hold');
    /* Модели ещё едут — ждём под облаками, а не собираем бой на
       процедурных, чтобы через минуту увидеть другие корабли. */
    if (waitingFor({ models: true })) {
      el.classList.add('wait');
      await waitAssets({ models: true }, el.querySelector('[data-role="sub"]'));
    }
    await nextPaint();
    try { swap(); } finally {
      prepBusy = false;
      // setMode вычищает HUD целиком, поэтому слой возвращаем поверх
      hudRoot.appendChild(el);
      el.classList.remove('hold');
      el.classList.add('out');
      setTimeout(() => el.remove(), 900);
    }
  }, 760);
}

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

/* Пробел и Enter по кнопке ПОД окном (её мог оставить в фокусе Tab)
   нажали бы её: снять паузу под меню, сдаться под вопросом. Кнопки
   самого окна с клавиатуры нажимаются как обычно. Когда в фокусе
   ничего (body), действие по умолчанию не трогаем: им Пробел и PgDn
   листают справку. */
function blockOutside(e, box) {
  if (e.code !== 'Space' && e.code !== 'Enter' && e.code !== 'NumpadEnter') return;
  const a = document.activeElement;
  if (a && a !== document.body && !box.contains(a)) e.preventDefault();
}

/* ── ПОДТВЕРЖДЕНИЕ (C34). Для действий, которые одним промахом
   проигрывают бой: «Отход», «Сдаться», выход посреди боя. Escape —
   «нет»; пока окно открыто, клавиши игры молчат (Пробел не снимает
   паузу под ним). Бой на это время ставит на паузу САМ экран и
   снимает её в onClose: окно гасит все клавиши, Пробел в том числе,
   и без паузы флот гиб бы, пока игрок читает вопрос.
   opts: {title, text, yes, no, danger, onClose} */
function confirmBox(opts, onYes) {
  const m = document.createElement('div');
  m.className = 'modal confirm';
  m.innerHTML = `<div class="modal-inner"><h3></h3><p></p>
    <div class="modal-actions">
      <button class="btn ${opts.danger === false ? 'primary' : 'danger'}" data-a="yes"></button>
      <button class="btn ghost" data-a="no"></button>
    </div></div>`;
  m.querySelector('h3').textContent = opts.title || 'Точно?';
  m.querySelector('p').textContent = opts.text || '';
  m.querySelector('[data-a="yes"]').textContent = opts.yes || 'Да';
  m.querySelector('[data-a="no"]').textContent = opts.no || 'Отмена';
  let done = false;
  const close = () => {
    if (done) return;
    done = true;
    m.remove();
    removeEventListener('keydown', onKey, true);
    if (opts.onClose) opts.onClose();
  };
  const onKey = e => {
    if (!m.isConnected) { removeEventListener('keydown', onKey, true); return; }
    if (e.code === 'F3' || e.code === 'F11') return;
    e.stopImmediatePropagation();
    if (e.code === 'Escape') { e.preventDefault(); if (!e.repeat) close(); }
    else blockOutside(e, m);
  };
  addEventListener('keydown', onKey, true);
  m.querySelector('[data-a="no"]').onclick = close;
  m.querySelector('[data-a="yes"]').onclick = () => { close(); onYes(); };
  m.addEventListener('click', e => { if (e.target === m) close(); });
  hudRoot.appendChild(m);
  return m;
}

/* ── МЕНЮ ПАУЗЫ (C35). Раньше выйти из боя или кампании можно было
   только перезагрузкой страницы, а Escape по привычке ничего не
   открывал. Теперь Escape — когда отменять нечего — или кнопка «☰»
   открывают меню: продолжить, управление, настройки, начать бой
   заново, в главное меню. Сам экран ставит бой на паузу и снимает
   её в onClose. Пока меню открыто, клавиши игры до экрана не доходят
   (иначе Пробел снял бы паузу под меню, а стрелки двигали камеру).
   В бою КАМПАНИИ вместо «В главное меню» — `leave` (отход, сдаться):
   кампания к этому моменту уже сохранена со СЛЕДУЮЩИМ ходом, и выход
   посреди боя был бы переигровкой, а атака ИИ на игрока просто
   пропадала бы. Бой кампании кончается так, как сыгран.
   opts: {restart, exitText, onExit, onClose, leave: {label, note, fn}} */
function showPause(opts = {}) {
  if (hudRoot.querySelector('.screen.pause')) return;
  const el = document.createElement('div');
  el.className = 'screen pause';
  el.innerHTML = `<div class="pause-inner">
      <h2>Пауза</h2>
      <div class="pause-actions">
        <button class="btn primary big" data-a="resume">Продолжить</button>
        <button class="btn big" data-a="help">Управление</button>
        <button class="btn big" data-a="settings">Настройки</button>
        ${opts.restart ? '<button class="btn big" data-a="restart">Начать бой заново</button>' : ''}
        ${opts.leave ? '<button class="btn ghost big" data-a="leave"></button>'
                     : '<button class="btn ghost big" data-a="menu">В главное меню</button>'}
      </div>
      ${opts.leave ? '<p class="pause-note" data-role="leave-note"></p>' : ''}
      <div class="pause-settings" data-role="settings" hidden>
        <label class="opt"><input type="checkbox" data-a="edge"${prefs.edge ? ' checked' : ''}>
          Прокрутка карты, когда курсор у края экрана</label>
        <button class="btn" data-a="full">Полный экран · F11</button>
        <label class="opt off" title="Звука в игре пока нет">
          <input type="range" min="0" max="100" value="70" disabled> Громкость — звука пока нет</label>
      </div>
    </div>`;
  let done = false;
  const close = () => {
    if (done) return;
    done = true;
    el.remove();
    removeEventListener('keydown', onKey, true);
    if (opts.onClose) opts.onClose();
  };
  const onKey = e => {
    if (!el.isConnected) { removeEventListener('keydown', onKey, true); return; }
    if (e.code === 'F3' || e.code === 'F11') return;
    /* Повтор удержанного Esc не закрывает ни меню, ни окно над ним
       и дальше не идёт: иначе повторы по очереди закрывали меню здесь
       и открывали его снова в бою — оно мигало, бой снимался с паузы.
       Держат Esc нарочно: так выходят из полного экрана (LOCK_KEYS). */
    if (e.code === 'Escape' && e.repeat) { e.stopImmediatePropagation(); e.preventDefault(); return; }
    /* Поверх меню открыта справка или подтверждение — Escape их.
       Остальные клавиши игре не отдаём и тогда: справка свои глушит
       сама, но правило «пока меню открыто, бой их не слышит» обязано
       держаться здесь — раньше отсюда был `return`, и Пробел, которым
       листают справку, снимал паузу под меню, а PgDn уводил корабли. */
    const top = document.querySelector('.modal.confirm') || document.querySelector('.screen.neuro');
    if (top) {
      if (e.code !== 'Escape') { e.stopImmediatePropagation(); blockOutside(e, top); }
      return;
    }
    e.stopImmediatePropagation();
    if (e.code === 'Escape') { e.preventDefault(); close(); }
    else blockOutside(e, el);
  };
  addEventListener('keydown', onKey, true);
  el.addEventListener('click', e => { if (e.target === el) close(); });
  el.querySelector('[data-a="resume"]').onclick = close;
  el.querySelector('[data-a="help"]').onclick = () => showNeuro(NEURO_CONTROLS);
  el.querySelector('[data-a="settings"]').onclick = e => {
    const s = el.querySelector('[data-role="settings"]');
    s.hidden = !s.hidden;
    e.currentTarget.classList.toggle('on', !s.hidden);
  };
  el.querySelector('[data-a="edge"]').onchange = e => setPref('edge', e.target.checked);
  el.querySelector('[data-a="full"]').onclick = () => toggleFullscreen();
  const restart = el.querySelector('[data-a="restart"]');
  if (restart) restart.onclick = () => { done = true; removeEventListener('keydown', onKey, true); el.remove(); opts.restart(); };
  if (opts.leave) {
    const lb = el.querySelector('[data-a="leave"]');
    lb.textContent = opts.leave.label;
    el.querySelector('[data-role="leave-note"]').textContent = opts.leave.note || '';
    lb.onclick = () => { close(); opts.leave.fn(); };
  } else el.querySelector('[data-a="menu"]').onclick = () => {
    const go = () => {
      done = true;
      removeEventListener('keydown', onKey, true);
      if (opts.onExit) opts.onExit();
      showMenu();
    };
    if (opts.exitText) confirmBox({ title: 'Выйти в главное меню?', text: opts.exitText, yes: 'Выйти', no: 'Остаться' }, go);
    else go();
  };
  hudRoot.appendChild(el);
}

/* ── ПОЛНЫЙ ЭКРАН (F11). В обычной вкладке браузер забирает себе
   Ctrl+1…8 (переключение вкладок), и отряды Ctrl+цифрой не записать —
   поэтому они пишутся и Shift+цифрой. В полноэкранном режиме
   Keyboard Lock (Chrome, Edge) отдаёт цифры игре, и Ctrl работает
   тоже. Escape запираем ТОЖЕ: в полном экране через Fullscreen API
   браузер забирает Esc себе, и каждый Esc — а это главная клавиша
   отмены в бою (атака с ходу, рамка, выбор) — выбрасывал из полного
   экрана, снимая заодно и замок с Ctrl+цифр. Запертый Esc короткий
   отдаётся игре, а из полного экрана выводит его УДЕРЖАНИЕ (браузер
   сам об этом пишет), F11 и «☰ → Настройки → Полный экран». */
const LOCK_KEYS = ['Escape', 'Digit1', 'Digit2', 'Digit3', 'Digit4', 'Digit5', 'Digit6', 'Digit7', 'Digit8', 'Digit9'];
async function toggleFullscreen() {
  try {
    if (document.fullscreenElement) {
      if (navigator.keyboard && navigator.keyboard.unlock) navigator.keyboard.unlock();
      await document.exitFullscreen();
      return;
    }
    await document.documentElement.requestFullscreen({ navigationUI: 'hide' });
    if (navigator.keyboard && navigator.keyboard.lock) await navigator.keyboard.lock(LOCK_KEYS).catch(() => {});
  } catch (e) { console.warn('Полный экран не открылся:', e); }
}
addEventListener('keydown', e => {
  if (e.code !== 'F11') return;
  e.preventDefault();          // свой полный экран, а не браузерный: только у него есть Keyboard Lock
  toggleFullscreen();
});

/* ── КНОПКИ НЕ ДЕРЖАТ ФОКУС (C28). После щелчка кнопка оставалась
   в фокусе, и браузер нажимал её снова по Пробелу и Enter: «Конец
   хода» и Пробел-пауза за компьютером пропускали по два хода. Мышью
   кнопки фокус больше не берут вовсе; с клавиатуры (Tab) — как
   обычно. */
document.addEventListener('mousedown', e => {
  if (e.target.closest && e.target.closest('button')) e.preventDefault();
}, true);
/* Меню браузера по ПКМ в игре не нужно нигде (C73): на панелях оно
   всплывало поверх боя. Текст ошибки в окне сбоя копировать можно. */
document.addEventListener('contextmenu', e => {
  if (!(e.target.closest && e.target.closest('input, textarea, pre'))) e.preventDefault();
});

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
          ${DEV ? '<button class="btn big" data-a="hangar">Ангар · модели</button>' : ''}
          <button class="btn ghost big" data-a="neuro">Нейроинтерфейс</button>
        </div>
        <div class="menu-opts">
          <label class="opt" title="Показывает кадры в секунду, вызовы отрисовки и треугольники. Пригодится, чтобы прислать цифры со своего компьютера.">
            <input type="checkbox" data-a="fps"${fpsMeter.on ? ' checked' : ''}> Счётчик кадров (F3)</label>
          <label class="opt" title="Курсор у края экрана двигает карту. Мешает, если окно не во весь экран или рядом второй монитор.">
            <input type="checkbox" data-a="edge"${prefs.edge ? ' checked' : ''}> Прокрутка у края экрана</label>
          <button class="btn ghost" data-a="full" title="Полный экран: в нём игре достаются и Ctrl+цифры">Полный экран · F11</button>
        </div>
        ${has ? `<div class="menu-note">Сохранение: ход ${has.turn}, клан
          ${FACTIONS[has.playerFaction].short}, миров под контролем —
          ${ownedCount(has, has.playerFaction)} · сложность «${diffOf(has.difficulty).name}».</div>` : ''}
      </div>`;
    hudRoot.appendChild(el);

    el.querySelector('[data-a="new"]').onclick = () => showFactionPick();
    el.querySelector('[data-a="skirmish"]').onclick = () => showSkirmish();
    el.querySelector('[data-a="neuro"]').onclick = () => showNeuro();
    el.querySelector('[data-a="fps"]').onchange = e => setFps(e.target.checked);
    el.querySelector('[data-a="edge"]').onchange = e => setPref('edge', e.target.checked);
    el.querySelector('[data-a="full"]').onclick = () => toggleFullscreen();
    const hangar = el.querySelector('[data-a="hangar"]');
    if (hangar) hangar.onclick = () => prepThen('Открываю ангар…', () => setMode(() => createHangar(ctx)), { models: true });
    const cont = el.querySelector('[data-a="continue"]');
    if (cont) cont.onclick = () => prepThen('Открываю карту системы…', () => { campaign = loadSave(); backToGalaxy(); }, NEED_MAP);

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
      <div class="form-row wide"><label>Сложность</label>
        <select data-f="diff">${DIFF_IDS.map(id =>
          `<option value="${id}"${id === 'normal' ? ' selected' : ''}>${DIFFICULTY[id].name}</option>`).join('')}</select></div>
      <div class="diff-note" data-role="diffnote"></div>
      <div class="picker-actions"><button class="btn ghost" data-a="back">Назад</button></div>
    </div>`;
  hudRoot.appendChild(el);
  el.querySelector('[data-a="back"]').onclick = () => el.remove();
  /* Сложность выбирается ОДИН раз, на старте кампании: подкрутить
     её перед тяжёлым боем нельзя, иначе она перестаёт что-либо
     значить. Поэтому рядом с выбором сразу написано, что она меняет. */
  const diffSel = el.querySelector('[data-f="diff"]');
  const diffNote = el.querySelector('[data-role="diffnote"]');
  const showDiff = () => { diffNote.textContent = DIFFICULTY[diffSel.value].desc; };
  diffSel.onchange = showDiff;
  showDiff();
  el.querySelectorAll('.fcard').forEach(b => {
    b.onclick = () => {
      campaign = newCampaign(b.dataset.f, diffSel.value);
      dropSave();
      save();
      el.remove();
      prepThen('Открываю карту системы…', backToGalaxy, NEED_MAP);
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
      <div class="form-row"><label>Сложность</label>
        <select data-f="diff">${DIFF_IDS.map(id =>
          `<option value="${id}"${id === 'normal' ? ' selected' : ''}>${DIFFICULTY[id].name}</option>`).join('')}</select></div>
      <div class="diff-note" data-role="diffnote"></div>
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
  {
    const d = el.querySelector('[data-f="diff"]'), note = el.querySelector('[data-role="diffnote"]');
    const upd = () => { note.textContent = DIFFICULTY[d.value].desc; };
    d.onchange = upd;
    upd();
  }

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
    runSpace(() => createSpaceBattle(ctx, {
      attacker: { faction: mine, ships: scaleFor(mine, fleetOf(size)), reserve: scaleFor(mine, fleetOf('small')) },
      defender: { faction: foe, ships: scaleFor(foe, fleetOf(size)), station: size === 'big' },
      playerSide: 'attacker', biome: 'klotho', title: 'Быстрый бой · орбита',
      difficulty: sel('diff'),
      // В быстром бою планета всегда огрызается: иначе «Давление Земли»
      // можно увидеть только в кампании, построив орудие
      groundGun: foe,
      onEnd: () => showMenu(),
    }));
  };
  el.querySelector('[data-a="ground"]').onclick = () => {
    const mine = sel('mine'), foe = sel('foe'), size = sel('size');
    el.remove();
    campaign = null;
    dive(() => setMode(() => createGroundBattle(ctx, {
      player: { faction: mine, regiments: sizes[size].regiments, credits: 4000 },
      // В быстром бою даём всю орбитальную поддержку: иначе её видно
      // только в кампании, и то если выиграть орбиту нужными кораблями
      orbit: ['strike', 'drop', 'emp'],
      enemy: { faction: foe, regiments: sizes[size].regiments, credits: 4000, turrets: size !== 'small' },
      difficulty: sel('diff'),
      // Биом быстрого боя можно подменить из консоли — удобно смотреть,
      // как выглядят снег и пустыня, не собирая ради этого кампанию.
      // Тем же способом подменяется мир целиком, вместе с особенностями:
      // window.__forceWorld = { traits: ['dust'] }
      biome: (typeof window !== 'undefined' && window.__forceBiome) || 'green',
      world: (typeof window !== 'undefined' && window.__forceWorld) || null,
      title: 'Быстрый бой · планета',
      onEnd: () => showMenu(),
    })));
  };
}

// ─────────────────────────────────────────────────────────────
// НЕЙРОИНТЕРФЕЙС — справочник
// ─────────────────────────────────────────────────────────────

const NEURO_CONTROLS = 4;    // вкладка «Управление»
function showNeuro(start = 0) {
  if (document.querySelector('.screen.neuro')) return;
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
        `<button data-tab="${i}"${i === start ? ' class="on"' : ''}>${t}</button>`).join('')}</div>
      <div class="neuro-body" data-role="body"></div>
    </div>`;
  hudRoot.appendChild(el);
  /* Закрыть — тремя путями (C2): кнопкой, щелчком по фону вокруг
     панели и клавишей Escape. Раньше кнопка не принимала нажатий
     (контейнер был прозрачен для указателя), Escape не слушался,
     и открытая справка запирала игру до перезагрузки. Escape ловим
     в перехвате и гасим: иначе тот же Escape заодно снял бы выделение
     на экране под справкой. */
  const close = () => {
    el.remove();
    removeEventListener('keydown', onKey, true);
  };
  const onKey = e => {
    // экран сменился, а справку унесло вместе с HUD — слушатель больше не нужен
    if (!el.isConnected) { removeEventListener('keydown', onKey, true); return; }
    if (e.code === 'F3' || e.code === 'F11') return;
    /* Пока справка открыта, игра клавиш не слышит: её листают Пробелом
       и PgDn, а Пробел под ней снимал паузу (бой шёл без игрока), PgDn
       уводил выделенные корабли «Ниже», G — в гипер. Действие по
       умолчанию не гасим — им справка и листается. */
    e.stopImmediatePropagation();
    // повтор удержанного Esc справку не закрывает — иначе следующий закрыл бы меню под ней
    if (e.code === 'Escape') { e.preventDefault(); if (!e.repeat) close(); }
    else blockOutside(e, el);
  };
  addEventListener('keydown', onKey, true);
  el.querySelector('[data-a="close"]').onclick = close;
  el.addEventListener('click', e => { if (e.target === el) close(); });

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
      /* Управление — СНАЧАЛА КОМПЬЮТЕР (C130): основное устройство —
         мышь и клавиатура, и раньше вкладка начиналась с «Планшета»
         и уверяла, что цифровых клавиш нет. Таблицей: клавишу ищут
         глазами, а не читают абзац. */
      const rows = list => `<table class="keys">${list.map(([k, v]) =>
        `<tr><td>${k}</td><td>${v}</td></tr>`).join('')}</table>`;
      body.innerHTML = `
        <section><h3>Камера</h3>${rows([
          ['Стрелки', 'двигать карту'],
          ['Курсор у края экрана', 'двигать карту (выключается: Esc → Настройки)'],
          ['Средняя кнопка, тянуть', 'двигать карту'],
          ['Колесо', 'приближение — к точке под курсором'],
          ['Правая кнопка, тянуть', 'повернуть камеру'],
          ['Q / E', 'повернуть камеру'],
          ['R / F', 'камера выше / ниже (бой на орбите)'],
          ['W A S D', 'двигать карту на карте системы и на земле; в бою на орбите эти буквы — приказы'],
          ['Миникарта', 'щёлкнуть или тянуть — камера туда; правой кнопкой — приказ туда'],
        ])}</section>
        <section><h3>Выбор</h3>${rows([
          ['Левая кнопка', 'выбрать; с протяжкой — рамка'],
          ['Shift + левая', 'добавить к выбору или убрать из него'],
          ['Двойной щелчок', 'все корабли этого типа на экране'],
          ['F2', 'весь флот (бой на орбите)'],
          ['Ctrl или Shift + 1…9', 'записать отряд из выбранного'],
          ['1…9', 'выбрать отряд; нажать дважды — камера к отряду'],
          ['Esc', 'отменить, снять выбор; если нечего — меню паузы'],
        ])}
        <p>В обычном окне браузер забирает Ctrl+1…8 себе (вкладки), поэтому
        отряд пишется и Shift+цифрой. В полноэкранном режиме (F11) работают оба.</p></section>
        <section><h3>Приказы в бою на орбите</h3>${rows([
          ['Правая кнопка', 'по полю — идти; по врагу (по кораблю или его подписи) — атаковать'],
          ['A, затем щелчок', 'атака с ходу: идут к точке и бьют всех встречных; по врагу — атаковать'],
          ['S', 'стоп: снять все приказы'],
          ['H', 'держать позицию: стоять и бить только тех, до кого достаёт оружие'],
          ['Z / X / C', 'поднять перехватчиков / истребителей / бомбардировщиков'],
          ['V', 'звено на посадку'],
          ['G', 'уйти в гипер или отменить; с авианосцем спросит — за ним отходит весь флот'],
          ['D', 'дрифт'],
          ['B', 'подкрепление'],
          ['J / K / L', 'купол РЭБ: глушение / прикрытие / молчать'],
          ['PgUp / PgDn', 'корабли выше / ниже'],
          ['Пробел', 'пауза'],
        ])}
        <p>Буква действия написана в углу его кнопки, а что она делает —
        в подсказке, если навести на кнопку мышь. Ростер флота над панелью
        собран по классам: щелчок — все корабли класса, ещё щелчок — по одному,
        Shift — добавить к выбранным. Свои всегда зелёные, противник — красный,
        какой бы клан ни был. Курсор подсказывает,
        что сделает щелчок: рука — выбрать, красный прицел — атаковать,
        зелёная метка — идти.</p></section>
        <section><h3>Карта системы</h3>${rows([
          ['Левая кнопка', 'выбрать мир'],
          ['Правая кнопка', 'по соседнему миру — отправить туда флот'],
          ['Esc или щелчок в пустоту', 'снять выбор — снова видны технологии'],
        ])}</section>
        <section><h3>Наземная операция</h3>${rows([
          ['Правая кнопка', 'идти, атаковать; при постройке — отменить'],
          ['Ctrl или Shift + 1…3', 'записать отряд (или придержать кнопку отряда)'],
          ['1…3', 'выбрать отряд и показать его'],
          ['Пробел / Esc', 'пауза / отменить; если нечего — меню паузы'],
        ])}</section>
        <section><h3>Общее</h3>${rows([
          ['Esc', 'меню паузы: управление, настройки, начать заново, выход'],
          ['F11', 'полный экран; выйти — F11 или удержать Esc'],
          ['F3', 'счётчик кадров'],
        ])}</section>
        <section><h3>Планшет</h3><p>
        Касание по своему кораблю или юниту — выбрать. Когда что-то выбрано:
        касание по врагу — атаковать, касание по пустому месту — идти туда.
        Тянуть одним пальцем — двигать карту. Щипок — приближение, поворот
        двух пальцев — облёт. Долгое нажатие и потянуть — рамка выделения
        (или кнопка «Рамка» справа).</p></section>
        <section><h3>Кнопки справа</h3><p>
        Быстрый выбор целых групп: весь флот, только линкоры, только
        авианосцы, вся авиация. На земле — все войска, техника, пехота,
        сборщики. Коснись той же кнопки ещё раз — камера перепрыгнет
        к следующему скоплению: пехота обычно стоит в двух-трёх местах,
        и «середина всех сразу» — это точка в чистом поле между ними.</p></section>
        <section><h3>Отряды на земле</h3><p>
        Три кнопки с цифрами под столбиком. Выдели войска и
        <b>придержи</b> цифру — отряд записан, на кнопке появится
        количество. Короткое нажатие выбирает отряд и переносит к нему
        камеру. С клавиатуры — Ctrl или Shift с цифрой и просто цифра.</p></section>
        <section><h3>Тактика поведения</h3><p>
        У выделенных боевых юнитов внизу появляются три кнопки.
        <b>Охрана</b> — держит участок: ввяжется в бой с тем, кто подошёл,
        погонится недалеко и вернётся на место. <b>Оборона</b> — стоит
        намертво и работает только по тому, до кого дотягивается; так
        ставят артиллерию и зенитки. <b>Нападение</b> — идёт на всё, что
        видит, и преследует до конца; так зачищают карту, но так же
        и теряют отряд по частям. Приказ атаковать конкретную цель
        сильнее любой тактики.</p></section>
        <section><h3>Идти с боем</h3><p>
        Обычный приказ идти гонит колонну мимо противника: стреляют
        на ходу, но не задерживаются. Кнопка «С боем» включает режим,
        в котором войска останавливаются на каждого встречного и
        добивают его, прежде чем идти дальше. Артиллерии он нужен
        особенно: на ходу она не стреляет вовсе. Режим остаётся
        включённым, пока не выключишь.</p></section>`;
    }
  };
  render(start);
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

/* ── СБОЙ В ИГРЕ (C19).
   Раньше requestAnimationFrame стоял В КОНЦЕ кадра без всякой защиты:
   одно исключение в update — и цикл обрывался навсегда. Игра замирала
   намертво, кнопки молчали, и ни слова о причине. Теперь следующий кадр
   заказывается ПЕРВЫМ, а тело кадра — в try. Исключение не останавливает
   цикл: показываем окно с текстом ошибки и двумя выходами — «Продолжить»
   (с того же места) и «В меню». Пока окно открыто, бой стоит (update не
   зовётся), а картинка рисуется дальше. Тем же окном ловятся ошибки
   вне кадра — в обработчиках кнопок и в обещаниях. */
const crash = { el: null, count: 0 };

function errText(err) {
  if (!err) return 'Неизвестная ошибка';
  if (typeof err === 'string') return err;
  const msg = `${err.name || 'Ошибка'}: ${err.message || err}`;
  const stack = String(err.stack || '').split('\n').slice(0, 7).join('\n');
  return stack.includes(err.message || '\u0000') ? stack : `${msg}\n${stack}`;
}

function showCrash(err) {
  console.error('Сбой в игре:', err);
  crash.count++;
  const text = errText(err);
  if (crash.el) {
    // окно уже открыто: не плодим второе, а говорим, что ошибка повторяется
    crash.el.querySelector('[data-role="again"]').textContent =
      `Ошибка повторилась: ${crash.count} раз. Если «Продолжить» не помогает — выйдите в меню или обновите страницу (F5).`;
    return;
  }
  const el = document.createElement('div');
  el.className = 'crash';
  el.setAttribute('role', 'alertdialog');
  el.innerHTML = `<div class="crash-inner">
      <h3>В игре произошла ошибка</h3>
      <p>Игра не зависла: можно продолжить с того же места или выйти в главное меню.
      Если ошибка повторяется — скопируйте текст ниже и пришлите разработчику.</p>
      <pre data-role="text"></pre>
      <p class="crash-again" data-role="again"></p>
      <div class="crash-actions">
        <button class="btn primary" data-a="go">Продолжить</button>
        <button class="btn" data-a="menu">В меню</button>
        <button class="btn ghost" data-a="copy">Скопировать текст</button>
      </div>
    </div>`;
  el.querySelector('[data-role="text"]').textContent = text;
  const go = el.querySelector('[data-a="go"]');
  // Продолжать нечего, если экран так и не собрался
  if (!mode) go.disabled = true;
  const close = () => { el.remove(); crash.el = null; crash.count = 0; };
  go.onclick = close;
  el.querySelector('[data-a="menu"]').onclick = () => { close(); showMenu(); };
  el.querySelector('[data-a="copy"]').onclick = async e => {
    const b = e.currentTarget;
    try { await navigator.clipboard.writeText(text); b.textContent = 'Скопировано'; }
    catch (_) {
      // буфер недоступен — выделим текст, чтобы скопировать руками
      const r = document.createRange();
      r.selectNodeContents(el.querySelector('[data-role="text"]'));
      const sel = getSelection(); sel.removeAllRanges(); sel.addRange(r);
      b.textContent = 'Выделено — нажмите Ctrl+C';
    }
  };
  stage.appendChild(el);
  crash.el = el;
}

/* Своей считаем только ошибку из НАШИХ файлов — game/js/ и
   game/vendor/ — по имени файла или по стеку. Расширения браузера
   (переводчики, кошельки, проверка орфографии) вставляют скрипты
   прямо в страницу, и у их ошибок имя файла — адрес самой игры
   (…/game/), а в стеке «<anonymous>». Раньше фильтр «/game/» их
   пропускал: окно сбоя открывалось над меню и ставило бой на паузу
   из-за чужой поломки. Отказ обещания без стека — тоже не наш:
   только строка в консоли. */
const OWN_CODE = /\/game\/(js|vendor)\//;
const ownError = (file, err) => OWN_CODE.test(file || '') || OWN_CODE.test(String((err && err.stack) || ''));
addEventListener('error', e => {
  if (!e.error && /^Script error/i.test(e.message || '')) return;
  if (!ownError(e.filename, e.error)) { console.warn('Ошибка чужого скрипта (расширение браузера?), игра её пропускает:', e.message); return; }
  showCrash(e.error || e.message);
});
addEventListener('unhandledrejection', e => {
  if (!ownError('', e.reason)) { console.warn('Отказ обещания не из кода игры, пропускаю:', e.reason); return; }
  showCrash(e.reason);
});

/* ── СЧЁТЧИК КАДРОВ (часть C52).
   Цифры со стенда разработчика ничего не говорят о компьютере
   игрока, поэтому счётчик встроен в игру: F3 или галочка в меню,
   выбор помнится. Показывает кадры в секунду, самый долгий кадр
   за полсекунды, вызовы отрисовки и треугольники. Вызовы считаются
   за ВЕСЬ кадр: постобработка рендерит несколько проходов, и штатный
   счётчик three.js сбрасывался бы на каждом, показывая только
   последний. Поэтому autoReset выключен, а сброс — в начале кадра. */
const fpsMeter = { on: false, el: null, frames: 0, t0: 0, worst: 0, calls: 0, tris: 0 };
try { fpsMeter.on = localStorage.getItem(FPS_KEY) === '1'; } catch (e) { /* приватный режим */ }

function setFps(on) {
  fpsMeter.on = !!on;
  try { localStorage.setItem(FPS_KEY, on ? '1' : '0'); } catch (e) { /* и ладно */ }
  if (!fpsMeter.el) {
    fpsMeter.el = document.createElement('div');
    fpsMeter.el.className = 'fpsmeter';
    stage.appendChild(fpsMeter.el);
  }
  fpsMeter.el.hidden = !fpsMeter.on;
  fpsMeter.el.textContent = 'кадры: замер…';
  fpsMeter.frames = 0; fpsMeter.worst = 0; fpsMeter.t0 = performance.now();
  const box = hudRoot.querySelector('[data-a="fps"]');
  if (box) box.checked = fpsMeter.on;
}

function fpsTick(now, frameMs) {
  const m = fpsMeter;
  m.frames++;
  if (frameMs > m.worst) m.worst = frameMs;
  if (now - m.t0 < 500) return;
  const fps = m.frames * 1000 / (now - m.t0);
  const tris = m.tris >= 1e6 ? (m.tris / 1e6).toFixed(2) + ' млн' : Math.round(m.tris / 1000) + ' тыс.';
  m.el.textContent = `${Math.round(fps)} к/с · худший ${Math.round(m.worst)} мс · вызовы ${m.calls} · треуг. ${tris}`;
  m.frames = 0; m.worst = 0; m.t0 = now;
}

addEventListener('keydown', e => {
  if (e.code !== 'F3') return;
  e.preventDefault();          // в браузере F3 — «найти далее»
  setFps(!fpsMeter.on);
});

/* ── ВИДЕОКАРТА СБРОСИЛА КАРТИНКУ. Так бывает после сбоя драйвера
   на Windows или переключения видеокарт ноутбука. three.js сам
   переживает потерю и восстановление, но экран всё это время
   чёрный — говорим словами, что происходит и что делать. */
let glNote = null;
canvas.addEventListener('webglcontextlost', () => {
  if (glNote) return;
  glNote = document.createElement('div');
  glNote.className = 'glnote';
  glNote.textContent = 'Видеокарта сбросила картинку — ждём, пока она вернётся. Если экран так и останется чёрным, обновите страницу (F5).';
  stage.appendChild(glNote);
});
canvas.addEventListener('webglcontextrestored', () => { if (glNote) { glNote.remove(); glNote = null; } });

// ─────────────────────────────────────────────────────────────
// ЦИКЛ
// ─────────────────────────────────────────────────────────────

let last = performance.now();
function frame(now) {
  // Следующий кадр — ПЕРВЫМ: что бы ни случилось ниже, цикл не оборвётся
  requestAnimationFrame(frame);
  const frameMs = now - last;
  const dt = Math.min(0.05, frameMs / 1000) || 0.016;
  last = now;
  if (!mode) return;
  // Пока открыто окно сбоя, бой стоит: игрок читает, что случилось
  if (!crash.el) {
    try { mode.update(dt); } catch (e) { showCrash(e); }
  }
  const info = viewport.renderer.info;
  info.reset();
  try { viewport.render(mode.scene, mode.camera); } catch (e) { showCrash(e); }
  if (fpsMeter.on && fpsMeter.el) {
    fpsMeter.calls = info.render.calls;
    fpsMeter.tris = info.render.triangles;
    fpsTick(now, frameMs);
  }
}

// Не даём странице скроллиться и зумиться на планшете
document.addEventListener('gesturestart', e => e.preventDefault());
document.addEventListener('touchmove', e => {
  if (e.target === canvas) e.preventDefault();
}, { passive: false });

/* ── ЗАПУСК (C40).
   Меню показывается СРАЗУ, а внешние модели и картинки планет едут
   в фоне. Раньше меню ждало их все: 5–11 секунд чёрного экрана на
   обычной связи, а зависший запрос не давал меню вовсе. Теперь у
   каждой загрузки свой предел времени (assets.js), и бой, если модели
   ещё в пути, дожидается их под «Подготовкой боя» с подписью. Не
   доехали — бой идёт на процедурных моделях, а приехавшая позже
   модель достанется следующему бою. */
const assetProgress = { total: 0, done: 0 };
// Модели и картинки планет — отдельно: разным экранам нужно разное
let modelsReady = !viewport, planetsReady = !viewport;
const modelsPromise = viewport
  ? loadModelLibrary(assetProgress)
    .then(m => { if (m) console.info(`Загружено внешних моделей: ${m} из ${modelCount()}`); })
    .catch(e => console.warn('Внешние модели не загрузились:', e))
    .finally(() => { modelsReady = true; })
  : Promise.resolve();
const planetsPromise = viewport
  ? loadPlanetTextures()
    .then(p => { if (p) console.info(`Загружено текстур планет: ${p} из ${planetCount()}`); })
    .catch(e => console.warn('Картинки планет не загрузились:', e))
    .finally(() => { planetsReady = true; })
  : Promise.resolve();

if (viewport) {
  viewport.renderer.info.autoReset = false;
  if (fpsMeter.on) setFps(true);
  showMenu();
  requestAnimationFrame(frame);
  window.__capellaUp = true;
  if (window.__bootDone) window.__bootDone();
}

// Автосохранение при уходе со страницы
addEventListener('visibilitychange', () => { if (document.hidden) save(); });
addEventListener('pagehide', save);
