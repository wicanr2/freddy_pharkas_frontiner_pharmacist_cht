#!/usr/bin/env python3
"""驗證批次譯文檔(translation/done/*.tsv)是否可安全併入。

檢查項目
  1. 結構:每行剛好一個 TAB、第二欄非空。
  2. key 保真:第一欄必須逐字對得上對應的 batch_src 檔(同行同序)。
  3. 控制序列:`%s/%d/%x/\\n` 等規格序列——譯文的規格序列必須是原文的
     **子序列**;且若序列不同、譯文又含 `%s`,引擎的 kFormat 重映射會退回英文
     (見 kstring.cpp sciChtMapFormatSpecs 的 SAFETY 註),視為錯誤。
  4. Big5:譯文每個字都要能編成 Big5(引擎的 runtime tsv 是 Big5)。
  5. 未翻:第二欄與第一欄完全相同、且原文含英文字母 → 漏翻。
  6. 統一譯名:命中譯名表的原文,譯文必須含指定譯名。
  7. 長度:中文顯示寬 vs 英文字元數,超過 1.6 倍列為警告(不擋)。

用法:validate_translations.py [檔案...]   (預設掃 translation/done/*.tsv)
     --strict 讓警告也算失敗。
"""
import sys, os, re, glob, argparse, unicodedata

SPEC = re.compile(r"%[-0-9.=]*([a-zA-Z])")

# 原文含 key(小寫比對) → 譯文必須含其中之一
GLOSSARY = {
    "coarsegold": ["粗金鎮"],
    "freddy": ["佛萊迪"],
    "pharkas": ["法卡斯", "佛萊迪"],
    "penelope": ["潘妮洛普"],
    "srini": ["斯里尼"],
    "hop singh": ["阿星"],
    "madame ovaree": ["歐薇莉"],
    "whittlin' willy": ["削木威利"],
    "kenny the kid": ["小鬼肯尼"],
}


# 這些是 SCI 內部/開發工具字串,玩家看不到,原樣不翻是對的
PASSTHROUGH = re.compile(
    r"^(?:\[control \$%x\]|%[ds]\.\w+|%d\.\w+|QA-COMMENT%d|totAngle.*"
    r"|Error in \(%s check:\)|\w+\.(?:pol|mem|log|scr|sc|hep))$")


# 演職員表的真人姓名維持拉丁字母(業界慣例,不音譯)
PERSON = re.compile(
    r"^(?:[A-Z][A-Za-z.'\-]*|\"[A-Za-z .'\-]+\"|[A-Z]\.)"
    r"(?: (?:[A-Z][A-Za-z.'\-]*|\"[A-Za-z .'\-]+\"|[A-Z]\.|Jr\.|Sr\.|II|III)){1,3}$")


def passthrough_ok(en):
    t = en.strip()
    if PASSTHROUGH.match(t) or PERSON.match(t):
        return True
    # 去掉 printf 規格後幾乎沒有英文字 → 純格式字串
    return len(re.sub(r"%[-0-9.]*[a-zA-Z]", "", t).strip()) < 3


def specs(s):
    return "".join(SPEC.findall(s)) + "".join(re.findall(r"\\[nrt]", s))


def is_subseq(sub, sup):
    it = iter(sup)
    return all(c in it for c in sub)


def dispwidth(s):
    return sum(2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in s)


def check(path, strict=False):
    name = os.path.basename(path)
    src = os.path.join("translation/batch_src", name)
    errs, warns = [], []
    rows = []
    with open(path, encoding="utf-8") as f:
        for i, line in enumerate(f, 1):
            line = line.rstrip("\n")
            if not line or line.lstrip().startswith("#"):
                continue
            if line.count("\t") != 1:
                errs.append(f"{name}:{i} TAB 數不是 1")
                continue
            en, zh = line.split("\t")
            if not zh.strip():
                errs.append(f"{name}:{i} 譯文空白")
            rows.append((i, en, zh))

    if os.path.exists(src):
        srckeys = [l.rstrip("\n").split("\t")[0]
                   for l in open(src, encoding="utf-8") if "\t" in l]
        if len(srckeys) != len(rows):
            errs.append(f"{name}: 行數 {len(rows)} != 原檔 {len(srckeys)}")
        for (i, en, _), k in zip(rows, srckeys):
            if en != k:
                errs.append(f"{name}:{i} key 被改動\n    原: {k[:70]!r}\n    現: {en[:70]!r}")

    for i, en, zh in rows:
        se, sz = specs(en), specs(zh)
        if sz != se:
            if not is_subseq(sz, se):
                errs.append(f"{name}:{i} 控制序列不是原文子序列 {se!r} → {sz!r}")
            elif "s" in sz:
                errs.append(f"{name}:{i} 規格數不同又含 %s(引擎會退回英文) {se!r} → {sz!r}")
        try:
            zh.encode("big5")
        except UnicodeEncodeError as e:
            bad = zh[e.start:e.end]
            errs.append(f"{name}:{i} 非 Big5 字元 {bad!r} @ {zh[:40]!r}")
        if zh == en and re.search(r"[A-Za-z]{2,}", en) and not passthrough_ok(en):
            errs.append(f"{name}:{i} 未翻譯: {en[:60]!r}")
        low = en.lower()
        for k, musts in GLOSSARY.items():
            if k in low and not any(m in zh for m in musts):
                warns.append(f"{name}:{i} 譯名可能不一致({k}): {zh[:50]!r}")
        if len(en) >= 20 and dispwidth(zh) > len(en) * 1.6:
            warns.append(f"{name}:{i} 譯文偏長 {dispwidth(zh)} vs {len(en)}")

    return len(rows), errs, warns


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="*")
    ap.add_argument("--strict", action="store_true")
    ap.add_argument("--quiet-warn", action="store_true")
    a = ap.parse_args()
    files = a.files or sorted(glob.glob("translation/done/*.tsv"))
    tot = nerr = nwarn = 0
    for p in files:
        n, errs, warns = check(p, a.strict)
        tot += n
        nerr += len(errs)
        nwarn += len(warns)
        for e in errs:
            print("✗", e)
        if not a.quiet_warn:
            for w in warns[:8]:
                print("⚠", w)
    print(f"\n== 檢查 {len(files)} 檔 / {tot} 行:錯誤 {nerr}、警告 {nwarn} ==")
    return 1 if nerr or (a.strict and nwarn) else 0


if __name__ == "__main__":
    sys.exit(main())
