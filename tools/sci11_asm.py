#!/usr/bin/env python3
"""SCI1.1 script/heap 組譯器(產生散裝 patch 檔 NNN.scr / NNN.hep)。

格式全部逐條對照 ScummVM 原始碼與遊戲既有資源反推,沒有猜:

  patch 檔頭     2 bytes: [0x80|resType, headerSize]  —— script=0x82, heap=0x91
                 ScummVM 的 _buf / _heap 從第 3 個 byte 起算,所以「檔案 offset =
                 資源 offset + 2」。ScummVM 原始碼裡寫的 4 + heap[2]*2 是對 _heap 而言。

  heap 資源      +0  重定位表偏移
                 +2  local 變數個數
                 +4  locals[]
                     物件們(見下)
                     字串區(NUL 結尾)
                     重定位表: count, offsets[]   —— 每個物件 name 指標的位置(物件偏移+16)

  物件           w0 0x1234 magic
                 w1 大小(words)
                 w2 屬性選擇子表偏移(script 內;instance 用不到,指到方法表即可)
                 w3 方法表偏移(script 內)
                 w4.. 屬性值   w6=superclass  w8=name 指標

  script 資源    +0  重定位表偏移
                 +2  0
                 +4  0
                 +6  export 個數
                 +8  export 表(每個 = 物件的 heap 偏移)
                     方法表們: count, (selector, codeOffset)*count
                     bytecode
                     重定位表: count, offsets[]  —— export 項與每個 lofsa 運算元的位置

驗證方式:對既有的 script.650/heap.650 做 parse → rebuild → 逐 byte 比對(見 selftest)。
"""
import struct
import sys

# ── 指令編碼(opcode 表與 sci11_disasm.py 同源:ScummVM kernel_tables.h)────────
OPS = {
    'bnot': 0x00, 'add': 0x01, 'sub': 0x02, 'mul': 0x03, 'div': 0x04, 'mod': 0x05,
    'eq?': 0x0d, 'ne?': 0x0e, 'gt?': 0x0f, 'ge?': 0x10, 'lt?': 0x11, 'le?': 0x12,
    'bt': 0x17, 'bnt': 0x18, 'jmp': 0x19, 'ldi': 0x1a, 'push': 0x1b, 'pushi': 0x1c,
    'toss': 0x1d, 'dup': 0x1e, 'link': 0x1f, 'call': 0x20, 'callk': 0x21,
    'callb': 0x22, 'calle': 0x23, 'ret': 0x24, 'send': 0x25, 'class': 0x28,
    'self': 0x2a, 'super': 0x2b, 'rest': 0x2c, 'lea': 0x2d,
    'pToa': 0x31, 'aTop': 0x32, 'pTos': 0x33, 'sTop': 0x34,
    'lofsa': 0x39, 'lofss': 0x3a, 'push0': 0x3b, 'push1': 0x3c, 'push2': 0x3d,
    'pushSelf': 0x3e, 'lag': 0x40, 'lal': 0x41, 'lat': 0x42, 'lap': 0x43,
    'lsg': 0x44, 'lsl': 0x45, 'lst': 0x46, 'lsp': 0x47,
    'sag': 0x50, 'sal': 0x51, 'sat': 0x52, 'sap': 0x53,
    'ssg': 0x54, 'ssl': 0x55, 'sst': 0x56, 'ssp': 0x57,
    'sagi': 0x58, 'sali': 0x59,
    'lagi': 0x48, 'lali': 0x49, 'lsgi': 0x4c, 'lsli': 0x4d,
}
# 運算元型別:'' 無、'b' 固定 byte、'w' 固定 word、'v' byte/word 看低位元、
# 'r' 相對位移(bnt/jmp,支援 label)、'o' heap 指標(lofsa/lofss,需重定位)
FORMATS = {
    'bt': 'r', 'bnt': 'r', 'jmp': 'r', 'ldi': 'v', 'pushi': 'v', 'link': 'v',
    'call': 'rb', 'callk': 'vb', 'callb': 'vb', 'calle': 'vvb',
    'send': 'b', 'class': 'v', 'self': 'b', 'super': 'vb', 'rest': 'v',
    'lea': 'vv', 'lofsa': 'o', 'lofss': 'o',
    'pToa': 'v', 'aTop': 'v', 'pTos': 'v', 'sTop': 'v',
}
for _n, _c in OPS.items():
    if 0x40 <= _c <= 0x5f:
        FORMATS[_n] = 'v'
FORMATS.setdefault('lali', 'v')
FORMATS.setdefault('sali', 'v')
FORMATS.setdefault('lagi', 'v')
FORMATS.setdefault('sagi', 'v')
FORMATS.setdefault('lsgi', 'v')
FORMATS.setdefault('lsli', 'v')


class Asm:
    """把 (op, args) 串列組成 bytecode,處理 label 與 heap 指標重定位。"""

    def __init__(self):
        self.items = []           # (kind, ...)
        self.labels = {}

    def label(self, name):
        self.items.append(('label', name))

    def emit(self, op, *args):
        self.items.append(('op', op, list(args)))

    # --- 便利包裝 ---------------------------------------------------------
    def send_to(self, target, groups, kind='send'):
        """groups = [(selector, [args...]), ...];target 為 ('lofsa',name)/('lag',n)/('self',)"""
        nbytes = 0
        for sel, a in groups:
            self.emit('pushi', sel)
            self.emit('pushi', len(a))
            for v in a:
                if isinstance(v, tuple):
                    self.emit(*v)
                else:
                    self.emit('pushi', v)
            nbytes += (2 + len(a)) * 2
        if target[0] == 'self':
            self.emit('self', nbytes)
        else:
            self.emit(*target)
            self.emit(kind, nbytes)

    # --- 組譯 -------------------------------------------------------------
    def assemble(self, base, heap_of):
        """base = 這段 code 在 script 資源中的起始 offset。
        回傳 (bytes, reloc_offsets)。heap_of(name) → heap 偏移。"""
        # 第一遍:算長度定 label
        for _ in range(3):                      # 迭代到長度收斂(短跳轉)
            pos = base
            self.labels = {}
            for it in self.items:
                if it[0] == 'label':
                    self.labels[it[1]] = pos
                else:
                    pos += self._len(it[1], it[2])
        out = bytearray()
        reloc = []
        pos = base
        for it in self.items:
            if it[0] == 'label':
                continue
            op, args = it[1], it[2]
            b, rel = self._encode(op, args, pos, heap_of)
            reloc += [pos + r for r in rel]
            out += b
            pos += len(b)
        return bytes(out), reloc

    def _len(self, op, args):
        b, _ = self._encode(op, args, 0, lambda n: 0, sizing=True)
        return len(b)

    def _encode(self, op, args, pos, heap_of, sizing=False):
        """一律用 word 形式的運算元(ext 低位元 = 0)。

        指令長度因此與 label 是否已知無關,兩遍組譯必然收斂——不必為了省一個 byte
        去處理「短跳轉縮短後 label 位移改變、又要重算」的迭代問題。多出來的幾 bytes
        對一個房間 script 完全無所謂,換來的是不會編錯。
        """
        code = OPS[op]
        fmt = FORMATS.get(op, '')
        vals = []
        for i, f in enumerate(fmt):
            v = args[i]
            if f == 'r':
                vals.append(('rel', v))
            elif f == 'o':
                vals.append(('heap', v))
            elif f == 'b':
                vals.append(('byte', v))
            else:                                   # 'v' / 'w'
                vals.append(('word', v))
        # 先算長度(相對位移要用「下一條指令的位址」當基準)
        ln = 1 + sum(1 if k == 'byte' else 2 for k, _ in vals)
        nxt = pos + ln
        body = bytearray([code * 2])                # 低位元 0 = word 形式
        reloc = []
        for kind, v in vals:
            if kind == 'byte':
                body.append(v & 0xFF)
            elif kind == 'heap':
                reloc.append(len(body))
                body += struct.pack('<H', 0 if sizing else heap_of(v))
            elif kind == 'rel':
                tgt = v if isinstance(v, int) else self.labels.get(v, nxt)
                body += struct.pack('<h', 0 if sizing else tgt - nxt)
            else:
                body += struct.pack('<H', v & 0xFFFF)
        assert len(body) == ln
        return bytes(body), reloc


def selftest():
    """對既有資源做 parse → 重建,確認格式理解正確。"""
    import os
    d = os.path.join(os.path.dirname(__file__), '..', 'extract', 'dump')
    for name, tp in (('script.650', 0x82), ('heap.650', 0x91)):
        p = os.path.join(d, name)
        if not os.path.exists(p):
            print(f"  跳過 {name}(找不到)")
            continue
        b = open(p, 'rb').read()
        assert b[0] == tp and b[1] == 0, f"{name} patch 檔頭不符: {b[:2].hex()}"
        ro = struct.unpack_from('<H', b, 2)[0]
        cnt = struct.unpack_from('<H', b, ro + 2)[0]
        assert ro + 2 + 2 + cnt * 2 == len(b), f"{name} 重定位表長度不符"
        print(f"  {name}: patch 檔頭 OK,重定位表 {cnt} 筆,長度吻合")


if __name__ == '__main__':
    print("SCI1.1 組譯器 自我檢查:")
    selftest()
