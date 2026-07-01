#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
test_coverage_int8tofp16 的专用比对脚本。

比对规则：
- 在当前子 case 路径下检索 bank*.hex（如 bank0.hex、bank2_sim.hex 等），提取 bank 编号
- 与 UR 输出 ur_result_<case_name>_bank<N>.hex 中编号一致的逐 bank 比对（每行 32 字符，128bit，严格一致）
"""
from __future__ import print_function

import os
import re
from base_handler import compare_case_single_bank


def get_banks_from_case_dir(case_dir):
    """
    在当前 case 路径下检索 bank*.hex 文件名，提取 bank 编号。
    支持 bank<N>.hex 与 bank<N>_sim.hex 两种命名。
    返回 [(bank_num, golden_filename), ...]，按 bank_num 排序。
    """
    if not os.path.isdir(case_dir):
        return []
    # 匹配 bank0.hex 或 bank2_sim.hex
    pattern = re.compile(r'^bank(\d+)(?:_sim)?\.hex$', re.IGNORECASE)
    found = []
    for item in os.listdir(case_dir):
        path = os.path.join(case_dir, item)
        if not os.path.isfile(path):
            continue
        m = pattern.match(item)
        if m:
            found.append((int(m.group(1)), item))
    return sorted(found, key=lambda x: x[0])


def compare_case(case_dir, case_name, bank=None):
    """
    比对该 case 的 golden 与 ur_result 文件（int8tofp16 模式）。
    从当前子 case 中检索 bank*.hex，再与 ur 输出的对应 bank hex 文件对比。
    
    Args:
        case_dir: case 文件夹的完整路径
        case_name: case 名称
        bank: 未使用（自动检测 case 下的 bank*.hex）
    
    Returns:
        (passed: bool, message: str)
    """
    banks = get_banks_from_case_dir(case_dir)
    if not banks:
        return False, "当前 case 路径下未找到 bank*.hex 文件"
    
    all_passed = True
    failed_banks = []
    for bank_num, golden_name in banks:
        golden_path = os.path.join(case_dir, golden_name)
        passed, msg = compare_case_single_bank(case_dir, case_name, bank_num, golden_path)
        if not passed:
            all_passed = False
            failed_banks.append("bank{} ({})".format(bank_num, msg))
    
    if all_passed:
        return True, ""
    return False, "失败的 bank: {}".format(", ".join(failed_banks))
