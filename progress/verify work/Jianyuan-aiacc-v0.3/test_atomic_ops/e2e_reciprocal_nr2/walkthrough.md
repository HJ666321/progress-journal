# 📝 Algorithm Walkthrough: e2e_reciprocal_nr2

## 1. 数学逻辑 (Mathematical Formula)
y = 1/x via Newton-Raphson: y_{n+1} = y_n(2 - x*y_n)

## 2. MIR 指令拆分流程 (MIR Step-by-Step)
Step 1: x*y0 -> t1
Step 2: 2 - t1 -> t2
Step 3: y0*t2 -> y1 (Iter 1)
Step 4: x*y1 -> t3
Step 5: 2 - t3 -> t4
Step 6: y1*t4 -> y2 (Iter 2)

## 3. 硬件映射策略 (Hardware Mapping)
- **单元选择**: FPMUL/FPADD
- **循环机制**: EMBED
- **精度目标**: FP32 (Tolerance < 1e-6)
