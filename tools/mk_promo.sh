#!/usr/bin/env bash
# 合成推廣片。在 game-video image 內跑(有 ffmpeg + ImageMagick + Noto CJK)。
#
# 做法:每一段先用 ImageMagick 畫「背景 PNG」與「前景 PNG(RGBA,文字/框線)」,
# 再用 ffmpeg 把 live 錄影夾在中間 overlay 起來。這樣中文排版交給 IM(它處理 CJK 比
# drawtext 可靠),ffmpeg 只負責疊圖與時間。
#
# [HARD] 三個 kb 雷:
#   1. 不用 zoompan(幀數會爆炸,見 kb 雷 #1)。要動就用 live 錄影本身的動態。
#   2. 配樂比影片短 → 先 aloop 再 atrim,不加 -shortest(否則結尾卡被砍掉)。
#   3. 遊戲畫面一律 2× nearest(scale=...:flags=neighbor),不做非整數縮放。
set -euo pipefail
source /w/tools/promo_theme.sh

T=/tmp/promo; mkdir -p "$T"
SRC=/w/out/video_src
OUT=/w/out/video; mkdir -p "$OUT"
AD=/w/images/banner-softworld.jpg

# 遊戲畫面在 1280×800 擷取畫面裡的位置(實測)
CROP="crop=640:456:480:304"
SCALE="scale=1280:912:flags=neighbor"

# ---------- 版面元件 ----------
bg() {  # $1 out —— 深木色徑向漸層 + 細黃銅框
  convert -size ${W}x${H} "radial-gradient:${BG_LITE}-${BG_DEEP}" \
    -fill none -stroke "$ACCENT_DK" -strokewidth 2 \
    -draw "rectangle 40,40 $((W-40)),$((H-40))" "$1"
}

band() { # $1=fg.png $2=主字幕 $3=次字幕 —— 底部木牌字幕條
  convert -size ${W}x${H} xc:none \
    -fill "#1a0c06e0" -draw "rectangle 0,$((H-148)) ${W},${H}" \
    -fill "$ACCENT" -draw "rectangle 0,$((H-150)) ${W},$((H-146))" \
    -font "$FONT_TITLE" -pointsize 46 -fill "$TEXT" -gravity south -annotate +0+78 "$2" \
    -font "$FONT_BODY"  -pointsize 27 -fill "$DIM"  -gravity south -annotate +0+34  "$3" "$1"
}

# ---------- 段落產生器 ----------
still() { # $1 png $2 secs $3 out.mp4
  local fo; fo=$(awk "BEGIN{print $2-0.4}")
  ffmpeg -y -loglevel error -loop 1 -i "$1" -t "$2" -r $FPS \
    -vf "fade=t=in:st=0:d=0.4,fade=t=out:st=$fo:d=0.4,format=yuv420p" \
    -threads 2 -c:v libx264 -preset veryfast -pix_fmt yuv420p "$3"
}

live() { # $1 raw.mkv $2 起點秒 $3 長度 $4 fg.png $5 out.mp4 [$6 額外overlay.png(貼在遊戲畫面上)]
  local fo extra=""; fo=$(awk "BEGIN{print $3-0.4}")
  if [ -n "${6:-}" ]; then
    extra="[b][3:v]overlay=${GX}:${GY}[c];"
    ffmpeg -y -loglevel error -loop 1 -i "$T/bg.png" -ss "$2" -t "$3" -i "$1" -i "$4" -i "$6" \
      -filter_complex "[1:v]${CROP},${SCALE},setpts=PTS-STARTPTS[g];[0:v][g]overlay=${GX}:${GY}[b];${extra}[c][2:v]overlay=0:0,fade=t=in:st=0:d=0.4,fade=t=out:st=$fo:d=0.4,format=yuv420p[o]" \
      -map "[o]" -t "$3" -r $FPS -threads 2 -c:v libx264 -preset veryfast -pix_fmt yuv420p "$5"
  else
    ffmpeg -y -loglevel error -loop 1 -i "$T/bg.png" -ss "$2" -t "$3" -i "$1" -i "$4" \
      -filter_complex "[1:v]${CROP},${SCALE},setpts=PTS-STARTPTS[g];[0:v][g]overlay=${GX}:${GY}[b];[b][2:v]overlay=0:0,fade=t=in:st=0:d=0.4,fade=t=out:st=$fo:d=0.4,format=yuv420p[o]" \
      -map "[o]" -t "$3" -r $FPS -threads 2 -c:v libx264 -preset veryfast -pix_fmt yuv420p "$5"
  fi
}

echo ">> 背景"
bg "$T/bg.png"

echo ">> 廣告素材"
# 廣告四格截圖在原掃描上的位置(實測):1=酒吧 2=老媽餐館 3=雜貨店 4=服飾店
# 取與遊戲畫面同比例(640:400)的中央區域,縮放到 1280×800 後只留左半 → 做前後對照的直立分割
adhalf() { # $1 廣告裁切區 $2 out.png
  convert "$AD" -crop "$1" +repage -resize 1280x912! -crop 640x912+0+0 +repage "$2"
}
adhalf "330x206+100+582"  "$T/ad_saloon_L.png"
adhalf "330x206+100+825"  "$T/ad_cafe_L.png"

# 廣告全幅(第 2 段)—— 左圖右文,標題不壓在廣告上
convert "$T/bg.png" \( "$AD" -resize x950 -bordercolor "$ACCENT_DK" -border 2 \) \
  -gravity west -geometry +170+0 -composite "$T/seg02_base.png"
convert "$T/seg02_base.png" \
  -font "$FONT_TITLE" -pointsize 48 -fill "$ACCENT_DK" -annotate +953+303 "一齣充滿歡樂爆笑的西部鬧劇！" \
  -font "$FONT_TITLE" -pointsize 48 -fill "$ACCENT"    -annotate +950+300 "一齣充滿歡樂爆笑的西部鬧劇！" \
  -font "$FONT_TITLE" -pointsize 48 -fill "$ACCENT_DK" -annotate +953+383 "一個富有傳奇色彩的西部人物！" \
  -font "$FONT_TITLE" -pointsize 48 -fill "$ACCENT"    -annotate +950+380 "一個富有傳奇色彩的西部人物！" \
  -font "$FONT_BODY" -pointsize 34 -fill "$TEXT" \
  -annotate +950+510 "台灣當年以《多情藥師酷牛仔》的譯名上市，" \
  -annotate +950+565 "《軟體世界》刊過整頁彩色廣告，還連載了兩期攻略。" \
  -font "$FONT_BODY" -pointsize 44 -fill "$DIM" \
  -annotate +950+700 "那個年代，它沒有中文版。" \
  -font "$FONT_BODY" -pointsize 26 -fill "$DIM" \
  -annotate +950+820 "圖片來源：《軟體世界》雜誌廣告" "$T/seg02.png"

echo ">> 前景文字層"
# 1. 冷開場對照(分割線 + 左右標)
cmp_fg() { # $1 out $2 左標 $3 右標 $4 額外大字(可空)
  # 標籤要壓深色底條:遊戲畫面與廣告掃描都偏亮,白字直接壓上去讀不到。
  convert -size ${W}x${H} xc:none \
    -fill "#1a0c06cc" -draw "rectangle ${GX},${GY} $((GX+1280)),$((GY+52))" \
    -fill "$ACCENT" -draw "rectangle $((GX+638)),${GY} $((GX+642)),$((GY+912))" \
    -font "$FONT_BODY" -pointsize 32 -fill "$DIM"  -annotate +$((GX+28))+$((GY+36)) "$2" \
    -font "$FONT_BODY" -pointsize 32 -fill "$TEXT" -annotate +$((GX+668))+$((GY+36)) "$3" "$1"
  if [ -n "${4:-}" ]; then
    convert "$1" -fill "#1a0c06e6" -draw "rectangle 0,$((H-148)) ${W},${H}" \
      -font "$FONT_TITLE" -pointsize 54 -fill "$ACCENT" -gravity south -annotate +0+62 "$4" \
      -font "$FONT_BODY" -pointsize 26 -fill "$DIM" -gravity south -annotate +0+26 \
      "Freddy Pharkas: Frontier Pharmacist ・ 1993 Sierra On-Line" "$1"
  fi
}
cmp_fg "$T/fg01a.png" "1993 年的廣告" "今天的繁體中文版" ""
cmp_fg "$T/fg01b.png" "1993 年的廣告" "今天的繁體中文版" "多情藥師酷牛仔 ・ 繁體中文化"
cmp_fg "$T/fg06.png"  "1993 年的廣告" "今天的繁體中文版" ""

band "$T/fg03.png" "西部最快的槍手，被一槍打掉右耳之後" "他發誓不再碰槍，改行當了藥劑師。鎮上沒人知道他的過去。"
band "$T/fg04.png" "然後，粗金鎮開始出事" "水被動了手腳、馬集體脹氣、蝸牛大舉搬家，還有一場大火。"
band "$T/fg07.png" "選單、按鈕、說明，全是中文" "載入・序幕・開始・說明・離開——連標題選單都翻了"
band "$T/fg08.png" "解謎核心在配藥" "查手冊、對劑量、照步驟做——沒有手冊過不了關。"
band "$T/fg09.png" "按 F8 隨時切回英文原文" "想看原文的雙關怎麼寫，按一下就好。"

# 5. 大引號對白卡(和其他版面明顯不同的視覺;使用者特別喜歡「馬脹氣」這條線)
convert "$T/bg.png" \
  -font "$FONT_TITLE" -pointsize 260 -fill "#d6ae3138" -annotate +150+400 "「" \
  -font "$FONT_TITLE" -pointsize 260 -fill "#d6ae3138" -annotate +1600+820 "」" \
  -font "$FONT_BODY" -pointsize 62 -fill "$TEXT" \
  -annotate +320+460 "不知是誰家可憐的馬，" \
  -annotate +320+550 "正在排放大量刺鼻的甲烷氣體。" \
  -font "$FONT_BODY" -pointsize 32 -fill "$DIM" \
  -annotate +320+645 "Somebody's poor horse seems to be dispelling" \
  -annotate +320+690 "huge quantities of a noxious methane compound." \
  -font "$FONT_BODY" -pointsize 32 -fill "$ACCENT" -gravity south -annotate +0+110 \
  "旁白比主角本人還嘴賤——這種句子，全遊戲有五千多則" "$T/seg05.png"

# 10. 成果卡
convert "$T/bg.png" \
  -font "$FONT_TITLE" -pointsize 72 -fill "$ACCENT_DK" -gravity north -annotate +3+203 "整套都是中文的" \
  -font "$FONT_TITLE" -pointsize 72 -fill "$ACCENT"    -gravity north -annotate +0+200 "整套都是中文的" \
  -font "$FONT_BODY" -pointsize 52 -fill "$TEXT" -gravity north \
  -annotate +0+390 "5,166 / 5,181 則文字　（99.7%）" \
  -annotate +0+480 "倚天點陣字 2,889 字　・　畫布 640×400" \
  -annotate +0+570 "對白　旁白　道具欄　選單　藥品名　片頭片尾　結局" \
  -font "$FONT_BODY" -pointsize 46 -fill "$DIM" -gravity north \
  -annotate +0+730 "Linux　・　Windows　・　macOS" \
  "$T/seg10.png"

# 11. 片尾卡
convert "$T/bg.png" \
  -font "$FONT_TITLE" -pointsize 88 -fill "$ACCENT_DK" -gravity north -annotate +3+283 "多情藥師酷牛仔" \
  -font "$FONT_TITLE" -pointsize 88 -fill "$ACCENT"    -gravity north -annotate +0+280 "多情藥師酷牛仔" \
  -font "$FONT_BODY" -pointsize 42 -fill "$TEXT" -gravity north -annotate +0+420 \
  "Freddy Pharkas: Frontier Pharmacist　繁體中文化" \
  -font "$FONT_BODY" -pointsize 34 -fill "$TEXT" -gravity north \
  -annotate +0+600 "致敬 Al Lowe、Josh Mandel，以及三十年來把這些遊戲留下來的 ScummVM 團隊" \
  -font "$FONT_BODY" -pointsize 30 -fill "$DIM" -gravity north \
  -annotate +0+700 "廣告圖出自《軟體世界》　・　遊戲版權屬 Sierra On-Line／Activision" \
  -annotate +0+760 "配樂為原版遊戲音樂（Roland MT-32）　・　本片僅供個人保存，不公開散布" \
  "$T/seg11.png"

echo ">> 逐段算繪"
#      段  來源                     起點  長度  前景         額外疊圖
live "$SRC/raw_s02_saloon.mkv"  3.0  4.0 "$T/fg01b.png" "$T/p1.mp4" "$T/ad_saloon_L.png"
still "$T/seg02.png"            5.0      "$T/p2.mp4"
live "$SRC/raw_s03_talk.mkv"    4.0  6.0 "$T/fg03.png"  "$T/p3.mp4"
live "$SRC/raw_s04_street.mkv"  4.0  5.0 "$T/fg04.png"  "$T/p4.mp4"
still "$T/seg05.png"            5.0      "$T/p5.mp4"
live "$SRC/raw_s09_cafe.mkv"    4.0  6.0 "$T/fg06.png"  "$T/p6.mp4" "$T/ad_cafe_L.png"
live "$SRC/raw_s10_menu.mkv"    2.0  6.0 "$T/fg07.png"  "$T/p7.mp4"
live "$SRC/raw_s07_counter.mkv" 3.0  7.0 "$T/fg08.png"  "$T/p8.mp4"
live "$SRC/raw_s08_f8.mkv"      5.0  7.0 "$T/fg09.png"  "$T/p9.mp4"
still "$T/seg10.png"            6.0      "$T/p10.mp4"
still "$T/seg11.png"            5.0      "$T/p11.mp4"

echo ">> 串接"
: > "$T/list.txt"
for f in p1 p2 p3 p4 p5 p6 p7 p8 p9 p10 p11; do echo "file '$T/$f.mp4'" >> "$T/list.txt"; done
ffmpeg -y -loglevel error -f concat -safe 0 -i "$T/list.txt" -threads 2 \
  -c:v libx264 -preset veryfast -pix_fmt yuv420p "$T/silent.mp4"

DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$T/silent.mp4")
FO=$(awk "BEGIN{print $DUR-3}")
echo ">> 影片長度 ${DUR}s,鋪配樂"
# [HARD] 先 aloop 無限循環再 atrim 到影片長度,不要 -shortest(見 kb 雷:結尾卡會被砍)
ffmpeg -y -loglevel error -i "$T/silent.mp4" -i "$SRC/music/bgm.wav" \
  -filter_complex "[1:a]aloop=loop=-1:size=2000000000,atrim=0:$DUR,afade=t=in:st=0:d=2,afade=t=out:st=$FO:d=3[a]" \
  -map 0:v -map "[a]" -threads 2 -c:v libx264 -preset veryfast -pix_fmt yuv420p \
  -c:a aac -b:a 192k -movflags +faststart "$OUT/freddy-cht-promo.mp4"

echo "== 完成 =="
ffprobe -v error -select_streams v -show_entries stream=width,height,avg_frame_rate:format=duration -of default=nw=1 "$OUT/freddy-cht-promo.mp4"
ffprobe -v error -select_streams a -show_entries stream=codec_name -of csv=p=0 "$OUT/freddy-cht-promo.mp4"
