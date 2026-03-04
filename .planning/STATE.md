---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: Adversarial Audit
status: unknown
last_updated: "2026-03-04T23:41:19.759Z"
progress:
  total_phases: 14
  completed_phases: 12
  total_plans: 78
  completed_plans: 69
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-04 after v2.0 milestone start)

**Core value:** Every ETH that enters the protocol must be accounted for, every RNG outcome must be unmanipulable, and no actor can extract value beyond what the game mechanics intend.
**Current focus:** v2.0 Adversarial Audit — Phase 8 COMPLETE; Phase 7 v2.0 backfill (07-04 + 07-05) COMPLETE; Phase 9 (Gas Analysis) is next.

## Current Position

Phase: 9 of 13 (advanceGame() Gas Analysis and Sybil Bloat) — not yet planned
Plan: 0 of TBD in current phase
Status: Phase 8 complete; Phase 7 final report complete (07-05); Phase 9 ready to plan
Last activity: 2026-03-04 — Phase 07-05 complete: 527-line final findings report written, 56/56 v1 requirements assessed, 0 Critical / 1 High / 3 Medium / 6 Low / 2 Fixed severity distribution confirmed

Progress: [##░░░░░░░░] 17% (1/6 phases complete)

## Performance Metrics

**Velocity (v1.0 baseline):**
- Total plans completed: 41
- Average duration: ~5min
- Total execution time: ~205min

**By Phase (v1.0):**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01 | 4 | ~8min | 2min |
| 02 | 6 | ~30min | 5min |
| 03a | 7 | ~35min | 5min |
| 03b | 6 | ~36min | 6min |
| 03c | 6 | ~22min | 4min |
| 05 | 7 | ~33min | 5min |
| 06 | 7 | ~34min | 5min |
| 07 | 3 | ~8min | 3min |

**Recent Trend:**
- Stable at ~5min/plan
- Trend: stable

*Updated after each plan completion*
| Phase 07 P03 | 15 | 1 tasks | 1 files |
| Phase 07 P05 | 5 | 1 tasks | 1 files |
| Phase 09 P01 | 20 | 2 tasks | 1 files |
| Phase 09 P04 | 8 | 2 tasks | 1 files |
| Phase 09 P02 | 15 | 2 tasks | 2 files |
| Phase 09 P03 | 3 | 2 tasks | 2 files |
| Phase 10 P03 | 18 | 2 tasks | 1 files |
| Phase 10 P02 | 6 | 2 tasks | 1 files |
| Phase 10 P01 | 2 | 2 tasks | 2 files |
| Phase 10 P04 | 10 | 2 tasks | 1 files |
| Phase 11 P04 | 8 | 2 tasks | 1 files |
| Phase 11 P03 | 15 | 2 tasks | 1 files |
| Phase 11 P02 | 10 | 2 tasks | 1 files |
| Phase 11 P01 | 12 | 2 tasks | 1 files |
| Phase 11 P05 | 10 | 2 tasks | 1 files |
| Phase 12 P03 | 12 | 2 tasks | 1 files |
| Phase 12 P01 | 15 | 2 tasks | 1 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [v1.0]: Phase 4 ETH accounting gap accepted — ACCT-01 through ACCT-10 are the entire scope of Phase 8
- [v1.0]: Phase 7 synthesis gap accepted — cross-function reentrancy is Phase 12 scope
- [v2.0]: Phases 8 and 9 are parallel work streams — Phase 8 covers accounting paths, Phase 9 covers gas paths; no dependency between them
- [v2.0]: ASSY-01/02 placed in Phase 10 alongside ADMIN — highest-risk assembly findings get early attention in the v2.0 sequence
- [v2.0]: VAULT and TIME folded into Phase 11 — too small for standalone phases, natural fit with TOKEN economic analysis
- [Phase 07]: 07-03: Phase 4-04 confirmed complete — 8 unlisted functions are all access-restricted or self-call-only with zero ETH-transfer surface
- [Phase 07]: 07-03: Cross-function reentrancy via resolveDegeneretteBets/claimDecimatorJackpot is SAFE — new credits are legitimately earned and properly balanced in claimablePool
- [Phase 07]: 07-03: handleFinalSweep is SAFE without a mutable guard — trusted-only recipients (VAULT, DGNRS) have non-reentrant receive() functions
- [Phase 07]: 07-05: deity pass double refund (GO-F01) reclassified to FIXED — deityPassPaidTotal[buyer] = 0 is already zeroed at refundDeityPass() line 710, closing the cross-transaction double-refund path
- [Phase 07]: 07-05: deityBoonSlots staticcall (XCON-F01) rated MEDIUM — view-only correctness issue, no state corruption; issueDeityBoon() uses delegatecall correctly
- [Phase 07]: 07-05: Final v1 audit severity distribution confirmed: 0 Critical, 1 High, 3 Medium, 6 Low, ~45 Info, 2 Fixed
- [Phase 09]: GAS-01 PASS: worst-case advanceGame() stage is STAGE_TICKETS_WORKING at 6,284,995 gas — well under 16M limit; all 12 stage constants verified and corrected in test harness
- [Phase 09]: GAS-07 PASS: no dominant whale strategy rationally delays advanceGame() indefinitely; three independent liveness paths confirmed via source analysis
- [Phase 09]: CREATOR key-management risk classified INFO (GAS-07-I1), forwarded to Phase 10 ADMIN-01
- [Phase 09]: VRF stall liveness dependency classified INFO (GAS-07-I2), forwarded to Phase 10 ADMIN-02
- [Phase 09]: GAS-02 PASS: processTicketBatch max measured 6,284,995 gas (39.3% of 16M); Sybil cold batch 5,193,019 gas
- [Phase 09]: GAS-03 PASS: WRITES_BUDGET_SAFE=550 enforces hard per-call ceiling of ~7.4M gas; no N wallets can push single advanceGame() call to 16M
- [Phase 09]: GAS-04 PASS: permanent Sybil DoS costs ~4,950 ETH/day at minimum ticket floor; exceeds 1,000 ETH threat model (LOW theoretical)
- [Phase 09]: GAS-05 PASS: payDailyJackpot stage=11 at 887,410 gas (5.5% of 16M); split design (stage-11 ETH + stage-9 BURNIE) is correct optimization per source comment
- [Phase 09]: GAS-06 PASS: VRF callback (rawFulfillRandomWords) measured at 62,740 gas — 137,260 below 200K target, 237,260 below 300K Chainlink limit
- [Phase 10]: ADMIN-03 MEDIUM: wireVrf + reverting coordinator halts game in 3 game days; griefing loop repeatable; ADMIN key required
- [Phase 10]: ADMIN-04 PASS: 18h lock window has no front-running surface; openLootBox/openBurnieLootBox are BLOCKED (RESEARCH.md correction)
- [Phase 10]: ADMIN-02: wireVrf classified MEDIUM per C4 methodology — admin-key-required + CRITICAL impact = MEDIUM; ungated vs. stall-gated distinction vs. updateVrfCoordinatorAndSub explicit
- [Phase 10]: ADMIN-01: 11 admin-gated functions mapped; wireVrf NatSpec/code discrepancy flagged (line 294 claims idempotency, code enforces none); isVaultOwner dual-auth documented INFO/QA; CREATOR single-EOA risk (GAS-07-I1) folded as ADMIN-01-I1 INFO/QA
- [Phase 10]: ASSY-01 PASS: JackpotModule assembly correctly computes traitBurnTicket[lvl][traitId] slot via keccak256 mapping formula + inplace array offset
- [Phase 10]: ASSY-02 PASS: MintModule assembly is byte-for-byte identical to JackpotModule, same verdict applies
- [Phase 10]: ASSY-03 PASS: _revertDelegate standard delegatecall bubble-up safe in 4 locations; DegenerusJackpots array-shrink safe with n <= 108
- [Phase 10]: Storage comment DegenerusGameStorage.sol line 104-105 is WRONG (nested mapping formula) but assembly is correct; rated INFO finding
- [Phase 10]: ADMIN-05 INFO: external drain impossible (_requestRng private, requestLootboxRng requires >=40 LINK); drain is admin-neglect path only
- [Phase 10]: ADMIN-06 PASS: no admin function modifies claimableWinnings[player]; wireVrf RNG word manipulation is batch-level (lootbox index), not wallet-level; pull pattern provides censorship resistance
- [Phase 11]: VAULT-01 PASS: receive() event-only, 1T DGVE pre-minted at construction closes ERC4626 inflation vector; live balance formula proportional to all shareholders
- [Phase 11]: VAULT-02 PASS: _burnFor() floor division protocol-favorable; partial burns sum ≤ full burn (proved arithmetically); onlyGame blocks Stonk donations
- [Phase 11]: TOKEN-07 PASS: self-referral blocked at two independent code paths; REF_CODE_LOCKED=bytes32(1) permanently seals slots; circular ring INFO only (6% recirculation = designed rakeback); wash trading is 6.25% discount, no amplification
- [Phase 11]: TOKEN-08 PASS: LockStillActive guard at unlock() line 469 blocks same-level double-cap; auto-unlock in lockForLevel() resets spend counters atomically without crediting claimables; _lockedClaimableValues is view-only; level-transition timing window is clean
- [Phase 11]: TOKEN-04 PASS: max EV surplus = 3.5 ETH per player per level; no whale+lootbox combination yields EV > 1.0 after accounting for purchase costs
- [Phase 11]: TOKEN-05 PASS: activity score inflation cost floor (~24-52 ETH cheapest path to max tier) exceeds maximum EV benefit ceiling (3.5 ETH); no positive-return inflation path exists
- [Phase 11]: TOKEN-06 PASS: operator-proxied purchaseCoin routes through _resolvePlayer() (beneficiary-naming only) then delegatecall to MintModule; COIN_PURCHASE_CUTOFF guard fires at ticketQuantity != 0 regardless of msg.sender; whale/lazy/deity passes use ETH tickets and are exempt by design
- [Phase 11]: TOKEN-01 PASS: all vaultAllowance sites guarded — constructor seed (compile-time), _transfer-to-VAULT (net-zero), vaultEscrow (GAME+VAULT gate BurnieCoin.sol:679-682)
- [Phase 11]: TOKEN-02 PASS: claimWhalePass strict CEI confirmed — whalePassClaims[player]=0 at line 498 before all effects; no ETH external call; replay blocked at line 495
- [Phase 11]: TOKEN-03 PASS: BurnieCoinflip entropy VRF-only — processCoinflipPayouts uses rngWordCurrent (Chainlink VRF); historical fallback uses rngWordByDay[] not blockhash/prevrandao
- [Phase 11]: TIME-01 PASS: dailyIdx guard + Ethereum timestamp monotonicity prevents double jackpot trigger via ±900s validator drift
- [Phase 11]: TIME-02 PASS (INFO): quest currentDay read from stored activeQuests[0].day, not block.timestamp; streak griefing risk is BURNIE-only (INFO), no ETH exposure
- [Phase 12]: REENT-03 PASS: _resolvePlayer is pure view SLOAD, no callback, no multicall interface in DegenerusGame
- [Phase 12]: REENT-05 PASS: formal mutual exclusion proof — future tickets always use lvl N+k (k>=1) vs current-level; ticketLevel!=lvl guard always resets cursor
- [Phase 12]: REENT-06 PASS: e.claimed=1 at DecimatorModule line 391 precedes _creditDecJackpotClaimCore line 424; auto-rebuy path is internal storage only
- [Phase 12]: REENT-07 PASS: adminSwapEthForStEth is value-neutral; amount==0 guard confirmed; claimablePool untouched; stETH ERC-20 no callback
- [Phase 12]: REENT-01: PASS — all 8 ETH-transfer sites across 4 contracts are CEI-safe; sentinel pattern protects arbitrary-recipient sites; trusted-recipient sites send to non-reentrant protocol contracts

### Pending Todos

None yet.

### Blockers/Concerns

- [Research flag]: Medusa Hardhat ESM compatibility — verify `--build-system hardhat` flag works before fuzzing campaigns; fall back to Echidna if crytic-compile integration fails
- [Research flag]: `_creditClaimable` claimablePool update — ARCHITECTURE.md flags as "suspected missing"; ACCT-02 is the most likely unconfirmed HIGH finding; audit every call site in Phase 8 before drawing conclusions
- [Resolved]: DAILY_ETH_MAX_WINNERS=321 confirmed; GAS-05 verdict PASS at 887,410 gas (stage=11)

## Session Continuity

Last session: 2026-03-04
Stopped at: Phase 10-02 complete — ADMIN-01 power map (11 functions, wireVrf MEDIUM) and ADMIN-02 wireVrf verdict delivered; NatSpec/code discrepancy on wireVrf idempotency flagged
Resume file: None

## Phase 8 Findings Summary (for Phase 13 report)

| Finding | Severity | Location | Notes |
|---------|----------|----------|-------|
| ACCT-05-L1 | LOW | DegenerusAdmin.sol:636 | creditLinkReward declared in interface, not implemented in BurnieCoin.sol — BURNIE bonus not credited, LINK still forwarded |
| ACCT-05-I1 | INFO | DegenerusAdmin.sol:613,636 | Formal CEI deviation in onTokenTransfer — not exploitable given coordinator trust model |
| ACCT-10-I1 | INFO | DegenerusGame.sol:2856 | selfdestruct surplus becomes permanent protocol reserve — increases solvency margin |
