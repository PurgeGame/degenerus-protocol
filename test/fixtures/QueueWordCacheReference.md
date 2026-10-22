# Archived queue drain reference

`contracts/mocks/QueueWordCacheReference.hex` and `QueueWordCacheReference.sol.txt` preserve an archived implementation and its source. Their level-keyed trait mapping and queue storage are incompatible with the current layout. Neither artifact is loaded by the current tests or deployment scripts.

`test/fuzz/QueueWordCache.t.sol` validates the live queue-word cache using an uncached oracle over raw queue lanes and canonical queue rotation. Current trait fixtures use the fixed parity buffers through `BucketSeed`, `MintBucketSeed`, or `bucketSeed.js`.

The archived source and bytecode remain paired; changing their slot calculations without recompiling the historical implementation would invalidate that record.
