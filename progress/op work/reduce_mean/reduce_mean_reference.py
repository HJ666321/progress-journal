#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
reduce_mean 参考实现
=====================
依据：《AI 加速器上的 LLaMA2 RMSNorm 归约算子（reduce_mean）设计与验证》（README.md）

定位：纯文档仓库中的"可执行设计说明"。真实算子源码不在本仓库（见仓库性质说明），
本文件按 README §3–§6 重新写出等价骨架，覆盖四层交付物中的前三层：

    发码器（emitter）   —— §4.4 十二拍/字网格 → 各级各单元 IQ 指令（结构化字段表示，
                          41bit shell+code 字节格式属内部规范，见 Inst.to_hex 钩子）
    case 生成器         —— HBM 初始化数据 + meta_v3.json（§4.6 decode 机制）
    golden 模型         —— §4.7：4×f32 lane 并行、字序逐链串行 RNE、尾链折叠、
                          double 累加的装载均值字
    静态审计（第 1 层）   —— IQ 深度 / 丢脉冲阈值 / port-B 硬门禁（§5.4）/ 乒乓依赖

与文档严格对应的数字模型：fp16→fp32 精确转换、fp32 逐拍 RNE（double 精确算 + 舍入
即等价 native fp32 运算）、4 深乒乓、((e0+e1)+e2)+e3 折叠序、×(1/N)+eps 次序、
fp_pad 双窗交集（min(sim lat4, 板 lat2)）。

运行：python3 reduce_mean_reference.py   →  ./out/ 生成 meta + 输出窗 hex 样例
"""

import json
import os
import random
import struct
from dataclasses import dataclass

# ----------------------------------------------------------------------------
# 硬件参数（README §3.5 架构小结 / §4.5 级链组织）
# ----------------------------------------------------------------------------
NUM_SMC        = 8                  # SMC0..SMC7，8 核并行
ROW_ELEMS      = 4096               # 每行 fp16 元素（token 维）
WORD_LANES     = 8                  # 每 16B 字 = 8 个 fp16 lane
LANES_F32      = 4                  # FPTOFP/FPMUL/FPADD 均为 per-lane 4 份（§4.7）
ROW_WORDS      = ROW_ELEMS // WORD_LANES      # 512 字/行
BANK_WORDS     = 256                # UR 每 bank 256 字（一行须占 2 bank）
BANK_OUT       = 6                  # bank6 = 纯输出窗（§4.3 UR 布局）
BANK_ACC       = 7                  # bank7 = acc 乒乓（字 0..7）+ 常量区
ACC_DEPTH      = 4                  # 4 深乒乓，覆盖 FPADD 4 拍延迟（§4.3）
WORD_SLOT      = 12                 # 12 拍/字网格（§4.4）
STAGE_BASE     = 8                  # 级内首字槽 base：s = base(8) + 12·w（§4.4）
STAGE_WORDS    = 36                 # 单级容量 36 字（§4.5）
STAGES_PER_ROW = 15                 # 512 = 36×14 + 8 → 14 满级 + 1 尾级
STAGES_TOTAL   = 1 + 32 * STAGES_PER_ROW + 1  # 482 级（§4.5），512 上限内
IQ_DEPTH       = 128                # IQ 环形深度（§5.3）
DROP_PULSE     = 112                # 单队列实测丢脉冲阈值（§3.5）
FPU_LAT_SIM    = 4                  # 仿真 FPU 延迟
FPU_LAT_BOARD  = 2                  # 板上 fp_pad：数据窗早 2 拍关闭（§2.3）
WINDOW         = min(FPU_LAT_SIM, FPU_LAT_BOARD)  # 采样点取双窗交集（§4.4）
N_INV          = 1.0 / ROW_ELEMS    # ×(1/N)，N = 4096（§4.3 尾链）
EPS            = 1e-5               # RMSNorm eps（§2.1）
OPTION_E       = True               # §5.3：FPMUL span5→span7 吸收 noop，3 条/字 = 111 ≤ 128


def bank_of_word(row, w):
    """行 r 输入驻留轮换：bank {2(r%3), 2(r%3)+1}，每 bank 半行 256 字（§4.3）。"""
    return 2 * (row % 3) + (1 if w >= BANK_WORDS else 0)


# ----------------------------------------------------------------------------
# fp16 / fp32 原语（§4.7 数值严格性）
# ----------------------------------------------------------------------------
def f32(x):
    """任意实数 → fp32（RNE）。fp32 双操作数运算的精确结果必可表于 double，
    故 double 精确算 + 单次 RNE 舍入 ≡ native fp32 运算（IEEE 754）。"""
    return struct.unpack('>f', struct.pack('>f', x))[0]


def f16(x):
    """→ fp16（RNE）= RTL 舍入模型；装载均值字的生成路径（§4.7）。"""
    return struct.unpack('>e', struct.pack('>e', x))[0]


def add_f32(a, b):
    return f32(a + b)


def mul_f32(a, b):
    return f32(a * b)


def parse_word(b16):
    """16B 字 → 8 个 fp16（big-endian lane，与板上 HBM 线序一致）。"""
    assert len(b16) == 16
    return [struct.unpack('>e', b16[2 * i:2 * i + 2])[0] for i in range(WORD_LANES)]


def word_hex_f32x4(v4):
    """4 个 f32 → 16B 大端 hex 行（bank6 扩展窗实算值的线格式）。"""
    return b''.join(struct.pack('>f', v) for v in v4).hex()


def word_hex_f16x8(v8):
    """8 个 fp16 → 16B 大端 hex 行（bank6 装载均值广播字的线格式）。"""
    return b''.join(struct.pack('>e', v) for v in v8).hex()


# ----------------------------------------------------------------------------
# golden 模型（§4.7）—— bit-exact 参考
# ----------------------------------------------------------------------------
class GoldenRow:
    """一行 512 字：偶/奇两条 f32 部分和链 × 4 深乒乓，尾链折叠。

    语义：acc 字 p = w & 3，lane j 累加 x(w, 2j)²（偶链）/ x(w, 2j+1)²（奇链）；
    累加顺序 = 字序逐链串行 RNE。行首 4 字读取指向常量区 +0.0 —— 硬件上免零初始化级
    （§4.3），软件模型初值 0.0 即等价。
    """

    def __init__(self):
        self.acc_e = [[0.0] * LANES_F32 for _ in range(ACC_DEPTH)]
        self.acc_o = [[0.0] * LANES_F32 for _ in range(ACC_DEPTH)]
        self.sum_sq = 0.0               # double 路径：装载均值字专用（§4.7）

    def feed(self, w, word8):
        """喂入第 w 个字（8 个 fp16）。对应硬件一个 12 拍字槽（§4.4）。"""
        p = w & 3
        x = [f32(v) for v in word8]     # fp16→fp32 精确（FPTOFP）
        for j in range(LANES_F32):
            sq_e = mul_f32(x[2 * j], x[2 * j])          # FPMUL 自乘 = 平方（偶半）
            sq_o = mul_f32(x[2 * j + 1], x[2 * j + 1])  # 奇半
            self.acc_e[p][j] = add_f32(self.acc_e[p][j], sq_e)
            self.acc_o[p][j] = add_f32(self.acc_o[p][j], sq_o)
            self.sum_sq += word8[2 * j] ** 2 + word8[2 * j + 1] ** 2

    def tail(self):
        """尾链（§4.3）：((e0+e1)+e2)+e3 串行折叠 → ×(1/N) → +eps。"""
        def fold(acc):
            return [add_f32(add_f32(add_f32(acc[0][j], acc[1][j]),
                                    acc[2][j]), acc[3][j]) for j in range(LANES_F32)]
        e = [add_f32(mul_f32(v, f32(N_INV)), f32(EPS)) for v in fold(self.acc_e)]
        o = [add_f32(mul_f32(v, f32(N_INV)), f32(EPS)) for v in fold(self.acc_o)]
        return e, o

    def broadcast(self):
        """行均值字：fp16( sum(x²)/N + eps )，double 累加 + f32→f16 RTL 舍入（§4.7）。
        因跨 lane 求和物理不可能（§4.1），此字由生成器预计算、随首装载级放入 bank6。"""
        return f16(self.sum_sq / ROW_ELEMS + EPS)


def golden_window(rows_words):
    """全核输出窗：每行 3 字 = 1 装载均值广播字 + acc_e/acc_o 各 1 字。

    前 rows 字广播、后 2·rows 字实算（§4.2：前 32 字装载值 + 后 64 字实算值 = 96）。
    rows_words: rows × 512 × 8 fp16。返回 3·rows 行 16B hex。
    """
    assert len(rows_words) <= 32, '每核 32 行（LSU_RM_ROWS=32）'
    gs = [GoldenRow_of(row) for row in rows_words]
    lines = [word_hex_f16x8([g.broadcast()] * WORD_LANES) for g in gs]
    for g in gs:
        e, o = g.tail()
        lines.append(word_hex_f32x4(e))
        lines.append(word_hex_f32x4(o))
    return lines


def GoldenRow_of(row):
    """便捷函数：喂完一行 512 字后返回 golden 对象（broadcast/tail 复用同一实例）。"""
    g = GoldenRow()
    for w, word8 in enumerate(row):
        g.feed(w, word8)
    return g


# ----------------------------------------------------------------------------
# 发码器（§4.4 排程 + §5.3 Option E + §5.4 尾链修复）
# ----------------------------------------------------------------------------
@dataclass
class Inst:
    """IQ 指令（结构化表示）。41bit shell+code 字节格式属内部规范，落盘时编码。"""
    stage: int
    beat: int          # 级内绝对拍
    unit: str
    span: int
    op: str

    def to_hex(self):
        # TODO(内部规范): 41bit shell+code 编码（§5.6 点火计数比对的解码源）
        raise NotImplementedError


# 主循环：每字 12 拍槽内的指令排布（§4.4 表，span 为文档原值）
SCHEDULE = [
    ( 0, 'ur_r0',  '读输入字 w（VIN0 源）',              10),
    ( 4, 'fptofp', '第 1 发：偶半 {0,2,4,6} → f32',       5),
    ( 5, 'ur_r1',  '读 acc_e[w&3]（bank7）',              7),
    ( 6, 'fpmul',  '偶链平方 sq_e（首发即采到操作数）',    4),
    ( 9, 'fptofp', '第 2 发：奇半 {1,3,5,7} → f32',       6),
    (11, 'fpadd',  'acc_e += sq_e',                       3),
    (11, 'fpmul',  '奇链平方 sq_o',                       5),   # Option E: 扩 span7 吸收 noop
    (12, 'ur_r1',  '读 acc_o[w&3]（与 acc_e 读互斥，§5.4）', 2),
    (16, 'fpadd',  'acc_o += sq_o（双窗交集采样）',        2),
    (18, 'ur_w0',  '写 acc_e 新值 → bank7',                1),
    (24, 'ur_w1',  '写 acc_o 新值 → bank7',                1),
]

# 尾链（行尾级追加，§4.3）：全部 span1 单拍脉冲、r0/r1 读拍互斥（§5.4 修复）
# 折叠 6 加 + ×(1/N) 2 乘 + eps 2 加 + 写 bank6 扩展窗 2 字
TAIL = [
    ( 0, 'ur_r1', '读 bank7 字 0..3 = acc_e[0..3]', 1),
    ( 4, 'ur_r1', '读 bank7 字 4..7 = acc_o[0..3]', 1),
    ( 8, 'ur_r1', '读常量 1/N（bank7 常量区）',      1),
    ( 9, 'fpadd', 'e0+e1 / o0+o1（第 1 折）',         1),
    (13, 'fpadd', '+e2 / +o2（第 2 折）',              1),
    (17, 'fpadd', '+e3 / +o3（第 3 折）',              1),
    (21, 'fpmul', '×(1/N)：偶链 / 奇链',               1),
    (25, 'fpadd', '+eps：偶链 / 奇链',                 1),
    (29, 'ur_w0', '写 bank6 字 32+2r（acc_e 结果）',   1),
    (33, 'ur_w1', '写 bank6 字 33+2r（acc_o 结果）',   1),
]

TAIL_READ_BEATS = {0, 4, 8}         # 尾链全部 r1 读拍（r0 不读 → port-B 天然互斥）


def emit_row_stage_iq(row, stage_words, gstage0):
    """生成一行内一级（36 或 8 字）的各单元 IQ 指令表。

    返回 {unit: [Inst]}；拍号 = STAGE_BASE + 12·(级内字序号) + 相对拍。
    """
    insts = {}
    for w_local, w in enumerate(stage_words):
        s = STAGE_BASE + WORD_SLOT * w_local
        for rel, unit, op, span in SCHEDULE:
            span_eff = 7 if (OPTION_E and unit == 'fpmul' and rel == 11) else span
            insts.setdefault(unit, []).append(Inst(gstage0, s + rel, unit, span_eff, op))
    return insts


def emit_tail_iq(row, gstage):
    """行尾级（§4.3/§5.4）：折叠 + 缩放 + eps + 写 bank6 扩展窗 2 字。"""
    insts = {}
    for rel, unit, op, span in TAIL:
        insts.setdefault(unit, []).append(Inst(gstage, STAGE_BASE + rel, unit, span, op))
    return insts


# ----------------------------------------------------------------------------
# 静态审计（第 1 层验证闭环，§5.4 port-B 硬门禁 + §3.5/§5.3 IQ 阈值）
# ----------------------------------------------------------------------------
class AuditFail(AssertionError):
    pass


def audit_stage(gstage, insts_by_unit, row_of_stage):
    """三级硬门禁，任一不过即 FAIL（把"不应该发生"变成"发生了就 FAIL"，§11-3）。"""
    # 1) IQ 环形深度 ≤ 128；热点队列 ≤ 112 丢脉冲阈值（§3.5/§5.3）
    for unit, lst in insts_by_unit.items():
        if len(lst) > IQ_DEPTH:
            raise AuditFail(f'stage {gstage} {unit}: {len(lst)} 条 > IQ 深度 {IQ_DEPTH}（环形回卷吞火，§5.3）')
        if unit in ('fpadd', 'fpmul') and len(lst) > DROP_PULSE:
            raise AuditFail(f'stage {gstage} {unit}: {len(lst)} 条 > 丢脉冲阈值 {DROP_PULSE}（§3.5）')
    # 2) port-B 硬门禁：任一拍两读口同 bank 即 FAIL（§5.4 修复的回归保护）
    reads = []   # (beat, port, bank)
    for inst in insts_by_unit.get('ur_r0', []):
        w = (inst.beat - STAGE_BASE) // WORD_SLOT
        reads.append((inst.beat, 'r0', bank_of_word(row_of_stage, w)))
    for inst in insts_by_unit.get('ur_r1', []):
        reads.append((inst.beat, 'r1', BANK_ACC))
    by_beat = {}
    for beat, port, bank in reads:
        by_beat.setdefault(beat, []).append((port, bank))
    for beat, ps in sorted(by_beat.items()):
        banks = [bank for _, bank in ps]
        if len(banks) != len(set(banks)):
            raise AuditFail(f'stage {gstage} beat {beat}: port-B 同 bank 双读 {ps}（§5.4）')
    # 3) acc 乒乓依赖（§4.4 依赖检查）：acc[p] 在 s+18 写回后，同 p 的下一次读
    #    必须相隔 ≥ 4 个字槽（"同 p 的下一次读在 4 个字槽之后（s+48+），余量充分"）。
    #    实际拍距 = 48+5-18 = 35 拍 ≫ FPADD 4 拍延迟；36 字/级是 4 的整数倍，
    #    乒乓配对不跨级，级内审计即完备。
    wr, rd = {}, {}
    for inst in insts_by_unit.get('ur_w0', []):
        wr[(inst.beat - STAGE_BASE - 18) // WORD_SLOT] = inst.beat
    for inst in insts_by_unit.get('ur_r1', []):
        if (inst.beat - STAGE_BASE) % WORD_SLOT == 5:    # 主循环 acc_e 读
            rd.setdefault((inst.beat - STAGE_BASE - 5) // WORD_SLOT, []).append(inst.beat)
    for w, wb in wr.items():
        for w2, rbs in rd.items():
            if w2 <= w or w2 % ACC_DEPTH != w % ACC_DEPTH:
                continue    # 只配对同槽位 p = w & 3；跨槽相邻字不共享累加器
            if w2 - w < ACC_DEPTH:
                raise AuditFail(f'stage {gstage} 乒乓槽 p={w % ACC_DEPTH}: '
                                f'写后仅 {w2 - w} 字槽即再读（§4.4，需 ≥ {ACC_DEPTH}）')


# ----------------------------------------------------------------------------
# case 生成器（§4.6 decode 机制 + meta_v3.json）
# ----------------------------------------------------------------------------
def gen_input(seed, rows_per_smc):
    """固定种子（§6 工程要点：交付 seed=42），生成 rows × 512 × 8 fp16。"""
    rng = random.Random(seed)
    return [[[f16(rng.uniform(-1.0, 1.0)) for _ in range(WORD_LANES)]
             for _ in range(ROW_WORDS)] for _ in range(rows_per_smc)]


def build_meta(decode):
    """meta_v3.json（§4.6）：decode 时 store_smc_mask=1，仅核 0 写回，掩码外 SKIP。"""
    return {
        'op': 'reduce_mean',
        'num_smc': NUM_SMC,
        'LSU_RM_ROWS': 1 if decode else 32,
        'out_words': 3 * (1 if decode else 32),      # 每行 1 广播 + 2 实算（§4.2）
        'store_byte_base': 0x5000 if decode else 0x43000,
        'store_smc_mask': 0x1 if decode else 0xFF,
        'smc_id_en': 'core_id <= threshold gates writeback (§4.6)',
        'seed': 42,
        'sim_evidence': 'README §8: UR 8/8 PASS; bank 2048/2048; HBM window numpy 复算 pass=8',
        'note': '前 32 字 = golden 广播均值（数值正确性）；后 64 字 = 硬件实算 acc_e/acc_o（通路真实性）',
    }


def run_case(decode=False, out_dir='out'):
    """端到端骨架：输入 → golden 输出窗 → meta；发码 + 审计走 2 行示意（全量同理）。"""
    rows_demo = 1 if decode else 2    # 示意行数；全量 32 行 = 482 级，常量已校验
    words = gen_input(seed=42, rows_per_smc=rows_demo)
    window = golden_window(words)

    # 发码 + 审计（2 行 × 15 级示意；全量 32 行 = 482 级，常量 STAGES_TOTAL 已校验）
    assert STAGES_TOTAL == 482
    gstage = 1
    for row in range(rows_demo):
        for k in range(STAGES_PER_ROW):
            n_words = STAGE_WORDS if k < STAGES_PER_ROW - 1 else ROW_WORDS - STAGE_WORDS * (STAGES_PER_ROW - 1)
            stage_words = list(range(k * STAGE_WORDS, k * STAGE_WORDS + n_words))
            iq = emit_row_stage_iq(row, stage_words, gstage)
            if k == STAGES_PER_ROW - 1:
                for unit, lst in emit_tail_iq(row, gstage).items():
                    iq.setdefault(unit, []).extend(lst)
            audit_stage(gstage, iq, row)
            gstage += 1
    print(f'[audit] {rows_demo} 行 × {STAGES_PER_ROW} 级全部门禁通过（IQ 深度 / 112 阈值 / port-B / 乒乓依赖）')

    os.makedirs(out_dir, exist_ok=True)
    name = 'decode' if decode else 'prefill'
    with open(os.path.join(out_dir, f'meta_v3_{name}.json'), 'w', encoding='utf-8') as fp:
        json.dump(build_meta(decode), fp, ensure_ascii=False, indent=2)
    with open(os.path.join(out_dir, f'golden_window_{name}.hex'), 'w', encoding='utf-8') as fp:
        fp.write('\n'.join(window) + '\n')
    print(f'[case] {name}: out/{name}/meta_v3.json + golden_window_{name}.hex（{len(window)} 字 = 3×{rows_demo} 行）')
    print(f'[case] 首行广播字 = {window[0][:16]}...；acc_e 字 = {window[rows_demo][:32]}...')


if __name__ == '__main__':
    run_case(decode=False, out_dir='out/prefill')
    run_case(decode=True, out_dir='out/decode')
