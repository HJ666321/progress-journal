import struct
import sys

def hex_to_fp16(hex_str):
    val = int(hex_str, 16)
    return struct.unpack('<e', struct.pack('<H', val))[0]

def parse_line(line):
    # line is 32 hex chars (128 bits)
    # broken into 8 chunks of 4 chars (16 bits)
    # Order: usually hex string represents big integer. 
    # string index 0 is MSB (i=7), index 28 is LSB (i=0) ?
    # Let's try parsing right-to-left as standard little-endian chunking
    # But usually file.write(hex(val)) writes 0x...
    # If sim writes: "3f74bcc..."
    # If val = (chunk7 << 112) | ... | chunk0
    # Then string is chunk7 ... chunk0
    chunks = []
    for i in range(0, 32, 4):
        chunks.append(line[i:i+4])
    # chunks[0] matches i=7 (MSB), chunks[7] matches i=0 (LSB)
    # Let's reverse to get i=0..7
    return [c for c in reversed(chunks)]

def get_st(val):
    if val > 0: return 4 # GT
    if val == 0: return 2 # EQ
    if val < 0: return 1 # LS
    return 0

def check_files():
    try:
        with open('bank0.hex', 'r') as f0, open('bank1.hex', 'r') as f1, open('bank5.hex', 'r') as f5:
            lines0 = [l.strip() for l in f0.readlines() if l.strip()]
            lines1 = [l.strip() for l in f1.readlines() if l.strip()]
            lines5 = [l.strip() for l in f5.readlines() if l.strip()]

        print(f"Read {len(lines0)} lines from bank0")
        print(f"Read {len(lines1)} lines from bank1")
        print(f"Read {len(lines5)} lines from bank5")

        for line_idx in range(min(2, len(lines0), len(lines1), len(lines5))):
            l0 = lines0[line_idx]
            l1 = lines1[line_idx]
            l5 = lines5[line_idx]

            chunks0 = parse_line(l0) # [i=0, i=1, ..., i=7]
            chunks1 = parse_line(l1)
            chunks5 = parse_line(l5)

            print(f"--- Line {line_idx} ---")
            
            # Check each of the 8 elements
            for i in range(8):
                val0 = hex_to_fp16(chunks0[i])
                val1 = hex_to_fp16(chunks1[i])
                res = val0 + val1
                
                # Check ST
                st_hex = chunks5[i]
                actual_st = int(st_hex, 16)
                expected_st = get_st(res)
                
                match = (actual_st == expected_st)
                status_str = "MATCH" if match else "FAIL"
                
                print(f"  Idx {i}: {val0} + {val1} = {res}")
                print(f"    Expected ST: {expected_st} ({bin(expected_st)})")
                print(f"    Actual ST:   {actual_st} ({bin(actual_st)}) - {status_str}")

                if not match:
                     print(f"    Mismatch at Line {line_idx} Idx {i}")

    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    check_files()
