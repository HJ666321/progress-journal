# compare_handlers

test_coverage_* 类型的独立比对脚本目录。

## 使用方法

每个 test_coverage_* 类型可以有自己的专用比对脚本，文件命名规则：
- `test_coverage_<type>.py`，例如：
  - `test_coverage_intadd.py` - 处理 test_coverage_intadd
  - `test_coverage_fpadd.py` - 处理 test_coverage_fpadd
  - `test_coverage_int8tofp16.py` - 处理 test_coverage_int8tofp16

如果某个类型没有专用脚本，将使用 `test_coverage_default.py` 作为默认比对方式。

## 脚本接口

每个比对脚本必须实现以下函数：

```python
def compare_case(case_dir, case_name, bank=None):
    """
    比对该 case 的 golden 与 ur_result 文件。
    
    Args:
        case_dir: case 文件夹的完整路径
        case_name: case 名称
        bank: UR bank 编号（可选，某些类型可能不使用）
    
    Returns:
        (passed: bool, message: str)
    """
    # 比对逻辑...
    return True, ""  # 或 False, "错误信息"
```

## 可用工具函数

从 `base_handler` 模块可以导入以下工具函数：

- `get_case_folders(coverage_dir)` - 获取所有 case 子文件夹列表
- `compare_case_single_bank(case_dir, case_name, bank, golden_path)` - 比对单个 bank 的 golden 和 UR 文件
- `normalize_hex_line(line)` - 标准化十六进制行（去空白、转大写）

## 示例

参考以下文件：
- `test_coverage_intadd.py` - intadd 专用比对（自动检测多个 bank，使用 golden_output_int32.txt）
- `test_coverage_inttoint.py` - inttoint 专用比对（自动检测多个 bank，使用 output_data/bank<N>.hex 作为 golden）
- `test_coverage_fptoint.py` - fptoint 专用比对（自动检测多个 bank，使用 output_data/bank<N>.hex 作为 golden）
- `test_coverage_inttofp.py` - inttofp 专用比对（自动检测多个 bank，使用 output_data/bank<N>.hex 作为 golden）
- `test_coverage_fptofp.py` - fptofp 专用比对（自动检测多个 bank，使用 output_data/bank<N>.hex 作为 golden）
- `test_coverage_fpadd.py` - fpadd 专用比对（使用 bank 参数，优先 golden_output_fp16.txt）
- `test_coverage_int8tofp16.py` - int8tofp16 专用比对（使用 bank 参数，使用 golden_output_fp16.txt）
- `test_coverage_default.py` - 默认比对方式（使用 bank 参数，优先 golden_output_fp16/fp32/int32.txt）
- `phase4_bank_constrained.py` - phase4_bank_constrained 单 case 比对（自动检测 bank，使用 output_data/bank<N>.hex 作为 golden，支持 FP32 ULP 容差）

## 比对模式说明

### 模式1：使用 output_data/bank<N>.hex 作为 golden（inttoint, fptoint, inttofp, fptofp）
- 从 `output_data/` 文件夹中读取所有 `bank<N>.hex` 文件
- 对每个 bank，比对 `output_data/bank<N>.hex`（golden）与 `ur_result_<case_name>_bank<N>.hex`（UR输出）
- 所有 bank 都通过才算 case 通过

### 模式2：使用固定的 golden_output_*.txt（intadd, fpadd, int8tofp16等）
- 使用固定的 golden 文件（如 `golden_output_int32.txt` 或 `golden_output_fp16.txt`）
- 比对该 golden 文件与 `ur_result_<case_name>_bank<N>.hex`
- 可能使用 bank 参数指定 bank，或自动检测多个 bank

### 模式3：单 case 目录（phase4_bank_constrained）
- `phase4_bank_constrained` 是一个单 case 目录（不是 `test_coverage_*` 格式）
- 可以直接运行脚本进行比对：`python phase4_bank_constrained.py <case_dir>`
- 自动检测 `output_data/` 中的所有 `bank<N>.hex` 文件
- 使用 FP32 精度，支持 1 ULP 容差比对
- 比对 `output_data/bank<N>.hex`（golden）与 `ur_result_phase4_bank_constrained_bank<N>.hex`（UR输出）
