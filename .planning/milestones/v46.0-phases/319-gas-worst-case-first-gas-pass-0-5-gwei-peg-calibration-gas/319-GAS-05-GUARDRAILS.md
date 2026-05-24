# Phase 319 — GAS-05 Security-Floor Guardrail Audit (Scavenger → Skeptic → contract-auditor)

**Authored:** 2026-05-24
**Contract HEAD:** `8d23f736` (contracts/ clean; every cited `file:line` source-verified this session against `contracts/`)
**Methodology rules (HARD floors):**
- `feedback_security_over_gas` — security / RNG-non-manipulability is a hard floor; NO gas optimization may weaken an invariant. The G1-G13 guards below are the floor — the audit CONFIRMS each is preserved and treats any removal/packing candidate that touches a guard as auto-rejected by the Skeptic unless the contract-auditor produces an invariant-preserving proof.
- `feedback_gas_worst_case` — paper-first (the worst-case derivation lives in `319-GAS-DERIVATION.md`; this doc is the security-floor half of the same pass).

**Skill chain (gas-audit coordinator):** `gas-scavenger` (intentionally reckless removal-candidate finder) → `gas-skeptic` (validates approve/reject/escalate against the G1-G13 hard-reject set) → `contract-auditor` (invariant proof for any candidate that touches a G-row). All three are local, read-only source-analysis agents; no package installs (RESEARCH §Package Legitimacy Audit = N/A).

---

## CRITICAL CORRECTION — optimizer is `runs=200`, NOT the SKILL.md `runs=2`

The `gas-scavenger` SKILL.md hard-codes "Optimizer runs: 2" and "With runs=2, bytecode size matters enormously." **That is stale.** The production compile path is:

| Toolchain | Setting | Source |
|-----------|---------|--------|
| Foundry (the measurement + production-equivalent path) | `optimizer_runs = 200`, `viaIR = true`, `solc 0.8.34`, `evm_version = paris` | `foundry.toml:10` [VERIFIED this session] |
| Hardhat (secondary legacy path) | `runs: 50`, `viaIR: true` | `hardhat.config.js:43` (RESEARCH §Standard Stack) |

**Consequence applied throughout this audit:** at `runs=200` the viaIR optimizer favors RUNTIME gas (SLOAD/SSTORE/CALL weight) over deployment/bytecode size far more than the skill's `runs=2` framing assumes. Therefore:
- A removal candidate justified PURELY by "saves deployment bytecode" carries LOW weight (the runs=200 optimizer is not size-first).
- A candidate is weighted by its RUNTIME effect — cold/warm SLOAD elimination, SSTORE avoidance, CALL-depth reduction.
- A candidate that the optimizer already performs (e.g. hoisting a `pure` call of compile-time constants out of a loop) is a **no-op** at runs=200 — the source edit changes nothing in the emitted bytecode, so "ship it" yields zero measured saving (T-319-13: mis-weighting from the stale runs=2 lens would wrongly "approve" such an edit as a saving).

This correction is the disposition lens for every candidate below.

---

## Scope of the Scavenger pass

Source regions fed to the Scavenger (the v46 do-work crank + AfKing sweep + the touched module resolve/open paths), all read in full this session:

- `contracts/DegenerusGame.sol:1490-1749` — crank region: `crankBets` (:1543), `crankBoxes` (:1592), `_crankResolveBet`/`_crankOpenBox` onlySelf wrappers (:1640/:1661), `batchPurchase` (:1687) + `_batchPurchaseUnit` (:1729), `_ethToBurnieValue` (:1743), the `boxCursor`/`boxCursorIndex` cursor pair (:1507/:1510), `enqueueBoxForCrank` (:1526), the peg constants (:1495/:1501/:1502).
- `contracts/AfKing.sol:516-749` — `sweep` per-player loop (the funding waterfall, two-tier skip-kill, swap-pop, the single batched `batchPurchase` + single `creditFlip` epilogue), the `Sub` struct (:80-88), the `BOUNTY_ETH_TARGET`/`SUB_COST_ETH_TARGET` immutables (:246/:252).
- `contracts/modules/DegenerusGameDegeneretteModule.sol:553-801,1117` — `resolveBets` → `_resolveFullTicketBet` spin loop (`MAX_SPINS_PER_BET = 10`, :226), the RngNotReady freeze guard (:578), the one-reward delete (:580), `_distributePayout` (:705), 2-arg `_addClaimableEth` (:1117).
- `contracts/modules/DegenerusGameLootboxModule.sol:477-655,917-1031` — `resolveLootboxDirect` (:628), `_resolveLootboxCommon` (:917) + nested BoonModule delegatecall (:992) + `_queueTickets` SSTORE, the open-time box-zeroing (`lootboxEth`/`lootboxEthBase = 0`, :530-531), the RngNotReady guards (:485/:567).

---

## G1-G13 Security-Floor Reject Set (the deliverable's spine)

This is the HARD-REJECT list handed to the Skeptic: any Scavenger candidate that touches one of these rows is auto-escalated to the contract-auditor for an invariant proof BEFORE it may be approved, and is rejected outright if the proof does not hold (`feedback_security_over_gas`). Each guard is `VERIFIED-PRESENT at HEAD 8d23f736` (re-grepped this session — the same byte-present strings the Task-1 `CrankLeversAndPacking.t.sol::testG1ThroughG13GuardsBytePresent` suite pins, so a future regression that deletes a guard flips that suite RED).

| # | Guard | `file:line` | Why it is load-bearing | Proving 318 test | Status |
|---|-------|-------------|------------------------|------------------|--------|
| G1 | `RngNotReady` resolve guard (bet) + placement mirror | `DegenerusGameDegeneretteModule.sol:578` (`if (rngWord == 0) revert RngNotReady();`); placement-side mirror `:452` (`if (lootboxRngWordByIndex[index] != 0) revert RngNotReady();`) | RNG-freeze: a bet may only RESOLVE post-VRF-unlock; placement stays gated to word==0. Removing it would let a resolution read a stale/known word (RNG manipulation) | 318-05 RngFreezeAndRemovalProofs 13/13 | VERIFIED-PRESENT |
| G2 | `RngNotReady` open-box guard / orphan-index skip | `DegenerusGame.sol:1603` (`if (lootboxRngWordByIndex[index] == 0) return;`) + LootboxModule open guard `:485`/`:567` | Same freeze + the v45 VRF-rotation orphan-index landmine: an index orphaned mid-day is skipped until the re-issued word lands. Removing it re-opens the 0-entropy-trait / forced-game-over vector | 318-05 | VERIFIED-PRESENT |
| G3 | one-reward-per-item: bet delete | `DegenerusGameDegeneretteModule.sol:580` (`delete degeneretteBets[player][betId];`) | A resolved bet zeroes its slot — a re-crank finds 0 and the item-0 probe (G5) short-circuits; no double reward / double payout | 318-02 SAFE-01 | VERIFIED-PRESENT |
| G4 | one-reward-per-item: box zeroing | `DegenerusGameLootboxModule.sol:531` (`lootboxEthBase[index][player] = 0;`, with `lootboxEth` zeroed `:530`) + `crankBoxes:1618` already-opened skip (`if (lootboxEthBase[index][player] == 0) continue;`) | Open zeroes the first-deposit signal; the re-walk skips the emptied box — no double open / double reward | 318-02 | VERIFIED-PRESENT |
| G5 | double-crank short-circuit (bets) | `DegenerusGame.sol:1552` (`if (degeneretteBets[players[0]][betIds[0]] == 0) revert BatchAlreadyTaken();`) | Loser-gas cap — a competitor-got-ahead caller reverts at item 0, reusing the SLOAD the item needs anyway; bounds wasted gas on a lost race | 318-02 | VERIFIED-PRESENT |
| G6 | `batchPurchase` per-player try/catch + slice-refund | `DegenerusGame.sol:1704-1711` (`try this._batchPurchaseUnit{value: slice}(...) {} catch {}`) + one refund `:1717-1721` | Non-brick: one reverting player is skipped and its slice is NOT consumed (stays in the contract, refunded once after the loop); the batch completes for the rest | 318-03 SAFE-02 (CrankNonBrick 12/12) | VERIFIED-PRESENT |
| G7 | crank per-item try/catch + `onlySelf` isolation | `crankBets:1562` / `crankBoxes:1620` (`try this._crankResolveBet/_crankOpenBox(...) {} catch {}`) + `onlySelf` guards `:1641`/`:1662` (`if (msg.sender != address(this)) revert E();`) | Non-brick: a stale/reverting/not-ready item skips; reward accrues only on success. `onlySelf` keeps the relaxed-approval resolve path callable only from the Game's own frame | 318-03 | VERIFIED-PRESENT |
| G8 | `burnForKeeper` all-or-nothing | `AfKing.sol:587-600` (`burnForKeeper` → `if (burned != extractCost) { ... auto-pause ... }`) — impl is `onlyAfKing` in `BurnieCoin` | The day-31 extract charge is all-or-nothing; a partial burn cannot leave a half-paid window (partial-burn faucet closed, SUB-08/PROTO-02) | 318-03 | VERIFIED-PRESENT |
| G9 | keeper / address gating | `batchPurchase:1692` (`if (msg.sender != ContractAddresses.AF_KING) revert E();`); `_batchPurchaseUnit:1733` / `_crankResolveBet:1641` / `_crankOpenBox:1662` onlySelf; `isOperatorApproved` sweep gate `AfKing.sol:610` | Authority surface — only the pinned keeper / the Game's own self-call / an operator-approved sub may transact. The OPEN-C CEI reentrancy proof depends on the AF_KING gate (the VAULT recipient cannot pass it) | 318-03 + 316-SPEC OPEN-C | VERIFIED-PRESENT |
| G10 | swap-pop / no-`++cursor` cursor integrity | `AfKing.sol:594-599` and `:683-688` (`_removeFromSet(player);` then `continue;` WITHOUT `++cursor` — the swapped-in occupant at this slot MUST be processed this sweep) | Tombstone-on-cancel must not skip the swapped-in entry (no missed sub, no dead-slot buildup). The deliberate cursor non-advance is load-bearing | 318-04 SAFE-03 (AfKingConcurrency 10/10) | VERIFIED-PRESENT |
| G11 | bounded tombstone / cursor self-partition | `AfKing.sol:532` (`cursor = _sweepDay == today ? uint256(_sweepCursor) : 0;`) + per-entry `lastSweptDay` (`:567` skip, `:711` day-stamp) | Same-day concurrent sweeps self-partition by the persisted cursor; the per-entry `lastSweptDay` is the idempotency backstop. Iteration is `maxCount`-bounded (anti-DoS) | 318-04 | VERIFIED-PRESENT |
| G12 | WWXRP zero reward | `crankBets:1564` (`if (currency == 3) { /* zero reward */ } else { reward += ... }`), currency decoded at `:1560` | Faucet lock — WWXRP is the most +EV currency, so it is excluded from the bounty (the work still resolves; only the reward is zeroed). Removing the gate opens a WWXRP self-crank faucet (CRANK-04) | 318-02 | VERIFIED-PRESENT |
| G13 | rngLocked / gameOver batch pre-check | `batchPurchase:1693-1694` (`if (rngLockedFlag) revert RngLocked();` + `if (gameOver) revert E();`); `AfKing.sol:523` sweep (`if (...rngLocked()) revert SweepAborted(msg.sender, 1);`) | Whole-batch abort BEFORE any work — clean, no partial state. RNG-locked or game-over operations are blocked at entry | 318-03 | VERIFIED-PRESENT |

**GAS-04 packing floor (not a guard, but a Scavenger MUST-NOT):** the `Sub` struct (`AfKing.sol:80-88`) uses 13 of 32 bytes (`uint8 + bool + bool + uint32 + uint32 + uint8 + uint8`) with 19 free padding bytes — it is ALREADY a single slot at minimum field widths. There is NO tighter packing available; the Scavenger MUST NOT propose widening any field (a widening would either spill to a second slot or be a no-op). `feedback_maximal_variable_packing` is already satisfied. Pinned by `CrankLeversAndPacking.t.sol::testGas04PackingAndNoNewHotPathStorageSourcePresence` (byte-width sum == 13 <= 32).

---

## Scavenger candidates + Skeptic dispositions + contract-auditor escalations

The Scavenger was run over the scope above with the runs=200 lens. Every candidate it surfaced is recorded below with its Skeptic disposition; any candidate touching a G-row carries a contract-auditor verdict.

### SCAV-319-01 — GAS-02 loop-invariant hoist (the OPTIONAL candidate; surfaced, NOT shipped here)

- **Location:** `crankBets:1567-1570` and `crankBoxes:1621-1623`.
- **Candidate (Scavenger):** the per-successful-item reward `reward += _ethToBurnieValue(CRANK_*_GAS_UNITS * CRANK_GAS_PRICE_REF, PriceLookupLib.priceForLevel(lvl))` recomputes `_ethToBurnieValue(...)` and `PriceLookupLib.priceForLevel(lvl)` on EVERY iteration. ALL inputs are loop-invariant: `lvl` is read once before the loop (`uint24 lvl = _activeTicketLevel();`, :1555/:1610), and `CRANK_*_GAS_UNITS` / `CRANK_GAS_PRICE_REF` are compile-time `constant`s. Hoist: compute `uint256 perItem = _ethToBurnieValue(CONST * CONST, priceForLevel(lvl));` ONCE before the loop, then `reward += perItem` (bets) / multiply by `opened` (boxes).
- **G-row touched:** NONE. This is a pure arithmetic-recomputation hoist; it does not touch any guard. (It is adjacent to G12 — the `else` branch of the `currency == 3` fork in `crankBets` — but it does not alter the WWXRP zero-reward gate; the hoisted `perItem` is simply NOT added when `currency == 3`.)
- **Skeptic disposition: APPROVE-IF-REAL-SAVING / NO-OP-IF-ALREADY-HOISTED.** The edit is behavior-identical (a pure recomputation of loop-invariants — `_ethToBurnieValue` is `private pure`, `priceForLevel` is a `pure` library lookup of a constant `lvl`). The reward math, the per-item reward value, and the G12 WWXRP exclusion are all unchanged. BUT: at viaIR `runs=200` the optimizer MAY already hoist the two pure calls of loop-invariant arguments out of the loop (common-subexpression elimination across iterations), in which case the source edit yields ZERO measured saving (a no-op). The runs=2 lens would have wrongly counted it as a bytecode saving (T-319-13); under the corrected runs=200 lens its weight is "measure before/after — ship only if a real runtime saving is observed."
- **Verdict / handoff:** SURFACED for Plan 05. **Ship IF and only IF Plan 02's before/after measurement shows a real saving; NO-OP if the optimizer already hoists it.** If it ships it is a `DegenerusGame.sol` edit and therefore batches into Plan 05's single USER-APPROVED diff (per `feedback_batch_contract_approval` + `feedback_never_preapprove_contracts`). **NOT edited in this plan** (Plan 04 makes zero `contracts/*.sol` mutation). The 318-02 `CrankFaucetResistance` reward-correctness + round-trip-≤0 tests must stay green at the hoisted value (they will — the value is byte-identical).

### SCAV-319-02 — empty `if (currency == 3) { /* zero reward */ }` then-branch (crankBets:1564)

- **Location:** `crankBets:1564-1571`.
- **Candidate (Scavenger):** the `if (currency == 3) { /* zero reward */ } else { reward += ... }` has an EMPTY then-branch; "invert to `if (currency != 3) { reward += ... }` and drop the empty branch to save bytecode."
- **G-row touched: G12 (WWXRP zero reward).** Auto-escalated to contract-auditor.
- **contract-auditor verdict:** the empty-then / non-empty-else and the inverted `if (currency != 3)` are SEMANTICALLY IDENTICAL — both add the reward exactly when `currency != 3` and zero it when `currency == 3`. The invariant (WWXRP earns zero bounty, CRANK-04) is preserved either way. HOWEVER: (a) at runs=200 the optimizer already elides the empty branch — the inversion yields ZERO runtime saving and only a trivial source-bytecode delta that the optimizer normalizes; (b) the explicit `if (currency == 3) { /* zero reward */ }` form is the DOCUMENTED lever (the `// zero reward` comment is the human-legible CRANK-04 anchor that the auditor + the Task-1 grep gate key on). Rewriting it would weaken the audit-traceability of a security-floor guard for no measured gain.
- **Skeptic disposition: REJECT (cosmetic, no runtime saving, weakens a documented guard's legibility).** `feedback_security_over_gas` + `feedback_no_history_in_comments` posture: keep the explicit zero-reward branch. Not shipped.

### SCAV-319-03 — `betPacked` SLOAD used only for the currency decode (crankBets:1557-1560)

- **Location:** `crankBets:1557` (`uint256 betPacked = degeneretteBets[players[i]][betIds[i]];`) → `:1560` (`uint8 currency = uint8((betPacked >> 42) & 0x3);`).
- **Candidate (Scavenger):** `betPacked` is read into a local and used ONLY to extract `currency`; "the resolve sub-call re-reads the bet anyway — fold the currency decode into the sub-call / drop the redundant SLOAD."
- **G-row touched: G12 (the currency gate depends on this read).** Auto-escalated to contract-auditor.
- **contract-auditor verdict:** the read is NOT redundant and NOT removable. The currency MUST be decoded in the TOP-LEVEL `crankBets` frame BEFORE `_crankResolveBet` deletes the bet slot (G3 delete at DegeneretteModule:580) — by the time the resolve sub-call returns, `degeneretteBets[player][betId]` is zeroed, so the currency bits are gone. Reading the packed bet in the caller frame is the only way to know the currency for the G12 reward gate. It is a single SLOAD that is WARM by the time the loop body runs (the item-0 probe at :1552 warmed item 0; each item's slot is touched by the resolve path), so the runtime cost is the warm-SLOAD floor (~100 gas), not a cold read. At runs=200 there is no cheaper correct alternative.
- **Skeptic disposition: REJECT (load-bearing — the read is the only pre-delete source of the currency for G12; not redundant).** Not shipped.

### SCAV-319-04 — `boxCursor`/`boxCursorIndex` widen-to-uint256 "to avoid masking" (crankBoxes)

- **Location:** `DegenerusGame.sol:1507`/`:1510` (`uint48 internal boxCursor;` / `uint48 internal boxCursorIndex;`) + the `uint48(cursor)` cast at `:1631`.
- **Candidate (Scavenger):** "widen the cursor pair to `uint256` to drop the `uint48(...)` cast and the implicit mask on read."
- **G-row touched:** NONE directly, but it is a GAS-04 packing-floor MUST-NOT.
- **Skeptic disposition: REJECT (anti-pattern — widening hurts packing).** `uint48` is correct: the index/cursor are bounded well within 48 bits, and the narrow widths let the pair share a slot with adjacent state (GAS-04 maximal packing, `feedback_maximal_variable_packing`). The `uint48(...)` cast is free at runtime (a mask the optimizer folds). Widening to `uint256` would FORCE two full slots and a cold-SSTORE regression — the opposite of a saving at runs=200. Not shipped.

### SCAV-319-05 — `Sub` struct field widening / repacking (AfKing:80-88)

- **Location:** `AfKing.sol:80-88`.
- **Candidate (Scavenger):** "the `Sub` struct has 19 free padding bytes — widen `dailyQuantity`/`reinvestPct` to larger types since there is room."
- **G-row touched:** NONE; GAS-04 packing-floor MUST-NOT.
- **Skeptic disposition: REJECT (the Scavenger MUST NOT propose widening — RESEARCH §GAS-04 note).** The fields are at minimum correct widths (`uint8` daily quantity / reinvest pct, `uint32` day indices, `bool` flags). The 19 free bytes are intentional headroom within a SINGLE slot; widening changes nothing on the runtime hot path (the whole `Sub` is one warm SLOAD via `_subOf`) and would only consume the free padding for no functional gain. The slot is the packing floor; `feedback_maximal_variable_packing` is satisfied. Not shipped.

### SCAV-319-06 — the `_sweepCursor` persist on a chunk that produced no buys (AfKing:721-726)

- **Location:** `AfKing.sol:721` (`_sweepCursor = uint224(cursor);`) → `:726` (`if (batchLen == 0) revert NoSubscribersSwept();`).
- **Candidate (Scavenger):** "the `_sweepCursor` SSTORE at :721 happens even when the call is about to revert at :726 (batchLen == 0) — the SSTORE is wasted since the revert rolls it back; reorder to skip it."
- **G-row touched:** G11 (cursor self-partition) is adjacent. Escalated to contract-auditor for a correctness read.
- **contract-auditor verdict:** the SSTORE at :721 is on the same execution path as the :726 revert ONLY when `batchLen == 0`. On a revert, the EVM discards ALL state changes in the frame — so the `_sweepCursor` write is automatically rolled back; it is NOT a "wasted SSTORE" in the persisted sense (it never persists on the revert path). Reordering the revert ABOVE the cursor persist would be a micro-saving of the in-frame SSTORE COMPUTE only (the value is discarded either way), and at runs=200 the gain is marginal and the reordering risks the G11 cursor-advance semantics on the SUCCESS path (the cursor MUST persist after a productive chunk). The current order is correct and the "saving" is illusory (reverted writes do not cost persisted-SSTORE gas; only the in-frame SSTORE opcode, which is dwarfed by the revert).
- **Skeptic disposition: REJECT (illusory saving; reordering near G11 carries correctness risk for no real gain).** Not shipped.

---

## Removal-clean verdict

**The GAS-05 pass is REMOVAL-CLEAN.** No Scavenger candidate was approved for shipping in this plan. Specifically:

- **Zero security-floor guards touched-and-approved.** Every candidate that touched a G-row (SCAV-319-02 → G12, SCAV-319-03 → G12, SCAV-319-06 → G11) was escalated to the contract-auditor and REJECTED — the guard is load-bearing and the proposed edit either weakens it, is semantically identical with no runtime gain, or is an illusory saving. `feedback_security_over_gas` held: when in doubt, reject.
- **Zero packing changes approved.** The `Sub` 1-slot floor and the `uint48` cursor pair are already maximally packed (SCAV-319-04, SCAV-319-05 rejected as anti-pattern widenings); `feedback_maximal_variable_packing` is satisfied.
- **One OPTIONAL candidate surfaced, NOT shipped here:** SCAV-319-01, the GAS-02 loop-invariant hoist. Its Skeptic disposition is **approve-if-real-saving / no-op-if-already-hoisted-by-the-optimizer**. It touches NO guard (pure arithmetic recomputation). It is handed to **Plan 05**, which will batch it into the single USER-APPROVED `DegenerusGame.sol` diff ONLY IF Plan 02's before/after measurement shows a real runtime saving at runs=200; otherwise it is dropped as a no-op. Plan 04 makes ZERO `contracts/*.sol` mutation.

**G1-G13 security floor: INTACT at HEAD `8d23f736`.** All 13 guards VERIFIED-PRESENT (re-grepped this session; pinned RED-on-regression by `test/gas/CrankLeversAndPacking.t.sol::testG1ThroughG13GuardsBytePresent`). The runs=200 (not runs=2) runtime-weight correction is documented and APPLIED to every disposition above — no candidate was approved on a stale bytecode-size justification.

**Handoff to Plan 05:** the security floor is clean; the only pending contract-touching item is the OPTIONAL SCAV-319-01 hoist, gated on Plan 02's measurement. Plan 05 owns the single USER-APPROVED diff (the two `*_GAS_UNITS` calibration constants ± the conditional hoist).

---

## Cite set (source lines re-verified at HEAD `8d23f736` this session)

- `contracts/DegenerusGame.sol` — `:1495` (`CRANK_GAS_PRICE_REF`), `:1501-1502` (`*_GAS_UNITS`), `:1507`/`:1510` (`boxCursor`/`boxCursorIndex` uint48), `:1526` (`enqueueBoxForCrank`), `:1543` (`crankBets`), `:1552` (G5 probe / `BatchAlreadyTaken`), `:1555`/`:1610` (`uint24 lvl = _activeTicketLevel();` read-once), `:1557`/`:1560` (`betPacked` SLOAD + currency decode), `:1562`/`:1620` (G7 try/catch), `:1564` (G12 `currency == 3` fork), `:1567-1570`/`:1621-1623` (SCAV-319-01 hoist candidate), `:1578`/`:1632` (one creditFlip per tx), `:1603` (G2 orphan-index skip), `:1618` (G4 already-opened skip), `:1641`/`:1662` (G7/G9 onlySelf `msg.sender != address(this)`), `:1692` (G9 AF_KING gate), `:1693-1694` (G13 rngLocked/gameOver), `:1704-1711`/`:1717-1721` (G6 batchPurchase try/catch + refund)
- `contracts/AfKing.sol` — `:80-88` (`Sub` 1-slot, 13/32 bytes), `:246`/`:252` (`SUB_COST_ETH_TARGET`/`BOUNTY_ETH_TARGET` immutables), `:523` (G13 rngLocked abort `SweepAborted`), `:532` (G11 cursor self-partition), `:567`/`:711` (per-entry `lastSweptDay`), `:587-600` (G8 burnForKeeper all-or-nothing), `:594-599`/`:683-688` (G10 swap-pop no-`++cursor`), `:610` (G9 isOperatorApproved), `:721-726` (SCAV-319-06 cursor persist + NoSubscribersSwept revert), `:738` (one batchPurchase value transfer), `:746` (one creditFlip bounty)
- `contracts/modules/DegenerusGameDegeneretteModule.sol` — `:226` (`MAX_SPINS_PER_BET = 10`), `:452` (G1 placement mirror), `:578` (G1 RngNotReady resolve), `:580` (G3 delete), `:705` (`_distributePayout`), `:1117` (2-arg `_addClaimableEth`)
- `contracts/modules/DegenerusGameLootboxModule.sol` — `:485`/`:567` (RngNotReady open guards), `:530-531` (G4 box zeroing), `:628` (`resolveLootboxDirect`), `:917` (`_resolveLootboxCommon`), `:992` (nested BoonModule delegatecall), `:1036` (box-reward `creditFlip` to the box owner — the conflation the Task-1 cranker-scoped counter isolates)
- `foundry.toml:10` (`optimizer_runs = 200`), `hardhat.config.js:43` (`runs: 50`) — the runs=200/50 correction (NOT the SKILL.md runs=2)
- Skills: `~/.claude/skills/{gas-scavenger,gas-skeptic,contract-auditor}/SKILL.md` (roles + the stale runs=2 caveat)
- Precedent / inputs: `319-RESEARCH.md` §GAS-05 + §Standard Stack WARNING, `319-PATTERNS.md` §"GAS-05 security-floor guardrail set", `319-GAS-DERIVATION.md`, the 318-02/03/04/05 proving suites
