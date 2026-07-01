# Phase 4: C_bank_constrained

## Nodes
- 0: ur_read_b_0 (UR-R1), stage=S1, bank=None
- 1: ur_read_alpha_0 (UR-R2), stage=S1, bank=None
- 2: fpmul_0 (FPMUL), stage=S1, bank=None
- 3: ur_read_a_0 (UR-R0), stage=S1, bank=None
- 4: fpadd_0 (FPADD), stage=S1, bank=None
- 5: ur_write_out_0 (UR-W0), stage=S1, bank=None
- 6: ur_read_b_1 (UR-R1), stage=S1, bank=None
- 7: ur_read_alpha_1 (UR-R2), stage=S1, bank=None
- 8: fpmul_1 (FPMUL), stage=S1, bank=None
- 9: ur_read_a_1 (UR-R0), stage=S1, bank=None
- 10: fpadd_1 (FPADD), stage=S1, bank=None
- 11: ur_write_out_1 (UR-W0), stage=S1, bank=None
- 12: ur_read_b_2 (UR-R1), stage=S1, bank=None
- 13: ur_read_alpha_2 (UR-R2), stage=S1, bank=None
- 14: fpmul_2 (FPMUL), stage=S1, bank=None
- 15: ur_read_a_2 (UR-R0), stage=S1, bank=None
- 16: fpadd_2 (FPADD), stage=S1, bank=None
- 17: ur_write_out_2 (UR-W0), stage=S1, bank=None
- 18: ur_read_b_3 (UR-R1), stage=S1, bank=None
- 19: ur_read_alpha_3 (UR-R2), stage=S1, bank=None
- 20: fpmul_3 (FPMUL), stage=S1, bank=None
- 21: ur_read_a_3 (UR-R0), stage=S1, bank=None
- 22: fpadd_3 (FPADD), stage=S1, bank=None
- 23: ur_write_out_3 (UR-W0), stage=S1, bank=None

## Edges
- 0 -> 2 (gap=2)
- 1 -> 2 (gap=2)
- 3 -> 4 (gap=2)
- 2 -> 4 (gap=5)
- 4 -> 5 (gap=5)
- 6 -> 8 (gap=2)
- 7 -> 8 (gap=2)
- 9 -> 10 (gap=2)
- 8 -> 10 (gap=5)
- 10 -> 11 (gap=5)
- 12 -> 14 (gap=2)
- 13 -> 14 (gap=2)
- 15 -> 16 (gap=2)
- 14 -> 16 (gap=5)
- 16 -> 17 (gap=5)
- 18 -> 20 (gap=2)
- 19 -> 20 (gap=2)
- 21 -> 22 (gap=2)
- 20 -> 22 (gap=5)
- 22 -> 23 (gap=5)
