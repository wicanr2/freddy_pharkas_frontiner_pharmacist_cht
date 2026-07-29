# 《多情藥師酷牛仔》繁中化：這一代新踩到的雷

SCI1.1 VGA + CD talkie 是這個系列前幾代沒做過的組合，以下是這次才第一次遇到、
值得回填到 `CLAUDE-Scummvm-Template.md` 的東西。已經寫在模板裡的通則不重複。

## 1. SCI1.1 的 script 字串住在 heap，不在 script

SCI0 要從 `script.NNN` 裡剝前導 bytecode 撈字串；SCI1.1 把資料段拆出去了，
`script.NNN` 是純 bytecode，玩家可見的字全在 `heap.NNN`。實測掃過全部 168 個
`script.*` 找 18 字元以上的英文句子，命中 0。所以 SCI1.1 只要掃 heap。

## 2. 抽字工具的「單一識別字」過濾會吃掉道具欄品名

`extract_sci11_strings.py` 對「只有一個 token」的字串預設當識別字丟掉，
只留下有空格或標點的。結果 `Door Key`、`Shot Glass` 這種留下來了，
`Beer`、`Rope`、`Knife`、`Shovel`、`Medallion` 這種**單字道具名全部被吃掉**——
偏偏它們就是道具欄裡玩家一直看著的字。

診斷法：把 `is_display()` 反過來跑一次，列出「被丟掉的候選」，人眼掃一遍。
1,242 個被丟掉的候選裡，絕大多數確實是 `sEnterFrom230`、`bottle3` 這種內部
物件名，但夾著 23 個真正的道具名。**這個反向清單一定要看過一次。**

同一輪還撈回來：`heap.625`（ChemicalObj）的單位字 `pills`／`powders`／`ml`／`gm`，
以及 `%s (%d %s)` 這類調藥數量模板。

## 3. 讓 kFormat 順便翻譯 `%s` 參數，得讓模板「有被翻到」

引擎的邏輯是「模板有翻，才對帶進去的 `%s` 參數也查表」（把風險關進已知字串）。
但如果中文模板長得跟英文一模一樣，`build_cht.py` 會判定 `zh == en` = 未翻譯而丟掉，
模板進不了 runtime 表，參數翻譯就永遠不會啟動。

解法是讓譯文與原文**有意義地不同**：`%s (%d %s)` → `%s（%d %s）`（半形括號改全形）。
規格序列一樣所以重映射是 no-op、安全，同時模板進得了表，`ml` → `毫升` 就會生效。

## 4. 長訊息被遊戲腳本切段顯示 → 整句查表必然 miss

這一代最花時間的問題。訊息資源裡是一整段 null 終止的長字串，但 `Narrator`／`Talker`
腳本會把它切成好幾個視窗分次顯示，切點落在句末標點。引擎的內容比對只看到片段，
整句查表 100% miss，實機就露出英文。

判斷是不是這個問題：開 `SCI_CHT_DEBUG=1`，看 `CHT-MISS` 印出來的字串是不是
某則已翻譯原文的**一段連續句子**。是的話就是它。

修法是 `sci.cpp` 的 `chtChunkFallback()`：miss 時掃譯表找出哪一則原文含有這段
連續句子，回傳對應的中文句段。兩個必要條件：
- **中英句數必須相同**才敢對應，不然句段對不起來會配出完全不相干的中文。
  對不上就放棄、露原文。
- 斷句要跳過 Big5 雙位元組字的尾位元組，否則 trail byte 會被誤判成標點。
結果（含查無的負結果）進快取，每個字串只掃一次譯表。

## 5. `warning()` 會在訊息尾巴加一個 `!`

`CHT-MISS` 的 log 看起來每條都多一個驚嘆號，`Score: ` 會變成 `Score: !`。
那是 ScummVM `warning()` 的格式，不是字串本身有問題。第一次看會以為抓到怪東西。

## 6. 拒絕優先的 `.gitignore` 會連 `.github/` 一起吃掉

`*` 全忽略、逐項放行的寫法對這種「工作目錄裡混著 600MB 遊戲資源 + ROM + 原始碼樹」
的專案是對的，但漏一條就是整個目錄靜靜消失。這次漏了 `.github/`，結果
「加入 macOS workflow」那個 commit 實際上沒帶到 workflow 檔，
`gh workflow run` 只回 `404 workflow not found on the default branch`——
跟模板裡雷 13 講的「新 repo 首推分支不是預設分支」症狀一模一樣，但成因完全不同。

**先查 `git ls-files .github/`**，比對預設分支還快。

## 7. 半形→全形標點的正規化會誤傷英文段落

譯文常常中英混排（版權宣告、Sierra 的電話地址、遊戲名縮寫）。
「整行有中文就把半形逗號轉全形」會把 `Sierra On-Line, Inc.` 弄成
`Sierra On-Line， Inc.`。判斷條件要看**標點左右緊鄰的字元是不是中文**，
而且要寫**反向修復**（夾在英數之間的全形標點轉回半形），否則第一次跑壞的
已經寫進檔案裡了。

## 8. 統一譯名表自己要先過 Big5

`Furachlordone → 呋氯酮` 的「呋」不在 Big5（只在 Big5-HKSCS）。譯者照表抄，
然後在自己的 `iconv` 驗證卡住，只好各自另譯——分歧就是這樣來的。
**寫譯名表的時候就先把每個字丟去 `encode('big5')` 跑一遍。**
同類：`喹`、`酞`、`萘`、`吲`、`哚`、`肼`、`腈` 都不在 Big5。

## 9. 多 agent 平行翻譯，分歧集中在「表上沒有的專名」

29 個批次各自翻譯，統一譯名表裡有的詞遵守度很好；表上沒有的配角與街名則各譯各的：
Sheriff Shift 有 4 種寫法、Salvatore 3 種、Balance Street 2 種、
Edukashun Street 3 種。

兩個對策：
- 併檔後跑一次「同一專名有幾種中文寫法」的稽核（拿候選變體去譯文裡數次數），
  分歧一眼就看得出來。
- 收斂結果**回填進 `normalize_done.py` 的 `NAME_FIXES`**，之後再併新批次會自動
  收斂，不必再靠人眼。

還有一種只有人眼看得出來的：**譯者寫給校對看的說明混進交付譯文**
（`那是「教育巷」（原文故意拼錯成 Edukashun）。`），機械檢查完全抓不到，
玩家會看到主角自己在講「原文故意拼錯」。

## 10. 存讀檔對話框是 ScummVM 自己的 GUI，不吃遊戲譯文表

按了「載入」跳出來的 `Restore game:`／`Cancel`／`Prev`／`Next` 是 ScummVM 的
`SaveLoadChooser`，跟 `translation.tsv` 無關。試過把 `gui_language` 設成
`zh_TW`／`zh_Hant` 並用 `--themepath` 指到 `translations.dat`（載入成功、
沒有 missing 警告），介面仍是英文——內建 theme 缺 CJK 字型會回退。
這條要當成已知限制寫進 README，不要當成中文化沒做完。

## 11. headless 驅動：固定座標點擊會反覆觸發同一句

原本每個場景點固定四個座標，結果同一句敘述被觸發五次，覆蓋率假高。
改成 5×5 格點掃描之後，同樣四個場景的 `CHT-HIT` 從 59 次跳到 123 次。

另外要用引擎自己的除錯器巡場景（`Ctrl+Alt+D` → `room N` → 再按一次關閉），
比想辦法讓 bot 走完劇情實際得多。

## 12. 推廣片:除錯器主控台要打 `exit` 關,不是再按一次 Ctrl+Alt+D

錄推廣片時整鏡錄到一片黑底綠字——那是 ScummVM 的除錯器主控台蓋在畫面上。
`room N` 其實**早就成功了**(主控台自己印 `Room number changed to 670`),
壞的是關閉那一步:再按一次 `ctrl+alt+d` 常常不生效。

主控台第一行就寫著 `type 'exit' to return to the game`。照做:

```
xdotool key ctrl+alt+d
xdotool type "room $ROOM"; xdotool key Return
xdotool type "exit";       xdotool key Return   # ← 關鍵
xdotool key Escape                              # 第二道保險
```

診斷順序也值得記:先看**錄到的畫面**,再回頭看 log。畫面上有主控台文字 = 沒關掉;
畫面是別的場景 = 真的沒換過去。兩者的修法完全不同,別混。

**中途走過的兩條冤枉路**:先以為是「載入時間浮動,room 指令下太早被起始場景蓋掉」,
所以改成下兩次——沒用,因為指令本來就成功。接著以為是「關掉除錯器後那個 Escape
把特寫場景退回街景」,把 Escape 拿掉——反而更糟,因為 Escape 正是當時唯一有效的關閉方式。
兩次都是在沒看清楚症狀就先猜成因。

## 13. `pgrep -f` 會匹配到自己那行等待指令

想等背景批次跑完再接手,寫了:

```bash
until ! pgrep -f cap_promo_all.sh; do sleep 15; done   # 永遠不會結束
```

這行**自己的命令列就含有 `cap_promo_all.sh`**,`pgrep -f` 比對的是完整命令列,
所以它永遠找得到一個匹配(它自己),迴圈不會結束。同一個坑踩了兩次:第二次是
`pkill -f 'until ! pgrep'`,那行自己也含有 `until ! pgrep`,結果把自己殺掉(exit 144)。

要等背景工作,用檔案存在與否當條件,或直接等 harness 的完成通知,別用 `pgrep -f` 比對
一個會出現在自己命令列裡的字串。

## 14. 擷取用的 ffmpeg 忘了 `-y`,補錄會整批靜靜地沒有產出

`ffmpeg ... out.mkv` 沒有 `-y` 時,如果檔案已存在,它會印
`File 'out.mkv' already exists. Overwrite? [y/N]`,在沒有 tty 的容器裡讀不到回應,
直接 `Not overwriting - exiting`。

這個 bug 有個很惡劣的性質:**第一輪全新錄影一定成功**(檔案不存在),
只有補錄才會失敗,而且失敗訊息被 `| tail -1` 吃掉,看起來就像「跑完了但沒東西」。
我因此往「除錯器沒關」「換場失敗」「Xvfb 掛了」猜了三輪,還進容器看行程列表,
才發現真正的錯誤訊息一直在那裡——只是被 tail 濾掉了。

**教訓**:管線裡的 `| tail -N` 會把錯誤訊息一起丟掉。診斷「跑完但沒產出」時,
第一件事是把過濾拿掉重跑一次,看完整輸出,而不是先猜成因。

## 15. `montage` 對多張 1920×1080 會靜默失敗，改用 `+append` / `-append`

做成品聯絡表時，`montage /t/f_*.png -tile 3x4 ...` **不產檔也不報錯**，只有後續的
`identify` 才說找不到檔案。先縮成 480px、再 `-depth 8` 都無效。

改用逐列 `convert a.png b.png c.png +append row.png`、再 `convert row1 row2 ... -append` 拼，
一次就成功。推測是 ImageMagick 的資源上限（`montage` 會把全部圖同時載入記憶體），
但沒有深究——因為 `+append` 這條路已經夠用。

診斷順序值得記：這次是**先確認 `+append` 可行**、再判定問題出在 `montage`，
而不是先猜「是不是 policy 擋了 / 是不是掛載沒寫入權限」。與第 12、14 則同源
（見 CLAUDE.md ⑩：靜靜失敗先看完整證據，別先猜成因）。
