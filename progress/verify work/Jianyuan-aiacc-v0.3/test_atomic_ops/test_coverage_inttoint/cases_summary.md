# INTtoINT 覆盖测试用例说明

验证整型转换（位宽调整、有符号/无符号处理、Lane选择）。

| 用例 | 源精度 | 目的精度 | 源符号 | 目的符号 | 功能说明 |
|------|--------|----------|--------|----------|----------|
| inttoint_case0001 | 0 | 0 | 0 | 0 | Int16(U) -> Int16(U) |
| inttoint_case0002 | 0 | 0 | 0 | 1 | Int16(U) -> Int16(S) |
| inttoint_case0003 | 0 | 0 | 1 | 0 | Int16(S) -> Int16(U) |
| inttoint_case0004 | 0 | 0 | 1 | 1 | Int16(S) -> Int16(S) |
| inttoint_case0005 | 0 | 1 | 0 | 0 | Int16(U) -> Int32(U), Sel Even |
| inttoint_case0006 | 0 | 1 | 0 | 0 | Int16(U) -> Int32(U), Sel Odd |
| inttoint_case0007 | 0 | 1 | 0 | 1 | Int16(U) -> Int32(S), Sel Even |
| inttoint_case0008 | 0 | 1 | 0 | 1 | Int16(U) -> Int32(S), Sel Odd |
| inttoint_case0009 | 0 | 1 | 1 | 0 | Int16(S) -> Int32(U), Sel Even |
| inttoint_case0010 | 0 | 1 | 1 | 0 | Int16(S) -> Int32(U), Sel Odd |
| inttoint_case0011 | 0 | 1 | 1 | 1 | Int16(S) -> Int32(S), Sel Even |
| inttoint_case0012 | 0 | 1 | 1 | 1 | Int16(S) -> Int32(S), Sel Odd |
| inttoint_case0013 | 1 | 0 | 0 | 0 | Int32(U) -> Int16(U), Write Even |
| inttoint_case0014 | 1 | 0 | 0 | 0 | Int32(U) -> Int16(U), Write Odd |
| inttoint_case0015 | 1 | 0 | 0 | 1 | Int32(U) -> Int16(S), Write Even |
| inttoint_case0016 | 1 | 0 | 0 | 1 | Int32(U) -> Int16(S), Write Odd |
| inttoint_case0017 | 1 | 0 | 1 | 0 | Int32(S) -> Int16(U), Write Even |
| inttoint_case0018 | 1 | 0 | 1 | 0 | Int32(S) -> Int16(U), Write Odd |
| inttoint_case0019 | 1 | 0 | 1 | 1 | Int32(S) -> Int16(S), Write Even |
| inttoint_case0020 | 1 | 0 | 1 | 1 | Int32(S) -> Int16(S), Write Odd |
| inttoint_case0021 | 1 | 1 | 0 | 0 | Int32(U) -> Int32(U) |
| inttoint_case0022 | 1 | 1 | 0 | 1 | Int32(U) -> Int32(S) |
| inttoint_case0023 | 1 | 1 | 1 | 0 | Int32(S) -> Int32(U) |
| inttoint_case0024 | 1 | 1 | 1 | 1 | Int32(S) -> Int32(S) |