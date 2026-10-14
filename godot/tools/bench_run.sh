#!/usr/bin/env bash
# Стенд «ИИ против ИИ» процессами по 25 боёв (архитектура, 8.6; план G5, п. 4):
#   godot/tools/bench_run.sh ПАПКА --load battle --n 100 --seed 1000 [--swap] [флажки…]
# Делит N боёв на процессы по 25 (зерно у каждого своё), гонит их разом не больше чем по числу
# ядер, строки BENCH кладёт в ПАПКА/bench_<load>_<зерно>.log и печатает сводку
# tools/summarize.py по этим файлам. Godot — из $GODOT. Процессы — по PID.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROJ="$ROOT/godot"
GODOT="${GODOT:-godot}"
OUT="$1"; shift
mkdir -p "$OUT"
arg() { local k="$1"; shift; while [[ $# -gt 0 ]]; do [[ "$1" == "$k" ]] && { echo "$2"; return; }; shift; done; echo "$DEF"; }
DEF=battle; LOAD="$(arg --load "$@")"
DEF=100; N="$(arg --n "$@")"
DEF=1000; SEED="$(arg --seed "$@")"
# остальное — как есть (без --load/--n/--seed)
REST=()
skip=0
for a in "$@"; do
  if [[ $skip -eq 1 ]]; then skip=0; continue; fi
  case "$a" in --load|--n|--seed) skip=1 ;; *) REST+=("$a") ;; esac
done
JOBS="${JOBS:-$(nproc)}"
# по 25 на процесс (архитектура, 8.6); меньше сотни — поровну на ядра, чтобы не ждать одного
PER=$(( (N + JOBS - 1) / JOBS )); [[ $PER -gt 25 ]] && PER=25; [[ $PER -lt 1 ]] && PER=1
pids=()
files=()
i=0
tag="$(echo "${REST[*]:-}" | tr -c 'a-zA-Z0-9_-' '_' | cut -c1-40)"
while [[ $i -lt $N ]]; do
  k=$(( N - i < PER ? N - i : PER ))
  s=$(( SEED + i ))
  f="$OUT/bench_${LOAD}_${s}${tag:+_$tag}.log"
  files+=("$f")
  timeout 3600 "$GODOT" --headless --path "$PROJ" -s res://tools/bench.gd -- --load "$LOAD" --n "$k" --seed "$s" "${REST[@]}" >"$f" 2>&1 &
  pids+=($!)
  i=$(( i + k ))
  while [[ $(jobs -rp | wc -l) -ge $JOBS ]]; do wait -n; done
done
code=0
for p in "${pids[@]}"; do wait "$p" || code=1; done
python3 "$PROJ/tools/summarize.py" "${files[@]}"
exit $code
