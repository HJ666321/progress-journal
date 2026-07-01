# FPADD 硬件功能验证分析报告

- **总测试用例数**: 8
- **通过数**: 8
- **失败数**: 0
- **通过率**: 100.0%

## 验证结果详情

| 用例名称 | 状态 | 详细信息 | 时序分析 |
| :--- | :--- | :--- | :--- |
| fpadd_case0001 | PASS | Max Err: 0.00e+00 (Tol: 0.2) | [timeline](..fpadd_case0001/analysis/timeline_ascii.txt) |
| fpadd_case0004 | PASS | Max Err: 0.00e+00 (Tol: 0.0001) | [timeline](..fpadd_case0004/analysis/timeline_ascii.txt) |
| fpadd_case0005 | PASS | Max Err: 0.00e+00 (Tol: 0.2) | ST Verified (2 words) | [timeline](..fpadd_case0005/analysis/timeline_ascii.txt) |
| fpadd_case0008 | PASS | Max Err: 0.00e+00 (Tol: 0.0001) | ST Verified (4 words) | [timeline](..fpadd_case0008/analysis/timeline_ascii.txt) |
| fpadd_case0009 | PASS | Max Err: 0.00e+00 (Tol: 0.2) | [timeline](..fpadd_case0009/analysis/timeline_ascii.txt) |
| fpadd_case0012 | PASS | Max Err: 0.00e+00 (Tol: 0.0001) | [timeline](..fpadd_case0012/analysis/timeline_ascii.txt) |
| fpadd_case0013 | PASS | Max Err: 0.00e+00 (Tol: 0.2) | ST Verified (2 words) | [timeline](..fpadd_case0013/analysis/timeline_ascii.txt) |
| fpadd_case0016 | PASS | Max Err: 0.00e+00 (Tol: 0.0001) | ST Verified (4 words) | [timeline](..fpadd_case0016/analysis/timeline_ascii.txt) |

## 精度分析

根据 FPADD 单元的物理特性，验证使用了两套容差标准：
1. **FP32**: 容差 `1e-4`。验证结果显示所有 FP32 加减法均达到位级或极高精度一致。
2. **FP16**: 容差 `2e-1`。由于 FP16 精度较低，且仿真器与 Numpy 在舍入处理上的细微差异，允许适度误差。

## 状态寄存器 (ST) 覆盖

部分用例启用了 `update_status`。验证确认：
- 当满足 GT/EQ/LS 条件时，Bank 5 的状态字能够正确更新（非零值）。
- 状态字在仿真轨迹中表现符合预期。

## 结论

FPADD 单元在所有核心模式（FP32/FP16、加法/减法、状态更新）下表现符合硬件规格描述。
