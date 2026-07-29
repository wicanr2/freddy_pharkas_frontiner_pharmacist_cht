#!/usr/bin/env bash
# 驗收:從乾淨的 upstream ScummVM 重新套 patch → configure → make,確認 patch 自足可重建。
#
# 為什麼要做:平常改的是 scummvm-src 這棵已經套過 patch 的樹,patch 是從它 diff 出來的。
# patch 少帶一個新檔(例如 fontchinese.cpp)或 hunk 有 drift,在那棵樹上完全看不出來——
# 只有從 pristine 重來一次才會爆。
#
# 用法:verify_patch_rebuild.sh [工作目錄]
set -euo pipefail
WP=/home/anr2/scummvm/Freddy_Pharkas/workplace
WORK="${1:-/tmp/freddy-verify}"
UP="$(cat "$WP/patches/UPSTREAM_COMMIT.txt")"

rm -rf "$WORK"; mkdir -p "$WORK/src"
echo ">> 1) 從本機 checkout 造 pristine 樹 @ $UP"
git -C "$WP/scummvm-src" archive "$UP" | tar -x -C "$WORK/src"

echo ">> 2) 套 patch(apply_patches.sh 的等價步驟,目錄已存在故不 clone)"
cp "$WP/patches/fontchinese.h"   "$WORK/src/engines/sci/graphics/fontchinese.h"
cp "$WP/patches/fontchinese.cpp" "$WORK/src/engines/sci/graphics/fontchinese.cpp"
patch -p1 -d "$WORK/src" < "$WP/patches/0001-sci-cht-zh_twn.patch"

echo ">> 3) docker 內 configure + make(MT-32 必須啟用)"
docker run --rm --name freddy-verify -v "$WORK":/w -w /w/src freddy-build:latest bash -c '
  set -e
  ./configure --disable-all-engines --enable-engine=sci --disable-detection-full >/tmp/conf.log 2>&1 || { tail -30 /tmp/conf.log; exit 1; }
  grep -q "^#define USE_MT32EMU" config.h || { echo "!!! MT-32 未啟用"; exit 1; }
  echo "   MT-32: $(grep USE_MT32EMU config.h)"
  make -j"$(nproc)" >/tmp/make.log 2>&1 || { tail -40 /tmp/make.log; exit 1; }
  ls -la scummvm
'

echo ">> 4) 用重建出來的 binary 實跑一次(headless,確認中文仍正常)"
mkdir -p "$WP/out/verify"; rm -f "$WP/out/verify"/*.png
timeout 240 docker run --rm --name freddy-verify-run \
  -v "$WP":/w -v "$WORK":/v -w /w freddy-capture:latest bash -c '
set -e
export XDG_RUNTIME_DIR=/tmp DISPLAY=:99 SDL_AUDIODRIVER=dummy SCI_CHT_DEBUG=1
Xvfb :99 -screen 0 1280x800x24 >/dev/null 2>&1 &
sleep 2
printf "[scummvm]\ngfx_mode=surfacesdl\nscale_factor=1\n\n[freddypharkas]\nengineid=sci\ngameid=freddypharkas\npath=/w/game\nextrapath=/w/game\nlanguage=tw\nsubtitles=true\n" > /tmp/scummvm.ini
/v/src/scummvm --config=/tmp/scummvm.ini freddypharkas > /w/out/verify/run.log 2>&1 &
sleep 30
import -window root /w/out/verify/menu.png 2>/dev/null || true
for _ in 1 2 3; do xdotool mousemove 832 717 click 1; sleep 8; done
xdotool mousemove 800 550 click 3; sleep 2
xdotool mousemove 900 400 click 1; sleep 5
import -window root /w/out/verify/ingame.png 2>/dev/null || true
pkill -f scummvm 2>/dev/null || true
sleep 1
' 2>&1 | tail -2

HIT=$(grep -ac 'CHT-HIT' "$WP/out/verify/run.log" || echo 0)
MISS=$(grep -ac 'CHT-MISS' "$WP/out/verify/run.log" || echo 0)
echo "== 重建驗證完成:CHT-HIT $HIT 次、CHT-MISS $MISS 次,截圖於 out/verify/ =="
[ "$HIT" -gt 0 ] || { echo "!!! 重建的 binary 沒有任何中文命中,patch 可能不完整"; exit 1; }
