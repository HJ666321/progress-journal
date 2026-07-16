# LLAMA Three-Operator Hardware-Native Status

## Completed in this iteration

- Added `common/v421_iq_adapter.h` and IQ-ID validation in `build_tvgen_rtl_v421.sh`.
- MeanDim pre_sum path: Sub-aligned IQ shape (`embed=7` first beat + drain), v4.21 widths, `smc_id_en=31`.
- IndexPut flat: unique STB/LDB `inst_id` pairing; verify request sets `alpha_bank=3`.
- Extended regression coverage (strict reject, cache_kind, no preload) remains green at golden/instruction level.

## Verified results

- `tvgen/golden`: all expanded regression cases pass.
- RTL/VCS (`/home/bupt/LLAMA_test/Jianyuan-aiacc_4.21`, suite `fhj_llama`):
  - Expand materialized compatibility path: **PASS** (exact UR).
  - Expand native lane-replicate (`strict_hardware_path`): **PASS** (exact UR).
  - IndexPut flat STB/LDB scatter: **PASS** (exact UR).
  - MeanDim pre-sum compatibility path: **PASS** (exact UR after embed/schedule fix).
  - MeanDim native `llama_chunk_reduce` (4096, no pre_sum): **PASS** (FP32 relaxed; |dump−gold|≈4.5e-4).
  - IndexPut cache-flash AXI (`index_put_cache_axi`): **PASS** (DDR exact via `verify_ddr_v3.py`).
- Real chip: not tested.

## Hardware blockers

### MeanDim

Compat + native RTL **PASS**. Native path: 4×256 UR tiles on banks `{4,5,6,7}`, spaced FPADD
(`embed=1` body period=6 + `inc_embed`), AddTree8to1 lane-sum, ×`1/4096`, write bank3.
Still preloads tiles into UR (LDBAXI streaming not yet wired).

### Expand

Compat PASS (materialized STB/LDB). Native lane-replicate **RTL PASS**:
`strict_hardware_path=1` keeps scalar input (4B), emits IQ92 sentinel
(`reshape` + `t_dim0/t_dim1=31`, `r_out=out_words-1`) + STB `tid=01` + LDB.
DS engine replicates lane0 across each 16B beat for `out_words` beats
(`[1]→[1,32]` ⇒ 1→8 FP32 words). Exact UR compare.

### IndexPut

Flat compat **RTL PASS**. Cache-flash hardware path **RTL PASS**:
`LDBAXI→LDB→UR→STB→STBAXI` via `common/axi_lsu_packer.h` (LSB header, paired
`inst_id`, contiguous runs with `brst≥1`). Store IQ waits on LDB with
`cond=26` + `dly=7` on the first STB/STBAXI only (subsequent `cond=0`). Case
`fhj_llama/index_put_cache_axi` uses HBM init @values`0x1000` / cache`0x2000`
and `verify_ddr_v3.py` (exact 16-word compare).

## Validation level

- `golden_pass`: true
- `instruction_pass`: true for compatibility simulation
- `rtl_pass`: true for three compat + Expand/MeanDim native + IndexPut cache AXI
- `chip_pass`: false
