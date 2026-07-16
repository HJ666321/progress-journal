#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SMI_IQ_ROOT="${SMI_IQ_ROOT:-/home/Hamid/Jianyuan-main/aiacc/SMI_IQ}"
CXX="${CXX:-g++}"

if [[ ! -f "${SMI_IQ_ROOT}/app/app_json_parser.h" ]]; then
    echo "error: invalid SMI_IQ_ROOT: ${SMI_IQ_ROOT}" >&2
    exit 2
fi
if ! rg -q "para_data_i64" "${SMI_IQ_ROOT}/app/app_json_parser.h"; then
    echo "error: app_json_parser.h lacks para_data_i64; refusing ABI-incompatible build" >&2
    exit 2
fi

mapfile -t IQ_SRCS < <(printf '%s\n' "${SMI_IQ_ROOT}"/iq/modules/*.cpp)

"${CXX}" -std=c++17 -O2 -Wall -Wextra \
    -I"${SMI_IQ_ROOT}/app" \
    -I"${SMI_IQ_ROOT}/op/Mean-dim" \
    -I"${SMI_IQ_ROOT}/op/expand" \
    -I"${SMI_IQ_ROOT}/op/index_put" \
    "${SMI_IQ_ROOT}/app/main.cpp" \
    "${SMI_IQ_ROOT}/app/tvgen_core.cpp" \
    "${SMI_IQ_ROOT}/app/tvgen_dynamic.cpp" \
    "${SMI_IQ_ROOT}/app/simulator_config_gen.cpp" \
    "${SMI_IQ_ROOT}/app/app_json_parser.cpp" \
    "${SMI_IQ_ROOT}/app/fp16_utils.cpp" \
    "${ROOT}/Mean-dim/mean_dim_op.cpp" \
    "${ROOT}/Mean-dim/mean_dim_op_bank_conflict.cpp" \
    "${ROOT}/Mean-dim/mean_dim_op_compute_inst.cpp" \
    "${ROOT}/Mean-dim/mean_dim_op_rtovr_inst.cpp" \
    "${ROOT}/Mean-dim/mean_dim_op_ur_inst.cpp" \
    "${ROOT}/expand/expand_op.cpp" \
    "${ROOT}/index_put/index_put_op.cpp" \
    "${SMI_IQ_ROOT}/math_utils/newton_method/newton_method.cpp" \
    "${SMI_IQ_ROOT}/math_utils/taylor_series/taylor_series.cpp" \
    "${IQ_SRCS[@]}" \
    -o "${ROOT}/tvgen_llama"

echo "built ${ROOT}/tvgen_llama"
