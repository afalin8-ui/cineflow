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
// ─────────────────────────────────────────────────────────────

const TROYDEN = {
  id: 'troyden',
  name: 'Клан Тройден',
  short: 'Тройден',
  tag: 'ТРД',
  color: 0x5ac8e0,
  colorCss: '#5ac8e0',
  style: 'sleek',
  motto: 'Нас мало. Значит, каждый должен стоить десятерых',
  desc: 'Самый малочисленный из двадцати семи кланов Капеллы и признанный ' +
        'лидер в высоких технологиях — за что соседи его и не любят. ' +
        'Изгнан с родной планеты Клото, флот уходит с боями. Техника ' +
        'дорогая и штучная, но нейроинтерфейс, наведение и авиакрылья ' +
        'лучше, чем у кого бы то ни было.',
  perks: [
    'Авиакрылья живучее и точнее на четверть',
    'ПВО кораблей бьёт дальше и больнее',
    'Штурмовики перезаряжаются быстрее',
  ],
  weakness: 'Всё дорого, кораблей мало — потери восполнять нечем',
};

const DEVIAN = {
  id: 'devian',
  name: 'Клан Девиан',
  short: 'Девиан',
  tag: 'ДВН',
  color: 0xe0603f,
  colorCss: '#e0603f',
  style: 'heavy',
  motto: 'Масса решает',
  desc: 'Военная машина внутренних миров, зачинщик изгнания. Толстая ' +
        'броня и главный калибр, от которого крейсер разваливается с ' +
        'одного попадания. На земле — тяжёлые танки и артиллерия ' +
        'залпового огня. Инерцию своих туш девианцы считают достоинством.',
  perks: [
    'Броня кораблей и техники выше на 15%',
    'Главный калибр бьёт сильнее и дальше',
    'Артиллерия стреляет залпом из трёх снарядов',
  ],
  weakness: 'Слабое ПВО и посредственная авиация — рой бомберов их смерть',
};

const PLEKTOR = {
  id: 'plektor',
  name: 'Клан Плэктор',
  short: 'Плэктор',
  tag: 'ПЛК',
  color: 0xe0b34e,
  colorCss: '#e0b34e',
  style: 'scrap',
  motto: 'Числом, а не числами',
  desc: 'Торговый клан, наполовину сросшийся с пиратами пояса. Корабли ' +
        'собраны из чего попало, зато их много, ангары набиты под завязку, ' +
        'а ракетные пакеты вешают куда придётся. Воюет не качеством, ' +
        'а тем, что не жалко.',
  perks: [
    'Всё стоит на четверть дешевле',
    'Авианосцы несут на одно звено больше',
    'Пехота и лёгкая техника строятся вдвое быстрее',
  ],
  weakness: 'Тонкая броня: под главным калибром тают на глазах',
};

export const FACTIONS = { troyden: TROYDEN, devian: DEVIAN, plektor: PLEKTOR };
export const FACTION_IDS = ['troyden', 'devian', 'plektor'];

// ─────────────────────────────────────────────────────────────
// КОСМИЧЕСКИЕ КОРАБЛИ
//
// Полёт ньютоновский, как в Homeplanet: у корабля есть вектор
// скорости, двигатель даёт ускорение, а не «скорость». Поэтому:
//   thrust   — ускорение маршевого двигателя (ед/с²)
//   maxSpeed — предел, который держит система стабилизации
//   turn     — скорость разворота корпуса (рад/с), не зависит от вектора
// Корабль может лететь боком, продолжая держать противника в прицеле —
// это и есть фирменное ощущение Homeplanet.
// ─────────────────────────────────────────────────────────────

const SQUAD_SIZE = 5;

export const STRIKE_ROLES = {
  interceptor: { label: 'Перехватчик', short: 'ПХВ', hint: 'Бьёт вражескую авиацию и сбивает торпеды' },
  fighter:     { label: 'Истребитель', short: 'ИСТ', hint: 'Универсал: по всему средне' },
  bomber:      { label: 'Бомбардировщик', short: 'БМБ', hint: 'Торпеды по крупным кораблям, в бою беспомощен' },
};

function strikeCraft(faction) {
  const trd = faction === 'troyden', plk = faction === 'plektor', dvn = faction === 'devian';
  const tough = trd ? 1.25 : dvn ? 0.9 : 0.85;
  const acc = trd ? 1.2 : dvn ? 0.85 : 1.0;
  return {
    interceptor: {
      id: 'interceptor', role: 'interceptor',
      name: trd ? '«Скальпель»' : dvn ? 'Тип-4 «Оса»' : '«Штырь»',
      cls: 'strike', hp: Math.round(70 * tough), armor: 0,
      maxSpeed: 155, thrust: 105, turn: 2.7,
      weapon: 'gunInt', dmg: 14 * acc, cd: 0.5, range: 60,
    },
    fighter: {
      id: 'fighter', role: 'fighter',
      name: trd ? '«Рекс»' : dvn ? 'Тип-7 «Клык»' : '«Латаный»',
      cls: 'strike', hp: Math.round(95 * tough), armor: 0.05,
      maxSpeed: 128, thrust: 82, turn: 2.1,
      weapon: 'gunFig', dmg: 17 * acc, cd: 0.62, range: 66,
    },
    bomber: {
      id: 'bomber', role: 'bomber',
      name: trd ? '«Молот»' : dvn ? 'Тип-11 «Ковш»' : '«Тачка»',
      cls: 'strike', hp: Math.round(150 * tough), armor: 0.1,
      maxSpeed: 84, thrust: 44, turn: 1.15,
      weapon: 'torp', dmg: 140 * (dvn ? 1.15 : 1), cd: 6.5, range: 95, torpedo: true,
    },
  };
}

function shipsFor(faction) {
  const dvn = faction === 'devian', plk = faction === 'plektor', trd = faction === 'troyden';
  const armorMod = dvn ? 1.15 : plk ? 0.82 : 1.0;
  const pdRange = trd ? 1.3 : dvn ? 0.8 : 1.0;
  const pdDmg = trd ? 1.25 : dvn ? 0.75 : 1.0;
  const costMod = plk ? 0.75 : trd ? 1.1 : 1.0;
  const A = a => Math.min(0.6, +(a * armorMod).toFixed(3));
  const C = c => Math.round(c * costMod / 10) * 10;

  const list = [];

  // ── ЭСКОРТ: дешёвый, вертлявый, весь в зенитках
  list.push({
    id: 'escort', cls: 'escort', tier: 1,
    name: trd ? 'Фрегат «Клинок»' : dvn ? 'Заслон «Гранит»' : 'Рейдер «Оса»',
    role: 'Эскорт · зонт ПВО',
    hp: 900 + (dvn ? 300 : plk ? -250 : 0), armor: A(0.15),
    maxSpeed: plk ? 42 : 34, thrust: plk ? 15 : 11, turn: 0.55, radius: 6, cost: C(320),
    guns: [{ type: 'light', dmg: 62, cd: 2.6, range: 260 }],
    pd: { count: 3, dmg: 16 * pdDmg, cd: 0.28, range: 120 * pdRange },
    hangar: null,
    desc: 'Быстрый, дешёвый, живёт недолго. Главное — его зенитки: ' +
          'без эскорта авиация противника разберёт линкор на болты.',
  });

  // ── КРЕЙСЕР: рабочая лошадь линии
  list.push({
    id: 'cruiser', cls: 'capital', tier: 2,
    name: trd ? 'Крейсер «Вектор»' : dvn ? 'Крейсер «Молот»' : 'Ракетоносец «Скорпион»',
    role: plk ? 'Ракетный залп' : 'Линейный крейсер',
    hp: 2400 + (dvn ? 600 : plk ? -500 : 0), armor: A(0.28),
    maxSpeed: 22, thrust: 4.2, turn: 0.3, radius: 12, cost: C(900),
    guns: plk
      ? [{ type: 'missile', dmg: 260, cd: 5.5, range: 700, salvo: 3, spread: 0.05 }]
      : [{ type: 'heavy', dmg: 420 * (dvn ? 1.2 : 1), cd: 9, range: dvn ? 820 : 760, charge: 1.2 }],
    pd: { count: 3, dmg: 14 * pdDmg, cd: 0.32, range: 110 * pdRange },
    hangar: null,
    desc: plk
      ? 'Пускает пачку ракет: суммарно меньше главного калибра, зато чаще ' +
        'и по площади. Ракеты медленные — чужое ПВО их сбивает.'
      : 'Один тяжёлый лазер. Стреляет редко — раз в девять секунд, — ' +
        'зато каждый выстрел выжигает эскорт целиком.',
  });

  // ── АВИАНОСЕЦ: почти без оружия, всё решает ангар
  const bays = plk ? 4 : trd ? 3 : 2;
  list.push({
    id: 'carrier', cls: 'carrier', tier: 2,
    name: trd ? 'Авианосец «Атриум»' : dvn ? 'Носитель «Улей»' : 'Плавучий док «Караван»',
    role: 'Авианосец · ' + bays + (bays === 4 ? ' звена' : bays === 3 ? ' звена' : ' звена'),
    hp: 3000 + (dvn ? 500 : plk ? -400 : 0), armor: A(0.22),
    maxSpeed: 18, thrust: 3.0, turn: 0.24, radius: 15, cost: C(1100),
    guns: [],
    pd: { count: 4, dmg: 15 * pdDmg, cd: 0.3, range: 130 * pdRange },
    hangar: bays,
    desc: 'Своего оружия нет — только ПВО. Вся сила в ангаре: ' +
          'перехватчики, истребители и бомбардировщики. Без прикрытия ' +
          'авианосец беззащитен, беречь как зеницу ока.',
  });

  // ── ЛИНКОР: главный калибр
  list.push({
    id: 'capital', cls: 'capital', tier: 3,
    name: trd ? 'Линкор «Меридиан»' : dvn ? 'Дредноут «Гора»' : 'Линкор «Ржавый Король»',
    role: 'Главный калибр',
    hp: dvn ? 7000 : plk ? 3800 : 5200, armor: A(dvn ? 0.42 : 0.36),
    maxSpeed: dvn ? 13 : 16, thrust: dvn ? 1.9 : 2.6, turn: 0.17, radius: 22,
    cost: C(dvn ? 2600 : 2200),
    guns: dvn
      ? [{ type: 'heavy', dmg: 1500, cd: 17, range: 950, charge: 2.2 }]
      : trd
        ? [{ type: 'heavy', dmg: 780, cd: 11, range: 880, charge: 1.6 },
           { type: 'heavy', dmg: 780, cd: 11, range: 880, charge: 1.6 }]
        : [{ type: 'missile', dmg: 300, cd: 6, range: 780, salvo: 4, spread: 0.06 },
           { type: 'heavy', dmg: 520, cd: 12, range: 800, charge: 1.4 }],
    pd: { count: 6, dmg: 18 * pdDmg, cd: 0.26, range: 140 * pdRange },
    hangar: null,
    desc: dvn
      ? 'Копит энергию две секунды и бьёт так, что крейсер исчезает. ' +
        'Разворачивается вечность, тормозит ещё дольше. ПВО слабое — ' +
        'рой бомбардировщиков для него смертелен.'
      : trd
        ? 'Две спаренные лазерные башни и лучшее в системе ПВО. ' +
          'Держит строй и не отпускает цель.'
        : 'Сборная солянка: ракетные пакеты и один трофейный лазер. ' +
          'Броня тонкая, зато цена смешная.',
  });

  return list;
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
  hp: 6000, armor: 0.4, maxSpeed: 0, thrust: 0, turn: 0.12, radius: 26, cost: 1400,
  guns: [{ type: 'heavy', dmg: 620, cd: 10, range: 900, charge: 1.5 }],
  pd: { count: 8, dmg: 18, cd: 0.24, range: 150 },
  hangar: 1, station: true,
  desc: 'Неподвижная крепость на орбите. Главный калибр, восемь батарей ПВО ' +
        'и одно звено перехватчиков. С места не сдвинется — но и не отступит.',
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
  const trd = faction === 'troyden', dvn = faction === 'devian', plk = faction === 'plektor';
  const armorMod = dvn ? 1.15 : plk ? 0.85 : 1;
  const costMod = plk ? 0.72 : trd ? 1.12 : 1;
  const buildMod = plk ? 0.6 : trd ? 1.1 : 1;
  const A = a => Math.min(0.6, +(a * armorMod).toFixed(3));
  const C = c => Math.round(c * costMod / 5) * 5;
  const B = b => +(b * buildMod).toFixed(1);

  return {
    worker: {
      id: 'worker', name: 'Сборщик', cls: 'vehicle', from: 'hq',
      hp: 260, armor: A(0.1), speed: 13, cost: C(180), build: B(5),
      cargo: 90, vision: 35, weapon: null,
      desc: 'Возит снабжение с полей на штаб. Безоружен. Без сборщиков ' +
            'быстро кончатся деньги.',
    },
    rifle: {
      id: 'rifle', cls: 'infantry', from: 'barracks',
      name: trd ? 'Стрелковое отделение' : dvn ? 'Штурмовая пехота' : 'Ополченцы',
      hp: dvn ? 190 : 160, armor: A(0.05), speed: 8.5, cost: C(120), build: B(4),
      vision: 45, weapon: { type: 'rifle', dmg: 22, cd: 0.75, range: 34 },
      desc: 'Дёшево и сердито. Косит чужую пехоту, по технике почти бесполезна.',
    },
    rocket: {
      id: 'rocket', cls: 'infantry', from: 'barracks',
      name: trd ? 'Расчёт ПТУР' : dvn ? 'Гранатомётчики' : 'Ракетчики',
      hp: 150, armor: A(0.05), speed: 7.5, cost: C(200), build: B(5),
      vision: 50, weapon: { type: 'at', dmg: 90, cd: 2.4, range: 48, air: true },
      desc: 'Вскрывает танки и достаёт самолёты. Против пехоты — плохо.',
    },
    tank: {
      id: 'tank', cls: 'vehicle', from: 'factory',
      name: trd ? 'ОБТ «Паладин»' : dvn ? 'Танк «Тайфун»' : 'Багги «Гвоздь»',
      hp: dvn ? 1250 : plk ? 620 : 950, armor: A(dvn ? 0.35 : plk ? 0.18 : 0.3),
      speed: plk ? 17 : dvn ? 9.5 : 11.5, cost: C(dvn ? 640 : plk ? 380 : 600), build: B(dvn ? 9 : 8),
      vision: 50, weapon: { type: 'cannon', dmg: dvn ? 165 : 130, cd: dvn ? 2.6 : 2.1, range: 55 },
      desc: 'Основа наземной армии. Давит пехоту, ломает здания, ' +
            'боится ракетчиков и артиллерии.',
    },
    aa: {
      id: 'aa', name: 'ЗСУ', cls: 'vehicle', from: 'factory',
      hp: 520, armor: A(0.2), speed: 13, cost: C(420), build: B(6),
      vision: 70, weapon: { type: 'aa', dmg: 80, cd: 0.85, range: 95, air: true },
      desc: 'Зенитная самоходка. Ставь под колонну, иначе штурмовики ' +
            'выбьют технику за один заход.',
    },
    arty: {
      id: 'arty', cls: 'vehicle', from: 'factory',
      name: dvn ? 'РСЗО «Ураган»' : trd ? 'САУ «Клинок»' : 'Миномёт на грузовике',
      hp: 420, armor: A(0.12), speed: 7, cost: C(760), build: B(11),
      vision: 40, weapon: {
        type: 'arty', dmg: dvn ? 100 : 200, cd: dvn ? 7 : 6, range: 175, minRange: 45,
        splash: 14, arc: true, salvo: dvn ? 3 : 1,
      },
      desc: 'Достаёт дальше любой турели, но слепая: без разведки бьёт ' +
            'в пустоту. Вблизи беззащитна, по воздуху не стреляет.',
    },
    jet: {
      id: 'jet', cls: 'air', from: 'airfield',
      name: trd ? 'Штурмовик «Ястреб»' : dvn ? 'Штурмовик «Серп»' : 'Ударный дрон',
      hp: trd ? 460 : 380, armor: A(0.15), speed: 46, cost: C(trd ? 900 : 700), build: B(10),
      vision: 80, air: true, ammo: trd ? 5 : 4, rearm: trd ? 6 : 9,
      weapon: { type: 'bomb', dmg: trd ? 260 : 230, cd: 0.9, range: 42, splash: 9 },
      desc: 'Заходит на цель, вываливает боезапас и возвращается на аэродром ' +
            'перезаряжаться. Пока летит домой — беззащитен.',
    },
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
    { id: 'tartarus',   name: 'Тартар',       pos: [48, -10, 38], income: 290, slots: 5, biome: 'city',   start: 'devian' },
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
  city:   { ground: 0x4a4640, accent: 0x6b6055, sky: 0x2a2a33 },
  green:  { ground: 0x4a5a3a, accent: 0x5f7048, sky: 0x2c3428 },
  rock:   { ground: 0x554a42, accent: 0x6b5c50, sky: 0x33291f },
  ice:    { ground: 0x5c6a72, accent: 0x7d8b93, sky: 0x27333a },
  desert: { ground: 0x7a6a4a, accent: 0x94805c, sky: 0x3a3020 },
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
    title: 'Авиакрыло',
    text: 'Перехватчик режет чужую авиацию и сбивает торпеды. Истребитель ' +
          'по всему средне. Бомбардировщик топит крупные корабли и не ' +
          'может ответить истребителю ничем. Авианосец своего оружия ' +
          'почти не имеет.',
  },
];
