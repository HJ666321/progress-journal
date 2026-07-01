#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
test_coverage_fptofp 的专用比对脚本。

比对规则：
- 比对前从各自文件夹（test_coverage_fptofp）中的 cases_summary.md 得出每个子 case 的目的精度：
  目的精度列 0 表示 16bit（FP16），1 表示 32bit（FP32）。
- 从当前子 case 路径下读取 bank<N>_sim.hex 文件名，提取 bank 编号
- 对每个找到的 bank，比对 case_dir/bank<N>_sim.hex（golden）与 ur_result_<case_name>_bank<N>.hex（UR输出）
- 根据目的精度解析每行：FP32 为 4 个元素，FP16 为 8 个元素
- 允许 1 ULP（Unit in Last Place）误差：如果两个浮点数二进制表示相差 1，算 pass
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

# Python 2/3 兼容的 UTF-8 文件读取
if sys.version_info[0] < 3:
    import codecs
    def open_utf8(filepath, mode='r'):
        return codecs.open(filepath, mode, encoding='utf-8')
else:
    def open_utf8(filepath, mode='r'):
        return _open(filepath, mode, encoding='utf-8')

# 安全的打印函数，自动处理编码错误
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
    """去掉首尾空白并转为大写，便于比较。空行保留为空字符串。"""
    s = line.strip()
    return s.upper() if s else ""


def parse_cases_summary(coverage_dir):
    """
    解析 coverage_dir/cases_summary.md 文件，提取每个子 case 的目的精度。
    目的精度列：0 表示 16bit（FP16），1 表示 32bit（FP32）。
    
    Args:
        coverage_dir: test_coverage_fptofp 目录路径（即各子 case 所在文件夹的父目录）
    
    Returns:
        dict: {case_name: dst_precision}，如 {'fptofp_case0001': 'FP16', 'fptofp_case0011': 'FP32'}
    """
    summary_path = os.path.join(coverage_dir, "cases_summary.md")
    if not os.path.isabs(summary_path):
        summary_path = os.path.abspath(summary_path)
    case_precision_map = {}
    
    if not os.path.isfile(summary_path):
        safe_print("  DEBUG: cases_summary.md not found: {}".format(summary_path), file=sys.stderr)
        return case_precision_map
    
    try:
        with open_utf8(summary_path, "r") as f:
            lines = f.readlines()
        
        if sys.version_info[0] < 3:
            lines = [
                line if isinstance(line, unicode) else line.decode('utf-8', 'replace')
                for line in lines
            ]
        
        data_start = -1
        for i, line in enumerate(lines):
            if 'fptofp_case' in line and line.strip().startswith('|'):
                data_start = i
                break
        
        if data_start == -1:
            safe_print("  DEBUG: No table data row (fptofp_case) found in cases_summary.md", file=sys.stderr)
            return case_precision_map
        
        for i in range(data_start, len(lines)):
            line = lines[i].strip()
            if not line or not line.startswith('|'):
                continue
            parts = [p.strip() for p in line.split('|')]
            if len(parts) >= 4:
                case_name = parts[1]
                dst_precision_raw = parts[3].strip()
                # 支持 0/1 格式：0=FP16, 1=FP32
                if dst_precision_raw == '0':
                    dst_precision = 'FP16'
                elif dst_precision_raw == '1':
                    dst_precision = 'FP32'
                else:
                    dst_precision = dst_precision_raw.upper()
                if case_name and dst_precision in ('FP16', 'FP32'):
                    case_precision_map[case_name] = dst_precision
    
    except Exception as e:
        try:
            error_type = type(e).__name__
            try:
                error_msg = str(e)
                if sys.version_info[0] < 3:
                    error_msg = error_msg.encode('ascii', 'replace') if isinstance(error_msg, unicode) else error_msg.decode('utf-8', 'replace').encode('ascii', 'replace')
                else:
                    error_msg = error_msg.encode('ascii', 'replace').decode('ascii')
            except:
                error_msg = "encoding error"
            safe_print("WARNING: Failed to parse cases_summary.md: {}: {}".format(error_type, error_msg), file=sys.stderr)
        except:
            try:
                safe_print("WARNING: Failed to parse cases_summary.md", file=sys.stderr)
            except:
                pass
    
    return case_precision_map


def compare_fp_with_ulp(golden_line, ur_line, dst_precision):
    """
    比对一行浮点数数据，允许 1 ULP 误差。
    
    Args:
        golden_line: golden 文件的 32 字符 hex 行（128bit）
        ur_line: UR 文件的 32 字符 hex 行（128bit）
        dst_precision: 'FP32' 或 'FP16'
    
    Returns:
        (passed: bool, error_msg: str) - 如果失败，error_msg 包含详细信息
    """
    if len(golden_line) != 32 or len(ur_line) != 32:
        return False, "行长度非 32 字符: golden len={}, ur len={}".format(len(golden_line), len(ur_line))
    
    if golden_line == ur_line:
        return True, ""
    
    # 根据精度拆分元素
    if dst_precision == 'FP32':
        # FP32: 每行 4 个元素，每个 8 字符（32bit）
        num_elements = 4
        element_width = 8
    elif dst_precision == 'FP16':
        # FP16: 每行 8 个元素，每个 4 字符（16bit）
        num_elements = 8
        element_width = 4
    else:
        return False, "未知的目的精度: {}".format(dst_precision)
    
    # 逐元素比对
    failed_elements = []
    for i in range(num_elements):
        start_idx = i * element_width
        end_idx = start_idx + element_width
        golden_elem = golden_line[start_idx:end_idx]
        ur_elem = ur_line[start_idx:end_idx]
        
        if golden_elem == ur_elem:
            continue
        
        # 计算二进制表示的差值
        try:
            golden_int = int(golden_elem, 16)
            ur_int = int(ur_elem, 16)
            diff = abs(golden_int - ur_int)
            
            if diff != 1:
                # 差值不为 1，失败
                failed_elements.append("元素[{}]: golden={} (0x{}), ur={} (0x{}), diff={}".format(
                    i, golden_int, golden_elem, ur_int, ur_elem, diff))
        except ValueError:
            failed_elements.append("元素[{}]: 无效的 hex 值: golden={}, ur={}".format(i, golden_elem, ur_elem))
    
    if failed_elements:
        return False, "; ".join(failed_elements)
    
    return True, ""


def get_banks_from_case_dir(case_dir):
    """
    从当前子 case 路径下读取所有 bank<N>_sim.hex 文件名，提取 bank 编号列表。
    返回 bank 编号列表（已排序），如 [0, 1, 2]。
    """
    banks = []
    if not os.path.isdir(case_dir):
        return banks
    bank_pattern = re.compile(r'^bank(\d+)_sim\.hex$', re.IGNORECASE)
    for item in os.listdir(case_dir):
        if not os.path.isfile(os.path.join(case_dir, item)):
            continue
        match = bank_pattern.match(item)
        if match:
            banks.append(int(match.group(1)))
    return sorted(banks)


def compare_case_single_bank_with_ulp(case_dir, case_name, bank, golden_path, dst_precision):
    """
    比对该 case 的单个 bank 的 golden 与 ur_result 文件（支持 ULP 误差）。
    
    Args:
        case_dir: case 文件夹路径
        case_name: case 名称
        bank: bank 编号
        golden_path: golden 文件路径
        dst_precision: 目的精度 'FP16' 或 'FP32'
    
    Returns:
        (passed: bool, message: str)
    """
    ur_path = os.path.join(case_dir, "ur_result_{}_bank{}.hex".format(case_name, bank))
    
    if not os.path.isfile(golden_path):
        return False, "无 golden 文件: {}".format(os.path.basename(golden_path))
    if not os.path.isfile(ur_path):
        return False, "无 UR 文件: {}".format(os.path.basename(ur_path))

    try:
        with _open(golden_path, "r", encoding="utf-8") as f:
            golden_lines = [normalize_hex_line(ln) for ln in f.readlines()]
    except IOError as e:
        return False, "读取 golden 失败: {}".format(e)

    try:
        with _open(ur_path, "r", encoding="utf-8") as f:
            ur_lines = [normalize_hex_line(ln) for ln in f.readlines()]
    except IOError as e:
        return False, "读取 UR 失败: {}".format(e)

    # 以 golden 有效行数为准，逐行与 ur 比对；ur 至少要有同样多行
    golden_valid = [ln for ln in golden_lines if ln]
    ur_valid = [ln for ln in ur_lines if ln]

    if len(ur_valid) < len(golden_valid):
        return False, "UR 行数不足: golden {} 行, ur {} 行".format(len(golden_valid), len(ur_valid))

    # 逐行比对（允许 ULP 误差）
    for i, (g, u) in enumerate(zip(golden_valid, ur_valid)):
        passed, msg = compare_fp_with_ulp(g, u, dst_precision)
        if not passed:
            return False, "第 {} 行: {}".format(i + 1, msg)

    return True, ""


def compare_case(case_dir, case_name, bank=None):
    """
    比对该 case 的 golden 与 ur_result 文件（fptofp 模式，支持 ULP 误差）。
    
    Args:
        case_dir: case 文件夹的完整路径
        case_name: case 名称
        bank: 未使用（fptofp 模式自动检测 bank）
    
    Returns:
        (passed: bool, message: str)
    """
    # 获取 coverage_dir（case_dir 的父目录，即 test_coverage_fptofp）
    coverage_dir = os.path.dirname(case_dir)
    
    # 比对数据前，根据各自文件夹中的 cases_summary.md 得出本子 case 的目的精度（0=16bit/FP16，1=32bit/FP32）
    case_precision_map = parse_cases_summary(coverage_dir)
    if not case_precision_map:
        safe_print("  [{}] WARNING: cases_summary.md parse result is empty, file: {}".format(
            case_name, os.path.join(coverage_dir, "cases_summary.md")), file=sys.stderr)
    
    dst_precision = case_precision_map.get(case_name)
    if not dst_precision:
        dst_precision = 'FP32'
        safe_print("  [{}] 目的精度: {} (默认值，未在 cases_summary.md 中找到)".format(case_name, dst_precision))
    else:
        safe_print("  [{}] 目的精度: {} (从 cases_summary.md 解析)".format(case_name, dst_precision))
    
    # 从当前子 case 路径下读取 bank 列表
    banks = get_banks_from_case_dir(case_dir)
    if not banks:
        return False, "当前 case 路径下未找到 bank*_sim.hex 文件"
    
    # 对每个 bank 进行比对（使用 ULP 比对）
    all_passed = True
    failed_banks = []
    for b in banks:
        golden_path = os.path.join(case_dir, "bank{}_sim.hex".format(b))
        passed, msg = compare_case_single_bank_with_ulp(case_dir, case_name, b, golden_path, dst_precision)
        if not passed:
            all_passed = False
            failed_banks.append("bank{} ({})".format(b, msg))
    
    if all_passed:
        return True, ""
    else:
        return False, "失败的 bank: {}".format(", ".join(failed_banks))
