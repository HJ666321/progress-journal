import struct

def hex_to_fp16(hex_val):
    return struct.unpack('<e', struct.pack('<H', hex_val))[0]

def get_st(val):
    if val > 0: return 4 # GT
    if val == 0: return 2 # EQ
    if val < 0: return 1 # LS
    return 0

bank0_hex = "3f74bcc7c826bd024430482ac497c6f0"
bank1_hex = "4772c677c259c6d9bd82c76dc0d73f65"

# Parse 16-bit chunks, assuming Input String is Big Endian representation of the vector
# i.e. MSB (Element 7) is on the left, LSB (Element 0) is on the right.
# However, the previous logic used 'reversed', implying Element 0 is at string end.
# Let's stick to the previous successful logic: String Right = Element 0.

def parse_chunks(hex_str):
    chunks = []
    # Process 4 chars at a time
    for i in range(0, len(hex_str), 4):
        chunk_str = hex_str[i:i+4]
        chunks.append(int(chunk_str, 16))
    # Correct order: chunks[0] corresponds to left-most characters (Idx 7)
    # chunks[-1] corresponds to right-most characters (Idx 0)
    # Let's store as [Idx 7, Idx 6, ..., Idx 0]
    return chunks

vals0 = parse_chunks(bank0_hex)
vals1 = parse_chunks(bank1_hex)
# vals0[0] is Idx 7 ('3f74'), vals0[7] is Idx 0 ('c6f0')

print(f"Bank0 Hex: {bank0_hex}")
print(f"Bank1 Hex: {bank1_hex}")
print("-" * 60)
print(f"{'Idx':<4} {'Input0':<12} {'Input1':<12} {'Sum':<12} {'ST':<4} {'Flag'}")
print("-" * 60)

st_results = []

# We interpret the string as: [Word7][Word6]...[Word0]
# So Loop from 0 to 7. 
# vals0[0] matches Word7.
# But conventionally Idx 0 is the LSB.
# Let's align with "Word N" notation.
# Word 7 is at index 0 of our parsed list.

word_outputs = []

for i in range(8):
    # Mapping list index to Vector Index
    # List: 0 (Left) -> 7 (Right)
    # Vector: 7 (MSB) -> 0 (LSB)
    # Actually, verify_fpadd logic often iterates range(8) where 0 is LSB.
    # bank5.hex logic: "0004...0001" -> Left is Idx 7, Right is Idx 0.
    
    # So if we iterate the list from 0 to 7:
    # i=0 is list start = Hex String Left = Idx 7
    # i=7 is list end = Hex String Right = Idx 0
    
    val0_int = vals0[i]
    val1_int = vals1[i]
    
    f0 = hex_to_fp16(val0_int)
    f1 = hex_to_fp16(val1_int)
    res = f0 + f1
    
    st = get_st(res)
    st_results.append(st)
    
    vector_idx = 7 - i
    flag_str = "GT" if st == 4 else ("EQ" if st == 2 else "LS")
    
    print(f"{vector_idx:<4} {f0:<12.4f} {f1:<12.4f} {res:<12.4f} {st:<4} {flag_str}")
    
    word_outputs.append(f"{st:04x}")

print("-" * 60)
final_hex = "".join(word_outputs)
print(f"ST Result Hex: {final_hex}")
