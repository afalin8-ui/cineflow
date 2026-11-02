#!/usr/bin/env python3
"""ЯРУСЫ В CI — ВСЕ И ПО ОДНОМУ РАЗУ (godot/CLAUDE.md, раздел 9, «Ярусы по заданиям CI»).

Ярусы тестов в CI разнесены по параллельным заданиям: задание `test-build` гоняет
`run_tests.sh rest <ярусы>` (всё, кроме ярусов, плюс названные), задание-матрица `tiers` —
`run_tests.sh tiers <ярусы>` по строке `tiers:` каждой своей ветки. Разнесение молча теряет
ярус, стоит забыть его вписать: прогон зелёный, а проверки не шли вовсе. Поэтому:

    python3 godot/tools/ci_tiers.py WORKFLOW ПАПКА_ТЕСТОВ -- ЯРУС…      проверка (код 1 — беды)
    python3 godot/tools/ci_tiers.py --selftest WORKFLOW ПАПКА_ТЕСТОВ -- ЯРУС…

ЯРУС… — полный список ярусов из run_tests.sh (`ALL_TIERS`, его же гоняет `run_tests.sh render`):
источник правды один, здесь он не повторяется. Правила:
1. каждый ярус списка гоняет РОВНО одно место CI (`rest` у test-build или ветка матрицы);
2. в CI нет яруса, которого нет в списке (опечатка гоняла бы пустоту — run.gd краснеет,
   но лучше сказать прямо);
3. у каждого файла `tests/test_<ярус>_*.gd` ярус есть в списке или это `bench` (его гоняет
   задание «стенд» — `run_tests.sh bench` обязан быть в файле);
4. матрица зовёт `run_tests.sh tiers ${{ matrix.tiers }}`, а задание `release` ждёт и её,
   и test-build, и windows-run: иначе упавший ярус не остановил бы выпуск.
`--selftest` портит копию файла (в памяти) по одному правилу и требует, чтобы покраснело
ИМЕННО оно.
"""
import os
import re
import sys


def parse(text):
    """→ (ярусы rest, [(ветка, [ярусы])], строки needs у release, есть ли вызов матрицы, есть ли bench)."""
    rest = None
    m = re.search(r'run_tests\.sh rest((?: [a-z_:]+)*)\s*$', text, re.M)
    if m:
        rest = m.group(1).split()
    legs = []
    for name, tiers in re.findall(r"^\s*-\s*name:\s*([\w-]+)\s*\n\s*tiers:\s*'([^']*)'", text, re.M):
        legs.append((name, tiers.split()))
    rel = re.search(r'^  release:\s*\n((?:    .*\n|\s*\n)*)', text, re.M)
    needs = ''
    if rel:
        n = re.search(r'^    needs:\s*(.*)$', rel.group(1), re.M)
        needs = n.group(1) if n else ''
    call = bool(re.search(r'run_tests\.sh tiers \$\{\{ matrix\.tiers \}\}', text))
    bench = bool(re.search(r'run_tests\.sh bench\b', text))
    return rest, legs, needs, call, bench


def problems(text, test_files, all_tiers):
    bad = []
    rest, legs, needs, call, bench = parse(text)
    if rest is None:
        bad.append('нет шага «run_tests.sh rest …» (задание test-build)')
        rest = []
    if not legs:
        bad.append('нет веток матрицы яруса (строки «- name: …» и «tiers: \'…\'»)')
    if not call:
        bad.append('матрица не зовёт «run_tests.sh tiers ${{ matrix.tiers }}»')
    where = {}
    for t in rest:
        where.setdefault(t, []).append('test-build')
    for name, tiers in legs:
        for t in tiers:
            where.setdefault(t, []).append(name)
    for t in all_tiers:
        got = where.get(t, [])
        if not got:
            bad.append(f'ярус {t} не гоняет ни одно задание CI')
        elif len(got) > 1:
            bad.append(f'ярус {t} гоняют два места CI: {", ".join(got)}')
    for t in where:
        if t not in all_tiers:
            bad.append(f'ярус {t} в CI, но его нет в списке run_tests.sh (ALL_TIERS)')
    bases = {t.split(':')[0] for t in all_tiers} | {'bench'}
    for f in sorted(test_files):
        m = re.match(r'test_([a-z]+)_.*\.gd$', f)
        if m and m.group(1) not in bases:
            bad.append(f'файл tests/{f} не входит ни в один ярус (ярус «{m.group(1)}» нигде не гоняется)')
    if not bench:
        bad.append('нет «run_tests.sh bench» (ярус bench гоняет задание «стенд»)')
    for job in ('test-build', 'tiers', 'windows-run'):
        if not re.search(r'(^|[\s\[,])' + re.escape(job) + r'($|[\s\],])', needs):
            bad.append(f'задание release не ждёт {job} (needs: {needs or "нет"}) — упавший ярус не остановил бы выпуск')
    return bad


def selftest(text, test_files, all_tiers):
    fails = []
    checks = 1
    base = problems(text, test_files, all_tiers)
    if base:
        fails.append(f'чистый файл не проходит: {base}')
    _, legs, _, _, _ = parse(text)
    one = legs[-1][1][-1] if legs and legs[-1][1] else all_tiers[-1]

    def spoiled(what, new_text, files, mark):
        nonlocal checks
        checks += 1
        got = problems(new_text, files, all_tiers)
        if not any(mark in b for b in got):
            fails.append(f'откат «{what}» не покраснел (ждали «{mark}»): {got}')

    # ярус выпал из ветки матрицы
    drop = re.sub(r"(tiers:\s*'[^']*?)\s*\b" + re.escape(one) + r"\b", r'\1', text, count=1)
    spoiled(f'{one} выпал из матрицы', drop, test_files, f'ярус {one} не гоняет ни одно задание CI')
    # тот же ярус и в rest, и в матрице
    dup = re.sub(r'(run_tests\.sh rest(?: [a-z_:]+)*)', r'\1 ' + one, text, count=1)
    spoiled('ярус в двух местах', dup, test_files, f'ярус {one} гоняют два места CI')
    # опечатка в имени яруса
    typo = re.sub(r"(tiers:\s*')", r"\1sim_typo ", text, count=1)
    spoiled('неизвестный ярус', typo, test_files, 'ярус sim_typo в CI, но его нет')
    # новый файл тестов с ярусом, которого нет
    spoiled('файл без яруса', text, list(test_files) + ['test_zzz_new.gd'], 'tests/test_zzz_new.gd не входит')
    # выпуск не ждёт матрицу
    rel_only = re.sub(r'^(  release:\s*\n(?:    .*\n|\s*\n)*?    needs: ).*$',
                      lambda m: m.group(1) + '[test-build, windows-run]', text, count=1, flags=re.M)
    spoiled('release не ждёт матрицу', rel_only, test_files, 'release не ждёт tiers')
    # матрица не зовёт свои ярусы (зовёт всё подряд)
    nocall = text.replace('run_tests.sh tiers ${{ matrix.tiers }}', 'run_tests.sh render')
    spoiled('матрица без своих ярусов', nocall, test_files, 'матрица не зовёт')
    for f in fails:
        print('  ' + f, file=sys.stderr)
    print(f'ci_tiers --selftest: ярусов {len(all_tiers)}, веток матрицы {len(legs)}, проверок {checks}, провалов {len(fails)}')
    return 1 if fails else 0


def main(argv):
    st = argv[:1] == ['--selftest']
    if st:
        argv = argv[1:]
    if '--' not in argv or argv.index('--') != 2:
        print(__doc__, file=sys.stderr)
        return 2
    wf, tdir = argv[0], argv[1]
    all_tiers = argv[3:]
    text = open(wf, encoding='utf-8').read()
    files = [f for f in os.listdir(tdir) if f.startswith('test_') and f.endswith('.gd')]
    if st:
        return selftest(text, files, all_tiers)
    bad = problems(text, files, all_tiers)
    for b in bad:
        print('  ' + b, file=sys.stderr)
    rest, legs, _, _, _ = parse(text)
    print(f'ci_tiers: ярусов {len(all_tiers)}; test-build: {" ".join(rest or []) or "—"}; '
          + '; '.join(f'{n}: {" ".join(t)}' for n, t in legs) + f'; бед {len(bad)}')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
