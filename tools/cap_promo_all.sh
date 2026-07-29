#!/usr/bin/env bash
# 依序錄完推廣片需要的每一鏡。每鏡都錄 16 秒(比實際需要長),剪接階段再挑最好的一段。
set -uo pipefail
cd /home/anr2/scummvm/Freddy_Pharkas/workplace
for s in s01_walk s03_talk s04_street s05_store s06_ui s07_counter s08_f8; do
  echo "===== $s ====="
  bash tools/cap_promo_shot.sh "$s" 16 || echo "!! $s 失敗,繼續下一鏡"
done
echo "===== 全部錄完 ====="
ls -la out/video_src/raw_*.mkv
