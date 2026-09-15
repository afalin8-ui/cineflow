#!/bin/sh
# Сборка Пульта. Собирается кросс-компилятором mingw-w64: получается обычный
# .exe без установщика и без внешних библиотек — скачал и запустил.
set -e
CXX=${CXX:-x86_64-w64-mingw32-g++}
RC=${RC:-x86_64-w64-mingw32-windres}
OUT=${OUT:-PenBar.exe}
cd "$(dirname "$0")"

if command -v python3 >/dev/null 2>&1; then python3 make_icon.py; fi
"$RC" src/penbar.rc -o build_res.o

"$CXX" -municode -mwindows -std=c++17 -O2 -DNDEBUG \
  -finput-charset=UTF-8 -fexec-charset=UTF-8 -fwide-exec-charset=UTF-16LE \
  src/main.cpp src/panel.cpp src/settings.cpp src/config.cpp src/keys.cpp src/util.cpp build_res.o \
  -o "$OUT" \
  -lgdiplus -lcomctl32 -lshlwapi -lshell32 -lole32 -luuid -luser32 -lgdi32 -ladvapi32 \
  -static -static-libgcc -static-libstdc++ -Wl,--gc-sections -ffunction-sections -fdata-sections
"${CXX%g++}strip" "$OUT" 2>/dev/null || true
rm -f build_res.o
ls -la "$OUT"
