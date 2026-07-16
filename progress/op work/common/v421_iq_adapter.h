#ifndef FHJ_OP_V421_IQ_ADAPTER_H
#define FHJ_OP_V421_IQ_ADAPTER_H

/**
 * @file v421_iq_adapter.h
 * @brief Shared v4.21 IQ IDs, CRU widths, and Sub-compatible steady-state schedule.
 *
 * Filename/name matching remains authoritative for data_list generation; these
 * IDs document the RTL map and keep operator emitters consistent.
 */

#include <cstdint>
#include <utility>

namespace aiacc {
namespace op {
namespace v421 {

constexpr uint32_t kIqIdFp32AddTree5to1 = 5;
constexpr uint32_t kIqIdFp32AddTree8to1 = 6;
constexpr uint32_t kIqIdFpmul = 7;
constexpr uint32_t kIqIdFpadd = 8;
constexpr uint32_t kIqIdLogic = 13;
constexpr uint32_t kIqIdShiftUp = 14;
constexpr uint32_t kIqIdShiftDn = 15;
constexpr uint32_t kIqIdUrR0 = 16;
constexpr uint32_t kIqIdUrR1 = 17;
constexpr uint32_t kIqIdUrR2 = 18;
constexpr uint32_t kIqIdUrR3 = 19;
constexpr uint32_t kIqIdUrW0 = 20;
constexpr uint32_t kIqIdUrW1 = 21;
constexpr uint32_t kIqIdUrW2 = 22;
constexpr uint32_t kIqIdUrW3 = 23;
constexpr uint32_t kIqIdStb = 24;
constexpr uint32_t kIqIdStbAxi = 25;
constexpr uint32_t kIqIdLdb = 26;
constexpr uint32_t kIqIdLdbAxi = 27;
constexpr uint32_t kIqIdRtovrBase = 28;
constexpr uint32_t kIqIdRtovrEnd = 67; // only 40 CRU ports are wired
constexpr uint32_t kIqIdDs = 92;

constexpr uint16_t kBitsHdr = 41;
constexpr uint16_t kBitsUrR = 17;   // 12 + smc_id_en(5)
constexpr uint16_t kBitsUrW = 33;   // 28 + smc_id_en(5)
constexpr uint16_t kBitsFpMul = 8;  // 3 + smc_id_en(5)
constexpr uint16_t kBitsFpAdd = 10; // 5 + smc_id_en(5)
constexpr uint16_t kBitsRtovr = 7;
constexpr uint16_t kBitsStb = 100;
constexpr uint16_t kBitsLdb = 106;
constexpr uint16_t kBitsStbAxi = 152;
constexpr uint16_t kBitsLdbAxi = 154;
constexpr uint16_t kBitsDs = 80;

constexpr uint8_t kDefaultSmcIdEn = 0x07;
constexpr uint8_t kMaxDlyField = 7;

inline uint32_t rtovr_iq_id(uint8_t port) {
    return kIqIdRtovrBase + static_cast<uint32_t>(port);
}

struct ScaleAddSteadyStateSchedule {
    // Match working Sub v4.21 vectors: extra IQ beats after the last useful
    // input so FP pipes drain into UR-W.
    static constexpr uint32_t kPipelineDrain = 13;
    // smi_iq_iic: embed==3'b111 bypasses EXE_EMBED0; embed==0+loops>0 enters it.
    static constexpr uint8_t kNoEmbed = 7;

    ScaleAddSteadyStateSchedule() {
        // UR read is visible one cycle after the read CRU; RtoVR is registered;
        // FP pipes produce D four cycles after launch (SubSteadyStateSchedule).
        ur_r1 = 0; // other / pre_sum
        ur_r2 = 0; // alpha
        rtovr_fpmul_s0 = 1;
        rtovr_fpmul_s1 = 1;
        fpmul = 2;

        ur_r0 = 5;
        rtovr_fpadd_s0 = 6;
        rtovr_fpadd_s1 = 6;
        fpadd = 7;

        rtovr_uwr0 = 11;
        ur_w0 = 12;
    }

    uint32_t ur_r0{0};
    uint32_t ur_r1{0};
    uint32_t ur_r2{0};
    uint32_t rtovr_fpmul_s0{0};
    uint32_t rtovr_fpmul_s1{0};
    uint32_t fpmul{0};
    uint32_t rtovr_fpadd_s0{0};
    uint32_t rtovr_fpadd_s1{0};
    uint32_t fpadd{0};
    uint32_t rtovr_uwr0{0};
    uint32_t ur_w0{0};
};

template <typename EmitDummyFn>
inline uint8_t emit_dummy_for_long_delay(uint32_t& total_dly, EmitDummyFn&& emit_dummy) {
    while (total_dly > kMaxDlyField) {
        emit_dummy();
        total_dly -= 8;
    }
    return static_cast<uint8_t>(total_dly);
}

template <typename EmitLongDummyFn, typename EmitPreciseDummyFn>
inline void consume_startup_delay(uint32_t& total_dly,
                                  EmitLongDummyFn&& emit_long_dummy,
                                  EmitPreciseDummyFn&& emit_precise_dummy) {
    emit_dummy_for_long_delay(total_dly, std::forward<EmitLongDummyFn>(emit_long_dummy));
    if (total_dly > 0) {
        emit_precise_dummy(static_cast<uint8_t>(total_dly - 1));
        total_dly = 0;
    }
}

} // namespace v421
} // namespace op
} // namespace aiacc

#endif // FHJ_OP_V421_IQ_ADAPTER_H
