#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
test_coverage_fp32addtree8to1 的专用比对脚本。

比对规则：
- Golden: case 目录下 output_data/bank<N>.hex
- UR 输出: case 目录下 ur_result_<case_name>_bank<N>.hex
- 数据 bit 分布参照 fp32_adder_tree_8_inputs_pipeline_8to1.v 输出：
  - o_dr_fp32addtree8to1_d[127:0] 为 128 位输出，每行包含 4 个完整的 FP32（每个 32 位）
  - 每行 32 个 hex 字符 = 128 bit = 4 × FP32（每个 FP32 8 个 hex 字符）
  - 每个 FP32 允许 1 ULP 误差。
- 每个 bank 逐行比对 4 个 FP32。
- 一个 case 下所有 bank 都通过才算该 case 通过。
"""
from __future__ import print_function

import os
import re
import sys
try:
    from io import open as _open
except ImportError:
    _open = open

# Python 2/3 兼容的 UTF-8 文件读取
if sys.version_info[0] < 3:
    import codecs
    def open_utf8(filepath, mode='r'):
        return codecs.open(filepath, mode, encoding='utf-8')
else:
    def open_utf8(filepath, mode='r'):
        return _open(filepath, mode, encoding='utf-8')

def safe_print(*args, **kwargs):
    """安全打印，遇 UnicodeEncodeError 时用 safe_str 转 ASCII 或跳过输出。"""
    def safe_str(s):
        if sys.version_info[0] < 3:
            if isinstance(s, unicode):
                try:
                    return s.encode('ascii', 'replace')
                except:
                    return '?'
            elif isinstance(s, str):
                try:
                    return s.decode('utf-8', 'replace').encode('ascii', 'replace')
                except:
                    try:
                        return s.decode('latin-1', 'replace').encode('ascii', 'replace')
                    except:
                        return ''.join(c if ord(c) < 128 else '?' for c in s)
            else:
                try:
                    s_str = str(s)
                    return s_str.encode('ascii', 'replace') if isinstance(s_str, unicode) else safe_str(s_str)
                except:
                    return '?'
        else:
            if isinstance(s, str):
                try:
                    return s.encode('ascii', 'replace').decode('ascii')
                except:
                    return '?'
            elif isinstance(s, bytes):
                try:
                    return s.decode('utf-8', 'replace').encode('ascii', 'replace').decode('ascii')
                except:
                    return '?'
            else:
                try:
                    return str(s).encode('ascii', 'replace').decode('ascii')
                except:
                    return '?'
    try:
        print(*args, **kwargs)
    except (UnicodeEncodeError, UnicodeDecodeError, UnicodeError):
        try:
            safe_args = [safe_str(a) for a in args]
            print(*safe_args, **kwargs)
        except:
            pass


def normalize_hex_line(line):
    """去掉首尾空白并转为大写。空行保留为空字符串。"""
    s = line.strip()
    return s.upper() if s else ""


# 每行 32 个 hex 字符 = 128 bit = 4 个完整的 FP32（每个 FP32 32 位 = 8 个 hex 字符）
NUM_FP32_PER_LINE = 4
HEX_CHARS_PER_FP32 = 8


def parse_line_to_fp32(line):
    """
    从一行（32 hex 字符）解析出 4 个 FP32 的 32 位整型表示。
    与 RTL 一致：o_dr_fp32addtree8to1_d[127:0] = {FP32[3], FP32[2], FP32[1], FP32[0]}
    每行格式：[31:0]=FP32[0], [63:32]=FP32[1], [95:64]=FP32[2], [127:96]=FP32[3]
    
    Returns:
        list of 4 int (32-bit FP32 bits), 若解析失败返回 None。
    """
    if len(line) != 32:
        return None
    result = []
    for i in range(NUM_FP32_PER_LINE):
        start = i * HEX_CHARS_PER_FP32
        end = start + HEX_CHARS_PER_FP32
        try:
            fp32_bits = int(line[start:end], 16)
            result.append(fp32_bits & 0xFFFFFFFF)
        except ValueError:
            return None
    return result


def compare_fp32_with_ulp(golden_bits, ur_bits):
    """
    比对两个 FP32 的 32 位表示，允许 1 ULP 误差。
    
    Returns:
        (passed: bool, error_msg: str)
    """
    if golden_bits == ur_bits:
        return True, ""
    diff = abs(golden_bits - ur_bits)
    if diff != 1:
        return False, "golden=0x{:08X} ur=0x{:08X} diff={}".format(
            golden_bits & 0xFFFFFFFF, ur_bits & 0xFFFFFFFF, diff)
    return True, ""


def compare_one_line(golden_line, ur_line, line_idx):
    """
    比对一行重构的 4 个 FP32，允许每个 1 ULP。
    
    Returns:
        (passed: bool, message: str)
    """
    g_list = parse_line_to_fp32(golden_line)
    u_list = parse_line_to_fp32(ur_line)
    if g_list is None:
        return False, "第 {} 行: golden 解析失败 (长度非 32 hex 字符或 hex 无效)".format(line_idx + 1)
    if u_list is None:
        return False, "第 {} 行: ur 解析失败 (长度非 32 hex 字符或 hex 无效)".format(line_idx + 1)
    for j in range(NUM_FP32_PER_LINE):
        passed, msg = compare_fp32_with_ulp(g_list[j], u_list[j])
        if not passed:
            return False, "第 {} 行 元素[{}]: {}".format(line_idx + 1, j, msg)
    return True, ""


def get_banks_from_output_data(case_dir):
    """从 case_dir/output_data/ 中读取所有 bank<N>.hex 的编号列表（已排序）。"""
    output_data_dir = os.path.join(case_dir, "output_data")
    banks = []
    if not os.path.isdir(output_data_dir):
        return banks
    bank_pattern = re.compile(r'^bank(\d+)\.hex$', re.IGNORECASE)
    for item in os.listdir(output_data_dir):
        match = bank_pattern.match(item)
        if match:
            banks.append(int(match.group(1)))
    return sorted(banks)


def read_hex_lines(filepath):
    """读取 hex 文件，返回规范化后的非空行列表。"""
    try:
        with _open(filepath, "r", encoding="utf-8") as f:
            lines = [normalize_hex_line(ln) for ln in f.readlines()]
    except IOError:
        return None
    return [ln for ln in lines if ln]


def compare_case_single_bank(case_dir, case_name, bank):
    """
    比对一个 bank：
    golden: output_data/bank{bank}.hex
    ur:     ur_result_<case_name>_bank{bank}.hex
    逐行比对 4 个 FP32，允许 1 ULP。
    
    Returns:
        (passed: bool, message: str)
    """
    golden_path = os.path.join(case_dir, "output_data", "bank{}.hex".format(bank))
    ur_path = os.path.join(case_dir, "ur_result_{}_bank{}.hex".format(case_name, bank))

    if not os.path.isfile(golden_path):
        return False, "缺少文件: output_data/bank{}.hex".format(bank)
    if not os.path.isfile(ur_path):
        return False, "缺少文件: ur_result_{}_bank{}.hex".format(case_name, bank)

    g_lines = read_hex_lines(golden_path)
    u_lines = read_hex_lines(ur_path)
    if g_lines is None:
        return False, "读取 golden bank{} 失败".format(bank)
    if u_lines is None:
        return False, "读取 ur_result bank{} 失败".format(bank)

    if len(u_lines) < len(g_lines):
        return False, "UR 行数不足: golden {} 行, ur {} 行".format(len(g_lines), len(u_lines))

    for i in range(len(g_lines)):
        passed, msg = compare_one_line(g_lines[i], u_lines[i], i)
        if not passed:
            return False, "bank{} {}".format(bank, msg)

    return True, ""


def compare_case(case_dir, case_name, bank=None):
    """
    比对该 case 的 output_data 与 ur_result_<case_name>_bank<N>.hex（fp32addtree8to1 模式：每行 4 个 FP32，允许 1 ULP）。
    
    Args:
        case_dir: case 文件夹的完整路径
        case_name: case 名称
        bank: 未使用（自动按 output_data 的 bank 比对）
    
    Returns:
        (passed: bool, message: str)
    """
    # 以 output_data 的 bank 为准，逐个比对；UR 文件为 ur_result_<case_name>_bank<N>.hex
    banks_out = get_banks_from_output_data(case_dir)

    if not banks_out:
        return False, "output_data/ 中未找到 bank<N>.hex 文件"

    all_passed = True
    failed = []
    for b in banks_out:
        passed, msg = compare_case_single_bank(case_dir, case_name, b)
        if not passed:
            all_passed = False
            failed.append("bank{} ({})".format(b, msg))
        else:
            safe_print("  [{}] bank{} 比对通过".format(case_name, b))

    if all_passed:
        safe_print("  [{}] 所有 bank 比对通过".format(case_name))
        return True, ""
    return False, "失败的 bank: {}".format("; ".join(failed))
