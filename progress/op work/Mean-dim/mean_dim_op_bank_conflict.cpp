#include "mean_dim_op_bank_conflict.h"
#include "mean_dim_op.h"
#include <iostream>

namespace aiacc {
namespace op {

uint8_t md_compute_slot_allocation(const MeanDimOpParams& params,
                                   std::vector<MeanDimOpInstructions::SlotAccess>& slot_accesses,
                                   uint8_t port_slots[3]) {
    slot_accesses.clear();
    for (int i = 0; i < 3; ++i) port_slots[i] = 0;

    // 统计 bank 使用: tensor_id 0=input(r0), 1=alpha(r1), 2=output(w0)
    std::vector<std::vector<uint8_t>> bank_tensors(8);
    bank_tensors[params.para_input_bank].push_back(0);
    bank_tensors[params.para_alpha_bank].push_back(1);
    bank_tensors[params.para_output_bank].push_back(2);

    // 构建冲突图
    bool conflicts[3][3] = {};
    for (auto& tensors : bank_tensors) {
        for (size_t i = 0; i < tensors.size(); ++i) {
            for (size_t j = i + 1; j < tensors.size(); ++j) {
                uint8_t a = tensors[i], b = tensors[j];
                conflicts[a][b] = true;
                conflicts[b][a] = true;
            }
        }
    }

    bool has_conflict = false;
    for (int i = 0; i < 3 && !has_conflict; ++i)
        for (int j = i + 1; j < 3 && !has_conflict; ++j)
            if (conflicts[i][j]) has_conflict = true;

    if (!has_conflict) {
        MeanDimOpInstructions::SlotAccess slot0;
        slot0.input_slot = 0;
        slot0.alpha_slot = 0;
        slot0.output_slot = 0;
        slot0.has_compute = true;
        slot_accesses.push_back(slot0);
        return 1;
    }

    // 贪心着色
    for (int p = 0; p < 3; ++p) {
        std::vector<bool> used(3, false);
        for (int q = 0; q < p; ++q) {
            if (conflicts[p][q]) used[port_slots[q]] = true;
        }
        uint8_t s = 0;
        while (s < 3 && used[s]) s++;
        port_slots[p] = s;
    }

    uint8_t max_slot = 0;
    for (int p = 0; p < 3; ++p)
        if (port_slots[p] > max_slot) max_slot = port_slots[p];
    uint8_t num_slots = max_slot + 1;

    slot_accesses.resize(num_slots);
    for (auto& slot : slot_accesses) {
        slot.input_slot = 0xFF;
        slot.alpha_slot = 0xFF;
        slot.output_slot = 0xFF;
        slot.has_compute = false;
    }

    slot_accesses[port_slots[0]].input_slot = port_slots[0];
    slot_accesses[port_slots[1]].alpha_slot = port_slots[1];
    if (port_slots[2] < num_slots)
        slot_accesses[port_slots[2]].output_slot = port_slots[2];

    uint8_t max_read_slot = 0;
    for (int i = 0; i < 2; ++i)
        if (port_slots[i] > max_read_slot) max_read_slot = port_slots[i];
    slot_accesses[max_read_slot].has_compute = true;

    std::cout << "[Info] MeanDim bank conflict: num_slots=" << (int)num_slots
              << ", port_slots=[r0=" << (int)port_slots[0]
              << ", r1=" << (int)port_slots[1]
              << ", w0=" << (int)port_slots[2] << "]\n";

    return num_slots;
}

} // namespace op
} // namespace aiacc
