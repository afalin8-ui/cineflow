#!/usr/bin/env bash
# Прогон всех проверок среза — здесь и в CI одинаково (архитектура, 8.2).
#   godot/tools/run_tests.sh            ярусы sim и ui, проверки данных, --selftest
#   godot/tools/run_tests.sh render     плюс ярус картинки под xvfb В ОБОИХ отрисовщиках
#                                       (Forward+ и Compatibility); снимки «Стола» —
#                                       в $LOGS/shots (смотреть глазами)
# Godot берётся из $GODOT (по умолчанию `godot` из PATH).
#
# Каждое правило обёртки проверено пробами (архитектура, 8.2):
# 1. сначала --import: без него class_name не находится;
# 2. --check-only по ВСЕМ скриптам: код 1 на ошибке разбора;
# 3. каждый прогон — под timeout: сцена со сломанным скриптом висит вечно;
# 4. от прогона требуется строка RESULT: нет её — провал;
# 5. любой SCRIPT ERROR в выводе — провал: в редакторе ошибка во время работы
#    даёт код 0;
# 6. вывод прогона — в файл, хвост — в stderr: при обрыве stdout теряется;
# 7. процессы — только по PID (никакого pkill -f: он убивает чужие прогоны).
# Плюс: главная сцена и в режиме --selftest, и С ОКНОМ (--quit-after); --overrides
# с относительным путём из чужой папки; номер выпуска по каждому случаю двери;
# «есть ли выпуск» на заглушке gh (с откатом на прежний «gh | grep -q»).
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROJ="$ROOT/godot"
GODOT="${GODOT:-godot}"
LOGS="${LOGS:-$(mktemp -d)}"
mkdir -p "$LOGS"
TIERS=(sim ui)
if [[ "${1:-}" == "render" ]]; then TIERS+=(render:forward_plus render:gl_compatibility); fi
FAILED=0

say() { printf '%s\n' "$*"; }
fail() { say "ПРОВАЛ: $*" >&2; FAILED=1; }

# вывод без шума: что Godot печатает при каждом запуске
show_tail() { grep -v -e '^Godot Engine v' -e '^\s*$' "$1" | tail -n "${2:-40}" >&2; }

# ── 1. импорт ──
say "── импорт"
if ! timeout 300 "$GODOT" --headless --path "$PROJ" --import >"$LOGS/import.log" 2>&1; then
  fail "импорт (код $?)"; show_tail "$LOGS/import.log"
fi
if grep -q -e 'SCRIPT ERROR' -e 'Parse Error' "$LOGS/import.log"; then
  fail "импорт: ошибки в скриптах"; grep -A1 -e 'SCRIPT ERROR' -e 'Parse Error' "$LOGS/import.log" | head -20 >&2
fi

# ── 2. --check-only по всем скриптам ──
say "── разбор скриптов (--check-only)"
n=0
while IFS= read -r f; do
  rel="${f#$PROJ/}"
  n=$((n + 1))
  if ! timeout 60 "$GODOT" --headless --path "$PROJ" --check-only -s "res://$rel" >"$LOGS/check.log" 2>&1; then
    fail "разбор $rel"; grep -A1 -e 'SCRIPT ERROR' -e 'Parse Error' "$LOGS/check.log" | head -12 >&2
  fi
done < <(find "$PROJ" -name '*.gd' -not -path '*/.godot/*' -not -path '*/build/*' | sort)
say "   скриптов: $n"

# ── *.gd.uid в git: Godot 4.7 заводит их сам, а ссылки по uid без них рвутся на чужой копии ──
if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  missing=$(git -C "$ROOT" ls-files 'godot/*.gd' | while read -r f; do git -C "$ROOT" ls-files --error-unmatch "$f.uid" >/dev/null 2>&1 || echo "$f"; done)
  if [[ -n "$missing" ]]; then fail "в git нет .uid у скриптов: $(echo $missing)"; fi
fi

# ── 3–5. ярусы тестов ──
run_tier() {
  local tier="$1" log="$LOGS/tier_${1/:/_}.log" code
  local cmd=("$GODOT" --headless --path "$PROJ" -s res://tests/run.gd -- "$tier")
  if [[ "$tier" == render:* ]]; then
    # картинка — с окном под xvfb, в заданном отрисовщике; снимки — в $LOGS/shots
    mkdir -p "$LOGS/shots"
    cmd=(env CAPELLA_SHOTS="$LOGS/shots" xvfb-run -a -s "-screen 0 1920x1080x24" "$GODOT" --path "$PROJ" --rendering-method "${tier#render:}" -s res://tests/run.gd -- render)
  fi
  say "── ярус $tier"
  timeout 900 "${cmd[@]}" >"$log" 2>&1
  code=$?
  grep -e '^test_' -e '^RESULT' -e "^${tier%%:*}:" -e '^    · ' "$log"
  if [[ $code -eq 124 ]]; then fail "ярус $tier: завис (timeout)"; show_tail "$log"; return; fi
  local result
  result="$(grep -E '^RESULT checks=[0-9]+ fails=[0-9]+$' "$log" | tail -1)"
  if [[ -z "$result" ]]; then fail "ярус $tier: нет строки RESULT (код $code)"; show_tail "$log"; return; fi
  if grep -q 'SCRIPT ERROR' "$log"; then fail "ярус $tier: SCRIPT ERROR"; grep -A3 'SCRIPT ERROR' "$log" | head -30 >&2; fi
  if [[ "$result" != *" fails=0" || "$result" == "RESULT checks=0 "* ]]; then fail "ярус $tier: $result"; grep -e 'ПРОВАЛ' "$log" | head -30 >&2; fi
  if [[ $code -ne 0 ]]; then fail "ярус $tier: код выхода $code"; fi
  # откат на другой отрисовщик молчалив (fallback_to_opengl3): проверяем, ЧТО поднялось
  case "$tier" in
    render:forward_plus) grep -q -- '- Forward+ - Using Device' "$log" || fail "ярус $tier: поднялся не Forward+ (Vulkan не нашёлся?)" ;;
    render:gl_compatibility) grep -q -- '- Compatibility - Using Device' "$log" || fail "ярус $tier: поднялся не Compatibility" ;;
  esac
}
for t in "${TIERS[@]}"; do run_tier "$t"; done

# ── главная сцена сама: режим --selftest (тот же, что запускает выгруженные сборки) ──
say "── главная сцена -- --selftest"
timeout 120 "$GODOT" --headless --path "$PROJ" -- --selftest >"$LOGS/selftest.log" 2>&1
code=$?
grep -m1 '^SELFTEST' "$LOGS/selftest.log"
if [[ $code -ne 0 ]] || ! grep -q '^SELFTEST ok' "$LOGS/selftest.log" || grep -q 'SCRIPT ERROR' "$LOGS/selftest.log"; then
  fail "--selftest (код $code)"; show_tail "$LOGS/selftest.log"
fi

# ── главная сцена С ОКНОМ: тот путь, что увидит игрок (--selftest выходит раньше вида) ──
say "── главная сцена с окном (--quit-after 60)"
timeout 120 "$GODOT" --headless --path "$PROJ" --quit-after 60 >"$LOGS/window.log" 2>&1
code=$?
grep -m1 '^Капелла: отрисовщик' "$LOGS/window.log"
if [[ $code -ne 0 ]] || ! grep -q '^Капелла: отрисовщик' "$LOGS/window.log" || grep -q 'SCRIPT ERROR' "$LOGS/window.log"; then
  fail "окно (код $code)"; show_tail "$LOGS/window.log"
fi

# ── минута замера кадров из командной строки (G0b, п. 7): короткая, итог в выводе, файл ──
say "── главная сцена -- --bench-render (2 с)"
bout="$(mktemp -d)"
timeout 180 "$GODOT" --headless --path "$PROJ" -- --bench-render --bench-seconds=2 --bench-out="$bout" >"$LOGS/bench.log" 2>&1
code=$?
grep -m3 '^BENCH' "$LOGS/bench.log"
csv="$(ls "$bout"/capella_frames_*.csv 2>/dev/null | head -1)"
if [[ $code -ne 0 ]] || ! grep -q '^BENCH Кадров: ' "$LOGS/bench.log" || ! grep -q '^BENCH Вызовов отрисовки' "$LOGS/bench.log" \
   || grep -q 'SCRIPT ERROR' "$LOGS/bench.log" || [[ -z "$csv" ]] || [[ "$(grep -c '^[0-9]' "$csv")" -lt 10 ]]; then
  fail "--bench-render (код $code, файл «$csv»)"; show_tail "$LOGS/bench.log"
fi
rm -rf "$bout"

# ── --overrides с ОТНОСИТЕЛЬНЫМ путём — из чужой папки, как запустит человек ──
# (архитектура, 7: «--overrides=tune.json»). Godot с --path уходит в папку проекта,
# и без launch_dirs «tune.json» искался бы там. Выгруженные сборки — то же в CI.
say "── --overrides=tune.json из папки запуска"
rel="$(mktemp -d)"
printf '{"main.dead_k": 0.43}\n' >"$rel/tune.json"
godot_bin="$(command -v "$GODOT" || echo "$GODOT")"
(cd "$rel" && timeout 120 "$godot_bin" --headless --path "$PROJ" -- --selftest --overrides=tune.json) >"$LOGS/selftest_rel.log" 2>&1
code=$?
grep -m1 '^SELFTEST' "$LOGS/selftest_rel.log"
if [[ $code -ne 0 ]] || ! grep -q '^SELFTEST ok: .*правок 1,' "$LOGS/selftest_rel.log"; then
  fail "--overrides с относительным путём (код $code)"; show_tail "$LOGS/selftest_rel.log"
fi
rm -rf "$rel"

# ── номер выпуска (tools/release_tag.sh): каждый случай двери выпуска ──
say "── номер выпуска"
relf="$(mktemp)"
tag_case() {  # tag_case <ждём> <событие> <тип ref> <имя ref> <поле release> <первая строка RELEASE>
  local want="$1" got
  printf '%s\nзаголовок\n---\n' "$6" >"$relf"
  got="$(GITHUB_EVENT_NAME="$2" GITHUB_REF_TYPE="$3" GITHUB_REF_NAME="$4" INPUT_RELEASE="$5" \
    "$PROJ/tools/release_tag.sh" "$relf" 2>/dev/null | sed -n 's/^tag=//p')"
  if [[ "$got" != "$want" ]]; then fail "номер выпуска: $2 $3 «$5» RELEASE «$6» — получили «$got», ждали «$want»"; fi
}
tag_case capella-v0.2 push branch claude/capella-godot "" capella-v0.2
tag_case ""           push branch claude/capella-godot "" v0.2
tag_case capella-v0.4 push tag capella-v0.4 "" capella-v0.2
tag_case capella-v0.3 workflow_dispatch branch claude/capella-godot capella-v0.3 capella-v0.2
tag_case ""           workflow_dispatch branch claude/capella-godot "" capella-v0.2
tag_case ""           workflow_dispatch branch claude/capella-godot "0.3" capella-v0.2
rm -f "$relf"
say "   случаев: 6"

# ── есть ли выпуск (tools/release_exists.sh): заглушка gh вместо GitHub ──
# Номер стоит ПЕРВЫМ, за ним ещё строки (настоящий gh пишет строка за строкой). Хвост —
# больше буфера канала (~750 КБ): прежний «gh | grep -q» обязан получить SIGPIPE
# при любой скорости машины, а не «если успеет» — паузой это было бы гонкой.
say "── есть ли выпуск"
ghstub="$(mktemp -d)"
cat >"$ghstub/gh" <<'EOF'
#!/usr/bin/env bash
case "${GH_STUB:-}" in
  first) echo capella-v0.1; seq -f 'capella-v9.%g' 1 50000 ;;
  empty) ;;
  fail) echo "HTTP 502: Bad Gateway" >&2; exit 1 ;;
esac
EOF
chmod +x "$ghstub/gh"
exists_case() {  # exists_case <скрипт> <режим заглушки> <номер> → yes / no / ERR (отказ)
  local out
  out="$(PATH="$ghstub:$PATH" GH_STUB="$2" GITHUB_REPOSITORY=afalin8-ui/cineflow bash "$1" "$3" 2>/dev/null)" || out=ERR
  printf '%s' "$out"
}
exists_ok() {  # все случаи верны → 0; первый неверный печатается
  local s="$1" c got want
  for c in "first capella-v0.1 yes" "first capella-v9.50000 yes" "first capella-v0.2 no" \
           "empty capella-v0.1 no" "fail capella-v0.1 ERR"; do
    set -- $c
    got="$(exists_case "$s" "$1" "$2")"; want="$3"
    if [[ "$got" != "$want" ]]; then echo "заглушка $1, номер $2: получили «$got», ждали «$want»"; return 1; fi
  done
}
if ! why="$(exists_ok "$PROJ/tools/release_exists.sh")"; then fail "release_exists.sh: $why"; fi
# откат: прежняя конструкция из задания release обязана краснеть
cat >"$ghstub/old.sh" <<'EOF'
set -euo pipefail
if gh release list --repo "$GITHUB_REPOSITORY" --limit 200 --json tagName --jq '.[].tagName' | grep -qx "$1"; then echo yes; else echo no; fi
EOF
if why="$(exists_ok "$ghstub/old.sh")"; then fail "откат: «gh | grep -q» прошёл проверку — проверка ничего не ловит"; else say "   откат «gh | grep -q» краснеет: $why"; fi
rm -rf "$ghstub"

# ── данные: выгрузка не устарела, доктрина цела и её проверка краснеет на порче ──
say "── данные"
if command -v node >/dev/null; then
  (cd "$ROOT" && node godot/tools/export_data.mjs --check) || fail "export_data.mjs --check"
  (cd "$ROOT" && node godot/tools/doctrine.mjs --check >"$LOGS/doctrine.log" 2>&1) || { fail "doctrine.mjs --check"; cat "$LOGS/doctrine.log" >&2; }
  tail -1 "$LOGS/doctrine.log"
  (cd "$ROOT" && node godot/tools/doctrine.mjs --selftest >"$LOGS/doctrine_self.log" 2>&1) || { fail "doctrine.mjs --selftest"; cat "$LOGS/doctrine_self.log" >&2; }
  tail -1 "$LOGS/doctrine_self.log"
  # модели кораблей: файлы на месте, узлы закрывают doctrine.json → nodes, длины, исходники
  # не менялись (сама выгрузка — с браузером, здесь только проверка и её откаты)
  (cd "$ROOT" && node godot/tools/export_ships.mjs --check >"$LOGS/ships.log" 2>&1) || { fail "export_ships.mjs --check"; cat "$LOGS/ships.log" >&2; }
  tail -1 "$LOGS/ships.log"
  (cd "$ROOT" && node godot/tools/export_ships.mjs --selftest >"$LOGS/ships_self.log" 2>&1) || { fail "export_ships.mjs --selftest"; cat "$LOGS/ships_self.log" >&2; }
  tail -1 "$LOGS/ships_self.log"
else
  fail "нет node — проверки данных не прошли"
fi

if [[ $FAILED -ne 0 ]]; then say "ИТОГ: ПРОВАЛ (журналы: $LOGS)" >&2; exit 1; fi
say "ИТОГ: всё зелёное"
