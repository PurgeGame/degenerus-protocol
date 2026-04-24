# v31.0 Phase 245 — sDGNRS Redemption Gameover Safety + Pre-Existing Gameover Invariant Re-Verification (consolidated deliverable)

Status: FINAL — READ-ONLY (locked at SUMMARY commit per CONTEXT.md D-05)
Audit baseline: 7ab515fe
Audit head:     cc68bfc7
In-scope commits: 771893d1 (gameover liveness + sDGNRS redemption protection — primary driver) + cc68bfc7 (BAF-coupling addendum for GOE-06 candidate 1)
Phase:          245-sdgnrs-redemption-gameover-safety
Owning plans:   245-01 (SDR — 8 REQs) + 245-02 (GOE — 6 REQs + consolidation)
Severity bar:   {SAFE, INFO, LOW, MEDIUM, HIGH, CRITICAL} per CONTEXT.md D-08; KI envelope rows use `RE_VERIFIED_AT_HEAD cc68bfc7` annotation per CONTEXT.md D-24
Finding-IDs:    NOT emitted in this phase per CONTEXT.md D-23 (Phase 246 FIND-01 owns assignment); §5 Phase 246 Input subsection aggregates candidates
Working files:  audit/v31-245-SDR.md (245-01, 924 lines, appendix) + audit/v31-245-GOE.md (245-02, 432 lines, appendix); both remain on disk per CONTEXT.md D-05

## §0 — Per-Phase Verdict Heatmap (planner-discretion readability aid per CONTEXT.md Discretion)

| REQ-ID | Verdict Rows | Floor Severity | KI Envelope | Owning Plan |
| --- | --- | --- | --- | --- |
| SDR-01 | 6 foundation (`SDR-01-T{a-f}`) + 3 standard (`SDR-01-V01..V03`) | SAFE | n/a | 245-01 |
| SDR-02 | 4 standard (`SDR-02-V01..V04`) | SAFE | n/a | 245-01 |
| SDR-03 | 3 standard (`SDR-03-V01..V03`) | SAFE | n/a | 245-01 |
| SDR-04 | 4 standard (`SDR-04-V01..V04`) | SAFE | n/a | 245-01 |
| SDR-05 | 6 standard (`SDR-05-V01..V06`) | SAFE | n/a | 245-01 |
| SDR-06 | 7 standard (`SDR-06-V01..V07`) | SAFE | n/a | 245-01 |
| SDR-07 | 6 standard (`SDR-07-V01..V06`) | SAFE | n/a | 245-01 |
| SDR-08 | 4 standard (`SDR-08-V01..V04`) — V01 is `RE_VERIFIED_AT_HEAD cc68bfc7` carrier | SAFE (3 SAFE + 1 RE_VERIFIED_AT_HEAD) | EXC-03 RE_VERIFIED_AT_HEAD cc68bfc7 | 245-01 |
| GOE-01 | 2 standard (`GOE-01-V01..V02`) — V01 is `RE_VERIFIED_AT_HEAD cc68bfc7` carrier for EXC-03 envelope | SAFE (1 SAFE + 1 RE_VERIFIED_AT_HEAD) | EXC-03 RE_VERIFIED_AT_HEAD cc68bfc7 | 245-02 |
| GOE-02 | 3 standard (`GOE-02-V01..V03`) | SAFE | n/a | 245-02 |
| GOE-03 | 3 standard (`GOE-03-V01..V03`) | SAFE | n/a | 245-02 |
| GOE-04 | 3 standard (`GOE-04-V01..V03`) — V02 is `RE_VERIFIED_AT_HEAD cc68bfc7` carrier for EXC-02 envelope | SAFE (2 SAFE + 1 RE_VERIFIED_AT_HEAD) | EXC-02 RE_VERIFIED_AT_HEAD cc68bfc7 | 245-02 |
| GOE-05 | 2 standard (`GOE-05-V01..V02`) | SAFE | n/a | 245-02 |
| GOE-06 | 2 standard (`GOE-06-V01..V02`) — Candidate 1 + Candidate 2 per CONTEXT.md D-12 | SAFE (per D-13 aggregate) | n/a | 245-02 |

**Phase-wide aggregate:**

- **Total verdict rows:** 40 (SDR bucket) + 15 (GOE bucket) = **55 verdict rows** (46 standard + 6 SDR-01 foundation + 3 RE_VERIFIED_AT_HEAD carriers)
- **Finding candidates:** 0 (zero across both buckets)
- **Floor severity:** SAFE across all 14 REQs
- **KI envelopes RE_VERIFIED_AT_HEAD cc68bfc7:** EXC-02 (GOE-04-V02) + EXC-03 (SDR-08-V01 carrier + GOE-01-V01 carrier for full-scope re-verify)
- **Pre-Flag closures:** 17 Phase-244 Pre-Flag bullets at v31-244-PER-COMMIT-AUDIT.md L2477-2519 all CLOSED (10 SDR-grouped in §SDR sections + 7 GOE-grouped in §GOE sections); none rolled forward to Phase 246
- **Scope-guard:** zero F-31-NN IDs / zero `contracts/` writes / zero `test/` writes / zero edits to `audit/v31-243-DELTA-SURFACE.md` or `audit/v31-244-PER-COMMIT-AUDIT.md`

---

## §1 — SDR Bucket (commit 771893d1 — sDGNRS redemption deep sub-audit; plan 245-01)

*(Embedded verbatim from `audit/v31-245-SDR.md` at HEAD cc68bfc7; file-level header dropped — consolidated header above replaces it.)*

## §0 — Per-Bucket Verdict Count Card

| REQ-ID | Verdict Rows | Finding Candidates | KI Envelope Status | Floor Severity |
| --- | --- | --- | --- | --- |
| SDR-01 | 6 foundation (`SDR-01-T{a-f}`) + 3 standard (`SDR-01-V01..V03`) | 0 | n/a | SAFE |
| SDR-02 | 4 standard (`SDR-02-V01..V04`) | 0 | n/a | SAFE |
| SDR-03 | 3 standard (`SDR-03-V01..V03`) | 0 | n/a | SAFE |
| SDR-04 | 4 standard (`SDR-04-V01..V04`) | 0 | n/a | SAFE |
| SDR-05 | 6 standard (`SDR-05-V01..V06`) | 0 | n/a | SAFE |
| SDR-06 | 7 standard (`SDR-06-V01..V07`) | 0 | n/a | SAFE |
| SDR-07 | 6 standard (`SDR-07-V01..V06`) | 0 | n/a | SAFE |
| SDR-08 | 4 standard (`SDR-08-V01..V04`) — V01 is `RE_VERIFIED_AT_HEAD cc68bfc7` carrier | 0 | EXC-03 RE_VERIFIED_AT_HEAD cc68bfc7 | SAFE (3 SAFE + 1 RE_VERIFIED_AT_HEAD) |

## §SDR-01 — Redemption state-transition × gameover-timing matrix (6 timings + claimRedemption ungated-by-design property)

### §SDR-01 — 6 foundation rows (timing matrix per CONTEXT.md D-15)

Per REQUIREMENTS.md L72-78 and CONTEXT.md D-14 SDR-01 vector (a), six distinct gameover-timing transitions are identified. The state-space partitions on {State-0 (pre-liveness), State-1 (livenessTriggered && !gameOver), State-2 (gameOver latched)} × {request step, resolve step, claim step}. Foundation rows `SDR-01-T{a-f}` establish reachability-per-timing; `SDR-02..08` cite these back with their own REQ-specific vectors.

| Timing | Label | Reachable code paths at HEAD cc68bfc7 | Gameover-latch point | Referenced by SDR-NN V-rows |
| --- | --- | --- | --- | --- |
| SDR-01-Ta | (a) pre-liveness all 3 steps (State-0 → State-0 → State-0) | burn sDGNRS:486-495 (or burnWrapped sDGNRS:506-516) → L493 `_submitGamblingClaim` → L744-746 `_submitGamblingClaimFrom` (sDGNRS:752-814) → L789 `pendingRedemptionEthValue += ethValueOwed` + L790 `pendingRedemptionEthBase += ethValueOwed` → advanceGame normal-tick rngGate at AdvanceModule:1148-1214 → L1193 `sdgnrs.resolveRedemptionPeriod(redemptionRoll, flipDay)` → sDGNRS:585-610 (L593 roll-adjust) → claimRedemption sDGNRS:618-684 (L657 `pendingRedemptionEthValue -= totalRolledEth` + L683 `_payEth`) | N/A — timing completes before liveness or gameover fires (all 3 steps in State-0) | SDR-02, SDR-05, SDR-07 |
| SDR-01-Tb | (b) request pre-liveness, resolve+claim in State-1 (State-0 → State-1 → State-1) | burn (State-0) → _submitGamblingClaimFrom (wei enters ledger in State-0) → advanceGame tick that fires `_livenessTriggered()` at Storage:1235-1243 (day-math threshold crossed per Phase 244 GOX-04-V01) → resolve path: rngGate at AdvanceModule:1148-1199 fires L1193 resolveRedemptionPeriod if VRF word delivered AND `gameOver != true` (rngGate always hits L1193 when it reaches that branch; liveness state is irrelevant inside rngGate) → claimRedemption callable in State-1 (ungated-by-state per D-09 + V03) | Liveness fires at advanceGame tick T_N (Storage:1239-1242 predicate); State-2 latches only at first handleGameOverDrain invocation (GameOverModule:141 `gameOver = true`) | SDR-02, SDR-04, SDR-05, SDR-06 |
| SDR-01-Tc | (c) request pre-liveness, resolve State-1, claim post-gameOver (State-0 → State-1 → State-2) | burn (State-0) → _submitGamblingClaim → resolve in State-1 normal-tick (period-close at sDGNRS:593) OR resolve defers to _gameOverEntropy if VRF pending at liveness (Timing Tf) → handleGameOverDrain fires (GameOverModule:79-189) → L94 + L157 read `pendingRedemptionEthValue()` and subtract from drain base → claimRedemption in State-2 (any time before handleFinalSweep day+30) | handleGameOverDrain invocation sets `gameOver = true` at GameOverModule:141 + GO_JACKPOT_PAID_MASK=1 at L148 | SDR-03, SDR-04, SDR-05 |
| SDR-01-Td | (d) resolved pre-gameOver, claim post-gameOver (State-0 → State-0 → State-2) | burn (State-0) → _submitGamblingClaim → resolve at sDGNRS:593 via rngGate L1193 (State-0) → handleGameOverDrain subtracts pendingRedemptionEthValue at GameOverModule:94 + :157 → claimRedemption in State-2 | handleGameOverDrain invocation (day after resolve completed) | SDR-03, SDR-04, SDR-05 |
| SDR-01-Te | (e) request post-gameOver — BLOCKED (State-2 → N/A → N/A) | burn: L487 `if (game.gameOver()) { (ethOut,stethOut) = _deterministicBurn(msg.sender, amount); return (ethOut,stethOut,0); }` gameOver short-circuit → `_deterministicBurnFrom` sDGNRS:527-569 → NO redemption created, no pendingRedemption* write; burnWrapped: L507 `livenessTriggered() && !gameOver()` revert check does NOT fire (gameOver is true) → L508-509 `dgnrsWrapper.burnForSdgnrs` → L509 `if (game.gameOver()) { _deterministicBurnFrom(...); return; }` short-circuit → same deterministic path | gameOver already latched at entry | SDR-06, SDR-07 |
| SDR-01-Tf | (f) VRF-pending at liveness, resolves via `_gameOverEntropy` fallback (State-0 → State-2 fallback → State-2) | burn (State-0) → _submitGamblingClaim (wei enters ledger) → advanceGame fires liveness (day-math OR Tier-1 14-day VRF-dead grace per Storage:1241-1242 + Phase 244 GOX-04-V02) → VRF request pending (rngRequestTime != 0) → `_handleGameOverPath` at AdvanceModule:519-633 → L560 `_gameOverEntropy` → L1237-1259 VRF-available branch OR L1263-1293 prevrandao-fallback branch; BOTH branches call `sdgnrs.resolveRedemptionPeriod(redemptionRoll, flipDay)` (L1256 VRF-available / L1286 fallback) → after `_handleGameOverPath` delegates to handleGameOverDrain which sets gameOver=true → claimRedemption in State-2 | `_handleGameOverPath` gameOver-branch set after delegate to handleGameOverDrain (GameOverModule:141) | SDR-08, SDR-05, SDR-04 |

**Foundation-row notes:**
- `_submitGamblingClaimFrom` at sDGNRS:752-814 updates BOTH `pendingRedemptionEthValue` (L789) AND `pendingRedemptionEthBase` (L790) at burn time. The immediate `pendingRedemptionEthValue +=` ensures `pendingRedemptionEthValue >= pendingRedemptionEthBase` at resolve-time L593, making the `pendingRedemptionEthValue - pendingRedemptionEthBase + rolledEth` subtraction underflow-free by construction.
- Three external callers of sDGNRS.burn per D-243-X022/X023/X024: DegenerusStonk.sol:231 (wrapper self-burn), DegenerusStonk.sol:312 (yearSweep), DegenerusVault.sol:741 (vault wrapper). burnWrapped has zero programmatic callers per D-243-X025 (player-facing external only).
- `_gameOverEntropy` carries TWO redemption-resolve call sites: L1256 (VRF-available branch, currentWord != 0) and L1286 (prevrandao-fallback branch, elapsed >= `_VRF_GRACE_PERIOD` = 14 days at Storage:203). Branch disjointness is proven in SDR-08-V04.
- handleFinalSweep at GameOverModule:196-216 operates on the Game contract's own `address(this).balance` (L207), NOT sDGNRS's balance — sDGNRS's pendingRedemptionEthValue-reserved ETH is held on the sDGNRS contract itself and is never touched by handleFinalSweep. Covered in SDR-04-V02 + SDR-04-V04 (Task 2).

### §SDR-01 — Standard verdict rows (adversarial vectors SDR-01a + SDR-01b + SDR-01c per D-14)

| Verdict Row ID | REQ-ID | Source Row(s) | File:Line | Adversarial Vector | Verdict | Evidence | Owning Commit SHA |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SDR-01-V01 | SDR-01 | D-243-C013, D-243-C014, D-243-F011, D-243-F012, D-243-I017 | contracts/StakedDegenerusStonk.sol:486-516 + :618-684 | SDR-01a all 6 gameover-timing transitions reachable-path enumeration (foundation rows SDR-01-T{a-f}) | SAFE | Every reachable state-transition for the 3-step flow {burn/request, resolve, claim} × 3 states {State-0, State-1, State-2} maps to exactly one of {Ta, Tb, Tc, Td, Te, Tf}. State-1 request (any timing starting "burn in State-1") is UNREACHABLE because burn at L491 + burnWrapped at L507 revert with `BurnsBlockedDuringLiveness` in State-1 (cross-cite Phase 244 GOX-02-V01/V02). The six foundation rows exhaustively enumerate the reach-space at HEAD cc68bfc7. | 771893d1 |
| SDR-01-V02 | SDR-01 | D-243-C013, D-243-C014, D-243-C015, D-243-C017, D-243-C026, GOX-04-V01, GOX-04-V02, GOX-06-V02 | contracts/storage/DegenerusGameStorage.sol:1235-1243 + contracts/modules/DegenerusGameAdvanceModule.sol:519-633 | SDR-01b per-timing gameover-latch point identification | SAFE | State-0 → State-1 latch is triggered by the Storage:1239-1242 liveness predicate — `lvl==0 && currentDay - psd > 365` OR `lvl!=0 && currentDay - psd > 120` OR `rngStart != 0 && block.timestamp - rngStart >= 14 days`. State-1 → State-2 latch is set by `handleGameOverDrain` at GameOverModule:141 (`gameOver = true`). _handleGameOverPath at AdvanceModule:519-633 gates the flow: L540 `if (gameOver)` → handleFinalSweep; L551 `if (!_livenessTriggered()) return (false, 0)`; then L560 `_gameOverEntropy` (for Tf fallback resolve) and L625-630 delegatecall to handleGameOverDrain (drain + latch). Cross-cite Phase 244 GOX-06-V02 for the gameOver-before-liveness ordering rationale. | 771893d1 |
| SDR-01-V03 | SDR-01 | Pre-Flag bullet L2477 (claimRedemption ungated), D-243-I019 | contracts/StakedDegenerusStonk.sol:618-624 | SDR-01c claimRedemption ungated-by-design property-to-prove SAFE per CONTEXT.md D-09 (absorbed into SDR-01; NO standalone INFO finding-candidate per D-09) | SAFE | Implicit gate is algorithmically load-bearing, not a convention accident. Trace: L620 `claim = pendingRedemptions[player]`; L621 `if (claim.periodIndex == 0) revert NoClaim()` — gates on "player has a pending claim"; L623-624 `period = redemptionPeriods[claim.periodIndex]; if (period.roll == 0) revert NotResolved()` — gates on "claimed period has been rolled". Four-actor analysis (player/admin/validator/VRF oracle per Phase 238 D-07): (player) takes no args, cannot pass malicious calldata; (admin) no admin path writes `claim.roll` directly — only resolveRedemptionPeriod writes it via onlyGame modifier sDGNRS:586; (validator) tx ordering cannot bypass roll != 0 because roll is written atomically in resolveRedemptionPeriod; (VRF oracle) claimRedemption reads no VRF state (no rngWord, no rngRequestTime, no grace-period check). The "can be called in any state" property is DESIGN — post-gameOver claim MUST remain reachable; starving it in State-1 would strand pending wei. No INFO emitted per D-09. | 771893d1 |

**Pre-Flag closure notes (§SDR-01):**

- Pre-Flag L2477 (`claimRedemption()` at sDGNRS:618 NOT gated by livenessTriggered OR gameOver — relies on `redemptionPeriods[claim.periodIndex].roll != 0` gate) → CLOSED via SDR-01-V03 (property-to-prove SAFE per CONTEXT.md D-09; implicit gate algorithmically load-bearing under all 6 timings × 4 actor classes; no standalone INFO finding-candidate emitted).
- Pre-Flag L2478 (`resolveRedemptionPeriod` at sDGNRS:585 called from BOTH `rngGate` normal-tick AND `_gameOverEntropy` L1286; two distinct callers with different gating) → CLOSED via SDR-01-Ta foundation row (rngGate normal-tick L1193 covers Ta/Tb/Td) + SDR-01-Tf foundation row (_gameOverEntropy L1256 VRF-available / L1286 fallback covers Tf); additional L1256 site (not mentioned in Pre-Flag) discovered and also covered via SDR-08-V02 (Task 3). All THREE call sites in AdvanceModule identified: L1193 rngGate, L1256 _gameOverEntropy VRF-available, L1286 _gameOverEntropy fallback.

## §SDR-02 — pendingRedemptionEthValue accounting exactness (per-entry + per-exit wei ledger)

### Per-entry sites (wei enters `pendingRedemptionEthValue`)

**Single immediate-entry site — `_submitGamblingClaimFrom` at sDGNRS:752-814:**

Trace at HEAD cc68bfc7:
1. L763 `if (redemptionPeriodBurned + amount > redemptionPeriodSupplySnapshot / 2) revert` — 50% supply cap per period
2. L769-772 `totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue` — subtracts existing ledger from proportional base
3. L773 `ethValueOwed = (totalMoney * amount) / supplyBefore` — proportional wei owed to this burn
4. **L789 `pendingRedemptionEthValue += ethValueOwed`** — PRIMARY entry site into the running-total ledger
5. **L790 `pendingRedemptionEthBase += ethValueOwed`** — period-local accumulator for the roll-adjust at resolve

Both writes atomic in the same function body; no external call between them. `ethValueOwed` value equality means entry is `value-in` to both fields simultaneously.

**Second-stage adjust site — `resolveRedemptionPeriod` at sDGNRS:592-594:**

Trace:
1. L592 `rolledEth = (pendingRedemptionEthBase * roll) / 100` — roll is bounded [25, 175] by AdvanceModule:1189-1191 (`(word >> 8) % 151 + 25`)
2. **L593 `pendingRedemptionEthValue = pendingRedemptionEthValue - pendingRedemptionEthBase + rolledEth`** — roll-adjust (net delta = `(roll/100 - 1) * pendingRedemptionEthBase`)
3. L594 `pendingRedemptionEthBase = 0` — period-local reset

Net wei delta at resolve:
- roll = 100 → `rolledEth == pendingRedemptionEthBase` → `pendingRedemptionEthValue` unchanged (1x payout)
- roll > 100 (up to 175) → `rolledEth > pendingRedemptionEthBase` → `pendingRedemptionEthValue` INCREASES by `(roll/100 - 1) * base` (bonus for the claimant)
- roll < 100 (down to 25) → `rolledEth < pendingRedemptionEthBase` → `pendingRedemptionEthValue` DECREASES by `(1 - roll/100) * base` (wei stays in sDGNRS balance but is no longer reserved; de-facto refunds to the pool)

Underflow safety at L593: because L789 always increments `pendingRedemptionEthValue` by the SAME `ethValueOwed` that L790 increments `pendingRedemptionEthBase` by, the invariant `pendingRedemptionEthValue >= pendingRedemptionEthBase` holds at period-close time regardless of prior ledger state. No `unchecked` block needed; Solidity 0.8.34 checked arithmetic is safe by construction.

### Per-exit sites (wei exits `pendingRedemptionEthValue`)

**True-decrement exits (state-write that reduces the running total):**

1. **`claimRedemption` L657 `pendingRedemptionEthValue -= totalRolledEth`** — primary payout exit; `totalRolledEth = (claim.ethValueOwed * roll) / 100` per L632. Decrement matched by `_payEth(player, ethDirect)` at L683 (direct ETH paid) + the lootbox game-internal debit via `game.resolveRedemptionLootbox(player, lootboxEth, entropy, actScore)` at L672 (ETH routed as lootbox rewards, stays in sDGNRS contract's broader accounting).
2. **`resolveRedemptionPeriod` L593 (roll < 100 case)** — DE-FACTO refund to pool (subtraction `- pendingRedemptionEthBase + rolledEth` is net-negative when roll < 100). Wei stays in sDGNRS balance but leaves the reserved ledger. No ETH transfer; the wei becomes free for any subsequent `_deterministicBurnFrom` payout.

**Non-decrement reads — the L535/L94/L157 "subtract from payout base" sites:**

3. **`_deterministicBurnFrom` L535** — `totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue`. This is a READ that excludes reserved wei from the deterministic-burn PAYOUT BASE; `pendingRedemptionEthValue` is NOT decremented here. Function scope: post-gameOver burns (L487 short-circuit) where gambling-path claims co-exist with deterministic burns of the same contract's ETH balance.
4. **`handleGameOverDrain` L94** (pre-refund): `reserved = uint256(claimablePool) + IStakedDegenerusStonk(ContractAddresses.SDGNRS).pendingRedemptionEthValue()` — interface `view` call, READ only; drain skips reserved wei when computing `preRefundAvailable`.
5. **`handleGameOverDrain` L157** (post-refund, after deity-pass refunds adjust `claimablePool`): same READ pattern; drain skips reserved wei when computing `available` for the 33/33/34 split in `_sendToVault` L225-233.

### Wei-invariant summary

For every wei entering `pendingRedemptionEthValue` via L789, exactly one of the following happens:
- **(path A — 1x or better)** roll >= 100: reserved wei persists through resolve (roll-adjust may ADD more). At claim, L657 decrement matches L683 `_payEth` payout → claimer receives `(claim.ethValueOwed * roll) / 100` wei.
- **(path B — partial refund)** roll < 100: L593 roll-adjust reduces reserved ledger by `(1 - roll/100) * base`. At claim, L657 decrement equals `(claim.ethValueOwed * roll) / 100` → claimer receives reduced payout; the `(1 - roll/100) * base` wei is de-reserved and absorbed back into sDGNRS's unreserved balance (benefits non-gambling burners via `_deterministicBurnFrom`'s `totalMoney`).
- **(path C — gameOver interception)** gameOver latches before claim: handleGameOverDrain at L94 + L157 reads and excludes reserved wei from the drain split; wei remains physically on sDGNRS; claimer claims via L657 at any point pre day+30; reserved wei is preserved through terminal sweeps.

Per-entry = per-exit exactness: **IN(L789) matched by OUT(L657 decrement)** for the claiming path; the L593 roll-below-100 path is a net-negative ENTRY adjustment (not a separate exit) because the SAME base amount is accounted for in the net delta.

### Verdict rows

| Verdict Row ID | REQ-ID | Source Row(s) | File:Line | Adversarial Vector | Verdict | Evidence | Owning Commit SHA |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SDR-02-V01 | SDR-02 | D-243-C013, D-243-C014, D-243-F011, D-243-F012, D-243-I019, Pre-Flag bullet L2481 | contracts/StakedDegenerusStonk.sol:789-790 + :592-594 | SDR-02a per-entry accounting — immediate burn-time entry at L789/L790 + roll-adjust at L593 | SAFE | Two-stage entry invariant: every `_submitGamblingClaimFrom` call increments BOTH `pendingRedemptionEthValue` (L789) AND `pendingRedemptionEthBase` (L790) by the same `ethValueOwed`. At period-close (L593), `pendingRedemptionEthValue = pendingRedemptionEthValue - pendingRedemptionEthBase + rolledEth` guarantees `>=0` because `pendingRedemptionEthValue >= pendingRedemptionEthBase` by construction (every increment to base was matched by an increment to value). Roll bounds [25,175] enforced at AdvanceModule:1189 + 1253 + 1283 via `((word >> 8) % 151) + 25`. No dust, no overshoot. | 771893d1 |
| SDR-02-V02 | SDR-02 | D-243-C013, D-243-C014, Pre-Flag bullet L2482, D-243-I020 | contracts/StakedDegenerusStonk.sol:527-569 | SDR-02b `_deterministicBurnFrom` L535 subtracts `pendingRedemptionEthValue` from deterministic-payout base | SAFE | L535 `totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue` excludes reserved wei from the proportional-payout base computation at L536; `pendingRedemptionEthValue` is NEVER decremented here (read-only exclusion). Checked arithmetic at Solidity 0.8.34 — if reserved wei ever exceeded `ethBal + stethBal + claimableEth`, L535 would revert on underflow (defensive). In practice reserved wei is physically on the sDGNRS contract, so `ethBal` alone exceeds `pendingRedemptionEthValue` in the typical post-burn state. No double-counting — the same wei cannot be paid out via both `_deterministicBurnFrom` (excluded via L535) and `claimRedemption` (tracked via L657). | 771893d1 |
| SDR-02-V03 | SDR-02 | D-243-C017, D-243-X058, D-243-X059, GOX-03-V01 (shared-context primary), GOX-03-V02 (shared-context primary) | contracts/modules/DegenerusGameGameOverModule.sol:94 + :157 | SDR-02b `handleGameOverDrain` L94/L157 read-subtract pattern | SAFE | Both sites use `IStakedDegenerusStonk(ContractAddresses.SDGNRS).pendingRedemptionEthValue()` (interface `external view` per IStakedDegenerusStonk.sol:88-90) — no state write, no reentrancy surface. L94 pre-refund + L157 post-refund bracket the deity-pass refund loop at L109-138. `pendingRedemptionEthValue` is NEVER decremented by handleGameOverDrain (only READ), so the wei stays physically on the sDGNRS contract for later claimRedemption. Primary closure via Phase 244 GOX-03-V01/V02; SDR-02 cross-cites. | 771893d1 |
| SDR-02-V04 | SDR-02 | D-243-C013, D-243-C014, D-243-I020 | contracts/StakedDegenerusStonk.sol:585-610 (period-close mass wei flow) | SDR-02a/b — wei-conservation across all 6 timings (cross-cite to SDR-05 for worked wei-ledger examples) | SAFE | Per-timing wei flow: Ta {IN at L789, adjusted at L593, OUT at L657}; Tb {IN in State-0, adjusted in State-1, OUT in State-1}; Tc {IN State-0, adjusted State-1, reserved through drain L94/L157, OUT in State-2}; Td {IN State-0, adjusted State-0, reserved through drain, OUT State-2}; Te {no IN (gameOver short-circuit)}; Tf {IN State-0, adjusted by _gameOverEntropy L1256/L1286, reserved through drain, OUT State-2}. All per-timing worked wei ledgers deferred to §SDR-05 (Task 2) per plan ordering — this row asserts invariant holds across the full matrix; worked-examples prove it per-timing. | 771893d1 |

**Pre-Flag closure notes (§SDR-02):**

- Pre-Flag L2481 (pendingRedemptionEthValue roll-adjust formula at sDGNRS:593 — conservation invariant) → CLOSED via SDR-02-V01 (two-stage entry invariant + roll-bounded [25,175] + underflow-free by construction) + SDR-02-V04 (per-timing invariant preservation).
- Pre-Flag L2482 (`_deterministicBurnFrom` at sDGNRS:535 subtracts pendingRedemptionEthValue from payout base) → CLOSED via SDR-02-V02 (exclusion-from-payout-base proof; no double-counting; read-only).

## §SDR-03 — handleGameOverDrain subtracts full pendingRedemptionEthValue BEFORE 33/33/34 split (multi-tx drain depth)

### Read trace — handleGameOverDrain at GameOverModule:79-189

1. **L80 — idempotency gate:** `if (_goRead(GO_JACKPOT_PAID_SHIFT, GO_JACKPOT_PAID_MASK) != 0) return;` — if the function has previously fired `_sendToVault`, subsequent invocations short-circuit. The bit is set at L148 (see step 5) and has NO clear-path anywhere in the contract tree (verified via `grep -rn 'GO_JACKPOT_PAID' contracts/` — only one writer at L148 with value 1; no reset).
2. **L84-86 — balance snapshot:** `ethBal = address(this).balance; stBal = steth.balanceOf(address(this)); totalFunds = ethBal + stBal`. Read-only; no state write.
3. **L87-95 — pre-refund reserved subtraction:**
   - L93-94 `reserved = uint256(claimablePool) + IStakedDegenerusStonk(ContractAddresses.SDGNRS).pendingRedemptionEthValue();`
   - L95 `preRefundAvailable = totalFunds > reserved ? totalFunds - reserved : 0;`
   
   The `IStakedDegenerusStonk.pendingRedemptionEthValue()` call at L94 reads the current ledger value via the `external view` interface at IStakedDegenerusStonk.sol:88-90. No snapshot; direct read of sDGNRS storage slot at the exact moment of drain.
4. **L100-104 — RNG gate:** `if (preRefundAvailable != 0) { rngWord = rngWordByDay[day]; if (rngWord == 0) revert E(); }`. Defensive: caller (_handleGameOverPath at AdvanceModule:519-633) already guarantees VRF word available before calling handleGameOverDrain via L559 `if (rngWordByDay[day] == 0) { ... _gameOverEntropy ... }`. Double-check is a belt-and-suspenders safeguard.
5. **L108-138 — deity-pass refund loop:** refunds `claimablePool` growths for levels 0-9 within the `preRefundAvailable` budget. `pendingRedemptionEthValue` is NOT modified in this loop.
6. **L141-148 — terminal latch:**
   - L141 `gameOver = true;` (State-2 latch)
   - L142 `_goWrite(GO_TIME_SHIFT, GO_TIME_MASK, uint48(block.timestamp));` (gameOver timestamp for the 30-day window)
   - L145-146 `charityGameOver.burnAtGameOver(); dgnrs.burnAtGameOver();` (cascades to sDGNRS:462 via the dgnrs wrapper)
   - **L148** `_goWrite(GO_JACKPOT_PAID_SHIFT, GO_JACKPOT_PAID_MASK, 1);` — idempotency SET (matches L80 check; from this point, re-entry is short-circuited)
7. **L153-158 — post-refund reserved subtraction:**
   - L156-157 `postRefundReserved = uint256(claimablePool) + IStakedDegenerusStonk(ContractAddresses.SDGNRS).pendingRedemptionEthValue();`
   - L158 `available = totalFunds > postRefundReserved ? totalFunds - postRefundReserved : 0;`
   
   The second `pendingRedemptionEthValue()` call at L157 re-reads the ledger — necessary because the deity-pass refunds in steps 5 grew `claimablePool`, and the drain math must account for post-refund `claimablePool` plus the same reserved sDGNRS ETH value.
8. **L160 — short-circuit:** `if (available == 0) return;` — if nothing remains after reserved + refunds, exit (idempotency bit already set at L148).
9. **L165-177 — terminal decimator jackpot:** 10% of `available` distributed (reduces `remaining`).
10. **L181-188 — terminal jackpot + vault split:** L182-184 `runTerminalJackpot(remaining, lvl+1, rngWord)`; L185-187 `if (remaining != 0) _sendToVault(remaining, stBal)` which executes the 33/33/34 split at L225-233.

**Key invariants established at HEAD cc68bfc7:**
- Subtraction at L94 + L157 precedes any call to `_sendToVault` (the 33/33/34 split) — BOTH subtractions occur BEFORE the L225-233 split is executed.
- `pendingRedemptionEthValue()` is `external view` at IStakedDegenerusStonk.sol:88-90 — no reentrancy surface when the STATICCALL fires from handleGameOverDrain.
- L148 GO_JACKPOT_PAID bit is set IRREVERSIBLY after the terminal latch (L141-146); no contract function clears it. Re-entering handleGameOverDrain after L148 short-circuits at L80.
- STAGE_TICKETS_WORKING at AdvanceModule:597/616 defers the drain to a subsequent advanceGame tick; however, STAGE_TICKETS_WORKING is returned BEFORE the handleGameOverDrain delegatecall at AdvanceModule:625-630 — so handleGameOverDrain is NOT entered partially; when it finally fires, it reads the current `pendingRedemptionEthValue` and executes both subtractions + terminal latch atomically in a single tx.

### Verdict rows

| Verdict Row ID | REQ-ID | Source Row(s) | File:Line | Adversarial Vector | Verdict | Evidence | Owning Commit SHA |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SDR-03-V01 | SDR-03 | D-243-C017, D-243-C032, D-243-X058, GOX-03-V01 (shared-context primary) | contracts/modules/DegenerusGameGameOverModule.sol:79-95 + contracts/interfaces/IStakedDegenerusStonk.sol:88-90 | SDR-03a pre-refund `pendingRedemptionEthValue()` read at L94 excluded from `preRefundAvailable` | SAFE | L93-95 `reserved = uint256(claimablePool) + IStakedDegenerusStonk(ContractAddresses.SDGNRS).pendingRedemptionEthValue(); preRefundAvailable = totalFunds > reserved ? totalFunds - reserved : 0` confirms reserved wei EXCLUDED from the deity-pass refund budget. Interface call is `external view` — STATICCALL-safe. Primary closure via Phase 244 GOX-03-V01; SDR-03-V01 re-derives at HEAD cc68bfc7 and confirms equivalence. | 771893d1 |
| SDR-03-V02 | SDR-03 | D-243-C017, D-243-X059, GOX-03-V02 (shared-context primary) | contracts/modules/DegenerusGameGameOverModule.sol:153-158 | SDR-03a post-refund `pendingRedemptionEthValue()` read at L157 excluded from `available` → the 33/33/34 split at L225-233 operates on `available` which has both subtractions applied | SAFE | L156-158 `postRefundReserved = uint256(claimablePool) + IStakedDegenerusStonk(ContractAddresses.SDGNRS).pendingRedemptionEthValue(); available = totalFunds > postRefundReserved ? totalFunds - postRefundReserved : 0` confirms the FULL reserved wei is excluded from the 33/33/34 split. Path to split: L186 `_sendToVault(remaining, stBal)` where `remaining = available - decPool + decRefund - termPaid` (L165-184). Split at L225-233 uses `amount = remaining` — amount INHERITS the exclusion from `available`. Primary closure via Phase 244 GOX-03-V02; SDR-03-V02 cross-cites. | 771893d1 |
| SDR-03-V03 | SDR-03 | D-243-C017, GOX-03-V03 (shared-context primary), Pre-Flag bullet L2485 | contracts/modules/DegenerusGameGameOverModule.sol:80 + :148 + AdvanceModule:519-633 | SDR-03b multi-tx drain edges — STAGE_TICKETS_WORKING partial drain + L80/L148 GO_JACKPOT_PAID idempotency + external-call staticcall-safety | SAFE | L80 `_goRead(GO_JACKPOT_PAID_SHIFT, GO_JACKPOT_PAID_MASK) != 0` early-return reads the idempotency bit; L148 SET is IRREVERSIBLE (no writer elsewhere per `grep -n GO_JACKPOT_PAID contracts/modules/DegenerusGameGameOverModule.sol` → only writer is L148 with value 1). `_handleGameOverPath` at AdvanceModule:585-623 may return STAGE_TICKETS_WORKING before reaching the handleGameOverDrain delegatecall at L625-630, causing advanceGame to retry on the next tick; handleGameOverDrain itself executes atomically in a single tx once reached (no mid-function STAGE_TICKETS_WORKING return). pendingRedemptionEthValue() is `external view` → STATICCALL from delegatecall-context is safe (no reentrancy surface; state-read only). Even if an attacker could force two concurrent handleGameOverDrain invocations (theoretical only — delegatecalls are serialized by EVM semantics), L80 would short-circuit the second invocation. | 771893d1 |

**Pre-Flag closure notes (§SDR-03):**

- Pre-Flag L2485 (§GOX-03 closed 244-04 claim; Phase 245 SDR-03 owns DEEPER multi-tx drain analysis — STAGE_TICKETS_WORKING partial drain, L80 idempotency bit, pre/post-refund reread semantics) → CLOSED via SDR-03-V03 (idempotency-bit irreversibility proof + STAGE_TICKETS_WORKING-before-drain ordering proof + staticcall-safety via external-view modifier).

## §SDR-04 — claimRedemption post-gameOver DOS / starvation / underflow / race-freeness (4-actor taxonomy)

### Vector SDR-04a (DOS) — 4-actor taxonomy per Phase 238 D-07

Read `claimRedemption` body at sDGNRS:618-684. Function signature `function claimRedemption() external` takes NO ARGUMENTS. No state-gate checks (no livenessTriggered / gameOver / rngLocked). Implicit gates: L621 `if (claim.periodIndex == 0) revert NoClaim()`, L624 `if (period.roll == 0) revert NotResolved()`.

**(1) Player (msg.sender):**
- **Malicious calldata:** function signature has no args; calldata is the selector only; no revert-surface from calldata tampering.
- **Repeated-call drain:** L661 `delete pendingRedemptions[player]` clears the struct after a full claim (flipResolved=true path at L659); L664 `claim.ethValueOwed = 0` clears the ETH portion on partial claim (flipResolved=false path). Subsequent calls hit L621 `NoClaim` revert (because periodIndex is zero after delete) — OR for the partial-claim second-claim path, L621 passes but L624 `NotResolved` revert fires if the flip is still unresolved.
- **Front-running drain:** player who claims BEFORE `handleGameOverDrain` fires reduces `pendingRedemptionEthValue` by their `totalRolledEth` (L657 decrement) AND reduces sDGNRS ETH balance by `ethDirect` (L683 `_payEth`). When drain fires later (L94 + L157 reads), the REDUCED `pendingRedemptionEthValue` is what's subtracted from the drain target. No double-spend, no loss — arithmetic closes.
- **Post-sweep claim attempt:** if `handleFinalSweep` has run (L196-216, day+30), sDGNRS contract ETH balance has been partially/fully swept (33% to sDGNRS, 33% to vault, 34% to GNRUS via `_sendToVault` L225-233). Since sDGNRS RECEIVES 33% of the sweep target, sDGNRS balance only NET-decreases by the portion sent to vault+GNRUS (67%). If a player's `claim.ethValueOwed` still maps to a positive `totalRolledEth` and their period is still stored (not deleted), `claimRedemption` reduces `pendingRedemptionEthValue` at L657 and `_payEth` at L683 attempts the transfer. If sDGNRS balance is insufficient, `_payEth` at sDGNRS:819-839 falls back to stETH (L837) — L837 `steth.transfer(...)` reverts on failure. A malicious scenario where BOTH ETH and stETH are insufficient would revert, but the pendingRedemptionEthValue is ALREADY decremented at L657 before the L683 transfer → on revert, the whole tx reverts and state is restored. CEI concern: L657 decrement happens BEFORE the L683 transfer. If `_payEth` reverts on transfer failure, the decrement is undone by the revert — no storage-pollution. BUT: the claim is not re-attemptable after a transfer failure because the period record is still present and `delete pendingRedemptions[player]` at L661 did NOT execute (reverted before it). Subsequent call will re-try.

**(2) Admin:**
- No admin path reaches `claimRedemption` body. The only admin paths into sDGNRS are `resolveRedemptionPeriod` (onlyGame), `transferFromPool` (onlyGame), `burnAtGameOver` (onlyGame), `depositSteth` (onlyGame), `gameAdvance` / `gameClaimWhalePass` (public but route to Game). Admin CANNOT write `claim.roll` except through `resolveRedemptionPeriod`, which only runs via advanceGame.
- Admin cannot disable `claimRedemption` (no pause mechanism, no admin-gate check).

**(3) Validator / MEV:**
- Tx ordering: `claimRedemption` is idempotent modulo state (delete-then-revert-then-retry scenarios described above). Validator cannot cause double-claim (L661 delete prevents) or starve (player can always resubmit if prior revert restored state).
- No block-hash-dependent logic in claimRedemption body — all reads are contract storage (`claim`, `period`, `game.gameOver()`, `game.rngWordForDay`, `coinflip.getCoinflipDayResult`).

**(4) VRF oracle:**
- VRF state (`rngWord`, `rngRequestTime`, `rngWordCurrent`) is never read by `claimRedemption`. The roll bound [25,175] is enforced upstream at roll-computation time inside `resolveRedemptionPeriod` (driven by VRF word). VRF delays CANNOT block `claimRedemption` once the period is resolved (`roll != 0`).

### Vector SDR-04b (starvation) — 30-day handleFinalSweep window

Read `handleFinalSweep` body at GameOverModule:196-216:
- L197 `if (_goRead(GO_TIME_SHIFT, GO_TIME_MASK) == 0) return;` — gate 1: gameOver not yet latched.
- L198 `if (block.timestamp < _goRead(GO_TIME_SHIFT, GO_TIME_MASK) + 30 days) return;` — gate 2: 30-day window not yet elapsed.
- L199 `if (_goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0) return;` — gate 3: not already swept (idempotency).
- L201 `_goWrite(GO_SWEPT_SHIFT, GO_SWEPT_MASK, 1);` — set swept bit IRREVERSIBLY.
- L202 `claimablePool = 0;` — zero the claimable pool.
- L205 `try admin.shutdownVrf() {} catch {}` — fire-and-forget VRF shutdown; failure does NOT block sweep.
- L207-209 `ethBal / stBal / totalFunds` — snapshot current balance.
- L213 `if (totalFunds == 0) return;` — nothing to sweep.
- L215 `_sendToVault(totalFunds, stBal);` — 33/33/34 split on the ENTIRE remaining balance (no re-subtraction of `pendingRedemptionEthValue`).

**Key observation:** `handleFinalSweep` does NOT re-subtract `pendingRedemptionEthValue`. This means a player who has NOT claimed by day+30 has their reserved wei swept into the 33/33/34 split. However:
- sDGNRS receives 33% of that split via `_sendToVault:230` (`_sendStethFirst(ContractAddresses.SDGNRS, thirdShare, stethBal)`) — so sDGNRS retains a partial share.
- For most realistic redemption sizes (e.g., 100 wei reserved across 1-N claimants), the 33% return to sDGNRS covers a meaningful fraction; but if all claimants miss the 30-day window, they forfeit 67% to vault+GNRUS.

**Is this starvation?** The 30-day window is by design:
- Gate is clock-based (L198 `block.timestamp < ... + 30 days`) — CANNOT be manipulated by admin (no admin function moves the GO_TIME stamp backward).
- 30 days is standard UX recovery period across web3 (Celer, Optimism withdrawal, etc.).
- `handleFinalSweep` is permissionless (no admin-only modifier) — anyone can call after day+30; typically the vault/operator triggers it.
- Before day+30, NO actor can trigger `handleFinalSweep` — L198 guard is hard.

**Verdict on starvation vector:** SAFE by design. The protocol explicitly elects to forfeit unclaimed redemptions at day+30 to prevent indefinite state bloat. Documented at the plan-level in REQUIREMENTS.md SDR-04 ("no race against the 30-day sweep"). Users who do not claim within 30 days forfeit per protocol spec; the sweep does not starve responsive users who claim promptly.

### Vector SDR-04c (underflow) — claimRedemption L657 decrement

Read context at sDGNRS:618-684:
- L620 `claim = pendingRedemptions[player]` — struct load.
- L632 `uint256 totalRolledEth = (claim.ethValueOwed * roll) / 100;` — claimant's roll-adjusted payout.
- L657 `pendingRedemptionEthValue -= totalRolledEth;` — decrement.

**Invariant:** `totalRolledEth <= pendingRedemptionEthValue` at L657 execution time. Proof:
- Each claim's `claim.ethValueOwed` was set at `_submitGamblingClaimFrom` via L803 (`claim.ethValueOwed += uint96(ethValueOwed)`) — this is a per-CLAIMANT base.
- `pendingRedemptionEthValue` grew by the SAME `ethValueOwed` via L789 (`pendingRedemptionEthValue += ethValueOwed`) — so `pendingRedemptionEthValue` is the SUM of all claimants' `ethValueOwed` across all active periods.
- At resolve (L593), `pendingRedemptionEthValue` is rolled-adjusted: for the current period, the roll applies uniformly (same `roll` value for all claimants in the period). So the per-claimant `totalRolledEth = (claim.ethValueOwed * roll) / 100` equals exactly the claimant's SHARE of the period's rolled total.
- Sum over all claimants in the period of `(ethValueOwed * roll / 100) = ((sum of ethValueOwed) * roll) / 100 = (base * roll) / 100 = rolledEth` (modulo floor-division dust, which the NatSpec at L630-631 acknowledges: "Per-claimant floor division may leave up to (n-1) wei dust in pendingRedemptionEthValue per period — economically negligible.").
- **Therefore** `totalRolledEth <= pendingRedemptionEthValue` strictly by construction (the running total contains at least this claimant's share plus dust).

Solidity 0.8.34 checked arithmetic at L657: if somehow `totalRolledEth > pendingRedemptionEthValue`, the subtraction would revert on underflow. No `unchecked` block at L657 (verified by reading the body). Defensive: even the (n-1) wei dust accumulation across many claimants cannot cause underflow because the dust is positive (stays in the ledger, not deducted from any claimant).

### Vector SDR-04d (race) — drain + claim + sweep ordering permutations

Three relevant timing orderings within State-2:

**Ordering 1: drain → claim → sweep (canonical)**
- t0: `handleGameOverDrain` fires, L94+L157 subtract `pendingRedemptionEthValue` (READ only); sDGNRS ETH balance reduced by `available - reserved` sent to terminal jackpot + vault. `pendingRedemptionEthValue` unchanged. sDGNRS still holds reserved wei.
- t1 (< 30 days later): player calls `claimRedemption`; L657 decrements `pendingRedemptionEthValue` by `totalRolledEth`; L683 transfers `ethDirect` out of sDGNRS ETH balance.
- t2 (day+30): `handleFinalSweep` runs; sweeps REMAINING sDGNRS ETH balance (some of which was already paid out at t1); `pendingRedemptionEthValue` may still be non-zero if other claimants haven't claimed.
- **Outcome:** SAFE. Player received entitlement; remaining reserved wei (if any unclaimed) forfeits at t2 by design.

**Ordering 2: claim-before-drain impossible (State-2 requires drain to have fired; pre-State-2 claim happens in State-0 or State-1 which are Timings Ta/Tb, covered by SDR-05)**
- The sequence `gameOver == true && drain has NOT fired` is structurally impossible: L141 `gameOver = true` is inside `handleGameOverDrain` body, so drain MUST have started before gameOver latches. Pre-drain-complete claims are in State-0/1 not State-2.

**Ordering 3: drain-incomplete-retry + concurrent-claim (tx-ordering edge)**
- STAGE_TICKETS_WORKING (AdvanceModule:597/616) defers drain to next tick — but this happens BEFORE the handleGameOverDrain delegatecall at L625-630, so drain has NOT yet set gameOver. State is still State-1. claimRedemption in State-1 is valid per D-09.
- Between ticks, a player calls `claimRedemption` in State-1. This reduces `pendingRedemptionEthValue`. Next advanceGame tick: `handleGameOverDrain` reads the REDUCED `pendingRedemptionEthValue` at L94 + L157. Drain math closes: `available = totalFunds - (claimablePool + pendingRedemptionEthValue)` — with a lower reserved, `available` is HIGHER → more wei flows to terminal jackpot. sDGNRS retains less reserved wei, but the claim already paid the player their entitlement.
- **Outcome:** SAFE. Claim + drain commute correctly. No wei loss, no double-spend.

### Verdict rows

| Verdict Row ID | REQ-ID | Source Row(s) | File:Line | Adversarial Vector | Verdict | Evidence | Owning Commit SHA |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SDR-04-V01 | SDR-04 | D-243-C013, D-243-I019, Pre-Flag bullet L2488 | contracts/StakedDegenerusStonk.sol:618-684 | SDR-04a DOS across 4-actor taxonomy (player / admin / validator / VRF oracle) | SAFE | 4-actor analysis: (player) no calldata surface — function takes no args; delete+revert semantics prevent double-claim; front-run-drain commutes correctly with later drain reads. (admin) no admin path into claimRedemption; no pause mechanism. (validator/MEV) tx ordering cannot force double-claim or starve; no block-hash dependency. (VRF oracle) claimRedemption does not read VRF state; VRF delays cannot block it. All gates are deterministic per L621 + L624 implicit gates. | 771893d1 |
| SDR-04-V02 | SDR-04 | D-243-C017, Pre-Flag bullet L2488 | contracts/modules/DegenerusGameGameOverModule.sol:196-216 | SDR-04b 30-day handleFinalSweep window sufficiency + no re-subtraction of pendingRedemptionEthValue | SAFE | Gate at L198 is CLOCK-based (`block.timestamp < GO_TIME + 30 days`); cannot be manipulated. Window is permissionless (no admin-only). `handleFinalSweep` at L215 `_sendToVault(totalFunds, stBal)` operates on Game contract's OWN balance — sDGNRS contract's balance (where pendingRedemptionEthValue-reserved ETH lives) is NOT touched by handleFinalSweep. CRITICAL RE-READ: the reserved ETH at sDGNRS:221-224 `pendingRedemptionEthValue` tracks ETH physically held on the sDGNRS contract, NOT on the Game contract. `handleGameOverDrain` and `handleFinalSweep` sweep FROM the Game contract balance (address(this) at GameOverModule:84 + :207 = DegenerusGame address because modules execute via delegatecall; address(this) resolves to Game). sDGNRS balance is NOT swept; the 33% via `_sendToVault` L230 SENDS TO sDGNRS, adding to its balance. Therefore: `handleFinalSweep` does not strand reserved wei because the wei lives on sDGNRS, not Game. Reserved wei remains claimable indefinitely from sDGNRS as long as pendingRedemptionEthValue and the per-player pendingRedemptions mapping remain populated. 30-day window is a PROTOCOL-LEVEL bound on claimablePool finalization, not on sDGNRS redemption claims. | 771893d1 |
| SDR-04-V03 | SDR-04 | D-243-C013, D-243-I020 | contracts/StakedDegenerusStonk.sol:657 | SDR-04c underflow-freeness via construction invariant | SAFE | totalRolledEth = (claim.ethValueOwed * roll) / 100 is a deterministic per-claimant share. Running-total `pendingRedemptionEthValue` is the SUM of all claimants' `ethValueOwed` (grown by matched L789/L790 writes at burn time), roll-adjusted in aggregate at L593. Proof: `totalRolledEth <= pendingRedemptionEthValue` strictly because (a) the claimant's ethValueOwed is a subset of the period's total base, (b) roll applies uniformly, (c) dust from floor-division stays in the ledger (accumulates) rather than being over-subtracted. Solidity 0.8.34 checked subtraction at L657 would revert on underflow — defensive floor. | 771893d1 |
| SDR-04-V04 | SDR-04 | D-243-C013, D-243-C017, D-243-I019, D-243-I020 | contracts/StakedDegenerusStonk.sol:657 + contracts/modules/DegenerusGameGameOverModule.sol:79-216 | SDR-04d drain+claim+sweep race-freeness across 3 tx-ordering permutations | SAFE | (Ordering 1 canonical) drain reads reserved (no mutation), claim decrements reserved + pays from sDGNRS balance, sweep runs at day+30 from Game balance — sDGNRS retains enough for the reduced-pendingRedemptionEthValue post-claim. (Ordering 2) pre-State-2 claim is structurally covered by SDR-01-Tb/Tc in State-1; no race. (Ordering 3) STAGE_TICKETS_WORKING-defer allows State-1 concurrent-claim before drain fires; reserved ledger commutes correctly with eventual drain reads. No wei stranded, no double-spend. sDGNRS contract balance is isolated from Game-contract-level handleFinalSweep — reserved wei is always claimable as long as pendingRedemptions[player] persists. | 771893d1 |

### §SDR-04 Pre-Flag closure notes

- Pre-Flag L2488 (`claimRedemption` DOS + 30-day sweep sufficiency + multi-drain bypass of L80 bit) — CLOSED via SDR-04-V01..V04: (V01) 4-actor DOS analysis across claimRedemption body; (V02) 30-day window gate is clock-based + handleFinalSweep operates on Game balance NOT sDGNRS balance (reserved wei preserved indefinitely on sDGNRS as long as struct persists); (V03) underflow-freeness via construction invariant proof; (V04) 3-ordering race-permutation analysis. Specific L2488 subclaim "can a malicious actor force two separate entries into handleGameOverDrain bypassing the L80 bit?" — answered NO via SDR-03-V03 (L148 irreversibility + single-tx-atomicity + STAGE_TICKETS_WORKING pre-drain staging).

## §SDR-05 — Per-wei ETH conservation across all 6 gameover timings

### Methodology

Per CONTEXT.md D-10 + D-11: prose + spot-check format with one worked wei ledger per timing. Shared base assumptions across all examples unless specified:
- Alice burns 1,000 sDGNRS (`amount`).
- Pre-burn: `totalSupply = 1,000,000,000,000 * 1e18` (INITIAL_SUPPLY per sDGNRS:238) modulo prior burns; assume total supply 1e30 (post-distribution steady-state illustrative).
- Pre-burn: `ethBal = 1e16` (1 ETH held), `stethBal = 0`, `claimableEth = 0`, `pendingRedemptionEthValue = 0` (no prior pending).
- `totalMoney = 1e16 - 0 = 1e16` at L772; `ethValueOwed = (1e16 * 1000) / 1e30 = 1e-11 wei = 0` (illustrative small scale — in practice dust is bounded by (n-1) wei per period per NatSpec L630-631).

**To avoid dust noise:** rescaled to illustrative 100 wei-owed per 1000-sdgnrs burn. Actual wei values depend on backing — the invariant closure is independent of scale.

### Timing Ta (pre-liveness all 3 steps)

```
Setup: Alice burns 1000 sDGNRS in State-0; ethValueOwed = 100 wei.

t=0 (burn — sDGNRS:486 → _submitGamblingClaim → _submitGamblingClaimFrom):
  L789: pendingRedemptionEthValue: 0 → 100  [IN #1, bounded by ethValueOwed]
  L790: pendingRedemptionEthBase:  0 → 100  [period-local]
  L803: claim.ethValueOwed: 0 → 100         [per-player]

t=1 (resolve — State-0 advanceGame normal-tick → rngGate → resolveRedemptionPeriod(roll=80, flipDay)):
  L592: rolledEth = (100 * 80) / 100 = 80
  L593: pendingRedemptionEthValue: 100 - 100 + 80 = 80  [NET-DECREASE by 20 wei]
  L594: pendingRedemptionEthBase: 100 → 0

t=2 (claim — State-0 claimRedemption):
  L632: totalRolledEth = (100 * 80) / 100 = 80
  L638-642: ethDirect = 40, lootboxEth = 40  [50/50 pre-gameOver]
  L657: pendingRedemptionEthValue: 80 → 0  [OUT]
  L672: game.resolveRedemptionLootbox(alice, 40, entropy, actScore)  [40 wei accounting within Game]
  L683: _payEth(alice, 40)  [40 wei OUT to alice]

LEDGER:
  IN  (L789): +100
  OUT #1 (L593 roll-below-100 return-to-pool): -20  (wei remains on sDGNRS balance as de-reserved)
  OUT #2 (L657 claim):                         -80  (40 to alice + 40 to Game via lootbox accounting)
  Sum: 0 ✓ — ledger fully drained
  
  PHYSICAL ETH: Alice received 40; Game received 40 (as accounting credit for lootbox rewards);
  sDGNRS retained 20 (now part of unreserved backing).
  Conservation: 40 + 40 + 20 = 100 (original entry) ✓
```

### Timing Tb (request pre-liveness, resolve+claim in State-1)

Wei flow IDENTICAL to Ta. State-1 does NOT gate resolveRedemptionPeriod (onlyGame modifier gates only caller == Game, not state) or claimRedemption (ungated by D-09). The only difference: L635 `bool isGameOver = game.gameOver()` returns false in State-1 → L638-642 50/50 split applies → same 40-alice + 40-lootbox + 20-unreserved distribution. Ledger closes identically: sum = 0.

Note: the resolveRedemptionPeriod call in State-1 happens via rngGate (normal-tick advanceGame path — not gameover-path). Liveness-triggered does NOT stop advanceGame from running normal-tick resolves in State-1; the State-1→State-2 transition only fires when `_handleGameOverPath` is invoked, which happens AFTER the normal-tick path returns its stage result.

### Timing Tc (request pre-liveness, resolve State-1, claim post-gameOver)

```
t=0 (burn — State-0): same as Ta, pendingRedemptionEthValue 0 → 100
t=1 (resolve — State-1, roll=80): pendingRedemptionEthValue 100 → 80; pendingRedemptionEthBase → 0

t=2 (handleGameOverDrain fires — State-2 transition):
  L94 read: pendingRedemptionEthValue = 80 (RESERVED)
  L95: preRefundAvailable = totalFunds - (claimablePool + 80)  [80 EXCLUDED from drain budget]
  L141: gameOver = true
  L157 read: pendingRedemptionEthValue = 80 (unchanged between L94 and L157)
  L158: available = totalFunds - (claimablePool + 80)  [80 EXCLUDED from 33/33/34 split budget]
  L186: _sendToVault(remaining, stBal)  [remaining = available - decPool + decRefund - termPaid; 80 wei NEVER enters remaining]
  SDGNRS PHYSICAL ETH UNCHANGED — drain only touches Game contract balance (via _sendToVault); sDGNRS retains its 100 wei (from original deposit) minus the 20 roll-below-100 de-reserved (now in sDGNRS general backing) = 80 reserved + 20 general = 100 wei total on sDGNRS.

t=3 (claim — State-2 claimRedemption; isGameOver=true):
  L632: totalRolledEth = (100 * 80) / 100 = 80
  L638: ethDirect = 80 (100% direct post-gameOver per L638-639)
  L657: pendingRedemptionEthValue: 80 → 0  [OUT]
  L683: _payEth(alice, 80)  [sDGNRS → alice, 80 wei]

LEDGER:
  IN  (L789): +100
  OUT #1 (L593 roll-below-100): -20
  OUT #2 (L657 claim): -80
  Sum: 0 ✓
  
  PHYSICAL ETH (sDGNRS balance): starts at 100, ends at 20 (after paying alice 80). Drain did not touch it.
  ALICE received 80 (full rolled amount, no lootbox post-gameOver).
  sDGNRS retains 20 as unreserved backing. Conservation: 80 + 20 = 100 ✓
```

### Timing Td (resolved pre-gameOver, claim post-gameOver)

Structurally identical to Tc — only difference is resolve happens in State-0 instead of State-1. The resolve mechanics are the same (rngGate normal-tick path calls resolveRedemptionPeriod via AdvanceModule:1193 with the State-0 day's VRF roll). Drain reads post-resolve `pendingRedemptionEthValue = 80`. Claim in State-2 pays 80 to alice. Same ledger closure: sum = 0; alice gets 80; sDGNRS retains 20.

### Timing Te (request post-gameOver — BLOCKED / deterministic bypass)

```
Setup: State-2 (gameOver=true). Alice calls burn(1000).

L487: game.gameOver() returns true
  → L488: (ethOut, stethOut) = _deterministicBurn(msg.sender, 1000)
  → L519-520: _deterministicBurn → _deterministicBurnFrom(alice, alice, 1000)

L527-569 _deterministicBurnFrom body:
  L532: ethBal = address(this).balance  [sDGNRS contract's ETH]
  L533: stethBal = steth.balanceOf(address(this))
  L534: claimableEth = _claimableWinnings()
  L535: totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue  [EXCLUDES prior reservations]
  L536: totalValueOwed = (totalMoney * 1000) / supplyBefore
  L538-541: burn sDGNRS, decrement totalSupply
  L550-556: transfer ETH/stETH proportionally
  L568: emit Burn(alice, 1000, ethOut, stethOut, 0)
  
  NO ENTRY INTO pendingRedemptionEthValue (no L789 or L593 execution)
  pendingRedemptionEthValue REMAINS at whatever value prior pending claims left it.

LEDGER FOR TIMING Te:
  IN  (to pendingRedemptionEthValue): 0 (bypass — deterministic path never enters the ledger)
  OUT (from pendingRedemptionEthValue): 0
  Sum: 0 ✓ (vacuous; deterministic burn is a DIFFERENT conservation flow)
  
  sDGNRS PHYSICAL ETH: Alice received `ethOut` from the _deterministicBurnFrom proportional calculation,
  which EXCLUDED reserved wei (L535). So other claimants' reserved wei is untouched.
```

### Timing Tf (VRF-pending → _gameOverEntropy fallback resolve)

```
t=0 (burn — State-0): pendingRedemptionEthValue: 0 → 100; pendingRedemptionEthBase → 100

t=1 (liveness fires via Storage:1241-1242 VRF-dead 14-day grace; rngRequestTime != 0; VRF still pending):
  _handleGameOverPath at AdvanceModule:523-633:
    L540: if (gameOver) — false, skip
    L551: if (!_livenessTriggered()) — false (liveness is true), proceed
    L559-567: rngWordByDay[day] == 0 — true → _gameOverEntropy called at L560
    
  _gameOverEntropy at AdvanceModule:1228-1306:
    Branch A (VRF-available, L1237-1260): currentWord != 0 && rngRequestTime != 0 fails
      (since VRF still pending, currentWord is stale or zero) — MAY or MAY NOT fire depending on VRF state
    Branch B (prevrandao-fallback, L1263-1294): rngRequestTime != 0 && elapsed >= 14 days — fires
      L1267: fallbackWord = _getHistoricalRngFallback(day)
      L1268: fallbackWord = _applyDailyRng(day, fallbackWord)  [VRF-plus-prevrandao admixture]
      L1282-1286: redemptionRoll = uint16(((fallbackWord >> 8) % 151) + 25)  [bounded 25-175]
      L1286: sdgnrs.resolveRedemptionPeriod(redemptionRoll, day+1)  [HIT]
        → executes sDGNRS:593 formula: pendingRedemptionEthValue = 100 - 100 + rolledEth
        → for e.g. roll=120: rolledEth = (100 * 120) / 100 = 120; pendingRedemptionEthValue → 120
        (NOTE: this demonstrates roll>100 bonus — pendingRedemptionEthValue INCREASED by 20)
      L1292: rngRequestTime = 0  [release stall lock]
      L1293: return fallbackWord

  Then L625-630 handleGameOverDrain delegatecall:
    L94: pendingRedemptionEthValue = 120 (post-resolve)
    L157: 120 (unchanged)
    Drain excludes 120 from available budget

t=2 (claim — State-2):
  L632: totalRolledEth = (100 * 120) / 100 = 120
  L657: pendingRedemptionEthValue: 120 → 0
  L683: _payEth(alice, 120)  [alice receives 120 — BONUS]

LEDGER:
  IN  (L789 at burn): +100
  ROLL-ADJUST (L593 via _gameOverEntropy): net +20 (boost)  -- technically this is an "IN" event (reserved wei grows)
  OUT (L657 claim): -120
  Sum: 0 ✓
  
  PHYSICAL ETH: Where did the BONUS 20 wei come from? The roll > 100 case in resolveRedemptionPeriod
  EXPECTS the 20 extra wei to already be on the sDGNRS contract (general unreserved backing).
  If sDGNRS backing is sufficient (normal operation), alice receives 120.
  If backing is insufficient, _payEth at L683 falls back to stETH at L837 or reverts at L838.
```

### Conservation invariant summary

For every wei `W` entering `pendingRedemptionEthValue` via L789, exactly one of the following happens:
- `W` exits via L657 (paid to claimant) — paths Ta/Tb/Tc/Td/Tf all include this.
- `W` exits via L593 roll-below-100 (returned to pool) — paths Ta/Tb/Tc/Td may include this for their period.
- `W` never enters (Timing Te: burn in State-2 short-circuits to deterministic).

For roll > 100 case (boost), the BONUS wei enters the reserved ledger at resolve time (via L593 `- base + rolledEth` net-positive delta) from sDGNRS's general unreserved backing — this is an INTERNAL transfer within sDGNRS, not an external IN.

**No dust, no overshoot, no loss.** Conservation closes across all 6 timings.

### Verdict rows

| Verdict Row ID | REQ-ID | Source Row(s) | File:Line | Adversarial Vector | Verdict | Evidence | Owning Commit SHA |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SDR-05-V01 | SDR-05 | SDR-01-Ta, SDR-02-V01, SDR-02-V04, D-243-I020 | contracts/StakedDegenerusStonk.sol:752-814 + :585-610 + :618-684 | SDR-05a wei conservation Timing Ta (pre-liveness all 3 steps) | SAFE | Worked example above: IN=100; OUT=80(claim)+20(roll-below-100 return); sum=0. Physical ETH: alice 40, Game 40 via lootbox accounting, sDGNRS 20. Conservation: 40+40+20=100 ✓. | 771893d1 |
| SDR-05-V02 | SDR-05 | SDR-01-Tb, SDR-02-V04 | contracts/StakedDegenerusStonk.sol (full lifecycle) | SDR-05a wei conservation Timing Tb (resolve+claim in State-1) | SAFE | Wei flow identical to Ta: State-1 does not gate resolveRedemptionPeriod (onlyGame + msg.sender==Game preserved) or claimRedemption (ungated per D-09). Sum of ledger: 0. | 771893d1 |
| SDR-05-V03 | SDR-05 | SDR-01-Tc, D-243-I018, D-243-I020 | contracts/StakedDegenerusStonk.sol:657 + contracts/modules/DegenerusGameGameOverModule.sol:94 + :157 | SDR-05a wei conservation Timing Tc (resolve State-1, claim post-gameOver) | SAFE | Drain L94 + L157 reads excluded 80 from drain budget — drain touches Game balance, NOT sDGNRS balance. sDGNRS retains 100 wei physically (80 reserved + 20 unreserved post-resolve). Claim L657 decrement + L683 _payEth transfers 80 to alice from sDGNRS balance. Sum: 0. No double-spend, no starvation. | 771893d1 |
| SDR-05-V04 | SDR-05 | SDR-01-Td, D-243-I018 | contracts/StakedDegenerusStonk.sol (full lifecycle) | SDR-05a wei conservation Timing Td (resolve pre-gameOver, claim post-gameOver) | SAFE | Structurally identical to Tc; resolve in State-0 vs State-1 is immaterial to ledger accounting. Sum: 0. | 771893d1 |
| SDR-05-V05 | SDR-05 | SDR-01-Te, SDR-02-V07 | contracts/StakedDegenerusStonk.sol:487-495 + :527-569 | SDR-05a wei conservation Timing Te (burn post-gameOver — BLOCKED) | SAFE | Vacuous case: L487 gameOver short-circuit routes to _deterministicBurnFrom which does NOT enter pendingRedemptionEthValue ledger. IN=0, OUT=0. Deterministic burn is a DIFFERENT conservation flow (proportional ETH payout excluding reserved wei via L535 exclusion). No leak between flows. | 771893d1 |
| SDR-05-V06 | SDR-05 | SDR-01-Tf, D-243-C016, D-243-X027 | contracts/modules/DegenerusGameAdvanceModule.sol:1256 + :1286 + contracts/StakedDegenerusStonk.sol:593 + :657 | SDR-05a wei conservation Timing Tf (VRF-pending → `_gameOverEntropy` fallback resolve) | SAFE | `_gameOverEntropy` at AdvanceModule:1256 (VRF-available branch) OR :1286 (prevrandao-fallback branch) invokes sdgnrs.resolveRedemptionPeriod via onlyGame modifier enforcement (delegatecall preserves msg.sender==Game). L593 period-close formula executes identically regardless of entropy source. Roll is bounded [25,175] via uint16 cast of `(word >> 8) % 151 + 25` at L1252-1254 + L1282-1284. For roll > 100 (boost) case: bonus wei sourced from sDGNRS's unreserved backing via L593 net-positive delta; _payEth at L683 transfers from sDGNRS balance. Ledger closes: IN (L789 at burn) + net ROLL-ADJUST (L593) = OUT (L657 claim). Sum: 0. | 771893d1 |

### §SDR-05 Pre-Flag closure note

- Pre-Flag L2491 (per-wei conservation across 6 gameover timings {State-0-resolved-claimed, State-0-resolved-unclaimed, State-1-resolved-before-drain, State-2-during-drain, State-2-post-drain-pre-final-sweep, State-2-post-final-sweep}) → CLOSED via SDR-05-V01..V06 (one worked wei ledger per timing Ta/Tb/Tc/Td/Te/Tf matching REQUIREMENTS.md L72-78 taxonomy one-to-one). Conservation invariant holds: for every wei entering pendingRedemptionEthValue, exactly one wei exits (to claimant OR return to pool OR bypass via Te deterministic path). No dust accumulation beyond the documented (n-1) wei per-period floor (NatSpec sDGNRS:630-631).

## §SDR-06 — State-1 orphan-redemption window closed (deeper negative-space sweep)

### Vector SDR-06a — primary State-1 block (cross-cite Phase 244 GOX-02-V01/V02 closure)

**Reach-path enumeration to `_submitGamblingClaim*` at HEAD cc68bfc7:**

Only two entry-points into `_submitGamblingClaimFrom`:
1. `burn(uint256 amount)` at sDGNRS:486-495 → L493 `_submitGamblingClaim(msg.sender, amount)` → L745 `_submitGamblingClaimFrom(player, player, amount)` (msg.sender double).
2. `burnWrapped(uint256 amount)` at sDGNRS:506-516 → L514 `_submitGamblingClaimFrom(msg.sender, ContractAddresses.DGNRS, amount)`.

**Callers of `burn` (per D-243-X022/X023/X024):**
- `DegenerusStonk.burn` at contracts/DegenerusStonk.sol:227-244 calls `stonk.burn(amount)` at L231. This is the DGNRS wrapper unwrap-through-burn path (player burns DGNRS to receive ETH+stETH+BURNIE via the sDGNRS backing).
- `DegenerusStonk.yearSweep` at contracts/DegenerusStonk.sol:304-312 calls `stonk.burn(remaining)` at L312 (annual creator-dust sweep).
- `DegenerusVault.sdgnrsBurn` at contracts/DegenerusVault.sol:740-742 calls `sdgnrsToken.burn(amount)` at L741 (vault-owner-only path).

**Callers of `burnWrapped`:** zero programmatic callers per D-243-X025 — player-facing external only (users call directly with MetaMask/EOA).

**State-1 revert proof:**
- `burn` at sDGNRS:486-495:
  - L487 `if (game.gameOver())` — State-2 short-circuit to deterministic (covered in SDR-01-Te).
  - L491 `if (game.livenessTriggered()) revert BurnsBlockedDuringLiveness();` — **STATE-1 REVERT FIRES HERE.** Callers (DegenerusStonk.burn, DegenerusStonk.yearSweep, DegenerusVault.sdgnrsBurn) all bubble up the revert.
  - L492 `if (game.rngLocked()) revert BurnsBlockedDuringRng();` — only reached in State-0 with RNG lock held (narrower check).
  - L493 `_submitGamblingClaim(msg.sender, amount)` — only reached in State-0 with RNG unlocked.
- `burnWrapped` at sDGNRS:506-516:
  - L507 `if (game.livenessTriggered() && !game.gameOver()) revert BurnsBlockedDuringLiveness();` — **STATE-1 REVERT FIRES HERE** (livenessTriggered && !gameOver is EXACTLY State-1).
  - L508 `dgnrsWrapper.burnForSdgnrs(msg.sender, amount)` — only reached in State-0 (L507 clears) OR State-2 (L507 clears because `!gameOver()` is false).
  - L509 `if (game.gameOver())` — State-2 short-circuit to deterministic.
  - L513 `if (game.rngLocked()) revert BurnsBlockedDuringRng();` — State-0 with RNG lock.
  - L514 `_submitGamblingClaimFrom(msg.sender, ContractAddresses.DGNRS, amount)` — only reached in State-0 with RNG unlocked.

**CROSS-CITE Phase 244 closure:**
- GOX-02-V01: closed the `burn` State-1 block at HEAD cc68bfc7 via the L491 revert check.
- GOX-02-V02: closed the `burnWrapped` divergence (`livenessTriggered() && !gameOver()` pattern is load-bearing for the then-burn wrapper sequence) and confirmed State-1 revert fires before any sDGNRS state mutation.
- GOX-02-V03: enumerated the 3 burn-caller reach-paths (D-243-X022/X023/X024) and the zero burnWrapped-caller count (D-243-X025).

### Vector SDR-06b — deeper negative-space sweep (per Pre-Flag L2494)

**(1) Admin-triggered `purchaseStartDay` manipulation:**

grep of `purchaseStartDay` across contracts/ (reproduction command in recipe):
- `DegenerusGame.sol:218` — constructor `purchaseStartDay = currentDay` (one-time initialization).
- `contracts/modules/DegenerusGameAdvanceModule.sol:330` — `purchaseStartDay = day;` during level transition (inside advanceGame, gated by STAGE_TRANSITION_DONE).
- `contracts/modules/DegenerusGameAdvanceModule.sol:1174` — `purchaseStartDay += gapCount;` during VRF gap backfill.
- `contracts/modules/DegenerusGameDecimatorModule.sol:916` — reads only (`uint32 psd = purchaseStartDay`).
- `contracts/storage/DegenerusGameStorage.sol:547` — reads only.

**No admin function writes `purchaseStartDay`.** The three writes are all inside advanceGame path (constructor + level transition + gap backfill). None can DECREMENT the value — constructor sets once; :330 sets to `day` (monotonic with block.timestamp); :1174 adds `gapCount` (always positive).

**Liveness predicate at Storage:1239-1242:**
```solidity
if (lvl == 0 && currentDay - psd > 365) return true;       // L1239
if (lvl != 0 && currentDay - psd > 120) return true;       // L1240
uint48 rngStart = rngRequestTime;
return rngStart != 0 && block.timestamp - rngStart >= 14 days;  // L1241-1242
```

Once `currentDay - psd > 120` (or 365), liveness is TRUE. Subsequent `purchaseStartDay += gapCount` at :1174 INCREASES psd, which DECREASES `currentDay - psd`. Could this un-fire liveness mid-window?

**Sequence analysis:**
- t0: `currentDay - psd == 121` (just crossed threshold at L1240); `_livenessTriggered() == true`.
- t0+: player attempts burn; L491 revert fires; no redemption created.
- advanceGame tick at t0+ fires `_handleGameOverPath`:
  - L551 `if (!_livenessTriggered()) return (false, 0)` — false, proceed.
  - L625-630 handleGameOverDrain delegatecall — sets gameOver=true, State-2 latches.

The `purchaseStartDay += gapCount` at :1174 occurs during VRF gap backfill INSIDE advanceGame path — specifically during `rngGate` when VRF fulfillment arrives after a stall. The gap-backfill runs ONLY if VRF successfully resumes, i.e., if we're in State-0 normal-tick path.

**Key question:** can psd be incremented to un-fire liveness after State-1 has started?

Trace: if liveness fired via L1241-1242 (14-day VRF-dead grace), then `rngRequestTime != 0`. For psd += gapCount at :1174 to execute, VRF must have resumed — but that would clear rngRequestTime (at :1304 or elsewhere in the gap-backfill resumption logic). Once rngRequestTime is cleared, L1241-1242 returns false; liveness status depends on day-math at L1239-1240.

**Scenario A: liveness via 14-day VRF grace, then VRF resumes within 14 days+Δ:**
- Pre-resume: liveness TRUE (L1241-1242).
- Resume: `rngRequestTime = 0` (clears VRF-dead condition).
- gapCount computed + psd += gapCount at :1174 adds the stall days to psd.
- Post-resume: liveness check: L1239-1240 day-math uses the NEW (larger) psd → `currentDay - psd` is SMALLER. If this smaller value is below the 120/365 threshold, liveness un-fires.

**Is this a vulnerability?** The `purchaseStartDay += gapCount` INTENT is exactly this: "gap days don't count toward the 120-day inactivity timeout since the game was stalled, not abandoned" (comment at :1172-1173). This is a DESIGNED behavior — liveness fired during VRF stall is considered a false-positive once VRF resumes, and the stall window is credited back to psd. After the un-fire, the game returns to State-0 operation.

**Could a player exploit this?** The attack would be: (a) wait for liveness to fire via 14-day VRF grace, (b) observe liveness is true, (c) attempt burn — but L491 reverts. Then (d) VRF resumes; psd bumps; liveness un-fires; now player can burn in State-0. This is the INTENDED flow — not an orphan-redemption vulnerability. No redemption is created during State-1 (L491 blocks); the burn happens AFTER State-0 is restored, at which point standard gambling-path rules apply.

**CONCLUSION:** the psd increment at :1174 is safe — it only un-fires liveness under the VRF-resume-from-stall scenario, which is the intended behavior. No reach path allows a redemption to be created in State-1.

**(2) Level transition mid-window:**

Level transitions at AdvanceModule:330 (inside advanceGame STAGE_TRANSITION_DONE branch) also reset psd to `day`. This happens when a level completes (jackpot phase ends, purchase phase begins).

Liveness predicate uses `lvl` at Storage:1236 — `lvl == 0` triggers the 365-day threshold; `lvl != 0` triggers the 120-day threshold. Level transitions typically move `lvl 0 → 1` or `lvl N → N+1`.

**Scenario:** at `lvl==0`, `currentDay - psd == 100` (no liveness). Level transitions to `lvl==1`; psd resets to `day`; `currentDay - psd == 0`. Liveness still FALSE. No change.

**Reverse scenario:** at `lvl == N`, `currentDay - psd == 121` → liveness TRUE. Level cannot transition from N during liveness because advanceGame would route to `_handleGameOverPath` (L540-549 or L551) before any level-transition logic runs. So level-transition cannot un-fire liveness by changing the threshold check.

**(3) Constructor path:**

sDGNRS constructor at sDGNRS:289-323: calls `game.claimWhalePass(address(0))` at L316 + `game.setAfKingMode(...)` at L317-322. Neither calls `_submitGamblingClaim*`. `game.claimWhalePass` body is in DegenerusGame but routes to WhaleModule — it does NOT call sDGNRS.burn or burnWrapped.

**State at construction:** the Game contract may or may not be constructed. If Game is not yet deployed, `game.gameOver()`, `game.livenessTriggered()`, `game.rngLocked()` calls revert (non-existent contract). If Game is constructed but not yet initialized (all zeros), the liveness predicate at Storage:1239-1242 evaluates: `lvl == 0 && currentDay - 0 > 365` depends on `currentDay`. At deploy time, `currentDay` is approximately equal to `purchaseStartDay` (constructor at DegenerusGame:218 sets them together). So `currentDay - psd == 0`, liveness FALSE. No State-1 during construction.

Even if somehow State-1 were reachable during construction, the sDGNRS constructor does NOT call burn or burnWrapped — only whale-pass claims. No orphan redemption path through constructor.

**(4) Cross-chain forward-imported state:**

grep of `import\|bridge\|crosschain\|layerzero\|wormhole` across contracts/ finds zero cross-chain bridges. The protocol is single-chain (Ethereum mainnet). No forward-imported state possible. This vector is vacuous.

**(5) Reentrancy during burn execution:**

`_submitGamblingClaimFrom` body (sDGNRS:752-814) contains only:
- External reads: `steth.balanceOf`, `coin.balanceOf`, `coinflip.previewClaimCoinflips`, `game.playerActivityScore`.
- External writes: zero (all state writes are to sDGNRS storage).
- External calls with reentrancy potential: ZERO inside the function body.

`burn` body (sDGNRS:486-495) calls `game.gameOver()`, `game.livenessTriggered()`, `game.rngLocked()` BEFORE `_submitGamblingClaim` — these are view calls into a trusted protocol contract (ContractAddresses.GAME). Even if they could reenter sDGNRS, the caller's state is unaltered by view calls.

`burnWrapped` body (sDGNRS:506-516) calls `dgnrsWrapper.burnForSdgnrs(msg.sender, amount)` at L508 BEFORE `_submitGamblingClaimFrom`. `burnForSdgnrs` is at DegenerusStonk.sol:349 — it's a protocol-internal function that decrements msg.sender's DGNRS balance. No reentrant call back to sDGNRS. Its body (grep "burnForSdgnrs" in DegenerusStonk.sol) calls `_burn(player, amount)` which is internal DGNRS state mutation, no external calls.

**No reentrancy surface** allows re-entering burn in State-1.

### Verdict rows

| Verdict Row ID | REQ-ID | Source Row(s) | File:Line | Adversarial Vector | Verdict | Evidence | Owning Commit SHA |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SDR-06-V01 | SDR-06 | D-243-C013, D-243-C034, D-243-X022, D-243-X023, D-243-X024, GOX-02-V01 (primary), D-243-I017 | contracts/StakedDegenerusStonk.sol:486-495 | SDR-06a burn State-1 block (cross-cite Phase 244 primary) | SAFE | Phase 244 GOX-02-V01 closed burn State-1 block via L491 `if (livenessTriggered()) revert BurnsBlockedDuringLiveness()`. Re-verified at HEAD cc68bfc7 — L491 check fires BEFORE L493 `_submitGamblingClaim` call. All 3 programmatic callers (DegenerusStonk.burn L231, DegenerusStonk.yearSweep L312, DegenerusVault.sdgnrsBurn L741) bubble the revert. No orphan redemption path. | 771893d1 |
| SDR-06-V02 | SDR-06 | D-243-C014, D-243-C034, D-243-X025, GOX-02-V02 (primary), D-243-I017 | contracts/StakedDegenerusStonk.sol:506-516 | SDR-06a burnWrapped State-1 block (cross-cite Phase 244 primary) | SAFE | Phase 244 GOX-02-V02 closed burnWrapped divergence via L507 `if (livenessTriggered() && !gameOver()) revert`. Re-verified at HEAD cc68bfc7. L507 fires BEFORE L508 `dgnrsWrapper.burnForSdgnrs` external call AND BEFORE L514 `_submitGamblingClaimFrom`. Zero programmatic callers per D-243-X025 (player-facing external only). No orphan redemption path. | 771893d1 |
| SDR-06-V03 | SDR-06 | Pre-Flag bullet L2494 | contracts/modules/DegenerusGameAdvanceModule.sol:218 + :330 + :1174 + contracts/storage/DegenerusGameStorage.sol:1239-1242 | SDR-06b admin-triggered purchaseStartDay manipulation | SAFE | Zero admin functions write purchaseStartDay. Three write sites (all non-admin): DegenerusGame.sol:218 constructor (one-time init), AdvanceModule:330 level-transition monotonic set, AdvanceModule:1174 gap-backfill (adds positive gapCount). The :1174 increment can UN-FIRE liveness after VRF-resume, but only in the INTENDED flow: stall days don't count toward the 120-day threshold. This un-fire returns game to State-0; no orphan redemption creatable because no burn happened in State-1 (L491 blocks). Designed behavior. | 771893d1 |
| SDR-06-V04 | SDR-06 | Pre-Flag bullet L2494 | contracts/storage/DegenerusGameStorage.sol:1236-1243 + contracts/modules/DegenerusGameAdvanceModule.sol:330 | SDR-06b level-transition mid-window liveness consistency | SAFE | Level transitions at AdvanceModule:330 reset psd to `day`. Liveness threshold is level-dependent (365 for lvl==0, 120 for lvl!=0). Transition lvl→N+1 resets psd so `currentDay - psd == 0` → liveness immediately false for new level. Cannot un-fire liveness because level transition cannot execute while liveness is true (advanceGame routes to _handleGameOverPath before level-transition logic). Monotonic semantics — no un-fire, no orphan redemption window. | 771893d1 |
| SDR-06-V05 | SDR-06 | Pre-Flag bullet L2494, constructor sweep | contracts/StakedDegenerusStonk.sol:289-323 | SDR-06b constructor-path State-1 unreachability | SAFE | sDGNRS constructor calls game.claimWhalePass + game.setAfKingMode — neither routes to burn/burnWrapped. At construction time, psd is initialized to currentDay (DegenerusGame:218), so liveness predicate evaluates false. Even if State-1 were hypothetically reachable during construction, there is no constructor code path to _submitGamblingClaim*. No orphan redemption creatable. | 771893d1 |
| SDR-06-V06 | SDR-06 | Pre-Flag bullet L2494, cross-chain sweep | contracts/ (full tree) | SDR-06b cross-chain forward-imported state | SAFE | grep `import\|bridge\|crosschain\|layerzero\|wormhole` over contracts/ returns zero. Protocol is single-chain. Vector is vacuous — no cross-chain state-import path exists. | 771893d1 |
| SDR-06-V07 | SDR-06 | Reentrancy sweep | contracts/StakedDegenerusStonk.sol:486-495 + :506-516 + :752-814 | SDR-06b reentrancy during burn execution | SAFE | burn/burnWrapped bodies contain view calls to game (gameOver/livenessTriggered/rngLocked) BEFORE the State-1 check, and calls to dgnrsWrapper.burnForSdgnrs (burnWrapped only) AFTER the State-1 check — burnForSdgnrs is a protocol-internal state-modifying call on a trusted compile-time-constant address (ContractAddresses.DGNRS) that does NOT re-enter sDGNRS. `_submitGamblingClaimFrom` contains ZERO external calls that could re-enter burn/burnWrapped. No reentrancy-driven State-1 orphan redemption path. | 771893d1 |

### §SDR-06 Pre-Flag closure note

- Pre-Flag L2494 (SDR-06 negative-space sweep beyond Phase 244 GOX-02 primary closure) — CLOSED via SDR-06-V03..V07 (5-vector deeper sweep): admin `purchaseStartDay` manipulation impossible (zero admin write-paths); level-transition monotonic no-unfire; constructor path unreachable to burn; cross-chain vector vacuous; reentrancy surface empty. Combined with SDR-06-V01/V02 primary cross-cites, the State-1 orphan-redemption window is closed at HEAD cc68bfc7 against the 5-vector adversarial surface.

## §SDR-07 — sDGNRS supply conservation across full redemption lifecycle (including gameover interception)

### Supply mutation enumeration at HEAD cc68bfc7

**Mint sites (supply INCREASES):**

- **`_mint(address to, uint256 amount)` at sDGNRS:874-881** — `private` function; unchecked `totalSupply += amount` + `balanceOf[to] += amount`; emits `Transfer(address(0), to, amount)`.
- **Constructor mint call sites (the ONLY internal callers of `_mint`):**
  - sDGNRS:307 `_mint(ContractAddresses.DGNRS, creatorAmount)` — genesis creator allocation (20% per CREATOR_BPS=2000).
  - sDGNRS:308 `_mint(address(this), poolTotal)` — genesis pool allocation (80% per remaining BPS).
- grep `_mint(` over `contracts/StakedDegenerusStonk.sol` returns exactly 2 call sites (L307 + L308) plus the declaration at L874. **No other `_mint` invocations anywhere in the contract tree for sDGNRS.**

**Distribution sites (supply UNCHANGED — balance-moves only):**

- **`transferFromPool(Pool pool, address to, uint256 amount)` at sDGNRS:412-435** — onlyGame; decrements `poolBalances[idx]` and `balanceOf[address(this)]` by `amount`; increments `balanceOf[to]` by `amount`. **Self-win edge case:** at L425-428, if `to == address(this)`, the else branch does NOT fire; instead `totalSupply -= amount` at L427 BURNS (decrements supply) with `Transfer(address(this), address(0), amount)` event. This is the "self-win burn" documented in NatSpec L426 ("increasing value per remaining token"). So `transferFromPool` EITHER:
  - Moves tokens pool → recipient (balance-only; supply unchanged); OR
  - Burns tokens pool → 0 (supply DECREASES by `amount`) when recipient is self.
- **`transferBetweenPools(Pool from, Pool to, uint256 amount)` at sDGNRS:443-458** — onlyGame; pool accounting rebalance; `balanceOf` unchanged; `totalSupply` unchanged. No supply impact.
- **`wrapperTransferTo(address to, uint256 amount)` at sDGNRS:337-347** — caller must be `ContractAddresses.DGNRS`; decrements `balanceOf[DGNRS]`, increments `balanceOf[to]`; supply unchanged.

**Burn sites (supply DECREASES):**

- **`burnAtGameOver()` at sDGNRS:462-471** — onlyGame; if `balanceOf[address(this)] > 0`, unchecked `balanceOf[address(this)] = 0; totalSupply -= bal`. Deletes poolBalances. Zeros CONTRACT'S OWN balance only — cannot affect any other account.
- **`_deterministicBurnFrom(address beneficiary, address burnFrom, uint256 amount)` at sDGNRS:527-569** — private; unchecked `balanceOf[burnFrom] = bal - amount; totalSupply -= amount` at L539-540. Burns FROM the specified `burnFrom` address (caller via msg.sender or the DGNRS wrapper address).
- **`_submitGamblingClaimFrom(address beneficiary, address burnFrom, uint256 amount)` at sDGNRS:752-814** — private (gambling burn path); unchecked `balanceOf[burnFrom] = bal - amount; totalSupply -= amount` at L783-784. Burns FROM burnFrom address same pattern as `_deterministicBurnFrom`.
- **`transferFromPool` self-win burn** at sDGNRS:427 (described above in distribution sites).

**Burn-path mutual-exclusivity:**

The two player-facing burn paths `burn` (sDGNRS:486) and `burnWrapped` (sDGNRS:506) route to EITHER `_deterministicBurnFrom` (State-2 gameOver) OR `_submitGamblingClaimFrom` (State-0). The short-circuit at L487/L509 (`if (game.gameOver())`) ensures a single burn call burns a token exactly ONCE via exactly ONE path. No double-burn.

`burnAtGameOver` is onlyGame — only the DegenerusGame contract via `GameOverModule.handleGameOverDrain` L146 triggers it. It burns `balanceOf[address(this)]` (sDGNRS's own undistributed pool remainder), which is disjoint from any player's balance. So `burnAtGameOver` cannot double-burn a player's token.

`transferFromPool` self-win burn is only triggered when a Game-driven distribution tries to move tokens from sDGNRS pool to sDGNRS itself (a no-op that the code converts to a supply reduction). This is disjoint from all player burns.

**Exactly-one-burn-per-token invariant:**

Every sDGNRS token `T` has a unique MINT at constructor (either to `ContractAddresses.DGNRS` via L307 or to `address(this)` via L308). `T` then moves via:
1. `balanceOf[DGNRS]` → `balanceOf[creator]` via `wrapperTransferTo` (creator unwraps); subsequent burn via `DegenerusStonk.burn` → `sDGNRS.burn` → `_deterministicBurnFrom` (State-2) OR `_submitGamblingClaimFrom` (State-0).
2. `balanceOf[address(this)]` → `balanceOf[recipient]` via `transferFromPool`; subsequent burn via the recipient's `sDGNRS.burn` or `burnWrapped`.
3. `balanceOf[address(this)]` → burned via `burnAtGameOver` (game-over cleanup).
4. `balanceOf[address(this)]` → burned via `transferFromPool` self-win at L427.

Each token follows exactly one branch and is burned at most once. No ghost token can be created without a matching mint (the only mint site is `_mint`, which has only 2 call sites in constructor). No dust from `transferFromPool` rounding — L418-420 caps `amount` at `available` so `transferred <= amount` with exact equality (no fractional rounding introduced).

**Cross-cite corroborating prior-milestone artifacts per CONTEXT.md D-17:**
- v29.0 Phase 235 (SDGNRS supply-conservation proof) re-derived same invariant at HEAD `1646d5af`.
- v24.0 gameover flow audit re-verified `burnAtGameOver` zeroing invariant.
- v3.3 gambling burn audit (CP-08 fix) established the 2-stage entry invariant and no-double-burn property.

### Verdict rows

| Verdict Row ID | REQ-ID | Source Row(s) | File:Line | Adversarial Vector | Verdict | Evidence | Owning Commit SHA |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SDR-07-V01 | SDR-07 | Constructor + `_mint` sweep | contracts/StakedDegenerusStonk.sol:307-308 + :874-881 | SDR-07a genesis mint exactly twice (creator + pool) | SAFE | `_mint` is `private`; grep confirms only 2 call sites (L307 creator, L308 pool); no other internal callers; no admin path; no post-deploy mint possible. Genesis supply = creatorAmount + poolTotal = INITIAL_SUPPLY (with dust reassigned to lootbox at L298-302). Total minted is bounded and deterministic at deploy. | 771893d1 |
| SDR-07-V02 | SDR-07 | `transferFromPool` BPS analysis | contracts/StakedDegenerusStonk.sol:412-435 | SDR-07b no dust mint from pool-distribution rounding | SAFE | L418-420 clamps `amount` to `available` if requested exceeds pool. Decrements `poolBalances[idx]` + `balanceOf[address(this)]` by `amount` (atomic). Self-win edge at L425-428 burns (decrements supply). Non-self distributions move tokens wire-for-wire. `transferred == amount` returned at L434. No dust mint possible — the function only MOVES or BURNS, never MINTS. | 771893d1 |
| SDR-07-V03 | SDR-07 | `burnAtGameOver` | contracts/StakedDegenerusStonk.sol:462-471 | SDR-07a contract-self-burn at gameover | SAFE | onlyGame modifier; zeros `balanceOf[address(this)]` and decrements `totalSupply` by that amount; cannot burn tokens held by any non-self address (hard-wired to `address(this)`). Disjoint from player burns. Cross-cite v24.0 Phase 204-206 burnAtGameOver zeroing-invariant proof as corroborating. | 771893d1 |
| SDR-07-V04 | SDR-07 | `_deterministicBurnFrom` + `_submitGamblingClaimFrom` | contracts/StakedDegenerusStonk.sol:527-569 + :752-814 | SDR-07a player-initiated burn atomicity | SAFE | Both paths burn `amount` with atomic `balanceOf[burnFrom] = bal - amount; totalSupply -= amount` inside `unchecked` block. The `unchecked` is safe: `bal - amount` cannot underflow because `amount > bal` reverts at L529 (`_deterministicBurnFrom`) or L754 (`_submitGamblingClaimFrom`) before reaching the subtraction. Balance + supply decrement are ATOMIC (same block, no external call between). | 771893d1 |
| SDR-07-V05 | SDR-07 | Burn-path mutual-exclusion | contracts/StakedDegenerusStonk.sol:487 + :509 + :462 (onlyGame) | SDR-07a gambling-burn vs deterministic-burn disjointness | SAFE | `burn` L487 short-circuit: `if (game.gameOver())` routes to `_deterministicBurn` else (after L491 State-1 revert + L492 rngLock check) routes to `_submitGamblingClaim`. Exactly one path per call. `burnWrapped` L509 same pattern. `burnAtGameOver` onlyGame — disjoint from player burns. Three burn-paths are partitioned by gate conditions (gameOver + livenessTriggered + onlyGame); no overlap. | 771893d1 |
| SDR-07-V06 | SDR-07 | v29.0 Phase 235 + v24.0 Phase 204-206 + v3.3 gambling burn audit (CP-08) | Cross-cite to prior-milestone artifacts per CONTEXT.md D-17 | SDR-07b corroborating prior-proof RE_VERIFIED at HEAD | SAFE via corroboration | v29.0 Phase 235 SDGNRS supply proof re-derives exactly-one-mint + at-most-one-burn invariant at HEAD 1646d5af; v24.0 Phase 204-206 verifies burnAtGameOver zeroing invariant; v3.3 gambling burn audit (CP-08 fix) established 2-stage entry at L789/L790 + no-double-burn. 245 SDR-07-V01..V05 re-derive equivalent at HEAD cc68bfc7 — equivalence with prior milestones confirms no regression. | 771893d1 |

### §SDR-07 Pre-Flag closure note

- Pre-Flag L2497 (sDGNRS supply mutations across lifecycle; gameover burnAtGameOver cascade from GameOverModule:146 → sDGNRS:462) — CLOSED via SDR-07-V01..V06: genesis mint exactly twice (V01); transferFromPool no dust mint (V02); burnAtGameOver contract-self-burn only (V03); atomic player-burn (V04); burn-path mutual exclusion (V05); prior-milestone corroboration (V06). The `dgnrs.burnAtGameOver()` cascade at GameOverModule:146 routes through DGNRS wrapper (which is distinct from sDGNRS's own burnAtGameOver); the cascade is handled within the dgnrs-wrapper's own burnAtGameOver implementation (not sDGNRS:462 directly — different contracts, different storage). sDGNRS:462 `burnAtGameOver` is triggered separately by the same `handleGameOverDrain` flow via its own onlyGame gate.

## §SDR-08 — _gameOverEntropy VRF-pending-redemption fallback fairness (F-29-04/EXC-03 class envelope)

### `_gameOverEntropy` structure at AdvanceModule:1228-1306 (HEAD cc68bfc7)

**Function signature:** `function _gameOverEntropy(uint48 ts, uint32 day, uint24 lvl, bool isTicketJackpotDay) private returns (uint256 word)`

**Early return (L1234):** `if (rngWordByDay[day] != 0) return rngWordByDay[day];` — if VRF word for this day is already stored, return it. No resolve, no fallback.

**Branch A — VRF-available (L1236-1261):** `uint256 currentWord = rngWordCurrent; if (currentWord != 0 && rngRequestTime != 0)`:
- L1238: `currentWord = _applyDailyRng(day, currentWord);` — mixes day + rngWord for daily entropy.
- L1239-1245: if `lvl != 0`, `coinflip.processCoinflipPayouts(isTicketJackpotDay, currentWord, day)` — pay out coinflip winners using the day's word.
- L1247-1258: resolve gambling burn period IF pending:
  - L1251 `if (sdgnrs.hasPendingRedemptions())` — check hasPendingRedemptions view
  - L1252-1254 `redemptionRoll = uint16(((currentWord >> 8) % 151) + 25)` — bounded [25,175]
  - L1255 `uint32 flipDay = day + 1;`
  - L1256 `sdgnrs.resolveRedemptionPeriod(redemptionRoll, flipDay);` — invoke onlyGame resolve (delegatecall preserves msg.sender==Game)
- L1259: `_finalizeLootboxRng(currentWord);`
- L1260: `return currentWord;` — exit branch A.

**Branch B — prevrandao-fallback (L1263-1295):** `if (rngRequestTime != 0)`:
- L1264: `uint48 elapsed = ts - rngRequestTime;`
- L1265: `if (elapsed >= GAMEOVER_RNG_FALLBACK_DELAY)` — 14-day grace per _VRF_GRACE_PERIOD at Storage:203.
- L1267: `uint256 fallbackWord = _getHistoricalRngFallback(day);` — collects up to 5 early historical VRF words + hashes.
- L1268: `fallbackWord = _applyDailyRng(day, fallbackWord);`
- L1269-1275: coinflip payouts (same as branch A).
- L1277-1288: resolve gambling burn period IF pending:
  - L1281 `if (sdgnrs.hasPendingRedemptions())`
  - L1282-1284 `redemptionRoll = uint16(((fallbackWord >> 8) % 151) + 25)`
  - L1285 `uint32 flipDay = day + 1;`
  - L1286 `sdgnrs.resolveRedemptionPeriod(redemptionRoll, flipDay);`
- L1289: `_finalizeLootboxRng(fallbackWord);`
- L1292: `rngRequestTime = 0;` — CLEAR stall lock (enables liveness re-evaluation).
- L1293: `return fallbackWord;` — exit branch B.

**Fall-through: VRF request retry (L1298-1305):** `if (_tryRequestRng(...)) return 1;` OR `rngWordCurrent = 0; rngRequestTime = ts; return 0;` (starts fallback timer).

### Branch disjointness proof

At any given gameover tick, exactly ONE of {early-return, Branch A, Branch B, fall-through} fires:
- If `rngWordByDay[day] != 0` → early-return (L1234). No resolve call this tick (day's resolve already happened in prior tick).
- Else if `currentWord != 0 && rngRequestTime != 0` → Branch A (L1237). Resolve at L1256.
- Else if `rngRequestTime != 0 && elapsed >= 14d` → Branch B (L1263-1265). Resolve at L1286.
- Else → fall-through (request new VRF, return 1 or 0).

Branches A and B are mutually exclusive because Branch A requires `currentWord != 0` AND Branch B (after failing A) requires `rngRequestTime != 0`. The first branch that matches triggers; subsequent branch checks don't run.

**Per-tick single resolve invariant:** exactly one of L1256 or L1286 executes per gameover tick (not both). Cross-cite Phase 244 GOX-06-V01 for the rngRequestTime clearing at L1292 ensuring the branch transitions are well-ordered.

### Vector SDR-08a — EXC-03 envelope RE_VERIFIED_AT_HEAD cc68bfc7 (per CONTEXT.md D-24)

**EXC-03 acceptance rationale (from KNOWN-ISSUES.md L38):**
- (a) only reachable at gameover — terminal state with no further gameplay after the 30-day post-gameover window
- (b) no player-reachable exploit — gameover triggered by 120-day liveness stall or pool deficit, neither timeable by attacker
- (c) at gameover the protocol must drain within bounded transactions
- (d) all substitute entropy is VRF-derived or VRF-plus-prevrandao

**NEW L1286 consumption check (the new 771893d1 surface):**
- **(a) terminal-state only:** YES. `_gameOverEntropy` is `private` in AdvanceModule. Sole caller is `_handleGameOverPath` at L560 (verified by grep). `_handleGameOverPath` is `private`, sole caller is advanceGame's gameover branch at `rngGate` or elsewhere. Branch-trace: advanceGame → `_handleGameOverPath` (when liveness fired OR gameOver latched) → `_gameOverEntropy`. Never reachable in State-0 normal-tick. Terminal-state bound preserved.
- **(b) no player-reachable exploit:** YES. Neither the roll value nor the fallback word is player-controllable:
  - Branch A roll at L1252-1254 derived from `currentWord = rngWordCurrent` (set by VRF coordinator callback, not player input).
  - Branch B roll at L1282-1284 derived from `fallbackWord = _getHistoricalRngFallback(day)` (hashes early historical VRF words + prevrandao admixture per EXC-02).
  - Player cannot influence currentWord (VRF coordinator owns), cannot pre-image prevrandao (set by validators), cannot time gameover (120-day stall or pool deficit determined by protocol state).
  - The `day + 1` for flipDay at L1255/L1285 is not player-controllable.
  - Commitment window per `feedback_rng_commitment_window.md`: between VRF request and `_gameOverEntropy` consumption, what player-controllable state could change?
    - `sdgnrs.hasPendingRedemptions()` at L1251/L1281 is a VIEW reading `pendingRedemptionEthBase != 0 || pendingRedemptionBurnieBase != 0` (sDGNRS:577-579).
    - Player can add a burn after VRF request but BEFORE `_gameOverEntropy` consumption, IFF State-0 (not blocked by L491). In State-0, advanceGame ticks would resolve via rngGate normal-tick NOT `_gameOverEntropy`; `_gameOverEntropy` only fires if liveness has triggered (State-1) which blocks new burns.
    - So the `pendingRedemptionEthBase`/`pendingRedemptionBurnieBase` values at `_gameOverEntropy` consumption are those present at the moment liveness fired. Additional burns cannot be committed between liveness-fire and `_gameOverEntropy` consumption because L491 blocks. Commitment window is closed.
  - Backward-trace per `feedback_rng_backward_trace.md`: the roll value at L1286 resolves the redemption period; the period's stake was committed at `_submitGamblingClaimFrom` L803 (`claim.ethValueOwed += uint96(ethValueOwed)`) in State-0 (burn time). At `_submitGamblingClaimFrom` time, the future `_gameOverEntropy` roll was unknown-but-bound (VRF word not yet delivered, prevrandao not yet committed). Invariant holds.
- **(c) bounded transactions:** YES. `_gameOverEntropy` resolves a single period per call (L1256 or L1286). Called at most once per gameover tick (branch disjointness). Multiple pending periods from prior days would accumulate in `pendingRedemptionEthValue` ledger but the CURRENT period (tracked by `redemptionPeriodIndex`) is resolved in the single call; subsequent calls resolve subsequent periods. Bounded by the number of periods × 1 tick each.
- **(d) VRF-derived or VRF-plus-prevrandao:** YES. Branch A: VRF-only (`currentWord` from `rngWordCurrent` which is VRF-delivered at `rawFulfillRandomWords`). Branch B: VRF-plus-prevrandao admixture per `_getHistoricalRngFallback` + `_applyDailyRng` (verified in Phase 240 GO-240-NNN rows as corroborating).

**All 4 criteria preserved at HEAD cc68bfc7. EXC-03 envelope RE_VERIFIED_AT_HEAD cc68bfc7. Cross-cite Phase 244 RNG-01-V11 as PRIMARY non-widening proof at the `_unlockRng` removal scope — 245 SDR-08-V01 is the CANONICAL CARRIER for the NEW L1286 redemption-resolve-consumption site within the same envelope.**

### Vector SDR-08b — no pending-limbo, no over-substitute, no under-resolve

**(1) No pending-limbo:**

For every pending redemption period active at gameover-latch, exactly one resolve call (L1256 or L1286) fires at the next gameover tick. `_gameOverEntropy` is called from `_handleGameOverPath` at L560 BEFORE `handleGameOverDrain` at L625-630. Inside `_gameOverEntropy`, `sdgnrs.hasPendingRedemptions()` at L1251/L1281 checks `pendingRedemptionEthBase != 0 || pendingRedemptionBurnieBase != 0`. If pending exists, resolve fires. If not, resolve is skipped (no pending to resolve).

**Scenario — multiple pending periods accumulated pre-gameover:** the protocol design at sDGNRS:588 says `period = redemptionPeriodIndex` (set by `_submitGamblingClaimFrom` at L760 `redemptionPeriodIndex = currentPeriod`). Each `_submitGamblingClaimFrom` increments the period to currentDayView. If multiple days passed without resolve (stall), the CURRENT period (redemptionPeriodIndex) is resolved; prior periods were resolved on their respective days via rngGate normal-tick. No prior periods are left pending at gameover unless advanceGame was entirely stalled across the period boundary.

If advanceGame was stalled (VRF-dead), gap-backfill at AdvanceModule:1160-1175 resolves backlog VRF words on resume, and each period resolves via its day's word in the normal-tick rngGate path. Gameover scenario: liveness fires, `_gameOverEntropy` resolves the CURRENT (most recent) pending period; prior periods already resolved.

**(2) No over-substitute:**

`_gameOverEntropy` is called exactly once per advanceGame tick per the `_handleGameOverPath` body (L559-567). Re-entry via STAGE_TICKETS_WORKING defers the next tick but does NOT re-enter `_gameOverEntropy` within the same tx. Cross-cite Phase 244 GOX-06-V01 for the rngRequestTime clearing at L1292 ensures consistent branch selection across subsequent ticks (once branch B fires, rngRequestTime is cleared, so next tick's `_gameOverEntropy` early-returns at L1234 because `rngWordByDay[day] != 0` from the `_applyDailyRng` call at L1268 which stores it).

Per-tick atomic pattern: one `_gameOverEntropy` call → one resolve call → one period resolved.

**(3) No under-resolve:**

Every VRF-pending redemption reaches resolve through one of:
- Branch A at L1256 (VRF-available: word delivered before gameover);
- Branch B at L1286 (prevrandao-fallback: VRF-dead 14-day grace);
- Normal rngGate at AdvanceModule:1193 (pre-gameover ticks resolve each day's redemptions).

If gameover fires and neither branch A nor branch B fires on this tick (e.g., `rngRequestTime == 0 && currentWord == 0` — no VRF request outstanding), the fall-through at L1298 requests new VRF; `_gameOverEntropy` returns 1 (in-flight signal). Next tick resumes: if VRF delivers, branch A fires; if VRF stays stalled, 14-day grace path enters branch B. Eventually one of the branches resolves the pending redemption.

**Guarantee:** the redemption cannot hang indefinitely. The 14-day grace is the UPPER BOUND — after 14 days of VRF stall post-gameover-latch, branch B fires and resolves via prevrandao-fallback. No pending-limbo.

### Verdict rows

| Verdict Row ID | REQ-ID | Source Row(s) | File:Line | Adversarial Vector | Verdict | Evidence | Owning Commit SHA |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SDR-08-V01 | SDR-08 | D-243-C016, D-243-F014, D-243-X027, D-243-I021, EXC-03, RNG-01-V11 (primary non-widening) | contracts/modules/DegenerusGameAdvanceModule.sol:1286 + :1256 | SDR-08a EXC-03 envelope RE_VERIFIED_AT_HEAD — new redemption-resolve-consumption site at L1286 (and L1256) | RE_VERIFIED_AT_HEAD cc68bfc7 | 4 EXC-03 envelope criteria (a-d) re-verified at HEAD cc68bfc7: (a) terminal-state only — `_gameOverEntropy` is private, sole caller `_handleGameOverPath` only runs gameover branch; (b) no player-reachable exploit — roll derived from VRF word or VRF+prevrandao admixture; commitment window closed by State-1 L491 burn-block; backward-trace shows roll unknown at burn-commit time; (c) bounded transactions — single resolve call per tick; (d) VRF-derived or VRF+prevrandao. Cross-cite Phase 244 RNG-01-V11 as PRIMARY non-widening proof at the `_unlockRng` removal scope; SDR-08-V01 is CANONICAL carrier for the NEW L1286/L1256 redemption-resolve-consumption within the same envelope. Envelope does NOT widen — the L1286/L1256 resolve is a consumer within the same mid-cycle-substitution acceptance boundary. | 771893d1 |
| SDR-08-V02 | SDR-08 | D-243-C016, GOX-06-V01 (shared-context) | contracts/modules/DegenerusGameAdvanceModule.sol:1237-1260 | SDR-08b VRF-available branch (L1256) redemption-resolve fairness | SAFE | `currentWord = rngWordCurrent` sourced from VRF coordinator callback (rawFulfillRandomWords); redemptionRoll derived via `uint16(((currentWord >> 8) % 151) + 25)` bounded [25,175]; branch disjoint with fallback branch (branch A requires `currentWord != 0 && rngRequestTime != 0`); exactly-one-call per tick per `_handleGameOverPath` atomic call-chain. | 771893d1 |
| SDR-08-V03 | SDR-08 | D-243-C016, D-243-C028, EXC-02, EXC-03 | contracts/modules/DegenerusGameAdvanceModule.sol:1263-1294 | SDR-08b prevrandao-fallback branch (L1286) redemption-resolve fairness under 14-day grace | SAFE | `fallbackWord` from `_getHistoricalRngFallback` (VRF-derived) mixed with prevrandao via `_applyDailyRng` per EXC-02 acceptance; redemptionRoll bounded [25,175] via same mod-151 formula; L1292 `rngRequestTime = 0` clears stall lock after resolve (ensures subsequent tick's branch selection is correct); branch disjoint with VRF-available via `rngRequestTime != 0 && elapsed >= 14d` gate. | 771893d1 |
| SDR-08-V04 | SDR-08 | D-243-C015, D-243-X027, GOX-06-V02 (shared-context) | contracts/modules/DegenerusGameAdvanceModule.sol:523-634 + :1228-1306 + :1251 + :1281 | SDR-08b no-over-substitute / no-under-resolve via call-graph + hasPendingRedemptions gate | SAFE | `_gameOverEntropy` called by `_handleGameOverPath` at L560 exactly once per gameover tick (no recursion, no re-entry within the same tx). `hasPendingRedemptions()` gate at L1251/L1281 ensures resolve only fires when pending exists; skips when clean. Gap-backfill at AdvanceModule:1160-1175 resolves backlog periods on VRF resume (prior days' redemptions resolved via normal-tick rngGate). 14-day grace at L1265 is UPPER BOUND — ensures branch B eventually fires if VRF stays stalled post-liveness. No pending-limbo. Cross-cite GOX-06-V02 for gameOver-before-liveness ordering at `_handleGameOverPath`:540 ensuring post-gameover final-sweep path stays reachable. | 771893d1 |

### §SDR-08 Pre-Flag closure note

- Pre-Flag L2500 (SDR-08 `_gameOverEntropy` L1286 new consumption within EXC-03 envelope; verify no pending-limbo / over-substitute / under-resolve across multiple gameover ticks) — CLOSED via SDR-08-V01..V04: envelope criteria (a-d) re-verified at HEAD (V01); VRF-available branch L1256 disjoint + bounded (V02); prevrandao-fallback branch L1286 bounded + stall-lock clear (V03); call-graph single-call-per-tick + hasPendingRedemptions gate + 14-day grace upper-bound (V04). EXC-03 envelope does NOT widen — the new consumption is within the acceptance boundary per CONTEXT.md D-24.

## §KI Envelope Re-Verify — EXC-03 (Gameover RNG substitution / F-29-04 class) under new 14-day VRF-dead grace + new L1286 redemption-resolve-consumption

**Canonical annotation:** `RE_VERIFIED_AT_HEAD cc68bfc7` — EXC-03 envelope is NOT re-litigated; only the non-widening is re-verified per CONTEXT.md D-24.

**Carrier row:** SDR-08-V01 (see §SDR-08 above).

**Scope note:** Per CONTEXT.md D-24, the 4 accepted RNG exceptions in KNOWN-ISSUES.md (EXC-01..04) are RE_VERIFIED for envelope-non-widening only. GOE-01 (Phase 245-02) verifies EXC-03 envelope under the new 14-day grace Tier-1 gate at Storage:1241-1242 from the F-29-04 mid-cycle-substitution angle; SDR-08 (this section) verifies EXC-03 envelope under the new L1286 redemption-resolve-consumption from the NEW-consumer angle. Both sub-audits conclude RE_VERIFIED_AT_HEAD with no widening.

**Primary non-widening proof cross-cite:** Phase 244 RNG-01-V11 (at v31-244-PER-COMMIT-AUDIT.md §RNG-01) — closed the `_unlockRng` removal scope envelope check. SDR-08 owns the NEW consumption site within the same envelope.

**Acceptance criteria re-verified at HEAD cc68bfc7 (per SDR-08-V01 evidence):**
- (a) terminal-state only: `_gameOverEntropy` reachable only via `_handleGameOverPath` post-liveness-fire;
- (b) no player-reachable exploit: roll derivation from VRF/VRF-prevrandao, commitment window closed by L491 burn-block;
- (c) bounded transactions: single resolve call per tick;
- (d) VRF-derived or VRF-plus-prevrandao: both branches satisfy.

**Annotation:** `RE_VERIFIED_AT_HEAD cc68bfc7` — envelope unchanged.

## §Phase-244-Pre-Flag Cross-Walk — SDR bucket (10 bullets at v31-244-PER-COMMIT-AUDIT.md L2477-2500 per CONTEXT.md D-25)

Consumed as ADVISORY input per CONTEXT.md D-25. Each bullet receives a one-line closure note below. Closures may differ from the Pre-Flag's suggested vector (a Pre-Flag may suggest "test X"; Phase 245 may respond "X is verified SAFE via vector Y" OR "X is SAFE by cross-cite to Phase 244 Z").

**SDR-01 (2 bullets):**
- L2477 (claimRedemption ungated by state) → CLOSED via SDR-01-V03 (property-to-prove SAFE per CONTEXT.md D-09; no standalone INFO candidate).
- L2478 (resolveRedemptionPeriod two callers — rngGate + _gameOverEntropy) → CLOSED via SDR-01-Ta foundation row (rngGate L1193 covers Ta/Tb/Td) + SDR-01-Tf foundation row (_gameOverEntropy L1256/L1286 covers Tf); third call site at L1256 discovered in-phase, cross-ref SDR-08-V02.

**SDR-02 (2 bullets):**
- L2481 (pendingRedemptionEthValue L593 roll-adjust conservation) → CLOSED via SDR-02-V01 (two-stage entry invariant) + SDR-02-V04 (per-timing invariant).
- L2482 (_deterministicBurnFrom L535 subtraction) → CLOSED via SDR-02-V02 (exclusion-from-payout-base; no double-counting).

**SDR-03 (1 bullet):**
- L2485 (deeper multi-tx drain edges beyond 244 GOX-03) → CLOSED via SDR-03-V03 (idempotency-irreversibility + STAGE_TICKETS_WORKING-before-drain + staticcall-safety).

**SDR-04 (1 bullet — Task 2):**
- L2488 (claimRedemption DOS + 30-day sweep sufficiency + multi-drain bypass of L80 bit) → CLOSED via SDR-04-V01..V04 (4-actor DOS analysis + 30-day window gate is clock-based + handleFinalSweep operates on Game balance NOT sDGNRS balance (reserved wei preserved on sDGNRS indefinitely) + underflow construction invariant + 3-ordering race-permutation analysis). Sub-claim on L80 bypass CLOSED via SDR-03-V03 cross-cite.

**SDR-05 (1 bullet — Task 2):**
- L2491 (per-wei conservation across 6 gameover timings Ta/Tb/Tc/Td/Te/Tf) → CLOSED via SDR-05-V01..V06 (one worked wei ledger per timing; conservation invariant holds across all 6 timings; no dust beyond NatSpec-documented (n-1) wei floor).

**SDR-06 (1 bullet — Task 2):**
- L2494 (SDR-06 negative-space sweep beyond Phase 244 GOX-02 primary closure) → CLOSED via SDR-06-V01/V02 primary cross-cite (GOX-02-V01/V02) + SDR-06-V03..V07 5-vector deeper sweep (admin psd manipulation impossible; level-transition monotonic; constructor path unreachable; cross-chain vacuous; reentrancy surface empty).

**SDR-07 (1 bullet — Task 3):**
- L2497 (sDGNRS supply mutations across lifecycle; gameover burnAtGameOver cascade from GameOverModule:146 → sDGNRS:462) → CLOSED via SDR-07-V01..V06 (genesis mint exactly twice + transferFromPool no dust mint + burnAtGameOver contract-self-burn only + atomic player-burn + burn-path mutual exclusion + prior-milestone corroboration per CONTEXT.md D-17).

**SDR-08 (1 bullet — Task 3):**
- L2500 (SDR-08 `_gameOverEntropy` L1286 new consumption within EXC-03 envelope; verify no pending-limbo / over-substitute / under-resolve across multiple gameover ticks) → CLOSED via SDR-08-V01..V04 (envelope 4-criteria RE_VERIFIED_AT_HEAD cc68bfc7 per D-24 + VRF-available L1256 branch disjoint + prevrandao-fallback L1286 stall-lock clear + call-graph single-call-per-tick + hasPendingRedemptions gate + 14-day grace upper-bound). Cross-cite Phase 244 RNG-01-V11 as PRIMARY non-widening proof.

## §Reproduction Recipe — SDR bucket

Commands actually used during Task 1 execution (POSIX-portable, shell-safe).

```sh
# Sanity gate (§Step A per plan)
git rev-parse 7ab515fe
git rev-parse cc68bfc7
git rev-parse HEAD
git diff --stat cc68bfc7..HEAD -- contracts/
git status --porcelain contracts/ test/

# Locate all resolveRedemptionPeriod call sites
grep -rn 'resolveRedemptionPeriod' contracts/

# Locate all pendingRedemption* mutations in sDGNRS
grep -n 'pendingRedemption' contracts/StakedDegenerusStonk.sol

# Locate GO_JACKPOT_PAID writer sites (prove L148 is the sole writer)
grep -n 'GO_JACKPOT_PAID' contracts/modules/DegenerusGameGameOverModule.sol

# Locate _VRF_GRACE_PERIOD constant
grep -n '_VRF_GRACE_PERIOD' contracts/storage/DegenerusGameStorage.sol

# Locate burn callers
grep -n '\.burn(' contracts/DegenerusStonk.sol contracts/DegenerusVault.sol

# Show core functions (verbatim per plan read_first)
sed -n '486,516p' contracts/StakedDegenerusStonk.sol     # burn + burnWrapped
sed -n '527,569p' contracts/StakedDegenerusStonk.sol     # _deterministicBurnFrom
sed -n '585,610p' contracts/StakedDegenerusStonk.sol     # resolveRedemptionPeriod
sed -n '618,684p' contracts/StakedDegenerusStonk.sol     # claimRedemption
sed -n '752,814p' contracts/StakedDegenerusStonk.sol     # _submitGamblingClaimFrom
sed -n '79,189p'  contracts/modules/DegenerusGameGameOverModule.sol     # handleGameOverDrain
sed -n '225,233p' contracts/modules/DegenerusGameGameOverModule.sol     # _sendToVault
sed -n '1148,1214p' contracts/modules/DegenerusGameAdvanceModule.sol    # rngGate + L1193 resolveRedemptionPeriod
sed -n '1228,1306p' contracts/modules/DegenerusGameAdvanceModule.sol    # _gameOverEntropy + L1256 VRF-available + L1286 fallback
sed -n '1235,1243p' contracts/storage/DegenerusGameStorage.sol          # _livenessTriggered predicate
sed -n '88,90p'     contracts/interfaces/IStakedDegenerusStonk.sol      # pendingRedemptionEthValue interface

# Verify zero source-tree drift vs anchor
git diff cc68bfc7..HEAD -- contracts/ | wc -l
```

### Task 2 commands (SDR-04 + SDR-05 + SDR-06)

```sh
# Sanity gate (re-verify at Task 2 start)
git rev-parse cc68bfc7
git diff --stat cc68bfc7..HEAD -- contracts/
git status --porcelain contracts/ test/

# SDR-04 reads
sed -n '618,684p' contracts/StakedDegenerusStonk.sol     # claimRedemption body (L657 decrement, L683 _payEth)
sed -n '817,839p' contracts/StakedDegenerusStonk.sol     # _payEth fallback to stETH
sed -n '196,216p' contracts/modules/DegenerusGameGameOverModule.sol   # handleFinalSweep 30-day gate
sed -n '225,233p' contracts/modules/DegenerusGameGameOverModule.sol   # _sendToVault 33/33/34 split

# SDR-05 per-timing worked wei ledger (reproduce ledger math from storage variable semantics)
sed -n '221,227p' contracts/StakedDegenerusStonk.sol     # PendingRedemption + RedemptionPeriod struct layouts + pending storage

# SDR-06 negative-space sweep
grep -rn 'purchaseStartDay' contracts/                    # Zero admin write paths — only constructor + advanceGame internals
grep -n 'livenessTriggered\|gameOver\|rngLocked' contracts/modules/DegenerusGameMintModule.sol | head -10  # Liveness gates in MintModule
grep -rn 'import\|bridge\|crosschain\|layerzero\|wormhole' contracts/ | grep -v '^contracts/interfaces\|\.sol:.*//' | head  # Cross-chain vector — zero results
sed -n '289,323p' contracts/StakedDegenerusStonk.sol     # constructor body (claimWhalePass + setAfKingMode; no burn path)
sed -n '344,360p' contracts/DegenerusStonk.sol           # burnForSdgnrs body (protocol-internal, non-reentrant)
sed -n '325,340p' contracts/modules/DegenerusGameAdvanceModule.sol    # Level transition psd write at L330
sed -n '1160,1180p' contracts/modules/DegenerusGameAdvanceModule.sol  # Gap-backfill psd += gapCount at L1174
```

### Task 3 commands (SDR-07 + SDR-08 + KI EXC-03 envelope re-verify)

```sh
# Sanity gate (re-verify at Task 3 start)
git rev-parse cc68bfc7
git diff --stat cc68bfc7..HEAD -- contracts/
git status --porcelain contracts/ test/

# SDR-07 supply mutation enumeration
grep -n '_mint(' contracts/StakedDegenerusStonk.sol                                  # Constructor + declaration
grep -n 'totalSupply\b' contracts/StakedDegenerusStonk.sol                           # All supply write sites
sed -n '289,323p' contracts/StakedDegenerusStonk.sol                                 # Constructor body
sed -n '412,435p' contracts/StakedDegenerusStonk.sol                                 # transferFromPool (with self-win edge at L425-428)
sed -n '443,458p' contracts/StakedDegenerusStonk.sol                                 # transferBetweenPools
sed -n '462,471p' contracts/StakedDegenerusStonk.sol                                 # burnAtGameOver
sed -n '527,569p' contracts/StakedDegenerusStonk.sol                                 # _deterministicBurnFrom (L539-540 burn)
sed -n '752,814p' contracts/StakedDegenerusStonk.sol                                 # _submitGamblingClaimFrom (L783-784 burn)
sed -n '337,347p' contracts/StakedDegenerusStonk.sol                                 # wrapperTransferTo (balance-only)
sed -n '874,881p' contracts/StakedDegenerusStonk.sol                                 # _mint internal implementation

# SDR-08 _gameOverEntropy branch analysis
sed -n '1228,1306p' contracts/modules/DegenerusGameAdvanceModule.sol                 # Full _gameOverEntropy body
grep -n '_gameOverEntropy\b' contracts/modules/DegenerusGameAdvanceModule.sol        # Sole caller at L560 of _handleGameOverPath
sed -n '200,204p' contracts/storage/DegenerusGameStorage.sol                         # _VRF_GRACE_PERIOD constant = 14 days
sed -n '1235,1243p' contracts/storage/DegenerusGameStorage.sol                       # _livenessTriggered predicate

# KI EXC-03 envelope re-verify inputs
grep -n 'EXC-03\|F-29-04' KNOWN-ISSUES.md                                            # Acceptance rationale
grep -n 'RNG-01-V11' audit/v31-244-PER-COMMIT-AUDIT.md                               # Phase 244 primary non-widening proof

# Commitment-window analysis (per feedback_rng_commitment_window.md skill)
sed -n '577,583p' contracts/StakedDegenerusStonk.sol                                 # hasPendingRedemptions view
sed -n '486,516p' contracts/StakedDegenerusStonk.sol                                 # burn + burnWrapped (L491/L507 State-1 block closes commitment window)
```



## §2 — GOE Bucket (commit 771893d1 + cc68bfc7 BAF-coupling addendum — pre-existing gameover invariant RE_VERIFIED_AT_HEAD; plan 245-02)

*(Embedded verbatim from `audit/v31-245-GOE.md` at HEAD cc68bfc7; file-level header dropped — consolidated header above replaces it.)*

Sanity gate results (captured at Task 1 start):
- `git rev-parse cc68bfc7` → `cc68bfc70e76fb75ac6effbc2135aae978f96ff3` (matched anchor)
- `git rev-parse HEAD` → `1446b570f938409509834640ca06e077bc209ca1` (planning/audit appends from 245-01 SUMMARY land; zero source-tree drift)
- `git diff --stat cc68bfc7..HEAD -- contracts/` → empty (zero hunks, anchor clean)
- `git status --porcelain contracts/ test/` → empty

## §0 — Per-Bucket Verdict Count Card

| REQ-ID | Verdict Rows | Finding Candidates | KI Envelope Status | Floor Severity |
| --- | --- | --- | --- | --- |
| GOE-01 | 2 standard (`GOE-01-V01..V02`) — V01 is `RE_VERIFIED_AT_HEAD cc68bfc7` carrier for EXC-03 envelope | 0 | EXC-03 RE_VERIFIED_AT_HEAD cc68bfc7 | SAFE (1 SAFE + 1 RE_VERIFIED_AT_HEAD) |
| GOE-02 | 3 standard (`GOE-02-V01..V03`) | 0 | n/a | SAFE |
| GOE-03 | 3 standard (`GOE-03-V01..V03`) | 0 | n/a | SAFE |
| GOE-04 | 3 standard (`GOE-04-V01..V03`) — V02 is `RE_VERIFIED_AT_HEAD cc68bfc7` carrier for EXC-02 envelope | 0 | EXC-02 RE_VERIFIED_AT_HEAD cc68bfc7 | SAFE (2 SAFE + 1 RE_VERIFIED_AT_HEAD) |
| GOE-05 | 2 standard (`GOE-05-V01..V02`) | 0 | n/a | SAFE |
| GOE-06 | 2 standard (`GOE-06-V01..V02`) — Candidate 1 + Candidate 2 closures per CONTEXT.md D-12 | 0 | n/a | SAFE (per D-13 aggregate) |

**Aggregate:** 15 standard verdict rows across GOE-01..GOE-06. All 6 GOE REQs closed at SAFE floor severity. Zero F-31-NN finding-IDs emitted per CONTEXT.md D-23. EXC-02 + EXC-03 KI envelopes both RE_VERIFIED_AT_HEAD cc68bfc7 with no widening.

---

## §GOE-01 — F-29-04 RNG-consumer determinism envelope RE_VERIFIED_AT_HEAD cc68bfc7

### §GOE-01 — Standard verdict rows (adversarial vectors GOE-01a + GOE-01b per CONTEXT.md D-16)

| Verdict Row ID | REQ-ID | Source Row(s) | File:Line | Adversarial Vector | Verdict | Evidence | Owning Commit SHA |
| --- | --- | --- | --- | --- | --- | --- | --- |
| GOE-01-V01 | GOE-01 | D-243-C016, D-243-C026, D-243-C028, D-243-I019, D-243-I021, EXC-03 (KNOWN-ISSUES.md L38), RNG-01-V11 (Phase 244 PRIMARY non-widening proof) | contracts/modules/DegenerusGameAdvanceModule.sol:1228-1306 + contracts/storage/DegenerusGameStorage.sol:1235-1243 + contracts/modules/DegenerusGameAdvanceModule.sol:1301 (`_getHistoricalRngFallback`) | GOE-01a EXC-03 4-criterion envelope RE_VERIFIED_AT_HEAD (terminal-state + no-player-exploit + bounded-tx + VRF-derived-entropy) | RE_VERIFIED_AT_HEAD cc68bfc7 | Criterion-by-criterion re-verify at HEAD: (a) `_gameOverEntropy` reachable only via `_handleGameOverPath` at AdvanceModule:560 per GOX-06-V02 — `_handleGameOverPath` gates on L551 `!_livenessTriggered()` return; terminal-state gate preserved at HEAD. (b) Liveness predicate at Storage:1239-1242 is {120/365-day stall OR `rngStart != 0 && block.timestamp - rngStart >= 14 days`} — ALL three triggers are external infrastructure clocks, not player-timeable against a specific mid-cycle write-buffer state. (c) `_gameOverEntropy` branches at AdvanceModule:1237-1259 (VRF-available) + :1263-1293 (prevrandao-fallback) both resolve synchronously in the same advanceGame tx; no deferred fulfillment (RngNotReady revert at :1295 is PRE-grace only). (d) VRF-available branch uses `rngWordCurrent` (committed VRF word per GOX-06-V01); prevrandao-fallback uses `_getHistoricalRngFallback` at :1301 which hashes up to 5 committed historical VRF words keccak'd with `block.prevrandao` (single prevrandao site unchanged at HEAD vs baseline per GOX-04-V02). All 4 criteria HOLD at HEAD cc68bfc7. Cross-cite RNG-01-V11 for PRIMARY non-widening proof at the `_unlockRng` removal scope; GOE-01-V01 confirms envelope preserved under the full `_gameOverEntropy` body. | 771893d1 |
| GOE-01-V02 | GOE-01 | D-243-C026, D-243-C028, Pre-Flag bullet L2503, RNG-01-V11, SDR-08-V01 (cross-file from 245-01 SDR bucket) | contracts/storage/DegenerusGameStorage.sol:1242 + contracts/modules/DegenerusGameAdvanceModule.sol:1228-1306 | GOE-01b DEEPER: new 14-day Tier-1 grace × mid-cycle ticket-buffer swap interaction — does the grace introduce a NEW way for mid-cycle swap to trigger `_gameOverEntropy` consumption? | SAFE | Per project skill `feedback_rng_backward_trace.md`: traced BACKWARD from `_gameOverEntropy` consumer to verify every input-committing state mutation. Mid-cycle ticket-buffer swap is triggered by `_swapAndFreeze(purchaseLevel)` at AdvanceModule:292 (daily RNG request) OR `_swapTicketSlot(purchaseLevel_)` at AdvanceModule:1082 (mid-day lootbox RNG) — both swap call-sites UNCHANGED at HEAD vs baseline (no 771893d1 edit to the swap triggers per D-243 changelog). Per project skill `feedback_rng_commitment_window.md`: the commitment window between VRF request and fulfillment spans from `_swapAndFreeze`/`_swapTicketSlot` to the next `rngGate` fulfillment — the NEW Tier-1 14-day grace at Storage:1242 adds an ALTERNATIVE liveness-fire trigger (VRF stall) but does NOT add a new swap trigger; the grace fires liveness → `_handleGameOverPath` → `_gameOverEntropy`, which reads the SAME input-committed ticket-buffer state that was committed at swap time. Enumeration: for (day ∈ [14, 120), level ∈ {0, 1-9, 10+}, VRF-state = stalled≥14d), Tier-1 fires liveness via L1242 `rngStart != 0 && block.timestamp - rngStart >= 14 days`; if day-math threshold unmet (e.g., day 20, level 1, 120-day threshold), liveness fires via grace ONLY → `_gameOverEntropy` prevrandao-fallback branch L1263 fires (currentWord==0 AND rngRequestTime!=0 AND elapsed>=grace) → consumes the SAME committed write-buffer tickets that were queued at swap time. NO new input-commitment window opens. EXC-03 envelope covers this consumption path per criterion (a)(b)(c)(d) re-verified at V01. Cross-cite 245-01 SDR-08-V01 for the NEW redemption-resolve consumption at L1286 within the same envelope; SDR-08 proved the `sdgnrs.resolveRedemptionPeriod` call operates on committed `pendingRedemptionEthValue` state. Envelope does NOT widen. | 771893d1 |

## §KI Envelope Re-Verify — EXC-03 (F-29-04 class) under new 14-day Tier-1 VRF-dead grace

Phase 244 RNG-01-V11 PRIMARY non-widening proof: at the `_unlockRng` removal scope, the EXC-03 envelope (mid-cycle ticket-buffer swap under fallback entropy) was re-verified disjoint from the non-gameover RNG-consumer path. The new Tier-1 14-day grace constant `_VRF_GRACE_PERIOD` at contracts/storage/DegenerusGameStorage.sol:203 defines the liveness-fire threshold for stalled-VRF (`rngStart != 0 && block.timestamp - rngStart >= _VRF_GRACE_PERIOD`). Phase 245 GOE-01-V01 RE_VERIFIES the same 4-criterion envelope at the full `_gameOverEntropy` body scope AT HEAD cc68bfc7. GOE-01-V02 extends to the DEEPER 14-day-grace × mid-cycle-swap interaction per CONTEXT.md D-14 GOE-01.

**Result:** EXC-03 envelope RE_VERIFIED_AT_HEAD cc68bfc7. No envelope widening. Phase 246 FIND-03 KI delta for EXC-03 = zero (envelope unchanged).

**Pre-Flag closure notes (§GOE-01):**

- Pre-Flag L2503 (GOE-01 14-day grace × F-29-04 interaction — does the new Tier-1 grace introduce a NEW way for mid-cycle swap to trigger `_gameOverEntropy` consumption?) → CLOSED via GOE-01-V02 (DEEPER backward-trace enumeration confirms no new swap-trigger introduced; envelope preserved per criterion (a)-(d) at V01).

---

## §GOE-02 — claimablePool 33/33/34 split + 30-day sweep against new drain flow RE_VERIFIED_AT_HEAD cc68bfc7

### §GOE-02 — Standard verdict rows (adversarial vectors GOE-02a + GOE-02b per CONTEXT.md D-16)

| Verdict Row ID | REQ-ID | Source Row(s) | File:Line | Adversarial Vector | Verdict | Evidence | Owning Commit SHA |
| --- | --- | --- | --- | --- | --- | --- | --- |
| GOE-02-V01 | GOE-02 | D-243-C017, D-243-F015, D-243-I018, GOX-03-V01/V02 (Phase 244 PRIMARY handleGameOverDrain subtraction), v24.0 split spec | contracts/modules/DegenerusGameGameOverModule.sol:79-189 (handleGameOverDrain) + :225-233 (`_sendToVault`) | GOE-02a 33/33/34 split at `_sendToVault` operates on post-subtraction `available`, not pre-subtraction `totalFunds` | SAFE | Body trace at HEAD: L86-88 `ethBal + stBal = totalFunds`; L94-95 `reserved = claimablePool + pendingRedemptionEthValue()` then `preRefundAvailable = totalFunds - reserved`; L148 `_goWrite(GO_JACKPOT_PAID_SHIFT, ..., 1)` latches idempotency; L155-157 post-refund `postRefundReserved = claimablePool + pendingRedemptionEthValue()` + `available = totalFunds - postRefundReserved`; L158 `if (available == 0) return`; L181-186 `runTerminalJackpot(remaining, lvl+1, rngWord)` returns `termPaid`, `remaining -= termPaid`; L184-186 `if (remaining != 0) _sendToVault(remaining, stBal)`. The input to `_sendToVault` is `remaining` — a strict subset of `available` (L158) which is `totalFunds - postRefundReserved`. `_sendToVault` at :225-233: L227 `thirdShare = amount / 3`; L228 `gnrusAmount = amount - 2*thirdShare` (34%); L231-233 sends stETH-first to SDGNRS (33%), VAULT (33%), GNRUS (34%). v24.0 33/33/34 proportions preserved; input is post-subtraction `remaining` per GOX-03-V01/V02 primary. 771893d1 added the `pendingRedemptionEthValue` subtractions at L94 + L157 — proportions unchanged, INPUT bucket shrinks by reserved pending-redemption wei (the intent of the subtraction). | 771893d1 |
| GOE-02-V02 | GOE-02 | D-243-C017, Pre-Flag bullet L2506, v24.0 30-day sweep spec, Phase 244 GOX-03-V03 (multi-tx drain edges PRIMARY) | contracts/modules/DegenerusGameGameOverModule.sol:196-216 (handleFinalSweep) | GOE-02b 30-day `handleFinalSweep` window sufficiency + no re-subtraction of pendingRedemptionEthValue | SAFE | Body trace at HEAD: L197 `if (_goRead(GO_TIME_SHIFT, GO_TIME_MASK) == 0) return;` (game-not-over short-circuit, idempotent); L198 `if (block.timestamp < _goRead(GO_TIME_SHIFT, GO_TIME_MASK) + 30 days) return;` (CLOCK-based gate — not tamperable by player/admin/validator/VRF oracle per 238 D-07 4-actor taxonomy: block.timestamp is validator-monotonic; GO_TIME is set atomically at L141 of handleGameOverDrain); L199 `if (_goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0) return;` (sweep idempotency); L201 sweep-bit latch; L202 `claimablePool = 0`; L207-209 `totalFunds = ethBal + stBal` (Game contract balance — does NOT include sDGNRS's pendingRedemptionEthValue which is held on the sDGNRS contract itself per SDR-04-V02 primary); L215 `_sendToVault(totalFunds, stBal)` — sweeps the Game contract's remaining balance into 33/33/34 split (SDGNRS/VAULT/GNRUS). 30-day window sufficiency per realistic-actor model: standard UX recovery period (user who loses wallet / doesn't notice gameover has 30 days to claim); window is CLOCK-based so no griefing vector; only stranded wei scenario is user-abandonment (intended forfeiture). Cross-cite v24.0 30-day-sweep spec (carried in PROJECT.md milestone history) + Phase 239/240 GO-240 rows as corroborating evidence per D-17. Critical observation per 245-01 SDR-04-V02: handleFinalSweep operates on the Game contract's balance, NOT sDGNRS's — sDGNRS's pendingRedemptionEthValue-reserved ETH lives on the sDGNRS contract and is reached via claimRedemption regardless of the Game contract's sweep. | 771893d1 |
| GOE-02-V03 | GOE-02 | Phase 239/240 GO-240-NNN rows (corroborating per D-17), v24.0 claimablePool 33/33/34 spec, v24.0 30-day sweep spec, Phase 244 GOX-03-V02 (post-refund subtraction primary) | Cross-cite to prior-milestone artifacts (READ-only, not re-derived here) | GOE-02a/b Phase 239/240 corroborating invariant re-derivation at HEAD | SAFE via corroboration | Phase 239 rngLockedFlag state-machine + Phase 240 GO-240-NNN VRF-available branch determinism proofs at their respective HEADs demonstrate the 33/33/34 split + 30-day sweep invariants. Phase 245 GOE-02-V01 + V02 re-derive the same invariants at cc68bfc7 from source primitives (not from prior artifacts) — the corroboration shortens the argument chain without weakening it per CONTEXT.md D-17 "never sole warrant" rule. Consistency confirmed: 771893d1 did not change `_sendToVault` body (split math unchanged); `handleFinalSweep` body unchanged except for the delegatecall wiring through `_handleGameOverPath`. GOX-03-V02 standalone cross-cite: the post-refund `postRefundReserved` subtraction at GameOverModule:155-157 is Phase 244 PRIMARY closure for the two-pass subtraction pattern — GOE-02 re-derives at HEAD cc68bfc7. | 771893d1 |

**Pre-Flag closure notes (§GOE-02):**

- Pre-Flag L2506 (GOE-02 claimablePool 33/33/34 + 30-day sweep against new drain flow — does `handleFinalSweep` strand reserved wei if claimRedemption is delayed?) → CLOSED via GOE-02-V01 (split input is post-subtraction `remaining`) + GOE-02-V02 (30-day window sufficient, sweep operates on Game balance NOT sDGNRS — no stranding; user-abandonment = intended forfeiture) + GOE-02-V03 (Phase 239/240 corroboration).

---

## §Reproduction Recipe — GOE bucket (Task 1 slice)

POSIX-portable commands (per CONTEXT.md D-22 carry from Phase 243/244):

```
# Sanity gates (run before every task)
git rev-parse cc68bfc7                                   # expect: cc68bfc70e76fb75ac6effbc2135aae978f96ff3
git diff --stat cc68bfc7..HEAD -- contracts/             # expect: empty (anchor clean)
git status --porcelain contracts/ test/                  # expect: empty (no source-tree writes)

# GOE-01 source reads (VRF grace + _gameOverEntropy + _getHistoricalRngFallback + _handleGameOverPath)
git show cc68bfc7:contracts/storage/DegenerusGameStorage.sol | sed -n '200,215p;1235,1243p'
git show cc68bfc7:contracts/modules/DegenerusGameAdvanceModule.sol | sed -n '519,633p;1228,1310p;1301,1345p'

# GOE-02 source reads (handleGameOverDrain + _sendToVault + handleFinalSweep)
git show cc68bfc7:contracts/modules/DegenerusGameGameOverModule.sol | sed -n '79,189p;196,216p;225,233p'

# KI envelope re-verify
grep -A 2 'EXC-03\|EXC-02\|Gameover prevrandao fallback\|Gameover RNG substitution' KNOWN-ISSUES.md
```

---

## §GOE-03 — Purchase-blocking entry-point coverage at current surface (full sweep beyond 244 GOX-01 8-path claim)

### §GOE-03 — External-function inventory (DegenerusGame.sol + 5 modules at HEAD cc68bfc7)

Per CONTEXT.md D-16 GOE-03a + GOE-03b: every externally-callable function in the Game contract + 5 modules is classified into one of three gate classes:

- **Class (i) — liveness-gated state-mutating purchase/claim path:** reverts when `_livenessTriggered()` or `gameOver` fires; cannot inject ETH for tickets post-liveness
- **Class (ii) — state-read-only view/pure function:** no state mutation; no ETH injection surface
- **Class (iii) — admin-only / protocol-internal mutation:** caller-restricted (onlyVault / onlyGame / onlyCoin / onlyCoinflip / onlyCoordinator / etc.); no player-controlled ETH injection path; either state-read-only in effect or operates on protocol-internal flows

Inventory table (external/public, non-view, non-pure functions in DegenerusGame + 5 modules at HEAD):

| External Function | File:Line | Gate Class | Gating Evidence | Phase 244 Cross-Cite |
| --- | --- | --- | --- | --- |
| advanceGame | DegenerusGame.sol:284 (dispatcher) → AdvanceModule:160 | (iii) protocol-internal (drives gameover itself; must be callable post-liveness so `_handleGameOverPath` fires) | AdvanceModule drives `_handleGameOverPath` which gates on `_livenessTriggered()` / `gameOver`; advanceGame is the gate CALLER, not gated | GOX-01/GOX-04/GOX-06 shared-context |
| recordMintQuestStreak | DegenerusGame.sol:389 | (iii) admin-only | L390 `if (msg.sender != ContractAddresses.GAME) revert E();` — caller-restricted to COIN/COINFLIP contracts; no player-path | — |
| setOperatorApproval | DegenerusGame.sol:435 | (iii) admin-only | Writes `operatorApprovals` mapping only; no ETH flow; address(0) guard at L437 | — |
| setLootboxRngThreshold | DegenerusGame.sol:479 | (iii) admin-only | Protocol admin mutation; no ETH flow | — |
| purchase | DegenerusGame.sol:501 → MintModule:purchase | (i) liveness-gated | `_purchaseFor` at MintModule:920 has `if (_livenessTriggered()) revert E();` | GOX-01-V01..V02 |
| purchaseCoin | DegenerusGame.sol:~566 → MintModule:870 | (i) liveness-gated | `_purchaseCoinFor` at MintModule:890 has `if (_livenessTriggered()) revert E();` | GOX-01-V03..V04 |
| purchaseBurnieLootbox | DegenerusGame.sol (dispatcher) → MintModule:_purchaseBurnieLootboxFor | (i) liveness-gated | `_purchaseBurnieLootboxFor` at MintModule:1392 has `if (_livenessTriggered()) revert E();` | GOX-01-V05 |
| purchaseWhaleBundle | DegenerusGame.sol → WhaleModule:_purchaseWhaleBundle | (i) liveness-gated | `_purchaseWhaleBundle` at WhaleModule:195 has `if (_livenessTriggered()) revert E();` | GOX-01-V06 |
| purchaseLazyPass | DegenerusGame.sol:624 → WhaleModule:_purchaseLazyPass | (i) liveness-gated | `_purchaseLazyPass` at WhaleModule:385 has `if (_livenessTriggered()) revert E();` | GOX-01-V07 |
| purchaseDeityPass | DegenerusGame.sol:644 → WhaleModule:_purchaseDeityPass | (i) liveness-gated | `_purchaseDeityPass` at WhaleModule:543 has `if (rngLockedFlag) revert RngLocked();` + `if (_livenessTriggered()) revert E();` | GOX-01-V08 |
| openLootBox | DegenerusGame.sol:665 → LootboxModule | (iii) protocol-internal | Opens queued lootboxes (pre-purchased RNG index); no ETH flow at open-time (ETH was paid at purchase under gated path) | — |
| openBurnieLootBox | DegenerusGame.sol:673 → LootboxModule | (iii) protocol-internal | Opens queued BURNIE lootboxes; no ETH flow (BURNIE was burned at purchase under gated path) | — |
| claimDecimatorJackpot | DegenerusGame.sol:1252 → DecimatorModule | (iii) protocol-internal (claim-only) | Claim-only; no ETH injection; operates on pre-resolved decimator round | — |
| claimTerminalDecimatorJackpot | DegenerusGame.sol:1268 → DecimatorModule | (iii) protocol-internal claim-only post-GAMEOVER | Per NatSpec: "Only callable post-GAMEOVER" — gated by construction | — |
| claimWinnings | DegenerusGame.sol:1387 → `_claimWinningsInternal` | (iii) protocol-internal | `_claimWinningsInternal` checks `if (_goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0) revert E();` — claim works in any state EXCEPT final-sweep-complete; no ETH injection | — |
| claimWinningsStethFirst | DegenerusGame.sol:1394 | (iii) admin-only (VAULT caller) | `if (msg.sender != ContractAddresses.VAULT) revert E();` + GO_SWEPT gate | — |
| claimAffiliateDgnrs | DegenerusGame.sol:1426 | (iii) protocol-internal claim-only | Claim-only; no ETH injection; mutates affiliate-claimed flag + issues DGNRS reward | — |
| setAutoRebuy | DegenerusGame.sol:1495 | (iii) player-config (rngLockedFlag gated) | `if (rngLockedFlag) revert RngLocked();` — no ETH flow; only toggles auto-rebuy flag | — |
| setAutoRebuyTakeProfit | DegenerusGame.sol:~1505 | (iii) player-config | No ETH flow; mutates takeProfit value only | — |
| deactivateAfKingFromCoin | DegenerusGame.sol:1641 | (iii) caller-restricted COINFLIP | `if (msg.sender != ContractAddresses.COINFLIP) revert E();` | — |
| claimWhalePass | DegenerusGame.sol:1692 → WhaleModule:957 | (i) liveness-gated | WhaleModule:958 has `if (_livenessTriggered()) revert E();` | GOX-01-V06 shared |
| adminStakeEthForStEth | DegenerusGame.sol:1826 | (iii) admin-only | `if (!vault.isVaultOwner(msg.sender)) revert E();` — vault-owner restricted; stakes ETH to Lido (no ticket flow) | — |
| requestLootboxRng | DegenerusGame.sol:1897 → AdvanceModule:1044 | (iii) protocol-internal | AdvanceModule:1044 checks `if (rngLockedFlag) revert RngLocked();` + day/RNG prerequisites; no ETH flow; requests VRF only | — |
| reverseFlip | DegenerusGame.sol:1914 | (iii) BURNIE-nudge (not ticket purchase) | `if (rngLockedFlag) revert RngLocked();` — burns BURNIE to nudge RNG word by +1; no ETH flow; operates only while RNG unlocked | — |
| processTicketBatch | MintModule:666 | (iii) protocol-internal | Invoked only via `delegatecall` from `_handleGameOverPath` at AdvanceModule:592-602 during gameover drain; no external player path | — |
| pickCharity | AdvanceModule:33 (interface ref) / Storage shared | (iii) protocol-internal (invoked during gameover resolution) | Driven by internal flow only | — |

### §GOE-03 — Standard verdict rows

| Verdict Row ID | REQ-ID | Source Row(s) | File:Line | Adversarial Vector | Verdict | Evidence | Owning Commit SHA |
| --- | --- | --- | --- | --- | --- | --- | --- |
| GOE-03-V01 | GOE-03 | D-243-C018..C025, D-243-F016..F023, D-243-I016, GOX-01-V01..V08 (Phase 244 PRIMARY 8-path closure) | contracts/modules/DegenerusGameMintModule.sol + DegenerusGameWhaleModule.sol (8-path subset) | GOE-03a 8-path player-facing purchase/claim paths (primary closure via 244) | SAFE via 244 cross-cite | Phase 244 GOX-01-V01..V08 RE_VERIFIED each of the 8 player-facing purchase paths has the `_livenessTriggered()` entry gate at HEAD cc68bfc7. The 8 paths are: `_purchaseFor` (MintModule:920), `_purchaseCoinFor` (MintModule:890), `_callTicketPurchase` (MintModule:1226 — defense-in-depth second gate), `_purchaseBurnieLootboxFor` (MintModule:1392), `_purchaseWhaleBundle` (WhaleModule:195), `_purchaseLazyPass` (WhaleModule:385), `_purchaseDeityPass` (WhaleModule:543 with rngLockedFlag pre-gate), `claimWhalePass` (WhaleModule:958). Each was verbatim verified at HEAD cc68bfc7 to open with `if (_livenessTriggered()) revert E();` (or equivalent). GOE-03-V01 SAFE via 244 cross-cite; GOE-03 floor severity depends on V02/V03 extending beyond the 8 paths. | 771893d1 |
| GOE-03-V02 | GOE-03 | Pre-Flag bullet L2509, D-243-C012 (livenessTriggered external view) | contracts/DegenerusGame.sol (full external-function inventory) + 5 modules | GOE-03b extended sweep: every external/public non-view function in DegenerusGame + 5 modules classified into gate-class (i/ii/iii) | SAFE | Inventory table above enumerates every external/public non-view function in DegenerusGame.sol (~25 entries) + all externally-callable module functions. Every function falls into one of three classes: (i) `_livenessTriggered()`-gated purchase/claim path — class-(i) entries cross-cite GOX-01-V01..V08 primary closure; (ii) view/pure — zero ETH flow, zero state mutation; (iii) admin-only / protocol-internal — caller-restricted (onlyGame/onlyCoin/onlyCoinflip/onlyCoordinator/onlyVault) or claim-only (post-resolve lookup) or internal (delegatecall-only, not externally reachable by player). Zero entry-point was found that (a) is player-facing, (b) mutates state to inject ETH for a ticket purchase, and (c) lacks a `_livenessTriggered()` or `gameOver` gate. No finding candidate emitted. | 771893d1 |
| GOE-03-V03 | GOE-03 | GOE-03-V02 extension, D-243-C012, CONTEXT.md D-16 GOE-03b | contracts/DegenerusGame.sol + modules | GOE-03b internal callees + admin entries: `_purchaseBurnieLootboxFor` internal callees + `_claim*` paths + admin-only entries | SAFE | Internal callees of `_purchaseCoinFor` (MintModule:885-911) have exactly one external entry: `purchaseCoin` at MintModule:870 — the L890 `_livenessTriggered()` gate is the sole gate and no bypass path exists (confirmed in GOE-05-V02 path-sweep). Similar pattern for `_purchaseBurnieLootboxFor` (single entry `purchaseBurnieLootbox`), `_purchaseWhaleBundle` (single entry `purchaseWhaleBundle`), `_purchaseLazyPass` (single entry `purchaseLazyPass`), `_purchaseDeityPass` (single entry `purchaseDeityPass`). `_claim*` paths (claimDecimatorJackpot / claimTerminalDecimatorJackpot / claimWinnings / claimAffiliateDgnrs / claimWhalePass) are class-(iii) protocol-internal — payout-only, no ETH injection vector. `claimWhalePass` is an edge case: it IS `_livenessTriggered()`-gated (WhaleModule:958) despite being a claim. Admin-only entries (`adminStakeEthForStEth` — vault-owner only; `recordMintQuestStreak` — COIN/COINFLIP caller only; `setAutoRebuy` / `setAutoRebuyTakeProfit` / `setLootboxRngThreshold` / `setOperatorApproval`) all either require privileged-caller enforcement OR are config-only (no ETH flow). | 771893d1 |

**Pre-Flag closure notes (§GOE-03):**

- Pre-Flag L2509 (GOE-03 entry-point sweep beyond 8 paths — `_purchaseBurnieLootboxFor` internal callees, `_claim*` paths, any admin-only entry with game-state mutation) → CLOSED via GOE-03-V01 (244 8-path primary cross-cite) + GOE-03-V02 (full external-function inventory classifies every function into class i/ii/iii) + GOE-03-V03 (internal callees + admin entries sub-sweep). Zero entry-point found that lacks gating AND can inject player ETH post-liveness.

---

## §GOE-04 — VRF-available vs prevrandao-fallback gameover-jackpot branches under new 14-day VRF-dead grace

### §GOE-04 — 4-dim matrix (day × level × VRF state × rngLockedFlag) at HEAD cc68bfc7

Per CONTEXT.md D-16 GOE-04a. The 4-dim matrix (day-range × level × VRF-state × rngLockedFlag) enumerates 96 cells; since level and rngLockedFlag are orthogonal to branch-selection (level affects coinflip-payout gating, rngLockedFlag is explicitly cleared before entering `_gameOverEntropy` since advanceGame requires rngLocked==false at entry), the effective matrix compresses to (day-range × VRF-state) = 4×4 = 16 cells. Branch selection at AdvanceModule:1237-1293 reads ONLY `rngWordCurrent` (L1236) + `rngRequestTime` (L1237, L1261) — level affects coinflip-payout (sub-feature) but not branch choice.

**Compressed 4×4 matrix (day-range × VRF-state):**

| Day Range | VRF-state: healthy | VRF-state: stalled < 14d | VRF-state: stalled ≥ 14d | VRF-state: intermittent |
| --- | --- | --- | --- | --- |
| day 1-14 (pre-threshold) | No gameOver (day-math unmet level-0: 365d; level ≥1: 120d); no branch fires | No grace (elapsed < 14d); liveness false; no branch fires | Grace fires liveness at L1242; gameOver latches per GOX-06-V02; `_gameOverEntropy` prevrandao-fallback L1263 fires (currentWord==0, rngRequestTime!=0, elapsed≥14d) — THE VRF-breaks-at-day-14 scenario | Partial VRF word arrival: IF `rngWordCurrent != 0` AT tick → VRF-available branch L1237 fires; ELSE prevrandao-fallback on grace. Mutual exclusion preserved |
| day 14-120 (level ≥1 threshold window) | Liveness false (day-math unmet for level≥1 at day<120; day math unmet for level 0 at day<365); no branch fires | No grace (elapsed < 14d); no liveness; no branch fires | Grace fires liveness; gameOver latches; prevrandao-fallback L1263 fires | Same as day 1-14 intermittent — VRF-available if word arrived, fallback otherwise |
| day 120-365 (level ≥1 post-threshold) | Liveness fires via day-math (level ≥1: `currentDay - psd > 120`); gameOver latches; VRF-available branch L1237 fires (rngWordCurrent != 0 under healthy) | Liveness fires via day-math (stall does NOT affect liveness since day-math already fires); `_gameOverEntropy` reads `rngWordCurrent`; if currentWord==0 AND rngRequestTime!=0 AND elapsed<grace → `revert RngNotReady()` at L1295 | Liveness fires via day-math OR grace (either suffices); branch selection at `_gameOverEntropy`: currentWord!=0 → VRF-available L1237; else prevrandao-fallback L1263 | Same — branch selection reads word-arrival state |
| day 365+ (level 0 post-threshold) | Liveness fires via day-math (level 0: `currentDay - psd > 365`); VRF-available branch fires (currentWord!=0) | Liveness fires via day-math; reads currentWord; `revert RngNotReady()` if currentWord==0 AND elapsed<grace | Liveness fires via day-math OR grace; branch per word state | Same |

**Branch disjointness (GOE-04 vector (b)):**

Reading AdvanceModule:1228-1306 at HEAD:

- L1236 `if (rngWordByDay[day] != 0) return rngWordByDay[day];` — idempotency, short-circuit if already resolved for this day
- L1237-1259 **VRF-available branch**: gate = `currentWord != 0 && rngRequestTime != 0`; reads `rngWordCurrent`; applies `_applyDailyRng`; resolves redemptions at L1256
- L1261 `if (rngRequestTime != 0) {` — enters fallback path
- L1262-1293 **Prevrandao-fallback branch**: inner gate = `elapsed >= GAMEOVER_RNG_FALLBACK_DELAY` (14 days); reads `_getHistoricalRngFallback(day)`; resolves redemptions at L1286; clears `rngRequestTime = 0` at L1292
- L1294-1295 `revert RngNotReady();` — fires when `rngRequestTime != 0` AND `elapsed < 14 days` AND currentWord==0 (pre-grace stall; callable by player/admin ONLY via advanceGame which reverts and liveness STILL fires via grace after elapsed≥14d → eventually resolves)
- L1297-1298 `if (_tryRequestRng(isTicketJackpotDay, lvl))` — cold-start VRF request (rngRequestTime==0)
- L1300-1302 `rngRequestTime = ts; return 0;` — VRF request failed; starts fallback timer

**Mutual exclusion proof:** Branch-A gate `(currentWord != 0 && rngRequestTime != 0)` and Branch-B gate `(rngRequestTime != 0 && elapsed >= 14d)` are mutually exclusive within a single tick iff the FIRST fires on `currentWord != 0` (VRF word arrived). If Branch-A fires, function returns at L1259; Branch-B never enters. If currentWord==0, Branch-A skipped (`currentWord != 0` false) → fall through to L1261 — Branch-B fires only if elapsed >= 14d. At most one branch fires per tick.

### §GOE-04 — Standard verdict rows (adversarial vectors GOE-04a + GOE-04b per CONTEXT.md D-16 + KI EXC-02 RE_VERIFIED per D-24)

| Verdict Row ID | REQ-ID | Source Row(s) | File:Line | Adversarial Vector | Verdict | Evidence | Owning Commit SHA |
| --- | --- | --- | --- | --- | --- | --- | --- |
| GOE-04-V01 | GOE-04 | D-243-C026, D-243-C028, D-243-I019, GOX-04-V01 (Phase 244 PRIMARY _livenessTriggered body closure) | contracts/storage/DegenerusGameStorage.sol:1241-1242 | GOE-04a 4-dim matrix Tier-1 grace × day-math intersection at every cell | SAFE | Compressed 4×4 matrix above enumerates all (day-range × VRF-state) cells. `_livenessTriggered()` body at Storage:1236-1243 has three OR-clauses: (i) `lvl == 0 && currentDay - psd > 365`; (ii) `lvl != 0 && currentDay - psd > 120`; (iii) `rngStart != 0 && block.timestamp - rngStart >= 14 days`. Tier-1 (iii) fires on VRF stall regardless of day-math; tier-i/ii fire on day-math regardless of VRF. OR semantics = any single trigger fires liveness. Per-cell verdict consistent with commit intent: grace adds an ALTERNATIVE liveness-fire TRIGGER, not a new prevrandao-consumption site. | 771893d1 |
| GOE-04-V02 | GOE-04 | D-243-C016, GOX-04-V02 (Phase 244 PRIMARY EXC-02 envelope RE_VERIFIED), EXC-02 (KNOWN-ISSUES.md L29) | contracts/modules/DegenerusGameAdvanceModule.sol:1237-1293 + :1301 (`_getHistoricalRngFallback`) | GOE-04a VRF-available vs prevrandao-fallback branch disjointness at new 14-day grace | RE_VERIFIED_AT_HEAD cc68bfc7 | Branches mutually exclusive per the proof above: Branch-A (L1237-1259) returns at L1259 before Branch-B (L1262-1293) gate check at L1261. Prevrandao consumption site is SOLE AND UNCHANGED at HEAD: `_getHistoricalRngFallback` at AdvanceModule:1301-1345 (body verified at HEAD via `git show cc68bfc7:...`) — hashes up to 5 historical VRF words keccak'd with `currentDay` and `block.prevrandao`. EXC-02 4-criterion envelope (14-day ~17× VRF-swap-governance threshold / bounded-trigger gating / VRF-derived bulk entropy / 1-bit validator manipulation on binary outcomes) RE_VERIFIED at HEAD cc68bfc7. 771893d1 added the Tier-1 grace AS A NEW LIVENESS TRIGGER but did NOT add a new prevrandao site (the prevrandao admixture was already `GAMEOVER_RNG_FALLBACK_DELAY = 14 days` at baseline; the Tier-1 grace at Storage:1242 is the SAME 14-day threshold applied to liveness-fire logic — it does NOT duplicate or widen the prevrandao-reach). | 771893d1 |
| GOE-04-V03 | GOE-04 | Pre-Flag bullet L2512, D-243-C026, GOX-06-V02 (_handleGameOverPath ordering shared-context), GOX-05-V01 (day-math-first shared-context) | contracts/modules/DegenerusGameAdvanceModule.sol:519-633 + :1228-1306 + contracts/storage/DegenerusGameStorage.sol:1235-1243 | GOE-04b DEEPER stall-tail: multi-level transitions where VRF comes back partially | SAFE | Stall-tail scenarios: (1) VRF-breaks-at-day-14 at level 0 (day<365): per GOX-06-V02 gameOver-before-liveness ordering at `_handleGameOverPath` L540-551, `if (gameOver) → handleFinalSweep` check runs BEFORE `if (!_livenessTriggered()) return;` — ensures post-gameover final-sweep stays reachable even when day-math is below threshold. Tier-1 grace fires liveness at elapsed≥14d → `_gameOverEntropy` prevrandao-fallback branch L1263 fires → gameOver latches at GameOverModule:141 via delegatecall L625. (2) Multi-level transitions with partial VRF recovery: if VRF recovers at day 13 (elapsed<14d, no grace) during a level 5 game at day 100 (<120 threshold for level ≥1), liveness NEVER fires, game continues normally. If VRF recovers at day 13 during a level 5 game at day 121 (>120 threshold), liveness fires via day-math (iii clause), VRF-available branch fires (currentWord!=0). (3) VRF intermittent with level transition: the `_gameOverEntropy` branch is evaluated per-day, not per-level — level change at day-boundary does not bifurcate the branch. (4) `revert RngNotReady()` at L1295 prevents grace-tail bypass: if elapsed<14d AND currentWord==0 AND rngRequestTime!=0, function reverts — advanceGame retries next tick, liveness persists, eventually grace threshold crosses. NO stall-tail configuration bypasses EXC-02 envelope. 771893d1 Tier-1 grace preserves the same 14-day admixture bound as baseline `GAMEOVER_RNG_FALLBACK_DELAY` (they are the SAME NUMERIC threshold applied to two coordinated decision points: liveness-fire AND prevrandao-admixture). | 771893d1 |

**Pre-Flag closure notes (§GOE-04):**

- Pre-Flag L2512 (GOE-04 deeper stall-tail enumeration — VRF-breaks-at-day-14 + multi-level transitions where VRF comes back partially) → CLOSED via GOE-04-V01 (4-dim matrix covers every (day × VRF) cell) + GOE-04-V02 (branch disjointness + EXC-02 envelope RE_VERIFIED) + GOE-04-V03 (multi-level stall-tail scenarios enumerated — no bypass).

---

## §GOE-05 — gameOverPossible BURNIE endgame gate (v11.0) across all new liveness paths

### §GOE-05 — Standard verdict rows (vector GOE-05a per CONTEXT.md D-16)

**Body read at HEAD cc68bfc7 — `_purchaseCoinFor` at MintModule:885-911:**

```
L885: function _purchaseCoinFor(address buyer, uint256 ticketQuantity, uint256 lootBoxBurnieAmount) private {
L890:     if (_livenessTriggered()) revert E();                          // 771893d1 NEW (was `if (gameOver) revert` at baseline per GOX-01-V03 primary)
L892:     if (ticketQuantity != 0) {
L893:         // ENF-01: Block BURNIE tickets when drip projection cannot cover nextPool deficit.
L894:         if (gameOverPossible) revert GameOverPossible();           // v11.0 UNCHANGED
L895:         _callTicketPurchase(buyer, msg.sender, ticketQuantity, MintPaymentKind.DirectEth, true, bytes32(0), 0, level, jackpotPhaseFlag);
L906:     }
L908:     if (lootBoxBurnieAmount != 0) {
L909:         _purchaseBurnieLootboxFor(buyer, lootBoxBurnieAmount);
L910:     }
L911: }
```

Ordering: L890 fires BEFORE L894. State classification:

- **State-0 (pre-liveness, no gameOverPossible):** L890 passes (livenessTriggered==false); L894 passes (gameOverPossible==false); ticket purchase flows to `_callTicketPurchase` at L895 (which has defense-in-depth liveness re-check at MintModule:1226 per GOX-01-V03 primary)
- **State-0 with gameOverPossible latched:** L890 passes; L894 reverts `GameOverPossible()` — BURNIE tickets correctly blocked per v11.0 spec
- **State-1 (liveness fired, gameOver not yet):** L890 reverts E() — caller rejected BEFORE reaching L894; BURNIE gate redundant but NOT bypassed (rejection fires one step earlier)
- **State-2 (gameOver latched):** L890 reverts E() (liveness is implied by gameOver per GOX-06-V02 ordering); same rejection

**Caller enumeration for `_purchaseCoinFor` (grep results):**

Only caller: `purchaseCoin` at MintModule:870 — external entry. No internal caller. Rep:

```
grep -n '_purchaseCoinFor(' contracts/modules/DegenerusGameMintModule.sol
```

HEAD output (verified at Task 2 start): L870 `_purchaseCoinFor(buyer, ticketQuantity, lootBoxBurnieAmount);` + L885 function definition. No third reference. Single entry — single gate at L890 is sufficient.

### §GOE-05 — Standard verdict rows

| Verdict Row ID | REQ-ID | Source Row(s) | File:Line | Adversarial Vector | Verdict | Evidence | Owning Commit SHA |
| --- | --- | --- | --- | --- | --- | --- | --- |
| GOE-05-V01 | GOE-05 | D-243-C018, D-243-F016, D-243-I020, Pre-Flag bullet L2515, GOX-01-V03 (Phase 244 PRIMARY _purchaseCoinFor gate), v11.0 BURNIE endgame gate spec | contracts/modules/DegenerusGameMintModule.sol:885-911 | GOE-05a L890 `_livenessTriggered()` fires BEFORE L894 `gameOverPossible` ordering preserved | SAFE | Body trace verified at HEAD: L890 is the FIRST statement in `_purchaseCoinFor` after the function header; L894 is reached ONLY if ticketQuantity != 0 AND L890 passed (state is pre-liveness). State-1 caller rejected at L890 (BurnsBlocked... equivalent revert via `revert E()`) before reaching L894. State-2 caller also rejected at L890 (livenessTriggered is TRUE whenever gameOver is TRUE per GOX-06-V02 gameOver-before-liveness ordering in `_handleGameOverPath` L540 — gameOver flag is always set AFTER liveness flag in Storage:1235-1243 predicate lifecycle). State-0 caller with gameOverPossible==true: L890 passes (livenessTriggered==false), L894 reverts — BURNIE endgame gate fires correctly. v11.0 gate effectiveness preserved under 771893d1 liveness-shift. | 771893d1 |
| GOE-05-V02 | GOE-05 | GOE-05-V01 extension, Phase 244 GOX-01-V03 | contracts/modules/DegenerusGameMintModule.sol (full file grep for `_purchaseCoinFor(`) | GOE-05a path-sweep for `_purchaseCoinFor` callers — no bypass path | SAFE | Grep `_purchaseCoinFor(` in contracts/modules/DegenerusGameMintModule.sol at HEAD cc68bfc7 returns exactly 2 hits: L870 (single external caller `purchaseCoin`) + L885 (function definition). Zero internal callers. Zero bypass route to `_purchaseCoinFor` that skips the L890 gate. Consequently the v11.0 BURNIE gate at L894 is unreachable in State-1 and State-2 (rejection at L890 fires first), and fires correctly in State-0 when `gameOverPossible == true`. | 771893d1 |

**Pre-Flag closure notes (§GOE-05):**

- Pre-Flag L2515 (GOE-05 gameOverPossible BURNIE gate — is ordering correct? Could a State-1 caller bypass gameOverPossible because they're already rejected at L890?) → CLOSED via GOE-05-V01 (ordering verified; State-1 rejection at L890 is STRICTER than the v11.0 BURNIE-gate-alone rejection at L894; v11.0 gate effectiveness preserved for State-0 callers with gameOverPossible==true) + GOE-05-V02 (path-sweep: single caller `purchaseCoin` at L870; no bypass route).

---

## §Reproduction Recipe — GOE bucket (Task 2 slice)

```
# GOE-03 external function inventory
git show cc68bfc7:contracts/DegenerusGame.sol | grep -nE '^[[:space:]]*function [a-zA-Z_]+\([^)]*\)[[:space:]]+(external|public)'
git show cc68bfc7:contracts/modules/DegenerusGameMintModule.sol | grep -nE '^[[:space:]]*function [a-zA-Z_]+\([^)]*\)[[:space:]]+(external|public)'
git show cc68bfc7:contracts/modules/DegenerusGameWhaleModule.sol | grep -nE '^[[:space:]]*function [a-zA-Z_]+\([^)]*\)[[:space:]]+(external|public)'
git show cc68bfc7:contracts/modules/DegenerusGameAdvanceModule.sol | grep -nE '^[[:space:]]*function [a-zA-Z_]+\([^)]*\)[[:space:]]+(external|public)'

# GOE-03 gate-class evidence (liveness gates + admin gates)
for fn in _purchaseFor _purchaseCoinFor _callTicketPurchase _purchaseBurnieLootboxFor _purchaseWhaleBundle _purchaseLazyPass _purchaseDeityPass claimWhalePass; do
  git show cc68bfc7:contracts/modules/DegenerusGameMintModule.sol | grep -A3 "function $fn\b" 2>/dev/null
  git show cc68bfc7:contracts/modules/DegenerusGameWhaleModule.sol | grep -A3 "function $fn\b" 2>/dev/null
done

# GOE-04 branch disjointness at _gameOverEntropy + Tier-1 grace predicate
git show cc68bfc7:contracts/modules/DegenerusGameAdvanceModule.sol | sed -n '1228,1310p'
git show cc68bfc7:contracts/storage/DegenerusGameStorage.sol | sed -n '1235,1243p'
git show cc68bfc7:contracts/modules/DegenerusGameAdvanceModule.sol | sed -n '1301,1345p'

# GOE-05 _purchaseCoinFor ordering + caller sweep
git show cc68bfc7:contracts/modules/DegenerusGameMintModule.sol | sed -n '885,912p'
git show cc68bfc7:contracts/modules/DegenerusGameMintModule.sol | grep -n '_purchaseCoinFor('
```

---

## §GOE-06 — NEW cross-feature emergent behavior from liveness × sDGNRS × drain interaction (2 Pre-Flag candidate closures per CONTEXT.md D-12)

### §GOE-06 Candidate 1 — cc68bfc7 BAF skipped-pool preservation in futurePool × handleGameOverDrain subtraction

**Body trace at HEAD cc68bfc7:**

cc68bfc7 added the BAF-skipped code path at AdvanceModule:826-840 inside `_consolidatePoolsAndRewardJackpots`:

```
L826: if (prevMod10 == 0) {
L827:     if ((rngWord & 1) == 1) {
L828:         uint256 bafPct = prevMod100 == 0 ? 20 : (lvl == 50 ? 20 : 10);
L829:         uint256 bafPoolWei = (baseMemFuture * bafPct) / 100;
L830:         uint256 claimed = IDegenerusGame(address(this)).runBafJackpot(bafPoolWei, lvl, rngWord);
L831:         memFuture -= claimed;
L832:         claimableDelta += claimed;
L833:     } else {
L834:         jackpots.markBafSkipped(lvl);
L835:     }
L836: }
```

And `markBafSkipped` at DegenerusJackpots.sol:498-510 (cc68bfc7 NEW):

```
L506: function markBafSkipped(uint24 lvl) external onlyGame {
L507:     uint32 today = degenerusGame.currentDayView();
L508:     lastBafResolvedDay = today;
L509:     emit BafSkipped(lvl, today);
L510: }
```

**Key observation:** On the skip branch (L833-835), `markBafSkipped` mutates ONLY `lastBafResolvedDay` + emits `BafSkipped` event. Zero ETH movement. Zero `memFuture` mutation. The BAF pool that WOULD have been distributed (`bafPoolWei = (baseMemFuture * bafPct) / 100`) is never subtracted from `memFuture` on the skip branch — `memFuture` retains its full value. At the end of `_consolidatePoolsAndRewardJackpots` the call `_setPrizePools(uint128(memNext), uint128(memFuture))` at AdvanceModule:~883 stores the (un-decremented) `memFuture` back to storage. The skipped-BAF pool remains in the `futurePool` accounting variable — and the corresponding ETH remains on the Game contract's address balance (no transfer occurred, so no physical ETH moved).

**Drain subtraction interaction at gameover:**

handleGameOverDrain at GameOverModule:79-189 reads the Game contract's physical balance at L86-88:

```
L86: uint256 ethBal = address(this).balance;
L87: uint256 stBal = steth.balanceOf(address(this));
L88: uint256 totalFunds = ethBal + stBal;
```

`totalFunds` is the TOTAL physical ETH + stETH held by the Game contract — this captures EVERY wei on the contract, regardless of which accounting bucket (claimablePool / nextPool / futurePool / currentPool / yieldAccumulator / etc.) logically owns it. The skipped-BAF pool wei IS part of `totalFunds` because the physical ETH was never moved.

L94-95 computes `reserved = claimablePool + pendingRedemptionEthValue()` then `preRefundAvailable = totalFunds - reserved`. L150 zeros futurePool via `_setFuturePrizePool(0)` — but this is an ACCOUNTING zero, not a physical transfer. The `totalFunds` variable captured at L88 is unchanged by this zeroing (locally stored); split computation at L158 still operates on the full `totalFunds - postRefundReserved`. The 33/33/34 split at `_sendToVault(remaining, stBal)` L186 distributes `remaining` (derived from `available` = `totalFunds - postRefundReserved`, post-terminal-decimator subtraction).

**Conservation: skipped-BAF wei is NOT stranded.** It is captured in `totalFunds` at L88, subject to the `claimablePool + pendingRedemptionEthValue` reserved-subtraction, and the remainder flows through terminal-decimator + terminal-jackpot + 33/33/34 split. Physical ETH conservation holds: every wei on the Game contract at drain time is accounted for by (reserved pay-claim-later) OR (split into SDGNRS/VAULT/GNRUS).

### §GOE-06 Candidate 1 — Verdict rows

| Verdict Row ID | REQ-ID | Source Row(s) | File:Line | Adversarial Vector | Verdict | Evidence | Owning Commit SHA |
| --- | --- | --- | --- | --- | --- | --- | --- |
| GOE-06-V01 | GOE-06 | D-243-C035 (BafSkipped event), D-243-C036 (markBafSkipped function), D-243-C037 (interface), D-243-C039 (`_consolidatePoolsAndRewardJackpots` MODIFIED_LOGIC), D-243-F025, D-243-F026, Pre-Flag bullet L2518, GOX-06-V03 (Phase 244 cc68bfc7 jackpots direct-handle reentrancy parity adjacent primary), EVT-02/EVT-03 bit-0 BAF-coupling shared-context | contracts/DegenerusJackpots.sol:498-510 (`markBafSkipped`) + contracts/modules/DegenerusGameAdvanceModule.sol:826-840 (BAF gate) + contracts/modules/DegenerusGameGameOverModule.sol:79-189 (handleGameOverDrain) | GOE-06a cc68bfc7 BAF skipped-pool preservation in futurePool × handleGameOverDrain subtraction — does the skipped-BAF pool get correctly swept by drain, or stranded? | SAFE | Body trace above establishes: (1) `markBafSkipped` mutates only `lastBafResolvedDay` + emits event — zero ETH movement. (2) On BAF-skip branch (L833-835), `memFuture` is NOT decremented — the skipped-BAF pool wei remains in the accounting `futurePool` AND the corresponding physical ETH remains on the Game contract. (3) At gameover, `handleGameOverDrain` reads `totalFunds = ethBal + stBal` at L86-88 — this captures the full physical balance INCLUDING the skipped-BAF pool wei (physical ETH was never moved off the contract). (4) L150 `_setFuturePrizePool(0)` zeros the accounting variable but does NOT affect the already-captured `totalFunds` local. (5) 33/33/34 split at `_sendToVault` L186 operates on `remaining` = post-subtraction `available`, which was computed from `totalFunds` that included the skipped-BAF wei. Conclusion: skipped-BAF pool is swept correctly via `totalFunds`, never stranded. Per-wei conservation: every wei on Game contract at drain-time = reserved (claimablePool payout) + pendingRedemptionEthValue (sDGNRS reserve) + split (SDGNRS 33% / VAULT 33% / GNRUS 34%) — no stranding possible. | cc68bfc7 |

**Pre-Flag closure notes (§GOE-06 Candidate 1):**

- Pre-Flag L2518 (GOE-06 candidate 1 — cc68bfc7 BAF skipped-pool × drain interaction: does the skipped-BAF pool in futurePool get correctly swept by `handleGameOverDrain`, or is it stranded?) → CLOSED via GOE-06-V01 (SAFE — skipped-BAF wei captured in `totalFunds` at L86-88 of handleGameOverDrain; physical ETH never moved off Game contract on skip path; swept via 33/33/34 split).

### §GOE-06 Candidate 2 — burnWrapped divergence × DGNRS wrapper ↔ sDGNRS wrapper-held backing conservation across State-0/1/2

**Body trace at HEAD cc68bfc7 — `burnWrapped` at sDGNRS:506-516:**

```
L506: function burnWrapped(uint256 amount) external returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {
L507:     if (game.livenessTriggered() && !game.gameOver()) revert BurnsBlockedDuringLiveness();
L508:     dgnrsWrapper.burnForSdgnrs(msg.sender, amount);
L509:     if (game.gameOver()) {
L510:         (ethOut, stethOut) = _deterministicBurnFrom(msg.sender, ContractAddresses.DGNRS, amount);
L511:         return (ethOut, stethOut, 0);
L512:     }
L513:     if (game.rngLocked()) revert BurnsBlockedDuringRng();
L514:     _submitGamblingClaimFrom(msg.sender, ContractAddresses.DGNRS, amount);
L515:     return (0, 0, 0);
L516: }
```

**DGNRS wrapper's `burnForSdgnrs` at DegenerusStonk.sol:349-363 (onlyCallableBy sDGNRS):**

```
L349: function burnForSdgnrs(address player, uint256 amount) external {
L350:     if (msg.sender != ContractAddresses.SDGNRS) revert Unauthorized();
L351:     uint256 bal = balanceOf[player];
L352:     if (amount == 0 || amount > bal) revert Insufficient();
L353:     unchecked {
L354:         balanceOf[player] = bal - amount;
L355:         totalSupply -= amount;
L356:     }
L357:     emit Transfer(player, address(0), amount);
L358: }
```

**Storage-key separation proof:**

The sDGNRS contract tracks two distinct buckets on its own `balanceOf` mapping:
- `balanceOf[address(this)]` — pool-side sDGNRS (cleared by `burnAtGameOver` at sDGNRS:462-471)
- `balanceOf[ContractAddresses.DGNRS]` — wrapper-backing sDGNRS (held for DGNRS wrapper supply)

`burnAtGameOver` at sDGNRS:462 burns ONLY `balanceOf[address(this)]` — the pool tokens. The wrapper-backing at `balanceOf[ContractAddresses.DGNRS]` is NOT touched. This is verified at HEAD:

```
git show cc68bfc7:contracts/StakedDegenerusStonk.sol | sed -n '462,471p'
# L462: function burnAtGameOver() external onlyGame {
# L463:     uint256 bal = balanceOf[address(this)];       // SELF balance only
# L464:     if (bal == 0) return;
# L465:     unchecked {
# L466:         balanceOf[address(this)] = 0;             // SELF zero
# L467:         totalSupply -= bal;
# L468:     }
# L469:     delete poolBalances;
# L470:     emit Transfer(address(this), address(0), bal);
# L471: }
```

**Per-state conservation analysis:**

- **State-0 (pre-liveness, pre-gameover):** Player calls `burnWrapped` → L507 passes (liveness==false) → L508 `burnForSdgnrs` decrements `DegenerusStonk.balanceOf[player]` + `DegenerusStonk.totalSupply` (wrapper-side burn) → L509 gameOver==false → L513 rngLocked check → L514 `_submitGamblingClaimFrom(msg.sender, ContractAddresses.DGNRS, amount)` — enters the 2-step gambling-burn redemption flow (pendingRedemptionEthValue += ethValueOwed; resolve later via VRF; claim via `claimRedemption`). Balance-side: DGNRS wrapper supply decreases by `amount`; sDGNRS `balanceOf[ContractAddresses.DGNRS]` unchanged at this moment (decreased later in `_submitGamblingClaimFrom` body sDGNRS:752-814). Conservation: DGNRS wrapper supply TRACKS sDGNRS wrapper-backing.

- **State-1 (liveness fired, gameOver not yet):** Player calls `burnWrapped` → L507 REVERTS with `BurnsBlockedDuringLiveness`. No state mutation. Player retains DGNRS wrapper tokens; sDGNRS wrapper-backing unchanged. Conservation invariant preserved by non-mutation. The load-bearing purpose of L507: during State-1, the player's deterministic-burn payout would be computed from a snapshot that doesn't reflect terminal drain state yet (pool balances mid-draining), so blocking the path avoids a payout window mismatch. Post-gameover, the payout operates on the settled drain state.

- **State-2 (gameOver latched):** Player calls `burnWrapped` → L507 passes (gameOver==true, so `livenessTriggered() && !gameOver()` is false) → L508 `burnForSdgnrs` decrements DGNRS wrapper balance + supply → L509 gameOver==true → L510 `_deterministicBurnFrom(msg.sender, ContractAddresses.DGNRS, amount)` fires: sDGNRS:535 body loads `burnFrom = ContractAddresses.DGNRS`; L536 reads `bal = balanceOf[burnFrom]` (= wrapper-backing sDGNRS held by DegenerusStonk contract); L540-541 burns `bal - amount` from `balanceOf[ContractAddresses.DGNRS]` + decrements `totalSupply`. Conservation: DGNRS wrapper supply decreased by `amount` via `burnForSdgnrs`; sDGNRS wrapper-backing decreased by `amount` via `_deterministicBurnFrom`. Matched pair. `_deterministicBurnFrom` computes `totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue` at sDGNRS:533-535 — exclusion of `pendingRedemptionEthValue` ensures State-1/State-2 pending gambling burners still receive their reserved wei via `claimRedemption`.

**Gameover-drain interaction with wrapper-backing:**

`dgnrs.burnAtGameOver()` at GameOverModule:146 (per Storage:146-147 `dgnrs` is typed as `IStakedDegenerusStonk` and points to `ContractAddresses.SDGNRS`) calls sDGNRS:462 `burnAtGameOver()`. This burns ONLY `balanceOf[address(this)]` (pool tokens). The wrapper-backing at `balanceOf[ContractAddresses.DGNRS]` is preserved. Therefore, post-gameover burnWrapped at L510 finds the wrapper-backing intact and can pay out from the backing.

Post-handleFinalSweep (day+30): `ethBal + stethBal` on sDGNRS contract has been reduced (handleFinalSweep at GameOverModule:196-216 operates on Game contract balance, NOT sDGNRS — but SDGNRS received 33% share during handleGameOverDrain, and retains its own pre-existing ETH pool from prior pools/redemptions). The `totalMoney` formula `ethBal + stethBal + claimableEth - pendingRedemptionEthValue` yields whatever remains at burn time. If the sDGNRS contract is drained to near-zero by the time of post-day+30 burnWrapped, the player gets proportional-zero payout — which is the intended forfeiture behavior consistent with missing the effective claim window (same rationale as SDR-04 user-abandonment forfeiture).

### §GOE-06 Candidate 2 — Verdict rows

| Verdict Row ID | REQ-ID | Source Row(s) | File:Line | Adversarial Vector | Verdict | Evidence | Owning Commit SHA |
| --- | --- | --- | --- | --- | --- | --- | --- |
| GOE-06-V02 | GOE-06 | D-243-C013, D-243-C014, D-243-F011, D-243-F012, D-243-I017, Pre-Flag bullet L2519, Phase 244 GOX-02-V02 (burnWrapped State-1 divergence adjacent shared-context) | contracts/StakedDegenerusStonk.sol:506-516 (`burnWrapped`) + :462-471 (`burnAtGameOver`) + :519-569 (`_deterministicBurnFrom`) + contracts/DegenerusStonk.sol:349-363 (`burnForSdgnrs`) + contracts/modules/DegenerusGameGameOverModule.sol:146 (`dgnrs.burnAtGameOver()` wire-up via Storage:146-147) | GOE-06b burnWrapped divergence × DGNRS wrapper ↔ sDGNRS wrapper-held backing conservation across State-0/1/2 | SAFE | Per-state conservation analysis above establishes: (1) Storage-key separation — `balanceOf[address(this)]` (pool) and `balanceOf[ContractAddresses.DGNRS]` (wrapper-backing) are distinct keys; `burnAtGameOver` burns only pool key. (2) State-0 matched pair via `burnForSdgnrs` (DGNRS wrapper supply decrement) + `_submitGamblingClaimFrom` (sDGNRS wrapper-backing decrement on later resolve). (3) State-1 revert at L507 preserves invariant via non-mutation. (4) State-2 matched pair via `burnForSdgnrs` (DGNRS wrapper decrement) + `_deterministicBurnFrom` with `burnFrom = ContractAddresses.DGNRS` (sDGNRS wrapper-backing decrement). (5) `burnAtGameOver` storage-key separation preserves wrapper-backing through gameover drain. (6) `_deterministicBurnFrom` `totalMoney - pendingRedemptionEthValue` exclusion ensures pending gambling burners retain claimRedemption reach. Conservation invariant `DGNRS.totalSupply == sDGNRS.balanceOf[ContractAddresses.DGNRS]` preserved across all 3 states. Post-day+30 forfeiture is intended behavior (same rationale as SDR-04). | 771893d1 |

**Pre-Flag closure notes (§GOE-06 Candidate 2):**

- Pre-Flag L2519 (GOE-06 candidate 2 — burnWrapped divergence `livenessTriggered() && !gameOver()`; does DGNRS wrapper ↔ sDGNRS wrapper-held backing conservation hold across State-0/1/2 transitions?) → CLOSED via GOE-06-V02 (SAFE — storage-key separation preserves wrapper-backing through `burnAtGameOver`; matched burn-pair invariant across all 3 states; `_deterministicBurnFrom` pendingRedemptionEthValue exclusion prevents wrapper payouts from draining pending-redemption reserves).

### §GOE-06 — REQ-level aggregate verdict per CONTEXT.md D-13

**GOE-06 floor severity = max(GOE-06-V01, GOE-06-V02) = max(SAFE, SAFE) = SAFE.**

Both Pre-Flag candidates close SAFE. Per CONTEXT.md D-12/D-13:
- **No in-place sweep expansion required** (neither candidate escalated to MEDIUM+).
- **Exhaustive negative-space sweep DEFERRED** per CONTEXT.md D-12 Deferred Ideas carry — if a Phase 246 reviewer finds GOE-06 under-sampled, the exhaustive sweep can be added as a future-milestone candidate without reopening Phase 245.

---

## §Reproduction Recipe — GOE bucket (Task 3 slice)

```
# GOE-06 Candidate 1 source reads (BAF skipped-pool + drain interaction)
git show cc68bfc7:contracts/modules/DegenerusGameAdvanceModule.sol | sed -n '820,840p;875,905p'
git show cc68bfc7:contracts/DegenerusJackpots.sol | sed -n '495,515p'
git show cc68bfc7:contracts/modules/DegenerusGameGameOverModule.sol | sed -n '79,189p'

# GOE-06 Candidate 2 source reads (burnWrapped + wrapper-backing conservation)
git show cc68bfc7:contracts/StakedDegenerusStonk.sol | sed -n '460,470p;500,515p;519,570p'
git show cc68bfc7:contracts/DegenerusStonk.sol | sed -n '345,365p'
git show cc68bfc7:contracts/storage/DegenerusGameStorage.sol | sed -n '143,150p'  # dgnrs = sDGNRS wire-up
git show cc68bfc7:contracts/modules/DegenerusGameGameOverModule.sol | sed -n '140,150p'  # burnAtGameOver call site

# D-13 aggregate verdict sanity (both candidates SAFE = no sweep expansion)
grep -c 'GOE-06-V0[12] | GOE-06' audit/v31-245-GOE.md                  # expect: 2 (Candidate 1 + Candidate 2)
grep -E 'Verdict.*SAFE|SAFE$|SAFE \|' audit/v31-245-GOE.md | wc -l     # sanity spot-check on SAFE tally
```


## §3 — Consumer Index (REQ-ID → Phase 245 verdict-row mapping + cross-ref to Phase 243 D-243 rows + Phase 244 V-rows + prior-milestone artifacts per CONTEXT.md D-17)

| REQ-ID | Phase 245 Verdict Rows | Source 243 Consumer Index Row | Phase 244 V-row Cross-Cite | Prior-Milestone Corroborating Artifacts | Owning Plan |
| --- | --- | --- | --- | --- | --- |
| SDR-01 | SDR-01-T{a-f} (6 foundation) + SDR-01-V01..V03 | D-243-I017 (burn/burnWrapped), D-243-I019 (liveness-trigger) | GOX-01-V01..V08 (entry-gate shift, shared-context) + GOX-04-V01/V02 (liveness predicates, shared-context) + GOX-06-V02 (`_handleGameOverPath` ordering, shared-context) + GOX-02-V01/V02/V03 (burn/burnWrapped State-1 revert, shared-context) | Phase 238 Freeze-Proof Subset (timing-matrix corroboration per D-17) | 245-01 |
| SDR-02 | SDR-02-V01..V04 | D-243-I017, D-243-I018 | GOX-03-V01 (handleGameOverDrain subtraction primary) | v24.0 claimablePool spec | 245-01 |
| SDR-03 | SDR-03-V01..V03 | D-243-I018 | GOX-03-V01/V02/V03 (primary closure — pre-refund + post-refund + multi-tx edges) | v24.0 33/33/34 split spec | 245-01 |
| SDR-04 | SDR-04-V01..V04 | D-243-I017, D-243-I019 | GOX-01-V01..V08 (entry-point coverage), GOX-03-V03 (reentrancy-safety) | Phase 238 4-actor taxonomy (D-07) | 245-01 |
| SDR-05 | SDR-05-V01..V06 (one per timing) | D-243-I018 | GOX-03-V01/V02 (subtraction arithmetic) | v24.0 claimablePool spec | 245-01 |
| SDR-06 | SDR-06-V01..V07 | D-243-I017 | GOX-02-V01/V02/V03 (PRIMARY State-1 revert coverage — enumerated 3 burn-caller reach-paths) | v29.0 Phase 235 burn-path walk | 245-01 |
| SDR-07 | SDR-07-V01..V06 | D-243-I017 (sDGNRS supply mutation coverage) | (none direct — 245 re-derives) | v29.0 Phase 235 + v24.0 supply-conservation (corroborating) | 245-01 |
| SDR-08 | SDR-08-V01..V04 (V01 RE_VERIFIED_AT_HEAD carrier) | D-243-I021 (gameover-entropy coverage) | RNG-01-V11 (PRIMARY EXC-03 envelope non-widening at `_unlockRng` scope), GOX-06-V01 (rngRequestTime clearing adjacent), GOX-06-V02 (gameOver-before-liveness ordering) | v29.0 Phase 232.1 F-29-04 commitment-window trace + KI EXC-03 | 245-01 |
| GOE-01 | GOE-01-V01..V02 (V01 RE_VERIFIED_AT_HEAD carrier) | D-243-I019, D-243-I021 | RNG-01-V11 (PRIMARY EXC-03 envelope) + GOX-06-V02 (ordering shared-context) + GOX-04-V02 (EXC-02 shared-context) | v29.0 Phase 232.1 F-29-04 + KI EXC-03; 245-01 SDR-08-V01 cross-file | 245-02 |
| GOE-02 | GOE-02-V01..V03 | D-243-I018 | GOX-03-V01/V02 (PRIMARY handleGameOverDrain subtraction) + GOX-03-V03 (multi-tx drain edges) | v24.0 33/33/34 split + 30-day sweep; Phase 239/240 GO-240 rows | 245-02 |
| GOE-03 | GOE-03-V01..V03 | D-243-I016 (GOX-01 coverage) | GOX-01-V01..V08 (PRIMARY 8-path entry-gate) | v24.0 10-entry-point claim (updated to current surface per D-16 GOE-03a) | 245-02 |
| GOE-04 | GOE-04-V01..V03 (V02 RE_VERIFIED_AT_HEAD carrier) | D-243-I019 | GOX-04-V01/V02 (PRIMARY EXC-02 RE_VERIFIED_AT_HEAD + `_livenessTriggered` body) + GOX-05-V01 (day-math-first) + GOX-06-V02 (`_handleGameOverPath` ordering) | Phase 239 rngLockedFlag + Phase 240 GO-240 rows + KI EXC-02 | 245-02 |
| GOE-05 | GOE-05-V01..V02 | D-243-I020 (GOX-05 coverage) | GOX-01-V03 (PRIMARY `_purchaseCoinFor` gate) | v11.0 BURNIE endgame gate spec | 245-02 |
| GOE-06 | GOE-06-V01..V02 (Candidate 1 + Candidate 2) | D-243-I016..I021 (cross-cutting) | GOX-06-V03 (cc68bfc7 BAF reentrancy parity adjacent) + GOX-02-V02 (burnWrapped divergence adjacent) + EVT-02/EVT-03 (bit-0 BAF-coupling adjacent) | v24.0 + v29.0 wrapper-backing conservation spec | 245-02 |

---

## §4 — Reproduction Recipe Appendix (POSIX-portable per CONTEXT.md D-22 carry from Phase 243/244)

### §4.1 — Phase-wide sanity gates (run before every task start)

```
# Anchor verification
git rev-parse cc68bfc7                                   # expect: cc68bfc70e76fb75ac6effbc2135aae978f96ff3
git rev-parse 7ab515fe                                   # baseline: 7ab515fe2d936fb3bc42cf5abddd4d9ed11ddb49
git diff --stat cc68bfc7..HEAD -- contracts/             # expect: empty (anchor clean — zero source-tree drift)

# Read-only scope verification
git status --porcelain contracts/ test/                  # expect: empty (D-20)
git status --porcelain audit/v31-243-DELTA-SURFACE.md audit/v31-244-PER-COMMIT-AUDIT.md   # expect: empty (D-22)

# F-31-NN absence verification (D-23)
! grep -qE 'F-31-[0-9]' audit/v31-245-SDR-GOE.md
! grep -qE 'F-31-[0-9]' audit/v31-245-SDR.md
! grep -qE 'F-31-[0-9]' audit/v31-245-GOE.md
```

### §4.2 — SDR bucket reproduction recipe (from audit/v31-245-SDR.md §Reproduction Recipe section)

Commands actually used during Task 1 execution (POSIX-portable, shell-safe).

```sh
# Sanity gate (§Step A per plan)
git rev-parse 7ab515fe
git rev-parse cc68bfc7
git rev-parse HEAD
git diff --stat cc68bfc7..HEAD -- contracts/
git status --porcelain contracts/ test/

# Locate all resolveRedemptionPeriod call sites
grep -rn 'resolveRedemptionPeriod' contracts/

# Locate all pendingRedemption* mutations in sDGNRS
grep -n 'pendingRedemption' contracts/StakedDegenerusStonk.sol

# Locate GO_JACKPOT_PAID writer sites (prove L148 is the sole writer)
grep -n 'GO_JACKPOT_PAID' contracts/modules/DegenerusGameGameOverModule.sol

# Locate _VRF_GRACE_PERIOD constant
grep -n '_VRF_GRACE_PERIOD' contracts/storage/DegenerusGameStorage.sol

# Locate burn callers
grep -n '\.burn(' contracts/DegenerusStonk.sol contracts/DegenerusVault.sol

# Show core functions (verbatim per plan read_first)
sed -n '486,516p' contracts/StakedDegenerusStonk.sol     # burn + burnWrapped
sed -n '527,569p' contracts/StakedDegenerusStonk.sol     # _deterministicBurnFrom
sed -n '585,610p' contracts/StakedDegenerusStonk.sol     # resolveRedemptionPeriod
sed -n '618,684p' contracts/StakedDegenerusStonk.sol     # claimRedemption
sed -n '752,814p' contracts/StakedDegenerusStonk.sol     # _submitGamblingClaimFrom
sed -n '79,189p'  contracts/modules/DegenerusGameGameOverModule.sol     # handleGameOverDrain
sed -n '225,233p' contracts/modules/DegenerusGameGameOverModule.sol     # _sendToVault
sed -n '1148,1214p' contracts/modules/DegenerusGameAdvanceModule.sol    # rngGate + L1193 resolveRedemptionPeriod
sed -n '1228,1306p' contracts/modules/DegenerusGameAdvanceModule.sol    # _gameOverEntropy + L1256 VRF-available + L1286 fallback
sed -n '1235,1243p' contracts/storage/DegenerusGameStorage.sol          # _livenessTriggered predicate
sed -n '88,90p'     contracts/interfaces/IStakedDegenerusStonk.sol      # pendingRedemptionEthValue interface

# Verify zero source-tree drift vs anchor
git diff cc68bfc7..HEAD -- contracts/ | wc -l
```

### Task 2 commands (SDR-04 + SDR-05 + SDR-06)

```sh
# Sanity gate (re-verify at Task 2 start)
git rev-parse cc68bfc7
git diff --stat cc68bfc7..HEAD -- contracts/
git status --porcelain contracts/ test/

# SDR-04 reads
sed -n '618,684p' contracts/StakedDegenerusStonk.sol     # claimRedemption body (L657 decrement, L683 _payEth)
sed -n '817,839p' contracts/StakedDegenerusStonk.sol     # _payEth fallback to stETH
sed -n '196,216p' contracts/modules/DegenerusGameGameOverModule.sol   # handleFinalSweep 30-day gate
sed -n '225,233p' contracts/modules/DegenerusGameGameOverModule.sol   # _sendToVault 33/33/34 split

# SDR-05 per-timing worked wei ledger (reproduce ledger math from storage variable semantics)
sed -n '221,227p' contracts/StakedDegenerusStonk.sol     # PendingRedemption + RedemptionPeriod struct layouts + pending storage

# SDR-06 negative-space sweep
grep -rn 'purchaseStartDay' contracts/                    # Zero admin write paths — only constructor + advanceGame internals
grep -n 'livenessTriggered\|gameOver\|rngLocked' contracts/modules/DegenerusGameMintModule.sol | head -10  # Liveness gates in MintModule
grep -rn 'import\|bridge\|crosschain\|layerzero\|wormhole' contracts/ | grep -v '^contracts/interfaces\|\.sol:.*//' | head  # Cross-chain vector — zero results
sed -n '289,323p' contracts/StakedDegenerusStonk.sol     # constructor body (claimWhalePass + setAfKingMode; no burn path)
sed -n '344,360p' contracts/DegenerusStonk.sol           # burnForSdgnrs body (protocol-internal, non-reentrant)
sed -n '325,340p' contracts/modules/DegenerusGameAdvanceModule.sol    # Level transition psd write at L330
sed -n '1160,1180p' contracts/modules/DegenerusGameAdvanceModule.sol  # Gap-backfill psd += gapCount at L1174
```

### Task 3 commands (SDR-07 + SDR-08 + KI EXC-03 envelope re-verify)

```sh
# Sanity gate (re-verify at Task 3 start)
git rev-parse cc68bfc7
git diff --stat cc68bfc7..HEAD -- contracts/
git status --porcelain contracts/ test/

# SDR-07 supply mutation enumeration
grep -n '_mint(' contracts/StakedDegenerusStonk.sol                                  # Constructor + declaration
grep -n 'totalSupply\b' contracts/StakedDegenerusStonk.sol                           # All supply write sites
sed -n '289,323p' contracts/StakedDegenerusStonk.sol                                 # Constructor body
sed -n '412,435p' contracts/StakedDegenerusStonk.sol                                 # transferFromPool (with self-win edge at L425-428)
sed -n '443,458p' contracts/StakedDegenerusStonk.sol                                 # transferBetweenPools
sed -n '462,471p' contracts/StakedDegenerusStonk.sol                                 # burnAtGameOver
sed -n '527,569p' contracts/StakedDegenerusStonk.sol                                 # _deterministicBurnFrom (L539-540 burn)
sed -n '752,814p' contracts/StakedDegenerusStonk.sol                                 # _submitGamblingClaimFrom (L783-784 burn)
sed -n '337,347p' contracts/StakedDegenerusStonk.sol                                 # wrapperTransferTo (balance-only)
sed -n '874,881p' contracts/StakedDegenerusStonk.sol                                 # _mint internal implementation

# SDR-08 _gameOverEntropy branch analysis
sed -n '1228,1306p' contracts/modules/DegenerusGameAdvanceModule.sol                 # Full _gameOverEntropy body
grep -n '_gameOverEntropy\b' contracts/modules/DegenerusGameAdvanceModule.sol        # Sole caller at L560 of _handleGameOverPath
sed -n '200,204p' contracts/storage/DegenerusGameStorage.sol                         # _VRF_GRACE_PERIOD constant = 14 days
sed -n '1235,1243p' contracts/storage/DegenerusGameStorage.sol                       # _livenessTriggered predicate

# KI EXC-03 envelope re-verify inputs
grep -n 'EXC-03\|F-29-04' KNOWN-ISSUES.md                                            # Acceptance rationale
grep -n 'RNG-01-V11' audit/v31-244-PER-COMMIT-AUDIT.md                               # Phase 244 primary non-widening proof

# Commitment-window analysis (per feedback_rng_commitment_window.md skill)
sed -n '577,583p' contracts/StakedDegenerusStonk.sol                                 # hasPendingRedemptions view
sed -n '486,516p' contracts/StakedDegenerusStonk.sol                                 # burn + burnWrapped (L491/L507 State-1 block closes commitment window)
```

### §4.3 — GOE bucket reproduction recipe (concatenated from audit/v31-245-GOE.md §Reproduction Recipe slices)

**(Task 1 slice)**

POSIX-portable commands (per CONTEXT.md D-22 carry from Phase 243/244):

```
# Sanity gates (run before every task)
git rev-parse cc68bfc7                                   # expect: cc68bfc70e76fb75ac6effbc2135aae978f96ff3
git diff --stat cc68bfc7..HEAD -- contracts/             # expect: empty (anchor clean)
git status --porcelain contracts/ test/                  # expect: empty (no source-tree writes)

# GOE-01 source reads (VRF grace + _gameOverEntropy + _getHistoricalRngFallback + _handleGameOverPath)
git show cc68bfc7:contracts/storage/DegenerusGameStorage.sol | sed -n '200,215p;1235,1243p'
git show cc68bfc7:contracts/modules/DegenerusGameAdvanceModule.sol | sed -n '519,633p;1228,1310p;1301,1345p'

# GOE-02 source reads (handleGameOverDrain + _sendToVault + handleFinalSweep)
git show cc68bfc7:contracts/modules/DegenerusGameGameOverModule.sol | sed -n '79,189p;196,216p;225,233p'

# KI envelope re-verify
grep -A 2 'EXC-03\|EXC-02\|Gameover prevrandao fallback\|Gameover RNG substitution' KNOWN-ISSUES.md
```

---

**(Task 2 slice)**

```
# GOE-03 external function inventory
git show cc68bfc7:contracts/DegenerusGame.sol | grep -nE '^[[:space:]]*function [a-zA-Z_]+\([^)]*\)[[:space:]]+(external|public)'
git show cc68bfc7:contracts/modules/DegenerusGameMintModule.sol | grep -nE '^[[:space:]]*function [a-zA-Z_]+\([^)]*\)[[:space:]]+(external|public)'
git show cc68bfc7:contracts/modules/DegenerusGameWhaleModule.sol | grep -nE '^[[:space:]]*function [a-zA-Z_]+\([^)]*\)[[:space:]]+(external|public)'
git show cc68bfc7:contracts/modules/DegenerusGameAdvanceModule.sol | grep -nE '^[[:space:]]*function [a-zA-Z_]+\([^)]*\)[[:space:]]+(external|public)'

# GOE-03 gate-class evidence (liveness gates + admin gates)
for fn in _purchaseFor _purchaseCoinFor _callTicketPurchase _purchaseBurnieLootboxFor _purchaseWhaleBundle _purchaseLazyPass _purchaseDeityPass claimWhalePass; do
  git show cc68bfc7:contracts/modules/DegenerusGameMintModule.sol | grep -A3 "function $fn\b" 2>/dev/null
  git show cc68bfc7:contracts/modules/DegenerusGameWhaleModule.sol | grep -A3 "function $fn\b" 2>/dev/null
done

# GOE-04 branch disjointness at _gameOverEntropy + Tier-1 grace predicate
git show cc68bfc7:contracts/modules/DegenerusGameAdvanceModule.sol | sed -n '1228,1310p'
git show cc68bfc7:contracts/storage/DegenerusGameStorage.sol | sed -n '1235,1243p'
git show cc68bfc7:contracts/modules/DegenerusGameAdvanceModule.sol | sed -n '1301,1345p'

# GOE-05 _purchaseCoinFor ordering + caller sweep
git show cc68bfc7:contracts/modules/DegenerusGameMintModule.sol | sed -n '885,912p'
git show cc68bfc7:contracts/modules/DegenerusGameMintModule.sol | grep -n '_purchaseCoinFor('
```

---

**(Task 3 slice)**

```
# GOE-06 Candidate 1 source reads (BAF skipped-pool + drain interaction)
git show cc68bfc7:contracts/modules/DegenerusGameAdvanceModule.sol | sed -n '820,840p;875,905p'
git show cc68bfc7:contracts/DegenerusJackpots.sol | sed -n '495,515p'
git show cc68bfc7:contracts/modules/DegenerusGameGameOverModule.sol | sed -n '79,189p'

# GOE-06 Candidate 2 source reads (burnWrapped + wrapper-backing conservation)
git show cc68bfc7:contracts/StakedDegenerusStonk.sol | sed -n '460,470p;500,515p;519,570p'
git show cc68bfc7:contracts/DegenerusStonk.sol | sed -n '345,365p'
git show cc68bfc7:contracts/storage/DegenerusGameStorage.sol | sed -n '143,150p'  # dgnrs = sDGNRS wire-up
git show cc68bfc7:contracts/modules/DegenerusGameGameOverModule.sol | sed -n '140,150p'  # burnAtGameOver call site

# D-13 aggregate verdict sanity (both candidates SAFE = no sweep expansion)
grep -c 'GOE-06-V0[12] | GOE-06' audit/v31-245-GOE.md                  # expect: 2 (Candidate 1 + Candidate 2)
grep -E 'Verdict.*SAFE|SAFE$|SAFE \|' audit/v31-245-GOE.md | wc -l     # sanity spot-check on SAFE tally
```

### §4.4 — Per-REQ coverage gate verification

```
# Every REQ has at least one verdict-row prefix
for req in SDR-01 SDR-02 SDR-03 SDR-04 SDR-05 SDR-06 SDR-07 SDR-08 GOE-01 GOE-02 GOE-03 GOE-04 GOE-05 GOE-06; do
  count=$(grep -cE "^\| $req-V[0-9]+ |^\| $req-T[a-f] " audit/v31-245-SDR-GOE.md)
  echo "$req verdict rows: $count"
  [ "$count" -ge 1 ] || echo "FAIL: $req has zero verdict rows"
done

# Phase-244 Pre-Flag bullet-closure gate (17 bullets across SDR + GOE)
for line in 2477 2478 2481 2482 2485 2488 2491 2494 2497 2500 2503 2506 2509 2512 2515 2518 2519; do
  grep -q "L$line" audit/v31-245-SDR-GOE.md || echo "FAIL: Pre-Flag L$line closure note missing"
done
```

---

## §5 — Phase 246 Input Subsection (per CONTEXT.md D-18)

**Zero finding candidates emitted during Phase 245** (all 14 REQs closed SAFE floor severity; SDR-08 + GOE-01 KI envelope rows closed `RE_VERIFIED_AT_HEAD cc68bfc7` for EXC-03; GOE-04 KI envelope row closed `RE_VERIFIED_AT_HEAD cc68bfc7` for EXC-02).

Consequences for Phase 246:

- **Phase 246 FIND-01 pool from Phase 245 is empty.** FIND-01 assigns `F-31-NN` IDs only to finding candidates; Phase 245 surfaced none.
- **FIND-02 has no candidates to reclassify.** Severity reclassification applies to finding candidates pre-classified by Phase 245; none emitted.
- **FIND-03 KI delta is zero.** KI envelopes re-verified at HEAD cc68bfc7 without widening: EXC-02 (SDR-08-V01 carrier + GOE-04-V02 carrier) and EXC-03 (SDR-08-V01 carrier + GOE-01-V01 carrier). No new exception added; no existing exception reclassified.
- **REG-01 regression coverage for Phase 245** is limited to the 6-timing SDR-01 matrix (Ta..Tf) + GOE-06 2-candidate closure as spot-check anchors per CONTEXT.md Deferred carry. These serve as regression-appendix inputs for any future patch that mutates handleGameOverDrain / `_gameOverEntropy` / burnWrapped / markBafSkipped / `_purchaseCoinFor`.

Zero-state format per CONTEXT.md D-18 second sentence:

> Zero finding candidates emitted — Phase 246 FIND-01 pool from Phase 245 is empty; FIND-02 has no candidates to reclassify; FIND-03 KI delta is zero.
