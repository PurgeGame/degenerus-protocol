# Phase 344 — Actor-Consequence Trace (D-344-01): v48 Recovery-Leg Removal

**Authored:** 2026-05-30 (during 344-05 execution, BEFORE any v48-recovery deletion)
**Decision:** D-344-01 — `feedback_design_intent_before_deletion`. The 343 inventory proved the legs are
grep-orphan / no-caller; this trace adds the required **actor-consequence** layer: it proves the v48 stuck-pool
recovery is FULLY REPLACED for BOTH **VAULT** and **sDGNRS** by the de-custody, or surfaces a gap to ESCALATE.

> ⚠ This trace gates Task 2 (the deletions). If the conclusion is "gap", Task 2 does NOT proceed.

---

## 0. What is being removed (the v48 recovery legs)

| Leg | Location (re-pinned, live tree) | What it did |
|-----|--------------------------------|-------------|
| VAULT.recoverAfKingPool() | `DegenerusVault.sol:516-517` | Permissionless, ANYTIME: `afKing.withdraw(afKing.poolOf(address(this)))` → pulls the vault's stranded AfKing `_poolOf` ETH back into the vault (lands in VAULT.receive()). |
| sDGNRS.burnAtGameOver AfKing leg | `StakedDegenerusStonk.sol:539` (inside `burnAtGameOver()` `:535`, GAME-only) | At gameOver (Game-triggered): `afKing.withdraw(afKing.poolOf(address(this)))` → pulls sDGNRS's stranded `_poolOf` ETH back (lands in sDGNRS.receive()). |
| sDGNRS receive() AF_KING relaxation | `StakedDegenerusStonk.sol:442` (inside `receive()` `:439-444`) | Allowed `msg.sender == AF_KING` so the AfKing withdraw send-back was receivable. Dead once the leg above is gone. |

Both legs exist because VAULT/sDGNRS **self-subscribe** to AfKing (`DegenerusVault.sol:482`,
`StakedDegenerusStonk.sol:388`, `fundingSource = address(0)` = self) and prepay ETH into AfKing's local
`_poolOf[VAULT]` / `_poolOf[SDGNRS]`, which they otherwise had no way to reclaim.

---

## 1. The de-custody replacement (where the ETH lives now)

After 344-01..04, AfKing holds **no ETH**. `subscribe`'s `msg.value` forwards to
`GAME.depositKeeperFunding{value}(subscriber)` (A2), so the self-subscriptions' prepaid ETH now lives in the
Game ledger as **`keeperFunding[VAULT]`** and **`keeperFunding[SDGNRS]`** (the systemwide total riding inside
`claimablePool`; SOLVENCY-01). The three asserted recovery legs (D-344-01):

- **(a) ungated `game.withdrawKeeperFunding`** — the funding source withdraws its own bucket (CEI; sends to `msg.sender`).
- **(b) the Game's withdraw/claim `.call` send-back is RECEIVABLE** by VAULT.receive() (open) and sDGNRS.receive() (GAME-allowed).
- **(c) the Decision-B `claimWinnings` keeper-merge** (344-02) — post-gameOver, a claim also pays the caller's `keeperFunding`.

---

## 2. VAULT recoverability trace

| Leg | Finding (verified against source) | Status |
|-----|-----------------------------------|--------|
| (a) `game.withdrawKeeperFunding` | VAULT has **NO** function that calls `game.withdrawKeeperFunding` (`grep withdrawKeeperFunding DegenerusVault.sol` → 0). So leg (a) is **NOT directly available** to the vault. (Available in general to any funding source that has a caller path — e.g. an EOA operator-funder — just not to the vault contract itself.) | N/A for vault |
| (b) send-back receivable | `DegenerusVault.sol:508` `receive() external payable { emit Deposit(...); }` — **OPEN, no sender gate** → accepts the Game's `.call` send-back unconditionally. | ✅ |
| (c) Decision-B claim-merge | VAULT calls the Game's claim path via its **existing** functions: `gameClaimWinnings()` (`:593`, onlyVaultOwner, callable anytime incl. post-gameOver) → `claimWinningsStethFirst()` → `_claimWinningsInternal(VAULT, true)`; and `gamePlayer.claimWinnings(address(this))` (`:584,:816`) → `_resolvePlayer(VAULT)==VAULT` → `_claimWinningsInternal(VAULT, false)`. Post-gameOver, `_claimWinningsInternal` (344-02) reads `keeperFunding[VAULT]`, pays `claimableWinnings + keeperFunding`, zeroes both, debits `claimablePool` by the combined sum. **The vault owner triggering any claim post-gameOver recovers `keeperFunding[VAULT]`.** | ✅ |

**VAULT conclusion: recoverable.** keeperFunding[VAULT] is reclaimed post-gameOver via the vault's existing
claim calls (Decision-B), with the send-back received by the open `receive()`.

---

## 3. sDGNRS recoverability trace

| Leg | Finding (verified against source) | Status |
|-----|-----------------------------------|--------|
| (a) `game.withdrawKeeperFunding` | sDGNRS has **NO** caller for `game.withdrawKeeperFunding` (grep → 0). Not directly available. | N/A for sDGNRS |
| (b) send-back receivable | `StakedDegenerusStonk.sol:439-444` `receive()` allows `msg.sender == ContractAddresses.GAME` (kept after the AF_KING narrow). The Game's claim payout `.call` has `msg.sender == GAME` → **accepted**. (The removed AF_KING allowance was only for the old AfKing send-back, which no longer exists.) | ✅ |
| (c) Decision-B claim-merge | sDGNRS calls `game.claimWinnings(address(0))` at `:622` (inside redemption settlement, fired when `totalValueOwed > ethBal && claimableEth != 0`). `_resolvePlayer(0)==sDGNRS` → `_claimWinningsInternal(sDGNRS,...)`. Post-gameOver, this reads + zeroes `keeperFunding[SDGNRS]` and pays it out (Decision-B). **A post-gameOver redemption that needs ETH recovers `keeperFunding[SDGNRS]`.** | ✅ |

**sDGNRS conclusion: recoverable.** keeperFunding[SDGNRS] is reclaimed post-gameOver via sDGNRS's existing
`game.claimWinnings(address(0))` call (Decision-B), with the send-back received by the GAME-allowed `receive()`.

---

## 4. Honest nuances surfaced (for the user's confirmation)

The recovery shifts from v48's **eager/guaranteed** legs to v54's **lazy/post-gameOver** claim-merge. Three
consequences the user should adjudicate:

1. **Timing — VAULT loses pre-gameOver recovery.** v48 `recoverAfKingPool()` was permissionless and callable
   ANYTIME; v54 recovery for the vault is **post-gameOver only** (the claim-merge gate is `gameOver`).
   Pre-gameOver the vault's `keeperFunding` is its own auto-buy budget, intentionally spent by the keeper —
   so there is no *stranding*, only a loss of the ability to yank it back mid-game. sDGNRS's v48 leg was
   ALREADY gameOver-only (`burnAtGameOver`), so sDGNRS has **no timing regression**.
2. **Lifecycle — claimable-equivalent 30-day forfeiture.** Per GAMEOVER-02 / PLAN-V54 §"GameOverModule" (LOCKED),
   `keeperFunding` is claimable-equivalent post-gameOver: if unclaimed before `handleFinalSweep` (30 days), it is
   swept WITH `claimablePool` (it stays in the protocol — redistributed at sweep — it is not lost to the void).
   Both withdraw/claim paths stay open until that sweep.
3. **sDGNRS recovery is now conditional (lazy), not guaranteed-at-gameOver.** v48 `burnAtGameOver` *guaranteed*
   the pull at gameOver; v54 relies on sDGNRS calling `claimWinnings(0)` during a post-gameOver redemption that
   needs ETH (`:622`). In practice post-gameOver redemptions trigger it; if none do within 30 days, the bucket is
   swept (claimable-equivalent, per nuance 2). No dedicated guaranteed replacement is added (the plan does not
   call for one). A vault-owner-style trigger does not exist for sDGNRS, but its redemption flow is the trigger.

None of these are new *gaps* relative to the LOCKED SPEC — GAMEOVER-01/02 and PLAN-V54 §"Decision B" explicitly
adopt the claimable-equivalent post-gameOver merge + 30-day forfeiture as the intended replacement. They are
surfaced here so the deletion is an informed one, per the audit-discipline maxim.

---

## 5. CONCLUSION

**Recoverability is PRESERVED for BOTH VAULT and sDGNRS.**

- (b) ✅ VAULT.receive() is open; sDGNRS.receive() is GAME-allowed — both accept the Game's send-back.
- (c) ✅ Both recover `keeperFunding[*]` post-gameOver through their EXISTING claim calls (Decision-B merge):
  VAULT via `gameClaimWinnings()`/`claimWinnings(this)`; sDGNRS via `game.claimWinnings(0)` (`:622`).
- (a) is the general funding-source mechanism (not wired into the vault/sDGNRS contracts themselves; they use (c)).

No **permanent** stranding exists within the 30-day post-gameOver window. The recovery is post-gameOver/lazy
(consistent with the LOCKED claimable-equivalent model), not the v48 eager/guaranteed legs — see §4.

**Gate verdict:** NO GAP that contradicts the LOCKED SPEC → Task 2 (the deletions) may proceed **once the user
confirms this conclusion** (the §4 nuances are the user's to accept). If the user judges the loss of VAULT's
pre-gameOver recovery (§4.1) or sDGNRS's guaranteed-at-gameOver pull (§4.3) unacceptable, ESCALATE (e.g. wire a
`withdrawKeeperFunding` caller into the vault, or add a `claimWinnings(0)` to `burnAtGameOver`) before deleting.

---

## 6. USER DECISION (2026-05-30, at the BLOCKING checkpoint) — partial escalation

**User directive: "VAULT should have withdrawkeeperfunding."** The user accepted the trace for sDGNRS but
ESCALATED §4.1 for the vault — VAULT must retain anytime (pre-gameOver) recovery.

**Resolution applied to the diff:**
- **VAULT:** `recoverAfKingPool()` is NOT deleted — it is RE-POINTED to the de-custodied ledger and renamed
  `recoverKeeperFunding()` (0 external callers, rename is safe): it now calls
  `gamePlayer.withdrawKeeperFunding(gamePlayer.keeperFundingOf(address(this)))`. Permissionless, anytime
  pre-sweep; the send-back lands in VAULT.receive() (open); a zero balance is a no-op; reverts post-final-sweep
  (claimable-equivalent forfeiture). **§4.1 fully resolved — the vault regains its anytime recovery.** The Vault's
  Game interface (`IDegenerusGamePlayerActions`) gains `withdrawKeeperFunding(uint256)` + `keeperFundingOf(address)`.
- **sDGNRS:** proceeds per the original plan (the user did not flag it). The `burnAtGameOver` AfKing leg is
  removed and `receive()` narrowed to GAME-only; recovery is via the existing `game.claimWinnings(0)` (`:622`)
  Decision-B merge. sDGNRS's v48 leg was already gameOver-only, so there is no timing regression vs v48; the
  lazy/conditional nature (§4.3) stands and is re-surfaced at the final hand-review for awareness.

This resolution keeps the de-custody (AfKing holds no ETH; `_poolOf`/`withdraw`/`poolOf` deleted) while routing
the vault's recovery through the new Game ledger instead of the deleted AfKing pool.
