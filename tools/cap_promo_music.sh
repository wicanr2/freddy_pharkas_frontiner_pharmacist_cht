#!/usr/bin/env bash
# 錄原版遊戲音樂當推廣片配樂 —— 即時側錄 Munt 模擬的 Roland MT-32 輸出。
#
# [HARD] 不要設 SDL_DISKAUDIODELAY=0。那是「全速灌」模式:mixer 以 CPU 全速跑,
#   但 SCI 的音樂排序器是依「遊戲時鐘」推進的,全速下排序器不動 → 錄出來是 GB 級的靜音檔。
#   即時側錄(不設 DELAY)才會錄到真的音樂。
# [HARD] 收尾用 pkill,不要 wait 背景的 Xvfb/ScummVM(它們不會自己結束,會卡死容器)。
set -euo pipefail
WP=/home/anr2/scummvm/Freddy_Pharkas/workplace
SECS="${1:-150}"
OUT="$WP/out/video_src/music"
mkdir -p "$OUT"

timeout $((SECS + 180)) docker run --rm --name freddy-video-music --cpus=2 \
  -v "$WP":/w -w /w -v /home/anr2/cht/mt32:/rom:ro freddy-video-capture:latest bash -uc '
    SECS="'"$SECS"'"
    XPID=""; GPID=""
    cleanup() { pkill -f scummvm 2>/dev/null || true
                [ -n "$XPID" ] && kill "$XPID" 2>/dev/null || true; }
    trap cleanup EXIT INT TERM

    # MT-32 ROM 要正名成 ScummVM 找得到的檔名,放進 extrapath
    mkdir -p /tmp/rom
    cp "$(ls /rom/MT32_CONTROL*.ROM | head -1)" /tmp/rom/MT32_CONTROL.ROM
    cp /rom/MT32_PCM.ROM /tmp/rom/MT32_PCM.ROM

    Xvfb :99 -screen 0 1280x800x24 >/dev/null 2>&1 & XPID=$!
    sleep 2
    export DISPLAY=:99
    export SDL_AUDIODRIVER=disk
    export SDL_DISKAUDIOFILE=/w/out/video_src/music/raw.pcm
    # 注意:這裡刻意不設 SDL_DISKAUDIODELAY

    printf "[scummvm]\ngfx_mode=surfacesdl\nscale_factor=1\n\n[freddypharkas]\nengineid=sci\ngameid=freddypharkas\npath=/w/game\nextrapath=/w/game\nlanguage=tw\nsubtitles=true\n" > /tmp/scummvm.ini

    ./scummvm-src/scummvm --config=/tmp/scummvm.ini \
        --music-driver=mt32 --extrapath=/tmp/rom \
        --music-volume=255 --output-rate=44100 \
        freddypharkas > /w/out/video_src/music/run.log 2>&1 &

    sleep "$SECS"
  ' 2>&1 | tail -3

echo "== ROM 載入檢查(要看到 Falling back to MT32) =="
grep -aiE 'mt32|munt|rom' "$OUT/run.log" | head -5 || true
ls -la "$OUT/raw.pcm"
