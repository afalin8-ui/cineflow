#!/usr/bin/env python3
"""Сводка стенда «ИИ против ИИ» (архитектура, 8.6; 09, 8.1–8.2; план G5, п. 4).

    python3 godot/tools/summarize.py ФАЙЛ… [--json]
    python3 godot/tools/summarize.py --selftest      проверка самой сводки (run_tests.sh)

Читает строки `BENCH {…}` (стенд tools/bench_core.gd или отчёт боя человека — та же строка
sim/report.gd) из файлов (или stdin, если файлов нет) и печатает по каждому набору (масштаб,
кланы, флажки, «без РЭБ»): медианы замеров, 10% худших и сравнение с порогами 09, 8.2.
М13 (победы) — по сочетанию кланов и роли; М12 — разница побед «с РЭБ и без», если в файлах
есть оба набора. Пороги — «первая прикидка» (8.2): не подгоняются под результат.
Выход: 0 — сводка построена (провалы порогов — в тексте, это замер, а не ошибка); 1 — нет
ни одного боя.
"""
import json
import statistics
import sys
from collections import defaultdict

SIZES = {"small": "Стычка", "mid": "Сражение", "big": "Генеральное"}
# длина боя (М11): «Стычка» 2–5 мин, «Сражение» 3–7 мин — медиана
LEN_RANGE = {"small": (120.0, 300.0), "mid": (180.0, 420.0)}


def med(a):
    a = [x for x in a if x is not None and x >= 0]
    return statistics.median(a) if a else None


def worst(a, q, low=True):
    """Значение на доле q худших: low — худшие наименьшие (М1), иначе наибольшие."""
    a = sorted(x for x in a if x is not None and x >= 0)
    if not a:
        return None
    if not low:
        a = a[::-1]
    i = min(len(a) - 1, max(0, int(q * len(a))))
    return a[i]


def read(paths):
    reps = []
    srcs = paths or ["-"]
    for p in srcs:
        f = sys.stdin if p == "-" else open(p, encoding="utf-8")
        for line in f:
            line = line.strip()
            if not line.startswith("BENCH {"):
                continue
            try:
                reps.append(json.loads(line[len("BENCH "):]))
            except json.JSONDecodeError:
                pass
        if f is not sys.stdin:
            f.close()
    return reps


def key_of(r):
    return (r.get("size", ""), r.get("attacker", ""), r.get("defender", ""),
            ",".join(sorted(r.get("flags", []))), ",".join(str(int(x)) for x in r.get("no_ecm", [])))


def fmt(v, nd=3):
    if v is None:
        return "—"
    if isinstance(v, float):
        return f"{v:.{nd}f}".rstrip("0").rstrip(".") if nd else f"{v:.0f}"
    return str(v)


def checks(rs):
    """→ список (замер, значение, порог, прошёл?)."""
    out = []
    def add(name, val, cond, rule):
        out.append((name, val, rule, None if val is None or cond is None else cond(val)))
    col = lambda k: [r.get(k) for r in rs]
    add("М1 тяжёлые в поясе, медиана", med(col("m1")), lambda v: v >= 0.65, "≥ 0,65")
    add("М1 у 10% худших", worst(col("m1"), 0.1, True), lambda v: v >= 0.5, "≥ 0,5")
    add("М2 вплотную, медиана", med(col("m2")), lambda v: v <= 0.15, "≤ 0,15")
    add("М2 эпизод, медиана", med(col("m2_ep_med")), lambda v: v <= 10.0, "≤ 10 с")
    add("М3 L/R_line, медиана", med(col("m3_med_k")), lambda v: 0.7 <= v <= 1.0, "в [0,7; 1,0]")
    p5k = [(r.get("m3_p5", -1) / r["r_line"]) if r.get("r_line", -1) > 0 and r.get("m3_p5", -1) >= 0 else None for r in rs]
    add("М3 5% худших / R_line, медиана", med(p5k), lambda v: v >= 0.5, "≥ 0,5")
    add("М3 шагов L < 360, сумма", float(sum(r.get("m3_short", 0) for r in rs)), lambda v: v == 0, "0")
    add("М4 лёгкие между линиями, медиана", med(col("m4")), lambda v: v >= 0.70, "≥ 0,70")
    add("М4 за своими тяжёлыми, медиана", med(col("m4_back")), lambda v: v <= 0.10, "≤ 0,10")
    m5 = [x for r in rs for x in r.get("m5", []) if x is not None and x >= 0]
    add("М5 авиация в середине, медиана", med(m5), lambda v: v >= 0.60, "≥ 0,60")
    add("М6 в отходе, медиана", med(col("m6")), lambda v: v <= 0.15, "≤ 0,15")
    add("М6 эпизод, медиана", med(col("m6_ep_med")), lambda v: v <= 8.0, "≤ 8 с")
    add("М6 линия назад, медиана", med(col("m6_back")), lambda v: v <= 400.0, "≤ 400")
    add("М6 за рубежом и у края, сумма", float(sum(r.get("m6_rear", 0) + r.get("m6_edge", 0) for r in rs)), lambda v: v == 0, "0")
    shares = defaultdict(list)
    sec_lt_main = 0
    n7 = 0
    for r in rs:
        for s in r.get("m7", []):
            if not s:
                continue
            n7 += 1
            for k in ("main", "sec", "light", "air"):
                shares[k].append(s.get(k, 0.0))
            if s.get("sec", 0.0) < s.get("main", 0.0):
                sec_lt_main += 1
    add("М7 главный калибр, медиана", med(shares["main"]), lambda v: 0.35 <= v <= 0.60, "35–60%")
    add("М7 батарея, медиана", med(shares["sec"]), lambda v: 0.05 <= v <= 0.15, "5–15%")
    add("М7 лёгкие, медиана", med(shares["light"]), lambda v: 0.15 <= v <= 0.35, "15–35%")
    add("М7 авиация, медиана", med(shares["air"]), lambda v: 0.10 <= v <= 0.30, "10–30%")
    add("М7 батарея меньше главного, доля сторон", (sec_lt_main / n7) if n7 else None, lambda v: v >= 1.0, "в каждом бою")
    per = [m.get("per_squad") for r in rs for m in r.get("m8", []) if m.get("up", 0) > 0]
    lost = [m.get("lost_share") for r in rs for m in r.get("m8", []) if m.get("up", 0) > 0]
    add("М8 урон по кораблям на звено, медиана", med(per), lambda v: v >= 300.0, "≥ 300")
    add("М8 доля сбитых звеньев, медиана", med(lost), lambda v: v <= 0.70, "≤ 0,70")
    add("М9 входы «свой в чужом», медиана", med(col("m9_entries")), lambda v: v <= 10.0, "≤ 10")
    add("М9 шагов с парой тяжёлых ближе 360, сумма", float(sum(r.get("m9_heavy", 0) for r in rs)), lambda v: v == 0, "0")
    add("М10 тяжёлые до места, медиана", med(col("m10_heavy")), lambda v: v <= 150.0, "≤ 150")
    add("М10 корветы до места, медиана", med(col("m10_corvette")), lambda v: v <= 260.0, "≤ 260")
    add("М10 фрегаты до места, медиана", med(col("m10_frigate")), lambda v: v <= 120.0, "≤ 120")
    fh = [r.get("first_hit", 0) for r in rs if r.get("first_hit", 0) > 0]
    add("М11 первое попадание, медиана", med(fh), lambda v: v <= 60.0, "≤ 60 с")
    add("М11 первое попадание, худшее", max(fh) if fh else None, lambda v: v <= 180.0, "≤ 180 с у 100%")
    add("М11 первый главный калибр, медиана", med([r.get("first_gun", 0) for r in rs if r.get("first_gun", 0) > 0]), lambda v: v <= 90.0, "≤ 90 с")
    add("М11 промежуток без урона, медиана", med(col("m11_gap")), lambda v: v <= 30.0, "≤ 30 с")
    gaps = [r.get("m11_gap", 0) for r in rs]
    add("М11 промежуток без урона, наибольший", max(gaps) if gaps else None, lambda v: v <= 60.0, "≤ 60 с")
    lr = LEN_RANGE.get(rs[0].get("size", ""))
    if lr:
        add("М11 длина боя, медиана (с)", med(col("len")), lambda v, lr=lr: lr[0] <= v <= lr[1], f"{lr[0]:.0f}–{lr[1]:.0f} с")
    add("М12 под чужими помехами, медиана", med(col("m12_jam")), lambda v: v <= 0.30, "≤ 0,30")
    # М16 «суета» тяжёлых (пакет GТ): порога в 09, 8.2 нет — меряется против прежней сборки на тех же
    # зёрнах (было — стало), поэтому строка без «ок/НЕТ»
    add("М16 путь тяжёлого за минуту после выхода на дистанцию, медиана", med(col("m16_path")), None, "— (было — стало)")
    add("М16 развороты хода на тяжёлый-минуту, медиана", med(col("m16_flips")), None, "— (было — стало)")
    add("М16 «тронулся с места» на тяжёлый-минуту, медиана", med(col("m16_starts")), None, "— (было — стало)")
    add("М16 доля времени в движении, медиана", med(col("m16_move")), None, "— (было — стало)")
    sm = [r.get("step_ms", {}) for r in rs]
    add("шаг модели p50, медиана (мс)", med([s.get("p50") for s in sm]), lambda v: v <= 2.0, "≤ 2 мс (пока предупреждение)")
    add("шаг модели p99, медиана (мс)", med([s.get("p99") for s in sm]), lambda v: True, "—")
    add("шаг модели худший, наибольший (мс)", max([s.get("worst", 0) for s in sm]) if sm else None, lambda v: True, "—")
    return out


def wins(rs):
    w = [0, 0, 0]
    for r in rs:
        w[r.get("winner", -1) + 1] += 1
    return {"att": w[1], "def": w[2], "draw": w[0], "n": len(rs)}


def main(argv):
    as_json = "--json" in argv
    paths = [a for a in argv if not a.startswith("--")]
    reps = read(paths)
    if not reps:
        print("СВОДКА: боёв нет")
        return 1
    groups = defaultdict(list)
    for r in reps:
        groups[key_of(r)].append(r)
    out = []
    for k, rs in sorted(groups.items()):
        size, att, dfn, flags, no_ecm = k
        w = wins(rs)
        res = {"size": size, "attacker": att, "defender": dfn, "flags": flags, "no_ecm": no_ecm, "wins": w,
               "checks": [(n, v, rule, ok) for n, v, rule, ok in checks(rs)]}
        out.append(res)
    if as_json:
        print(json.dumps(out, ensure_ascii=False))
        return 0
    for res in out:
        head = f"«{SIZES.get(res['size'], res['size'])}» {res['attacker']} (атакующий) × {res['defender']}"
        if res["flags"]:
            head += f" · флажки {res['flags']}"
        if res["no_ecm"]:
            head += f" · без РЭБ у стороны {res['no_ecm']}"
        w = res["wins"]
        print(f"\n== {head}: боёв {w['n']} · победы атакующего {w['att']}, защитника {w['def']}, ничьих {w['draw']}")
        for n, v, rule, ok in res["checks"]:
            mark = "  " if ok is None else ("ок" if ok else "НЕТ")
            print(f"  {mark}  {n}: {fmt(v)}  (порог {rule})")
    # М13: зеркало и роли — победы атакующего по сочетанию кланов (без флажков и без «без РЭБ»)
    print("\n== М13 (40–60 из 100 у каждого клана в каждой роли; зеркало — 40–60):")
    pair = defaultdict(lambda: [0, 0, 0])
    for r in reps:
        if r.get("flags") or r.get("no_ecm"):
            continue
        p = pair[(r.get("size"), r.get("attacker"), r.get("defender"))]
        p[0] += 1
        if r.get("winner") == 0:
            p[1] += 1
        elif r.get("winner") == 1:
            p[2] += 1
    for (size, att, dfn), (n, wa, wd) in sorted(pair.items()):
        share = 100.0 * wa / n if n else 0
        ok = 40.0 <= share <= 60.0
        print(f"  {'ок' if ok else 'НЕТ'}  «{SIZES.get(size, size)}» {att} × {dfn}: атакующий {wa} из {n} ({share:.0f}%), защитник {wd}")
    # М12: разница побед с РЭБ и без (у той же пары)
    base = {}
    for r in reps:
        if r.get("flags"):
            continue
        k = (r.get("size"), r.get("attacker"), r.get("defender"), ",".join(str(int(x)) for x in r.get("no_ecm", [])))
        base.setdefault(k, [0, 0])
        base[k][0] += 1
        base[k][1] += 1 if r.get("winner") == 0 else 0
    printed = False
    for (size, att, dfn, ne), (n, wa) in sorted(base.items()):
        if ne == "":
            continue
        ref = base.get((size, att, dfn, ""))
        if not ref or not n or not ref[0]:
            continue
        if not printed:
            print("\n== М12 (победы атакующего с РЭБ и без, не больше 15 из 100):")
            printed = True
        d = abs(100.0 * wa / n - 100.0 * ref[1] / ref[0])
        side = "атакующего" if ne == "0" else "защитника"
        print(f"  {'ок' if d <= 15 else 'НЕТ'}  «{SIZES.get(size, size)}» {att} × {dfn}, без РЭБ у {side}: {wa} из {n} против {ref[1]} из {ref[0]} — разница {d:.0f} из 100")
    return 0


def selftest():
    """Проверка сводки на выдуманных отчётах (run_tests.sh): чистый набор проходит пороги, а
    каждая порча краснеет СВОИМ замером (откат обязан бить в свою проверку, godot/CLAUDE.md, 9)."""
    base = {"size": "mid", "attacker": "troyden", "defender": "plektor", "flags": [], "no_ecm": [],
            "m1": 0.9, "m2": 0.05, "m2_ep_med": 5.0, "m3_med_k": 0.9, "m3_p5": 600.0, "r_line": 780.0, "m3_short": 0,
            "m4": 0.9, "m4_back": 0.0, "m5": [0.8, 0.8], "m6": 0.05, "m6_ep_med": 5.0, "m6_back": 200.0, "m6_rear": 0,
            "m6_edge": 0, "m7": [{"main": 0.5, "sec": 0.1, "light": 0.2, "air": 0.2}] * 2,
            "m8": [{"up": 4, "per_squad": 400.0, "lost_share": 0.5}] * 2, "m9_entries": 0, "m9_heavy": 0,
            "m10_heavy": 100.0, "m10_corvette": 100.0, "m10_frigate": 50.0, "first_hit": 10.0, "first_gun": 12.0,
            "m11_gap": 10.0, "len": 240.0, "m12_jam": 0.0, "step_ms": {"p50": 1.0, "p99": 2.0, "worst": 3.0}}
    reps = [dict(base, seed=i, winner=i % 2) for i in range(10)]
    n = 0
    fails = []

    def verdict(rs):
        return {name: ok for name, _v, _r, ok in checks(rs)}

    n += 1
    clean = verdict(reps)
    red = [k for k, ok in clean.items() if ok is False]
    if red:
        fails.append("чистый набор краснеет: " + ", ".join(red))
    spoil = [("m1", 0.55, "М1 тяжёлые в поясе, медиана"), ("m2_ep_med", 30.0, "М2 эпизод, медиана"),
             ("m6_back", 900.0, "М6 линия назад, медиана"), ("m9_heavy", 5, "М9 шагов с парой тяжёлых ближе 360, сумма"),
             ("len", 60.0, "М11 длина боя, медиана (с)"), ("m12_jam", 0.6, "М12 под чужими помехами, медиана")]
    for key, val, name in spoil:
        n += 1
        got = verdict([dict(r, **{key: val}) for r in reps])
        if got.get(name) is not False:
            fails.append(f"порча {key} = {val}: «{name}» не краснеет")
        other = [k for k, ok in got.items() if ok is False and k != name]
        if other:
            fails.append(f"порча {key} краснит чужое: {', '.join(other)}")
    n += 1
    if wins(reps) != {"att": 5, "def": 5, "draw": 0, "n": 10}:
        fails.append(f"победы посчитаны неверно: {wins(reps)}")
    for f in fails:
        print("ПРОВАЛ:", f)
    print(f"RESULT checks={n} fails={len(fails)}")
    return 1 if fails else 0


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        sys.exit(selftest())
    sys.exit(main(sys.argv[1:]))
