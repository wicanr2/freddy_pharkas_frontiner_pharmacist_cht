#!/usr/bin/env bash
# 重建《俠盜羅賓漢》繁中化所需的全部 docker image。
# 這些 image 原本複用自 qfg-1 / jones 專案;dev-setup 附上 Dockerfile 讓新機器可獨立重建。
# image 名沿用 build 腳本裡的既定名稱(qfg1-*),不要改名否則 tools/*.sh 找不到。
set -euo pipefail
cd "$(dirname "$0")"

echo "== qfg1-build (SCI 引擎編譯環境: debian12 + SDL2 + zlib/png/... ) =="
docker build -f Dockerfile.build   -t qfg1-build:latest   .

echo "== qfg1-capture (headless 擷取: FROM qfg1-build + xvfb/imagemagick/xdotool) =="
docker build -f Dockerfile.capture -t qfg1-capture:latest .

echo "== qfg1-mingw (Windows x86_64 交叉編譯: mingw-w64 + SDL2 mingw + zlib) =="
docker build -f Dockerfile.mingw   -t qfg1-mingw:latest   .

echo "== qfg1-video (推廣影片: ffmpeg + imagemagick + CJK 字型) =="
docker build -f Dockerfile.video   -t qfg1-video:latest   .

echo "== python:3.12-slim (build_cht.py / 烘字型 / 疊圖, 直接 pull) =="
docker pull python:3.12-slim

echo
echo "全部 image 就緒。驗證:"
docker images --format '{{.Repository}}:{{.Tag}}' | grep -E 'qfg1-(build|capture|mingw|video)|python' | sort -u
