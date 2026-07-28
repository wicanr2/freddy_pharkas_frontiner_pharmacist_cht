#!/usr/bin/env bash
# 《多情藥師酷牛仔》繁中化 Windows x86_64 打包(mingw 交叉編譯產物)。
#
#   patch → 引擎 + 中文資料,玩家自備遊戲,上 GitHub Release
#   full  → 內嵌整個 game\,雙擊即玩,只放本機 dist-all/
#
# 用法:freddy_package_windows.sh patch|full
# 前置:先跑 mingw configure+make 產出 scummvm-win/scummvm.exe
#
# .bat 自己寫 scummvm.ini 再指定 target,理由同 AppImage:本專案 CD 版遊戲檔案 md5
# 跟內建 detection_tables.h 指紋對不上,--auto-detect/--language=tw 這種命令列參數
# 在偵測階段就會抓不到 target,只能直接寫 config 指定 engineid=sci + gameid=freddypharkas。
#
# [HARD] MT-32 ROM 有版權,不放進任何包(patch 或 full 都不放)。
set -euo pipefail
MODE="${1:?用法: freddy_package_windows.sh patch|full}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

MINGW_IMG="${MINGW_IMG:-freddy-mingw:latest}"
EXE="$ROOT/scummvm-win/scummvm.exe"
[ -f "$EXE" ] || { echo "!! 找不到 $EXE(先跑 mingw build)"; exit 1; }

case "$MODE" in
  patch) STAGE="$ROOT/build/win64-patch"; DIST="$ROOT/dist";     OUT="$DIST/FreddyPharkas-CHT-patch-win64.zip" ;;
  full)  STAGE="$ROOT/build/win64-full";  DIST="$ROOT/dist-all"; OUT="$DIST/FreddyPharkas-CHT-full-win64.zip" ;;
  *) echo "MODE 只能是 patch 或 full"; exit 1 ;;
esac

mkdir -p "$DIST"; rm -rf "$STAGE"; mkdir -p "$STAGE"

echo ">> 複製 scummvm.exe + strip"
cp "$EXE" "$STAGE/scummvm.exe"
docker run --rm --name freddy-winpkg-strip -v "$STAGE:/s" "$MINGW_IMG" x86_64-w64-mingw32-strip /s/scummvm.exe

echo ">> 收集 mingw runtime DLL(SDL2.dll + libwinpthread-1.dll,其餘皆系統內建)"
docker run --rm --name freddy-winpkg-sdl2 "$MINGW_IMG" cat /usr/x86_64-w64-mingw32/bin/SDL2.dll > "$STAGE/SDL2.dll"
docker run --rm --name freddy-winpkg-pthread "$MINGW_IMG" cat /usr/x86_64-w64-mingw32/lib/libwinpthread-1.dll > "$STAGE/libwinpthread-1.dll"

if [ "$MODE" = patch ]; then
  echo ">> 放入中文化資料(patch-only,不含遊戲)"
  mkdir -p "$STAGE/scummvm-cht"
  cp "$ROOT/dist-cht/translation.tsv" "$ROOT/dist-cht/freddy_big5.fnt" \
     "$ROOT/dist-cht/freddy_big5_hi.fnt" "$STAGE/scummvm-cht/"
else
  echo ">> 放入遊戲資料(game/ 已含中文資料)"
  mkdir -p "$STAGE/game"
  cp -r "$ROOT/game/." "$STAGE/game/"
fi

# --- 啟動器 .bat(CRLF 換行,逐行 append 寫 ini——區塊重導向在部分 cmd 實作/wine 不生效)-----
if [ "$MODE" = patch ]; then
cat > "$STAGE/玩-多情藥師酷牛仔-繁中.bat" <<'BAT'
@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
set GAME=%~1
if "%GAME%"=="" (
  echo.
  echo   用法: 把你的「多情藥師酷牛仔」遊戲資料夾拖到這個 .bat 上,或
  echo         玩-多情藥師酷牛仔-繁中.bat D:\games\freddy
  echo.
  echo   遊戲夾內要有 resource.000 / resource.map / resource.aud（自備正版）。
  echo.
  pause
  exit /b 1
)
set "INI=%~dp0scummvm.ini"
> "%INI%"  echo [scummvm]
>>"%INI%"  echo.
>>"%INI%"  echo [freddypharkas]
>>"%INI%"  echo engineid=sci
>>"%INI%"  echo gameid=freddypharkas
>>"%INI%"  echo description=Freddy Pharkas CHT
>>"%INI%"  echo path=%GAME%
>>"%INI%"  echo extrapath=%~dp0scummvm-cht
>>"%INI%"  echo language=tw
>>"%INI%"  echo subtitles=true
>>"%INI%"  echo speech_mute=false
"%~dp0scummvm.exe" --config="%~dp0scummvm.ini" freddypharkas
BAT
else
cat > "$STAGE/玩-多情藥師酷牛仔-繁中.bat" <<'BAT'
@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
set "INI=%~dp0scummvm.ini"
> "%INI%"  echo [scummvm]
>>"%INI%"  echo.
>>"%INI%"  echo [freddypharkas]
>>"%INI%"  echo engineid=sci
>>"%INI%"  echo gameid=freddypharkas
>>"%INI%"  echo description=Freddy Pharkas CHT (full)
>>"%INI%"  echo path=%~dp0game
>>"%INI%"  echo extrapath=%~dp0game
>>"%INI%"  echo language=tw
>>"%INI%"  echo subtitles=true
>>"%INI%"  echo speech_mute=false
"%~dp0scummvm.exe" --config="%~dp0scummvm.ini" freddypharkas %*
BAT
fi
sed -i 's/$/\r/' "$STAGE/玩-多情藥師酷牛仔-繁中.bat"

cat > "$STAGE/讀我.txt" <<'TXT'
多情藥師酷牛仔（Freddy Pharkas: Frontier Pharmacist）繁體中文化 — Windows x86_64

怎麼玩
------
  patch 版：把你的遊戲資料夾拖到「玩-多情藥師酷牛仔-繁中.bat」上（或在命令列把路徑當參數帶進去）。
  完整版：直接雙擊「玩-多情藥師酷牛仔-繁中.bat」，遊戲已內嵌在 game\ 裡。

.bat 會自動產生一份 scummvm.ini 並指定中文 target。
不要改用 --auto-detect 或 --language=tw 這種命令列參數：本專案的 CD 版遊戲檔案
跟 ScummVM 內建的偵測指紋對不上（同尺寸、不同壓製批次的 md5），偵測階段就會抓不到，
必須直接指定 engineid=sci + gameid=freddypharkas。

MT-32 音效
------
引擎已編入 MT-32 模擬（Munt），音色遠勝 AdLib，但本包不隨附 ROM（有版權）。
自備 MT32_CONTROL.ROM 與 MT32_PCM.ROM 放進遊戲資料夾，再到音效選項選 Roland MT-32。

repo（patch-only，不含遊戲資源/ROM）：https://github.com/wicanr2/freddy_pharkas_frontiner_pharmacist_cht
TXT
sed -i 's/$/\r/' "$STAGE/讀我.txt"

rm -f "$OUT"
echo ">> zip 打包"
( cd "$STAGE" && zip -qr "$OUT" . )
echo ">> 完成: $OUT ($(du -h "$OUT" | cut -f1))"
