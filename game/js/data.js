/* КАПЕЛЛА: ГАЛАКТИЧЕСКИЙ ФРОНТ — игровые данные.
   Сеттинг взят у Homeplanet (Revolt Games, 2003): система Капелла,
   двадцать семь кланов, изгнание клана Тройден с родной планеты Клото,
   ньютоновская физика полёта и нейроинтерфейс пилота.

   Здесь только числа и названия. Логика — в space.js, ground.js,
   galaxy.js. Правишь баланс — правишь этот файл. */

// ─────────────────────────────────────────────────────────────
// ТАБЛИЦЫ УРОНА
// «Камень-ножницы-бумага»: множитель урона оружия по классу цели.
// 0 — оружие вообще не может достать такую цель.
// ─────────────────────────────────────────────────────────────

export const SPACE_DMG = {
  // Главный калибр: редко, но насмерть. По мелочи не наводится вообще.
  heavy:   { capital: 1.00, carrier: 1.00, escort: 1.25, strike: 0.00, torpedo: 0.00 },
  // Ракетный залп: слабее главного калибра, но чаще. Ракеты сбиваемы.
  missile: { capital: 0.85, carrier: 0.95, escort: 1.00, strike: 0.00, torpedo: 0.00 },
  // Средние орудия эскорта
  light:   { capital: 0.30, carrier: 0.45, escort: 1.00, strike: 0.20, torpedo: 0.00 },
  // ПВО. Работает само и только по мелочи
  pd:      { capital: 0.00, carrier: 0.00, escort: 0.00, strike: 1.00, torpedo: 1.40 },
  // Перехватчик — убийца авиации, по большим кораблям бесполезен
  gunInt:  { capital: 0.04, carrier: 0.08, escort: 0.15, strike: 1.50, torpedo: 1.00 },
  // Истребитель — по всему средне
  gunFig:  { capital: 0.22, carrier: 0.32, escort: 0.55, strike: 0.85, torpedo: 0.35 },
  // Бомбардировщик — торпеды строго по крупным целям
  torp:    { capital: 1.00, carrier: 1.00, escort: 0.55, strike: 0.00, torpedo: 0.00 },
};

export const GROUND_DMG = {
  rifle:   { infantry: 1.00, vehicle: 0.14, structure: 0.18, air: 0.00 },
  at:      { infantry: 0.40, vehicle: 1.00, structure: 0.70, air: 0.75 },
  cannon:  { infantry: 0.50, vehicle: 1.00, structure: 0.95, air: 0.00 },
  arty:    { infantry: 1.25, vehicle: 0.80, structure: 1.40, air: 0.00 },
  aa:      { infantry: 0.15, vehicle: 0.10, structure: 0.00, air: 1.60 },
  bomb:    { infantry: 0.90, vehicle: 1.15, structure: 1.30, air: 0.00 },
};

export function dmgMult(table, weapon, targetClass) {
  const row = table[weapon];
  if (!row) return 1;
  const m = row[targetClass];
  return m === undefined ? 1 : m;
}

// ─────────────────────────────────────────────────────────────
// КЛАНЫ
//
// Тройден  — технологичный кулак: дорого, мало, но каждый юнит сильнее
//            чужого. Ближе всего к США из Generals.
// Плэктор  — рой: дёшево, быстро, много. По одному не стоит ничего,
//            толпой сносит всё.
// Рииз   — спецоперации: скрытность у всех юнитов без исключения,
//            мощные орудия, но броня бумажная.
// ─────────────────────────────────────────────────────────────

const TROYDEN = {
  id: 'troyden',
  name: 'Клан Тройден',
  short: 'Тройден',
  tag: 'ТРД',
  color: 0x5ac8e0,
  colorCss: '#5ac8e0',
  style: 'sleek',
  doctrine: 'tech',
  motto: 'Нас мало. Значит, каждый должен стоить десятерых',
  desc: 'Самый малочисленный из двадцати семи кланов Капеллы и признанный ' +
        'лидер в высоких технологиях. Корабли строит подземный комплекс ' +
        'LT-Farm, основанный Лансом Тройденом. Техника дороже чужой вдвое ' +
        'и стоит этих денег: броня, наведение, ПВО и авиакрылья лучшие ' +
        'в системе. Но потери восполнять нечем.',
  perks: [
    'Каждый юнит крепче и точнее чужого того же класса',
    'ПВО и авиакрылья — лучшие в системе',
    'Главный калибр стреляет чаще: лучше охлаждение',
  ],
  weakness: 'Всё дороже на треть и строится дольше. Размен не в нашу пользу',
};

const PLEKTOR = {
  id: 'plektor',
  name: 'Клан Плэктор',
  short: 'Плэктор',
  tag: 'ПЛК',
  color: 0xe0b34e,
  colorCss: '#e0b34e',
  style: 'scrap',
  doctrine: 'swarm',
  motto: 'Числом, а не числами',
  desc: 'Тот самый клан, что сжёг LT-Farm и вместе с Риизом выдавил ' +
        'Тройден с Клото. Корабли неказистые: истребитель «Бронко» ' +
        'летает отвратительно, зато хорошо защищён, а бомбардировщики ' +
        '«Шерман» возят мало бомб — поэтому летают звеньями вдвое ' +
        'больше обычных. Плэктор воюет не качеством, а количеством.',
  perks: [
    'Всё вдвое дешевле и строится вдвое быстрее',
    'Носители несут на два звена больше',
    'Кораблей и полков за те же деньги выходит втрое больше',
  ],
  weakness: 'Поодиночке беспомощны: тонкая броня, слабые орудия',
};

const REEZ = {
  id: 'reez',
  name: 'Клан Рииз',
  short: 'Рииз',
  tag: 'РИЗ',
  color: 0xb07ae0,
  colorCss: '#b07ae0',
  style: 'stealth',
  doctrine: 'stealth',
  motto: 'Тебя убьёт то, чего ты не видел',
  desc: 'Клан без собственных верфей для больших кораблей: единственный ' +
        'линейный корабль «Касатка» построен на заказ и несёт всю ударную ' +
        'мощь клана. Отсюда доктрина — скрытность вместо брони. Вся ' +
        'техника Рииза несёт маскировочное поле и не видна, пока не ' +
        'откроет огонь; орудия при этом бьют больнее чужих.',
  perks: [
    'Скрытность у всех юнитов: невидимы, пока не выстрелят',
    'Орудия бьют на четверть сильнее',
    'Раскрытые снова исчезают через несколько секунд',
  ],
  weakness: 'Броня вдвое тоньше. Раскрытый риизец живёт недолго',
};

export const FACTIONS = { troyden: TROYDEN, reez: REEZ, plektor: PLEKTOR };
export const FACTION_IDS = ['troyden', 'reez', 'plektor'];

// Скрытность: сколько секунд юнит виден после выстрела и с какого
// расстояния его вскрывает противник, даже пока он молчит.
export const STEALTH = { revealFor: 5.0, detectRange: 130, groundDetect: 55 };

// Радиоэлектронная борьба. «Сайленсер» — канонический корабль РЭБ
// клана Тройден; здесь это отдельный класс у всех трёх кланов.
export const ECM = {
  radius: 380,          // радиус купола
  lockRange: 170,       // ближе этого расстояния наведение всё же работает
  missileBlind: true,   // ракеты и торпеды теряют наведение внутри купола
  pdPenalty: 0.55,      // чужое ПВО внутри купола бьёт вполсилы
  spinUp: 2.5,          // секунд на разворачивание купола
};

// ─────────────────────────────────────────────────────────────
// КОСМИЧЕСКИЕ КОРАБЛИ
//
// Названия — из канона Homeplanet (elite-games.ru, раздел «Корабли»).
// Что канон, а что достроено мной, помечено полем canon.
//
// Полёт ньютоновский: thrust даёт ускорение, а не скорость;
// разворот корпуса от вектора не зависит.
// Гипер: hyperCharge — секунды накачки перехода, всё это время
// корабль беззащитен. flee — порог, ниже которого уходит сам.
// ─────────────────────────────────────────────────────────────

const SQUAD_SIZE = 5;

export const STRIKE_ROLES = {
  interceptor: { label: 'Перехватчик', short: 'ПХВ', hint: 'Бьёт вражескую авиацию и сбивает торпеды' },
  fighter:     { label: 'Истребитель', short: 'ИСТ', hint: 'Универсал: по всему средне' },
  bomber:      { label: 'Бомбардировщик', short: 'БМБ', hint: 'Торпеды по крупным кораблям, в бою беспомощен' },
};

// canon: true — название и роль взяты из игры; false — достроено
const STRIKE_NAMES = {
  troyden: {
    interceptor: { name: '«Зонг»', canon: true },
    fighter:     { name: '«Рекс»', canon: true },
    bomber:      { name: '«Паларм»', canon: true },
  },
  reez: {
    interceptor: { name: '«Акула»', canon: true },
    fighter:     { name: '«Пиранья»', canon: true },
    bomber:      { name: '«Нарвал»', canon: false },
  },
  plektor: {
    interceptor: { name: '«Драккар»', canon: true },
    fighter:     { name: '«Бронко»', canon: true },
    bomber:      { name: '«Шерман»', canon: true },
  },
};

function strikeCraft(faction) {
  const trd = faction === 'troyden', plk = faction === 'plektor', rez = faction === 'reez';
  const tough = trd ? 1.3 : rez ? 0.75 : 0.95;   // «Бронко» неповоротлив, но живуч
  const gun = trd ? 1.15 : rez ? 1.25 : 0.85;
  const N = STRIKE_NAMES[faction];
  const mk = (id, role, hp, speed, thrust, turn, weapon, dmg, cd, range, extra) => ({
    id, role, name: N[role].name, canon: N[role].canon, cls: 'strike',
    hp: Math.round(hp * tough), armor: role === 'bomber' ? 0.1 : role === 'fighter' ? 0.05 : 0,
    maxSpeed: speed, thrust, turn,
    weapon, dmg: dmg * gun, cd, range, stealth: rez, ...(extra || {}),
  });
  // Плэкторовский «Драккар»: огромная скорость, низкая манёвренность
  const turnMod = plk ? 0.75 : 1;
  return {
    interceptor: mk('interceptor', 'interceptor', 70, plk ? 175 : 155, 105, 2.7 * turnMod, 'gunInt', 14, 0.5, 60),
    fighter:     mk('fighter', 'fighter', 95, 128, 82, 2.1 * turnMod, 'gunFig', 17, 0.62, 66),
    bomber:      mk('bomber', 'bomber', 150, 84, 44, 1.15, 'torp', 140, 6.5, 95, { torpedo: true }),
  };
}

/* Шесть классов на клан.
   Тройден и Плэктор названы строго по канону; у Рииза канон даёт
   только «Касатку», поэтому остальные достроены в его же манере —
   морские хищники. */
const SHIP_NAMES = {
  troyden: {
    corvette: { name: 'Корвет «Гроссер»', canon: true },
    frigate:  { name: 'Фрегат «Диксон»', canon: true },
    ecm:      { name: 'Корабль РЭБ «Сайленсер»', canon: true },
    cruiser:  { name: 'Линейный крейсер «Ховард»', canon: true },
    carrier:  { name: 'Носитель «Хантер»', canon: true },
    capital:  { name: 'Флагман «Ланселот»', canon: true },
  },
  reez: {
    corvette: { name: 'Корвет «Барракуда»', canon: false },
    frigate:  { name: 'Фрегат «Мурена»', canon: false },
    ecm:      { name: 'Корабль РЭБ «Скат»', canon: false },
    cruiser:  { name: 'Крейсер «Марлин»', canon: false },
    carrier:  { name: 'Носитель «Касатка»', canon: true },
    capital:  { name: 'Линкор «Кашалот»', canon: false },
  },
  plektor: {
    corvette: { name: 'Корвет «Исса»', canon: true },
    frigate:  { name: 'Фрегат «Севен Клоз»', canon: true },
    ecm:      { name: 'Корабль РЭБ «Уайт Шарк»', canon: true },
    cruiser:  { name: 'Крейсер «Рэш»', canon: true },
    carrier:  { name: 'Носитель «Норман»', canon: true },
    capital:  { name: 'Флагман «Орк»', canon: true },
  },
};

function shipsFor(faction) {
  const trd = faction === 'troyden', plk = faction === 'plektor', rez = faction === 'reez';
  const hpMod    = trd ? 1.30 : plk ? 0.68 : 0.82;
  const armorMod = trd ? 1.25 : plk ? 0.75 : 0.55;
  const gunMod   = trd ? 1.10 : plk ? 0.78 : 1.25;
  const costMod  = trd ? 1.35 : plk ? 0.50 : 0.95;
  const buildMod = trd ? 1.30 : plk ? 0.50 : 1.0;
  const pdRange  = trd ? 1.35 : rez ? 0.85 : 1.0;
  const pdDmg    = trd ? 1.30 : rez ? 0.85 : 0.9;
  const cdMod    = trd ? 0.9 : 1.0;

  const N = SHIP_NAMES[faction];
  const H = h => Math.round(h * hpMod);
  const A = a => Math.min(0.6, +(a * armorMod).toFixed(3));
  const C = c => Math.round(c * costMod / 10) * 10;
  const G = d => Math.round(d * gunMod);

  const base = [
    {
      id: 'corvette', cls: 'escort', tier: 1, role: 'Корвет · разведка и ПВО',
      hp: 620, armor: 0.12, maxSpeed: 46, thrust: 18, turn: 0.7, radius: 5,
      cost: 220, build: 1, hyperCharge: 5,
      guns: [{ type: 'light', dmg: 40, cd: 2.2, range: 220 }],
      pd: { count: 2, dmg: 15, cd: 0.26, range: 120 },
      desc: 'Самый дешёвый корабль и самый быстрый. Видит дальше всех — ' +
            'именно корветы вскрывают маскировку Рииза. В линейном бою ' +
            'живёт полминуты.',
    },
    {
      id: 'frigate', cls: 'escort', tier: 1, role: 'Фрегат · зонт ПВО',
      hp: 1000, armor: 0.18, maxSpeed: 34, thrust: 11, turn: 0.55, radius: 6.5,
      cost: 380, build: 1, hyperCharge: 6,
      guns: [{ type: 'light', dmg: 66, cd: 2.6, range: 270 }],
      pd: { count: 4, dmg: 17, cd: 0.26, range: 130 },
      desc: 'Рабочая лошадь охранения. Главное — зенитки: без фрегатов ' +
            'звено бомбардировщиков разберёт линкор на болты.',
    },
    {
      id: 'ecm', cls: 'escort', tier: 2, role: 'РЭБ · глушение',
      hp: 1400, armor: 0.20, maxSpeed: 30, thrust: 9, turn: 0.5, radius: 8,
      cost: 720, build: 2, hyperCharge: 8, ecm: true,
      guns: [],
      pd: { count: 2, dmg: 14, cd: 0.3, range: 120 },
      desc: 'Разворачивает купол помех. Внутри купола чужой главный ' +
            'калибр не может взять цель на дальней дистанции, ракеты ' +
            'теряют наведение, ПВО бьёт вполсилы, а маскировку никто ' +
            'не вскрывает. Можно переключить на защитный режим — тогда ' +
            'купол наоборот прикрывает своих от чужих помех.',
    },
    {
      id: 'cruiser', cls: 'capital', tier: 2, role: 'Крейсер · тяжёлый лазер',
      hp: 2600, armor: 0.30, maxSpeed: 22, thrust: 4.2, turn: 0.30, radius: 12,
      cost: 980, build: 2, hyperCharge: 9,
      guns: [{ type: 'heavy', dmg: 430, cd: 9, range: 780, charge: 1.3 }],
      pd: { count: 3, dmg: 14, cd: 0.32, range: 115 },
      desc: 'Один тяжёлый лазер. Копит энергию секунду, потом бьёт лучом, ' +
            'от которого корвет испаряется целиком. По истребителям ' +
            'не наводится вообще.',
    },
    {
      id: 'carrier', cls: 'carrier', tier: 2, role: 'Носитель',
      hp: 3100, armor: 0.22, maxSpeed: 18, thrust: 3.0, turn: 0.24, radius: 15,
      cost: 1150, build: 3, hyperCharge: 12,
      guns: [],
      pd: { count: 5, dmg: 15, cd: 0.3, range: 135 },
      hangar: 3,
      desc: 'Своего оружия нет — только ПВО. Вся сила в ангаре. Уход ' +
            'носителя в гипер означает, что бой проигран: без него ' +
            'флот остаётся без авиации и без ремонта.',
    },
    {
      id: 'capital', cls: 'capital', tier: 3, role: 'Флагман · главный калибр',
      hp: 5400, armor: 0.38, maxSpeed: 16, thrust: 2.5, turn: 0.17, radius: 22,
      cost: 2300, build: 4, hyperCharge: 14, flee: 0.2,
      guns: [
        { type: 'heavy', dmg: 820, cd: 12, range: 900, charge: 1.8 },
        { type: 'heavy', dmg: 820, cd: 12, range: 900, charge: 1.8 },
      ],
      pd: { count: 6, dmg: 18, cd: 0.26, range: 145 },
      desc: 'Две башни главного калибра. Разгоняется полминуты и столько ' +
            'же тормозит. Получив больше 80% повреждений, уходит в гипер ' +
            'сам — командир флагмана не спрашивает разрешения.',
    },
  ];

  return base.map(d => {
    const bays = d.hangar ? d.hangar + (plk ? 2 : trd ? 0 : -1) : null;
    return {
      ...d,
      name: N[d.id].name,
      canon: N[d.id].canon,
      role: d.hangar ? `Носитель · ${bays} звена` : d.role,
      hp: H(d.hp),
      armor: A(d.armor),
      cost: C(d.cost),
      build: Math.max(1, Math.round(d.build * buildMod)),
      stealth: rez,
      hangar: bays,
      guns: (d.guns || []).map(g => ({ ...g, dmg: G(g.dmg), cd: +(g.cd * cdMod).toFixed(2) })),
      pd: d.pd ? {
        ...d.pd,
        dmg: +(d.pd.dmg * pdDmg).toFixed(1),
        range: Math.round(d.pd.range * pdRange),
      } : null,
    };
  });
}

export const SHIPS = {};
export const STRIKE = {};
for (const f of FACTION_IDS) {
  SHIPS[f] = shipsFor(f);
  STRIKE[f] = strikeCraft(f);
}
export { SQUAD_SIZE };

export function shipDef(faction, id) {
  return SHIPS[faction].find(s => s.id === id);
}

export const STATION = {
  id: 'station', cls: 'capital', name: 'Орбитальная станция', role: 'Неподвижная крепость',
  hp: 6500, armor: 0.42, maxSpeed: 0, thrust: 0, turn: 0.12, radius: 26, cost: 1400,
  hyperCharge: 0, station: true,
  guns: [{ type: 'heavy', dmg: 640, cd: 10, range: 920, charge: 1.5 }],
  pd: { count: 8, dmg: 18, cd: 0.24, range: 155 },
  hangar: 1,
  desc: 'Неподвижная крепость на орбите. Главный калибр, восемь батарей ПВО ' +
        'и звено перехватчиков. В гипер уйти не может — стоит до конца.',
};

// Подкрепления из гиперпространства: сколько ждать и по чём
export const HYPER = {
  reinforceDelay: 32,     // секунд от вызова до выхода из гипера
  jumpCharge: 1.0,        // множитель к hyperCharge корабля
  fleeThreshold: 0.2,     // линкор уходит сам ниже этой доли прочности
};

// ─────────────────────────────────────────────────────────────
// НАЗЕМНЫЕ ВОЙСКА (классика RTS в духе Generals)
// ─────────────────────────────────────────────────────────────

export const GROUND_BUILDINGS = {
  hq: {
    id: 'hq', name: 'Штаб', cls: 'structure', hp: 4500, armor: 0.35,
    cost: 0, build: 0, size: 12, vision: 60, produces: ['worker'],
    desc: 'Сердце плацдарма. Строит сборщиков и принимает снабжение. ' +
          'Потеряешь штаб — отстроиться будет нечем.',
  },
  barracks: {
    id: 'barracks', name: 'Казарма', cls: 'structure', hp: 1600, armor: 0.2,
    cost: 400, build: 8, size: 9, vision: 40, produces: ['rifle', 'rocket'],
    desc: 'Пехота: стрелки и ракетчики.',
  },
  factory: {
    id: 'factory', name: 'Завод', cls: 'structure', hp: 2200, armor: 0.28,
    cost: 700, build: 12, size: 11, vision: 40, produces: ['tank', 'aa', 'arty'],
    desc: 'Тяжёлая техника: танки, ЗСУ, артиллерия.',
  },
  airfield: {
    id: 'airfield', name: 'Аэродром', cls: 'structure', hp: 1800, armor: 0.22,
    cost: 900, build: 14, size: 14, vision: 55, produces: ['jet'],
    desc: 'Штурмовики. После захода самолёт обязан вернуться на полосу ' +
          'за боезапасом — как в старых RTS.',
  },
  turret: {
    id: 'turret', name: 'Турель', cls: 'structure', hp: 1300, armor: 0.35,
    cost: 350, build: 6, size: 6, vision: 55,
    weapon: { type: 'cannon', dmg: 120, cd: 2.2, range: 90 },
    desc: 'Автоматическая пушка. По воздуху не стреляет.',
  },
  sam: {
    id: 'sam', name: 'Зенитка', cls: 'structure', hp: 1000, armor: 0.3,
    cost: 400, build: 6, size: 6, vision: 75,
    weapon: { type: 'aa', dmg: 95, cd: 1.1, range: 110, air: true },
    desc: 'Ракетная батарея ПВО. Только по воздуху.',
  },
};

function groundUnits(faction) {
  const trd = faction === 'troyden', rez = faction === 'reez', plk = faction === 'plektor';
  // Та же доктрина, что и в космосе: Тройден дорог и крепок,
  // Плэктор дёшев и многочислен, Рииз невидим и зубаст, но хрупок.
  const hpMod    = trd ? 1.25 : plk ? 0.70 : 0.85;
  const armorMod = trd ? 1.25 : plk ? 0.75 : 0.50;
  const dmgMod   = trd ? 1.10 : plk ? 0.80 : 1.30;
  const costMod  = trd ? 1.35 : plk ? 0.50 : 0.95;
  const buildMod = trd ? 1.30 : plk ? 0.50 : 1.0;
  const H = h => Math.round(h * hpMod);
  const A = a => Math.min(0.6, +(a * armorMod).toFixed(3));
  const C = c => Math.round(c * costMod / 5) * 5;
  const B = b => +(b * buildMod).toFixed(1);
  const W = w => w && { ...w, dmg: Math.round(w.dmg * dmgMod) };

  const nm = {
    rifle:  trd ? 'Стрелковое отделение' : rez ? 'Диверсанты' : 'Ополченцы',
    rocket: trd ? 'Расчёт ПТУР' : rez ? 'Ракетчики-призраки' : 'Гранатомётчики',
    tank:   trd ? 'ОБТ «Паладин»' : rez ? 'Танк «Морок»' : 'Багги «Гвоздь»',
    arty:   trd ? 'САУ «Клинок»' : rez ? 'САУ «Затмение»' : 'Миномёт на грузовике',
    jet:    trd ? 'Штурмовик «Ястреб»' : rez ? 'Штурмовик «Саван»' : 'Ударный дрон',
  };

  const mk = (o) => ({ ...o, hp: H(o.hp), armor: A(o.armor), cost: C(o.cost),
                       build: B(o.build), weapon: W(o.weapon), stealth: rez });

  return {
    worker: mk({
      id: 'worker', name: 'Сборщик', cls: 'vehicle', from: 'hq',
      hp: 260, armor: 0.1, speed: 13, cost: 180, build: 5,
      cargo: 90, vision: 35, weapon: null,
      desc: 'Возит снабжение с полей на штаб. Безоружен. Без сборщиков ' +
            'быстро кончатся деньги.',
    }),
    rifle: mk({
      id: 'rifle', name: nm.rifle, cls: 'infantry', from: 'barracks',
      hp: 170, armor: 0.05, speed: 8.5, cost: 120, build: 4,
      vision: 45, weapon: { type: 'rifle', dmg: 22, cd: 0.75, range: 34 },
      desc: 'Дёшево и сердито. Косит чужую пехоту, по технике почти бесполезна.',
    }),
    rocket: mk({
      id: 'rocket', name: nm.rocket, cls: 'infantry', from: 'barracks',
      hp: 150, armor: 0.05, speed: 7.5, cost: 200, build: 5,
      vision: 50, weapon: { type: 'at', dmg: 90, cd: 2.4, range: 48, air: true },
      desc: 'Вскрывает танки и достаёт самолёты. Против пехоты — плохо.',
    }),
    tank: mk({
      id: 'tank', name: nm.tank, cls: 'vehicle', from: 'factory',
      hp: 950, armor: 0.3, speed: plk ? 15 : 11.5, cost: 600, build: 8,
      vision: 50, weapon: { type: 'cannon', dmg: 130, cd: 2.1, range: 55 },
      desc: 'Основа наземной армии. Давит пехоту, ломает здания, ' +
            'боится ракетчиков и артиллерии.',
    }),
    aa: mk({
      id: 'aa', name: 'ЗСУ', cls: 'vehicle', from: 'factory',
      hp: 520, armor: 0.2, speed: 13, cost: 420, build: 6,
      vision: 70, weapon: { type: 'aa', dmg: 80, cd: 0.85, range: 95, air: true },
      desc: 'Зенитная самоходка. Ставь под колонну, иначе штурмовики ' +
            'выбьют технику за один заход.',
    }),
    arty: mk({
      id: 'arty', name: nm.arty, cls: 'vehicle', from: 'factory',
      hp: 420, armor: 0.12, speed: 7, cost: 760, build: 11,
      vision: 40, weapon: {
        type: 'arty', dmg: 200, cd: 6, range: 175, minRange: 45,
        splash: 14, arc: true, salvo: plk ? 2 : 1,
      },
      desc: 'Достаёт дальше любой турели, но слепая: без разведки бьёт ' +
            'в пустоту. Вблизи беззащитна, по воздуху не стреляет.',
    }),
    jet: mk({
      id: 'jet', name: nm.jet, cls: 'air', from: 'airfield',
      hp: 420, armor: 0.15, speed: 46, cost: 800, build: 10,
      vision: 80, air: true, ammo: trd ? 5 : 4, rearm: trd ? 6 : 9,
      weapon: { type: 'bomb', dmg: 240, cd: 0.9, range: 42, splash: 9 },
      desc: 'Заходит на цель, вываливает боезапас и возвращается на аэродром ' +
            'перезаряжаться. Пока летит домой — беззащитен.',
    }),
  };
}

export const GROUND_UNITS = {};
for (const f of FACTION_IDS) GROUND_UNITS[f] = groundUnits(f);

export function unitDef(faction, id) {
  return GROUND_UNITS[faction][id];
}

// ─────────────────────────────────────────────────────────────
// СИСТЕМА КАПЕЛЛА
// Узлы карты — планеты, станции и пояса. Связи — маршруты.
// Клото, Лахесис и Атропос — три мойры, как и положено родным мирам.
// ─────────────────────────────────────────────────────────────

export const GALAXY_MAP = {
  systems: [
    { id: 'prometheus', name: 'Прометей',     pos: [-4, 6, -70],  income: 240, slots: 5, biome: 'ice',    start: 'troyden', station: true },
    { id: 'klotho',     name: 'Клото',        pos: [30, -4, -46], income: 280, slots: 5, biome: 'green',  homeOf: 'troyden' },
    { id: 'lachesis',   name: 'Лахесис',      pos: [-42, 10, -44],income: 180, slots: 4, biome: 'rock' },
    { id: 'atropos',    name: 'Атропос',      pos: [2, 14, -24],  income: 160, slots: 3, biome: 'ice' },
    { id: 'vespa',      name: 'Рудники Веспы',pos: [-58, -6, -6], income: 210, slots: 4, biome: 'rock' },
    { id: 'erebus',     name: 'Эреб',         pos: [-16, -12, 2], income: 150, slots: 3, biome: 'desert' },
    { id: 'gate',       name: 'Гиперворота',  pos: [18, 4, 2],    income: 320, slots: 5, biome: 'city' },
    { id: 'xanthia',    name: 'Ксантия',      pos: [54, 10, -4],  income: 170, slots: 3, biome: 'green' },
    { id: 'phlegethon', name: 'Флегетон',     pos: [-46, 8, 30],  income: 175, slots: 4, biome: 'desert' },
    { id: 'styx',       name: 'Стикс',        pos: [-6, -8, 34],  income: 155, slots: 3, biome: 'ice' },
    { id: 'tartarus',   name: 'Тартар',       pos: [48, -10, 38], income: 290, slots: 5, biome: 'city',   start: 'reez' },
    { id: 'wolfdelta',  name: 'Дельта Волка', pos: [14, 16, 52],  income: 145, slots: 3, biome: 'rock' },
    { id: 'morbelt',    name: 'Пояс Мора',    pos: [-60, -14, 58],income: 250, slots: 4, biome: 'rock',   start: 'plektor' },
    { id: 'ferrum',     name: 'Феррум',       pos: [-28, 12, 66], income: 190, slots: 3, biome: 'desert' },
  ],
  links: [
    ['prometheus', 'lachesis'], ['prometheus', 'klotho'], ['prometheus', 'atropos'],
    ['lachesis', 'vespa'], ['lachesis', 'atropos'],
    ['klotho', 'xanthia'], ['klotho', 'atropos'],
    ['atropos', 'gate'],
    ['vespa', 'erebus'], ['vespa', 'phlegethon'],
    ['erebus', 'gate'], ['erebus', 'styx'],
    ['gate', 'xanthia'], ['gate', 'styx'], ['gate', 'wolfdelta'],
    ['xanthia', 'tartarus'],
    ['phlegethon', 'ferrum'], ['phlegethon', 'styx'],
    ['styx', 'wolfdelta'], ['styx', 'morbelt'],
    ['tartarus', 'wolfdelta'], ['tartarus', 'morbelt'],
    ['morbelt', 'ferrum'],
    ['ferrum', 'wolfdelta'],
  ],
};

export const PLANET_BUILDINGS = {
  mine:     { id: 'mine',     name: 'Рудник',              cost: 400,  desc: '+120 кредитов за ход' },
  shipyard: { id: 'shipyard', name: 'Верфь',               cost: 800,  desc: 'Позволяет строить корабли' },
  garrison: { id: 'garrison', name: 'Гарнизон',            cost: 600,  desc: 'Позволяет набирать полки' },
  station:  { id: 'station',  name: 'Орбитальная станция', cost: 1400, desc: 'Крепость в бою на орбите' },
};

export const REGIMENT_COST = 350;

export const BIOME_COLORS = {
  city:   { ground: 0x4a4640, accent: 0x746a5e, rock: 0x5a534b, sky: 0x2a2a33 },
  green:  { ground: 0x46603a, accent: 0x6d8450, rock: 0x6a5c48, sky: 0x2c3428 },
  rock:   { ground: 0x554a42, accent: 0x7a6a58, rock: 0x8a7a66, sky: 0x33291f },
  ice:    { ground: 0x5c6a72, accent: 0xa8bcc8, rock: 0x5a626a, sky: 0x27333a },
  desert: { ground: 0x7a6a4a, accent: 0xa89068, rock: 0x8a6f4a, sky: 0x3a3020 },
};

// Короткая справка нейроинтерфейса — показывается на экране обучения
export const NEURO_BRIEF = [
  {
    title: 'Инерция',
    text: 'Корабль летит по вектору, а не «куда смотрит». Отдав приказ ' +
          'на движение, ты задаёшь тягу, а не скорость: линкор будет ' +
          'разгоняться полминуты и столько же тормозить. Разворот корпуса ' +
          'от вектора не зависит — можно скользить боком, держа противника ' +
          'в прицеле.',
  },
  {
    title: 'Главный калибр',
    text: 'Тяжёлый лазер бьёт раз в 9–17 секунд и сносит цель почти ' +
          'целиком. Перед выстрелом видна накачка — это единственное ' +
          'предупреждение. По истребителям главный калибр не наводится ' +
          'вообще: башня физически не успевает за ними.',
  },
  {
    title: 'ПВО',
    text: 'Зенитки работают сами, без приказа, и только по мелочи: ' +
          'авиация, торпеды, ракеты. Корабль без прикрытия эскорта ' +
          'разбирается звеном бомбардировщиков за минуту.',
  },
  {
    title: 'Гиперпространство',
    text: 'Любой корабль может уйти в гипер: даёшь приказ, он копит ' +
          'переход от пяти до четырнадцати секунд и всё это время ' +
          'беззащитен. Ушедший корабль сохраняется для кампании. ' +
          'Линкор с повреждениями больше 80% прыгает сам, не спрашивая. ' +
          'А вот уход носителя означает проигранный бой: без него флот ' +
          'остаётся без авиации. Из гипера можно и вызвать подкрепление — ' +
          'резерв придёт примерно через полминуты.',
  },
  {
    title: 'Радиоэлектронная борьба',
    text: 'Корабль РЭБ разворачивает купол помех радиусом около четырёхсот ' +
          'единиц. Внутри купола чужой главный калибр не может взять цель ' +
          'дальше ста семидесяти, ракеты и торпеды теряют наведение и ' +
          'летят прямо, ПВО бьёт вполсилы, а маскировку никто не ' +
          'вскрывает. Тот же корабль переключается в защитный режим — ' +
          'тогда купол снимает чужие помехи со своих. Два РЭБ друг ' +
          'против друга — это дуэль: кто первым переключится.',
  },
  {
    title: 'Скрытность Рииза',
    text: 'Вся техника клана Рииз невидима, пока не откроет огонь. ' +
          'После выстрела корабль видно пять секунд, потом он снова ' +
          'растворяется. Вскрыть маскировку заранее можно только ' +
          'подойдя вплотную — дальше всех видят корветы и ЗСУ.',
  },
  {
    title: 'Авиакрыло',
    text: 'Перехватчик режет чужую авиацию и сбивает торпеды. Истребитель ' +
          'по всему средне. Бомбардировщик топит крупные корабли и не ' +
          'может ответить истребителю ничем. Авианосец своего оружия ' +
          'почти не имеет.',
  },
];
