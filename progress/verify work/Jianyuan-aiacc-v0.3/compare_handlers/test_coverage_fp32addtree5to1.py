#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
test_coverage_fp32addtree5to1 的专用比对脚本。

比对规则：
- Golden: 子 case 的 output_data 路径下固定两个 hex 文件：
  - bank4.hex：每行 128 bit = 8×16 bit，为 8 个 FP32 的**低 16 位**（d0）；
  - bank5.hex：每行 128 bit = 8×16 bit，为 8 个 FP32 的**高 16 位**（d1）。
- UR 输出: case 目录下 ur_result_<case_name>_bank4.hex、ur_result_<case_name>_bank5.hex（格式同 bank4/bank5）。
- 两文件按行一一对应：第 i 行 bank4 + 第 i 行 bank5 拼成 8 个 FP32，与 UR 的 bank4/bank5 第 i 行拼成的 8 个 FP32 逐值对比，误差允许 1 个 ULP。

Bit 布局（与 RTL 一致：d0=add_result[15:0], d1=add_result[31:16]）：
  - bank4 第 i 行 = d0 行（32 hex）= 8×16 bit 低半字；
  - bank5 第 i 行 = d1 行（32 hex）= 8×16 bit 高半字；
  - FP32[j] = (bank5 第 i 行第 j 个 16bit << 16) | bank4 第 i 行第 j 个 16bit，j=0..7。
"""
from __future__ import print_function

import os
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


# 每行 32 个 hex 字符 = 128 bit。RTL 中 8 个 FP32：每个占 16bit 在 d0/d1 中，即每 4 个 hex 字符一个 16bit。
# FP32[i] = (d1_line[i*4:(i+1)*4] << 16) | d0_line[i*4:(i+1)*4]
NUM_FP32_PER_LINE = 8
HEX_CHARS_PER_16BIT = 4
HEX_CHARS_PER_FP32 = 8  # 每个 FP32 32 bit = 8 hex 字符


def parse_line_pair_to_fp32(d0_line, d1_line):
    """
    从一对 d0/d1 行（各 32 hex 字符）解析出 8 个 FP32 的 32 位整型表示。
    与 RTL 一致：d0[out_idx*16+:16]=add_result[out_idx][15:0], d1[out_idx*16+:16]=add_result[out_idx][31:16]。
    
    Returns:
        list of 8 int (32-bit FP32 bits), 若解析失败返回 None。
    """
    if len(d0_line) != 32 or len(d1_line) != 32:
        return None
    result = []
    for i in range(NUM_FP32_PER_LINE):
        start = i * HEX_CHARS_PER_16BIT
        end = start + HEX_CHARS_PER_16BIT
        try:
            low16 = int(d0_line[start:end], 16)
            high16 = int(d1_line[start:end], 16)
            fp32_bits = (high16 << 16) | low16
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


def compare_one_line_pair(golden_d0, golden_d1, ur_d0, ur_d1, line_idx):
    """
    比对一对 (d0,d1) 行重构的 8 个 FP32，允许每个 1 ULP。
    
    Returns:
        (passed: bool, message: str)
    """
    g_list = parse_line_pair_to_fp32(golden_d0, golden_d1)
    u_list = parse_line_pair_to_fp32(ur_d0, ur_d1)
    if g_list is None:
        return False, "第 {} 行: golden 解析失败 (d0长度={}, d1长度={}, d0={}, d1={})".format(
            line_idx + 1, len(golden_d0) if golden_d0 else 0, len(golden_d1) if golden_d1 else 0,
            golden_d0[:20] if golden_d0 else "None", golden_d1[:20] if golden_d1 else "None")
    if u_list is None:
        return False, "第 {} 行: ur 解析失败 (d0长度={}, d1长度={}, d0={}, d1={})".format(
            line_idx + 1, len(ur_d0) if ur_d0 else 0, len(ur_d1) if ur_d1 else 0,
            ur_d0[:20] if ur_d0 else "None", ur_d1[:20] if ur_d1 else "None")
    for j in range(NUM_FP32_PER_LINE):
        passed, msg = compare_fp32_with_ulp(g_list[j], u_list[j])
        if not passed:
            return False, "第 {} 行 元素[{}]: {}".format(line_idx + 1, j, msg)
    return True, ""


# output_data 中固定使用 bank4.hex（低 16bit）与 bank5.hex（高 16bit）
BANK_D0 = 4
BANK_D1 = 5


def has_bank4_bank5_in_output_data(case_dir):
    """检查子 case 的 output_data 中是否存在 bank4.hex 与 bank5.hex。"""
    output_data_dir = os.path.join(case_dir, "output_data")
    if not os.path.isdir(output_data_dir):
        return False
    path4 = os.path.join(output_data_dir, "bank4.hex")
    path5 = os.path.join(output_data_dir, "bank5.hex")
    return os.path.isfile(path4) and os.path.isfile(path5)


def read_hex_lines(filepath):
    """读取 hex 文件，返回规范化后的非空行列表。"""
    try:
        with _open(filepath, "r", encoding="utf-8") as f:
            lines = [normalize_hex_line(ln) for ln in f.readlines()]
    except IOError:
        return None
    return [ln for ln in lines if ln]


def compare_case_bank4_bank5(case_dir, case_name):
    """
    用 output_data 中的 bank4.hex（低 16bit）与 bank5.hex（高 16bit）作为 golden，
    与 ur_result_*_bank4.hex、ur_result_*_bank5.hex 逐行比对，每行 8 个 FP32，允许 1 ULP。
    
    Returns:
        (passed: bool, message: str)
    """
    out_dir = os.path.join(case_dir, "output_data")
    golden_d0_path = os.path.join(out_dir, "bank4.hex")
    golden_d1_path = os.path.join(out_dir, "bank5.hex")
    ur_d0_path = os.path.join(case_dir, "ur_result_{}_bank4.hex".format(case_name))
    ur_d1_path = os.path.join(case_dir, "ur_result_{}_bank5.hex".format(case_name))

    for p, name in [
        (golden_d0_path, "output_data/bank4.hex"),
        (golden_d1_path, "output_data/bank5.hex"),
        (ur_d0_path, "ur_result_{}_bank4.hex".format(case_name)),
        (ur_d1_path, "ur_result_{}_bank5.hex".format(case_name)),
    ]:
        if not os.path.isfile(p):
            return False, "缺少文件: {}".format(name)

    g_d0_lines = read_hex_lines(golden_d0_path)
    g_d1_lines = read_hex_lines(golden_d1_path)
    u_d0_lines = read_hex_lines(ur_d0_path)
    u_d1_lines = read_hex_lines(ur_d1_path)
    if g_d0_lines is None:
        return False, "读取 golden bank4.hex 失败"
    if g_d1_lines is None:
        return False, "读取 golden bank5.hex 失败"
    if u_d0_lines is None:
        return False, "读取 ur_result bank4 失败"
    if u_d1_lines is None:
        return False, "读取 ur_result bank5 失败"

    n_g = min(len(g_d0_lines), len(g_d1_lines))
    n_u = min(len(u_d0_lines), len(u_d1_lines))
    if n_u < n_g:
        return False, "UR 行数不足: golden {} 行, ur {} 行".format(n_g, n_u)

    for idx in range(n_g):
        if len(g_d0_lines[idx]) != 32 or len(g_d1_lines[idx]) != 32:
            return False, "golden 第 {} 行长度错误: 期望 32 hex".format(idx + 1)
        if len(u_d0_lines[idx]) != 32 or len(u_d1_lines[idx]) != 32:
            return False, "UR 第 {} 行长度错误: 期望 32 hex".format(idx + 1)

    for i in range(n_g):
        passed, msg = compare_one_line_pair(
            g_d0_lines[i], g_d1_lines[i], u_d0_lines[i], u_d1_lines[i], i)
        if not passed:
            return False, "第 {} 行: {}".format(i + 1, msg)

    return True, ""


def compare_case(case_dir, case_name, bank=None):
    """
    比对该子 case 的 output_data 中的 bank4.hex（低 16bit）与 bank5.hex（高 16bit）
    与 ur_result_*_bank4.hex、ur_result_*_bank5.hex 逐行比对，每行 8 个 FP32，允许 1 ULP。
    
    Args:
        case_dir: 子 case 文件夹的完整路径（golden 为 case_dir/output_data/bank4.hex、bank5.hex）
        case_name: case 名称
        bank: 未使用
    
    Returns:
        (passed: bool, message: str)
    """
    if not has_bank4_bank5_in_output_data(case_dir):
        return False, "子 case 的 output_data/ 中未找到 bank4.hex 与 bank5.hex"

    passed, msg = compare_case_bank4_bank5(case_dir, case_name)
    if passed:
        safe_print("  [{}] bank4/bank5 比对通过".format(case_name))
        return True, ""
    return False, msg
