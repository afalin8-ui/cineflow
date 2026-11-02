#!/usr/bin/env python3
"""УСТАНОВКА РУЧНОЙ МОДЕЛИ КОРАБЛЯ (CLAUDE.md, раздел 15, «Ручные модели флота»).

Ручная модель — корабль, сделанный в Blender (а не выгруженный из three.js), со своей
записью обмера. Её ставит этот скрипт, и только он: выгрузка `export_ships.mjs` такие записи
не перезаписывает, а `export_ships.mjs --check` проверяет их по своим правилам (файл есть
и не подменён, узлы из doctrine.json → nodes на месте, длина в ±20% от model_len).

Запуск из корня репозитория (одна команда на сколько угодно кораблей):

    python3 godot/tools/install_model.py troyden.cruiser=ПАПКА [plektor.frigate=ПАПКА …]
            [--sheet ПАПКА_ЛИСТА] [--fit model_len|none] [--godot ПРОГРАММА] [--dry]

ПАПКА — то, что отдаёт сборка модели: `ship_models_record.json` (запись — её собирает
`make_record.py` автора модели; ИСТОЧНИК ДАННЫХ — она, а не extras в .glb: там поле plume
лежит строкой JSON) и .glb. Если .glb несколько — берётся `*_shared.glb` (трим-лист общий,
в файле заглушка), иначе единственный. `--sheet` — папка с общим трим-листом флота
(`trim_basecolor/normal/orm/emission.png`): кладётся в view/hero/tex/ (нужен один раз).

Что делает:
1. проверяет запись: узлы из doctrine.json → nodes корабля на месте, узлы оружия модели есть
   в данных, `plume` — словарь (не строка), узлы записи есть в .glb, материалы совпадают;
2. МАСШТАБ: модель встаёт ровно в длину корабля в бою (`--fit model_len`, по умолчанию) —
   `space_data.json → model_len.ship[id]`; от неё модель считает корпус для расталкивания
   и строя (hull = max(radius × 1,6, len × 0,36)), и трогать её нельзя: она одна на все
   кланы и в модели боя. Запись хранит обмер УЖЕ В ЕДИНИЦАХ БОЯ (len, aabb, pos, size…),
   поле `scale` — во сколько вид уменьшает модель (ShipVisual). `--fit none` — как есть
   (только если длина и так в ±20%);
3. копирует .glb в godot/view/hero/<клан>_<id>.glb (с .import: без LOD, без анимаций,
   картинки — извлечь), убирает устаревшие извлечённые картинки (`*_ao.png` от файлов,
   которых больше нет);
4. пишет запись в godot/data/ship_models.json с полем `hand` (кто поставил, sha256 файла,
   длина до масштаба) — по нему выгрузка её не трогает;
5. с `--godot` — импорт проекта (карта AO извлекается в view/hero/ при импорте).
"""
import hashlib
import json
import os
import shutil
import struct
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
PROJ = os.path.join(ROOT, 'godot')
HERO = os.path.join(PROJ, 'view', 'hero')
MODELS = os.path.join(PROJ, 'data', 'ship_models.json')
DOCTRINE = os.path.join(PROJ, 'data', 'doctrine.json')
SPACE = os.path.join(PROJ, 'data', 'space_data.json')
SHEET = ('trim_basecolor.png', 'trim_normal.png', 'trim_orm.png', 'trim_emission.png')
LEN_TOL = 0.2
IMPORT_PARAMS = """[params]

nodes/root_type=""
nodes/root_name=""
nodes/root_script=null
mesh_library/use_node_names_as_mesh_names=false
array_mesh/deduplicate_surfaces=true
nodes/apply_root_scale=true
nodes/root_scale=1.0
nodes/import_as_skeleton_bones=false
nodes/use_name_suffixes=true
nodes/use_node_type_suffixes=true
meshes/ensure_tangents=true
meshes/generate_lods=false
meshes/create_shadow_meshes=true
meshes/light_baking=1
meshes/lightmap_texel_size=0.2
meshes/force_disable_compression=false
skins/use_named_skins=true
animation/import=false
animation/fps=30
animation/trimming=false
animation/remove_immutable_tracks=true
animation/import_rest_as_RESET=false
import_script/path=""
materials/extract=0
materials/extract_format=0
materials/extract_path=""
_subresources={}
gltf/naming_version=2
gltf/embedded_image_handling=1
gltf/texture_map_mode=1
"""
# числа, которые меняет масштаб: обмер и у узлов — положение, размер сопла, размер факела
SCALED_TOP = ('len', 'len_z', 'width', 'height')


def die(msg):
    print('install_model: ' + msg, file=sys.stderr)
    sys.exit(2)


def glb_json(path):
    with open(path, 'rb') as f:
        head = f.read(20)
        if len(head) < 20 or head[:4] != b'glTF':
            die(f'{path}: не .glb')
        n = struct.unpack('<I', head[12:16])[0]
        return json.loads(f.read(n))


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def has_model_node(names, model):
    if model.endswith('*'):
        pre = model[:-1]
        return any(n.startswith(pre) and n[len(pre):].isdigit() for n in names)
    return model in names


def pick_glb(folder):
    glbs = sorted(f for f in os.listdir(folder) if f.endswith('.glb'))
    shared = [f for f in glbs if f.endswith('_shared.glb')]
    if len(shared) == 1:
        return os.path.join(folder, shared[0])
    if len(glbs) == 1:
        return os.path.join(folder, glbs[0])
    die(f'{folder}: не понять, какой .glb ставить ({", ".join(glbs) or "нет ни одного"})')


def r6(x):
    return round(x, 6)


def scale_record(rec, k):
    out = json.loads(json.dumps(rec))
    for key in SCALED_TOP:
        if key in out:
            out[key] = r6(out[key] * k)
    if 'aabb' in out:
        out['aabb'] = [[r6(v * k) for v in corner] for corner in out['aabb']]
    for n in out.get('nodes', {}).values():
        if 'pos' in n:
            n['pos'] = [r6(v * k) for v in n['pos']]
        if 'size' in n:
            n['size'] = r6(n['size'] * k)
        if isinstance(n.get('plume'), dict) and 'size' in n['plume']:
            n['plume']['size'] = r6(n['plume']['size'] * k)
    return out


def problems(fac, sid, rec, gj, doctrine, space):
    """Беды записи до установки (пусто — можно ставить)."""
    bad = []
    nodes = rec.get('nodes')
    if not isinstance(nodes, dict) or not nodes:
        return ['в записи нет узлов']
    spec = doctrine['nodes']['v'].get(sid)
    if spec is None:
        return [f'в doctrine.json → nodes нет корабля {sid}']
    names = list(nodes)
    for key, n in spec.items():
        if not has_model_node(names, n['model']):
            bad.append(f'узел «{key}» ({n["model"]}) из doctrine.json не найден в записи')
    spec_models = [n['model'] for n in spec.values()]
    for nm in names:
        if (nm.split('_')[0] in ('turret', 'aux', 'launcher') and nm.split('_')[-1].isdigit()
                and nm not in spec_models):
            bad.append(f'узел {nm} есть в модели, но не в doctrine.json')
    for nm, n in nodes.items():
        p = n.get('pos')
        if not (isinstance(p, list) and len(p) == 3 and all(isinstance(v, (int, float)) for v in p)):
            bad.append(f'{nm}: нет положения')
        if 'plume' in n:
            pl = n['plume']
            if isinstance(pl, str):
                bad.append(f'{nm}: plume строкой — запись собрана из extras .glb, а не make_record.py')
            elif not isinstance(pl, dict) or not (pl.get('size', 0) > 0):
                bad.append(f'{nm}: plume без размера')
    in_glb = {n.get('name') for n in gj.get('nodes', [])}
    for nm in names:
        if nm not in in_glb:
            bad.append(f'узла {nm} нет в .glb')
    mats = [m.get('name') for m in gj.get('materials', [])]
    if rec.get('materials') and sorted(rec['materials']) != sorted(mats):
        bad.append(f'материалы записи и .glb разные: {rec["materials"]} против {mats}')
    if not (rec.get('len', 0) > 0 and rec.get('width', 0) > 0 and rec.get('height', 0) > 0):
        bad.append('нет длины, ширины или высоты')
    if sid not in space['model_len']['ship']:
        bad.append(f'нет model_len.ship.{sid} в space_data.json')
    return bad


def install_import(dst):
    imp = dst + '.import'
    if not os.path.exists(imp):
        with open(imp, 'w') as f:
            f.write(IMPORT_PARAMS)


# лист флота: без сжатия (тон, как у автора), но С МИП-УРОВНЯМИ и без «detect 3D». Импорт по умолчанию
# (картинка для 2D) мипов не делает — тогда на рабочем виде 2400, где лист 2048² ложится на сотню
# точек экрана, огни и швы листа мерцают россыпью; а «detect 3D» в редакторе сам перевёл бы лист
# в сжатие VRAM и молча сменил тон (CLAUDE.md, раздел 15)
SHEET_PARAMS = {'compress/mode': '0', 'mipmaps/generate': 'true', 'detect_3d/compress_to': '0'}


def sheet_import(png):
    """.import листа с SHEET_PARAMS: свой — правится построчно, нет — пишется (uid и путь допишет Godot)."""
    imp = png + '.import'
    if os.path.exists(imp):
        lines = open(imp, encoding='utf-8').read().split('\n')
        seen = set()
        for i, ln in enumerate(lines):
            k = ln.split('=', 1)[0]
            if k in SHEET_PARAMS:
                lines[i] = f'{k}={SHEET_PARAMS[k]}'
                seen.add(k)
        miss = [f'{k}={v}' for k, v in SHEET_PARAMS.items() if k not in seen]
        text = '\n'.join(lines).rstrip('\n') + '\n' + ''.join(m + '\n' for m in miss)
    else:
        text = '[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\n' + \
            ''.join(f'{k}={v}\n' for k, v in SHEET_PARAMS.items())
    with open(imp, 'w', encoding='utf-8') as f:
        f.write(text)


def sheet_import_problems():
    bad = []
    for name in SHEET:
        imp = os.path.join(HERO, 'tex', name + '.import')
        got = {}
        if os.path.exists(imp):
            for ln in open(imp, encoding='utf-8'):
                k, _, v = ln.strip().partition('=')
                if k in SHEET_PARAMS:
                    got[k] = v
        for k, v in SHEET_PARAMS.items():
            if got.get(k) != v:
                bad.append(f'лист {name}: {k}={got.get(k, "нет")}, ждали {v}')
    return bad


def drop_stale_images(folder=None):
    """Картинки, которые Godot извлёк из .glb, которых больше нет (переименовали, поставили
    другой файл): «<имя .glb>_<картинка>.png». Сиротам — прочь, иначе путают (как
    cruiser_cruiser_ao.png после замены cruiser.glb)."""
    folder = folder or HERO
    stems = [f[:-4] for f in os.listdir(folder) if f.endswith('.glb')]
    gone = []
    for f in sorted(os.listdir(folder)):
        if not f.endswith('.png'):
            continue
        if any(f.startswith(s + '_') for s in stems):
            continue
        for p in (f, f + '.import'):
            if os.path.exists(os.path.join(folder, p)):
                os.remove(os.path.join(folder, p))
        gone.append(f)
    return gone


def selftest():
    """Путь установки цел (гоняет run_tests.sh): у каждой ручной модели в обмере запись, разобранная
    обратно в «запись автора» (до масштаба), проходит проверки и ставится в ту же запись; sha256
    файла тот же; порча каждой проверки краснеет своим словом; сироты-картинки убираются."""
    import tempfile
    doctrine = json.load(open(DOCTRINE, encoding='utf-8'))
    space = json.load(open(SPACE, encoding='utf-8'))
    models = json.load(open(MODELS, encoding='utf-8'))
    fails = []
    checks = 0
    hand = [(f, i, r) for f, ships in models['ships'].items() for i, r in ships.items() if r.get('hand')]
    if not hand:
        fails.append('в обмере нет ни одной ручной модели')
    for fac, sid, rec in hand:
        tag = f'{fac}.{sid}'
        glb = os.path.join(PROJ, rec['file'].replace('res://', ''))
        gj = glb_json(glb)
        checks += 1
        if sha256(glb) != rec['hand']['sha256']:
            fails.append(f'{tag}: sha256 файла не тот, что при установке')
        k = rec['scale']
        raw = scale_record({x: y for x, y in rec.items() if x not in ('file', 'scale', 'hand')}, 1.0 / k)
        checks += 1
        bad = problems(fac, sid, raw, gj, doctrine, space)
        if bad:
            fails.append(f'{tag}: запись не проходит своих проверок: {bad}')
        # повторная установка тем же --fit, каким ставили: model_len — в длину корабля в бою, none — как есть
        fit_k = space['model_len']['ship'][sid] / raw['len'] if rec['hand'].get('fit') == 'model_len' else 1.0
        again = scale_record(raw, fit_k)
        checks += 1
        diff = [x for x in ('len', 'width', 'height') if abs(again[x] - rec[x]) > 1e-3]
        diff += [n for n in rec['nodes'] if 'pos' in rec['nodes'][n]
                 and max(abs(a - b) for a, b in zip(again['nodes'][n]['pos'], rec['nodes'][n]['pos'])) > 1e-3]
        if diff:
            fails.append(f'{tag}: повторная установка дала другой обмер: {diff}')
        checks += 1
        if abs(rec['len'] - space['model_len']['ship'][sid]) > 1e-3 and rec['hand'].get('fit') == 'model_len':
            fails.append(f'{tag}: длина {rec["len"]} не равна model_len')

        def spoiled(what, f, mark, use_glb=gj):
            nonlocal checks
            checks += 1
            r2 = json.loads(json.dumps(raw))
            g2 = json.loads(json.dumps(use_glb))
            f(r2, g2)
            got = problems(fac, sid, r2, g2, doctrine, space)
            if not any(mark in b for b in got):
                fails.append(f'{tag}: откат «{what}» не покраснел (ждали «{mark}»): {got}')

        plumes = [n for n, v in raw['nodes'].items() if isinstance(v.get('plume'), dict)]
        if plumes:
            spoiled('plume строкой из extras', lambda r, g: r['nodes'][plumes[0]].update(
                plume=json.dumps(r['nodes'][plumes[0]]['plume'])), 'plume строкой')
        spoiled('нет узла из doctrine.json', lambda r, g: r['nodes'].pop('hull'), '«hull»')
        spoiled('узел записи не в .glb', lambda r, g: g.update(nodes=[n for n in g['nodes'] if n.get('name') != 'bay']),
                'узла bay нет в .glb')
        spoiled('лишняя башня', lambda r, g: r['nodes'].update(turret_7={'pos': [0, 0, 0]}), 'не в doctrine.json')
        spoiled('материалы разные', lambda r, g: g['materials'].pop(), 'материалы записи')
    checks += 1
    bad = sheet_import_problems()
    if bad:
        fails.append('импорт листа: ' + '; '.join(bad))
    with tempfile.TemporaryDirectory() as d:
        # порча: .import листа по умолчанию (2D: без мипов, «detect 3D») — sheet_import чинит
        p = os.path.join(d, 'trim_x.png')
        open(p + '.import', 'w').write('[params]\n\ncompress/mode=0\nmipmaps/generate=false\ndetect_3d/compress_to=1\n')
        sheet_import(p)
        checks += 1
        txt = open(p + '.import').read()
        if 'mipmaps/generate=true' not in txt or 'detect_3d/compress_to=0' not in txt or 'mipmaps/generate=false' in txt:
            fails.append(f'sheet_import не поправил .import листа: {txt!r}')
    with tempfile.TemporaryDirectory() as d:
        for f in ('a_ship.glb', 'a_ship_cruiser_ao.png', 'cruiser_cruiser_ao.png', 'cruiser_cruiser_ao.png.import'):
            open(os.path.join(d, f), 'w').close()
        os.makedirs(os.path.join(d, 'tex'))
        gone = drop_stale_images(d)
        checks += 1
        left = sorted(os.listdir(d))
        if gone != ['cruiser_cruiser_ao.png'] or left != ['a_ship.glb', 'a_ship_cruiser_ao.png', 'tex']:
            fails.append(f'сироты-картинки: убраны {gone}, осталось {left}')
    for f in fails:
        print('  ' + f, file=sys.stderr)
    print(f'install_model --selftest: ручных моделей {len(hand)}, проверок {checks}, провалов {len(fails)}')
    sys.exit(1 if fails else 0)


def main(argv):
    if argv == ['--selftest']:
        selftest()
    fit = 'model_len'
    sheet = None
    godot = None
    dry = False
    jobs = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ('--fit', '--sheet', '--godot'):
            if i + 1 >= len(argv):
                die(f'{a}: нет значения')
            v = argv[i + 1]
            i += 2
            if a == '--fit':
                if v not in ('model_len', 'none'):
                    die('--fit: model_len или none')
                fit = v
            elif a == '--sheet':
                sheet = v
            else:
                godot = v
            continue
        if a == '--dry':
            dry = True
        elif '=' in a and '.' in a.split('=', 1)[0]:
            ship, folder = a.split('=', 1)
            fac, sid = ship.split('.', 1)
            jobs.append((fac, sid, folder))
        else:
            die(f'непонятный ключ {a} (см. начало файла)')
        i += 1
    if not jobs and not sheet:
        die('нечего ставить: клан.id=ПАПКА или --sheet ПАПКА')
    doctrine = json.load(open(DOCTRINE, encoding='utf-8'))
    space = json.load(open(SPACE, encoding='utf-8'))
    with open(MODELS, encoding='utf-8') as f:
        models = json.load(f)
    os.makedirs(os.path.join(HERO, 'tex'), exist_ok=True)
    if sheet:
        for name in SHEET:
            src = os.path.join(sheet, name)
            if not os.path.exists(src):
                die(f'--sheet: нет {src}')
            if not dry:
                shutil.copyfile(src, os.path.join(HERO, 'tex', name))
                sheet_import(os.path.join(HERO, 'tex', name))
        print(f'лист флота → godot/view/hero/tex/ ({len(SHEET)} картинки, мип-уровни, без сжатия)')
    for name in SHEET:
        if not os.path.exists(os.path.join(HERO, 'tex', name)) and not dry:
            die(f'нет общего листа godot/view/hero/tex/{name} — поставь его ключом --sheet')
    all_bad = []
    for fac, sid, folder in jobs:
        rec_path = os.path.join(folder, 'ship_models_record.json')
        if not os.path.exists(rec_path):
            die(f'{folder}: нет ship_models_record.json (его собирает make_record.py)')
        rec = json.load(open(rec_path, encoding='utf-8'))
        src = pick_glb(folder)
        gj = glb_json(src)
        bad = problems(fac, sid, rec, gj, doctrine, space)
        if fac not in models['ships']:
            bad.append(f'клана {fac} нет в ship_models.json')
        if bad:
            all_bad += [f'{fac}.{sid}: {b}' for b in bad]
            continue
        want = space['model_len']['ship'][sid]
        raw = rec['len']
        k = want / raw if fit == 'model_len' else 1.0
        if fit == 'none' and abs(raw - want) > want * LEN_TOL:
            all_bad.append(f'{fac}.{sid}: длина {raw} вне ±20% от model_len {want} — ставь с --fit model_len')
            continue
        out = scale_record(rec, k)
        name = f'{fac}_{sid}.glb'
        out['file'] = 'res://view/hero/' + name
        out['bytes'] = os.path.getsize(src)
        out['materials'] = [m.get('name') for m in gj.get('materials', [])]
        out['scale'] = r6(k)
        out['hand'] = {
            'by': 'godot/tools/install_model.py',
            'sha256': sha256(src),
            'raw_len': raw,
            'fit': fit,
            'source': os.path.basename(src),
            'note': 'ручная модель: выгрузка export_ships.mjs её не перезаписывает; обмер — в единицах боя, '
                    'scale — во сколько вид уменьшает модель',
        }
        dst = os.path.join(HERO, name)
        if not dry:
            shutil.copyfile(src, dst)
            install_import(dst)
            models['ships'][fac][sid] = out
        print(f'{fac}.{sid}: {os.path.basename(src)} → godot/view/hero/{name}; длина {raw} → {out["len"]} '
              f'(model_len {want}, масштаб {out["scale"]}), ширина {out["width"]}, узлов {len(out["nodes"])}, '
              f'треугольников {out.get("tris")}')
    if all_bad:
        for b in all_bad:
            print('  ' + b, file=sys.stderr)
        die(f'беды: {len(all_bad)} — ничего не записано' if not dry else f'беды: {len(all_bad)}')
    if dry:
        print('--dry: ничего не записано')
        return
    with open(MODELS, 'w', encoding='utf-8') as f:
        f.write(json.dumps(models, ensure_ascii=False, indent=1) + '\n')
    gone = drop_stale_images()
    if gone:
        print('убраны устаревшие картинки: ' + ', '.join(gone))
    print('обмер → godot/data/ship_models.json')
    if godot:
        r = subprocess.run([godot, '--headless', '--path', PROJ, '--import'], capture_output=True, text=True)
        if r.returncode != 0:
            print(r.stdout[-2000:] + r.stderr[-2000:], file=sys.stderr)
            die(f'импорт: код {r.returncode}')
        gone = drop_stale_images()
        print('импорт проекта — готово' + (f'; убраны {", ".join(gone)}' if gone else ''))
    else:
        print('дальше: импорт проекта (godot --headless --path godot --import), потом '
              'node godot/tools/export_ships.mjs --check и godot/tools/run_tests.sh')


if __name__ == '__main__':
    main(sys.argv[1:])
