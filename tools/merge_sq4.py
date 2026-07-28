#!/usr/bin/env python3
"""合併 SQ4 譯文各來源 → translation/translation.tsv(UTF-8 master)。

來源與優先序(後者覆蓋前者):
  1. translation/prefill.tsv       從 SQ3 繁中版複用的同句
  2. translation/done/NN.tsv       批次 subagent 譯文(格式:行號<TAB>中文,行號對 index.json)
  3. translation/manual_ctrl.tsv   含 SCI 控制碼、主 session 自譯(英文<TAB>中文)
  4. translation/override.tsv      人工修訂,最高優先(英文<TAB>中文)

同時做驗收(問題會列出來但不中止,除非 --strict):
  - 行號對不上 index.json
  - 格式符(%s/%d/...)數量或型別與原文不符
  - 譯文仍是英文原文(等於沒翻)
  - 非 Big5 字元
  - 批次檔行數與輸入不符(subagent 漏行)

用法:merge_sq4.py [--strict]
"""
import os, re, json, glob, sys, argparse

WP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
T = os.path.join(WP, "translation")
SPEC = re.compile(r"%[-+#0-9.]*[a-zA-Z]")


def norm(s):
    return " ".join(s.split())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--strict", action="store_true")
    a = ap.parse_args()

    idx = {int(k): v for k, v in json.load(open(f"{T}/index.json", encoding="utf-8")).items()}
    out, problems = {}, []

    def load_pairs(path, tag):
        n = 0
        for line in open(path, encoding="utf-8"):
            line = line.rstrip("\n")
            if "\t" not in line:
                continue
            en, zh = line.split("\t", 1)
            if not zh.strip():
                continue
            out[norm(en)] = zh.strip()
            n += 1
        return n

    n_pre = load_pairs(f"{T}/prefill.tsv", "prefill") if os.path.exists(f"{T}/prefill.tsv") else 0

    n_batch = 0
    batch_files = sorted(glob.glob(f"{T}/done/*.tsv"))
    for p in batch_files:
        src = f"{T}/batch/{os.path.basename(p)}"
        want = sum(1 for _ in open(src, encoding="utf-8")) if os.path.exists(src) else None
        got = 0
        for line in open(p, encoding="utf-8"):
            line = line.rstrip("\n")
            if "\t" not in line:
                continue
            num, zh = line.split("\t", 1)
            got += 1
            if not num.strip().isdigit():
                problems.append(f"{os.path.basename(p)}: 行首不是行號 → {line[:60]!r}")
                continue
            i = int(num)
            if i not in idx:
                problems.append(f"{os.path.basename(p)}: 行號 {i} 不在 index.json")
                continue
            zh = zh.strip()
            if not zh:
                continue
            en = idx[i]
            en_specs = sorted(SPEC.findall(en))
            zh_specs = sorted(SPEC.findall(zh))
            if en_specs != zh_specs:
                problems.append(f"{os.path.basename(p)}#{i}: 格式符不符 原文{en_specs} 譯文{zh_specs} | {en[:50]!r}")
                continue          # 格式符錯會讓引擎崩,寧可退回英文
            if zh == en:
                problems.append(f"{os.path.basename(p)}#{i}: 未翻譯(譯文==原文)")
                continue
            out[norm(en)] = zh
            n_batch += 1
        if want is not None and got != want:
            problems.append(f"{os.path.basename(p)}: 行數 {got} != 輸入 {want}(subagent 漏行/多行)")

    n_ctrl = load_pairs(f"{T}/manual_ctrl.tsv", "ctrl") if os.path.exists(f"{T}/manual_ctrl.tsv") else 0
    n_ovr = load_pairs(f"{T}/override.tsv", "override") if os.path.exists(f"{T}/override.tsv") else 0

    # 非 Big5 掃描
    nonbig5 = {}
    for zh in out.values():
        for ch in zh:
            if ord(ch) < 0x80:
                continue
            try:
                ch.encode("big5")
            except UnicodeEncodeError:
                nonbig5[ch] = nonbig5.get(ch, 0) + 1

    with open(f"{T}/translation.tsv", "w", encoding="utf-8") as f:
        for en in sorted(out):
            f.write(f"{en}\t{out[en]}\n")

    total = sum(1 for _ in open(f"{T}/full_skeleton.tsv", encoding="utf-8"))
    print(f"合併:prefill {n_pre} + 批次 {n_batch} + 控制碼 {n_ctrl} + override {n_ovr}")
    print(f"master translation.tsv:{len(out)} 則 / skeleton {total} 則 = 覆蓋率 {len(out)*100/total:.1f}%")
    print(f"批次檔 {len(batch_files)}/12 到齊")
    if nonbig5:
        print("非 Big5 字元(會遺失,需補 corrections.tsv):",
              " ".join(f"{c}×{n}" for c, n in nonbig5.items()))
    if problems:
        print(f"\n問題 {len(problems)} 項:")
        for p in problems[:40]:
            print("  ", p)
        if len(problems) > 40:
            print(f"   …另有 {len(problems)-40} 項")
        if a.strict:
            sys.exit(1)


if __name__ == "__main__":
    main()
