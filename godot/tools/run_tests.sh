#!/usr/bin/env bash
# Прогон всех проверок среза — здесь и в CI одинаково (архитектура, 8.2).
#   godot/tools/run_tests.sh            ярусы sim и ui, проверки данных, --selftest
#   godot/tools/run_tests.sh render     плюс ярус картинки под xvfb (G0b)
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
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROJ="$ROOT/godot"
GODOT="${GODOT:-godot}"
LOGS="${LOGS:-$(mktemp -d)}"
mkdir -p "$LOGS"
TIERS=(sim ui)
if [[ "${1:-}" == "render" ]]; then TIERS+=(render); fi
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
  local tier="$1" log="$LOGS/tier_$1.log" code
  local cmd=("$GODOT" --headless --path "$PROJ" -s res://tests/run.gd -- "$tier")
  if [[ "$tier" == "render" ]]; then
    cmd=(xvfb-run -a -s "-screen 0 1920x1080x24" "$GODOT" --path "$PROJ" -s res://tests/run.gd -- render)
  fi
  say "── ярус $tier"
  timeout 600 "${cmd[@]}" >"$log" 2>&1
  code=$?
  grep -e '^test_' -e '^RESULT' -e "^$tier:" "$log"
  if [[ $code -eq 124 ]]; then fail "ярус $tier: завис (timeout)"; show_tail "$log"; return; fi
  local result
  result="$(grep -E '^RESULT checks=[0-9]+ fails=[0-9]+$' "$log" | tail -1)"
  if [[ -z "$result" ]]; then fail "ярус $tier: нет строки RESULT (код $code)"; show_tail "$log"; return; fi
  if grep -q 'SCRIPT ERROR' "$log"; then fail "ярус $tier: SCRIPT ERROR"; grep -A3 'SCRIPT ERROR' "$log" | head -30 >&2; fi
  if [[ "$result" != *" fails=0" || "$result" == "RESULT checks=0 "* ]]; then fail "ярус $tier: $result"; grep -e 'ПРОВАЛ' "$log" | head -30 >&2; fi
  if [[ $code -ne 0 ]]; then fail "ярус $tier: код выхода $code"; fi
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

# ── данные: выгрузка не устарела, доктрина цела и её проверка краснеет на порче ──
say "── данные"
if command -v node >/dev/null; then
  (cd "$ROOT" && node godot/tools/export_data.mjs --check) || fail "export_data.mjs --check"
  (cd "$ROOT" && node godot/tools/doctrine.mjs --check >"$LOGS/doctrine.log" 2>&1) || { fail "doctrine.mjs --check"; cat "$LOGS/doctrine.log" >&2; }
  tail -1 "$LOGS/doctrine.log"
  (cd "$ROOT" && node godot/tools/doctrine.mjs --selftest >"$LOGS/doctrine_self.log" 2>&1) || { fail "doctrine.mjs --selftest"; cat "$LOGS/doctrine_self.log" >&2; }
  tail -1 "$LOGS/doctrine_self.log"
else
  fail "нет node — проверки данных не прошли"
fi

if [[ $FAILED -ne 0 ]]; then say "ИТОГ: ПРОВАЛ (журналы: $LOGS)" >&2; exit 1; fi
say "ИТОГ: всё зелёное"
