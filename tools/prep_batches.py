#!/usr/bin/env python3
"""把 full_skeleton.tsv 切成翻譯批次(每批 N 則),供 subagent 平行翻譯。

跳過不該翻/翻了會壞的行:
  - 純控制碼/單字元/無英文字母
  - SCI 內建除錯字串(文字編輯器、Font Number: 之類)
  - 內部旗標名(Med 1 / Correct Rx / Incorrect Med2)——玩家看不到
輸出:translation/batch_src/NNN.tsv(英文<TAB>英文,待翻)

用法:prep_batches.py [--size 180] [--sample N --out FILE]
  --sample:改成抽 N 則代表性樣本產一個試作批(均勻取樣,長短句都涵蓋)
"""
import os, re, argparse

SKIP_EXACT = {
    "x.yyy.zzz", "ok",
    "Med 1", "Med 2", "Med 3", "Incorrect Med", "Incorrect Med2", "Correct Rx",
    "Font Number:", "Position: %d, %d", "Erase outlines?",
    "Enter text (after this, get help with '?')",
    "Enter text (then get help with `?')",
}
SKIP_RE = re.compile(
    r"^(?:ERROR: Object passed|Move text with mouse|Copyright|Sierra On)", re.I)


def load(path):
    rows = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line or "\t" not in line:
                continue
            en, _ = line.split("\t", 1)
            rows.append(en)
    return rows


def translatable(en):
    s = en.strip()
    if s in SKIP_EXACT or SKIP_RE.match(s):
        return False
    if len(s) < 2:
        return False
    # 去掉 printf spec 後要還有兩個以上連續英文字母
    if not re.search(r"[A-Za-z]{2,}", re.sub(r"%[-0-9.]*[a-zA-Z]", "", s)):
        return False
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--skeleton", default="translation/full_skeleton.tsv")
    ap.add_argument("--size", type=int, default=180)
    ap.add_argument("--outdir", default="translation/batch_src")
    ap.add_argument("--sample", type=int, default=0)
    ap.add_argument("--out", default="translation/batch_src/sample.tsv")
    a = ap.parse_args()

    rows = [en for en in load(a.skeleton) if translatable(en)]
    # 去重(同一句可能在多個資源出現)
    seen, uniq = set(), []
    for en in rows:
        if en not in seen:
            seen.add(en)
            uniq.append(en)

    os.makedirs(a.outdir, exist_ok=True)
    if a.sample:
        step = max(1, len(uniq) // a.sample)
        pick = uniq[::step][:a.sample]
        with open(a.out, "w", encoding="utf-8") as f:
            for en in pick:
                f.write(f"{en}\t{en}\n")
        print(f"試作批 {len(pick)} 則 → {a.out}(母體 {len(uniq)} 則)")
        return

    n = 0
    for i in range(0, len(uniq), a.size):
        n += 1
        with open(f"{a.outdir}/{n:03d}.tsv", "w", encoding="utf-8") as f:
            for en in uniq[i:i + a.size]:
                f.write(f"{en}\t{en}\n")
    print(f"可翻 {len(uniq)} 則 → {n} 批(每批 {a.size})於 {a.outdir}/")


if __name__ == "__main__":
    main()
