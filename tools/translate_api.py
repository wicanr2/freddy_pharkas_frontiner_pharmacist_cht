#!/usr/bin/env python3
"""用 Kimi API 便宜模型(kimi-for-coding-highspeed)批次翻譯 batch/*.tsv。

- 每批一次 chat completion;system prompt 內嵌 LOCALIZE_INSTRUCTIONS.md 全文。
- 嚴格驗證:行數/第一欄 key 逐字相同/格式碼數量順序/Big5 可編/無控制字元/無空譯。
- 失敗帶錯誤回饋重試(最多 4 次)。6 執行緒平行。
- token 每次從 credentials 檔重讀(CLI 會刷新它)。

用法:translate_api.py [批次號...](預設全部缺譯批次)
"""
import json, os, re, sys, glob, time, threading
import urllib.request, urllib.error
from concurrent.futures import ThreadPoolExecutor, as_completed

W = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CRED = os.path.expanduser("~/.kimi-code/credentials/kimi-code.json")
URL = "https://api.kimi.com/coding/v1/chat/completions"
MODEL = "kimi-for-coding-highspeed"
INSTR = open(f"{W}/translation/LOCALIZE_INSTRUCTIONS.md", encoding="utf-8").read()
LOG = open(f"{W}/translation/translate_api.log", "a", buffering=1, encoding="utf-8")
LOCK = threading.Lock()

def log(*a):
    with LOCK:
        msg = " ".join(str(x) for x in a)
        LOG.write(msg + "\n")
        print(msg, flush=True)

def get_tok():
    return json.load(open(CRED))["access_token"]

SPEC = re.compile(r"%[-+0-9.]*[a-zA-Z]")

def call_api(messages, max_tokens=32000, timeout=600):
    req = urllib.request.Request(
        URL,
        data=json.dumps({"model": MODEL, "messages": messages,
                         "max_tokens": max_tokens}).encode(),
        headers={"Authorization": f"Bearer {get_tok()}", "Content-Type": "application/json"})
    r = urllib.request.urlopen(req, timeout=timeout)
    d = json.load(r)
    return d["choices"][0]["message"]["content"], d.get("usage", {})

def validate(src_lines, out_text):
    """回傳 (ok, errors[], rows[])"""
    txt = out_text.strip()
    if txt.startswith("```"):
        txt = re.sub(r"^```[a-z]*\n", "", txt)
        txt = re.sub(r"\n```$", "", txt.strip())
    out_lines = txt.split("\n")
    errs = []
    if len(out_lines) != len(src_lines):
        errs.append(f"行數不符: 期望 {len(src_lines)} 實得 {len(out_lines)}")
        return False, errs, None
    rows = []
    for i, (s, o) in enumerate(zip(src_lines, out_lines), 1):
        if "\t" not in o:
            errs.append(f"行{i}: 缺 TAB")
            continue
        en, zh = o.split("\t", 1)
        if en != s:
            errs.append(f"行{i}: key 被改 (期望 {s[:30]!r} 實得 {en[:30]!r})")
            continue
        if not zh.strip():
            errs.append(f"行{i}: 譯文空白")
            continue
        if SPEC.findall(s) != SPEC.findall(zh):
            errs.append(f"行{i}: 格式碼不符 ({SPEC.findall(s)} vs {SPEC.findall(zh)})")
            continue
        try:
            zh.encode("big5")
        except UnicodeEncodeError as e:
            errs.append(f"行{i}: 非 Big5 字元 {e}")
            continue
        if re.search(r"[\x00-\x08\x0b-\x1f]", zh):
            errs.append(f"行{i}: 含控制字元")
            continue
        rows.append((s, zh))
    return (not errs), errs, rows

PROMPT = """請翻譯以下 {n} 行遊戲字串。每行格式:英文原文<TAB>(空)。
輸出:完全相同的 {n} 行,第二欄填入繁體中文譯文。

規則(違反會被驗證退回):
- 第一欄英文原文**逐字不變**(含前導/尾隨空格),直接照抄到輸出行開頭。
- 只輸出 {n} 行 TSV,不要任何前言、註解、markdown 圍欄。
- 格式碼(%s/%d 等)數量與順序保留;全形標點;Big5 繁體字;按鈕標籤短譯。
- 除錯字串/檔名/拉丁文 → 第二欄照抄英文原文。

待譯內容:
{body}"""

def do_batch(path):
    name = os.path.basename(path)
    src = [l.split("\t")[0] for l in open(path, encoding="utf-8").read().split("\n") if "\t" in l]
    if not src:
        return name, "skip(empty)"
    body = "\n".join(s + "\t" for s in src)
    messages = [
        {"role": "system", "content": INSTR},
        {"role": "user", "content": PROMPT.format(n=len(src), body=body)},
    ]
    for attempt in range(1, 5):
        try:
            out, usage = call_api(messages)
        except Exception as e:
            log(name, f"attempt{attempt} API 錯誤: {e}")
            time.sleep(5 * attempt)
            continue
        ok, errs, rows = validate(src, out)
        if ok:
            with open(path, "w", encoding="utf-8") as f:
                for en, zh in rows:
                    f.write(en + "\t" + zh + "\n")
            log(name, f"OK attempt{attempt} {len(rows)} 行 in={usage.get('prompt_tokens')} out={usage.get('completion_tokens')}")
            return name, "ok"
        log(name, f"attempt{attempt} 驗證失敗 {len(errs)} 項: {'; '.join(errs[:4])}")
        messages.append({"role": "assistant", "content": out})
        messages.append({"role": "user", "content":
            "驗證失敗,請修正後**重新輸出完整 {n} 行**(規則同上):\n".format(n=len(src)) + "\n".join(errs[:12])})
    return name, "FAIL"

def main():
    targets = sys.argv[1:]
    if not targets:
        targets = sorted(os.path.basename(p)[:2] for p in glob.glob(f"{W}/translation/batch/*.tsv"))
    paths = []
    for t in targets:
        p = f"{W}/translation/batch/{t}.tsv"
        # 已完成(全部有譯文)的跳過
        if any(l.split("\t", 1)[1].strip() == "" for l in open(p, encoding="utf-8") if "\t" in l):
            paths.append(p)
    log(f"== 待處理 {len(paths)} 批: {[os.path.basename(p) for p in paths]}")
    fails = []
    with ThreadPoolExecutor(max_workers=6) as ex:
        futs = {ex.submit(do_batch, p): p for p in paths}
        for fu in as_completed(futs):
            name, st = fu.result()
            if st != "ok":
                fails.append(name)
    log(f"== 完成。失敗批次: {fails if fails else '無'}")

if __name__ == "__main__":
    main()
