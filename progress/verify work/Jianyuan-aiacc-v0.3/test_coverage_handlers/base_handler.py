#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
test_coverage 处理脚本的基础模块，提供通用函数。
"""
from __future__ import print_function

import os
import sys
try:
    from io import open
except ImportError:
    pass

# 延迟导入主脚本中的 generate_data_list 函数（避免循环导入）
# 通过 sys.path 添加主脚本目录
_script_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _script_dir not in sys.path:
    sys.path.insert(0, _script_dir)

# 延迟导入 generate_data_list 函数（在首次使用时导入）
_generate_data_list = None


def _import_generate_data_list():
    """延迟导入主脚本的 generate_data_list 函数（避免循环导入）。"""
    global _generate_data_list
    if _generate_data_list is None:
        try:
            import generate_data_list_coverage
            _generate_data_list = generate_data_list_coverage.generate_data_list
        except ImportError as e:
            raise ImportError("无法导入 generate_data_list_coverage: {}".format(e))


def generate_data_list(*args, **kwargs):
    """调用主脚本的 generate_data_list 函数。"""
    _import_generate_data_list()
    return _generate_data_list(*args, **kwargs)


def _to_unicode(s):
    """Python 2: 写入 io.open(encoding='utf-8') 的文件需 unicode；Python 3 无需转换。"""
    if sys.version_info[0] < 3 and isinstance(s, str):
        return s.decode('utf-8', 'replace')
    return s


def get_case_folders(coverage_folder_path):
    """返回 coverage_folder_path 下名称包含 _case 的子文件夹路径列表（已排序）。"""
    if not os.path.isdir(coverage_folder_path):
        return []
    case_folders = []
    for item in os.listdir(coverage_folder_path):
        if "_case" in item.lower():
            full_path = os.path.join(coverage_folder_path, item)
            if os.path.isdir(full_path):
                case_folders.append(full_path)
    return sorted(case_folders)


