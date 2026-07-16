#!/usr/bin/env python3
"""Run LLAMA-oriented validation for fhj_op.

This script exercises the three local operators with the real round-1/round-2
trace shapes where the current kernel interface can represent them:
  - MeanDim: full hidden-size dim=-1 reduce for one token / decode token.
  - Expand: scalar-to-[1,32] lane broadcast from the captured trace.
  - IndexPut: cache_flash mode with captured slot_mapping and one KV token.
It also keeps a small flat IndexPut regression to cover the non-cache path.
"""

from __future__ import annotations

import argparse
import json
import math
import shutil
import struct
import subprocess
from pathlib import Path
from typing import Any, Dict, Iterable, List, Tuple


ROOT = Path("/home/bupt/fhj_op")
DEFAULT_TVGEN = ROOT / "tvgen_llama"
DEFAULT_OUT = ROOT / "llama_verify_out"

TRACE = {
    "mean_r1": Path("/home/bupt/0000-round-1/0047-forward/0233-2/0305-post_attention_layernorm/0310-aten::mean.dim"),
    "mean_r2": Path("/home/bupt/0000-round-2/0037-forward/2548-27/2548-input_layernorm/2553-aten::mean.dim"),
    "expand_r1": Path("/home/bupt/0000-round-1/0047-forward/0233-2/0244-self_attn/0285-attn/0296-aten::expand"),
    "expand_r2": Path("/home/bupt/0000-round-2/0037-forward/2548-27/2559-self_attn/2600-attn/2610-aten::expand"),
    "cache_r1": Path("/home/bupt/0000-round-1/0047-forward/0233-2/0244-self_attn/0285-attn/0291-_C_cache_ops::reshape_and_cache_flash"),
    "cache_r2": Path("/home/bupt/0000-round-2/0037-forward/2548-27/2559-self_attn/2600-attn/2606-_C_cache_ops::reshape_and_cache_flash"),
}


def tensor(dtype: str, shape: List[int], data: Iterable[float | int]) -> Dict[str, Any]:
    return {"shape": shape, "dtype": dtype, "data": list(data)}


def i32(values: Iterable[int] | int) -> Dict[str, Any]:
    vals = [values] if isinstance(values, int) else list(values)
    return tensor("int32", [len(vals)], vals)


def int64_param(values: Iterable[int] | int) -> Dict[str, Any]:
    vals = [values] if isinstance(values, int) else list(values)
    return tensor("int64", [len(vals)], vals)


def dims(n: int, c: int, h: int, w: int) -> Dict[str, int]:
    return {"N": n, "C": c, "H": h, "W": w}


def run(cmd: List[str]) -> str:
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if proc.returncode != 0:
        raise RuntimeError("command failed rc={}:\n{}\n{}".format(proc.returncode, " ".join(cmd), proc.stdout))
    return proc.stdout


def write_json(path: Path, obj: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, indent=2, ensure_ascii=True), encoding="utf-8")


def read_fp32(path: Path, count: int | None = None, offset: int = 0) -> List[float]:
    data = path.read_bytes()
    start = offset * 4
    n = (len(data) - start) // 4 if count is None else count
    return list(struct.unpack("<{}f".format(n), data[start : start + n * 4]))


def read_fp16(path: Path, count: int | None = None, offset: int = 0) -> List[float]:
    data = path.read_bytes()
    start = offset * 2
    n = (len(data) - start) // 2 if count is None else count
    return [float(v) for v in struct.unpack("<{}e".format(n), data[start : start + n * 2])]


def read_i64(path: Path, count: int | None = None, offset: int = 0) -> List[int]:
    data = path.read_bytes()
    start = offset * 8
    n = (len(data) - start) // 8 if count is None else count
    return [int(v) for v in struct.unpack("<{}q".format(n), data[start : start + n * 8])]


def unpack_fp32(data: bytes) -> List[float]:
    if not data:
        return []
    n = len(data) // 4
    return list(struct.unpack("<{}f".format(n), data[: n * 4]))


def unpack_fp16(data: bytes) -> List[float]:
    if not data:
        return []
    n = len(data) // 2
    return [float(v) for v in struct.unpack("<{}e".format(n), data[: n * 2])]


def allclose(a: List[float], b: List[float], rtol: float = 1e-3, atol: float = 1e-4) -> Tuple[bool, float]:
    if len(a) != len(b):
        return False, float("inf")
    max_err = 0.0
    for x, y in zip(a, b):
        err = abs(x - y)
        max_err = max(max_err, err)
        if not math.isfinite(x) or err > atol + rtol * abs(y):
            return False, max_err
    return True, max_err


def run_tvgen(tvgen: Path, out_dir: Path, name: str, req: Dict[str, Any]) -> Dict[str, Any]:
    case_dir = out_dir / "cases" / name
    tvgen_dir = case_dir / "tvgen"
    req_path = case_dir / "request.json"
    if case_dir.exists():
        shutil.rmtree(case_dir)
    case_dir.mkdir(parents=True, exist_ok=True)
    write_json(req_path, req)
    stdout = run([str(tvgen), "--json", str(req_path), "--output", str(tvgen_dir)])
    return {
        "name": name,
        "request": str(req_path),
        "tvgen_dir": str(tvgen_dir),
        "stdout": stdout,
        "golden_bytes": (tvgen_dir / "golden.bin").stat().st_size,
        "iq_files": sorted(p.name for p in (tvgen_dir / "hex_instructions").glob("*.hex")),
    }


def run_tvgen_expect_fail(
    tvgen: Path,
    out_dir: Path,
    name: str,
    req: Dict[str, Any],
    expected_message: str,
) -> Dict[str, Any]:
    case_dir = out_dir / "cases" / name
    req_path = case_dir / "request.json"
    if case_dir.exists():
        shutil.rmtree(case_dir)
    case_dir.mkdir(parents=True, exist_ok=True)
    write_json(req_path, req)
    proc = subprocess.run(
        [str(tvgen), "--json", str(req_path), "--output", str(case_dir / "tvgen")],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    ok = proc.returncode != 0 and expected_message in proc.stdout
    return {
        "name": name,
        "request": str(req_path),
        "stdout": proc.stdout,
        "numeric": {
            "ok": ok,
            "elements": 0,
            "max_abs_err": 0.0,
            "expected_failure": expected_message,
            "returncode": proc.returncode,
        },
    }


def mean_case_from_trace(name: str, trace_dir: Path, token_offset: int, token_count: int) -> Tuple[Dict[str, Any], List[float]]:
    src = next(trace_dir.glob("*-self.bin"))
    ret = next(trace_dir.glob("*-return.bin"))
    values = read_fp32(src, count=token_count * 4096, offset=token_offset * 4096)
    expected = read_fp32(ret, count=token_count, offset=token_offset)
    req = {
        "operator": "MeanDim",
        "dimensions": dims(token_count, 1, 1, 4096),
        "parameters": {
            "dim": i32(-1),
            "keepdim": i32(1),
            "reduce_elems": i32(4096),
        },
        "inputs": {
            "input_tensor": tensor("float32", [token_count, 4096], values),
        },
    }
    return req, expected


def expand_case_from_trace(name: str, trace_dir: Path) -> Tuple[Dict[str, Any], List[float]]:
    src = next(trace_dir.glob("*-self.bin"))
    ret = next(trace_dir.glob("*-return.bin"))
    value = read_fp32(src)
    expected = read_fp32(ret)
    req = {
        "operator": "Expand",
        "dimensions": dims(1, 1, 1, 32),
        "parameters": {
            "input_shape": i32([1]),
            "llama_expand": i32(1),
        },
        "inputs": {
            "input_tensor": tensor("float32", [1], value),
        },
    }
    return req, expected


def index_put_flat_regression() -> Tuple[Dict[str, Any], List[float]]:
    elems_per_word = 4
    words = 8
    base = [float(i) for i in range(words * elems_per_word)]
    indices = [1, 3, 6]
    values: List[float] = []
    expected = list(base)
    for update_idx, word_idx in enumerate(indices):
        word = [100.0 + update_idx * 10.0 + lane for lane in range(elems_per_word)]
        values.extend(word)
        start = word_idx * elems_per_word
        expected[start : start + elems_per_word] = word
    req = {
        "operator": "IndexPut",
        "dimensions": dims(1, 1, words, elems_per_word),
        "parameters": {
            "indices": i32(indices),
            "num_updates": i32(len(indices)),
            "accumulate": i32(0),
            # base (alpha.bin) must land in bank3 so LDB scatter overwrites in-place
            "alpha_bank": i32(3),
            "output_bank": i32(3),
            "other_bank": i32(1),
        },
        "inputs": {
            "input_tensor": tensor("float32", [1, 1, words, elems_per_word], base),
            "values_tensor": tensor("float32", [len(indices), elems_per_word], values),
        },
        "outputs": {
            "output_tensor": tensor("float32", [1, 1, words, elems_per_word], expected),
        },
    }
    return req, expected


def index_put_cache_case(name: str, trace_dir: Path, token_offset: int = 0) -> Tuple[Dict[str, Any], Dict[str, Any]]:
    key = next(trace_dir.glob("*-key.bin"))
    slot_file = next(trace_dir.glob("*-slot_mapping.bin"))
    slots = read_i64(slot_file, count=1, offset=token_offset)
    values = read_fp16(key, count=32 * 128, offset=token_offset * 32 * 128)
    slot = slots[0]
    block_size = 16
    num_heads = 32
    head_size = 128
    elems_per_word = 8
    head_words = head_size // elems_per_word
    token_words = num_heads * head_words
    cache_words = (max(slot, 0) + 1) * token_words
    expected_meta = {
        "slot": int(slot),
        "token_words": token_words,
        "cache_words": int(cache_words),
        "expected_first_values": values[:8],
    }
    req = {
        "operator": "IndexPut",
        "dimensions": dims(1, 1, int(cache_words), elems_per_word),
        "parameters": {
            "cache_flash_mode": i32(1),
            "slot_mapping": int64_param([int(slot)]),
            "token_count": i32(1),
            "block_size": i32(block_size),
            "num_heads": i32(num_heads),
            "head_size": i32(head_size),
            "cache_kind": i32(0),
        },
        "inputs": {
            "values_tensor": tensor("float16", [1, num_heads, head_size], values),
        },
    }
    return req, expected_meta


def synthetic_cache_case(
    cache_kind: int,
    slots: List[int],
    strict_rtl: bool = False,
) -> Tuple[Dict[str, Any], List[float]]:
    num_heads = 2
    head_size = 8
    elems_per_word = 8
    token_words = num_heads
    cache_slots = 4
    cache_words = cache_slots * token_words
    kinds = 2 if cache_kind == 2 else 1
    sentinel = 0.25
    base = [sentinel] * (kinds * cache_words * elems_per_word)
    expected = list(base)
    inputs: Dict[str, Any] = {
        "input_tensor": tensor(
            "float16",
            [kinds, cache_slots, num_heads, head_size],
            base,
        ),
    }
    for kind in range(kinds):
        values: List[float] = []
        for token_idx in range(len(slots)):
            token = [
                float((kind + 1) * 100 + token_idx * 10 + elem)
                for elem in range(num_heads * head_size)
            ]
            values.extend(token)
            slot = slots[token_idx]
            if slot >= 0:
                start = kind * cache_words * elems_per_word + slot * num_heads * head_size
                expected[start : start + len(token)] = token
        name = (
            ("key_tensor" if kind == 0 else "value_tensor")
            if cache_kind == 2
            else ("key_tensor" if cache_kind == 0 else "value_tensor")
        )
        inputs[name] = tensor(
            "float16",
            [len(slots), num_heads, head_size],
            values,
        )
    req = {
        "operator": "IndexPut",
        "dimensions": dims(kinds, cache_slots, num_heads, head_size),
        "parameters": {
            "cache_flash_mode": i32(1),
            "slot_mapping": int64_param(slots),
            "token_count": i32(len(slots)),
            "block_size": i32(2),
            "num_heads": i32(num_heads),
            "head_size": i32(head_size),
            "cache_words": i32(cache_words),
            "cache_kind": i32(cache_kind),
            "strict_rtl_lsu_v2": i32(1 if strict_rtl else 0),
        },
        "inputs": inputs,
    }
    return req, expected


def validate_mean(case: Dict[str, Any], expected: List[float]) -> Dict[str, Any]:
    # LLAMA MeanDim golden stores one 16B word per token: lane0=mean, lanes1..3=0.
    got_words = unpack_fp32((Path(case["tvgen_dir"]) / "golden.bin").read_bytes())
    got = [got_words[i * 4] for i in range(len(expected))]
    ok, max_err = allclose(got, expected, rtol=1e-4, atol=1e-5)
    return {"ok": ok, "elements": len(got), "max_abs_err": max_err}


def validate_fp32(case: Dict[str, Any], expected: List[float]) -> Dict[str, Any]:
    got = unpack_fp32((Path(case["tvgen_dir"]) / "golden.bin").read_bytes())
    ok, max_err = allclose(got, expected, rtol=1e-5, atol=1e-6)
    return {"ok": ok, "elements": len(got), "max_abs_err": max_err}


def validate_cache(case: Dict[str, Any], meta: Dict[str, Any]) -> Dict[str, Any]:
    got = unpack_fp16((Path(case["tvgen_dir"]) / "golden.bin").read_bytes())
    slot = meta["slot"]
    start = int(slot) * 32 * 128
    observed = got[start : start + 8]
    ok, max_err = allclose(observed, meta["expected_first_values"], rtol=1e-3, atol=1e-3)
    return {
        "ok": ok,
        "elements": len(got),
        "max_abs_err": max_err,
        "slot": slot,
        "checked_cache_elem_offset": start,
    }


def validate_cache_full(case: Dict[str, Any], expected: List[float]) -> Dict[str, Any]:
    got = unpack_fp16((Path(case["tvgen_dir"]) / "golden.bin").read_bytes())
    ok, max_err = allclose(got, expected, rtol=1e-3, atol=1e-3)
    return {"ok": ok, "elements": len(got), "max_abs_err": max_err}


def validate_strict_cache_no_preload(
    case: Dict[str, Any],
    expected_initial: List[float],
) -> Dict[str, Any]:
    tvgen_dir = Path(case["tvgen_dir"])
    alpha = unpack_fp16((tvgen_dir / "alpha.bin").read_bytes())
    golden = unpack_fp16((tvgen_dir / "golden.bin").read_bytes())
    initial_ok, initial_err = allclose(alpha, expected_initial, rtol=0.0, atol=0.0)
    differs_from_golden = alpha != golden
    iq_names = set(case["iq_files"])
    has_axi = "iq_25_stb_axi.hex" in iq_names and "iq_27_ldb_axi.hex" in iq_names
    ldb_path = tvgen_dir / "hex_instructions" / "iq_27_ldb_axi.hex"
    ldb_gr_addresses: List[int] = []
    if ldb_path.exists():
        for line in ldb_path.read_text().split():
            raw = int(line, 16)
            # Full LDBAXI = 50-bit header + 104-bit CRU; gr_base is CRU[52:13].
            code = raw & ((1 << 104) - 1)
            ldb_gr_addresses.append((code >> 13) & ((1 << 40) - 1))
    contiguous_kv_values = ldb_gr_addresses == [0x1000, 0x1010, 0x1020, 0x1030]
    return {
        "ok": initial_ok and differs_from_golden and has_axi and contiguous_kv_values,
        "elements": len(alpha),
        "max_abs_err": initial_err,
        "alpha_is_initial_cache": initial_ok,
        "alpha_differs_from_golden": differs_from_golden,
        "has_axi_lsu": has_axi,
        "ldb_gr_addresses": ldb_gr_addresses,
        "contiguous_kv_values": contiguous_kv_values,
    }


def trace_summary() -> Dict[str, Dict[str, Any]]:
    out: Dict[str, Dict[str, Any]] = {}
    for key, path in TRACE.items():
        files = sorted(p.name for p in path.glob("*")) if path.exists() else []
        out[key] = {
            "path": str(path),
            "exists": path.exists(),
            "schema": (path / "schema.txt").read_text(encoding="utf-8").strip() if (path / "schema.txt").exists() else "",
            "scalars": (path / "scalars.txt").read_text(encoding="utf-8").strip() if (path / "scalars.txt").exists() else "",
            "bin_files": [f for f in files if f.endswith(".bin")],
        }
    return out


def write_report(out_dir: Path, payload: Dict[str, Any]) -> Path:
    report = out_dir / "LLAMA_three_ops_verify_report.md"
    lines = [
        "# LLAMA Three Ops Verify Report (fhj_op)",
        "",
        "## Summary",
    ]
    for name, item in payload["cases"].items():
        status = "PASS" if item["numeric"]["ok"] else "FAIL"
        lines.append(
            f"- {name}: {status}, elements={item['numeric']['elements']}, "
            f"max_abs_err={item['numeric']['max_abs_err']}"
        )
    lines.extend(["", "## Trace Coverage"])
    lines.append("- MeanDim: round-2 full `1x4096` and round-1 token0 `4096` dim=-1 reduce are validated against captured return tensors.")
    lines.append("- Expand: round-1/round-2 captured scalar `[1] -> [1,32]` lane broadcast is validated against captured return tensors.")
    lines.append("- IndexPut: round-1/round-2 cache_flash mode uses captured key token and captured `slot_mapping`; checked written cache slot content.")
    lines.append("- IndexPut flat scatter regression is also retained for the non-cache path.")
    lines.extend(["", "## Trace Inputs"])
    for key, info in payload["trace"].items():
        lines.append(f"- {key}: exists={info['exists']}, bin_files={len(info['bin_files'])}, scalars={info['scalars']!r}")
    lines.extend(["", "## Remaining Limits"])
    lines.append("- This is still `tvgen/golden` validation, not RTL/VCS or real-chip execution.")
    lines.append("- MeanDim round-1 validates token0 full hidden reduce; running all 1147 tokens through JSON/tvgen is intentionally avoided due to very large request size.")
    lines.append("- IndexPut checks one captured token per round; full prefill 1147-token cache replay needs streaming/chunked case generation.")
    lines.extend(["", "## Validation Level"])
    for level, passed in payload["validation_level"].items():
        lines.append(f"- `{level}`: {passed}")
    lines.extend(["", "## Native Hardware Blockers"])
    lines.append("- MeanDim strict 4096 reduction is rejected because the available lane-wise path cannot reduce the final four FP32 lanes.")
    lines.append("- Expand strict scalar broadcast is rejected because the available datapath has no lane0 replicate/shuffle operation.")
    lines.append(
        "- IndexPut cache-flash emits LDBAXI/STBAXI (IQ27/25); RTL HBM compare still pending."
    )
    report.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return report


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tvgen", type=Path, default=DEFAULT_TVGEN)
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--clean", action="store_true")
    args = ap.parse_args()
    if not args.tvgen.exists():
        raise FileNotFoundError(f"tvgen not found: {args.tvgen}")
    if args.clean and args.out.exists():
        shutil.rmtree(args.out)
    args.out.mkdir(parents=True, exist_ok=True)

    case_defs: List[Tuple[str, Dict[str, Any], Any, str]] = []
    req, exp = mean_case_from_trace("mean_round1_token0_full", TRACE["mean_r1"], 0, 1)
    case_defs.append(("mean_round1_token0_full", req, exp, "mean"))
    req, exp = mean_case_from_trace("mean_round2_full", TRACE["mean_r2"], 0, 1)
    case_defs.append(("mean_round2_full", req, exp, "mean"))
    req, exp = expand_case_from_trace("expand_round1_full", TRACE["expand_r1"])
    case_defs.append(("expand_round1_full", req, exp, "fp32"))
    req, exp = expand_case_from_trace("expand_round2_full", TRACE["expand_r2"])
    case_defs.append(("expand_round2_full", req, exp, "fp32"))
    req, exp = index_put_flat_regression()
    case_defs.append(("index_put_flat_regression", req, exp, "fp32"))
    req, exp = index_put_cache_case("index_put_cache_round1_token0", TRACE["cache_r1"], 0)
    case_defs.append(("index_put_cache_round1_token0", req, exp, "cache"))
    req, exp = index_put_cache_case("index_put_cache_round2", TRACE["cache_r2"], 0)
    case_defs.append(("index_put_cache_round2", req, exp, "cache"))
    for cache_kind in (0, 1, 2):
        req, exp = synthetic_cache_case(cache_kind, [1, -1, 1])
        case_defs.append((f"index_put_cache_kind_{cache_kind}", req, exp, "cache_full"))

    cases: Dict[str, Dict[str, Any]] = {}
    for name, req_obj, expected, kind in case_defs:
        case = run_tvgen(args.tvgen, args.out, name, req_obj)
        if kind == "mean":
            case["numeric"] = validate_mean(case, expected)
        elif kind == "cache":
            case["numeric"] = validate_cache(case, expected)
        elif kind == "cache_full":
            case["numeric"] = validate_cache_full(case, expected)
        else:
            case["numeric"] = validate_fp32(case, expected)
        cases[name] = case

    mean_strict, mean_strict_exp = mean_case_from_trace("mean_round2_strict", TRACE["mean_r2"], 0, 1)
    mean_strict["parameters"]["strict_hardware_path"] = i32(1)
    mean_strict["parameters"]["llama_chunk_reduce"] = i32(1)
    mean_strict_case = run_tvgen(args.tvgen, args.out, "mean_round2_strict", mean_strict)
    mean_strict_case["numeric"] = validate_mean(mean_strict_case, mean_strict_exp)
    cases["mean_round2_strict"] = mean_strict_case
    expand_strict, expand_strict_exp = expand_case_from_trace(
        "expand_round2_strict", TRACE["expand_r2"]
    )
    expand_strict["parameters"]["strict_hardware_path"] = i32(1)
    expand_strict_case = run_tvgen(args.tvgen, args.out, "expand_round2_strict", expand_strict)
    expand_strict_case["numeric"] = validate_fp32(expand_strict_case, expand_strict_exp)
    cases["expand_round2_strict"] = expand_strict_case
    strict_req, strict_expected = synthetic_cache_case(2, [1], strict_rtl=True)
    strict_case = run_tvgen(args.tvgen, args.out, "index_put_strict_no_preload", strict_req)
    initial_cache = strict_req["inputs"]["input_tensor"]["data"]
    strict_case["numeric"] = validate_strict_cache_no_preload(strict_case, initial_cache)
    strict_case["golden_numeric"] = validate_cache_full(strict_case, strict_expected)
    cases["index_put_strict_no_preload"] = strict_case
    overflow_req, _ = synthetic_cache_case(0, [3])
    overflow_req["parameters"]["cache_words"] = i32(2)
    cases["index_put_slot_overflow_reject"] = run_tvgen_expect_fail(
        args.tvgen,
        args.out,
        "index_put_slot_overflow_reject",
        overflow_req,
        "IndexPut slot_mapping exceeds cache_words capacity",
    )

    payload = {
        "validation_level": {
            "golden_pass": all(
                item.get("golden_numeric", item["numeric"])["ok"]
                for item in cases.values()
            ),
            "instruction_pass": all(item["numeric"]["ok"] for item in cases.values()),
            "rtl_pass": False,
            "chip_pass": False,
        },
        "trace": trace_summary(),
        "cases": cases,
    }
    write_json(args.out / "LLAMA_three_ops_verify_report.json", payload)
    report = write_report(args.out, payload)
    ok = all(item["numeric"]["ok"] for item in cases.values())
    print(json.dumps({"ok": ok, "report": str(report), "cases": list(cases.keys())}, indent=2))
    return 0 if ok else 2


if __name__ == "__main__":
    raise SystemExit(main())
