# Expand LLAMA Delivery Notes

## Supported Semantics

The operator normalizes 1D/2D/4D shapes into an internal NCHW layout:

- 1D `[W]` becomes `[1,1,1,W]`.
- 2D `[H,W]` becomes `[1,1,H,W]`.
- 4D is used as-is.

Broadcast follows PyTorch `expand` rules for dimensions whose input size is 1.

## Hardware Path Classification

- Word-level broadcast: native IQ mapping with `UR_R -> RtoVR -> UR_W`.
- Scalar/lane broadcast such as `[1] -> [1,32]`: model-level baseline currently
  materializes the expanded input in TVGen and then moves it through hardware.

`strict_hardware_path=1` rejects scalar/lane broadcast until a native lane
replicate/permute route is implemented and validated in RTL.

## LLAMA Trace Coverage Targets

The script `scripts/llama_three_ops_verify.py` can generate synthetic versions
of the scalar and 2D leading-dim broadcast cases. For captured traces, pass the
node-specific `return.bin` path and compare the generated golden/output against:

- round-1 attention nodes: `0294`, `0295`, `0296`
- round-2 attention nodes: `2609`, `2610`, `2611`

The comparison must check dtype, logical shape and every output element.
