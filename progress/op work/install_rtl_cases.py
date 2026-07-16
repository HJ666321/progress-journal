#!/usr/bin/env python3
"""Install fhj_op TVGen vectors into the Jianyuan v4.21 RTL suite."""

from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path


ROOT = Path(__file__).resolve().parent
DEFAULT_RTL = Path("/home/bupt/LLAMA_test/Jianyuan-aiacc_4.21")
DEFAULT_OUT = ROOT / "llama_verify_out" / "cases"
CASES = {
    "mean_round2_full": "mean_dim_compat",
    "mean_round2_strict": "mean_dim_native",
    "expand_round2_full": "expand_compat",
    "expand_round2_strict": "expand_native",
    "index_put_flat_regression": "index_put_flat",
    "index_put_strict_no_preload": "index_put_cache_axi",
}

# UR banks used by MeanDim llama_chunk_reduce tiles (see mean_dim_op_constants.h).
MEAN_NATIVE_TILE_BANKS = (4, 5, 6, 7)
UR_WORDS = 256
UR_BYTES = UR_WORDS * 16
HBM_WORD_BYTES = 16


def canonical_iq_name(path: Path) -> str:
    stem = path.stem
    parts = stem.split("_", 2)
    name = parts[2] if len(parts) == 3 and parts[1].isdigit() else stem[3:] if stem.startswith("iq_") else stem
    name = (
        name.replace("ur_rdata_0", "ur-r0")
        .replace("ur_rdata_1", "ur-r1")
        .replace("ur_rdata_2", "ur-r2")
        .replace("ur_rdata_3", "ur-r3")
        .replace("ur_wdata_0", "ur-w0")
        .replace("ur_wdata_1", "ur-w1")
        .replace("ur_wdata_2", "ur-w2")
        .replace("ur_wdata_3", "ur-w3")
    )
    return f"iq_{name}.hex"


def padded_hex_lines(path: Path, words: int = 256) -> list[str]:
    lines = []
    for line in path.read_text().splitlines():
        value = line.strip()
        if value:
            lines.append(value[2:] if value.lower().startswith("0x") else value)
    if len(lines) > words:
        raise ValueError(f"{path} has {len(lines)} words, exceeds RTL UR capacity {words}")
    return lines + ["0" * 32] * (words - len(lines))


def binary_hex_lines(path: Path, words: int = 256) -> list[str]:
    data = path.read_bytes()
    lines = [data[i : i + 16].ljust(16, b"\0")[::-1].hex() for i in range(0, len(data), 16)]
    if len(lines) > words:
        raise ValueError(f"{path} has {len(lines)} words, exceeds RTL UR capacity {words}")
    return lines + ["0" * 32] * (words - len(lines))


def write_lines(path: Path, lines: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def split_mean_native_tiles(input_bin: Path, ur_data_dir: Path) -> None:
    """Place 1024 FP32 words across banks 0/1/4/5 (256 each)."""
    data = input_bin.read_bytes()
    if len(data) < UR_BYTES * len(MEAN_NATIVE_TILE_BANKS):
        raise ValueError(
            f"{input_bin} too small for native tiles: {len(data)} bytes "
            f"(need {UR_BYTES * len(MEAN_NATIVE_TILE_BANKS)})"
        )
    for i, bank in enumerate(MEAN_NATIVE_TILE_BANKS):
        chunk = data[i * UR_BYTES : (i + 1) * UR_BYTES]
        lines = [chunk[j : j + 16].ljust(16, b"\0")[::-1].hex() for j in range(0, len(chunk), 16)]
        lines += ["0" * 32] * (UR_WORDS - len(lines))
        write_lines(ur_data_dir / f"bank{bank}.hex", lines)


def decode_axi_gr_bases(hex_path: Path, code_bits: int) -> list[int]:
    addrs: list[int] = []
    for line in hex_path.read_text().splitlines():
        raw = line.strip()
        if not raw:
            continue
        value = int(raw, 16)
        code = value & ((1 << code_bits) - 1)
        addrs.append((code >> 13) & ((1 << 40) - 1))
    return addrs


def patch_hbm_image(lines: list[str], byte_base: int, blob: bytes) -> None:
    start = byte_base // HBM_WORD_BYTES
    for i in range(0, len(blob), HBM_WORD_BYTES):
        word = blob[i : i + HBM_WORD_BYTES].ljust(HBM_WORD_BYTES, b"\0")[::-1].hex()
        idx = start + i // HBM_WORD_BYTES
        while len(lines) <= idx:
            lines.append("0" * 32)
        lines[idx] = word


def install_index_put_cache_axi(tvgen: Path, target: Path) -> None:
    """Install LDBAXI/STBAXI cache-flash case with local HBM init image."""
    ldb_hex = target / "iq_ldb_axi.hex"
    stb_hex = target / "iq_stb_axi.hex"
    if not ldb_hex.exists() or not stb_hex.exists():
        raise FileNotFoundError(f"missing AXI IQ files under {target}")

    ldb_addrs = decode_axi_gr_bases(ldb_hex, 104)
    stb_addrs = decode_axi_gr_bases(stb_hex, 102)
    if not ldb_addrs or not stb_addrs:
        raise ValueError("AXI IQ files have no instructions")

    values_base = min(ldb_addrs)
    store_base = min(stb_addrs) & ~0xFFF  # 4KB-align window used by remap
    # Prefer exact output remapped base from STB if already aligned.
    if min(stb_addrs) >= 0x2000:
        store_base = min(stb_addrs) & ~0xFFF

    other = (tvgen / "other.bin").read_bytes()
    initial = (tvgen / "input.bin").read_bytes()
    golden = (tvgen / "golden.bin").read_bytes()
    if not other or not initial or not golden:
        raise ValueError("cache AXI install requires other.bin/input.bin/golden.bin")

    # Cover max touched line with a little margin for dump compares.
    max_byte = max(max(ldb_addrs) + HBM_WORD_BYTES, max(stb_addrs) + HBM_WORD_BYTES)
    max_byte = max(max_byte, store_base + len(golden), values_base + len(other))
    n_lines = (max_byte + HBM_WORD_BYTES - 1) // HBM_WORD_BYTES + 8

    hbm_lines = ["0" * 32] * n_lines
    patch_hbm_image(hbm_lines, values_base, other)
    patch_hbm_image(hbm_lines, store_base, initial)

    hbm_dir = target.parent / "hbm_init"
    hbm_dir.mkdir(parents=True, exist_ok=True)
    write_lines(hbm_dir / "memory_init1.hex", hbm_lines)
    # TB loads memory_init1..8; replicate zeros for unused SMCs.
    for smc in range(2, 9):
        write_lines(hbm_dir / f"memory_init{smc}.hex", ["0" * 32] * 8)

    cache_words = len(golden) // HBM_WORD_BYTES
    write_lines(target / "output_bank" / "bank3_final.hex", binary_hex_lines(tvgen / "golden.bin", cache_words))

    meta = {
        "op": "index_put",
        "num_smc": 1,
        "out_bank": 3,
        "out_words": cache_words,
        "dtype": "fp16",
        "store_byte_base": store_base,
        "word_bytes": HBM_WORD_BYTES,
        "inputs": [
            {"name": "values", "byte_base": values_base, "words": len(other) // HBM_WORD_BYTES},
            {"name": "cache", "byte_base": store_base, "words": cache_words},
        ],
        "ldb_addrs": ldb_addrs,
        "stb_addrs": stb_addrs,
    }
    (target.parent / "meta_v3.json").write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
    (target.parent / "HBM_INIT_DIR.txt").write_text(str(hbm_dir.resolve()) + "\n", encoding="utf-8")


def install_case(source_root: Path, suite_root: Path, source_name: str, rtl_name: str) -> Path:
    tvgen = source_root / source_name / "tvgen"
    if not (tvgen / "simulator_config.json").exists():
        raise FileNotFoundError(f"missing TVGen case: {tvgen}")
    target = suite_root / rtl_name / "smc_0"
    if target.parent.exists():
        shutil.rmtree(target.parent)
    (target / "ur_data").mkdir(parents=True)
    (target / "output_bank").mkdir()

    for iq_file in sorted((tvgen / "hex_instructions").glob("iq_*.hex")):
        shutil.copy2(iq_file, target / canonical_iq_name(iq_file))
    for bank in range(8):
        src = tvgen / f"ur_{bank:02d}.hex"
        if rtl_name in ("mean_dim_native", "index_put_cache_axi"):
            lines = ["0" * 32] * 256
        elif src.exists():
            lines = padded_hex_lines(src)
        else:
            lines = ["0" * 32] * 256
        write_lines(target / "ur_data" / f"bank{bank}.hex", lines)

    # Native MeanDim: TVGen dumps the full input onto bank0; re-tile into 4 banks.
    if rtl_name == "mean_dim_native":
        input_bin = tvgen / "input.bin"
        if input_bin.exists():
            split_mean_native_tiles(input_bin, target / "ur_data")
        alpha_bin = tvgen / "alpha.bin"
        if alpha_bin.exists():
            write_lines(target / "ur_data" / "bank2.hex", binary_hex_lines(alpha_bin))

    if rtl_name == "index_put_cache_axi":
        install_index_put_cache_axi(tvgen, target)
        return target

    golden_bin = tvgen / "golden.bin"
    simulated = tvgen / "sim_result" / "bank3.hex"
    if golden_bin.exists():
        golden_lines = binary_hex_lines(golden_bin)
    else:
        golden_lines = padded_hex_lines(simulated if simulated.exists() else tvgen / "ur_03.hex")
    write_lines(target / "output_bank" / "bank3_final.hex", golden_lines)
    return target


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rtl-root", type=Path, default=DEFAULT_RTL)
    parser.add_argument("--vectors", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--suite", default="fhj_llama")
    args = parser.parse_args()
    suite_root = args.rtl_root / "test_atomic_ops" / args.suite
    installed = []
    for source_name, rtl_name in CASES.items():
        src = args.vectors / source_name
        if not (src / "tvgen" / "simulator_config.json").exists():
            print(f"skip missing {source_name}")
            continue
        installed.append(install_case(args.vectors, suite_root, source_name, rtl_name))
    print("\n".join(str(path) for path in installed))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
