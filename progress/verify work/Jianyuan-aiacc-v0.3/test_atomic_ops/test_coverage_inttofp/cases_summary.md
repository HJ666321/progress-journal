# INTtoFP 覆盖测试用例说明

验证整形转浮点型及 lane 选择逻辑。

| 用例 | 源精度 | 目的精度 | 源位置 | 目的位置 | 功能说明 |
|------|--------|----------|--------|----------|----------|
| inttofp_case0001 | 0 | 0 | 0 | 0 | Int16 -> FP16 |
| inttofp_case0002 | 0 | 0 | 0 | 1 | Int16 -> FP16 |
| inttofp_case0003 | 0 | 1 | 0 | 0 | Int16 -> FP32, Select Even Lanes (S->D) |
| inttofp_case0004 | 0 | 1 | 0 | 1 | Int16 -> FP32, Select Even Lanes (S->D) |
| inttofp_case0005 | 0 | 0 | 1 | 0 | Int16 -> FP16 |
| inttofp_case0006 | 0 | 0 | 1 | 1 | Int16 -> FP16 |
| inttofp_case0007 | 0 | 1 | 1 | 0 | Int16 -> FP32, Select Odd Lanes (S->D) |
| inttofp_case0008 | 0 | 1 | 1 | 1 | Int16 -> FP32, Select Odd Lanes (S->D) |
| inttofp_case0009 | 1 | 0 | 0 | 0 | Int32 -> FP16, Write Even Lanes (S->D) |
| inttofp_case0010 | 1 | 0 | 0 | 1 | Int32 -> FP16, Write Odd Lanes (S->D) |
| inttofp_case0011 | 1 | 1 | 0 | 0 | Int32 -> FP32 |
| inttofp_case0012 | 1 | 1 | 0 | 1 | Int32 -> FP32 |
| inttofp_case0013 | 1 | 0 | 1 | 0 | Int32 -> FP16, Write Even Lanes (S->D) |
| inttofp_case0014 | 1 | 0 | 1 | 1 | Int32 -> FP16, Write Odd Lanes (S->D) |
| inttofp_case0015 | 1 | 1 | 1 | 0 | Int32 -> FP32 |
| inttofp_case0016 | 1 | 1 | 1 | 1 | Int32 -> FP32 |