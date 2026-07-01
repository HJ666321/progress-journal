#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
将 .npz 中数组转为 FP32，并输出到 .txt（不覆盖原文件）。

输出规则：
- 每个输入 .npz 生成一个 txt：<name><suffix>.txt
- txt 中按 key 分段写入，值均为 float32

用法:
    python convert_npz_to_fp32.py <file.npz> [<file2.npz> ...]
    python convert_npz_to_fp32.py --all
"""
import argparse
import os
import sys

try:
    import numpy as np
except ImportError:
    print("需要安装 numpy: pip install numpy", file=sys.stderr)
    sys.exit(1)


DEFAULT_SUFFIX = "_fp32"


def to_fp32_or_keep(a):
    """数值数组转 float32；无法转换时保留原值并返回 False。"""
    try:
        if np.issubdtype(a.dtype, np.number) or a.dtype == bool:
            return np.asarray(a, dtype=np.float32), True
        return np.asarray(a, dtype=np.float32), True
    except (ValueError, TypeError):
        return a, False


def get_output_path(path, suffix):
    """基于输入路径生成输出路径：<name><suffix>.txt。"""
    base, ext = os.path.splitext(path)
    if ext.lower() == ".npz":
        return base + suffix + ".txt"
    return path + suffix + ".txt"


def format_array_lines(arr):
    """输出数组文本（原始数据区使用）。"""
    arr = np.asarray(arr)
    formatter = None
    if np.issubdtype(arr.dtype, np.floating):
        formatter = {
            "float_kind": lambda x: np.format_float_positional(
                float(x), precision=16, unique=False, fractional=False, trim="k"
            )
        }
    text = np.array2string(
        arr,
        separator=" ",
        max_line_width=1_000_000,
        formatter=formatter,
    )
    return text.splitlines()


def format_fp32_packed128_lines(arr):
    """
    将数组转换为 FP32 后按 128bit 打包输出十六进制文本。
    规则：每 4 个 FP32 拼成 1 行 128bit，前面的数据放低位。
      - d0 -> [31:0]
      - d1 -> [63:32]
      - d2 -> [95:64]
      - d3 -> [127:96]
    输出格式：0x<32 hex chars>
    """
    a = np.asarray(arr, dtype=np.float32).reshape(-1)
    bits = a.view(np.uint32)
    lines = []
    n = bits.shape[0]
    for i in range(0, n, 4):
        w0 = int(bits[i]) if i < n else 0
        w1 = int(bits[i + 1]) if (i + 1) < n else 0
        w2 = int(bits[i + 2]) if (i + 2) < n else 0
        w3 = int(bits[i + 3]) if (i + 3) < n else 0
        packed = (w3 << 96) | (w2 << 64) | (w1 << 32) | w0
        lines.append("0x{:032X}".format(packed))
    return lines


def format_fp32_hex_lines(arr):
    """将数组转换为 FP32 后逐元素输出十六进制位模式（0xXXXXXXXX）。"""
    a = np.asarray(arr, dtype=np.float32).reshape(-1)
    bits = a.view(np.uint32)
    return [" ".join("0x{:08X}".format(int(x)) for x in bits)]


def write_fp32_txt(out_path, orig_data, fp32_data):
    """将原始数组、逐元素 FP32 hex、128bit 打包结果按顺序写入 txt。"""
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("===== ORIGINAL DATA (copied from source npz) =====\n")
        for key in sorted(orig_data.keys()):
            arr = orig_data[key]
            f.write("# key: {}\n".format(key))
            f.write("# dtype: {}\n".format(arr.dtype))
            f.write("# shape: {}\n".format(tuple(arr.shape)))
            for line in format_array_lines(arr):
                f.write(line + "\n")
            f.write("\n")

        f.write("===== FP32 HEX DATA (PER ELEMENT, 32b) =====\n")
        for key in sorted(fp32_data.keys()):
            arr = fp32_data[key]
            f.write("# key: {}\n".format(key))
            f.write("# dtype: float32 (per-element hex bit pattern)\n")
            f.write("# shape: {}\n".format(tuple(arr.shape)))
            for line in format_fp32_hex_lines(arr):
                f.write(line + "\n")
            f.write("\n")

        # 按你的要求：128bit 拼接结果放在文件最后
        f.write("===== FP32 HEX DATA (PACKED 128b, first element in low bits) =====\n")
        for key in sorted(fp32_data.keys()):
            arr = fp32_data[key]
            f.write("# key: {}\n".format(key))
            f.write("# dtype: float32 (packed to 128-bit hex)\n")
            f.write("# shape: {}\n".format(tuple(arr.shape)))
            for line in format_fp32_packed128_lines(arr):
                f.write(line + "\n")
            f.write("\n")


def convert_npz_to_fp32(path, suffix=DEFAULT_SUFFIX):
    """将单个 npz 输出为 txt 文件，内容为 FP32 数据。"""
    path = os.path.abspath(path)
    if not os.path.isfile(path):
        print("文件不存在: {}".format(path), file=sys.stderr)
        return False
    try:
        z = np.load(path, allow_pickle=True)
        keys = list(z.keys())
        if not keys:
            print("  {}: 无数组，跳过".format(os.path.basename(path)))
            z.close()
            return True
        orig = {}
        out = {}
        for k in keys:
            a = z[k]
            orig[k] = a
            fp32_arr, converted = to_fp32_or_keep(a)
            out[k] = fp32_arr
            if not converted:
                print("  {}[{}] 无法转为 float32，按原 dtype {} 写入".format(
                    os.path.basename(path), k, a.dtype
                ))
        z.close()
        out_path = get_output_path(path, suffix)
        write_fp32_txt(out_path, orig, out)
        print("  已生成: {}".format(out_path))
        print("    来源: {}  keys={}".format(path, keys))
        return True
    except Exception as e:
        print("  处理失败 {}: {}".format(path, e), file=sys.stderr)
        return False


def main():
    parser = argparse.ArgumentParser(description="将 npz 转为 FP32 的 txt 文件")
    parser.add_argument("files", nargs="*", help=".npz 文件路径")
    parser.add_argument("--all", action="store_true", help="转换当前目录下所有 .npz")
    parser.add_argument(
        "--suffix",
        default=DEFAULT_SUFFIX,
        help="输出文件后缀，默认: {}".format(DEFAULT_SUFFIX),
    )
    args = parser.parse_args()
    if args.all:
        cwd = os.getcwd()
        files = []
        for f in os.listdir(cwd):
            if not f.endswith(".npz"):
                continue
            files.append(os.path.join(cwd, f))
        if not files:
            print("当前目录下无 .npz 文件")
            return
    elif not args.files:
        parser.print_help()
        sys.exit(2)
    else:
        files = args.files
    ok = 0
    for f in files:
        if convert_npz_to_fp32(f, suffix=args.suffix):
            ok += 1
    print("完成: {} / {}".format(ok, len(files)))
    sys.exit(0 if ok == len(files) else 1)


if __name__ == "__main__":
    main()
