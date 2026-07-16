#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="${APP_ROOT:-/home/Hamid/Jianyuan-main/aiacc/SMI_IQ}"
RTL_ROOT="${RTL_ROOT:-/home/bupt/LLAMA_test/Jianyuan-aiacc_4.21}"
IQ_ROOT="${IQ_ROOT:-${RTL_ROOT}/aiacc/SMI_IQ}"
CXX="${CXX:-g++}"

[[ -f "${APP_ROOT}/app/app_json_parser.h" ]] || { echo "invalid APP_ROOT: ${APP_ROOT}" >&2; exit 2; }
[[ -f "${IQ_ROOT}/iq/iq_id_defs.h" ]] || { echo "invalid IQ_ROOT: ${IQ_ROOT}" >&2; exit 2; }
rg -q "para_data_i64" "${APP_ROOT}/app/app_json_parser.h" || {
    echo "APP_ROOT parser lacks para_data_i64" >&2
    exit 2
}

# Fail closed if IQ ID map drifts from the adapter used by operators.
python3 - "${IQ_ROOT}/iq/iq_id_defs.h" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path).read()
want = {
    "IQ_ID_FPMUL": 7,
    "IQ_ID_FPADD": 8,
    "IQ_ID_UR_RDATA_0": 16,
    "IQ_ID_UR_WDATA_0": 20,
    "IQ_ID_STB": 24,
    "IQ_ID_STBAXI": 25,
    "IQ_ID_LDB": 26,
    "IQ_ID_LDBAXI": 27,
    "IQ_ID_RTOVR_BASE": 28,
    "IQ_ID_DS": 92,
}
found = {}
for name, expect in want.items():
    m = re.search(rf"(?:constexpr\s+uint32_t|#define)\s+{name}\s*=?\s*(\d+)", text)
    if not m:
        sys.exit(f"missing {name} in {path}")
    got = int(m.group(1))
    found[name] = got
    if got != expect:
        sys.exit(f"{name}: got {got}, expected {expect}")
print("iq_id_defs ok:", ", ".join(f"{k}={v}" for k, v in found.items()))
PY

OVERLAY="${ROOT}/.rtl_v421_include"
mkdir -p "${OVERLAY}/op/Mean-dim" "${OVERLAY}/op/expand" "${OVERLAY}/op/index_put"
ln -sfn "${APP_ROOT}/app" "${OVERLAY}/app"
ln -sfn "${APP_ROOT}/op/common" "${OVERLAY}/op/common"
ln -sfn "${IQ_ROOT}/hal" "${OVERLAY}/hal"
ln -sfn "${IQ_ROOT}/iq" "${OVERLAY}/iq"

mapfile -t IQ_SRCS < <(printf '%s\n' "${IQ_ROOT}"/iq/modules/*.cpp)

"${CXX}" -std=c++17 -O2 -Wall -Wextra \
    -I"${APP_ROOT}/app" \
    -I"${IQ_ROOT}" \
    -I"${ROOT}" \
    -I"${OVERLAY}/op/Mean-dim" \
    -I"${OVERLAY}/op/expand" \
    -I"${OVERLAY}/op/index_put" \
    "${APP_ROOT}/app/main.cpp" \
    "${APP_ROOT}/app/tvgen_core.cpp" \
    "${APP_ROOT}/app/tvgen_dynamic.cpp" \
    "${APP_ROOT}/app/simulator_config_gen.cpp" \
    "${APP_ROOT}/app/app_json_parser.cpp" \
    "${APP_ROOT}/app/fp16_utils.cpp" \
    "${ROOT}/Mean-dim/mean_dim_op.cpp" \
    "${ROOT}/Mean-dim/mean_dim_op_bank_conflict.cpp" \
    "${ROOT}/Mean-dim/mean_dim_op_compute_inst.cpp" \
    "${ROOT}/Mean-dim/mean_dim_op_rtovr_inst.cpp" \
    "${ROOT}/Mean-dim/mean_dim_op_ur_inst.cpp" \
    "${ROOT}/expand/expand_op.cpp" \
    "${ROOT}/index_put/index_put_op.cpp" \
    "${APP_ROOT}/math_utils/newton_method/newton_method.cpp" \
    "${APP_ROOT}/math_utils/taylor_series/taylor_series.cpp" \
    "${IQ_SRCS[@]}" \
    -o "${ROOT}/tvgen_rtl_v421"

echo "built ${ROOT}/tvgen_rtl_v421"
