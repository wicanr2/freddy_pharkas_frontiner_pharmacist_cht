#!/usr/bin/env python3
"""SCI1.1 script.NNN 反組譯器（唯讀分析用）。

規格逐條對照 ScummVM 原始碼抄下來，沒有自己發明：
  engines/sci/engine/vm.cpp            readPMachineInstruction()  指令長度與運算元編碼
  engines/sci/engine/kernel_tables.h   g_base_opcode_formats[128][4]
  engines/sci/engine/scriptdebug.cpp   opcodeNames[]
  engines/sci/engine/script.cpp        initializeObjectsSci11()   物件區起點

heap 的 local 區起點有個坑：ScummVM 的 _heap 比 SCI_DUMP_RES 倒出來的 heap.NNN 檔
少 2 bytes，所以照 ScummVM 寫的「4 + heap[2]*2」對不上檔案。實測（三個 heap 交叉驗證，
預測值與第一個 0x1234 物件標記完全吻合）在檔案上是：

    localsCount = uint16 @ 4
    locals[i]   = uint16 @ 6 + i*2
    物件區起點  = 6 + localsCount*2

用法:
  sci11_disasm.py disasm <script.NNN> [--start OFF] [--end OFF]
  sci11_disasm.py locals <heap.NNN>
  sci11_disasm.py objects <heap.NNN>
"""
import argparse
import struct
import sys

OPNAMES = """bnot add sub mul div mod shr shl xor and or neg not eq? ne? gt? ge? lt? le? ugt?
uge? ult? ule? bt bnt jmp ldi push pushi toss dup link call callk callb calle ret send dummy dummy
class dummy self super &rest lea selfID dummy pprev pToa aTop pTos sTop ipToa dpToa ipTos dpTos
lofsa lofss push0 push1 push2 pushSelf line lag lal lat lap lsg lsl lst lsp lagi lali lati lapi
lsgi lsli lsti lspi sag sal sat sap ssg ssl sst ssp sagi sali sati sapi ssgi ssli ssti sspi
+ag +al +at +ap +sg +sl +st +sp +agi +ali +ati +api +sgi +sli +sti +spi
-ag -al -at -ap -sg -sl -st -sp -agi -ali -ati -api -sgi -sli -sti -spi""".split()

NONE, BYTE, SBYTE, WORD, SWORD, VAR, SVAR, SREL, OFFS, END, INVALID = range(11)

# g_base_opcode_formats 逐格對照；Script_Variable/Property/Local/Temp/Global/Param/Offset
# 在解碼時行為相同（byte 或 word 看 extOpcode 低位元），統一記成 VAR。
FMT = [[NONE]] * 0x17 + [
    [SREL], [SREL], [SREL], [SVAR], [NONE], [SVAR], [NONE], [NONE], [VAR],   # 17..1F
    [SREL, BYTE], [VAR, BYTE], [VAR, BYTE], [VAR, SVAR, BYTE],               # 20..23
    [END], [BYTE], [INVALID], [INVALID],                                      # 24..27
    [VAR], [INVALID], [BYTE], [VAR, BYTE],                                    # 28..2B
    [SVAR], [SVAR, VAR], [NONE], [INVALID],                                   # 2C..2F
    [NONE], [VAR], [VAR], [VAR], [VAR], [VAR], [VAR], [VAR], [VAR],           # 30..38
    [OFFS], [OFFS], [NONE], [NONE], [NONE], [NONE], [WORD],                   # 39..3F
] + [[VAR]] * 0x40                                                            # 40..7F


def decode(buf, pos):
    """回傳 (指令名, [運算元], 長度)。"""
    ext = buf[pos]
    op = ext >> 1
    fmt = FMT[op]
    off = pos + 1
    params = []
    for f in fmt:
        if f in (NONE, END):
            break
        if f == INVALID:
            raise ValueError(f"invalid opcode {ext:02x} @ {pos:04x}")
        if f == BYTE:
            params.append(buf[off]); off += 1
        elif f == SBYTE:
            params.append(struct.unpack_from('<b', buf, off)[0]); off += 1
        elif f == WORD:
            params.append(struct.unpack_from('<H', buf, off)[0]); off += 2
        elif f == SWORD:
            params.append(struct.unpack_from('<h', buf, off)[0]); off += 2
        elif f in (VAR, OFFS):
            if ext & 1:
                params.append(buf[off]); off += 1
            else:
                params.append(struct.unpack_from('<H', buf, off)[0]); off += 2
        elif f in (SVAR, SREL):
            if ext & 1:
                params.append(struct.unpack_from('<b', buf, off)[0]); off += 1
            else:
                params.append(struct.unpack_from('<h', buf, off)[0]); off += 2
    return OPNAMES[op], params, off - pos


def heap_locals(path):
    b = open(path, 'rb').read()
    n = struct.unpack_from('<H', b, 4)[0]
    return [struct.unpack_from('<H', b, 6 + i * 2)[0] for i in range(n)], b


def cmd_locals(args):
    loc, _ = heap_locals(args.heap)
    print(f"{len(loc)} locals")
    for i in range(0, len(loc), 8):
        print(f"  L{i:<4}" + ' '.join(f'{v:6d}' for v in loc[i:i + 8]))


def cmd_objects(args):
    loc, b = heap_locals(args.heap)
    pos = 6 + len(loc) * 2
    while pos < len(b) - 1 and struct.unpack_from('<H', b, pos)[0] == 0x1234:
        nvars = struct.unpack_from('<H', b, pos + 2)[0]
        species = struct.unpack_from('<H', b, pos + 10)[0]
        print(f"  物件 @0x{pos:04x} vars={nvars} species={species}")
        pos += nvars * 2


def cmd_disasm(args):
    b = open(args.script, 'rb').read()
    pos = args.start
    end = args.end if args.end else len(b)
    while pos < end:
        try:
            name, params, ln = decode(b, pos)
        except (ValueError, struct.error, IndexError):
            print(f"{pos:04x}: .db {b[pos]:02x}")
            pos += 1
            continue
        raw = ' '.join(f'{x:02x}' for x in b[pos:pos + ln])
        ptxt = ' '.join(str(p) for p in params)
        extra = ''
        if name in ('bt', 'bnt', 'jmp'):
            extra = f"   -> {pos + ln + params[0]:04x}"
        print(f"{pos:04x}: {raw:<14} {name:<8} {ptxt}{extra}")
        pos += ln


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='cmd', required=True)
    d = sub.add_parser('disasm'); d.add_argument('script')
    d.add_argument('--start', type=lambda s: int(s, 0), default=0)
    d.add_argument('--end', type=lambda s: int(s, 0), default=0)
    d.set_defaults(func=cmd_disasm)
    l = sub.add_parser('locals'); l.add_argument('heap'); l.set_defaults(func=cmd_locals)
    o = sub.add_parser('objects'); o.add_argument('heap'); o.set_defaults(func=cmd_objects)
    args = ap.parse_args()
    args.func(args)


if __name__ == '__main__':
    sys.exit(main())
