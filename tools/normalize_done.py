#!/usr/bin/env python3
"""就地整理 translation/done/*.tsv 的譯文欄:

  1. 套 corrections.tsv(非 Big5 字元 → Big5 內等義字)。
  2. 套統一譯名(各批 subagent 各自音譯出來的人名收斂成一種寫法)。
  3. 半形逗號/句號/驚嘆號/問號 → 全形(只在該行譯文含中文字時才換,
     避免動到純英文的 debug 字串與檔名)。

只改第二欄,第一欄(遊戲查表 key)逐位元組不動。可重複執行。

用法:normalize_done.py [--dry-run] [檔案...]
"""
import sys, os, re, glob, argparse

# 統一譯名:先長後短,依序取代。key 是各批可能出現的變體。
NAME_FIXES = [
    # Sheriff Chicken P. Shift
    ("奇肯希夫特警長", "席夫特警長"),
    ("膽小希夫特", "膽小席夫特"),
    ("希夫特警長", "席夫特警長"),
    ("席福特警長", "席夫特警長"),
    ("警長希夫特", "席夫特警長"),
    ("警長席夫特", "席夫特警長"),
    ("希夫特", "席夫特"),
    ("席福特", "席夫特"),
    # Salvatore O'Hanahan
    ("薩爾瓦多·歐哈納翰", "薩瓦多·歐哈納翰"),
    ("沙瓦多·奧哈納漢", "薩瓦多·歐哈納翰"),
    ("薩瓦多·歐哈納漢", "薩瓦多·歐哈納翰"),
    ("沙瓦多", "薩瓦多"),
    ("薩爾瓦多", "薩瓦多"),
    ("奧哈納漢", "歐哈納翰"),
    ("歐哈納漢", "歐哈納翰"),
    ("奧哈納翰", "歐哈納翰"),
    # Helen Back
    ("海倫貝克", "海倫·貝克"),
    # P. H. Balance
    ("P.H.貝倫斯", "P·H·貝倫斯"),
    ("P．H．貝倫斯", "P·H·貝倫斯"),
    # Hop Singh 的西部片諧音全名 Hopalong Singh
    ("霍普龍·辛", "霍帕龍·星"),
    ("霍帕龍·辛", "霍帕龍·星"),
]

HALF2FULL = {",": "，", "!": "！", "?": "？", ";": "；", ":": "："}
# 括號另外處理:只有「括號內確實是中文」時才轉全形,免得動到 %s/%d 模板與英文原詞
PAREN = re.compile(r"\(([^()]*[一-鿿][^()]*)\)")
CJK = re.compile(r"[一-鿿]")


def load_corrections(path="translation/corrections.tsv"):
    out = []
    try:
        for line in open(path, encoding="utf-8"):
            line = line.rstrip("\n")
            if "\t" in line and not line.startswith("#"):
                w, r = line.split("\t", 1)
                out.append((w, r))
    except FileNotFoundError:
        pass
    return out


def fix_punct(zh):
    """半形標點 → 全形。跳過 printf 規格、|cN| 色碼、英文縮寫中的點。"""
    if not CJK.search(zh):
        return zh
    # 中文內容的半形括號 → 全形(括號裡沒有 % 規格才動)
    zh = PAREN.sub(lambda m: "（" + m.group(1) + "）" if "%" not in m.group(1) else m.group(0), zh)
    out = []
    for i, ch in enumerate(zh):
        if ch in HALF2FULL:
            prev = zh[i - 1] if i else ""
            nxt = zh[i + 1] if i + 1 < len(zh) else ""
            # 英文/數字之間的標點多半屬於原文保留的片段,不動
            if prev.isascii() and prev.isalnum() and nxt.isascii() and nxt.isalnum():
                out.append(ch)
                continue
            out.append(HALF2FULL[ch])
        else:
            out.append(ch)
    return "".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="*")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--no-punct", action="store_true")
    a = ap.parse_args()

    corrections = load_corrections()
    files = a.files or sorted(glob.glob("translation/done/*.tsv"))
    total = 0
    for p in files:
        lines = open(p, encoding="utf-8").read().split("\n")
        changed = 0
        out = []
        for line in lines:
            if "\t" not in line or line.lstrip().startswith("#"):
                out.append(line)
                continue
            en, zh = line.split("\t", 1)
            orig = zh
            for w, r in corrections:
                zh = zh.replace(w, r)
            for w, r in NAME_FIXES:
                zh = zh.replace(w, r)
            if not a.no_punct:
                zh = fix_punct(zh)
            if zh != orig:
                changed += 1
            out.append(f"{en}\t{zh}")
        if changed and not a.dry_run:
            open(p, "w", encoding="utf-8").write("\n".join(out))
        if changed:
            print(f"{os.path.basename(p)}: 修正 {changed} 行")
        total += changed
    print(f"== 共修正 {total} 行{'(dry-run,未寫檔)' if a.dry_run else ''} ==")


if __name__ == "__main__":
    main()
