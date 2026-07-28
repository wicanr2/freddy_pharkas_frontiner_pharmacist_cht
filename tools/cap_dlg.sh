#!/usr/bin/env bash
# 觸發對白框並擷取:進遊戲後右鍵循環游標到「看」,點場景物件逼出敘述框。
# 用法:cap_dlg.sh [out_subdir] [--en]
set -euo pipefail
WP=/home/anr2/scummvm/Freddy_Pharkas/workplace
OUT="${1:-dlg}"
EN="${2:-}"
mkdir -p "$WP/out/$OUT"; rm -f "$WP/out/$OUT"/*.png

LANGLINE="language=tw"
[ "$EN" = "--en" ] && LANGLINE=""

timeout 240 docker run --rm --name "freddy-cap-$OUT" -v "$WP":/w -w /w freddy-capture:latest bash -c "
set -e
export XDG_RUNTIME_DIR=/tmp DISPLAY=:99
Xvfb :99 -screen 0 1280x800x24 >/dev/null 2>&1 &
sleep 2
cat > /tmp/scummvm.ini <<INI
[scummvm]
gfx_mode=surfacesdl
scale_factor=1

[freddypharkas]
engineid=sci
gameid=freddypharkas
path=/w/game
extrapath=/w/game
description=Freddy Pharkas
$LANGLINE
subtitles=true
speech_mute=false
talkspeed=255
INI
./scummvm-src/scummvm --config=/tmp/scummvm.ini freddypharkas > /w/out/$OUT/run.log 2>&1 &
sleep 12
WID=\$(xdotool search --class scummvm | head -1)
shot() { import -window root /w/out/$OUT/\$1.png 2>/dev/null || true; }

# 片頭:連續 ESC 跳過
for i in 1 2 3 4 5 6; do xdotool key --window \$WID Escape; sleep 1; done
shot a_after_intro

# 遊戲區在 1280x800 螢幕置中:x 480..1120, y 300..760(640x400)
# 右鍵循環游標(不必回 icon bar),點場景物件逼出敘述
for round in 1 2 3; do
  xdotool mousemove 800 550 click 3; sleep 1
  xdotool mousemove 900 365 click 1; sleep 3      # 藥房招牌
  shot b_sign_\$round
  xdotool mousemove 1030 545 click 1; sleep 3     # 木桶
  shot c_barrel_\$round
  xdotool mousemove 620 500 click 1; sleep 3      # 遠處建築
  shot d_far_\$round
done

# icon bar:滑到畫面頂端
xdotool mousemove 800 305; sleep 2; shot e_iconbar

pkill -f scummvm 2>/dev/null || killall scummvm 2>/dev/null || true
sleep 1
" 2>&1 | tail -3

echo "== 截圖 =="; ls "$WP/out/$OUT"/*.png 2>/dev/null | wc -l
grep -iE "chinese|big5|translation|zh_twn|hires|warning: sci" "$WP/out/$OUT/run.log" | head -10 || true
