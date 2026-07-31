/* Движок: всё, что общее для трёх экранов (галактика, космос, земля).
   Рендерер, тактическая камера, единое управление для пальцев и мыши,
   пул эффектов (лучи, трассеры, взрывы) и мелкая математика.

   Управление сделано «планшет в первую очередь»:
     палец: тянуть по пустому — двигать карту, щипок — приближение,
            два пальца — облёт, короткое касание — выбрать/приказать,
            долгое нажатие и потянуть — рамка выделения;
     мышь:  ЛКМ-рамка, ПКМ — приказ, колесо — приближение,
            средняя кнопка или Alt — облёт, WASD — двигать карту. */

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
    this.composer = new EffectComposer(this.renderer);
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
    this.keys = new Set();
    this.smooth = new THREE.Vector3().copy(this.target);
    this._onKeyDown = e => {
      if (e.target && /input|textarea|select/i.test(e.target.tagName)) return;
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

  update(dt) {
    const k = this.keys;
    let fx = 0, fz = 0;
    if (k.has('KeyW') || k.has('ArrowUp')) fz -= 1;
    if (k.has('KeyS') || k.has('ArrowDown')) fz += 1;
    if (k.has('KeyA') || k.has('ArrowLeft')) fx -= 1;
    if (k.has('KeyD') || k.has('ArrowRight')) fx += 1;
    if (k.has('KeyQ')) this.yaw += dt * 1.3;
    if (k.has('KeyE')) this.yaw -= dt * 1.3;
    if (this.allowY) {
      if (k.has('KeyR')) this.target.y += this.dist * 0.5 * dt;
      if (k.has('KeyF')) this.target.y -= this.dist * 0.5 * dt;
    }
    if (fx || fz) {
      const speed = this.dist * 0.8 * dt;
      const s = Math.sin(this.yaw), c = Math.cos(this.yaw);
      this.target.x += (fx * c - fz * s) * speed;
      this.target.z += (fx * s + fz * c) * speed;
    }
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
    const cp = Math.cos(this.pitch), sp = Math.sin(this.pitch);
    this.cam.position.set(
      this.smooth.x + Math.sin(this.yaw) * cp * this.dist,
      this.smooth.y + sp * this.dist,
      this.smooth.z + Math.cos(this.yaw) * cp * this.dist,
    );
    this.cam.lookAt(this.smooth);
  }
}

// ─────────────────────────────────────────────────────────────
// УПРАВЛЕНИЕ: пальцы и мышь в одном месте
//
// handlers:
//   onTap(worldPoint, entity, opts)  — короткое касание / клик
//   onBox(rect, additive)            — рамка выделения
//   onOrder(worldPoint, entity, opts)— ПКМ на мыши (на планшете приказы
//                                      идут через onTap с флагом order)
//   pickMeshes()                     — что можно ткнуть
//   planeY()                         — высота плоскости для приказов
//   hasSelection()                   — есть ли выделение (решает,
//                                      касание — это приказ или выбор)
// ─────────────────────────────────────────────────────────────

const LONG_PRESS_MS = 420;
const TAP_SLOP = 12;

export class Controls {
  constructor(dom, tcam, handlers = {}) {
    this.dom = dom;
    this.tcam = tcam;
    this.h = handlers;
    this.enabled = true;
    this.ray = new THREE.Raycaster();
    this.ndc = new THREE.Vector2();
    this.pointers = new Map();
    this.mode = null;        // 'pan' | 'box' | 'orbit' | 'pinch' | null
    this.boxMode = false;    // принудительная рамка (кнопка на панели)
    this.plane = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0);

    this.boxEl = document.createElement('div');
    this.boxEl.className = 'select-box';
    this.boxEl.style.display = 'none';
    dom.parentElement.appendChild(this.boxEl);

    this._bind();
  }

  dispose() {
    this.boxEl.remove();
    for (const [k, v] of this._listeners) this.dom.removeEventListener(k, v);
    removeEventListener('pointerup', this._up);
    removeEventListener('pointercancel', this._up);
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

  pick(x, y) {
    const meshes = this.h.pickMeshes ? this.h.pickMeshes() : [];
    if (!meshes.length) return null;
    this.ray.setFromCamera(this._ndc(x, y), this.tcam.cam);
    // На пальце цельтесь щедрее: маленькие корабли иначе не поймать
    this.ray.params.Points.threshold = 6;
    const hits = this.ray.intersectObjects(meshes, true);
    for (const hit of hits) {
      let o = hit.object;
      while (o && !o.userData.entity) o = o.parent;
      if (o && o.userData.entity && !o.userData.entity.dead) return o.userData.entity;
    }
    return null;
  }

  // Ближайшая к точке экрана сущность — запасной способ прицеливания
  // пальцем, когда луч прошёл мимо мелкой модели.
  pickNear(x, y, list, camera, w, h, radiusPx) {
    const r = this.dom.getBoundingClientRect();
    const px = x - r.left, py = y - r.top;
    let best = null, bd = radiusPx * radiusPx;
    for (const e of list) {
      if (e.dead) continue;
      const p = screenOf(e.pos, camera, w, h);
      if (p.z > 1) continue;
      const d = (p.x - px) ** 2 + (p.y - py) ** 2;
      if (d < bd) { bd = d; best = e; }
    }
    return best;
  }

  // ── события ────────────────────────────────────────────
  _bind() {
    const d = this.dom;
    this._listeners = [];
    const on = (name, fn, opts) => { d.addEventListener(name, fn, opts); this._listeners.push([name, fn]); };

    on('contextmenu', e => e.preventDefault());
    on('wheel', e => {
      e.preventDefault();
      this.tcam.zoom(Math.exp(e.deltaY * 0.0012));
    }, { passive: false });

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
        if (e.button === 2) {                       // ПКМ — приказ
          this._emitOrder(e);
          this.mode = null;
        } else if (e.button === 1 || e.altKey) {
          this.mode = 'orbit';
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
      const p = this.pointers.get(e.pointerId);
      if (!p) return;
      const prevX = p.x, prevY = p.y;
      p.x = e.clientX; p.y = e.clientY;
      if (Math.abs(p.x - p.x0) > TAP_SLOP || Math.abs(p.y - p.y0) > TAP_SLOP) {
        if (!p.moved) { p.moved = true; this._clearLongPress(); }
      }
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

      if (this.mode === 'orbit') {
        this.tcam.orbit((p.x - prevX) * 0.005, (p.y - prevY) * 0.005);
        return;
      }

      if (this.mode === 'maybe-pan' || this.mode === 'pan') {
        this.mode = 'pan';
        // «схватить мир»: держим точку под пальцем
        const now = this.worldAt(p.x, p.y);
        if (now && this._panAnchor) {
          this.tcam.target.copy(this._panStart).add(this._panAnchor).sub(now);
          this.tcam.clampTarget();
          // якорь пересчитываем от новой позиции камеры
          this.tcam.apply(0.016, true);
          const re = this.worldAt(p.x, p.y);
          if (re) this._panAnchor = re;
          this._panStart = this.tcam.target.clone();
        }
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

      if (this.mode === 'box' && (p.moved || this._boxOrigin)) {
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

      if (!p.moved && dur < 500 && (p.type !== 'mouse' || p.button === 0)) {
        this._emitTap(p, e.shiftKey);
      }
      if (!this.pointers.size) this.mode = null;
      else if (this.pointers.size === 1) this.mode = 'maybe-pan';
    };
    addEventListener('pointerup', this._up);
    addEventListener('pointercancel', this._up);
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
    const ent = this.pick(p.x, p.y);
    const world = this.worldAt(p.x, p.y);
    this.h.onTap && this.h.onTap({ x: p.x, y: p.y, entity: ent, world, shift, touch: p.type !== 'mouse' });
  }

  _emitOrder(e) {
    const ent = this.pick(e.clientX, e.clientY);
    const world = this.worldAt(e.clientX, e.clientY);
    this.h.onOrder && this.h.onOrder({ x: e.clientX, y: e.clientY, entity: ent, world, shift: e.shiftKey });
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

const BEAM_GEO = new THREE.CylinderGeometry(1, 1, 1, 6, 1, true);
BEAM_GEO.translate(0, 0.5, 0);
const RING_GEO = new THREE.RingGeometry(0.82, 1, 44);

function glowTexture() {
  const c = document.createElement('canvas');
  c.width = c.height = 64;
  const g = c.getContext('2d');
  const grad = g.createRadialGradient(32, 32, 0, 32, 32, 32);
  grad.addColorStop(0, 'rgba(255,255,255,1)');
  grad.addColorStop(0.25, 'rgba(255,240,210,0.85)');
  grad.addColorStop(0.6, 'rgba(255,160,80,0.30)');
  grad.addColorStop(1, 'rgba(255,120,40,0)');
  g.fillStyle = grad;
  g.fillRect(0, 0, 64, 64);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}
export const GLOW_TEX = glowTexture();

export class Fx {
  constructor(scene, budget = {}) {
    this.scene = scene;
    this.beams = [];
    this.sprites = [];
    this.rings = [];
    this.camera = null;
    this.maxBeams = budget.beams || (IS_TOUCH ? 90 : 160);
    this.maxSprites = budget.sprites || (IS_TOUCH ? 160 : 300);
    this.group = new THREE.Group();
    this.group.frustumCulled = false;
    scene.add(this.group);
    this.shake = 0;
  }

  _beam() {
    for (const b of this.beams) if (!b.live) return b;
    if (this.beams.length >= this.maxBeams) return this.beams[(Math.random() * this.beams.length) | 0];
    const m = new THREE.Mesh(BEAM_GEO, new THREE.MeshBasicMaterial({
      color: 0xffffff, transparent: true, opacity: 1, blending: THREE.AdditiveBlending,
      depthWrite: false, toneMapped: false,
    }));
    m.visible = false;
    m.frustumCulled = false;
    const b = { mesh: m, live: false, t: 0, life: 1, w: 1 };
    this.beams.push(b);
    this.group.add(m);
    return b;
  }

  _sprite() {
    for (const s of this.sprites) if (!s.live) return s;
    if (this.sprites.length >= this.maxSprites) return this.sprites[(Math.random() * this.sprites.length) | 0];
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

  beam(from, to, opts = {}) {
    const b = this._beam();
    b.live = true; b.t = 0; b.life = opts.life ?? 0.35;
    b.w = opts.width ?? 1.6;
    b.mesh.visible = true;
    b.mesh.material.color.set(opts.color ?? 0xff9d5c);
    b.mesh.material.opacity = 1;
    const dir = new THREE.Vector3().subVectors(to, from);
    const len = dir.length() || 0.001;
    b.mesh.position.copy(from);
    b.mesh.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), dir.normalize());
    b.mesh.scale.set(b.w, len, b.w);
    return b;
  }

  tracer(from, to, color = 0xffe08a, life = 0.12, width = 0.28) {
    return this.beam(from, to, { color, life, width });
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
    s.live = true; s.t = 0; s.life = life;
    s.r0 = r0; s.r1 = r1;
    s.mesh.visible = true;
    s.mesh.material.color.set(color);
    s.mesh.material.opacity = 1;
    s.mesh.position.copy(pos);
    s.mesh.scale.setScalar(r0);
    return s;
  }

  _ringObj() {
    if (!this.rings) this.rings = [];
    for (const r of this.rings) if (!r.live) return r;
    if (this.rings.length >= (IS_TOUCH ? 14 : 26)) return this.rings[0];
    const geo = RING_GEO;
    const m = new THREE.Mesh(geo, new THREE.MeshBasicMaterial({
      color: 0xffffff, transparent: true, opacity: 1, side: THREE.DoubleSide,
      blending: THREE.AdditiveBlending, depthWrite: false, toneMapped: false,
    }));
    m.visible = false;
    m.frustumCulled = false;
    const r = { mesh: m, live: false, t: 0, life: 1, r0: 1, r1: 2 };
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

  explosion(pos, size = 10, color = 0xffa050) {
    this.flash(pos, size, 0xffffff, 0.16);
    this.flash(pos, size * 1.5, color, 0.55);
    const n = clamp(Math.round(size * (IS_TOUCH ? 0.6 : 0.9)), 3, 14);
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
      if (k <= 0) { b.live = false; b.mesh.visible = false; continue; }
      b.mesh.material.opacity = k;
      b.mesh.scale.x = b.mesh.scale.z = b.w * (0.35 + k * 0.65);
    }
    for (const s of this.sprites) {
      if (!s.live) continue;
      s.t += dt;
      const k = s.t / s.life;
      if (k >= 1) { s.live = false; s.mesh.visible = false; continue; }
      s.mesh.scale.setScalar(lerp(s.r0, s.r1, k));
      s.mesh.material.opacity = 1 - k * k;
      if (s.vel) {
        s.mesh.position.addScaledVector(s.vel, dt);
        s.vel.multiplyScalar(1 - dt * 2.2);
      }
    }
    for (const r of this.rings || []) {
      if (!r.live) continue;
      r.t += dt;
      const k = r.t / r.life;
      if (k >= 1) { r.live = false; r.mesh.visible = false; continue; }
      r.mesh.scale.setScalar(lerp(r.r0, r.r1, Math.sqrt(k)));
      r.mesh.material.opacity = (1 - k) * (1 - k);
      if (this.camera) r.mesh.quaternion.copy(this.camera.quaternion);
    }
    if (this.shake > 0) this.shake = Math.max(0, this.shake - dt * 2);
  }

  // Кольца всегда развёрнуты к зрителю — эффектам нужна камера
  setCamera(cam) { this.camera = cam; }
}

// ─────────────────────────────────────────────────────────────
// МЕЛОЧИ ДЛЯ СЦЕН
// ─────────────────────────────────────────────────────────────

export function starfield(count = 2600, radius = 4000) {
  const n = IS_TOUCH ? Math.round(count * 0.6) : count;
  const pos = new Float32Array(n * 3);
  const col = new Float32Array(n * 3);
  const c = new THREE.Color();
  for (let i = 0; i < n; i++) {
    const u = Math.random() * 2 - 1, a = Math.random() * TAU;
    const r = radius * (0.7 + Math.random() * 0.3);
    const s = Math.sqrt(1 - u * u);
    pos[i * 3] = Math.cos(a) * s * r;
    pos[i * 3 + 1] = u * r;
    pos[i * 3 + 2] = Math.sin(a) * s * r;
    const t = Math.random();
    c.setHSL(t < 0.7 ? 0.58 : 0.09, 0.35, 0.55 + Math.random() * 0.45);
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

export function ringMesh(radius, color, opacity = 0.9, thickness = 0.12) {
  const g = new THREE.RingGeometry(radius * (1 - thickness), radius, 40);
  g.rotateX(-Math.PI / 2);
  const m = new THREE.MeshBasicMaterial({
    color, transparent: true, opacity, side: THREE.DoubleSide,
    depthWrite: false, toneMapped: false,
  });
  return new THREE.Mesh(g, m);
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
