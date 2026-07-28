#!/usr/bin/env python3
"""SCI1.1 的 script 內嵌字串抽取。

為什麼要另抽:`extract_strings.py` 只吃 message/text 資源,但 SCI1.1 把一部分玩家
可見的字(存讀檔對話框、按鈕、道具名、Print 直呼、動態句模板)放在 **heap** 裡
——SCI1.1 把 SCI0 的單一 script 資源拆成 `script.NNN`(bytecode)+ `heap.NNN`(資料段,
字串常數住這)。只掃 script.* 會整批漏掉。

抽法(照 ④-S「剝前導 bytecode」):以 null 切段 → 取第一個可見字元起到段尾 →
嚴格過濾(≥2 個英文字母、可列印比例高、排 SCI 內部符號名 / CamelCase 類別名 /
檔名 / 選擇器名)。key 一律過 norm_key,與引擎 sciChtNormKey 一致。

用法:extract_sci11_strings.py <dump_dir> <out_tsv> [--exclude 已抽過的.tsv ...]
       [--sidecar out.jsonl]
純 stdlib。
"""
import os, re, glob, json, argparse

IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
# SCI 內部符號/選擇器/檔名的樣子
NOISE = re.compile(
    r"^(?:[a-z]+[A-Z]\w*"          # camelCase 選擇器 (doVerb, setScript)
    r"|[A-Z][a-z]+[A-Z]\w*"        # PascalCase 類別 (BoxSelector)
    r"|\w+\.(?:sc|hep|scr|drv|exe|bat|000|map|aud)\w*"  # 檔名
    r")$")
KEEP_IDENT = {"quit", "save", "restore", "restart", "cancel", "ok", "yes", "no",
              "play", "pause", "done", "look", "talk", "walk", "use", "inventory"}


def norm_key(s):
    return " ".join(s.split())


def candidates(path):
    d = open(path, "rb").read()
    body = d[2:] if len(d) > 2 else d      # 去 patch header
    out = []
    for chunk in body.split(b"\x00"):
        if not chunk or len(chunk) > 900:
            continue
        s = chunk.decode("latin1", "replace")
        # 剝前導非文字 byte:從第一個字母/引號/數字起
        m = re.search(r"[A-Za-z\"'(\[]", s)
        if not m:
            continue
        s = s[m.start():]
        # 到第一個控制碼(SCI 內嵌 \x01-\x07 顏色碼除外)為止
        s = re.split(r"[\x00-\x06\x0e-\x1f\x7f]", s, maxsplit=1)[0]
        s = norm_key(s)
        if len(s) < 2:
            continue
        letters = len(re.findall(r"[A-Za-z]", s))
        printable = sum(1 for c in s if 32 <= ord(c) < 127)
        if letters < 2 or printable / len(s) < 0.95:
            continue
        out.append(s)
    return out


def is_display(s):
    t = s.strip()
    if not re.search(r"[A-Za-z]{2,}", t):
        return False
    if IDENT.match(t):
        # 單一 token:只留已知的 UI 字
        return t.lower() in KEEP_IDENT
    if NOISE.match(t):
        return False
    # 兩個以上單字,或帶句讀 → 視為顯示字串
    return (" " in t) or bool(re.search(r"[.!?,:;\"']", t))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dump_dir")
    ap.add_argument("out_tsv")
    ap.add_argument("--exclude", nargs="*", default=[])
    ap.add_argument("--sidecar", default=None)
    ap.add_argument("--max-res", type=int, default=899,
                    help="只收資源編號 <= 此值(9xx 是 Sierra 內建開發工具 script,非玩家可見)")
    ap.add_argument("--patterns", nargs="*", default=["heap.*"],
                    help="SCI1.1 字串常數住 heap;script.* 是純 bytecode,掃出來全是雜訊")
    a = ap.parse_args()

    known = set()
    for p in a.exclude:
        for line in open(p, encoding="utf-8"):
            if "\t" in line:
                known.add(norm_key(line.split("\t", 1)[0]))

    seen, rows = set(), []
    for pat in a.patterns:
        for f in sorted(glob.glob(os.path.join(a.dump_dir, pat)),
                        key=lambda p: (p.rsplit(".", 2)[-2], int(p.rsplit(".", 1)[1]))):
            if int(f.rsplit(".", 1)[1]) > a.max_res:
                continue
            for s in candidates(f):
                if s in known or s in seen or not is_display(s):
                    continue
                seen.add(s)
                rows.append({"res": os.path.basename(f), "en": s})

    with open(a.out_tsv, "w", encoding="utf-8") as out:
        for r in rows:
            out.write(f"{r['en']}\t{r['en']}\n")
    if a.sidecar:
        with open(a.sidecar, "w", encoding="utf-8") as out:
            for r in rows:
                out.write(json.dumps(r, ensure_ascii=False) + "\n")
    print(f"script/heap 內嵌新增 {len(rows)} 則 → {a.out_tsv}")


if __name__ == "__main__":
    main()
