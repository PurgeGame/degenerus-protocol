---
phase: 328-terminal-delta-audit-3-skill-adversarial-sweep-closure
plan: 03
milestone: v48.0
milestone_name: sDGNRS Far-Future Salvage Swap + v47 Deferred-Findings Fixes + Keeper/Pool/Tombstone/Hero Bundle
audit_baseline: da5c9d50989707c8964a9411e68c51ca1b1a25f2
audit_baseline_signal: MILESTONE_V47_AT_HEAD_da5c9d50989707c8964a9411e68c51ca1b1a25f2
v46_baseline_signal: MILESTONE_V46_AT_HEAD_16e9668a6de35cc0c809d81ce960aee137950687
source_tree_frozen_ref: 1575f4a9
audit_subject_head: "MILESTONE_V48_AT_HEAD_<sha>"
closure_signal: MILESTONE_V48_AT_HEAD_<sha>
deliverable: audit/FINDINGS-v48.0.md
new_findings: 0
new_findings_disposition: 0 NEW_FINDINGS — both v47-deferred MEDIUM findings (F-47-01 presale closing-box DGNRS over-distribution + F-47-02 redemption submit ETH-empty stETH-fallback gap) RESOLVED-AT-V48; one informational ADVISORY (SWAP cash-share ceiling 60% code vs <=40% design memo — no-arb holds, doc-drift for USER reconciliation, NOT a finding)
---

# v48.0 Findings — sDGNRS Far-Future Salvage Swap + v47 Deferred-Findings Fixes + Keeper/Pool/Tombstone/Hero Bundle (Terminal)

## 1. Audit Subject + Baseline

**Audit Baseline.** v47.0 closure HEAD `da5c9d50989707c8964a9411e68c51ca1b1a25f2` (signal
`MILESTONE_V47_AT_HEAD_da5c9d50989707c8964a9411e68c51ca1b1a25f2`). v46 chain reference:
`MILESTONE_V46_AT_HEAD_16e9668a6de35cc0c809d81ce960aee137950687`. v48.0 closure HEAD is
`MILESTONE_V48_AT_HEAD_<sha>` (resolved at the Phase 328 closure commit per the single-commit
sequential-SHA closure orchestration; see §9c). SOURCE-TREE FROZEN reference for the terminal:
`1575f4a9` (contracts/ byte-frozen; `git diff 1575f4a9 HEAD -- contracts/` empty throughout Phase 328).

**Subject.** The frozen subject HEAD `1575f4a9` = the Phase 326 IMPL batched diff `f50cc634` + the
Phase 327 HERO-04 byte-reproduced Degenerette payout-finals constant-landing `1575f4a9`. Every v47->v48
`contracts/` commit (`git log da5c9d50..1575f4a9 -- contracts/`):
- `f50cc634` — the single batched Phase 326 IMPL diff (USER-APPROVED hand-review): the seven v48 work
  items reconciled across 12 files (`git diff da5c9d50..1575f4a9 -- contracts/` = 12 files, +611 / -324) —
  **PFIX** (presale-box DGNRS drain fix, F-47-01), **RFALL** (redemption ETH-empty stETH fallback, F-47-02),
  **KEEP** (keeper rename autoBuy/autoOpen/autoResolve + `bytes32("DGNRS")` VAULT-code affiliate wiring),
  **POOL** (AfKing prepaid-pool recovery), **BTOMB** (gameover BURNIE 1e36-wei tombstone), **HERO**
  (Degenerette hero 2-point rescale, standalone multiplier net-deleted), **SWAP** (sDGNRS far-future
  salvage swap).
- `1575f4a9` — the USER-APPROVED HERO-04 byte-reproduced Degenerette payout finals: 15 byte-reproduced
  constants (5 `QUICK_PLAY_PAYOUTS_N{0..4}_PACKED` + 5 `QUICK_PLAY_PAYOUT_N{0..4}_S8` + 5
  `WWXRP_FACTORS_N{0..4}_PACKED`) landed into `DegenerusGameDegeneretteModule.sol`. **Constant-only**, 0
  storage impact; the frozen subject HEAD.

v48.0 is a contract-accounting/behavior bundle that closes two v47-deferred MEDIUM findings and ships a
sanctioned -EV exit + four refinements. It ships the full 9-section deliverable, `chmod 444` at close.

---

## 2. Executive Summary

### Closure Verdict Summary
v48.0 resolves the two v47.0-deferred MEDIUM findings (**F-47-01** presale closing-box DGNRS
over-distribution — divisor `1_000->400`; **F-47-02** redemption submit ETH-empty stETH-fallback gap —
pure-ETH-OR-pure-stETH, donation-robust, fail-closed), renames the keeper surface
(`crank`/`sweep`/`do-work` -> autoBuy/autoOpen/autoResolve) and wires VAULT's registered `bytes32("DGNRS")`
two-tier 75/20/5 affiliate code (foreclosure intended), makes the AfKing prepaid pools recoverable
(VAULT permissionless `recoverAfKingPool()` + sDGNRS `burnAtGameOver()` auto-recovery + `receive()`
AF_KING relax), floods BURNIE's virtual VAULT mint-allowance by 1e36 wei at gameOver as an honest
worthless-token tombstone (circulating `totalSupply()` untouched), rescales the Degenerette hero to a
2-point scoring element (`S = A + 2*H`, standalone multiplier net-deleted, per-N `basePayoutEV` byte-
reproduced <=100 centi-x, `S=9 == old M=8` relabel), and ships the sDGNRS far-future salvage swap
(`sellFarFutureTickets`, -EV by design). The SC1 delta-audit + the SC2 3-skill genuine-PARALLEL
adversarial sweep + the LEAN regression find the change set sound with **0 NEW FINDINGS** — both v47-
deferred findings are re-confirmed RESOLVED-AT-V48 and the sweep surfaced zero FINDING_CANDIDATE. One
informational ADVISORY (the SWAP withdrawable-cash ceiling is 60% in code vs <=40% in the design memo;
no-arb holds; doc-drift for USER reconciliation, NOT a vulnerability — §4.4 / §9d).

### Verdict Math
- **Adversarial sweep (Phase 328 SC2):** 16 deduplicated disposition rows across the 7 v48 surfaces +
  composition — **10 NEGATIVE-VERIFIED / 6 SAFE_BY_DESIGN / 0 FINDING_CANDIDATE**. 0 skeptic-filter
  self-discards; 0 orchestrator integration-time discards. Multi-skill cross-confirmation: SWAP, RFALL,
  KEEP, POOL, BTOMB each received >=1 Tier-2/Tier-3 consensus row.
- **Delta-audit (Phase 328 SC1):** every one of the 7 v48 work-item surfaces attests NON-WIDENING vs
  `da5c9d50` with grep/diff anchors; the keeper kill-set (`crank`/`sweep`/`do-work`) is grep-ZERO in
  mainnet code (`AfKing.sol` + `DegenerusGame.sol` in-game entrypoints), and the standalone-hero-multiplier
  kill-set (`_applyHeroMultiplier`/`HERO_BOOST_*`/`HERO_PENALTY`/`HERO_SCALE`) is grep-ZERO in
  `DegeneretteModule.sol`. Each delta hunk maps to exactly one of the 7 surfaces (no orphan hunks across
  the four multi-item shared files).
- **Regression:** NON-WIDENING; foundry suite **632 pass / 42 fail of 674** (`594 + 38 NEW_PASSING` + `0
  net-new` vs the 326-08 594/42 baseline) — 38 new passing tests fully attributed to the 5 wave-1 test
  files + the redemption invariant extension; the 42 reds classify into named buckets (8 VRF/RNG
  pre-existing + 34 stale-harness/v48-behavioral fixtures, owned by a future fixture-repair plan). The
  HERO-04 byte-reproduce Hardhat stat gate flipped 15/20-diverge-RED -> 0-diff-GREEN at `1575f4a9`
  (per-N `basePayoutEV == 100 centi-x`, ETH bonus == 5.000%); the forge 42-count is unchanged (the
  byte-reproduce red was Hardhat-only).

### Severity Counts
- CATASTROPHE 0 · HIGH 0 · MEDIUM 0 (both v47-deferred MEDIUMs RESOLVED-AT-V48) · LOW 0 · informational
  SAFE_BY_DESIGN 6 · informational ADVISORY 1 (SWAP cash-share doc-drift).

### KI Gating Rubric Reference
KNOWN-ISSUES.md byte-unmodified vs v47 (§6). No KI promotion/demotion this milestone.

### Forward-Cite Closure Summary
Two forward items, both **RESOLVED-AT-V48** (§8): **F-47-01** (presale closing-box DGNRS over-distribution,
the v47.0-deferred MEDIUM) closed by PFIX-01 (divisor `1_000->400`) + the PFIX-02/03 dust-bound proof; and
**F-47-02** (redemption submit ETH-empty stETH-fallback gap, the v47.0-deferred MEDIUM) closed by
RFALL-01/02/03 (pure-ETH/stETH fallback) + the RFALL-05 / POOL-04 regression proof. The three prior-
milestone v48 descriptive seeds (keeper-rename, gameover-burnie-tombstone, sDGNRS far-future salvage swap)
are now SHIPPED.

### Attestation Anchor
All `contracts/` file:line anchors herein are sourced from the Phase 328 workstream logs (328-01-DELTA-AUDIT,
328-02-ADVERSARIAL-LOG), each re-grep-verified against the frozen subject `1575f4a9`
(`git diff 1575f4a9 HEAD -- contracts/` empty).

---

## 3. Per-Phase Sections

- **§3a Phase 325 — SPEC (design-lock).** `f7ad4ee2` (3 plans, VERIFICATION 5/5, paper-only — zero contract
  mutation) — the locked v48.0 design across the 7 work items + the call-graph attestation (BATCH-01):
  shared-surface signature reconciliation across `DegenerusGame`/`StakedDegenerusStonk`/`DegenerusVault`,
  the load-bearing SWAP-08 no-arb floor RE-CONFIRMED at the v47.0-closure HEAD (salvage ceiling 16.5% <
  acquisition ~21%, margin ~4.5pp @d6; STOP NOT triggered), the SWAP-03 jitter source pinned to a SETTLED
  past VRF word (`rngWordByDay[currentDay-1]`, freeze-safe), the SWAP-06 swap-pop enumeration (11
  `ticketQueue` consumers; H-CANCEL-SWAP-MISS proven absent on paper), and every SPEC-time open item
  resolved (RFALL-04, KEEP-04/05, POOL-06, BTOMB packing, HERO-04 shape+packing). The verifier caught and
  closed an INVERTED KEEP-04 owner attribution -> USER-LOCKED two-tier affiliate routing primary
  SDGNRS(protocol) / secondary VAULT via `bytes32("DGNRS")`.
- **§3b Phase 326 — IMPL (the ONE batched contract diff).** `f50cc634` (USER-APPROVED hand-review;
  VERIFICATION 6/6) — all seven work items as a single reconciled `contracts/*.sol` diff (12 files,
  +611/-324), forge 594/42 no-net-regression. PFIX-01 · RFALL-01/02/03 · KEEP-01/02/03 · POOL-01/02/03/05 ·
  BTOMB-01/02 · HERO-01/02/03/05 · SWAP-01..07 · BATCH-02. 3 USER steers folded in (SWAP ticket = normal
  mint, SWAP -> MintModule, new `previewSellFarFutureTickets`).
- **§3c Phase 327 — TST.** 6 plans (sequential, USE_WORKTREES=false; 5 new `test/fuzz/*` files green):
  presale-drain dust bound (PFIX-02/03 `PresaleBoxDrain.t.sol` 3/3), redemption-fallback regression
  (RFALL-05 `RedemptionStethFallback.t.sol` 10/10 + `RedemptionAccounting.t.sol` 16->18 invariants) + sDGNRS
  `receive()` accounting-safety (POOL-04), BURNIE-tombstone non-circulating (BTOMB-03 `BurnieTombstone.t.sol`
  8/8), Degenerette byte-reproduce (HERO-04/06 `DegeneretteHeroScore.t.sol` 6/6 + the Hardhat stat gate),
  salvage-swap no-arb at the band ceiling + solvency (SWAP-08/09 `FarFutureSalvageSwap.t.sol` 9/9). The
  327-06 full-suite regression gate proved NET-ZERO new regression (632/42). The HERO-04 byte-reproduced
  Degenerette payout finals then LANDED into the frozen contract (`1575f4a9`, USER-approved hand-review,
  constant-only) -> the Hardhat PASS_ALL byte-reproduce gate flips 0-diff GREEN; forge stays 632/42.
- **§3d Phase 328 — TERMINAL.** This deliverable; SOURCE-TREE FROZEN at `1575f4a9`; the SC1 delta-audit +
  the SC2 3-skill GENUINE PARALLEL_SUBAGENT sweep + the regression + the gated closure flip.

### §3.A Delta-Surface Table (folded from 328-01-DELTA-AUDIT.md §2)

| Surface | Requirements | Re-grepped anchors @ `1575f4a9` | Disposition |
| --- | --- | --- | --- |
| **PFIX** — presale-box DGNRS drain fix (F-47-01) | PFIX-01·02·03 | `_presaleBoxDgnrsReward` divisor `1_000 -> 400`, base `poolStart/100 -> poolStart/40` (`LootboxModule:719/:709/:717`; curve comment `:299-302`); tier shape preserved (`PRESALE_BOX_DGNRS_TIER1..5_TENTHS = 30/25/20/15/10`, `:304-308`, tier-1 still 3x tier-5); `transferFromPool(Pool.PresaleBox,...)` clamp held (`:720`). ISOLATED — only `LootboxModule.sol` (15-line diff). PFIX-02/03 dust-bound proof: `test/fuzz/PresaleBoxDrain.t.sol` (327-01, 3/3). | **NON-WIDENING** |
| **RFALL** — redemption ETH-empty stETH fallback (F-47-02) | RFALL-01·02·03·04·05 | `pullRedemptionReserve(uint256)` rewritten pure-ETH OR pure-stETH, no mix (`DegenerusGame.sol:1896`): ETH leg checked debit + CEI move-out (`:1900-1909`); stETH leg fallback against `steth.balanceOf(SDGNRS) >= amount`, no game-side move (`:1916-1918`); `revert E()` fail-closed if neither covers (`:1921`). sStonk `_submitGamblingClaimFrom` + `_payEth` ETH-then-stETH selection updated (`StakedDegenerusStonk.sol:884-892`/`:930-938`); `pendingRedemptionEthValue` single-tracked-value shape held (RFALL-04). Donation-robust (same-asset-basis coverage). RFALL-05: `test/fuzz/RedemptionStethFallback.t.sol` (327-02, 10/10) + `invariant_RFALL05_SolvencyUnderFallback`. | **NON-WIDENING** |
| **KEEP** — keeper rename + VAULT affiliate code | KEEP-01·02·03·04·05 | Kill-set **grep-ZERO**: `crank`/`sweep`/`do-work` = 0 in `AfKing.sol` AND `DegenerusGame.sol` in-game entrypoints. New names: `AfKing.autoBuy(uint256)` (`:567`), `autoBuyProgress()` (`:527`); `DegenerusGame.autoResolve(...)` (`:1587`), `autoOpen(uint256)` (`:1636`), `enqueueBoxForAutoOpen(...)` (`:1570`), `_autoResolveBet`/`_autoOpenBox` (`:1684`/`:1705`). `creditFlip`/`BOUNTY_ETH_TARGET` KEPT (KEEP-02). Affiliate two-tier wiring: keeper purchase passes `bytes32("DGNRS")` (was `0`) at `_batchPurchaseUnit` (`:598`), USER-LOCKED KEEP-04 — primary 75% SDGNRS (protocol; `DegenerusAffiliate.sol:247-250`) / secondary 20% VAULT; human affiliate preserved via `!infoSet` fall-through. Interface rename `enqueueBoxForCrank -> enqueueBoxForAutoOpen`. | **NON-WIDENING** |
| **POOL** — AfKing pool recovery | POOL-01·02·03·04·05·06 | VAULT permissionless `recoverAfKingPool()` -> `afKing.withdraw(afKing.poolOf(address(this)))` (`DegenerusVault.sol:38-40`; no owner/gameOver gate; `withdraw` sends to CALLER). sDGNRS `receive()` relaxed to accept `AF_KING` (`StakedDegenerusStonk.sol:439-443`). sDGNRS `burnAtGameOver()` (`onlyGame`) auto-recovers at `:539` BEFORE the `balanceOf(this)==0` early-return (`:541`); `withdraw(0)` no-op can't brick gameOver. NO standalone sDGNRS withdraw. Interface adds `withdraw(uint256)` + `poolOf(address)` matching `AfKing.sol` verbatim; **AfKing recovery LOGIC UNCHANGED** (only AfKing diff is item-3 rename). POOL-04 proof: 327-02. | **NON-WIDENING** |
| **BTOMB** — gameover BURNIE tombstone | BTOMB-01·02·03 | `BurnieCoin.tombstoneAtGameOver()` (`:36`): GAME-only, one-shot via `_tombstoneFlooded` latch (`:22`/`:38-39`); `_supply.vaultAllowance += BURNIE_TOMBSTONE_WEI` (`:40-42`, `BURNIE_TOMBSTONE_WEI = 1e36`, `:12`); CHECKED add via `_toUint128` (1e36 << uint128 max ~3.4e38, ~340x headroom — BTOMB-02). Circulating `totalSupply()` UNTOUCHED (signal lands only in `supplyIncUncirculated()`/`vaultMintAllowance()`/`balanceOf(VAULT)`, `:33`). Wired one-shot from `GameOverModule` (`:31`/`:152`). BTOMB-03 proof: `test/fuzz/BurnieTombstone.t.sol` (327-03, 8/8). | **NON-WIDENING** |
| **HERO** — Degenerette hero 2-pt rescale | HERO-01·02·03·04·05·06 | Standalone-multiplier kill-set **grep-ZERO** (`_applyHeroMultiplier`/`HERO_BOOST`/`HERO_PENALTY`/`HERO_SCALE` = 0 in `DegeneretteModule.sol`). Scoring `S = A + 2*H in {0..9}` — `_score(...)` replaces `_countMatches` (`:673`; comments `:245`/`:95`). Hero quadrant mandatory (`heroQuadrant >= 4` revert, `:495`; `FT_HERO_SHIFT` decode kept `:337`/`:629`/`:893-896`). 15 byte-reproduced finals landed at `1575f4a9` (constant-only). HERO-04 PASS_ALL byte-reproduce gate: Hardhat 0-diff GREEN (per-N `basePayoutEV == 100 centi-x`, ETH bonus == 5.000%; `DegenerettePerNEvExactness` + `DegeneretteBonusEv`); HERO-06 write-batch DGAS equivalence + `dailyHeroWagers` no-leak: `test/fuzz/DegeneretteHeroScore.t.sol` (327-04, 6/6). | **NON-WIDENING** |
| **SWAP** — sDGNRS far-future salvage swap | SWAP-01·02·03·04·05·06·07·08·09 | `DegenerusGame.sellFarFutureTickets(player, levels, quantities, queueIndices)` (`:1933`): `_resolvePlayer` operator-honor (`:1939`); delegatecall to MintModule (`:1944`). MintModule body: `rngLocked`-gated; ticket-floor-first (`oneTicketWei = priceForLevel(_activeTicketLevel())`, revert if `totalBudget < oneTicketWei`); inline fail-closed claimable debit `claimableWinnings[SDGNRS] < totalBudget + 1 ether` revert (>=1 ETH floor, NO `pendingRedemptionEthValue` term); `claimableWinnings[SDGNRS] -= totalBudget` claimant-to-claimant relabel (claimablePool unchanged); per-line `_removeFarFutureTickets` O(1) caller-verified swap-pop (`q[idx]==player`) maintaining `membership <=> packed != 0`; d-curve + settled-word jitter (`_farFutureFractionBps` + `_quoteFarFutureSwap`, `MintStreakUtils.sol:19`/`:37`). VAULT `gameSellFarFutureTickets(...) onlyVaultOwner` wrapper (`DegenerusVault.sol:51-55`). SWAP-08 no-arb (margin ~4.5pp @d6) + SWAP-09 solvency: `test/fuzz/FarFutureSalvageSwap.t.sol` (327-05, 9/9). | **NON-WIDENING** |

All 40 v48.0 REQ-IDs are referenced in the table above (PFIX 3 · RFALL 5 · KEEP 5 · POOL 6 · BTOMB 3 ·
HERO 6 · SWAP 9 · BATCH 3 [BATCH-01 SPEC `325-SPEC.md`; BATCH-02 IMPL the batched diff `f50cc634`; BATCH-03
= this TERMINAL audit]).

### §3.B Composition Attestation Matrix (folded from 328-01 §3)
- **No orphan hunks across the four multi-item shared files.** `DegenerusGame.sol` (160 lines, items 2/3/7):
  every hunk lands in exactly one of {RFALL `pullRedemptionReserve` rewrite + submit/`_payEth` comments
  `:1896-1921`; KEEP `autoResolve`/`autoOpen`/`enqueueBoxForAutoOpen` renames + `bytes32("DGNRS")` wiring
  `:598`/`:1570-1705`; SWAP `sellFarFutureTickets` `:1933-1944`}. `StakedDegenerusStonk.sol` (39 lines,
  items 2/4): RFALL `_submitGamblingClaimFrom`/`_payEth` || POOL `receive()` relax + `burnAtGameOver`
  recover + interface adds. `DegenerusVault.sol` (29 lines, items 3/4/7): POOL `recoverAfKingPool()` || SWAP
  `gameSellFarFutureTickets` wrapper || KEEP affiliate-routing through the game. The two interfaces: KEEP
  rename + SWAP add + POOL `withdraw`/`poolOf` adds — each decl maps to one surface. Conclusion: **zero
  orphan hunks** across the +611/-324 delta.
- **claimable-balance preserved (`claimablePool == Sum claimableWinnings`):** RFALL ETH leg debits
  `claimableWinnings[SDGNRS]` AND `claimablePool` in lockstep (`:1905-1906`); stETH leg moves nothing
  (records via `pendingRedemptionEthValue`). SWAP cash leg is a pure claimant-to-claimant **relabel**
  (`claimablePool` unchanged); the ticket leg routes ETH into pools (slack gained). POOL recovery only moves
  donated AfKing-pool ETH back via `address(this).balance` (no claimable entry created/destroyed). NON-WIDENING.
- **BURNIE-net / tombstone non-circulating:** BTOMB floods only the virtual `_supply.vaultAllowance` by 1e36
  wei (one-shot, GAME-gated, CHECKED); no mint, `totalSupply()` untouched, ~340x below uint128 max (BTOMB-03).
  KEEP keeps the v46 `creditFlip` minted-flip-credit bounty UNCHANGED (no new BURNIE emission). NON-WIDENING.
- **RNG-freeze-intact (no new in-window VRF consumer):** SWAP jitter seeds off an already-SETTLED past VRF
  word (`rngWordByDay[currentDay-1]`, freeze-safe per `v45-vrf-freeze-invariant`); `rngLocked`-gated; the
  swap-pop is deterministic bookkeeping. HERO write-batch is bookkeeping-only post-outcome (per-spin `S`
  from the already-resolved result; tables are constants); `dailyHeroWagers`/`_rollHeroSymbol` unaffected
  (HERO-06 no-leak). PFIX reuses the v47 committed-word + domain-salt path UNCHANGED (only the scalar divisor
  moved). **Composition verdict: NON-WIDENING across all four axes.**

### §3.C Requirement Re-Attestation
All 40 v48.0 requirements (PFIX 3 · RFALL 5 · KEEP 5 · POOL 6 · BTOMB 3 · HERO 6 · SWAP 9 · BATCH 3) are
re-attested at closure. The IMPL/TST/SPEC dispositions: **PFIX-01** divisor `1_000->400` (`LootboxModule:719`)
+ **PFIX-02/03** dust-bound proof (327-01, mean closing-buyer leftover capture 7.3% vs the old systematic
60%); **RFALL-01/02/03** pure-ETH-OR-pure-stETH fallback (`DegenerusGame.sol:1896-1921`) + **RFALL-04**
single-tracked-`pendingRedemptionEthValue` shape (SPEC) + **RFALL-05** REDEEM-08 invariants under fallback
(327-02); **KEEP-01/02/03** rename + `creditFlip` kept + `bytes32("DGNRS")` wiring + **KEEP-04/05** VAULT
registered-code prerequisite + autoOpen scoping (SPEC, USER-LOCKED two-tier 75/20/5); **POOL-01/02/03/05**
VAULT `recoverAfKingPool()` + sDGNRS `receive()` AF_KING relax + `burnAtGameOver` recover + verbatim
interface adds + **POOL-04** `address(this).balance` accounting-safety (327-02) + **POOL-06** post-gameOver
re-stranding decision (SPEC); **BTOMB-01/02** 1e36 one-shot checked flood + **BTOMB-03** non-circulating
signal (327-03); **HERO-01/02/03/05** `S=A+2*H` scoring + standalone-multiplier net-deletion + per-N table
recalibration + `S=9==old M=8` relabel + **HERO-04** byte-reproduce PASS_ALL gate (327-04, 0-diff GREEN @
`1575f4a9`) + **HERO-06** write-batch DGAS equivalence + daily-hero no-leak; **SWAP-01..07** entrypoint +
d-curve + jitter + ticket-floor + inline fail-closed claimable debit + swap-pop + VAULT wrapper +
**SWAP-08** no-arb at the band ceiling (327-05, margin ~4.5pp @d6) + **SWAP-09** solvency; **BATCH-01** SPEC
design-lock (325) + **BATCH-02** the batched IMPL diff (`f50cc634`) + **BATCH-03** this TERMINAL audit. The
actual REQUIREMENTS.md row-flip to Complete is 328-04's closure-gate job; §3.C records the attestation
narrative. NOTE: **40 requirements, NOT 45** (v47 had 45; v48 has 40).

---

## 4. Adversarial-Pass Disposition (folded from 328-02-ADVERSARIAL-LOG.md)

### §4.1 Outcome
3-skill GENUINE PARALLEL_SUBAGENT sweep (`/contract-auditor` + `/zero-day-hunter` + `/economic-analyst`;
`/degen-skeptic` OUT per D-271-ADVERSARIAL-02), run as 3 concurrent background Task spawns from the
orchestrator (the plan ran INLINE in the main context, which holds the Task tool — the v45 P314 / v47 P324
genuine-parallel path, NOT the HYBRID fallback). **16 deduplicated disposition rows across the 7 v48
surfaces + composition: 10 NEGATIVE-VERIFIED + 6 SAFE_BY_DESIGN + 0 FINDING_CANDIDATE.** 0 skeptic-filter
self-discards; 0 orchestrator integration-time discards. The five charged-probe families (SWAP no-arb /
swap-pop H-CANCEL-SWAP-MISS regression / RFALL donation-robustness / PFIX dust bound / POOL pool-recovery)
each have >=1 row; every surface received multi-skill cross-confirmation (Tier-2/Tier-3). **Clean closure
outcome: ZERO FINDING_CANDIDATEs survive the dual-gate skeptic filter — the `0 NEW_FINDINGS` clause of the
closure verdict HOLDS.** Each subagent probed the actual frozen subject via `git show 1575f4a9:contracts/...`
(READ-ONLY; `git diff 1575f4a9 HEAD -- contracts/` empty throughout).

### §4.2 FINDING_CANDIDATEs
**None.** Zero elevations reached FINDING_CANDIDATE. Both v47-deferred findings are re-confirmed holding:
- **F-47-01** (PFIX dust bound — economist EA-3, SAFE_BY_DESIGN): divisor `1_000->400` confirmed by diff;
  Monte-Carlo (30k, 1-ETH boxes) closing-buyer leftover capture mean **7.3%** (median 0%, p99 41%) vs the
  OLD `/100` systematic **60%** — the structural windfall is closed; residual is mean-zero clamped variance;
  `transferFromPool` still clamps to the live pool balance (no over-drain / no mint).
- **F-47-02** (RFALL donation-robustness — auditor CA-4 / hunter ZD-5): coverage pure-ETH-OR-pure-stETH,
  fail-closed only when neither single leg covers the 175%; donation-robust (stETH-leg coverage reads
  `steth.balanceOf(SDGNRS)` — the exact basis a donation inflates); worst case = self-DoS on an oversized
  single burn (recoverable by burning less), nothing lost / nothing burned on revert.

The PRIMARY SWAP-pop H-CANCEL-SWAP-MISS regression probe (hunter ZD-1) is **NEGATIVE-VERIFIED** — the
operation class does not reproduce (disjoint keyspaces: SWAP sells only far-future `6<=d<=100` while cursor
walks touch only `level+1..+5`, a 5-level isolation gap; `membership <=> packed != 0` maintained;
`rngLocked`/gameOver/`_livenessTriggered`-gated), matching the SWAP-06 SPEC enumeration (325-02) + the
327-05 membership proof.

### §4.3 SAFE_BY_DESIGN rows (informational)
- **SWAP grinder-waiter timing** (hunter ZD-2, economist EA-2): jitter seed off a settled past VRF word;
  ceiling = d6 15% x 110% = 16.5% of face vs 100% acquisition -> 83.5% loss; favorable-day selection never
  crosses the ceiling.
- **SWAP x redemption-desk** (hunter ZD-3, economist EA-6): both reservation legs disjoint from the
  SWAP-drainable asset (ETH physically segregated out of `claimableWinnings[SDGNRS]` at submit; stETH leg
  backed by sDGNRS's own custody); SWAP is a pure pool-conserving relabel; >=1 ETH floor is a redundant
  cushion; omitting the `pendingRedemptionEthValue` term is CORRECT (funds already left the ledger).
- **RFALL force-feed** (hunter ZD-5): stETH donation self-covers; ETH selfdestruct can fail-closed-revert a
  submit but that DoS existed identically (worse) in the old pure-ETH code, is pay-to-grief (attacker's ETH
  becomes permanent backing), and the victim's sDGNRS is not burned on revert.
- **BTOMB x gameover sequencing x DGVB** (auditor CA-1, hunter ZD-6): 1e36 lands only in virtual
  uncirculated `vaultAllowance` (excluded from `totalSupply()`), GAME-only, one-shot, uint128-checked; DGVB
  pro-rata claim `<= 3.4e68 << uint256 max` (no overflow); `totalFunds` snapshotted before side-effects.
- **PFIX dust bound** (economist EA-3) — see §4.2.
- **KEEP foreclosure + minted-credit faucet** (auditor CA-2, economist EA-4): 75/20/5 winner-takes-all roll
  => unreferred joiner effective 80% SDGNRS / 20% VAULT (both protocol sinks), `creditFlip`'d (no liquid
  transfer); human affiliate preserved via `!infoSet` fall-through; bounty ETH-pegged, `lastAutoBoughtDay`
  caps 1 bounty/day/sub, self-crank needs the player's mint to actually fire (>=1 mintPrice real ETH into
  pools).

### §4.4 Skeptic-Reviewer Filter Attestation
Dual-gate filter (structural-protection check -> 3-condition EV lens) applied per-skill self-arm + orchestrator
integration-time re-application. ZERO elevations reached FINDING_CANDIDATE: each either failed the
structural-protection gate or failed the 3-condition EV lens. No "tricked into approving" actor modeled
(per `open-e-operator-approval-trust-boundary`); the SWAP `sellFarFutureTickets` operator-gated action was
treated as a consented same-principal/fixed-contract grantee (OPEN-E disposition honored).

**ADVISORY (NON-finding) — SWAP cash-share ceiling: code 60% vs design <=40%.** Independently surfaced by
`/economic-analyst` (EA-1) and `/zero-day-hunter` (ZD-2), orchestrator-verified directly against the frozen
subject: `DegenerusGameMintStreakUtils.sol:118` @ `1575f4a9` — `ticketShareBps = 4000 + ((seed >> 128) %
4001)` -> ticket share `[40%,80%]` => withdrawable-cash share `[20%,60%]`. The frozen code permits a
withdrawable-cash ceiling of **60%, not the <=40% described in the v48 design memo / SPEC**. No-arb HOLDS at
the actual 60% ceiling (max withdrawable cash = `0.15 x 1.10 x 0.60 = 9.9%` of face — deeply -EV); the
redemption desk is structurally segregated (EA-6/ZD-3); the >=1 ETH claimable floor is preserved. **Skeptic-
filter outcome: NOT a finding** (a documentation discrepancy, not a vulnerability — no positive-EV path, no
solvency impact at 60% vs 40%). **Disposition: ADVISORY / doc-drift, recorded for USER reconciliation at the
328-04 closure gate** — reconcile the design memo / verdict text to the implemented `<=60%` cash ceiling, OR
confirm 60% was the intended IMPL calibration. The closure verdict's SWAP clause is authored with the ACTUAL
`<=60% withdrawable cash` ceiling (§9a). `0 NEW_FINDINGS` is unaffected.

**Read-only attestation.** `git diff 1575f4a9 HEAD -- contracts/` is empty throughout the sweep — no
`contracts/*.sol` was opened or mutated; all source was read via `git show 1575f4a9:...`.

---

## 5. LEAN Regression Appendix (folded from 328-01 §4)

### §5a Suite Baseline — 632 pass / 42 fail of 674, NON-WIDENING vs the 326-08 594/42 baseline
Per the 327-06 ledger `test/REGRESSION-BASELINE-v48.md` (the full `forge test` tree, NOT `--match-path`):
`632 == 594 + 38 NEW_PASSING` ✓ ; `42 == 42 + 0 net-new` ✓. The **38 NEW_PASSING** are fully attributed to
the 5 wave-1 test files + the redemption invariant extension (all PASSING-only, zero red): `PresaleBoxDrain`
3 + `RedemptionStethFallback` 10 + `RedemptionAccounting` invariant extension +2 (16->18) + `BurnieTombstone`
8 + `DegeneretteHeroScore` 6 + `FarFutureSalvageSwap` 9 = **38**. The **42 reds** classify into named buckets
(each red in exactly one bucket): **Bucket A = 8** VRF/RNG pre-existing reds (out of v48 scope — v48 touched
no VRF/Advance code) + **Bucket B = 34** stale-harness / v48-behavioral baseline reds (fixtures not yet
re-synced to the v48 contract; present at the 326-08 HEAD; re-sync owned by a future fixture-repair plan,
NOT this terminal) + **Bucket C = 0** HERO-deferred FOUNDRY-side reds. A(8) + B(34) + C(0) = **42** ✓.
**Membership proof (327-06 §4):** NONE of the 18 failing suites was last touched by a 327-01..05 wave-1
commit (every failing suite's last-touching commit is at or before `f50cc634`); the 5 new wave-1 test files
added only PASSING tests. **Net new regression from the wave-1 work = 0.**

### §5b Hardhat PASS_ALL byte-reproduce gate — 15/20-diverge-RED -> 0-diff-GREEN at `1575f4a9`
The HERO-04 PASS_ALL byte-reproduce gate runs in the **Hardhat stat tree** (`DegenerettePerNEvExactness` +
`DegeneretteBonusEv`), NOT `forge test`. Pre-landing (subject `f50cc634`): 15 passing / **1 failing**
(PASS_ALL RED — 15/20 constants diverge from the canonical generator). Post-landing (subject `1575f4a9`,
the USER-approved constant-only HERO-04 finals landing): **16 passing / 0 failing** (PASS_ALL 0-diff GREEN;
per-N `basePayoutEV == 100` centi-x, ETH bonus == 5.000%). The forge whole-tree count is unchanged 632/42
across the landing (the byte-reproduce red was Hardhat-only; the forge HERO-deferred count = 0 since
`DegeneretteHeroScore.t.sol` asserts scoring SHAPE/dispatch off `FullTicketResult.matches`, GREEN 6/6). The
audit subject `1575f4a9` IS the post-landing state — the Memory-noted Hardhat PASS_ALL 1->0 flip is realized
at the frozen subject.

### §5c REG-01-equivalent NON-WIDENING attestation
`git diff da5c9d50..1575f4a9 -- contracts/ test/`: every hunk is attributable to a known v48-scope commit —
the batched IMPL diff `f50cc634` (12-file contract surface across PFIX/RFALL/KEEP/POOL/BTOMB/HERO/SWAP), the
HERO-04 finals landing `1575f4a9` (constant-only into `DegeneretteModule.sol`), and the AGENT-committed
wave-1 test files (the 5 new `test/fuzz/*` + the `RedemptionAccounting`/`RedemptionHandler` invariant
extension under Phase 327). `git diff 1575f4a9 HEAD -- contracts/` is **empty** (zero contract mutation in
this terminal phase; subject byte-frozen). **NON-WIDENING confirmed.**

---
