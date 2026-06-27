The solvency routing, 1-wei sentinel, once-fired latch, and chunk idempotency hold. One conditional known-word sizing path survives.

FINDINGS:

1. MEDIUM | contracts/modules/GameAfkingModule.sol:1170 | A skipped bonus can later fire against an already-public RNG word | A fulfilled request may leave `rngWordCurrent` public across a day rollover; `rngGate` then assigns that word to `processDay`, while an earlier `cl <= mp` skip leaves the bonus latch open and no pending box. An attacker can settle selected old redemption dust or use the presale box’s 20% sDGNRS credit before calling `advanceGame`, choosing the amount incorporated into `keccak256(word, SDGNRS, day, amount)` after learning the word. A material sDGNRS/DGNRS holder can execute only a favorable liquid ETH-spin outcome whose value exceeds batch and advance gas even at 50 gwei, without relying on FLIP liquidity.
