# Entry reveal baseline

`contracts/mocks/EntryRevealBaseline.hex` is the deployed FoilPack runtime from commit
`6d02e4bf` before the direct-reveal changes, built with the session's initial
`ContractAddresses.sol` pins, Solidity 0.8.34, via IR, optimizer 1000, Osaka.

Keccak-256: `0xbc93ffbe68b1d942cd336e84ec4c3c1681d763bf33449383cf657189014e9ce5`.

`test/gas/EntryRevealGas.t.sol` overlays this runtime at the same module address and
compares ordered storage writes and decoded player/trait inventory from identical
snapshots. Its high-budget cases isolate event cost from chunk-boundary changes;
its 650/1000-unit cases measure the changed chunk throughput separately. This fixture
retains the old event and old work charge deliberately and is not a deployment input.
