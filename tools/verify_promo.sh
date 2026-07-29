#!/usr/bin/env bash
# 推廣片驗收:對照提案第 13 節的驗收標準逐條檢查。
set -uo pipefail
WP=/home/anr2/scummvm/Freddy_Pharkas/workplace
V="$WP/out/video/freddy-cht-promo.mp4"
fail=0
chk() { if [ "$2" = "1" ]; then echo "  ✓ $1"; else echo "  ✗ $1"; fail=$((fail+1)); fi; }

echo "== 影像 =="
read -r W H FR DUR <<< "$(docker run --rm --name freddy-video-vfy -v "$WP":/w game-video:latest bash -c "
  ffprobe -v error -select_streams v -show_entries stream=width,height,avg_frame_rate -show_entries format=duration -of default=nw=1:nk=1 /w/out/video/freddy-cht-promo.mp4 | tr '\n' ' '")"
echo "  解析度 ${W}x${H}  fps ${FR}  長度 ${DUR}s"
chk "master 為 1920x1080" "$([ "$W" = 1920 ] && [ "$H" = 1080 ] && echo 1 || echo 0)"
chk "30 fps"              "$([ "$FR" = "30/1" ] && echo 1 || echo 0)"
chk "長度 62 秒(±0.2)"    "$(awk -v d="$DUR" 'BEGIN{print (d>61.8 && d<62.2)?1:0}')"

echo "== 音訊 =="
AINFO=$(docker run --rm --name freddy-video-vfy2 -v "$WP":/w game-video:latest bash -c "
  ffprobe -v error -select_streams a -show_entries format=duration -of csv=p=0 /w/out/video/freddy-cht-promo.mp4;
  ffmpeg -hide_banner -i /w/out/video/freddy-cht-promo.mp4 -af volumedetect -f null /dev/null 2>&1 | grep -E 'mean_volume|max_volume'")
echo "$AINFO" | sed 's/^/  /'
ADUR=$(echo "$AINFO" | head -1)
MEAN=$(echo "$AINFO" | grep mean_volume | awk '{print $5}')
MAX=$(echo "$AINFO" | grep max_volume | awk '{print $5}')
chk "視訊/音訊等長(差<0.1s)" "$(awk -v a="$ADUR" -v v="$DUR" 'BEGIN{d=a-v; if(d<0)d=-d; print (d<0.1)?1:0}')"
chk "非靜音(mean > -60dB)"   "$(awk -v m="$MEAN" 'BEGIN{print (m>-60)?1:0}')"
chk "無削波(max < 0dB)"      "$(awk -v m="$MAX" 'BEGIN{print (m<0)?1:0}')"

echo "== 安全界線 =="
cd "$WP"
chk "影片未進版控"   "$(git ls-files | grep -cE '\.(mp4|mkv|wav|pcm)$' | awk '{print ($1==0)?1:0}')"
chk "git status 乾淨" "$([ -z "$(git status --porcelain)" ] && echo 1 || echo 0)"
chk "dist-all/ 未被動" "$([ "$(find dist-all -newermt '2026-07-29T02:00:00' 2>/dev/null | wc -l)" = 0 ] && echo 1 || echo 0)"
chk "無殘留錄影容器"  "$([ -z "$(docker ps -a --format '{{.Names}}' | grep '^freddy-video-')" ] && echo 1 || echo 0)"

echo
[ "$fail" = 0 ] && echo "== 全部通過 ==" || echo "== 有 $fail 項未通過 =="
exit $fail
