#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
test_coverage_intadd 的专用处理脚本。

处理规则：
- 对每个 case 生成 data_list_<case名>.txt
- 将 golden_output.npy 转为 int32（golden_output_int32.txt），不读 summary.txt
"""
from __future__ import print_function

import os
from base_handler import get_case_folders, generate_data_list, convert_to_int32


def process_coverage_folder(coverage_folder_path):
    """
    处理 test_coverage_intadd 文件夹。
    
    Args:
        coverage_folder_path: test_coverage_intadd 的完整路径
    
    Returns:
        None
    """
    coverage_name = os.path.basename(coverage_folder_path)
    print("\n" + "=" * 60)
    print("处理 test_coverage_intadd: {}".format(coverage_name))
    print("=" * 60)
    print("  intadd 模式：golden_output.npy 转为 int32，不读 summary.txt")
    
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
        
        # 转换 golden_output.npy 为 int32
        convert_to_int32(case_folder, npy_filename="golden_output.npy", out_filename="golden_output_int32.txt")
