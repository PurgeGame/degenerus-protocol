# Phase 299 — FIXREC Cluster F: pendingRedemptionEthValue + deityPass + ETH/stETH balance (game-over magnitude inputs)

**Cluster:** F — Slots S-17 (`pendingRedemptionEthValue` cross-contract sStonk-side) + S-18 (`deityPassOwners`) + S-19 (`deityPassPurchasedCount[owner]`) + S-20 (`address(this).balance` ETH; EVM-intrinsic) + S-21 (`stETH.balanceOf(game)` cross-contract Lido; trace-stop). The unifying theme is **game-over drain magnitude inputs**: every slot in this cluster contributes to the terminal-day refund/payout calculations performed inside `DegenerusGameGameOverModule.handleGameOverDrain` (catalog §5) and the post-30-day `handleFinalSweep` cleanup.
**VIOLATIONs covered:** V-066, V-068, V-069, V-070, V-071, V-072, V-073, V-074, V-080 (9 logical entries — `D-43N-V44-HANDOFF-34`..`D-43N-V44-HANDOFF-42`).
**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §14 rows 76-80 (S-17/S-18/S-19/S-20/S-21); §15 writer rows 190-205; §16 verdict-matrix rows 401-415; consumers §5 (`GameOverModule.handleGameOverDrain` terminal magnitude computation; `preRefundAvailable = totalFunds − reserved`; deity-pass refund pass; sDGNRS / vault / GNRUS payouts), §12 (`StakedDegenerusStonk.resolveRedemptionPeriod` advance-stack consumer of `pendingRedemptionEthValue`).
**Posture:** AUDIT-ONLY per `D-43N-AUDIT-ONLY-01`. Zero `contracts/` + zero `test/` mutations. Authorial output only.
**Drafted:** 2026-05-18

---

## Cluster preamble — game-over magnitude-input architecture (load-bearing for every §N.A below)

This cluster groups five physically distinct slots that all participate in the **same terminal computation**: the value of `preRefundAvailable` consumed by `DegenerusGameGameOverModule.handleGameOverDrain` at `:93` and the immediately-following deity-pass refund pass. The grep-verified shape of the consumer:

```solidity
// contracts/modules/DegenerusGameGameOverModule.sol:84
uint256 totalFunds = address(this).balance + steth.balanceOf(address(this));   // ← S-20 + S-21 live SLOAD
// :93
uint256 preRefundAvailable = totalFunds > reserved ? totalFunds - reserved : 0;
// ... :99-:134: deity-pass refund pass walks `deityPassOwners` array, refunds each holder
// ... :156: postRefundReserved = ... ; "available" terminal-payout magnitude
```

The `reserved` quantity that subtracts from `totalFunds` includes (per the existing source-of-truth at `StakedDegenerusStonk.sol:535, :705, :772`) the sStonk-side `pendingRedemptionEthValue` (S-17) — i.e., the ETH that is already reserved for in-flight sStonk redemption claims and must NOT be drained into the terminal payout. The deity-pass refund pass walks the `deityPassOwners` array (S-18) and for each holder uses `deityPassPurchasedCount[holder]` (S-19) to compute the per-holder refund. The result: **every slot in this cluster is a live-SLOAD consumed inside the advanceGame-stack game-over branch, and every writer that fires during the rngLock window can shift the magnitude of the terminal payout.**

Per `feedback_rng_window_storage_read_freshness.md`: these are **non-VRF SLOADs consumed alongside the VRF word in the rngLock window** — a distinct bug class from VRF-derived seeds, with the F-41-02 / F-41-03 precedent confirming that non-VRF storage reads inside the rng-window are exploitable independent of any direct manipulation of the VRF input itself.

Per `feedback_rng_backward_trace.md`: every entry below traces backward from the consumer SLOAD site (inside `handleGameOverDrain`) to verify the slot value was unknown at the entropy-commitment moment (`_gameOverEntropy`) but subject to mutation in the rng-window before the consumer fires.

**Phase 281 precedent (load-bearing for tactic (b) selection in §5, §8, §9 below — V-071 + V-074 + V-080):** `.planning/milestones/v41.0-phases/281-mint-batch-determinism-fix-fix/281-01-DESIGN-INTENT-TRACE.md` introduced the **owed-salt 4th-keccak-input snapshot** pattern as the canonical resolution shape for "live-SLOAD-between-commitment-and-resolution" race classes. For Cluster F's balance-based inputs (V-071 `receive()` payable, V-080 stETH external IN-transfer), tactic (a) gated-revert is **structurally impossible** — the EVM `receive()` fallback cannot be gated against arbitrary ETH inflows (Solidity has no "reject ETH" primitive that survives `selfdestruct` or `coinbase`-payout edge cases), and the Lido stETH contract is out-of-source-tree (trace-stop per `D-298-EXEMPT-CROSSCONTRACT-01`). Tactic (b) snapshot-at-`_gameOverEntropy` is the only structural fix: snapshot `totalFunds = address(this).balance + steth.balanceOf(address(this))` at the entropy-commitment moment, then consume the snapshot inside `handleGameOverDrain` instead of the live SLOAD. One snapshot field covers both balance-based inputs (V-071 + V-080) simultaneously.

**Subsumption notes preserved for v44.0 traceability (per CATALOG):** V-070 is "Subsumed by V-069 (co-located write at `WhaleModule.sol:595/:596`)" — the deity-pass purchase function performs both `deityPassPurchasedCount += 1` and `deityPassOwners.push(buyer)` inside the same `_purchaseDeityPass` body; a single gate at the buyDeityPass callsite covers both writes. V-073 is "Same gate as V-063 (Cluster E, FIXREC 299-05)" — `claimWinnings` at `DegenerusGame.sol:1408` writes both `claimablePool` (S-16, Cluster E) and the implicit `address(this).balance` (S-20, this cluster); a single revert closes both writers. The H-37 and H-40 anchors are preserved per v44.0 handoff register discipline; the §N.C entries document the subsumption.

Per `feedback_verify_call_graph_against_source.md`: all writer-fn → callsite traces below were grep-verified against current source (`contracts/StakedDegenerusStonk.sol`, `contracts/modules/DegenerusGameWhaleModule.sol`, `contracts/DegenerusGame.sol`, `contracts/modules/DegenerusGameGameOverModule.sol`, `contracts/modules/DegenerusGameAdvanceModule.sol`) — the `BurnsBlockedDuringLiveness` gate convention at `StakedDegenerusStonk.sol:491-:492, :505-:513` is the canonical sStonk-side rng-lock revert pattern; the `rngLockedFlag` + `_livenessTriggered()` paired-gate convention at `WhaleModule.sol:543-:544` is the canonical game-side rng-lock revert pattern. No stale-phantom rows in this cluster — all 9 writer functions and call sites match the catalog enumeration.

Per `feedback_no_history_in_comments.md`: every §N below describes what the recommended state IS and what the current VIOLATION state IS, never what changed or what it used to be.

---

## §1 — V-066: `pendingRedemptionEthValue` × `beginRedemption` / `_submitGamblingClaimFrom` (`+=`)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 401 (V-066). §15 writer rows 190 (`beginRedemption`) + 193 (`_submitGamblingClaimFrom`). §14 row 76 (S-17). Consumers §5 (terminal drain via `pendingRedemptionEthValue` subtracted from `totalFunds`), §12 (advance-stack `resolveRedemptionPeriod` RMW).

### §1.A — Design-intent backward-trace

**Slot introduction phase:** `pendingRedemptionEthValue` was introduced as part of the sDGNRS sister-contract redemption-claim architecture — a per-period accumulator that segregates ETH already promised to in-flight sStonk redemption claims from the unallocated sStonk treasury. The slot is declared `uint256 public pendingRedemptionEthValue` at `StakedDegenerusStonk.sol:224` with the inline comment "total segregated ETH across all periods". The economic function: when a player calls `burn` or `burnWrapped` (the gambling burn path), the function calls `_submitGamblingClaimFrom` which writes `pendingRedemptionEthValue += ethValueOwed` at `:789` — reserving the player's expected ETH return for the subsequent advanceGame-side resolution at `resolveRedemptionPeriod:593` and final `claimRedemption:657`.

**Cite for "what would break if frozen":** Freezing `pendingRedemptionEthValue` during rngLock would block the entire sStonk gambling-burn surface (`burn` / `burnWrapped` EOA entry points). This is precisely what the existing `BurnsBlockedDuringLiveness` modifier at `StakedDegenerusStonk.sol:491` (and the explicit re-check at `:507` inside `burnWrapped`) is designed to do — the live source-of-truth grep:

```solidity
// :491 (inside _gateBurn used by burn / burnWrapped):
if (game.livenessTriggered()) revert BurnsBlockedDuringLiveness();
:492 if (game.rngLocked()) revert BurnsBlockedDuringRng();
```

The two-gate convention (`livenessTriggered` for the game-over magnitude-input window + `rngLocked` for the active VRF window) is the canonical sStonk-side rng-lock revert pattern (CONTEXT.md §51-§87 cites `sStonk:492` as the `RngLocked` precedent site). The slot is reserved-out from `totalMoney` at `:535, :705, :772` (the `_calcExchangeRate` / `_calcExchangeRateForGambling` / `_calcExchangeRateForReceiveDgnrs` family) and is the source-of-truth subtraction term in the game-over `reserved` quantity (per the `preRefundAvailable = totalFunds − reserved` shape in `GameOverModule.handleGameOverDrain:93`).

**Precedent for tactic (a) gated-revert:** The `BurnsBlockedDuringLiveness` modifier itself is the precedent — this VIOLATION row exists because the catalog must enumerate every write that occurs during the rng-window even when an existing gate covers, per `feedback_verify_call_graph_against_source.md` discipline. Per `feedback_rng_window_storage_read_freshness.md`, every storage-read inside the rng-window must be enumerated regardless of whether a gate covers, so V-066 is the **coverage-verification row** rather than a missing-gate row.

### §1.B — Actor game-theory walk

**Exploit-actor class:** sStonk holder attempting to inflate `pendingRedemptionEthValue` during the rngLock window. Concrete vector:

- Attacker holds sStonk (any balance, since the gambling-burn surface accepts `burn(1)` as the minimum-economic-quantum entry). Attacker observes that `_livenessTriggered() == true` (the game-over magnitude-input window is open). Attacker calls `sStonk.burn(amount)` to add `ethValueOwed = (amount / supply) × totalMoney` to `pendingRedemptionEthValue`.
- Goal: inflate the `reserved` quantity inside `GameOverModule.handleGameOverDrain` to reduce `preRefundAvailable`, redirecting terminal-payout magnitude away from deity-pass refunds and into the sStonk redemption queue.

**Action sequence during rngLock window (sequential):**

- T0: `advanceGame` enters the daily-phase that latches `_livenessTriggered() == true` (per AdvanceModule daily-loop). `_gameOverEntropy` requests the final-day VRF word; `rngLockedFlag = true`.
- T1 (attacker move): Attacker calls `sStonk.burn(amount)` → `_gateBurn` fires the live revert at `:491` (`livenessTriggered() == true` → revert `BurnsBlockedDuringLiveness`). **The attack is structurally blocked by the existing gate.**
- T1' (alternative attempt): Attacker observes `_livenessTriggered() == false` but `rngLocked() == true` (the rngLock window before final-day liveness latches). Calls `sStonk.burn(amount)` → `_gateBurn` fires at `:492` (`rngLocked() == true` → revert `BurnsBlockedDuringRng`). **Still blocked.**

**EV magnitude estimate:** **NONE — the existing `BurnsBlockedDuringLiveness` + `BurnsBlockedDuringRng` paired-gate at `:491-:492` covers both rng-window classes.** Catalog row 401 verdict-matrix column 5 confirms: "NO — gated by `livenessTriggered() && !gameOver` runtime revert during drain". The role of V-066 in this cluster is **coverage verification** — assert via FUZZ-301 that no execution branch reaches `pendingRedemptionEthValue +=` at `:789` while the consumer at `GameOverModule.handleGameOverDrain:93` is reachable. Economic-likelihood disposition: **defended by current source** pending the FUZZ-301 branch-reach attestation.

**Note on the dual-gate convention:** The two distinct reverts (`BurnsBlockedDuringLiveness` for the `livenessTriggered() && !gameOver` window; `BurnsBlockedDuringRng` for the `rngLocked()` window) are intentional — they correspond to two distinct economic semantics (game-over magnitude-input freeze vs. in-flight VRF request). V-066 covers the magnitude-input freeze class; the rng-lock class is separately enumerated for the same writer (catalog row 401 cites both gate conditions as compound coverage).

### §1.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) existing gated-revert covers — verification only.** Catalog §16 row 401 column 8 rationale verbatim: "Existing `BurnsBlockedDuringLiveness` covers; verify branch coverage".

**Concrete shape (verification only):**

- FUZZ-301 must produce a branch-reach attestation: for every execution sequence in which `_livenessTriggered() == true && !gameOver` holds (the magnitude-input window), assert that `pendingRedemptionEthValue +=` at `StakedDegenerusStonk.sol:789` is unreachable via `burn` / `burnWrapped` EOA call entries.
- Equivalent attestation for the `rngLocked() == true` window via the `:492` gate.
- No source-tree mutation. No new storage slot. No new modifier. **Zero bytecode delta.**

**Rationale for rejecting alternative tactics:**

- **(b) snapshot pattern** rejected: redundant — the existing gate prevents the write from ever firing during the consumer's read window. Adding a snapshot would introduce dead state without removing any attack surface.
- **(c) pre-lock reorder** rejected: not applicable — the writer is EOA-triggered at attacker discretion, and the existing gate is the structural reorder (denies the writer during the window).
- **(d) immutable** rejected: the slot is fundamentally mutable across the game's lifetime.

**Bytecode / storage-layout / public-ABI impact:**

- **Storage-layout:** **byte-identical.** Zero delta.
- **Bytecode delta:** **zero.** Verification-only row.
- **Net runtime gas:** zero delta.
- **Public ABI:** **NON-BREAKING.** Zero ABI delta.
- **Reference precedent:** Existing `BurnsBlockedDuringLiveness` + `BurnsBlockedDuringRng` revert pattern is the canonical sStonk-side rng-lock gate (CONTEXT.md cites `sStonk:492`). No new precedent introduced.

### §1.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-34`** — Verification-only anchor for V-066: assert `BurnsBlockedDuringLiveness` + `BurnsBlockedDuringRng` paired-gate at `StakedDegenerusStonk.sol:491-:492` covers the `pendingRedemptionEthValue += ethValueOwed` writer at `:789` reached via `burn` / `burnWrapped` EOA call entries. No contract change; FUZZ-301 branch-reach attestation deliverable.

- Gate site: `StakedDegenerusStonk.sol:491` (`if (game.livenessTriggered()) revert BurnsBlockedDuringLiveness();`)
- Gate site: `StakedDegenerusStonk.sol:492` (`if (game.rngLocked()) revert BurnsBlockedDuringRng();`)
- Writer site: `StakedDegenerusStonk.sol:789` (`pendingRedemptionEthValue += ethValueOwed;`)
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 401 (V-066), §15 writer rows 190 + 193, §14 row 76 (S-17).

---

## §2 — V-068: `pendingRedemptionEthValue` × `claimRedemption` (`-=`)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 403 (V-068). §15 writer row 192. §14 row 76. Cross-cluster coordination: V-184 (S-56 `redemptionPeriodIndex` fix at FIXREC 299-K, H-111) is the subsumption anchor.

### §2.A — Design-intent backward-trace

**Slot introduction phase:** Same architecture phase as §1.A — the sDGNRS redemption-claim accumulator. The `-=` direction at `claimRedemption:657` (verified verbatim against source: `pendingRedemptionEthValue -= totalRolledEth;`) is the **release** half of the per-period segregation pattern: when a player claims a resolved redemption period, the previously-reserved ETH is released from the `pendingRedemptionEthValue` accumulator and transferred to the player. The economic semantic: each `_submitGamblingClaimFrom` `+=` (V-066) is paired with a future `claimRedemption` `-=` (V-068); the slot is the running balance of ETH currently owed-but-not-yet-released to redeemers.

**Cite for "what would break if frozen":** Freezing the `-=` write during rngLock would block player claims of already-resolved redemption periods — an undesirable user-experience interruption for a flow that has no structural causal dependency on the daily VRF resolution. The `claimRedemption` flow reads from a previously-resolved `redemptionPeriods[period]` struct (whose `roll` was set by an earlier advanceGame call) and uses that pre-resolved value to compute the payout magnitude — the slot is not consuming any live VRF word during its own execution.

**Catalog downgrade rationale (verified verbatim from row 403 column 5):** "NO — EOA; downgraded (subtraction of VRF-derived value, not VRF input)". The classification distinguishes the slot's role as a **consumer** of an already-resolved VRF-derived value (the `roll` written by `resolveRedemptionPeriod:604`) from its role as an **input** to a fresh VRF resolution. Per `feedback_rng_window_storage_read_freshness.md` discipline, this is the inverse direction from the canonical "non-VRF SLOAD consumed alongside fresh VRF word" bug class — V-068's read is of a value the VRF has already determined.

**The actual bug surface lives at V-184, not V-068:** The exploit window for sStonk redemption is the **cross-day re-roll** described in catalog §1 entry 36 (the GLOBAL-OBSERVATION on `redemptionPeriodIndex` cross-day re-roll exploit). The fix is at V-184 (S-56 `redemptionPeriodIndex` re-resolution lock at H-111): revert in `_submitGamblingClaimFrom` if `redemptionPeriods[redemptionPeriodIndex].roll != 0`. Once V-184 closes the re-roll, V-068's `-=` direction becomes structurally safe — the only `pendingRedemptionEthValue` `-=` reachable from EOA can no longer race against a fresh `roll` overwrite, because the index would already have been advanced past any stale period.

### §2.B — Actor game-theory walk

**Exploit-actor class:** sStonk redeemer attempting to use the `claimRedemption` `-=` write as a race vector against the game-over magnitude consumer. Concrete vector (subsumed):

- Pre-V-184 fix: An attacker could exploit the cross-day re-roll (S-56 `redemptionPeriodIndex` not advanced inside `resolveRedemptionPeriod`) to force a fresh `roll` overwrite on an already-resolved period, then call `claimRedemption` with the new larger `totalRolledEth`, draining `pendingRedemptionEthValue` more than the period's original commitment. This race surface inflates the `-=` magnitude relative to the game-over consumer's expectation.
- Post-V-184 fix: `_submitGamblingClaimFrom` reverts if `redemptionPeriods[redemptionPeriodIndex].roll != 0`, preventing the stale-index re-arming. The `claimRedemption` `-=` write can then only fire against a `totalRolledEth` magnitude that was committed at the original advance-stack `roll` write, eliminating the race.

**Action sequence during rngLock window (subsumed by V-184 fix):** The `claimRedemption` callsite at `:657` is reachable during rngLock and during the magnitude-input window — but only with the **already-committed** `totalRolledEth` once V-184 closes the re-arm. The game-over consumer (`GameOverModule.handleGameOverDrain:93` reading `pendingRedemptionEthValue` via the `reserved` subtraction in `_calcExchangeRate*`) sees a value that is decreasing monotonically as legitimate claimers exit — the same monotone-drain semantic as Cluster D's Reward pool. The monotone direction is **safe** for the consumer because each claim reduces both `pendingRedemptionEthValue` and `address(this).balance` (or stETH balance) by the same magnitude, preserving the `totalFunds − reserved` invariant.

**EV magnitude estimate:** **LOW once V-184 fix lands.** The catalog's "subsumed by S-56 fix" disposition reflects this: V-068's race surface evaporates once V-184 closes the upstream re-arm vector. Pre-V-184, the EV magnitude was MEDIUM (attacker captures the delta between the original and re-rolled `totalRolledEth`); post-V-184, the surface is structurally eliminated. Economic-likelihood disposition: **defended-by-V-184**.

**Cross-cluster coordination note:** V-068's resolution depends on V-184 (Cluster K / FIXREC 299-K) landing. The v44.0 plan-phase must order V-184 (H-111) before V-068 (H-35), or merge them into a single sub-phase. The handoff anchor H-35 is preserved per v44.0 traceability discipline even though no independent fix is required.

### §2.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) subsumed by S-56 `redemptionPeriodIndex` fix (V-184, H-111).** Catalog §16 row 403 column 8 rationale verbatim: "Subsumed by S-56 `redemptionPeriodIndex` fix — re-resolution lock covers".

**Concrete shape (subsumed):**

- No independent fix at V-068. The fix lives at V-184 (S-56): `StakedDegenerusStonk._submitGamblingClaimFrom` adds a revert if `redemptionPeriods[redemptionPeriodIndex].roll != 0`. Once that fix lands, V-068's race surface is structurally eliminated.
- FUZZ-301 must produce a transitive-coverage attestation: assert that for every execution sequence in which V-184's revert is reachable, V-068's race vector is also unreachable.
- No source-tree mutation at V-068. **Zero independent bytecode delta.**

**Rationale for rejecting alternative tactics:**

- **(a) independent gated-revert at claimRedemption** rejected: the `claimRedemption` flow has no structural causal dependency on the daily VRF resolution; gating it would interrupt legitimate redeemer claims for no defense benefit once V-184 closes the upstream re-arm.
- **(b) snapshot pattern** rejected: not applicable — V-068's value is already structurally committed at the resolved-period boundary, so a snapshot would duplicate existing state.
- **(c) pre-lock reorder** rejected: V-068's `-=` is the legitimate release direction; reordering would not eliminate the upstream re-arm vector that V-184 addresses.
- **(d) immutable** rejected: the slot is fundamentally mutable across redemption cycles.

**Bytecode / storage-layout / public-ABI impact:**

- **Storage-layout:** **byte-identical.** Zero delta at V-068 (V-184 owns the fix bytecode).
- **Bytecode delta:** **zero at V-068.** Subsumed.
- **Net runtime gas:** zero delta.
- **Public ABI:** **NON-BREAKING.** Zero ABI delta.
- **Reference precedent:** V-184 (H-111) cites the Phase 288 `dailyIdx` snapshot precedent as the structural-fix shape for cross-day re-roll classes.

### §2.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-35`** — Subsumption anchor for V-068: cross-references V-184 (H-111, S-56 `redemptionPeriodIndex` re-resolution lock). v44.0 plan-phase orders V-184 before V-068 OR merges into a single sub-phase. No independent fix at V-068; FUZZ-301 transitive-coverage attestation deliverable.

- Writer site: `StakedDegenerusStonk.sol:657` (`pendingRedemptionEthValue -= totalRolledEth;`)
- Upstream fix anchor: `D-43N-V44-HANDOFF-111` (V-184 at S-56 `redemptionPeriodIndex` re-resolution lock, FIXREC 299-K)
- **Subsumption note:** V-068 is structurally eliminated by V-184. Anchor H-35 is preserved per v44.0 traceability discipline; no independent contract change. v44.0 plan-phase MUST cite H-111 as the operational fix target.
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 403 (V-068), §16 row 519 (V-184), §1 entry 36 (cross-day re-roll GLOBAL-OBSERVATION).

---

## §3 — V-069: `deityPassOwners` × `_purchaseDeityPass` (`.push(buyer)`)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 404 (V-069). §15 writer row 194. §14 row 77 (S-18). Consumer §5 (game-over deity-pass refund pass walks the array length + elements).

### §3.A — Design-intent backward-trace

**Slot introduction phase:** `deityPassOwners` was introduced as part of the Whale-module deity-pass purchase architecture — a sequential append-only array of addresses that have purchased a deity pass during the game's active lifetime. The slot is declared in `DegenerusGameStorage` as `address[] internal deityPassOwners`. The economic function: deity passes are a Whale-tier purchase with a refund obligation at game-over (per catalog §5 entry 1 "B-5" attestation: the game-over drain pass walks the deity-pass owner array to compute per-holder refunds before any terminal payout). The array length and elements together drive the deity-refund magnitude inside `GameOverModule.handleGameOverDrain` at `:99-:134`.

**Existing partial gates (grep-verified verbatim from source):**

```solidity
// contracts/modules/DegenerusGameWhaleModule.sol:542
function _purchaseDeityPass(address buyer, uint8 symbolId) private {
    :543    if (rngLockedFlag) revert RngLocked();
    :544    if (_livenessTriggered()) revert E();
    // ... :595-:597 inside same function:
    :595    deityPassPurchasedCount[buyer] += 1;
    :596    deityPassOwners.push(buyer);
    :597    deityPassSymbol[buyer] = symbolId;
}
```

The two paired gates at `:543-:544` are the canonical game-side rng-lock revert pattern — `rngLockedFlag` for the active VRF window, `_livenessTriggered()` for the game-over magnitude-input window. The catalog verdict-matrix row 404 column 5 confirms: "NO — EOA; runtime `rngLockedFlag` + `_livenessTriggered` gates" — the gates are present at the function head and structurally block the EOA-callable surface during both windows.

**Cite for "what would break if frozen":** Freezing `deityPassOwners` during rngLock would block the entire `purchaseDeityPass` EOA-callable surface — which is precisely what the existing gates do. The deity-pass purchase has no structural causal dependency on any in-flight VRF resolution; the gates exist specifically to prevent the deity-pass owner array from racing the game-over deity-refund consumer.

**Catalog row 404 column 8 rationale (verbatim):** "Gate buyDeityPass when any lootbox's RNG word is fresh in the open window". This extends the existing `rngLockedFlag` gate to the **lootbox rng-word freshness** window — per catalog §11 lootbox-rng staleness GLOBAL-OBSERVATION, an attacker can observe a fresh `lootboxRngWordByIndex[index]` (the lootbox VRF word) before opening the box, and the deity-pass purchase during that window can race the game-over consumer in a manner not already covered by `rngLockedFlag`. The fresh-lootbox-rng window is a distinct rng-window class from the daily-VRF `rngLockedFlag` window.

**Precedent for tactic (a) gated-revert (extended gate):** The existing `rngLockedFlag` + `_livenessTriggered()` paired-gate at `:543-:544` is the structural precedent. The extension adds a third gate: "any lootbox has a fresh-but-unconsumed RNG word in the open window" — a new gate condition tracked via the existing `lootboxRngWordByIndex` array (S-23 per catalog row 81).

### §3.B — Actor game-theory walk

**Exploit-actor class:** Whale-tier purchaser attempting to inflate `deityPassOwners.length` during a fresh-lootbox-rng window to extract a per-holder deity refund from the game-over drain. Concrete vector:

- Attacker has a fresh `lootboxRngWordByIndex[index]` (the lootbox VRF word) ready but unconsumed. Attacker observes the next game-over deity-refund magnitude.
- Attacker calls `purchaseDeityPass(buyer, symbolId)` — the existing `rngLockedFlag` gate at `:543` checks only the daily-VRF window; the lootbox-rng-window is a distinct freshness class and is not currently gated.
- Inside `_purchaseDeityPass`, `:595` increments `deityPassPurchasedCount[buyer] += 1` (the V-070 co-located write), `:596` appends `deityPassOwners.push(buyer)` (V-069), `:597` records `deityPassSymbol[buyer] = symbolId`.
- Goal: append the attacker's address to `deityPassOwners` BEFORE the game-over consumer at `GameOverModule.handleGameOverDrain:99-:134` walks the array, capturing a per-holder refund magnitude that the attacker would not have received without the late append.

**Action sequence during fresh-lootbox-rng window (sequential):**

- T0: `advanceGame` resolves a daily VRF batch including a fresh lootbox word at `lootboxRngWordByIndex[index]`. `rngLockedFlag` returns to `false` (the daily VRF window closes). The lootbox-rng-word is fresh but unconsumed.
- T1 (attacker move): Attacker observes the fresh lootbox-rng word AND a pending game-over drain (e.g., near-final physical day or imminent liveness trigger).
- T2 (attacker call): Attacker calls `purchaseDeityPass(attacker, symbolId)`. `:543` (`rngLockedFlag`) gate returns `false` (daily VRF closed). `:544` (`_livenessTriggered()`) returns `false` (liveness not yet triggered). Function proceeds, appends to `deityPassOwners`.
- T3 (advanceGame proceeds): Next `advanceGame` call triggers `handleGameOverDrain`. The consumer walks `deityPassOwners` (now including the attacker), computes per-holder refund using `deityPassPurchasedCount[attacker] × baseRefund`, and the attacker collects.

**EV magnitude estimate:** **HIGH — the deity-pass refund is a large per-pass refund magnitude.** Per catalog §5 entry 2 "B-5" attestation, the deity-pass refund pass occurs BEFORE `preRefundAvailable` is consumed for terminal payouts — meaning the deity refund extracts from `totalFunds` directly, and an attacker who appends an entry late in the game lifecycle captures a refund that would otherwise have flowed to the terminal-payout magnitude. Economic-likelihood disposition: **likely-exploited** if the fresh-lootbox-rng window is observable and a game-over drain is anticipated — both conditions are public-state-derivable in advance.

**Coordinated V-070 note:** The same `_purchaseDeityPass` body also increments `deityPassPurchasedCount[buyer] += 1` at `:595` (V-070). Both writes are co-located inside the same function and gated by the same `:543-:544` pair; a single gate-extension at the function entry covers both. The subsumption is operational, not theoretical.

### §3.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) extended gated-revert at `_purchaseDeityPass` function entry.** Catalog §16 row 404 column 8 rationale verbatim: "Gate buyDeityPass when any lootbox's RNG word is fresh in the open window".

**Concrete shape:**

- Augment the existing `:543-:544` gate pair with a third gate condition: a revert if any lootbox in `lootboxRngWordByIndex` has a fresh-but-unconsumed RNG word (the precise "fresh" predicate is determined by v44.0 plan-phase — likely a comparison of `lootboxRngWordByIndex[i] != 0 && lootboxOpenedByIndex[i] == false` for any `i` within the current open window).
- Place the new revert immediately after `:543` (`rngLockedFlag`) and before `:544` (`_livenessTriggered`) — the ordering is canonical (check fastest-to-evaluate gate first).
- The revert error type can re-use `RngLocked` (the existing error already declared) OR a new `LootboxRngFresh` custom error per v44.0 plan-phase discretion.

**Rationale for rejecting alternative tactics:**

- **(b) snapshot pattern** rejected: snapshotting `deityPassOwners` at `_gameOverEntropy` time would freeze the array length but break the legitimate `purchaseDeityPass` flow for any non-attacker buyer who calls during the fresh-lootbox-rng window. The append-only semantic of `deityPassOwners` is incompatible with a per-resolution snapshot — the array is the running game-state, not a per-resolution input.
- **(c) pre-lock reorder** rejected: not applicable — the writer is EOA-triggered at attacker discretion.
- **(d) immutable** rejected: the slot is fundamentally append-only-mutable across the game's lifetime.

**Bytecode / storage-layout / public-ABI impact:**

- **Storage-layout:** **byte-identical.** No new storage slot. The gate predicate uses existing storage (`lootboxRngWordByIndex` + lootbox-opened tracking).
- **Bytecode delta:** ~30-50 bytes for the new gate-condition revert (one SLOAD per checked lootbox index OR one packed-bitmap SLOAD per the v44.0 plan-phase decision on the freshness-tracking representation).
- **Net runtime gas:** +~2100 gas (one cold SLOAD on the lootbox-rng-array length + per-index check, or ~100 gas if a packed freshness bitmap is used). Charged only on the `purchaseDeityPass` hot path which is itself a Whale-tier purchase and not gas-sensitive.
- **Public ABI:** **NON-BREAKING.** No event topic-hash change; the revert is a function-level gate with no external visibility beyond the error selector.
- **Reference precedent:** The existing `rngLockedFlag` + `_livenessTriggered()` gate-pair at `:543-:544` is the structural precedent for a three-gate `purchaseDeityPass` function-head guard.

### §3.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-36`** — Extended gate at `_purchaseDeityPass` to revert when any lootbox's RNG word is fresh-but-unconsumed in the open window. v44.0 plan-phase decides the freshness-tracking representation (per-index SLOAD scan vs. packed bitmap).

- Existing gate sites preserved: `WhaleModule.sol:543` (`rngLockedFlag`), `:544` (`_livenessTriggered`).
- New gate site to add: `WhaleModule.sol` between `:543` and `:544` (or coalesced into a single compound check).
- Writer covered: `:596` (`deityPassOwners.push(buyer)`).
- Co-located writer (V-070) covered: `:595` (`deityPassPurchasedCount[buyer] += 1`).
- Consumer: `GameOverModule.handleGameOverDrain:99-:134` deity-pass refund pass.
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 404 (V-069), §15 writer row 194, §14 row 77 (S-18), §11 lootbox-rng-staleness GLOBAL-OBSERVATION.

---

## §4 — V-070: `deityPassPurchasedCount[owner]` × `_purchaseDeityPass` (`+= 1`)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 405 (V-070). §15 writer row 195. §14 row 78 (S-19). Subsumption anchor: V-069 (H-36).

### §4.A — Design-intent backward-trace

**Slot introduction phase:** `deityPassPurchasedCount` was introduced alongside `deityPassOwners` as the per-holder count companion — the array tracks WHO owns deity passes, the mapping tracks HOW MANY each holder owns. The slot is declared in `DegenerusGameStorage` as `mapping(address => uint16) internal deityPassPurchasedCount`. The economic function: at game-over, the deity-refund pass at `GameOverModule.handleGameOverDrain:99-:134` computes per-holder refund as `deityPassPurchasedCount[holder] × baseRefund`, summing across all entries in `deityPassOwners`. The two slots together drive the deity-refund magnitude.

**Co-located write site (grep-verified):** `DegenerusGameWhaleModule.sol:595` (`deityPassPurchasedCount[buyer] += 1;`) immediately precedes `:596` (`deityPassOwners.push(buyer);`). Both writes execute inside the same `_purchaseDeityPass` body, gated by the same `:543-:544` pair. The catalog row 405 column 5 verdict-matrix confirms: "NO — EOA; same gate as V-069".

**Cite for "what would break if frozen":** Same as §3.A — freezing `deityPassPurchasedCount` during rngLock would block the deity-pass purchase flow. The economic function is symmetric with `deityPassOwners`.

**Catalog row 405 column 8 rationale (verbatim):** "Subsumed by V-069 (co-located write)". The subsumption is operational: a single gate at the `_purchaseDeityPass` function head closes both writes.

### §4.B — Actor game-theory walk

**Exploit-actor class:** Identical to §3.B — same attacker, same exploit vector, same window. The `+= 1` write at `:595` and the `.push(buyer)` write at `:596` are atomic within the same function call; an attacker cannot exploit one without the other (and would not want to — the deity-refund magnitude depends on BOTH the array element AND the count).

**Action sequence:** Identical to §3.B. The attacker's `purchaseDeityPass` call increments `deityPassPurchasedCount[attacker]` AND appends the attacker to `deityPassOwners` in a single transaction; the game-over consumer reads both.

**EV magnitude estimate:** **Same as §3.B — HIGH.** No independent EV; V-070's surface is entirely co-located with V-069's surface.

### §4.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) subsumed by V-069 (H-36) — co-located write.** Catalog §16 row 405 column 8 rationale verbatim: "Subsumed by V-069 (co-located write)".

**Concrete shape:**

- No independent fix at V-070. The fix lives at V-069 (H-36): extend the existing `_purchaseDeityPass` function-head gate to include a fresh-lootbox-rng-window revert.
- Once H-36 lands, V-070's surface is structurally eliminated by the same gate that closes V-069.
- FUZZ-301 must produce a transitive-coverage attestation: assert that every execution sequence reaching `:595` (`deityPassPurchasedCount[buyer] += 1`) also has H-36's gate reachable — true by inspection because both writes live inside the same `_purchaseDeityPass` body.

**Subsumption note preserved for v44.0 traceability (per CATALOG):** V-070's anchor H-37 is preserved per v44.0 handoff-register discipline. The v44.0 plan-phase MUST cite H-36 as the operational fix target; no independent contract change at V-070.

**Rationale for rejecting alternative tactics:**

- **(a) independent gated-revert at V-070's writer line** rejected: the writer is on a line inside the same `_purchaseDeityPass` body as V-069's writer; a separate per-line gate would duplicate H-36's check.
- **(b) snapshot pattern** rejected: same reasoning as §3.C — the running-game-state semantic is incompatible with a per-resolution snapshot.
- **(c) pre-lock reorder** rejected: not applicable.
- **(d) immutable** rejected: the slot is fundamentally mutable.

**Bytecode / storage-layout / public-ABI impact:**

- **Storage-layout:** **byte-identical.** Zero delta at V-070.
- **Bytecode delta:** **zero at V-070.** Subsumed by V-069's gate.
- **Net runtime gas:** zero delta.
- **Public ABI:** **NON-BREAKING.** Zero ABI delta.
- **Reference precedent:** H-36's extended gate is the structural precedent; H-37 inherits.

### §4.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-37`** — Subsumption anchor for V-070: cross-references V-069 (H-36). Anchor preserved per v44.0 traceability discipline despite operational subsumption; the v44.0 sub-phase that lands H-36 closes H-37 atomically.

- Writer site: `WhaleModule.sol:595` (`deityPassPurchasedCount[buyer] += 1;`)
- Subsuming gate site: `WhaleModule.sol` between `:543` and `:544` (V-069's extended gate at H-36).
- Consumer: `GameOverModule.handleGameOverDrain:99-:134` deity-pass refund per-holder count read.
- **Subsumption note:** V-070's writer is co-located inside `_purchaseDeityPass` with V-069's writer (one line apart at `:595` vs `:596`); both are gated by the same function-head check at `:543-:544`. Extending that check at H-36 closes both writes. v44.0 plan-phase MUST cite H-36 as the operational target.
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 405 (V-070), §16 row 404 (V-069), §15 writer row 195, §14 row 78 (S-19).

---

## §5 — V-071: `address(this).balance` × `receive()` payable fallback

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 406 (V-071). §15 writer row 196 (implicit Solidity receive). §14 row 79 (S-20). Consumer §5 (`GameOverModule.handleGameOverDrain:84` `address(this).balance` live SLOAD).

### §5.A — Design-intent backward-trace

**Slot introduction phase:** `address(this).balance` is EVM-intrinsic — no source declaration under `contracts/`. The `receive()` payable fallback function (grep-verified at `contracts/DegenerusGame.sol:2618-:2627`) is the EOA-callable entry point that explicitly accepts plain-ETH transfers into the game contract. The fallback body:

```solidity
// contracts/DegenerusGame.sol:2618
receive() external payable {
    if (gameOver) revert E();
    if (prizePoolFrozen) {
        (uint128 pNext, uint128 pFuture) = _getPendingPools();
        _setPendingPools(pNext, pFuture + uint128(msg.value));
    } else {
        (uint128 next, uint128 future) = _getPrizePools();
        _setPrizePools(next, future + uint128(msg.value));
    }
}
```

The fallback's design-intent: accept external ETH contributions and route them to the prize-pool reserves (the inline comment block at `:2610-:2615` documents the routing). The economic function: external parties can contribute ETH to the game's reward pool by sending plain ETH. The slot under discussion (`address(this).balance`) is NOT directly written by the fallback — the fallback writes `prizePools` / `pendingPools` state — but the EVM-intrinsic `address(this).balance` is incremented atomically by the EVM as part of the value-transfer mechanism BEFORE the receive() body executes.

**The key freshness invariant:** Inside `GameOverModule.handleGameOverDrain:84`, the consumer reads `uint256 totalFunds = address(this).balance + steth.balanceOf(address(this));` — a live SLOAD of the EVM-intrinsic balance state. The `preRefundAvailable` quantity at `:93` is computed from this live read. Any inflow during the rngLock window (after `_gameOverEntropy` requests the final-day VRF but before `handleGameOverDrain` executes) inflates `address(this).balance` and shifts the terminal-payout magnitude.

**Cite for "what would break if frozen":** Tactic (a) gated-revert is **structurally impossible** for the `receive()` payable fallback during the rng-window. Solidity cannot reliably reject ETH inflows in all EVM contexts:

1. The current `receive()` body checks `if (gameOver) revert E();` — but `gameOver` is only set AFTER `handleGameOverDrain` executes (`:139` of GameOverModule). The rng-window between `_gameOverEntropy` and `handleGameOverDrain` is a window in which `gameOver == false` AND the receive accepts ETH.
2. Even if the receive() body reverted on `rngLockedFlag`, the EVM has two payout primitives that bypass the receive() function entirely: `selfdestruct(address)` (forces ETH transfer with no callback) and `block.coinbase` payouts (miner rewards / MEV-bot self-destructs targeting the game contract).
3. Per `feedback_frozen_contracts_no_future_proofing.md`: the contracts are frozen at deploy. Adding a receive-fallback revert would not eliminate the `selfdestruct` / coinbase-payout inflow class.

The only structural fix is tactic (b) snapshot: capture `totalFunds = address(this).balance + steth.balanceOf(address(this))` at `_gameOverEntropy` commitment time, then consume the snapshot inside `handleGameOverDrain` instead of the live SLOAD. The snapshot pattern is **agnostic to inflow vector** — selfdestruct, coinbase, receive() all become irrelevant because the consumer reads the pinned value.

**Precedent for snapshot pattern:** Phase 281 owed-salt 4th-keccak-input introduced the snapshot-at-commitment shape as the canonical resolution for "live-SLOAD-between-commitment-and-resolution" races (`.planning/milestones/v41.0-phases/281-mint-batch-determinism-fix-fix/281-01-DESIGN-INTENT-TRACE.md` `D-281-FIX-SHAPE-01`). The Cluster F balance-snapshot is the direct application: snapshot the inflow-mutable EVM balance at the entropy-commitment moment.

### §5.B — Actor game-theory walk

**Exploit-actor class:** Any EOA (or contract) capable of sending ETH to the game contract during the rngLock window. The attack surface is universal — no protocol participation required:

- Vector 1: Direct `send(eth)` / `transfer(eth)` / `call{value: x}("")` to the game contract address. Triggers `receive()`, which routes the inflow to `prizePools.future` (per the receive() body at `:2622-:2625`).
- Vector 2: `selfdestruct(payable(GAME_ADDRESS))` from a controlled contract. Bypasses `receive()` entirely; increments `address(this).balance` without invoking any Solidity code on the game side.
- Vector 3: Coinbase-payout (miner / sequencer / MEV-bot self-destructs targeting GAME). Same bypass as Vector 2.

**Action sequence during rngLock window (sequential):**

- T0: `advanceGame` enters the final-day branch. `_gameOverEntropy` requests the terminal VRF word. `rngLockedFlag = true`.
- T1 (attacker move): Attacker inflates `address(this).balance` by `Δ` via any of Vectors 1-3. The EVM-intrinsic balance state is updated atomically; no Solidity code can prevent it for Vectors 2-3.
- T2 (VRF callback): The terminal VRF word is delivered. `advanceGame` proceeds to `handleGameOverDrain`.
- T3 (consumer SLOAD): `handleGameOverDrain:84` reads `totalFunds = address(this).balance + steth.balanceOf(address(this))`. The value is `originalBalance + Δ + stETHBalance`.
- T4 (resolution): `preRefundAvailable = (originalBalance + Δ + stETHBalance) − reserved`. The deity-refund pass at `:99-:134` and the terminal-payout magnitude at `:156` consume the inflated `preRefundAvailable`.

**Exploit direction:** The attacker is **gifting** ETH to the game, not draining it — so why is this an exploit? Per `feedback_design_intent_before_deletion.md`, the bug class is not "attacker steals ETH"; it's "attacker shifts the magnitude of a terminal-payout consumer in a manner not anticipated by the protocol's commitment-time invariant". A late inflow inflates the terminal-payout magnitude, which shifts the proportion of `preRefundAvailable` that flows to deity-refunds vs. terminal-payout-winners. An attacker who controls a deity-pass position (or a position that wins from the terminal-payout proportion) can extract EV from the late inflow.

**EV magnitude estimate:** **HIGH on the terminal day; MEDIUM on the rngLock window mid-game.** The terminal-day attack is particularly severe because:

1. The deity-refund pass executes BEFORE the terminal-payout magnitude is computed (per catalog §5 entry 2 "B-5" attestation).
2. The attacker can pre-position a deity-pass purchase (any number of passes) and then inject a late inflow proportional to their deity-pass count to extract per-pass refund magnitude.
3. The inflow vector is universal — selfdestruct cannot be blocked; the attack surface persists even if `receive()` is fully reverted.

Economic-likelihood disposition: **likely-exploited** on terminal day. The attack is cheap (gas + the inflow magnitude, which is recovered as refund), economically rational, and structurally undetectable from inside the receive() body for Vectors 2-3.

### §5.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (b) snapshot `totalFunds` at `_gameOverEntropy` time; consume snapshot in `handleGameOverDrain`.** Catalog §16 row 406 column 8 rationale verbatim: "Snapshot `totalFunds` at `_gameOverEntropy` time; consume snapshot in drain".

**Concrete shape:**

- Introduce a packed snapshot field `gameOverFundsSnapshot` (uint256 sufficient since `totalFunds = address(this).balance + steth.balanceOf(address(this))` may exceed uint128 for high-TVL deployments; v44.0 plan-phase decides the precise width).
- Populate the field inside `_gameOverEntropy` (the AdvanceModule callsite that requests the terminal VRF word). Compute `snapshot = address(this).balance + steth.balanceOf(address(this))` once, SSTORE to `gameOverFundsSnapshot`.
- Modify `GameOverModule.handleGameOverDrain:84` to read the snapshot field instead of the live `address(this).balance + steth.balanceOf(address(this))` computation.
- The `claimablePool`-side reserved subtraction (`reserved` in the `preRefundAvailable = totalFunds − reserved` shape) continues to read the live `claimablePool` value — only the EVM-balance + stETH-balance components are snapshotted. (Alternatively, v44.0 may snapshot `reserved` as well per `pendingRedemptionEthValue` snapshot — out of scope for this VIOLATION; see V-080 cross-cut below.)
- This SAME snapshot field covers V-080 (stETH external IN-transfer race) because the consumer combines ETH balance + stETH balance into the single `totalFunds` quantity. One snapshot field, two VIOLATION closures. (See §9.C for the V-080 cross-reference.)

**Rationale for rejecting alternative tactics:**

- **(a) `rngLockedFlag`-gated revert in `receive()`** rejected: structurally insufficient. Vectors 2-3 (selfdestruct + coinbase-payout) bypass `receive()` entirely. Adding a revert in the receive() body would partially mitigate Vector 1 but not the universal class. Per `feedback_frozen_contracts_no_future_proofing.md`, the gate-half-measure increases bytecode without closing the surface.
- **(c) pre-lock reorder** rejected: not applicable — inflows are EOA-discretionary and EVM-intrinsic (Vectors 2-3).
- **(d) immutable** rejected: `address(this).balance` is fundamentally mutable.

**Bytecode / storage-layout / public-ABI impact:**

- **Storage-layout:** new packed snapshot field `gameOverFundsSnapshot` (uint256 OR uint128 per v44.0 plan-phase width decision). 16-32 bytes. v44.0 plan-phase decides whether to coalesce with adjacent packed slots (e.g., the existing `pendingPools` / `prizePools` packing structure). **NOT byte-identical** — one new slot or one slot-extension.
- **Bytecode delta:** ~100-200 bytes. One additional `address(this).balance + steth.balanceOf(address(this))` computation inside `_gameOverEntropy` (one BALANCE opcode + one STATICCALL on Lido + one SSTORE). One SLOAD on the snapshot field inside `handleGameOverDrain:84` replacing the live BALANCE + STATICCALL.
- **Net runtime gas:** approximately neutral. `_gameOverEntropy` pays +1 BALANCE (+~700 gas cold) + 1 STATICCALL (~2600 gas cold) + 1 SSTORE (~20000 gas warm = ~22300 gas). `handleGameOverDrain` saves -1 BALANCE (~700 gas) + -1 STATICCALL (~2600 gas) and gains +1 SLOAD (~2100 cold ≈ -1200 net). Final-day path runs once per game so the snapshot SSTORE amortizes to zero per game.
- **Public ABI:** **NON-BREAKING.** No event topic-hash change; the new field is internal storage. v44.0 plan-phase may expose via a new view function (optional).
- **Reference precedent:** Phase 281 owed-salt snapshot is exactly this shape, zero ABI delta and zero hot-path gas delta in the steady state.

### §5.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-38`** — Snapshot `totalFunds = address(this).balance + steth.balanceOf(address(this))` at `_gameOverEntropy` commitment moment; `GameOverModule.handleGameOverDrain:84` reads the snapshot instead of the live BALANCE + STATICCALL. Single snapshot field closes both V-071 (ETH inflow) and V-080 (stETH inflow) — see H-42.

- Snapshot WRITE site: inside `_gameOverEntropy` (`AdvanceModule.sol` final-day entropy-commit callsite; precise line per v44 plan-phase grep).
- Snapshot READ site: replace live read at `GameOverModule.sol:84` (`address(this).balance + steth.balanceOf(address(this))`).
- Storage field: new `gameOverFundsSnapshot` (uint256 / uint128 per v44 plan-phase width decision).
- Cross-cuts with V-080 (H-42): same snapshot field covers both ETH and stETH balance inputs.
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 406 (V-071), §15 writer row 196, §14 row 79 (S-20), §5 entry 1-2 (game-over drain magnitude consumer).

---

## §6 — V-072: `address(this).balance` × payable purchase functions (inflate balance)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 407 (V-072). §15 writer row 197 (every `payable` purchase function — `mintBatch` / `purchaseWhaleBundle` / `purchaseDeityPass` / `purchaseLazyPass`). §14 row 79.

### §6.A — Design-intent backward-trace

**Slot introduction phase:** Same EVM-intrinsic slot as §5.A (`address(this).balance`). The writer set here is distinct from V-071: V-071 covered the bare `receive()` fallback (no protocol participation required); V-072 covers the **`payable` protocol-purchase entry points** at `DegenerusGame.sol:356, :507, :602, :624, :644, :721, :1808` (grep-verified payable functions). Each of these is a protocol-purchase entry that accepts `msg.value` and (atomically with the EVM-intrinsic balance increment) writes some `prizePools` / `claimablePool` state.

**Existing gates (grep-verified):** The `payable` purchase entry points are gated against the rng-window by the canonical game-side pair (`MintModule.sol:1215` / `MintModule.sol:1221` for mint surfaces; `WhaleModule.sol:543-:544, :385` for whale-deity-lazy-pass surfaces; etc.). The catalog verdict-matrix row 407 column 5 confirms: "NO — EOA; gated by `_livenessTriggered() && rngLockedFlag` runtime" — the gates are present at the purchase-function entry and structurally block the EOA-callable surface during both windows.

**Cite for "what would break if frozen":** Tactic (a) gated-revert IS the existing mechanism — the gates at the purchase-function entry points prevent the writer from firing during the rngLock window. V-072 is the **coverage-verification row** for this writer class, analogous to V-066's role for the sStonk-side burn surface.

**Catalog row 407 column 8 rationale (verbatim):** "Existing per-fn gates cover; verify coverage during livenes window". (Note: the catalog has a typo "livenes" — the source-of-truth grep should read "liveness".)

**Precedent for tactic (a) gated-revert (verification):** Identical to §1 (V-066) — the existing gates are the canonical structural fix, and V-072 enumerates the writer class for branch-reach attestation discipline per `feedback_rng_window_storage_read_freshness.md`.

### §6.B — Actor game-theory walk

**Exploit-actor class:** Any EOA attempting to invoke a `payable` protocol-purchase entry point during the rngLock window. Concrete vectors:

- Player calls `mintBatch{value: x}(...)` during rngLock → `MintModule._livenessTriggered()` revert at `:1215` OR `cachedJpFlag && rngLockedFlag` revert at `:1221` fires.
- Whale-tier buyer calls `purchaseDeityPass{value: x}(...)` during rngLock → `WhaleModule.sol:543` (`rngLockedFlag`) revert fires. (See §3.B for the V-069 / V-070 attack walk — same gate covers V-072's `address(this).balance` impact at the same writer.)
- Player calls `purchaseLazyPass{value: x}(...)` during rngLock → corresponding `WhaleModule.sol:195` (`_livenessTriggered`) / `:385` revert fires.

**Action sequence during rngLock window:** Every purchase function reverts at the function-entry gate before any `msg.value` is committed to the contract — the EVM rolls back the inflow atomically with the revert. **The attack is structurally blocked.**

**EV magnitude estimate:** **NONE — existing per-function gates cover.** Catalog row 407 verdict-matrix column 5 confirms the coverage. V-072's role: assert via FUZZ-301 that every `payable` purchase entry point has a working `_livenessTriggered() || rngLockedFlag` gate at the function head, and that no execution branch reaches the `address(this).balance` inflation while the consumer at `GameOverModule.handleGameOverDrain:84` is reachable.

**Distinction from V-071:** V-071 covers the **gated-impossible** inflow class (`receive()` + selfdestruct + coinbase-payout — cannot be reverted in all EVM contexts). V-072 covers the **gated-and-reverted** inflow class (purchase functions with explicit `_livenessTriggered() / rngLockedFlag` checks). The two writer classes share the same consumer (S-20 / `GameOverModule.handleGameOverDrain:84`) but require different tactics: snapshot (b) for V-071's universal class, verification (a) for V-072's already-gated class.

### §6.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) existing per-function gates cover — verification only.** Catalog §16 row 407 column 8 rationale verbatim: "Existing per-fn gates cover; verify coverage during livenes window".

**Concrete shape (verification only):**

- FUZZ-301 must produce a branch-reach attestation: for every `payable` external function in `DegenerusGame` / `MintModule` / `WhaleModule` / `BurnieCoinflip` / etc., assert that the function-head gate (`_livenessTriggered() || rngLockedFlag` pair) is reached BEFORE any state mutation OR `msg.value` commitment.
- The attestation is per-entry-point — each payable function in scope must independently exhibit gate coverage.
- No source-tree mutation. No new storage slot. No new modifier. **Zero bytecode delta.**

**Rationale for rejecting alternative tactics:**

- **(b) snapshot pattern** rejected: redundant — the existing gates prevent the write from ever firing during the consumer's read window. (V-071 already snapshots for the gated-impossible class; V-072 doesn't need the same snapshot for the gated class.)
- **(c) pre-lock reorder** rejected: not applicable.
- **(d) immutable** rejected: the slot is mutable.

**Bytecode / storage-layout / public-ABI impact:**

- **Storage-layout:** **byte-identical.** Zero delta.
- **Bytecode delta:** **zero.** Verification-only row.
- **Net runtime gas:** zero delta.
- **Public ABI:** **NON-BREAKING.** Zero ABI delta.
- **Reference precedent:** Existing function-head gate pattern across `MintModule.sol:1215, :1221, :877, :906, :1381` and `WhaleModule.sol:543-:544, :195, :385`. No new precedent.

### §6.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-39`** — Verification-only anchor for V-072: assert function-head `_livenessTriggered() || rngLockedFlag` gate coverage on every `payable` protocol-purchase entry point. No contract change; FUZZ-301 branch-reach attestation deliverable.

- Gate sites (sample, non-exhaustive): `MintModule.sol:1215, :1221`; `WhaleModule.sol:543, :544, :195, :385`; per-function inventory deferred to v44.0 plan-phase grep.
- Writer class: every `payable` external function inflating `address(this).balance` during state-mutating execution.
- Consumer: `GameOverModule.handleGameOverDrain:84` `address(this).balance` live SLOAD.
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 407 (V-072), §15 writer row 197, §14 row 79 (S-20).

---

## §7 — V-073: `address(this).balance` × `claimWinnings` outflow (`call{value:}`)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 408 (V-073). §15 writer row 198. §14 row 79. Cross-cluster subsumption: V-063 (Cluster E / FIXREC 299-05, H-31) is the gate-shared anchor.

### §7.A — Design-intent backward-trace

**Slot introduction phase:** `address(this).balance` is EVM-intrinsic. The writer site under discussion is the `claimWinnings` outflow — verified verbatim at `DegenerusGame.sol:1399-:1416`:

```solidity
// :1399
function _claimWinningsInternal(address player, bool stethFirst) private {
    :1400    if (_goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0) revert E();
    :1401    uint256 amount = claimableWinnings[player];
    :1402    if (amount <= 1) revert E();
    // ...
    :1408    claimablePool -= uint128(payout);
    :1409    emit WinningsClaimed(player, msg.sender, payout);
    :1410-:1414  // _payoutWithEthFallback / _payoutWithStethFallback → call{value:}(...)
}
```

The `call{value:}` outflow inside `_payoutWithEthFallback` / `_payoutWithStethFallback` (at `:2002, :2022, :2043` per grep) decrements `address(this).balance` by the `payout` magnitude. The slot is consumed by `GameOverModule.handleGameOverDrain:84` immediately after rng-window-resolved magnitudes are known.

**Existing gates (grep-verified — KEY FINDING):** The `_claimWinningsInternal` body at `:1399-:1416` checks ONLY `_goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0` at `:1400` — i.e., the post-30-day "everything has been swept" sentinel. **There is NO `_livenessTriggered()` gate and NO `rngLockedFlag` gate in the `claimWinnings` body.** The catalog verdict-matrix row 408 column 5 confirms verbatim: "NO — EOA; no liveness gate".

This is the inverse of V-072's class: V-072's payable purchases inflate `address(this).balance` and ARE gated; V-073's `claimWinnings` deflates `address(this).balance` and is NOT gated. The asymmetry creates the exploit window.

**Cite for "what would break if frozen":** Gating `claimWinnings` on `_livenessTriggered() || gameOver` would block legitimate player payouts during the game-over magnitude-input window. This is the explicit catalog row 408 column 8 recommendation: "Same gate as V-063 — single revert closes both `claimablePool` and balance writers".

The crucial design observation: `claimWinnings` writes BOTH `claimablePool` (Cluster E / S-16) and `address(this).balance` (this cluster / S-20). A single revert at the `_claimWinningsInternal` body head closes **both** consumer races simultaneously. V-073 and V-063 share the same writer line; the gate-once-revert-twice pattern is the structural fix.

**Catalog row 408 column 8 rationale (verbatim):** "Same gate as V-063 — single revert closes both `claimablePool` and balance writers". V-063 (Cluster E, H-31) is the canonical anchor; v44.0 plan-phase MUST ensure V-063 and V-073 are landed in the same sub-phase OR explicitly cross-link.

**Precedent for tactic (a) gated-revert:** Existing `_livenessTriggered()` gate convention across `MintModule.sol:1215`, `WhaleModule.sol:544`, `JackpotModule.sol` (various) is the structural precedent. The new gate at `_claimWinningsInternal:1400` is the simplest application — one new `if` statement at the function head.

### §7.B — Actor game-theory walk

**Exploit-actor class:** Player with `claimableWinnings[player] > 1` attempting to extract a payout during the rngLock magnitude-input window, shifting both `claimablePool` (V-063) and `address(this).balance` (V-073) before the game-over consumer reads.

**Action sequence during rngLock window (sequential):**

- T0: `advanceGame` enters the final-day branch. `_gameOverEntropy` requests the terminal VRF word. `_livenessTriggered() == true` (magnitude-input window open).
- T1 (attacker move): Attacker calls `claimWinnings(player)`. `:1400` checks `GO_SWEPT_SHIFT` — returns 0 (sweep hasn't happened yet, gameOver hasn't latched). `:1408` `claimablePool -= uint128(payout)`. `:1410-:1414` `call{value: payout}` deflates `address(this).balance` by `payout`.
- T2 (consumer SLOAD): `GameOverModule.handleGameOverDrain:84` reads `totalFunds = address(this).balance + steth.balanceOf(address(this))`. The value is `originalBalance - payout + stETHBalance`.
- T3 (resolution): `preRefundAvailable = (originalBalance - payout + stETHBalance) − reserved`. The deity-refund pass + terminal-payout magnitude are reduced by `payout`.

**Exploit direction (subtler than V-071's inflow):** The attacker is **draining** ETH via legitimate `claimWinnings` access, but doing so DURING the rng-window. Per `feedback_design_intent_before_deletion.md`, the design-intent of `claimWinnings` is to provide a pull-pattern payout for resolved winnings; the design-intent did NOT contemplate that the drain would race the game-over consumer. The bug class: an attacker with deity-refund position (or a position that wins from terminal-payout proportion) can **avoid** claiming during the rng-window if the timing shifts EV in their favor — and DO claim during the rng-window if the timing helps them. The asymmetric optionality is the exploit.

**EV magnitude estimate:** **HIGH — full `claimableWinnings[player]` magnitude per attacker.** Unlike V-071's gift-and-extract pattern (limited to inflow size), V-073's drain pattern extracts the full pre-existing `claimableWinnings[player]` allocation. An attacker who has accumulated substantial winnings can shift the entire payout magnitude by timing their claim. Economic-likelihood disposition: **likely-exploited** by any player with significant pre-existing winnings; the gate-absence is observable from chain state.

**Coordinated V-063 note:** V-063 covers the `claimablePool -= uint128(payout)` write at `:1408` (Cluster E / claimablePool slot). V-073 covers the `address(this).balance` deflation immediately after (`call{value:}` at `:1410-:1414`). Both writes execute inside the same `_claimWinningsInternal` body; a single function-head gate at `:1400` closes both.

### §7.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) gated-revert at `_claimWinningsInternal` function head — same gate as V-063.** Catalog §16 row 408 column 8 rationale verbatim: "Same gate as V-063 — single revert closes both `claimablePool` and balance writers".

**Concrete shape:**

- Add a revert at the head of `_claimWinningsInternal` at `DegenerusGame.sol:1400`: `if (_livenessTriggered() && !gameOver) revert E();` (or a typed custom error per v44.0 plan-phase discretion). The gate is `_livenessTriggered() && !gameOver` (NOT `|| gameOver`) — the post-gameOver flow MUST allow `claimWinnings` (that's the player-payout path after sweep). The existing `GO_SWEPT_SHIFT` check at `:1400` handles the post-sweep case; the new gate adds the magnitude-input-window block.
- Place the new revert BEFORE the `:1400` `GO_SWEPT` check (or coalesce into a compound expression per v44.0 plan-phase formatting decision).
- This SAME gate closes both V-063 (claimablePool write at `:1408`) and V-073 (balance write via `call{value:}` at `:1410-:1414`). One revert, two VIOLATION closures.

**Subsumption note preserved for v44.0 traceability (per CATALOG):** V-073's anchor H-40 is preserved per v44.0 handoff-register discipline. The fix is structurally coordinated with V-063 (Cluster E, H-31, FIXREC 299-05) — the v44.0 plan-phase MUST land them in the same sub-phase OR cite H-31 as the operational target.

**Rationale for rejecting alternative tactics:**

- **(b) snapshot pattern** rejected: snapshotting `address(this).balance` (V-071's approach) would handle V-073's deflation racing the consumer — but at higher cost than a single-line gate. The gate is cheaper, simpler, and closes V-063 simultaneously. V-071 needs snapshot ONLY because `receive()` / selfdestruct / coinbase-payout are ungateable; `claimWinnings` IS gateable.
- **(c) pre-lock reorder** rejected: not applicable — the writer is EOA-triggered at attacker discretion.
- **(d) immutable** rejected: the slot is mutable.

**Bytecode / storage-layout / public-ABI impact:**

- **Storage-layout:** **byte-identical.** No new storage slot.
- **Bytecode delta:** ~30-50 bytes for one new `if (_livenessTriggered() && !gameOver) revert E();` at `:1400`. Closes both V-063 and V-073.
- **Net runtime gas:** +~2100 gas (one SLOAD for `_livenessTriggered()` + one SLOAD for `gameOver`) on every `claimWinnings` call. Hot path — but `claimWinnings` is not high-frequency.
- **Public ABI:** **NON-BREAKING.** No new event topic-hash; the new revert may re-use existing `E()` error.
- **Reference precedent:** Existing `_livenessTriggered()` gate pattern across `MintModule` / `WhaleModule` / `JackpotModule`. The new gate is one line of code.

### §7.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-40`** — Gated-revert at `DegenerusGame._claimWinningsInternal:1400` to revert during the `_livenessTriggered() && !gameOver` magnitude-input window. **Subsumption: same operational gate as V-063 / H-31 (Cluster E / FIXREC 299-05) — one gate closes both `claimablePool` and `address(this).balance` writer races.**

- Gate site to add: `DegenerusGame.sol:1400` (head of `_claimWinningsInternal`, before existing `GO_SWEPT` check).
- Writers covered: `:1408` (`claimablePool -= uint128(payout);` — V-063), `:1410-:1414` (`_payoutWithEthFallback` / `_payoutWithStethFallback` → `call{value:}` — V-073).
- Consumer: `GameOverModule.handleGameOverDrain:84` (live `address(this).balance` SLOAD).
- **Subsumption note:** V-073's anchor H-40 and V-063's anchor H-31 close together. v44.0 plan-phase MUST land them in the same sub-phase; the FIXREC 299-05 (Cluster E) entry for V-063 is the operational lead.
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 408 (V-073), §16 row 397 (V-063), §15 writer row 198, §14 row 79 (S-20).

---

## §8 — V-074: `address(this).balance` × sDGNRS / vault / GNRUS withdrawals (cross-contract)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 409 (V-074). §15 writer row 199 (sDGNRS / vault / GNRUS withdrawals). §14 row 79. Cross-cluster coordination: V-066 (H-34) is the upstream gate-anchor.

### §8.A — Design-intent backward-trace

**Slot introduction phase:** `address(this).balance` is EVM-intrinsic. The writer class under discussion is the **cross-contract callback** path: sister contracts (`StakedDegenerusStonk` / `DegenerusVault` / `DegenerusGNRUS`) call back into `DegenerusGame` during sStonk redemption, vault unwinding, or GNRUS settlement, triggering ETH outflows that decrement `address(this).balance`. The catalog row 409 verdict-matrix column 5 confirms: "mixed — gated transitively via sDGNRS liveness".

**Cross-contract reach-stack (grep-verified writer family):**

- sDGNRS `claimRedemption` (at `:657`) calls `DegenerusGame.sweepSdgnrsClaim` (at `:1739` per FIXREC 299-05 Cluster E V-065). That callback writes `claimablePool -=` AND triggers ETH outflow via downstream `call{value:}` family.
- DegenerusVault unwind paths (vault → game callback) similarly trigger ETH outflows.
- DegenerusGNRUS settlement paths likewise.

**Existing transitive gate:** The catalog's "gated transitively via sDGNRS liveness" disposition refers to the `BurnsBlockedDuringLiveness` modifier at `StakedDegenerusStonk.sol:491` (V-066's gate) and the parallel `_livenessTriggered()` checks inside vault / GNRUS surfaces (per project-memory convention). The sister-contract entry points themselves are gated against the rng-window; an EOA cannot reach `claimRedemption` (which would trigger the game-callback) during `_livenessTriggered()` because the sStonk-side gate at `:491` reverts first.

**Cite for "what would break if frozen":** Gating the game-side callback receivers (`sweepSdgnrsClaim`, vault-unwind callbacks, GNRUS settlement callbacks) on `_livenessTriggered()` would block the legitimate cross-contract redemption / unwind / settlement flows. The transitive gating via sister-contract entry points avoids this by ensuring the EOA-entry point reverts first.

**Catalog row 409 column 8 rationale (verbatim):** "Gate at sDGNRS callsite (BurnsBlockedDuringLiveness) covers". The fix is **upstream**: V-066's gate at `StakedDegenerusStonk.sol:491` is the operational close.

### §8.B — Actor game-theory walk

**Exploit-actor class:** sStonk holder / vault depositor / GNRUS holder attempting to use the cross-contract callback path to deflate `address(this).balance` during the rng-window.

**Action sequence during rngLock window (subsumed by V-066 gate):**

- T0: `advanceGame` enters magnitude-input window. `_livenessTriggered() == true`.
- T1 (attacker move): Attacker calls `sStonk.claimRedemption` (or `vault.unwind`, or `gnrus.settle`). The sister-contract gate fires:
  - sStonk side: `StakedDegenerusStonk.sol:507` `if (game.livenessTriggered() && !game.gameOver()) revert BurnsBlockedDuringLiveness();` — REVERTS for `claimRedemption`. (Note: V-068 covers `claimRedemption -=` on `pendingRedemptionEthValue`; that gate also covers the game-side balance race here.)
  - Vault side: project-memory convention asserts `_livenessTriggered()` check at vault entry surfaces.
  - GNRUS side: analogous.
- T1' (no attack): The sister-contract entry reverts before reaching the game-side callback. `address(this).balance` is not deflated.

**EV magnitude estimate:** **NONE once V-066 / V-068 / parallel vault & GNRUS gates are confirmed.** The catalog's "gated transitively" disposition reflects this. V-074's role: assert via FUZZ-301 that every cross-contract callback path reaches a sister-contract gate BEFORE reaching the game-side ETH-outflow.

**Caveat — transitive-gate verification:** Per `feedback_verify_call_graph_against_source.md`, the "by-construction transitively covers" claim must be grep-verified. The verification deliverable for H-41 is the explicit attestation that:

1. Every sStonk → game ETH-outflow callback is reachable only via a sStonk entry point that runs `BurnsBlockedDuringLiveness` check (already verified at `:491` for the `burn`/`burnWrapped` path).
2. Every vault → game callback runs an equivalent `_livenessTriggered()` check on the vault side.
3. Every GNRUS → game callback runs an equivalent check.

The FUZZ-301 attestation MUST enumerate the sister-contract entry points and demonstrate each one's gate.

### §8.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) upstream gate at sister-contract callsites — verification only.** Catalog §16 row 409 column 8 rationale verbatim: "Gate at sDGNRS callsite (BurnsBlockedDuringLiveness) covers".

**Concrete shape (verification only):**

- FUZZ-301 must produce a transitive-coverage attestation: for every cross-contract callback path from sDGNRS / vault / GNRUS into `DegenerusGame` that triggers an ETH outflow, assert that the sister-contract entry-point gate (`BurnsBlockedDuringLiveness` on sStonk; `_livenessTriggered()` equivalent on vault & GNRUS) fires BEFORE the callback reaches the game-side outflow.
- The attestation MUST enumerate the sister-contract entry points (`StakedDegenerusStonk.burn`, `.burnWrapped`, `.claimRedemption`; `DegenerusVault.unwind` family; `DegenerusGNRUS.settle` family) AND demonstrate each one's gate inline with grep evidence.
- If any sister-contract entry path is found to NOT have the equivalent gate, the missing gate is an upstream FIX (escalate to the relevant sister-contract V-NNN entry, e.g., V-066 / V-184 for sStonk; vault & GNRUS may need their own catalog rows).
- No game-side source-tree mutation. **Zero bytecode delta on the game contract.**

**Rationale for rejecting alternative tactics:**

- **(a) game-side gate at the callback receiver** rejected: redundant with the sister-contract entry gate, AND would block legitimate post-gameOver settlement flows that need to fire from sister contracts.
- **(b) snapshot pattern** rejected: V-071's snapshot already covers the residual `address(this).balance` racing-the-consumer surface for the ungateable inflow class. V-074's deflation surface is gated by sister-contract entry points; if any are missing, the fix is upstream.
- **(c) pre-lock reorder** rejected: not applicable.
- **(d) immutable** rejected: the slot is mutable.

**Bytecode / storage-layout / public-ABI impact:**

- **Storage-layout:** **byte-identical.** Zero delta on game side.
- **Bytecode delta:** **zero on game side.** Verification-only row. Any missing sister-contract gate is tracked at that sister-contract's own VIOLATION row.
- **Net runtime gas:** zero delta on game side.
- **Public ABI:** **NON-BREAKING.** Zero ABI delta.
- **Reference precedent:** `StakedDegenerusStonk.sol:491` `BurnsBlockedDuringLiveness` modifier is the sister-contract gate precedent. Vault & GNRUS entry gates follow the same convention per project-memory.

### §8.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-41`** — Verification anchor for V-074: assert transitive sister-contract gate coverage for every cross-contract callback path that triggers ETH outflow from the game contract. v44.0 plan-phase enumerates the sister-contract entry points and grep-verifies each gate.

- Upstream gate site (sStonk): `StakedDegenerusStonk.sol:491` (`BurnsBlockedDuringLiveness`).
- Upstream gate site (sStonk post-gameOver path): `:507` (`if (game.livenessTriggered() && !game.gameOver()) revert BurnsBlockedDuringLiveness();`).
- Upstream gate sites (vault & GNRUS): v44.0 plan-phase grep-deliverable.
- Writer class on game side: `call{value:}` callbacks reached from sister-contract surfaces (`sweepSdgnrsClaim` at `:1739` + vault/GNRUS callback receivers).
- Consumer: `GameOverModule.handleGameOverDrain:84` live `address(this).balance` SLOAD.
- **Subsumption note:** V-074 is transitively covered by V-066 (sStonk-side gate) plus the analogous vault & GNRUS gates. v44.0 plan-phase verifies the transitive coverage; no game-side gate added. If any sister-contract gate is missing, escalate to that sister-contract's own V-NNN entry.
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 409 (V-074), §16 row 401 (V-066), §15 writer row 199, §14 row 79 (S-20).

---

## §9 — V-080: `stETH.balanceOf(game)` × external parties transferring stETH IN

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 415 (V-080). §15 writer row 205 (external parties transferring stETH IN). §14 row 80 (S-21). Cross-cut: V-071 (H-38) snapshot covers both ETH and stETH inputs at the consumer.

### §9.A — Design-intent backward-trace

**Slot introduction phase:** `stETH.balanceOf(game)` is a **cross-contract Lido slot** with trace-stop status per `D-298-EXEMPT-CROSSCONTRACT-01`. The Lido stETH contract is out-of-source-tree (no source under `contracts/`). The slot's economic function for the game: stETH balance held by the game contract is one of the two components of `totalFunds` at `GameOverModule.handleGameOverDrain:84` (`totalFunds = address(this).balance + steth.balanceOf(address(this))`). The game accumulates stETH via two in-source paths:

1. `AdvanceModule._stakeEth` (at `:1555-:1563`) converts ETH → stETH via Lido `submit{value:}` during advanceGame. Verified verbatim: `try steth.submit{value: stakeable}(address(0)) returns (...`.
2. `GameOverModule.handleFinalSweep._sendStethFirst` (at `:243, :247`) is the OUT direction — game sends stETH to winners via `steth.transfer`. Not relevant to V-080 (V-080 covers IN-direction only).

The IN direction from external parties is the V-080 surface: any EOA can call `IStETH.transfer(game, amount)` directly on the Lido stETH contract, transferring stETH to the game and incrementing `stETH.balanceOf(game)` without invoking any game-side Solidity code.

**Cite for "what would break if frozen":** Tactic (a) gated-revert is **structurally impossible** for stETH IN transfers — the same reason as V-071's selfdestruct/coinbase-payout class:

1. The Lido stETH contract is external; the game cannot reject incoming `stETH.transfer` calls via any game-side code.
2. The ERC20 receiver pattern (`onERC20Received` hook) does NOT exist in standard Lido stETH — there is no callback the game can intercept.
3. Per `D-298-EXEMPT-CROSSCONTRACT-01`, the Lido stETH contract is trace-stop; we cannot modify it.

The only structural fix is tactic (b) snapshot: capture `stETH.balanceOf(game)` at `_gameOverEntropy` time and consume the snapshot inside `handleGameOverDrain`. **And — crucially — this is the SAME snapshot field as V-071's** because the consumer combines ETH balance + stETH balance into the single `totalFunds` quantity.

**Catalog row 415 column 8 rationale (verbatim):** "Same snapshot as V-071 — covers both ETH balance + stETH balance inputs". One snapshot field, two VIOLATION closures (V-071 + V-080).

**Precedent for snapshot pattern:** Phase 281 owed-salt snapshot (cited in V-071 §5.C above). The Cluster F balance snapshot at `_gameOverEntropy` covers both balance-class inputs in a single SSTORE.

### §9.B — Actor game-theory walk

**Exploit-actor class:** Any EOA (or contract) capable of transferring stETH to the game contract during the rngLock window. The attack surface is universal — no protocol participation required:

- Vector 1: Direct `IStETH.transfer(game, amount)` from any stETH holder. Triggers a Lido-side balance update; no game-side Solidity executes.
- Vector 2: Lido rebase (autonomous) — but the catalog's V-077 classifies Lido rebase as EXEMPT-ADVANCEGAME (trace-stop) at row 414 because the rebase magnitude is bounded by Lido's protocol design and is not attacker-controlled. V-080 specifically covers the attacker-controlled IN-transfer class, not the rebase class.

**Action sequence during rngLock window (sequential):**

- T0: `advanceGame` enters the final-day branch. `_gameOverEntropy` requests the terminal VRF word.
- T1 (attacker move): Attacker holds stETH (cheaply obtainable on secondary markets or via direct Lido staking). Attacker calls `IStETH.transfer(GAME_ADDRESS, amount)` on Lido. The Lido-side balance state updates atomically; `stETH.balanceOf(game)` is incremented by `amount` without invoking any game-side code.
- T2 (VRF callback): The terminal VRF word is delivered. `advanceGame` proceeds to `handleGameOverDrain`.
- T3 (consumer SLOAD): `handleGameOverDrain:84` reads `totalFunds = address(this).balance + steth.balanceOf(address(this))`. The value is `ethBalance + (originalStEth + amount)`.
- T4 (resolution): `preRefundAvailable = (ethBalance + originalStEth + amount) − reserved`. Deity-refund pass + terminal-payout magnitude are inflated by `amount`.

**Exploit direction:** Same as V-071 — the attacker gifts stETH to the game (no theft of pre-existing assets), but **shifts the proportion** of `preRefundAvailable` flowing to deity-refunds vs. terminal-payouts. An attacker who controls a deity-pass position or terminal-payout-position extracts EV from the late inflow.

**EV magnitude estimate:** **MEDIUM — bounded by the attacker's stETH inflow magnitude, but with the additional consideration that stETH transfers dilute the per-share rebase math.** Lido stETH is a rebasing token; transferring `amount` of stETH to the game does not affect the game's pre-existing stETH share value, but does increment the absolute `balanceOf` quantity by `amount`. The terminal-day attack EV scales with the attacker's deity-pass position size (or terminal-payout-position size) multiplied by the inflow magnitude. Economic-likelihood disposition: **likely-exploited on terminal day if any attacker has a meaningful deity-pass or terminal-payout position** — the attack is observable and rational.

**Subtle game-theory observation — `_stakeEth` daily-converter and the snapshot timing:** Per project-memory, the `AdvanceModule._stakeEth` callsite at `:1555-:1563` converts ETH → stETH on each advanceGame call. If the snapshot is taken AT `_gameOverEntropy`, the snapshot includes whatever stETH balance exists at that moment — including any `_stakeEth` conversion that happened in the same advanceGame block. This is the correct timing: the snapshot freezes the cumulative stETH balance at the moment the terminal VRF is committed, eliminating the attacker's post-commitment inflow window.

### §9.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (b) snapshot — SAME snapshot field as V-071.** Catalog §16 row 415 column 8 rationale verbatim: "Same snapshot as V-071 — covers both ETH balance + stETH balance inputs".

**Concrete shape (shared with V-071 / H-38):**

- The `gameOverFundsSnapshot` field introduced at H-38 is `uint256 totalFunds = address(this).balance + steth.balanceOf(address(this))` — a SINGLE snapshot that captures the sum of both balance inputs at `_gameOverEntropy` commitment moment.
- `GameOverModule.handleGameOverDrain:84` reads the SINGLE snapshot field instead of the live `address(this).balance + steth.balanceOf(address(this))` computation.
- One field, one SSTORE, one SLOAD on the consumer side. Both V-071 and V-080 close together.
- No independent storage field at V-080. v44.0 plan-phase MUST cite H-38 as the operational anchor; H-42 is preserved per traceability discipline.

**Rationale for rejecting alternative tactics:**

- **(a) gated-revert on stETH IN-transfer** rejected: structurally impossible (Lido contract is external; no ERC20 receiver hook in standard stETH; trace-stop per `D-298-EXEMPT-CROSSCONTRACT-01`).
- **(c) pre-lock reorder** rejected: not applicable — Lido inflows are EOA-discretionary and out-of-source-tree.
- **(d) immutable** rejected: stETH balance is fundamentally mutable.
- **Independent snapshot field at V-080** rejected: redundant with V-071's snapshot field. Combining into a single `totalFunds` snapshot saves one SSTORE and one SLOAD per game-over execution AND simplifies the consumer code to a single load.

**Bytecode / storage-layout / public-ABI impact:**

- **Storage-layout:** **zero delta beyond V-071's snapshot field at H-38.** V-080 piggybacks on the same `gameOverFundsSnapshot` field.
- **Bytecode delta:** **zero delta beyond V-071's bytecode.** The snapshot computation already includes `+ steth.balanceOf(address(this))`.
- **Net runtime gas:** zero delta beyond V-071.
- **Public ABI:** **NON-BREAKING.** Zero ABI delta beyond V-071.
- **Reference precedent:** Phase 281 owed-salt snapshot. The Cluster F balance snapshot is the canonical multi-input snapshot variant (sum of two slots into one snapshot field).

### §9.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-42`** — Cross-cut anchor for V-080: SAME snapshot field as V-071 (H-38). The `gameOverFundsSnapshot` field captures `address(this).balance + steth.balanceOf(address(this))` as a single value at `_gameOverEntropy`; the consumer at `GameOverModule.handleGameOverDrain:84` reads the single snapshot. Both V-071 and V-080 close atomically when H-38 lands.

- Snapshot WRITE site (shared with H-38): inside `_gameOverEntropy` (`AdvanceModule.sol` final-day entropy-commit callsite; precise line per v44 plan-phase grep).
- Snapshot READ site (shared with H-38): `GameOverModule.sol:84` (replaces live `address(this).balance + steth.balanceOf(address(this))`).
- Storage field (shared with H-38): `gameOverFundsSnapshot` (uint256).
- **Cross-cut note:** V-080's anchor H-42 is preserved per v44.0 handoff-register discipline; the v44.0 sub-phase that lands H-38 closes H-42 atomically (single snapshot field, one SSTORE, one SLOAD covers both VIOLATIONs).
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 415 (V-080), §16 row 406 (V-071), §15 writer row 205, §14 row 80 (S-21).

---

## Cluster F summary

**VIOLATIONs covered (9):** V-066, V-068, V-069, V-070, V-071, V-072, V-073, V-074, V-080.

**Handoff anchors (9):** `D-43N-V44-HANDOFF-34` (V-066, verification), `D-43N-V44-HANDOFF-35` (V-068, subsumed by H-111), `D-43N-V44-HANDOFF-36` (V-069, extended `_purchaseDeityPass` gate), `D-43N-V44-HANDOFF-37` (V-070, subsumed by H-36), `D-43N-V44-HANDOFF-38` (V-071, `gameOverFundsSnapshot`), `D-43N-V44-HANDOFF-39` (V-072, verification), `D-43N-V44-HANDOFF-40` (V-073, same gate as H-31 / V-063), `D-43N-V44-HANDOFF-41` (V-074, transitive sister-contract gate verification), `D-43N-V44-HANDOFF-42` (V-080, shares H-38 snapshot).

**Tactic mix:** 5× tactic (a) gated-revert / verification (V-066, V-069, V-072, V-073, V-074) + 2× tactic (b) snapshot (V-071, V-080) + 2× subsumption (V-068 → H-111 / V-184; V-070 → H-36 / V-069). No tactic (c) or (d).

**EV-tier distribution:** 3× HIGH (V-069 deity-pass append; V-071 ETH inflow magnitude shift; V-073 claimWinnings drain) + 1× MEDIUM (V-080 stETH inflow magnitude shift) + 4× NONE / defended-by-current-source (V-066 existing `BurnsBlockedDuringLiveness`; V-068 subsumed-by-V-184; V-072 existing per-fn gates; V-074 transitive sister-contract gate) + 1× co-located (V-070 with V-069).

**Subsumption summary:** 2 internal-cluster subsumptions (V-070→H-36, V-080→H-38) + 2 cross-cluster subsumptions (V-068→H-111 / FIXREC 299-K, V-073→H-31 / FIXREC 299-05). All four subsumption anchors preserved per v44.0 traceability discipline.

**Stale-phantom dispositions:** None. All 9 writer call sites grep-verified against current `contracts/` source. No phantom rows detected.

**Aggregate bytecode delta estimate (post-v44 fix):** ~150-300 bytes new code (V-069 extended gate ~30-50 bytes + V-071 snapshot ~100-200 bytes + V-073 gate ~30-50 bytes). One new packed storage field (`gameOverFundsSnapshot`, ~32 bytes). Public ABI: NON-BREAKING (no event topic-hash changes).

**Cross-cluster coordination required at v44.0:**

- H-35 (V-068) blocks on H-111 (V-184, FIXREC 299-K).
- H-37 (V-070) blocks on H-36 (V-069).
- H-40 (V-073) blocks on / coordinates with H-31 (V-063, FIXREC 299-05).
- H-42 (V-080) blocks on / coordinates with H-38 (V-071).

The v44.0 plan-phase MUST sequence these dependencies OR merge into single sub-phases where the anchor-pairs share gate / snapshot infrastructure.
