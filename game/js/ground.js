/* НАЗЕМНЫЙ БОЙ — классическая RTS в духе Command & Conquer: Generals.

   База, снабжение, три ветки производства и связка «пехота — техника —
   артиллерия — авиация». Ключевые правила:
     · сборщики возят снабжение с полей на штаб, без них кончаются деньги;
     · пехота косит пехоту, ракетчики вскрывают технику и достают авиацию;
     · артиллерия бьёт дальше всех, но слепая и беззащитна вблизи;
     · штурмовик отрабатывает по цели и обязан вернуться на аэродром
       за боезапасом — пока летит домой, он мишень;
     · ЗСУ и зенитные башни — единственная защита от авиации. */

import {
  THREE, TacticalCamera, Controls, Fx, screenOf, ringMesh,
  clamp, lerp, rnd, disposeScene, IS_TOUCH,
} from './engine.js';
import {
  buildGroundUnit, buildStructure, buildSupplyField, buildProp, buildWater, mat,
  buildGrass, buildTreeField, buildTrackField, buildScorchField,
} from './models.js';
import { groundTexture, terrainSet } from './textures.js';
import { Noise, seedFrom } from './noise.js';
import {
  FACTIONS, GROUND_BUILDINGS, GROUND_UNITS, GROUND_DMG, BIOME_COLORS, STEALTH,
  dmgMult, unitDef, MAX_TECH, ORBITAL_SUPPORT,
} from './data.js';

const MAP = 270;              // половина стороны карты (игровая зона)
const TERRAIN = MAP * 2.4;    // сам ландшафт шире, чтобы не было видно края
const _v = new THREE.Vector3();
const _v2 = new THREE.Vector3();
const UPV = new THREE.Vector3(0, 1, 0);

/* КАРТА ВЫСОТ.
   Складываем несколько слоёв шума: крупные складки задают общий
   рельеф, хребтовый шум добавляет гряды, мелкий — неровности почвы.
   Площадки под базы принудительно выравниваются, иначе штаб уезжает
   в овраг, а сборщики застревают на склоне. */

const HEIGHT_SCALE = 36;      // перепад высот от низины до гребня
const BASIN_DEPTH = 4.5;      // во сколько раз утапливаем дно ниже уреза воды
let WATER_LEVEL = -7.5;       // ниже этой отметки — вода, туда не заедешь
let heightNoise = null;
let flatSpots = [];           // {x, z, r, h} — выровненные площадки

export function makeHeightField(seed, waterFraction = 0.18) {
  heightNoise = { a: new Noise(seed), b: new Noise(seed + 8123), c: new Noise(seed + 55) };
  flatSpots = [];
  WATER_LEVEL = computeWaterLevel(waterFraction);
  return WATER_LEVEL;
}

/* Уровень воды подбираем по самому рельефу: берём нужную долю самых
   низких точек. Задавать его числом бесполезно — шум от карты к карте
   гуляет, и вода то заливает всё, то не появляется вовсе. */
function computeWaterLevel(fraction) {
  if (fraction <= 0) return -1e6;
  const N = 72;
  const vals = [];
  for (let j = 0; j < N; j++) {
    for (let i = 0; i < N; i++) {
      const x = (i / (N - 1) - 0.5) * MAP * 2;
      const z = (j / (N - 1) - 0.5) * MAP * 2;
      vals.push(rawHeight(x, z));
    }
  }
  vals.sort((a, b) => a - b);
  return vals[Math.floor(vals.length * fraction)];
}

export function waterLevel() { return WATER_LEVEL; }

export function addFlatSpot(x, z, r) {
  // База не должна оказаться на дне озера — приподнимаем над водой
  const h = Math.max(rawHeight(x, z), WATER_LEVEL + 4);
  flatSpots.push({ x, z, r, h });
}

function rawHeight(x, z) {
  if (!heightNoise) return 0;
  const s = 0.0045;
  const base = heightNoise.a.fbm2(x * s, z * s, 5) * 0.5 + 0.5;      // 0..1 складки
  const ridge = heightNoise.b.ridged2(x * s * 2.1, z * s * 2.1, 4);   // гряды
  const grain = heightNoise.c.fbm2(x * s * 9, z * s * 9, 3) * 0.5;    // шероховатость
  // Гряды проявляются только на возвышенностях — в низинах остаются поля
  const h = base * 0.70 + ridge * base * 0.72 + grain * 0.10;
  return (h - 0.45) * HEIGHT_SCALE;
}

// Вода занимает низины. Техника в неё не идёт, строить в ней нельзя.
export function isWater(x, z) {
  return terrainH(x, z) < WATER_LEVEL;
}

export function terrainH(x, z) {
  let h = rawHeight(x, z);
  /* Дно водоёмов утапливаем. Уровень воды берётся долей от рельефа,
     поэтому без этого озеро выходит плёнкой в палец толщиной: воды
     не видно, видно только пену по всей луже. Утопив дно, получаем
     настоящую котловину — у берега мелко и просвечивает грунт,
     в середине темно. */
  if (h < WATER_LEVEL) h = WATER_LEVEL - (WATER_LEVEL - h) * BASIN_DEPTH;
  for (const f of flatSpots) {
    const d = Math.hypot(x - f.x, z - f.z);
    if (d >= f.r) continue;
    // плавный переход от площадки к рельефу, без ступеньки по краю
    const k = 1 - (d / f.r) * (d / f.r);
    h += (f.h - h) * k;
  }
  return h;
}

export function createGroundBattle(ctx, config) {
  const { viewport, hudRoot } = ctx;
  const biome = BIOME_COLORS[config.biome] || BIOME_COLORS.rock;
  const seed = seedFrom(config.seed || config.title || 'капелла');
  // Сколько карты под водой: в пустыне почти нет, во льдах много
  const waterFrac = config.biome === 'desert' ? 0.06
                  : config.biome === 'ice' ? 0.24
                  : config.biome === 'city' ? 0.10 : 0.18;
  makeHeightField(seed, waterFrac);

  const scene = new THREE.Scene();
  scene.background = new THREE.Color(biome.sky);
  scene.fog = new THREE.Fog(biome.sky, 420, 900);

  const tcam = new TacticalCamera({
    dist: 150, minDist: 40, maxDist: 380, pitch: 0.8, yaw: 0.4,
    bounds: { x: MAP - 20, z: MAP - 20 }, far: 2600,
  });

  // Ровные площадки: базы и поля снабжения. Задаём до построения меша
  const BX0 = MAP * 0.62;
  addFlatSpot(-BX0, BX0, 78);
  addFlatSpot(BX0, -BX0, 78);
  const FIELD_SPOTS = [
    [-0.66, 0.48], [-0.40, 0.79], [0.66, -0.48], [0.40, -0.79],
    [-0.17, -0.25], [0.17, 0.25], [-0.79, -0.32], [0.79, 0.32],
  ].map(([fx, fz]) => [fx * MAP, fz * MAP]);
  for (const [fx, fz] of FIELD_SPOTS) addFlatSpot(fx, fz, 26);

  scene.add(new THREE.AmbientLight(0x93a0b4, 1.35));
  const sun = new THREE.DirectionalLight(0xfff2dc, 3.6);
  sun.position.set(210, 190, 130);
  /* Солнце отбрасывает тени. Ортографическая камера тени натянута на
     игровую зону — не на весь ландшафт: он вчетверо шире, и растянув
     карту теней на него, мы получили бы кашу вместо контуров.
     Карта 2048 на планшете тянется нормально, потому что она одна
     и обновляется не каждый кадр. */
  sun.castShadow = true;
  sun.shadow.mapSize.set(IS_TOUCH ? 1024 : 2048, IS_TOUCH ? 1024 : 2048);
  const SH = MAP * 1.15;
  sun.shadow.camera.left = -SH; sun.shadow.camera.right = SH;
  sun.shadow.camera.top = SH; sun.shadow.camera.bottom = -SH;
  sun.shadow.camera.near = 1; sun.shadow.camera.far = 900;
  // без сдвига тень «отрывается» от подошвы юнита и ползёт полосами
  sun.shadow.bias = -0.0012;
  sun.shadow.normalBias = 0.9;
  sun.position.multiplyScalar(1.6);
  sun.target.position.set(0, 0, 0);
  scene.add(sun.target);
  scene.add(sun);
  const bounce = new THREE.DirectionalLight(0x6a7a90, 0.6);
  bounce.position.set(-160, 80, -140);
  scene.add(bounce);

  // ── ЛАНДШАФТ ─────────────────────────────────────────────
  // Плотнее сетка — мельче ступенька там, где рельеф уходит под воду
  const segs = IS_TOUCH ? 170 : 260;
  const tGeo = new THREE.PlaneGeometry(TERRAIN * 2, TERRAIN * 2, segs, segs);
  tGeo.rotateX(-Math.PI / 2);
  const posAttr = tGeo.attributes.position;
  const colors = new Float32Array(posAttr.count * 3);
  const slopes = new Float32Array(posAttr.count);   // для смешивания текстур
  const cLow = new THREE.Color(biome.ground);
  const cHigh = new THREE.Color(biome.accent);
  const cRock = new THREE.Color(biome.rock || 0x6a5f52);
  const cBed = new THREE.Color(config.biome === 'ice' ? 0x40525c : 0x5a4c34);  // ил и мокрый песок
  const tmpC = new THREE.Color();
  const WHITE = new THREE.Color(0xffffff);
  const step = (TERRAIN * 2) / segs;
  for (let i = 0; i < posAttr.count; i++) {
    const x = posAttr.getX(i), z = posAttr.getZ(i);
    const h = terrainH(x, z);
    posAttr.setY(i, h);
    // уклон: крутые склоны — голый камень, пологие — грунт
    const dx = (terrainH(x + step, z) - terrainH(x - step, z)) / (2 * step);
    const dz = (terrainH(x, z + step) - terrainH(x, z - step)) / (2 * step);
    const slope = Math.min(1, Math.hypot(dx, dz) * 2.6);
    slopes[i] = slope;
    const alt = clamp((h + HEIGHT_SCALE * 0.45) / HEIGHT_SCALE, 0, 1);
    tmpC.copy(cLow).lerp(cHigh, Math.pow(alt, 1.4));
    tmpC.lerp(cRock, Math.pow(slope, 0.8) * 0.9);
    // Под водой не трава, а ил и мокрый песок: у кромки светлая
    // отмель, дальше темнеет. Без этого сквозь мелководье
    // просвечивает луг и вода не читается вовсе.
    if (h < WATER_LEVEL) {
      /* Дно ЗАМЕТНО темнее суши. Светлое дно просвечивает сквозь
         мелководье и читается бледной каймой вокруг каждого озера —
         именно оно, а не пена, делало берега белёсыми. Ил и мокрый
         песок в жизни тоже сильно темнее сухого грунта. */
      const sub = clamp((WATER_LEVEL - h) / (HEIGHT_SCALE * 0.35), 0, 1);
      tmpC.lerp(cBed, 0.8);
      tmpC.multiplyScalar(0.42 - sub * 0.22);
    }
    /* Вертексный цвет теперь только подкрашивает биом: рисунок даёт
       фотоскан, а полная насыщенность заливки его душит. Осветляем
       к белому — под водой не трогаем, там цвет несёт ил. */
    if (h >= WATER_LEVEL) tmpC.lerp(WHITE, 0.5);
    const jitter = 0.96 + Math.random() * 0.08;
    colors[i * 3] = tmpC.r * jitter;
    colors[i * 3 + 1] = tmpC.g * jitter;
    colors[i * 3 + 2] = tmpC.b * jitter;
  }
  tGeo.setAttribute('color', new THREE.BufferAttribute(colors, 3));
  tGeo.setAttribute('aSlope', new THREE.BufferAttribute(slopes, 1));
  tGeo.computeVertexNormals();
  // Гладкое затенение плюс тайловая деталь: фасетки уходят, а вблизи
  // видно крупицы и трещины — полигонов при этом не прибавилось.
  const detail = groundTexture(config.biome || 'rock');
  detail.repeat.set(48, 48);
  if (detail.userData.normal) detail.userData.normal.repeat.set(48, 48);
  /* Три фотоскана, смешанные по уклону прямо в шейдере: на пологом
     трава, на обрыве камень, между ними глина. Вертексные цвета
     остаются, но приглушены — они теперь только подкрашивают биом,
     а рисунок поверхности дают сканы. Вмешиваемся через
     onBeforeCompile, а не пишем свой материал: так у ландшафта
     сохраняется штатное освещение three.js и, главное, тени. */
  const T = terrainSet(config.biome);
  const terrainMat = new THREE.MeshStandardMaterial({
    vertexColors: true,
    normalMap: T.grassN,
    normalScale: new THREE.Vector2(1.1, 1.1),
    roughness: 0.95, metalness: 0,
  });
  terrainMat.onBeforeCompile = sh => {
    sh.uniforms.uGrass = { value: T.grass };
    sh.uniforms.uRock = { value: T.rock };
    sh.uniforms.uDirt = { value: T.dirt };
    sh.uniforms.uTexScale = { value: 0.055 };
    sh.vertexShader = sh.vertexShader
      .replace('#include <common>',
        '#include <common>\nattribute float aSlope;\nvarying float vSlope;\nvarying vec3 vWPosT;')
      .replace('#include <begin_vertex>',
        '#include <begin_vertex>\nvSlope = aSlope;\nvWPosT = (modelMatrix * vec4(position, 1.0)).xyz;');
    sh.fragmentShader = sh.fragmentShader
      .replace('#include <common>',
        '#include <common>\nuniform sampler2D uGrass;\nuniform sampler2D uRock;\n'
        + 'uniform sampler2D uDirt;\nuniform float uTexScale;\n'
        + 'varying float vSlope;\nvarying vec3 vWPosT;')
      .replace('#include <map_fragment>', [
        'vec2 tuv = vWPosT.xz * uTexScale;',
        // разный масштаб у слоёв: одинаковый выдаёт повтор сеткой
        'vec3 cG = texture2D(uGrass, tuv).rgb;',
        'vec3 cR = texture2D(uRock, tuv * 0.62).rgb;',
        'vec3 cD = texture2D(uDirt, tuv * 1.45).rgb;',
        'float rockK = smoothstep(0.30, 0.70, vSlope);',
        'float dirtK = smoothstep(0.17, 0.45, vSlope) * (1.0 - rockK);',
        'vec3 blend = mix(mix(cG, cD, dirtK), cR, rockK);',
        'diffuseColor.rgb *= blend * 1.75;',
      ].join('\n'));
    terrainMat.userData.shader = sh;
  };
  const terrain = new THREE.Mesh(tGeo, terrainMat);
  terrain.receiveShadow = true;
  scene.add(terrain);

  /* ── ВОДА.
     Пекём карту глубины прямо из рельефа: шейдер по ней рисует
     прибой у берега и темноту на глубине. */
  /* Разрешение карты глубины решает, насколько плавен урез воды.
     На 256 текселях один тексель накрывает десять игровых единиц, и
     вблизи берег читается ступеньками. На 512 их пять, а лёгкое
     размытие добивает остаток лесенки — линия воды становится
     похожей на линию воды, а не на пиксельную границу. */
  const DW = 512;
  const depthCv = document.createElement('canvas');
  depthCv.width = depthCv.height = DW;
  {
    const dctx = depthCv.getContext('2d');
    const img = dctx.createImageData(DW, DW);
    const dd = img.data;
    // Сперва меряем, потом нормируем: делить на выдуманное число
    // нельзя — у горной карты озёра глубокие, у степной мелкие,
    // и на одной из двух вода вышла бы либо чернилами, либо молоком.
    const raw = new Float32Array(DW * DW);
    let deepest = 1e-3;
    for (let j = 0; j < DW; j++) {
      for (let i = 0; i < DW; i++) {
        /* Плоскость воды растянута на TERRAIN*2. Строку j НЕ переворачиваем:
           three.js грузит канву с flipY, то есть нижняя строка картинки
           становится v=0, а у повёрнутой плоскости v=0 — это z=+TERRAIN.
           Одно переворачивание гасит другое. Если ошибиться, карта глубины
           окажется зеркальной по Z: озёра станут «берегом» и зальются пеной. */
        const x = (i / (DW - 1) - 0.5) * TERRAIN * 2;
        const z = (j / (DW - 1) - 0.5) * TERRAIN * 2;
        const d = Math.max(0, WATER_LEVEL - terrainH(x, z));
        raw[j * DW + i] = d;
        if (d > deepest) deepest = d;
      }
    }
    // размытие 3x3: сглаживает ступеньки на кромке
    const sm = new Float32Array(DW * DW);
    for (let j = 0; j < DW; j++) {
      for (let i = 0; i < DW; i++) {
        let acc = 0, n = 0;
        for (let dj = -1; dj <= 1; dj++) {
          const jj = j + dj; if (jj < 0 || jj >= DW) continue;
          for (let di = -1; di <= 1; di++) {
            const ii = i + di; if (ii < 0 || ii >= DW) continue;
            acc += raw[jj * DW + ii]; n++;
          }
        }
        sm[j * DW + i] = acc / n;
      }
    }
    for (let k = 0; k < DW * DW; k++) {
      const v = Math.min(255, (sm[k] / deepest) * 255);
      const o = k * 4;
      dd[o] = dd[o + 1] = dd[o + 2] = v; dd[o + 3] = 255;
    }
    dctx.putImageData(img, 0, 0);
  }
  // Цвет неба идёт в воду: по касательной она отражает именно его,
  // и без этого озеро не связано с окружением
  /* Палитра насыщенная, по референсу Red Alert 3: вода на тактической
     камере должна читаться как вода с первого взгляда, а не как серая
     плёнка. Отмель — яркая бирюза, глубина — густая синь. */
  const waterTint = config.biome === 'ice'
    ? { shallow: 0x1f93b4, deep: 0x0a2f4e, sky: 0xc8e2f2 }
    : config.biome === 'desert'
      ? { shallow: 0x199a8e, deep: 0x074a4a, sky: 0xe2cfa2 }
      : { shallow: 0x158da4, deep: 0x073055, sky: 0xa8ceea };
  const water = buildWater(TERRAIN, WATER_LEVEL, depthCv, waterTint);
  water.userData.setSun(sun.position.clone().normalize());
  scene.add(water);

  viewport.setBloom({ strength: 0.34, radius: 0.5, threshold: 0.84, exposure: 1.18 });

  // камни и растительность: масштаб и ощущение живой поверхности
  /* Камни. Додекаэдр читается как гранёная деталь конструктора, а не
     как валун. Берём сферу низкого разбиения, гнём её шумом и слегка
     приплющиваем — получается неровный обломок. Форм несколько, чтобы
     по карте не лежали клоны, и одеты они в тот же скан скалы, что
     и обрывы рельефа. */
  const rockMat = new THREE.MeshStandardMaterial({
    map: T.rock, normalMap: T.rockN, normalScale: new THREE.Vector2(1.2, 1.2),
    color: biome.rock || biome.accent, roughness: 0.95, metalness: 0,
  });
  const rockShapes = [];
  for (let v = 0; v < 4; v++) {
    const g = new THREE.IcosahedronGeometry(1, 2);
    const pos = g.attributes.position;
    const nz = new Noise(seed + 400 + v * 37);
    for (let i = 0; i < pos.count; i++) {
      const x = pos.getX(i), y = pos.getY(i), z = pos.getZ(i);
      // крупные грани плюс мелкая щербатость
      const big = nz.fbm3(x * 1.1, y * 1.1, z * 1.1, 3) * 0.34;
      const fine = nz.fbm3(x * 4.5, y * 4.5, z * 4.5, 2) * 0.11;
      const k = 1 + big + fine;
      pos.setXYZ(i, x * k, y * k * 0.78, z * k);   // приплюснутость
    }
    g.computeVertexNormals();
    g.userData.shared = true;
    rockShapes.push(g);
  }
  const rockGeo = rockShapes[0];
  const busy = [[-BX0, BX0, 90], [BX0, -BX0, 90]];   // рядом с базами не сорим
  const freeSpot = (x, z) => !busy.some(([bx, bz, r]) => Math.hypot(x - bx, z - bz) < r);
  for (let i = 0; i < (IS_TOUCH ? 70 : 120); i++) {
    const near = i % 2 === 0;
    const lim = near ? MAP * 0.95 : TERRAIN * 0.8;
    const x = rnd(-lim, lim), z = rnd(-lim, lim);
    // На дне камни читаются тёмными кляксами сквозь воду — не сорим туда
    if (isWater(x, z)) continue;
    const r = new THREE.Mesh(rockShapes[i % rockShapes.length], rockMat);
    r.castShadow = true; r.receiveShadow = true;
    const s = near ? rnd(2, 6) : rnd(4, 12);
    r.scale.set(s, s * rnd(0.5, 1), s);
    r.position.set(x, terrainH(x, z) + s * 0.3, z);
    r.rotation.set(rnd(0, 3), rnd(0, 3), rnd(0, 3));
    scene.add(r);
  }
  /* ── ПОДЛЕСОК.
     Раньше здесь было семьдесят пять отдельных ёлок — по мешу на
     дерево, и между ними голая крашеная сетка. Теперь трава и лес
     идут инстансами: одна геометрия на всю карту, у каждого кустика
     своя матрица. Десять тысяч травинок стоят одного вызова
     отрисовки, поэтому их можно позволить себе даже на планшете.

     Куда сажать, решает одна проверка: не в воду, не на крутой
     склон (там камень), не на площадки баз и не в поля снабжения. */
  const canPlant = (x, z) => {
    if (Math.abs(x) > MAP * 0.99 || Math.abs(z) > MAP * 0.99) return null;
    if (isWater(x, z)) return null;
    // Вокруг баз трава растёт, просто не в самом дворе: радиус вдвое
    // меньше, чем у камней, иначе рядом со штабом голая земля
    for (const [bx, bz] of [[-BX0, BX0], [BX0, -BX0]]) {
      if (Math.hypot(x - bx, z - bz) < 46) return null;
    }
    const y = terrainH(x, z);
    const d = 3;
    const slope = Math.hypot(
      (terrainH(x + d, z) - terrainH(x - d, z)) / (2 * d),
      (terrainH(x, z + d) - terrainH(x, z - d)) / (2 * d));
    if (slope > 0.55) return null;                       // на обрыве не растёт
    for (const [fx, fz] of FIELD_SPOTS) {
      if (Math.hypot(x - fx, z - fz) < 30) return null;  // не заслоняем склады
    }
    return { y, ok: true };
  };

  /* Подлесок по биому. Зелёная трава на снегу и в барханах — первое,
     что выдаёт подделку, поэтому меняем не только цвет, но и густоту:
     во льдах и песках это редкие сухие кустики, а не луг. */
  const FLORA = {
    green:  { n: 1.00, tint: 0xffffff },
    klotho: { n: 0.55, tint: 0x9d9464 },
    desert: { n: 0.30, tint: 0x8f8148 },
    ice:    { n: 0.22, tint: 0x6d7168 },
  };
  const flora = FLORA[config.biome];
  if (flora) {
    const grassTint = flora.tint;
    const grass = buildGrass(
      Math.round((IS_TOUCH ? 9000 : 26000) * flora.n), MAP, canPlant, grassTint);
    // Трава тень принимает, но не отбрасывает: двадцать шесть тысяч
    // травинок в карте теней стоят дороже, чем видно на глаз
    grass.receiveShadow = true;
    scene.add(grass);
  }
  scene.add(shadowed(buildTreeField(IS_TOUCH ? 90 : 180, MAP, canPlant, config.biome || 'rock')));

  // Колея от гусениц и колёс: техника пишет её на ходу
  const tracks = buildTrackField(IS_TOUCH ? 260 : 460);
  scene.add(tracks.mesh);
  // Копоть от взрывов: поле боя должно помнить, где горело
  const scorch = buildScorchField(IS_TOUCH ? 90 : 170);
  scene.add(scorch.mesh);

  const fx = new Fx(scene);
  fx.setCamera(tcam.cam);

  // ── СОСТОЯНИЕ ────────────────────────────────────────────
  const state = {
    units: [], buildings: [], proj: [], fields: [],
    time: 0, speed: 1, paused: false,
    selection: [], placing: null, rallyMode: false,
    playerSide: 'me',
    /* Орбитальная поддержка: что уцелело в космосе, то и доступно.
       aiming — выбранная, но ещё не наведённая способность; следующее
       касание по полю указывает ей точку. */
    support: {
      list: config.orbit || [],
      cd: {},              // id -> время, когда снова можно
      aiming: null,
      calls: [],           // отложенные удары: {id, at, pos, def}
    },
  };
  /* Уровень технологий приезжает с галактической карты и решает,
     какая техника вообще есть в меню. В быстром бою его не передают —
     тогда открыто всё, иначе половина ростера была бы недоступна. */
  const sides = {
    me: {
      faction: FACTIONS[config.player.faction], credits: config.player.credits ?? 3000,
      tech: config.player.tech ?? MAX_TECH, id: 'me',
    },
    foe: {
      faction: FACTIONS[config.enemy.faction], credits: config.enemy.credits ?? 3000,
      tech: config.enemy.tech ?? MAX_TECH, id: 'foe',
    },
  };
  const other = s => (s === 'me' ? 'foe' : 'me');

  /* Тени вешаем на всё, что стоит на земле. Принимать тень юнитам
     тоже нужно: танк, заехавший под дерево, должен потемнеть, иначе
     тень выглядит нарисованной на грунте, а не лежащей в мире. */
  function shadowed(obj, receive = true) {
    obj.traverse(o => {
      if (!o.isMesh && !o.isInstancedMesh) return;
      o.castShadow = true;
      o.receiveShadow = receive;
    });
    return obj;
  }
  let uid = 1;

  // ── ПОЛЯ СНАБЖЕНИЯ ───────────────────────────────────────
  for (const [x, z] of FIELD_SPOTS) {
    if (isWater(x, z)) continue;      // склад посреди озера — нелепо
    const obj = shadowed(buildSupplyField());
    obj.position.set(x, terrainH(x, z), z);
    scene.add(obj);
    state.fields.push({ kind: 'field', pos: obj.position, obj, left: 5000, uid: uid++ });
  }

  // ── СОЗДАНИЕ ─────────────────────────────────────────────
  function makeBuilding(sideId, defId, x, z, instant) {
    const def = GROUND_BUILDINGS[defId];
    const side = sides[sideId];
    const obj = shadowed(buildStructure(def, side.faction));
    const y = terrainH(x, z);
    obj.position.set(x, y, z);
    scene.add(obj);
    const b = {
      uid: uid++, kind: 'building', side: sideId, faction: side.faction, def,
      obj, pos: obj.position, cls: 'structure',
      hp: instant ? def.hp : def.hp * 0.15, maxHp: def.hp, armor: def.armor,
      dead: false, radius: def.size * 0.75,
      building: !instant, buildLeft: instant ? 0 : def.build,
      queue: [], produceLeft: 0,
      rally: new THREE.Vector3(x + rnd(-1, 1) * 18, y, z + 26),
      cd: 0, target: null,
    };
    obj.userData.entity = b;
    if (!instant) obj.scale.y = 0.25;
    state.buildings.push(b);
    return b;
  }

  function makeUnit(sideId, defId, x, z) {
    const side = sides[sideId];
    const def = unitDef(side.faction.id, defId);
    const obj = shadowed(buildGroundUnit(def, side.faction));
    const y = def.air ? 45 : terrainH(x, z);
    obj.position.set(x, y, z);
    scene.add(obj);
    const u = {
      uid: uid++, kind: 'unit', side: sideId, faction: side.faction, def,
      obj, pos: obj.position, cls: def.cls, air: !!def.air,
      hp: def.hp, maxHp: def.hp, armor: def.armor, dead: false,
      radius: def.cls === 'infantry' ? 3.2 : 5,
      moveTo: null, target: null, forced: null, cd: rnd(0, 1), retarget: rnd(0, 1),
      heading: rnd(0, 6.28), turretAngle: 0,
      ammo: def.ammo || 0, rearm: 0, phase: 'idle',
      carry: 0, field: null, homeBase: null,
      stealth: !!def.stealth, revealUntil: 0, exposed: false,
    };
    obj.userData.entity = u;
    obj.rotation.y = u.heading;
    state.units.push(u);
    return u;
  }

  // ── БАЗЫ ─────────────────────────────────────────────────
  function setupBase(sideId, bx, bz, garrison) {
    const hq = makeBuilding(sideId, 'hq', bx, bz, true);
    const away = bx > 0 ? -1 : 1;      // достройки — в сторону противника
    makeBuilding(sideId, 'barracks', bx + away * 40, bz + 8, true);
    makeBuilding(sideId, 'factory', bx - 8, bz - away * 42, true);
    for (let i = 0; i < 3; i++) {
      const u = makeUnit(sideId, 'worker', bx + rnd(-28, 28), bz + rnd(-28, 28));
      u.homeBase = hq;
    }
    // полки, привезённые с орбиты
    const roster = ['rifle', 'rifle', 'rocket', 'tank'];
    for (let i = 0; i < garrison; i++) {
      const id = roster[i % roster.length];
      const a = (i / Math.max(1, garrison)) * Math.PI * 2;
      makeUnit(sideId, id, bx + Math.cos(a) * rnd(40, 60), bz + Math.sin(a) * rnd(40, 60));
    }
    return hq;
  }
  const BX = BX0;
  const myHQ = setupBase('me', -BX, BX, config.player.regiments ?? 3);
  const foeHQ = setupBase('foe', BX, -BX, config.enemy.regiments ?? 3);
  if (config.enemy.turrets) {
    makeBuilding('foe', 'turret', BX - 52, -BX + 24, true);
    makeBuilding('foe', 'sam', BX + 24, -BX - 46, true);
  }

  // ── УРОН ─────────────────────────────────────────────────
  function damage(target, amount, weapon) {
    if (!target || target.dead) return;
    const mult = dmgMult(GROUND_DMG, weapon, target.cls);
    if (mult <= 0) return;
    target.hp -= amount * mult * (1 - (target.armor || 0));
    if (target.hp <= 0) destroy(target);
  }

  function splash(pos, radius, amount, weapon, side) {
    // Воронка на грунте: не на каждое попадание, а только на площадное
    if (radius > 8 && pos.y > WATER_LEVEL) {
      scorch.drop(pos.x, terrainH(pos.x, pos.z), pos.z,
        rnd(0, 6.28), radius * 1.7, radius * 1.7);
    }
    for (const list of [state.units, state.buildings]) {
      for (const e of list) {
        if (e.dead || e.side === side || e.air) continue;
        const d = e.pos.distanceTo(pos);
        if (d > radius) continue;
        damage(e, amount * (1 - d / radius * 0.6), weapon);
      }
    }
  }

  function destroy(e) {
    if (e.dead) return;
    e.dead = true;
    const size = e.kind === 'building' ? e.def.size * 1.5 : e.cls === 'infantry' ? 3 : 6;
    fx.explosion(e.pos, size, 0xffa050);
    if (e.kind === 'building') fx.shake = Math.min(1, fx.shake + 0.4);
    scene.remove(e.obj);
    state.selection = state.selection.filter(s => s !== e);
  }

  // ── СКРЫТНОСТЬ ───────────────────────────────────────────
  // Техника Рииза не видна, пока не откроет огонь; вплотную её
  // вскрывают любые войска, а дальше всех видят ЗСУ и зенитки.

  function hiddenU(u) {
    return !!u.stealth && state.time >= u.revealUntil && !u.exposed;
  }
  function revealU(u) {
    if (u.stealth) u.revealUntil = state.time + STEALTH.revealFor;
  }
  function updateExposure() {
    for (const u of state.units) {
      if (!u.stealth || u.dead) continue;
      u.exposed = false;
      const foe = other(u.side);
      for (const list of [state.units, state.buildings]) {
        for (const t of list) {
          if (t.dead || t.side !== foe) continue;
          const r = (t.def.id === 'aa' || t.def.id === 'sam')
            ? STEALTH.groundDetect * 1.8 : STEALTH.groundDetect;
          if (t.pos.distanceToSquared(u.pos) < r * r) { u.exposed = true; break; }
        }
        if (u.exposed) break;
      }
      // невидимую технику противника не рисуем вовсе
      u.obj.visible = !(hiddenU(u) && u.side !== 'me');
    }
  }

  // ── ПОИСК ────────────────────────────────────────────────
  function nearestEnemy(e, range, needAir) {
    const foe = other(e.side);
    let best = null, bd = range * range;
    for (const list of [state.units, state.buildings]) {
      for (const t of list) {
        if (t.dead || t.side !== foe) continue;
        if (t.air && !needAir) continue;
        if (t.kind === 'unit' && hiddenU(t)) continue;
        if (dmgMult(GROUND_DMG, e.def.weapon.type, t.cls) <= 0) continue;
        const d = t.pos.distanceToSquared(e.pos);
        if (d < bd) { bd = d; best = t; }
      }
    }
    return best;
  }

  // ── ДВИЖЕНИЕ ─────────────────────────────────────────────
  function moveGround(u, dest, dt, speedMul = 1) {
    _v.subVectors(dest, u.pos);
    _v.y = 0;
    const d = _v.length();
    if (d < 2.5) return true;
    _v.divideScalar(d);
    // расталкивание
    for (const o of state.units) {
      if (o === u || o.dead || o.air !== u.air) continue;
      const dd = o.pos.distanceTo(u.pos);
      const min = (o.radius + u.radius) * 1.15;
      if (dd < min && dd > 0.01) {
        _v2.subVectors(u.pos, o.pos).setY(0).divideScalar(dd).multiplyScalar((min - dd) / min * 1.4);
        _v.add(_v2);
      }
    }
    // вода: наземная техника в неё не лезет, разворачиваем вдоль берега
    if (!u.air) {
      const ahead = _v2.set(u.pos.x + _v.x * 6, 0, u.pos.z + _v.z * 6);
      if (isWater(ahead.x, ahead.z)) {
        // пробуем обойти: берём касательную к берегу
        const left = _v2.set(-_v.z, 0, _v.x);
        const okLeft = !isWater(u.pos.x + left.x * 8, u.pos.z + left.z * 8);
        _v.set(okLeft ? left.x : -left.x, 0, okLeft ? left.z : -left.z);
      }
    }

    // обход зданий
    for (const b of state.buildings) {
      if (b.dead) continue;
      const dd = b.pos.distanceTo(u.pos);
      const min = b.radius + u.radius + 1;
      if (dd < min && dd > 0.01) {
        _v2.subVectors(u.pos, b.pos).setY(0).divideScalar(dd).multiplyScalar((min - dd) / min * 2.2);
        _v.add(_v2);
      }
    }
    _v.normalize();
    const step = u.def.speed * speedMul * dt;
    u.moved0 = step;             // пройдено за кадр — по нему кладём колею
    u.pos.x = clamp(u.pos.x + _v.x * step, -MAP + 8, MAP - 8);
    u.pos.z = clamp(u.pos.z + _v.z * step, -MAP + 8, MAP - 8);
    u.pos.y = terrainH(u.pos.x, u.pos.z);
    const want = Math.atan2(-_v.x, -_v.z);
    let diff = ((want - u.heading + Math.PI) % (Math.PI * 2) + Math.PI * 2) % (Math.PI * 2) - Math.PI;
    u.heading += clamp(diff, -4 * dt, 4 * dt);
    u.obj.rotation.y = u.heading;
    return false;
  }

  function moveAir(u, dest, dt) {
    _v.subVectors(dest, u.pos);
    const d = _v.length();
    if (d < 4) return true;
    _v.divideScalar(d);
    const step = u.def.speed * dt;
    u.pos.addScaledVector(_v, step);
    u.pos.x = clamp(u.pos.x, -MAP, MAP);
    u.pos.z = clamp(u.pos.z, -MAP, MAP);
    const want = Math.atan2(-_v.x, -_v.z);
    let diff = ((want - u.heading + Math.PI) % (Math.PI * 2) + Math.PI * 2) % (Math.PI * 2) - Math.PI;
    u.heading += clamp(diff, -2.2 * dt, 2.2 * dt);
    u.obj.rotation.y = u.heading;
    u.obj.rotation.z = clamp(-diff * 0.9, -0.7, 0.7);
    return false;
  }

  /* ── ОРБИТАЛЬНАЯ ПОДДЕРЖКА ───────────────────────────────
     Обратная сторона «Давления Земли». Выигранная орбита не просто
     даёт право высадиться — уцелевшие корабли продолжают работать по
     поверхности. Погиб последний носитель в космосе — кнопка десанта
     на земле мертва. Именно это связывает два слоя. */

  function supportReady(id) {
    if (!state.support.list.includes(id)) return false;
    return (state.support.cd[id] || 0) <= state.time;
  }

  function callSupport(id, pos) {
    const def = ORBITAL_SUPPORT[id];
    if (!def || !supportReady(id) || !pos) return false;
    state.support.cd[id] = state.time + def.cooldown;
    state.support.calls.push({ id, def, pos: pos.clone(), at: state.time + def.delay });

    // Метка наводки: игрок должен видеть, куда и когда прилетит
    const mark = ringMesh(def.radius || 30, sides.me.faction.color);
    mark.position.set(pos.x, terrainH(pos.x, pos.z) + 0.6, pos.z);
    scene.add(mark);
    state.support.calls[state.support.calls.length - 1].mark = mark;
    toast(`${def.name}: наводка принята`);
    return true;
  }

  function updateSupport(dt) {
    const calls = state.support.calls;
    for (let i = calls.length - 1; i >= 0; i--) {
      const c = calls[i];
      if (state.time < c.at) continue;
      if (c.mark) { scene.remove(c.mark); c.mark = null; }
      resolveSupport(c);
      calls.splice(i, 1);
    }
  }

  function resolveSupport(c) {
    const d = c.def;
    const ground = new THREE.Vector3(c.pos.x, terrainH(c.pos.x, c.pos.z), c.pos.z);
    // Столб короткий и тонкий: длинный широкий цилиндр в аддитивном
    // смешивании засвечивает пол-экрана и прячет сам удар
    const sky = ground.clone().setY(ground.y + 240);

    if (d.id === 'strike') {
      // Главный калибр сверху: столб света и воронка
      fx.laser(sky, ground, { color: 0x9fe8ff, width: 1.8, life: 0.7 });
      fx.explosion(ground, d.radius * 0.6, 0xbfe8ff);
      fx.ring(ground, d.radius * 0.3, d.radius * 1.8, 0x9fe8ff, 0.55);
      fx.shake = Math.min(1, fx.shake + 0.5);
      splash(ground, d.radius, d.dmg, 'arty', 'me');

    } else if (d.id === 'drop') {
      // Капсулы с носителя: техника появляется прямо на месте
      for (let i = 0; i < d.count; i++) {
        const a = (i / d.count) * Math.PI * 2;
        const x = ground.x + Math.cos(a) * 11, z = ground.z + Math.sin(a) * 11;
        if (isWater(x, z)) continue;
        fx.beam(new THREE.Vector3(x, ground.y + 400, z), new THREE.Vector3(x, ground.y, z),
          { color: 0x8fffc8, width: 2.2, life: 0.6 });
        fx.ring(new THREE.Vector3(x, ground.y + 0.5, z), 3, 16, 0x8fffc8, 0.6);
        const u = makeUnit('me', d.unit, x, z);
        u.hp = u.maxHp;
      }
      fx.shake = Math.min(1, fx.shake + 0.25);

    } else if (d.id === 'emp') {
      // Обесточиваем чужие постройки: не стреляют и не производят
      fx.ring(ground, 4, d.radius, 0xc79fff, 1.1);
      let n = 0;
      for (const b of state.buildings) {
        if (b.dead || b.side === 'me') continue;
        if (b.pos.distanceTo(ground) > d.radius) continue;
        b.empUntil = state.time + d.disable;
        fx.flash(b.pos, 7, 0xc79fff, 0.5);
        n++;
      }
      toast(n ? `ЭМИ: обесточено построек — ${n}` : 'ЭМИ: в радиусе пусто');
    }
  }

  // ── СТРЕЛЬБА ─────────────────────────────────────────────
  function muzzleOf(e) {
    const list = e.obj.userData.muzzles || [new THREE.Vector3(0, 2, 0)];
    return list[0].clone().applyQuaternion(e.obj.quaternion).add(e.pos);
  }

  // Винт крутится всегда, пока машина жива: неподвижный вертолёт
  // читается как макет, а не как техника в воздухе
  function spinRotor(e, dt) {
    const r = e.obj.userData.rotor;
    if (r) r.rotation.y += dt * 26;
  }

  function aimTurret(e, target, dt) {
    const tur = e.obj.userData.turret;
    if (!tur || !target) return;
    const want = Math.atan2(target.pos.x - e.pos.x, target.pos.z - e.pos.z) - e.obj.rotation.y + Math.PI;
    let diff = ((want - tur.rotation.y + Math.PI) % (Math.PI * 2) + Math.PI * 2) % (Math.PI * 2) - Math.PI;
    tur.rotation.y += clamp(diff, -3 * dt, 3 * dt);
  }

  function tryFire(e, target, dt) {
    const w = e.def.weapon;
    if (!w || !target || target.dead) return;
    const d = e.pos.distanceTo(target.pos);
    if (d > w.range) return;
    if (w.minRange && d < w.minRange) return;
    if (target.air && !w.air && w.type !== 'aa') return;
    e.cd -= dt;
    if (e.cd > 0) return;
    e.cd = w.cd;
    if (e.kind === 'unit') revealU(e);    // выстрел срывает маскировку
    const from = muzzleOf(e);
    const mine = e.side === state.playerSide;

    if (w.arc) {
      for (let i = 0; i < (w.salvo || 1); i++) {
        spawnShell(e, target.pos.clone().add(_v.set(rnd(-6, 6), 0, rnd(-6, 6))), w, i * 0.18);
      }
      fx.flash(from, 4, 0xffd0a0, 0.2);
      fx.shake = Math.min(1, fx.shake + 0.1);
      return;
    }
    const color = mine ? 0x9fe8ff : 0xffb070;
    fx.tracer(from, target.pos, color, 0.1, w.type === 'cannon' ? 0.35 : 0.2);
    fx.flash(from, w.type === 'cannon' ? 2.6 : 1.4, 0xffe0b0, 0.14);
    if (w.splash) {
      fx.explosion(target.pos, w.splash * 0.7, 0xffa050);
      splash(target.pos, w.splash, w.dmg, w.type, e.side);
    } else {
      damage(target, w.dmg, w.type);
    }
  }

  function spawnShell(owner, dest, w, delay) {
    const from = muzzleOf(owner);
    state.proj.push({
      kind: 'shell', side: owner.side, from: from.clone(), to: dest.clone(),
      t: -delay, dur: Math.max(0.9, from.distanceTo(dest) / 130), w, dead: false,
    });
  }

  function updateShell(p, dt) {
    p.t += dt;
    if (p.t < 0) return;
    const k = p.t / p.dur;
    if (k >= 1) {
      p.dead = true;
      dest_impact(p);
      return;
    }
    _v.lerpVectors(p.from, p.to, k);
    _v.y += Math.sin(k * Math.PI) * 45;
    fx.flash(_v, 1.3, 0xffe0a0, 0.09);
  }
  function dest_impact(p) {
    fx.explosion(p.to, p.w.splash || 8, 0xffa050);
    fx.shake = Math.min(1, fx.shake + 0.14);
    splash(p.to, p.w.splash || 8, p.w.dmg, p.w.type, p.side);
  }

  // ── ЮНИТЫ ────────────────────────────────────────────────
  /* РЕМОНТНИК.
     Ищет самого побитого своего в радиусе и подливает ему прочность.
     Сам безоружен, поэтому в бою держится за спинами: без приказа
     подходит к раненому, с приказом — идёт куда сказали. */
  function updateEngineer(u, dt) {
    const def = u.def;
    if (u.moveTo && moveGround(u, u.moveTo, dt)) u.moveTo = null;

    u.retarget -= dt;
    if (!u.patient || u.patient.dead || u.patient.hp >= u.patient.maxHp || u.retarget <= 0) {
      u.patient = null;
      let worst = 1;
      for (const list of [state.units, state.buildings]) {
        for (const e of list) {
          if (e.dead || e.side !== u.side || e === u || e.building) continue;
          const frac = e.hp / e.maxHp;
          if (frac >= 1) continue;
          if (e.pos.distanceTo(u.pos) > def.repairRange * 3) continue;
          if (frac < worst) { worst = frac; u.patient = e; }
        }
      }
      u.retarget = rnd(0.6, 1.2);
    }
    if (!u.patient) return;

    const d = u.pos.distanceTo(u.patient.pos);
    if (d > def.repairRange) {
      if (!u.moveTo) moveGround(u, u.patient.pos, dt);
      return;
    }
    u.patient.hp = Math.min(u.patient.maxHp, u.patient.hp + def.repair * dt);
    u.repairBlink = (u.repairBlink || 0) - dt;
    if (u.repairBlink <= 0) {
      u.repairBlink = 0.55;
      fx.ring(u.patient.pos, 2.5, 7, 0x8fffc8, 0.35);
    }
  }

  function updateUnit(u, dt) {
    const def = u.def;
    spinRotor(u, dt);
    /* Отпечаток кладём не каждый кадр, а раз в несколько метров пути:
       иначе колея превращается в сплошную кляксу, а пул забивается
       за пару секунд. Авиация и пехота следов не оставляют. */
    if (def.cls === 'vehicle' && !u.air) {
      u.trackLeft = (u.trackLeft || 0) - (u.moved0 || 0);
      u.moved0 = 0;
      if (u.trackLeft <= 0) {
        u.trackLeft = 3.6;   // с запасом на перекрытие: колея сплошная
        const w = def.id === 'scout' ? 4.5 : 7;
        tracks.drop(u.pos.x, terrainH(u.pos.x, u.pos.z), u.pos.z, u.heading, w, 7);
      }
    }
    if (u.target && u.target.dead) u.target = null;
    if (u.forced && u.forced.dead) u.forced = null;

    // ── ремонтник: чинит соседнюю технику и постройки, сам не стреляет
    if (def.repair) {
      updateEngineer(u, dt);
      return;
    }

    // ── сборщик
    if (def.id === 'worker') {
      const hq = (u.homeBase && !u.homeBase.dead) ? u.homeBase
        : state.buildings.find(b => !b.dead && b.side === u.side && b.def.id === 'hq');
      u.homeBase = hq || null;
      if (u.moveTo) { if (moveGround(u, u.moveTo, dt)) u.moveTo = null; return; }
      if (!hq) return;
      if (u.carry >= def.cargo) {
        if (u.pos.distanceTo(hq.pos) < hq.radius + 9) {
          sides[u.side].credits += u.carry;
          u.carry = 0;
          fx.flash(hq.pos.clone().setY(hq.pos.y + 10), 6, 0xffd76a, 0.45);
        } else moveGround(u, hq.pos, dt);
        return;
      }
      if (!u.field || u.field.left <= 0) {
        let best = null, bd = Infinity;
        for (const f of state.fields) {
          if (f.left <= 0) continue;
          const d = f.pos.distanceToSquared(u.pos);
          if (d < bd) { bd = d; best = f; }
        }
        u.field = best;
      }
      if (!u.field) return;
      if (u.pos.distanceTo(u.field.pos) < 12) {
        const take = Math.min(def.cargo * 0.6 * dt, u.field.left, def.cargo - u.carry);
        u.carry += take;
        u.field.left -= take;
        if (u.field.left <= 0) u.field.obj.visible = false;
      } else moveGround(u, u.field.pos, dt);
      return;
    }

    // ── авиация: заход, боезапас, возврат
    if (u.air) {
      const field = state.buildings.find(b => !b.dead && b.side === u.side && b.def.id === 'airfield');
      if (u.phase === 'rearm') {
        u.rearm -= dt;
        u.obj.visible = false;
        if (u.rearm <= 0) {
          u.ammo = def.ammo;
          u.phase = 'idle';
          u.obj.visible = true;
          if (field) u.pos.set(field.pos.x, 45, field.pos.z);
        }
        return;
      }
      if (u.ammo <= 0) {
        if (!field) { u.phase = 'idle'; u.ammo = 1; }
        else {
          u.phase = 'home';
          if (moveAir(u, _v2.set(field.pos.x, 45, field.pos.z), dt)) {
            u.phase = 'rearm';
            u.rearm = def.rearm;
          }
          return;
        }
      }
      const t = u.forced || u.target || nearestEnemy(u, def.vision * 2.2, false);
      u.target = t;
      if (!t) {
        const anchor = field ? field.pos : (u.moveTo || u.pos);
        _v2.set(anchor.x + Math.sin(state.time * 0.5 + u.uid) * 60, 45,
                anchor.z + Math.cos(state.time * 0.5 + u.uid) * 60);
        moveAir(u, _v2, dt);
        return;
      }
      _v2.set(t.pos.x, 45, t.pos.z);
      moveAir(u, _v2, dt);
      const d = Math.hypot(t.pos.x - u.pos.x, t.pos.z - u.pos.z);
      u.cd -= dt;
      if (d < def.weapon.range && u.cd <= 0) {
        u.cd = def.weapon.cd;
        u.ammo--;
        const hit = t.pos.clone();
        fx.explosion(hit, def.weapon.splash, 0xffb060);
        fx.shake = Math.min(1, fx.shake + 0.12);
        fx.sparks(hit, 9, 0xffd08a, 22);
        splash(hit, def.weapon.splash, def.weapon.dmg, def.weapon.type, u.side);
      }
      return;
    }

    // ── наземные боевые
    u.retarget -= dt;
    if (!u.target || u.retarget <= 0) {
      u.target = u.forced || nearestEnemy(u, def.vision + (def.weapon ? def.weapon.range : 0),
        !!(def.weapon && def.weapon.air));
      u.retarget = rnd(0.5, 1.1);
    }

    if (u.moveTo) {
      if (moveGround(u, u.moveTo, dt)) u.moveTo = null;
      // на ходу стреляют все, кроме артиллерии
      if (u.target && def.weapon && !def.weapon.arc) { aimTurret(u, u.target, dt); tryFire(u, u.target, dt); }
      return;
    }

    if (u.target && def.weapon) {
      const d = u.pos.distanceTo(u.target.pos);
      const w = def.weapon;
      if (d > w.range) {
        if (u.forced) moveGround(u, u.target.pos, dt);      // приказ — идём добивать
        else if (d < def.vision * 1.6) moveGround(u, u.target.pos, dt);
      } else if (w.minRange && d < w.minRange) {
        _v2.subVectors(u.pos, u.target.pos).setY(0).setLength(w.minRange + 12).add(u.target.pos);
        moveGround(u, _v2, dt);
      }
      aimTurret(u, u.target, dt);
      tryFire(u, u.target, dt);
    }
  }

  // ── ЗДАНИЯ ───────────────────────────────────────────────
  function updateBuilding(b, dt) {
    // ЭМИ-удар с орбиты: постройка обесточена — не стреляет и не строит
    if (b.empUntil && state.time < b.empUntil) return;
    if (b.building) {
      b.buildLeft -= dt;
      const k = clamp(1 - b.buildLeft / Math.max(0.1, b.def.build), 0, 1);
      b.obj.scale.y = 0.25 + k * 0.75;
      b.hp = b.maxHp * (0.15 + k * 0.85);
      if (b.buildLeft <= 0) {
        b.building = false;
        b.obj.scale.y = 1;
        b.hp = b.maxHp;
        fx.flash(b.pos.clone().setY(b.pos.y + 6), b.def.size, 0xffd76a, 0.5);
      }
      return;
    }
    // производство
    if (b.queue.length) {
      b.produceLeft -= dt;
      if (b.produceLeft <= 0) {
        const id = b.queue.shift();
        const a = rnd(0, Math.PI * 2);
        const u = makeUnit(b.side, id, b.pos.x + Math.cos(a) * (b.def.size + 6), b.pos.z + Math.sin(a) * (b.def.size + 6));
        if (id === 'worker') u.homeBase = b;
        else u.moveTo = b.rally.clone();
        if (b.queue.length) b.produceLeft = unitDef(b.faction.id, b.queue[0]).build;
      }
    }
    // оборонительные башни
    if (b.def.weapon) {
      if (!b.target || b.target.dead) {
        b.target = nearestEnemy(b, b.def.weapon.range, !!b.def.weapon.air);
      }
      if (b.target) {
        if (b.target.air && !b.def.weapon.air) b.target = null;
        else { aimTurret(b, b.target, dt); tryFire(b, b.target, dt); }
      }
    }
  }

  function enqueue(b, unitId) {
    const def = unitDef(b.faction.id, unitId);
    const side = sides[b.side];
    if (side.credits < def.cost) return false;
    if (b.queue.length >= 6) return false;
    side.credits -= def.cost;
    b.queue.push(unitId);
    if (b.queue.length === 1) b.produceLeft = def.build;
    return true;
  }

  function canPlace(sideId, defId, x, z) {
    const def = GROUND_BUILDINGS[defId];
    if (Math.abs(x) > MAP - 20 || Math.abs(z) > MAP - 20) return false;
    if (isWater(x, z)) return false;
    // и края площадки тоже должны быть на суше
    for (const [dx, dz] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
      if (isWater(x + dx * def.size * 0.8, z + dz * def.size * 0.8)) return false;
    }
    let nearOwn = false;
    for (const b of state.buildings) {
      if (b.dead) continue;
      const d = Math.hypot(b.pos.x - x, b.pos.z - z);
      if (d < (b.def.size + def.size) * 0.75) return false;
      if (b.side === sideId && d < 130) nearOwn = true;
    }
    for (const f of state.fields) if (f.left > 0 && f.pos.distanceTo(_v.set(x, f.pos.y, z)) < 22) return false;
    return nearOwn;
  }

  // ── ИИ ───────────────────────────────────────────────────
  const ai = { next: 4, wave: 0, attacking: false };
  function updateAI(dt) {
    ai.next -= dt;
    if (ai.next > 0) return;
    ai.next = 3.5;
    const side = sides.foe;
    const mine = state.units.filter(u => !u.dead && u.side === 'foe');
    const myB = state.buildings.filter(b => !b.dead && b.side === 'foe');
    const has = id => myB.some(b => b.def.id === id && !b.building);
    const workers = mine.filter(u => u.def.id === 'worker').length;
    const army = mine.filter(u => u.def.id !== 'worker');

    const hq = myB.find(b => b.def.id === 'hq');
    if (!hq) return;

    // достройка базы
    const wish = [];
    if (!has('barracks') && !myB.some(b => b.def.id === 'barracks')) wish.push('barracks');
    if (!has('factory') && !myB.some(b => b.def.id === 'factory')) wish.push('factory');
    if (army.length > 4 && !myB.some(b => b.def.id === 'airfield')) wish.push('airfield');
    if (army.length > 6 && myB.filter(b => b.def.id === 'turret').length < 2) wish.push('turret');
    if (army.length > 8 && myB.filter(b => b.def.id === 'sam').length < 1) wish.push('sam');
    for (const w of wish) {
      const def = GROUND_BUILDINGS[w];
      if (side.credits < def.cost) break;
      for (let tries = 0; tries < 14; tries++) {
        const a = rnd(0, Math.PI * 2), r = rnd(35, 95);
        const x = hq.pos.x + Math.cos(a) * r, z = hq.pos.z + Math.sin(a) * r;
        if (canPlace('foe', w, x, z)) { side.credits -= def.cost; makeBuilding('foe', w, x, z, false); break; }
      }
      break;
    }

    // производство
    if (workers < 5) { const h = myB.find(b => b.def.id === 'hq'); if (h && !h.queue.length) enqueue(h, 'worker'); }
    const bar = myB.find(b => b.def.id === 'barracks' && !b.building);
    if (bar && bar.queue.length < 2) enqueue(bar, Math.random() < 0.55 ? 'rifle' : 'rocket');
    const fac = myB.find(b => b.def.id === 'factory' && !b.building);
    if (fac && fac.queue.length < 2) {
      const roll = Math.random();
      enqueue(fac, roll < 0.55 ? 'tank' : roll < 0.8 ? 'aa' : 'arty');
    }
    const air = myB.find(b => b.def.id === 'airfield' && !b.building);
    if (air && air.queue.length < 1 && mine.filter(u => u.air).length < 3) enqueue(air, 'jet');

    // волна
    if (!ai.attacking && army.length >= 6 + ai.wave) {
      ai.attacking = true;
      ai.wave = Math.min(6, ai.wave + 1);
      const targets = state.buildings.filter(b => !b.dead && b.side === 'me');
      const t = targets.find(b => b.def.id === 'hq') || targets[0];
      if (t) for (const u of army) { u.forced = t; u.moveTo = null; }
    } else if (ai.attacking && army.length < 3) {
      ai.attacking = false;
      for (const u of army) { u.forced = null; u.moveTo = hq.pos.clone(); }
    }
  }

  // ── HUD ──────────────────────────────────────────────────
  const hud = document.createElement('div');
  hud.className = 'hud hud-ground';
  hud.innerHTML = `
    <div class="topbar">
      <div class="res"><span class="credits" data-role="credits">0</span><small>кредитов</small></div>
      <div class="title" data-role="banner"></div>
      <div class="speedctl">
        <button data-speed="0" aria-label="Пауза">❚❚</button>
        <button data-speed="1" class="on">1×</button>
        <button data-speed="2">2×</button>
        <button data-speed="4">4×</button>
        <button data-role="retreat" class="danger">Сдаться</button>
      </div>
    </div>
    <div class="markers" data-role="markers"></div>
    <div class="sidebar">
      <button data-q="army">Все<br>войска</button>
      <button data-q="tank">Техника</button>
      <button data-q="infantry">Пехота</button>
      <button data-q="worker">Сбор-<br>щики</button>
      <button data-role="buildmenu">Строить</button>
      <button data-role="boxmode">Рамка</button>
    </div>
    <div class="buildbar" data-role="buildbar" style="display:none"></div>
    <div class="orbitbar" data-role="orbitbar"></div>
    <div class="botpanel">
      <div class="sel-info" data-role="sel"></div>
      <div class="sel-actions" data-role="acts"></div>
    </div>
    <div class="toasts" data-role="toasts"></div>
    <div class="hint" data-role="hint"></div>
    <div class="endcard" data-role="end" style="display:none"></div>
  `;
  hudRoot.appendChild(hud);
  const $ = r => hud.querySelector(`[data-role="${r}"]`);
  $('banner').textContent = config.title || 'Наземная операция';
  $('hint').innerHTML = IS_TOUCH
    ? 'Касание по своему — выбрать · по врагу — атаковать · по земле — идти · тянуть — карта · щипок — приближение · долгое нажатие — рамка'
    : 'ЛКМ — выбрать, рамкой — группу · ПКМ — приказ · колесо — приближение · WASD — карта';

  hud.querySelectorAll('[data-speed]').forEach(b => {
    b.onclick = () => {
      const v = +b.dataset.speed;
      state.paused = v === 0;
      if (v) state.speed = v;
      hud.querySelectorAll('[data-speed]').forEach(x => x.classList.toggle('on', +x.dataset.speed === v));
    };
  });
  $('retreat').onclick = () => finish('defeat');

  hud.querySelectorAll('[data-q]').forEach(b => {
    b.onclick = () => {
      const q = b.dataset.q;
      state.selection = state.units.filter(u => !u.dead && u.side === 'me' && (
        q === 'army' ? u.def.id !== 'worker'
          : q === 'worker' ? u.def.id === 'worker'
          : q === 'infantry' ? u.cls === 'infantry'
          : u.cls === 'vehicle' && u.def.id !== 'worker' || u.air));
      if (state.selection.length) {
        const c = new THREE.Vector3();
        for (const e of state.selection) c.add(e.pos);
        tcam.focus(c.divideScalar(state.selection.length));
      }
      refreshSel();
    };
  });

  const boxBtn = $('boxmode');
  boxBtn.onclick = () => controls.setBoxMode(!controls.boxMode);

  const buildbar = $('buildbar');
  $('buildmenu').onclick = () => {
    const open = buildbar.style.display === 'none';
    buildbar.style.display = open ? 'flex' : 'none';
    $('buildmenu').classList.toggle('on', open);
    if (open) renderBuildBar();
    else { state.placing = null; ghost.visible = false; }
  };

  function renderBuildBar() {
    buildbar.innerHTML = '';
    for (const id of ['barracks', 'factory', 'airfield', 'turret', 'sam']) {
      const def = GROUND_BUILDINGS[id];
      const b = document.createElement('button');
      b.className = 'build-btn';
      b.innerHTML = `<b>${def.name}</b><span class="cost">${def.cost}</span><small>${def.desc}</small>`;
      b.disabled = sides.me.credits < def.cost;
      b.onclick = () => {
        state.placing = id;
        buildbar.querySelectorAll('.build-btn').forEach(x => x.classList.remove('on'));
        b.classList.add('on');
      };
      buildbar.appendChild(b);
    }
  }

  // призрак постройки
  const ghost = new THREE.Mesh(
    new THREE.BoxGeometry(1, 1, 1),
    new THREE.MeshBasicMaterial({ color: 0x8fffc8, transparent: true, opacity: 0.35, depthWrite: false }),
  );
  ghost.visible = false;
  scene.add(ghost);

  // ── маркеры ──────────────────────────────────────────────
  const markers = $('markers');
  const markerPool = [];
  function updateMarkers() {
    const w = viewport.w, h = viewport.h;
    let i = 0;
    const all = [...state.buildings, ...state.units];
    for (const s of all) {
      if (s.dead) continue;
      if (s.kind === 'unit' && s.side === 'me' && s.hp >= s.maxHp && !state.selection.includes(s)) continue;
      if (s.kind === 'unit' && s.side !== 'me' && hiddenU(s)) continue;
      let d = markerPool[i];
      if (!d) {
        d = document.createElement('div');
        d.className = 'marker small';
        d.innerHTML = '<span class="mk-bar"><i></i></span>';
        markers.appendChild(d);
        markerPool[i] = d;
      }
      i++;
      const p = screenOf(_v.copy(s.pos).setY(s.pos.y + (s.kind === 'building' ? s.def.size * 0.9 : 6)), tcam.cam, w, h);
      if (p.z > 1 || p.x < -40 || p.x > w + 40 || p.y < -20 || p.y > h + 20) { d.style.display = 'none'; continue; }
      d.style.display = 'block';
      d.style.transform = `translate(${(p.x - 22) | 0}px,${(p.y - 8) | 0}px)`;
      const hp = clamp(s.hp / s.maxHp, 0, 1);
      const bar = d.firstChild.firstChild;
      bar.style.width = (hp * 100) + '%';
      bar.style.background = s.side === 'me' ? (hp > 0.4 ? '#7fd8a0' : '#e0a94e') : '#e05555';
      d.classList.toggle('sel', state.selection.includes(s));
    }
    for (; i < markerPool.length; i++) markerPool[i].style.display = 'none';
  }

  const selRings = [];
  function updateRings() {
    let i = 0;
    for (const e of state.selection) {
      if (e.dead) continue;
      if (!selRings[i]) {
        const r = ringMesh(1, 0x8fffc8, 0.9, 0.12);
        r.renderOrder = 4;
        scene.add(r);
        selRings[i] = r;
      }
      const r = selRings[i++];
      r.visible = true;
      r.position.copy(e.pos).setY(e.pos.y + (e.air ? -40 : 0.6));
      r.scale.setScalar(e.kind === 'building' ? e.def.size * 0.9 : e.radius * 2.2);
    }
    for (; i < selRings.length; i++) selRings[i].visible = false;
  }

  // ── управление ───────────────────────────────────────────
  function pickMeshes() {
    const m = [];
    for (const b of state.buildings) if (!b.dead) m.push(b.obj);
    for (const u of state.units) if (!u.dead) m.push(u.obj);
    return m;
  }
  function entityAt(x, y) {
    let ent = controls.pick(x, y);
    if (!ent) {
      const cands = [...state.units.filter(u => !u.dead && !(u.side !== 'me' && hiddenU(u))),
                     ...state.buildings.filter(b => !b.dead)];
      ent = controls.pickNear(x, y, cands, tcam.cam, viewport.w, viewport.h, IS_TOUCH ? 40 : 20);
    }
    return ent;
  }

  function selectEntity(ent, additive) {
    if (!ent) { if (!additive) state.selection = []; refreshSel(); return; }
    if (ent.side !== 'me') { state.selection = [ent]; refreshSel(); return; }
    if (additive) {
      state.selection = state.selection.includes(ent)
        ? state.selection.filter(x => x !== ent)
        : [...state.selection, ent];
    } else state.selection = [ent];
    refreshSel();
  }

  function issueOrder(ent, world) {
    const mine = state.selection.filter(s => s.side === 'me' && !s.dead);
    if (!mine.length) return false;
    // здание выделено — назначаем точку сбора
    const bld = mine.filter(s => s.kind === 'building');
    if (bld.length && world) {
      for (const b of bld) b.rally.copy(world);
      fx.flash(world, 6, 0x8fffc8, 0.5);
    }
    const units = mine.filter(s => s.kind === 'unit');
    if (!units.length) return bld.length > 0;

    if (ent && ent.side !== 'me') {
      for (const u of units) { u.forced = ent; u.target = ent; u.moveTo = null; }
      fx.flash(ent.pos, 6, 0xff6b5a, 0.5);
      return true;
    }
    if (!world) return false;
    const n = units.length, cols = Math.ceil(Math.sqrt(n));
    units.forEach((u, i) => {
      const col = i % cols, row = Math.floor(i / cols);
      const d = world.clone().add(_v.set((col - (cols - 1) / 2) * 9, 0, (row - (cols - 1) / 2) * 9));
      d.y = terrainH(d.x, d.z);
      u.moveTo = d;
      u.forced = null;
      u.target = null;
      if (u.def.id === 'worker') u.field = null;
    });
    fx.flash(world, 7, 0x8fffc8, 0.5);
    return true;
  }

  function tryPlace(world) {
    if (!state.placing || !world) return false;
    const def = GROUND_BUILDINGS[state.placing];
    if (sides.me.credits < def.cost) return false;
    if (!canPlace('me', state.placing, world.x, world.z)) {
      fx.flash(world, 8, 0xff5555, 0.4);
      return true;
    }
    sides.me.credits -= def.cost;
    makeBuilding('me', state.placing, world.x, world.z, false);
    state.placing = null;
    ghost.visible = false;
    buildbar.querySelectorAll('.build-btn').forEach(x => x.classList.remove('on'));
    renderBuildBar();
    return true;
  }

  const controls = new Controls(viewport.canvas, tcam, {
    pickMeshes,
    planeY: () => 0,
    onBoxModeChange: on => boxBtn.classList.toggle('on', on),
    onTap({ x, y, shift, touch }) {
      const world = controls.worldAt(x, y);
      if (state.support.aiming) {
        if (callSupport(state.support.aiming, world)) {
          state.support.aiming = null;
          refreshOrbit();
          return;
        }
      }
      if (state.placing) { if (tryPlace(world)) return; }
      const ent = entityAt(x, y);
      if (!touch) { selectEntity(ent, shift); return; }
      if (ent && ent.side === 'me') { selectEntity(ent, shift); return; }
      if (state.selection.some(s => s.side === 'me' && !s.dead)) {
        if (issueOrder(ent, world)) return;
      }
      selectEntity(ent, shift);
    },
    onOrder({ x, y }) {
      const world = controls.worldAt(x, y);
      if (state.placing) { state.placing = null; ghost.visible = false; return; }
      issueOrder(entityAt(x, y), world);
    },
    onBox(rect, additive) {
      const w = viewport.w, h = viewport.h;
      const found = [];
      for (const u of state.units) {
        if (u.dead || u.side !== 'me') continue;
        const p = screenOf(u.pos, tcam.cam, w, h);
        if (p.z < 1 && p.x >= rect.x0 && p.x <= rect.x1 && p.y >= rect.y0 && p.y <= rect.y1) found.push(u);
      }
      state.selection = additive ? [...new Set([...state.selection, ...found])] : found;
      refreshSel();
    },
  });

  // ── панель выделения ─────────────────────────────────────
  /* Короткие сообщения по центру — как в бою на орбите. Наводка,
     подтверждение удара, отчёт по ЭМИ: без них игрок не понимает,
     сработала способность или нет. */
  const toastBox = $('toasts');
  function toast(text) {
    const d = document.createElement('div');
    d.className = 'toast';
    d.textContent = text;
    toastBox.appendChild(d);
    setTimeout(() => d.classList.add('out'), 2600);
    setTimeout(() => d.remove(), 3400);
  }

  /* Панель орбитальной поддержки. Показываем ВСЕ три способности
     всегда: если корабля нужного класса в космосе не осталось, кнопка
     не исчезает, а покрывается помехами — игрок должен видеть, что он
     потерял и почему. */
  const orbitBar = $('orbitbar');
  const orbitBtns = {};
  for (const def of Object.values(ORBITAL_SUPPORT)) {
    const b = document.createElement('button');
    b.className = 'orbit-btn';
    b.innerHTML = `<b>${def.short}</b><small data-role="cd"></small><i></i>`;
    b.title = def.desc;
    b.onclick = () => {
      if (!supportReady(def.id)) return;
      state.support.aiming = state.support.aiming === def.id ? null : def.id;
      state.placing = null; ghost.visible = false;
      refreshOrbit();
    };
    orbitBar.appendChild(b);
    orbitBtns[def.id] = b;
  }

  function refreshOrbit() {
    for (const def of Object.values(ORBITAL_SUPPORT)) {
      const b = orbitBtns[def.id];
      const have = state.support.list.includes(def.id);
      const left = Math.ceil((state.support.cd[def.id] || 0) - state.time);
      b.classList.toggle('lost', !have);
      b.classList.toggle('on', state.support.aiming === def.id);
      b.disabled = !have || left > 0;
      b.querySelector('[data-role="cd"]').textContent =
        !have ? 'нет корабля' : left > 0 ? left + ' с' : 'готово';
    }
  }
  refreshOrbit();

  function refreshSel() {
    const sel = $('sel'), acts = $('acts');
    const list = state.selection.filter(s => !s.dead);
    acts.innerHTML = '';
    if (!list.length) {
      sel.innerHTML = '<div class="sel-empty">Ничего не выбрано</div>';
      return;
    }
    if (list.length === 1) {
      const e = list[0];
      const foreign = e.side !== 'me' ? '<span class="tag foe">противник</span>' : '';
      let sub = e.kind === 'building'
        ? (e.building ? `Строится · ${Math.ceil(e.buildLeft)} с` : e.def.name)
        : `${e.def.cls === 'infantry' ? 'Пехота' : e.air ? 'Авиация' : 'Техника'}`;
      if (e.def.id === 'worker') sub += ` · груз ${Math.round(e.carry)}/${e.def.cargo}`;
      if (e.air) sub += ` · боезапас ${e.ammo}/${e.def.ammo}`;
      sel.innerHTML = `<div class="sel-title">${e.def.name} ${foreign}</div>
        <div class="sel-sub">${sub} · ${Math.max(0, Math.round(e.hp))}/${e.maxHp}</div>
        <div class="sel-hpbar"><i style="width:${clamp(e.hp / e.maxHp, 0, 1) * 100}%"></i></div>
        <div class="sel-desc">${e.def.desc || ''}</div>`;
    } else {
      const by = {};
      for (const e of list) by[e.def.name] = (by[e.def.name] || 0) + 1;
      sel.innerHTML = `<div class="sel-title">Выделено: ${list.length}</div>
        <div class="sel-sub">${Object.entries(by).map(([n, c]) => `${n} ×${c}`).join(' · ')}</div>`;
    }

    // производство
    const prod = list.filter(e => e.kind === 'building' && e.side === 'me' && !e.building && e.def.produces);
    if (prod.length) {
      const b = prod[0];
      for (const id of b.def.produces) {
        const def = unitDef(b.faction.id, id);
        // Закрытую технику показываем серой: видно, ради чего копить науку
        const locked = (def.tier || 1) > sides.me.tech;
        const btn = document.createElement('button');
        btn.className = 'act' + (locked ? ' locked' : '');
        btn.innerHTML = `<b>${def.name}</b><small>${locked
          ? `нужен ${def.tier}-й уровень технологий`
          : `${def.cost} кр · ${def.build} с`}</small>`;
        btn.disabled = locked || sides.me.credits < def.cost;
        btn.onclick = () => { if (!locked && enqueue(b, id)) refreshSel(); };
        acts.appendChild(btn);
      }
      if (b.queue.length) {
        const q = document.createElement('div');
        q.className = 'act-note';
        q.textContent = `В очереди: ${b.queue.length} · готов через ${Math.ceil(b.produceLeft)} с`;
        acts.appendChild(q);
      }
    }
    const units = list.filter(e => e.kind === 'unit' && e.side === 'me');
    if (units.length) {
      const stop = document.createElement('button');
      stop.className = 'act';
      stop.innerHTML = '<b>Стоп</b><small>Отменить приказ</small>';
      stop.onclick = () => { for (const u of units) { u.moveTo = null; u.forced = null; } };
      acts.appendChild(stop);
    }
  }
  refreshSel();

  function onKey(e) {
    if (e.target && /input|textarea/i.test(e.target.tagName)) return;
    if (e.code === 'Space') { e.preventDefault(); hud.querySelector(`[data-speed="${state.paused ? state.speed : 0}"]`).click(); }
    if (e.code === 'Escape') { state.selection = []; state.placing = null; state.support.aiming = null;
      ghost.visible = false; refreshSel(); refreshOrbit(); }
  }
  addEventListener('keydown', onKey);

  // ── завершение ───────────────────────────────────────────
  let ended = false;
  function finish(result) {
    if (ended) return;
    ended = true;
    state.paused = true;
    const win = result === 'victory';
    const card = $('end');
    card.style.display = 'flex';
    card.innerHTML = `<div class="end-inner">
      <h2>${win ? 'Планета взята' : 'Плацдарм потерян'}</h2>
      <p>${win ? 'Наземные силы противника уничтожены. Система переходит под наш контроль.'
                : 'Десант разбит. Планета остаётся за противником.'}</p>
      <button class="btn primary" data-role="cont">Продолжить</button></div>`;
    card.querySelector('[data-role="cont"]').onclick = () => {
      const left = state.units.filter(u => !u.dead && u.side === 'me' && u.def.id !== 'worker').length;
      config.onEnd && config.onEnd({ result, regiments: Math.max(0, Math.round(left / 2)) });
    };
  }

  function checkEnd() {
    if (ended) return;
    const foeAlive = state.buildings.some(b => !b.dead && b.side === 'foe')
                  || state.units.some(u => !u.dead && u.side === 'foe' && u.def.id !== 'worker');
    const meAlive = state.buildings.some(b => !b.dead && b.side === 'me')
                 || state.units.some(u => !u.dead && u.side === 'me');
    if (!foeAlive) finish('victory');
    else if (!meAlive) finish('defeat');
  }

  // ── цикл ─────────────────────────────────────────────────
  function update(rawDt) {
    tcam.update(rawDt);
    const dt = state.paused ? 0 : Math.min(rawDt, 0.05) * state.speed;
    if (dt > 0) {
      state.time += dt;
      updateExposure();
      updateAI(dt);
      for (const b of state.buildings) if (!b.dead) updateBuilding(b, dt);
      updateSupport(dt);
      tracks.tick(dt);
      scorch.tick(dt);
      refreshOrbit();
      for (const u of state.units) if (!u.dead) updateUnit(u, dt);
      for (const p of state.proj) if (!p.dead) updateShell(p, dt);
      state.proj = state.proj.filter(p => !p.dead);
      if (state.units.length > 260) state.units = state.units.filter(u => !u.dead);
      checkEnd();
    }

    fx.update(rawDt);
    water.userData.tick(performance.now() * 0.001);
    if (fx.shake > 0.001) {
      const s = fx.shake * 1.6;
      tcam.cam.position.x += rnd(-s, s);
      tcam.cam.position.y += rnd(-s, s);
    }

    // призрак постройки под курсором/пальцем
    if (state.placing) {
      const def = GROUND_BUILDINGS[state.placing];
      const p = controls.worldAt(
        viewport.canvas.getBoundingClientRect().left + viewport.w / 2,
        viewport.canvas.getBoundingClientRect().top + viewport.h / 2);
      if (p) {
        ghost.visible = true;
        ghost.scale.set(def.size * 1.3, 6, def.size * 1.3);
        ghost.position.set(p.x, terrainH(p.x, p.z) + 3, p.z);
        ghost.material.color.set(canPlace('me', state.placing, p.x, p.z) ? 0x8fffc8 : 0xff6b5a);
      }
    } else ghost.visible = false;

    updateMarkers();
    updateRings();
    $('credits').textContent = Math.floor(sides.me.credits);

    if (state.selection.some(s => s.dead)) {
      state.selection = state.selection.filter(s => !s.dead);
      refreshSel();
    }
  }

  function dispose() {
    removeEventListener('keydown', onKey);
    tcam.dispose();
    controls.dispose();
    hud.remove();
    disposeScene(scene);
  }

  tcam.focus(myHQ.pos.clone());
  tcam.apply(1, true);

  // Состояние наружу — по нему автотесты проверяют юнитов и ремонт.
  // На игру не влияет, читать можно из консоли.
  if (typeof window !== 'undefined') {
    window.__gr = state;
    state.callSupportTest = (id, x, z) =>
      callSupport(id, new THREE.Vector3(x, terrainH(x, z), z));
    state.spawnTest = (id, x, z, side = 'me') => makeUnit(
      side, id,
      x === undefined ? rnd(-60, 60) : x,
      z === undefined ? rnd(-60, 60) : z);
  }
  return { scene, camera: tcam.cam, update, dispose, state };
}

// Быстрый расчёт наземного боя
export function autoResolveGround(attacker, defender) {
  const p = s => (s.regiments || 0) * (s.faction === 'reez' ? 1.15 : s.faction === 'troyden' ? 1.1 : 0.95)
    + (s.turrets ? 1.5 : 0);
  const a = p(attacker) * rnd(0.85, 1.2);
  const d = (p(defender) + 1) * rnd(0.85, 1.2);
  const win = a > d;
  return {
    result: win ? 'attacker' : 'defender',
    regiments: Math.max(0, Math.round((win ? attacker.regiments - d * 0.6 : defender.regiments - a * 0.6))),
  };
}
