# Тестовая версия «на посмотреть» — подпапкой, не трогая рабочее приложение.
#
# Зачем отдельная папка: проверить видео надо на iPad и iPhone, с живым
# Dropbox и настоящим роликом с камеры, а рабочий адрес при этом должен
# остаться прежним — по нему работает группа. Так уже делали с /proba/.
#
# Что важно и не видно на глаз: приложение и его копия лежат на ОДНОМ
# адресе сайта, значит у них общий Cache Storage. Скопировав service
# worker как есть, копия начала бы делить кэши с корнем — а её чистка
# старых версий снесла бы корневые. Поэтому у копии свой род имён
# (FAMILY) и чистка ТОЛЬКО своих кэшей. Собранный код тоже в своём
# кэше: у корня и копии разные исходники, и общий кэш они бы вытесняли
# друг у друга, заставляя Babel переводить десять тысяч строк заново.
#
# Что ОБЩЕЕ и это намеренно: комната, localStorage и ключи облака. Копия
# открывает ТОТ ЖЕ проект и ТО ЖЕ хранилище — подключать заново нечего,
# а пробные ролики потом удаляются как обычные референсы.
#
# ПАПКУ НЕЛЬЗЯ ПРОСТО УДАЛИТЬ, когда проверка кончилась. У копии свой
# service worker, и у того, кто поставил её на домашний экран, он остался
# бы жить навсегда: приложение открывалось бы из кэша старой сборкой, молча
# и без единой ошибки. Правильный конец — оставить на её месте страницу,
# которая СНИМАЕТ свой service worker, стирает ТОЛЬКО свои кэши и уводит
# в рабочее приложение. Так закрыта папка /video/ — можно взять за образец.
#
# Запуск из корня репозитория:
#   python3 build-video.py                       — из файлов рядом
#   python3 build-video.py --ref <ветка>         — из файлов ветки
#
# Второй вид нужен затем, что папку кладут на master (её отдаёт Pages),
# а само видео живёт в ветке: собирать «из того, что рядом», стоя
# на master, значило бы выложить копию БЕЗ видео и не заметить этого.
import io, os, subprocess, sys

ROOT = os.path.dirname(os.path.abspath(__file__))
DST = os.path.join(ROOT, 'video')
NAME = 'CineFlow · видео'
FAMILY = 'cineflow-video'
REF = ''
if '--ref' in sys.argv:
    REF = sys.argv[sys.argv.index('--ref') + 1]

def read(p):
    if REF:
        return subprocess.run(['git', 'show', f'{REF}:{p}'], cwd=ROOT, check=True,
                              stdout=subprocess.PIPE).stdout.decode('utf-8')
    return io.open(os.path.join(ROOT, p), encoding='utf-8').read()

def write(p, s):
    io.open(os.path.join(DST, p), 'w', encoding='utf-8').write(s)

os.makedirs(DST, exist_ok=True)
changes = []

def must(cond, what):
    if not cond:
        print('build-video: не нашлось — ' + what)
        sys.exit(1)
    changes.append(what)

# --- index.html ---
app = read('index.html')

# Заголовок вкладки: когда открыты обе версии, он отличает их в списке
# вкладок. Правится в ДВУХ местах, иначе правка не видна: приложение
# переписывает title само, чтобы показать число непрочитанных в чате.
before = app
app = app.replace('<title>CineFlow Prep — Doppler Studio</title>',
                  f'<title>{NAME} (тест) — Doppler Studio</title>', 1)
must(app != before, 'заголовок страницы')

before = app
app = app.replace("+ 'CineFlow Prep'; }, [unreadCount]);",
                  f"+ '{NAME} (тест)'; }}, [unreadCount]);", 1)
must(app != before, 'заголовок со счётчиком чата')

# Свой кэш собранного кода (см. вводный комментарий).
before = app
app = app.replace("var CACHE = 'cf-app-build';", "var CACHE = 'cf-app-build-video';", 1)
must(app != before, 'кэш собранного кода')

# Метка «это тестовая версия». Внизу по центру, мимо пальца и мимо
# мини-карты доски (правый низ) и панели инструментов (лево). На телефоне
# не показывается вовсе: там внизу таб-бар, и место дороже подписи.
mark = """
      /* ТЕСТОВАЯ ВЕРСИЯ (подпапка /video/). Метка нужна затем, что копия
         открывает тот же проект, что и рабочий адрес: без неё человек
         не знает, где он. Нажатий не ловит и на телефоне скрыта. */
      body::after {
        content: 'видео · тестовая версия';
        position: fixed; left: 50%; transform: translateX(-50%); bottom: 2px;
        z-index: 90; pointer-events: none; opacity: .5;
        font: 700 8.5px/1 var(--font-mono); letter-spacing: .1em;
        color: var(--accent); background: var(--bg);
        border: 1px solid var(--border); border-radius: 5px; padding: 3px 7px;
      }
      @media (max-width: 699px) { body::after { display: none } }
    </style>"""
before = app
app = app.replace('\n    </style>', mark, 1)
must(app != before, 'метка тестовой версии')

write('index.html', app)

# --- sw.js ---
sw = read('sw.js')

before = sw
sw = sw.replace(
    "const VERSION = 'cineflow-v11';",
    "// Копия «на посмотреть» лежит на том же адресе сайта, что и рабочее\n"
    "// приложение, и Cache Storage у них общий. Свой род имён нужен затем,\n"
    "// чтобы чистка старых версий (ниже) не снесла кэш корневого приложения\n"
    "// и не отобрала у него офлайн. Правится сборщиком build-video.py.\n"
    f"const FAMILY = '{FAMILY}';\n"
    "const VERSION = FAMILY + '-v11';", 1)
must(sw != before, 'имя версии service worker')

before = sw
sw = sw.replace(
    "  await Promise.all(keys.filter(k => !k.startsWith(VERSION) && k !== 'cf-app-build')\n"
    "                        .map(k => caches.delete(k)));",
    "  // ТОЛЬКО СВОИ: кэши корневого приложения начинаются иначе, и снести\n"
    "  // их значило бы оставить рабочий адрес без офлайна.\n"
    "  await Promise.all(keys.filter(k => k.startsWith(FAMILY) && !k.startsWith(VERSION))\n"
    "                        .map(k => caches.delete(k)));", 1)
must(sw != before, 'чистка только своих кэшей')

write('sw.js', sw)

# --- manifest ---
man = read('manifest.webmanifest')
before = man
man = man.replace('"name": "CineFlow Prep"', f'"name": "{NAME} (тест)"', 1)
man = man.replace('"short_name": "CineFlow"', '"short_name": "CF видео"', 1)
must(man != before, 'название в манифесте')
write('manifest.webmanifest', man)

# --- значок ---
write('icon.svg', read('icon.svg'))

print('Собрано в ' + DST + (f' из ветки {REF}' if REF else ' из файлов рядом'))
for c in changes:
    print('  · ' + c)
