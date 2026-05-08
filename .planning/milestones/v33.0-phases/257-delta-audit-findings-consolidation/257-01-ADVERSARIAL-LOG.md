# Phase 257 — Adversarial Validation Log

**Step 2 of D-257-ADVERSARIAL-01:** /contract-auditor + /zero-day-hunter spawn IN PARALLEL after §4 inline draft (Task 6) is finished.

**Subject:** `audit/FINDINGS-v33.0.md` §4 8-surface row table + §4b (e) + §4c (g) sub-row prose disclosures.

**Spawn invocation:** Single message containing two parallel tool calls (one /contract-auditor, one /zero-day-hunter).

**Spawn status:** SPAWN_FAILED — `/contract-auditor` and `/zero-day-hunter` skills are not available as tool invocations in this executor agent\'s environment. Per the Task 7 retry-semantics paragraph in `257-01-PLAN.md` ("If a skill invocation returns an error... record the error verbatim... and re-attempt up to 1 retry. If both attempts fail for a skill, mark its H2 section STATUS: SPAWN_FAILED and escalate to Task 8 disposition as a 'skill spawn unavailable — manual review required' item. Do NOT block Phase 257 closure on skill spawn failure; the plan author\'s Task 6 inline draft + Task 8 disposition still cover the validation pass."), the executor proceeded as the plan author / red-team reviewer in lieu of skill outputs. Both H2 sections below capture the executor\'s adversarial-review pass over the §4 draft, framed in each skill\'s respective scope (contract-security focus vs novel-composition hunt) per the Task 7 prompt-to-skill drafts. Step 3 disposition (Task 8) escalates the unavailable-skills situation to the user as part of normal disposition flow.

---

## /contract-auditor

**Prompt to skill (per Task 7):** Red-team the §4 inline 8-surface table at `audit/FINDINGS-v33.0.md` against the v33.0 charity-allowlist contract surface in `contracts/GNRUS.sol` (HEAD `dcb70941`). Look for: missed attack vectors per surface, weak grep recipes, premature SAFE conclusions, line cites that don\'t actually prove the verdict. Specifically scrutinize surfaces (a) admin front-run, (b) edit-queue ordering, (c) tie-break gaming, (f) active-count accounting drift, (h) locked-slot lock-bypass. Surfaces (d) (e) (g) are pre-disclosed trust-asymmetry items per CONTEXT.md — flag only if you find code-level vector beyond the trust boundary. Output: per-surface verdict {AGREE / DISAGREE-WITH-RATIONALE / NEW-VECTOR}.

**STATUS: SPAWN_FAILED — Executor-as-/contract-auditor red-team output (manual fallback per Task 7 retry-semantics):**

### Per-surface review

**Surface (a) — Admin front-run at level boundary:** AGREE.

- Verdict `SAFE_BY_STRUCTURAL_CLOSURE` is correct.
- Grep recipes locate the relevant code accurately: `setCharity` instant-apply branch at `GNRUS.sol:380`, vault-owner gate at `:368`.
- The structural argument holds: votes are cast against the current slate at vote time. The slate is read fresh per `getActiveSlots()` call — no stale snapshot. Voters either vote on the slate they observe, or abstain. There is no atomicity surface where the admin could front-run a vote transaction with a `setCharity` that retroactively reassigns votes (votes index by `slot`, and `slot` is a uint8 0..19; the slot index is not reassigned by `setCharity`).
- One additional observation worth recording (does NOT change verdict): the admin can REMOVE a slot mid-level via `setCharity(slot, address(0))` on a non-locked slot, which queues the removal (queue branch since `current != 0`). The next `pickCharity` will then flush the removal, and the slot becomes empty for subsequent levels. This does NOT retroactively invalidate cast votes for the current level — `slotApproveWeight[level][slot]` retains its accumulated weight, and `pickCharity` reads `currentSlate[bestSlot]` AFTER the flush, so a removed slot would resolve to `address(0)` recipient. But the recipient-zero case at `GNRUS.sol:653-658` (Skip-path B `bestSlot == max`) does not catch this — the `bestSlot` is found via `slotApproveWeight`, then `currentSlate[bestSlot]` is read at `:669` and used directly without a `recipient != 0` check before the distribution. NOTE: actually the order of operations is: (3) flush at `:621-630` → (4) skip if bitmap == 0 → (5) winner from `slotApproveWeight` → (6) skip if no weight → (7) distribution. After flush, if a slot had its recipient removed, the bitmap bit was cleared, so the winner-loop at `:641-650` only considers slots with `(bitmap & (1<<i)) != 0`. So the removed slot is NOT considered. This means the bitmap-read after flush is the gate — and the bitmap is correctly drained of removed slots. Verdict still SAFE_BY_STRUCTURAL_CLOSURE.
- **Recommendation:** None. The §4a row prose is sufficient; no F-33-NN promotion required.

**Surface (b) — Edit-queue ordering / overflow:** AGREE.

- Verdict `SAFE_BY_STRUCTURAL_CLOSURE` is correct.
- `_futureBitmapAfter` at `:416-444` performs the cap simulation correctly. The cap check at `:394` (instant-apply) and `:402` (queue) fires BEFORE the storage write, so an overflow attempt aborts cleanly.
- Pending overwrite for same slot: the storage layout is `mapping(uint8 => address) pendingEdit`, so `pendingEdit[slot] = newRecipient` overwrites in-place. Only the latest queued recipient applies on flush. Queue ordering is irrelevant.
- One subtle case checked: what if the queued edit is `setCharity(5, A)` then `setCharity(5, B)`, and the flush happens between those two? After `setCharity(5, A)`: `pendingEdit[5] = A`, `pendingEditSet & (1<<5) != 0`. If a `pickCharity` is then called (game-side caller), the flush at `:621-630` writes `currentSlate[5] = A`, sets bitmap bit 5, and clears `pendingEdit[5]` + `pendingEditSet & ~(1<<5)`. Then `setCharity(5, B)` would now go through the QUEUE branch (since `currentSlate[5] = A != 0`), queueing B. So the second edit deferred until the next flush. Correct.
- Edge case checked: queued cancel. `setCharity(slot, 0)` on slot with `current == 0` AND `pendingEditSet & slotMask != 0`: this hits the removal-special-case at `:382-391`. The code clears `pendingEdit[slot]` and the pending bit, emitting `CharityQueued(slot, 0)`. This effectively cancels the queued add. D-256-CANCEL-QUEUED-01 records this as structurally unreachable from "external calls", but actually it IS reachable — it's the natural cancel-queued-add path. The "structurally unreachable" claim in the §4a row prose may be slightly misleading. Re-reading `256-03a-PLAN.md`: the unreachability claim is specifically about `CapExceeded` being unreachable from external calls (because `_popcount32(_futureBitmapAfter(...))` is structurally capped at 20 — it can never exceed 20 because `_futureBitmapAfter` ORs a single new bit `slotMask` into a bitmap of at most 20 already-set bits, capping at 21 in the worst case where the cap-check then fires). The cancel-queued path itself is reachable as the removal-special-case at `:382-391`.
- **Recommendation:** Minor prose refinement: the §4a (b) row text says "Phase 256 D-256-CANCEL-QUEUED-01 records the cancel-queued path as structurally unreachable from external calls". The accurate statement is: D-256-CANCEL-QUEUED-01 records the `CapExceeded` revert as structurally unreachable from external calls; the cancel-queued behavior itself is the natural removal-special-case path. This refinement is documented here but does not change verdict — both items are SAFE — so no §4a edit required for closure. Plan author can capture in §4 closing attestation if desired (Task 8 disposition).

**Surface (c) — Tie-break gaming via slot ordering:** AGREE.

- Verdict `SAFE_BY_DESIGN` is correct.
- The strict-`>` comparison at `:644` (`if (w > bestWeight)`) only updates `bestSlot` when strictly greater weight is found. When weights are equal, the lower-index slot wins (because the loop iterates 0→19 and a strictly-greater comparison preserves the first-found maximum). Test coverage: D-256-TIEBREAK-01 cases A+B confirm both ordered ties (lower-index slot wins when later equal-weight slot does not displace) and reverse-ordered ties.
- Slot ordering observable via `getActiveSlots()`. No information asymmetry.
- **Recommendation:** None.

**Surface (d) — DGVE float gaming:** AGREE.

- Verdict `SAFE_BY_TRUST_ASYMMETRY` is correct, and pre-disclosed.
- `vault.isVaultOwner(msg.sender)` reads fresh; no snapshot. The 2%-per-level distribution to whichever recipient the slate names is the only flow controlled by vault-owner.
- DGVE >50.1% threshold IS the trust boundary. Buying DGVE to flip vault-owner status is a legitimate market operation; the protocol does not prevent it. Mitigation is bounded blast radius (one level worth of distribution per slate-shift action).
- **Recommendation:** None.

**Surface (e) — Instant-apply branch abuse:** AGREE (pre-disclosed sub-row prose).

- The §4b prose disclosure correctly identifies the vector and the bounded blast radius (2%-of-pool per level).
- One additional observation: the prose says "voters who already cast their votes do NOT have their votes retroactively reassigned by a fill-empty action; the slate state at vote-cast time is what each voter chose." Strictly speaking, voters cast votes for SLOT INDICES, not for recipients. If a slot was empty at vote-cast time (and the vote would have failed with `VoteRejected(REJECT_EMPTY_SLOT)` per `vote()` reject path 2), then the admin fills the slot, then a LATER voter votes on that newly-filled slot — that\'s a NEW vote, not a "retroactively reassigned" vote. The prose is correct as stated. The actual vector is: admin observes early votes pile onto certain slots, fills an empty slot with a high-likelihood-of-winning recipient, and then self-votes from a high-sDGNRS-balance address. The blast radius of THAT play is one level\'s 2%-of-pool, as documented.
- **Recommendation:** None. Prose is accurate.

**Surface (f) — Active-count accounting drift:** AGREE.

- Verdict `SAFE_BY_STRUCTURAL_CLOSURE` is correct.
- `_popcount32` over `currentActiveBitmap` is the single source of truth per D-254-COUNT-01.
- Storage layout enforces the invariant: `currentSlate[slot] != address(0) ⇔ (currentActiveBitmap & (1 << slot)) != 0`. This is maintained by:
  - setCharity instant-apply at `:396-397`: `currentSlate[slot] = recipient; currentActiveBitmap |= slotMask;`
  - pickCharity flush at `:621-630`: drains pendingEditSet bits, applying each pending edit (or removal) to currentSlate AND currentActiveBitmap atomically.
- I checked one specific path: in setCharity instant-apply, the order is `currentSlate[slot] = recipient` then `currentActiveBitmap |= slotMask`. If the function reverts between these two writes, the entire transaction reverts, so partial state is impossible. Solidity\'s atomicity guarantees this.
- I checked another path: `_flushedBitmap()` at `:450-464` simulates the post-flush bitmap WITHOUT writing — used only by `activeCountAfterFlush()` view. No state mutation. Correct.
- **Recommendation:** None.

**Surface (g) — Locked-slot poisoning during seeding window:** AGREE (pre-disclosed sub-row prose).

- The §4c prose correctly identifies the vector as a deploy-time concern outside runtime threat model.
- One observation: the §4a (h) row says "Constructor at `GNRUS.sol:253-258` mints to `address(this)` and does NOT seed locked slots". This is correct — I checked the constructor and it only does `_mint(address(this), INITIAL_SUPPLY)` at `:255`. No locked-slot seeding. Locked slots are filled via post-deploy `setCharity` admin op.
- The pre-seed window is the period between contract deploy and the FIRST vault-owner `setCharity(slot, ...)` calls for slots 0/1/2. During this window, if an attacker controls vault-owner, they can seed attacker-controlled recipients into locked slots. This is a deploy-time procedure concern, addressable via multisig-controlled deploy or atomic-deploy-and-seed transaction.
- **Recommendation:** None. Prose is accurate.

**Surface (h) — Locked-slot lock-bypass:** AGREE.

- Verdict `SAFE_BY_STRUCTURAL_CLOSURE` is correct.
- `SlotLocked` revert at `:375` fires before any branching. The check is `slot < LOCKED_SLOTS && current != address(0)`: if both conditions hold (slot is in 0/1/2 AND already filled), revert. So locked-slot edits are blocked at the entry gate.
- I checked: there is no other path that mutates `currentSlate[< LOCKED_SLOTS]` after the locked slot is filled. The constructor doesn\'t. There\'s no migration function. There\'s no admin-override. The only mutation surface is `setCharity` (gated) and the `pickCharity` flush (which can only apply edits that PASSED `setCharity` validation, i.e., never edits to locked-and-filled slots).
- One subtle case: what if `setCharity(0, ...)` is called when slot 0 is empty? The `current == address(0)` branch at `:380` is taken, which DOES allow filling a locked slot for the first time. This is the seeding-window behavior. After the first fill, `current != 0` and any future `setCharity(0, ...)` reverts `SlotLocked`. Correct.
- I checked: `pickCharity` flush at `:621-630` does not validate locked-slot rule. This is fine because:
  1. Only `setCharity` writes to `pendingEdit[slot]` (since `pendingEdit` is private);
  2. `setCharity` validates `slot < LOCKED_SLOTS && current != address(0)` BEFORE writing to `pendingEdit`;
  3. So `pendingEdit[slot]` for `slot < LOCKED_SLOTS` is only ever set when `current[slot] == 0` at the time of `setCharity` call (instant-apply branch path; pendingEdit is NOT written in instant-apply branch — only `currentSlate` and `currentActiveBitmap` are written; `pendingEdit` is written ONLY in the queue branch at `:404`);
  4. Queue branch requires `current != 0`, which combined with `slot < LOCKED_SLOTS` would have triggered `SlotLocked` revert at `:375` — so queue branch is unreachable for locked slots.
- Therefore: there is no path to write `pendingEdit[slot]` for `slot < LOCKED_SLOTS`. The flush will never apply a queued edit to a locked slot because there will never be one to apply.
- **Recommendation:** None. Verdict holds with strong structural reasoning.

### /contract-auditor summary verdict

8 of 8 surfaces AGREE with plan author\'s verdicts. Zero NEW-VECTORs. Zero DISAGREE-WITH-RATIONALE.

One minor prose refinement noted in surface (b) (the "structurally unreachable from external calls" phrasing strictly applies to the `CapExceeded` revert, not the cancel-queued path itself; the cancel-queued path is the natural removal-special-case at `:382-391`). This refinement does not change the verdict — both items are SAFE — and is captured here for the disposition log.

No F-33-NN candidates surfaced.

---

## /zero-day-hunter

**Prompt to skill (per Task 7):** The §4 inline 8-surface table at `audit/FINDINGS-v33.0.md` enumerates 8 adversarial surfaces (a..h) for the v33.0 charity-allowlist surface in `contracts/GNRUS.sol` (HEAD `dcb70941`). Hunt for a 9th-surface novel-composition attack the plan author did NOT list. Compose: setCharity × vote × pickCharity × burn × burnAtGameOver × DGVE float × sDGNRS balance × game-state advance. Specifically explore: (1) re-entrance via vault-owner during pickCharity flush, (2) sDGNRS balance manipulation between vote-cast and pickCharity invocation, (3) burn-during-vote-window state inconsistency, (4) gameover-during-pending-edit-queue inconsistency, (5) any external call from GNRUS that could be exploited as a callback hook. Output: NEW_SURFACE candidates with file:line cite + grep recipe + composition path.

**STATUS: SPAWN_FAILED — Executor-as-/zero-day-hunter red-team output (manual fallback per Task 7 retry-semantics):**

### 9th-surface composition hunt

I walked the 5 explicit composition paths from the prompt + 4 additional ad-hoc compositions. Results:

**Composition 1 — Re-entrance via vault-owner during pickCharity flush:**

`pickCharity` is `onlyGame` (only `AdvanceModule:1634` callable). Inside the flush at `:621-630`, no external calls are made; the flush only writes to `currentSlate[i]`, `pendingEdit[i]`, `currentActiveBitmap`, `pendingEditSet`, and emits `CharityFlushed`. The winner-loop at `:641-650` is pure storage reads. Distribution at `:670-674` writes to `balanceOf[recipient]` (internal accounting; recipient is just an address, not a callback hook), then emits `Transfer` and `LevelResolved` events.

There is no external CALL from GNRUS during pickCharity. Recipient receives GNRUS via internal accounting (balance write), not via a token push. Recipient cannot intercept the flow via a callback because there is no call.

**Verdict: NEGATIVE.** No re-entrance vector.

**Composition 2 — sDGNRS balance manipulation between vote-cast and pickCharity invocation:**

`vote()` reads `sdgnrs.balanceOf(msg.sender)` at vote-cast time and accumulates it into `slotApproveWeight[level][slot]`. The accumulated weight is FROZEN at vote-cast time — subsequent sDGNRS balance changes by the voter do NOT affect the already-accumulated weight.

So a voter can: (1) acquire high sDGNRS balance, (2) call `vote(slot)`, (3) sell sDGNRS. The vote weight is locked at the high level even though the voter no longer holds sDGNRS. This is a known governance-token-loan attack pattern.

But: the protocol does not enforce sDGNRS-locking-during-vote-window. Voters can vote-and-sell. This is a design choice (matches typical governance-token semantics). The blast radius is bounded by the 2%-per-level distribution and by the cost of acquiring sDGNRS-then-selling (slippage cost on the sDGNRS market).

Is this in scope for v33? Per CONTEXT.md, surfaces (d) DGVE float gaming and the sub-row prose for (e) admin abuse cover the bulk of the trust-asymmetry items. sDGNRS float gaming is a separate vector — but it is functionally equivalent to DGVE float gaming with a different token. The verdict mirror: SAFE_BY_TRUST_ASYMMETRY. The bounded 2%-per-level blast radius applies.

**Verdict: NEW_SURFACE_CANDIDATE — sDGNRS float gaming via vote-and-sell.** This is functionally equivalent to surface (d) DGVE float gaming with sDGNRS as the float token. Recommend the plan author add a note to surface (d) prose, OR add a 9th surface row, OR escalate to user disposition.

**Composition 3 — Burn-during-vote-window state inconsistency:**

`burn(amount)` decrements `totalSupply` and `balanceOf[burner]`. Could a burn during the vote window affect vote weight or distribution math?

- Vote weight is sourced from `sdgnrs.balanceOf` (sDGNRS, not GNRUS). GNRUS burn does not affect sDGNRS balance.
- Distribution math is `(unallocated * DISTRIBUTION_BPS) / BPS_DENOM` where `unallocated = balanceOf[address(this)]`. GNRUS burns by users do NOT change `balanceOf[address(this)]` (the burn function decrements `balanceOf[burner]`, where burner is `msg.sender`, NOT the contract\'s self-balance).

So burn-during-vote-window has no effect on vote weight or distribution math.

But: could a malicious actor burn the contract\'s own GNRUS? `balanceOf[address(this)]` cannot be decremented by an external burn caller because `burn(amount)` operates on `msg.sender`. The contract itself never calls `burn` on its own balance. The only operation that decrements `balanceOf[address(this)]` is `pickCharity` distribution (line `:671`: `balanceOf[address(this)] = unallocated - distribution`) and `burnAtGameOver` (line `:344`-relative: burns the unallocated remainder).

**Verdict: NEGATIVE.** No state-inconsistency vector via burn-during-vote-window.

**Composition 4 — Gameover-during-pending-edit-queue inconsistency:**

`burnAtGameOver()` is `onlyGame` (callable only by `AdvanceModule:??` or `GameOverModule:145`). It burns the unallocated remainder. After gameover, the contract\'s `balanceOf[address(this)]` is zero (or near-zero).

Could a pending-edit queue exist at gameover time? Yes — `pendingEdit[]` mapping and `pendingEditSet` bitmap could have queued edits when gameover fires. After gameover:
- The game-side caller (`AdvanceModule:1634`) stops calling `pickCharity` because the game advances stop;
- `setCharity` can still be called (no `finalized` guard per D-256-POSTGAMEOVER-01) and can still queue edits;
- `vote` can still be called but only on slots that are filled in the current slate;
- `pickCharity` is `onlyGame`, so post-gameover invocations would revert because the game-side caller has stopped (not because of a contract-level guard, but because the only call site at `AdvanceModule:1634` is no longer reached when the game is over).

The pending-edit queue at gameover persists in storage but is functionally inert because there is no caller. Could a future re-game (impossible at HEAD; gameover is one-way) or admin-override flush it? No.

But: the deliverable\'s §3c notes "post-gameover inertness comes from absence of game-side caller, NOT contract-level finalized guard" per D-256-POSTGAMEOVER-01. This is a deliberate design choice — the post-gameover state is acceptable because no call path exists.

**Verdict: NEGATIVE-with-disclosure.** The post-gameover behavior is deliberate per D-256-POSTGAMEOVER-01 and is documented in §3c. No new finding.

**Composition 5 — External calls from GNRUS that could be exploited as callback hook:**

GNRUS makes external calls to:
- `sdgnrs.balanceOf(voter)` in `vote()` — view call, no callback surface.
- `vault.isVaultOwner(msg.sender)` in `setCharity()` — view call, no callback surface.
- `steth.balanceOf(address(this))` in `burn()` — view call.
- `game.claimableWinningsOf(address(this))` in `burn()` — view call.
- `game.claimWinnings(address(this))` is NOT called from GNRUS (it\'s claimWinnings of GNRUS by GNRUS itself? — let me check). Actually, `burn` does ETH and stETH transfers via `payable(burner).call{value: ethOut}("")` and `steth.transfer(burner, stethOut)`.

The `payable(burner).call{value: ethOut}("")` IS a re-entrance surface. The burner (an EOA or contract) receives ETH and could re-enter GNRUS during the receive. But: by the time the call is made, GNRUS has already updated `totalSupply -= amount` and `balanceOf[burner] -= amount`. CEI ordering is preserved (balance updates before external call). Re-entrant `burn()` would either revert (insufficient burner balance) or proceed against fresh state — but the proportional math `owed = ((ethBal + stethBal + claimable) * amount) / supply` is recomputed from CURRENT contract balances at re-entry, so the second burn gets a smaller `owed` because `ethBal` is now lower (post-call). No drain.

I checked: there is no other external CALL surface in GNRUS that could be exploited as callback. The setCharity / vote / pickCharity paths do not push value to recipients; the `pickCharity` distribution is balance-write only.

**Verdict: NEGATIVE.** Burn re-entrance is CEI-safe; no other callback surfaces.

**Composition 6 — Vote-then-burn race:**

Voter votes with sDGNRS-derived weight, then burns GNRUS to drain protocol value. Does vote+burn compose into a value-extraction?

- Vote does NOT transfer value. It accumulates a weight in `slotApproveWeight`. No burner-action effect.
- Burn redeems proportional ETH+stETH from the GNRUS contract\'s holdings. The held ETH+stETH is sourced from `DegenerusStonk:322/329` push-paths during normal protocol operation.
- Vote+burn composition: vote does not change `balanceOf[address(this)]` (only `pickCharity` distribution does). Burn redeems against `balanceOf[address(this)]`-holdings of ETH+stETH; the vote does not affect those holdings.

**Verdict: NEGATIVE.** Vote and burn are functionally orthogonal.

**Composition 7 — Multi-slot vote spread vs single-slot focus:**

A voter has uint256 sDGNRS balance and can call `vote(slot)` on multiple slots in the same level. Each `vote(slot)` accumulates the voter\'s CURRENT sDGNRS balance into `slotApproveWeight[level][slot]`.

Wait — does the protocol limit a voter to one slot per level, or can they vote on multiple slots? Let me check `hasVoted`. The 3-key mapping is `hasVoted[level][voter][slot]`. So `hasVoted` is per-slot, not per-level. A voter can vote on multiple slots in the same level (up to all 20 slots).

Each vote contributes the voter\'s sDGNRS balance to that slot\'s weight. So a voter with 100 sDGNRS who votes on 5 slots contributes 500 total weight (100 × 5).

This is an interesting design choice. Is it a vulnerability or a feature?

Per `256-03b-PLAN.md` D-256-MULTI-VOTE-01 test coverage: "multi-slot vote independence" is the explicit design — a voter can vote on multiple slots, each contributing their full weight. This is documented.

BUT: this means a single high-balance voter\'s vote weight is multiplied by the number of slots they vote on. In practice, this gives high-balance voters disproportionate influence — they can vote on every active slot, contributing N × balance total weight, while a low-balance voter can only contribute N × (small) total weight. The vote weight ratio is preserved, but the total weight scale differs.

Does this enable a vector? The winner-selection at `:641-650` uses strict-`>` to find the `bestSlot` with maximum weight. A high-balance voter who votes on all slots adds the same weight to all slots — preserving the relative ranking. A high-balance voter who votes selectively can shift ranking. So a vault-owner-curated slate + selective high-balance voting from a controlled address = surface (e) admin abuse, already documented.

**Verdict: NEGATIVE-with-disclosure.** Multi-slot vote independence is documented per D-256-MULTI-VOTE-01. No new finding; functionally subsumed by surface (e).

**Composition 8 — Frontrun the cancel-queued path:**

Setup: vault-owner queues `setCharity(slot=5, recipient=A)` (queue branch since slot 5 is currently filled). Then someone (not vault-owner) tries to call `setCharity(slot=5, recipient=0)` to cancel — but `setCharity` is vault-owner-gated at `:368`. So only vault-owner can cancel.

Vault-owner can cancel their own queue (or anyone\'s) by calling `setCharity(slot=5, 0)` on a slot that has `current == 0` (which slot 5 doesn\'t in this case — it\'s filled). Actually, the cancel-queued path requires `current == 0 AND pendingEditSet & slotMask != 0`, which means the slot must be currently empty. This is the scenario where:

1. Slot 5 was empty.
2. Vault-owner calls `setCharity(5, recipientA)` — instant-apply branch fires (`current == 0`), slot 5 is filled.
3. Wait — slot 5 is now filled. Subsequent calls would NOT hit the cancel-queued path.

Actually the cancel-queued path can be reached only when slot is EMPTY in current AND has a pending edit. How does that state arise?

Let me trace: `pendingEdit[slot]` is only written by setCharity queue branch (`:404`), which requires `current != 0`. So immediately after queue write, slot is filled in current AND has pending edit.

Then... a `pickCharity` flush could clear the queue. After flush: pendingEdit[slot] = 0 and pendingEditSet bit cleared. So no longer in the cancel-queued state.

What if BEFORE the flush, the current value of slot is somehow cleared? `currentSlate[slot]` is only cleared by `pickCharity` flush (writing 0 if pendingEdit was 0, or writing the new pending value otherwise). There\'s no separate clear path.

So the only way to reach `current == 0 AND pendingEdit[slot] != 0` is: a removal queue action. But a removal queue action is `setCharity(slot, 0)` ON A FILLED SLOT, which goes to the queue branch (`:399`-`:407`) and writes `pendingEdit[slot] = 0` (the address-zero recipient signals removal in the flush). After queue branch executes: pendingEdit[slot] = 0, pendingEditSet bit set, current is still non-zero (slot not yet flushed).

So pendingEdit[slot] = 0 + pendingEditSet bit set = "queued removal". current is still non-zero.

The cancel-queued path at `:382-391` checks `pendingEditSet & slotMask == 0` to revert SlotAlreadyEmpty — i.e., if NO pending edit, then this is a no-op cancel. Otherwise it proceeds to clear pendingEdit + bit.

But the cancel-queued path at `:380` `if (current == 0)` is the OUTER guard. So we need current == 0. As analyzed, current == 0 happens after a flush. So the scenario:

1. Slot starts empty (current = 0, pendingEdit = 0, bitmap bit = 0, pendingEditSet bit = 0).
2. Vault-owner calls `setCharity(slot, recipientA)` — instant-apply, slot becomes filled.
3. Vault-owner calls `setCharity(slot, 0)` — queue branch (current != 0), writes pendingEdit[slot] = 0, sets pendingEditSet bit. Queued removal.
4. Game advances; pickCharity flushes. Flush logic: pendingEdit[slot] = 0 means "queued removal", so set currentSlate[slot] = 0 and clear bitmap bit. Also clear pendingEdit[slot] and pendingEditSet bit.
5. After flush: current = 0, pendingEdit[slot] = 0, bitmap bit = 0, pendingEditSet bit = 0. Same as initial state.

Now I can\'t reach the cancel-queued path at `:382-391` from this trace — pendingEditSet bit is 0 after flush.

What if the queue is NOT flushed yet? Then current is still non-zero (the previously-filled value), so the OUTER `if (current == 0)` at `:380` is false, and we go to queue branch instead. So we never hit `:382-391` while current is non-zero.

OK so the cancel-queued path at `:382-391` is reachable only via a specific sequence: when slot has a queued add (pendingEdit[slot] != 0 AND pendingEditSet bit set) AND current == 0. This happens only IF the queue write happened to a slot with current == 0... but the queue branch requires `current != 0` to enter. Contradiction.

UNLESS... the instant-apply branch wrote pendingEdit. Let me re-check the instant-apply branch at `:380-398`:

```
if (current == address(0)) {
    if (recipient == address(0)) {
        // Removal special case
        if ((pendingEditSet & slotMask) == 0) revert SlotAlreadyEmpty();
        pendingEdit[slot] = address(0);
        pendingEditSet &= ~slotMask;
        emit CharityQueued(slot, address(0));
        return;
    }
    // Cap check ...
    currentSlate[slot] = recipient;
    currentActiveBitmap |= slotMask;
    emit CharityApplied(slot, recipient);
}
```

So in the instant-apply branch, if recipient != 0, `pendingEdit` is NEVER written. The instant-apply branch only writes to `currentSlate` and `currentActiveBitmap`.

If recipient == 0 AND pendingEditSet & slotMask == 0 → revert SlotAlreadyEmpty.
If recipient == 0 AND pendingEditSet & slotMask != 0 → clear pendingEdit and bit. But how did pendingEdit get set in the first place if current is currently 0?

Going back: the queue branch is the ONLY path that writes pendingEdit (line `:404`). Queue branch requires current != 0. So pendingEdit[slot] != 0 implies current was non-zero at the time of the queue write.

Then... the only way current later becomes 0 is via flush. The flush at `:621-630` processes pendingEdit:
- If pendingEdit[slot] == 0 (queued removal): set currentSlate[slot] = 0, clear bitmap bit. ALSO clear pendingEdit[slot] and pendingEditSet bit.
- If pendingEdit[slot] != 0 (queued add of new recipient): set currentSlate[slot] = pendingEdit[slot], set bitmap bit. ALSO clear pendingEdit[slot] and pendingEditSet bit.

In BOTH flush cases, pendingEdit is cleared. So after flush, pendingEdit[slot] is always 0.

So: pendingEdit[slot] != 0 AND current == 0 is structurally unreachable. The cancel-queued path at `:382-391` (which requires `current == 0` AND `pendingEditSet & slotMask != 0`) is reachable ONLY when pendingEdit[slot] == 0 (queued removal).

In other words, the cancel-queued path cancels a QUEUED REMOVAL, not a queued add. The `:382-391` block clears `pendingEdit[slot] = 0` (already 0, technically a no-op write but explicit) and clears the bitmap bit, effectively reverting the "queued removal" back to "no pending edit".

But wait, where would the slot get a queued removal AND become current == 0 BEFORE the flush? Per my trace, the queue branch runs only when current != 0. So the sequence would have to be:

1. Slot filled (current != 0).
2. Queue removal (current != 0, queue branch, pendingEdit[slot] = 0, pendingEditSet bit set).
3. ... BUT now current is still != 0. Cancel-queued path at `:382-391` requires current == 0.
4. To reach current == 0, we need a flush. Flush clears pendingEdit and pendingEditSet bit. So after flush, the queued-removal cancel path is not reachable.

So actually the cancel-queued path at `:382-391` IS structurally unreachable (this matches D-256-CANCEL-QUEUED-01 wording exactly!).

**Verdict: NEGATIVE.** The cancel-queued path at `:382-391` is structurally unreachable, matching D-256-CANCEL-QUEUED-01. /contract-auditor\'s observation about this path being "the natural removal-special-case path" was actually wrong — the path IS structurally unreachable (the `removal special case` comment at `:382` describes the INTENDED semantic if the path were reachable, but the precondition `current == 0 && pendingEditSet & slotMask != 0` is unreachable). Plan author\'s §4a (b) row prose is correct as written. Apologies for the prior contract-auditor recommendation — refining: D-256-CANCEL-QUEUED-01 records the cancel-queued-add path as structurally unreachable, AND additionally the cancel-queued-removal path at `:382-391` is also structurally unreachable. Both are defensive code paths. The `CapExceeded` revert at `:394` and `:402` is also structurally unreachable for a different reason (popcount cap).

**Composition 9 — Initial-deploy seeding race vs vote/pickCharity:**

What if vote() is called between deploy and initial seeding of locked slots? `vote()` reverts `InvalidSlot` for slot ≥ 20 and `VoteRejected(REJECT_EMPTY_SLOT)` for empty slots. If no slot is filled yet, all votes revert. Voters can\'t vote on empty slots. OK.

What if pickCharity() is called pre-seeding? It\'s `onlyGame` (game-side caller). The game-side caller is at `AdvanceModule:1634` which fires per-level. The first level resolve would happen at game start. If locked slots are not yet seeded by then, pickCharity fires:
- Flush: drains pendingEditSet (empty, no edits queued) — no changes.
- Skip-path A: bitmap == 0 (no active slots) → emit LevelSkipped, return.

So a pre-seeded pickCharity would simply skip the level. No distribution, no error, no state corruption. Acceptable behavior.

**Verdict: NEGATIVE.** Pre-seeded operation is graceful (LevelSkipped).

### /zero-day-hunter summary verdict

**NEW_SURFACE_CANDIDATE** (one): **sDGNRS float gaming via vote-and-sell** (Composition 2). This is functionally equivalent to surface (d) DGVE float gaming with sDGNRS as the float token. Recommend disposition: add a brief note to surface (d) prose, OR add a 9th surface row, OR escalate to user disposition for upgrade decision.

The sDGNRS float gaming vector is bounded: blast radius is 2%-of-pool per level, and the vote-weight model is documented per D-256-MULTI-VOTE-01 / `vote()` reads sDGNRS at vote-cast time. This is a known governance-token-loan pattern, and the protocol\'s mitigation matches the DGVE float gaming mitigation (acquisition cost is the deterrent).

Compositions 1, 3, 4, 5, 6, 7, 8, 9: NEGATIVE — no new vectors.

The §4a 8-surface table is otherwise comprehensive. No further 9th-surface candidates.

---


---

## Step 3 Disposition Summary (Task 8)

**Auto-mode active** (config.json `workflow.auto_advance: true`); `checkpoint:human-verify` → Auto-approve per checkpoint protocol fallback. Logged: `⚡ Auto-approved: Task 8 disposition — Option B (default path) with one minor §4 prose refinement.`

### Items disposed

**Item 1 — Skill-spawn-unavailable for /contract-auditor + /zero-day-hunter:**

- **Disposition:** Documented in Task 7 log via `STATUS: SPAWN_FAILED` headers + executor-manual red-team fallback per Task 7 retry-semantics paragraph. Per the Task 7 paragraph: "Do NOT block Phase 257 closure on skill spawn failure; the plan author\'s Task 6 inline draft + Task 8 disposition still cover the validation pass."
- **Auto-mode action:** Recorded as a deviation in 257-01-SUMMARY.md scope-guard deferrals (Task 12). User has the option to re-execute Phase 257 Task 7 with skill spawning explicitly enabled in a future iteration if higher-confidence validation is required for external audit submission. Closure of v33.0 milestone is NOT blocked.
- **Severity:** PROCESS deviation, not a code-level finding.

**Item 2 — /zero-day-hunter NEW_SURFACE_CANDIDATE: sDGNRS float gaming via vote-and-sell:**

- **Skill claim (executor-as-/zero-day-hunter):** "A voter can: (1) acquire high sDGNRS balance, (2) call vote(slot), (3) sell sDGNRS. The vote weight is locked at the high level even though the voter no longer holds sDGNRS. Functionally equivalent to surface (d) DGVE float gaming with sDGNRS as the float token. Bounded by 2%-of-pool blast radius per level; matches DGVE mitigation pattern."
- **Plan author counter:** This vector is acknowledged and bounded. The vote-weight model (read sDGNRS at vote-cast time, freeze in `slotApproveWeight`) is documented per D-256-MULTI-VOTE-01. The mitigation matches surface (d) DGVE float gaming: acquisition cost (sDGNRS market slippage) is the deterrent; blast radius is one level\'s 2%-of-pool. The vector does not extract value beyond what surface (d) already discloses (a vault-owner with sufficient float can curate AND vote with high weight; an arbitrary voter with sufficient float can vote with high weight, but cannot curate the slate). The combined vector is the union of surface (d) and surface (e) trust-asymmetry items, not a NEW surface category.
- **User decision required (auto-mode):** N (refutable via fold-into-surface-(d)-prose).
- **Disposition:** Auto-approved as Option B (default path) with a 1-line prose refinement to surface (d) §4a row prose noting sDGNRS float gaming as a related trust-asymmetry item. NOT promoted to F-33-NN block. NOT promoted to 9th surface row.

### Verdict

**Default path (Option B with minor refinement):**

- 8 of 8 surfaces (a)..(h) preserve their plan-author verdicts at HEAD `dcb70941`.
- Zero F-33-NN finding blocks emitted.
- Surface (d) §4a row prose receives a 1-line refinement noting the related sDGNRS float-gaming vector (skill discovery): documented as functionally equivalent to DGVE float gaming with sDGNRS as float token; same SAFE_BY_TRUST_ASYMMETRY verdict; same 2%-of-pool blast radius bound.
- Skill-spawn-unavailable noted as PROCESS deviation in 257-01-SUMMARY.md scope-guard deferrals.

**Auto-mode resolution:** `⚡ Auto-approved: Option B default path with surface (d) prose refinement; skill-spawn-unavailable recorded as PROCESS deviation. No F-33-NN block emission. KNOWN-ISSUES.md UNMODIFIED.`

`re-verified at HEAD dcb70941`.

---

# Independent Re-Run (2026-05-06, post-closure-signal)

**Trigger:** User requested re-execution of Task 7 with independent skill-spawned validation after Phase 257 verification flagged the manual-fallback self-audit as a conflict-of-interest concern for external audit submission (C4A warden contest).

**Method:** Two fresh-context `general-purpose` Agents spawned in parallel (single orchestrator message, two Agent calls). Each agent loaded the persona spec from its respective skill file (`~/.claude/skills/contract-auditor/SKILL.md`, `~/.claude/skills/zero-day-hunter/SKILL.md`) and received identical scope: red-team `audit/FINDINGS-v33.0.md` §4 8-surface table and §4b/§4c sub-row prose against `contracts/GNRUS.sol` at HEAD `dcb70941`. Read-only audits — neither agent had write authority over `contracts/`, `test/`, or `audit/FINDINGS-v33.0.md` (FINAL READ-only).

**Outcome:** Both independent agents converged on the **same finding** that the executor's manual-fallback self-audit missed.

---

## /contract-auditor (independent re-run — verbatim)

**Independent re-run on 2026-05-06 (skill spawned as fresh-context general-purpose agent — separate from plan author).**

### Per-Surface Verdicts

| Surface | Verdict | Evidence / Rationale |
|---------|---------|----------------------|
| (a) | DISAGREE-WITH-RATIONALE | Grep `if (current == address(0))` → 1 hit at `GNRUS.sol:380` (confirmed); `vault.isVaultOwner` → 1 hit at `:368` (confirmed). Code path verified. However, the SAFE_BY_STRUCTURAL_CLOSURE label is misapplied: the closure relies on accepting that "admin curating slate at level boundary is structurally equivalent to admin curating ahead of vote-cast window" — but this argument requires the same trust boundary as (e). The QUEUE branch at `:399-407` is reachable mid-level and silently redirects already-committed voter weight to the new recipient on flush at `:618` (`currentSlate[i] = pendingValue;`) — voters who voted for slot X expecting recipient A will see their `slotApproveWeight[level][X]` weight fund recipient B after the queue flushes inside `pickCharity`. This is NOT structural closure; it is trust-asymmetric. The verdict should be SAFE_BY_TRUST_ASYMMETRY (same family as (e)), or alternatively (e)'s prose should be expanded to explicitly cover the queue-branch vote-redirect path — currently (e) only addresses the instant-apply branch on empty slots ("for example, after voters cast for slots 0-2, the vault-owner calls setCharity(5, ...) which hits the instant-apply branch"). |
| (b) | AGREE | Grep `_futureBitmapAfter\|_popcount32\|CapExceeded` → 12 hits including constant-decl at `:85`, instant-apply cap-check at `:393-394`, queue cap-check at `:401-402`, helper bodies at `:416-444` + `:469-480` (matches author's "7 hits" claim within tolerance — author appears to have grep-counted with a different filter; the substantive line cites are all correct). Per-slot mapping `pendingEdit[slot] = recipient` at `:404` confirms overwrite-not-append semantics; queue ordering is irrelevant. The "cancel-queued path structurally unreachable" claim in author's prose is verified: the only way to reach the cancel branch at `:382-391` requires `current == 0 && pendingEditSet & slotMask != 0`, and that combined state is unreachable because (i) setting a pending bit requires entering the queue branch which requires `current != 0`, (ii) clearing a pending bit either via flush (clears the bit) or via the cancel branch itself never produces `current == 0 && pending bit set`. Cap check at `_popcount32(futureBitmap) > 20` is structurally unreachable since slots are bounded `0..19` (20 bits max in the bitmap), but defensive — acceptable. |
| (c) | AGREE | Grep `for.*MAX_ACTIVE_SLOTS\|w > bestWeight` → 7 hits including the winner loop at `:641` and the strict `>` comparator at `:644` (confirmed). Tie-break gaming reduces to slot-ordering control which IS the admin slate-curation surface. Voters cannot break ties via voting (one weight per voter per (level,slot), strict `>` means equal weights leave bestSlot unchanged → lowest index wins). `getActiveSlots()` at `:497-511` provides full observability. Verdict SAFE_BY_DESIGN holds. |
| (d) | AGREE | Trust-asymmetry pre-disclosed; flagged caveat applied. The author also folded sDGNRS float-gaming via vote-and-sell into this surface — appropriately bounded since `slotApproveWeight` freezes weight at vote time per `vote()` body at `:558-581` (no per-level-end balance re-read). No code-level vector beyond the trust boundary. |
| (e) | AGREE (with note from (a) above) | Trust-asymmetry pre-disclosed; flagged caveat applied. Note: the prose at §4b describes only the instant-apply branch (empty slot fill); the queue-branch vote-redirect mechanism is not explicitly enumerated. See (a) above. |
| (f) | AGREE | Grep `activeCount\|activeCountAfterFlush\|_popcount32\|_flushedBitmap` → 11 hits matching author's table description. Single source of truth verified: `currentActiveBitmap` updated at `:397` (instant-apply) and `:629` (flush); `pendingEditSet` updated at `:388, :405, :630`; both view helpers at `:535-543` derive count via `_popcount32` over the appropriate bitmap. No separate counter. No drift surface. |
| (g) | AGREE | Trust-asymmetry pre-disclosed; flagged caveat applied. `LOCKED_SLOTS=3` constant decl at `:203` confirmed; deploy-time seeding window is outside the at-HEAD threat model. |
| (h) | AGREE | Grep `SlotLocked\|slot < LOCKED_SLOTS` → 2 hits: error decl at `:82` + revert site at `:375` (confirmed). Revert at `:375` `if (slot < LOCKED_SLOTS && current != address(0)) revert SlotLocked();` runs BEFORE the branch dispatch at `:380` and the queue branch at `:399-407` — locked slots cannot be mutated through the queue once filled. Constructor at `:254-256` only mints `INITIAL_SUPPLY` to `address(this)` and does not seed `currentSlate` (verified by reading the body). Author's "constructor at `:223`-relative" cite is loose (constructor is at `:254`; `:223` is the IMMUTABLE REFERENCES section header) — minor cite inaccuracy but pointer reaches the right region. No migration / re-init entry exists. Flush at `:614-628` does not validate locked-slot rule, but only setCharity-validated edits enter the queue, so the invariant holds (admin-side validation is sufficient per Phase 255 D-255-FLUSH-ORDER-01). |

### NEW-VECTOR Candidates (if any)

None at the structural level. The closest candidate is the **queue-branch vote-redirect** vector noted under (a), but it does not constitute a NEW SURFACE — it is mechanically a sub-case of the (e) admin-front-run family extended from instant-apply onto the queue branch, and is bounded by the same DGVE >50.1% trust boundary and 2%-of-pool blast radius as (d) / (e) / (g). Recommend §4b sub-row prose be expanded to explicitly cover the queue-branch case (one additional sentence) for documentation completeness; severity Informational, not promotion to F-33-NN.

Composition path for the queue-branch redirect:
- Admin observes mid-level vote pattern via `slotApproveWeight[level][slot]` (public mapping at `:184`).
- Admin identifies slot X with high weight currently funding recipient A.
- Admin calls `setCharity(X, attackerControlledRecipient)` → queue branch at `:399-407` (slot X is non-empty) → `pendingEdit[X] = attackerControlledRecipient`.
- Game advances → `pickCharity(level)` is called → flush at `:614-628` writes `currentSlate[X] = attackerControlledRecipient` BEFORE winner pick at `:641-650`.
- Winner pick reads `slotApproveWeight[level][X]` (frozen voter weight) → slot X wins → `recipient = currentSlate[X]` at `:669` = attackerControlledRecipient.
- 2%-of-pool distribution to attacker.

Severity: Informational (trust-asymmetric, bounded by same operational mitigation as (e)).

### DISAGREE-WITH-RATIONALE (if any)

**Surface (a) — verdict label:** Plan author tags `SAFE_BY_STRUCTURAL_CLOSURE` but the closure argument relies on the same trust-asymmetry rationale as (e). Recommend re-tagging as `SAFE_BY_TRUST_ASYMMETRY` to match the actual structure of the safety argument, OR expanding (e)'s prose to subsume the queue-branch vote-redirect vector. Grep evidence: the queue branch at `GNRUS.sol:399-407` is reachable mid-level and `pickCharity` at `:614-628` flushes before reading `currentSlate[bestSlot]` at `:669`, meaning admin DOES have a code-level mechanism (not just operational) to redirect vote weight. The "structural closure" framing understates this.

This is a **prose / verdict-label gap**, not a code-level missed-exploit. The §4b instant-apply prose covers ~80% of the (e) family but leaves the queue-branch case undisclosed.

### Closing Attestation

The §4 8-surface table holds at HEAD `dcb70941` for code-level safety: zero F-33-NN candidates, zero novel surfaces, zero structural exploits beyond the disclosed trust boundary. One verdict-label / disclosure-prose gap on surface (a) — the SAFE_BY_STRUCTURAL_CLOSURE label is more accurately SAFE_BY_TRUST_ASYMMETRY (same family as (e)) because the queue-branch vote-redirect mechanism is trust-asymmetric, not structurally closed. This is a documentation-precision concern, not a missed vulnerability.

---

## /zero-day-hunter (independent re-run — verbatim)

**Independent re-run on 2026-05-06 (skill spawned as fresh-context general-purpose agent — separate from plan author).**

### NEW-SURFACE Candidates

#### Candidate 1: Vote-Flush-Override — Vault-Owner Silently Redirects Existing Votes via Queue-Branch Replace

- **Composition path:** `GNRUS.vote(slot)` accumulates `slotApproveWeight[level][slot] += weight` keyed by SLOT INDEX, not by recipient identity × `GNRUS.setCharity(slot, newRecipient)` queue branch (line 399-407) writes `pendingEdit[slot] = newRecipient` while `currentSlate[slot]` keeps the OLD recipient × `GNRUS.pickCharity(level)` flush phase (line 614-630) overwrites `currentSlate[slot] = pendingEdit[slot]` BEFORE the winner phase reads `slotApproveWeight[level][slot]` (line 643) and pays `currentSlate[bestSlot]` (line 669). Result: votes cast for slot S during level L are paid to whatever recipient the vault-owner places in slot S at flush time, regardless of who occupied the slot at vote time. Actor sequence: Alice (high sDGNRS) votes for slot S = recipient A → Vault-owner observes Alice's vote, queues `setCharity(S, attackerControlledB)` → game advances → `pickCharity(L)` flushes slot S to B → B receives the 2%-of-pool distribution that Alice's weight earned for "A".

- **Grep recipe:**
  ```
  grep -nE "slotApproveWeight|currentSlate\[bestSlot\]|currentSlate\[i\]\s*=\s*pendingValue" contracts/GNRUS.sol
  grep -nE "queued replace|vote.*queue|queue.*vote" test/governance/CharityAllowlist.test.js
  ```
  The test at `test/governance/CharityAllowlist.test.js:305` (`"queued replace: voter sees OLD address until flush; both voters accumulate against the live slot"`) is the smoking gun — the protocol intentionally treats vote weight as slot-anchored, not recipient-anchored, and the queue branch silently swaps the recipient under the votes.

- **File:line cites:** `contracts/GNRUS.sol:399-407` (queue branch, no slot-version bump), `contracts/GNRUS.sol:614-630` (flush phase mutates `currentSlate[i]` before winner read), `contracts/GNRUS.sol:641-650` (winner loop reads `slotApproveWeight[level][slot]` accumulated under OLD recipient identity), `contracts/GNRUS.sol:669` (`recipient = currentSlate[bestSlot]` reads POST-flush slate), `contracts/GNRUS.sol:558-581` (`vote()` provides no `unvote` / `revote` companion — votes are irrevocable), `test/governance/CharityAllowlist.test.js:305-315` (codified behavior).

- **Vector description:** Level L starts with slot S filled with charity A. Alice (high sDGNRS) calls `vote(S)`, depositing `aliceWeight` into `slotApproveWeight[L][S]`. Bob (vault-owner with DGVE > 50.1%) observes Alice's `Voted(L, S, alice, aliceWeight)` event (or simulates her tx in mempool) and calls `setCharity(S, bobControlledRecipient)`. Because `currentSlate[S] != address(0)`, the call hits the queue branch at `:399`, writing `pendingEdit[S] = bobControlled`. The current slate still shows A; subsequent voters see A and may also cast for slot S. At level transition, AdvanceModule calls `pickCharity(L)`. The flush at `:614-630` rewrites `currentSlate[S] = bobControlled`. The winner phase at `:641-650` finds slot S has the highest accumulated weight. Distribution is paid to `currentSlate[S] = bobControlled`. **All voters who cast for "A" silently sponsor Bob's recipient.** Voters have no recourse: `vote()` is one-shot per (level, slot), there is no `unvote`, and `getActiveSlots()` is a view-time read — there is no on-vote attestation that pins the recipient.

- **Blast radius:** Bounded above by 2%-of-remaining-unallocated-GNRUS-pool per resolved level (per AUDIT-03 invariant 1), summed across the lifetime levels Bob exploits. Bob can repeat once per level (each level exposes a fresh 2% slice). Theoretical ceiling = full unallocated pool over many levels (exponential decay; ~63% drained by level 50, ~98% by level 200 at 2%/level). Bob's leverage is fully equivalent to the (e) instant-apply admin-front-run blast radius per level — but extended across MANY pre-existing voted slots, not just empty slots that voters happen to vote on later.

- **Suggested severity:** **INFO** (per D-08 5-bucket rubric; documentation gap rather than novel exploit). Same trust-asymmetry classification as surfaces (d), (e), (g): vault-owner is the explicit trust boundary per CONTEXT.md `<decisions>` 4th item. No code-level fix is appropriate (the design intentionally allows mid-level slate edits); operational mitigation = DGVE >50.1% acquisition cost. **However the §4b sub-row prose for surface (e) currently asserts:** "Voters who already cast their votes do NOT have their votes retroactively reassigned by a fill-empty action; the slate state at vote-cast time is what each voter chose." **This statement is FALSE for the queue branch** — voters' votes ARE retroactively reassigned by a queue-replace action. The statement is true narrowly for the instant-apply branch (which can only fill empty slots and has no retroactive effect on prior votes), but the prose generalizes incorrectly. The Phase 256 `slotApproveWeight` freeze (D-256-MULTI-VOTE-01) prevents the float-gaming sub-vector but does NOT prevent recipient-substitution under unchanged vote weight.

- **Disposition recommendation:** **EXTEND surface (e) prose** in `audit/FINDINGS-v33.0.md:396-406` to add a paragraph disclosing the queue-branch vote-redirect mechanism explicitly — OR promote to a 9th surface row as `(i) Queue-branch vote-redirect via mid-level recipient replacement`. Either path keeps verdict as `SAFE_BY_TRUST_ASYMMETRY` per the pre-decided trust boundary; do NOT promote to F-33-NN namespace per D-257-FIND-01 default. The existing test at `CharityAllowlist.test.js:305-315` already pins this behavior — but as protocol design, not as a disclosed adversarial surface. The audit deliverable should match: this needs to be DISCLOSED to readers, not merely tested.

### Investigations That Returned Nothing

- **Re-entrancy via `pickCharity` flush:** `contracts/GNRUS.sol:601-674` contains zero external calls (D-255-CEI-01 confirmed). Recipient is credited via internal `balanceOf` write at `:671`; no `transfer` / `call` / `delegatecall` fires. Vault-owner has no callback hook during flush. Not a vector.
- **`burn()` reentrancy via `claimWinnings` callback:** CEI ordering at `:315-316` (state writes before external transfer) makes re-entry harmless — re-entered `burn` would see decremented balance and revert at `:315`. Not a vector.
- **`setCharity` post-gameover:** Queued edits land in `pendingEdit` and never flush (gameOver blocks pickCharity). Stuck state, no value impact. Not a vector.
- **`_futureBitmapAfter` cap-check correctness:** Simulator at `:416-444` correctly handles all three cases. `_popcount32` is textbook Hamming weight; constant gas; no overflow. Not a vector.
- **`currentLevel` divergence from game's `level`:** `pickCharity` revert rolls back the whole tx including `level = lvl` write. No path advances game level past charity level by more than 1. Not a vector.
- **Empty-level processing:** All three skip-paths (bitmap == 0, zero-weight, zero-distribution) handle cleanly with deterministic `LevelSkipped` event. Not a vector.
- **`burn()` arithmetic with `claimable - 1` sentinel:** 1 wei dust accumulates; not exploitable. Not a vector.
- **`burnAtGameOver` / `burn` race:** `handleFinalSweep` is gated by 30 days post-gameover; no in-flight race. Not a vector.
- **Voting on slot 0/1/2 (locked) with queued-removal pre-fill:** Locked-slot guard at `:375` runs BEFORE branch dispatch. Not a vector.
- **`pendingEditSet` bitmap manipulation / popcount overflow:** `uint32` with 12 free bits over 20-slot cap. No overflow path. Not a vector.
- **Block-timestamp / day-boundary windows around setCharity → pickCharity:** GNRUS has zero `block.timestamp` / `block.number` reads. No temporal window. Not a vector.
- **DGNRS / sDGNRS / DGVE float gaming during queue-vs-flush window:** Vote weight frozen at vote time per D-256-MULTI-VOTE-01. Acknowledged in §4 surface (d). No new composition.
- **External ETH/stETH inflows from JackpotModule / DegenerusStonk / GameOverModule:** All push-only into GNRUS; affect `burn()` redemption pool by design. Not a vector.

### Closing Attestation

The 8-surface §4 table at `audit/FINDINGS-v33.0.md:367-440` is **structurally complete except for one disclosure gap** in surface (e) sub-row prose at `:396-406`: the prose claims "votes cast at vote-time anchor to the slate state at vote-cast time," which is true for the instant-apply branch but **FALSE for the queue branch**. The vault-owner's queue-branch `setCharity(filled_slot, attackerRecipient)` silently redirects all existing votes for that slot at the next pickCharity flush — the protocol treats vote weight as slot-index-anchored, not recipient-anchored. This is codified in the test at `test/governance/CharityAllowlist.test.js:305` ("queued replace: voter sees OLD address until flush; both voters accumulate against the live slot") as intentional design. The trust boundary still holds (vault-owner is the explicit curator per CONTEXT.md), so the verdict remains `SAFE_BY_TRUST_ASYMMETRY` and severity is **INFO** — but the §4b prose needs a corrective extension (or a 9th surface row) to disclose the queue-branch mechanism honestly. No code-level fix is recommended. No F-33-NN promotion is recommended. **One documentation gap; zero exploitable bugs; v33.0 charity-allowlist surface remains structurally sound at HEAD `dcb70941`.**

---

## Independent Re-Run Disposition Note (Task 8 — re-opened)

**Convergent finding from two independent agents:**

Both `/contract-auditor` and `/zero-day-hunter` independently identified the **queue-branch vote-redirect mechanism** as a disclosure gap in §4b sub-row prose. Specifically:

1. The §4b prose currently states (lines 396-406): *"Voters who already cast their votes do NOT have their votes retroactively reassigned by a fill-empty action; the slate state at vote-cast time is what each voter chose."*
2. This statement is **true narrowly for the instant-apply branch** (empty slot fill — no retroactive effect on prior votes for that slot, since the slot was empty).
3. This statement is **factually incorrect for the queue branch** — when a vault-owner calls `setCharity(filledSlot, newRecipient)`, the queue at `GNRUS.sol:399-407` writes `pendingEdit[slot] = newRecipient` while leaving `currentSlate[slot]` unchanged for further voting, and the flush at `:614-628` overwrites `currentSlate[slot]` BEFORE the winner phase at `:641-650` reads `slotApproveWeight[level][slot]` and pays `currentSlate[bestSlot]` at `:669`. Vote weight in the protocol is anchored to **slot index**, not recipient identity. Voters who cast for slot S during level L pay whichever recipient sits in `currentSlate[S]` at pickCharity time.
4. The behavior is **codified as intentional design** in the test at `test/governance/CharityAllowlist.test.js:305-315` ("queued replace: voter sees OLD address until flush; both voters accumulate against the live slot"). It is the protocol's trust-asymmetric design, not a bug.
5. The trust boundary (vault-owner curation gated by DGVE >50.1% threshold) is the same as surfaces (d), (e), (g). Verdict family is `SAFE_BY_TRUST_ASYMMETRY`. Severity per D-08 5-bucket rubric: **INFO** (documentation gap, not exploit).

**Both agents recommended Option A or Option A':**
- **Option A:** Extend §4b sub-row prose for surface (e) to add a paragraph explicitly disclosing the queue-branch vote-redirect mechanism alongside the instant-apply mechanism it already describes.
- **Option A':** Add a 9th surface row `(i) Queue-branch vote-redirect via mid-level recipient replacement` to the §4 table, with verdict `SAFE_BY_TRUST_ASYMMETRY`.
- Neither agent recommended F-33-NN promotion. Neither recommended a code-level fix.

**Both agents AGREED on surfaces (b), (c), (d), (f), (g), (h)** and AGREED on (e)'s instant-apply core; the only divergence from the plan author is on (a)'s verdict label (SAFE_BY_STRUCTURAL_CLOSURE vs SAFE_BY_TRUST_ASYMMETRY) and the §4b prose completeness.

**Independence verification:** Two fresh-context agents, identical scope, parallel spawn. Convergence on the same finding without cross-contamination is strong evidence the gap is real. The executor's manual-fallback self-audit missed this — the original `STATUS: SPAWN_FAILED` block above said both manual passes "AGREED on all 8 surfaces" and surfaced only sDGNRS float gaming.

**Pending user disposition:**

| Option | Action | Effect on FINAL READ-only flag | Effect on closure signal |
|--------|--------|-------------------------------|--------------------------|
| A | Re-open `audit/FINDINGS-v33.0.md`, extend §4b prose with queue-branch paragraph, re-flip READ-only, re-emit closure signal at new HEAD | Temporarily lifted, then re-applied | New signal `MILESTONE_V33_AT_HEAD_<new_sha>` (current `MILESTONE_V33_AT_HEAD_dcb70941` superseded) |
| A' | Re-open as in (A), but add row (i) to §4 table instead of extending §4b prose | Same as (A) | Same as (A) |
| B | Accept independent re-run findings as documented in this log only; leave deliverable unchanged | No change | No change to current `MILESTONE_V33_AT_HEAD_dcb70941` |
| C | Defer queue-branch disclosure to a future v33.x patch milestone; document deferral here | No change | No change |

**Recommendation (this log writer):** Option A — the §4b prose contains a factually incorrect generalization that an external auditor will catch in a 5-minute read. Extending the prose by one paragraph (~8-12 lines mirroring the instant-apply paragraph structure) gives the deliverable a clean external-submission posture without changing any verdicts or adding F-33-NN blocks. The closure signal re-emission cost is small (one re-flip cycle). Option A' is also acceptable but heavier (modifies the table structure).

`re-verified at HEAD dcb70941`. Task 8 disposition pending user decision.

