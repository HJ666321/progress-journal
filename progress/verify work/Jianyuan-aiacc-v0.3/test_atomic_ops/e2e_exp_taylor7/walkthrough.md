# 📝 Algorithm Walkthrough: e2e_exp_taylor7

## 1. 数学逻辑 (Mathematical Formula)
y = exp(x) via 7th-order Taylor (Horner Form)

## 2. MIR 指令拆分流程 (MIR Step-by-Step)
1 + x(1 + x(1/2! + x(1/3! + ...)))

## 3. 硬件映射策略 (Hardware Mapping)
- **单元选择**: FPMUL/FPADD
- **循环机制**: EMBED
- **精度目标**: FP32 (Tolerance < 1e-6)
