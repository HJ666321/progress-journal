# FPtoINT 覆盖测试用例说明

验证浮点转整型及 lane 选择逻辑。

| 用例 | 源精度 | 目的精度 | 源位置 | 目的位置 | 功能说明 |
|------|--------|----------|--------|----------|----------|
| fptoint_case0001 | 0 | 0 | 0 | 0 | FP16 -> Int16 |
| fptoint_case0002 | 0 | 0 | 0 | 1 | FP16 -> Int16 |
| fptoint_case0003 | 0 | 1 | 0 | 0 | FP16 -> Int32, Select Even Lanes (S->D) |
| fptoint_case0004 | 0 | 1 | 0 | 1 | FP16 -> Int32, Select Even Lanes (S->D) |
| fptoint_case0005 | 0 | 0 | 1 | 0 | FP16 -> Int16 |
| fptoint_case0006 | 0 | 0 | 1 | 1 | FP16 -> Int16 |
| fptoint_case0007 | 0 | 1 | 1 | 0 | FP16 -> Int32, Select Odd Lanes (S->D) |
| fptoint_case0008 | 0 | 1 | 1 | 1 | FP16 -> Int32, Select Odd Lanes (S->D) |
| fptoint_case0009 | 1 | 0 | 0 | 0 | FP32 -> Int16, Write Even Lanes (S->D) |
| fptoint_case0010 | 1 | 0 | 0 | 1 | FP32 -> Int16, Write Odd Lanes (S->D) |
| fptoint_case0011 | 1 | 1 | 0 | 0 | FP32 -> Int32 |
| fptoint_case0012 | 1 | 1 | 0 | 1 | FP32 -> Int32 |
| fptoint_case0013 | 1 | 0 | 1 | 0 | FP32 -> Int16, Write Even Lanes (S->D) |
| fptoint_case0014 | 1 | 0 | 1 | 1 | FP32 -> Int16, Write Odd Lanes (S->D) |
| fptoint_case0015 | 1 | 1 | 1 | 0 | FP32 -> Int32 |
| fptoint_case0016 | 1 | 1 | 1 | 1 | FP32 -> Int32 |