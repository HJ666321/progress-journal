# test_coverage_handlers

test_coverage_* 类型的独立处理脚本目录。

## 使用方法

每个 test_coverage_* 类型可以有自己的专用处理脚本，文件命名规则：
- `test_coverage_<type>.py`，例如：
  - `test_coverage_intadd.py` - 处理 test_coverage_intadd
  - `test_coverage_fpadd.py` - 处理 test_coverage_fpadd
  - `test_coverage_int8tofp16.py` - 处理 test_coverage_int8tofp16

如果某个类型没有专用脚本，将使用 `test_coverage_default.py` 作为默认处理方式。

## 脚本接口

每个处理脚本必须实现以下函数：

```python
def process_coverage_folder(coverage_folder_path):
    """
    处理 test_coverage_* 文件夹。
    
    Args:
        coverage_folder_path: test_coverage_* 的完整路径
    
    Returns:
        None
    """
    # 处理逻辑...
```

## 可用工具函数

从 `base_handler` 模块可以导入以下工具函数：

- `get_case_folders(coverage_folder_path)` - 获取所有 case 子文件夹列表
- `generate_data_list(case_folder, data_list_suffix=None)` - 生成 data_list.txt
- `convert_to_fp32(case_folder, npy_filename, out_filename)` - 转换 npy 为 FP32
- `convert_to_fp16(case_folder, npy_filename, out_filename)` - 转换 npy 为 FP16
- `convert_to_int32(case_folder, npy_filename, out_filename)` - 转换 npy 为 int32
- `parse_summary_txt(coverage_folder_path)` - 解析 summary.txt

## 示例

参考以下文件：
- `test_coverage_intadd.py` - intadd 专用处理（转 int32，不读 summary）
- `test_coverage_int8tofp16.py` - int8tofp16 专用处理（转 FP16，不读 summary）
- `test_coverage_fpadd.py` - fpadd 专用处理（读 summary，转 FP16/FP32）
- `test_coverage_default.py` - 默认处理方式（读 summary，转 FP16/FP32）
