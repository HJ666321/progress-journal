#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
test_coverage_inttofp 的专用比对脚本。

比对规则：
- 比对前从各自文件夹（test_coverage_inttofp）中的 cases_summary.md 得出每个子 case 的目的精度：
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
    """
    安全的打印函数，自动处理 UnicodeEncodeError。
    如果遇到编码错误，会尝试将非 ASCII 字符替换为 '?' 或跳过输出。
    """
    def safe_str(s):
        """将字符串安全地转换为 ASCII 编码的字符串"""
        if sys.version_info[0] < 3:
            # Python 2
            if isinstance(s, unicode):
                try:
                    return s.encode('ascii', 'replace')
                except:
                    return '?'
            elif isinstance(s, str):
                # 尝试解码为 unicode 再编码，以处理包含非 ASCII 字节的情况
                try:
                    # 先尝试 UTF-8 解码
                    return s.decode('utf-8', 'replace').encode('ascii', 'replace')
                except:
                    # 如果失败，尝试 latin-1（不会失败）
                    try:
                        return s.decode('latin-1', 'replace').encode('ascii', 'replace')
                    except:
                        # 最后的降级：替换所有非 ASCII 字节
                        return ''.join(c if ord(c) < 128 else '?' for c in s)
            else:
                # 其他类型，先转为字符串再处理
                try:
                    s_str = str(s)
                    if isinstance(s_str, unicode):
                        return s_str.encode('ascii', 'replace')
                    else:
                        return safe_str(s_str)  # 递归处理
                except:
                    return '?'
        else:
            # Python 3
            if isinstance(s, str):
                try:
                    return s.encode('ascii', 'replace').decode('ascii')
                except:
                    return '?'
            elif isinstance(s, bytes):
                try:
                    return s.decode('utf-8', 'replace').encode('ascii', 'replace').decode('ascii')
                except:
                    try:
                        return s.decode('ascii', 'replace')
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
        # 如果编码失败，尝试将参数转换为 ASCII 安全的形式
        try:
            safe_args = [safe_str(arg) for arg in args]
            print(*safe_args, **kwargs)
        except:
            # 如果还是失败，完全跳过输出以避免崩溃
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
        coverage_dir: test_coverage_inttofp 目录路径（即各子 case 所在文件夹的父目录）
    
    Returns:
        dict: {case_name: dst_precision}，如 {'inttofp_case0001': 'FP16', 'inttofp_case0003': 'FP32'}
    """
    summary_path = os.path.join(coverage_dir, "cases_summary.md")
    # 转换为绝对路径，避免相对路径问题
    if not os.path.isabs(summary_path):
        summary_path = os.path.abspath(summary_path)
    
    case_precision_map = {}
    
    if not os.path.isfile(summary_path):
        safe_print("  DEBUG: cases_summary.md not found: {}".format(summary_path), file=sys.stderr)
        return case_precision_map
    
    try:
        # 使用 UTF-8 编码读取文件
        with open_utf8(summary_path, "r") as f:
            lines = f.readlines()
        
        # 确保所有行为 unicode，避免 Py2 下 "unicode in str" 触发 ASCII 编码
        if sys.version_info[0] < 3:
            lines = [
                line if isinstance(line, unicode) else line.decode('utf-8', 'replace')
                for line in lines
            ]
        
        # 通过 ASCII 关键字定位数据行，避免依赖中文字符导致编码错误
        # 表格格式：表头行 | 分隔行 | 数据行(含 inttofp_case...)
        data_start = -1
        for i, line in enumerate(lines):
            # 使用纯 ASCII 判断
            if 'inttofp_case' in line and line.strip().startswith('|'):
                data_start = i
                break
        
        if data_start == -1:
            safe_print("  DEBUG: No table data row (inttofp_case) found in cases_summary.md", file=sys.stderr)
            return case_precision_map
        
        # 从第一行数据开始解析（列顺序固定：用例|源精度|目的精度|...，parts[3]=目的精度）
        parsed_count = 0
        for i in range(data_start, len(lines)):
            line = lines[i].strip()
            if not line or not line.startswith('|'):
                continue
            
            # 解析表格行：| inttofp_case0001 | Int16 | FP16 | ... 或 | inttofp_case0001 | 0 | 0 | ...
            parts = [p.strip() for p in line.split('|')]
            if len(parts) >= 4:
                case_name = parts[1]
                dst_precision_raw = parts[3].strip()  # 原始值，可能是 FP16、FP32、0、1 等
                # 支持 0/1 格式：0=FP16, 1=FP32
                if dst_precision_raw == '0':
                    dst_precision = 'FP16'
                elif dst_precision_raw == '1':
                    dst_precision = 'FP32'
                else:
                    dst_precision = dst_precision_raw.upper()  # 转为大写
                
                if case_name and dst_precision in ('FP16', 'FP32'):
                    case_precision_map[case_name] = dst_precision
                    parsed_count += 1
                elif case_name:
                    # 调试：打印未匹配的精度值
                    safe_print("  DEBUG: case_name={}, dst_precision_raw='{}', dst_precision='{}' (not matched)".format(
                        case_name, dst_precision_raw, dst_precision), file=sys.stderr)
        
        # 调试：打印解析统计
        if parsed_count == 0:
            safe_print("  DEBUG: No precision parsed, data_start={}".format(data_start), file=sys.stderr)
    
    except Exception as e:
        # 解析失败时返回空字典，后续会使用默认行为
        # 安全地转换异常消息，避免编码错误
        try:
            # 先获取异常类型名称（通常是 ASCII）
            error_type = type(e).__name__
            # 然后安全地获取异常消息
            try:
                error_msg = str(e)
                if sys.version_info[0] < 3:
                    if isinstance(error_msg, unicode):
                        error_msg = error_msg.encode('ascii', 'replace')
                    else:
                        try:
                            error_msg = error_msg.decode('utf-8', 'replace').encode('ascii', 'replace')
                        except:
                            pass
                else:
                    error_msg = error_msg.encode('ascii', 'replace').decode('ascii')
            except:
                error_msg = "encoding error"
            safe_print("WARNING: Failed to parse cases_summary.md: {}: {}".format(error_type, error_msg), file=sys.stderr)
        except:
            # 如果连格式化都失败，使用最简单的消息
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


def compare_case_single_bank_with_tolerance(case_dir, case_name, bank, golden_path, dst_precision, compare_func):
    """
    比对该 case 的单个 bank 的 golden 与 ur_result 文件（支持容差）。
    
    Args:
        case_dir: case 文件夹路径
        case_name: case 名称
        bank: bank 编号
        golden_path: golden 文件路径
        dst_precision: 目的精度
        compare_func: 比对函数（compare_fp_with_ulp 或 compare_int_with_tolerance）
    
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

    # 逐行比对（使用传入的比对函数）
    for i, (g, u) in enumerate(zip(golden_valid, ur_valid)):
        passed, msg = compare_func(g, u, dst_precision)
        if not passed:
            return False, "第 {} 行: {}".format(i + 1, msg)

    return True, ""


def compare_case(case_dir, case_name, bank=None):
    """
    比对该 case 的 golden 与 ur_result 文件（inttofp 模式，支持 ULP 误差）。
    
    Args:
        case_dir: case 文件夹的完整路径
        case_name: case 名称
        bank: 未使用（inttofp 模式自动检测 bank）
    
    Returns:
        (passed: bool, message: str)
    """
    # 获取 coverage_dir（case_dir 的父目录，即 test_coverage_inttofp）
    coverage_dir = os.path.dirname(case_dir)
    
    # 比对数据前，根据各自文件夹中的 cases_summary.md 得出本子 case 的目的精度（0=16bit/FP16，1=32bit/FP32）
    case_precision_map = parse_cases_summary(coverage_dir)
    
    # 调试：打印解析结果
    if not case_precision_map:
        safe_print("  [{}] WARNING: cases_summary.md parse result is empty, file: {}".format(
            case_name, os.path.join(coverage_dir, "cases_summary.md")), file=sys.stderr)
    
    dst_precision = case_precision_map.get(case_name)
    
    if not dst_precision:
        # 如果找不到目的精度，尝试从 case_name 推断或使用默认值
        # 这里可以根据实际情况调整，暂时使用 FP32 作为默认值
        dst_precision = 'FP32'
        safe_print("  [{}] 目的精度: {} (默认值，未在 cases_summary.md 中找到)".format(case_name, dst_precision))
    else:
        safe_print("  [{}] 目的精度: {} (从 cases_summary.md 解析)".format(case_name, dst_precision))
    
    # 从当前子 case 路径下读取 bank 列表
    banks = get_banks_from_case_dir(case_dir)
    if not banks:
        return False, "当前 case 路径下未找到 bank*_sim.hex 文件"
    
    # 选择比对函数（根据精度类型）
    if dst_precision in ('FP32', 'FP16'):
        compare_func = compare_fp_with_ulp
    else:
        return False, "未知的目的精度: {}".format(dst_precision)
    
    # 对每个 bank 进行比对（使用容差比对）
    all_passed = True
    failed_banks = []
    for b in banks:
        golden_path = os.path.join(case_dir, "bank{}_sim.hex".format(b))
        passed, msg = compare_case_single_bank_with_tolerance(
            case_dir, case_name, b, golden_path, dst_precision, compare_func)
        if not passed:
            all_passed = False
            failed_banks.append("bank{} ({})".format(b, msg))
    
    if all_passed:
        return True, ""
    else:
        return False, "失败的 bank: {}".format(", ".join(failed_banks))
