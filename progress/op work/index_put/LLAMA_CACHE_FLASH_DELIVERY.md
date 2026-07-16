# IndexPut LLAMA Cache Flash Delivery Notes

## Current Cache Flash Semantics

`cache_flash_mode` implements the `reshape_and_cache_flash` address model:

```text
block_idx = slot / block_size
block_offset = slot % block_size
dst_word = (((block_idx * block_size + block_offset) * num_heads + head)
            * head_words + head_word)
```

Invalid slots (`slot < 0`) are skipped. The input `values_tensor` is interpreted
as `[token, head, head_size]`.

## Key / Value Coverage

`cache_kind` selects the cache stream:

- `0`: key cache
- `1`: value cache
- `2`: key and value cache with per-kind GR/output offsets

The LLAMA delivery harness generates all three modes.

## Sentinel Integrity

Model-level cache validation must initialize cache with a non-zero sentinel and
verify that only words addressed by valid `slot_mapping` entries change. This is
the main guard against accidentally overwriting historical KV cache.

## Strict RTL LSU v2 Mode

By default, cache flash data generation preloads `alpha_bin` with the final cache
image because the Python SMC simulator may not execute `ldb_v2/stb_v2`.

When `strict_rtl_lsu_v2=1`, this compatibility preload is disabled. Passing in
that mode means the result must come from real v2 load/store execution in the
RTL/VCS path.

## Boundary Tests

- single token decode
- multi-token prefill, including 1147 tokens
- `slot=-1` skip
- duplicate slots
- maximum slot
- continuous decode where `cache_len` grows between steps
