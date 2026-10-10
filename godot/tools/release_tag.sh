#!/usr/bin/env bash
# Номер выпуска для задания release (архитектура, 9.2; godot/CLAUDE.md, 13).
#   godot/tools/release_tag.sh godot/RELEASE >> "$GITHUB_OUTPUT"
# Вход — переменные GitHub: GITHUB_EVENT_NAME, GITHUB_REF_TYPE, GITHUB_REF_NAME
# и INPUT_RELEASE (поле «release» у кнопки); первым аргументом — файл godot/RELEASE.
# Выход — строки «tag=capella-vX.Y» и «publish=true|false» в stdout, если выпуск
# нужен; пояснение — в stderr. publish — публиковать ли (иначе черновик):
#   метка capella-v*              → её номер; публикуется (метку ставит только владелец)
#   кнопка, поле release заполнено → номер из поля; публикуется, только если отмечена
#                                    галочка publish (INPUT_PUBLISH=true)
#   кнопка, поле ПУСТОЕ            → выпуска нет: «только тесты». НЕ номер из RELEASE:
#                                    иначе «просто прогнать тесты» кнопкой после упавшего
#                                    пуша с новым номером завело бы черновик (замечание G0a)
#   пуш в ветку                    → первая строка godot/RELEASE (новый ли он — решает
#                                    задание release: черновики видны только с правом записи);
#                                    публикует ТОЛЬКО пуш в саму claude/capella-godot, а пробная
#                                    claude/capella-godot-* — черновик (хвост G0: пробная ветка
#                                    не должна выложить сборку для всех)
#   номер не вида capella-vX.Y     → выпуска нет
# Проверяется в tools/run_tests.sh («── номер выпуска»), каждый случай.
set -euo pipefail
release_file="${1:-godot/RELEASE}"
event="${GITHUB_EVENT_NAME:-push}"
main_branch="claude/capella-godot"
if [[ "${GITHUB_REF_TYPE:-branch}" == "tag" ]]; then
  tag="${GITHUB_REF_NAME:-}"; why="метка"; publish=true
elif [[ "$event" == "workflow_dispatch" ]]; then
  if [[ -z "${INPUT_RELEASE:-}" ]]; then
    echo "кнопка без номера — только тесты, выпуска нет" >&2; exit 0
  fi
  tag="$INPUT_RELEASE"; why="кнопка"
  publish=false; [[ "${INPUT_PUBLISH:-false}" == true ]] && publish=true
else
  tag="$(head -n1 "$release_file" | tr -d '\r[:space:]')"; why="godot/RELEASE"
  publish=false; [[ "${GITHUB_REF_NAME:-}" == "$main_branch" ]] && publish=true
fi
if ! [[ "$tag" =~ ^capella-v[0-9]+(\.[0-9]+)+$ ]]; then
  echo "номер «$tag» ($why) не вида capella-vX.Y — выпуска нет" >&2; exit 0
fi
echo "tag=$tag"
echo "publish=$publish"
echo "номер выпуска $tag ($why), $([[ $publish == true ]] && echo "публикуется" || echo "черновиком"); новый ли он — решит задание release" >&2
