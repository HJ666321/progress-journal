# FP32ADDTREE8TO1 覆盖测试用例

由 run_fp32addtree8to1_coverage.py 生成。

## 字段含义
- **目的寄存器编码 (DST_REG)**: 0~3，结果写入 DR-FP32ADDTREE8TO1-D[x]，x 为该编码。

## 用例列表
| 用例目录 | 目的寄存器编码 | 功能说明 |
| --- | --- | --- |
| fp32addtree8to1_case0001 | 0 | D[x] = sum({S1[y],S0[y]} for y=0..7)，结果写 D[0]（目的寄存器编码=0） |
| fp32addtree8to1_case0002 | 1 | D[x] = sum({S1[y],S0[y]} for y=0..7)，结果写 D[1]（目的寄存器编码=1） |
| fp32addtree8to1_case0003 | 2 | D[x] = sum({S1[y],S0[y]} for y=0..7)，结果写 D[2]（目的寄存器编码=2） |
| fp32addtree8to1_case0004 | 3 | D[x] = sum({S1[y],S0[y]} for y=0..7)，结果写 D[3]（目的寄存器编码=3） |
