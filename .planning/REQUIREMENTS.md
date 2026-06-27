# Requirements — Milestone v74.0 — As-Built Milestone Audit + C4A Package (supersedes the v74 "C4A Readiness" plan)

**Defined:** 2026-06-26
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

> **Subject (BYTE-FROZEN at HEAD):** the `v73.0 → HEAD` diff — `3986926c` ("sDGNRS level lootbox + pre-deploy hardening batch"), **29 contract files, +1861/−1030**, never put through a milestone audit. Frozen baseline = the local HEAD `3986926c` (on `main`, not pushed; push stays separately gated). Prior closure being reset off = v73.0 `MILESTONE_V73_AT_HEAD_15650b6a…` (`contracts/` tree `d6615306` @ `64ec993e`).
> **What this supersedes:** the prior "v74.0 — C4A Readiness" plan (phases 457–465) is **superseded, never tagged** — its premise (subject stays byte-frozen / no contract change) was overtaken by this contract batch. The old plan is archived to `milestones/v74.0-superseded-plan-{ROADMAP,REQUIREMENTS}.md`. The already-built live adversarial agent + 24/7 soak + partial package artifacts **carry forward in place** (re-pointed, not rebuilt). Phase numbering continues 465 → **466**.
> **Posture:** this is a contract-touching milestone whose subject is **already committed** — the audit verifies the as-built tree. Default disposition is the subject stays frozen as-is. The **SOLE possible contract-commit gate** is the conditional squash at Phase 475/478 — fires only if the cross-model re-audit (or any phase) surfaces a real defect warranting a fix. All verify / harness / audit / manifest / agent / package / findings work commits autonomously (`.planning/`, `test/`, `audit/`, `agent/` are not gated).
> **Method:** the repo's established milestone-audit shape — verify → freeze-confirm → harness-green → 6-cluster code audit → manifest re-point → cross-model adversarial re-audit → live agent/soak re-attest → C4A package → terminal closure. Cross-model finder = **Codex** (primary); the Gemini CLI is currently unavailable — re-check liveness before leaning on a two-model council, do not assume it.
> **Threat weighting (locked):** DOMINANT = RNG/freeze manipulability · HIGH = gas-DoS in the advanceGame chain (worst-case >16.7M = game-over) · SPINE = solvency/backing conservation · LOWER = access-control / reentrancy / MEV.
> **Grounding:** `.planning/v74-grounding/v74.0-asbuilt-audit-map.md` (8-cluster change-map + 8 ranked attack surfaces) + the raw fan-out `v74.0-asbuilt-map-RAW.json`.

---

## v1 Requirements

Requirements for v74.0. Each maps to exactly one roadmap phase (466–478).

### SUBJ — subject freeze + storage-layout golden (Phase 466)

- [ ] **SUBJ-01**: The `contracts/` working tree is clean at HEAD `3986926c`; the frozen `contracts/` tree hash + impl commit are recorded as the milestone subject.
- [ ] **SUBJ-02**: The 2 dirty liveness `.test.js` files (LivenessMidJackpot / LivenessProductivePause) are committed or explicitly quarantined out of the frozen subject (test-only; not part of the contract subject).
- [ ] **SUBJ-03**: A `forge inspect storageLayout` by-name golden is captured and shows **no top-level slot move** vs v73 — only the within-slot `Sub` repack (`reinvestPct` removal, 48→40 bits) and the additive `_sdgnrsBonusLevel` (cursor slot 58 offset 25; `boxPlayers` stays slot 59; `WHALE_PASS_TYPE_SHIFT` stays bit 152).
- [ ] **SUBJ-04**: The milestone closure baseline `MILESTONE_V74_AT_HEAD_<sha>` is defined distinct from the stale v73 `d6615306` pin; the subject = local HEAD and push posture is recorded (push not required for the audit).

### HARN — frozen-subject harness green (Phase 467, test-only)

- [ ] **HARN-01**: Every slot-hardcoded `vm.store`/`vm.load` harness keyed on `Sub` field offsets is re-derived from the 466 golden after the `reinvestPct`-removal repack (no harness reads a stale offset).
- [ ] **HARN-02**: Every ABI-breaking selector/signature change is reflected in all JS + Foundry callers/tests — `claimBingo(+address)`, `subscribe(−reinvestPct)`, `recordAfkingSecondary(+uint16)`, `purchaseWhalePass`, `resolveDegeneretteBets`, `processTicketBatch`/`processFoilDrain` tuples, `claimAffiliateDgnrs` batch, `payAffiliateCombined`, `handleFoilPurchase`.
- [ ] **HARN-03**: Full `forge` + Hardhat suite green at HEAD (target the recorded ≥893/0 floor; VRFGovernance stays 42/42 kill-on-recovery era; the new `DegenerusGasFaucet` + `DegenerusQuests` unit suites pass; the 2 deferred liveness edge tests fold back to green).

### SOLV — solvency / backing conservation (Phase 468)

- [ ] **SOLV-01**: Σ(per-player claimable+afking debits) == the single combined `claimablePool -= totalClaimableDraw` on every `payKind` branch (DirectEth / Claimable / Combined), with and without a lootbox leg.
- [ ] **SOLV-02**: Σ(per-leg next/future splits) == the single `_addPrizeContribution`; `prizePoolFrozen` cannot flip between the ticket and lootbox legs; pending-vs-live routing is correct.
- [ ] **SOLV-03**: The boon-consume delegatecall reentrancy window (per-player balances debited inside `_callTicketPurchase`, `claimablePool` decremented later) cannot let any reader observe an inconsistent pool.
- [ ] **SOLV-04**: `payAffiliateCombined` returns `winnerCredit` (not paid); the MintModule caller fully credits winner (referrer + noReferrer VAULT/DGNRS) + buyer via `creditFlipBatch` with `winner!=buyer` collision-safety; no unbacked credit is minted.
- [ ] **SOLV-05**: The sDGNRS bonus box (`claimableUse=box`, `claimablePool-=box`, then `_routeAfkingPoolEth(box,0)` into the box prize pool) keeps `claimablePool >= Σ claimable` and the 1-wei sentinel (`box<=cl-1`) for every `cl` given the `cl>mp` guard + `mp` floor.
- [ ] **SOLV-06**: Partial `claimWinnings(address,uint256)`: the `maxClaim` cap matches the per-player debit exactly and leaves the sentinel pre-gameOver; post-gameOver ignores the cap and settles all claimable + prepaid afking.
- [ ] **SOLV-07**: The GameOver freeze-clear (`prizePoolPendingPacked=0`, `prizePoolFrozen=false`) runs on every game-over path before any `_unfreezePool` / post-gameOver resolution, so zeroed pools cannot be resurrected.
- [ ] **SOLV-08**: The `_settleShortfallNoPool` + single-aggregate-decrement split and the `_resolveBuy` frozen-`dailyQuantity` funding-split rewrite preserve no-underflow / no-brick across the 2 subscribe cover-buys and the STAGE loop; the `==`→`>=` `claimablePool` invariant doc reflects code that only ever over-reserves.

### RNG — RNG-freeze / VRF integrity (Phase 469) — DOMINANT dimension

- [ ] **RNG-01**: `_vrfDeadmanFired` (`_simulatedDayIndex()-dailyIdx>120`) cannot false-fire on a healthy game (no legitimate >120d sealed-day gap), stays latched through the multi-tx drain, and commits a non-steerable historical fallback word (`totalFlipReversals` cancellation) only when the game is genuinely dead.
- [ ] **RNG-02**: Mid-day abandon-and-promote (`retryLootboxRng` removed; 4h `MIDDAY_RNG_STALL_TIMEOUT`) preserves the reserved bucket index (`lootboxRngIndex-1`) via `_finalizeRngRequest isRetry`; the stale mid-day `requestId` is never honored later in `rawFulfillRandomWords`; no entropy-reroll / double-resolution.
- [ ] **RNG-03**: Tickets queued during the liveness-timeout window (queue-gate removed from `_queueTickets`/`_queueTicketsScaled`/`_queueTicketRange`) are provably never processed into and never resolve a manipulable terminal jackpot (v45 freeze invariant); the `_swapAndFreeze`-vs-`_freezePool` drained fork isolates post-delivery tickets.
- [ ] **RNG-04**: The sDGNRS bonus box amount (`min(cl/20, 6 ether)` floored at `mp`), sized off a LIVE `_claimableOf(SDGNRS)` read in the pre-RNG STAGE, is not steerable between that read and the day's word landing; the once-per-level latch cannot re-fire to re-size after the word is knowable.
- [ ] **RNG-05**: Foil claim consumes only the sealed word; Degenerette resolve consumes only `lootboxRngWordByIndex[index]`; the StaleAdvance/forward-commit + `rngWordByDay` sealed-word guards are intact; the BAF/jackpot RNG-word consumption + winner fan-out (JackpotModule) are byte-unchanged (only the `OnlySelf` rename).

### LIVE — liveness / no-brick / advance-chain gas (Phase 469) — HIGH dimension

- [ ] **LIVE-01**: `processTicketBatch` `(finished,didWork)` + `processFoilDrain` `(done,drained)` never report a false negative on a start-and-finish-in-one-call finishing batch (a false negative re-enables same-tx BAF/jackpot composition toward the 16.7M ceiling); the 64-byte (`data.length>=64`) decode guards cannot brick the advance heartbeat.
- [ ] **LIVE-02**: The fail-open `_swapTicketSlot` deferred non-empty branch (read-slot non-empty revert dropped) is truly unreachable (callers only swap after the read slot is drained); the standalone `_freezePool` 1%-futurePool pre-seed does not double-seed / leak backing.
- [ ] **LIVE-03**: The deadman game-over multi-tx drain and the `mintFlip` open-leg `openHumanBoxes` drain stay under the per-tx gas ceiling in a worst-case test; the combined `OPEN_KNEE` bounty is farm-by-splitting resistant.
- [ ] **LIVE-04**: The foil readiness gate (`FOIL_PACK_ENTRIES*2+3` budget) still blocks the daily draw until foil buyers drain, and the 4h mid-day recovery fold does not stall the advance; `claimWhalePass` empty-claim now reverting `NothingToClaim` breaks no permissionless crank / Vault / sDGNRS harvest caller that relied on the prior silent no-op.

### ACCESS — access-control / permissionless settlement / governance trust (Phase 470)

- [ ] **ACCESS-01**: The dispatch-stub conversions (`openBox`/`placeDegeneretteBet`/`resolveDegeneretteBets`/`claimWhalePass`, with `_resolvePlayer` moved Game→modules) each resolve player / sender-or-approved inside the module, so no caller acts for an unconsenting player on a SPEND or gift path.
- [ ] **ACCESS-02**: Coinflip + Degenerette caller-funded gift placement sources spend from `msg.sender` on the gift branch (funder=player only when self / operator-approved); no branch burns a non-consenting party's FLIP; WWXRP is gift-excluded; the funder-earns-quest / player-receives-stake split cannot farm a funder streak or grief a player; `directDeposit=false` suppresses biggestFlip/bounty on gift/operator deposits.
- [ ] **ACCESS-03**: `claimBingo(+address)` is sender-or-approved with player-keyed dedup; the timing-sensitive `poolBal*bps/10000` reward cannot be force-settled for a non-consenting slot owner.
- [ ] **ACCESS-04**: `claimAffiliateDgnrs` full permissionlessness (+ batch `try/catch` isolation) credits only the affiliate from a frozen per-level score and corrupts no shared state on a reverting item.
- [ ] **ACCESS-05**: `openBox` / `gameClaimBingo` / `gameClaimWhalePass` are harvest-inward-only (reward always credits the resolved owner/contract; the caller cannot redirect value).
- [ ] **ACCESS-06**: Admin governance timing — the payable `receive()` force-forwards native to VAULT with a never-revert `pop(call)` under inner-OOG (strands nothing); `ADMIN_STALL_THRESHOLD` 44h is sawtooth-safe (no false-fire on healthy ~24h cadence / multi-day catch-up / jackpot suppression); `vote()` kill-on-recovery checks active-before-stall, is terminal (`Killed`), and admits no record-while-recovered vote window.
- [ ] **ACCESS-07**: The `ContractAddresses` `GAME_ENDGAME_MODULE` removal leaves no live dispatcher delegatecalling a zero / absent module.

### EV — EV / RTP economy preservation (Phase 471)

- [ ] **EV-01**: Foil `streakSnapshot` (post-primary / pre-secondary / pre-floor in `handleFoilPurchase`) reproduces v73 `effectiveBaseStreak` timing exactly; `foilBoostBps(score)` / the frozen `foilRecord` / claim-spin RTP / P(match-tier) are byte-equivalent.
- [ ] **EV-02**: Degenerette strict / non-strict batch trailing-skip mutates no storage before the `packed==0` / `rngWord==0` gates; the cross-bet `ResolveAcc` flush is byte-identical to the prior per-spin writes; only `lootboxRngWordByIndex[index]` is consumed; the WWXRP rig is untouched.
- [ ] **EV-03**: `payAffiliateCombined` winner-selection distribution, per-leg fresh/recycled bps + lootbox-taper floor-of-sum rounding, and score-freeze at `cachedLevel+1` match four separate `payAffiliate` calls; the single `quests.handleAffiliate(sumShareBase)` hop is reward-linear (or the divergence is documented).
- [ ] **EV-04**: The activity-score skip (`cachedScore=0` on ticket-only non-century buys) is behaviour-preserving — every `cachedScore` consumer is enumerated (century bonus gated `%100==0`, lootbox-EV first-deposit gated `lootBoxAmount!=0`, `payAffiliateCombined lbFreshScore` which only scales the zero `lbFreshFlip` leg) and none depends on a real score in the skipped case.
- [ ] **EV-05**: Quests `LEVEL_QUEST_STREAK_BONUS` 1→5 + the activity-boon routed to the afking sub base grant the century shield exactly once per threshold and reconcile exactly once at `finalizeAfking`.
- [ ] **EV-06**: `reinvestPct` is fully excised on every subscribe / afking / quest path with no orphaned read; the sDGNRS self-sub 2%-reinvest removal and the vault signature-only change are intended.
- [ ] **EV-07**: `_handlePurchase` and `_resolveReferral` are behaviour-identical verbatim extractions shared across their access-tiered wrappers.

### WIRE — rename / wiring / storage-layout / named-error inertness (Phase 472)

- [ ] **WIRE-01**: The `Sub` `reinvestPct` removal is a within-slot 48→40 repack (all flags/score/amount/markers/accumulator offsets shift down 8 bits, `_subOf` slot 54 unchanged); `_sdgnrsBonusLevel` packs into cursor slot 58 offset 25 with no downstream slot move; `WHALE_PASS_TYPE_SHIFT` stays bit 152 — all confirmed against the 466 golden.
- [ ] **WIRE-02**: Every `E()`→named-error swap (20 shared in Storage + per-file SelfBoon/ValueMismatch/MidDayActive/InsufficientLink/NoPendingLootbox/BelowThreshold/RngInFlight/ScoreTooLow/PrizePoolFrozen/…) preserves the exact original revert condition (a per-swap table); stale-natspec mismatches (e.g. `handleGameOverDrain` advertising `ZeroValue` but reverting `Invariant`) are catalogued for documentation correction.
- [ ] **WIRE-03**: `grep` confirms 0 stale references in `contracts/` (`WHALE_BUNDLE_TYPE_SHIFT`, `WrappedWrappedXRP`, `purchaseWhaleBundle`, `resolveBets(`, `retryLootboxRng`, `handleFoilPack`, `foilStreakBoost`); every renamed selector and new return tuple (`processTicketBatch.didWork`, `processFoilDrain.drained`, `_callTicketPurchase` 4→9) is matched to its implementation and all callers; build green.
- [ ] **WIRE-04**: The new events (`TicketsBought`, `WhalePassPurchased`, `LazyPassPurchased`, `AfkingDelivered`+weiIn, `FoilPackBought`+weiIn) are observability-only with no value-flow change; the affiliate single-emit (`AffiliateEarningsRecorded`, no `Affiliate(...)`, none on `sumScaled==0`) indexer-parity is documented; `claimBingo` retargets all three events to the resolved player.

### GAS — gas-faucet attest (Phase 473) — now in-scope (dormant)

- [ ] **GAS-01**: `DegenerusGasFaucet` is unwired / dormant in `deploy.js` and `deploy-local.js` (sole references = the contract + its test); its intended deploy posture is confirmed as dormant-in-scope this milestone.
- [ ] **GAS-02**: `distribute()` is `onlyDistributor`-gated, sets `hasReceived` BEFORE a 2300-gas-capped low-level call (CEI = reentrancy-safe), gates on `balance==0` + `affiliateScore>=minAffiliateScore`, early-breaks when `balance<amount`, and forfeits on `SendFailed`; `NothingToDispense` guard holds.
- [ ] **GAS-03**: Authority is bound to live `VAULT.isVaultOwner` (majority DGVE) + the `approvedDistributor` set; `setParams`/`setApprovedDistributor`/`withdraw` gating + `ZeroAddress` guards hold; `withdraw()` full-gas to a vault-owner-chosen sink is a documented trust boundary.
- [ ] **GAS-04**: The faucet has no mint/burn/ledger path, performs no protocol-state writes, custodies only externally-donated ETH (sole inflow = `receive()`), and cannot touch protocol backing/solvency; the 26/26-era unit suite is green.

### MAN — shared invariant manifest re-point (Phase 474)

- [ ] **MAN-01**: `invariants.json` subject is re-pinned from v73 `d6615306` to the HEAD `3986926c` tree/impl/closure, with all 28 existing entries (SOLV/REDEEM/COIN/VAULT/FSM/TICKET/BOX/RNG/VRF/DEG/CURSE) re-validated against the frozen getters and slots.
- [ ] **MAN-02**: New-surface invariants are added — claimablePool/prize-pool fold conservation (468), sDGNRS-box claimable→prize-pool routing + sentinel, `payAffiliateCombined` winnerCredit conservation, `_vrfDeadmanFired` monotonic-latch + terminal release, gift funder-sourcing (no non-consenting FLIP burn), queue-window-tickets-never-resolve — each on-chain or statistically evaluable.
- [ ] **MAN-03**: The manifest stays the single source shared verbatim by `agent/src/oracle.js` and the README Main-Invariants section; `MAIN-INVARIANTS.md` is regenerated and byte-matches the oracle's asserted set.

### CMRA — cross-model adversarial re-audit (Phase 475) — conditional contract gate

- [ ] **CMRA-01**: Codex (primary; Gemini re-checked at execution but currently unavailable) runs a documented adversarial pass over each ranked top attack surface in isolated neutral-prompt subagents; the skeptic filter (structural-protection check + 3-condition EV lens) is applied before any CATASTROPHE/HIGH label; contracts are git-verified unmodified after every Write-capable subagent.
- [ ] **CMRA-02**: Every raised candidate has a written disposition — **fixed** (→ the conditional, owner-approved squash commit, the SOLE contract gate: `CONTRACTS_COMMIT_APPROVED=1` + hook move-aside), **refuted**, or **carried to known-issues**; an all-refuted result ships gate-free.

### SOAK — live agent + 24/7 soak re-attest (Phase 476)

- [ ] **SOAK-01**: An independently-run testnet of the HEAD subject exists; the already-built agent (which never deploys/forks) is re-pointed at it with the 474-re-pinned MAN-01 manifest.
- [ ] **SOAK-02**: The connect-and-play attack campaign + 24/7 soak re-run with **0 final on-chain MAN-01 violations and 0 per-actor profit-vs-EV alarms** (window-transient `stateViol` counts explained as mempool-race artifacts, not genuine); the front-run / sandwich / shared-window-grief probes are carried.
- [ ] **SOAK-03**: Every violation path is reproducible from logged state; the attestation cites the soak ledger.

### PKG — C4A contest package (Phase 477)

- [ ] **PKG-01**: `scope.txt` is regenerated against the as-built HEAD tree (replacing the v55-era list that names BurnieCoin/BurnieCoinflip/WrappedWrappedXRP/EndgameModule; reflecting the FLIP rename, the WWXRP rename, the EndgameModule removal, and `DegenerusGasFaucet` per its dormant-in-scope posture) + an `out_of_scope.txt` is authored (currently absent: mocks, in-tree Solidity test harnesses, the test suite, scripts/deploy, node_modules) + an in-scope nSLOC table for the frozen tree.
- [ ] **PKG-02**: `SECURITY.md` + a trusted/restricted-roles trust-model enumerates every trusted role — sDGNRS majority governance (44h stall gate, payable receive, vote kill-on-recovery), vault-owner (>50.1% DGVE), `approvedDistributor` (faucet), VRF coordinator — and the permissionless-settlement trust boundary.
- [ ] **PKG-03**: A C4-section-order contest README is assembled with the Main-Invariants section sharing MAN-01 verbatim; `ACCESS-CONTROL-MATRIX.md` and `ETH-FLOW-MAP.md` are refreshed for the new permissionless/gift, sDGNRS level-lootbox, and gas-faucet surfaces.

### KI — known-issues perimeter (Phase 477)

- [ ] **KI-01**: The known-issues perimeter folds every locked by-design ruling — EV>100% RTP, positive-EV lootbox/coinflip, WWXRP worthless, capBucketCounts imprecision, lootbox open-level non-manipulability, presale over-credit wontfix, redemption-dust lootbox drop — each mechanism-+-impact specific (no vague blanket disclaimer).
- [ ] **KI-02**: The carried items are documented as defended/out-of-scope (not accepted vulnerabilities): the mid-day re-roll `==0` single-writer `requestId` guard **re-checked against the as-built code since this batch folded `retryLootboxRng` into the daily advance**; the 423 VRF rotation-timer (governance-malice out-of-scope per trust model + non-resettable 120/365-day backstop); the affiliate floor-of-sum (immaterial) — plus any 475 carries and the genesis-admin-self-break non-finding.

### TERM — terminal closure (Phase 478)

- [ ] **TERM-01**: `audit/FINDINGS-v74.0.md` (chmod 444) records every candidate's disposition across all 8 clusters plus the cross-model + soak attestations and the final verdict; an HTML report is generated.
- [ ] **TERM-02**: The closure signal `MILESTONE_V74_AT_HEAD_<sha>` is emitted pinned to the frozen `3986926c` tree (or the updated subject if 475 fired a fix); the v74 ROADMAP/REQUIREMENTS are archived to `milestones/`.
- [ ] **TERM-03**: The C4A package, the manifest, and the soak attestation all reference the same frozen subject (scope ↔ SLOC ↔ manifest ↔ known-issues cross-checked internally consistent); the only commit gate (a conditional contract-fix if 475 surfaced a real defect) is resolved.

---

## Out of Scope

| Item | Reason |
|------|--------|
| New protocol features | v74.0 is an as-built audit of the already-committed batch + the contest package — not feature work. The subject stays frozen unless the re-audit surfaces a fix. |
| Re-running the v62–v73 manual/cross-model audits | Those milestones closed 0 CAT/0 HIGH against their subjects; v74 audits only the *new* `v73.0→HEAD` diff (plus a re-attest of the carried-forward agent/soak). |
| Re-deriving the v73-frozen EV/RTP pins | The Degenerette Variant-2 rescore EV (DEG-01/02/03), WWXRP RTP curve, P(S=9)/jackpot pins, activity ROI, S=9 whale bracket, pay-floor S≥2 are byte-fixed and were Codex-1024-state re-derived at v73 close — re-attest unchanged, do not re-derive. |
| Wiring `DegenerusGasFaucet` into deploy | In-scope to AUDIT this milestone, but stays dormant/unwired (no deploy wiring). Deploying it is a separate product decision. |
| Mainnet deployment / launch ops + pushing the subject | Out of audit-repo scope; the soak targets the testnet only; pushing local HEAD `3986926c` stays separately gated and is not required to run the audit. |
| Indexer/ABI re-vendor, website/papers repos | Separate repos / follow-ups; OBS-02 only *documents* the affiliate single-emit indexer-parity delta. |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| SUBJ-01..04 | 466 | Pending |
| HARN-01..03 | 467 | Pending |
| SOLV-01..08 | 468 | Pending |
| RNG-01..05 | 469 | Pending |
| LIVE-01..04 | 469 | Pending |
| ACCESS-01..07 | 470 | Pending |
| EV-01..07 | 471 | Pending |
| WIRE-01..04 | 472 | Pending |
| GAS-01..04 | 473 | Pending |
| MAN-01..03 | 474 | Pending |
| CMRA-01..02 | 475 | Pending (conditional contract gate) |
| SOAK-01..03 | 476 | Pending |
| PKG-01..03 | 477 | Pending |
| KI-01..02 | 477 | Pending |
| TERM-01..03 | 478 | Pending |

**Coverage:**
- v1 requirements: 62 total across 15 categories
- Mapped to phases: 62
- Unmapped: 0 ✓

---
*Requirements defined: 2026-06-26 after milestone v74.0 re-scope (supersedes the v74 "C4A Readiness" plan)*
*Last updated: 2026-06-26 after milestone v74.0 initialization*
