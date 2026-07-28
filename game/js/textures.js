/* Процедурные текстуры: планеты, облака, ночные огни, туманность.

   Всё рисуется один раз на canvas и кладётся в кэш: биомов пять,
   планет на карте четырнадцать, но текстур всё равно будет пять.
   Никаких внешних картинок — игра остаётся самодостаточной. */

import { THREE, IS_TOUCH } from './engine.js';
import { Noise } from './noise.js';

const cache = new Map();

// Палитры высот: от глубин к вершинам. stop — доля высоты 0..1
const PALETTES = {
  green: {
    sea: 0.46,
    ramp: [
      [0.00, [10, 30, 58]], [0.30, [18, 62, 92]], [0.45, [40, 104, 130]],
      [0.47, [186, 170, 120]], [0.52, [78, 116, 66]], [0.68, [48, 84, 52]],
      [0.80, [96, 88, 70]], [0.92, [140, 134, 124]], [1.00, [236, 242, 246]],
    ],
    cloud: 0.55, lights: false, atmo: 0x8fc4ff, atmoPower: 0.16,
  },
  desert: {
    sea: 0.30,
    ramp: [
      [0.00, [92, 68, 40]], [0.30, [140, 106, 62]], [0.48, [198, 162, 100]],
      [0.62, [214, 184, 126]], [0.76, [166, 126, 74]], [0.88, [122, 92, 56]],
      [1.00, [224, 214, 188]],
    ],
    cloud: 0.78, lights: false, atmo: 0xffcf90, atmoPower: 0.13,
  },
  ice: {
    sea: 0.40,
    ramp: [
      [0.00, [26, 52, 74]], [0.36, [58, 96, 122]], [0.42, [122, 158, 182]],
      [0.52, [186, 212, 230]], [0.70, [214, 232, 242]], [0.86, [232, 244, 250]],
      [1.00, [252, 254, 255]],
    ],
    cloud: 0.50, lights: false, atmo: 0x9fd0ff, atmoPower: 0.20,
  },
  rock: {
    sea: -1,
    ramp: [
      [0.00, [46, 38, 32]], [0.28, [74, 62, 52]], [0.48, [104, 88, 72]],
      [0.66, [134, 114, 92]], [0.82, [96, 82, 68]], [1.00, [162, 148, 128]],
    ],
    cloud: 0.95, lights: false, atmo: 0x9a8f80, atmoPower: 0.07,
  },
  city: {
    sea: 0.44,
    ramp: [
      [0.00, [12, 28, 48]], [0.30, [22, 56, 82]], [0.43, [44, 92, 112]],
      [0.46, [96, 96, 92]], [0.56, [82, 86, 88]], [0.70, [104, 106, 104]],
      [0.84, [126, 124, 120]], [1.00, [206, 208, 210]],
    ],
    cloud: 0.66, lights: true, atmo: 0x9fb8ff, atmoPower: 0.18,
  },
};

function rampColor(ramp, t) {
  for (let i = 1; i < ramp.length; i++) {
    if (t <= ramp[i][0]) {
      const [a, ca] = ramp[i - 1], [b, cb] = ramp[i];
      const k = (t - a) / Math.max(1e-6, b - a);
      return [
        ca[0] + (cb[0] - ca[0]) * k,
        ca[1] + (cb[1] - ca[1]) * k,
        ca[2] + (cb[2] - ca[2]) * k,
      ];
    }
  }
  return ramp[ramp.length - 1][1];
}

function canvasTexture(canvas, srgb = true) {
  const t = new THREE.CanvasTexture(canvas);
  if (srgb) t.colorSpace = THREE.SRGBColorSpace;
  t.wrapS = THREE.RepeatWrapping;
  t.wrapT = THREE.ClampToEdgeWrapping;
  t.anisotropy = 4;
  t.needsUpdate = true;
  return t;
}

/* Набор карт для планеты: цвет, нормали, облака, ночные огни.
   Считается на равнопрямоугольной развёртке: для каждого пикселя
   берём точку на сфере и щупаем в ней трёхмерный шум — тогда
   не будет ни шва по долготе, ни каши на полюсах. */
export function planetTextures(biome, seed = 1) {
  const key = `${biome}|${seed}`;
  if (cache.has(key)) return cache.get(key);

  const P = PALETTES[biome] || PALETTES.rock;
  const W = IS_TOUCH ? 640 : 1024;
  const H = W / 2;
  const oct = IS_TOUCH ? 5 : 6;

  const land = new Noise(seed);
  const detail = new Noise(seed + 7717);
  const clouds = new Noise(seed + 4242);

  const heights = new Float32Array(W * H);
  const surf = document.createElement('canvas');
  surf.width = W; surf.height = H;
  const sctx = surf.getContext('2d');
  const simg = sctx.createImageData(W, H);
  const sd = simg.data;

  const nightOn = P.lights;
  let nimg = null, nd = null;
  if (nightOn) {
    nimg = sctx.createImageData(W, H);
    nd = nimg.data;
  }

  const F = 2.1;
  for (let j = 0; j < H; j++) {
    const lat = (0.5 - j / H) * Math.PI;
    const cl = Math.cos(lat), sl = Math.sin(lat);
    // ближе к полюсам — холоднее, шапки появляются сами
    const polar = Math.pow(Math.abs(sl), 3.0);
    for (let i = 0; i < W; i++) {
      const lon = (i / W) * Math.PI * 2;
      const x = cl * Math.cos(lon), y = sl, z = cl * Math.sin(lon);

      let h = land.fbm3(x * F, y * F, z * F, oct) * 0.5 + 0.5;
      // хребты и мелкая шероховатость
      h += (detail.fbm3(x * F * 4.3, y * F * 4.3, z * F * 4.3, 3)) * 0.09;
      h = Math.min(1, Math.max(0, h));
      const idx = j * W + i;
      heights[idx] = h;

      let t = h;
      if (P.sea > 0 && h > P.sea) t = h;             // суша как есть
      const c = rampColor(P.ramp, t);
      let r = c[0], g = c[1], b = c[2];

      // полярные шапки поверх всего, кроме глубокой воды
      if (polar > 0.45 && h > (P.sea > 0 ? P.sea - 0.04 : -1)) {
        const k = Math.min(1, (polar - 0.45) / 0.4);
        r += (242 - r) * k; g += (248 - g) * k; b += (252 - b) * k;
      }

      const o = idx * 4;
      sd[o] = r; sd[o + 1] = g; sd[o + 2] = b; sd[o + 3] = 255;

      if (nightOn) {
        // Огни городов: только на суше, кучно, не у полюсов
        let a = 0;
        if (P.sea < 0 || h > P.sea + 0.02) {
          const cluster = detail.fbm3(x * 6, y * 6, z * 6, 3) * 0.5 + 0.5;
          const spark = clouds.noise3(x * 90, y * 90, z * 90) * 0.5 + 0.5;
          const density = Math.max(0, cluster - 0.52) * 2.6 * (1 - polar);
          if (spark > 1 - density * 0.5) a = Math.min(255, density * 420);
        }
        nd[o] = 255; nd[o + 1] = 214; nd[o + 2] = 150; nd[o + 3] = a;
      }
    }
  }
  sctx.putImageData(simg, 0, 0);

  // ── карта нормалей из поля высот
  const norm = document.createElement('canvas');
  norm.width = W; norm.height = H;
  const nctx = norm.getContext('2d');
  const nrm = nctx.createImageData(W, H);
  const ndata = nrm.data;
  const strength = 2.6;
  for (let j = 0; j < H; j++) {
    const jm = j > 0 ? j - 1 : 0, jp = j < H - 1 ? j + 1 : H - 1;
    for (let i = 0; i < W; i++) {
      const im = (i - 1 + W) % W, ip = (i + 1) % W;
      const hl = heights[j * W + im], hr = heights[j * W + ip];
      const hu = heights[jm * W + i], hd = heights[jp * W + i];
      let nx = (hl - hr) * strength, ny = (hu - hd) * strength, nz = 1;
      const len = Math.hypot(nx, ny, nz) || 1;
      const o = (j * W + i) * 4;
      ndata[o] = (nx / len * 0.5 + 0.5) * 255;
      ndata[o + 1] = (ny / len * 0.5 + 0.5) * 255;
      ndata[o + 2] = (nz / len * 0.5 + 0.5) * 255;
      ndata[o + 3] = 255;
    }
  }
  nctx.putImageData(nrm, 0, 0);

  // ── облака отдельным слоем
  const cl = document.createElement('canvas');
  const CW = Math.round(W * 0.75), CH = Math.round(H * 0.75);
  cl.width = CW; cl.height = CH;
  const cctx = cl.getContext('2d');
  const cimg = cctx.createImageData(CW, CH);
  const cd = cimg.data;
  const thr = P.cloud;
  for (let j = 0; j < CH; j++) {
    const lat = (0.5 - j / CH) * Math.PI;
    const clat = Math.cos(lat), slat = Math.sin(lat);
    // облака вытянуты по широте — как настоящие пояса
    for (let i = 0; i < CW; i++) {
      const lon = (i / CW) * Math.PI * 2;
      const x = clat * Math.cos(lon), y = slat, z = clat * Math.sin(lon);
      const n = clouds.fbm3(x * 3.0, y * 6.0, z * 3.0, 4) * 0.5 + 0.5;
      const a = Math.max(0, n - thr) / (1 - thr);
      const o = (j * CW + i) * 4;
      cd[o] = 255; cd[o + 1] = 255; cd[o + 2] = 255;
      cd[o + 3] = Math.min(255, a * a * 300);
    }
  }
  cctx.putImageData(cimg, 0, 0);

  const out = {
    map: canvasTexture(surf),
    normalMap: canvasTexture(norm, false),
    cloudMap: canvasTexture(cl),
    emissiveMap: nightOn ? canvasTexture(nimg && (() => {
      const c = document.createElement('canvas');
      c.width = W; c.height = H;
      c.getContext('2d').putImageData(nimg, 0, 0);
      return c;
    })()) : null,
    atmo: P.atmo,
    atmoPower: P.atmoPower,
  };
  cache.set(key, out);
  return out;
}

/* Туманность на фон. Тоже равнопрямоугольная развёртка, но
   рисуется в цвет — это просто «небо» на дальней сфере. */
export function nebulaTexture(seed = 11) {
  const key = 'nebula|' + seed;
  if (cache.has(key)) return cache.get(key);

  const W = IS_TOUCH ? 1024 : 1536;
  const H = W / 2;
  const a = new Noise(seed);
  const b = new Noise(seed + 999);
  const c = new Noise(seed + 31337);

  const cv = document.createElement('canvas');
  cv.width = W; cv.height = H;
  const ctx = cv.getContext('2d');
  const img = ctx.createImageData(W, H);
  const d = img.data;

  // два облака разного цвета плюс тёмная пыль
  const C1 = [58, 96, 190];    // холодный синий
  const C2 = [196, 92, 150];   // пурпурный
  const C3 = [220, 140, 70];   // тёплый край

  for (let j = 0; j < H; j++) {
    const lat = (0.5 - j / H) * Math.PI;
    const cl = Math.cos(lat), sl = Math.sin(lat);
    for (let i = 0; i < W; i++) {
      const lon = (i / W) * Math.PI * 2;
      const x = cl * Math.cos(lon), y = sl, z = cl * Math.sin(lon);

      const n1 = a.fbm3(x * 1.6, y * 1.6, z * 1.6, 5) * 0.5 + 0.5;
      const n2 = b.fbm3(x * 2.9 + 4, y * 2.9, z * 2.9, 4) * 0.5 + 0.5;
      const dust = c.fbm3(x * 5.5, y * 5.5, z * 5.5, 3) * 0.5 + 0.5;

      const m1 = Math.pow(Math.max(0, n1 - 0.46) * 2.2, 1.7);
      const m2 = Math.pow(Math.max(0, n2 - 0.52) * 2.4, 2.0);
      const rim = Math.pow(Math.max(0, n1 - 0.66) * 3.0, 2.4);

      let r = 4 + C1[0] * m1 + C2[0] * m2 + C3[0] * rim;
      let g = 6 + C1[1] * m1 + C2[1] * m2 + C3[1] * rim;
      let bl = 12 + C1[2] * m1 + C2[2] * m2 + C3[2] * rim;

      // тёмная пыль съедает часть свечения — так получаются прожилки
      const k = 1 - Math.max(0, dust - 0.55) * 1.4;
      r *= k; g *= k; bl *= k;

      const o = (j * W + i) * 4;
      d[o] = Math.min(255, r);
      d[o + 1] = Math.min(255, g);
      d[o + 2] = Math.min(255, bl);
      d[o + 3] = 255;
    }
  }
  ctx.putImageData(img, 0, 0);

  // Звёзды в фон НЕ запекаем: сфера туманности огромная, один тексель
  // растягивается на пол-экрана, и звезда превращается в квадратное
  // пятно. Звёзды рисует отдельный слой точек (starfield в engine.js).

  const t = canvasTexture(cv);
  cache.set(key, t);
  return t;
}

/* Мелкая деталь грунта. Тайлится по ландшафту с большим повтором:
   даёт крупицы, трещины и пятна вблизи, не добавляя ни одного полигона. */
export function groundTexture(biome, seed = 5) {
  const key = 'ground|' + biome + '|' + seed;
  if (cache.has(key)) return cache.get(key);
  const S = IS_TOUCH ? 256 : 512;
  const n = new Noise(seed);
  const fine = new Noise(seed + 3);
  const cv = document.createElement('canvas');
  cv.width = cv.height = S;
  const ctx = cv.getContext('2d');
  const img = ctx.createImageData(S, S);
  const d = img.data;
  for (let y = 0; y < S; y++) {
    for (let x = 0; x < S; x++) {
      // бесшовно: щупаем шум на торе, поэтому края сходятся
      const a = (x / S) * Math.PI * 2, b = (y / S) * Math.PI * 2;
      const px = Math.cos(a) * 2, py = Math.sin(a) * 2;
      const qy = Math.sin(b) * 2, qx = Math.cos(b) * 2;
      const big = n.fbm3(px + qx * 0.3, py, qy, 4) * 0.5 + 0.5;
      const gr = fine.fbm3(px * 6, py * 6, qy * 6, 3) * 0.5 + 0.5;
      let v = 0.78 + big * 0.30 + (gr - 0.5) * 0.26;
      if (gr > 0.78) v *= 0.72;      // крапины: камешки и трещины
      const o = (y * S + x) * 4;
      const c = Math.max(0, Math.min(255, v * 255));
      d[o] = c; d[o + 1] = c; d[o + 2] = c; d[o + 3] = 255;
    }
  }
  ctx.putImageData(img, 0, 0);
  const t = new THREE.CanvasTexture(cv);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 8;
  cache.set(key, t);
  return t;
}

export function clearTextureCache() {
  for (const v of cache.values()) {
    if (v && v.dispose) v.dispose();
    else if (v) for (const k of ['map', 'normalMap', 'cloudMap', 'emissiveMap']) {
      if (v[k] && v[k].dispose) v[k].dispose();
    }
  }
  cache.clear();
}
