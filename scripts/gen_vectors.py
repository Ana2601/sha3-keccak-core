#!/usr/bin/env python3
"""Generate SHA-3 test vectors from Python's hashlib (the golden model).

Line format:  <mode> <len> <byte0> <byte1> ... <digest as 512-bit LE integer>
"""
import hashlib
import random
import sys

ALGS = [(hashlib.sha3_224, 144), (hashlib.sha3_256, 136), (hashlib.sha3_384, 104), (hashlib.sha3_512, 72)]


def main(path, seed=1):
    rng = random.Random(seed)
    lines = []
    for mode, (alg, rate) in enumerate(ALGS):
        # Corner cases around the block boundary plus random lengths.
        lengths = [0, 1, 3, rate - 2, rate - 1, rate, rate + 1, 2 * rate - 1, 2 * rate, 2 * rate + 1]
        lengths += [rng.randrange(0, 4 * rate) for _ in range(40)]
        for n in lengths:
            msg = bytes(rng.randrange(256) for _ in range(n))
            dig = int.from_bytes(alg(msg).digest(), "little")
            lines.append(" ".join([str(mode), str(n)] + [f"{b:02x}" for b in msg] + [f"{dig:0128x}"]))
    # NIST "abc" known-answer vectors
    for mode, (alg, _) in enumerate(ALGS):
        dig = int.from_bytes(alg(b"abc").digest(), "little")
        lines.append(" ".join([str(mode), "3", "61", "62", "63", f"{dig:0128x}"]))
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"wrote {len(lines)} vectors to {path}")


if __name__ == "__main__":
    main(sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 1)
