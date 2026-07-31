/* Процедурные текстуры: планеты, облака, ночные огни, туманность.

   Всё рисуется один раз на canvas и кладётся в кэш: биомов пять,
   планет на карте четырнадцать, но текстур всё равно будет пять.
   Никаких внешних картинок — игра остаётся самодостаточной. */

import { THREE, IS_TOUCH } from './engine.js';
import { Noise } from './noise.js';
import { customPlanet } from './assets.js';

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
    // влажный экватор · пояс пустынь · тайга и тундра
    climate: { wet: [46, 82, 44], dry: [188, 158, 104], cold: [92, 104, 96] },
  },
  desert: {
    sea: 0.30,
    ramp: [
      [0.00, [92, 68, 40]], [0.30, [140, 106, 62]], [0.48, [198, 162, 100]],
      [0.62, [214, 184, 126]], [0.76, [166, 126, 74]], [0.88, [122, 92, 56]],
      [1.00, [224, 214, 188]],
    ],
    cloud: 0.78, lights: false, atmo: 0xffcf90, atmoPower: 0.13,
    climate: { wet: [162, 132, 78], dry: [222, 190, 128], cold: [186, 176, 158] },
  },
  ice: {
    sea: 0.40,
    ramp: [
      [0.00, [26, 52, 74]], [0.36, [58, 96, 122]], [0.42, [122, 158, 182]],
      [0.52, [186, 212, 230]], [0.70, [214, 232, 242]], [0.86, [232, 244, 250]],
      [1.00, [252, 254, 255]],
    ],
    cloud: 0.50, lights: false, atmo: 0x9fd0ff, atmoPower: 0.20,
    climate: { wet: [120, 150, 168], dry: [178, 200, 214], cold: [238, 248, 252] },
  },
  rock: {
    sea: -1,
    ramp: [
      [0.00, [46, 38, 32]], [0.28, [74, 62, 52]], [0.48, [104, 88, 72]],
      [0.66, [134, 114, 92]], [0.82, [96, 82, 68]], [1.00, [162, 148, 128]],
    ],
    cloud: 0.95, lights: false, atmo: 0x9a8f80, atmoPower: 0.07,
  },
  // Клото — родина Тройден: охристая суша, изрезанная почти чёрными
  // морями и каньонами, редкие белые облака. По референсу из игры.
  klotho: {
    sea: 0.44,
    ramp: [
      [0.00, [6, 10, 16]], [0.36, [10, 16, 24]], [0.43, [18, 28, 38]],
      [0.45, [96, 82, 56]], [0.52, [178, 156, 112]], [0.66, [206, 186, 142]],
      [0.78, [186, 162, 118]], [0.90, [214, 200, 168]], [1.00, [240, 236, 226]],
    ],
    cloud: 0.80, lights: false, atmo: 0x9fc0ff, atmoPower: 0.15,
    // Клото сухая: зелени почти нет, зато пески и солончаки
    climate: { wet: [148, 140, 92], dry: [214, 190, 140], cold: [176, 172, 158] },
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
export function planetTextures(biome, seed = 1, id = null, quality = 0) {
  /* Три ступени качества по тому, насколько крупно планета видна.
     На карте системы она занимает три десятка пикселей — там
     развёртка 2048 не видна вообще, а считается секунду с лишним,
     и таких планет шесть. Полный размер нужен только той планете,
     над которой идёт бой: она во весь экран.
       0 — карта системы, 1 — заставка и луны, 2 — бой на орбите */
  const key = `${id || ''}|${biome}|${seed}|q${quality}`;
  if (cache.has(key)) return cache.get(key);

  const P = PALETTES[biome] || PALETTES.rock;

  // Если положена своя картинка — берём её, а недостающие карты
  // добираем значениями палитры. Сперва ищем по имени планеты
  // («klotho»), потом по биому — так у Клото может быть своё лицо,
  // а у безымянных ледяных миров одна общая картинка на всех.
  const custom = customPlanet(id) || customPlanet(biome);
  if (custom) {
    const out = {
      map: custom.map,
      roughnessMap: custom.roughnessMap || null,
      normalMap: custom.normalMap || null,
      cloudMap: custom.cloudMap || null,
      emissiveMap: custom.emissiveMap || null,
      atmo: custom.atmo !== undefined ? custom.atmo : P.atmo,
      atmoPower: custom.atmoPower !== undefined ? custom.atmoPower : P.atmoPower,
      custom: true,
    };
    cache.set(key, out);
    return out;
  }
  const W = quality >= 2 ? (IS_TOUCH ? 1024 : 2048)
          : quality >= 1 ? 1024 : 512;
  const H = W / 2;

  const land = new Noise(seed);
  const detail = new Noise(seed + 7717);
  const clouds = new Noise(seed + 4242);
  const warp = new Noise(seed + 1861);      // искажает координаты — рвёт берега
  const ridge = new Noise(seed + 5090);     // горные гряды
  const climate = new Noise(seed + 2733);   // пятна биомов поверх широтных поясов

  const F = 2.1;

  /* ── ПОЛЕ ВЫСОТ В ДВА ПРОХОДА.

     Искажение координат и хребтовый шум — самое дорогое, что здесь
     есть: втрое-вчетверо дороже обычного фрактального шума. Считать
     их на каждый пиксель развёртки 2048×1024 значит заморозить
     вкладку на несколько секунд, а на карте системы биомов шесть.

     Но вся эта тяжесть — низкочастотная: и материки, и хребты
     крупнее пикселя в десятки раз. Поэтому считаем их на сетке
     вдвое мельче и растягиваем билинейно, а поверх в полном
     разрешении добавляем один дешёвый слой мелкой шероховатости —
     он и держит берег острым. На глаз разницы нет, времени уходит
     впятеро меньше. */
  const LW = W >> 1, LH = H >> 1;
  const low = new Float32Array(LW * LH);
  {
    const wf = 1.7, wa = 0.42;
    const wOct = 2, bOct = IS_TOUCH ? 4 : 5, rOct = 3;
    for (let j = 0; j < LH; j++) {
      const lat = (0.5 - (j + 0.5) / LH) * Math.PI;
      const cl = Math.cos(lat), sl = Math.sin(lat);
      for (let i = 0; i < LW; i++) {
        const lon = ((i + 0.5) / LW) * Math.PI * 2;
        const x = cl * Math.cos(lon), y = sl, z = cl * Math.sin(lon);

        /* Искажение координат (domain warping): прежде чем щупать шум,
           сдвигаем точку другим шумом. Один этот приём превращает
           круглые кляксы в материки с заливами, полуостровами и
           архипелагами — берег перестаёт быть окружностью. */
        const wx = warp.fbm3(x * wf, y * wf, z * wf, wOct);
        const wy = warp.fbm3(x * wf + 5.2, y * wf + 1.3, z * wf + 9.1, wOct);
        const wz = warp.fbm3(x * wf - 3.7, y * wf + 6.4, z * wf - 2.8, wOct);
        const px = x + wx * wa, py = y + wy * wa, pz = z + wz * wa;

        let h = land.fbm3(px * F, py * F, pz * F, bOct) * 0.5 + 0.5;

        /* Горные гряды — только на суше и тем выше, чем дальше от моря.
           Так хребты идут вдоль побережий и вглубь материка, а не
           торчат посреди океана. */
        const landness = P.sea > 0 ? Math.max(0, h - P.sea) / (1 - P.sea) : 1;
        if (landness > 0.02) {
          const r3 = ridge.ridged3(px * F * 2.6, py * F * 2.6, pz * F * 2.6, rOct);
          h += (r3 - 0.5) * 0.30 * Math.pow(landness, 0.7);
        }
        low[j * LW + i] = h;
      }
    }
  }
  // билинейная выборка из мелкой сетки, по долготе — с заворотом
  const lowAt = (u, v) => {
    const fx = u * LW - 0.5, fy = v * LH - 0.5;
    const x0 = Math.floor(fx), y0 = Math.floor(fy);
    const tx = fx - x0, ty = fy - y0;
    const xa = ((x0 % LW) + LW) % LW, xb = (xa + 1) % LW;
    const ya = Math.min(LH - 1, Math.max(0, y0)), yb = Math.min(LH - 1, ya + 1);
    const a = low[ya * LW + xa], b = low[ya * LW + xb];
    const c = low[yb * LW + xa], d = low[yb * LW + xb];
    return (a + (b - a) * tx) * (1 - ty) + (c + (d - c) * tx) * ty;
  };

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

  for (let j = 0; j < H; j++) {
    const lat = (0.5 - j / H) * Math.PI;
    const cl = Math.cos(lat), sl = Math.sin(lat);
    // ближе к полюсам — холоднее, шапки появляются сами
    const polar = Math.pow(Math.abs(sl), 3.0);
    const v = (j + 0.5) / H;
    for (let i = 0; i < W; i++) {
      const lon = (i / W) * Math.PI * 2;
      const x = cl * Math.cos(lon), y = sl, z = cl * Math.sin(lon);

      // крупная форма — из мелкой сетки, мелочь — здесь и сейчас
      let h = lowAt((i + 0.5) / W, v);
      h += detail.fbm3(x * F * 4.3, y * F * 4.3, z * F * 4.3, 2) * 0.075;

      h = Math.min(1, Math.max(0, h));
      const idx = j * W + i;
      heights[idx] = h;

      const landness = P.sea > 0 ? Math.max(0, h - P.sea) / (1 - P.sea) : 1;
      const c = rampColor(P.ramp, h);
      let r = c[0], g = c[1], b = c[2];

      /* Климат по широте. На настоящей планете вдоль экватора и
         тропиков идут пояса: влажный лес — пустыня — степь — тайга.
         Без этого суша по всему шару одного цвета и планета читается
         как раскрашенный шум. Пояса размываем пятнами, иначе видно
         полосы, как на школьном глобусе. */
      if (P.climate && landness > 0.01) {
        const latN = Math.abs(sl);                       // 0 экватор, 1 полюс
        const blot = climate.fbm3(x * 2.4, y * 2.4, z * 2.4, 2) * 0.16;
        const dry = Math.exp(-Math.pow((latN + blot - 0.32) / 0.16, 2));   // пояс пустынь
        const cold = Math.max(0, (latN + blot - 0.56) / 0.34);             // тайга и тундра
        const wet = Math.exp(-Math.pow((latN + blot) / 0.22, 2));          // экваториальный лес
        const mix = (col, k) => {
          r += (col[0] - r) * k; g += (col[1] - g) * k; b += (col[2] - b) * k;
        };
        const alt = Math.min(1, landness * 1.6);         // выше — климат бледнее
        mix(P.climate.wet, wet * 0.55 * (1 - alt * 0.5));
        mix(P.climate.dry, dry * 0.62 * (1 - alt * 0.4));
        mix(P.climate.cold, Math.min(1, cold) * 0.7);
      }

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

  /* ── карта шероховатости.
     Вода гладкая, суша матовая. Именно из-за этого на океане
     появляется солнечный блик — то, без чего планета выглядит
     нарисованной на бумаге. */
  const rough = document.createElement('canvas');
  rough.width = W; rough.height = H;
  const rctx = rough.getContext('2d');
  const rimg = rctx.createImageData(W, H);
  const rd = rimg.data;
  for (let i = 0; i < W * H; i++) {
    const h = heights[i];
    let v;
    if (P.sea > 0 && h < P.sea) {
      // вода: у берега чуть шероховатее, на глубине — зеркало
      v = 0.10 + Math.max(0, (h - (P.sea - 0.12))) * 1.6;
    } else {
      v = 0.86 + (h - (P.sea > 0 ? P.sea : 0)) * 0.2;
    }
    const c = Math.max(0, Math.min(255, v * 255));
    const o = i * 4;
    rd[o] = rd[o + 1] = rd[o + 2] = c; rd[o + 3] = 255;
  }
  rctx.putImageData(rimg, 0, 0);

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
      const water = P.sea > 0 && heights[j * W + i] < P.sea;
      const k = water ? 0.15 : 1;
      let nx = (hl - hr) * strength * k, ny = (hu - hd) * strength * k, nz = 1;
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
  const CW = Math.round(W * 0.5), CH = Math.round(H * 0.5);
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
      /* Закрутка по широте. Атмосфера вращается быстрее у экватора,
         поэтому облачные поля вытягиваются в ленты и заворачиваются.
         Просто повернуть точку вокруг оси на угол, зависящий от
         широты, — и ровный шум становится похож на циклоны. */
      const spin = (1 - Math.abs(slat)) * 2.6 + slat * 1.4;
      const cs = Math.cos(spin), sn = Math.sin(spin);
      const sx = x * cs - z * sn, sz = x * sn + z * cs;

      // вытянутые по долготе ленты плюс мелкая рваность поверх
      let n = clouds.fbm3(sx * 2.2, y * 5.4, sz * 2.2, 4) * 0.5 + 0.5;
      n += (clouds.fbm3(sx * 7.5, y * 9.0, sz * 7.5, 2) * 0.5 + 0.5 - 0.5) * 0.22;
      // просветы в поясе пассатов — небо не затянуто ровным одеялом
      n -= Math.exp(-Math.pow((Math.abs(slat) - 0.3) / 0.1, 2)) * 0.10;

      const a = Math.max(0, n - thr) / (1 - thr);
      const o = (j * CW + i) * 4;
      cd[o] = 255; cd[o + 1] = 255; cd[o + 2] = 255;
      cd[o + 3] = Math.min(255, a * a * 300);
    }
  }
  cctx.putImageData(cimg, 0, 0);

  const out = {
    map: canvasTexture(surf),
    roughnessMap: canvasTexture(rough, false),
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

  /* Карта нормалей из той же яркости. Без неё грунт под солнцем
     плоский, как крашеная бумага: свет одинаков по всей поверхности,
     и никакой рельеф вблизи не читается. Считаем наклон по соседним
     пикселям — комки и трещины начинают ловить тень. */
  const nrm = document.createElement('canvas');
  nrm.width = nrm.height = S;
  const nctx = nrm.getContext('2d');
  const nimg = nctx.createImageData(S, S);
  const nd = nimg.data;
  const at = (x, y) => d[(((y + S) % S) * S + ((x + S) % S)) * 4] / 255;
  const STR = 3.4;
  for (let y = 0; y < S; y++) {
    for (let x = 0; x < S; x++) {
      const dx = (at(x - 1, y) - at(x + 1, y)) * STR;
      const dy = (at(x, y - 1) - at(x, y + 1)) * STR;
      const len = Math.hypot(dx, dy, 1);
      const o = (y * S + x) * 4;
      nd[o] = (dx / len * 0.5 + 0.5) * 255;
      nd[o + 1] = (dy / len * 0.5 + 0.5) * 255;
      nd[o + 2] = (1 / len * 0.5 + 0.5) * 255;
      nd[o + 3] = 255;
    }
  }
  nctx.putImageData(nimg, 0, 0);
  const nt = new THREE.CanvasTexture(nrm);
  nt.wrapS = nt.wrapT = THREE.RepeatWrapping;
  nt.anisotropy = 8;
  t.userData.normal = nt;

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
