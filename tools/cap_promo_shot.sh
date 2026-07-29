#!/usr/bin/env bash
# 推廣片 live 錄影:每次錄一鏡。用 ffmpeg x11grab 錄 Xvfb 畫面,不是把截圖排成投影片。
#
# 用法:cap_promo_shot.sh <鏡號> [秒數]
#
# 設計要點:
#  - ffmpeg 以固定 -t 在前景跑完 = 這一鏡的計時器;Xvfb/ScummVM 記 PID 由 trap 收。
#    [HARD] 不要 wait 長駐行程(它們不會自己結束,容器會卡到天荒地老)。
#  - 每鏡都錄得比實際需要長,剪接階段再挑最好的一段。硬要現場掐秒只會重錄很多次。
#  - 遊戲視窗在 1280x800 螢幕上是置中 letterbox:遊戲座標 (x,y) → 螢幕 (480+x, 304+y)。
set -euo pipefail
WP=/home/anr2/scummvm/Freddy_Pharkas/workplace
SHOT="${1:?用法: cap_promo_shot.sh <鏡號> [秒數]}"
SECS="${2:-16}"
OUT="$WP/out/video_src"
mkdir -p "$OUT"

# 每鏡的:房號 + 錄影期間的 xdotool 操作序列
#   座標已換算成螢幕座標。sleep 拿捏成剛好填滿錄影長度。
case "$SHOT" in
  s01_walk)      ROOM=600; OPS='
      xdotool mousemove 620 620 click 1; sleep 4
      xdotool mousemove 1000 640 click 1; sleep 5
      xdotool mousemove 760 600 click 1; sleep 5' ;;
  # 廣告第 1 格(酒吧)的同機位 —— 冷開場對照用
  s02_saloon)    ROOM=670; OPS='
      xdotool mousemove 800 550 click 3; sleep 1
      xdotool mousemove 700 450 click 1; sleep 5
      xdotool mousemove 950 480 click 1; sleep 5
      xdotool mousemove 620 600 click 1; sleep 4' ;;
  # 廣告第 2 格(老媽餐館,向日葵橢圓框)的同機位 —— 第二組對照用
  s09_cafe)      ROOM=660; OPS='
      xdotool mousemove 800 550 click 3; sleep 1
      xdotool mousemove 720 460 click 1; sleep 5
      xdotool mousemove 900 520 click 1; sleep 5
      xdotool mousemove 800 620 click 1; sleep 4' ;;
  # 標題選單:載入/序幕/開始/說明/離開 全是中文,滑鼠滑過各鈕。
  # 這鏡不換場(還沒進遊戲),所以 ROOM 設 0 當作「跳過換場」。
  s10_menu)      ROOM=0; OPS='
      for x in 612 700 832 910 1000; do xdotool mousemove $x 717; sleep 1.6; done
      xdotool mousemove 832 717; sleep 3
      for x in 612 910 832; do xdotool mousemove $x 717; sleep 1.6; done' ;;
  s03_talk)      ROOM=600; OPS='
      xdotool mousemove 800 550 click 3; sleep 1
      xdotool mousemove 560 420 click 1; sleep 5
      xdotool mousemove 900 660 click 1; sleep 5
      xdotool mousemove 1050 430 click 1; sleep 4' ;;
  s04_street)    ROOM=250; OPS='
      xdotool mousemove 800 550 click 3; sleep 1
      xdotool mousemove 700 430 click 1; sleep 5
      xdotool mousemove 1000 480 click 1; sleep 5
      xdotool mousemove 850 640 click 1; sleep 4' ;;
  s05_store)     ROOM=650; OPS='
      xdotool mousemove 800 550 click 3; sleep 1
      xdotool mousemove 700 450 click 1; sleep 5
      xdotool mousemove 950 500 click 1; sleep 5
      xdotool mousemove 820 620 click 1; sleep 4' ;;
  s06_ui)        ROOM=600; OPS='
      for y in 320 312 308 306; do xdotool mousemove 800 $y; sleep 1; done
      xdotool mousemove 640 306 click 1; sleep 4
      xdotool key Escape; sleep 1
      xdotool mousemove 760 306 click 1; sleep 4
      xdotool key Escape; sleep 2' ;;
  s07_counter)   ROOM=620; OPS='
      xdotool mousemove 800 550 click 3; sleep 1
      xdotool mousemove 700 480 click 1; sleep 5
      xdotool mousemove 900 520 click 1; sleep 5
      xdotool mousemove 1000 460 click 1; sleep 4' ;;
  # F8 是「下一則訊息才生效」:必須關掉對白框 → 按 F8 → 重新觸發同一句
  s08_f8)        ROOM=250; OPS='
      xdotool mousemove 800 550 click 3; sleep 1
      xdotool mousemove 760 420 click 1; sleep 4
      xdotool mousemove 800 700 click 1; sleep 1
      xdotool key F8; sleep 1
      xdotool mousemove 760 420 click 1; sleep 4
      xdotool mousemove 800 700 click 1; sleep 1
      xdotool key F8; sleep 1
      xdotool mousemove 760 420 click 1; sleep 5' ;;
  *) echo "未知鏡號: $SHOT" >&2; exit 1 ;;
esac

echo ">> 錄 $SHOT (room $ROOM, ${SECS}s)"
timeout $((SECS + 180)) docker run --rm --name "freddy-video-cap-$SHOT" --cpus=2 \
  -v "$WP":/w -w /w freddy-video-capture:latest bash -uc '
    SHOT="'"$SHOT"'"; SECS="'"$SECS"'"; ROOM="'"$ROOM"'"
    XPID=""; GPID=""; OPPID=""
    cleanup() {
      for pid in "$OPPID" "$GPID" "$XPID"; do
        [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
      done
      pkill -f scummvm 2>/dev/null || true
    }
    trap cleanup EXIT INT TERM

    export XDG_RUNTIME_DIR=/tmp DISPLAY=:99 SDL_AUDIODRIVER=dummy
    Xvfb :99 -screen 0 1280x800x24 >/dev/null 2>&1 & XPID=$!
    sleep 2

    printf "[scummvm]\ngfx_mode=surfacesdl\nscale_factor=1\n\n[freddypharkas]\nengineid=sci\ngameid=freddypharkas\npath=/w/game\nextrapath=/w/game\nlanguage=tw\nsubtitles=true\nspeech_mute=true\ntalkspeed=1\n" > /tmp/scummvm.ini

    ./scummvm-src/scummvm --config=/tmp/scummvm.ini freddypharkas \
        > "/w/out/video_src/$SHOT.log" 2>&1 & GPID=$!

    # 過標題選單進遊戲(ROOM=0 的鏡就是要拍標題選單本身,不進遊戲)
    sleep 30
    if [ "$ROOM" != "0" ]; then
      for _ in 1 2 3; do xdotool mousemove 832 717 click 1; sleep 8; done
      sleep 14
    fi        # 載入時間會浮動,等久一點再下除錯器指令

    # 用除錯器換到目標場景(不玩劇情)。
    # [雷] 只下一次會失敗:遊戲還在載入/還在選單時下 room,指令會被隨後載入的起始場景蓋掉,
    #      結果整鏡都停在起始街景。下兩次(第二次是冪等的)才穩。
    # [雷] 關除錯器要打 exit,不是再按一次 ctrl+alt+d。
    #   主控台自己就寫著 "type 'exit' to return to the game"。用 ctrl+alt+d 切回去常常
    #   不生效 → 主控台整片蓋在畫面上,錄下來就是一片黑底綠字(而 room 指令其實早就成功了,
    #   log 會印 "Room number changed to N")。Escape 當第二道保險。
    jump() {
      xdotool key ctrl+alt+d; sleep 3
      xdotool type --delay 60 "room $ROOM"; xdotool key Return; sleep 2
      xdotool type --delay 60 "exit"; xdotool key Return; sleep 3
      xdotool key Escape; sleep 4
    }
    if [ "$ROOM" != "0" ]; then jump; sleep 6; jump; sleep 6; fi
    import -window root "/w/out/video_src/${SHOT}_check.png" 2>/dev/null || true

    # 操作序列在背景送鍵,ffmpeg 在前景錄滿 SECS 秒
    ( '"$OPS"' ) & OPPID=$!

    # [雷] -y 不能省:重錄同一鏡時 ffmpeg 會停下來問 "File already exists. Overwrite?"
    #   然後直接退出。第一輪全新錄影不會遇到,一補錄就整批靜靜地沒有產出。
    ffmpeg -y -hide_banner -loglevel error -f x11grab -framerate 30 \
           -video_size 1280x800 -i :99 -t "$SECS" \
           -c:v libx264 -preset ultrafast -qp 0 "/w/out/video_src/raw_$SHOT.mkv"

    wait "$OPPID" 2>/dev/null || true
  ' 2>&1 | tail -3

ls -la "$OUT/raw_$SHOT.mkv"
