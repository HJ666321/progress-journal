# MeanDim LLAMA Chunk Reduce Assessment

## Current Delivery Baseline

LLAMA RMSNorm calls `mean(..., dim=-1, keepdim=True)` on a hidden dimension of
4096. In the current operator, this path is detected by:

- `dim = -1`
- `keepdim = 1`
- `reduce_elems = W = 4096`

The deliverable baseline uses software `pre_sum` compatibility:

1. TVGen computes one scalar sum per token.
2. The hardware path multiplies the pre-sum by `1 / reduce_elems`.
3. Physical output is one 16B word per token: lane0 is the mean, lanes1-3 are zero.

This is model-level functional coverage, not native hardware scalar reduction.

## Why Strict Hardware Mode Rejects This Path

For FP32, 4096 elements are 1024 UR words. FPADD feedback can reduce those 1024
words into one SIMD word:

```text
[sum_lane0, sum_lane1, sum_lane2, sum_lane3]
```

But PyTorch `mean(dim=-1, keepdim=True)` needs:

```text
sum_lane0 + sum_lane1 + sum_lane2 + sum_lane3
```

That is a lane-internal scalar reduction. The current FPADD-only MeanDim path
does not provide a proven lane-reduce stage, so `strict_hardware_path` or
`llama_chunk_reduce` intentionally fails with a clear error instead of silently
reporting pre_sum as hardware-native.

## Proposed Native Path

1. Stream each token in 256-word UR windows.
2. Use FPADD feedback to reduce each window into a 4-lane partial sum.
3. Merge the four window partials into a final 4-lane sum per token.
4. Convert the 4 lanes into the input format required by `FP32AddTree8to1` or
   another verified lane-reduce unit.
5. Multiply the scalar sum by `1 / 4096`.
6. Write lane0 to output and zero padded lanes.

## Validation Requirements

- `[1,4096]` smoke.
- `[1147,4096]` round-1 prefill case.
- Compare token0, token_middle, token_last first, then full scalar lanes.
- Strict mode must not use TVGen pre-sum.
