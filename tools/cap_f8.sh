#!/usr/bin/env bash
# 驗 F8 中英切換:同一個熱點,先中文看一次 → 按 F8 → 再看一次應變英文 → 再按 F8 → 又變中文。
# F8 是「下一則文字生效」語意(SCI 文字框繪製與 transient port 狀態緊耦合,就地重繪風險高),
# 所以每次切換後都要重新觸發一則訊息才看得出來。
set -euo pipefail
WP=/home/anr2/scummvm/Freddy_Pharkas/workplace
OUT="${1:-f8}"
mkdir -p "$WP/out/$OUT"; rm -f "$WP/out/$OUT"/*.png

timeout 300 docker run --rm --name "freddy-cap-$OUT" -v "$WP":/w -w /w freddy-capture:latest bash -c "
set -e
export XDG_RUNTIME_DIR=/tmp DISPLAY=:99 SDL_AUDIODRIVER=dummy SCI_CHT_DEBUG=1
Xvfb :99 -screen 0 1280x800x24 >/dev/null 2>&1 &
sleep 2
printf '[scummvm]\ngfx_mode=surfacesdl\nscale_factor=1\n\n[freddypharkas]\nengineid=sci\ngameid=freddypharkas\npath=/w/game\nextrapath=/w/game\nlanguage=tw\nsubtitles=true\n' > /tmp/scummvm.ini
./scummvm-src/scummvm --config=/tmp/scummvm.ini freddypharkas > /w/out/$OUT/run.log 2>&1 &
shot() { import -window root /w/out/\$1.png 2>/dev/null || true; }

sleep 30
for _ in 1 2 3; do xdotool mousemove 832 717 click 1; sleep 8; done
xdotool mousemove 800 550 click 3; sleep 2      # 切「看」游標

poke() {   # 點同一個熱點逼出敘述框
  xdotool mousemove 900 400 click 1; sleep 4
}

poke; shot $OUT/1_cht        # 預設中文
xdotool mousemove 800 700 click 1; sleep 2
xdotool key F8; sleep 1
poke; shot $OUT/2_en         # F8 後應為英文
xdotool mousemove 800 700 click 1; sleep 2
xdotool key F8; sleep 1
poke; shot $OUT/3_cht_again  # 再按 F8 應切回中文

pkill -f scummvm 2>/dev/null || true
sleep 1
" 2>&1 | tail -2
echo "== 截圖 $(ls "$WP/out/$OUT"/*.png 2>/dev/null | wc -l) 張,請逐張看 1_cht / 2_en / 3_cht_again =="
