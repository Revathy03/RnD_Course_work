import random
import struct

num_floats = 16384   # 64KB worth of floats

with open("floats_64kb.bin", "wb") as f:
    for _ in range(num_floats):
        value = random.random()   # float between 0 and 1
        f.write(struct.pack('f', value))