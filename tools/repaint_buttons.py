#!/usr/bin/env python3
"""把 SCI view 裡「烘進美術圖的英文按鈕字」重繪成中文。

問題:SQ4 暫停面板的按鈕 cel 是 50×15,扣掉立體邊框只剩約 11px 文字帶,中文縮到
那個高度必糊(倚天 24×24 縮到 11px 筆劃會黏成一團)。標籤 cel 更只有 9px 高。

做法(rulebook 81「拉畫布不縮字」在 cel 尺度的落地):**把 cel 加高**,吃掉按鈕之間
原本留白的間距,讓 16×15 的倚天字模原尺寸放得進去,而不是把字縮到糊掉。
- 邊框保真:把原 cel 拆成「上邊框 / 可重複的中段 / 下邊框」,中段整列複製到新高度,
  立體邊框的像素完全沿用原圖。
- 顏色不自創:face(底色)與 ink(字色)都從原 cel 自己的像素統計出來,再用 view 內嵌
  調色盤原色寫回,避免 RGB→index 量化失真。

用法:
  repaint_buttons.py <view 檔> <輸出 patch> --spec <loop>,<cel>,<中文>[,<新高度>] ...
"""
import os, sys, argparse, collections, subprocess, tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_eten_font import EtenFont, ETEN
from PIL import Image

TOOLS = os.path.dirname(os.path.abspath(__file__))


def load_font():
    """回傳 (16×15, 24×24) 兩份倚天字模。
    小標籤要縮到 12px 時用 24×24 當來源:24→12 是整數 2:1 縮減,比 16×15 縮到 12
    的非整數縮放乾淨得多(參考 kb eten-bitmap-font 對縮放的實測)。"""
    lo = EtenFont(os.path.join(ETEN, "STDFONT.15"), os.path.join(ETEN, "SPCFONT.15"), 16, 15)
    hi = EtenFont(os.path.join(ETEN, "stdfont.24"), os.path.join(ETEN, "SPCFONT.24"), 24, 24)
    return lo, hi


def glyph_mask(font, ch, size=None):
    """回傳 (w, h, set of (x,y))。size 給定時把 24×24 字模縮到該尺寸(小標籤用)。"""
    b5 = ch.encode("big5")
    g = font.glyph(b5[0], b5[1])
    if g is None:
        return 0, 0, set()
    rb = (font.w + 7) // 8
    pts = {(x, y) for y in range(font.h) for x in range(font.w)
           if g[y * rb + (x >> 3)] & (0x80 >> (x & 7))}
    if size is None:
        return font.w, font.h, pts
    im = Image.new("L", (font.w, font.h), 0)
    px = im.load()
    for x, y in pts:
        px[x, y] = 255
    im = im.resize(size, Image.BOX).point(lambda v: 255 if v >= 0.42 * 255 else 0)
    p2 = im.load()
    return size[0], size[1], {(x, y) for y in range(size[1]) for x in range(size[0]) if p2[x, y]}


def analyse(img, border):
    """從 cel 內部統計 face(最多的色)與 ink(次多的色)。"""
    w, h = img.size
    px = img.convert("RGB").load()
    inner = collections.Counter()
    for y in range(border, h - border):
        for x in range(border, w - border):
            inner[px[x, y]] += 1
    if not inner:
        raise SystemExit("cel 太小,取不到內部像素")
    ranked = inner.most_common()
    face = ranked[0][0]
    # ink 取「離 face 最遠」的內部顏色,而不是第二多的那個——第二多常常是立體邊框的
    # 亮/暗灰,拿它當字色會畫出幾乎看不見的字。正常鈕是灰底黑字、反白鈕是暗底綠字,
    # 兩種都是「離底色最遠」那一個。只考慮出現次數夠多的色,避免抓到單點雜訊。
    cands = [c for c, n in ranked[1:] if n >= 4] or [c for c, _ in ranked[1:]]
    if cands:
        ink = max(cands, key=lambda c: sum((a - b) ** 2 for a, b in zip(c, face)))
    else:
        ink = face
    return face, ink


def stretch(img, new_h, top_keep, bottom_keep):
    """把 cel 縱向拉高:保留上下邊框,中段整列重複。"""
    w, h = img.size
    if new_h == h:
        return img.copy()
    src = img.convert("RGBA")
    out = Image.new("RGBA", (w, new_h))
    # 上邊框
    out.paste(src.crop((0, 0, w, top_keep)), (0, 0))
    # 中段:取原圖中段的第一列反覆填
    mid_src_y = top_keep
    fill_h = new_h - top_keep - bottom_keep
    row = src.crop((0, mid_src_y, w, mid_src_y + 1))
    for i in range(fill_h):
        out.paste(row, (0, top_keep + i))
    # 原中段內容(邊框的左右直線之外的部分)也要保留 → 直接把原中段貼在最上面
    orig_mid = src.crop((0, top_keep, w, h - bottom_keep))
    out.paste(orig_mid, (0, top_keep))
    # 下邊框貼到新的底部
    out.paste(src.crop((0, h - bottom_keep, w, h)), (0, new_h - bottom_keep))
    return out


def repaint(png_path, text, new_h, out_path, fonts, label=False):
    """把一個 cel 重繪成中文。

    label=False:立體按鈕。保留原邊框,只把內部塗成底色再畫字;高度不足就縱向拉伸中段。
    label=True :面板上的無框標籤(DETAIL/GAME PAUSED 這類)。整張以底色重畫,
                寬度不夠就往右加寬——中文一定比等義英文短詞寬,不加寬就得縮字。
    """
    lo, _hi = fonts
    img = Image.open(png_path).convert("RGBA")
    w, h = img.size
    border = 0 if label else 2
    face, ink = analyse(img, border)
    new_h = new_h or h

    gw, gh = lo.w, lo.h
    masks = [glyph_mask(lo, ch, None) for ch in text]
    total_w = sum(m[0] for m in masks) + (len(masks) - 1)

    if label:
        new_w = max(w, total_w)
        out = Image.new("RGBA", (new_w, new_h), face + (255,))
    else:
        if new_h != h:
            img = stretch(img, new_h, top_keep=border + 1, bottom_keep=border + 1)
        out = img
        new_w = out.size[0]
        px = out.load()
        for y in range(border + 1, new_h - border - 1):
            for x in range(border + 1, new_w - border - 1):
                px[x, y] = face + (255,)
        if total_w > new_w - 2 * (border + 1):
            raise SystemExit(f"{png_path}: 「{text}」寬 {total_w} 放不進 {new_w}px 的按鈕")

    px = out.load()
    ox = (new_w - total_w) // 2
    oy = (new_h - gh) // 2
    x = ox
    for mw, mh, pts in masks:
        for gx, gy in pts:
            xx, yy = x + gx, oy + gy
            if 0 <= xx < new_w and 0 <= yy < new_h:
                px[xx, yy] = ink + (255,)
        x += mw + 1

    out.save(out_path)
    return out.size


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("view")
    ap.add_argument("out_patch")
    ap.add_argument("--decoded", required=True, help="sci_view.py decode 的輸出目錄")
    ap.add_argument("--view-id", type=int, required=True)
    ap.add_argument("--spec", action="append", required=True,
                    help="loop,cel,中文[,新高度[,label]]")
    ap.add_argument("--workdir", default=None)
    a = ap.parse_args()

    fonts = load_font()
    work = a.workdir or tempfile.mkdtemp(prefix="repaint_")
    os.makedirs(work, exist_ok=True)

    replaces = []
    for spec in a.spec:
        parts = spec.split(",")
        loop, cel, text = int(parts[0]), int(parts[1]), parts[2]
        new_h = int(parts[3]) if len(parts) > 3 and parts[3] else None
        label = len(parts) > 4 and parts[4] == "label"
        src = os.path.join(a.decoded, f"view_{a.view_id}_{loop}_{cel}.png")
        dst = os.path.join(work, f"cht_{loop}_{cel}.png")
        w, h = repaint(src, text, new_h, dst, fonts, label=label)
        print(f"  loop{loop} cel{cel}「{text}」→ {w}×{h}")
        replaces.append(f"{loop},{cel},{dst}")

    cmd = [sys.executable, os.path.join(TOOLS, "sci_view.py"), "encode",
           a.view, a.out_patch, "--patch", "--allow-resize"]
    for r in replaces:
        cmd += ["--replace", r]
    subprocess.run(cmd, check=True)


if __name__ == "__main__":
    main()
