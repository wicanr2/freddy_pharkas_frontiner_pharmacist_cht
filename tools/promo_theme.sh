#!/usr/bin/env bash
# 這部片專屬的設計 token。
#
# [HARD] 不要沿用其他專案的配色(kb game-promo-video-ffmpeg「每片一個 theme」)。
# 底下每個顏色都是從《多情藥師酷牛仔》自己的實機畫面用 histogram 萃取出來的:
#   convert shot.png -resize 100x100! -colors 6 -format %c histogram:info:- | sort -rn
# 藥局/街景/酒吧三個場景的主色一致落在「深木色 → 陶土色 → 沙色」這條線上,
# 而 accent 直接取標題畫面 FREDDY PHARKAS logo 的招牌黃 #d6ae31。
THEME_NAME="西部藥房的木頭與黃銅"

BG_DEEP='#241109'   # 深木(由場景最暗的 #4F3E36 再壓深)
BG_LITE='#5e4131'   # 中木(標題畫面 dominant)
ACCENT='#d6ae31'    # 招牌黃(遊戲 logo 原色)
ACCENT_DK='#8a6b17' # 招牌黃的陰影,做浮雕
TEXT='#f2e6d0'      # 暖米白
DIM='#a06653'       # 陶土色,次要文字

FONT_TITLE=/usr/share/fonts/opentype/noto/NotoSerifCJK-Bold.ttc
FONT_BODY=/usr/share/fonts/opentype/noto/NotoSerifCJK-Regular.ttc

W=1920; H=1080; FPS=30
GX=320; GY=100          # 遊戲畫面(2× → 1280×800)在 1920×1080 上的位置
