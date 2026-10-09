/* ЗВУК — синтезом через Web Audio, без единого файла (C54).

   В игре не было звука вообще: ни отклика на приказ, ни выстрела, ни
   взрыва, и атаку за кадром было легко пропустить — бой ощущался
   мёртвым. Файлы звуков (CC0-наборы) — работа для движка: при переезде
   на Godot их и возьмём. Здесь — то, без чего не понять, интересен ли
   бой: каждый звук собирается из генераторов и шума за доли
   миллисекунды, весит ноль байт и не требует сети.

   Правила, без которых синтез превращается в кашу:
   — AudioContext заводится по ПЕРВОМУ жесту игрока (нажатие, клавиша):
     до жеста браузер его не запустит, а созданный раньше висит
     «на паузе» молча;
   — голосов одновременно не больше VOICE_MAX, а у частых звуков
     (зенитки, пушки авиации) свой минимальный промежуток: сотня очередей
     ПВО в секунду — это треск, а не бой;
   — громкость падает с расстоянием до камеры, сторона — по положению
     на экране: взрыв слева слышен слева;
   — тревоги и подтверждения — без расстояния: это голос интерфейса. */

import { prefs, setPref } from './engine.js';

const VOICE_MAX = 14;
// Минимальный промежуток (с) между звуками одного рода — от треска
const GAP = { pd: 0.07, gun: 0.06, light: 0.05, hit: 0.04, pop: 0.05, missile: 0.08, laser: 0.03 };
// Сколько звуков одного рода звучит разом
const KIND_MAX = { pd: 2, gun: 2, light: 3, hit: 3, pop: 3, missile: 3, laser: 4, boom: 4 };

try {
  const v = localStorage.getItem('capella_vol');
  prefs.vol = v === null ? 70 : Math.max(0, Math.min(100, +v || 0));
  prefs.mute = localStorage.getItem('capella_mute') === '1';
} catch (e) { prefs.vol = 70; prefs.mute = false; }

let ac = null, master = null, noiseBuf = null;
let voices = 0;
const lastAt = {}, live = {};
let listener = null;      // {cam} — камера, от которой меряется расстояние

function start() {
  if (ac) { if (ac.state === 'suspended') ac.resume().catch(() => {}); return; }
  const AC = window.AudioContext || window.webkitAudioContext;
  if (!AC) return;
  try { ac = new AC(); } catch (e) { ac = null; return; }
  master = ac.createGain();
  master.gain.value = level();
  // Мягкий ограничитель: несколько взрывов разом не должны хрипеть
  const comp = ac.createDynamicsCompressor();
  comp.threshold.value = -14; comp.knee.value = 8; comp.ratio.value = 6;
  comp.attack.value = 0.004; comp.release.value = 0.2;
  master.connect(comp).connect(ac.destination);
  // Секунда белого шума — из неё режутся выстрелы, взрывы и гипер
  noiseBuf = ac.createBuffer(1, ac.sampleRate, ac.sampleRate);
  const d = noiseBuf.getChannelData(0);
  for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
}
const level = () => (prefs.mute ? 0 : Math.pow((prefs.vol || 0) / 100, 1.6) * 0.9);

/* Первый жест игрока — заводим звук. Слушаем в перехвате: панели боя
   гасят всплытие, а нажатие по ним — тоже жест */
for (const ev of ['pointerdown', 'keydown']) addEventListener(ev, start, { capture: true, passive: true });

export const sound = {
  get on() { return !!ac && !prefs.mute && prefs.vol > 0; },
  get muted() { return !!prefs.mute; },
  get volume() { return prefs.vol; },
  setVolume(v) {
    setPref('vol', Math.max(0, Math.min(100, Math.round(v))));
    if (master) master.gain.setTargetAtTime(level(), ac.currentTime, 0.03);
  },
  setMuted(m) {
    setPref('mute', !!m);
    if (master) master.gain.setTargetAtTime(level(), ac.currentTime, 0.03);
  },
  toggleMute() { this.setMuted(!prefs.mute); return prefs.mute; },
  // Камера экрана: от неё громкость и сторона
  setListener(cam) { listener = cam ? { cam } : null; },
  /* Звук в точке мира: kind — род (laser, missile, light, pd, gun, hit,
     pop, boom, hyper, hyperIn), size — крупность (взрыв корабля) */
  at(kind, pos, size = 1) {
    if (!this.on || !listener) return;
    const cam = listener.cam;
    const dx = pos.x - cam.position.x, dy = pos.y - cam.position.y, dz = pos.z - cam.position.z;
    const d = Math.sqrt(dx * dx + dy * dy + dz * dz);
    const ref = kind === 'boom' ? 900 : kind === 'laser' || kind === 'hyper' || kind === 'hyperIn' ? 700 : 420;
    const g = 1 / (1 + (d / ref) * (d / ref));
    if (g < 0.04) return;
    // сторона: проекция на правый вектор камеры
    const e = cam.matrixWorld.elements;
    const pan = d > 1 ? Math.max(-0.85, Math.min(0.85, (dx * e[0] + dy * e[1] + dz * e[2]) / d)) : 0;
    play(kind, g, pan, size);
  },
  // Голос интерфейса: order, select, alarm, lost, warn, deny
  ui(kind) { if (this.on) play(kind, 1, 0, 1); },
  // Для стенда: что играло (род → число)
  stats: {},
};
if (typeof window !== 'undefined') window.__sound = sound;

function play(kind, gain, pan, size) {
  const t = ac.currentTime;
  if (GAP[kind] && t - (lastAt[kind] || -9) < GAP[kind]) return;
  if ((live[kind] || 0) >= (KIND_MAX[kind] || 2)) return;
  if (voices >= VOICE_MAX && !/alarm|lost|order|warn/.test(kind)) return;
  const R = RECIPES[kind];
  if (!R) return;
  lastAt[kind] = t;
  live[kind] = (live[kind] || 0) + 1;
  voices++;
  sound.stats[kind] = (sound.stats[kind] || 0) + 1;
  const out = ac.createGain();
  out.gain.value = gain;
  let node = out;
  if (pan && ac.createStereoPanner) {
    const p = ac.createStereoPanner();
    p.pan.value = pan;
    out.connect(p);
    node = p;
  }
  node.connect(master);
  const len = R(out, t, size);
  setTimeout(() => {
    voices--; live[kind]--;
    try { node.disconnect(); out.disconnect(); } catch (e) { /* уже */ }
  }, (len + 0.1) * 1000);
}

// ── Кирпичики ──────────────────────────────────────────────────
function env(g, t, a, peak, dur) {
  g.gain.setValueAtTime(0.0001, t);
  g.gain.exponentialRampToValueAtTime(peak, t + a);
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
}
function osc(out, t, type, f0, f1, dur, peak, a = 0.005) {
  const o = ac.createOscillator(), g = ac.createGain();
  o.type = type;
  o.frequency.setValueAtTime(f0, t);
  if (f1 !== f0) o.frequency.exponentialRampToValueAtTime(Math.max(20, f1), t + dur);
  env(g, t, a, peak, dur);
  o.connect(g).connect(out);
  o.start(t); o.stop(t + dur + 0.02);
}
function noise(out, t, dur, peak, type, f0, f1 = f0, q = 0.8, a = 0.003) {
  const s = ac.createBufferSource(), f = ac.createBiquadFilter(), g = ac.createGain();
  s.buffer = noiseBuf;
  s.playbackRate.value = 0.8 + Math.random() * 0.4;
  f.type = type; f.Q.value = q;
  f.frequency.setValueAtTime(f0, t);
  if (f1 !== f0) f.frequency.exponentialRampToValueAtTime(Math.max(30, f1), t + dur);
  env(g, t, a, peak, dur);
  s.connect(f).connect(g).connect(out);
  s.start(t, Math.random() * 0.5); s.stop(t + dur + 0.02);
}

// ── Рецепты: каждый возвращает длительность в секундах ─────────
const RECIPES = {
  // Подтверждение приказа: два коротких сигнала вверх
  order(out, t) { osc(out, t, 'sine', 660, 660, 0.07, 0.16); osc(out, t + 0.075, 'sine', 990, 990, 0.09, 0.14); return 0.18; },
  select(out, t) { osc(out, t, 'sine', 520, 560, 0.06, 0.1); return 0.07; },
  deny(out, t) { osc(out, t, 'square', 220, 180, 0.12, 0.06); return 0.13; },
  // Главный калибр: тяжёлый луч — пила с падающей нотой и глухой удар
  laser(out, t, s) {
    osc(out, t, 'sawtooth', 1400, 90, 0.42, 0.22);
    osc(out, t, 'sine', 180, 45, 0.5, 0.35, 0.002);
    noise(out, t, 0.3, 0.25, 'lowpass', 2400, 300);
    return 0.52;
  },
  // Ракетный пуск: шипящий свист вверх
  missile(out, t) { noise(out, t, 0.45, 0.22, 'bandpass', 500, 2600, 1.4, 0.02); return 0.46; },
  // Орудия эскорта: короткий сухой хлопок
  light(out, t) { osc(out, t, 'square', 420, 140, 0.09, 0.12); noise(out, t, 0.07, 0.14, 'highpass', 1800); return 0.1; },
  // Зенитки и пушки авиации — щелчок
  pd(out, t) { noise(out, t, 0.035, 0.1, 'highpass', 3200); return 0.04; },
  gun(out, t) { noise(out, t, 0.03, 0.08, 'bandpass', 2600, 2600, 2); return 0.035; },
  // Попадание по броне
  hit(out, t) { noise(out, t, 0.16, 0.3, 'lowpass', 1800, 260); osc(out, t, 'triangle', 140, 70, 0.12, 0.15); return 0.17; },
  // Гибель машины или ракеты
  pop(out, t) { noise(out, t, 0.25, 0.22, 'lowpass', 1400, 200); return 0.26; },
  // Гибель корабля: раскат, крупнее — дольше и ниже
  boom(out, t, s) {
    const k = Math.max(0.6, Math.min(2.2, s));
    noise(out, t, 0.9 * k, 0.55, 'lowpass', 1600, 60, 0.6, 0.004);
    osc(out, t, 'sine', 90 / Math.sqrt(k), 28, 0.8 * k, 0.5, 0.004);
    noise(out, t + 0.12 * k, 0.6 * k, 0.25, 'bandpass', 700, 120, 0.9);
    return 1.0 * k + 0.15;
  },
  // Уход в гипер: нарастающий свист; выход — наоборот
  hyper(out, t) { osc(out, t, 'sine', 160, 1800, 1.1, 0.16, 0.6); noise(out, t + 0.6, 0.6, 0.18, 'bandpass', 600, 4000, 1.2, 0.3); return 1.25; },
  hyperIn(out, t) { osc(out, t, 'sine', 1600, 140, 0.8, 0.18, 0.01); noise(out, t, 0.5, 0.2, 'bandpass', 3500, 400, 1.2, 0.01); return 0.85; },
  // Тревоги — голос интерфейса
  alarm(out, t) { for (let i = 0; i < 2; i++) { osc(out, t + i * 0.22, 'square', 740, 740, 0.1, 0.07); osc(out, t + i * 0.22 + 0.11, 'square', 520, 520, 0.1, 0.07); } return 0.46; },
  lost(out, t) { osc(out, t, 'triangle', 560, 180, 0.55, 0.2, 0.01); osc(out, t + 0.06, 'square', 280, 90, 0.5, 0.05, 0.01); return 0.6; },
  warn(out, t) { for (let i = 0; i < 3; i++) osc(out, t + i * 0.18, 'sawtooth', 880, 620, 0.14, 0.06); return 0.56; },
};
