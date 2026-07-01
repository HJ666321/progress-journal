#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
test_coverage_int8tofp16 的专用处理脚本。

处理规则：
- 对每个 case 生成 data_list_<case名>.txt
- 将 golden_output.npy 转为 FP16（golden_output_fp16.txt），不读 summary.txt
- 特殊处理：将第一个FP16值的每个4bit分别放在4个128bit的最低位
  - A_128[0][3:0] = 第一个FP16的bit[3:0]（最低4bit）
  - A_128[1][3:0] = 第一个FP16的bit[7:4]
  - A_128[2][3:0] = 第一个FP16的bit[11:8]
  - A_128[3][3:0] = 第一个FP16的bit[15:12]（最高4bit）
"""
from __future__ import print_function

import os
import sys
try:
    from io import open as _open
except ImportError:
    _open = open
try:
    import numpy as np
    HAS_NUMPY = True
except ImportError:
    HAS_NUMPY = False

from base_handler import get_case_folders, generate_data_list


def _to_unicode(s):
    """Python 2: 写入 io.open(encoding='utf-8') 的文件需 unicode；Python 3 无需转换。"""
    if sys.version_info[0] < 3 and isinstance(s, str):
        return s.decode('utf-8', 'replace')
    return s


def float_to_fp16_hex(value):
    """将标量转为 IEEE 754 FP16 十六进制（16 位，4 位十六进制字符串，无 0x 前缀）。需 numpy。"""
    if not HAS_NUMPY:
        return None
    try:
        f16 = np.float16(float(value))
        bits = np.array([f16], dtype=np.float16).view(np.uint16)[0]
        return "{:04X}".format(bits & 0xFFFF)
    except (TypeError, ValueError):
        return None


def convert_to_fp16_with_special_formatting(subfolder_path, npy_filename="golden_output.npy", out_filename="golden_output_fp16.txt"):
    """
    将 npy 文件转为 IEEE 754 FP16 十六进制，并应用特殊格式化：
    - 32个FP16值，标记为FP16[0]到FP16[31]
    - 输出4行128bit，每行32个4bit
    - 第1行：FP16[31][3:0], FP16[30][3:0], ..., FP16[1][3:0], FP16[0][3:0]（32个4bit）
    - 第2行：FP16[31][7:4], FP16[30][7:4], ..., FP16[1][7:4], FP16[0][7:4]（32个4bit）
    - 第3行：FP16[31][11:8], FP16[30][11:8], ..., FP16[1][11:8], FP16[0][11:8]（32个4bit）
    - 第4行：FP16[31][15:12], FP16[30][15:12], ..., FP16[1][15:12], FP16[0][15:12]（32个4bit）
    - 每行128bit = 32个十六进制字符，从FP16[31]到FP16[0]排列
    
    Args:
        subfolder_path: 子文件夹路径
        npy_filename: 输入的 npy 文件名
        out_filename: 输出的 txt 文件名
    """
    npy_path = os.path.join(subfolder_path, npy_filename)
    if not os.path.isfile(npy_path):
        print("  警告: 未找到文件 {}".format(npy_filename))
        return
    if not HAS_NUMPY:
        print("  跳过 {} 转换: 未安装 numpy（FP16 需要）".format(npy_filename))
        return
    try:
        arr = np.load(npy_path)
        flat = np.asarray(arr).flatten()
    except Exception as e:
        print("  错误: 无法加载 {}: {}".format(npy_filename, e))
        return
    
    hex_list = []
    for item in flat:
        hex_str = float_to_fp16_hex(item)
        if hex_str is not None:
            hex_list.append(hex_str)
    
    if len(hex_list) == 0:
        print("  警告: {} 中没有有效数据".format(npy_filename))
        return
    
    # 确保有32个FP16值，不足用"0000"补齐
    while len(hex_list) < 32:
        hex_list.append("0000")
    
    # 提取第一个FP16值的4个4bit（用于特殊处理）
    first_fp16 = hex_list[0]  # 例如 "5990"
    if len(first_fp16) != 4:
        print("  警告: 第一个FP16值格式错误: {}".format(first_fp16))
        return
    
    # 拆分成4个4bit：bit[15:12], bit[11:8], bit[7:4], bit[3:0]
    # 例如 "5990" -> '5', '9', '9', '0'
    nibble_3 = first_fp16[0]  # bit[15:12] = 5
    nibble_2 = first_fp16[1]  # bit[11:8] = 9
    nibble_1 = first_fp16[2]  # bit[7:4] = 9
    nibble_0 = first_fp16[3]  # bit[3:0] = 0
    
    print("  第一个FP16值: {} -> 4bit: [{}] [{}] [{}] [{}]".format(first_fp16, nibble_3, nibble_2, nibble_1, nibble_0))
    
    out_path = os.path.join(subfolder_path, out_filename)
    lines = []
    
    try:
        # 生成4行，每行对应不同的bit位段
        # 第1行：bit[3:0]（从FP16[31]到FP16[0]）
        line0_nibbles = []
        for i in range(31, -1, -1):  # 从31到0
            fp16_hex = hex_list[i]
            line0_nibbles.append(fp16_hex[3])  # bit[3:0]，即最后一个字符
        line0 = ''.join(line0_nibbles)  # 32个十六进制字符
        lines.append(line0)
        
        # 第2行：bit[7:4]（从FP16[31]到FP16[0]）
        line1_nibbles = []
        for i in range(31, -1, -1):  # 从31到0
            fp16_hex = hex_list[i]
            line1_nibbles.append(fp16_hex[2])  # bit[7:4]，即第三个字符
        line1 = ''.join(line1_nibbles)  # 32个十六进制字符
        lines.append(line1)
        
        # 第3行：bit[11:8]（从FP16[31]到FP16[0]）
        line2_nibbles = []
        for i in range(31, -1, -1):  # 从31到0
            fp16_hex = hex_list[i]
            line2_nibbles.append(fp16_hex[1])  # bit[11:8]，即第二个字符
        line2 = ''.join(line2_nibbles)  # 32个十六进制字符
        lines.append(line2)
        
        # 第4行：bit[15:12]（从FP16[31]到FP16[0]）
        line3_nibbles = []
        for i in range(31, -1, -1):  # 从31到0
            fp16_hex = hex_list[i]
            line3_nibbles.append(fp16_hex[0])  # bit[15:12]，即第一个字符
        line3 = ''.join(line3_nibbles)  # 32个十六进制字符
        lines.append(line3)
        
        # 特殊处理：将第一个FP16值的4个4bit分别放在4行的最低4bit（最后一个字符）
        # 第1行：最低4bit = nibble_0（第一个FP16的bit[3:0]）
        line0_modified = lines[0][:-1] + nibble_0
        lines[0] = line0_modified
        
        # 第2行：最低4bit = nibble_1（第一个FP16的bit[7:4]）
        line1_modified = lines[1][:-1] + nibble_1
        lines[1] = line1_modified
        
        # 第3行：最低4bit = nibble_2（第一个FP16的bit[11:8]）
        line2_modified = lines[2][:-1] + nibble_2
        lines[2] = line2_modified
        
        # 第4行：最低4bit = nibble_3（第一个FP16的bit[15:12]）
        line3_modified = lines[3][:-1] + nibble_3
        lines[3] = line3_modified
        
        print("  已修改4行最低4bit: [0]={}, [1]={}, [2]={}, [3]={}".format(nibble_0, nibble_1, nibble_2, nibble_3))
        
        # 写入文件
        with _open(out_path, "w", encoding="utf-8") as f:
            for line in lines:
                f.write(_to_unicode(line + "\n"))
                
    except IOError as e:
        print("  错误: 无法写入 {}: {}".format(out_path, e))
        return
    
    print("  已由 {} 生成 {}: {} 个 FP16 值 -> 4 行 128bit（每行32个4bit，从FP16[31]到FP16[0]）".format(npy_filename, out_filename, len(hex_list)))


def process_coverage_folder(coverage_folder_path):
    """
    处理 test_coverage_int8tofp16 文件夹。
    
    Args:
        coverage_folder_path: test_coverage_int8tofp16 的完整路径
    
    Returns:
        None
    """
    coverage_name = os.path.basename(coverage_folder_path)
    print("\n" + "=" * 60)
    print("处理 test_coverage_int8tofp16: {}".format(coverage_name))
    print("=" * 60)
    print("  int8tofp16 模式：golden_output.npy 转为 FP16，不读 summary.txt")
    print("  特殊格式化：第一个FP16的4个4bit分别放在前4个128bit的最低位")
    
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
        
        # 转换 golden_output.npy 为 FP16（带特殊格式化）
        convert_to_fp16_with_special_formatting(case_folder, npy_filename="golden_output.npy", out_filename="golden_output_fp16.txt")
