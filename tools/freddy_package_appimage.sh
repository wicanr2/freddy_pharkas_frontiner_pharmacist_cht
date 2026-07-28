#!/usr/bin/env bash
# 《多情藥師酷牛仔》繁中化 AppImage 打包(Linux x86_64)。
#
#   patch  → 只有引擎 + 中文資料,玩家自備遊戲,上 GitHub Release
#   full   → 內嵌整個 game/,雙擊即玩,只放本機 dist-all/(不上傳)
#
# 用法:freddy_package_appimage.sh patch|full
#
# 為什麼啟動器要自己寫 config 而不是用 --auto-detect / --language=tw:
#   SCI 的中文開關讀的是 **target 設定** 裡的 language=tw,不吃命令列的 --language。
#   直接寫一份帶 engineid/gameid/language=tw 的 ini 再指定 target,是最不會出錯的做法
#   (實測 ScummVM 認得這份 CD 版、偵測本身沒問題,寫 ini 只是省掉偵測與設定這兩步)。
#   跟 cap.sh/cap_rooms.sh 驗證過的做法一致:直接寫一份帶 engineid=sci、gameid=freddypharkas、
#   language=tw 的 scummvm.ini,再指定 target 啟動,繞過完整偵測。
#
# [HARD] MT-32 ROM 有版權:**patch 版一律不放**(要上公開 Release)。
# full 版只留在本機 dist-all/(gitignore、不散布),依專案規則可附 ROM,
# 沒有 ROM 時 stage_mt32_rom() 會自己略過並退回預設音效驅動。
set -euo pipefail
MODE="${1:?用法: freddy_package_appimage.sh patch|full}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

BUILD_IMG="${BUILD_IMG:-freddy-build:latest}"

case "$MODE" in
  patch) STAGE="$ROOT/build/appimg-patch"; DIST="$ROOT/dist"
         OUT="$DIST/FreddyPharkas-CHT-patch-x86_64.AppImage" ;;
  full)  STAGE="$ROOT/build/appimg-full";  DIST="$ROOT/dist-all"
         OUT="$DIST/FreddyPharkas-CHT-full-x86_64.AppImage" ;;
  *) echo "MODE 只能是 patch 或 full"; exit 1 ;;
esac
APPDIR="$STAGE/AppDir"

mkdir -p "$DIST"
rm -rf "$APPDIR"; mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/lib"

echo ">> 複製 scummvm + strip"
cp "$ROOT/scummvm-src/scummvm" "$APPDIR/usr/bin/scummvm"
docker run --rm --name freddy-pkg-strip -v "$APPDIR/usr/bin:/b" "$BUILD_IMG" strip /b/scummvm 2>/dev/null || true

echo ">> 收集共享庫(freddy-build 內 ldd,排除 glibc 核心)"
docker run --rm --name freddy-pkg-libs \
  -v "$APPDIR/usr/bin/scummvm:/collect/bin:ro" \
  -v "$APPDIR/usr/lib:/collect/out" \
  -v "$ROOT/tools/pkg_collect_libs.py:/collect/collect.py:ro" \
  -w /collect "$BUILD_IMG" python3 collect.py bin out
echo "   $(ls "$APPDIR/usr/lib" | wc -l) 個 .so"

if [ "$MODE" = patch ]; then
  echo ">> 放入中文資料(patch-only,不含遊戲)"
  mkdir -p "$APPDIR/usr/share/scummvm-cht"
  cp "$ROOT/dist-cht/translation.tsv" "$ROOT/dist-cht/freddy_big5.fnt" \
     "$ROOT/dist-cht/freddy_big5_hi.fnt" "$APPDIR/usr/share/scummvm-cht/"
else
  echo ">> 放入遊戲資料(game/ 已含中文資料)"
  # shellcheck source=/dev/null
  . "$ROOT/tools/pkg_common.sh"
  mkdir -p "$APPDIR/usr/share/game"
  cp -r "$ROOT/game/." "$APPDIR/usr/share/game/"
  MT32_OK=0
  stage_mt32_rom "$APPDIR/usr/share/game" && MT32_OK=1
fi

cp "$ROOT/tools/assets/freddy-cht.png" "$APPDIR/freddy-cht.png"
ln -sf freddy-cht.png "$APPDIR/.DirIcon"
cat > "$APPDIR/freddy-cht.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=多情藥師酷牛仔（繁體中文版）
Comment=Freddy Pharkas: Frontier Pharmacist 繁體中文化 — ScummVM
Exec=AppRun
Icon=freddy-cht
Categories=Game;
Terminal=false
DESK

# --- AppRun ------------------------------------------------------------------
if [ "$MODE" = patch ]; then
cat > "$APPDIR/AppRun" <<'APPRUN'
#!/bin/bash
set -e
HERE="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="$HERE/usr/lib:${LD_LIBRARY_PATH:-}"
if [ -z "${1:-}" ]; then
  echo "用法: $(basename "$0") <多情藥師酷牛仔 遊戲資料夾路徑> [其他 scummvm 參數...]"
  echo "  範例: ./FreddyPharkas-CHT-patch-x86_64.AppImage ~/games/freddy"
  echo "  遊戲夾內要有 resource.000 / resource.map / resource.aud 等(自備正版)。"
  exit 1
fi
GAME="$(readlink -f "$1")"; shift
CFGDIR="${XDG_CONFIG_HOME:-$HOME/.config}/freddy-cht"
CFG="$CFGDIR/scummvm.ini"
mkdir -p "$CFGDIR"
cat > "$CFG" <<CFGEOF
[scummvm]

[freddypharkas]
engineid=sci
gameid=freddypharkas
description=多情藥師酷牛仔（繁體中文）
path=$GAME
extrapath=$HERE/usr/share/scummvm-cht
language=tw
subtitles=true
speech_mute=false
CFGEOF
exec "$HERE/usr/bin/scummvm" --config="$CFG" freddypharkas "$@"
APPRUN
else
cat > "$APPDIR/AppRun" <<'APPRUN'
#!/bin/bash
set -e
HERE="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="$HERE/usr/lib:${LD_LIBRARY_PATH:-}"
GAME="$HERE/usr/share/game"
CFGDIR="${XDG_CONFIG_HOME:-$HOME/.config}/freddy-cht-full"
CFG="$CFGDIR/scummvm.ini"
mkdir -p "$CFGDIR"
cat > "$CFG" <<CFGEOF
[scummvm]

[freddypharkas]
engineid=sci
gameid=freddypharkas
description=多情藥師酷牛仔（繁體中文・完整版）
path=$GAME
extrapath=$GAME
language=tw
subtitles=true
speech_mute=false
CFGEOF
exec "$HERE/usr/bin/scummvm" --config="$CFG" freddypharkas "$@"
APPRUN
  # 有 ROM 才設 MT-32 為預設驅動:沒 ROM 卻設 mt32,ScummVM 會先彈一次
  # 「MT-32 emulator cannot be used」擋住玩家再回退 AdLib。
  if [ "${MT32_OK:-0}" = 1 ]; then
    sed -i 's|^speech_mute=false$|speech_mute=false\nmusic_driver=mt32|' "$APPDIR/AppRun"
  fi
fi
chmod +x "$APPDIR/AppRun"

rm -f "$OUT"
echo ">> appimagetool 打包(--appimage-extract-and-run 免 FUSE)"
docker run --rm --name freddy-pkg-appimagetool -v "$STAGE:/stage" -v "$ROOT/tools/.cache:/cache:ro" \
  -e ARCH=x86_64 -w /stage "$BUILD_IMG" bash -c \
  "apt-get update -qq >/dev/null && apt-get install -y -qq file >/dev/null && \
   /cache/appimagetool-x86_64.AppImage --appimage-extract-and-run 'AppDir' '/stage/$(basename "$OUT")' && \
   chown $(id -u):$(id -g) '/stage/$(basename "$OUT")'"
mv "$STAGE/$(basename "$OUT")" "$OUT"
chmod +x "$OUT"
echo ">> 完成: $OUT ($(du -h "$OUT" | cut -f1))"
