# 328-02 — SC2 Adversarial Sweep (v48.0 TERMINAL)

**Phase:** 328-terminal-delta-audit-3-skill-adversarial-sweep-closure · **Plan:** 02
**Audit subject (FROZEN):** `1575f4a9` (Phase 326 IMPL batched diff `f50cc634` + Phase 327 HERO-04 byte-reproduced Degenerette finals landing `1575f4a9`, constant-only)
**Baseline:** v47.0 closure HEAD `da5c9d50989707c8964a9411e68c51ca1b1a25f2`
**Read-only:** every probe reads source via `git show 1575f4a9:contracts/...`; `git diff 1575f4a9 HEAD -- contracts/` stays empty.

This log mirrors the v47 Phase 324 / v46 Phase 320 adversarial-log structure: a CHARGE (§A), the raw per-skill outputs (§B), the per-probe disposition table (§C, the Outcome summary), and the dual-gate Skeptic-Reviewer Filter Attestation (§D).

---

## §A — CHARGE

### A.1 Skill set (FIXED) — `/degen-skeptic` OUT
The 3-skill set is FIXED per the carried decision **D-271-ADVERSARIAL-02** (held through v44/v45/v46/v47):

| Skill | Role | Persona source |
|-------|------|----------------|
| `/contract-auditor` | Adversarial contract security + 1000-ETH-attacker lens | `~/.claude/skills/contract-auditor/SKILL.md` |
| `/zero-day-hunter` | Novel / composition / edge-case attack surface | `~/.claude/skills/zero-day-hunter/SKILL.md` |
| `/economic-analyst` | Game-theory / mechanism-design / EV + no-arb | `~/.claude/skills/economic-analyst/SKILL.md` |

`/degen-skeptic` is **OUT** (D-271-ADVERSARIAL-02). The skeptic FUNCTION is preserved as the integration-time dual-gate filter applied to every elevation (§D), not as a fourth persona.

### A.2 Execution path — GENUINE PARALLEL_SUBAGENT
**Path used: `PARALLEL_SUBAGENT`.** Per the v45 Phase 314 / v47 Phase 324 lesson, `/gsd-execute-phase` ran THIS plan **INLINE in the main orchestrator context** (which holds the Task/Agent tool), so the 3 skills launched as **concurrent background Task spawns** for the ~3× wall-clock speedup — NOT nested inside a `gsd-executor` (which lacks the Task tool and would force the HYBRID/SEQUENTIAL_MAIN_CONTEXT fallback). Persona fidelity is preserved via each skill's dedicated `SKILL.md`. Each subagent probed the actual frozen subject via `git show 1575f4a9:contracts/...` (not from memory), READ-ONLY, with every cited `file:line` re-grep-verified against `1575f4a9`.

### A.3 Charged probe set → skill assignment (the 7 v48 surfaces + composition)

| Probe | Surface | Primary skill(s) | Expectation (verify honestly) |
|-------|---------|------------------|-------------------------------|
| SWAP no-arb-at-ceiling (d6..d100) | SWAP | economic-analyst | NEGATIVE-VERIFIED (margin ~4.5pp @d6; never +EV) |
| SWAP grinder-waiter timing (jitter band) | SWAP | economic-analyst + zero-day-hunter | NEGATIVE-VERIFIED (settled past word; no +EV day-select) |
| SWAP swap-pop H-CANCEL-SWAP-MISS regression | SWAP | zero-day-hunter | NEGATIVE/SAFE_BY_DESIGN (caller-verified swap-pop; `membership ⟺ packed != 0`) |
| SWAP × redemption-desk structural protection | SWAP | zero-day-hunter + economic-analyst | NEGATIVE-VERIFIED (≥1 ETH floor; desk structurally protected) |
| RFALL donation-robustness (force-feed/selfdestruct) | RFALL | all 3 | NEGATIVE-VERIFIED (F-47-02 fix holds; same-asset-basis coverage) |
| PFIX dust bound (closing-buyer windfall) | PFIX | economic-analyst | NEGATIVE-VERIFIED (F-47-01 fix holds; divisor 1_000→400) |
| KEEP foreclosure + minted-credit faucet | KEEP | contract-auditor + economic-analyst | NEGATIVE/SAFE_BY_DESIGN (two-tier 75/20/5; bounded bounty) |
| POOL pool-recovery accounting + griefing | POOL | contract-auditor + zero-day-hunter | NEGATIVE-VERIFIED (`address(this).balance`; no double-count) |
| BTOMB 1e36 overflow + DGVB-claim | BTOMB | contract-auditor | NEGATIVE-VERIFIED (checked add/cap; one-shot; totalSupply untouched) |
| HERO byte-identical RTP / neutral-EV | HERO | economic-analyst | NEGATIVE-VERIFIED (basePayoutEV ≤100 per-N; S=9≡old M=8) |

### A.4 Skeptic filter (mandatory dual-gate — per `feedback_skeptic_pass_before_catastrophe`)
Every elevation is run through BOTH gates BEFORE it can be recorded as a FINDING_CANDIDATE:
1. **Structural-protection check** — does a structural mechanism already prevent the elevation?
2. **3-condition EV lens** — (a) does the harm manifest without an attacker / is it positive-EV to execute? (b) is the magnitude material? (c) does the severity survive the skeptic re-read?

An elevation becomes a FINDING_CANDIDATE only if it survives BOTH gates. Applied twice: per-skill self-arm (in each subagent) AND orchestrator integration-time re-application (§D). The **OPEN-E operator-trust disposition** holds: operator-approval IS the trust boundary — the SWAP `sellFarFutureTickets` operator-gated action is NOT modelled with a "tricked into approving" actor.

### A.5 Disposition vocabulary + elevation routing (mirror v47 §4)
- **NEGATIVE-VERIFIED** — probe investigated, no issue.
- **SAFE_BY_DESIGN** — intended behavior, informational.
- **FINDING_CANDIDATE** — survives the dual-gate → recorded here, surfaced to 328-03 (§4) and the 328-04 USER closure gate for adjudication. NOT auto-fixed (subject FROZEN at `1575f4a9`; any fix is a NEW contract phase requiring USER approval — the v47 F-47-01/F-47-02 DEFER precedent). Tier-1 = single-skill; Tier-2 = multi-skill consensus.

---

## §B — Raw per-skill outputs

All three skills ran concurrently (PARALLEL_SUBAGENT) against `1575f4a9`, each citing anchors re-grep-verified against `git show 1575f4a9:...`. Condensed faithfully below; dispositions verbatim.

### B.1 `/contract-auditor` — 4 probes
- **CA-1 BTOMB** (`BurnieCoin.sol:187-188,358-361,264,271,583-590` · `GameOverModule.sol:30-32,51-53,87,152` · `DegenerusVault.sol:756,949-959`): `BURNIE_TOMBSTONE_WEI=1e36`; `tombstoneAtGameOver()` is `OnlyGame`, dual one-shot latch (`GO_JACKPOT_PAID` in caller + `_tombstoneFlooded` in BurnieCoin), `vaultAllowance += 1e36` done in uint256 then `_toUint128`-checked (reverts `SupplyOverflow` only if `> ~3.4e38`; starts ~2e6 ether). `totalSupply()` returns `_supply.totalSupply` only — structurally untouched. DGVB pro-rata claim `coinBal(≤3.4e38) × amount(≤1e30) ≤ 3.4e68 ≪ uint256 max 1.15e77` → no overflow in `burnCoin`/`previewCoin`/`previewBurnForCoinOut`. → **NEGATIVE-VERIFIED.**
- **CA-2 KEEP** (`DegenerusGame.sol:1778,1567,1570,1636,1684,1705` · `AfKing.sol:527,567,846` · `DegenerusAffiliate.sol:247-256,388-516,691-694`): `_purchaseFor(player,0,msg.value,bytes32("DGNRS"),payKind)` is the AfKing keeper leg; `crank/sweep/do-work` gone (doc-comment text only), `autoBuy/autoOpen/autoResolve`+`creditFlip` present. Affiliate `"DGNRS".owner==SDGNRS`; unreferred joiner → 80% SDGNRS / 20% VAULT (both protocol sinks). `_vaultReferralMutable` returns false for any non-VAULT/non-LOCKED storedCode → a registered human affiliate code is NOT overwritable; the only mutable case redistributes between VAULT↔SDGNRS during presale. → **NEGATIVE-VERIFIED.**
- **CA-3 POOL** (`DegenerusVault.sol:514-518` · `StakedDegenerusStonk.sol:438-444,539` · `AfKing.sol:318-331,503-504`): `recoverAfKingPool()` = `afKing.withdraw(afKing.poolOf(address(this)))`, permissionless but `withdraw` debits + sends to `msg.sender` only (no redirection); `withdraw(0)` early-returns (empty pool can't brick `burnAtGameOver`, which recovers before its `bal==0` return); reserves read live via `address(this).balance` (no double-countable counter); re-entrant `receive()` only emits an event. → **NEGATIVE-VERIFIED.**
- **CA-4 RFALL** (`DegenerusGame.sol pullRedemptionReserve ~:1882-1923` · `StakedDegenerusStonk.sol:308,856-951`): coverage pure-ETH-OR-pure-stETH (no mix), fail-closed only when neither single leg covers the 175%; `maxIncrement` telescopes `floor(newBase×175/100)−floor(prevBase×175/100)`; donation-robust (stETH-leg coverage reads `steth.balanceOf(SDGNRS)` — the exact basis a donation inflates); every outflow first subtracts `pendingRedemptionEthValue`. Worst case = self-DoS on an oversized single burn (recoverable by burning less), nothing lost. → **NEGATIVE-VERIFIED.**
- **Summary:** contract-auditor: 4 probes, 4 NEGATIVE-VERIFIED, 0 FINDING_CANDIDATE.

### B.2 `/zero-day-hunter` — 6 probes
- **ZD-1 SWAP swap-pop H-CANCEL-SWAP-MISS regression (PRIMARY)** (`MintModule.sol:907-993,393-418` · samplers `DegenerusGame.sol:2672-2708`, `JackpotModule.sol:1754-1793` · cursors `AdvanceModule.sol:1459-1490,307-322`): does NOT reproduce, two independent reasons — (1) **disjoint keyspaces**: SWAP sells only far-future `6≤d≤100` (levels `≥ level+6/7`); the only cursor-walks touch the *near-future* band `level+1..+5` + the FF-promotion drain of exactly `level+5` — a 5-level hard isolation gap; far-future samplers are random-index, not cursor walks, so a swap-pop can't strand them. (2) **invariant maintained**: `_removeFarFutureTickets` pops iff `newOwed==0 && rem==0` (zeroes `ticketsOwedPacked` in the same branch), caller-verified `q[idx]==player`, swap-with-last+pop loses no element; `membership ⟺ packed != 0` holds (load-bearing for the coin-jackpot sampler that awards `queue[idx]` without re-reading owed); over-sell guard reverts a double-pop; gated by `rngLockedFlag`/`gameOver`/`_livenessTriggered`. → **NEGATIVE-VERIFIED.**
- **ZD-2 SWAP timing/grinder-waiter** (`MintStreakUtils.sol:111-117` · `AdvanceModule.sol:1176,1847`): jitter seed `keccak256(player, rngWordByDay[currentDay-1])` — a settled, past, write-once-immutable VRF word (backward-trace: unknowable at the swap's commitment time; not buffered-for-next nor pre-commitment-mutable). Ceiling = d6 15% × 110% = 16.5% of face vs 100% acquisition → 83.5% loss. → **SAFE_BY_DESIGN.**
- **ZD-3 SWAP × redemption-desk** (`MintModule.sol:936-955` · `DegenerusGame.sol:1895-1923,2041-2042` · `StakedDegenerusStonk.sol:884-903`): both reservation legs are disjoint from the SWAP-drainable asset — ETH physically segregated out of `claimableWinnings[SDGNRS]` at submit; stETH leg backed by sDGNRS's own stETH custody. SWAP is a pure pool-conserving relabel (`claimablePool` unchanged); ≥1 ETH floor is a redundant cushion. → **SAFE_BY_DESIGN (desk structurally protected).**
- **ZD-4 POOL griefing** (`DegenerusVault.sol:512-516` · `StakedDegenerusStonk.sol:431-444,535-548` · `AfKing.sol:318-331`): caller-scoped `withdraw` (debit + send both to caller) + CEI + atomic read/withdraw; front-run `depositFor(vault)` only donates ETH; re-entrant `burnAtGameOver` would fail `onlyGame` (sender=AF_KING). → **NEGATIVE-VERIFIED.**
- **ZD-5 RFALL force-feed** (`DegenerusGame.sol:1895-1923` · `StakedDegenerusStonk.sol:308,858-862,896-903`): stETH donation self-covers (inflates base AND stETH-leg coverage); ETH selfdestruct can inflate `maxIncrement` to fail-closed-revert a submit, but this DoS existed identically (worse) in the old pure-ETH code, is pay-to-grief (attacker's ETH becomes permanent backing enriching all holders), and the victim's sDGNRS is not burned on revert. → **SAFE_BY_DESIGN.**
- **ZD-6 BTOMB × gameover sequencing × DGVB** (`BurnieCoin.sol:171-174,264,271,278,579-609` · `GameOverModule.sol:91,144-164,202-238`): 1e36 lands only in virtual uncirculated `vaultAllowance` (excluded from `totalSupply()`), GAME-only, one-shot, uint128-checked; conversion is `onlyVault` and BURNIE has no BURNIE→ETH path post-gameover; `totalFunds` snapshotted before side-effects; sDGNRS AfKing-recovery ETH lands in sDGNRS's own balance (not the game drain math). → **SAFE_BY_DESIGN.**
- **Summary:** zero-day-hunter: 6 probes, 2 NEGATIVE-VERIFIED, 4 SAFE_BY_DESIGN, 0 FINDING_CANDIDATE.

### B.3 `/economic-analyst` — 6 probes
- **EA-1 SWAP no-arb-at-ceiling (PRIMARY)** (`MintStreakUtils.sol:79-82,97-145` · `MintModule.sol:907-967` · `PriceLookupLib`): fraction curve `d≤20: 1500−((d−6)·500)/14` (15%→10%), `d>20: 1000−((d−20)·500)/80` (10%→5%); `jitterMult=7000+(seed%4001)` [70%,110%]; `ticketShareBps=4000+((seed>>128)%4001)` [40%,80%] tickets ⇒ cash [20%,60%]. Max TOTAL recovery (cash+tickets) @ ceiling = `fbps(6)·110% = 16.5%` of face; max withdrawable CASH (d6, 110%, 60%) = `0.15·1.10·0.60 = 9.9%` of face. All ETH-denominated (wei) → no current-vs-far price arb. Every distance dominated; cheapest acquisition (direct 100%, lootbox path ~1469%) ≫ recovery. → **NEGATIVE-VERIFIED.** _(advisory: code allows cash ≤60%, doc says ≤40% — see §D.3)_
- **EA-2 SWAP grinder-waiter EV**: jitter band only scales an already-discounted offer; absolute best day = 9.9% cash / 16.5% total ≪ 100% — favorable-day selection approaches but never crosses the ceiling. → **NEGATIVE-VERIFIED.**
- **EA-3 PFIX dust bound (F-47-01 fix)** (`LootboxModule.sol:679-749,1364-1432,1288-1292` · `StakedDegenerusStonk.sol:485-509`): divisor `1_000→400` (base `poolStart/100→poolStart/40`) confirmed by diff. Tiers tenths `[30,25,20,15,10]`; over 50 ETH E[drain]=`0.40·2.5=1.0·poolStart` (pool expected to fully drain). `transferFromPool` clamps to `available`. Monte-Carlo (30k, 1-ETH boxes): closing-buyer leftover capture mean **7.3%** (median 0%, p99 41%) vs the OLD /100 systematic mean **60%** windfall — the F-47-01 structural windfall is closed; residual is mean-zero clamped variance. Closing requires `presaleBoxCredit ≥ gap`, credit accrues at 25% of mint ETH → closing capability costs 4× the gap in real ETH (into pools). Total DGNRS out ≤ poolStart (clamp). → **SAFE_BY_DESIGN.**
- **EA-4 KEEP foreclosure + minted-credit faucet** (`DegenerusGame.sol:1773-1781` · `DegenerusAffiliate.sol:243-256,388+` · `AfKing.sol:567-849`): 75/20/5 is a winner-takes-all weighted roll (`<15→affiliate`, `15-18→upline1`, `19→upline2`) ⇒ unreferred joiner effective 80% SDGNRS / 20% VAULT (both protocol-owned), `creditFlip`'d (FLIP, no liquid transfer), human affiliate preserved via `!infoSet` fall-through. Bounty `batchLen·(BOUNTY_ETH_TARGET·PRICE_COIN_UNIT·mult)/mintPrice`, ETH-pegged, stall-mult 1/2/4/6, one `creditFlip`; self-crank needs the player's mint to actually fire (≥1 mintPrice real ETH into pools), `lastAutoBoughtDay>=today` caps 1 bounty/day/sub, no-buy tail-reverts. → **SAFE_BY_DESIGN.**
- **EA-5 HERO byte-identical RTP** (`DegeneretteModule.sol:259-280,926-953,1037-1060,529-545` · `JackpotModule.sol:1475-1538` · `TraitUtils:201-223`): independently rebuilt `P_N(S)` from the actual trait roll (symbol uniform 1/8; gold color 1/15, others 2/15) and `Σ_S P_N(S)·basePayout_N(S)` from the on-chain table constants → basePayoutEV per N = {99.9994, 99.9998, 100.0000, 99.9999, 100.0000} centi-x — all ≤100 & ~100, byte-verified. `S=9` constants byte-unchanged from old `M=8` (relabel = identical physical event). `ROI_MAX_BPS=9990` → base RTP ≤ 99.9% < 100% pre-bonus. `dailyHeroWagers`/`_rollHeroSymbol` is a hero-SYMBOL lottery (independent of score S) → the `0-8→0-9` range widening lives only in `_score`/`_getBasePayoutBps`, can't leak into the daily-hero EV. WWXRP/ETH 5% bonus is the accepted out-of-scope on-top redistribution. → **NEGATIVE-VERIFIED.**
- **EA-6 redemption-desk structural protection** (`DegenerusGame.sol:1894-1920` · `StakedDegenerusStonk.sol:824-921` · `MintModule.sol:936`): `pullRedemptionReserve` physically debits the 175% reservation out of `claimableWinnings[SDGNRS]` (CEI, ETH moved to SDGNRS) BEFORE any salvage can read the ledger; salvage reads the reduced ledger + requires a ≥1 ETH floor. Omitting a `pendingRedemptionEthValue` term is CORRECT — the funds already left the ledger salvage operates on. Segregation is the primary protection (no temporal window; atomic inside submit). → **NEGATIVE-VERIFIED.**
- **Summary:** economic-analyst: 6 probes, 4 NEGATIVE-VERIFIED, 2 SAFE_BY_DESIGN, 0 FINDING_CANDIDATE.

---

## §C — Per-probe disposition table + Outcome

| Probe | Skill | Surface | Disposition | Skeptic-filter | Tier / consensus |
|-------|-------|---------|-------------|----------------|------------------|
| CA-1 | contract-auditor | BTOMB | NEGATIVE-VERIFIED | structural (uncirculated/one-shot/checked); no EV | T2 w/ ZD-6 |
| CA-2 | contract-auditor | KEEP | NEGATIVE-VERIFIED | structural (protocol-sink routing, immutable human code); no EV | T2 w/ EA-4 |
| CA-3 | contract-auditor | POOL | NEGATIVE-VERIFIED | structural (caller-scoped withdraw); no EV | T2 w/ ZD-4 |
| CA-4 | contract-auditor | RFALL | NEGATIVE-VERIFIED | structural (same-basis coverage, fail-closed); no EV | T3 w/ ZD-5, EA(impl) |
| ZD-1 | zero-day-hunter | SWAP swap-pop | NEGATIVE-VERIFIED | structural (disjoint keyspaces + invariant + RNG-lock) | T1 (PRIMARY) |
| ZD-2 | zero-day-hunter | SWAP timing | SAFE_BY_DESIGN | structural (settled-word freeze) + EV (-83.5%) | T2 w/ EA-2 |
| ZD-3 | zero-day-hunter | SWAP×redemption | SAFE_BY_DESIGN | structural (disjoint asset backing) | T2 w/ EA-6 |
| ZD-4 | zero-day-hunter | POOL griefing | NEGATIVE-VERIFIED | structural (CEI, atomic) + EV (donate) | T2 w/ CA-3 |
| ZD-5 | zero-day-hunter | RFALL force-feed | SAFE_BY_DESIGN | structural (fail-closed, not-burned) + EV (pay-to-grief) | T3 w/ CA-4 |
| ZD-6 | zero-day-hunter | BTOMB composition | SAFE_BY_DESIGN | structural (uncirculated, onlyVault, snapshot) | T2 w/ CA-1 |
| EA-1 | economic-analyst | SWAP no-arb | NEGATIVE-VERIFIED | structural (≤16.5% face ceiling) + EV (no +EV pawn) | T1 (PRIMARY) |
| EA-2 | economic-analyst | SWAP grinder-waiter | NEGATIVE-VERIFIED | structural+EV (ceiling < acquisition) | T2 w/ ZD-2 |
| EA-3 | economic-analyst | PFIX dust bound | SAFE_BY_DESIGN | structural (≤poolStart clamp) + EV (4× credit cost, mean-zero) | T1 |
| EA-4 | economic-analyst | KEEP faucet | SAFE_BY_DESIGN | structural (protocol sinks, work-gated bounty) + EV (no self-crank) | T2 w/ CA-2 |
| EA-5 | economic-analyst | HERO RTP | NEGATIVE-VERIFIED | structural (≤100 per-N reproduced; S-isolated jackpot) | T1 |
| EA-6 | economic-analyst | redemption-desk | NEGATIVE-VERIFIED | structural (physical segregation, no window) | T2 w/ ZD-3 |

### §C.1 Outcome summary
- **16 probe-rows** across the 7 v48 surfaces + composition: **10 NEGATIVE-VERIFIED · 6 SAFE_BY_DESIGN · 0 FINDING_CANDIDATE.**
- **Clean closure outcome: ZERO FINDING_CANDIDATEs survive the dual-gate skeptic filter.** The `0 NEW_FINDINGS` clause of the closure verdict HOLDS.
- The two v47-deferred fixes are re-confirmed holding: **F-47-01** (PFIX dust bound — EA-3, SAFE_BY_DESIGN, windfall closed) and **F-47-02** (RFALL donation-robustness — CA-4/ZD-5, fail-closed + same-basis coverage).
- The PRIMARY SWAP-pop H-CANCEL-SWAP-MISS regression probe (ZD-1) is **NEGATIVE-VERIFIED** — the operation class does not reproduce (disjoint keyspaces + `membership ⟺ packed != 0` + RNG-lock gate), matching the SWAP-06 SPEC enumeration (325-02) + the 327-05 membership proof.
- Cross-skill consensus: every surface received ≥1 probe; SWAP, RFALL, KEEP, POOL, BTOMB each got multi-skill cross-confirmation (Tier-2/Tier-3), strengthening the clean result.

---

## §D — Skeptic-Reviewer Filter Attestation (dual-gate)

### §D.1 Dual-gate applied
The mandatory dual-gate (per `feedback_skeptic_pass_before_catastrophe`) was applied at BOTH layers:
1. **Per-skill self-arm** — each subagent self-applied the structural-protection check + 3-condition EV lens to every probe before reporting (recorded in §B per row).
2. **Orchestrator integration-time re-application** — at fold-in, every elevation was re-run through both gates. ZERO elevations reached FINDING_CANDIDATE: each either failed the structural-protection gate (a structural mechanism already prevents it) or failed the 3-condition EV lens (no positive-EV path / immaterial magnitude / severity does not survive re-read). No self-discards required beyond the dispositions recorded — no probe produced a borderline elevation that needed downgrading.

### §D.2 OPEN-E operator-trust boundary honored
The SWAP `sellFarFutureTickets` is the first value-destructive operator-gated action. Per the LOCKED OPEN-E disposition (`open-e-operator-approval-trust-boundary`), operator-approval IS the trust boundary — no "tricked into approving" actor was modelled. The swap-pop / drain probes treated the operator as a consented same-principal/fixed-contract grantee.

### §D.3 Advisory (NON-finding) — SWAP cash-share ceiling: code 60% vs design ≤40%
Independently surfaced by `/economic-analyst` (EA-1) and `/zero-day-hunter` (ZD-2), and orchestrator-verified directly against the frozen subject:
- `DegenerusGameMintStreakUtils.sol:118` @ `1575f4a9`: `ticketShareBps = 4000 + ((seed >> 128) % 4001); // ticket share [40%,80%] (cash [20%,60%])`.
- The frozen code permits a **withdrawable-cash share up to 60%** of the swap budget; the v48 design memo / SPEC describe "~60% tickets + **≤40%** withdrawable ETH". Midpoint (60/40) matches the design center; the implemented range extends to 60% cash at the jitter extreme.
- **Skeptic-filter outcome: NOT a finding.** No-arb is verified at the actual 60% ceiling (max withdrawable cash = 9.9% of face — deeply -EV), the redemption desk is structurally segregated (EA-6/ZD-3), and the ≥1 ETH claimable floor is preserved. There is no positive-EV path and no solvency impact at 60% vs 40%.
- **Disposition: ADVISORY / doc-drift.** Recorded for USER visibility at the 328-04 closure gate. Action: reconcile the design memo/verdict text to the implemented `≤60%` cash ceiling, OR confirm the 60% ceiling was the intended IMPL calibration. The closure verdict's SWAP clause is amended to state the **actual** `≤60%` cash ceiling (see §9a / the findings deliverable). `0 NEW_FINDINGS` is unaffected (this is a documentation discrepancy, not a vulnerability).

### §D.4 Read-only attestation
`git diff 1575f4a9 HEAD -- contracts/` is empty throughout this sweep — no `contracts/*.sol` was opened or mutated; all source was read via `git show 1575f4a9:...`.
