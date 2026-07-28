#!/usr/bin/env python3
"""把《宇宙傳奇 IV》CD 版被移除的 271 號房「因法律理由被拿掉的東西的倉庫」寫回遊戲。

CD 版只留下背景圖 pic.570、對白 message.271 與 view.271,房間程式(script/heap)
被整包拿掉,所以那組 18 個符號的時空艙座標按下去會找不到房間。本工具產生
271.scr / 271.hep 兩個散裝 patch 檔補回去——ScummVM 偵測到 script 271 存在後,
會自動停用它那條「停用該座標」的相容性 patch(script_patches.cpp,bug #11006),
座標因此自動復活,不必動引擎。

所有結構常數都是從遊戲既有資源反推來的(推導過程見 docs/room271-restoration.md):

  selector   0=y 1=x 2=view 3=loop 4=cel 110=init 144=changeState 146=setScript
             219=onMe 278=doVerb 376=newRoom 536=完整版 say 601=Messager 的 noun
  class      6=Script 122=Feature 124=Prop 136=Rm
  global     0=ego 2=目前房間 5=cast 32=features 89=Messager
  屬性 index 房間 16=背景圖;Prop 9=y 10=x 27=view 28=loop
             Feature w9=x w10=y w13=noun w14=module
                     w15..w18 = nsTop/nsLeft/nsBottom/nsRight
                     w19/w21   = 兩個附加檢查,26505(0x6789)= 未設定
  死亡       callb export10(類別, 索引)
  HandsOn    callb export3

用法: build_room271.py <dump 目錄> <輸出目錄>
"""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sci11_asm import Asm                                    # noqa: E402

SEL_Y, SEL_X = 0, 1
SEL_INIT, SEL_CHANGESTATE, SEL_SETSCRIPT = 110, 144, 146
SEL_DOVERB, SEL_NEWROOM, SEL_SAYFULL, SEL_NOUN = 278, 376, 536, 601
G_EGO, G_ROOM, G_MESSAGER = 0, 2, 89        # 89 才是遊戲的 Messager;91 是 9xx 開發工具用的
MODULE, PIC = 271, 570
POD_VIEW, POD_LOOP = 410, 1
UNSET = 26505                                # 0x6789:Feature 附加檢查的「未設定」哨兵

# 動詞編號(從 613 的 ship/building doVerb 對照 message tuple 反推)
V_LOOK, V_DO = 1, 4

# 熱區:(名稱, noun, 左, 上, 右, 下)。座標對著 pic.570(320x200)量的。
# noun → 物件的對應是重建的:message.271 只留下文字,原始指派無從得知,
# 這裡照描述內容配到畫面上對得起來的東西。
HOTSPOTS = [
    ('guys',    3, 104, 101, 164, 158),   # 兩個彈吉他的毛茸茸傢伙(Two Guys from Andromeda)
    ('critter', 4, 127,  52, 174,  94),   # 中央牆上的綠色生物
    ('flyer',   5,  13,  47,  48,  98),   # 左牆上的飛行生物
    ('graffiti', 6,  0, 113,  64, 140),   # 左下角的塗鴉人物
    ('droids',  7, 216,  33, 319, 101),   # DROIDS R US 招牌
    ('shock',   8, 196, 112, 294, 181),   # RADIO SHOCK 招牌
    ('note',    9, 176,  95, 198, 118),   # 牆上的小紙條(實際只有 183-190 x 101-110,框放寬一點好點)
    ('crates', 10,   0, 159,  64, 185),   # 左下角的箱子(兼房間本身的描述)
]
POD_NOUN = 1
POD_RECT = (232, 166, 302, 197)             # 時空艙的熱區(左上右下)
EGO_X, EGO_Y = 205, 180
POD_X, POD_Y = 265, 190


# ── 讀模板 ──────────────────────────────────────────────────────────────────
def load_objects(path):
    b = open(path, 'rb').read()
    n = struct.unpack_from('<H', b, 4)[0]
    pos = 6 + n * 2
    objs = []
    while pos < len(b) - 1 and struct.unpack_from('<H', b, pos)[0] == 0x1234:
        sz = struct.unpack_from('<H', b, pos + 2)[0]
        objs.append([struct.unpack_from('<H', b, pos + k * 2)[0] for k in range(sz)])
        pos += sz * 2
    strs = {}
    j = pos
    while j < len(b):
        e = b.find(b'\0', j)
        if e < 0:
            break
        s = b[j:e].decode('latin1')
        if s:
            strs[j] = s
        j += 1 + len(s)
    return objs, strs


def template(dump, res, name):
    objs, strs = load_objects(os.path.join(dump, res))
    for w in objs:
        if strs.get(w[8] + 2) == name:
            return list(w)
    raise SystemExit(f"!! 在 {res} 找不到物件 {name}")


# ── 產生 ────────────────────────────────────────────────────────────────────
def build(dump, out):
    rm_t = template(dump, 'heap.613', 'rm613')          # 一般可走動的房間
    ft_t = template(dump, 'heap.613', 'building')       # 純熱區 Feature
    sc_t = template(dump, 'heap.650', 'meltRoger')      # Script 子類別

    hs_names = [h[0] for h in HOTSPOTS] + ['pod']
    names = ['rm271', 'roomScript', 'deathScript'] + hs_names
    sizes = [len(rm_t), len(sc_t), len(sc_t)] + [len(ft_t)] * len(hs_names)

    heap_off = {}
    o = 4                                                # heap +0 重定位偏移, +2 locals 數
    for nm, sz in zip(names, sizes):
        heap_off[nm] = o
        o += sz * 2
    obj_end = o

    strtab, strpos = bytearray(), {}
    for nm in names:
        strpos[nm] = obj_end + len(strtab)
        strtab += nm.encode('ascii') + b'\0'

    meth = {'rm271': [(SEL_INIT, 'rm_init')],
            'roomScript': [(SEL_CHANGESTATE, 'room_script')],
            'deathScript': [(SEL_CHANGESTATE, 'death_script')],
            'pod': [(SEL_DOVERB, 'pod_doverb')]}
    for nm in [h[0] for h in HOTSPOTS]:
        meth[nm] = [(SEL_DOVERB, f'{nm}_doverb')]

    sp = 10                                              # +6 export 數, +8 export[0]
    meth_off = {}
    for nm in names:
        meth_off[nm] = sp
        sp += 2 + len(meth[nm]) * 4
    code_base = sp

    a = Asm()

    def say(noun, verb):
        """先設 noun 屬性,再 sayFull(module, _, verb, cond, seq)。

        say(291) 只吃 cond,noun/verb/module 來自 Messager 自己的屬性;536 才是
        一次帶進去的那個(逐條追過 class 127 → class 114)。"""
        a.emit('pushi', SEL_NOUN); a.emit('pushi', 1); a.emit('pushi', noun)
        a.emit('pushi', SEL_SAYFULL); a.emit('pushi', 5)
        for v in (MODULE, 0, verb, 0, 1):
            a.emit('pushi', v)
        a.emit('lag', G_MESSAGER); a.emit('send', 20)

    # --- rm271:init -------------------------------------------------------
    a.label('rm_init')
    a.emit('pushi', SEL_INIT); a.emit('pushi', 0)
    a.emit('super', rm_t[6], 4)                          # super init:(畫背景、建 cast)
    a.emit('pushi', SEL_X); a.emit('pushi', 1); a.emit('pushi', EGO_X)
    a.emit('pushi', SEL_Y); a.emit('pushi', 1); a.emit('pushi', EGO_Y)
    a.emit('pushi', SEL_INIT); a.emit('pushi', 0)
    a.emit('lag', G_EGO); a.emit('send', 16)              # 定位 + 把羅傑加進場景
    for nm in hs_names:
        a.emit('pushi', SEL_INIT); a.emit('pushi', 0)
        a.emit('lofsa', nm); a.emit('send', 4)            # 登記進 features(global 32)
    # callb 前面那個 push 是「參數個數」,不能省(省掉會 stack underflow);
    # callb 的第二個運算元則是參數佔的 byte 數。
    a.emit('pushi', 0); a.emit('callb', 3, 0)            # HandsOn:把控制權交還玩家
    a.emit('pushi', SEL_SETSCRIPT); a.emit('pushi', 1)
    a.emit('lofsa', 'roomScript'); a.emit('push'); a.emit('self', 6)
    a.emit('ret')

    # --- roomScript:changeState -------------------------------------------
    # 只做一件事:等房間畫完再說出房間描述。不要在 init 裡直接 say——實測會讓
    # 訊息框卡在 modal 狀態(游標一直是 Wait)。
    a.label('room_script')
    a.emit('lap', 1); a.emit('aTop', 20)                 # state = 參數
    a.emit('push')
    a.emit('dup'); a.emit('ldi', 0); a.emit('eq?'); a.emit('bnt', 'rs1')
    a.emit('ldi', 2); a.emit('aTop', 26)                 # 等兩個 cycle
    a.emit('jmp', 'rs_end')
    a.label('rs1')
    a.emit('dup'); a.emit('ldi', 1); a.emit('eq?'); a.emit('bnt', 'rs_end')
    say(10, V_LOOK)
    a.label('rs_end')
    a.emit('toss'); a.emit('ret')

    # --- pod:doVerb ——「動作」= 專屬 bad ending -------------------------
    a.label('pod_doverb')
    a.emit('lsp', 1)
    a.emit('dup'); a.emit('ldi', V_DO); a.emit('eq?'); a.emit('bnt', 'pod_look')
    say(POD_NOUN, V_DO)                                  # 1.4.0.1 那句專屬台詞
    # say 是非阻塞的,直接接死亡畫面會把那句瞬間蓋掉(實測)。
    # 掛一個 Script 隔幾個 cycle 再叫死亡,讓玩家讀得到。
    a.emit('pushi', SEL_SETSCRIPT); a.emit('pushi', 1)
    a.emit('lofsa', 'deathScript'); a.emit('push')
    a.emit('lag', G_ROOM); a.emit('send', 6)
    a.emit('jmp', 'pod_done')
    a.label('pod_look')
    say(POD_NOUN, 0)                                     # 1.0.0.1「這是一艘時空艙。」
    a.label('pod_done')
    a.emit('toss'); a.emit('ret')

    # --- deathScript:changeState —— 等一下再叫死亡畫面 --------------------
    a.label('death_script')
    a.emit('lap', 1); a.emit('aTop', 20)
    a.emit('push')
    a.emit('dup'); a.emit('ldi', 0); a.emit('eq?'); a.emit('bnt', 'ds1')
    a.emit('ldi', 60); a.emit('aTop', 26)
    a.emit('jmp', 'ds_end')
    a.label('ds1')
    a.emit('dup'); a.emit('ldi', 1); a.emit('eq?'); a.emit('bnt', 'ds_end')
    a.emit('pushi', 2); a.emit('pushi', 5); a.emit('pushi', 16)
    a.emit('callb', 10, 4)
    a.label('ds_end')
    a.emit('toss'); a.emit('ret')

    # --- 熱區:doVerb → 說對應的 noun --------------------------------------
    for nm, noun, *_ in HOTSPOTS:
        a.label(f'{nm}_doverb')
        a.emit('lsp', 1); a.emit('toss')
        say(noun, V_LOOK)
        a.emit('ret')

    code, code_reloc = a.assemble(code_base, lambda n: heap_off[n])

    # --- 組 script --------------------------------------------------------
    scr = bytearray(code_base + len(code))
    struct.pack_into('<H', scr, 6, 1)                    # 1 個 export
    struct.pack_into('<H', scr, 8, heap_off['rm271'])
    for nm in names:
        p = meth_off[nm]
        struct.pack_into('<H', scr, p, len(meth[nm]))
        for k, (sel, lbl) in enumerate(meth[nm]):
            struct.pack_into('<H', scr, p + 2 + k * 4, sel)
            struct.pack_into('<H', scr, p + 4 + k * 4, a.labels[lbl])
    scr[code_base:] = code
    reloc = [8] + sorted(code_reloc)
    struct.pack_into('<H', scr, 0, len(scr))
    scr += struct.pack('<H', len(reloc)) + b''.join(struct.pack('<H', r) for r in reloc)

    # --- 組 heap ----------------------------------------------------------
    def mkobj(tmpl, nm, over):
        w = list(tmpl)
        w[2] = meth_off[nm]                              # instance 沒有屬性表,指方法表即可
        w[3] = meth_off[nm]
        w[8] = strpos[nm]                                # name 指標(heap 偏移)
        for i, v in over.items():
            w[i] = v & 0xFFFF
        return w

    def feature(nm, noun, l, t, r, bm):
        # w19 / w21 一定要還原成 UNSET。範本 building 把 w21 設成 2,那是 613 那個
        # 房間要的「控制層附加檢查」——Feature:onMe(selector 219)在矩形測試通過後,
        # 若 w21 != 26505 會再 AND 一次 callk 78。整包複製會把這道檢查一起帶過來,
        # 在 pic.570 上永遠不會通過,熱區就永遠點不到(找了很久的那個 bug)。
        return mkobj(ft_t, nm, {9: (l + r) // 2, 10: bm,          # x, y
                                13: noun, 14: MODULE,             # noun, module
                                15: t, 16: l, 17: bm, 18: r,      # nsTop/Left/Bottom/Right
                                19: UNSET, 21: UNSET, 26: 0})

    objs = [mkobj(rm_t, 'rm271', {16: PIC, 21: 531, 22: 531, 23: 531}),
            mkobj(sc_t, 'roomScript', {}),
            mkobj(sc_t, 'deathScript', {})]
    for nm, noun, l, t, r, bm in HOTSPOTS:
        objs.append(feature(nm, noun, l, t, r, bm))
    objs.append(feature('pod', POD_NOUN, *POD_RECT))

    hp = bytearray(4)
    struct.pack_into('<H', hp, 2, 0)                     # 沒有 local
    for w in objs:
        for v in w:
            hp += struct.pack('<H', v)
    hp += strtab
    hreloc = [heap_off[nm] + 16 for nm in names]         # 每個物件的 name 指標
    struct.pack_into('<H', hp, 0, len(hp))
    hp += struct.pack('<H', len(hreloc)) + b''.join(struct.pack('<H', r) for r in hreloc)

    os.makedirs(out, exist_ok=True)
    open(os.path.join(out, '271.scr'), 'wb').write(bytes([0x82, 0]) + bytes(scr))
    open(os.path.join(out, '271.hep'), 'wb').write(bytes([0x91, 0]) + bytes(hp))
    print(f">> 271.scr {len(scr)+2} bytes  /  271.hep {len(hp)+2} bytes")
    print(f"   物件 {len(objs)} 個,程式碼 {len(code)} bytes,"
          f"重定位 script {len(reloc)} 筆 / heap {len(hreloc)} 筆")


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    build(sys.argv[1], sys.argv[2])
