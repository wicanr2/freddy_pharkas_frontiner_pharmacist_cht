#!/usr/bin/env bash
# 驗 UI:控制面板(存/讀/重新開始/說明/離開)、存讀檔對話框、道具欄。
# 這些不是對白,走的是另一條繪字路徑(選單/視窗),必須單獨看過才算驗收完。
set -euo pipefail
WP=/home/anr2/scummvm/Freddy_Pharkas/workplace
OUT="${1:-ui}"
mkdir -p "$WP/out/$OUT"; rm -f "$WP/out/$OUT"/*.png

timeout 420 docker run --rm --name "freddy-cap-$OUT" -v "$WP":/w -w /w freddy-capture:latest bash -c "
set -e
export XDG_RUNTIME_DIR=/tmp DISPLAY=:99 SDL_AUDIODRIVER=dummy SCI_CHT_DEBUG=1
Xvfb :99 -screen 0 1280x800x24 >/dev/null 2>&1 &
sleep 2
printf '[scummvm]\ngfx_mode=surfacesdl\nscale_factor=1\n\n[freddypharkas]\nengineid=sci\ngameid=freddypharkas\npath=/w/game\nextrapath=/w/game\nlanguage=tw\nsubtitles=true\n' > /tmp/scummvm.ini
./scummvm-src/scummvm --config=/tmp/scummvm.ini freddypharkas > /w/out/$OUT/run.log 2>&1 &
shot() { import -window root /w/out/\$1.png 2>/dev/null || true; }

sleep 30
shot $OUT/00_titlemenu           # 標題選單(載入/序幕/開始/說明/離開)
xdotool mousemove 910 717 click 1; sleep 6
shot $OUT/01_help                # 標題選單的「說明」
xdotool key Escape; sleep 3
xdotool mousemove 612 717 click 1; sleep 6
shot $OUT/02_restore_from_title  # 標題選單的「載入」→ 讀檔對話框
xdotool key Escape; sleep 3

for _ in 1 2 3; do xdotool mousemove 832 717 click 1; sleep 8; done
sleep 4
shot $OUT/03_ingame

# 進遊戲後把滑鼠推到畫面最上緣,SCI1.1 的 icon bar 會拉下來
for y in 302 303 305 308; do xdotool mousemove 800 \$y; sleep 2; done
shot $OUT/04_iconbar
# 沿著 icon bar 逐格點,把道具欄/控制面板都翻出來
i=0
for x in 520 560 600 640 680 720 760 800 840 880 920 960 1000 1040 1080; do
  i=\$((i+1))
  xdotool mousemove \$x 306 click 1; sleep 3
  shot $OUT/05_bar_\$(printf %02d \$i)
  xdotool key Escape; sleep 2
done

pkill -f scummvm 2>/dev/null || true
sleep 1
" 2>&1 | tail -2
echo "== 截圖 $(ls "$WP/out/$OUT"/*.png 2>/dev/null | wc -l) 張 =="
grep -a 'CHT-MISS' "$WP/out/$OUT/run.log" | sed 's/^.*CHT-MISS\[[0-9]*\]://' | sort | uniq -c | sort -rn > "$WP/out/$OUT/miss.txt" || true
echo "== MISS $(wc -l < "$WP/out/$OUT/miss.txt") 種 =="
