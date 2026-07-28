#!/bin/bash
# 把 GitHub Actions CI 建好的 macOS ScummVM.app(engine-only)在本機注入
# 遊戲資源 + 中文資料 + MT-32 ROM + 啟動包裝,做成「完整包」。
#
# 為什麼 macOS 完整包不是 CI 產的:.app 只能在 macOS host build(codesign/hdiutil
# 都是 macOS 限定),但 CI 拿不到遊戲本體與 ROM(兩者都不在公開 repo)。所以
# 引擎在 CI 建、遊戲與 ROM 在本機注入。產物含遊戲/ROM → 只放本機 dist-all/,不散布。
#
# 前提:先從 CI artifact 下載 engine-only tar.gz
#   gh run download <run-id> --name freddy-pharkas-cht-macos --dir dist-macos/dl
# 用法:package_macos_full.sh <ci-tar.gz> [game-dir] [mt32-rom-dir]
#
# [HARD] 改動已簽名的 .app 會讓簽章失效 → 這裡直接移除 _CodeSignature(變「未簽」
#   勝過「壞簽」),另附「修復-macOS.command」讓玩家在 Mac 上去隔離 + ad-hoc 重簽。
#   Linux 端無法代簽也無法實測,**整包要請使用者在 Mac 上跑一次修復腳本再開 app 確認**。
set -e
CI_TAR="${1:?用法: package_macos_full.sh <ci-tar.gz> [game-dir] [rom-dir]}"
ROOT="/home/anr2/scummvm/Freddy_Pharkas/workplace"
GAME_SRC="${2:-$ROOT/game}"
ROM_SRC="${3:-/home/anr2/cht/mt32}"
OUT="$ROOT/dist-all"
WORK="$(mktemp -d)"; APP="$WORK/ScummVM.app"

tar xzf "$CI_TAR" -C "$WORK"
[ -d "$APP" ] || { echo "!! CI tar 內找不到 ScummVM.app" >&2; exit 1; }

echo ">> 1) 統一 game 夾:遊戲資源 + 中文資料(game/ 已含 translation.tsv 與兩個 .fnt)"
GAME="$APP/Contents/Resources/game"; mkdir -p "$GAME"
cp "$GAME_SRC"/resource.* "$GAME/" 2>/dev/null || cp "$GAME_SRC"/RESOURCE.* "$GAME/"
cp "$GAME_SRC"/*.map "$GAME/" 2>/dev/null || true
cp "$GAME_SRC"/*.drv "$GAME/" 2>/dev/null || true
cp "$GAME_SRC"/translation.tsv "$GAME_SRC"/freddy_big5.fnt "$GAME_SRC"/freddy_big5_hi.fnt "$GAME/"
# CI 版把中文資料放在 Resources/cht-data,完整包統一改由 game 夾提供,移掉免混淆
rm -rf "$APP/Contents/Resources/cht-data"

echo ">> 2) MT-32 ROM(正名;完整包專用,不散布)"
if [ -f "$ROM_SRC/MT32_PCM.ROM" ]; then
  CTRL="$(ls "$ROM_SRC"/MT32_CONTROL.1987*.ROM "$ROM_SRC"/MT32_CONTROL*.ROM 2>/dev/null | head -1)"
  cp "$CTRL" "$GAME/MT32_CONTROL.ROM"
  cp "$ROM_SRC/MT32_PCM.ROM" "$GAME/MT32_PCM.ROM"
  MT32_ARG='--music-driver=mt32 '
  echo "   放入 $(basename "$CTRL") → MT32_CONTROL.ROM"
else
  MT32_ARG=''
  echo "   (找不到 ROM,略過;不設 mt32 預設,免玩家吃到一次錯誤框)"
fi

echo ">> 3) 啟動包裝:原 binary 改名,CFBundleExecutable 位置換成 bash wrapper"
# wrapper 與 scummvm.bin 同在 MacOS/,所以 @executable_path/../Frameworks 的 SDL2 rpath 仍解析得到
# [HARD] SCI 的中文開關讀的是 **target 設定裡的 language=tw**,不吃命令列的 --language,
# 所以這裡跟 Linux/Windows 啟動器一樣自己寫一份 ini 再指定 target,不用 --auto-detect。
MT32_INI=""
[ -n "$MT32_ARG" ] && MT32_INI="music_driver=mt32"
mv "$APP/Contents/MacOS/scummvm" "$APP/Contents/MacOS/scummvm.bin"
cat > "$APP/Contents/MacOS/scummvm" <<WRAP
#!/bin/bash
DIR="\$(cd "\$(dirname "\$0")" && pwd)"; GAME="\$DIR/../Resources/game"
CFGDIR="\$HOME/Library/Application Support/FreddyPharkas-CHT"; CFG="\$CFGDIR/scummvm.ini"
mkdir -p "\$CFGDIR"
cat > "\$CFG" <<CFGEOF
[scummvm]

[freddypharkas]
engineid=sci
gameid=freddypharkas
description=多情藥師酷牛仔（繁體中文・完整版）
path=\$GAME
extrapath=\$GAME
language=tw
subtitles=true
speech_mute=false
${MT32_INI}
CFGEOF
exec "\$DIR/scummvm.bin" --config="\$CFG" freddypharkas "\$@"
WRAP
chmod +x "$APP/Contents/MacOS/scummvm" "$APP/Contents/MacOS/scummvm.bin"

echo ">> 4) 移除失效簽章(改成未簽,配修復腳本)"
rm -rf "$APP/Contents/_CodeSignature"

echo ">> 5) 修復腳本 + 說明"
cat > "$WORK/修復-macOS.command" <<'FIX'
#!/bin/bash
cd "$(dirname "$0")"; echo "處理中…"
xattr -cr ScummVM.app 2>/dev/null
codesign --force --deep --sign - ScummVM.app 2>/dev/null && echo "已重簽。" || echo "（codesign 略過）"
echo "完成！雙擊 ScummVM.app 開始玩《多情藥師酷牛仔》。"
read -n1 -p "按任意鍵關閉…"
FIX
chmod +x "$WORK/修復-macOS.command"
cat > "$APP/Contents/Resources/README-cht.txt" <<'RM'
多情藥師酷牛仔（Freddy Pharkas: Frontier Pharmacist）— 繁體中文化 macOS 完整包

內含遊戲資源、中文對白與字型、MT-32 ROM，開箱即玩，不必自己指路徑。

【首次使用】
先雙擊「修復-macOS.command」（去掉隔離屬性並重新 ad-hoc 簽章），再雙擊 ScummVM.app。
這一步是必要的：包在 Linux 上組裝，動過 .app 內容之後原本的簽章就失效了。

【音效】預設走 Roland MT-32（Munt 模擬），音色遠勝 AdLib。
RM

echo ">> 6) 打包"
mkdir -p "$OUT"
( cd "$WORK" && tar czf "$OUT/FreddyPharkas-CHT-macos-universal-full.tar.gz" "ScummVM.app" "修復-macOS.command" )
echo "完成 → $OUT/FreddyPharkas-CHT-macos-universal-full.tar.gz ($(du -h "$OUT/FreddyPharkas-CHT-macos-universal-full.tar.gz" | cut -f1))"
rm -rf "$WORK"
