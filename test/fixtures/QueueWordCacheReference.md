# Queue drain differential reference

`contracts/mocks/QueueWordCacheReference.hex` contains the deployed FoilPack runtime for the packed queue without the input-word cache. `QueueWordCacheReference.sol.txt` preserves that implementation's source. It uses the same combined registry/owed record and lane codec as the candidate.

`test/fuzz/QueueWordCache.t.sol` pins the runtime hash, overlays the reference and candidate at the same module address, and compares each drain's storage writes, event bytes, cursor, and deterministic work charge from an identical snapshot. The reference is a test fixture and is never deployed by protocol deployment scripts.

Compiler: Solidity 0.8.34, via IR, optimizer 1000, Osaka, Foundry address pins. The source is compiled at `contracts/modules/DegenerusGameFoilPackModule.sol` in an isolated copy of the queue-packing candidate. Reference compiler metadata and hash verification evidence are retained under `.planning/queue-packing/word-cache/`.

Reference runtime Keccak-256: `0x5a6a7e70f0c61accb0ac17b9d3698408b2a40be2dc2d09f7c7e197c25c6fd76f`.

Run #53 refresh: changed only the independent reference's old round emit to the direct
`EntryTraitsRevealed` emitter and its per-round compute charge from 3 to 4, then rebuilt
against the appended generation-window slot and updated round reserve. The uncached
queue-read implementation remains unchanged. This keeps the differential test about
queue caching while comparing the same reveal format and budget on both sides.

Keep this reference independent of the cached implementation; regenerating it from the candidate would invalidate the differential comparison.
