#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
生成 data_list.txt 并清理 hex 文件中的 0x 前缀

功能：
- 扫描指定子文件夹（或自动检测所有子文件夹）下的所有 .hex 文件
- 生成 data_list.txt 文件，包含 mem_name 和绝对路径
- 移除所有 hex 文件中每行开头的 0x 前缀（含 case 下 output_data 路径中的 hex）
- 特殊处理：对于 test_atomic_ops 下名称包含 "test_coverage" 的文件夹：
  * 使用插件式架构：动态加载 test_coverage_handlers/ 目录下对应的处理脚本
  * 每个 test_coverage_* 类型可以有独立的处理脚本（test_coverage_<type>.py）
  * 如果未找到专用脚本，使用 test_coverage_default.py 作为默认处理方式
  * 处理脚本负责：
    - 遍历该文件夹下的所有 case 子文件夹（如 fpadd_case001, fpadd_case002 等）
    - 对每个 case 子文件夹生成 data_list_<case名>.txt（如 data_list_fpadd_case001.txt）

使用方法：
    python generate_data_list_coverage.py [subfolder_name]
    
- 脚本位于 A_Integration/，扫描根目录为 A_Integration/test_atomic_ops/。
- 若提供 subfolder_name（如 intadd、fpadd、test_coverage_fpadd），则仅处理 test_atomic_ops/<subfolder_name>/。
- 若不提供参数，则自动检测 test_atomic_ops/ 下的所有子文件夹并逐个生成 data_list.txt。
- 对于 test_coverage_* 文件夹，会自动处理其下的所有 case 子文件夹。
- 特殊处理：若 case 下存在 smc_0 子目录且其中包含 .hex 文件（如 e2e_sin_v3/smc_0），
  则从 smc_0 收集 hex 并生成 data_list.txt 到 case 根目录，便于仿真时 MEM_DATA_SUBFOLDER=e2e_sin_v3 即可。
- 对于 e2e_*_v3、e2e_reciprocal_nr2、e2e_exp_taylor7 等 case，递归清理该 case 目录下所有 .hex 的 0x/0X 前缀。

兼容 Python 2.7.5（无 pathlib，使用 os.path）。
"""
from __future__ import print_function

import os
import sys
import re
try:
    from io import open
except ImportError:
    pass


def _to_unicode(s):
    """Python 2: 写入 io.open(encoding='utf-8') 的文件需 unicode；Python 3 无需转换。"""
    if sys.version_info[0] < 3 and isinstance(s, str):
        return s.decode('utf-8', 'replace')
    return s

# ============================================================================
# Mem Name 列表（从 tb_aiacc_top.v 提取）
# ============================================================================
MEM_NAME_LIST = [
    "inst_mem_intadd",
    "inst_mem_int8tofp16",
    "inst_mem_fp16mul",
    "inst_mem_fp32addtree5to1",
    "inst_mem_fp32addtree8to1",
    "inst_mem_fpmul",
    "inst_mem_fpadd",
    "inst_mem_fptofp",
    "inst_mem_inttoint",
    "inst_mem_fptoint",
    "inst_mem_inttofp",
    "inst_mem_logic",
    "inst_mem_shiftup",
    "inst_mem_shiftdn",
    "inst_mem_ur_rdata_0",
    "inst_mem_ur_rdata_1",
    "inst_mem_ur_rdata_2",
    "inst_mem_ur_rdata_3",
    "inst_mem_ur_wdata_0",
    "inst_mem_ur_wdata_1",
    "inst_mem_ur_wdata_2",
    "inst_mem_ur_wdata_3",
    "inst_mem_stb",
    "inst_mem_ldb",
    "dut.u_smc.u_user_register.bram_bank_inst[0].u_bank_sram.memory_array",
    "dut.u_smc.u_user_register.bram_bank_inst[1].u_bank_sram.memory_array",
    "dut.u_smc.u_user_register.bram_bank_inst[2].u_bank_sram.memory_array",
    "dut.u_smc.u_user_register.bram_bank_inst[3].u_bank_sram.memory_array",
    "dut.u_smc.u_user_register.bram_bank_inst[4].u_bank_sram.memory_array",
    "dut.u_smc.u_user_register.bram_bank_inst[5].u_bank_sram.memory_array",
    "dut.u_smc.u_user_register.bram_bank_inst[6].u_bank_sram.memory_array",
    "dut.u_smc.u_user_register.bram_bank_inst[7].u_bank_sram.memory_array",
]

RTOVR_PATTERN = re.compile(r'^iq_rtovr-(\d+)\.hex$', re.IGNORECASE)
UR_RDATA_PATTERN = re.compile(r'^iq_ur-r(\d+)\.hex$', re.IGNORECASE)
UR_WDATA_PATTERN = re.compile(r'^iq_ur-w(\d+)\.hex$', re.IGNORECASE)
BANK_PATTERN = re.compile(r'^bank(\d+).*\.hex$', re.IGNORECASE)
HEX_TOKEN_PREFIX_RE = re.compile(r'\b0[xX]([0-9a-fA-F]+)\b')


def match_filename_to_mem_name(filename):
    """根据文件名在 MEM_NAME_LIST 中查找相似匹配的 mem name。"""
    name_without_ext = filename.replace('.hex', '').lower()
    
    match = RTOVR_PATTERN.match(filename)
    if match:
        index = int(match.group(1))
        if 0 <= index <= 39:
            return "inst_mem_rtovr[{}]".format(index)
    
    match = UR_RDATA_PATTERN.match(filename)
    if match:
        index = int(match.group(1))
        mem_name = "inst_mem_ur_rdata_{}".format(index)
        if mem_name in MEM_NAME_LIST:
            return mem_name
    
    match = UR_WDATA_PATTERN.match(filename)
    if match:
        index = int(match.group(1))
        mem_name = "inst_mem_ur_wdata_{}".format(index)
        if mem_name in MEM_NAME_LIST:
            return mem_name
    
    match = BANK_PATTERN.match(filename)
    if match:
        index = int(match.group(1))
        mem_name = "dut.u_smc.u_user_register.bram_bank_inst[{}].u_bank_sram.memory_array".format(index)
        if mem_name in MEM_NAME_LIST:
            return mem_name
    
    keywords = name_without_ext
    if keywords.startswith('inst_'):
        keywords = keywords[5:]
    elif keywords.startswith('iq_'):
        keywords = keywords[3:]
    
    best_match = None
    best_score = 0
    for mem_name in MEM_NAME_LIST:
        mem_keywords = mem_name.lower()
        if mem_keywords.startswith('inst_mem_'):
            mem_keywords = mem_keywords[9:]
        elif mem_keywords.startswith('dut.u_smc.u_user_register.bram_bank_inst['):
            bank_match = re.search(r'\[(\d+)\]', mem_keywords)
            if bank_match:
                mem_keywords = "bank{}".format(bank_match.group(1))
        score = 0
        if keywords == mem_keywords:
            score = 100
        elif keywords in mem_keywords:
            score = 50
        elif mem_keywords in keywords:
            score = 30
        if score > best_score:
            best_score = score
            best_match = mem_name
    if best_score >= 30:
        return best_match
    return None


def find_subfolders(base_dir):
    """查找 base_dir 下的所有直接子文件夹。返回字符串路径列表。跳过 __pycache__。"""
    if not os.path.exists(base_dir) or not os.path.isdir(base_dir):
        return []
    subfolders = []
    for item in os.listdir(base_dir):
        if item == '__pycache__':
            continue
        full = os.path.join(base_dir, item)
        if os.path.isdir(full):
            subfolders.append(full)
    return sorted(subfolders)


def rglob_hex_files(root_dir):
    """
    查找 root_dir 下的 .hex 文件。
    - 只扫描 case 目录下的直接文件（用于 smi_iq，如 iq_*.hex）
    - 只扫描 ur_data/ 子目录（用于 UR bank 文件，如 bank*.hex）
    - 不扫描其他子目录（如 output_data, analysis 等）
    - 排除 UR 输出文件（如 ur_result_*.hex），这些是仿真结果文件，不应加载到 DUT
    
    Args:
        root_dir: case 目录路径
    
    Returns:
        绝对路径列表
    """
    result = []
    root_dir = os.path.abspath(root_dir)
    
    # 1. 扫描根目录下的直接文件（用于 smi_iq，如 iq_fp32addtree5to1.hex, iq_rtovr-*.hex, iq_ur-*.hex）
    if os.path.isdir(root_dir):
        for name in os.listdir(root_dir):
            # 排除 UR 输出文件（ur_result_*.hex）
            if name.lower().startswith('ur_result_'):
                continue
            item_path = os.path.join(root_dir, name)
            if os.path.isfile(item_path) and name.endswith('.hex'):
                result.append(os.path.abspath(item_path))
    
    # 2. 扫描 ur_data/ 子目录（用于 UR bank 文件，如 bank0.hex, bank1.hex）
    ur_data_dir = os.path.join(root_dir, "ur_data")
    if os.path.isdir(ur_data_dir):
        for name in os.listdir(ur_data_dir):
            # 排除 UR 输出文件（ur_result_*.hex）
            if name.lower().startswith('ur_result_'):
                continue
            item_path = os.path.join(ur_data_dir, name)
            if os.path.isfile(item_path) and name.endswith('.hex'):
                result.append(os.path.abspath(item_path))
    
    return sorted(result)


# 使用 smc_0 作为数据子目录的 case（如 e2e_sin_v3）：hex 文件在 case/smc_0/ 下，data_list.txt 写在 case 根目录
SMC_0_SUBDIR = "smc_0"
E2E_V3_CASE_RE = re.compile(r'^e2e_.*_v3$', re.IGNORECASE)


def get_data_dir_for_case(subfolder_path):
    """
    确定 case 的数据目录：若存在 smc_0 子目录且其中有 .hex 文件，则使用 smc_0 作为数据源；
    否则使用 case 根目录。
    
    Returns:
        (data_dir, use_smc_0): data_dir 为用于收集 hex 的目录（绝对路径），use_smc_0 为是否使用了 smc_0
    """
    subfolder = os.path.abspath(subfolder_path)
    smc_0_dir = os.path.join(subfolder, SMC_0_SUBDIR)
    if os.path.isdir(smc_0_dir):
        hex_in_smc0 = rglob_hex_files(smc_0_dir)
        if hex_in_smc0:
            return (os.path.abspath(smc_0_dir), True)
    return (subfolder, False)


def is_e2e_v3_case(case_dir):
    """判断是否为 e2e_*_v3 case 目录。"""
    return E2E_V3_CASE_RE.match(os.path.basename(os.path.abspath(case_dir))) is not None


def case_needs_hex_0x_clean_recursive(case_dir):
    """判断该 case 是否需要在生成 data_list 时递归清理目录下所有 .hex 的 0x 前缀。
    目前包括：e2e_*_v3、e2e_reciprocal_nr2、e2e_exp_taylor7。
    """
    name = os.path.basename(os.path.abspath(case_dir))
    if E2E_V3_CASE_RE.match(name):
        return True
    if name == "e2e_reciprocal_nr2":
        return True
    if name == "e2e_exp_taylor7":
        return True
    return False


def remove_0x_prefix_from_file(file_path):
    """移除文件中的 0x 前缀（逐 token 处理）。返回 (是否修改, 处理行数)。"""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()
        modified = False
        processed_lines = []
        for line in lines:
            line_ending = '\n' if line.endswith('\n') else ''
            line_body = line[:-1] if line_ending else line
            new_body = HEX_TOKEN_PREFIX_RE.sub(r'\1', line_body)
            if new_body != line_body:
                modified = True
            processed_lines.append(new_body + line_ending)
        if modified:
            with open(file_path, 'w', encoding='utf-8') as f:
                f.writelines(processed_lines)
            return True, len(lines)
        return False, len(lines)
    except Exception as e:
        print("  错误: 处理文件 {} 时出错: {}".format(file_path, e))
        return False, 0


def remove_0x_prefix_in_output_data(case_dir):
    """
    检测并清理 case 目录下 output_data 路径中的 .hex 文件：若某行带有 0x/0X 前缀则去掉。
    返回修改过的文件数量。
    """
    output_data_dir = os.path.join(case_dir, "output_data")
    if not os.path.isdir(output_data_dir):
        return 0
    count = 0
    for name in os.listdir(output_data_dir):
        if not name.lower().endswith('.hex'):
            continue
        path = os.path.join(output_data_dir, name)
        if not os.path.isfile(path):
            continue
        modified, _ = remove_0x_prefix_from_file(path)
        if modified:
            count += 1
    return count


def remove_0x_prefix_in_all_hex_recursive(case_dir):
    """
    递归清理 case_dir 下所有 .hex 文件中的行首 0x/0X 前缀。
    返回修改过的文件数量。
    """
    count = 0
    for root, _, files in os.walk(case_dir):
        for name in files:
            if not name.lower().endswith('.hex'):
                continue
            path = os.path.join(root, name)
            if not os.path.isfile(path):
                continue
            modified, _ = remove_0x_prefix_from_file(path)
            if modified:
                count += 1
    return count


def generate_data_list(subfolder_path, data_list_suffix=None):
    """
    为指定子文件夹生成 data_list 文件并清理 hex 文件。
    data_list_suffix: 若提供（如 "fpadd_case001"），输出文件名为 data_list_<suffix>.txt；否则为 data_list.txt。
    若 case 下存在 smc_0 子目录且含 hex 文件（如 e2e_sin_v3），则从 smc_0 收集 hex，
    data_list 写到 case 根目录，其中每行为 mem_name + 绝对路径（路径已含 smc_0），tb 按 data_list 中的路径加载即可。
    """
    subfolder = os.path.abspath(subfolder_path)
    if not os.path.exists(subfolder) or not os.path.isdir(subfolder):
        print("错误: 子文件夹不存在或不是目录: {}".format(subfolder))
        return
    print("\n处理子文件夹: {}".format(os.path.basename(subfolder)))
    print("  路径: {}".format(subfolder))
    
    # 确定数据目录：若存在 smc_0 且其中有 hex，则从 smc_0 收集（如 e2e_sin_v3）
    data_dir, use_smc_0 = get_data_dir_for_case(subfolder)
    if use_smc_0:
        print("  使用子目录 {} 作为数据源: {}".format(SMC_0_SUBDIR, data_dir))
    
    if data_list_suffix:
        data_list_filename = "data_list_{}.txt".format(data_list_suffix)
    else:
        data_list_filename = "data_list.txt"
    
    hex_files = rglob_hex_files(data_dir)
    if not hex_files:
        print("  未找到任何 .hex 文件")
        data_list_path = os.path.join(subfolder, data_list_filename)
        try:
            open(data_list_path, 'w').close()
        except IOError:
            pass
        print("  已创建空的 {}: {}".format(data_list_filename, data_list_path))
        output_data_modified = remove_0x_prefix_in_output_data(data_dir)
        if output_data_modified:
            print("  已去掉 output_data 中 {} 个 hex 文件的 0x 前缀".format(output_data_modified))
        return
    
    # data_list 写到 case 根目录，路径列使用绝对路径（含 smc_0 时已指向 smc_0 下文件），tb 直接按路径加载
    data_list_path = os.path.join(subfolder, data_list_filename)
    matched_count = 0
    unmatched_files = []
    with open(data_list_path, 'w', encoding='utf-8') as f:
        for hex_file in hex_files:
            filename = os.path.basename(hex_file)
            absolute_path = os.path.abspath(hex_file)
            mem_name = match_filename_to_mem_name(filename)
            if mem_name:
                f.write(_to_unicode("{} {}\n".format(mem_name, absolute_path)))
                matched_count += 1
            else:
                f.write(_to_unicode("{}\n".format(absolute_path)))
                unmatched_files.append(filename)
    print("  已生成 {}: {}".format(data_list_filename, data_list_path))
    if unmatched_files:
        print("  未匹配到 mem name: {} 个".format(len(unmatched_files)))
        for uf in unmatched_files:
            print("    - {}".format(uf))
    total_modified = 0
    total_skipped = 0
    for hex_file in hex_files:
        modified, _ = remove_0x_prefix_from_file(hex_file)
        if modified:
            total_modified += 1
        else:
            total_skipped += 1

    # 清理数据目录下的 output_data 中的 hex 的 0x 前缀（data_dir 可能是 smc_0）
    output_data_modified = remove_0x_prefix_in_output_data(data_dir)
    if output_data_modified:
        print("  已去掉 output_data 中 {} 个 hex 文件的 0x 前缀".format(output_data_modified))

    # e2e_*_v3 / e2e_reciprocal_nr2 等特例：递归清理该 case 目录下所有 .hex 的 0x 前缀
    # （包括 smc_0/ur_data_out、ur_data_final、ur_data、以及其他子目录中的 hex）
    if case_needs_hex_0x_clean_recursive(subfolder):
        modified_all = remove_0x_prefix_in_all_hex_recursive(subfolder)
        if modified_all:
            print("  [{}] 已递归去掉 {} 个 hex 文件的 0x 前缀".format(
                os.path.basename(subfolder), modified_all
            ))
        else:
            print("  [{}] 递归检查完成，未发现带 0x 前缀的 hex 文件".format(
                os.path.basename(subfolder)
            ))


def load_coverage_handler(coverage_name):
    """
    动态加载 test_coverage_handlers 目录下对应的处理脚本。
    
    Args:
        coverage_name: test_coverage_* 文件夹名，如 test_coverage_fpadd
    
    Returns:
        处理函数 process_coverage_folder，如果未找到则返回 None
    """
    script_dir = os.path.dirname(os.path.abspath(__file__))
    handlers_dir = os.path.join(script_dir, "test_coverage_handlers")
    
    # 提取类型名（去掉 test_coverage_ 前缀）
    handler_name = coverage_name.replace("test_coverage_", "").replace("test_coverage", "")
    if not handler_name:
        handler_name = "default"
    
    # 尝试加载专用脚本：test_coverage_<type>.py
    handler_module_name = "test_coverage_{}".format(handler_name)
    handler_file = os.path.join(handlers_dir, "{}.py".format(handler_module_name))
    
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
            
            if hasattr(module, "process_coverage_folder"):
                return module.process_coverage_folder
        except Exception as e:
            print("  警告: 加载处理脚本 {} 失败: {}".format(handler_file, e))
    
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
            
            if hasattr(module, "process_coverage_folder"):
                return module.process_coverage_folder
        except Exception as e:
            print("  警告: 加载默认处理脚本失败: {}".format(e))
    
    return None


def process_test_coverage_folder(coverage_folder_path):
    """
    处理 test_coverage_* 文件夹：动态加载对应的处理脚本并调用。
    如果未找到专用脚本，使用默认处理方式。
    """
    coverage_name = os.path.basename(coverage_folder_path)
    
    # 尝试加载专用处理脚本
    handler_func = load_coverage_handler(coverage_name)
    
    if handler_func:
        # 调用专用处理脚本
        handler_func(coverage_folder_path)
    else:
        # 回退到默认处理方式（保持向后兼容）
        print("\n" + "=" * 60)
        print("处理 test_coverage 文件夹: {}".format(coverage_name))
        print("=" * 60)
        print("  警告: 未找到专用处理脚本，使用默认处理方式")
        print("  建议: 在 test_coverage_handlers/ 目录下创建 {}.py".format(coverage_name))
        
        # 查找所有 case 子文件夹
        case_folders = []
        for item in os.listdir(coverage_folder_path):
            if "_case" in item.lower():
                full_path = os.path.join(coverage_folder_path, item)
                if os.path.isdir(full_path):
                    case_folders.append(full_path)
        
        if not case_folders:
            print("  未找到任何 case 子文件夹")
            return
        
        case_folders = sorted(case_folders)
        print("  找到 {} 个 case 子文件夹:".format(len(case_folders)))
        for cf in case_folders:
            print("    - {}".format(os.path.basename(cf)))
        print()
        
        # 处理每个 case 文件夹
        for case_folder in case_folders:
            case_name = os.path.basename(case_folder)
            print("\n处理 case: {}".format(case_name))
            print("  路径: {}".format(case_folder))
            
            generate_data_list(case_folder, data_list_suffix=case_name)


def main():
    """主函数：扫描根目录为 <脚本目录>/test_atomic_ops/。"""
    script_dir = os.path.dirname(os.path.abspath(os.path.realpath(__file__)))
    # 扫描根目录：A_Integration/test_atomic_ops/
    base_dir = os.path.join(script_dir, "test_atomic_ops")
    print("=" * 60)
    print("生成 data_list.txt 并清理 hex 文件")
    print("=" * 60)
    print("扫描根目录: {}".format(base_dir))
    if not os.path.exists(base_dir) or not os.path.isdir(base_dir):
        print("错误: test_atomic_ops 目录不存在: {}".format(base_dir))
        sys.exit(1)
    print()
    if len(sys.argv) > 1:
        subfolder_name = sys.argv[1]
        subfolder_path = os.path.join(base_dir, subfolder_name)
        if not os.path.exists(subfolder_path):
            print("错误: 子文件夹不存在: {}".format(subfolder_path))
            sys.exit(1)
        
        # 检查是否是 test_coverage 文件夹
        if "test_coverage" in subfolder_name.lower():
            process_test_coverage_folder(subfolder_path)
        else:
            generate_data_list(subfolder_path)
    else:
        subfolders = find_subfolders(base_dir)
        if not subfolders:
            print("未在 test_atomic_ops 下找到任何子文件夹")
            return
        print("自动检测到 test_atomic_ops 下 {} 个子文件夹:".format(len(subfolders)))
        for sf in subfolders:
            print("  - {}".format(os.path.basename(sf)))
        print()
        for subfolder in subfolders:
            subfolder_name = os.path.basename(subfolder)
            # 检查是否是 test_coverage 文件夹
            if "test_coverage" in subfolder_name.lower():
                process_test_coverage_folder(subfolder)
            else:
                generate_data_list(subfolder)
    print()
    print("=" * 60)
    print("处理完成")
    print("=" * 60)


if __name__ == "__main__":
    main()
