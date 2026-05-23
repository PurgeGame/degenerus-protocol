# Phase 314 `/contract-auditor` Adversarial Pass — v45.0 VRF-Rotation Fix + Consolidate-Forward Delta

```yaml
[invocation]
skill: /contract-auditor
mode: SEQUENTIAL_MAIN_CONTEXT
dispatch_timestamp: "2026-05-23T00:00:00Z"
runner: orchestrator-main-context
fallback_reason: null
charge_anchor: ".planning/phases/314-sweep-3-skill-adversarial-degenerette-audit-sweep/314-ADVERSARIAL-CHARGE.md"
```

```yaml
[skeptic-filter]
arm: per-skill self-filter
protocol: D-314-SKEPTIC-FILTER-01
discarded: []
note: "No (a)-only hard discards at the per-skill self-filter arm. Every probed hypothesis produced either a structural-protection-cited NEGATIVE-VERIFIED verdict or a SAFE_BY_DESIGN intentional-design citation. No FINDING_CANDIDATE rows produced; the (b)+(c) severity-downgrade arm is therefore inapplicable. Orchestrator integration-time re-application at Task 5 re-verifies against the union of all 3 skills."
```

---

## §0 Charge-frame re-anchor

This pass executes **SWP-01** (VRF-rotation fix red-team) + **SWP-02** (consolidated-delta composition) + the **DGAUD-01..04** degenerette audit FOLDED into `/contract-auditor` scope per D-05, verbatim per `314-ADVERSARIAL-CHARGE.md`:

> **SWP-01**: Red-team the VRF-rotation fix — rotation-spam / stuck-pending / double-request griefing, a new liveness-DoS, a new freeze violation, or a `wireVrf`-lock that breaks a legitimate ops path. *(The "wireVrf-lock" clause is STALE per D-04 — re-prove constructor-only-reachability instead.)*
> **SWP-02**: Composition pass across the consolidated delta surfaces — V-081 allocation/packing, jackpot pending-pool obligations, degenerette removal — any cross-surface composition attack or differential behaviour an attacker can game.

Mandated SWP-01 rows per CONTEXT D-01..D-04: wireVrf constructor-only RE-PROOF (D-04), rotation-spam SAFE_BY_DESIGN (D-03), LINK-funding SPOT-CHECK (D-01), daily/mid-day exclusivity (D-02). DGAUD bars per D-06/D-07/D-08.

**Subject HEAD:** post-`a303ae18` (VRF-rotation fix) + `9bcd582d` (V-081) + `6e5acd7e`/`f3e21064` (jackpot pending-pool) + `92b110bf` (degenerette). All file:line anchors grep-verified against source HEAD 2026-05-23.

---

## §1 Per-hypothesis disposition table

| Hypothesis-ID | Verdict | Severity tag | Evidence anchors | Reasoning summary |
| --- | --- | --- | --- | --- |
| **SWP-01.A** — wireVrf second-wire / post-deploy re-wire (D-04 constructor-only RE-PROOF) | SAFE_BY_DESIGN | N-A | `AdvanceModule.sol:498` (`wireVrf`), `:503` (ADMIN guard), `:506` (`_setVrfConfig`); tree-wide caller grep; `DegenerusAdmin.sol:445` (constructor) → `:458` (`gameAdmin.wireVrf(`); §9d.4 ADMA-01. | RE-PROVEN: `grep -rnE 'wireVrf\(' contracts/` yields exactly ONE call site — `DegenerusAdmin.sol:458`, inside the `DegenerusAdmin` constructor (`:445`). The other matches are an interface decl (`DegenerusAdmin.sol:109`, `IDegenerusGameModules.sol:22`) and a storage comment (`DegenerusGameStorage.sol:1587`) — neither is a call. ADMIN has no post-construction function that re-invokes `wireVrf`, and the `:503` `msg.sender != ContractAddresses.ADMIN` guard blocks every other caller. The init-only lock (SPEC D-03/VRF-04) was correctly OMITTED as dead code: `wireVrf` is constructor-only-reachable BY CONSTRUCTION + runtime-guarded. No "lock to break" exists (D-04). The "by construction" claim is now grep-re-proven per `feedback_verify_call_graph_against_source`, not asserted. |
| **SWP-01.B** — rotation-spam griefing (D-03) | SAFE_BY_DESIGN | N-A | `AdvanceModule.sol:1712` (`updateVrfCoordinatorAndSub`), `:1717` (ADMIN guard); `v45-vrf-freeze-invariant`; T-314-01. | `updateVrfCoordinatorAndSub` is ADMIN-only (`:1717` `msg.sender != ContractAddresses.ADMIN → revert`). Admin rotation is freeze-EXEMPT per the v45 freeze invariant. No player can reach the rotation entry point — player-driven rotation-spam is STRUCTURALLY IMPOSSIBLE. Recorded as an explicit SAFE_BY_DESIGN row per the enumerate-everything precedent (D-03), NOT dropped. |
| **SWP-01.C** — LINK-funding order (re-issue fires before LINK lands) (D-01 SPOT-CHECK) | SAFE_BY_DESIGN | N-A | `DegenerusAdmin.sol:859` (`_executeSwap`), `:886-888` (createSubscription), `:894` (addConsumer GAME), `:901` (dispatch `updateVrfCoordinatorAndSub` → re-issue), `:911` (`transferAndCall` same-tx LINK), `:909` (`if (bal != 0)`); `AdvanceModule.sol:1131` (`retryLootboxRng` failsafe), `:1722-1725` (diff rationale comment). | SPOT-CHECK (NOT a deep trace, per D-01): `_executeSwap` orders create-sub (`:886`) → addConsumer GAME (`:894`) → dispatch the re-issue `requestRandomWords` on the new coordinator (`:901`) → `transferAndCall` LINK to the new sub (`:911`) — ALL in the same transaction. VRF V2.5 accepts a `requestRandomWords` from an added consumer and checks funding at NODE FULFILLMENT time (a later block); the same-tx `transferAndCall` ensures the sub is funded before any fulfillment attempt. The documented rationale (`:1722-1725`) carries it; `retryLootboxRng` (`:1131`, permissionless, timeout+LINK-gated) is the standing failsafe if the new coordinator stalls. SAFE_BY_DESIGN. (The `:909 if (bal != 0)` zero-LINK skip is an operational concern — admin must hold LINK — not a player-exploitable vector.) |
| **SWP-01.D** — daily/mid-day exclusivity: both flags set → daily word silently dropped → permanent post-rotation freeze? (D-02 standalone row) | NEGATIVE-VERIFIED | N-A | `AdvanceModule.sol:1726` (mid-day-wins branch), `:1731-1740` (daily branch), `:1043` (`rngLockedFlag` guard), `:1046` (LR_MID_DAY guard), `:1052` (pre-reset window), `:1054` (daily-consumed guard), `:1056` (rngRequestTime guard), `:209-214` (advance waits for mid-day word), `:225` (advance clears LR_MID_DAY). | D-02 discretion exercised: traced ALL `LR_MID_DAY` / `rngLockedFlag` set-clear sites → standalone row warranted. Exclusivity is DOUBLE-enforced: (1) the mid-day request `requestLootboxRng` reverts if `rngLockedFlag` set (`:1043`), if a mid-day is already pending (`:1046`), inside the 15-min pre-reset window (`:1052`), and until today's daily word is consumed (`:1054`) — mid-day cannot START while daily is locked; (2) the advance flow, if `LR_MID_DAY` is set, WAITS for the mid-day word (`:209-214 revert RngNotReady` if absent) and processes+clears `LR_MID_DAY` (`:225`) BEFORE the daily RNG lock — daily cannot lock while a mid-day is pending. The both-set state is unreachable; the `:1726` mid-day-wins rotation precedence is defensive ordering for a designed-impossible case. No silent daily-drop, no permanent freeze. (VER-03 resolved at Phase 312 IMPL, VTST-covered at Phase 313.) |
| **SWP-01.E** — stuck-pending / double-request / freeze re-break via the rawFulfill guard | NEGATIVE-VERIFIED | N-A | `AdvanceModule.sol:1788` (`rawFulfillRandomWords`), `:1792` (coordinator-only), `:1793` (`requestId != vrfRequestId \|\| rngWordCurrent != 0 → return`), `:1729`/`:1735` (rotation sets fresh `vrfRequestId`), `:1801-1808` (mid-day finalize); `v45-vrf-freeze-invariant`. | The rotation re-issue sets a FRESH `vrfRequestId` (`:1729` mid-day / `:1735` daily). A stale (pre-rotation) callback from the OLD coordinator carries the OLD requestId → `requestId != vrfRequestId` → inert `return` (`:1793`). A duplicate/late callback after the word landed → `rngWordCurrent != 0` → inert `return`. The consumed-this-cycle word is therefore ALWAYS the fresh re-issued one; the old word is abandoned. No double-request consumption, no stuck-pending (the re-issue replaces the in-flight request), no freeze re-break. Coordinator-only (`:1792`) blocks spoofed callbacks. NEGATIVE-VERIFIED. |
| **SWP-01.F** — orphan-index backfill correctness (the v45 headline fix) | NEGATIVE-VERIFIED | N-A | `AdvanceModule.sol:1849` (`_backfillOrphanedLootboxIndices`), `:1854-1867` (backward scan + keccak fallback), `:1727-1728` (rotation preserves LR_INDEX), `:1654-1664` (`_finalizeRngRequest` fresh-vs-retry index advance). | The orphan-index closure: `_backfillOrphanedLootboxIndices` scans backward from the most-recent reserved index, filling any zero (orphaned) `lootboxRngWordByIndex[i]` with `keccak256(vrfWord, i)` derived from the FRESH daily VRF word (`:1857-1861`) — non-player-controllable entropy, distinct per index. The rotation re-issue preserves `LR_INDEX` (`:1727` "LR_INDEX preserved so the new word lands in the same reserved slot") and does NOT advance it (it sets `vrfRequestId` directly, not via `_finalizeRngRequest`), so the in-flight reserved index is not orphaned by the rotation itself. Backfill derives entropy from the fresh word — no 0-entropy traits. NEGATIVE-VERIFIED. |
| **SWP-02.V081** — EV-cap packing-collision + order-independence / penalty-dodge | NEGATIVE-VERIFIED | N-A | `Storage.sol:1387` (`_packLootboxPurchase`), `:1396` (`_unpackLootboxPurchase`), `:1442` (`lootboxPurchasePacked`), `:1491` (`lootboxEvBenefitUsedByLevel`); `LootboxModule.sol:433` (`_applyEvMultiplierWithCap`), `:442` (bonus-only early-return), `:458` (`adjustedPortion = min(amount,remainingCap)`), `:462` (cap advance), `:477` (`openLootBox`), `:504-505` (frozen-snapshot SLOAD), `:524-526` (frozen apply), `:533` (whole-word zero). | Packing: `_packLootboxPurchase` lays scorePlus1[0:16] + adj[16:80] + baseLevelPlus1[80:104] = 104 bits in one word, each field `&`-masked then `<<`-shifted to disjoint ranges; `_unpackLootboxPurchase` is the exact inverse. No field overlap, no spill — compiler-managed, no manual asm. Order-independence: the per-(player,level) EV-benefit cap (`lootboxEvBenefitUsedByLevel`, 10 ETH) is drawn ONCE at DEPOSIT (`:462`) and the eligible `adjustedPortion` FROZEN into `lootboxPurchasePacked`; `openLootBox` reads the frozen `adj` and applies the multiplier with NO cap re-draw (`:524-526`, "the cap was drawn at deposit"). Deposit order cannot extract more than the 10-ETH cap (monotonic accumulation, capped); open order is irrelevant (frozen apply). Penalty/neutral boxes early-return on full amount (`:442`). No EV-positive ordering. NEGATIVE-VERIFIED. |
| **SWP-02.JACKPOT** — pending-pool over-distribution / solvency (`6e5acd7e` + `f3e21064`) | NEGATIVE-VERIFIED | N-A | `JackpotModule.sol:732` (`distributeYieldSurplus`), `:735-739` (live-pool obligations), `:746-747` (`_getPendingPools()` → `obligations += pNext + pFuture`), `:749` (`totalBal <= obligations → return`), `:751` (`yieldPool = totalBal - obligations`). | The fix adds the freeze-window pending buffer (`prizePoolPendingPacked`, read via `_getPendingPools()`) to `obligations` (`:746-747`) BEFORE computing the distributable surplus. Pending ETH — a live liability sitting in balance during the freeze window — is therefore no longer misread as yield surplus and over-distributed. `_getPendingPools` reads 0 when not frozen, so no double-count after `_unfreezePool` folds the buffer back into the live pools. `yieldPool` is the strict balance-minus-all-obligations surplus; `totalBal <= obligations` short-circuits to no distribution. Solvency preserved. NEGATIVE-VERIFIED. |
| **SWP-02.DEGEN** — degenerette-removal cross-surface composition (`92b110bf`) | NEGATIVE-VERIFIED | N-A | `DegeneretteModule.sol:480` (emit BetPlaced — unchanged), `:489-497` (dailyHeroWagers — de-indented only); `git show 92b110bf`. | The refactor removed only the per-bet `playerDegeneretteEthWagered`/`topDegeneretteByLevel` SSTOREs + their views. `dailyHeroWagers` (the Jackpot RNG hero-override input) and `degeneretteBets[player][nonce]` writes + the `BetPlaced` emit are untouched (only de-indented). The removed mappings had NO readers outside the deleted views (dangling-ref grep ZERO). No cross-surface composition with V-081 or jackpot pending-pool (disjoint storage + disjoint code paths). NEGATIVE-VERIFIED. (Full DGAUD detail in §2.) |

**SWP summary:** 9 disposition rows — 6 NEGATIVE-VERIFIED + 3 SAFE_BY_DESIGN (SWP-01.A wireVrf, SWP-01.B rotation-spam, SWP-01.C LINK-order) + 0 FINDING_CANDIDATE + 0 self-discards.

---

## §2 Degenerette Refactor Audit (DGAUD-01..04) — the D-05 fold

Dedicated section per D-05 (degenerette coverage lives HERE + in the LOG §4, NOT a separate note file).

| Hypothesis-ID | Verdict | Severity tag | Evidence anchors | Reasoning summary |
| --- | --- | --- | --- | --- |
| **DGAUD-01** — storage-slot shift safe + recompile clean (D-08 deterministic) | NEGATIVE-VERIFIED | N-A | `forge build` exit 0; `grep -rnE "playerDegeneretteEthWagered\|topDegeneretteByLevel\|getPlayerDegeneretteWager\|getTopDegenerette" contracts/` → ZERO; `git show 92b110bf --stat` (Storage.sol −12 lines, Game.sol −23, IDegenerusGame.sol −4). | `forge build` recompiles CLEAN (exit 0; the only forge-output is a `forge-lint` *advisory* on an unrelated uint32 cast — not a compile error). The two removed mappings (`playerDegeneretteEthWagered`, `topDegeneretteByLevel`) + the two removed views were APPEND-ordered storage (declared after the retained slots), so their removal does not shift any retained slot's offset in a pre-deploy redeploy-fresh posture (`feedback_frozen_contracts_no_future_proofing`). Dangling-ref grep ZERO confirms no retained code references the removed slots. NEGATIVE-VERIFIED (deterministic, D-08). |
| **DGAUD-02** — `dailyHeroWagers` write-path BEHAVIORAL identity (D-07, NOT literal bytes) | NEGATIVE-VERIFIED | N-A | `git show 92b110bf -- contracts/modules/DegenerusGameDegeneretteModule.sol`; `DegeneretteModule.sol:489` (read), `:497` (write). | The `92b110bf` diff shows the `dailyHeroWagers` computation is BEHAVIORALLY IDENTICAL: `day = _simulatedDayIndex()`, `heroSymbol = uint8(customTicket >> (heroQuadrant*8)) & 7`, `wagerUnit = totalBet / 1e12`, `if (wagerUnit > 0) { shift = heroSymbol*32; current = (wPacked>>shift)&0xFFFFFFFF; updated = min(current+wagerUnit, 0xFFFFFFFF); wPacked = (wPacked & ~mask) | (updated<<shift); dailyHeroWagers[day][heroQuadrant] = wPacked; }` — every line preserved. The ONLY changes are (a) removal of the enclosing `{ }` scope braces (one de-indent level) and (b) deletion of the sibling per-player/per-level block that followed it. This is exactly the whitespace + scope-brace removal D-07 anticipated; literal byte-identity would spuriously "fail" but SEMANTIC/BEHAVIORAL identity holds. NEGATIVE-VERIFIED (D-07). |
| **DGAUD-03** — no dangling refs + `BetPlaced` off-chain reconstruction VIABLE-IN-PRINCIPLE (D-06) | SAFE_BY_DESIGN | N-A | Dangling-ref grep ZERO; `DegeneretteModule.sol:69` (`BetPlaced(address indexed player, uint32 indexed index, uint64 indexed betId, uint256 packed)`), `:480` (emit on every ETH bet path); `Storage.sol:1475` (packed layout — amountPerTicket uint128 @ bit 44). | Dangling-ref grep ZERO (no references in `contracts/` or interfaces to the removed mappings/views). `BetPlaced` still fires on EVERY ETH bet path (`:480`) carrying `player` (indexed) + `packed` (which holds `amountPerTicket` uint128 + ticketCount → the wager amount). Off-chain leaderboard reconstruction is therefore VIABLE-IN-PRINCIPLE. The removed `topDegeneretteByLevel` was keyed by GAME LEVEL; the event carries the lootbox-RNG `index` (uint32), NOT `level` — so the index→level derivation is required off-chain. Per D-06, this is the user's ACCEPTED off-chain-indexer convention, NOT a defect — explicitly NOT escalated to FINDING_CANDIDATE. SAFE_BY_DESIGN (accepted convention). |
| **DGAUD-04** — re-verify HANDOFF-01/02/03 + 18 + 81 + 82 (D-08 carry-forward) | NEGATIVE-VERIFIED | N-A | `audit/FINDINGS-v44.0.md` §9d; `DegeneretteModule.sol:489-497` (dailyHeroWagers untouched), `:479` (`degeneretteBets[player][nonce]` write retained); `JackpotModule.sol:746-747` (prizePoolPendingPacked). | The refactor surface (removed `playerDegeneretteEthWagered`/`topDegeneretteByLevel`) does NOT intersect the DGAUD-04 anchors: HANDOFF-01/02/03 (S-02 `dailyHeroWagers`) — `dailyHeroWagers` untouched (de-indent only); HANDOFF-18 (V-031 prizePool degenerette-bet) — prizePool accounting untouched; HANDOFF-81 (V-142 `degeneretteBets`) — `degeneretteBets[player][nonce] = packed` still present (`:479`); HANDOFF-82 (V-147 `prizePoolPendingPacked` frozen-branch) — untouched. All four dispositions CARRY FORWARD unchanged. NEGATIVE-VERIFIED (D-08). |

**DGAUD summary:** 4 disposition rows — 3 NEGATIVE-VERIFIED + 1 SAFE_BY_DESIGN (DGAUD-03 accepted convention) + 0 FINDING_CANDIDATE.

---

## §3 Skeptic-Filter Self-Discarded subsection

**No self-discards.** Every probed hypothesis produced a concrete NEGATIVE-VERIFIED verdict (structural-protection cited) or a SAFE_BY_DESIGN verdict (intentional-design cited). The (a)-only hard-discard arm had no FINDING_CANDIDATE inputs; the (b)+(c) severity-downgrade arm is inapplicable. Orchestrator integration-time re-application at Task 5 re-verifies.

| Hypothesis-ID | Source skill | Structural-protection citation (file:line) | EV-lens failed condition | Note |
| --- | --- | --- | --- | --- |
| (none) | /contract-auditor | n/a | n/a | No FINDING_CANDIDATE produced; nothing to discard. |

---

## §4 Cross-skill hand-off notes (anchors hunter + economist; keeps coverage divergent)

### Hand-off to `/zero-day-hunter` (SWP-01-novel + SWP-02-novel surfaces)

- **Rotation-between-`_requestVrfWord`-and-`rawFulfillRandomWords` timing window:** The auditor confirmed the `:1793` guard abandons stale words and the SWP-01.D exclusivity is structurally enforced. The HUNTER should probe whether any player-controllable state mutation between the re-issue (`:1729`/`:1735`) and the fresh callback can change a VRF-derived output (per `feedback_rng_commitment_window`) — e.g., does `totalFlipReversals` (consumed in `_applyDailyRng` `:1875`, NOT reset on rotation per `:1743-1746`) create a nudge-grind surface across a rotation boundary?
- **Cross-module reads of `lootboxRngWordByIndex` / `lootboxPurchasePacked`:** AdvanceModule writes `lootboxRngWordByIndex` (`:1804`, `:1861`); LootboxModule `openLootBox` reads it (`:484`). Hunter should probe a read/write race or a backfill-vs-mid-day-fulfill interleave on the same index.
- **Backfill `keccak(vrfWord, i)` collision/foreknowledge:** The backfill word is `keccak256(vrfWord, i)`. Hunter should confirm no index `i` lets a player foreknow or grind the fallback word (vrfWord is the fresh daily VRF word, unknown at deposit; index is monotonic).

### Hand-off to `/economic-analyst` (SWP-02-economic + beyond-charge MEV/game-theory)

- **V-081 EV-cap EV-positive ordering:** The auditor proved order-independence structurally (cap drawn+frozen at deposit). The ECONOMIST should probe whether the activity-score snapshot (`scorePlus1` frozen at deposit, `:520`) interacts with deposit timing to let a player time deposits at a high-activity-score moment for a frozen-in bonus — and whether that is an INTENDED engagement mechanic vs a gameable edge.
- **Jackpot pending-pool distribution game-theory:** The auditor proved obligations now include the pending buffer. Economist should probe whether a coordinated actor can time freeze-window revenue to influence the `yieldPool` surplus split (23/23/23) — or whether the `_getPendingPools` 0-when-not-frozen read closes that.
- **VRF-rotation MEV:** Rotation is ADMIN-only (`:1717`); the roll is VRF-derived (no mempool visibility). Economist should confirm there is no backrun/sandwich on a rotation tx that an MEV builder can extract, bounded by the `:1793` guard + ADMIN gate.

### Auditor residual concerns

- **None promoted to FINDING_CANDIDATE.** All probed hypotheses produced concrete NEGATIVE-VERIFIED / SAFE_BY_DESIGN verdicts with structural citations.
- **Informational (NOT a finding):** Internal NatSpec comments at `AdvanceModule.sol:1728`/`:1739` reference stale line-refs `:1761`/`:1772` for the rawFulfill guard / mid-day branch; the live guard is `:1793` and the mid-day finalize branch is `:1801`. Cosmetic comment doc-drift in already-landed frozen code, ZERO behavioral impact — recorded for the trail, not escalated.

---

## §5 Summary

| Bucket | Count |
| --- | --- |
| Hypotheses charged (SWP) | 9 (SWP-01.A..F + SWP-02.V081/JACKPOT/DEGEN) |
| DGAUD rows (D-05 fold) | 4 (DGAUD-01..04) |
| Total disposition rows | 13 |
| NEGATIVE-VERIFIED | 9 |
| SAFE_BY_DESIGN | 4 (SWP-01.A wireVrf, SWP-01.B rotation-spam, SWP-01.C LINK-order, DGAUD-03 off-chain convention) |
| FINDING_CANDIDATE | 0 |
| Skeptic-filter self-discards | 0 |
| Severity downgrades | 0 (no findings to downgrade) |

**Verdict:** `/contract-auditor` SEQUENTIAL_MAIN_CONTEXT pass produces **0 FINDING_CANDIDATE** rows. The genuinely-new VRF re-issue surface (`a303ae18`) is structurally sound: wireVrf is constructor-only-reachable (re-proven, D-04), rotation is ADMIN-gated + freeze-exempt (D-03), LINK funds same-tx (D-01), daily/mid-day exclusivity is double-enforced (D-02), the `:1793` guard abandons stale words (freeze-invariant intact under rotation), and orphan indices backfill from fresh entropy. The consolidated deltas (V-081 packing + frozen-cap, jackpot pending-pool obligations, degenerette removal) all NEGATIVE-VERIFIED. DGAUD-01..04: recompile-clean + dangling-ref-ZERO + dailyHeroWagers behavioral-identity + HANDOFF carry-forward. Cross-skill hand-off rows in §4 route the novel-attack-surface + game-theoretic lenses to `/zero-day-hunter` + `/economic-analyst`.

---

*Phase 314 / Plan 01 / Task 2 / `/contract-auditor` SEQUENTIAL_MAIN_CONTEXT / 2026-05-23.*
