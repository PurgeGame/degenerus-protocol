# Adversarial VRF-Coordinator-Rotation Review — Degenerus Protocol spinal column (v67.0 phase 423 VRFSWAP)

You are an independent senior smart-contract auditor reviewing **honest-governance VRF coordinator rotation** on a real-money on-chain ETH game. Read-only. Subject = the **frozen `contracts/` working tree at commit `0bb7deca` / tree `4a67209a`** (clean — read files under `contracts/` directly; cite `file:line`). Assume **honest admin/governance — admin MALICE is out of scope, but rotation LIVENESS is fully in scope** (an honest admin must always be able to rotate the coordinator without bricking the game or corrupting the request↔word binding).

## The structure under test

The game's daily/mid-day words come from Chainlink VRF. If the coordinator/subscription must change (Chainlink migration, sub re-funding), governance calls `updateVrfCoordinatorAndSub` (HUB stub ~DegenerusGame:1776 → `DegenerusGameAdvanceModule.sol` ~:1755). VRF state: `vrfCoordinator` (slot 31), `vrfKeyHash` (slot 32), `vrfSubscriptionId` (slot 33), `vrfRequestId` (slot 4), `rngWordCurrent` (slot 3), `rngLockedFlag`/`rngRequestTime` (slot 0), `lootboxRngPacked.LR_MID_DAY` (slot 34), and the slot-5 co-resident `totalFlipReversals | lastVrfProcessedTimestamp`. `rawFulfillRandomWords` (~:1844) validates requestId + coordinator and splits daily/mid-day by `rngLockedFlag`; `_gameOverEntropy` (~:1337) is the VRF-dead fallback.

## CLAIMS (find any reachable counterexample)

### VRFSWAP-01 — Rotation holds every freeze-relevant variable consistent
`updateVrfCoordinatorAndSub` under honest governance: NO rotation branch strands the lock (`rngLockedFlag` left true with no way to fulfill), de-syncs `vrfRequestId` / `rngWordCurrent`, or leaves the daily word permanently unobtainable; an in-flight request at rotation time is either preserved or cleanly re-requested. Verify the rotation writes slots 31/32/33 atomically vs the in-flight `vrfRequestId` (slot 4); verify it re-issues the in-flight request (it intentionally preserves `totalFlipReversals` so nudges carry to the first post-swap word, ~:1786-1789) and routes by `LR_MID_DAY` / `rngLockedFlag` / `rngWordCurrent` correctly. If the module body can revert under a needed rotation while `rngLockedFlag` is set (below the grace threshold), recovery is blocked — verify it cannot.

### VRFSWAP-02 — Mid-day / mid-request / stalled / while-locked rotation cannot brick or corrupt the binding
A rotation performed at ANY point (mid-day, mid-request, stalled, while-locked) cannot brick liveness or corrupt the request↔word binding — the rotation + retry composition ALWAYS restores a path to a fulfilled word, and the CORRECT day binds it. Compose: rotate while a daily request is in flight; rotate while a mid-day lootbox request is in flight; rotate during a VRF stall (word never fulfilled); rotate then immediately advance/retry. For each, show a fulfilled word remains obtainable on the correct day and no index/day binds the wrong word.

### VRFSWAP-03 — rawFulfillRandomWords requestId/coordinator validation correct across a rotation
A stale (pre-rotation) coordinator or a stale requestId CANNOT write a word; the post-rotation coordinator's fulfillment lands on the intended day/index. Verify `rawFulfillRandomWords` (~:1844) rejects a stale requestId (~:1833 — note it silently returns, no revert; confirm that is safe, not a swallow that strands), and that a callback from the OLD coordinator after rotation is rejected. Verify the daily/mid-day split (`rngLockedFlag`) still routes correctly after slots 31/32/33 change.

## Priority hotspots
- **slot 5 co-residence** (`totalFlipReversals | lastVrfProcessedTimestamp`) — the corruption surface that crosses MIDRNG/VRFSWAP/CORRUPT; `reverseFlip:1826` masked RMW + the rotation's intentional non-reset of `totalFlipReversals`. Verify the carry-over is correct and cannot corrupt the timestamp or the post-swap word.
- `_gameOverEntropy` (~:1337) pre-subtracts `totalFlipReversals` to cancel a committer-steerable nudge (the VRF-dead fallback never set `rngLockedFlag`) — verify this fallback can't be reached in a way that double-counts or strands after a rotation.
- In-flight `vrfRequestId` (slot 4) atomicity vs the slot 31/32/33 write — a window where the old requestId is still live but the coordinator changed.
- The grace-threshold / 12h-14d recovery timers vs a rotation: can a rotation reset or skip a timer so recovery is blocked or premature?

## Output
For EACH of VRFSWAP-01..03 and each hotspot: verdict (**REAL / REFUTED / UNCERTAIN**), severity (**CATASTROPHE** for a rotation that permanently bricks liveness or lets a stale coordinator write a word; else HIGH/MED/LOW/INFO), `reachable` under honest governance (rotation liveness in scope; admin malice NOT), the concrete trigger if REAL, and reasoning with `file:line`. Default to REFUTED only when the rotation+retry composition provably restores a path to a fulfilled word for every rotation timing. Report any **newVectors**. Be concrete and skeptical.
