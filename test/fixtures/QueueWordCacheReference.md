# Queue cache fixture boundary

`contracts/mocks/QueueWordCacheReference.hex` and `test/fixtures/QueueWordCacheReference.sol.txt`
form a paired bytecode/source fixture. Their level-keyed trait mapping and queue storage are
incompatible with the production layout. No test or deployment script loads either artifact.

`test/fuzz/QueueWordCache.t.sol` validates the production queue-word cache using an uncached oracle
over raw queue lanes and canonical queue rotation. Trait fixtures use the fixed parity buffers
through `BucketSeed`, `MintBucketSeed`, or `bucketSeed.js`.
