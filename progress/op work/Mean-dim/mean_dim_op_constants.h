#ifndef MEAN_DIM_OP_CONSTANTS_H
#define MEAN_DIM_OP_CONSTANTS_H

/**
 * @file mean_dim_op_constants.h
 * @brief Mean-dim 算子常量定义：RtoVR 端口编号映射
 *
 * Mean-dim 数据流:
 *   input(UR_RDATA_0) → FPMUL_S1
 *   alpha(UR_RDATA_1) → FPMUL_S0
 *   FPMUL_D            → FPADD_S0
 *   FPADD_D            → UVR_WDATA_0 (写回 UR)
 */

#include <cstdint>

namespace aiacc {
namespace op {

// RtoVR 输入编号 (DR/UR → RtoVR)
constexpr uint8_t MD_RTOVR_IN_DR_FPMUL_D  = 3;   // DR_FPMUL_D
constexpr uint8_t MD_RTOVR_IN_DR_FPADD_D  = 4;   // DR_FPADD_D
constexpr uint8_t MD_RTOVR_IN_DR_FP32ADDTREE8TO1_D = 28; // DR_FP32ADDTREE8TO1_D
constexpr uint8_t MD_RTOVR_IN_DR_SHIFTUP_D = 29; // DR_SHIFTUP_D
constexpr uint8_t MD_RTOVR_IN_UR_RDATA_0  = 30;  // UR_RDATA_0 (input)
constexpr uint8_t MD_RTOVR_IN_UR_RDATA_1  = 31;  // UR_RDATA_1 (other / scratch)
constexpr uint8_t MD_RTOVR_IN_UR_RDATA_2  = 32;  // UR_RDATA_2 (alpha)
constexpr uint8_t MD_RTOVR_IN_ZERO        = 34;  // tied-off / zero source (SHIFTDN idle)

// RtoVR 输出编号 (RtoVR → DVR/UVR)
constexpr uint8_t MD_RTOVR_OUT_DVR_FPMUL_S0  = 3;   // DVR_FPMUL_S0 (alpha)
constexpr uint8_t MD_RTOVR_OUT_DVR_FPMUL_S1  = 4;   // DVR_FPMUL_S1 (input)
constexpr uint8_t MD_RTOVR_OUT_DVR_FPADD_S0  = 5;   // DVR_FPADD_S0 (mul result)
constexpr uint8_t MD_RTOVR_OUT_DVR_FPADD_S1  = 6;   // DVR_FPADD_S1 (feedback)
constexpr uint8_t MD_RTOVR_OUT_DVR_FP32ADDTREE8TO1_S0 = 32; // AddTree S0
constexpr uint8_t MD_RTOVR_OUT_DVR_FP32ADDTREE8TO1_S1 = 33; // AddTree S1
constexpr uint8_t MD_RTOVR_OUT_DVR_SHIFTDN_S = 34;  // DVR_SHIFTDN_S
constexpr uint8_t MD_RTOVR_OUT_UVR_WDATA_0   = 35;  // UVR_WDATA_0

// LLAMA 4096 FP32: 1024 UR words → 4 tiles × 256 words (UR addr 8-bit limit).
constexpr uint32_t MD_LLAMA_TILE_WORDS = 256;
// Consecutive banks so one UR embed+INC can walk all 1024 words linearly
// (bank stride = 256 words). Avoids chaining multiple embed segments.
// Alpha stays on bank2; output on bank3.
constexpr uint8_t MD_LLAMA_TILE_BANKS[4] = {4, 5, 6, 7};

} // namespace op
} // namespace aiacc

#endif // MEAN_DIM_OP_CONSTANTS_H
