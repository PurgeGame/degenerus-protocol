# Gas round-5 packet — GNRUS.sol

5 findings: TOKENS-01, TOKENS-02, TOKENS-05, TOKENS-06 (APPROVED) · TOKENS-08 (PARTIAL, adjudicated below).
Locate by CONTENT — line numbers are audit-time. Three of these (TOKENS-01/05/08) reduce
advanceGame-chain execution gas — the bound that matters (16.7M ceiling; refunds do NOT lower it).

## Adjudications (round-5 orchestrator)

- **TOKENS-08 — APPLY sub-changes (b)+(c) ONLY; skip (a)** (skeptic's own split, adopted):
  (b) wrap the whole flush phase incl. the currentActiveBitmap/pendingEditSet writes in
  `if (pSet != 0)`; (c) running `mask <<= 1` in place of per-iteration shifts (pure mechanical, may
  extend to view loops). Sub-change (a) (winner-loop early break) trades worst-case for typical-case
  in the advance chain — never do that; omitted.
- TOKENS-01 note: deleting the levelResolved mapping SHIFTS GNRUS storage layout (everything below
  moves up one slot) — production-safe (fresh deploy, no shared storage) but recalibrate any
  vm.store/vm.load GNRUS harness via forge inspect, and expect JS tests reading the public getter to
  need updates. Public getter disappears (off-chain derives from currentLevel / events). Update
  PickCharityRejected natspec + idempotence comments; REJECT_LEVEL_NOT_ACTIVE stays 0.
- TOKENS-05 note: ceiling-vs-net trade resolved in favor of the worst-case ceiling per the
  USER-locked bound. Reword the dual-sentinel natspec (bit = only sentinel; value may be stale).
- TOKENS-06 note: checked subtraction MANDATORY (`balanceOf[burner] = burnerBal - amount;` — the
  implicit underflow revert is the over-burn guard). No unchecked.

## Ledger bodies

#### TOKENS-01 — contracts/GNRUS.sol (L174, L626, L629, L232-233)
**Category:** redundant_check · **Frequency:** warm · **Confidence:** high · **Batch:** tokens

The levelResolved mapping is fully dominated by the currentLevel monotonicity check. pickCharity (L625) requires level == currentLevel; on success L630 sets currentLevel = level+1. currentLevel is written NOWHERE else in the codebase (grep-verified) and only ever increases (checked uint24 add reverts at max), so levelResolved[level] == true implies currentLevel >= level+1, which makes the L626 check unreachable-true — L625 always reverts first. The L629 write is a cold SSTORE 0->1 (~20,000 gas) plus the L626 cold SLOAD (~2,100) paid on EVERY level transition inside the advanceGame chain (caller: modules/DegenerusGameAdvanceModule.sol:1759). No other contract reads levelResolved (grep over all of contracts/ excluding mocks/test returned only GNRUS.sol).

**Change:** Delete the mapping declaration (L174), the check at L626, the write at L629, and the REJECT_LEVEL_ALREADY_RESOLVED constant (L232-233); update the PickCharityRejected natspec reason codes. Off-chain consumers can derive resolution state from currentLevel or the LevelResolved/LevelSkipped events.

**Savings:** runtime ~22,100 per level transition (2,100 cold SLOAD at L626 + 20,000 SSTORE 0->1 at L629; slot warm after the check read). This is a direct worst-case-execution reduction in the bounded advanceGame chain. · bytecode ~60 (check + write + public auto-getter) · skeptic-revised: Confirmed ~22,100 gas per level transition (2,100 cold SLOAD + 20,000 zero->nonzero SSTORE; key is unique per level so always cold/zero). Warm path, advance-chain ceiling-reducing.

**Skeptic (APPROVED, risk low, invariant impact none):** Domination proof verified against live source. GNRUS.sol:625 requires level == currentLevel; currentLevel's SOLE writer in the entire codebase is GNRUS.sol:630 (grep over contracts/ ex mocks/test confirms — all other 'currentLevel' hits are unrelated locals in Game modules), and the checked uint24 add makes it strictly increasing (reverts at max). Therefore levelResolved[level]==true implies currentLevel >= level+1, making L626 unreachable-true: L625 always reverts first. No cross-contract reader of levelResolved exists (grep clean; AdvanceModule's local interface at modules/DegenerusGameAdvanceModule.sol:29 declares only pickCharity). The sole call site (AdvanceModule:1759, charityResolve.pickCharity(lvl-1)) is a direct call with no try/catch keyed on the error, so no caller semantics depend on the never-firing REJECT_LEVEL_ALREADY_RESOLVED. pickCharity has zero external calls, so no reentrant double-resolve path bypasses L625. Idempotence remains fully enforced by L625 post-removal — a duplicate call reverts identically today and after the change. This is the highest-value finding in the batch: a real worst-case reduction inside the advanceGame chain.

**Implementation notes:** Deleting the mapping at L174 shifts GNRUS storage layout (hasVoted and everything below move up one slot). Production-safe — GNRUS deploys fresh, no modules share its storage — but recalibrate any vm.store/vm.load GNRUS test harnesses via forge inspect. Also update: PickCharityRejected natspec (L91-93), the step-(2) idempotence comment at L607/L628, and remove REJECT_LEVEL_ALREADY_RESOLVED (L232-233). REJECT_LEVEL_NOT_ACTIVE stays 0 — no other reason-code shifts. Contract edit requires explicit user approval per standing rules; batch with the other approved GNRUS edits into one diff.

**Finder risk notes:** Removes a defense-in-depth idempotence guard; the dominating guarantee is GNRUS.sol:625 (level != currentLevel) plus the fact that L630 is the sole currentLevel writer and is strictly increasing. Public getter disappears (off-chain API change). Frozen-deploy rule applies: the second guard is unreachable on the deployed system.


#### TOKENS-02 — contracts/GNRUS.sol (L405-406, L413-414, L428-456, L85)
**Category:** dead_code · **Frequency:** cold · **Confidence:** high · **Batch:** tokens

CapExceeded is unreachable. The cap check is `_popcount32(futureBitmap) > MAX_ACTIVE_SLOTS` with MAX_ACTIVE_SLOTS = 20, but every bit ever set in currentActiveBitmap (L409 with slot<20 enforced at L383; L680 with loop i<20) and pendingEditSet (L417 with slot<20) lies in positions 0..19, and _futureBitmapAfter only manipulates bits 0..19. A 20-bit-domain bitmap has popcount <= 20, so `> 20` can never be true. The dominating check is GNRUS.sol:383 (`if (slot >= MAX_ACTIVE_SLOTS) revert InvalidSlot();`) plus the structural 20-slot domain. Consequently both cap-check blocks, the entire _futureBitmapAfter helper (20-iteration loop with up to ~17 cold SLOADs of pendingEdit), and the CapExceeded error are dead code.

**Change:** Delete L405-406 and L413-414 (both cap-check blocks), the _futureBitmapAfter function (L428-456), and the CapExceeded error (L85). The cap is structurally enforced by the slot < 20 guard at L383.

**Savings:** runtime ~700-1,000 per setCharity call typical (20-iteration loop + popcount + call overhead); up to ~36,000 when many pending edits exist (cold SLOAD of pendingEdit[i] per set bit). Admin-only path. · bytecode ~300-400 · skeptic-revised: As claimed: ~700-1,000 typical per setCharity, up to ~36k with many pending edits — but cold (vault-owner admin only), so the real value is the ~300-400 bytecode bytes and source simplification.

**Skeptic (APPROVED, risk low, invariant impact none):** Bit-domain induction verified: currentActiveBitmap is written only at L409 (|= slotMask with slot<20 enforced at L383) and L680 (a value derived from currentActiveBitmap by setting/clearing masks for i in 0..19), initial 0 — so its bits always lie in positions 0..19. pendingEditSet writers (L400 clear, L417 |= slotMask with slot<20, L681 =0) share the domain. _futureBitmapAfter only flips bits 0..19 of that value, so its popcount is structurally <= 20 and '> MAX_ACTIVE_SLOTS' (>20) can never be true. Both cap-check blocks are dead; _futureBitmapAfter's only two call sites are those dead checks, so the whole helper (including its up-to-17 cold pendingEdit SLOADs) and the CapExceeded error fall out. CapExceeded is referenced nowhere else in contracts/. Design-intent trace: the post-flush cap is already guaranteed by the fixed 20-slot domain — the check is vacuous as written, and frozen-deploy rules out future-proofing retention.

**Implementation notes:** Delete L405-406, L413-414, L428-456, and the CapExceeded error (L84-85). No storage change. Cap-check natspec at L422-427 and the setCharity branch comments need trimming.

**Finder risk notes:** Pure unreachable-revert removal — cannot weaken any invariant since the revert can never fire. Per feedback_design_intent_before_deletion: the apparent intent was a post-flush active-slot cap, which is already guaranteed by the fixed 20-slot domain.


#### TOKENS-05 — contracts/GNRUS.sol (L675 (and L399))
**Category:** other · **Frequency:** warm · **Confidence:** low · **Batch:** tokens

The flush loop's `delete pendingEdit[i]` is observationally redundant: every read of pendingEdit[i] in the contract is gated by the corresponding pendingEditSet bit (L446 for i != slot, L468, L538, L668; for i == slot in _futureBitmapAfter the proposed `recipient` is used instead), and pendingEditSet is zeroed at L681. Stale values are never observable. Same applies to the zero-write at L399 in the cancel branch (bit cleared at L400). Each delete costs ~2,900 EXECUTION gas (warm nonzero->zero SSTORE) inside pickCharity, which runs in the advanceGame chain — execution gas counts against the 16.7M ceiling; the 4,800 EIP-3529 refund does NOT lower the execution ceiling. Bonus: leaving stale values makes a future re-queue of the same slot a 2,900 nonzero->nonzero SSTORE instead of 20,000.

**Change:** Remove `delete pendingEdit[i];` from the flush loop (L675) and `pendingEdit[slot] = address(0);` from the cancel branch (L399); treat pendingEditSet as the sole source of truth for pending-edit existence.

**Savings:** runtime Worst-case execution: -2,900 per flushed edit in pickCharity (up to ~49k with 17 queueable slots 3..19). Long-run NET gas is slightly NEGATIVE when refunds fully apply (delete nets -1,900/edit after refund), so this is a ceiling-vs-net trade. · bytecode ~20 · skeptic-revised: Worst-case advance-chain execution: -2,900 per flushed edit (up to ~49k at 17 edits). Average net is roughly neutral: forfeits -1,900/edit of post-refund gain, but stale-slot re-queues drop from 22,100 to ~5,000 (cold nonzero->nonzero). Treat as a ceiling-vs-net trade resolved in favor of the ceiling per the user's stated bound.

**Skeptic (APPROVED, risk low, invariant impact none):** Gating claim verified exhaustively: every pendingEdit read in the contract — L446 (_futureBitmapAfter, i != slot path), L468 (_flushedBitmap), L538 (getPendingEdits), L668 (flush loop) — is guarded by the corresponding pendingEditSet/pSet bit, and pendingEdit is private with no auto-getter, so stale values are unobservable through the contract API. Cancel-branch trace (L399 removal): stale nonzero value with bit cleared is never read; a later queue-branch write at L416 overwrites it (and becomes a cheaper nonzero->nonzero SSTORE). Flush-loop trace (L675 removal): pendingEditSet=0 at L681 clears all gates atomically in the same function. Behavior-identical. The trade is honest as stated: removing the deletes lowers worst-case advance-chain EXECUTION by 2,900 per flushed edit (refunds do not reduce the execution counted against the 16.7M ceiling), at the cost of forfeiting the 4,800 EIP-3529 refund per delete — and the user's locked priority is the worst-case ceiling in the advance chain, which this strictly improves. Magnitude is small either way (pending edits require rare vault-owner action, <=17 slots).

**Implementation notes:** Remove L675 and L399; pendingEditSet stays the sole existence oracle. Raw-storage test harnesses (vm.load on the pendingEdit mapping) may need expectation updates — no production impact. The dual-sentinel natspec at L183-184 should be reworded (bit is the only sentinel; value may be stale when bit clear).

**Finder risk notes:** Honest trade-off: improves worst-case execution bound of the advance chain but forfeits refunds (worse average net gas when refunds apply). getPendingEdits/_flushedBitmap correctness preserved because all reads are bitmap-gated. The Skeptic should weigh the user's hard-ceiling priority against long-run net; pending edits also require rare admin action, so magnitude is small either way.


#### TOKENS-06 — contracts/GNRUS.sol (L327)
**Category:** redundant_sload · **Frequency:** warm · **Confidence:** high · **Batch:** tokens

burn() reads balanceOf[burner] into burnerBal at L299, then `balanceOf[burner] -= amount` at L327 re-SLOADs the same slot (warm, ~100 gas). No intervening operation can mutate balanceOf[burner]: L309-310 are STATICCALLs, and game.claimWinnings (L318) only sends ETH to GNRUS's empty receive() and/or stETH (no hooks) — no reentrant path writes GNRUS balances.

**Change:** Replace L327 with `balanceOf[burner] = burnerBal - amount;` using CHECKED subtraction (preserves the underflow revert for amount > burnerBal in the non-sweep path). Do NOT wrap in unchecked.

**Savings:** runtime ~100 per burn (warm SLOAD avoided; mapping-slot keccak recompute also avoided, ~40 more) · bytecode ~0 · skeptic-revised: ~140 gas per burn (warm SLOAD ~100 + mapping keccak/slot recompute ~40). burn() is player-paid — warm.

**Skeptic (APPROVED, risk low, invariant impact none):** Reentrancy-freshness verified end-to-end, which was the load-bearing claim since the cache spans an external state-changing call. Between L299 (read) and L327 (write): steth.balanceOf and game.claimableWinningsOf are interface-view STATICCALLs; game.claimWinnings(address(this)) at L318 executes DegenerusGame._claimWinningsInternal (Game-storage effects only, then _payoutWithStethFallback at DegenerusGame.sol:2353 which hands control ONLY to the payee — here GNRUS itself, whose receive() at L694 is empty; the stETH leg has no hooks) followed by the maybeCurse delegatecall — which early-returns for player == ContractAddresses.GNRUS at GameAfkingModule.sol:1662-1666 before touching anything, closing the one theoretical path where Game-context code could have passed GNRUS's onlyGame gate. GNRUS.balanceOf is writable only by GNRUS's own code, and no GNRUS entry point executes during the window; the burner gets no control until after L327 (CEI transfers at L334-340). The checked `burnerBal - amount` preserves the over-burn underflow revert exactly (sweep path sets amount = burnerBal, so it never underflows there; non-sweep over-ask reverts as today). Do NOT wrap in unchecked, as the recommendation correctly states.

**Implementation notes:** One-line change: balanceOf[burner] = burnerBal - amount; (checked). Keep the existing CEI comment.

**Finder risk notes:** Must keep checked math — the implicit underflow revert is the only thing preventing over-burn when amount > balance and neither sweep condition hits. Reentrancy-freshness argument: receive() is empty, stETH transfer has no callback.


#### TOKENS-08 — contracts/GNRUS.sol (L636-645, L664-681)
**Category:** loop · **Frequency:** warm · **Confidence:** medium · **Batch:** tokens

pickCharity always runs two fixed 20-iteration loops even when most iterations are no-ops. (a) Winner loop: no early exit once the bitmap's highest set bit is passed — with the typical 3 locked low slots active, ~16 empty tail iterations (~20 gas each) are wasted every level. (b) Flush phase: when pendingEditSet == 0 (the common case — pending edits require rare vault-owner action), the loop still runs 20 iterations AND the contract still rewrites currentActiveBitmap with its unchanged value (L680) and pendingEditSet with 0 (L681) — two warm packed-field read-modify-writes (~100+ gas each) on every level. Also both loops recompute `uint32(1) << i` per iteration instead of doubling a running mask.

**Change:** (a) Add `if ((bitmap >> i) == 0) break;` at the top of the winner loop. (b) Wrap the entire flush phase, including the L680-681 writes, in `if (pSet != 0) { ... }`. (c) Optionally replace per-iteration shifts with a running `mask <<= 1` in both loops (and the view loops).

**Savings:** runtime ~500-800 per pickCharity in the common case (no pending edits, low-slot winners): ~300 winner-loop tail + ~400 flush loop + ~150-200 skipped packed-slot writes. Runs once per level in the advanceGame chain. · bytecode ~0 (slightly larger from the extra branches) · skeptic-revised: (b)+(c) only: ~400-600 per pickCharity in the common no-pending-edits case (~350 flush-loop iterations + ~200 skipped packed-slot read-modify-writes; via_ir may already merge the L680/L681 writes into one SSTORE, which would lower the write-skip share). Once per level in the advance chain.

**Skeptic (PARTIAL, risk low, invariant impact none):** Sub-change (b) verified safe and approved: the winner loop (L636-645) never writes `bitmap`, so when pSet == 0 the flush loop is a pure no-op, L680 rewrites currentActiveBitmap with its own unchanged value, and L681 writes 0 over an already-zero pendingEditSet — wrapping the whole flush phase including both writes in `if (pSet != 0)` is state- and event-identical (no CharityFlushed events are skipped; the loop body never ran). Sub-change (c) (running mask <<= 1) is mechanical and equivalent. Sub-change (a) (winner-loop early break) is also behavior-identical — no bit >= i can match once bitmap >> i == 0, and tie-break semantics are untouched — BUT it ADDS ~10 gas x 20 iterations (~200) to the absolute worst case (full 20-slot slate) to save ~320 in the typical 3-slot case. Under the user's worst-case-first dual bound for the advance chain, approve (b)+(c) unconditionally; treat (a) as optional/neutral and recommend omitting it — both its cost and benefit are noise, and the clean rule is never to trade worst-case for typical-case in this chain.

**Implementation notes:** Implement: uint32 pSet = pendingEditSet; if (pSet != 0) { <flush loop>; currentActiveBitmap = bitmap; pendingEditSet = 0; }. Skip sub-change (a). If (c) is applied to the view loops too, keep it a pure mechanical substitution.

**Finder risk notes:** (b) is safe because pSet == 0 implies bitmap is unmodified and pendingEditSet is already 0 — skipping the writes is state-identical. (a) is safe because no bit >= i can match once bitmap >> i == 0. Keep the strict `>` tie-break semantics untouched.



## APPLIED (round-5 session, pending validation)
- TOKENS-01: levelResolved mapping + L-check + write + REJECT_LEVEL_ALREADY_RESOLVED deleted; pickCharity
  docblock/step comments reworded (currentLevel monotonicity = the idempotence proof). Storage layout
  shifted (hasVoted and below move up one slot).
- TOKENS-02: both cap-check blocks + _futureBitmapAfter + CapExceeded error deleted; structural-cap
  comment left at the instant-apply site.
- TOKENS-05: cancel-branch zero-write + flush-loop delete removed; pendingEdit natspec reworded
  (bit = sole sentinel, stale values unobservable).
- TOKENS-06: balanceOf[burner] = burnerBal - amount (checked); freshness comment added.
- TOKENS-08 (b)+(c): flush phase (incl. both packed-field writes) wrapped in if (pSet != 0); running
  mask in winner + flush loops. Sub-change (a) omitted per adjudication.

## APPLIED (vault) — see packet-vault.md
