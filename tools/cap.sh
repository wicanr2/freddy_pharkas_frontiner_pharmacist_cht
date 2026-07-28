#!/usr/bin/env bash
# headless 擷取:Xvfb 內跑 ScummVM,依時間點連續截圖。
#
# 用法:cap.sh <out_subdir> [秒數] [--en]
#   --en:不寫 language=tw(跑英文版對照,判斷「是不是中文化造成的迴歸」用)
#
# [HARD] SDL_AUDIODRIVER=dummy 不可省:Freddy Pharkas 的 intro/選單流程同步於音樂 cue,
#        容器內沒有音效裝置時 SCI script 會永遠等不到 cue → 畫面卡在第一張 pic 不動
#        (英文版同樣卡,不是中文化造成的)。給了 dummy audio device 才會推進。
# [HARD] 容器一律具名 freddy-cap-*、包 timeout;結束用 killall 收 scummvm,
#        不要 wait 背景的 Xvfb(不退會永久卡)。
set -euo pipefail
WP=/home/anr2/scummvm/Freddy_Pharkas/workplace
OUT="${1:?用法: cap.sh <out_subdir> [秒數] [--en]}"
SECS="${2:-40}"
LANGLINE="language=tw"
[ "${3:-}" = "--en" ] && LANGLINE=""

mkdir -p "$WP/out/$OUT"
rm -f "$WP/out/$OUT"/*.png

timeout $((SECS + 90)) docker run --rm --name "freddy-cap-$OUT" \
  -v "$WP":/w -w /w freddy-capture:latest bash -c "
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
description=Freddy Pharkas
$LANGLINE
subtitles=true
speech_mute=false
talkspeed=255
INI

./scummvm-src/scummvm --config=/tmp/scummvm.ini freddypharkas \
  > /w/out/$OUT/run.log 2>&1 &

for i in \$(seq 1 $SECS); do
  sleep 1
  import -window root /w/out/$OUT/t\$(printf %03d \$i).png 2>/dev/null || true
done

killall scummvm 2>/dev/null || true
sleep 1
" 2>&1 | tail -3

echo "== 截圖 $(ls "$WP/out/$OUT"/*.png 2>/dev/null | wc -l) 張,不重複 $(md5sum "$WP/out/$OUT"/*.png | awk '{print $1}' | sort -u | wc -l) 種 =="
