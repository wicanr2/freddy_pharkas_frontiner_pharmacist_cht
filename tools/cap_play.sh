#!/usr/bin/env bash
# 進遊戲(點主選單 Play)→ 走到場景 → 右鍵切「看」游標 → 點物件逼出中文敘述框。
# 用法:cap_play.sh [out_subdir] [--en]
set -euo pipefail
WP=/home/anr2/scummvm/Freddy_Pharkas/workplace
OUT="${1:-play}"
LANGLINE="language=tw"
[ "${2:-}" = "--en" ] && LANGLINE=""
mkdir -p "$WP/out/$OUT"; rm -f "$WP/out/$OUT"/*.png

timeout 300 docker run --rm --name "freddy-cap-$OUT" -v "$WP":/w -w /w freddy-capture:latest bash -c "
set -e
export XDG_RUNTIME_DIR=/tmp DISPLAY=:99 SDL_AUDIODRIVER=dummy
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
$LANGLINE
subtitles=true
speech_mute=false
talkspeed=255
INI
./scummvm-src/scummvm --config=/tmp/scummvm.ini freddypharkas > /w/out/$OUT/run.log 2>&1 &
shot() { import -window root /w/out/\$1.png 2>/dev/null || true; }

sleep 24                      # 等 Sierra logo → 標題 → 選單長出來
shot $OUT/00_menu
xdotool mousemove 832 717 click 1   # 主選單「開始」(第三顆按鈕)
sleep 12
shot $OUT/01_ingame

# 遊戲區 640x400 置中:x 480..1120, y 300..760
for r in 1 2 3 4; do
  xdotool mousemove 800 550 click 3      # 右鍵循環游標
  sleep 1
  xdotool mousemove 900 400 click 1; sleep 4; shot $OUT/02_r\${r}_a
  xdotool mousemove 1030 545 click 1; sleep 4; shot $OUT/03_r\${r}_b
  xdotool mousemove 650 520 click 1; sleep 4; shot $OUT/04_r\${r}_c
done
xdotool mousemove 800 310; sleep 3; shot $OUT/05_iconbar

killall scummvm 2>/dev/null || true
sleep 1
" 2>&1 | tail -3
echo "== $(ls "$WP/out/$OUT"/*.png 2>/dev/null | wc -l) 張 =="
