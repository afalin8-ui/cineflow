#!/usr/bin/env bash
# Выпуск для задания release (godot/CLAUDE.md, 13) — ЧЕРНОВИКОМ по умолчанию.
#   PUBLISH=false godot/tools/release_publish.sh capella-vX.Y <папка с архивами>
# Черновик видит только владелец репозитория; опубликованный — все. Согласия
# пользователя на публичные выпуски в ЕГО СОБСТВЕННЫХ словах пока нет, поэтому
# опубликовать можно только нарочно: PUBLISH=true (галочка publish у кнопки) или
# кнопкой «Publish release» на странице черновика.
#   нет выпуска       → черновик с двумя архивами (--target этот коммит)
#   есть черновик     → кандидат: в него — свежие архивы этого прогона, подпись
#                       и коммит; метку, если осталась (выпуск снимали с публикации),
#                       убираем — у черновика её нет, при публикации заведётся заново
#   опубликован       → не трогаем
# Потом сверка: у черновика архивы скачиваются через gh и совпадают побайтно с
# собранными; у опубликованного — скачиваются по ссылке без входа.
# Нужны GH_TOKEN с правом записи, GITHUB_REPOSITORY, GITHUB_SHA (и для подписи
# GITHUB_SERVER_URL, GITHUB_RUN_ID). Текст — godot/RELEASE ($RELEASE_FILE).
# Проверяется в tools/run_tests.sh («── выпуск черновиком») на заглушке gh.
set -euo pipefail
tag="${1:?номер выпуска}"
dl="${2:?папка с архивами}"
repo="${GITHUB_REPOSITORY:?нет GITHUB_REPOSITORY}"
sha="${GITHUB_SHA:?нет GITHUB_SHA}"
server="${GITHUB_SERVER_URL:-https://github.com}"
publish="${PUBLISH:-false}"
here="$(cd "$(dirname "$0")" && pwd)"
rel_file="${RELEASE_FILE:-$here/../RELEASE}"
files=("$dl/capella-windows.zip" "$dl/capella-linux.zip")
for f in "${files[@]}"; do [[ -s "$f" ]] || { echo "нет архива $f" >&2; exit 1; }; done

state="$("$here/release_exists.sh" "$tag")"
echo "выпуск $tag: $state"
if [[ "$state" == yes ]]; then
  echo "выпуск $tag уже опубликован — не трогаем"; exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
title="$(sed -n 2p "$rel_file")"
if [[ "$(head -n1 "$rel_file" | tr -d '\r[:space:]')" != "$tag" ]]; then title="Капелла $tag"; fi
sed -n '4,$p' "$rel_file" > "$work/notes.md"
printf '\n---\nСобрано из коммита %s, прогон %s/%s/actions/runs/%s\n' "$sha" "$server" "$repo" "${GITHUB_RUN_ID:-?}" >> "$work/notes.md"

if [[ "$state" == no ]]; then
  gh release create "$tag" "${files[@]}" --draft --target "$sha" --title "$title" --notes-file "$work/notes.md"
else
  if gh api "repos/$repo/git/ref/tags/$tag" >/dev/null 2>&1; then
    gh api -X DELETE "repos/$repo/git/refs/tags/$tag" >/dev/null
    echo "метка $tag у черновика снята (держала прежний коммит)"
  fi
  gh release upload "$tag" "${files[@]}" --clobber
  gh release edit "$tag" --target "$sha" --title "$title" --notes-file "$work/notes.md" >/dev/null
fi
if [[ "$publish" == true ]]; then
  gh release edit "$tag" --draft=false >/dev/null
  echo "выпуск $tag опубликован (PUBLISH=true)"
fi

draft="$(gh release view "$tag" --json isDraft --jq .isDraft)"
if [[ "$publish" == true ]]; then
  [[ "$draft" == false ]] || { echo "выпуск $tag остался черновиком" >&2; exit 1; }
  for f in "${files[@]}"; do
    name="$(basename "$f")"
    url="$server/$repo/releases/download/$tag/$name"
    code="$(curl -sS -o /dev/null -w '%{http_code}' -L -r 0-1023 "$url")"
    echo "$name: $code ($url)"
    case "$code" in 200|206) ;; *) echo "$name не скачивается без входа: $code" >&2; exit 1 ;; esac
  done
else
  [[ "$draft" == true ]] || { echo "выпуск $tag не черновик, а публиковать не просили" >&2; exit 1; }
  mkdir -p "$work/got"
  gh release download "$tag" -p 'capella-*.zip' -D "$work/got" --clobber
  for f in "${files[@]}"; do
    name="$(basename "$f")"
    cmp -s "$f" "$work/got/$name" || { echo "$name в черновике — не тот, что собран" >&2; exit 1; }
    echo "$name: в черновике — сборка этого прогона ($(wc -c < "$f") байт)"
  done
fi
