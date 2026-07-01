#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
test_coverage_logic 的专用比对脚本。

比对规则：
- 从每个 case 目录及其子目录中递归扫描 bank<N>.hex，与 ur_result_<case_name>_bank<N>.hex 逐行比对
- 不读取 cases_summary.md，比对要求数据全部一致（无容差）
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

from base_handler import get_case_folders, compare_case_single_bank

# Python 2/3 兼容的 UTF-8 文件读取（与 skill 一致）
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


def get_banks_from_case_dir(case_dir):
    """
    从 case_dir/ 及其子目录中递归读取所有 bank<N>.hex 文件名，提取 bank 编号列表（已排序）。
    """
    banks = []
    if not os.path.isdir(case_dir):
        return banks
    bank_pattern = re.compile(r'^bank(\d+)\.hex$', re.IGNORECASE)
    
    # 递归搜索所有子目录
    for root, dirs, files in os.walk(case_dir):
        for filename in files:
            match = bank_pattern.match(filename)
            if match:
                bank_num = int(match.group(1))
                if bank_num not in banks:
                    banks.append(bank_num)
    
    return sorted(banks)


def find_bank_file_in_case_dir(case_dir, bank_num):
    """
    在 case_dir 及其子目录中查找 bank<N>.hex 文件。
    
    Args:
        case_dir: case 文件夹的完整路径
        bank_num: bank 编号
    
    Returns:
        找到的文件路径，如果未找到返回 None
    """
    bank_filename = "bank{}.hex".format(bank_num)
    bank_pattern = re.compile(r'^bank{}\.hex$'.format(bank_num), re.IGNORECASE)
    
    # 递归搜索所有子目录
    for root, dirs, files in os.walk(case_dir):
        for filename in files:
            if bank_pattern.match(filename):
                return os.path.join(root, filename)
    
    return None


def compare_case(case_dir, case_name, bank=None):
    """
    比对该 case 目录及其子目录中的 bank<N>.hex 与 ur_result 文件（logic 模式，严格一致）。

    Args:
        case_dir: case 文件夹的完整路径
        case_name: case 名称（如 logic_case0001）
        bank: 未使用（自动检测 case 目录及其子目录下的 bank）

    Returns:
        (passed: bool, message: str)
    """
    banks = get_banks_from_case_dir(case_dir)
    if not banks:
        safe_print("  [{}] WARNING: no bank<N>.hex in case directory or subdirectories".format(case_name), file=sys.stderr)
        return False, "case 目录及其子目录中未找到 bank<N>.hex 文件"

    all_passed = True
    failed_banks = []
    for b in banks:
        golden_path = find_bank_file_in_case_dir(case_dir, b)
        if golden_path is None:
            all_passed = False
            failed_banks.append("bank{} (未找到文件)".format(b))
            continue
        
        passed, msg = compare_case_single_bank(case_dir, case_name, b, golden_path)
        if not passed:
            all_passed = False
            failed_banks.append("bank{} ({})".format(b, msg))

    if all_passed:
        return True, ""
    return False, "失败的 bank: {}".format(", ".join(failed_banks))
