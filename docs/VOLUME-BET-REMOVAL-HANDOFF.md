# Consumer Handoff — The Ticket-Volume Parimutuel Is Removed

- **Status:** the removal is complete in source. Deployment, frontend and indexer work is owed.
- **Source baseline:** `.planning/PLAN-REMOVE-VOLUME-BET.md` (umbrella plan) and its slices 01–10.
- **Contract:** `DegenerusParimutuel`, at the same deterministic `ContractAddresses.PARIMUTUEL`.

## The one thing that decides everything below

**This is a fresh deployment. No volume position has ever existed on chain.** There is nothing to
refund, migrate, settle, or unwind, and no compatibility shim was left behind. A consumer that
queries a new deployment for a legacy volume position is asking about state that never existed —
the call reverts on an unknown selector rather than returning an empty position.

The growth market is untouched: same address, same selectors, same event topics, same fixed
1,000-FLIP stake, same eligibility, same quest ladder, same pushed settlement, same claim and batch
crank. **A consumer that only ever used growth needs no change beyond replacing the ABI.**

## Removed — seven methods

| Method | Selector |
|---|---|
| `VOLUME_BET_CREDIT()` | `0xa7f2de31` |
| `placeVolumeBet(address,bool)` | `0x65e372dd` |
| `volumeBetCredit()` | `0x9d59bf27` |
| `claimVolume(address,uint24[])` | `0x6ac5a3b5` |
| `claimVolumeRound(uint24,address[])` | `0x2e6b6f33` |
| `volumeMarketState(address,uint24)` | `0x520739bb` |
| `recordVolume(uint24,uint48)` | `0x6461c74a` |

## Removed — three events

| Event | Topic 0 |
|---|---|
| `VolumeBetPlaced(address,uint24,bool,uint256)` | `0xb256da398c4ed44de896917570681f2d47e0286f38253b3558d43de77105cf3c` |
| `VolumeBetClaimed(address,uint24,uint8,uint256)` | `0xd2d6f656c40e54ce22fa3351150754d677fa61a78b6b066e1105b5b9f4810aae` |
| `VolumeRoundSealed(uint24,uint48,uint48)` | `0x0655c621883298d79dfd9499016ff1f0e8215d2efc7661206c7f43e38269cde4` |

Also gone, with no replacement: the decaying 25→5 FLIP placement credit, the daily volume round and
its 22:57–00:00 UTC window, the void/refund rule for an unscoreable round, and the game's
in-progress ticket-volume counter (the top 48 bits of prize-pool slots 2 and 11, which are now two
full `uint128` halves).

## Retained — the complete growth surface

| Method | Selector |
|---|---|
| `QUEST_BASE()` | `0x9e4a23f2` |
| `STAKE()` | `0x125fdbbc` |
| `claim(address,uint24[])` | `0xfbdc1e8a` |
| `claimRound(uint24,address[])` | `0x30c194e5` |
| `marketState(address,uint24)` | `0xc1ca0ce7` |
| `placeBet(address,bool)` | `0xd7604ca3` |
| `recordGrowth(uint24,bool)` | `0xa126a091` |

| Event | Topic 0 |
|---|---|
| `BetPlaced(address,uint24,bool,uint256)` | `0x8e0aa1e952464967d9730a4e1121dc8ac73d06d1ac109c983c8da3a77598170b` |
| `BetClaimed(address,uint24,uint8,uint256)` | `0xfe51f04082426a2a3607b3158e84cf13b31ef5e3d39a6700d249479a916bfdd4` |
| `GrowthRoundSealed(uint24,bool)` | `0xca3ee902860d838642f9002bad6dfde77682e901e6c518ef99504d6d98b9f9a3` |

`recordGrowth` is GAME-only and stays a push: the level transition that banks the successor ratchet
entry latches the round's side into a write-once two-bit outcome and emits `GrowthRoundSealed`.
Claims read that bit.

## Who owns what

| Owner | Obligation |
|---|---|
| Deployment / release | Supply the final generated ABI from the completed tree before the next deployment. The ABI in this repository is the source of truth; this document is a summary of it, not a substitute. |
| Frontend | Remove every volume placement, view, claim and crank path plus its UI. Record completion in the frontend repository. |
| Indexer | Drop the three removed topics and any derived volume state; keep `GrowthRoundSealed` indexing. Record completion in the indexer repository. |

## Checklist

- [ ] Replace the generated `DegenerusParimutuel` ABI wholesale — do not hand-edit the old one.
- [ ] Remove volume placement builders (`placeVolumeBet`) and the credit quote (`volumeBetCredit`,
      `VOLUME_BET_CREDIT`).
- [ ] Remove volume view/claim/crank builders (`volumeMarketState`, `claimVolume`,
      `claimVolumeRound`).
- [ ] Remove `recordVolume` from any keeper or game-side integration; the daily freeze now makes no
      parimutuel call at all.
- [ ] Drop subscriptions to `VolumeBetPlaced`, `VolumeBetClaimed` and `VolumeRoundSealed`, and
      delete the derived volume series, benchmarks and void/refund state built from them.
- [ ] Remove volume betting windows, countdowns and credit-decay timers from the UI.
- [ ] Keep growth placement (`placeBet`), state (`marketState`), claim (`claim`), crank
      (`claimRound`) and `GrowthRoundSealed` indexing exactly as they are.
- [ ] Never query a new deployment for a legacy volume position — none exists.

## Verification

`node scripts/check-parimutuel-abi.js --handoff docs/VOLUME-BET-REMOVAL-HANDOFF.md` asserts that the
compiled contract exposes exactly the retained surface, that none of the removed surface came back,
and that this document still lists every signature and selector/topic on both sides. The gate and
this file share one canonical set of arrays, so they cannot drift apart silently.
