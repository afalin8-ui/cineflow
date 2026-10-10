#!/usr/bin/env bash
# Есть ли уже выпуск (и черновик) с этим номером — для задания release
# (godot/CLAUDE.md, 13). Печатает «yes» или «no»; отказ gh — ненулевой код
# (задание падает), а НЕ «no» (задание завело бы черновик):
#   state=$(godot/tools/release_exists.sh "$TAG")
# Нужны GH_TOKEN с правом записи (черновики видны только с ним) и GITHUB_REPOSITORY.
#
# Список берётся в переменную ЦЕЛИКОМ, и только потом ищется номер. Конвейер
# «gh … | grep -qx» под pipefail — ловушка (замечание к доработке G0a): grep -q
# уходит на первом совпадении, gh на следующей строке получает SIGPIPE, конвейер
# отдаёт 141 — «не нашёл», и задание заводило ВТОРОЙ черновик с тем же номером.
# Там же отказ API читался как «выпуска нет». Проверяется в tools/run_tests.sh
# («── есть ли выпуск»): заглушка gh и откат на прежнюю конструкцию.
set -euo pipefail
tag="${1:?номер выпуска}"
repo="${GITHUB_REPOSITORY:?нет GITHUB_REPOSITORY}"
tags="$(gh release list --repo "$repo" --limit 200 --json tagName --jq '.[].tagName')"
if grep -qxF -- "$tag" <<<"$tags"; then echo yes; else echo no; fi
