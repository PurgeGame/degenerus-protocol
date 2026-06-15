# FINDINGS — v63.0 (Post-v62 Audit — Critical Invariants + Reward Game-Theory — DUAL-NET)

- **Frozen audit subject (SHA):** `a8b702a7` — byte-frozen at FOUNDATION (Phase 388). Contracts are byte-identical throughout the sweep: **zero `contracts/*.sol` mutation** (`git diff a8b702a7 -- contracts/` is empty at every checkpoint, including before AND after every Write-capable council fan-out). Contracts tree-hash `2934d3d8987a09c5f073549a0cb499f6c5f28620` == `git rev-parse a8b702a7:contracts` == `git rev-parse HEAD:contracts`. This is a document-only audit.
- **Baseline (last formally audited, frozen):** `77580320` (v62.0 closure subject). The audit delta vs the baseline = ~60 commits / 40 contract files / +4322 -3489 (storage packing - the BURNIE zero-start emission rework - gas-identity refactors - 4 new permissionless/keeper entrypoints - the reward/economic rebalances - the folded v50/v51/v52 legacy debt).
- **Date:** 2026-06-15.
- **Regression oracle:** `test/REGRESSION-BASELINE-v63.md` — forge **854 / 0 / 110** (122 suites green, 0 deterministic failures, supersedes any carried-red ledger; v62's 3 VRF-path invariants now pass 7/7). All adjudication ran against this green baseline.
- **Method — COUNCIL + CLAUDE, BOTH (the dual-net premise, AUDIT-V63-PLAN section 2):** two independent finding nets ran in every sweep phase. NET 1 = the cross-model council (Gemini 3 Pro + OpenAI Codex via `council.sh`), the primary external finder per the v62 cross-model premise. NET 2 = the deep Claude-led adversarial Workflow net (isolated top-model subagents, neutral prompts). Claude is the orchestrator: builds the foundation, runs both nets, **adjudicates every lead against the frozen source**, applies the locked threat model + by-design rulings, runs the **skeptic gate before any CATASTROPHE/HIGH**, and synthesizes. A no-finding verdict for a sweep area requires **both nets on record**.
- **Council pipeline:** `.planning/audit-v52/cross-model/bin/council.sh` -> `ask-gemini.sh` (read-only `--approval-mode plan`) + `ask-codex.sh` (`exec --sandbox read-only`). Raw outputs committed under `.planning/audit-v52/cross-model/{389-packing,...,396-terminal}/council/`. After every Write-capable fan-out the subject was git-status-verified unmutated.

---

## Executive summary

**v63 confirms the post-v62 change set holds the protocol's hard invariants — solvency, RNG-freeze, storage-layout correctness, and the game-theory of the rebalanced rewards — with exactly ONE bounded MEDIUM gap.** The dual-net swept seven dimensions (389-395) across 58 requirements and surfaced a single CONFIRMED contract finding: **BURNIE-04**, an sDGNRS redemption backing-completeness gap (the auto-rebuy carry is excluded from the redemption BURNIE base, so redeemers are progressively under-credited). It is conservative (no over-credit, no insolvency), off the ETH/`claimablePool` solvency spine, USER-ruled a REAL GAP, and **routed to a separate, gated, USER-hand-reviewed post-audit fix — NOT applied in this audit**. No CATASTROPHE, no HIGH. Every other lead across the seven sweeps is REFUTED / BY-DESIGN / MONITOR / INFO with both nets on record, or a KILLED test-coverage hole.

| Disposition | Count |
|---|---|
| **CONFIRMED contract finding (MED — routed to a gated fix, NOT applied)** | **1** — BURNIE-04 |
| CONFIRMED-as-risk -> USER BY-DESIGN / WONTFIX (protocol-owned, no contract change) | 1 — BURNIE-05 |
| CONFIRMED oracle-integrity (LOW, test-only; contract unaffected) | 1 — R-389-01 |
| Mutation GENUINE survivors — test-coverage holes KILLED-by-regression (not contract defects) | 7 — G-BPL-01, K1-K6 |
| Council-flagged HIGH candidates REFUTED at the gate (re-confirmed by the council-on-refuted re-run) | 3 — ECON-04, ECON-06, SOLV-07 |
| Council-flagged INFO/LOW candidate REFUTED-as-break (re-confirmed) | 1 — RNG-04 |
| Other leads REFUTED / BY-DESIGN / MONITOR / INFO (both nets on record) | ~78 |
| **CATASTROPHE / HIGH contract findings** | **0** |

> **Milestone outcome:** this is an AUDIT milestone; its deliverable is **this findings document**. The result is a near-clean delta with **one bounded MED gap (BURNIE-04) routed to a gated, USER-reviewed contract fix** applied AFTER the sweep — the subject stays byte-frozen at `a8b702a7` through the audit. The skeptic gate clears: no severity above MED (`396-SKEPTIC-GATE.md`). The council-on-refuted re-run resurrected nothing (`396-COUNCIL-ON-REFUTED.md`). Deduped master ledger: `396-CONSOLIDATED-LEDGER.md` (89 rows).

---

## The durable foundation (Phase 388 + Phase 395 — the regression net)

Built before and validated through the sweeps; the always-on regression oracle that every adjudication ran against.

| Source | Net | Result |
|---|---|---|
| **Phase 388 — green baseline + subject freeze** | Claude-built | `test/REGRESSION-BASELINE-v63.md`: forge **854/0/110**, 0 deterministic failures, ZERO carried bucket-A reds (v62's 3 VRF-path invariants now 7/7); supersedes the carried-red ledger. Storage layout re-derived via `forge inspect storageLayout` at `a8b702a7`; every slot-hardcoded harness recalibrated against the packing slot shifts (Game tail, sDGNRS, BurnieCoinflip, Admin). Verifier oracle-holes closed; the 7 surface-maps intaken as 45 tracked candidates routed to their sweep phases. |
| **Phase 395 — bounded mutation campaign** | mutation net | `audit/mutation/CAMPAIGN-REPORT-v63.md` + `MUTATION-FINDINGS-v63.md`. 3 SPINE targets fully scored + triaged (`BitPackingLib` - `DegenerusGameStorage` - `StakedDegenerusStonk`; 132 distinct survivors). 7 GENUINE survivors (1 packing-identity + 6 solvency-spine) = test-coverage holes on CORRECT subject lines, ALL KILLED-by-regression (`test/mutation/MutationKills.t.sol`, 8 tests). 0 contract defects, 0 routed. 3 RNG/v63-changed modules (BurnieCoinflip - Lootbox - Decimator) CI-deferred/resumable (surface already exhaustively covered by the 389-394 dual-net + the BURNIE-04 fix-design). |

---

## Per-sweep-area result (both nets on record at `a8b702a7`)

Each area carries BOTH the council net (NET 1) and the Claude net (NET 2). Pending second-sources (the 392/393 codex usage-cap and the 394 v51 gemini non-response) were all obtained and resolved in the council-on-refuted re-run (`396-COUNCIL-ON-REFUTED.md` section 4).

| Phase | Area | Reqs | NET 1 (council) | NET 2 (Claude) | Area verdict |
|---|---|---|---|---|---|
| 389 | PACKING-IDENTITY (storage + gas-identity) | STORAGE-01..07, GASID-01..05 | gemini+codex on record | on record | 0 CONFIRMED contract findings; 1 LOW test-only oracle item (R-389-01). |
| 390 | SOLVENCY-SPINE | SOLV-01..07 | gemini+codex on record | on record | 0 CONFIRMED. The one divergent HIGH lead (SOLV-07, gemini) REFUTED at source (codex SOUND). |
| 391 | RNG-SPINE (DOMINANT class) | RNG-01..06 | gemini+codex on record | on record | 0 CONFIRMED. The one divergence (RNG-04, codex INFO/LOW vs gemini SOUND) REFUTED-as-break (benign). |
| 392 | ENTROPY-AND-ECON (reward game-theory + BURNIE) | ECON-01..06, BURNIE-01..06 | gemini on record; codex second-sourced at 396 | on record | **1 CONFIRMED MED (BURNIE-04)** + 1 CONFIRMED-as-risk WONTFIX (BURNIE-05). 0 CONFIRMED in ECON; the 2 gemini ECON HIGH candidates REFUTED. |
| 393 | PERMISSIONLESS-COMPOSITION (access/reentrancy/MEV) | ACCESS-01..05 | gemini SOUND; codex second-sourced at 396 | REFUTED/BY-DESIGN | 0 CONFIRMED. Keeper box-bounty net-negative vs real gas; burst-solvency conserved. |
| 394 | LEGACY-DEBT (v50 + v51 folded) | LEGACY-01..06 | both on record (v51 gemini second-sourced at 396) | on record | 0 CONFIRMED across both slices; LEGACY-05/06 deferred FINDINGS discharged; 2 INFO doc-only. |
| 395 | MUTATION (folded) | MUT-01..03 | — | mutation net | 7 GENUINE survivors KILLED-by-regression; 0 contract defects. |

---

## Actionable findings

### BURNIE-04 — sDGNRS auto-rebuy carry excluded from the redemption BURNIE backing — **MEDIUM (CONFIRMED — routed to a gated fix, NOT applied)**

- **Origin:** Phase 392 — **convergent** (gemini council PRIME-01 + the Claude net), the surface-map FA-1 prime lead; second-sourced by codex in the council-on-refuted re-run (`396-COUNCIL-ON-REFUTED.md` section 4 / AREA A; both council models independently CONFIRM the under-credit and note it is CONSERVATIVE and off the ETH spine).
- **Defect:** every sDGNRS BURNIE-base read funnels through `coinflip.previewClaimCoinflips(SDGNRS)` = `_viewClaimableCoin + claimableStored` (`BurnieCoinflip.sol:971-975`), which **provably omits `autoRebuyCarry`**. Once sDGNRS arms perpetual 0-take-profit auto-rebuy (post day-20), winnings never route to `claimableStored` — they roll into the carry (`BurnieCoinflip.sol:497-506`, `573`). So in steady state the redemption BURNIE base is structurally near-zero and the carry — the bulk of sDGNRS's BURNIE house value — is invisible to `redeemBurnieShare`. There is **no sDGNRS-reachable liquidation path** into the carry (`claimCoinflipCarry` and the auto-rebuy toggles are not on the sDGNRS call list). => redeemers are progressively under-credited for carry-resident BURNIE.
- **Impact / severity (MED, skeptic-gated):** a real backing-completeness gap (under-credit / value strand), value-bearing but bounded. CONSERVATIVE — `base <= burnieBal + claimableBurnie`; the `redeemBurnieShare` waterfall never reverts; **no over-credit, no insolvency**. OFF the ETH/`claimablePool` solvency spine (BURNIE-06 attested 392) — **no ETH-solvency consequence**. BURNIE is rated "worthless except the near-unfarmable whale pass," bounding the real-world worth low. NO attacker profit (it is an under-credit of redeemers, not an extraction). Below the HIGH bar (no money pump, no supply break, no ETH insolvency); above INFO (real value un-accounted vs the proportional-backing premise). Full gate: `396-SKEPTIC-GATE.md` section 2.
- **USER ruling:** REAL GAP (an under-implementation of the intended design — confirmed 2026-06-15: the intended redemption value for the BURNIE part = OWNED [held + claimable] PLUS the flip CARRY, the carry slice flip-contingent on the next coinflip).
- **ROUTED gated-fix state (NOT applied in this audit):** the fix is a SEPARATE post-audit, USER-hand-reviewed contract change; the subject stays byte-frozen at `a8b702a7` through the audit. Fix-design: `.planning/phases/392-entropy-and-econ/392-BURNIE-04-FIX-DESIGN.md`; alt-design review: `392-BURNIE-04-ALT-DESIGN-REVIEW.md`. The adjudicated direction is an **aggregate-`burnieBase`-lane** redemption widening: (a) widen the redemption BURNIE base to include the carry via a NEW sDGNRS-only settle-then-read view (do NOT touch the shared `previewClaimCoinflips`); (b) at submit, **remove the redeemer's carry slice from the shared `autoRebuyCarry` slot** (a submit-time carry decrement — the conservation fix, reversing the original "not removed at submit" framing) so an intervening loss/win/recycle cannot move it and same-day redeemers cannot double-fraction the same wei; (c) resolve the contingency on **day `D+1`'s** coinflip (the flip the carry actually rides — unknown at submit; NOT the redeemed day `D`, whose result is public at submit and grindable), keyed off an absolute `coinflipDayWon(D+1)` day-result view (mirroring the proven ETH lootbox `rngWordForDay(day+1)` pattern), NOT the resolve-advance `currentWord` (stall-correctness); (d) the win-path is a **pure deferred mint** of the already-segregated slice (no claim-time carry read — keeping the carry consumption inside the `rngLocked`-gated submit window); (e) a `uint96`-whole-token re-pack of the `DayPending` lane (raw-wei `uint64` rejected outright — 1 BURNIE = 1e18 wei overflows `uint64` ~10,842x at genesis). The carry stays pure BURNIE — no term enters the `distributeYieldSurplus` obligations sum or `handleGameOverDrain` (the ETH-spine axis is preserved).
- **5 pending USER decisions (must be resolved before implementation — `392-BURNIE-04-FIX-DESIGN.md` section 8):**
  1. **Owned-vs-carry split granularity** — settle the OWNED portion atomically at submit (non-contingent, as today) and make only the CARRY portion flip-contingent (the spec default, lower gas), or make the ENTIRE share contingent and drawn carry-first?
  2. **Contingency coin = day `D+1`** — confirm the carry slice binds to day `D+1`'s coinflip (the flip the carry rides, unknown at submit), not the redeemed day `D`'s public result.
  3. **Reserve subtraction scope** — confirm single-counting (`_pendingBurnieEscrow` subtracted saturating from the BURNIE base, mirroring `pendingRedemptionEthValue` on the ETH side); confirm no intended over-collateralization where multiple redeemers SHOULD share contingent claims on the same carry.
  4. **GameOver stranding rule** — confirm unresolved-at-gameOver = LOSS (force-zero every outstanding escrow at the `handleGameOverDrain` latch, guard the contingency leg on `!isGameOver`), symmetric with BURNIE tombstoning and the loss-pays-nothing branch.
  5. **Recycle-bonus interaction** — confirm the redeemer is NOT entitled to the post-submit carry recycle growth (+0.75%/win + the 50-156% multiplier) between submit and resolve; all D+1 upside accrues to remaining holders (they chose to exit at submit).

---

## Lower-severity findings (test-coverage holes — NOT contract defects)

All KILLED-by-regression in Phase 395 / closed at FOUNDATION; the subject line is CORRECT in each case — these are oracle/harness-integrity items, not contract changes.

- **R-389-01 — two stale test harnesses hard-code a moved storage slot — LOW (oracle-integrity, test-only).** Phase 389 (both nets), `STORAGE-06` / `FC-389-04`: Composition `MINT_PACKED_SLOT=10` should be 9; HeroOverride JS `LOOTBOX_RNG_PACKED_SLOT=35` should be 34. Confirmed vs fresh `forge inspect` at `a8b702a7`. Test-only; the contract is unaffected and the forge primary baseline is intact. The Phase 395 regression-assertion path is the sibling class (`test/mutation/MutationKills.t.sol` asserts the packing round-trip). DOCUMENTED + re-routed as a test-hardening item, NOT a contract change.
- **G-BPL-01 — `BitPackingLib.setPacked` masked-RMW round-trip oracle gap — KILLED-BY-TEST.** Phase 395 (mutation net). Packing-identity test-coverage hole on a correct line; killed (`MutationKills.t.sol` — also kills the C1 mask mutants).
- **K1-K6 — `StakedStonk` solvency-spine oracle gaps — KILLED-BY-TEST.** Phase 395 (mutation net). Six post-gameOver / pool-drain / pool-rebalance / wrapper-transfer post-condition oracle holes (deterministic burn payout + stETH-fallback; `burnAtGameOver` drain; `transferFromPool` regular + self-win; `transferBetweenPools` conservation; `wrapperTransferTo`). All on correct subject lines; all killed. The dominant survivor shape: the live gambling-burn -> `claimRedemption` path was exhaustively driven, but the post-gameOver deterministic / pool-drain paths and the `setPacked` round-trip were never ASSERTED — every GENUINE survivor is a correct line the net never checked, not a defect.

---

## Refuted / by-design / WONTFIX (recorded so they are not re-flagged)

### Council-flagged candidates — REFUTED at the gate, re-confirmed by the council-on-refuted re-run

Per the v60 LIFECYCLE lesson, every Claude-REFUTED HIGH survived a FRESH council pass before dismissal (`396-COUNCIL-ON-REFUTED.md`, charge set A). All four remain REFUTED.

- **ECON-04 — money-pump (floor 100% + 10% recycle kicker = 110% loop) — gemini HIGH — REFUTED.** Both council models HOLDS on the re-run. Per-leg liquid accounting: the recycle kicker is illiquid flip-credit (survive-flip x0.5 + peg ~0.59 => realized ~=0.030*V, not 0.10*V), the box at neutral EV pays sub-unity liquid, value-in is won-first, ETH-spin recirc is depth-1 (`allowEthSpin=false`), and the EV uplift is 10-ETH-capped per (player, level). No closed positive-EV liquid loop. EV-neutrality re-verified IN CODE vs the PAPER brief (split 40/15/15/15/10/5; x11/9=19,678 -> 8,855==8,855; far/near 1.000; variance sum=0.78595==0.786x).
- **ECON-06 — streak-pump (afking<->manual same-day double-channel) — gemini HIGH — REFUTED.** Both models HOLDS. The double-channel does not exist: `completionMask` per-day-per-slot dedup + the afking slot-0 streak-skip + the mutually-exclusive `_effectiveQuestStreak`; the now-uncapped/halved quest-streak is a ramp-SPEED change only, raising no ceiling (fixed downstream ceilings: EV 40,000 / ROI 30,500 / decimator clamp 100). A transient over-count is a ramp matter, not a ceiling breach.
- **SOLV-07 — JackpotModule `whalePassCost` double-credit — gemini HIGH — REFUTED.** Both models HOLDS. `_handleSoloBucketWinner` adds BOTH `paid` and `wpSpent` into `paidDelta` (`JackpotModule:1202-1222`) => `paidDailyEth` includes the cost => `unpaidDailyEth` excludes it; `whalePassCost` is credited to `futurePrizePool` exactly ONCE. Single-counted; even a hypothetical conservative over-reservation is outside the `claimablePool` identity, not an underbacked payout.
- **RNG-04 — cross-round `uint32` decimator-seed collision — codex INFO/LOW (gemini SOUND) — REFUTED-as-break.** On the re-run codex raised a NEW mechanism (the `reverseFlip` +1 nudge into the decimator word) and labelled it "BREAKS (ACTIONABLE)" — adjudicated REFUTED at frozen source (`396-COUNCIL-ON-REFUTED.md` section 3). The nudge is gated by `rngLockedFlag` (reverts once the VRF request is in-flight, `DegenerusGame.sol:1817`); the base word is unknown when the nudge is committed; the net is predictability-WITHOUT-control (a blind additive offset on an unknown uniform word is still uniform), magnitude set by the claim's independent `amount`, off the ETH spine, not grindable. This is the contract's documented by-design PRE-reveal influence — the same structure attested for RNG-01/RNG-05. The original benign INFO/LOW verdict stands. gemini independently ruled HOLDS.

### CONFIRMED-as-risk -> USER BY-DESIGN / WONTFIX

- **BURNIE-05 — VAULT day-1-20 seed window-aging forfeiture — MED — USER BY-DESIGN / WONTFIX (no contract change).** Phase 392 — convergent (gemini PRIME-02 + Claude); second-sourced by codex (`396-COUNCIL-ON-REFUTED.md` AREA B — both confirm it is NOT a player extraction path). The VAULT day-1-20 ~2M-expected BURNIE seed is silently + irreversibly forfeited if the VAULT owner does not claim OR arm within the first 30 resolved days (the claim clamp `if (start < minClaimableDay) start = minClaimableDay` skips seed days 1-20 once the first claim lands >= day 51; no auto-claim safety net, asymmetric vs sDGNRS). Skeptic gate (`396-SKEPTIC-GATE.md` section 3): a genuine silent unrecoverable lost-emission window, but NOT an attacker exploit (no third-party gain — the seed forfeits to nobody) and off the ETH spine. The VAULT is a PROTOCOL-controlled address (deployer/operator >50.1% DGVE) with two escape hatches (arm before day 51, or claim by day <= 30). **USER-ruled BY-DESIGN/WONTFIX:** the owner will claim/arm within the window; an operational runbook item, NOT a player-facing defect; no contract change, no KNOWN-ISSUES disclosure. Survives the gate as a documented, USER-accepted operational posture; NOT carried as an open finding.

### Standing by-design rulings (recorded, not re-litigated)

- **ECON-05 — box WWXRP-spin whale-half-pass — BY-DESIGN.** P(S=9)~=6.74e-8 / ~99M boxes-per-pass; the global per-bracket flag caps supply at one per bracket across the box+bet routes — a cost-curve change, supply intact (degenerette-wwxrp-rtp-by-design).
- **Lootbox-resolution timing** (permissionless, economically-incentivized open) — BY-DESIGN (lootbox-resolution-timing-by-design).
- **Redemption dust-lootbox forfeit self-credit** (anti-dust-farm) — BY-DESIGN (redemption-dust-lootbox-drop-bydesign).
- **Operator-approval trust boundary** (BURNIE-funding overload accepted) — BY-DESIGN (open-e-operator-approval-trust-boundary).
- **Intended EV>100% RTP / positive-EV lootbox+coinflip / bounded PvP curses** — BY-DESIGN, not findings (intended-game-mechanics-not-findings).
- **INFO/MONITOR doc-hygiene:** stale EV-band comment "8000-13500" (FC-392-04); stale code-comments `JackpotModule:1047`/`:1160` (v51 LEGACY-04); the carried v62 affiliate-score asymmetry (FC-392-15, unchanged by v63, no new defect); the `DecEntry.burn` raw-vs-effective comment (FC-389-03). All comment-only; off the spine.

---

## Reproduction / regression artifacts (test-only, real contracts)

- `test/REGRESSION-BASELINE-v63.md` — the green oracle (forge 854/0/110) every adjudication ran against.
- `test/mutation/MutationKills.t.sol` — kills the 7 GENUINE mutation survivors (G-BPL-01 + K1-K6); each test validated fail-with-mutation / pass-without on the clean subject.
- `audit/mutation/CAMPAIGN-REPORT-v63.md` + `SURVIVOR-TRIAGE-v63.md` + `MUTATION-FINDINGS-v63.md` — the bounded campaign score + per-survivor disposition (125 FALSE + 7 GENUINE).
- `.planning/phases/392-entropy-and-econ/392-BURNIE-04-FIX-DESIGN.md` + `392-BURNIE-04-ALT-DESIGN-REVIEW.md` — the BURNIE-04 routed fix-design + adversarial alt-review (the eventual fix's regression test plan lives in the fix-design section 7).
- `.planning/phases/396-terminal/396-CONSOLIDATED-LEDGER.md` (89-row deduped master ledger) + `396-COUNCIL-ON-REFUTED.md` (the council re-run) + `396-SKEPTIC-GATE.md` (the MED-or-above clearance).
- Council raw outputs: `.planning/audit-v52/cross-model/{389...396}/council/`.

---

## Remediation note (the sole open gated item)

**BURNIE-04 is the only open gated item** — a separate, USER-hand-reviewed contract change applied AFTER this audit, batched, never pre-approved. The 5 pending USER decisions above must be resolved first; the eventual fix's reproduction/regression plan (`392-BURNIE-04-FIX-DESIGN.md` section 7) flips from characterizing the gap to asserting the fix, re-attested against `test/REGRESSION-BASELINE-v63.md` (any new failing test NAME is a regression; raw red count is not). BURNIE-05 is USER-WONTFIX (an operational runbook item, no contract change). Everything else is REFUTED / BY-DESIGN / KILLED. No fix is applied in this audit milestone; the subject stays byte-frozen at `a8b702a7` (tree `2934d3d8987a09c5f073549a0cb499f6c5f28620`).
