#!/usr/bin/env bash
# 用 ScummVM 內建除錯器的 `room` 指令巡場景,每個場景用「看」游標點幾下逼出敘述框,
# 逐場截圖 + 收 CHT-MISS。比在同一個場景亂點可靠得多(亂點只會反覆觸發同一句)。
#
# 用法:cap_rooms.sh [out_subdir] [room...]
set -euo pipefail
WP=/home/anr2/scummvm/Freddy_Pharkas/workplace
OUT="${1:-rooms}"; shift || true
ROOMS="${*:-220 230 250 260 300 310 320 400 410 600 610 620 630 640 650 660 670 690 710 720}"
mkdir -p "$WP/out/$OUT"; rm -f "$WP/out/$OUT"/*.png

timeout 900 docker run --rm --name "freddy-cap-$OUT" -v "$WP":/w -w /w freddy-capture:latest bash -c "
set -e
export XDG_RUNTIME_DIR=/tmp DISPLAY=:99 SDL_AUDIODRIVER=dummy SCI_CHT_DEBUG=1
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
language=tw
subtitles=true
speech_mute=false
talkspeed=255
INI
./scummvm-src/scummvm --config=/tmp/scummvm.ini freddypharkas > /w/out/$OUT/run.log 2>&1 &
shot() { import -window root /w/out/\$1.png 2>/dev/null || true; }

sleep 30
for _ in 1 2 3; do xdotool mousemove 832 717 click 1; sleep 8; done
sleep 6
shot $OUT/00_start

# 右鍵把游標切到「看」(第二個游標),之後每個場景都用它點
xdotool mousemove 800 550 click 3; sleep 2

for R in $ROOMS; do
  # 開除錯器 → room N → 關閉
  xdotool key ctrl+alt+d; sleep 3
  xdotool type --delay 60 \"room \$R\"; xdotool key Return; sleep 3
  xdotool key ctrl+alt+d; sleep 1
  xdotool key Escape; sleep 6
  shot $OUT/r\${R}_0
  for xy in '760 420' '900 500' '1020 560' '620 480'; do
    xdotool mousemove \$xy click 1; sleep 4
  done
  shot $OUT/r\${R}_1
  xdotool mousemove 800 700 click 1; sleep 2
done

pkill -f scummvm 2>/dev/null || true
sleep 1
" 2>&1 | tail -3

LOG="$WP/out/$OUT/run.log"
grep -a 'CHT-MISS' "$LOG" | sed 's/^.*CHT-MISS\[[0-9]*\]://' | sort | uniq -c | sort -rn \
  > "$WP/out/$OUT/miss.txt" || true
echo "== 截圖 $(ls "$WP/out/$OUT"/*.png 2>/dev/null | wc -l) 張 =="
echo "== CHT-HIT $(grep -ac 'CHT-HIT' "$LOG" || echo 0) 次 / MISS $(wc -l < "$WP/out/$OUT/miss.txt") 種 =="
