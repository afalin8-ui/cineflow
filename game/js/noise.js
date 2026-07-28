/* Шум для процедурной генерации: планеты, туманности, рельеф.
   Обычный значный шум (value noise) на решётке с плавной
   интерполяцией — быстрый и предсказуемый. Всё детерминировано
   от зерна: одна и та же планета всегда выглядит одинаково. */

// Таблица перестановок от зерна — чтобы разные миры не были близнецами
function permTable(seed) {
  const p = new Uint8Array(512);
  const base = new Uint8Array(256);
  for (let i = 0; i < 256; i++) base[i] = i;
  // перемешивание Фишера—Йетса на простом генераторе
  let s = (seed | 0) || 1;
  const rnd = () => {
    s ^= s << 13; s |= 0;
    s ^= s >>> 17;
    s ^= s << 5; s |= 0;
    return ((s >>> 0) % 1000000) / 1000000;
  };
  for (let i = 255; i > 0; i--) {
    const j = Math.floor(rnd() * (i + 1));
    const t = base[i]; base[i] = base[j]; base[j] = t;
  }
  for (let i = 0; i < 512; i++) p[i] = base[i & 255];
  return p;
}

const smooth = t => t * t * (3 - 2 * t);
const lerp = (a, b, t) => a + (b - a) * t;

export class Noise {
  constructor(seed = 1) {
    this.p = permTable(seed);
    // случайные значения решётки
    this.g = new Float32Array(256);
    let s = (seed * 2654435761) >>> 0;
    for (let i = 0; i < 256; i++) {
      s = (s * 1664525 + 1013904223) >>> 0;
      this.g[i] = (s >>> 8) / 8388608 - 1;   // −1..1
    }
  }

  // Значный шум в трёх измерениях
  noise3(x, y, z) {
    const p = this.p, g = this.g;
    const X = Math.floor(x) & 255, Y = Math.floor(y) & 255, Z = Math.floor(z) & 255;
    const fx = x - Math.floor(x), fy = y - Math.floor(y), fz = z - Math.floor(z);
    const u = smooth(fx), v = smooth(fy), w = smooth(fz);
    const at = (i, j, k) => g[p[(p[(p[i] + j) & 511] + k) & 511]];
    const x0 = X, x1 = (X + 1) & 255, y0 = Y, y1 = (Y + 1) & 255, z0 = Z, z1 = (Z + 1) & 255;
    const c000 = at(x0, y0, z0), c100 = at(x1, y0, z0);
    const c010 = at(x0, y1, z0), c110 = at(x1, y1, z0);
    const c001 = at(x0, y0, z1), c101 = at(x1, y0, z1);
    const c011 = at(x0, y1, z1), c111 = at(x1, y1, z1);
    return lerp(
      lerp(lerp(c000, c100, u), lerp(c010, c110, u), v),
      lerp(lerp(c001, c101, u), lerp(c011, c111, u), v),
      w);
  }

  noise2(x, y) { return this.noise3(x, y, 0.5); }

  // Многослойный шум: крупные формы плюс мелкие детали
  fbm3(x, y, z, octaves = 5, lacunarity = 2.0, gain = 0.5) {
    let sum = 0, amp = 1, norm = 0, f = 1;
    for (let i = 0; i < octaves; i++) {
      sum += this.noise3(x * f, y * f, z * f) * amp;
      norm += amp;
      amp *= gain;
      f *= lacunarity;
    }
    return sum / norm;
  }

  fbm2(x, y, octaves = 5, lacunarity = 2.0, gain = 0.5) {
    return this.fbm3(x, y, 0.5, octaves, lacunarity, gain);
  }

  /* Хребтовый шум на сфере. Нужен отдельно от ridged2: на планете
     координата трёхмерная, и плоский вариант дал бы шов по долготе
     и кашу на полюсах. */
  ridged3(x, y, z, octaves = 4, lacunarity = 2.0, gain = 0.5) {
    let sum = 0, amp = 1, norm = 0, f = 1;
    for (let i = 0; i < octaves; i++) {
      const n = 1 - Math.abs(this.noise3(x * f, y * f, z * f));
      sum += n * n * amp;
      norm += amp;
      amp *= gain;
      f *= lacunarity;
    }
    return sum / norm;
  }

  // Хребтовый шум — даёт горные гряды, а не мягкие холмы
  ridged2(x, y, octaves = 4, lacunarity = 2.0, gain = 0.5) {
    let sum = 0, amp = 1, norm = 0, f = 1;
    for (let i = 0; i < octaves; i++) {
      const n = 1 - Math.abs(this.noise2(x * f, y * f));
      sum += n * n * amp;
      norm += amp;
      amp *= gain;
      f *= lacunarity;
    }
    return sum / norm;
  }
}

// Быстрый детерминированный «случайный» из строки — для зерна карты
export function seedFrom(str) {
  let h = 2166136261;
  for (let i = 0; i < String(str).length; i++) {
    h ^= String(str).charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}
