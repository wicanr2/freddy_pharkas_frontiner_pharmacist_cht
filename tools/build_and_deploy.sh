#!/usr/bin/env bash
# 一鍵:merge 批次譯文 → 用倚天點陣字烘 Big5 字型(低解析 16×15 + hi-res 24×24)
#       + 產 runtime translation.tsv → 部署到 game/ 與 dist-cht/。
#
# 引擎常數(engines/sci/graphics/fontchinese.cpp)必須與這裡一致:
#   kBig5Width=12(低解析 advance)、kHiW=24 kHiH=24(hi-res glyph box)
# 字型來源:倚天中文系統 3.53 原生點陣字(tools/assets/eten/),非 TTF rasterize。
set -euo pipefail
WP=/home/anr2/scummvm/Freddy_Pharkas/workplace
cd "$WP"

echo ">> 1) merge 骨架 + 批次譯文 → translation/translation.tsv"
# 用法:merge_translations.py <skeleton> <out> <batch...>
# 順序:batch/*.tsv 在前、pretranslated.tsv 在後 → 同一 key 由 pretranslated 覆蓋
#      (權威 UI/道具譯文優先)。glob 無命中時 nullglob 讓它安靜略過。
shopt -s nullglob
BATCHES=(translation/batch/*.tsv translation/done/*.tsv translation/pretranslated.tsv)
shopt -u nullglob
python3 tools/merge_translations.py \
  translation/full_skeleton.tsv \
  translation/translation.tsv \
  "${BATCHES[@]}"

echo ">> 2) docker 內產 runtime tsv(UTF-8→Big5) + 烘倚天點陣字型"
docker run --rm --name freddy-fontbuild -v "$WP":/w -w /w python:3.12-slim bash -c '
  set -e
  mkdir -p dist-cht
  # runtime translation.tsv(Big5) —— --no-font:字型走倚天點陣,不用 TTF rasterize
  python tools/build_cht.py translation/translation.tsv dist-cht \
    --no-font --corrections translation/corrections.tsv
  # 低解析 16×15 + hi-res 24×24 兩份 Big5 字型(倚天 3.53 原生點陣)
  python tools/build_eten_font.py translation/translation.tsv dist-cht \
    --prefix freddy --corrections translation/corrections.tsv
'

echo ">> 3) 部署到 game/"
cp dist-cht/translation.tsv dist-cht/freddy_big5.fnt dist-cht/freddy_big5_hi.fnt game/

echo "== 部署完成 =="
ls -la game/translation.tsv game/freddy_big5.fnt game/freddy_big5_hi.fnt
