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
