#!/usr/bin/env python3
"""Справочник CineFlow: кладёт handbook/fixtures.json внутрь index.html.

Приборы живут в handbook/fixtures.json — это исходник, его и правят.
В приложение они едут блоком <script type="application/json"
id="cf-handbook-fixtures"> внутри index.html: отдельный файл service worker
отдавал бы из кэша, не спрашивая сеть, и поправленная таблица до людей
не доехала бы.

Скрипт заодно проверяет данные: у каждого прибора бренд, название и
источник, у каждого замера — положительные расстояние и освещённость.
Ошибка в таблице — это неверная диафрагма на площадке, поэтому кривое
не кладётся вовсе, а сборка падает со словами, что именно не так.

    python3 build-handbook.py
"""
import json, re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent
SRC = ROOT / 'handbook' / 'fixtures.json'
APP = ROOT / 'index.html'
KINDS = {'point', 'panel', 'tube', 'fresnel', 'par', 'mat', 'other'}
COLORS = {'daylight', 'bicolor', 'rgb', 'tungsten'}

def fail(msg):
    sys.exit('handbook: ' + msg)

data = json.loads(SRC.read_text(encoding='utf-8'))
if not isinstance(data, list):
    fail('ожидался список приборов')
seen = set()
for i, f in enumerate(data):
    where = f'#{i} {f.get("brand")} {f.get("name")}'
    for k in ('brand', 'name', 'url'):
        if not f.get(k):
            fail(f'{where}: нет поля {k}')
    if f.get('kind') not in KINDS:
        fail(f'{where}: kind {f.get("kind")!r}')
    if f.get('color') not in COLORS:
        fail(f'{where}: color {f.get("color")!r}')
    key = (f['brand'].lower(), f['name'].lower())
    if key in seen:
        fail(f'{where}: прибор повторяется')
    seen.add(key)
    for j, p in enumerate(f.get('photometry') or []):
        if not p.get('mod'):
            fail(f'{where}, замер {j}: нет названия режима')
        pts = p.get('pts') or []
        if not pts:
            fail(f'{where}, {p["mod"]}: нет точек')
        for d, e in pts:
            if not (isinstance(d, (int, float)) and d > 0 and isinstance(e, (int, float)) and e > 0):
                fail(f'{where}, {p["mod"]}: точка {d}, {e}')
        ds = sorted(d for d, _ in pts)
        if len(set(ds)) != len(ds):
            fail(f'{where}, {p["mod"]}: расстояние повторяется')
        # Дальше — темнее. Обратное почти всегда опечатка при переносе.
        es = [e for _, e in sorted(pts)]
        if any(b > a for a, b in zip(es, es[1:])):
            fail(f'{where}, {p["mod"]}: освещённость растёт с расстоянием')

blob = json.dumps(data, ensure_ascii=False, separators=(',', ':')).replace('</', '<\\/')
html = APP.read_text(encoding='utf-8')
pat = re.compile(r'(<script type="application/json" id="cf-handbook-fixtures">)(.*?)(</script>)', re.S)
if len(pat.findall(html)) != 1:
    fail('в index.html не найден ровно один блок cf-handbook-fixtures')
html = pat.sub(lambda m: m.group(1) + blob + m.group(3), html)
APP.write_text(html, encoding='utf-8')
n_ph = sum(1 for f in data if f.get('photometry'))
print(f'handbook: {len(data)} приборов, с фотометрией {n_ph}, {len(blob) // 1024} КБ')
