#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
e2e_reciprocal_nr2 单 case 的 Golden vs UR 比对脚本。

比对规则：
- Golden 目录固定为 <case_dir>/smc_0/ur_data_final/，其中文件名为 bankN_final.hex
- 若 ur_data_final 目录不存在：跳过对比并打印目录不存在（返回成功）
- 若目录存在：与 tb 输出的 ur_result_<case_name>_bankN.hex 逐一对比
- 所有 bank 都通过才算通过
"""
from __future__ import print_function

import os
import re
import sys

script_dir = os.path.dirname(os.path.abspath(__file__))
if script_dir not in sys.path:
    sys.path.insert(0, script_dir)
from base_handler import compare_case_single_bank

GOLDEN_DIR = os.path.join("smc_0", "ur_data_final")
BANK_RE = re.compile(r"^bank(\d+)_final\.hex$", re.IGNORECASE)


def main():
    if len(sys.argv) < 2:
        print("用法: {} <case_dir>".format(os.path.basename(sys.argv[0])), file=sys.stderr)
        sys.exit(2)

    case_tag = os.path.splitext(os.path.basename(__file__))[0]
    case_dir = os.path.abspath(sys.argv[1].rstrip(os.sep))
    case_name = os.path.basename(case_dir)
    golden_dir = os.path.join(case_dir, GOLDEN_DIR)
    if not os.path.isdir(golden_dir):
        print("{} 跳过对比: 目录不存在 {}".format(case_tag, golden_dir))
        sys.exit(0)

    bank_items = []
    for name in os.listdir(golden_dir):
        m = BANK_RE.match(name)
        if m:
            bank_items.append((int(m.group(1)), name))

    if not bank_items:
        print("{} 比对失败: {} 下未找到 bank*_final.hex".format(case_tag, golden_dir), file=sys.stderr)
        sys.exit(1)

    bank_items.sort(key=lambda x: x[0])
    failed = []
    for bank_idx, filename in bank_items:
        golden_path = os.path.join(golden_dir, filename)
        passed, msg = compare_case_single_bank(case_dir, case_name, bank_idx, golden_path)
        if passed:
            print("bank{} 比对通过 (Golden: {}, UR: ur_result_{}_bank{}.hex)".format(
                bank_idx, filename, case_name, bank_idx
            ))
        else:
            failed.append("bank{}: {}".format(bank_idx, msg))
            print("bank{} 比对失败: {}".format(bank_idx, msg), file=sys.stderr)

    if failed:
        print("{} 比对失败，共 {} 个 bank 失败".format(case_tag, len(failed)), file=sys.stderr)
        sys.exit(1)

    print("{} 所有 bank 比对通过".format(case_tag))
    sys.exit(0)


if __name__ == "__main__":
    main()
