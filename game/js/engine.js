/* Движок: всё, что общее для трёх экранов (галактика, космос, земля).
   Рендерер, тактическая камера, единое управление для мыши и пальцев,
   пул эффектов (лучи, трассеры, взрывы) и мелкая математика.

   Управление сделано «компьютер в первую очередь», как в RTS (C25, C72):
     мышь:  ЛКМ — выбрать, протяжкой — рамка; ПКМ — приказ (на
            ОТПУСКАНИИ, если мышь не уехала), ПКМ с протяжкой — поворот
            камеры; средняя кнопка с протяжкой — двигать карту; колесо —
            приближение к курсору; курсор у края экрана — прокрутка;
     клавиши: стрелки — двигать карту, Q/E — поворот; WASD — только
            там, где буквы не заняты приказами (см. `wasd`);
     палец: тянуть по пустому — двигать карту, щипок — приближение,
            два пальца — облёт, короткое касание — выбрать/приказать,
            долгое нажатие и потянуть — рамка выделения.
   Alt с мышью не используется вовсе: в Linux его забирает оконный
   менеджер — Alt+протяжка двигает окно браузера (C72). */

import * as THREE from '../vendor/three.module.min.js';
import { EffectComposer } from '../vendor/EffectComposer.js';
import { RenderPass } from '../vendor/RenderPass.js';
import { UnrealBloomPass } from '../vendor/UnrealBloomPass.js';
import { OutputPass } from '../vendor/OutputPass.js';

export { THREE };

export const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
export const lerp = (a, b, t) => a + (b - a) * t;
export const rnd = (a, b) => a + Math.random() * (b - a);
export const pickOne = arr => arr[(Math.random() * arr.length) | 0];
export const TAU = Math.PI * 2;

export const IS_TOUCH = matchMedia('(pointer: coarse)').matches ||
  ('ontouchstart' in window && navigator.maxTouchPoints > 0);

/* Настройки управления — одни на все экраны, помнятся в localStorage
   (`capella_<имя>`). Прокрутка у края по умолчанию включена: это первое,
   чего ждёт рука за компьютером, а выключают её из меню паузы те, кому
   она мешает (окно не во весь экран, второй монитор рядом). */
export const prefs = { edge: true };
try {
  const v = localStorage.getItem('capella_edge');
  if (v !== null) prefs.edge = v === '1';
} catch (e) { /* приватный режим */ }
export function setPref(key, val) {
  prefs[key] = val;
  try { localStorage.setItem('capella_' + key, val === true ? '1' : val === false ? '0' : String(val)); } catch (e) { /* и ладно */ }
}

// ─────────────────────────────────────────────────────────────
// РЕНДЕРЕР
// ─────────────────────────────────────────────────────────────

export class Viewport {
  constructor(canvas) {
    this.canvas = canvas;
    this.renderer = new THREE.WebGLRenderer({
      canvas, antialias: !IS_TOUCH, powerPreference: 'high-performance', alpha: false,
    });
    // На планшете полное разрешение Retina съедает кадры без видимой пользы
    this.renderer.setPixelRatio(Math.min(devicePixelRatio || 1, IS_TOUCH ? 1.5 : 1.75));
    /* Тени. Без них любая сцена читается как плоская аппликация —
       это первое, чем отличается картинка нулевых от картинки
       девяностых. Мягкая фильтрация (PCFSoft) стоит немного дороже
       жёсткой, но жёсткая на планшете даёт пиксельную лесенку по
       краю тени, и лучше бы её тогда не было вовсе. */
    this.renderer.shadowMap.enabled = true;
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    this.renderer.shadowMap.autoUpdate = true;
    this.renderer.setClearColor(0x05070c, 1);
    // Киношная тональная компрессия: яркое перестаёт «выжигаться» в белое,
    // а тени не проваливаются. Без неё свечение выглядит дёшево.
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.renderer.toneMappingExposure = 1.05;

    this.w = 1; this.h = 1;
    this.bloomOn = true;
    this._buildComposer();
    this.resize();
    addEventListener('resize', () => this.resize());
    addEventListener('orientationchange', () => setTimeout(() => this.resize(), 250));
  }

  _buildComposer() {
    // Свечение считаем в половинном разрешении — на глаз разницы нет,
    // а кадров на планшете это экономит заметно.
    const k = IS_TOUCH ? 0.5 : 0.6;
    /* СГЛАЖИВАНИЕ. Флаг antialias у рендерера работает только при
       прямой отрисовке в канву. Мы же рисуем через постобработку —
       кадр уходит в промежуточный буфер, а у него сглаживания нет
       по умолчанию, и все грани получают лесенку. Отсюда и берётся
       ощущение «пиксельности» у эффектов: не текстуры виноваты,
       а край. Просим буфер с мультисэмплингом явно. */
    const size = this.renderer.getDrawingBufferSize(new THREE.Vector2());
    const rt = new THREE.WebGLRenderTarget(size.width, size.height, {
      type: THREE.HalfFloatType,
      samples: IS_TOUCH ? 2 : 4,
    });
    this.composer = new EffectComposer(this.renderer, rt);
    this.renderPass = new RenderPass(new THREE.Scene(), new THREE.PerspectiveCamera());
    this.bloom = new UnrealBloomPass(new THREE.Vector2(640 * k, 360 * k), 0.85, 0.55, 0.72);
    this.outputPass = new OutputPass();
    this.composer.addPass(this.renderPass);
    this.composer.addPass(this.bloom);
    this.composer.addPass(this.outputPass);
  }

  // Каждый экран задаёт своё свечение: в космосе сильное, на земле мягкое
  setBloom(opts) {
    if (!this.bloom) return;
    if (opts === false) { this.bloomOn = false; return; }
    this.bloomOn = true;
    if (opts) {
      if (opts.strength !== undefined) this.bloom.strength = opts.strength;
      if (opts.radius !== undefined) this.bloom.radius = opts.radius;
      if (opts.threshold !== undefined) this.bloom.threshold = opts.threshold;
    }
    if (opts && opts.exposure !== undefined) this.renderer.toneMappingExposure = opts.exposure;
  }

  resize() {
    const r = this.canvas.getBoundingClientRect();
    this.w = Math.max(1, Math.floor(r.width));
    this.h = Math.max(1, Math.floor(r.height));
    this.renderer.setSize(this.w, this.h, false);
    if (this.composer) this.composer.setSize(this.w, this.h);
    if (this.camera) this.syncCamera(this.camera);
  }

  syncCamera(cam) {
    this.camera = cam;
    cam.aspect = this.w / this.h;
    cam.updateProjectionMatrix();
  }

  /* Карта окружения. Без неё физически корректные материалы
     (а именно такие приезжают из Prism, Meshy и Blender) выглядят
     почти чёрными: металлу нечего отражать. Собираем её один раз
     из той же туманности, что служит фоном. */
  environmentFrom(equirect) {
    if (!this._pmrem) this._pmrem = new THREE.PMREMGenerator(this.renderer);
    if (this._env) this._env.dispose();
    this._env = this._pmrem.fromEquirectangular(equirect).texture;
    return this._env;
  }

  render(scene, camera) {
    if (this.camera !== camera) this.syncCamera(camera);
    const r = this.canvas.getBoundingClientRect();
    if (Math.abs(r.width - this.w) > 1 || Math.abs(r.height - this.h) > 1) this.resize();
    if (this.bloomOn && this.composer) {
      this.renderPass.scene = scene;
      this.renderPass.camera = camera;
      this.composer.render();
    } else {
      this.renderer.render(scene, camera);
    }
  }
}

// ─────────────────────────────────────────────────────────────
// ТАКТИЧЕСКАЯ КАМЕРА — только состояние и клавиатура.
// Пальцы и мышь ею двигает Controls.
// ─────────────────────────────────────────────────────────────

export class TacticalCamera {
  constructor(opts = {}) {
    this.cam = new THREE.PerspectiveCamera(opts.fov || 52, 1, opts.near || 0.6, opts.far || 12000);
    this.target = new THREE.Vector3(opts.tx || 0, opts.ty || 0, opts.tz || 0);
    this.yaw = opts.yaw ?? 0.6;
    this.pitch = opts.pitch ?? 0.85;
    this.dist = opts.dist ?? 180;
    this.minDist = opts.minDist ?? 25;
    this.maxDist = opts.maxDist ?? 1400;
    this.minPitch = opts.minPitch ?? 0.14;
    this.maxPitch = opts.maxPitch ?? 1.45;
    this.bounds = opts.bounds || null;
    this.allowY = !!opts.allowY;
    /* WASD двигает камеру только там, где буквы не заняты приказами.
       В бою на орбите A — атака с ходу, S — стоп, и половина раскладки
       (W и D двигают, A и S — нет) путала бы сильнее, чем её отсутствие:
       там камера на стрелках, у края экрана и на средней кнопке. */
    this.wasd = opts.wasd !== false;
    // Прокрутка у края экрана — только у камер игровых экранов
    this.edge = !!opts.edge;
    this.controls = null;          // Controls сам вписывается сюда
    this.keys = new Set();
    this.smooth = new THREE.Vector3().copy(this.target);
    /* Расстояние сглаживается так же, как точка взгляда (C131): `dist` —
       куда едем, `sdist` — где камера сейчас. Колесо раньше меняло
       расстояние мгновенно, и приближение шло рывками по 13%. */
    this.sdist = this.dist;
    this._onKeyDown = e => {
      if (e.target && /input|textarea|select/i.test(e.target.tagName)) return;
      // Ctrl/⌘ с буквой — это сочетание (группы, браузер), а не камера
      if (e.ctrlKey || e.metaKey) return;
      this.keys.add(e.code);
    };
    this._onKeyUp = e => this.keys.delete(e.code);
    this._onBlur = () => this.keys.clear();
    addEventListener('keydown', this._onKeyDown);
    addEventListener('keyup', this._onKeyUp);
    addEventListener('blur', this._onBlur);
    this.apply(1, true);
  }

  dispose() {
    removeEventListener('keydown', this._onKeyDown);
    removeEventListener('keyup', this._onKeyUp);
    removeEventListener('blur', this._onBlur);
  }

  zoom(factor) { this.dist = clamp(this.dist * factor, this.minDist, this.maxDist); }
  orbit(dx, dy) {
    this.yaw -= dx;
    this.pitch = clamp(this.pitch + dy, this.minPitch, this.maxPitch);
  }
  focus(v3, dist) {
    this.target.copy(v3);
    if (dist) this.dist = clamp(dist, this.minDist, this.maxDist);
  }

  /* Сдвиг точки взгляда в осях ЭКРАНА: fx — вправо, fz — к себе
     (отрицательное — вперёд, вглубь экрана), amount — в единицах мира.
     Раньше у s-членов стоял обратный знак: при взгляде строго с юга или
     с севера (yaw 0 и π) этого не видно, а после поворота камеры Q/E
     стрелки и WASD уводили карту в зеркальную сторону. */
  move(fx, fz, amount) {
    const s = Math.sin(this.yaw), c = Math.cos(this.yaw);
    this.target.x += (fx * c + fz * s) * amount;
    this.target.z += (-fx * s + fz * c) * amount;
  }

  // Сколько единиц мира приходится на точку экрана у точки взгляда
  worldPerPx(hPx) {
    return 2 * this.sdist * Math.tan(THREE.MathUtils.degToRad(this.cam.fov) / 2) / Math.max(1, hPx);
  }

  /* Сдвиг «за экран»: мышь уехала на dx, dy точек — мир едет за ней.
     Запасной путь там, где луч не встречает плоскость (над горизонтом). */
  panScreen(dxPx, dyPx, hPx) {
    const w = this.worldPerPx(hPx);
    this.move(-dxPx * w, -dyPx * w / Math.max(0.25, Math.sin(this.pitch)), 1);
    this.clampTarget();
  }

  /* Приближение К ТОЧКЕ ПОД КУРСОРОМ (C131). Масштабируем положение
     камеры вокруг точки P на плоскости взгляда: тогда P остаётся под
     тем же пикселем и в итоге, и на всём пути сглаживания (точка
     взгляда и расстояние сглаживаются одной долей, и камера идёт по
     прямой через P). P считаем от камеры «как встанет», а не от той,
     что ещё в пути: иначе быстрые щелчки колеса копили бы увод.
     nx, ny — координаты курсора в −1…1. */
  zoomAt(factor, nx, ny) {
    const d0 = this.dist;
    const d1 = clamp(d0 * factor, this.minDist, this.maxDist);
    if (d1 === d0) return;
    const P = nx === undefined ? null : this._goalPoint(nx, ny);
    this.dist = d1;
    if (!P) return;
    const k = 1 - d1 / d0;
    this.target.x += (P.x - this.target.x) * k;
    this.target.z += (P.z - this.target.z) * k;
    this.clampTarget();
  }

  _goalPoint(nx, ny) {
    const c = this._goal || (this._goal = new THREE.PerspectiveCamera());
    c.fov = this.cam.fov; c.aspect = this.cam.aspect; c.near = this.cam.near; c.far = this.cam.far;
    c.updateProjectionMatrix();
    this._place(c, this.target, this.dist);
    c.updateMatrixWorld();
    const ray = this._ray || (this._ray = new THREE.Raycaster());
    ray.setFromCamera(new THREE.Vector2(nx, ny), c);
    const o = ray.ray.origin, d = ray.ray.direction;
    // Над горизонтом или почти вдоль плоскости — приближаем к середине
    if (d.y > -0.02) return null;
    const py = this.target.y;
    const t = (py - o.y) / d.y;
    if (t < 0) return null;
    const P = new THREE.Vector3(o.x + d.x * t, py, o.z + d.z * t);
    // У горизонта точка улетает за тридевять земель — тянем не дальше трёх дистанций
    const dx = P.x - this.target.x, dz = P.z - this.target.z, L = Math.hypot(dx, dz), max = this.dist * 3;
    if (L > max) { P.x = this.target.x + dx / L * max; P.z = this.target.z + dz / L * max; }
    return P;
  }

  update(dt) {
    const k = this.keys;
    let fx = 0, fz = 0;
    if (k.has('ArrowUp') || (this.wasd && k.has('KeyW'))) fz -= 1;
    if (k.has('ArrowDown') || (this.wasd && k.has('KeyS'))) fz += 1;
    if (k.has('ArrowLeft') || (this.wasd && k.has('KeyA'))) fx -= 1;
    if (k.has('ArrowRight') || (this.wasd && k.has('KeyD'))) fx += 1;
    if (k.has('KeyQ')) this.yaw += dt * 1.3;
    if (k.has('KeyE')) this.yaw -= dt * 1.3;
    if (this.allowY) {
      if (k.has('KeyR')) this.target.y += this.dist * 0.5 * dt;
      if (k.has('KeyF')) this.target.y -= this.dist * 0.5 * dt;
    }
    // Курсор у края экрана — та же прокрутка, что стрелками (C25)
    const ed = this.edge && prefs.edge && this.controls ? this.controls.edgeDir() : null;
    if (ed) { fx = clamp(fx + ed.x, -1, 1); fz = clamp(fz + ed.y, -1, 1); }
    if (fx || fz) this.move(fx, fz, this.dist * 0.8 * dt);
    this.clampTarget();
    this.apply(dt);
  }

  clampTarget() {
    const b = this.bounds;
    if (!b) return;
    this.target.x = clamp(this.target.x, -b.x, b.x);
    this.target.z = clamp(this.target.z, -b.z, b.z);
    if (b.y !== undefined) this.target.y = clamp(this.target.y, -b.y, b.y);
  }

  apply(dt, instant) {
    const t = instant ? 1 : 1 - Math.pow(0.0012, Math.min(dt, 0.1));
    this.smooth.lerp(this.target, t);
    this.sdist += (this.dist - this.sdist) * t;
    this._place(this.cam, this.smooth, this.sdist);
  }

  _place(cam, at, dist) {
    const cp = Math.cos(this.pitch), sp = Math.sin(this.pitch);
    cam.position.set(
      at.x + Math.sin(this.yaw) * cp * dist,
      at.y + sp * dist,
      at.z + Math.cos(this.yaw) * cp * dist,
    );
    cam.lookAt(at);
  }
}

// ─────────────────────────────────────────────────────────────
// УПРАВЛЕНИЕ: мышь и пальцы в одном месте
//
// handlers:
//   onTap({x, y, entity, world, shift, touch, double})
//                                    — щелчок / касание; double — второй
//                                      щелчок ЛКМ в том же месте за 0,4 с
//   onBox(rect, additive)            — рамка выделения
//   onOrder({x, y, entity, world, shift})
//                                    — ПКМ на мыши, на ОТПУСКАНИИ: если
//                                      мышь уехала дальше 6 точек, это был
//                                      поворот камеры, а не приказ
//   pickMeshes()                     — что можно ткнуть
//   canPick(entity)                  — можно ли его выбрать сейчас
//                                      (скрытый противник — нельзя)
//   planeY()                         — высота плоскости для приказов
//
// Наружу: hover {x, y, in} — где мышь над полем (экран сам решает,
// что под ней, и красит курсор через setCursor); edgeDir() — для
// прокрутки у края; viewQuad() — рамка обзора на миникарте.
// ─────────────────────────────────────────────────────────────

const LONG_PRESS_MS = 420;
const TAP_SLOP = 12;
// У мыши рука твёрже пальца: 6 точек отличают «щёлкнул» от «потянул»
const MOUSE_SLOP = 6;
const DBL_MS = 400, DBL_PX = 10;
// Полоса у края экрана, где курсор прокручивает карту
export const EDGE_PX = 10;

// Виден ли объект на самом деле: спрятан он сам или кто-то из предков
function shownInScene(o) {
  for (let p = o; p; p = p.parent) if (p.visible === false) return false;
  return true;
}

export class Controls {
  constructor(dom, tcam, handlers = {}) {
    this.dom = dom;
    this.tcam = tcam;
    this.h = handlers;
    this.enabled = true;
    this.ray = new THREE.Raycaster();
    this.ndc = new THREE.Vector2();
    this.pointers = new Map();
    // 'pan' | 'box' | 'orbit' | 'pinch' | 'rotate' | 'mpan' | 'maybe-…' | null
    this.mode = null;
    this.boxMode = false;    // принудительная рамка (кнопка на панели)
    this.plane = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0);
    this.hover = { x: 0, y: 0, in: false };
    this._cur = null;
    tcam.controls = this;

    this.boxEl = document.createElement('div');
    this.boxEl.className = 'select-box';
    this.boxEl.style.display = 'none';
    dom.parentElement.appendChild(this.boxEl);

    this._bind();
  }

  dispose() {
    this.boxEl.remove();
    this.setCursor(null);
    this.dom.classList.remove('cur-drag');
    for (const [k, v] of this._listeners) this.dom.removeEventListener(k, v);
    for (const [k, v] of this._winListeners) removeEventListener(k, v);
    if (this.tcam.controls === this) this.tcam.controls = null;
  }

  /* Курсор поля: экран говорит, что сейчас под мышью (выбрать /
     атаковать / идти), а Controls держит ровно один такой класс на
     канве. Канва общая для всех экранов, поэтому dispose его снимает. */
  setCursor(cls) {
    if (this._cur === cls) return;
    if (this._cur) this.dom.classList.remove(this._cur);
    this._cur = cls || null;
    if (cls) this.dom.classList.add(cls);
  }

  // ── геометрия ──────────────────────────────────────────
  _ndc(x, y) {
    const r = this.dom.getBoundingClientRect();
    this.ndc.x = ((x - r.left) / r.width) * 2 - 1;
    this.ndc.y = -((y - r.top) / r.height) * 2 + 1;
    return this.ndc;
  }

  worldAt(x, y, planeY) {
    const py = planeY !== undefined ? planeY : (this.h.planeY ? this.h.planeY() : 0);
    this.ray.setFromCamera(this._ndc(x, y), this.tcam.cam);
    const o = this.ray.ray.origin, d = this.ray.ray.direction;
    if (Math.abs(d.y) < 1e-5) return null;
    const t = (py - o.y) / d.y;
    if (t < 0 || t > 1e6) return null;
    return new THREE.Vector3(o.x + d.x * t, py, o.z + d.z * t);
  }

  /* Рамка обзора на плоскости — четыре угла экрана (C73). Угол, чей
     луч уходит над горизонтом, кладём на дальний край по направлению
     взгляда: иначе рамка на миникарте рвётся. [[x, z] × 4] */
  viewQuad(planeY = 0, far = 1e4) {
    const out = [];
    for (const [sx, sy] of [[-1, 1], [1, 1], [1, -1], [-1, -1]]) {
      this.ndc.set(sx, sy);
      this.ray.setFromCamera(this.ndc, this.tcam.cam);
      const o = this.ray.ray.origin, d = this.ray.ray.direction;
      let t = d.y < -1e-4 ? (planeY - o.y) / d.y : Infinity;
      if (t < 0) t = Infinity;
      if (t > far) {
        const L = Math.hypot(d.x, d.z) || 1;
        out.push([o.x + d.x / L * far, o.z + d.z / L * far]);
      } else out.push([o.x + d.x * t, o.z + d.z * t]);
    }
    return out;
  }

  pick(x, y) {
    const meshes = this.h.pickMeshes ? this.h.pickMeshes() : [];
    if (!meshes.length) return null;
    this.ray.setFromCamera(this._ndc(x, y), this.tcam.cam);
    // На пальце цельтесь щедрее: маленькие корабли иначе не поймать
    this.ray.params.Points.threshold = 6;
    const hits = this.ray.intersectObjects(meshes, true);
    for (const hit of hits) {
      /* Луч three.js НЕ смотрит на `visible` (C18): невидимый корабль
         Рииза ловился кликом и выдавал себя панелью с прочностью.
         Скрытое — у самого меша или у любого предка — не выбирается. */
      if (!shownInScene(hit.object)) continue;
      let o = hit.object;
      while (o && !o.userData.entity) o = o.parent;
      const ent = o && o.userData.entity;
      if (!ent || ent.dead) continue;
      if (this.h.canPick && !this.h.canPick(ent)) continue;
      return ent;
    }
    return null;
  }

  // Ближайшая к точке экрана сущность — запасной способ прицеливания,
  // когда луч прошёл мимо мелкой модели.
  pickNear(x, y, list, camera, w, h, radiusPx) {
    const r = this.dom.getBoundingClientRect();
    const px = x - r.left, py = y - r.top;
    let best = null, bd = radiusPx * radiusPx;
    for (const e of list) {
      if (e.dead) continue;
      if (this.h.canPick && !this.h.canPick(e)) continue;
      const p = screenOf(e.pos, camera, w, h);
      if (p.z > 1) continue;
      const d = (p.x - px) ** 2 + (p.y - py) ** 2;
      if (d < bd) { bd = d; best = e; }
    }
    return best;
  }

  /* ── ПРОКРУТКА У КРАЯ (C25). Куда толкает курсор: {x, y} в −1…1 или
     null. Не толкает, если окно не в фокусе или мышь ушла из окна
     (иначе карта уезжала бы, пока человек в соседней программе), если
     под курсором панель интерфейса (кнопка «Отход» у верхнего края —
     не повод уводить карту) и пока идёт протяжка камеры. Что под
     курсором, спрашиваем у самой страницы (elementFromPoint), а не
     помним с последнего движения: мышь стоит, а поверх поля открылось
     меню паузы — карта под ним ехать не должна. Спрашиваем только
     в полосе у края, то есть почти никогда. */
  edgeDir() {
    if (!this.enabled || !this._mouseIn) return null;
    if (this.mode === 'rotate' || this.mode === 'mpan' || this.mode === 'maybe-rotate') return null;
    if (typeof document.hasFocus === 'function' && !document.hasFocus()) return null;
    const r = this.dom.getBoundingClientRect();
    const x = this._mx - r.left, y = this._my - r.top;
    if (x < 0 || y < 0 || x > r.width || y > r.height) return null;
    let ex = 0, ey = 0;
    if (x < EDGE_PX) ex = -1; else if (x > r.width - EDGE_PX) ex = 1;
    if (y < EDGE_PX) ey = -1; else if (y > r.height - EDGE_PX) ey = 1;
    if (!ex && !ey) return null;
    if (document.elementFromPoint(this._mx, this._my) !== this.dom) return null;
    return { x: ex, y: ey };
  }

  // ── события ────────────────────────────────────────────
  _bind() {
    const d = this.dom;
    this._listeners = [];
    this._winListeners = [];
    const on = (name, fn, opts) => { d.addEventListener(name, fn, opts); this._listeners.push([name, fn]); };
    const onWin = (name, fn, opts) => { addEventListener(name, fn, opts); this._winListeners.push([name, fn]); };

    on('contextmenu', e => e.preventDefault());
    // Средняя кнопка в Windows включает автопрокрутку, в Linux — вставку
    on('mousedown', e => { if (e.button === 1) e.preventDefault(); });
    on('auxclick', e => { if (e.button === 1) e.preventDefault(); });

    /* Колесо — приближение к курсору (C131). Тачпад приходит сюда же:
       щипок — это колесо с Ctrl (приближение мелким шагом, иначе
       браузер зумил бы страницу целиком), а прокрутка двумя пальцами
       вбок — сдвиг карты (C72). Строки и страницы (Firefox) переводим
       в точки, иначе один щелчок колеса двигал бы на три точки. */
    on('wheel', e => {
      e.preventDefault();
      if (!this.enabled) return;
      let dx = e.deltaX, dy = e.deltaY;
      if (e.deltaMode === 1) { dx *= 40; dy *= 40; } else if (e.deltaMode === 2) { dx *= 800; dy *= 800; }
      const n = this._ndc(e.clientX, e.clientY);
      const nx = n.x, ny = n.y;
      if (e.ctrlKey) { this.tcam.zoomAt(Math.exp(clamp(dy, -60, 60) * 0.01), nx, ny); return; }
      if (Math.abs(dx) > Math.abs(dy)) {
        this.tcam.panScreen(-dx, 0, this.dom.getBoundingClientRect().height);
        return;
      }
      this.tcam.zoomAt(Math.exp(clamp(dy, -400, 400) * 0.0012), nx, ny);
    }, { passive: false });

    // Где мышь — для прокрутки у края (по всему окну, а не только над полем)
    onWin('pointermove', e => {
      if (e.pointerType !== 'mouse') return;
      this._mx = e.clientX; this._my = e.clientY; this._mouseIn = true;
    }, { passive: true });
    onWin('mouseout', e => { if (!e.relatedTarget) this._mouseIn = false; });
    onWin('blur', () => { this._mouseIn = false; });

    on('pointerleave', e => { if (e.pointerType === 'mouse') this.hover.in = false; });

    on('pointerdown', e => {
      if (!this.enabled) return;
      // Захват указателя — вещь полезная, но необязательная: в Safari он
      // иногда бросает исключение, а падение здесь ломает всё управление.
      try { d.setPointerCapture(e.pointerId); } catch (_) { /* и ладно */ }
      const p = {
        id: e.pointerId, type: e.pointerType, button: e.button,
        x: e.clientX, y: e.clientY, x0: e.clientX, y0: e.clientY,
        t0: performance.now(), moved: false,
      };
      this.pointers.set(e.pointerId, p);

      if (e.pointerType === 'mouse') {
        if (e.button === 2) {
          /* ПКМ — приказ, но на ОТПУСКАНИИ: потянул больше 6 точек —
             это поворот камеры, приказ не отдаётся */
          this.mode = 'maybe-rotate';
        } else if (e.button === 1) {
          // Средняя — «схватить мир» и тянуть карту, как пальцем
          e.preventDefault();
          this.mode = 'mpan';
          this._panAnchor = this.worldAt(e.clientX, e.clientY);
          this._panStart = this.tcam.target.clone();
          d.classList.add('cur-drag');
        } else if (e.button === 0) {
          this.mode = this.boxMode ? 'box' : 'maybe-box';
        }
        return;
      }

      // палец
      if (this.pointers.size === 2) {
        this.mode = 'pinch';
        const [a, b] = [...this.pointers.values()];
        this._pinchD = Math.hypot(a.x - b.x, a.y - b.y);
        this._pinchC = { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
        this._clearLongPress();
      } else if (this.pointers.size === 1) {
        this.mode = this.boxMode ? 'box' : 'maybe-pan';
        this._panAnchor = this.worldAt(e.clientX, e.clientY);
        this._panStart = this.tcam.target.clone();
        this._longPress = setTimeout(() => {
          const pp = this.pointers.get(e.pointerId);
          if (!pp || pp.moved) return;
          this.mode = 'box';
          this._boxOrigin = { x: pp.x, y: pp.y };
          if (navigator.vibrate) navigator.vibrate(18);
          this._drawBox(pp.x, pp.y, pp.x, pp.y);
        }, LONG_PRESS_MS);
      }
    });

    on('pointermove', e => {
      if (e.pointerType === 'mouse') {
        this.hover.x = e.clientX; this.hover.y = e.clientY; this.hover.in = true;
      }
      const p = this.pointers.get(e.pointerId);
      if (!p) return;
      const prevX = p.x, prevY = p.y;
      p.x = e.clientX; p.y = e.clientY;
      const slop = p.type === 'mouse' ? MOUSE_SLOP : TAP_SLOP;
      if (Math.abs(p.x - p.x0) > slop || Math.abs(p.y - p.y0) > slop) {
        if (!p.moved) { p.moved = true; this._clearLongPress(); }
      }

      // Средняя кнопка тянет карту с первой же точки — порога ей не нужно
      if (this.mode === 'mpan') { this._grab(p, prevX, prevY); return; }
      if (!p.moved) return;

      if (this.mode === 'pinch' && this.pointers.size >= 2) {
        const [a, b] = [...this.pointers.values()];
        const dd = Math.hypot(a.x - b.x, a.y - b.y);
        if (this._pinchD > 0) this.tcam.zoom(clamp(this._pinchD / dd, 0.5, 2));
        this._pinchD = dd;
        const cx = (a.x + b.x) / 2, cy = (a.y + b.y) / 2;
        // Смещение середины щипка вращает камеру
        this.tcam.orbit((cx - this._pinchC.x) * 0.006, (cy - this._pinchC.y) * 0.004);
        this._pinchC = { x: cx, y: cy };
        return;
      }

      if (this.mode === 'maybe-rotate') { this.mode = 'rotate'; d.classList.add('cur-drag'); }
      if (this.mode === 'rotate' || this.mode === 'orbit') {
        this.tcam.orbit((p.x - prevX) * 0.005, (p.y - prevY) * 0.004);
        return;
      }

      if (this.mode === 'maybe-pan' || this.mode === 'pan') {
        this.mode = 'pan';
        this._grab(p, prevX, prevY);
        return;
      }

      if (this.mode === 'maybe-box') this.mode = 'box';
      if (this.mode === 'box') {
        const o = this._boxOrigin || { x: p.x0, y: p.y0 };
        this._drawBox(o.x, o.y, p.x, p.y);
      }
    });

    this._up = e => {
      const p = this.pointers.get(e.pointerId);
      if (!p) return;
      this.pointers.delete(e.pointerId);
      this._clearLongPress();
      const dur = performance.now() - p.t0;
      const mode = this.mode;
      d.classList.remove('cur-drag');

      if (p.type === 'mouse' && p.button !== 0) {
        // ПКМ без протяжки — приказ; с протяжкой был поворот
        if (p.button === 2 && mode === 'maybe-rotate' && !p.moved) this._emitOrder(p, e.shiftKey);
        this.mode = this.pointers.size ? this.mode : null;
        return;
      }

      if (mode === 'box' && (p.moved || this._boxOrigin)) {
        const shown = this.boxEl.style.display === 'block';
        this.boxEl.style.display = 'none';
        this._boxOrigin = null;
        if (shown) {
          const r = this.dom.getBoundingClientRect();
          const o = { x: p.x0, y: p.y0 };
          const rect = {
            x0: Math.min(p.x, o.x) - r.left, y0: Math.min(p.y, o.y) - r.top,
            x1: Math.max(p.x, o.x) - r.left, y1: Math.max(p.y, o.y) - r.top,
          };
          if (rect.x1 - rect.x0 > 8 && rect.y1 - rect.y0 > 8) {
            this.h.onBox && this.h.onBox(rect, e.shiftKey);
            if (this.boxMode) this.setBoxMode(false);
            this.mode = this.pointers.size ? this.mode : null;
            return;
          }
        }
      }
      this.boxEl.style.display = 'none';

      if (!p.moved && (p.type === 'mouse' ? dur < 900 : dur < 500)) {
        this._emitTap(p, e.shiftKey);
      }
      if (!this.pointers.size) this.mode = null;
      else if (this.pointers.size === 1) this.mode = 'maybe-pan';
    };
    onWin('pointerup', this._up);
    onWin('pointercancel', this._up);
  }

  /* «Схватить мир»: точка под указателем остаётся под ним. Где луч не
     встречает плоскость (над горизонтом), двигаем «за экран». */
  _grab(p, prevX, prevY) {
    const now = this.worldAt(p.x, p.y);
    if (now && this._panAnchor) {
      this.tcam.target.copy(this._panStart).add(this._panAnchor).sub(now);
      this.tcam.clampTarget();
      // якорь пересчитываем от новой позиции камеры
      this.tcam.apply(0.016, true);
      const re = this.worldAt(p.x, p.y);
      if (re) this._panAnchor = re;
      this._panStart = this.tcam.target.clone();
    } else {
      this.tcam.panScreen(p.x - prevX, p.y - prevY, this.dom.getBoundingClientRect().height);
      this._panAnchor = this.worldAt(p.x, p.y);
      this._panStart = this.tcam.target.clone();
    }
  }

  _clearLongPress() {
    if (this._longPress) { clearTimeout(this._longPress); this._longPress = null; }
  }

  _drawBox(x0, y0, x1, y1) {
    const r = this.dom.getBoundingClientRect();
    this.boxEl.style.display = 'block';
    this.boxEl.style.left = (Math.min(x0, x1) - r.left) + 'px';
    this.boxEl.style.top = (Math.min(y0, y1) - r.top) + 'px';
    this.boxEl.style.width = Math.abs(x1 - x0) + 'px';
    this.boxEl.style.height = Math.abs(y1 - y0) + 'px';
  }

  _emitTap(p, shift) {
    // Второй щелчок ЛКМ в том же месте за 0,4 с — двойной (C50)
    let double = false;
    if (p.type === 'mouse') {
      const now = performance.now(), l = this._lastTap;
      double = !!l && now - l.t < DBL_MS && Math.hypot(p.x - l.x, p.y - l.y) < DBL_PX;
      this._lastTap = double ? null : { t: now, x: p.x, y: p.y };
    }
    const ent = this.pick(p.x, p.y);
    const world = this.worldAt(p.x, p.y);
    this.h.onTap && this.h.onTap({ x: p.x, y: p.y, entity: ent, world, shift, touch: p.type !== 'mouse', double });
  }

  _emitOrder(p, shift) {
    const ent = this.pick(p.x, p.y);
    const world = this.worldAt(p.x, p.y);
    this.h.onOrder && this.h.onOrder({ x: p.x, y: p.y, entity: ent, world, shift });
  }

  setBoxMode(on) {
    this.boxMode = on;
    this.dom.classList.toggle('box-cursor', on);
    this.h.onBoxModeChange && this.h.onBoxModeChange(on);
  }
}

// Экранные координаты точки мира
const _v = new THREE.Vector3();
export function screenOf(pos, camera, w, h) {
  _v.copy(pos).project(camera);
  return { x: (_v.x * 0.5 + 0.5) * w, y: (-_v.y * 0.5 + 0.5) * h, z: _v.z };
}

// ─────────────────────────────────────────────────────────────
// ЭФФЕКТЫ
// ─────────────────────────────────────────────────────────────

/* ── ТЕКСТУРЫ ЭФФЕКТОВ.

   Всё светящееся рисуется мягкими картами, а не геометрией с резким
   краем. Причина простая: край многоугольника даёт на экране лесенку,
   и чем ярче объект, тем она заметнее — свечение её ещё и раздувает.
   У мягкой карты края нет вовсе, поэтому луч, кольцо и искра остаются
   гладкими на любом приближении.

   Размер карт — 256: на 64 пикселях градиент идёт ступеньками, стоит
   растянуть спрайт на пол-экрана. Мип-уровни и анизотропия добивают
   остаток ряби на мелких искрах. */

const BEAM_GEO = new THREE.PlaneGeometry(1, 1, 1, 1);
BEAM_GEO.translate(0, 0.5, 0);          // растёт вдоль +Y от начала
const RING_GEO = new THREE.PlaneGeometry(1, 1, 1, 1);
const UP = new THREE.Vector3(0, 1, 0);
const _bv = new THREE.Vector3(), _bx = new THREE.Vector3(), _bz = new THREE.Vector3();
const _bm = new THREE.Matrix4();

function canvasTex(size, draw, opts = {}) {
  const c = document.createElement('canvas');
  c.width = size; c.height = opts.height || size;
  draw(c.getContext('2d'), c.width, c.height);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.generateMipmaps = true;
  t.minFilter = THREE.LinearMipmapLinearFilter;
  t.magFilter = THREE.LinearFilter;
  t.anisotropy = 4;
  return t;
}

function glowTexture() {
  return canvasTex(256, (g, S) => {
    const h = S / 2;
    const grad = g.createRadialGradient(h, h, 0, h, h, h);
    grad.addColorStop(0, 'rgba(255,255,255,1)');
    grad.addColorStop(0.14, 'rgba(255,248,232,0.92)');
    grad.addColorStop(0.34, 'rgba(255,206,150,0.46)');
    grad.addColorStop(0.62, 'rgba(255,150,70,0.14)');
    grad.addColorStop(1, 'rgba(255,120,40,0)');
    g.fillStyle = grad;
    g.fillRect(0, 0, S, S);
  });
}
export const GLOW_TEX = glowTexture();

/* Луч: поперёк — раскалённая сердцевина с мягким спадом, вдоль —
   затухание к обоим концам, чтобы отрезок не обрывался поперечной
   линией. */
function beamTexture() {
  return canvasTex(64, (g, W, H) => {
    const grad = g.createLinearGradient(0, 0, W, 0);
    grad.addColorStop(0, 'rgba(255,255,255,0)');
    grad.addColorStop(0.28, 'rgba(255,255,255,0.35)');
    grad.addColorStop(0.5, 'rgba(255,255,255,1)');
    grad.addColorStop(0.72, 'rgba(255,255,255,0.35)');
    grad.addColorStop(1, 'rgba(255,255,255,0)');
    g.fillStyle = grad;
    g.fillRect(0, 0, W, H);
    const ends = g.createLinearGradient(0, 0, 0, H);
    ends.addColorStop(0, 'rgba(0,0,0,1)');
    ends.addColorStop(0.06, 'rgba(0,0,0,0)');
    ends.addColorStop(0.94, 'rgba(0,0,0,0)');
    ends.addColorStop(1, 'rgba(0,0,0,1)');
    g.globalCompositeOperation = 'destination-out';
    g.fillStyle = ends;
    g.fillRect(0, 0, W, H);
  }, { height: 256 });
}
export const BEAM_TEX = beamTexture();

// Кольцо ударной волны: тонкий светящийся обод с размытыми краями
function ringTexture() {
  return canvasTex(256, (g, S) => {
    const h = S / 2;
    const grad = g.createRadialGradient(h, h, 0, h, h, h);
    grad.addColorStop(0, 'rgba(255,255,255,0)');
    grad.addColorStop(0.62, 'rgba(255,255,255,0)');
    grad.addColorStop(0.80, 'rgba(255,255,255,0.55)');
    grad.addColorStop(0.90, 'rgba(255,255,255,1)');
    grad.addColorStop(0.97, 'rgba(255,255,255,0.30)');
    grad.addColorStop(1, 'rgba(255,255,255,0)');
    g.fillStyle = grad;
    g.fillRect(0, 0, S, S);
  });
}
export const RING_TEX = ringTexture();

/* Факел двигателя: сверху раскалённое горло, книзу — рыжий язык,
   сходящий на нет. Плоская карта на скрещённых плоскостях читается
   пламенем с любой стороны, круглый спрайт — только кляксой. */
function plumeTexture() {
  return canvasTex(128, (g, W, H) => {
    /* Рисуем строку за строкой, БЕЗ масок вырезания. Ловушка тут в
       том, что `destination-in` действует на весь холст, а не на
       нарисованный прямоугольник: в цикле по строкам каждая
       следующая стирала всё, что нарисовали раньше, и от факела
       оставалась одна полоска. */
    for (let y = 0; y < H; y++) {
      const t = y / (H - 1);
      // яркость вдоль струи: раскалённое горло → рыжий язык → ничего
      const a = Math.pow(1 - t, 1.7);
      const r = 255;
      const gr = Math.round(250 - 130 * t);
      const b = Math.round(224 - 200 * t);
      // ширина: сопло у среза, сходит на нет к хвосту
      const wide = W * (0.5 - 0.40 * Math.pow(t, 0.6));
      const grad = g.createLinearGradient(W / 2 - wide, 0, W / 2 + wide, 0);
      grad.addColorStop(0, `rgba(${r},${gr},${b},0)`);
      grad.addColorStop(0.35, `rgba(${r},${gr},${b},${(a * 0.55).toFixed(3)})`);
      grad.addColorStop(0.5, `rgba(255,255,255,${(a * (0.35 + 0.65 * (1 - t))).toFixed(3)})`);
      grad.addColorStop(0.65, `rgba(${r},${gr},${b},${(a * 0.55).toFixed(3)})`);
      grad.addColorStop(1, `rgba(${r},${gr},${b},0)`);
      g.fillStyle = grad;
      g.fillRect(W / 2 - wide, y, wide * 2, 1);
    }
  }, { height: 256 });
}
export const PLUME_TEX = plumeTexture();

export class Fx {
  constructor(scene, budget = {}) {
    this.scene = scene;
    this.beams = [];
    this.sprites = [];
    this.rings = [];
    this.camera = null;
    this.maxBeams = budget.beams || (IS_TOUCH ? 90 : 160);
    this.maxSprites = budget.sprites || (IS_TOUCH ? 160 : 300);
    this.maxRings = budget.rings || (IS_TOUCH ? 14 : 26);
    this.busy = 0;           // доля занятых спрайтов, считается в update
    this.group = new THREE.Group();
    this.group.frustumCulled = false;
    scene.add(this.group);
    this.shake = 0;
    /* Отложенные эффекты крутятся на игровом времени, а не на
       setTimeout: иначе на паузе взрыв догорит без игрока, а на
       четырёхкратной скорости отстанет от боя. */
    this.timers = [];
  }

  delay(after, fn) { this.timers.push({ t: after, fn }); }

  /* ── ПУЛ ПЕРЕПОЛНЕН (C44).
     Раньше при переполнении отдавался СЛУЧАЙНЫЙ живой эффект: взрыв
     обрывался на середине, луч гас раньше времени, искра прыгала через
     экран. Теперь отдаём тот, что ближе всех к концу своей жизни (он и
     так почти погас), — разница на глаз не видна. Поиск свободного и
     самого старого — один проход по пулу. */
  _oldest(list) {
    let worst = null, wk = -1;
    for (const x of list) {
      if (!x.live) return x;
      const k = x.t / x.life;
      if (k > wk) { wk = k; worst = x; }
    }
    return list.length >= this._cap(list) ? worst : null;
  }
  _cap(list) {
    return list === this.beams ? this.maxBeams : list === this.sprites ? this.maxSprites : this.maxRings;
  }

  /* Можно ли сейчас тратить спрайты на след (дым ракеты, инверсия
     истребителя, дым обломка). Следы — главные пожиратели пула, а
     вспышкам и взрывам место нужнее: при пуле, занятом больше чем на
     70%, и вдали от камеры, где клуб в пару пикселей всё равно не
     виден, след не кладём. */
  trailOk(pos, far = 2400) {
    if (this.busy > 0.7) return false;
    return !this.camera || !pos || this.camera.position.distanceToSquared(pos) < far * far;
  }

  /* Сколько частиц класть на самом деле. В большом бою пул спрайтов
     занят ВЕСЬ бой: замер — четыре выдачи из пяти отбирали живой
     эффект. Поэтому при занятом пуле искр, обломков и дыма меньше (при
     полном — около трети), а вдали от камеры вдвое меньше: там искра
     мельче пикселя. Лишняя частица всё равно отобрала бы место у
     вспышки, которая сейчас на виду. */
  _n(count, pos) {
    let k = this.busy > 0.6 ? Math.max(0.35, 1 - (this.busy - 0.6) * 1.6) : 1;
    if (this.camera && pos && this.camera.position.distanceToSquared(pos) > 2400 * 2400) k *= 0.5;
    return count * k;
  }

  _beam() {
    const old = this._oldest(this.beams);
    if (old) return old;
    const m = new THREE.Mesh(BEAM_GEO, new THREE.MeshBasicMaterial({
      map: BEAM_TEX, color: 0xffffff, transparent: true, opacity: 1,
      blending: THREE.AdditiveBlending, depthWrite: false, toneMapped: false,
      side: THREE.DoubleSide,
    }));
    m.visible = false;
    m.frustumCulled = false;
    const b = { mesh: m, live: false, t: 0, life: 1, w: 1 };
    this.beams.push(b);
    this.group.add(m);
    return b;
  }

  _sprite() {
    /* smokeEvery сбрасывать обязательно: иначе бывший обломок, ставший
       клубом дыма, сам начинал дымить — след плодил след */
    const reset = s => { s.vel = null; s.grav = 0; s.fadeIn = false; s.smokeEvery = 0; s.mesh.material.opacity = 1; return s; };
    const old = this._oldest(this.sprites);
    if (old) return reset(old);
    const m = new THREE.Sprite(new THREE.SpriteMaterial({
      map: GLOW_TEX, color: 0xffffff, transparent: true, blending: THREE.AdditiveBlending,
      depthWrite: false, toneMapped: false,
    }));
    m.visible = false;
    const s = { mesh: m, live: false, t: 0, life: 1, r0: 1, r1: 2, vel: null };
    this.sprites.push(s);
    this.group.add(m);
    return s;
  }

  /* Плоскость луча разворачиваем так, чтобы её нормаль смотрела на
     камеру: иначе с некоторых ракурсов луч виден с ребра и исчезает.
     Ось (длина) при этом остаётся на месте — крутим только вокруг неё. */
  _faceBeam(b) {
    const ax = b.axis;
    if (!ax) return;
    if (!this.camera) {
      b.mesh.quaternion.setFromUnitVectors(UP, ax.dir);
      return;
    }
    _bv.subVectors(this.camera.position, b.mesh.position);
    _bx.crossVectors(_bv, ax.dir);
    if (_bx.lengthSq() < 1e-6) _bx.set(1, 0, 0).cross(ax.dir);   // смотрим вдоль луча
    _bx.normalize();
    _bz.crossVectors(_bx, ax.dir).normalize();
    _bm.makeBasis(_bx, ax.dir, _bz);
    b.mesh.quaternion.setFromRotationMatrix(_bm);
  }

  beam(from, to, opts = {}) {
    const b = this._beam();
    b.live = true; b.t = 0; b.life = opts.life ?? 0.35; b.travel = null; b.trail = null;
    b.w = opts.width ?? 1.6;
    b.mesh.visible = true;
    b.mesh.material.color.set(opts.color ?? 0xff9d5c);
    b.mesh.material.opacity = 1;
    const dir = new THREE.Vector3().subVectors(to, from);
    const len = dir.length() || 0.001;
    dir.divideScalar(len);
    /* Луч — не труба, а плоскость, развёрнутая ребром к зрителю.
       У трубы виден шестигранный силуэт и жёсткий край; плоскость
       с мягкой картой края не имеет вовсе и всегда смотрит на
       камеру, как и положено свечению. */
    b.axis = { from: from.clone(), dir, len };
    b.mesh.position.copy(from);
    b.mesh.scale.set(b.w * 2, len, 1);
    this._faceBeam(b);
    return b;
  }

  tracer(from, to, color = 0xffe08a, life = 0.12, width = 0.28) {
    return this.beam(from, to, { color, life, width });
  }

  /* ── ЛЕТЯЩИЙ СНАРЯД.
     Трассер рисует всю линию разом — это правильно для пулемётной
     очереди, но танковый выстрел так превращается в мигающую нитку
     от ствола до цели. Здесь короткий отрезок ЕДЕТ от ствола к цели
     за отведённое время: видно, что летит болванка, а не что кто-то
     провёл линейкой. */
  shot(from, to, opts = {}) {
    const b = this._beam();
    const dir = new THREE.Vector3().subVectors(to, from);
    const dist = dir.length() || 0.001;
    dir.divideScalar(dist);
    b.live = true; b.t = 0;
    b.life = opts.life ?? Math.max(0.12, dist / (opts.speed ?? 320));
    b.w = opts.width ?? 0.5;
    b.travel = { from: from.clone(), dir, dist, len: Math.min(opts.len ?? 9, dist * 0.6) };
    b.axis = { from: from.clone(), dir, len: b.travel.len };
    // Ракете нужен след: без него она неотличима от болванки
    b.trail = opts.trail ? { every: 0.03, at: 0 } : null;
    b.mesh.visible = true;
    b.mesh.material.color.set(opts.color ?? 0xffe08a);
    b.mesh.material.opacity = 1;
    b.mesh.scale.set(b.w * 2, b.travel.len, 1);
    b.mesh.position.copy(from);
    this._faceBeam(b);
    return b;
  }

  /* Кольцо, ЛЕЖАЩЕЕ на земле, а не развёрнутое к зрителю. Ударная
     волна по грунту читается только так: повёрнутое к камере кольцо
     на земле выглядит нимбом, висящим в воздухе. */
  ringFlat(pos, r0, r1, color = 0xffd08a, life = 0.5) {
    const r = this.ring(pos, r0, r1, color, life);
    r.flat = true;
    r.mesh.rotation.set(-Math.PI / 2, 0, 0);
    return r;
  }

  /* Обломки: тёмные быстрые крупицы с дымным следом. Отличаются от
     искр тем, что летят дальше, гаснут медленнее и тянут за собой
     дым — из-за них взрыв выглядит разрушением, а не вспышкой. */
  debris(pos, count = 6, color = 0x6a5a48, speed = 30, gravity = -42) {
    const n = clamp(Math.round(this._n(count, pos) * (IS_TOUCH ? 0.5 : 1)), 1, 16);
    for (let i = 0; i < n; i++) {
      const s = this._sprite();
      s.live = true; s.t = 0; s.life = rnd(0.7, 1.5);
      s.r0 = rnd(0.9, 2.2); s.r1 = rnd(0.4, 1.0);
      s.mesh.visible = true;
      s.mesh.material.color.set(color);
      s.mesh.position.copy(pos);
      s.vel = new THREE.Vector3(rnd(-1, 1), rnd(0.3, 1.5), rnd(-1, 1))
        .normalize().multiplyScalar(speed * rnd(0.5, 1.4));
      s.grav = gravity;
      s.smokeEvery = 0.09;      // след: клуб каждые несколько сотых
      s.smokeAt = 0;
    }
  }

  /* Дульное пламя. Круглое пятно у ствола читается лампочкой:
     у выстрела нет направления. Здесь короткий язык ВДОЛЬ ствола —
     та же плоскость, что у луча, только совсем короткая и живущая
     одно мгновение. */
  muzzle(from, dir, size = 3, color = 0xffd9a0) {
    const to = _bv.copy(dir).normalize().multiplyScalar(size * 2.2).add(from);
    const b = this.beam(from, to, { color, width: size * 0.5, life: 0.09 });
    this.flash(from, size * 0.55, 0xfff2d8, 0.08);
    return b;
  }

  // Клуб выхлопа: маленький, всплывающий, быстро тающий. Ракета
  // без следа читается как летящая искра, а не как ракета.
  puff(pos, size = 1.6, color = 0x8a8378, life = 0.55) {
    const s = this._sprite();
    s.live = true; s.t = 0; s.life = life;
    s.r0 = size; s.r1 = size * 3.4;
    s.mesh.visible = true;
    s.mesh.material.color.set(color);
    s.mesh.position.copy(pos);
    s.vel = new THREE.Vector3(rnd(-1, 1), rnd(0.2, 1.4), rnd(-1, 1));
    s.grav = 0;
    s.fadeIn = true;
    return s;
  }

  // Главный калибр — именно лазер: добела раскалённое ядро,
  // вокруг него цветной ореол, на цели — вспышка и ударное кольцо.
  laser(from, to, opts = {}) {
    const color = opts.color ?? 0x7fd8ff;
    const w = opts.width ?? 2;
    const life = opts.life ?? 0.5;
    this.beam(from, to, { color, life, width: w * 2.6 });        // ореол
    this.beam(from, to, { color: 0xffffff, life: life * 0.75, width: w * 0.55 }); // ядро
    this.flash(from, w * 5, 0xffffff, 0.22);
    this.flash(to, w * 6, color, 0.4);
    this.flash(to, w * 3, 0xffffff, 0.18);
    this.ring(to, w * 3, w * 16, color, 0.45);
  }

  // Расходящееся кольцо: попадание и взрывы читаются мгновенно
  ring(pos, r0, r1, color = 0x9fe8ff, life = 0.4) {
    const s = this._ringObj();
    s.live = true; s.t = 0; s.life = life; s.flat = false;
    s.r0 = r0; s.r1 = r1;
    s.mesh.visible = true;
    s.mesh.material.color.set(color);
    s.mesh.material.opacity = 1;
    s.mesh.position.copy(pos);
    s.mesh.scale.setScalar(r0 * 2);
    return s;
  }

  _ringObj() {
    if (!this.rings) this.rings = [];
    const old = this._oldest(this.rings);
    if (old) return old;
    const m = new THREE.Mesh(RING_GEO, new THREE.MeshBasicMaterial({
      map: RING_TEX, color: 0xffffff, transparent: true, opacity: 1, side: THREE.DoubleSide,
      blending: THREE.AdditiveBlending, depthWrite: false, toneMapped: false,
    }));
    m.visible = false;
    m.frustumCulled = false;
    const r = { mesh: m, live: false, t: 0, life: 1, r0: 1, r1: 2, flat: false };
    this.rings.push(r);
    this.group.add(m);
    return r;
  }

  flash(pos, size = 6, color = 0xffd08a, life = 0.25) {
    const s = this._sprite();
    s.live = true; s.t = 0; s.life = life;
    s.r0 = size; s.r1 = size * 1.9; s.vel = null;
    s.mesh.visible = true;
    s.mesh.material.color.set(color);
    s.mesh.position.copy(pos);
    s.mesh.scale.setScalar(size);
    return s;
  }

  /* ── ИСКРЫ.
     Раскалённые крупицы, летящие веером и гаснущие на лету. Именно
     они читаются как «попало»: вспышка одна сообщает только «здесь
     что-то произошло», а искры показывают, куда ударило и с какой
     силой. Живут в том же пуле спрайтов, поэтому бесплатны. */
  sparks(pos, count = 10, color = 0xffd08a, speed = 26, gravity = true) {
    const n = clamp(Math.round(this._n(count, pos) * (IS_TOUCH ? 0.55 : 1)), 2, 26);
    for (let i = 0; i < n; i++) {
      const s = this._sprite();
      s.live = true; s.t = 0; s.life = rnd(0.25, 0.7);
      s.r0 = rnd(0.5, 1.4); s.r1 = 0.05;
      s.mesh.visible = true;
      s.mesh.material.color.set(color);
      s.mesh.position.copy(pos);
      s.vel = new THREE.Vector3(rnd(-1, 1), rnd(gravity ? 0.2 : -1, 1.4), rnd(-1, 1))
        .normalize().multiplyScalar(speed * rnd(0.5, 1.5));
      s.grav = gravity ? -42 : 0;
    }
  }

  /* Дым: несколько клубов, которые всплывают и разбухают. Без него
     после взрыва не остаётся ничего — как будто ничего и не было. */
  smoke(pos, size = 6, color = 0x4a4238, count = 4) {
    const n = clamp(Math.round(this._n(count, pos) * (IS_TOUCH ? 0.6 : 1)), 1, 8);
    for (let i = 0; i < n; i++) {
      const s = this._sprite();
      s.live = true; s.t = 0; s.life = rnd(1.1, 2.2);
      s.r0 = size * rnd(0.4, 0.7); s.r1 = size * rnd(1.6, 2.6);
      s.mesh.visible = true;
      s.mesh.material.color.set(color);
      s.mesh.position.copy(pos).add(
        new THREE.Vector3(rnd(-1, 1), rnd(0, 1), rnd(-1, 1)).multiplyScalar(size * 0.3));
      s.vel = new THREE.Vector3(rnd(-2, 2), rnd(3, 7), rnd(-2, 2));
      s.grav = 0;
      s.fadeIn = true;
    }
  }

  /* Взрыв. Кольцо ударной волны сюда НЕ зашито: его рисуют на местах
     вызова, и два кольца в аддитивном смешивании белят пол-экрана.
     Просят его отдельно — `opts.ground` кладёт волну по грунту.
     `opts.chain` — серия догорающих вторичных взрывов: так гибнет
     большой корабль, у которого рвутся погреба. */
  explosion(pos, size = 10, color = 0xffa050, opts = {}) {
    // Белое ядро держим мелким: в аддитивном режиме несколько
    // белых пятен подряд дают молоко, а не огонь
    this.flash(pos, size * 0.55, 0xffffff, 0.13);
    this.flash(pos, size * 1.5, color, 0.55);
    this.sparks(pos, Math.round(size * 1.1), 0xffe0a0, size * 2.4);
    this.smoke(pos, size * 0.8, 0x3c352c, Math.round(size * 0.35));
    if (opts.debris !== false) {
      this.debris(pos, Math.round(size * 0.5), 0x5b4f40, size * 1.6,
        opts.gravity === undefined ? -42 : opts.gravity);
    }
    if (opts.ground) {
      // Пыль по грунту и волна, лежащая на земле
      this.ringFlat(pos, size * 0.4, size * 3.2, 0x9c7f58, 0.45);
      this.smoke(pos, size * 1.1, 0x4f4437, Math.round(size * 0.4));
    }
    if (opts.chain) {
      for (let i = 0; i < opts.chain; i++) {
        this.delay(rnd(0.15, 1.1), () => {
          const p = pos.clone().add(new THREE.Vector3(rnd(-1, 1), rnd(-1, 1), rnd(-1, 1))
            .multiplyScalar(size * 0.55));
          this.flash(p, size * rnd(0.35, 0.7), 0xffffff, 0.12);
          this.flash(p, size * rnd(0.5, 1.0), color, 0.4);
          this.sparks(p, 5, 0xffd090, size * 1.6, opts.gravity !== 0);
        });
      }
    }
    const n = clamp(Math.round(this._n(size, pos) * (IS_TOUCH ? 0.6 : 0.9)), 2, 14);
    for (let i = 0; i < n; i++) {
      const s = this._sprite();
      s.live = true; s.t = 0; s.life = rnd(0.4, 1.0);
      s.r0 = size * 0.35; s.r1 = size * 0.08;
      s.mesh.visible = true;
      s.mesh.material.color.set(color);
      s.mesh.position.copy(pos);
      s.vel = new THREE.Vector3(rnd(-1, 1), rnd(-1, 1), rnd(-1, 1))
        .normalize().multiplyScalar(size * rnd(0.8, 2.4));
    }
  }

  update(dt) {
    for (const b of this.beams) {
      if (!b.live) continue;
      b.t += dt;
      const k = 1 - b.t / b.life;
      if (k <= 0) { b.live = false; b.mesh.visible = false; b.travel = null; continue; }
      // Летящий снаряд не гаснет и не худеет — он едет
      if (b.travel) {
        const tr = b.travel;
        const s = (1 - k) * tr.dist;
        b.mesh.position.copy(tr.from).addScaledVector(tr.dir, Math.max(0, s - tr.len));
        this._faceBeam(b);
        b.mesh.material.opacity = 1;
        if (b.trail) {
          b.trail.at -= dt;
          if (b.trail.at <= 0) {
            b.trail.at = b.trail.every;
            if (this.trailOk(b.mesh.position)) this.puff(b.mesh.position, 1.1, 0x9a9186, 0.5);
          }
        }
        continue;
      }
      b.mesh.material.opacity = k;
      b.mesh.scale.x = b.w * 2 * (0.35 + k * 0.65);
      this._faceBeam(b);
    }
    let liveSprites = 0;
    for (const s of this.sprites) {
      if (!s.live) continue;
      s.t += dt;
      const k = s.t / s.life;
      if (k >= 1) { s.live = false; s.mesh.visible = false; continue; }
      liveSprites++;
      s.mesh.scale.setScalar(lerp(s.r0, s.r1, k));
      s.mesh.material.opacity = 1 - k * k;
      if (s.vel) {
        s.mesh.position.addScaledVector(s.vel, dt);
        s.vel.multiplyScalar(1 - dt * 2.2);
        if (s.grav) s.vel.y += s.grav * dt;
        // Обломок тянет за собой дым. Клубы берутся из того же пула,
        // поэтому след ничего не стоит сверх уже отведённого бюджета
        if (s.smokeEvery) {
          s.smokeAt -= dt;
          if (s.smokeAt <= 0) {
            s.smokeAt = s.smokeEvery;
            if (this.trailOk(s.mesh.position)) this.puff(s.mesh.position, 0.9, 0x51483c, 0.45);
          }
        }
      }
      // дым не выпрыгивает из ниоткуда, а наплывает
      if (s.fadeIn) s.mesh.material.opacity *= Math.min(1, k * 6);
    }
    this.busy = liveSprites / this.maxSprites;
    for (const r of this.rings || []) {
      if (!r.live) continue;
      r.t += dt;
      const k = r.t / r.life;
      if (k >= 1) { r.live = false; r.mesh.visible = false; continue; }
      r.mesh.scale.setScalar(lerp(r.r0, r.r1, Math.sqrt(k)) * 2);
      r.mesh.material.opacity = (1 - k) * (1 - k);
      // Лежащее кольцо разворачивать к камере нельзя: ударная волна
      // по грунту тут же превратится в нимб, висящий в воздухе
      if (this.camera && !r.flat) r.mesh.quaternion.copy(this.camera.quaternion);
    }
    for (let i = this.timers.length - 1; i >= 0; i--) {
      const tm = this.timers[i];
      tm.t -= dt;
      if (tm.t <= 0) { this.timers.splice(i, 1); tm.fn(); }
    }
    if (this.shake > 0) this.shake = Math.max(0, this.shake - dt * 2);
  }

  // Кольца всегда развёрнуты к зрителю — эффектам нужна камера
  setCamera(cam) { this.camera = cam; }
}

// ─────────────────────────────────────────────────────────────
// МЕЛОЧИ ДЛЯ СЦЕН
// ─────────────────────────────────────────────────────────────

/* ── МИНИКАРТА.
   Одна на все слои: и бой на орбите, и наземная операция рисуют в неё
   одинаково — точки по позициям и рамка обзора. Рисуем на канве, а не
   вторым рендером сцены: второй проход стоит кадров, а нужна нам
   схема, а не картинка.

   Перерисовываем не каждый кадр: на планшете это заметная доля
   времени кадра, а на глаз десять раз в секунду неотличимо. */
export function createMinimap(root, extent, opts = {}) {
  const box = document.createElement('div');
  box.className = 'minimap';
  const cv = document.createElement('canvas');
  const S = opts.size || (IS_TOUCH ? 132 : 168);
  cv.width = cv.height = S * 2;            // ретина: рисуем вдвое крупнее
  cv.style.width = cv.style.height = S + 'px';
  box.appendChild(cv);
  root.appendChild(box);
  const ctx = cv.getContext('2d');
  let acc = 0;

  const toMap = (x, z) => [
    (x / extent * 0.5 + 0.5) * cv.width,
    (z / extent * 0.5 + 0.5) * cv.height,
  ];

  /* Мышью по миникарте — как в любой RTS (C73): ЛКМ переносит камеру,
     протяжка ведёт её за курсором (указатель захвачен — можно уехать
     за край карты и не потерять ведение), ПКМ отдаёт приказ в точку.
     Меню браузера по ПКМ здесь не всплывает. opts.onGo(x, z),
     opts.onOrder(x, z) — в игровых координатах. */
  const toWorld = ev => {
    const r = cv.getBoundingClientRect();
    return {
      x: clamp((ev.clientX - r.left) / r.width - 0.5, -0.5, 0.5) * 2 * extent,
      z: clamp((ev.clientY - r.top) / r.height - 0.5, -0.5, 0.5) * 2 * extent,
    };
  };
  let dragId = null;
  box.addEventListener('contextmenu', e => e.preventDefault());
  box.addEventListener('pointerdown', ev => {
    ev.preventDefault();
    const w = toWorld(ev);
    if (ev.pointerType === 'mouse' && ev.button === 2) { if (opts.onOrder) opts.onOrder(w.x, w.z); return; }
    if (ev.pointerType === 'mouse' && ev.button !== 0) return;
    dragId = ev.pointerId;
    try { box.setPointerCapture(ev.pointerId); } catch (_) { /* и ладно */ }
    if (opts.onGo) opts.onGo(w.x, w.z);
  });
  box.addEventListener('pointermove', ev => {
    if (dragId !== ev.pointerId) return;
    const w = toWorld(ev);
    if (opts.onGo) opts.onGo(w.x, w.z);
  });
  const end = ev => { if (dragId === ev.pointerId) dragId = null; };
  box.addEventListener('pointerup', end);
  box.addEventListener('pointercancel', end);

  return {
    el: box,
    /* dots — [{x, z, color, r}], view — область обзора: {pts: [[x, z]×4]}
       (трапеция углов экрана, см. Controls.viewQuad) или {x, z, r}.
       view можно отдать функцией — посчитается только при перерисовке.
       Всё в игровых координатах, пересчёт здесь. */
    draw(dt, dots, view) {
      acc += dt;
      if (acc < 0.1) return;
      acc = 0;
      if (typeof dots === 'function') dots = dots();
      if (typeof view === 'function') view = view();
      ctx.clearRect(0, 0, cv.width, cv.height);
      ctx.fillStyle = opts.bg || 'rgba(6,10,17,0.72)';
      ctx.fillRect(0, 0, cv.width, cv.height);

      for (const d of dots) {
        const [px, py] = toMap(d.x, d.z);
        ctx.fillStyle = d.color;
        const r = (d.r || 2) * 2;
        ctx.fillRect(px - r / 2, py - r / 2, r, r);
      }
      if (view) {
        ctx.strokeStyle = 'rgba(230,240,250,0.65)';
        ctx.lineWidth = 2;
        if (view.pts) {
          ctx.beginPath();
          view.pts.forEach(([x, z], i) => {
            const [px, py] = toMap(x, z);
            if (i) ctx.lineTo(px, py); else ctx.moveTo(px, py);
          });
          ctx.closePath();
          ctx.stroke();
        } else {
          const [vx, vy] = toMap(view.x, view.z);
          const vr = view.r / extent * 0.5 * cv.width;
          ctx.strokeRect(vx - vr, vy - vr, vr * 2, vr * 2);
        }
      }
    },
    dispose() { box.remove(); },
  };
}

export function starfield(count = 2600, radius = 4000) {
  const n = IS_TOUCH ? Math.round(count * 0.6) : count;
  const pos = new Float32Array(n * 3);
  const col = new Float32Array(n * 3);
  const c = new THREE.Color();
  /* Треть звёзд сбиваем в полосу — «млечный путь». Равномерная
     россыпь по сфере читается сеткой из точек и выдаёт процедуру;
     у неоднородного неба сразу появляется глубина. Полоса наклонена,
     чтобы не совпадать с плоскостью боя. */
  const tilt = 0.38, ct = Math.cos(tilt), st = Math.sin(tilt);
  for (let i = 0; i < n; i++) {
    const inBand = i % 3 === 0;
    let u = Math.random() * 2 - 1;
    if (inBand) u = (Math.random() + Math.random() + Math.random() - 1.5) * 0.22;
    const a = Math.random() * TAU;
    const r = radius * (0.7 + Math.random() * 0.3);
    const s = Math.sqrt(Math.max(0, 1 - u * u));
    const x = Math.cos(a) * s * r, y = u * r, z = Math.sin(a) * s * r;
    pos[i * 3] = x;
    pos[i * 3 + 1] = y * ct - z * st;
    pos[i * 3 + 2] = y * st + z * ct;
    const t = Math.random();
    // в полосе звёзды мельче и холоднее — это пыль, а не светила
    c.setHSL(t < 0.7 ? 0.58 : 0.09, inBand ? 0.22 : 0.35,
             inBand ? 0.42 + Math.random() * 0.3 : 0.55 + Math.random() * 0.45);
    col[i * 3] = c.r; col[i * 3 + 1] = c.g; col[i * 3 + 2] = c.b;
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  g.setAttribute('color', new THREE.BufferAttribute(col, 3));
  // Точки обязательно с круглой текстурой и скромного размера: без карты
  // они рисуются квадратами, а свечение раздувает их в белые кубики.
  const m = new THREE.PointsMaterial({
    size: radius * 0.0016, vertexColors: true, sizeAttenuation: true,
    map: GLOW_TEX, alphaTest: 0.02,
    transparent: true, opacity: 0.55, depthWrite: false, toneMapped: true,
    blending: THREE.AdditiveBlending,
  });
  const p = new THREE.Points(g, m);
  p.frustumCulled = false;
  return p;
}

/* Кольцо выделения. Раньше это была `RingGeometry` — сорок отрезков
   с резким краем, и именно она оставалась единственным местом
   в кадре с настоящей лесенкой: тонкая яркая линия под наклонной
   камерой рвётся на ступеньки, а свечение их подчёркивает.
   Теперь плоскость с той же мягкой картой обода, что у ударных волн. */
export function ringMesh(radius, color, opacity = 0.9, thickness = 0.12) {
  /* Плоскость делаем размером 2×2, чтобы масштаб меша по-прежнему
     означал РАДИУС кольца: места вызова задают его через
     `scale.setScalar`, и менять их семантику ради формы нельзя. */
  const g = RING_GEO.clone();
  g.scale(2, 2, 1);
  g.rotateX(-Math.PI / 2);
  g.userData.shared = false;
  const m = new THREE.MeshBasicMaterial({
    map: RING_TEX, color, transparent: true, opacity, side: THREE.DoubleSide,
    depthWrite: false, toneMapped: false,
  });
  const mesh = new THREE.Mesh(g, m);
  mesh.scale.setScalar(radius);
  return mesh;
}

export function disposeScene(scene) {
  scene.traverse(o => {
    if (o.geometry && o.geometry.dispose && !o.geometry.userData.shared) o.geometry.dispose();
    if (o.material) {
      const mats = Array.isArray(o.material) ? o.material : [o.material];
      for (const m of mats) if (m && m.dispose && !m.userData.shared) m.dispose();
    }
  });
}
