#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
比对脚本的基础模块，提供通用函数。
"""
from __future__ import print_function

import os
import sys
try:
    from io import open as _open
except ImportError:
    _open = open


def normalize_hex_line(line):
    """去掉首尾空白并转为大写，便于比较。空行保留为空字符串。"""
    s = line.strip()
    return s.upper() if s else ""


def get_case_folders(coverage_dir):
    """返回 coverage_dir 下名称包含 _case 的子文件夹名列表（已排序）。"""
    if not os.path.isdir(coverage_dir):
        return []
    names = []
    for item in os.listdir(coverage_dir):
        if "_case" in item.lower() and os.path.isdir(os.path.join(coverage_dir, item)):
            names.append(item)
    return sorted(names)


def compare_case_single_bank(case_dir, case_name, bank, golden_path):
    """
    比对该 case 的单个 bank 的 golden 与 ur_result 文件。
    返回 (passed: bool, message: str)。
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

    for i, (g, u) in enumerate(zip(golden_valid, ur_valid)):
        if len(g) != 32 or len(u) != 32:
            return False, "第 {} 行长度非 32 字符: golden len={}, ur len={}".format(i + 1, len(g), len(u))
        if g != u:
            return False, "第 {} 行不一致: golden {} vs ur {}".format(i + 1, g, u)

    return True, ""
