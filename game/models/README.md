# Модели кораблей и техники

По умолчанию игра рисует всё из коробок и цилиндров — это работает всегда
и весит ноль. Но сюда можно положить настоящие модели, и игра возьмёт их
вместо процедурных. Ничего в коде править не надо: только положить файл
и вписать строчку в `manifest.json`.

---

## Что нужно от модели

| Требование | Значение |
|---|---|
| Формат | **`.glb`** (glTF binary, текстуры вшиты внутрь) |
| Сжатие | Draco и meshopt понимаем — галочку в экспортёре можно не снимать |
| Полигоны | корабль — до 30 000, техника — до 8 000, здание — до 12 000 |
| Текстуры | 1024×1024 или 2048×2048, PBR: base color + normal + roughness + metallic |
| Размер файла | до 4 МБ на модель (иначе игра долго открывается на планшете) |
| Ориентация | нос корабля смотрит в **−Z**, верх — **+Y** |
| Опора | здания и техника: низ модели на нуле по Y |
| Материал | без анимаций, без скелета, один-два материала на модель |

Размер модели не важен: игра сама подгонит её под класс корабля.
Ориентацию, если она не та, чинят не в модели, а в манифесте — полем
`rotate` (градусы).

### Что игра НЕ откроет

- **`.fbx`, `.obj`, `.blend`, `.max`, `.dae`** — их надо сперва
  пересохранить в `.glb` (как — ниже).
- **`.gltf` россыпью** (сам файл + `.bin` + папка текстур) откроется,
  если положить всё рядом и не переименовывать. Но лучше всё-таки
  собрать в один `.glb`: одним файлом проще жить.
- **Текстуры в KTX2/Basis** — редкий формат сжатия картинок, декодера
  у нас нет. Пересохрани с обычными PNG/JPG.
- **Скелет и анимации** игра проигнорирует: возьмёт модель в позе
  по умолчанию. Гусеницы и винты она крутит своими средствами.

### Как пересохранить в .glb

Самое простое — **[Blender](https://www.blender.org/)** (бесплатный):
открыть модель, `File → Export → glTF 2.0 (.glb)`, в настройках
экспорта включить `Format: glTF Binary (.glb)` и `Include → Materials`.
Галочку `Compression` можно оставить включённой — Draco мы понимаем.

Онлайн, без установки: **[products.aspose.app/3d/conversion](https://products.aspose.app/3d/conversion)**
или **[anyconv.com/fbx-to-glb-converter](https://anyconv.com/fbx-to-glb-converter/)**.
Для секретных проектов онлайн-конвертеры не годятся, для CC0-моделей
из интернета — вполне.

Если модель тяжёлая (больше 4 МБ), её стоит облегчить:
**[gltf.report](https://gltf.report/)** — открывает `.glb` в браузере,
показывает вес по частям и умеет сжимать геометрию и текстуры одной
кнопкой.

---

## Как подключить

1. Положи файл, например `troyden_capital.glb`, в эту папку.
2. Открой `manifest.json` и добавь строку.

```json
{
  "models": {
    "ship:troyden:capital": {
      "file": "troyden_capital.glb",
      "rotate": [0, 180, 0]
    },
    "ship:devian:capital": "devian_dread.glb",
    "strike:any:fighter":  "fighter_generic.glb",
    "ground:troyden:tank": { "file": "paladin.glb", "groundLevel": true }
  }
}
```

Коротко: `"ключ": "файл.glb"` — если всё и так правильно;
`"ключ": { "file": ..., "rotate": [x, y, z], "scale": 1 }` — если нужно
довернуть или подмасштабировать.

### Ключи

```
ship:<клан>:escort | cruiser | carrier | capital | station
strike:<клан>:interceptor | fighter | bomber
ground:<клан>:worker | rifle | rocket | tank | aa | arty | jet
building:<клан>:hq | barracks | factory | airfield | turret | sam
```

`<клан>` — это `troyden`, `devian`, `plektor` или `any` (одна модель на всех).

Если файл не нашёлся или сломан — игра просто нарисует процедурную
модель и напишет предупреждение в консоль. Сломать игру плохой моделью
нельзя.

---

## Промты для Prism (3D AI Studio)

Prism 3.1 отдаёт `.glb` с полным набором PBR-карт — то, что нужно.
Prism Turbo быстрее и дешевле, годится для наземной техники.

**Общая часть — дописывай в конец каждого промта:**

> hard-surface sci-fi, low-poly game asset, clean topology, quad-based,
> single connected mesh, PBR textures 2048px, base color + normal +
> roughness + metallic, neutral studio lighting, no background, no ground
> plane, no text, no logos, symmetrical, front of the ship pointing along
> negative Z axis

### Клан Тройден — высокие технологии, дорого и штучно

**Линкор «Меридиан»**
> A sleek high-tech capital warship, 400 meters long, elongated angular
> hull with faceted armour panels, two twin laser turrets on the dorsal
> spine, long thin radiator wings on both sides, three large engine
> nozzles at the stern, pale gunmetal grey hull with polished cyan
> accent stripes, glowing cyan sensor strips, precise clean panel lines

**Крейсер «Вектор»**
> A medium sci-fi cruiser, 180 meters, narrow arrowhead hull, one heavy
> laser turret forward, swept radiator fins, two engine nozzles,
> light grey armour with cyan trim, crisp panel seams, no visible crew
> details

**Авианосец «Атриум»**
> A sci-fi carrier warship, wide flat flight deck, open hangar mouth at
> the bow, small command tower offset to starboard side, deck marked with
> glowing cyan landing strips, three engines at the stern, grey armour
> plating, no weapons except small point-defence turrets

**Фрегат «Клинок»**
> A small fast escort frigate, 60 meters, narrow wedge-shaped hull,
> pointed nose cone, two engine nacelles on short pylons, many small
> point-defence turret blisters along the hull, grey with cyan stripe

**Истребитель «Рекс»**
> A single-seat space fighter, sharp delta wings, bubble canopy, twin
> cannons in the nose, one rear engine, light grey with cyan wing edges,
> compact and aggressive silhouette

**Перехватчик «Скальпель»**
> A very slim space interceptor, extremely long thin straight wings,
> tiny fuselage, single engine, minimal armour, light grey with bright
> cyan leading edges, looks fragile and fast

**Бомбардировщик «Молот»**
> A heavy space bomber, thick blocky fuselage, torpedo bay bulge under
> the belly, short stubby wings, two engines, armoured cockpit, grey with
> cyan markings, looks slow and heavily loaded

### Клан Девиан — броня и главный калибр

**Дредноут «Гора»**
> A massive brutalist sci-fi dreadnought, 600 meters, slab-sided armoured
> hull built from thick overlapping plates, one enormous forward-facing
> spinal cannon, blocky superstructure, heavy armour belt, rust-orange and
> dark grey paint, industrial rivets and welds, no elegance, pure mass

**Крейсер «Молот»**
> A heavy armoured sci-fi cruiser, boxy hull with thick armour belt, one
> huge turret forward, small bridge tower, two big engines, dark grey with
> rust-orange stripes, industrial and blunt

**Носитель «Улей»**
> A blocky armoured carrier ship, flat armoured deck, two hangar doors,
> heavy plating everywhere, small tower, dark grey with orange trim,
> looks like a floating factory

**Заслон «Гранит»**
> A short stubby armoured escort ship, thick blunt nose, heavy plating,
> two engines, gun blisters, dark grey and rust-orange

### Клан Плэктор — собрано из хлама

**Линкор «Ржавый Король»**
> A patchwork pirate capital ship, asymmetric hull welded from mismatched
> salvaged sections, missile pod racks bolted on at odd angles, exposed
> pipes and cables, one stolen laser turret, mismatched paint, rust
> streaks, ochre yellow warning stripes, deliberately ugly and improvised

**Ракетоносец «Скорпион»**
> A scrappy missile cruiser, asymmetric hull, large missile launcher racks
> on both sides, exposed machinery, patched armour plates of different
> colours, ochre yellow stripes, rust and grime

**Плавучий док «Караван»**
> A converted civilian freighter used as a carrier, long flat cargo spine,
> four open hangar bays welded along the sides, cranes and containers,
> ochre yellow and rust, looks like a flying junkyard

### Земля (годится Prism Turbo)

**ОБТ «Паладин» (Тройден)**
> A futuristic main battle tank, angular sloped armour, long smoothbore
> cannon, low profile turret, tracked chassis, grey-green with cyan unit
> markings, game-ready low poly

**Танк «Тайфун» (Девиан)**
> A heavy futuristic battle tank, very thick boxy armour, short wide
> cannon, reactive armour blocks, wide tracks, dark grey with rust-orange
> markings

**РСЗО «Ураган» (Девиан)**
> A futuristic multiple rocket launcher vehicle, six-wheeled armoured
> truck chassis, box launcher with three large rocket tubes on the back,
> dark grey with orange markings

**ЗСУ**
> A futuristic anti-aircraft vehicle, wheeled armoured chassis, turret
> with twin autocannons pointing upward, radar dish on the side,
> grey military paint

**Штурмовик «Ястреб»**
> A futuristic ground-attack jet aircraft, straight wings with weapon
> pylons, twin engines at the rear, armoured cockpit, grey with cyan
> markings, landing gear retracted

**Штаб**
> A modular sci-fi military headquarters building, wide armoured base,
> tall central tower, communications antenna and radar dish on the roof,
> concrete and metal, grey with coloured accent stripes, flat bottom

**Завод**
> A sci-fi military vehicle factory building, wide hangar with large
> rolling door, three exhaust chimneys on the roof, industrial concrete
> and metal, flat bottom, grey

**Турель**
> A sci-fi automated defence turret, concrete base, armoured rotating
> turret with a single cannon, compact, grey military paint, flat bottom

---

## Если модель встала не так

| Что видно | Что править в манифесте |
|---|---|
| Корабль летит хвостом вперёд | `"rotate": [0, 180, 0]` |
| Корабль лежит на боку | `"rotate": [0, 0, 90]` |
| Корабль стоит «на попа» | `"rotate": [-90, 0, 0]` |
| Здание висит в воздухе / утонуло | `"groundLevel": true` |
| Модель слишком мелкая рядом с другими | `"scale": 1.3` |

Правится и проверяется за секунды: поменял число — обновил страницу.

---

## Где ещё брать модели бесплатно

- **Kenney** (kenney.nl) — space kit и tower-defence kit, лицензия CC0,
  можно брать и переделывать без ограничений. Стиль ровно тот, что
  сейчас в игре.
- **Poly Pizza** (poly.pizza) — большая библиотека low-poly, есть CC0.
- **Quaternius** (quaternius.com) — sci-fi техника и корабли, CC0.
- **Sketchfab** — много всего, но обязательно проверяй лицензию:
  берём только CC0 / CC-BY, а CC-BY требует указать автора.

Формат везде надо получить `.glb`. Если скачался `.fbx` или `.obj` —
открыть в Blender и экспортировать в glTF Binary.
