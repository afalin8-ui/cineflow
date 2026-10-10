#!/usr/bin/env bash
# Номер выпуска для задания release (архитектура, 9.2; godot/CLAUDE.md, 13).
#   godot/tools/release_tag.sh godot/RELEASE >> "$GITHUB_OUTPUT"
# Вход — переменные GitHub: GITHUB_EVENT_NAME, GITHUB_REF_TYPE, GITHUB_REF_NAME
# и INPUT_RELEASE (поле «release» у кнопки); первым аргументом — файл godot/RELEASE.
# Выход — строка «tag=capella-vX.Y» в stdout, если выпуск нужен; пояснение — в stderr.
#   метка capella-v*              → её номер
#   кнопка, поле release заполнено → номер из поля
#   кнопка, поле ПУСТОЕ            → выпуска нет: «только тесты». НЕ номер из RELEASE:
#                                    иначе «просто прогнать тесты» кнопкой после упавшего
#                                    пуша с новым номером завело бы черновик (замечание G0a)
#   пуш в ветку                    → первая строка godot/RELEASE (новый ли он — решает
#                                    задание release: черновики видны только с правом записи)
#   номер не вида capella-vX.Y     → выпуска нет
# Проверяется в tools/run_tests.sh («── номер выпуска»), каждый случай.
set -euo pipefail
release_file="${1:-godot/RELEASE}"
event="${GITHUB_EVENT_NAME:-push}"
if [[ "${GITHUB_REF_TYPE:-branch}" == "tag" ]]; then
  tag="${GITHUB_REF_NAME:-}"; why="метка"
elif [[ "$event" == "workflow_dispatch" ]]; then
  if [[ -z "${INPUT_RELEASE:-}" ]]; then
    echo "кнопка без номера — только тесты, выпуска нет" >&2; exit 0
  fi
  tag="$INPUT_RELEASE"; why="кнопка"
else
  tag="$(head -n1 "$release_file" | tr -d '\r[:space:]')"; why="godot/RELEASE"
fi
if ! [[ "$tag" =~ ^capella-v[0-9]+(\.[0-9]+)+$ ]]; then
  echo "номер «$tag» ($why) не вида capella-vX.Y — выпуска нет" >&2; exit 0
fi
echo "tag=$tag"
echo "номер выпуска $tag ($why); новый ли он — решит задание release" >&2
