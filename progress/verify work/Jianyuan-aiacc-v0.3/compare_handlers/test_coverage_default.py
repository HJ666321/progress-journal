#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
test_coverage_* 的默认比对脚本（用于未定义专用脚本的类型）。

比对规则：
- 使用 bank 参数（默认 2）
- 优先使用 golden_output_fp16.txt，不存在则使用 golden_output_fp32.txt，再不存在则使用 golden_output_int32.txt
- 与 ur_result_<case_name>_bank<N>.hex 逐行比对（每行 32 个十六进制字符，128bit）
"""
from __future__ import print_function

import os
from base_handler import compare_case_single_bank


def compare_case(case_dir, case_name, bank=None):
    """
    比对该 case 的 golden 与 ur_result 文件（默认模式）。
    
    Args:
        case_dir: case 文件夹的完整路径
        case_name: case 名称
        bank: UR bank 编号（默认 2）
    
    Returns:
        (passed: bool, message: str)
    """
    if bank is None:
        bank = 2  # 默认 bank 2
    
    # 优先使用 FP16，不存在则使用 FP32，再不存在则使用 INT32
    golden_fp16 = os.path.join(case_dir, "golden_output_fp16.txt")
    golden_fp32 = os.path.join(case_dir, "golden_output_fp32.txt")
    golden_int32 = os.path.join(case_dir, "golden_output_int32.txt")
    
    if os.path.isfile(golden_fp16):
        golden_path = golden_fp16
    elif os.path.isfile(golden_fp32):
        golden_path = golden_fp32
    elif os.path.isfile(golden_int32):
        golden_path = golden_int32
    else:
        return False, "无 golden 文件 (golden_output_fp16/fp32/int32.txt)"
    
    return compare_case_single_bank(case_dir, case_name, bank, golden_path)
