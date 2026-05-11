# Phase 269: Lootbox Dead-Branch Cleanup + SURF-05 Gas-Pin Re-Pinning - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-10
**Phase:** 269-lootbox-dead-branch-cleanup-surf-05-gas-pin-re-pinning
**Areas discussed:** LBX deletion shape (deep game-theory dive); plan structure; test-commit batching; GASPIN-01 root-cause method; GASPIN-02 stabilization preference + SURF-03 update form

---

## Initial gray-area menu (multiSelect — user diverted to deeper question)

| Option | Description | Selected |
|--------|-------------|----------|
| Plan structure & workstream sequencing | Single multi-task PLAN vs split into LBX/GASPIN PLANs; LBX-first vs GASPIN-first vs interleaved | (deferred to second pass) |
| Test commit batching shape | One batched test commit vs two separate USER-APPROVED commits | (deferred to second pass) |
| GASPIN-01 root-cause method + deliverable | Bisect / instrumentation / trace / combo; inline NatSpec vs working-file appendix | (deferred to second pass) |
| GASPIN-02 stabilization preference + SURF-03 update form | Lock default vs wait for RCA; re-baseline vs allowed-hunk exception | (deferred to second pass) |

**User's choice:** "what was this originally intended to do and how are we handling it now that this code is unreachable" — diverted from the plan-mechanics menu to a deep design-intent dive on the dead branch BEFORE making any cleanup decision. Surfaced the underlying game-theory concern: "I need to be sure that holding lootboxes can't confer any advantage and that it doesn't totally fuck people who don't open them immediately."

**Notes:** Triggered a multi-step trace through the lootbox open→resolve flow:
1. Git pickaxe trace (`-S "targetLevel < currentLevel"`) confirmed both the inner check AND the caller-clamp landed in the same initial commit `aafb7e0d` — inner branch was dead from inception (defensive double-guard, not vestigial leftover from an earlier design).
2. `_rollTargetLevel` (L812-826) trace: 90% near-future (baseLevel + 0..4), 10% far-future (baseLevel + 5..50). Per-roll bit budget consumed from per-resolution keccak seed (rangeRoll bits[0..15], near-offset bits[16..23], far-offset bits[24..39]).
3. `openLootBox` (L526-598) grace-period rule trace: `withinGracePeriod = currentDay <= day + 7`; `baseLevel = withinGracePeriod ? graceLevel : purchaseLevel`. Held player past grace gets `baseLevel = purchaseLevel`.
4. Triple-defense clamp identification: layer 1 (L557 outer caller), layer 2 (L882 inner caller), layer 3 (L1574 dead inner check). All three came in at `aafb7e0d`.
5. `seed = keccak256(rngWord, player, day, amount)` for ETH lootboxes; `day = lootboxDay[index][player]` snapshotted at buy via `MintModule.sol` L1409-1410. Player CANNOT grind seed by choosing open day for ETH lootboxes.
6. BURNIE-lootbox path (`openBurnieLootBox` L606-661): `day` falls back to `_simulatedDayIndex()` if `lootboxDay == 0` at L623-626 — potentially RNG-grindable IF a BURNIE-lootbox buy path leaves `lootboxDay` unset. Routed to deferred ideas (v38+).
7. Game-theory verdict: holding confers NO advantage (clamp constrains upside; cannot pick `targetLevel` by timing); holding does NOT lose tickets (clamp prevents past-bucket queueing); ONLY loses far-future bucket distribution variety (the 10% far-future roll's spread collapses to "currentLevel only").

This deep dive validated the `D-269-LBX-SHAPE-01` pure-deletion choice on substance, not just on the gas/bytecode argument.

---

## LBX deletion shape (after game-theory dive)

| Option | Description | Selected |
|--------|-------------|----------|
| Pure deletion | Replace L1568-1581 with `if (ticketsScaled != 0) { ticketsOut = ticketsScaled; }`. Maximum gas savings (~50g/open + bytecode shrink). Fits `feedback_no_dead_guards.md` letter exactly. Forward risk bounded by `private` visibility + Phase 271 §3.A grep recipe. | ✓ |
| Deletion + invariant assert | Add `require(targetLevel >= currentLevel)` before the assignment. ~Zero gas savings (require + LT ≈ original cost), no bytecode shrink. Trades gas for loud-fail revert on any future bypass. Slight tension with `feedback_no_dead_guards.md` (still a dead guard, just LOUDER dead). | |
| Pure deletion + NatSpec contract | Same code as Option 1 plus a single NatSpec line documenting caller's clamp responsibility. Documentation-as-discipline; zero runtime cost; same gas savings. Tension with `feedback_no_history_in_comments.md` if wording leaks history. | |

**User's choice:** Pure deletion (recommended option).
**Notes:** D-269-LBX-SHAPE-01 locked. Forward-risk bound = `_resolveLootboxRoll` private visibility (`grep -rn "_resolveLootboxRoll" contracts/` returns only the definition + 2 caller-sites at `_resolveLootboxCommon` L910 + L938 — no external visibility means future call-graph widening requires an explicit visibility change that an audit would catch) + Phase 271 LBX-03 §3.A audit-trail row (mandates post-deletion grep recipe consistency). NO trace comment at the deletion site per `feedback_no_history_in_comments.md` (caller-clamp invariant self-evident from local L860-884 reading).

---

## Plan structure & workstream sequencing

| Option | Description | Selected |
|--------|-------------|----------|
| Single multi-task PLAN | One `269-01-PLAN.md` covering both workstreams. ~5 atomic tasks: GASPIN RCA → batched USER-APPROVED contract commit (LBX-01) → batched USER-APPROVED test commit (LBX-02 + GASPIN fix + SURF-03 + optional package.json) → phase-close SUMMARY. Mirrors Phase 267/268 single-multi-task precedent. | ✓ |
| Two separate PLANs | Split into `269-01-LBX-PLAN.md` + `269-02-GASPIN-PLAN.md`. Clearer per-workstream attribution + STATE.md tracking. Breaks Phase 267/268 single-plan precedent. Adds planning overhead. | |
| Single PLAN, GASPIN-first sequencing | One PLAN, GASPIN root-cause + stabilization runs FIRST (decouples investigation from LBX deletion noise), then LBX contract commit, then LBX gas-test extension validates against post-LBX baseline. | |

**User's choice:** Single multi-task PLAN (recommended option).
**Notes:** D-269-PLAN-01 locked. Default ordering inside the PLAN: GASPIN RCA → LBX contract commit → batched test commit → phase-close. Planner refines exact decomposition.

---

## Test commit batching shape

| Option | Description | Selected |
|--------|-------------|----------|
| Single batched test commit | ONE USER-APPROVED test commit covering LBX-02 + GASPIN re-pin/fix + SURF-03 update + any package.json wiring. Mirrors Phase 268 `4b277aaf` pattern. One diff, one approval round. | ✓ |
| Two separate test commits | Commit A: LBX-02 + SURF-03 update. Commit B: GASPIN re-pin/fix. Two approval rounds; matches ROADMAP wording "test/chore commit(s)" (plural). | |

**User's choice:** Single batched test commit (recommended option).
**Notes:** D-269-COMMITS-01 locked. ROADMAP plural wording "test/chore commit(s)" accommodates the singular case (the singular satisfies the plural). Phase 268 `4b277aaf` precedent is the strong guide.

---

## GASPIN-01 root-cause method + deliverable shape

| Option | Description | Selected |
|--------|-------------|----------|
| Bisect-by-removal first, escalate if needed | Start with bisect across `test:stat` 14-file ordering. ~log₂(14) ≈ 4 rounds to isolate. Escalate to instrumented hardhat-snapshot diff or trace inspection if bisect inconclusive. Deliverable: short root-cause section in `269-01-PLAN.md` + inline NatSpec at the test fixture. | ✓ |
| Full instrumentation pass up-front | Skip bisect; jump to instrumented hardhat-snapshot diff + per-test gas-meter trace inspection. Higher upfront cost; complete root-cause picture. Deliverable: `269-NN-GASPIN-RCA.md` working-file appendix (mirrors Phase 270 precedent). | |
| Pragmatic re-pin first, RCA second | Just re-pin gas snapshots to combined-suite-stable values now to unblock CI; document deferred RCA. Faster but skips understanding — violates the spirit of GASPIN-01 ("root-cause investigation"). | |

**User's choice:** Bisect-by-removal first, escalate if needed (recommended option).
**Notes:** D-269-RCA-01 locked. NO separate `269-NN-GASPIN-RCA.md` working file — the RCA documentation lives in `269-01-PLAN.md` short root-cause section + inline NatSpec at the test fixture (per ROADMAP letter "decision documented inline at the test fixture"). Phase 270 owns the only working-file appendix in v37.0; Phase 269 stays plan-internal.

---

## GASPIN-02 stabilization preference + SURF-03 update form

| Option | Description | Selected |
|--------|-------------|----------|
| Wait for RCA, then pick least-invasive | Don't lock preference now — RCA dictates which of (a) re-pin / (b) ordering-fix / (c) split-files is structurally feasible AND least-invasive. SURF-03 update: re-baseline to Phase-269-close HEAD (cleaner than allowed-hunk exception for a small hunk). | ✓ |
| Default to re-pin + offset rationale, override if RCA shows trivial fix | Lock default: re-pin to combined-suite-stable values. Override only if RCA reveals a one-line ordering fix. SURF-03: re-baseline. | |
| Default to ordering-fix attempt, fall back to re-pin | Try ordering-fix path first regardless of RCA — only path that FIXES the underlying issue. Re-pin only if infeasible. SURF-03: allowed-hunk exception. | |

**User's choice:** Wait for RCA, then pick least-invasive (recommended option).
**Notes:** D-269-STAB-01 locked. Three RCA-driven stabilization paths documented in CONTEXT.md (re-pin / ordering-fix / split-files); planner reports chosen path with rationale in `269-01-PLAN.md`. D-269-SURF03-01 locked: re-baseline SURF-03 to Phase-269-close HEAD (cleaner than allowed-hunk exception which would require a growing hunk-allowlist). Update lands in same batched test commit per D-269-COMMITS-01.

---

## Claude's Discretion

- **Bisect ordering** for D-269-RCA-01 — reverse-order vs forward-order vs binary partition first. Planner picks; binary partition is fewest rounds.
- **GASPIN-02 stabilization choice** — locked only post-RCA per D-269-STAB-01; planner reports the chosen path with rationale.
- **`package.json` `test:stat` wiring** — only changes if RCA chooses split-files; planner adds the new file path(s) to the existing space-separated list per Phase 268 precedent.
- **LBX-02 test-file shape** — extending an existing `LootboxOpenGas.test.js` describe vs adding a new top-level describe block within the same file. ROADMAP says "extended"; planner picks describe-shape.
- **Worst-case seed engineering form** for D-269-WORSTGAS-01 — direct precomputed seed vs deterministic-seed helper. Planner picks; reuse if existing helper present.
- **Atomic-commit count** — D-269-PLAN-01 estimates ~3-4 commits; planner finalizes (whether GASPIN RCA produces a standalone chore commit or folds into the test commit's approval round).

---

## Deferred Ideas

### BURNIE-lootbox `lootboxDay = 0` fallback at `openBurnieLootBox` L623-626 (NEW — surfaced during game-theory dive)

`openBurnieLootBox` L623-626 falls back to `day = _simulatedDayIndex()` if `lootboxDay[index][player] == 0`. Since `seed = keccak256(rngWord, player, day, amount)` (L628), this could let a player grind the seed by choosing the open day, IF a BURNIE-lootbox buy path leaves `lootboxDay` unset. ETH-lootbox path is safe (`MintModule.sol` L1409-1410 unconditionally sets `lootboxDay` at buy). Confirmation requires tracing all BURNIE-lootbox buy paths to verify they all write `lootboxDay`. NOT a Phase 269 concern (orthogonal to LBX dead-branch cleanup AND GASPIN drift). Routed to v38+ backlog or a dedicated maintenance phase if confirmed exploitable.

### Phase 270 post-v32.0 deferred-commit adversarial sub-audit (`002bde55` + `2713ce61`)

Carry-forward deferral. Phase 270 audit-only. NOT a Phase 269 concern. Phase 270 can run in parallel with Phase 269 from a content perspective.

### Phase 271 §3.A LBX-03 audit-trail row + §4 surface (f) byte-equivalence audit

Authored at Phase 271, NOT Phase 269. Phase 269 LBX-01 commit produces the post-deletion HEAD against which the §3.A row is authored.

### `/economic-analyst` + `/degen-skeptic` adversarial-skill expansion for Phase 271

Resolve at Phase 271 discuss-phase. NOT a Phase 269 concern (LBX/GASPIN cleanup has zero economic-mechanism implications).

### Carry-forward backlog items (v38+)

`_jackpotTicketRoll` BAF jackpot xorshift refactor (v36 ENT-05 carry); `runrewardjackpots` module-misplacement (2026-04-02 stale backlog note); game-over thorough hardening (`gameover-thorough-test.md`). All out of v37.0 scope.
