#!/usr/bin/env bash

#  仿真脚本 - AIACC Top Module
# ----------------------------------------------------------------------------
# 说明：
#   - 将"可配置项（宏）"集中在顶部，便于他人修改适配
#   - 下方"固定逻辑区"尽量不要改动
#   - 包含 aiacc_top 模块及其所有依赖的 .v 文件
# ============================================================================

set -euo pipefail

# ============================= 可配置项 =============================
# 工程根目录
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# 本 cell 目录（A_Integration）
CELL_DIR="$(cd "$(dirname "$0")" && pwd)"

# 仿真数据子目录：test_atomic_ops/<MEM_DATA_SUBFOLDER>/data_list.txt
# 可通过脚本第一个参数传入，默认 fpadd。例如：./run_sim_aiacc_top.sh intadd
# 若传入 test_coverage_* 目录（如 test_coverage_fpadd），则循环处理其下的所有 case 子文件夹
# 用法: ./run_sim_aiacc_top.sh [subfolder] [ur_compare_bank]
#   subfolder: 默认 fpadd；多 case 时传 test_coverage_fpadd 等
#   ur_compare_bank: 多 case 模式下 Golden vs UR 比对的 bank 编号 0/1/2/3/4/5/6/7，默认 2
INPUT_SUBFOLDER="${1:-fpadd}"
UR_COMPARE_BANK="${2:-2}"

# 验证 UR_COMPARE_BANK 参数（如果提供）
if [[ -n "${UR_COMPARE_BANK}" ]]; then
    if ! [[ "${UR_COMPARE_BANK}" =~ ^[0-7]$ ]]; then
        echo "错误: UR_COMPARE_BANK 必须为 0-7 之间的整数，当前值: ${UR_COMPARE_BANK}"
        exit 1
    fi
fi
# 数据根目录（testbench 中 MEM_DATA_BASE，用于拼 data_list.txt 路径）
MEM_DATA_BASE="${CELL_DIR}/test_atomic_ops"

# 输出目录
OUT_DIR="sim_output_aiacc_top"

# Verilog 源文件列表（按模块分组）
# 注意：文件顺序很重要，底层模块应该在前，顶层模块在后
VSRC_FILES=(
    # ========== RtoVR Module ==========
    "${CELL_DIR}/RtoVR/RtoVR.v"
    
    # ========== User Register Module ==========
    "${CELL_DIR}/user_register/bank_sram.v"
    "${CELL_DIR}/user_register/user_register.v"
    
    # ========== INTADD Module ==========
    "${CELL_DIR}/intadd/add8_comb.v"
    "${CELL_DIR}/intadd/add8.v"
    "${CELL_DIR}/intadd/add32_comb.v"
    "${CELL_DIR}/intadd/add32.v"
    "${CELL_DIR}/intadd/intadd.v"
    
    # ========== INT8toFP16 Module ==========
    "${CELL_DIR}/int8tofp16/int8_to_fp16.v"
    "${CELL_DIR}/int8tofp16/int8_to_fp16_array.v"
    
    # ========== FP16MUL Module ==========
    "${CELL_DIR}/fp16mul/fp16tofp32_multiplier.v"
    "${CELL_DIR}/fp16mul/fp16mul.v"
    
    # ========== Common Modules ==========
    "${CELL_DIR}/common/full_adder.v"
    "${CELL_DIR}/common/leading_zero_counter_fp32_m.v"
    "${CELL_DIR}/common/leading_zero_counter_fp16_m.v"
    "${CELL_DIR}/common/IPR.sv"
    "${CELL_DIR}/common/OPR.sv"

    # ========== FP32ADDTREE5TO1 Module ==========
    "${CELL_DIR}/fp32addtree5to1/fp32_aligner_5to1.v"
    "${CELL_DIR}/fp32addtree5to1/fp32_normalizer_rounder_5to1.v"
    "${CELL_DIR}/fp32addtree5to1/fp32_packer_5to1.v"
    "${CELL_DIR}/fp32addtree5to1/fp32_unpacker_5to1.v"
    "${CELL_DIR}/fp32addtree5to1/wallace_tree_5_inputs_5to1.v"
    "${CELL_DIR}/fp32addtree5to1/fp32_adder_tree_final_pipeline_5to1.v"
    
    # ========== FP32ADDTREE8TO1 Module ==========
    "${CELL_DIR}/fp32addtree8to1/delay_align_8to1.v"
    "${CELL_DIR}/fp32addtree8to1/fp32_aligner_8to1.v"
    "${CELL_DIR}/fp32addtree8to1/fp32_normalizer_rounder_8to1.v"
    "${CELL_DIR}/fp32addtree8to1/fp32_packer_8to1.v"
    "${CELL_DIR}/fp32addtree8to1/fp32_unpacker_8to1.v"
    "${CELL_DIR}/fp32addtree8to1/wallace_tree_8_inputs_8to1.v"
    "${CELL_DIR}/fp32addtree8to1/fp32_adder_tree_8_inputs_pipeline_8to1.v"
    
    # ========== FPADD Module ==========
    "${CELL_DIR}/fpadd/fp16_adder_pipeline.v"
    "${CELL_DIR}/fpadd/fp32_adder_pipeline.v"
    "${CELL_DIR}/fpadd/fp_adder_rtl.v"
    
    # ========== FPMUL Module ==========
    "${CELL_DIR}/fpmul/fpmul.v"
    
    # ========== FPTOINT Module ==========
    "${CELL_DIR}/fpto_int/fpto_int.v"
    "${CELL_DIR}/fpto_int/fpto_int_array.v"
    
    # ========== FPTOFP Module ==========
    "${CELL_DIR}/fptofp/fp16_to_fp16.v"
    "${CELL_DIR}/fptofp/fp16_to_fp32.v"
    "${CELL_DIR}/fptofp/fp32_to_fp16.v"
    "${CELL_DIR}/fptofp/fp32_to_fp32.v"
    "${CELL_DIR}/fptofp/fptofp_array.v"
    
    # ========== INTTOINT Module ==========
    "${CELL_DIR}/int_to_int/int_to_int.v"
    "${CELL_DIR}/int_to_int/int_to_int_array.v"
    
    # ========== INTTOFP Module ==========
    "${CELL_DIR}/inttofp/int2fp16.v"
    "${CELL_DIR}/inttofp/int2fp32.v"
    "${CELL_DIR}/inttofp/int32tofp16.v"
    "${CELL_DIR}/inttofp/inttofp.v"
    
    # ========== LOGICAL Module ==========
    "${CELL_DIR}/logical/logical.v"
    
    # ========== SHIFT_UP Module ==========
    "${CELL_DIR}/shift_up/shift_up.v"
    
    # ========== SHIFT_DOWN Module ==========
    "${CELL_DIR}/shift_down/shift_down.v"
    
    # ========== SMI_IQ Module (Instruction Queue) ==========
    "${CELL_DIR}/smi_iq/smi_iq_inst_queen.v"
    "${CELL_DIR}/smi_iq/smi_iq_iic.v"
    "${CELL_DIR}/smi_iq/smi_iq_dly_queen.v"
    "${CELL_DIR}/smi_iq/smi_iq.v"
    
    # ========== Top Module and Testbench ==========
    "${CELL_DIR}/SMC.sv"
    "${CELL_DIR}/aiacc_top.v"
    "${CELL_DIR}/tb_aiacc_top.v"
)

# 仿真选项
ENABLE_COVERAGE=1     # 1 收集覆盖率；0 不收集
ENABLE_FSDB=1        # 1 使能 +fsdb；0 关闭
ENABLE_KDB=1         # 1 使能 -kdb；0 关闭
RUN_URG=1            # 1 生成 URG 报告；0 跳过
TIMESCALE="1ns/1ps"  # 仿真时间精度
# =========================== 可配置项结束 ===========================


# ============================== 固定逻辑区 ===============================
echo "=================================================="
echo "         AIACC Top Module 仿真脚本"
echo "=================================================="
if [[ "${INPUT_SUBFOLDER}" == test_coverage_* ]]; then
    echo "多 case 模式: test_atomic_ops/${INPUT_SUBFOLDER}/*_case*"
else
    echo "单 case 模式: test_atomic_ops/${INPUT_SUBFOLDER} (data_list.txt)"
fi
echo "=================================================="
echo "准备仿真环境..."

# 检查源文件是否存在
echo "检查源文件..."
MISSING_FILES=()
for file in "${VSRC_FILES[@]}"; do
    if [[ ! -f "${file}" ]]; then
        MISSING_FILES+=("${file}")
    fi
done

if [[ ${#MISSING_FILES[@]} -gt 0 ]]; then
    echo "错误: 以下源文件不存在:"
    for file in "${MISSING_FILES[@]}"; do
        echo "  - ${file}"
    done
    exit 1
fi

echo "找到 ${#VSRC_FILES[@]} 个源文件"
# 创建输出目录
rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}"
cd "${OUT_DIR}"
LIB_PATH="$(pwd)"

# 构建 VCS 编译命令
VCS_CMD=(vcs -full64 -debug_access+all -kdb +v2k -sverilog -vhdl -timescale="${TIMESCALE}")

# 添加包含目录（用于 `include 文件）
# 1. CELL_DIR: 用于包含 fp32_defines.vh（位于 A_Integration/ 目录）
# 2. ROOT_DIR: 用于包含 global_defines.v（fp32_defines.vh 中引用 ../../global_defines.v）
VCS_CMD+=(+incdir+"${CELL_DIR}")

# 传入 testbench 数据路径宏（MEM_DATA_BASE, MEM_DATA_SUBFOLDER, DATA_LIST_FILE）
# 注意：对于 test_coverage 模式，这些宏在运行时通过 plusarg 传入，编译时使用默认值
VCS_CMD+=(+define+MEM_DATA_BASE=\"${MEM_DATA_BASE}\")
VCS_CMD+=(+define+MEM_DATA_SUBFOLDER=\"fpadd\")  # 编译时默认值，运行时会被 plusarg 覆盖
VCS_CMD+=(+define+DATA_LIST_FILE=\"data_list.txt\")  # 编译时默认值，运行时会被 plusarg 覆盖

# 添加覆盖率选项
if [[ ${ENABLE_COVERAGE} -eq 1 ]]; then
    VCS_CMD+=(-cm line+cond+fsm+tgl+branch -cm_dir coverage_db)
fi

# 添加波形选项
if [[ ${ENABLE_FSDB} -eq 1 ]]; then
    VCS_CMD+=(+define+WAVES_FSDB +define+WAVES="fsdb")
fi

# 添加源文件和输出目标
VCS_CMD+=("${VSRC_FILES[@]}" -o simv)

echo "=================================================="
echo "编译 RTL..."
echo "=================================================="
if ! "${VCS_CMD[@]}" > compile.log 2>&1; then
    echo "错误: 编译失败，详情见 $(pwd)/compile.log"
    echo "前 50 行错误信息:"
    head -n 50 compile.log
    exit 1
fi

echo "编译成功！"

# ==========================================================================
# 运行仿真：根据输入参数决定是单 case 还是多 case 模式
# ==========================================================================
if [[ "${INPUT_SUBFOLDER}" == test_coverage_* ]]; then
    # 多 case 模式：test_coverage_* 目录
    COVERAGE_DIR="${MEM_DATA_BASE}/${INPUT_SUBFOLDER}"
    if [[ ! -d "${COVERAGE_DIR}" ]]; then
        echo "错误: test_coverage 目录不存在: ${COVERAGE_DIR}"
        exit 1
    fi
    
    # 查找所有 case 子文件夹（名称包含 "_case"）
    CASE_FOLDERS=()
    for item in "${COVERAGE_DIR}"/*; do
        if [[ -d "${item}" ]] && [[ "${item}" == *_case* ]]; then
            CASE_FOLDERS+=("$(basename "${item}")")
        fi
    done
    
    if [[ ${#CASE_FOLDERS[@]} -eq 0 ]]; then
        echo "错误: 在 ${COVERAGE_DIR} 下未找到任何 case 子文件夹"
        exit 1
    fi
    
    # 排序 case 文件夹
    IFS=$'\n' CASE_FOLDERS=($(sort <<<"${CASE_FOLDERS[*]}"))
    unset IFS
    
    echo "=================================================="
    echo "多 case 模式: 找到 ${#CASE_FOLDERS[@]} 个 case"
    echo "=================================================="
    for case in "${CASE_FOLDERS[@]}"; do
        echo "  - ${case}"
    done
    echo ""
    
    # 循环运行每个 case
    TOTAL_CASES=${#CASE_FOLDERS[@]}
    PASSED_CASES=0
    FAILED_CASES=0
    
    for case_idx in "${!CASE_FOLDERS[@]}"; do
        case_name="${CASE_FOLDERS[case_idx]}"
        case_num=$((case_idx + 1))
        
        echo "=================================================="
        echo "运行 Case ${case_num}/${TOTAL_CASES}: ${case_name}"
        echo "=================================================="
        
        # 构建 case 的完整路径和 data_list 文件名
        MEM_DATA_SUBFOLDER="${INPUT_SUBFOLDER}/${case_name}"
        DATA_LIST_FILE="data_list_${case_name}.txt"
        
        # 运行仿真
        RUN_CMD=(./simv)
        
        # 传入运行时宏（覆盖编译时的默认值）
        RUN_CMD+=(+MEM_DATA_SUBFOLDER="${MEM_DATA_SUBFOLDER}")
        RUN_CMD+=(+DATA_LIST_FILE="${DATA_LIST_FILE}")
        
        # 设置仿真运行时选项
        [[ ${ENABLE_COVERAGE} -eq 1 ]] && RUN_CMD+=(-cm line+cond+fsm+tgl+branch -cm_dir coverage_db)
        
        # FSDB 波形选项（每个 case 使用不同的波形文件）
        if [[ ${ENABLE_FSDB} -eq 1 ]]; then
            FSDB_FILE="${LIB_PATH}/tb_aiacc_top_${case_name}.fsdb"
            RUN_CMD+=(+fsdbfile+"${FSDB_FILE}")
            
            WAVE_DO_FILE="${CELL_DIR}/wave_fsdb_aiacc_top.do"
            if [[ -f "${WAVE_DO_FILE}" ]]; then
                RUN_CMD+=(-ucli -do "${WAVE_DO_FILE}")
            fi
        fi
        
        # 执行仿真
        LOG_FILE="sim_output_${case_name}.log"
        if ! "${RUN_CMD[@]}" > "${LOG_FILE}" 2>&1; then
            echo "错误: Case ${case_name} 仿真失败，详情见 ${LOG_FILE}"
            echo "前 50 行错误信息:"
            head -n 50 "${LOG_FILE}"
            FAILED_CASES=$((FAILED_CASES + 1))
            continue
        fi
        
        echo "Case ${case_name} 完成"
        PASSED_CASES=$((PASSED_CASES + 1))
        echo ""
    done
    
    # 汇总结果
    echo "=================================================="
    echo "多 case 测试汇总"
    echo "=================================================="
    echo "总 case 数: ${TOTAL_CASES}"
    echo "完成: ${PASSED_CASES}"
    echo "失败: ${FAILED_CASES}"
    echo "=================================================="
    
    # 仿真结束后调用 Python 进行 Golden vs UR 比对（按 128bit 逐行比较）
    COMPARE_SCRIPT="${CELL_DIR}/compare_golden_ur.py"
    if [[ -f "${COMPARE_SCRIPT}" ]]; then
        echo ""
        if python "${COMPARE_SCRIPT}" "${COVERAGE_DIR}" "${UR_COMPARE_BANK}"; then
            echo "完成"
        else
            echo "Golden vs UR 比对未全部通过，退出码 1"
            exit 1
        fi
    else
        echo "未找到比对脚本 ${COMPARE_SCRIPT}，跳过 Golden vs UR 比对"
    fi
    
    if [[ ${FAILED_CASES} -gt 0 ]]; then
        exit 1
    fi
else
    # 单 case 模式：普通子文件夹
    echo "=================================================="
    echo "运行仿真..."
    echo "=================================================="
    RUN_CMD=(./simv)
    
    # 传入运行时宏
    RUN_CMD+=(+MEM_DATA_SUBFOLDER="${INPUT_SUBFOLDER}")
    RUN_CMD+=(+DATA_LIST_FILE="data_list.txt")
    
    # 设置仿真运行时选项
    [[ ${ENABLE_COVERAGE} -eq 1 ]] && RUN_CMD+=(-cm line+cond+fsm+tgl+branch -cm_dir coverage_db)
    
    # FSDB 波形选项
    if [[ ${ENABLE_FSDB} -eq 1 ]]; then
        FSDB_FILE="${LIB_PATH}/tb_aiacc_top.fsdb"
        RUN_CMD+=(+fsdbfile+"${FSDB_FILE}")
        
        WAVE_DO_FILE="${CELL_DIR}/wave_fsdb_aiacc_top.do"
        if [[ -f "${WAVE_DO_FILE}" ]]; then
            RUN_CMD+=(-ucli -do "${WAVE_DO_FILE}")
        fi
    fi
    
    # 执行仿真并检查结果
    if ! "${RUN_CMD[@]}" > sim_output.log 2>&1; then
        echo "错误: 仿真失败，详情见 $(pwd)/sim_output.log"
        echo "前 100 行错误信息:"
        head -n 100 sim_output.log
        exit 1
    fi
    
    # 单 case 模式：仿真结束后调用 Python 进行 Golden vs UR 比对
    CASE_DIR="${MEM_DATA_BASE}/${INPUT_SUBFOLDER}"
    COMPARE_HANDLER="${CELL_DIR}/compare_handlers/${INPUT_SUBFOLDER}.py"
    
    if [[ -f "${COMPARE_HANDLER}" ]]; then
        echo ""
        echo "=================================================="
        echo "Golden vs UR 比对（单 case 模式）"
        echo "Case: ${INPUT_SUBFOLDER}"
        echo "=================================================="
        if python "${COMPARE_HANDLER}" "${CASE_DIR}"; then
            echo "${INPUT_SUBFOLDER} passed"
        else
            echo "${INPUT_SUBFOLDER} failed"
            exit 1
        fi
        echo "=================================================="
    else
        echo ""
        echo "提示: 未找到比对脚本 ${COMPARE_HANDLER}，跳过 Golden vs UR 比对"
        echo "      如需比对，请在 compare_handlers/ 目录下创建 ${INPUT_SUBFOLDER}.py"
    fi
fi

# 检查仿真日志中的测试结果并提取摘要（仅单 case 模式存在 sim_output.log）
if [[ -f sim_output.log ]]; then
echo "=================================================="
echo "           测试结果汇总"
echo "=================================================="

# 提取测试结果
TEST_RESULTS=()

# 检查 AIACC Top 测试结果
if grep -q "\[PASS\]" sim_output.log; then
    PASS_COUNT=$(grep -c "\[PASS\]" sim_output.log || true)
    TEST_RESULTS+=("✓ 找到 $PASS_COUNT 个 PASS 结果")
fi

if grep -q "\[FAIL\]" sim_output.log; then
    FAIL_COUNT=$(grep -c "\[FAIL\]" sim_output.log || true)
    TEST_RESULTS+=("✗ 找到 $FAIL_COUNT 个 FAIL 结果")
fi

if grep -q "\[WARN\]" sim_output.log; then
    WARN_COUNT=$(grep -c "\[WARN\]" sim_output.log || true)
    TEST_RESULTS+=("⚠ 找到 $WARN_COUNT 个 WARN 结果")
fi

# 检查关键测试点
if grep -q "cru_intadd_o\[0\] (valid) is asserted" sim_output.log; then
    TEST_RESULTS+=("✓ INTADD valid signal asserted")
fi

if grep -q "INTADD result matches expected value" sim_output.log; then
    TEST_RESULTS+=("✓ INTADD result verification passed")
elif grep -q "INTADD result mismatch" sim_output.log; then
    TEST_RESULTS+=("✗ INTADD result verification failed")
fi

if grep -q "INTADD produced non-zero result" sim_output.log; then
    TEST_RESULTS+=("✓ INTADD produced non-zero result")
fi

# 显示每个测试的结果
if [[ ${#TEST_RESULTS[@]} -gt 0 ]]; then
    for result in "${TEST_RESULTS[@]}"; do
        echo "  $result"
    done
    echo "=================================================="
    
    # 统计通过和失败的测试数量
    PASSED_COUNT=0
    FAILED_COUNT=0
    for result in "${TEST_RESULTS[@]}"; do
        if [[ "$result" == *"✓"* ]]; then
            ((PASSED_COUNT++))
        elif [[ "$result" == *"✗"* ]]; then
            ((FAILED_COUNT++))
        fi
    done
    TOTAL_COUNT=${#TEST_RESULTS[@]}
    
    echo "总计: $TOTAL_COUNT 个测试检查点"
    echo "完成: $PASSED_COUNT 个"
    echo "失败: $FAILED_COUNT 个"
    
    if [[ $FAILED_COUNT -eq 0 ]]; then
        echo "=================================================="
        echo "            ✓ 所有测试通过！"
        echo "=================================================="
    else
        echo "=================================================="
        echo "            ✗ 部分测试失败"
        echo "=================================================="
        echo "请查看 sim_output.log 了解详情"
        echo ""
        echo "失败测试的相关日志:"
        echo "----------------------------------------"
        grep -A 3 "\[FAIL\]" sim_output.log | head -n 20
    fi
else
    echo "  ? 未找到明确的测试结果"
    echo "=================================================="
    echo "请查看 sim_output.log 了解详情"
    echo "最后 50 行日志:"
    tail -n 50 sim_output.log
fi
else
    echo "  多 case 模式，结果见上方 Golden vs UR 比对"
    echo "=================================================="
fi

# 生成覆盖率报告（如果启用且工具存在）
if [[ ${ENABLE_COVERAGE} -eq 1 && ${RUN_URG} -eq 1 ]] && command -v urg >/dev/null 2>&1; then
    echo "=================================================="
    echo "生成覆盖率报告..."
    echo "=================================================="
    # 生成 HTML 和文本格式的覆盖率报告
    urg -dir coverage_db -report coverage_report -format both 2>/dev/null || true
    if [[ -f coverage_report/dashboard.html ]]; then
        echo "HTML 报告: coverage_report/dashboard.html"
    fi
    if [[ -f coverage_report/dashboard.txt ]]; then
        echo "文本报告: coverage_report/dashboard.txt"
    fi
fi

echo "=================================================="
echo "                     仿真完成"
echo " 输出目录: $(pwd)"
if [[ -f sim_output.log ]]; then
    echo " 日志文件: sim_output.log"
else
    echo " 多 case 模式，日志见 sim_output_<case名>.log"
fi
if [[ ${ENABLE_FSDB} -eq 1 ]]; then
    echo " 波形文件: tb_aiacc_top.fsdb"
fi
echo "=================================================="

# ============================ 固定逻辑区 结束 ============================
