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
  // Автопушка БМП: косит пехоту, дырявит лёгкую технику, слегка достаёт
  // низколетящие вертолёты. Против брони и стен — почти бесполезна.
  auto:    { infantry: 0.95, vehicle: 0.45, structure: 0.30, air: 0.35 },
  // Снайпер: строго по живой силе, зато с огромной дистанции
  sniper:  { infantry: 1.80, vehicle: 0.00, structure: 0.00, air: 0.00 },
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
//            чужого. Ближе всего к США из Generals. Базу не строит —
//            сбрасывает готовые модули с орбиты.
// Плэктор  — тяжёлая индустрия и рой: дёшево, быстро, много. Разворачивает
//            левиафан-MCV, застраивается бульдозерами, копит бетон.
// Рииз     — скрытность и авиация: вся техника невидима, пока не выстрелит,
//            орудия сильные, броня бумажная. Носители просторнее чужих.
// Девиан   — помехи и крепости: сам бьёт средне, зато чужой залп не
//            наводится. Строит модули вплотную к центральному узлу.
// ─────────────────────────────────────────────────────────────

const TROYDEN = {
  id: 'troyden', name: 'Клан Тройден', short: 'Тройден', tag: 'ТРД',
  color: 0x5ac8e0, colorCss: '#5ac8e0', style: 'sleek', doctrine: 'tech',
  motto: 'Нас мало. Значит, каждый должен стоить десятерых',
  desc: 'Самый малочисленный из двадцати семи кланов Капеллы и признанный ' +
        'лидер в высоких технологиях. Корабли строит подземный комплекс ' +
        'LT-Farm, основанный Лансом Тройденом. Техника дороже чужой вдвое ' +
        'и стоит этих денег: броня, наведение и ПВО лучшие в системе. ' +
        'Но потери восполнять нечем.',
  perks: [
    'Каждый корабль крепче и точнее чужого того же класса',
    'Лучшее в системе ПВО',
    'Главный калибр стреляет чаще: лучше охлаждение',
  ],
  weakness: 'Всё дороже на треть и строится дольше',
};

const PLEKTOR = {
  id: 'plektor', name: 'Клан Плэктор', short: 'Плэктор', tag: 'ПЛК',
  color: 0xe0b34e, colorCss: '#e0b34e', style: 'scrap', doctrine: 'swarm',
  motto: 'Числом, а не числами',
  desc: 'Тот самый клан, что сжёг LT-Farm и вместе с Риизом выдавил ' +
        'Тройден с Клото. Истребитель «Бронко» летает отвратительно, ' +
        'зато хорошо защищён, а бомбардировщики «Шерман» возят мало ' +
        'ракет — поэтому летают звеньями вдвое больше обычных. ' +
        'Плэктор воюет не качеством, а количеством.',
  perks: [
    'Всё вдвое дешевле и строится вдвое быстрее',
    'Кораблей за те же деньги выходит втрое больше',
    'Звенья бомбардировщиков крупнее',
  ],
  weakness: 'Поодиночке беспомощны: тонкая броня, слабые орудия',
};

const REEZ = {
  id: 'reez', name: 'Клан Рииз', short: 'Рииз', tag: 'РИЗ',
  color: 0x6ee0b0, colorCss: '#6ee0b0', style: 'wedge', doctrine: 'stealth',
  motto: 'Верфей нет — есть ангары и тени',
  desc: 'У клана нет производственных мощностей для больших кораблей: ' +
        '«Касатка» построена на заказ и осталась единственным линейным ' +
        'кораблём, причём она же служит носителем. Воевать приходится ' +
        'авиацией и внезапностью: вся техника Рииза несёт маскировочное ' +
        'поле и не видна, пока не откроет огонь. Экономия веса ушла из ' +
        'брони в орудия — бьют они больнее всех, но раскрытый риизец ' +
        'живёт недолго.',
  perks: [
    'Скрытность у всех юнитов: невидимы, пока не выстрелят',
    'Орудия бьют на пятую часть сильнее',
    'Носители несут на два звена больше, звено — семь машин',
  ],
  weakness: 'Броня вдвое тоньше. Под главным калибром рассыпаются',
};

const DEVIAN = {
  id: 'devian', name: 'Клан Девиан', short: 'Девиан', tag: 'ДВН',
  color: 0xb07ae0, colorCss: '#b07ae0', style: 'fortress', doctrine: 'ecm',
  motto: 'Пусть стреляют. Попасть — не дадим',
  desc: 'Клан радиоэлектронной борьбы и крепостей. Девиан не выигрывает ' +
        'перестрелку — он делает её невозможной: поля помех глушат чужое ' +
        'наведение, ракеты теряют цель, ПВО бьёт вполсилы. Корабли крепкие ' +
        'и терпеливые, орудия средние. На земле Девиан не расползается по ' +
        'карте, а наращивает модули вплотную к центральному узлу.',
  perks: [
    'Поле помех шире и держится дольше чужого',
    'Корпуса крепче и лучше бронированы',
    'Хакеры вместо сборщиков: доход взламывают, а не возят',
  ],
  weakness: 'Орудия слабее чужих: в лоб Девиан перестрелку не выигрывает',
};

export const FACTIONS = { troyden: TROYDEN, reez: REEZ, plektor: PLEKTOR, devian: DEVIAN };
export const FACTION_IDS = ['troyden', 'reez', 'plektor', 'devian'];

export const STEALTH = { revealFor: 5.0, detectRange: 130, groundDetect: 55 };

// Радиоэлектронная борьба. «Сайленсер» — канонический корабль РЭБ
// клана Тройден. Поле помех — плоский блин в плоскости боя,
// а не шар: так видно, кто под ним, а кто уже вышел.
export const ECM = {
  radius: 420,          // радиус блина
  height: 90,           // его толщина по вертикали
  lockRange: 170,       // ближе этого наведение всё же работает
  missileBlind: true,
  pdPenalty: 0.55,
  spinUp: 2.5,
};

/* У Девиана помехи — не приложение к флоту, а сам флот. Его блин
   заметно шире чужого, разворачивается быстрее и глушит наведение
   даже вблизи. Это то, чем клан заменяет недостающую огневую мощь. */
export const ECM_OF = faction => (faction === 'devian'
  ? { ...ECM, radius: ECM.radius * 1.45, lockRange: ECM.lockRange * 0.6,
      pdPenalty: 0.40, spinUp: ECM.spinUp * 0.6 }
  : ECM);

// ─────────────────────────────────────────────────────────────
// КОСМИЧЕСКИЕ КОРАБЛИ
// Названия — из канона Homeplanet (elite-games.ru, раздел «Корабли»);
// поле canon помечает, что из игры, а что достроено.
// ─────────────────────────────────────────────────────────────

const SQUAD_SIZE = 5;

export const STRIKE_ROLES = {
  interceptor: { label: 'Перехватчик', short: 'ПХВ', hint: 'Пушки. Бьёт авиацию и сбивает ракеты' },
  fighter:     { label: 'Истребитель', short: 'ИСТ', hint: '8 ракет, промах 25%. Универсал' },
  bomber:      { label: 'Бомбардировщик', short: 'БМБ', hint: '6 тяжёлых ракет, промах 10%. По крупным целям' },
};

const STRIKE_NAMES = {
  troyden: { interceptor: ['«Зонг»', true], fighter: ['«Рекс»', true], bomber: ['«Паларм»', true] },
  reez:    { interceptor: ['«Акула»', true], fighter: ['«Пиранья»', true], bomber: ['«Нарвал»', false] },
  plektor: { interceptor: ['«Драккар»', true], fighter: ['«Бронко»', true], bomber: ['«Шерман»', true] },
  devian:  { interceptor: ['«Игла»', false], fighter: ['«Морок»', false], bomber: ['«Саван»', false] },
};

/* Вооружение авиации.
   Перехватчик — пушки: по ракете не набьёшь скорострельности,
   а его работа — рвать чужие звенья очередями.
   Истребитель и бомбардировщик — ракеты с боезапасом: восемь и шесть.
   Кончились — можно перезарядиться прямо в космосе, но ограниченное
   число раз; дальше только на носитель. Ракеты промахиваются:
   у истребителя каждая четвёртая, у бомбардировщика каждая десятая. */
function strikeCraft(faction) {
  const trd = faction === 'troyden', plk = faction === 'plektor';
  const rez = faction === 'reez', dvn = faction === 'devian';
  const tough = trd ? 1.3 : rez ? 1.25 : dvn ? 0.8 : 1.0;
  const gun = trd ? 1.15 : rez ? 1.2 : dvn ? 1.25 : 0.85;
  const N = STRIKE_NAMES[faction];
  const turnMod = plk ? 0.75 : 1;      // «Драккар» неповоротлив
  const nm = k => ({ name: N[k][0], canon: N[k][1] });

  return {
    interceptor: {
      id: 'interceptor', role: 'interceptor', ...nm('interceptor'), cls: 'strike',
      hp: Math.round(70 * tough), armor: 0,
      maxSpeed: plk ? 175 : 155, thrust: 105, turn: 2.7 * turnMod,
      weaponKind: 'gun', weapon: 'gunInt',
      dmg: 14 * gun, cd: 0.5, range: 60, stealth: rez,
    },
    fighter: {
      id: 'fighter', role: 'fighter', ...nm('fighter'), cls: 'strike',
      hp: Math.round(95 * tough), armor: 0.05,
      maxSpeed: 128, thrust: 82, turn: 2.1 * turnMod,
      weaponKind: 'missile', weapon: 'gunFig',
      dmg: 95 * gun, cd: 1.7, range: 95, stealth: rez,
      ammo: 8, reloads: 4, reloadTime: 7, missChance: 0.25,
      missileSpeed: 150, missileHp: 20,
    },
    bomber: {
      id: 'bomber', role: 'bomber', ...nm('bomber'), cls: 'strike',
      hp: Math.round(160 * tough), armor: 0.1,
      maxSpeed: 72, thrust: 38, turn: 1.05,
      weaponKind: 'missile', weapon: 'torp',
      dmg: 260 * (dvn ? 1.25 : 1), cd: 3.4, range: 120, stealth: rez,
      ammo: 6, reloads: 2, reloadTime: 11, missChance: 0.10,
      missileSpeed: 88, missileHp: 34, torpedo: true,
    },
  };
}

const SHIP_NAMES = {
  troyden: {
    corvette: ['Корвет «Гроссер»', true], frigate: ['Фрегат «Диксон»', true],
    ecm: ['Корабль РЭБ «Сайленсер»', true], cruiser: ['Линейный крейсер «Ховард»', true],
    carrier: ['Носитель «Хантер»', true], capital: ['Флагман «Ланселот»', true],
  },
  reez: {
    corvette: ['Корвет «Барракуда»', false], frigate: ['Фрегат «Мурена»', false],
    ecm: ['Корабль РЭБ «Скат»', false], cruiser: ['Крейсер «Марлин»', false],
    carrier: ['Носитель «Касатка»', true], capital: ['Линкор «Кашалот»', false],
  },
  plektor: {
    sinho: ['Крейсер «Синхо»', true],
    corvette: ['Корвет «Исса»', true], frigate: ['Фрегат «Севен Клоз»', true],
    ecm: ['Корабль РЭБ «Уайт Шарк»', true], cruiser: ['Крейсер «Рэш»', true],
    carrier: ['Носитель «Норман»', true], capital: ['Флагман «Орк»', true],
  },
  devian: {
    corvette: ['Корвет «Тень»', false], frigate: ['Фрегат «Морок»', false],
    ecm: ['Корабль РЭБ «Полог»', false], cruiser: ['Крейсер «Затмение»', false],
    carrier: ['Носитель «Призрак»', false], capital: ['Линкор «Немезида»', false],
  },
};

function shipsFor(faction) {
  const trd = faction === 'troyden', plk = faction === 'plektor';
  const rez = faction === 'reez', dvn = faction === 'devian';
  /* Рииз забрал скрытность, а вместе с ней её цену: броня тоньше всех,
     зато орудия бьют сильнее. Девиан стал кланом помех и крепостей —
     он крепкий и терпеливый, но сам по себе бьёт средне: его сила
     не в залпе, а в том, что чужой залп не наводится. */
  const hpMod    = trd ? 1.30 : plk ? 0.68 : rez ? 0.85 : 1.05;
  const armorMod = trd ? 1.25 : plk ? 0.75 : rez ? 0.55 : 1.10;
  const gunMod   = trd ? 1.10 : plk ? 0.78 : rez ? 1.20 : 0.90;
  const costMod  = trd ? 1.35 : plk ? 0.50 : rez ? 1.00 : 0.95;
  const buildMod = trd ? 1.30 : plk ? 0.50 : 1.0;
  const pdRange  = trd ? 1.35 : dvn ? 0.85 : 1.0;
  const pdDmg    = trd ? 1.30 : dvn ? 0.85 : 0.9;
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
            'именно корветы вскрывают маскировку Девиана.',
    },
    {
      id: 'frigate', cls: 'escort', tier: 1, role: 'Фрегат · зонт ПВО',
      hp: 1000, armor: 0.18, maxSpeed: 34, thrust: 11, turn: 0.55, radius: 6.5,
      cost: 380, build: 1, hyperCharge: 6,
      guns: [{ type: 'light', dmg: 66, cd: 2.6, range: 270 }],
      pd: { count: 4, dmg: 17, cd: 0.26, range: 130 },
      desc: 'Рабочая лошадь охранения. Главное — зенитки: они сбивают ' +
            'ракеты. Без фрегатов звено бомбардировщиков разберёт линкор.',
    },
    {
      id: 'ecm', cls: 'escort', tier: 2, role: 'РЭБ · поле помех',
      hp: 1400, armor: 0.20, maxSpeed: 30, thrust: 9, turn: 0.5, radius: 8,
      cost: 720, build: 2, hyperCharge: 8, ecm: true,
      guns: [],
      pd: { count: 2, dmg: 14, cd: 0.3, range: 120 },
      desc: 'Разворачивает плоское поле помех вокруг себя. Внутри чужой ' +
            'главный калибр не берёт цель на дальней дистанции, ракеты ' +
            'теряют наведение, ПВО бьёт вполсилы, маскировку никто ' +
            'не вскрывает. Переключается в защитный режим — тогда поле ' +
            'наоборот снимает чужие помехи со своих.',
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
      desc: 'Своего оружия нет — только ПВО. Вся сила в ангаре, и он же ' +
            'единственное место, где авиация пополняет ракеты. Уход ' +
            'носителя в гипер означает, что бой проигран.',
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

  // «Синхо» — тот самый большой корабль противника со вступительного
  // ролика. Класса в открытых источниках нет, поэтому пока это
  // тяжёлый крейсер Плэктора: медленный, много брони, залповый огонь.
  if (plk) base.push({
    id: 'sinho', cls: 'capital', tier: 3, role: 'Тяжёлый крейсер · залп',
    hp: 4200, armor: 0.34, maxSpeed: 14, thrust: 2.2, turn: 0.15, radius: 18,
    cost: 1700, build: 3, hyperCharge: 13, flee: 0.15,
    guns: [
      { type: 'heavy', dmg: 560, cd: 11, range: 840, charge: 1.6 },
      { type: 'missile', dmg: 210, cd: 5, range: 640, salvo: 3, spread: 0.06 },
    ],
    pd: { count: 5, dmg: 16, cd: 0.28, range: 130 },
    desc: 'Тот самый корабль, что идёт первым во вступительном ролике. ' +
          'Тяжёлый, медленный, с лазером и ракетными пакетами разом. ' +
          'Класс в открытых источниках не описан — если помнишь точнее, ' +
          'поправим.',
  });

  return base.map(d => {
    const bays = d.hangar ? d.hangar + (plk ? 1 : rez ? 2 : trd ? 0 : -1) : null;
    return {
      ...d,
      name: N[d.id][0], canon: N[d.id][1],
      role: d.hangar ? `Носитель · ${bays} звена` : d.role,
      hp: H(d.hp), armor: A(d.armor), cost: C(d.cost),
      build: Math.max(1, Math.round(d.build * buildMod)),
      stealth: rez, hangar: bays,
      guns: (d.guns || []).map(g => ({ ...g, dmg: G(g.dmg), cd: +(g.cd * cdMod).toFixed(2) })),
      pd: d.pd ? { ...d.pd, dmg: +(d.pd.dmg * pdDmg).toFixed(1), range: Math.round(d.pd.range * pdRange) } : null,
    };
  });
}

export const SHIPS = {};
export const STRIKE = {};
for (const f of FACTION_IDS) {
  SHIPS[f] = shipsFor(f);
  STRIKE[f] = strikeCraft(f);
}
// Рииз держит в звене семь машин вместо пяти
export const SQUAD_SIZE_OF = f => (f === 'reez' ? 7 : f === 'plektor' ? 6 : 5);
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
    cost: 400, build: 8, size: 9, vision: 40, produces: ['rifle', 'rocket', 'eng', 'sniper'],
    desc: 'Пехота: стрелки, ракетчики, ремонтники и снайперы.',
  },
  factory: {
    id: 'factory', name: 'Завод', cls: 'structure', hp: 2200, armor: 0.28,
    cost: 700, build: 12, size: 11, vision: 40, produces: ['scout', 'tank', 'ifv', 'aa', 'arty', 'mlrs'],
    desc: 'Техника: разведка, танки, БМП, ЗСУ и артиллерия.',
  },
  airfield: {
    id: 'airfield', name: 'Аэродром', cls: 'structure', hp: 1800, armor: 0.22,
    cost: 900, build: 14, size: 14, vision: 55, produces: ['jet', 'heli'],
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
  const hpMod    = trd ? 1.25 : plk ? 0.70 : rez ? 0.80 : 1.05;
  const armorMod = trd ? 1.25 : plk ? 0.75 : rez ? 0.50 : 1.10;
  const dmgMod   = trd ? 1.10 : plk ? 0.80 : rez ? 1.30 : 0.90;
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
    scout:  trd ? 'Разведмашина «Дозор»' : rez ? 'Глайдер «Шёпот»' : 'Мотоцикл-разведчик',
    ifv:    trd ? 'БМП «Копейщик»' : rez ? 'БМП «Наваждение»' : 'Пикап с автопушкой',
    eng:    trd ? 'Ремонтная группа' : rez ? 'Техники-невидимки' : 'Механики',
    mlrs:   trd ? 'РСЗО «Гроза»' : rez ? 'РСЗО «Морок»' : 'Связка труб на шасси',
    heli:   trd ? 'Вертолёт «Секира»' : rez ? 'Вертолёт «Тень»' : 'Винтокрыл-стервятник',
    sniper: trd ? 'Снайперская пара' : rez ? 'Ликвидатор' : 'Охотник с длинным стволом',
  };

  const mk = (o) => ({ ...o, hp: H(o.hp), armor: A(o.armor), cost: C(o.cost),
                       build: B(o.build), weapon: W(o.weapon), stealth: rez });

  return {
    worker: mk({
      id: 'worker', name: 'Сборщик', cls: 'vehicle', from: 'hq', tier: 1,
      hp: 260, armor: 0.1, speed: 13, cost: 180, build: 5,
      cargo: 90, vision: 35, weapon: null,
      desc: 'Возит снабжение с полей на штаб. Безоружен. Без сборщиков ' +
            'быстро кончатся деньги.',
    }),
    rifle: mk({
      id: 'rifle', name: nm.rifle, cls: 'infantry', from: 'barracks', tier: 1,
      hp: 170, armor: 0.05, speed: 8.5, cost: 120, build: 4,
      vision: 45, weapon: { type: 'rifle', dmg: 22, cd: 0.75, range: 34 },
      desc: 'Дёшево и сердито. Косит чужую пехоту, по технике почти бесполезна.',
    }),
    rocket: mk({
      id: 'rocket', name: nm.rocket, cls: 'infantry', from: 'barracks', tier: 1,
      hp: 150, armor: 0.05, speed: 7.5, cost: 200, build: 5,
      vision: 50, weapon: { type: 'at', dmg: 90, cd: 2.4, range: 48, air: true },
      desc: 'Вскрывает танки и достаёт самолёты. Против пехоты — плохо.',
    }),
    tank: mk({
      id: 'tank', name: nm.tank, cls: 'vehicle', from: 'factory', tier: 1,
      hp: 950, armor: 0.3, speed: plk ? 15 : 11.5, cost: 600, build: 8,
      vision: 50, weapon: { type: 'cannon', dmg: 130, cd: 2.1, range: 55 },
      desc: 'Основа наземной армии. Давит пехоту, ломает здания, ' +
            'боится ракетчиков и артиллерии.',
    }),
    aa: mk({
      id: 'aa', name: 'ЗСУ', cls: 'vehicle', from: 'factory', tier: 1,
      hp: 520, armor: 0.2, speed: 13, cost: 420, build: 6,
      vision: 70, weapon: { type: 'aa', dmg: 80, cd: 0.85, range: 95, air: true },
      desc: 'Зенитная самоходка. Ставь под колонну, иначе штурмовики ' +
            'выбьют технику за один заход.',
    }),
    arty: mk({
      id: 'arty', name: nm.arty, cls: 'vehicle', from: 'factory', tier: 2,
      hp: 420, armor: 0.12, speed: 7, cost: 760, build: 11,
      vision: 40, weapon: {
        type: 'arty', dmg: 200, cd: 6, range: 175, minRange: 45,
        splash: 14, arc: true, salvo: plk ? 2 : 1,
      },
      desc: 'Достаёт дальше любой турели, но слепая: без разведки бьёт ' +
            'в пустоту. Вблизи беззащитна, по воздуху не стреляет.',
    }),
    jet: mk({
      id: 'jet', name: nm.jet, cls: 'air', from: 'airfield', tier: 2,
      hp: 420, armor: 0.15, speed: 46, cost: 800, build: 10,
      vision: 80, air: true, ammo: trd ? 5 : 4, rearm: trd ? 6 : 9,
      weapon: { type: 'bomb', dmg: 240, cd: 0.9, range: 42, splash: 9 },
      desc: 'Заходит на цель, вываливает боезапас и возвращается на аэродром ' +
            'перезаряжаться. Пока летит домой — беззащитен.',
    }),

    // ── Открываются с ростом технологий ──────────────────────
    scout: mk({
      id: 'scout', name: nm.scout, cls: 'vehicle', from: 'factory', tier: 1,
      hp: 300, armor: 0.08, speed: 22, cost: 220, build: 4,
      vision: 130, weapon: { type: 'rifle', dmg: 26, cd: 0.7, range: 40 },
      desc: 'Глаза армии. Видит вдвое дальше всех и бегает быстрее всех, ' +
            'но в драке бесполезен. Без него артиллерия бьёт в пустоту, ' +
            'а маскировку Рииза никто не вскроет.',
    }),
    ifv: mk({
      id: 'ifv', name: nm.ifv, cls: 'vehicle', from: 'factory', tier: 2,
      hp: 620, armor: 0.22, speed: 15, cost: 460, build: 7,
      vision: 60, weapon: { type: 'auto', dmg: 62, cd: 0.55, range: 62, air: true },
      desc: 'Автопушка. Выкашивает пехоту быстрее танка и цепляет ' +
            'вертолёты, но лобовую броню не пробьёт — от танков держись ' +
            'подальше.',
    }),
    eng: mk({
      id: 'eng', name: nm.eng, cls: 'infantry', from: 'barracks', tier: 2,
      hp: 190, armor: 0.05, speed: 8, cost: 260, build: 6,
      vision: 40, weapon: null, repair: 55, repairRange: 26,
      desc: 'Чинит соседнюю технику и здания прямо в поле. Сам безоружен. ' +
            'Пара ремонтников за танковой колонной удваивает её живучесть.',
    }),
    mlrs: mk({
      id: 'mlrs', name: nm.mlrs, cls: 'vehicle', from: 'factory', tier: 3,
      hp: 400, armor: 0.10, speed: 9, cost: 900, build: 12,
      vision: 40, weapon: {
        type: 'arty', dmg: 130, cd: 8, range: 130, minRange: 35,
        splash: 26, arc: true, salvo: plk ? 6 : 4,
      },
      desc: 'Бьёт ближе ствольной артиллерии, зато накрывает залпом целую ' +
            'площадь. Идеально по скоплению пехоты и по стройке. ' +
            'Перезаряжается долго.',
    }),
    heli: mk({
      id: 'heli', name: nm.heli, cls: 'air', from: 'airfield', tier: 3,
      hp: 560, armor: 0.18, speed: 26, cost: 950, build: 12,
      vision: 85, air: true, ammo: 14, rearm: 5,
      weapon: { type: 'at', dmg: 115, cd: 1.6, range: 70, air: true },
      desc: 'В отличие от штурмовика не проносится мимо, а висит над полем ' +
            'и долбит по технике. Боезапаса вчетверо больше, зато тихоходен ' +
            'и от зениток не убежит.',
    }),
    sniper: mk({
      id: 'sniper', name: nm.sniper, cls: 'infantry', from: 'barracks', tier: 3,
      hp: 140, armor: 0.03, speed: 7, cost: 420, build: 8,
      vision: 95, stealthAlways: true,
      weapon: { type: 'sniper', dmg: 150, cd: 3.2, range: 88 },
      desc: 'Снимает пехоту с дистанции, на которой её нечем достать. ' +
            'По технике не стреляет вовсе. Не двигаясь — не виден, ' +
            'но один залп артиллерии его стирает.',
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
    { id: 'klotho',     name: 'Клото',        pos: [30, -4, -46], income: 280, slots: 5, biome: 'klotho', homeOf: 'troyden' },
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
    { id: 'ferrum',     name: 'Феррум',       pos: [-28, 12, 66], income: 250, slots: 4, biome: 'desert', start: 'devian' },
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
  lab:      { id: 'lab',      name: 'Научный центр',       cost: 900,  desc: '+45 очков науки за ход' },
  aogun:    { id: 'aogun',    name: 'Противоорбитальное орудие', cost: 1100,
              desc: 'Бьёт по чужому флоту снизу вверх во время боя на орбите' },
  shipyard: { id: 'shipyard', name: 'Верфь',               cost: 800,  desc: 'Позволяет строить корабли' },
  garrison: { id: 'garrison', name: 'Гарнизон',            cost: 600,  desc: 'Позволяет набирать полки' },
  station:  { id: 'station',  name: 'Орбитальная станция', cost: 1400, desc: 'Крепость в бою на орбите' },
};

export const REGIMENT_COST = 350;

/* ─────────────────────────────────────────────────────────────
   ДАВЛЕНИЕ ЗЕМЛИ.

   Бой на орбите не может тянуться вечно. Если у защитника на планете
   стоит противоорбитальное орудие, оно вмешивается в космический бой
   снизу вверх, сквозь атмосферу, с постоянным периодом. Атакующему
   приходится ломать оборону быстро, а не выжидать.

   Оружие у каждого клана своё и бьёт по-разному: одно калечит
   отдельный корабль, другое накрывает площадь, третье ослепляет флот
   целиком. Общее одно — таймер виден игроку, и по нему можно
   планировать заход.
   ───────────────────────────────────────────────────────────── */

export const ORBITAL_DEFENCE = {
  troyden: {
    name: 'Ионный луч', short: 'ИОН', period: 26, warn: 4,
    kind: 'beam', dmg: 900, disable: 10, color: 0x8fd8ff,
    desc: 'Сжигает броню одному кораблю и на десять секунд глушит ему ' +
          'двигатели: цель повисает в пустоте неуправляемой мишенью.',
  },
  plektor: {
    name: 'Ядерная ракета', short: 'ЯДР', period: 34, warn: 7,
    kind: 'nuke', dmg: 1500, radius: 190, color: 0xffb060,
    desc: 'Идёт снизу семь секунд — за это время из-под неё можно уйти. ' +
          'Кто не ушёл, получает колоссальный урон по площади.',
  },
  devian: {
    name: 'РЭБ-излучатель', short: 'РЭБ', period: 30, warn: 3,
    kind: 'blind', blind: 15, color: 0xc79fff,
    desc: 'Накрывает весь чужой флот помехами: наведение сбито, ' +
          'миникарта гаснет на пятнадцать секунд.',
  },
  reez: {
    name: 'ЭМИ-капсулы', short: 'ЭМИ', period: 28, warn: 5,
    kind: 'emp', sabotage: 18, color: 0x8fffc8,
    desc: 'Прилипают к носителям и флагманам и саботируют их системы: ' +
          'на восемнадцать секунд ангары не выпускают авиацию.',
  },
};

export const ORBITAL_DEFENCE_OF = f => ORBITAL_DEFENCE[f] || ORBITAL_DEFENCE.troyden;

/* ─────────────────────────────────────────────────────────────
   РАЗВИТИЕ.

   Ресурс один — кредиты. Их дают сами планеты (поле income) и
   рудники на них. Наука — вторая, непокупаемая валюта: её дают
   только научные центры, и потратить её можно лишь на следующий
   уровень технологий.

   Уровень технологий у клана один на всю кампанию и открывает
   технику разом и в космосе, и на земле: у кораблей это поле
   `tier`, у наземных юнитов — `tier`. Поэтому вкладываться в науку
   выгоднее, чем в очередной рудник, но наука не кормит флот.
   ───────────────────────────────────────────────────────────── */

export const RESEARCH_PER_LAB = 45;
export const RESEARCH_BASE = 10;      // столько капает даже без центров

export const TECH_LEVELS = [
  {
    level: 1, cost: 0, name: 'Мобилизация',
    unlocks: 'Корветы и фрегаты · пехота, танки, ЗСУ, разведчики',
  },
  {
    level: 2, cost: 900, name: 'Тяжёлые платформы',
    unlocks: 'Корабли РЭБ, крейсеры, носители · артиллерия, БМП, ' +
             'штурмовики, ремонтники',
  },
  {
    level: 3, cost: 2400, name: 'Главный калибр',
    unlocks: 'Флагманы · РСЗО, ударные вертолёты, снайперы',
  },
  {
    level: 4, cost: 5000, name: 'Боевые протоколы',
    unlocks: 'Новой техники нет: вся уже построенная получает ' +
             '+15% прочности и +10% урона',
  },
];

export const MAX_TECH = TECH_LEVELS.length;

// Бонус последнего уровня — единственное, что меняет числа задним числом
export function techBonus(level) {
  return level >= 4 ? { hp: 1.15, dmg: 1.10 } : { hp: 1, dmg: 1 };
}

export function techCost(level) {
  const t = TECH_LEVELS[level];      // level — текущий, индекс даёт следующий
  return t ? t.cost : null;
}

export const BIOME_COLORS = {
  klotho: { ground: 0x8a7550, accent: 0xb09a6c, rock: 0x6a5a3e, sky: 0x2e2a1e },
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
