# Phase 358: SPEC — Design-Lock + Freeze/Solvency Re-Attestation + Call-Graph Attestation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-04
**Phase:** 358-spec-design-lock-freeze-solvency-re-attestation-call-graph-a
**Areas discussed:** Terminal-dec promotion vs weight-only (freeze gate), Terminal-dec economic levers, WWXRP whale-halfpass design, UDVT width/byte discipline

---

## Terminal-decimator: promotion vs weight-only (freeze gate)

The opening framing presented bucket-promotion as exploitable (read final-day rngWord while `!gameOver` → selectively promote into a winning subBucket) and proposed weight-only as the safe fallback, with options weight-only / promotion+timing-buffer / promotion+accept-risk.

**USER correction (rejected the framing):** "isn't livenesstriggered by itself enough? like the rng roll that determines the terminal decimator definitely cannot be rolled before that" + "what does the bucket swap have to do with that anyways. if the number or bucket was manipulable between rng request and decimator resolution that would violate the rules" + "this boost should be stopped when liveness is dead, so that happens before the rng request that would determine all this."

This reframed the issue: the governing rule is no manipulation between RNG **request** and resolution; the correct gate is liveness (pre-request), not `!gameOver`. Under that gate, bucket promotion is no different from a weight bump — both commit before any randomness. A verification scout confirmed the resolution word (`rngWordByDay[gameOverDay]`) is a future-day word relative to any admitted boost.

Reformulated into three locked sub-decisions:

| Sub-decision | Options | Selected |
|--------------|---------|----------|
| Freeze gate | `rngWordByDay[today]==0` (airtight) / **`!_livenessTriggered()` alone** | `!_livenessTriggered()` alone (USER: liveness is enough) |
| Boost window | **Final day only** / any time pre-reveal | Last day only |
| Promotion rule | **Re-derive bucket from live activity score, promote if strictly better** / weight-only | Re-derive + promote if strictly better |

**User's choice:** `!_livenessTriggered()` gate (the `rngWordByDay[today]==0` refinement was retracted — the same-day-reuse scenario doesn't hold); last day only; promotion ON (re-derive bucket from live `playerActivityScore`, promote iff strictly lower denom, re-derive subBucket, re-key aggregate).
**Notes:** Belt-and-suspenders `rngWordByDay[resolutionDay]==0` is a fallback only if the SPEC's formal pass surfaces a backlog/catch-up edge. TDEC-03 proof obligation: "the resolution word cannot exist before the boost gate closes."

---

## Terminal-decimator economic levers

| Decision | Options | Selected |
|----------|---------|----------|
| Double-count (streak already in burn-time weight) | **Keep both levers** / strip streak from burn-time / keep both + temper curve | Keep both levers |
| uint88 overflow on boost | **Saturate at uint88 max** / prove headroom | Saturate at uint88 max |
| Shields on streak validation | **Read-only (no consume)** / force-consume as affirmation | Read-only (no consume) |

**User's choice:** keep both streak levers (intentional stacking; `playerActivityScore` untouched — shared, large blast radius if stripped); saturate uint88 (matches `recordTerminalDecBurn:750-752`); shields read-only via the `getPlayerQuestView` `view`.
**Notes:** Finding presented: `MintStreakUtils:251` adds `questStreak*100` bps into `playerActivityScore`, driving both the frozen bucket and the `multBps` multiplier — confirmed double-count, accepted as-is.

---

## WWXRP whale-halfpass design

| Decision | Options | Selected |
|----------|---------|----------|
| Rationing granularity | **Global per bracket** (1 per `level/10`) / per-player-per-bracket | Global per bracket |
| Recipient (operator-resolved bet) | **player (bettor)** / need to discuss | player (bettor); resolve stays permissionless |

**User's choice:** global per bracket (`mapping(uint256=>bool)` keyed `level/10`; multi-bracket allow for a single player); pass accrues to the bettor — "anyone should be able to resolve degenerette bets (dont we have a mass resolve function?) but the winnings should always accrue to the bettor."
**Notes:** Confirmed via grep — permissionless `resolveBets:407` (no access modifier) + router stubs `resolveDegeneretteBets:902` / `degeneretteResolve:1742`, all funnel through `_resolveFullTicketBet`; `_resolvePlayer` always returns the bettor. `resolveBets` reverts on `_livenessTriggered()` (`:414`) → WWXRP award only fires pre-liveness, consistent with the freeze model.

---

## UDVT width/byte discipline

| Decision | Options | Selected |
|----------|---------|----------|
| Per-site matrix | **Confirm the matrix** / refine something | Confirm the matrix |
| Test-file handling | **Contract diff first, tests follow (agent-committable)** / everything in one reviewed batch | Contract diff first, tests follow |

**User's choice:** confirm the matrix (3 encodePacked sites cast→uint32; packed fields = Day/uint24; standalone slots + event topics stay uint32; rngWordByDay key unchanged; operators `<,<=,==,%,+,-`; repo-wide); test updates land as separate agent-committable commits.
**Notes:** The 3 RNG `abi.encodePacked` day sites were grep-attested present at `AdvanceModule:1405`, `:1828`, `Game:1011` before the question.

## Mid-358 scope additions (post-discussion, USER-driven 2026-06-04)

Two new items folded into v57.0 AFTER the four-area discussion, surfaced by the user during 358:

**BURNIE — coin-buy ticket-queue Critical fix (BURNIE-01/02/03).** The user reported (from the degenerus-sim afking-scale stress test) that BURNIE ticket buys via `purchaseCoin` burn the coin but queue zero tickets. VERIFIED against the audit tree `1e7a646d` (a dedicated scout: `_purchaseCoinFor:887-907` discards `_callTicketPurchase`'s returns; phase-160 `24f0898b` orphaned the coin path). USER decisions: fold into v57.0 (not a separate hot-fix — pre-launch); restore tickets + MINT_BURNIE quest credit (skip score/affiliate); **the MINT_BURNIE reward is a BURN REBATE** (require full cost upfront, defer the burn, burn net = full − reward); fix all three doc/test drifts (positive test, 3-arg `purchaseCoin` test, RNG-locked docstring). Highest-severity item.

**SALVAGE — sDGNRS salvage-swap combo ETH/BURNIE pawn-shop payout (SALVAGE-01/02/03).** The user asked to turn the v48 `sellFarFutureTickets` cash leg into a combo ETH + BURNIE-flip payout with variability. VERIFIED structure via scout. USER decisions: full-range `[0..eth-cap]` randomized ETH/BURNIE split of the cash leg (BURNIE @ current eth-equivalent via `_ethToBurnieValue`→`creditFlip`); ticket leg unchanged; reuse the existing prior-day seed (no new VRF). Key framing correction (USER): it's a **pawn shop** — VARIABLE, KNOWABLE-IN-ADVANCE offers, NOT value-neutral; the SOLE safety property is the **total payout cap (no-arb ceiling) + eth-% cap** → no exploitability even though predictable; suboptimal players forfeit EV to the protocol/pools (intended). Solvency-positive (less ETH out, BURNIE off the pool).

**CANCEL — manual sub-cancel auto-claim + auto-evict forfeit (CANCEL-01/02/03).** The user asked to make manual sub-cancel auto-claim the BURNIE for the canceller + their affiliate tree, leaving auto-evict as a pure delete. Scout VERIFIED + surfaced a latent LOSS BUG: manual cancel tombstones + leaves `pendingBurnie`/`affiliateBase` in the slot (comment promises "claim whenever"), but the next `processSubscriberStage` reclaim `delete _subOf[player]` (`:1144`) wipes both → lost in the race. USER decisions: manual cancel auto-claims self `pendingBurnie` (+ presale-box parity) AND settles the affiliate tree A/U1/U2 75/20/5, then clears (closes the race); **auto-evict = pure FORFEIT** (delete both accumulators, no payout to self OR uplines — the chose-to-leave vs got-kicked distinction). All BURNIE-emission off the ETH path, `rngLock`-gated → SOLVENCY-untouched + RNG-freeze-clean.

(The degenerus-sim "afking scale test" transition prompt that arrived alongside the BURNIE report was a wrong copy-paste — confirmed by the user, NOT acted on.)

## Claude's Discretion

- Exact `daysRemaining` "last day" threshold, the precise `boostFactor` curve constants, and the final operator-overload set + per-site UDVT count — calibrated/grepped at SPEC/IMPL within the locked shapes.

## Deferred Ideas

- Generalized operator-spend of `claimableWinnings` — separate optional feature.
- The v52 consolidated cross-model audit — separate future track.
- Confirmed NON-ISSUES (not work): O1 double-credit, `resolveLootboxRoll` dead branch, `_runRewardJackpots` misplacement (only stale comments remain → HYG-02), the 4 older balance notes.
