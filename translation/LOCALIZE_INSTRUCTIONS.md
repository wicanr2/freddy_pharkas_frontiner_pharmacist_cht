# 《多情藥師酷牛仔》繁中在地化指令

每個翻譯 subagent 動手前先完整讀這份，全程照辦。目標不是「看得懂」，是「台灣玩家會心一笑」。

## 這款遊戲是什麼

Sierra 1993 年的西部喜劇 *Freddy Pharkas: Frontier Pharmacist*，Al Lowe（《Leisure Suit Larry》作者）
與 Josh Mandel 合寫。主角 Freddy Pharkas 是加州小鎮 Coarsegold 的藥劑師，年輕時是快槍手，
一場意外炸掉一隻耳朵後金盆洗手，改行賣藥。全片充滿雙關、諧音、爛笑話與西部片戲仿。

當年台灣以《多情藥師酷牛仔》之名代理，軟體世界雜誌 61/62 期刊過攻略。

## 風格定位

> **笑在雙關與自嘲，台味中度提味，西部腔用「老派江湖味」而非鄉土劇腔。**

- **台味濃度＝中度提味**：口語國語為主，情緒點插少量台語詞（歹勢、衝、款、衰、齁、凍未條、
  哪ㄟ按呢）。**不要整句台語**、不要刻意堆疊。
- **色色尺度＝乾淨**：本作比 LSL 收斂得多（當年廣告寫「沒有色情渲染，只有歡笑不斷」）。
  雙關保留（如 Madame Ovaree 的妓院、Testosterate 壯陽藥），但**字面乾淨、靠聯想**。
- **西部腔**：牛仔講話用「俺、咱、老兄、這位客倌、要得、成」這類老派江湖味，
  避免「你他媽」等現代粗口，也避免歌仔戲腔。
- **旁白（Narrator）**：本作旁白很賤很會吐槽，可放開用綜藝吐槽腔、報紙社會版標題腔。

## 硬規則（違反會壞遊戲）

1. **第一欄英文原文一字不改**（含大小寫、標點、前後空格）——那是遊戲查表的 key。
2. **控制序列原樣保留**、位置與數量都要對：`%s` `%d` `%3d` `\n` `\r` 以及任何 `%` 開頭的東西。
   中文規格數**不可多於**英文。
3. **長度控制在英文的 ±30%**（中文字算 2 個英文字元寬）。**UI 按鈕/道具名要更短**：
   按鈕框寬度是照英文字寬算的，中文太長會壓到隔壁按鈕（已實測：`Play` 只能放「開始」不能放「開始遊戲」）。
4. **繁體中文，且必須是 Big5 打得出來的字**。避免：𨑨迌、啧、腚、咔、銹、é、・、emoji、
   簡體字、日文漢字（込、駅）。標點用全形（，。！？「」……），**不要半形逗號句號**。
   - **人名中間點一律用 `·`（U+00B7）**，例如「佛萊迪·法卡斯」。
     **不要用 `‧`（U+2027）或 `・`（U+30FB）——這兩個不在 Big5 裡。**
   - 波浪號用 `∼`（U+223C），不要用 `～`／`〜`；刪節號用 `…`，不要用 `⋯`。
5. **功能句別硬塞梗**：存讀檔提示、錯誤訊息、操作說明照實翻，清楚優先。
6. **玩家要打字輸入的字串不翻**（本作是點選式，理論上沒有，遇到就留原文並回報）。
7. **藥品/化學品名照手冊翻**（見下方對照表）——這些是解謎關鍵，玩家要跟手冊配方對照。

## 統一譯名表（**一律照抄，不要自己另譯**）

### 人物
| 原文 | 譯名 | 備註 |
|---|---|---|
| Freddy Pharkas / Frederick | 佛萊迪·法卡斯／佛萊迪 | 正式場合用全名，平常「佛萊迪」 |
| Srini (Lalkakalaka) | 斯里尼 | 印度裔藥局助手 |
| Penelope Primm | 潘妮洛普 | 女主角，學校老師 |
| Hop Singh | 阿星 | 中國廚子，別譯成「合星」 |
| Madame Ovaree | 歐薇莉夫人 | 妓院老闆娘（ovary 諧音，中文不強求還原） |
| Sheriff (Hodge) | 警長 | |
| Whittlin' Willy | 削木威利 | 老在削木頭的老頭 |
| Kenny the Kid | 小鬼肯尼 | |
| Sam (the bartender) | 山姆 | 酒保 |
| Sal | 阿薩 | |
| Chester | 切斯特 | |
| Smithie | 鐵匠史密 | 鐵匠 |
| Helen Steele | 海倫 | |
| Doc | 大夫 | 醫生 |
| Mom | 老媽 | Mom's Cafe 的老闆娘 |
| Trixie | 翠西 | 鎮上的羊 |
| Rover | 阿旺 | 鎮上的狗 |
| Duck Gillespie | 鴨子吉勒斯比 | |
| Ol' Pickaxe Pete | 鶴嘴鋤老皮 | |
| Carrie Sue | 凱莉蘇 | |

### 地名
| 原文 | 譯名 |
|---|---|
| Coarsegold | 粗金鎮 |
| Main Street | 大街 |
| Mom's Cafe | 老媽餐館 |
| Pharmacy | 藥局 |
| Saloon | 酒館 |
| Assay Office | 驗金所 |
| Livery Stable | 馬廄 |
| Jail | 牢房 |
| Cliff / The Cliffs | 懸崖 |

### 藥品與化學品（**照手冊，解謎關鍵，不可自由發揮**）
| 原文 | 譯名 |
|---|---|
| Aminophyllic Citrate | 檸檬酸胺非林 |
| Bisalicylate Antitoxidene | 雙水楊酸抗毒素 |
| Estrosterane | 雌固烷 |
| Testosterate | 睪固酯 |
| Peptic-Lymacine Tetrazole | 胃淋四唑 |
| Tyloxypolynide | 泰洛西聚醯胺 |
| Sodium Bicarbonate | 碳酸氫鈉 |
| Magnesium Sulfate | 硫酸鎂 |
| Bismuth Subsalicylate | 次水楊酸鉍 |
| Furachlordone | 弗氯酮 |
| Orphenamethihydride | 鄰甲氫化物 |
| mortar and pestle | 研缽與杵 |
| beaker | 燒杯 |
| test tube | 試管 |
| prescription / Rx | 處方箋 |

## 手法範例（照這個調性）

| 原文 | ✗ 直譯 | ✓ 在地化 |
|---|---|---|
| That's just another bit of authentic Western scenery. | 那只是另一個真正的西部風景。 | 那不過是道地西部風景的一部分罷了。 |
| You can't walk there; at least, not thisaway. | 你不能走那裡，至少不是這條路。 | 你走不過去；至少，不是走這條路。 |
| Nice shootin', Tex! | 好射擊，德州人！ | 好槍法啊，老兄！ |
| I'm no gossip, Freddy Pharkas, and I've got work to do. | 我不是八卦者… | 我可不是那種愛嚼舌根的人，佛萊迪，我還有活要幹呢。 |

## 產出格式

- 每行：`英文原文<TAB>繁中譯文`，UTF-8，不加標題列、不加註解、不加程式碼圍欄。
- **行數與輸入完全一致，順序一致**。
- 有疑慮的行照樣翻，另外在**檔案最後**用 `# NOTE:` 開頭的行說明（會被 merge 工具忽略）。
