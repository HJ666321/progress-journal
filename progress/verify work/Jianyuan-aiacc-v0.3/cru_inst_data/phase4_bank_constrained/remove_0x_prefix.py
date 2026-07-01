#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
移除 hex 文件中的 0x 前缀脚本

功能：
- 扫描指定目录下的所有 .hex 文件
- 移除每行开头的 0x 前缀
- 保持文件的其他格式不变

使用方法：
    python remove_0x_prefix.py
"""

import os
import sys
from pathlib import Path

def remove_0x_prefix_from_file(file_path):
    """
    移除文件中的 0x 前缀
    
    Args:
        file_path: 文件路径
        
    Returns:
        tuple: (是否修改, 处理的行数)
    """
    try:
        # 读取文件内容
        with open(file_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()
        
        modified = False
        processed_lines = []
        
        # 处理每一行
        for line in lines:
            stripped_line = line.strip()
            
            # 如果行以 0x 开头，去掉前缀
            if stripped_line.startswith('0x') or stripped_line.startswith('0X'):
                # 去掉 0x 前缀，保留后面的内容
                new_line = stripped_line[2:]
                # 保留原始行的换行符
                if line.endswith('\n'):
                    new_line += '\n'
                processed_lines.append(new_line)
                modified = True
            else:
                # 没有 0x 前缀，保持原样（包括空行）
                processed_lines.append(line)
        
        # 如果文件被修改，直接写回
        if modified:
            with open(file_path, 'w', encoding='utf-8') as f:
                f.writelines(processed_lines)
            return True, len(lines)
        else:
            return False, len(lines)
            
    except Exception as e:
        print(f"  错误: 处理文件 {file_path} 时出错: {e}")
        return False, 0

def main():
    """主函数"""
    # 获取脚本所在目录
    script_dir = Path(__file__).parent.absolute()
    target_dir = script_dir
    
    print("=" * 60)
    print("移除 hex 文件中的 0x 前缀")
    print("=" * 60)
    print(f"目标目录: {target_dir}")
    print()
    
    # 查找所有 .hex 文件
    hex_files = list(target_dir.glob("*.hex"))
    
    if not hex_files:
        print("未找到任何 .hex 文件")
        return
    
    print(f"找到 {len(hex_files)} 个 .hex 文件:")
    for f in sorted(hex_files):
        print(f"  - {f.name}")
    print()
    
    # 处理每个文件
    total_modified = 0
    total_skipped = 0
    total_lines = 0
    
    for hex_file in sorted(hex_files):
        print(f"处理: {hex_file.name}...", end=' ')
        modified, line_count = remove_0x_prefix_from_file(hex_file)
        total_lines += line_count
        
        if modified:
            print(f"[OK] 已修改 ({line_count} 行)")
            total_modified += 1
        else:
            print(f"[SKIP] 无需修改 ({line_count} 行)")
            total_skipped += 1
    
    print()
    print("=" * 60)
    print("处理完成")
    print("=" * 60)
    print(f"总计: {len(hex_files)} 个文件")
    print(f"  已修改: {total_modified} 个")
    print(f"  无需修改: {total_skipped} 个")
    print(f"  总行数: {total_lines} 行")
    print()

if __name__ == "__main__":
    main()
