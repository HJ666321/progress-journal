#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
test_coverage_intadd 的专用比对脚本。

比对规则：
- 比对前从 test_coverage_intadd/cases_summary.md 读取每个子 case 的 Mode：Mode=0 为 4b，Mode=3 为 32b
- 在当前 case 路径下直接检测 bank*.hex 文件名，与 UR 输出 ur_result_<case_name>_bank<N>.hex 中 bank 编号一致的逐对比对
- Mode=4b：奇数行（第1、3、5…行）按 4bit 比对，拆成 32 个数（每数 1 个 hex），每个数允许 1 ULP（相差≤1）；偶数行严格一致
- Mode=32b：每行 4 个 int32，每个 int32 允许 1 ULP（相差 1）以内
- 一个 case 的所有 bank 都通过才算该 case 通过
"""
from __future__ import print_function

import os
import re
import sys
try:
    from io import open as _open
except ImportError:
    _open = open

from base_handler import get_case_folders, normalize_hex_line

# Python 2/3 兼容的 UTF-8 文件读取（与 skill 一致，供本模块或后续扩展使用）
if sys.version_info[0] < 3:
    import codecs
    def open_utf8(filepath, mode='r'):
        return codecs.open(filepath, mode, encoding='utf-8')
else:
    def open_utf8(filepath, mode='r'):
        return _open(filepath, mode, encoding='utf-8')

# 安全的打印函数，自动处理编码错误（与 skill 一致）
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


def parse_cases_summary_intadd(coverage_dir):
    """
    解析 coverage_dir/cases_summary.md，提取每个子 case 的 Mode。
    表格列：Case | Mode | Op | ST | Description；Mode 列 0 表示 4b，3 表示 32b。
    
    Args:
        coverage_dir: test_coverage_intadd 目录路径（即各子 case 所在文件夹的父目录）
    
    Returns:
        dict: {case_name: '4b'|'32b'}，如 {'intadd_case0001': '4b', 'intadd_case0017': '32b'}
    """
    summary_path = os.path.join(coverage_dir, "cases_summary.md")
    if not os.path.isabs(summary_path):
        summary_path = os.path.abspath(summary_path)
    case_mode_map = {}
    if not os.path.isfile(summary_path):
        safe_print("  DEBUG: cases_summary.md not found: {}".format(summary_path), file=sys.stderr)
        return case_mode_map
    try:
        with open_utf8(summary_path, "r") as f:
            lines = f.readlines()
        if sys.version_info[0] < 3:
            lines = [
                line if isinstance(line, unicode) else line.decode('utf-8', 'replace')
                for line in lines
            ]
        # 表格：| Case | Mode | Op | ST | Description | -> parts[1]=Case, parts[2]=Mode
        data_start = -1
        for i, line in enumerate(lines):
            s = line.strip()
            if s.startswith('|') and 'intadd_case' in s:
                data_start = i
                break
        if data_start == -1:
            return case_mode_map
        for i in range(data_start, len(lines)):
            line = lines[i].strip()
            if not line or not line.startswith('|'):
                continue
            parts = [p.strip() for p in line.split('|')]
            if len(parts) >= 3:
                case_name = parts[1]
                mode_raw = parts[2].strip()
                # Mode 0 -> 4b, Mode 3 -> 32b
                if mode_raw == '0':
                    mode = '4b'
                elif mode_raw == '3':
                    mode = '32b'
                else:
                    continue
                if case_name and re.match(r'^intadd_case\d+$', case_name, re.IGNORECASE):
                    case_mode_map[case_name] = mode
    except Exception as e:
        try:
            err_type = type(e).__name__
            try:
                err_msg = str(e)
                if sys.version_info[0] < 3:
                    err_msg = err_msg.encode('ascii', 'replace') if isinstance(err_msg, unicode) else err_msg.decode('utf-8', 'replace').encode('ascii', 'replace')
                else:
                    err_msg = err_msg.encode('ascii', 'replace').decode('ascii')
            except:
                err_msg = "encoding error"
            safe_print("WARNING: Failed to parse cases_summary.md: {}: {}".format(err_type, err_msg), file=sys.stderr)
        except:
            try:
                safe_print("WARNING: Failed to parse cases_summary.md", file=sys.stderr)
            except:
                pass
    return case_mode_map


def _compare_intadd_line(ref_line, ur_line, mode, line_index_0based):
    """
    比对一行 32 字符 hex。
    - 32b：每行 4 个 int32（每个 8 字符），每个 int32 允许相差 1（1 ULP）以内。
    - 4b：奇数行（第 1、3、5…行，即 line_index 0,2,4…）按 4bit 比对，拆成 32 个数（每数 1 个 hex），每个数允许 1 ULP（相差≤1）；偶数行严格一致。
    """
    if len(ref_line) != 32 or len(ur_line) != 32:
        return False, "行长度非 32 字符: ref len={}, ur len={}".format(len(ref_line), len(ur_line))
    if ref_line == ur_line:
        return True, ""
    # 4b 奇数行：32 个 4bit 数（每数 1 个 hex 字符）
    if mode == '4b' and (line_index_0based % 2) == 0:
        num_elements = 32
        element_width = 1
    else:
        # 32b 或 4b 偶数行
        if mode == '32b':
            num_elements = 4
            element_width = 8
        else:
            # 4b 偶数行：严格一致
            return False, "第 {} 行不一致: ref {} vs ur {}".format(line_index_0based + 1, ref_line, ur_line)
    failed = []
    for i in range(num_elements):
        start = i * element_width
        end = start + element_width
        re_hex = ref_line[start:end]
        ur_hex = ur_line[start:end]
        if re_hex == ur_hex:
            continue
        try:
            rv = int(re_hex, 16)
            uv = int(ur_hex, 16)
            diff = abs(rv - uv)
            if diff > 1:
                failed.append("元素[{}]: ref={} (0x{}), ur={} (0x{}), diff={}".format(i, rv, re_hex, uv, ur_hex, diff))
        except ValueError:
            failed.append("元素[{}]: 无效 hex ref={} ur={}".format(i, re_hex, ur_hex))
    if failed:
        return False, "第 {} 行: {}".format(line_index_0based + 1, "; ".join(failed))
    return True, ""


def compare_case_single_bank_intadd(case_dir, case_name, bank, ref_path, mode):
    """
    比对该 case 的单个 bank：ref（case_dir/bank<N>.hex）与 ur_result_<case_name>_bank<N>.hex。
    根据 mode（4b/32b）进行容差比对。
    """
    ur_path = os.path.join(case_dir, "ur_result_{}_bank{}.hex".format(case_name, bank))
    if not os.path.isfile(ref_path):
        return False, "无参考文件: {}".format(os.path.basename(ref_path))
    if not os.path.isfile(ur_path):
        return False, "无 UR 文件: {}".format(os.path.basename(ur_path))
    try:
        with _open(ref_path, "r", encoding="utf-8") as f:
            ref_lines = [normalize_hex_line(ln) for ln in f.readlines()]
    except IOError as e:
        return False, "读取参考文件失败: {}".format(e)
    try:
        with _open(ur_path, "r", encoding="utf-8") as f:
            ur_lines = [normalize_hex_line(ln) for ln in f.readlines()]
    except IOError as e:
        return False, "读取 UR 失败: {}".format(e)
    ref_valid = [ln for ln in ref_lines if ln]
    ur_valid = [ln for ln in ur_lines if ln]
    if len(ur_valid) < len(ref_valid):
        return False, "UR 行数不足: ref {} 行, ur {} 行".format(len(ref_valid), len(ur_valid))
    for i, (r, u) in enumerate(zip(ref_valid, ur_valid)):
        passed, msg = _compare_intadd_line(r, u, mode, i)
        if not passed:
            return False, msg
    return True, ""


def get_banks_from_case_dir(case_dir):
    """
    在当前 case 路径下直接检测 bank<N>.hex 文件名，提取 bank 编号列表。
    返回 bank 编号列表（已排序），如 [0, 1, 2]。
    """
    banks = []
    if not os.path.isdir(case_dir):
        return banks
    bank_pattern = re.compile(r'^bank(\d+)\.hex$', re.IGNORECASE)
    for item in os.listdir(case_dir):
        item_path = os.path.join(case_dir, item)
        if os.path.isfile(item_path):
            match = bank_pattern.match(item)
            if match:
                banks.append(int(match.group(1)))
    return sorted(banks)


def compare_case(case_dir, case_name, bank=None):
    """
    比对该 case 的 golden 与 ur_result 文件（intadd 模式）。
    参考数据来自当前 case 路径下 bank<N>.hex，与 ur_result_<case_name>_bank<N>.hex 逐 bank 比对。
    
    Args:
        case_dir: case 文件夹的完整路径
        case_name: case 名称
        bank: 未使用（intadd 模式自动检测 bank）
    
    Returns:
        (passed: bool, message: str)
    """
    # 比对前从各自文件夹中的 cases_summary.md 得出本子 case 的 Mode（0=4b，3=32b）
    coverage_dir = os.path.dirname(case_dir)
    case_mode_map = parse_cases_summary_intadd(coverage_dir)
    mode = case_mode_map.get(case_name)
    if not mode:
        mode = "32b"
        safe_print("  [{}] Mode: {} (默认，未在 cases_summary.md 中找到)".format(case_name, mode), file=sys.stderr)
    else:
        safe_print("  [{}] Mode: {} (从 cases_summary.md 解析)".format(case_name, mode), file=sys.stderr)
    
    # 在当前 case 路径下直接检测 bank*.hex，仅与 UR 输出中 bank 编号一致的文件比对
    banks = get_banks_from_case_dir(case_dir)
    if not banks:
        safe_print("  [{}] WARNING: no bank<N>.hex in case dir".format(case_name), file=sys.stderr)
        return False, "当前 case 路径下未找到 bank<N>.hex 文件"
    
    # 对每个 bank：case_dir/bank<N>.hex 与 ur_result_<case_name>_bank<N>.hex 按 Mode 容差比对
    all_passed = True
    failed_banks = []
    for b in banks:
        ref_path = os.path.join(case_dir, "bank{}.hex".format(b))
        passed, msg = compare_case_single_bank_intadd(case_dir, case_name, b, ref_path, mode)
        if not passed:
            all_passed = False
            failed_banks.append("bank{} ({})".format(b, msg))
    
    if all_passed:
        return True, ""
    else:
        return False, "失败的 bank: {}".format(", ".join(failed_banks))
