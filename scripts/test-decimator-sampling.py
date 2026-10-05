#!/usr/bin/env python3
"""Independent full-word Keccak replay and position-frequency checks for Decimator strata."""
from Crypto.Hash import keccak
import json
import math


def digest(data):
    h = keccak.new(digest_bits=256)
    h.update(data)
    return h.digest()


TAG = digest(b'decimator.battle.sample.v1')


def survivor_positions(word, level, total):
    count = min(1000, (total + 1) // 2)
    prefix = TAG + word.to_bytes(32, 'big') + level.to_bytes(32, 'big')
    rotation = int.from_bytes(digest(prefix), 'big') % total
    positions = []
    for stratum in range(count):
        lo, hi = stratum * total // count, (stratum + 1) * total // count
        offset = int.from_bytes(digest(prefix + stratum.to_bytes(32, 'big')), 'big') % (hi - lo)
        positions.append((lo + offset + rotation) % total)
    return positions


def main():
    result = []
    for total in [1, 2, 3, 1999, 2000, 2001, 2500, 2 * (2**40 - 1)]:
        words = 2000
        bins = total if total <= 2500 else 100
        frequencies = [0] * bins
        count = min(1000, (total + 1) // 2)
        for trial in range(words):
            word = int.from_bytes(digest(b'decimator.sampling.statistics.v1' + trial.to_bytes(32, 'big')), 'big')
            positions = survivor_positions(word, 5, total)
            assert len(positions) == count and len(set(positions)) == count
            for pos in positions:
                frequencies[min(pos * bins // total, bins - 1)] += 1
        expected = words * count / bins
        # For individual positions use Bernoulli inclusion variance. Large fields use equal
        # position bands, whose stratum counts are strongly constrained; this is conservative.
        variance = expected * (1 - count / total) if bins == total else expected
        sigma = math.sqrt(variance)
        zmax = max(abs(f - expected) / sigma for f in frequencies) if sigma else 0
        assert zmax < 7, (total, zmax, min(frequencies), max(frequencies))
        # Conditional on any fixed set of stratum offsets, every ID appears in precisely
        # count of all possible rotations. Exhaustively demonstrate it at each small boundary.
        if total <= 2500:
            rotation_counts = [0] * total
            for pos in survivor_positions(777, 5, total):
                for rotation in range(total):
                    rotation_counts[(pos + rotation) % total] += 1
            assert set(rotation_counts) == {count}
        result.append(dict(T=total, S=count, words=words, bins=bins, expected=expected,
                           minimum=min(frequencies), maximum=max(frequencies), max_sigma=round(zmax, 4)))
    vectors = []
    for total in [1, 2, 3, 1999, 2000, 2001, 2500, 2 * (2**40 - 1)]:
        positions = survivor_positions(777, 5, total)
        vectors.append(dict(T=total, first=positions[0] + 1, middle=positions[len(positions)//2] + 1, last=positions[-1] + 1))
    print(json.dumps(dict(statistics=result, replay_vectors=vectors), indent=2))


if __name__ == '__main__':
    main()
