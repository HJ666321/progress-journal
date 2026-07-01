#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
e2e_sin_v3 单 case 的 Golden vs UR 比对脚本。

比对规则：
- Golden 文件目录：<case_dir>/smc_0/ur_data_out/
- 读取其中所有 bank*.hex（如 bank0.hex, bank1.hex, ...）
- 与 tb 输出的 ur_result_<case_name>_bankN.hex 逐一对比
- 所有 bank 都通过才算通过

用法（由 run_sim_aiacc_top.sh 单 case 模式调用）:
    python compare_handlers/e2e_sin_v3.py <case_dir>
"""
from __future__ import print_function

import os
import re
import sys

# 使用 base_handler 的逐行比对（128bit 严格一致）
script_dir = os.path.dirname(os.path.abspath(__file__))
if script_dir not in sys.path:
    sys.path.insert(0, script_dir)
from base_handler import compare_case_single_bank

GOLDEN_DIR = os.path.join("smc_0", "ur_data_out")
BANK_RE = re.compile(r"^bank(\d+)\.hex$", re.IGNORECASE)


def main():
    if len(sys.argv) < 2:
        print("用法: {} <case_dir>".format(os.path.basename(sys.argv[0])), file=sys.stderr)
        sys.exit(2)
    case_dir = os.path.abspath(sys.argv[1].rstrip(os.sep))
    case_name = os.path.basename(case_dir)
    golden_dir = os.path.join(case_dir, GOLDEN_DIR)
    if not os.path.isdir(golden_dir):
        print("e2e_sin_v3 比对失败: Golden 目录不存在: {}".format(golden_dir), file=sys.stderr)
        sys.exit(1)

    bank_items = []
    for name in os.listdir(golden_dir):
        m = BANK_RE.match(name)
        if not m:
            continue
        bank_items.append((int(m.group(1)), name))

    if not bank_items:
        print("e2e_sin_v3 比对失败: {} 下未找到 bank*.hex".format(golden_dir), file=sys.stderr)
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
        print("e2e_sin_v3 比对失败，共 {} 个 bank 失败".format(len(failed)), file=sys.stderr)
        sys.exit(1)

    print("e2e_sin_v3 所有 bank 比对通过")
    sys.exit(0)


if __name__ == "__main__":
    main()
