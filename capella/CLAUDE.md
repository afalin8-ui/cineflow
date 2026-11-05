# Капелла (папка capella/) — заметки для Claude

RTS на Godot 4.5.1, космический бой против ИИ. Спецификация — `PLAN.md`
(она одна, новых документов не плодить). С CineFlow и со старой игрой в
`game/` общего только репозиторий. Пользователь — не программист:
объяснять простыми словами.

## Устройство
- `scripts/sim/` — бой без графики: `defs.gd` (ВСЕ числа), `unit.gd`,
  `world.gd` (шаг 0,1 с, приказы `cmd_*`), `ai.gd` (ИИ отдаёт приказы теми же
  `cmd_*` и видит только своё). Экран (`scripts/view/`) только рисует и зовёт `cmd_*`
- 1 единица сцены = 10 м (`S = 0.1`). Мелочь рисуется крупнее настоящего
  (`ShipMesh.vis_len`), иначе с высоты её не видно

## Проверки (гонять перед каждой сборкой)
- Автобой «не свалка»: `godot --headless --path capella -s res://tools/autobattle.gd
  -- troyden plector hard S 1` (порядок фракций, сложность, карта, зерно).
  Около минуты на бой. Код выхода 0 — все три условия в рамке
- Управление настоящими событиями мыши (под Xvfb, рендер opengl3):
  `xvfb-run -a -s "-screen 0 1600x900x24" godot --path capella --rendering-driver
  opengl3 --rendering-method gl_compatibility --resolution 1600x900
  -s res://tools/ui_test.gd` — «ПРОВАЛОВ: 0»
- Снимок экрана для глаза: `godot … -- shot=/путь.png t=600 me=-1 dist=900`
  (см. `_autoshot` в `scripts/main.gd`)

## Сборка
- Пуш в `capella/` на ветке `capella` → GitHub Actions (`.github/workflows/capella.yml`)
  собирает `Capella.exe` и выкладывает в Releases с текстом из `BUILD_NOTES.md`.
  Перед пушем обнови `BUILD_NOTES.md`: что поменялось и что проверить руками
- Локально: `godot --headless --path capella --export-release "Windows Desktop"
  ../build/Capella.exe` (шаблоны в `~/.local/share/godot/export_templates/4.5.1.stable`)

## Грабли
- GDScript не выводит тип из выражений с нетипизированными значениями
  (`var x := t.pos - u.pos`, `:= max(...)`): пиши тип явно
- `get_meta(key, null)` ругается, если ключа нет: состояние юнита — обычными полями
- Отпускание рамки выделения ловится в `_input`, а не в `_unhandled_input`:
  иначе отпускание над панелью съедает интерфейс
- Позиции хардпоинтов на корпусе — `HP_PLACE` в `hud.gd` (доля длины от носа);
  у станции — по кругу. Щелчок по кружку ловится в `battle_view._unhandled_input`
  РАНЬШЕ начала рамки выделения
- Проверяя одиночный щелчок после двойного, жди настоящее время
  (`create_timer`), а не кадры: под Xvfb 30 кадров проходят быстрее 0,45 с.
  И бери позицию корабля заново — он успевает улететь
