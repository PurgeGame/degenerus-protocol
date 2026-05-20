# Phase 307 `/contract-auditor` Adversarial Pass — v44.0 sStonk Per-Day Redemption Refactor

```yaml
[invocation]
skill: /contract-auditor
mode: SEQUENTIAL_MAIN_CONTEXT
dispatch_timestamp: "2026-05-19T16:30:00Z"
runner: orchestrator-main-context
fallback_reason: null
charge_anchor: ".planning/phases/307-adversarial-sweep-sweep/307-ADVERSARIAL-CHARGE.md"
```

```yaml
[skeptic-filter]
arm: per-skill self-filter
protocol: D-307-SKEPTIC-FILTER-01
discarded: []
note: "No (a)-only hard discards at per-skill self-filter arm. All probed hypotheses produced either a structural-protection-cited NEGATIVE-VERIFIED verdict or a SAFE_BY_DESIGN intentional-design citation. No FINDING_CANDIDATE rows produced; (b)+(c) downgrade arm therefore inapplicable. Orchestrator integration-time re-application at Task 5 will re-verify."
```

---

## §0 Charge-frame re-anchor

This pass executes **SWP-01** verbatim per `307-ADVERSARIAL-CHARGE.md` §1:

> `/contract-auditor` SEQUENTIAL_MAIN_CONTEXT pass. Charge: find any state transition that violates INV-01..12; any (burn, advance, claim, gameOver) interleaving that produces an exploitable outcome; any storage-collision or packing bug in the new layout.

INV-13 (Phase 305 emergent invariant per D-305-SENTINEL-01) treated as first-class per CHARGE §1 SWP-01 note. Charge scope extends to INV-01..13.

Plus the 5 v44-specific augments per `307-ADVERSARIAL-CHARGE.md` §2:
- **Augment (i)** — 1-slot DayPending packing edges (D-305-STRUCT-TIGHTEN-01).
- **Augment (ii)** — `pendingResolveDay` sentinel race/collision (D-305-SENTINEL-01 + INV-13).
- **Augment (iii)** — gwei-snap × cap arithmetic precision (D-305-GWEI-SNAP-01 + INV-11).
- **Augment (iv)** — Phase 306 INV harness perturbation-class gaps (auditor scope: state-transition / storage / packing arms only; SWP-02/SWP-03 arms deferred to hunter/economist per D-307-DISPATCH-01 cross-skill divergence).
- **Augment (v)** — Vault scope-expansion ACL surface (`DegenerusVault.sdgnrsClaimRedemption`).

---

## §1 Per-hypothesis disposition table

| Hypothesis-ID | Verdict | Severity tag | Evidence anchors | Reasoning summary |
| --- | --- | --- | --- | --- |
| **SWP-01.INV-01** (`redemptionPeriods[D].roll` write-once-never-mutated) | NEGATIVE-VERIFIED | N-A | `StakedDegenerusStonk.sol:633-666` (`resolveRedemptionPeriod` — only writer of `redemptionPeriods[dayToResolve]`); `:641` early-return on empty pool; `:654` write; `:662` `delete pendingByDay[dayToResolve]`. INV-01 (SPEC §3.A). | Single writer + early-return-on-zero-pool + delete-after-resolve structurally enforces single-write. A second call for the same `dayToResolve` reads the deleted pool (ethBase==0 && burnieBase==0), returns early at `:641`, never reaches the write at `:654`. INV-01 holds. |
| **SWP-01.INV-02** (ETH conservation) | NEGATIVE-VERIFIED | N-A | `StakedDegenerusStonk.sol:874` (`pendingRedemptionEthValue += ethValueOwed`); `:645` (decrement at resolve); `:713` (decrement at claim); `:858-861` (gwei snap); `:875` (per-day pool gwei segregation). INV-02 (SPEC §3.A). | Cumulative `pendingRedemptionEthValue` increments by gwei-snapped per-claim values; decrements by exact same gwei-snapped values at resolve (`:645` reads `pool.ethBase × 1e9` which is byte-exact equal to sum of post-snap claim values per augment (i) reasoning). Per-claim payout dust ≤99 wei from `× roll / 100` at `:688` floor-div is within INV-02 tolerance. PROVEN by `test/invariant/RedemptionAccounting.t.sol invariant_INV_02_*` at 256k+ calls. |
| **SWP-01.INV-03** (BURNIE conservation) | NEGATIVE-VERIFIED | N-A | `:876-877` (cumulative + per-day pool); `:651` (release at resolve, NOT claim — preserves v43-era semantics); `:732-734` (claim-side BURNIE payout). | BURNIE reservation released at resolve (`:651`) BEFORE claim, matching SPEC-04 semantics. Pool-side decrement matches the per-day burnieBase × 1e9 reconstruction. PROVEN at Phase 306. |
| **SWP-01.INV-04** (per-day base correctness) | NEGATIVE-VERIFIED | N-A | `:823` (`pool = pendingByDay[currentPeriod]`); `:875` (`pool.ethBase += uint64(ethValueOwed / 1e9)`); `:880` (composite-key claim slot `pendingRedemptions[beneficiary][currentPeriod]`); `:885` (`claim.ethValueOwed += uint96(ethValueOwed)`). | Both pool.ethBase and the sum-of-(player, day)-claim values are populated with the same post-snapped `ethValueOwed` (multiple of 1e9). `pool.ethBase × 1e9` = sum-of-claim-ethValueOwed for the day. PROVEN at Phase 306. |
| **SWP-01.INV-05** (cumulative correctness) | NEGATIVE-VERIFIED | N-A | `:257` (`pendingRedemptionEthValue`); `:874` (increment on burn); `:645` (decrement on resolve); `:713` (decrement on claim). | Accounting is closed: increment-on-burn matches the (per-claim or pool-side) sum; decrement-on-resolve matches the pool-side pre-roll sum; decrement-on-claim matches the rolled per-claim value. PROVEN at Phase 306. |
| **SWP-01.INV-06** (no cross-player roll manipulation) | NEGATIVE-VERIFIED | N-A | `:633-666` (`resolveRedemptionPeriod` written only by AdvanceModule via `onlyGame`-equivalent caller check at `:634`); `:680-683` (claim-side reads `period.roll` — immutable post-resolve per INV-01). | Roll is set by AdvanceModule's VRF-derived `redemptionRoll` (`AdvanceModule.sol:1230-1232`) — no player-controllable input. Claim reads stored roll; cannot mutate. PROVEN at Phase 306 V-184 strict-byte-identity assertion. |
| **SWP-01.INV-07** (no self-roll manipulation via timing) | NEGATIVE-VERIFIED | N-A | `:880, :885-887` (composite-key per-(player, day) ethValueOwed locked at burn time); `:688` (claim reads `claim.ethValueOwed`). | `claim.ethValueOwed` is written at burn-time + composite-keyed by `(beneficiary, currentPeriod)`. No code path mutates it post-burn except claim itself (`delete` at `:717` or zero-out at `:720`). PROVEN at Phase 306. |
| **SWP-01.INV-08** (pre-advance-gap burn safety) | NEGATIVE-VERIFIED | N-A | `:814` (`currentPeriod = game.currentDayView()` — day reads wall clock, not "last-advanced day"); `:823` (pool indexed by currentPeriod); `:1227-1235, :1289-1301, :1320-1334` (AdvanceModule reads `pendingResolveDay()` sentinel — does NOT touch today's pool). | Burns on day D land in `pendingByDay[D]` regardless of whether day-D's advance has fired; day-D's advance resolves the sentinel-named day (which is D-1 or earlier, NOT D itself). EDGE-01 PROVEN at Phase 306. |
| **SWP-01.INV-09** (skipped-advance recovery) | NEGATIVE-VERIFIED | N-A | `:269` sentinel — single value, names at-most-one unresolved day; `:820` revert prevents multi-day-pool accumulation. AdvanceModule resolves sentinel-named day on the next successful advance. EDGE-06 PROVEN at Phase 306. | Multi-day stalls produce at most one unresolved pool (sentinel-stamped); subsequent advance/gameOver entropy resolves exactly that day. No bypass; no overwrite. |
| **SWP-01.INV-10** (per-day supply cap) | NEGATIVE-VERIFIED | N-A | `:828-830` (lazy-init `pool.supplySnapshot = uint64(totalSupply / 1e18)` on first burn of day); `:832-836` (ceiling-divide amount→whole + cap check vs `supplySnapshot / 2`). | supplySnapshot frozen at first burn of day (whole-token units, uint64 holds 1.84e19 vs max realistic 1e12 — 1.84e7× headroom). Cap check ceiling-rounds amount → conservative against cap. INV-10 STRUCTURALLY ENFORCED. EDGE-14 PROVEN at Phase 306. |
| **SWP-01.INV-11** (per-(player, day) EV cap) | NEGATIVE-VERIFIED | N-A | `:292` (`MAX_DAILY_REDEMPTION_EV = 160 ether`); `:883` (cap check `claim.ethValueOwed + ethValueOwed > MAX_DAILY_REDEMPTION_EV` reverts `ExceedsDailyRedemptionCap`). | Cap is read against the composite-key claim slot; per-(player, day) cap resets on a new day (different `currentPeriod` → different slot). Snap to gwei at `:858-861` does NOT permit exceeding cap (cap check uses post-snap value). EDGE-15 + EDGE-16 PROVEN at Phase 306. |
| **SWP-01.INV-12** (gameOver mid-pending safety) | NEGATIVE-VERIFIED | N-A | `_gameOverEntropy` paths at `AdvanceModule.sol:1269-1353` (3 sub-paths: rngWord-current, fallback-after-3-day-delay, request-retry) — all read `pendingResolveDay()` + call `resolveRedemptionPeriod` if stamped; `:691-699` (claim reads `game.gameOver()` — post-gameOver pays 100% direct ETH); `:715-721` (partial-claim BURNIE branch). | gameOver path resolves any stamped pool via fallback word OR current word. If gameOver fires before sentinel was set (sentinel == 0), there's no pool to resolve. If gameOver fires after sentinel + before resolve, the gameOver entropy path covers it. EDGE-08 PROVEN at Phase 306. |
| **SWP-01.INV-13** (single-pool invariant, sentinel-enforced) | NEGATIVE-VERIFIED | N-A | `:269, :819-821, :665` (sentinel write + read + revert + clear); `:1228, 1294, 1327` (AdvanceModule readers). | Burn at `:820` reverts `PriorDayUnresolved` if a prior day's sentinel is non-zero AND not equal to currentPeriod. Sentinel cleared at `:665` on resolve. STRUCTURAL: at-most-one unresolved pool exists at any time. PROVEN at Phase 306 (INV-13 added to harness). |
| **SWP-01.PACKING** (storage collision / packing in v44 layout) | NEGATIVE-VERIFIED | N-A | `:247-252` (`struct DayPending { uint64 ethBase; uint64 burnieBase; uint64 supplySnapshot; uint64 burned; }`). | 4 × uint64 = 256 bits = exactly 1 slot. Compiler-managed packing (NO manual bit-shift / inline-asm). Solidity `+=` on a packed field generates SHL/SHR/AND-mask sequences that cannot spill into adjacent fields (compiler responsibility). `pool.burned += uint64(amountWhole)` is bounded by INV-10's cap check (`:835`) so the uint64 cannot overflow either. Compile-time + runtime safety. |
| **SWP-01.INTERLEAVING-BURN-ADVANCE** (burn-advance race) | NEGATIVE-VERIFIED | N-A | Above traces for INV-08, INV-09, INV-13. | A burn on day D lands in `pendingByDay[D]` regardless of advance-state. Day-D's advance resolves the sentinel-named (D-1 or earlier) day, not D itself. No race. |
| **SWP-01.INTERLEAVING-ADVANCE-CLAIM** (advance-claim race) | NEGATIVE-VERIFIED | N-A | `:681` (claim reverts `NotResolved` if `period.roll == 0`); `:654` (advance writes roll). | Claim-before-advance reverts; claim-after-advance reads stable post-write roll. Sequential semantics. EDGE-05 PROVEN at Phase 306. |
| **SWP-01.INTERLEAVING-CLAIM-CLAIM** (multi-day claim ordering) | NEGATIVE-VERIFIED | N-A | `:677` (claim reads composite key `pendingRedemptions[player][day]`); `:717` (`delete pendingRedemptions[player][day]` post-full-claim). | Composite-keyed per-day slot. Two distinct days = two distinct slots. Each claim mutates only its own slot. EDGE-03 PROVEN at Phase 306. |
| **SWP-01.INTERLEAVING-GAMEOVER-CLAIM** (gameOver mid-claim) | NEGATIVE-VERIFIED | N-A | `:691-699` (claim reads `game.gameOver()` once at start of claim); CEI ordering — state mutation at `:713, :717, :720` precedes external calls at `:728, :733, :739`. | Mid-claim gameOver flip cannot affect the in-progress claim (gameOver read once). Future claims after gameOver pay 100% direct ETH. EDGE-08 PROVEN at Phase 306. |
| **Augment (i)** — DayPending 1-slot packing edges | NEGATIVE-VERIFIED | N-A | `:247-252` (struct); `:639-640` (gwei→wei reconstruction at resolve); `:858-861` (snap); `:875` (per-day pool increment); `:828-830` (lazy-init snapshot). | uint64 overflow: worst-case ethBase = 1.6e15 gwei (10k wallets × 160 ETH cap); uint64.max = 1.84e19; headroom ~11500×. Worst-case supplySnapshot = 1e12 whole tokens; uint64.max headroom ~1.84e7×. uint64 packing is compiler-managed in a single struct — no manual bit-shift means no cross-field corruption. Gwei↔wei reconstruction is byte-exact: every per-claim `ethValueOwed` is pre-snapped to multiple of 1e9 → `pool.ethBase × 1e9` byte-equals sum-of-claims at resolve. |
| **Augment (ii)** — pendingResolveDay sentinel race/collision | NEGATIVE-VERIFIED | N-A | `:269, :665, :819-821`; `AdvanceModule.sol:1228, 1234, 1294, 1300, 1327, 1333`. | 6 sub-probes traced: (a) sentinel-vs-pool desync — EVM transactional rollback on revert handles all "set sentinel then revert before pool write" cases; (b) multi-day stall — sentinel always names the at-most-one stuck day; resolve writes correct period; (c) gameOver mid-stall — `_gameOverEntropy` resolves sentinel-stamped pool via current-word OR fallback-word path; (d) cross-actor — second burn on same day sees `stamp == currentPeriod` → does NOT re-write sentinel (`if (stamp == 0)` guard); pool accumulates correctly; (e) clear-on-resolve ordering — `delete pendingByDay` THEN sentinel clear in same tx; revert in between rolls back both atomically; (f) single-pool invariant integrity — burn reverts at `:820` if `stamp != 0 && stamp != currentPeriod`; structurally enforced. All paths NEGATIVE-VERIFIED. |
| **Augment (iii)** — gwei-snap × cap arithmetic precision | NEGATIVE-VERIFIED | N-A | `:858-861` (snap); `:883` (cap check post-snap); `:644, :648, :688` (× roll / 100). | EV cap check uses POST-snap `ethValueOwed` at `:883`; cap is 160e18 wei; post-snap value is always a multiple of 1e9 < cap. Player loses ≤1 gwei per burn to truncation (downward); they cannot exceed cap via snap. `pool.ethBase × 1e9` reconstructs sum-of-claims exactly (every claim is multiple of 1e9). `gcd(1e9, 100) = 100` precision claim holds — `(gwei × roll) / 100` divisor-100 commutes with the 1e9-multiple. Per-claim sub-roll floor-div dust ≤99 wei is v43-era behavior unchanged. INV-02 dust tolerance accommodates both per-claim dust AND the snap-truncation residue. |
| **Augment (iv)** — Phase 306 INV harness perturbation-class gaps (auditor scope: state-transition / storage / packing arms only) | NEGATIVE-VERIFIED | N-A | `test/invariant/RedemptionAccounting.t.sol` + `test/fuzz/handlers/RedemptionHandler.sol` (5-action set: burn, advance, claim, gameOver, burnOnPreviousDay). | Auditor's INV-perspective scope: a missing handler action (e.g., transfer mid-pending) does NOT break an INV that the existing handler PROVES. Transfer of sDGNRS does NOT mutate `pool.supplySnapshot` (snapshot was frozen at first burn — STORED, not derived); INV-10 (per-day supply cap) reads the stored snapshot, immune to post-snapshot totalSupply changes. Approve does NOT mutate any redemption-state. The remaining sub-classes (re-entry, coinflip drain, partial-claim BURNIE, admin during rngLock) point at composition + game-theoretic surfaces — those are SWP-02 (`/zero-day-hunter`) and SWP-03 (`/economic-analyst`) scope per D-307-DISPATCH-01 cross-skill divergence. Cross-skill hand-off documented in §3. |
| **Augment (v)** — Vault scope-expansion ACL surface | NEGATIVE-VERIFIED | N-A | `DegenerusVault.sol:431` (`onlyVaultOwner` modifier); `:719-721` (`sdgnrsBurn` → `sdgnrsToken.burn(amount)`); `:729-731` (`sdgnrsClaimRedemption` → `sdgnrsToken.claimRedemption(day)`). | Vault path: `sdgnrsBurn(amount)` (onlyVaultOwner) → `sdgnrsToken.burn` → in-game = gambling path → populates `pendingRedemptions[vaultAddr][D]`. Day D+1 advance resolves; vault owner (possibly different post-rebalance) calls `sdgnrsClaimRedemption(D)` (onlyVaultOwner) → `sdgnrsToken.claimRedemption(D)` → ETH/BURNIE flow to vault, NOT to caller. DGVE holders share pro-rata via standard vault accounting. No extraction primitive: vault-owner change between burn + claim does NOT redirect payout to the new owner — payout always lands in vault. Reentrancy: claim follows CEI (`delete pendingRedemptions` at `:717` BEFORE external calls); vault's `receive()` at `DegenerusVault.sol:489` only emits Deposit event with no state mutation. Auditor scope (ACL + reentrancy + claim-side state) NEGATIVE-VERIFIED. Composability / game-theoretic concerns deferred to `/economic-analyst` per cross-skill divergence. |

---

## §2 Skeptic-Filter Self-Discarded subsection

**No self-discards.** All probed hypotheses produced NEGATIVE-VERIFIED verdicts at first pass with concrete structural-protection citations. The skeptic-filter (a)-only hard discard arm therefore had no `FINDING_CANDIDATE` inputs to consider; (b)+(c) severity-downgrade arm inapplicable. The orchestrator integration-time re-application at Task 5 will re-verify against the union of all 3 skills' outputs.

| Hypothesis-ID | Source skill | Structural-protection citation (file:line) | EV-lens failed condition | Note |
| --- | --- | --- | --- | --- |
| (none) | /contract-auditor | n/a | n/a | No FINDING_CANDIDATE produced; nothing to discard. |

---

## §3 Cross-skill hand-off notes

For the parallel `/zero-day-hunter` + `/economic-analyst` dispatch (Tasks 3 + 4):

### Hand-off to `/zero-day-hunter` (SWP-02 + augment (iv) re-entry / composition arms)

- **Augment (iv) sub-class 3 (multi-actor sentinel race):** Two burns on the same day interleaved in a single block. Auditor confirmed the sentinel-write guard at `:821` (`if (stamp == 0)`) prevents double-writes within the same day, and that the cap checks at `:835` / `:883` operate on stored pool / claim values that survive re-ordering. No INV violates. But novel ordering surfaces (e.g., MEV-induced reorder between two burns where one races a vault rebalance) merit hunter's lens.
- **Augment (iv) sub-class 4 (ERC20-callback-induced state mutation):** sStonk's outbound external calls during burn: `coin.transfer` (BURNIE token transfer to recipient — but `_payBurnie` is claim-side, not burn-side; burn-side has no recipient call). Burn-side external reads: `game.currentDayView()`, `game.gameOver()`, `steth.balanceOf`, `coin.balanceOf`, `coinflip.previewClaimCoinflips`, `game.playerActivityScore` — all view-only. The hunter should look for callback-from-view-call surfaces (none typical, but stETH rebases mid-call could be a probe).
- **Augment (iv) sub-class 5 (coinflip pool drain mid-multi-day-claim):** Claim-side `_payBurnie` at `:933` calls `coinflip.claimCoinflipsForRedemption(address(this), remaining)`. If coinflip pool is dry, what happens? Hunter should trace coinflip's behavior under drain.
- **Augment (iv) sub-class 6 (partial-claim BURNIE branch under sentinel-stall):** The partial-claim branch at `:715-721` is reachable if `flipResolved == false` (coinflip's `getCoinflipDayResult(period.flipDay)` returned no resolution). Auditor confirmed CEI ordering (state mutation BEFORE external calls); hunter should trace the flipResolved-state under sentinel-stall to confirm no skipped-decrement.
- **Augment (v) reentrancy on vault claim path:** Auditor traced vault `receive()` is benign (event-only). Hunter should trace whether vault has any pending state machine of its own that could be desynced mid-claim.

### Hand-off to `/economic-analyst` (SWP-03 + game-theoretic / MEV arms)

- **Augment (iii) gwei-snap × player extraction strategy:** Auditor confirmed snap is monotonic-downward — players LOSE up to 1 gwei per burn, not gain. But: can a player concentrate burns at high-value moments (e.g., post-jackpot when stETH yield just landed) and snap-truncate to a beneficial gwei boundary? Economist's lens for sub-gwei timing arbitrage.
- **Augment (iv) sub-class 7 (admin-class actions during rngLock mid-pending):** Auditor saw no admin action that mutates redemption-state. Economist should probe whether admin actions affecting the cumulative scalars (`pendingRedemptionEthValue`, `pendingRedemptionBurnie`) — e.g., emergency withdraws, governance — can disadvantage in-flight redemption claims.
- **Augment (iv) sub-class 8 (rngLock + sentinel double-window):** Burn during rngLock reverts (`:536`); claim during rngLock — auditor traced no rngLock check on `claimRedemption`. Vault's `sdgnrsClaimRedemption(day)` similarly has no rngLock gate (`DegenerusVault.sol:729-731`). Is there a profitable timing for a claim during rngLock that the cap math would otherwise block on a burn? Economist's call.
- **MEV beyond-charge:** Auditor confirmed `redemptionRoll` is VRF-derived → no mempool-visible roll → no roll-frontrunning. Economist should probe burn-ordering MEV: in a block where Player A burns 100 sDGNRS and Player B burns 100 sDGNRS for day D, does the order matter for the pool's per-claim distribution? Pool-based pro-rata makes order irrelevant for the cumulative pool, but per-claim activity-score snapshots at `:891` could create order-dependence in BURNIE rolled payouts.
- **Coordinated-burn scenario:** N whales each burn near the 160 ETH cap on day D. Pool ethBase becomes ~N×160 ETH (in gwei units, fits in uint64). Roll fires day D+1 with VRF-derived 25..175. Each player receives `claim.ethValueOwed × roll / 100`. Symmetric outcome — no coordination gain. But: economist should probe whether a whale can strategically time burns relative to the resolve schedule.

### Auditor's residual concerns (none promoted to FINDING_CANDIDATE, but flagged for orchestrator integration-time re-application)

- **None.** All probed hypotheses produced concrete NEGATIVE-VERIFIED verdicts with structural-protection citations.

---

## §4 Summary

| Bucket | Count |
| --- | --- |
| Hypotheses charged | 22 (13 INV rows + 4 PACKING/INTERLEAVING rows + 5 augments) |
| NEGATIVE-VERIFIED | 22 |
| FINDING_CANDIDATE | 0 |
| SAFE_BY_DESIGN | 0 |
| Skeptic-filter self-discards | 0 |
| Severity downgrades | 0 (no findings to downgrade) |

**Verdict:** `/contract-auditor` SEQUENTIAL_MAIN_CONTEXT pass produces 0 FINDING_CANDIDATE rows. All charged invariants + augments + interleavings produce concrete NEGATIVE-VERIFIED verdicts with structural-protection citations. Phase 306 TST coverage (13 INV + 20 EDGE PROVEN at 256k+ calls) reinforces the structural arguments — every INV the harness PROVES is structurally enforced by current source, with no state transitions the auditor identified as bypass-eligible.

Cross-skill hand-off rows in §3 flag concerns the auditor's SWP-01 scope deferred to `/zero-day-hunter` (re-entry / composition) and `/economic-analyst` (game-theoretic / MEV).

---

*Phase 307 / Plan 01 / Task 2 / `/contract-auditor` SEQUENTIAL_MAIN_CONTEXT / 2026-05-19.*
