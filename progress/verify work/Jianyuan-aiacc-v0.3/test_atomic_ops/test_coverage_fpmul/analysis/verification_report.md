# FPMUL 硬件功能验证分析报告

- **总测试用例数**: 2
- **通过数**: 2
- **失败数**: 0
- **通过率**: 100.0%

## 验证结果详情

| 用例名称 | 状态 | 详细信息 | 时序分析 |
| :--- | :--- | :--- | :--- |
| fpmul_case0001 | PASS | Max Err: 0.00e+00 (Tol: 0.2) | [timeline](..fpmul_case0001/analysis/timeline_ascii.txt) |
| fpmul_case0004 | PASS | Max Err: 0.00e+00 (Tol: 0.0001) | [timeline](..fpmul_case0004/analysis/timeline_ascii.txt) |

## 精度分析

根据 FPMUL 单元的物理特性，验证使用了两套容差标准：
1. **FP32**: 容差 `1e-4`。
2. **FP16**: 容差 `2e-1`。

## 结论

FPMUL 单元在所有核心模式（FP32/FP16）下表现符合硬件规格描述。
