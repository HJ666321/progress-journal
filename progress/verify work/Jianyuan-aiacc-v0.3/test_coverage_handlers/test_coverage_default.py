#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
test_coverage_* 的默认处理脚本（用于未定义专用脚本的类型）。

处理规则：
- 对每个 case 生成 data_list_<case名>.txt
"""
from __future__ import print_function

import os
from base_handler import get_case_folders, generate_data_list


def process_coverage_folder(coverage_folder_path):
    """
    处理 test_coverage_* 文件夹（默认处理方式）。
    
    Args:
        coverage_folder_path: test_coverage_* 的完整路径
    
    Returns:
        None
    """
    coverage_name = os.path.basename(coverage_folder_path)
    print("\n" + "=" * 60)
    print("处理 test_coverage: {}".format(coverage_name))
    print("=" * 60)
    
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
