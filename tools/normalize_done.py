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
    # 以下是併完各批之後用譯名稽核挑出來的分歧(同一角色/專名被不同批各譯一種)
    ("謝夫警長", "席夫特警長"),
    ("警長謝夫", "席夫特警長"),
    ("奇肯", "切肯"),          # Sheriff "Chicken" P. Shift 的綽號
    ("巴蘭斯", "貝倫斯"),      # P. H. Balance
    ("阿牌", "王牌"),          # Wheaton "Aces" Hall
    ("重啟山莊", "重開機墓園"),  # ReBoot Hill(Boot Hill + reboot)
    ("G痔瘡膏", "G藥膏"),      # Preparation G
    ("普林姆小姐", "潘妮洛普小姐"),
    ("普林姆", "潘妮洛普"),
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


FULL2HALF = {v: k for k, v in HALF2FULL.items()}


def _iscjk(c):
    return bool(c) and CJK.match(c) is not None


def fix_punct(zh):
    """半形標點 ↔ 全形,以「左右是不是中文」判斷,兩個方向都修。

    只看「這行有中文」不夠:譯文常同時含中文與整段保留的英文(版權宣告、
    Sierra 的電話地址、遊戲名縮寫)。早期版本只要整行有中文就把半形逗號全轉全形,
    把 `Sierra On-Line, Inc.` 弄成 `Sierra On-Line， Inc.`。改成只在標點**緊鄰中文**
    時才轉全形;反過來,夾在英數之間的全形標點也轉回半形(修掉先前轉壞的)。
    """
    if not CJK.search(zh):
        return zh
    # 中文內容的半形括號 → 全形(括號裡沒有 % 規格才動)
    zh = PAREN.sub(lambda m: "（" + m.group(1) + "）" if "%" not in m.group(1) else m.group(0), zh)
    out = []
    for i, ch in enumerate(zh):
        prev = zh[i - 1] if i else ""
        nxt = zh[i + 1] if i + 1 < len(zh) else ""
        if ch in HALF2FULL and (_iscjk(prev) or _iscjk(nxt)):
            out.append(HALF2FULL[ch])
        elif ch in FULL2HALF and prev.isascii() and prev.isalnum() and \
                (nxt == " " or (nxt.isascii() and nxt.isalnum())):
            out.append(FULL2HALF[ch])   # 夾在英文中間的全形標點:轉回半形
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
