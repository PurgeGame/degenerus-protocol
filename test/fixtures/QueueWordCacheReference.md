# Queue drain differential reference

`contracts/mocks/QueueWordCacheReference.hex` contains the deployed FoilPack runtime for the packed queue without the input-word cache. `QueueWordCacheReference.sol.txt` preserves that implementation's source. It uses the same combined registry/owed record and lane codec as the candidate.

`test/fuzz/QueueWordCache.t.sol` pins the runtime hash, overlays the reference and candidate at the same module address, and compares each drain's storage writes, event bytes, cursor, and deterministic work charge from an identical snapshot. The reference is a test fixture and is never deployed by protocol deployment scripts.

Compiler: Solidity 0.8.34, via IR, optimizer 1000, Osaka, Foundry address pins. The source is compiled at `contracts/modules/DegenerusGameFoilPackModule.sol` in an isolated copy of the queue-packing candidate. Reference compiler metadata and hash verification evidence are retained under `.planning/queue-packing/word-cache/`.

Reference runtime Keccak-256: `0x2392545ce73d2150008289f7384976ab4a3fc35164df362dae578383fcb22917`.

Keep this reference independent of the cached implementation; regenerating it from the candidate would invalidate the differential comparison.
