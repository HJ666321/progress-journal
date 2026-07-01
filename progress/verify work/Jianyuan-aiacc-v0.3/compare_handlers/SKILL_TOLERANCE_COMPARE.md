# 容差比对 Skill

## 概述

本 skill 描述了如何实现带容差的比对逻辑，用于处理浮点数和整数转换的验证场景。当硬件实现与参考模型之间存在微小的舍入误差时，允许一定范围内的容差，而不是要求严格相等。

## 适用场景

- **浮点数转换**（FPtoFP, INTtoFP）：允许 1 ULP（Unit in Last Place）误差
- **整数转换**（FPtoINT, INTtoINT）：允许 ±1 容差
- **多精度支持**：根据目的精度自动调整每行元素数量（FP32/Int32: 4个，FP16/Int16: 8个）

## 核心功能

### 1. 解析 cases_summary.md

从测试用例摘要文件中提取每个 case 的目的精度信息。

```python
def parse_cases_summary(coverage_dir):
    """
    解析 coverage_dir/cases_summary.md 文件，提取每个 case 的目的精度。
    
    Args:
        coverage_dir: test_coverage_* 目录路径
    
    Returns:
        dict: {case_name: dst_precision}，如 {'case0001': 'FP16', 'case0003': 'FP32'}
    """
    summary_path = os.path.join(coverage_dir, "cases_summary.md")
    case_precision_map = {}
    
    if not os.path.isfile(summary_path):
        return case_precision_map
    
    try:
        with _open(summary_path, "r", encoding="utf-8") as f:
            lines = f.readlines()
        
        # 查找表格开始（包含 "目的精度" 的行）
        table_start = -1
        for i, line in enumerate(lines):
            if "目的精度" in line:
                table_start = i
                break
        
        if table_start == -1:
            return case_precision_map
        
        # 解析表格行（跳过表头，从 table_start+2 开始）
        for i in range(table_start + 2, len(lines)):
            line = lines[i].strip()
            if not line or not line.startswith('|'):
                continue
            
            # 解析表格行：| case0001 | ... | FP16 | ...
            parts = [p.strip() for p in line.split('|')]
            if len(parts) >= 4:
                case_name = parts[1]
                dst_precision = parts[3].upper()  # 根据实际表格列位置调整
                if case_name and dst_precision:
                    case_precision_map[case_name] = dst_precision
    
    except Exception as e:
        pass
    
    return case_precision_map
```

### 2. 浮点数 ULP 比对

允许两个浮点数二进制表示相差 1（1 ULP 误差）。

```python
def compare_fp_with_ulp(golden_line, ur_line, dst_precision):
    """
    比对一行浮点数数据，允许 1 ULP 误差。
    
    Args:
        golden_line: golden 文件的 32 字符 hex 行（128bit）
        ur_line: UR 文件的 32 字符 hex 行（128bit）
        dst_precision: 'FP32' 或 'FP16'
    
    Returns:
        (passed: bool, error_msg: str)
    """
    if len(golden_line) != 32 or len(ur_line) != 32:
        return False, "行长度非 32 字符"
    
    if golden_line == ur_line:
        return True, ""
    
    # 根据精度拆分元素
    if dst_precision == 'FP32':
        num_elements = 4
        element_width = 8  # 每个 FP32 8 字符（32bit）
    elif dst_precision == 'FP16':
        num_elements = 8
        element_width = 4  # 每个 FP16 4 字符（16bit）
    else:
        return False, "未知的目的精度: {}".format(dst_precision)
    
    # 逐元素比对
    failed_elements = []
    for i in range(num_elements):
        start_idx = i * element_width
        end_idx = start_idx + element_width
        golden_elem = golden_line[start_idx:end_idx]
        ur_elem = ur_line[start_idx:end_idx]
        
        if golden_elem == ur_elem:
            continue
        
        # 计算二进制表示的差值
        try:
            golden_int = int(golden_elem, 16)
            ur_int = int(ur_elem, 16)
            diff = abs(golden_int - ur_int)
            
            if diff != 1:
                # 差值不为 1，失败
                failed_elements.append("元素[{}]: golden=0x{}, ur=0x{}, diff={}".format(
                    i, golden_elem, ur_elem, diff))
        except ValueError:
            failed_elements.append("元素[{}]: 无效的 hex 值".format(i))
    
    if failed_elements:
        return False, "; ".join(failed_elements)
    
    return True, ""
```

### 3. 整数容差比对

允许两个整数相差 ±1。

```python
def compare_int_with_tolerance(golden_line, ur_line, dst_precision):
    """
    比对一行整数数据，允许 ±1 容差。
    
    Args:
        golden_line: golden 文件的 32 字符 hex 行（128bit）
        ur_line: UR 文件的 32 字符 hex 行（128bit）
        dst_precision: 'INT32' 或 'INT16'
    
    Returns:
        (passed: bool, error_msg: str)
    """
    if len(golden_line) != 32 or len(ur_line) != 32:
        return False, "行长度非 32 字符"
    
    if golden_line == ur_line:
        return True, ""
    
    # 根据精度拆分元素
    if dst_precision == 'INT32':
        num_elements = 4
        element_width = 8  # 每个 Int32 8 字符（32bit）
    elif dst_precision == 'INT16':
        num_elements = 8
        element_width = 4  # 每个 Int16 4 字符（16bit）
    else:
        return False, "未知的目的精度: {}".format(dst_precision)
    
    # 逐元素比对
    failed_elements = []
    for i in range(num_elements):
        start_idx = i * element_width
        end_idx = start_idx + element_width
        golden_elem = golden_line[start_idx:end_idx]
        ur_elem = ur_line[start_idx:end_idx]
        
        if golden_elem == ur_elem:
            continue
        
        # 计算整数差值（有符号整数）
        try:
            golden_int = int(golden_elem, 16)
            ur_int = int(ur_elem, 16)
            
            # 转换为有符号整数（如果超过范围）
            if dst_precision == 'INT32':
                if golden_int > 0x7FFFFFFF:
                    golden_int = golden_int - 0x100000000
                if ur_int > 0x7FFFFFFF:
                    ur_int = ur_int - 0x100000000
            elif dst_precision == 'INT16':
                if golden_int > 0x7FFF:
                    golden_int = golden_int - 0x10000
                if ur_int > 0x7FFF:
                    ur_int = ur_int - 0x10000
            
            diff = abs(golden_int - ur_int)
            
            if diff > 1:
                # 差值大于 1，失败
                failed_elements.append("元素[{}]: golden={} (0x{}), ur={} (0x{}), diff={}".format(
                    i, golden_int, golden_elem, ur_int, ur_elem, diff))
        except ValueError:
            failed_elements.append("元素[{}]: 无效的 hex 值".format(i))
    
    if failed_elements:
        return False, "; ".join(failed_elements)
    
    return True, ""
```

### 4. 单 Bank 比对函数模板

```python
def compare_case_single_bank_with_tolerance(case_dir, case_name, bank, golden_path, dst_precision, compare_func):
    """
    比对该 case 的单个 bank 的 golden 与 ur_result 文件（支持容差）。
    
    Args:
        case_dir: case 文件夹路径
        case_name: case 名称
        bank: bank 编号
        golden_path: golden 文件路径
        dst_precision: 目的精度
        compare_func: 比对函数（compare_fp_with_ulp 或 compare_int_with_tolerance）
    
    Returns:
        (passed: bool, message: str)
    """
    ur_path = os.path.join(case_dir, "ur_result_{}_bank{}.hex".format(case_name, bank))
    
    if not os.path.isfile(golden_path):
        return False, "无 golden 文件: {}".format(os.path.basename(golden_path))
    if not os.path.isfile(ur_path):
        return False, "无 UR 文件: {}".format(os.path.basename(ur_path))

    try:
        with _open(golden_path, "r", encoding="utf-8") as f:
            golden_lines = [normalize_hex_line(ln) for ln in f.readlines()]
    except IOError as e:
        return False, "读取 golden 失败: {}".format(e)

    try:
        with _open(ur_path, "r", encoding="utf-8") as f:
            ur_lines = [normalize_hex_line(ln) for ln in f.readlines()]
    except IOError as e:
        return False, "读取 UR 失败: {}".format(e)

    # 以 golden 有效行数为准
    golden_valid = [ln for ln in golden_lines if ln]
    ur_valid = [ln for ln in ur_lines if ln]

    if len(ur_valid) < len(golden_valid):
        return False, "UR 行数不足: golden {} 行, ur {} 行".format(len(golden_valid), len(ur_valid))

    # 逐行比对（使用传入的比对函数）
    for i, (g, u) in enumerate(zip(golden_valid, ur_valid)):
        passed, msg = compare_func(g, u, dst_precision)
        if not passed:
            return False, "第 {} 行: {}".format(i + 1, msg)

    return True, ""
```

### 5. 主比对函数模板

```python
def compare_case(case_dir, case_name, bank=None):
    """
    比对该 case 的 golden 与 ur_result 文件（支持容差）。
    
    Args:
        case_dir: case 文件夹的完整路径
        case_name: case 名称
        bank: 未使用（自动检测 bank）
    
    Returns:
        (passed: bool, message: str)
    """
    # 获取 coverage_dir（case_dir 的父目录）
    coverage_dir = os.path.dirname(case_dir)
    
    # 解析 cases_summary.md 获取目的精度
    case_precision_map = parse_cases_summary(coverage_dir)
    dst_precision = case_precision_map.get(case_name)
    
    if not dst_precision:
        # 如果找不到目的精度，使用默认值
        dst_precision = 'FP32'  # 或 'INT32'，根据实际情况调整
    
    # 从 output_data/ 读取 bank 列表
    banks = get_banks_from_output_data(case_dir)
    if not banks:
        return False, "output_data/ 中未找到 bank<N>.hex 文件"
    
    # 选择比对函数
    if dst_precision in ('FP32', 'FP16'):
        compare_func = compare_fp_with_ulp
    elif dst_precision in ('INT32', 'INT16'):
        compare_func = compare_int_with_tolerance
    else:
        return False, "未知的目的精度: {}".format(dst_precision)
    
    # 对每个 bank 进行比对
    all_passed = True
    failed_banks = []
    for b in banks:
        golden_path = os.path.join(case_dir, "output_data", "bank{}.hex".format(b))
        passed, msg = compare_case_single_bank_with_tolerance(
            case_dir, case_name, b, golden_path, dst_precision, compare_func)
        if not passed:
            all_passed = False
            failed_banks.append("bank{} ({})".format(b, msg))
    
    if all_passed:
        return True, ""
    else:
        return False, "失败的 bank: {}".format(", ".join(failed_banks))
```

## 使用示例

### 浮点数比对（FPtoFP, INTtoFP）

```python
# 在 compare_case 中
case_precision_map = parse_cases_summary(coverage_dir)
dst_precision = case_precision_map.get(case_name) or 'FP32'

# 使用浮点数 ULP 比对
passed, msg = compare_case_single_bank_with_tolerance(
    case_dir, case_name, bank, golden_path, dst_precision, compare_fp_with_ulp)
```

### 整数比对（FPtoINT, INTtoINT）

```python
# 在 compare_case 中
case_precision_map = parse_cases_summary(coverage_dir)
dst_precision = case_precision_map.get(case_name) or 'INT32'

# 使用整数容差比对
passed, msg = compare_case_single_bank_with_tolerance(
    case_dir, case_name, bank, golden_path, dst_precision, compare_int_with_tolerance)
```

## 注意事项

1. **cases_summary.md 格式**：确保表格中包含"目的精度"列，且列位置正确（通常是第4列，索引为3）
2. **精度映射**：根据实际情况调整精度值的识别（FP16/FP32 vs Int16/Int32）
3. **有符号整数处理**：整数比对时需要正确处理有符号数（超过最大值时转换为负数）
4. **错误信息**：提供详细的错误信息，包括行号、元素索引、golden/UR 值和差值
5. **默认值**：如果无法从 cases_summary.md 获取精度，使用合理的默认值

## 参考实现

- `test_coverage_inttofp.py` - 浮点数 ULP 比对示例
- `test_coverage_fptofp.py` - 浮点数 ULP 比对示例
- `test_coverage_fptoint.py` - 整数容差比对示例
- `test_coverage_inttoint.py` - 整数容差比对示例
