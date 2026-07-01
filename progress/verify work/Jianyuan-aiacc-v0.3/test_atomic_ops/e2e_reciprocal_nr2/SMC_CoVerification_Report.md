# 🚀 SMC Co-Verification Report: e2e_reciprocal_nr2
**Status:** ✅ PASSED
**Max Difference:** 0.001543

## 🎯 阶段零：终端误差定位 (E2E Semantic Check)
| Tensor | Index | Golden (预期) | Hardware (实际) | Diff |
|---|---|---|---|---|

## 🔗 阶段一：编译器意图 vs 仿真器调度对齐 (Alignment)
**结论：** 🟢 完美对齐 (未命中拍均在 ±5 拍窗口内命中，软对齐)
- [Cycle 1] RTOVR-3 在该周期未命中，但在 ±5 拍内 (c=2) 有命中，视为软对齐。
- [Cycle 1] RTOVR-4 在该周期未命中，但在 ±5 拍内 (c=2) 有命中，视为软对齐。
- [Cycle 1] RTOVR-5 在该周期未命中，但在 ±5 拍内 (c=2) 有命中，视为软对齐。
- [Cycle 2] FPMUL 在该周期未命中，但在 ±5 拍内 (c=3) 有命中，视为软对齐。
- [Cycle 6] RTOVR-6 在该周期未命中，但在 ±5 拍内 (c=7) 有命中，视为软对齐。
- [Cycle 7] FPADD 在该周期未命中，但在 ±5 拍内 (c=8) 有命中，视为软对齐。
- [Cycle 11] RTOVR-3 在该周期未命中，但在 ±5 拍内 (c=12) 有命中，视为软对齐。
- [Cycle 12] FPMUL 在该周期未命中，但在 ±5 拍内 (c=13) 有命中，视为软对齐。
- [Cycle 13] RTOVR-3 在该周期未命中，但在 ±5 拍内 (c=12) 有命中，视为软对齐。
- [Cycle 16] RTOVR-4 在该周期未命中，但在 ±5 拍内 (c=17) 有命中，视为软对齐。
- [Cycle 17] FPMUL 在该周期未命中，但在 ±5 拍内 (c=13) 有命中，视为软对齐。
- [Cycle 21] RTOVR-6 在该周期未命中，但在 ±5 拍内 (c=22) 有命中，视为软对齐。
- [Cycle 22] FPADD 在该周期未命中，但在 ±5 拍内 (c=23) 有命中，视为软对齐。
- [Cycle 26] RTOVR-3 在该周期未命中，但在 ±5 拍内 (c=27) 有命中，视为软对齐。
- [Cycle 27] FPMUL 在该周期未命中，但在 ±5 拍内 (c=28) 有命中，视为软对齐。
- [Cycle 31] RTOVR-38 在该周期未命中，但在 ±5 拍内 (c=32) 有命中，视为软对齐。

## 🧠 阶段二：计算单元底层语义追踪 (Data-Flow Semantic Trace)
未捕获异常或语义数据不足。

## 🛡️ 阶段三：隐藏状态冒险保护 (Hazard Detection)
🟢 `DR_ST` 生命周期未发现覆盖冒险。

## 🌩️ 阶段四：物理总线脉冲覆盖侦测 (Bus Overwrite Detection)

## 🧊 阶段五：RtoVR 物理端口锁存冲突 (Port Latch Hazard)
🟢 RtoVR 物理端口锁存状态一致，无覆写碰撞。