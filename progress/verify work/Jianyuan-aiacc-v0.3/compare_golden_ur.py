#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
多 case 模式下，对每个 case 的 golden 与 UR dump 进行逐行（128bit）比对。

用法:
    python compare_golden_ur.py <coverage_dir> [bank]

参数:
    coverage_dir: test_coverage_* 的完整路径，如 .../test_atomic_ops/test_coverage_fpadd
    bank: 参与比对的 UR bank 编号，0/1/2/3/4/5/6/7（可选，默认值见规则）

规则:
    - 使用插件式架构：动态加载 compare_handlers/ 目录下对应的比对脚本
    - 每个 test_coverage_* 类型可以有独立的比对脚本（test_coverage_<type>.py）
    - 如果未找到专用脚本，使用 test_coverage_default.py 作为默认比对方式
    - 比对脚本负责具体的比对逻辑（bank 选择、golden 文件选择等）
    - 单个 case 下所有 128bit 行都一致则该 case 通过，打印 passed；否则打印 failed
    - 无 golden 或 ur 文件、行数不一致、任一行不一致均视为该 case 失败

退出码: 全部 case 通过为 0，否则为 1。
"""
from __future__ import print_function

import os
import sys
try:
    from io import open as _open
except ImportError:
    _open = open


def load_compare_handler(coverage_name):
    """
    动态加载 compare_handlers 目录下对应的比对脚本。
    
    Args:
        coverage_name: test_coverage_* 文件夹名，如 test_coverage_fpadd
    
    Returns:
        比对函数 compare_case，如果未找到则返回 None
    """
    script_dir = os.path.dirname(os.path.abspath(__file__))
    handlers_dir = os.path.join(script_dir, "compare_handlers")
    
    # 提取类型名（去掉 test_coverage_ 前缀）
    handler_name = coverage_name.replace("test_coverage_", "").replace("test_coverage", "")
    if not handler_name:
        handler_name = "default"
    
    # 尝试加载专用脚本：test_coverage_<type>.py
    handler_module_name = "test_coverage_{}".format(handler_name)
    handler_file = os.path.join(handlers_dir, "{}.py".format(handler_module_name))
    
    # 调试信息
    print("  调试: coverage_name={}, handler_name={}, handler_file={}, exists={}".format(
        coverage_name, handler_name, handler_file, os.path.isfile(handler_file)), file=sys.stderr)
    
    if os.path.isfile(handler_file):
        # 动态导入模块
        if handlers_dir not in sys.path:
            sys.path.insert(0, handlers_dir)
        try:
            # Python 2/3 兼容的导入方式
            if sys.version_info[0] < 3:
                import imp
                module = imp.load_source(handler_module_name, handler_file)
            else:
                import importlib.util
                spec = importlib.util.spec_from_file_location(handler_module_name, handler_file)
                module = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(module)
            
            if hasattr(module, "compare_case"):
                return module.compare_case
        except Exception as e:
            print("  警告: 加载比对脚本 {} 失败: {}".format(handler_file, e), file=sys.stderr)
    
    # 如果未找到专用脚本，尝试加载默认脚本
    default_file = os.path.join(handlers_dir, "test_coverage_default.py")
    if os.path.isfile(default_file):
        try:
            if sys.version_info[0] < 3:
                import imp
                module = imp.load_source("test_coverage_default", default_file)
            else:
                import importlib.util
                spec = importlib.util.spec_from_file_location("test_coverage_default", default_file)
                module = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(module)
            
            if hasattr(module, "compare_case"):
                return module.compare_case
        except Exception as e:
            print("  警告: 加载默认比对脚本失败: {}".format(e), file=sys.stderr)
    
    return None


def get_case_folders(coverage_dir):
    """返回 coverage_dir 下名称包含 _case 的子文件夹名列表（已排序）。"""
    if not os.path.isdir(coverage_dir):
        return []
    names = []
    for item in os.listdir(coverage_dir):
        if "_case" in item.lower() and os.path.isdir(os.path.join(coverage_dir, item)):
            names.append(item)
    return sorted(names)


def main():
    if len(sys.argv) < 2:
        print("用法: {} <coverage_dir> [bank]".format(os.path.basename(sys.argv[0])), file=sys.stderr)
        sys.exit(2)
    coverage_dir = sys.argv[1].rstrip('/\\')  # 移除末尾的路径分隔符
    
    coverage_name = os.path.basename(coverage_dir)
    
    # 解析 bank 参数（可选，某些类型可能不使用）
    bank = None
    if len(sys.argv) >= 3:
        try:
            bank = int(sys.argv[2])
            if bank < 0 or bank > 7:
                print("错误: bank 必须为 0-7 之间的整数，当前值: {}".format(bank), file=sys.stderr)
                sys.exit(2)
        except ValueError:
            print("错误: bank 必须为整数", file=sys.stderr)
            sys.exit(2)
    
    # 尝试加载专用比对脚本
    compare_func = load_compare_handler(coverage_name)
    
    if not compare_func:
        print("错误: 未找到比对脚本，且默认脚本加载失败", file=sys.stderr)
        print("建议: 在 compare_handlers/ 目录下创建 {}.py".format(coverage_name), file=sys.stderr)
        sys.exit(2)

    case_folders = get_case_folders(coverage_dir)
    if not case_folders:
        print("未找到任何 case 子文件夹: {}".format(coverage_dir), file=sys.stderr)
        sys.exit(1)

    print("==================================================")
    print("Golden vs UR 比对")
    print("目录: {}".format(coverage_dir))
    print("类型: {}".format(coverage_name))
    if bank is not None:
        print("Bank: {}".format(bank))
    print("==================================================")

    all_passed = True
    failed_cases = []
    for case_name in case_folders:
        case_dir = os.path.join(coverage_dir, case_name)
        passed, msg = compare_func(case_dir, case_name, bank)
        if passed:
            print("{} passed".format(case_name))
        else:
            print("{} failed  ({})".format(case_name, msg))
            all_passed = False
            failed_cases.append(case_name)

    print("==================================================")
    if all_passed:
        print("全部 case 比对通过")
    else:
        print("未通过的 case: {}".format(", ".join(failed_cases)))
    print("==================================================")
    sys.exit(0 if all_passed else 1)


if __name__ == "__main__":
    main()
