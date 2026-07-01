#!/usr/bin/env bash

#  仿真脚本 - SMC Module
# ----------------------------------------------------------------------------
# 说明：
#   - 将"可配置项（宏）"集中在顶部，便于他人修改适配
#   - 下方"固定逻辑区"尽量不要改动
#   - 包含 A_Integration 目录下所有子模块的 .v 文件
# ============================================================================

set -euo pipefail

# ============================= 可配置项 =============================
# 工程根目录
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# 本 cell 目录（A_Integration）
CELL_DIR="$(cd "$(dirname "$0")" && pwd)"

# 输出目录
OUT_DIR="sim_output"

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
    
    # ========== Top Module and Testbench ==========
    "${CELL_DIR}/SMC.sv"
    "${CELL_DIR}/tb_smc.sv"
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
echo "         SMC Module 仿真脚本"
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
VCS_CMD=(vcs -full64 -debug_access+all -kdb -lca +v2k -sverilog -vhdl -timescale="${TIMESCALE}")

# 添加包含目录（用于 `include 文件）
# 1. CELL_DIR: 用于包含 fp32_defines.vh（位于 A_Integration/ 目录）
# 2. ROOT_DIR: 用于包含 global_defines.v（fp32_defines.vh 中引用 ../../global_defines.v）
VCS_CMD+=(+incdir+"${CELL_DIR}")

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

# 运行仿真
echo "=================================================="
echo "运行仿真..."
echo "=================================================="
RUN_CMD=(./simv)

# 设置仿真运行时选项
[[ ${ENABLE_COVERAGE} -eq 1 ]] && RUN_CMD+=(-cm line+cond+fsm+tgl+branch -cm_dir coverage_db)

# FSDB 波形选项
if [[ ${ENABLE_FSDB} -eq 1 ]]; then
    # 波形文件路径
    FSDB_FILE="${LIB_PATH}/tb_smc.fsdb"
    RUN_CMD+=(+fsdbfile+"${FSDB_FILE}")
    
    # UCLI 脚本选项（如果wave_fsdb.do存在）
    WAVE_DO_FILE="${CELL_DIR}/wave_fsdb.do"
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


# 检查仿真日志中的测试结果并提取摘要
echo "=================================================="
echo "           测试结果汇总"
echo "=================================================="

# 提取每个测试task的结果
TEST_RESULTS=()

# 检查各个测试的结果
if grep -q "FPMUL TEST PASSED!" sim_output.log; then
    TEST_RESULTS+=("✓ FPMUL TEST PASSED")
elif grep -q "FPMUL TEST FAILED!" sim_output.log; then
    TEST_RESULTS+=("✗ FPMUL TEST FAILED")
fi

if grep -q "FPADD TEST PASSED!" sim_output.log; then
    TEST_RESULTS+=("✓ FPADD TEST PASSED")
elif grep -q "FPADD TEST FAILED!" sim_output.log; then
    TEST_RESULTS+=("✗ FPADD TEST FAILED")
fi

if grep -q "INTADD TEST PASSED!" sim_output.log; then
    TEST_RESULTS+=("✓ INTADD TEST PASSED")
elif grep -q "INTADD TEST FAILED!" sim_output.log; then
    TEST_RESULTS+=("✗ INTADD TEST FAILED")
fi

if grep -q "FPTOINT TEST PASSED!" sim_output.log; then
    TEST_RESULTS+=("✓ FPTOINT TEST PASSED")
elif grep -q "FPTOINT TEST FAILED!" sim_output.log; then
    TEST_RESULTS+=("✗ FPTOINT TEST FAILED")
fi

if grep -q "INTTOINT TEST PASSED!" sim_output.log; then
    TEST_RESULTS+=("✓ INTTOINT TEST PASSED")
elif grep -q "INTTOINT TEST FAILED!" sim_output.log; then
    TEST_RESULTS+=("✗ INTTOINT TEST FAILED")
fi

if grep -q "FPTOFP TEST PASSED!" sim_output.log; then
    TEST_RESULTS+=("✓ FPTOFP TEST PASSED")
elif grep -q "FPTOFP TEST FAILED!" sim_output.log; then
    TEST_RESULTS+=("✗ FPTOFP TEST FAILED")
fi

if grep -q "INTTOFP TEST PASSED!" sim_output.log; then
    TEST_RESULTS+=("✓ INTTOFP TEST PASSED")
elif grep -q "INTTOFP TEST FAILED!" sim_output.log; then
    TEST_RESULTS+=("✗ INTTOFP TEST FAILED")
fi

if grep -q "LOGICAL TEST PASSED!" sim_output.log; then
    TEST_RESULTS+=("✓ LOGICAL TEST PASSED")
elif grep -q "LOGICAL TEST FAILED!" sim_output.log; then
    TEST_RESULTS+=("✗ LOGICAL TEST FAILED")
fi

if grep -q "INT8toFP16 TEST PASSED!" sim_output.log; then
    TEST_RESULTS+=("✓ INT8toFP16 TEST PASSED")
elif grep -q "INT8toFP16 TEST FAILED!" sim_output.log; then
    TEST_RESULTS+=("✗ INT8toFP16 TEST FAILED")
fi

if grep -q "SHIFT_UP TEST PASSED!" sim_output.log; then
    TEST_RESULTS+=("✓ SHIFT_UP TEST PASSED")
elif grep -q "SHIFT_UP TEST FAILED!" sim_output.log; then
    TEST_RESULTS+=("✗ SHIFT_UP TEST FAILED")
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
    
    echo "总计: $TOTAL_COUNT 个测试"
    echo "通过: $PASSED_COUNT 个"
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
        echo "失败测试的最后 20 行日志:"
        echo "----------------------------------------"
        # 提取失败测试的相关日志
        for test_name in "FPMUL" "FPADD" "INTADD" "FPTOINT" "INTTOINT" "FPTOFP" "INTTOFP" "LOGICAL" "INT8toFP16" "SHIFT_UP"; do
            if grep -q "${test_name} TEST FAILED!" sim_output.log; then
                echo "[${test_name} 测试失败信息]"
                grep -A 5 "${test_name} TEST FAILED!" sim_output.log | head -n 6
                echo ""
            fi
        done
    fi
elif grep -q "Test Summary" sim_output.log; then
    # 如果存在Test Summary，提取它
    SUMMARY_LINE=$(grep -n "Test Summary" sim_output.log | tail -n 1 | cut -d: -f1)
    if [[ -n "$SUMMARY_LINE" ]]; then
        PREV_LINE=$((SUMMARY_LINE - 1))
        if [[ $PREV_LINE -gt 0 ]]; then
            tail -n +${PREV_LINE} sim_output.log | head -n 6
        else
            tail -n +${SUMMARY_LINE} sim_output.log | head -n 5
        fi
    fi
else
    echo "  ? 未找到明确的测试结果"
    echo "=================================================="
    echo "请查看 sim_output.log 了解详情"
    echo "最后 50 行日志:"
    tail -n 50 sim_output.log
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
echo " 日志文件: sim_output.log"
if [[ ${ENABLE_FSDB} -eq 1 ]]; then
    echo " 波形文件: tb_SMC_UR.fsdb"
fi
echo "=================================================="

# ============================ 固定逻辑区 结束 ============================
