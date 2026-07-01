#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
test_coverage_fpadd 的专用处理脚本。

处理规则：
- 对每个 case 生成 data_list_<case名>.txt
- 读 summary.txt 判断每个 case 的 Output 精度（FP16/FP32）
- 将 golden_output.npy 转为 golden_output_fp16.txt 或 golden_output_fp32.txt
"""
from __future__ import print_function

import os
from base_handler import get_case_folders, generate_data_list, convert_to_fp16, convert_to_fp32, parse_summary_txt


def process_coverage_folder(coverage_folder_path):
    """
    处理 test_coverage_fpadd 文件夹。
    
    Args:
        coverage_folder_path: test_coverage_fpadd 的完整路径
    
    Returns:
        None
    """
    coverage_name = os.path.basename(coverage_folder_path)
    print("\n" + "=" * 60)
    print("处理 test_coverage_fpadd: {}".format(coverage_name))
    print("=" * 60)
    
    # 读取 summary.txt 得到 case -> Output 精度（FP16/FP32）
    case_precision = parse_summary_txt(coverage_folder_path)
    if case_precision:
        print("  已从 summary.txt 读取 {} 个 case 的精度".format(len(case_precision)))
    
    # 查找所有 case 子文件夹
    case_folders = get_case_folders(coverage_folder_path)
    if not case_folders:
        print("  未找到任何 case 子文件夹")
        return
    
    print("  找到 {} 个 case 子文件夹:".format(len(case_folders)))
    for cf in case_folders:
        print("    - {}".format(os.path.basename(cf)))
    print()
    
    # 处理每个 case 文件夹
    for case_folder in case_folders:
        case_name = os.path.basename(case_folder)
        print("\n处理 case: {}".format(case_name))
        print("  路径: {}".format(case_folder))
        
        # 生成 data_list_<case名>.txt
        generate_data_list(case_folder, data_list_suffix=case_name)
        
        # 根据 summary.txt 判断该 case 的 Output 精度，再转换 golden_output.npy
        precision = case_precision.get(case_name, "FP32")
        if precision == "FP16":
            convert_to_fp16(case_folder, npy_filename="golden_output.npy", out_filename="golden_output_fp16.txt")
        else:
            convert_to_fp32(case_folder, npy_filename="golden_output.npy", out_filename="golden_output_fp32.txt")
