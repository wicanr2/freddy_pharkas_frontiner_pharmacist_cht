#!/usr/bin/env bash
# 開 SCI_CHT_DEBUG=1 跑一輪 headless playtest,收集引擎回報的 CHT-MISS/CHT-HIT。
#
# 為什麼:引擎每次要畫字都會查 translation.tsv,查不到就印 CHT-MISS。
# 這是「畫面上還有哪些英文」最直接的 oracle——比人工翻截圖找可靠。
# 產出 out/<subdir>/miss.txt(去重、依出現次數排序)供補譯/補抽字。
#
# 用法:cap_miss.sh [out_subdir]
set -euo pipefail
WP=/home/anr2/scummvm/Freddy_Pharkas/workplace
OUT="${1:-miss}"
mkdir -p "$WP/out/$OUT"; rm -f "$WP/out/$OUT"/*.png

timeout 420 docker run --rm --name "freddy-cap-$OUT" -v "$WP":/w -w /w freddy-capture:latest bash -c "
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
shot $OUT/00_menu
# 主選單「開始」在 (832,717)。開 SCI_CHT_DEBUG 後啟動較慢,點一次可能還沒進選單 →
# 點三次、每次間隔夠久;已經進遊戲後多點的那幾下落在天空/建築上,只會多出一句敘述。
for _ in 1 2 3; do
  xdotool mousemove 832 717 click 1
  sleep 8
done
sleep 6
shot $OUT/01_ingame

# 遊戲區 640x400 置中於 1280x800:x 480..1120, y 300..760
# 每輪:右鍵換游標(走/看/手/說/…),再點幾個熱點逼出敘述框
for r in 1 2 3 4 5; do
  xdotool mousemove 800 550 click 3; sleep 1
  for xy in '900 400' '1030 545' '650 520' '760 480' '980 430'; do
    xdotool mousemove \$xy click 1; sleep 3
  done
  shot $OUT/1\${r}_round
done

# 上緣 icon bar:滑鼠移到遊戲區頂端會自動拉下來(SCI1.1 慣例),先截一張看有哪些圖示
xdotool mousemove 800 305; sleep 3; shot $OUT/20_iconbar
# 道具欄:icon bar 上的背包圖示(位置依畫面,先掃過幾個 x 再截)
for x in 560 620 680 740 900 960 1020; do
  xdotool mousemove \$x 312 click 1; sleep 3; shot $OUT/21_bar_\$x
  xdotool mousemove 800 600 click 1; sleep 2   # 點回場景關掉可能開起來的視窗
done
# F8:中英切換(自訂鍵),切過去再切回來
xdotool mousemove 800 600; xdotool key F8; sleep 3; shot $OUT/24_f8_en
xdotool key F8; sleep 3; shot $OUT/25_f8_cht

pkill -f scummvm 2>/dev/null || true
sleep 1
" 2>&1 | tail -3

LOG="$WP/out/$OUT/run.log"
grep -a 'CHT-MISS' "$LOG" | sed 's/^.*CHT-MISS\[[0-9]*\]://' | sort | uniq -c | sort -rn \
  > "$WP/out/$OUT/miss.txt" || true
grep -ac 'CHT-HIT' "$LOG" > "$WP/out/$OUT/hit_count.txt" || true
echo "== 截圖 $(ls "$WP/out/$OUT"/*.png 2>/dev/null | wc -l) 張 =="
echo "== CHT-HIT $(cat "$WP/out/$OUT/hit_count.txt" 2>/dev/null || echo 0) 次 / MISS $(wc -l < "$WP/out/$OUT/miss.txt") 種 =="
