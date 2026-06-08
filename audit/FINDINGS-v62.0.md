# FINDINGS — v62.0 (Blind-Spot-Driven Pre-C4A Audit — CROSS-MODEL-LED)

- **Frozen audit subject (SHA):** `c4d48008` (= v61.0 closure `b97a7a2e` + the committed forgiving-funding change). Contracts are byte-identical from `c4d48008` through the audit HEAD — **zero `contracts/*.sol` mutation** (`git diff c4d48008 -- contracts/` is empty at every checkpoint; this is a document-only audit, AUDIT-02).
- **Baseline (frozen):** `b97a7a2e` (v61.0 closure HEAD).
- **Date:** 2026-06-08.
- **Method — CROSS-MODEL-LED (the defining premise):** the convergent external council (Gemini 3 Pro + OpenAI Codex/GPT-5.x) is the PRIMARY finder; Claude orchestrates the dispatch, **adjudicates every candidate vs the frozen source**, applies the locked threat model + by-design rulings, and **reproduces every actionable finding on the test harness**. Foundation-first: Phase 380 drove the full forge suite to a green baseline at `c4d48008`; Phase 381 built a durable always-on invariant net (FUZZ-01..06); Phases 382–386 ran the council sweeps; Phase 387 (this document) consolidates.
- **Council pipeline:** `.planning/audit-v52/cross-model/bin/council.sh` → `ask-gemini.sh` (read-only `--approval-mode plan`) + `ask-codex.sh` (`exec --sandbox read-only`). Both models headless, 0 skipped across all 6 dispatches. Raw outputs committed under `.planning/audit-v52/cross-model/{381-fuzz-completeness,382-prime,383-asym,384-compo,385-loop,386-periph}/`.

---

## Executive summary

**v62 surfaced THREE actionable findings the prior Claude-only audits missed — exactly what the cross-model premise predicted.** Two are HIGH (a permanent `advanceGame` gas-brick composition; an sDGNRS redemption reentrancy that breaks the solvency reserve identity) and one is MEDIUM–HIGH (the permissionless lootbox auto-open is structurally dead for human/presale boxes). All three are **empirically reproduced on the real contracts** (test-only, zero source mutation) and routed to a **USER-gated, batched remediation** — nothing is fixed or committed autonomously.

| Disposition | Count |
|---|---|
| **HIGH (contract fix required)** | **2** — V62-02, V62-03 |
| **MEDIUM–HIGH (contract fix required)** | **1** — V62-01 |
| LOW (bounded; fix recommended) | 4 — V62-04..07 |
| MEDIUM (open — adjudication pending, cap-truncated) | 1 — coinflip presale-flag freshness |
| Design seams / net-gaps (documented, no fix) | 2 |
| Council candidates REFUTED or BY-DESIGN | ~15 (incl. the divergent DOMINANT-class claim) |

> **Milestone outcome:** this is an AUDIT milestone; its deliverable is **this findings document**. The 3 actionable findings constitute an **open remediation gate** — the protocol is NOT C4A-ready until V62-01/02/03 are fixed under USER review. The fixes are a separate, USER-gated contract milestone (each finding ships with its reproduction as the future regression test).

---

## The durable foundation (Phase 381 — the always-on invariant net)

Built before the sweeps and now the regression oracle. All green at `c4d48008` (combined 24/24, 0 reverts):

| Req | Invariant | Proof |
|---|---|---|
| FUZZ-01 | SOLVENCY — `claimablePool == Σ(claimable+afking halves)` & `≤ bal+stETH` over a wide buyer action-space | `V61SolvencyAfpay.inv.t.sol` (256 runs / 32768 calls / 0 reverts) + falsifiability + non-vacuity gate |
| FUZZ-02 | RNG-FREEZE — no in-window player action mutates any enumerated consumed slot (incl. non-VRF reads) | `RngWindowFreeze.inv.t.sol` |
| FUZZ-03 | GAS-CEILING — every `advanceGame` tx ≤ 16,777,216 (reusable component) | `AdvanceGasCeiling.sol` + `AdvanceGasCeilingFuzz.t.sol` (1000 runs) |
| FUZZ-04 | BOX-ENQUEUE — every persisted box is enqueued until opened | `BoxEnqueue.inv.t.sol` |
| FUZZ-05 | POOL-CONSERVATION — 4-pool total fully backed; transfers conserve | `PoolConservation.inv.t.sol` |
| FUZZ-06 | Council completeness review of the property SET | `381-06-COUNCIL-ADJUDICATION.md` → surfaced V62-01 |

---

## Actionable findings

### V62-01 — Permissionless lootbox auto-open is structurally dead for human + presale boxes — **MEDIUM–HIGH**
- **Origin:** Phase 381-06 council (codex) → reproduced `test/repro/C1BoxAutoOpen.t.sol` (2/2).
- **Defect:** boxes enqueue at `boxPlayers[LR_INDEX]`, but VRF words land at `LR_INDEX − 1` (the request pre-increments the index). `_openHumanBoxes` / `boxesPending` read the **active** `LR_INDEX` (`DegenerusGame.sol:1889/1899`), so the just-finalized box at `LR_INDEX − 1` is never auto-opened; presale-only boxes are additionally skipped by the `lootboxEthBase==0` guard (`:1912`). The afking-cover leg is immune (keys off `rngWordByDay`) — the differential tell.
- **Reproduced behavior:** word lands at index N=2, `LR_INDEX=3` → `openBoxes(50)` opens 0, base unchanged across repeated calls + a further index advance; manual `openLootBox(actor,2)` opens it. Identical on the daily-finalize path.
- **Impact:** re-opens the WHALE-01 anti-timing vector for the mainline human/presale box classes — with the permissionless valve dead, the box owner solely controls open timing. No fund loss / no solvency or RNG-freeze break.
- **Candidate fix (gated, NOT applied):** point `openBoxes` / `boxesPending` index reads at `LR_INDEX − 1`; include the presale-box leg. Ship the after-fix regression (assert `openBoxes` drains a ready box).

### V62-02 — `advanceGame` gas brick: subscriber-evict chunk + 120-day gap-backfill compose in one tx — **HIGH**
- **Origin:** Phase 384 council — **CONVERGENT (Gemini + Codex)** → reproduced `test/repro/V62GasBrickCompose.t.sol`.
- **Defect:** the new-day path runs the afking subscriber STAGE then falls through to `rngGate` → `_backfillGapDays` with **no intervening stage-break** (`DegenerusGameAdvanceModule.sol:336→341`). On a 121+ day VRF-stall recovery with a large funded subscriber set, a saturated final all-evict chunk + the 120-day backfill run in ONE `advanceGame` tx. The v60 decouple (`6d2c8d0c`, `:363`) only separates the backfill from the DOWNSTREAM terminal jackpot — NOT from the UPSTREAM subscriber stage.
- **Reproduced:** composed single tx COLD = **20,255,533 gas > 16,777,216** (497 subscribers evicted in the final chunk + 119 gap days backfilled in the same tx; `subsFullyProcessed` fall-through confirmed). Cross-checked against the existing harness (isolated all-evict chunk 13.6M; isolated 120-day backfill 7.3M). A boundary control confirms the worst composable case (a sub-budget final chunk + full backfill). → permanent game-over-advance **brick** during stall recovery.
- **Candidate fix (gated, NOT applied):** insert a stage-break between subscriber-stage completion and `rngGate`/`_backfillGapDays` (mirror the v60 gap decouple on the upstream side) so the two heavy stages never share a tx.

### V62-03 — sDGNRS redemption reentrancy → in-flight stETH double-counted as backing — **HIGH (solvency spine)**
- **Origin:** Phase 386 council (codex) → reproduced `test/repro/V62RedemptionReentrancy.t.sol`.
- **Defect:** `claimRedemption` decrements `pendingRedemptionEthValue` and deletes the claim BEFORE payout (`StakedDegenerusStonk.sol:728/733`); `_payEth`'s mixed branch sends direct ETH via `player.call` BEFORE transferring the stETH remainder (`:948` then `:953`), with **no reentrancy guard anywhere in the contract**. In the ETH receive hook the attacker reentrantly calls `burn()` (reachable when `!gameOver && !rngLocked`); the reentrant backing calc (`:867-869`) still counts the in-flight `stethOut` (not yet sent, no longer reserved) as free backing → over-reserves a new redemption (`pullRedemptionReserve`, +175%) → `pendingRedemptionEthValue` exceeds ETH+stETH held → breaks SOLVENCY-01.
- **Reproduced:** before = `pending 17.50` / held 17.50 (identity holds); after the attack = `pending 0.791 ETH` while **ETH+stETH held = 0** (unbacked deficit); reentrant `burn()` landed 28× during the hook.
- **Direct evidence it's an sDGNRS-local bug:** `DegenerusVault.burnEth` already does the safe ordering (transfers stETH BEFORE the ETH `.call`, `DegenerusVault.sol:846-847`).
- **Candidate fix (gated, NOT applied):** transfer stETH BEFORE the untrusted ETH `.call` (as the Vault does), or add a reentrancy guard to the claim/burn paths.

---

## Lower-severity findings

- **V62-04 — False game-over from a >120-day VRF stall consuming the death clock — LOW–MED.** `_handleGameOverPath` runs before the `purchaseStartDay`-extending `_backfillGapDays` (`AdvanceModule.sol:208` vs `:1235`); a 120+ day stall latches game-over before the stall-credit applies. Bounded: needs a 4-month governance failure to rotate the coordinator (normal recovery 20h–7d), and a long unrecoverable VRF outage draining to players may be the intended safety outcome. Document.
- **V62-05 — Deity pass `ticketStartLevel` 50-boundary overshoot drops 1–2 paid levels — LOW (CONVERGENT).** `WhaleModule.sol:639-641` `((passLevel+1)/50)*50+1` (passLevel 49 → start 51, loses 49/50); whale anchors at `passLevel`. Buyer-only under-delivery. Fix: `ticketStartLevel = passLevel`.
- **V62-06 — Lazy-pass boon price-basis — LOW.** `WhaleModule.sol:491/519` size the presale-box credit + lootbox-10% on the undiscounted `benefitValue` while the buyer pays a boon-discounted price; whale/deity use the discounted `totalPrice`. Bounded by the boon discount; gated behind earning a boon.
- **V62-07 — `resolveLootboxDirect` seed omits index/betId — LOW/INFO.** `LootboxModule.sol:762` `keccak(rngWord,player,amount)` → same player + same lootbox index batch + same summed `betLootboxShare` correlate. No EV / no freshness break — a fairness/diversity quirk.

## Open candidate (adjudication pending — cap-truncated)

- **Coinflip presale-bonus-flag freshness (codex, Phase 385) — ~MED, UNADJUDICATED.** The daily coinflip payout reads `lootboxPresaleActiveFlag()` (+6pp presale bonus), not frozen at the daily VRF request and readable after the word is public; a lootbox buy crossing `LOOTBOX_PRESALE_ETH_CAP` clears `PS_ACTIVE`. Codex: "payout-parameter manipulation, not bet-after-randomness" (new stake can't join the resolving day; `_targetFlipDay = wall-day+1`). Narrow (presale = game start). **Recommended next step: backward-trace this to a verdict before C4A.**

## Design seams / net-gaps (documented, no fix)

- **NETGAP-02 — `advanceGame` non-revert liveness.** No invariant forbids `advanceGame()` reverting in a due/unlocked state. The broken-coordinator revert (G1) is an external-VRF dependency recoverable via governance `updateVrfCoordinatorAndSub` (Admin gate keys on `lastVrfProcessed`, independent of liveness) — not a contract bug. Folding a non-revert invariant is recommended.
- **Mid-day lootbox boon-roll live-state seam.** `_rollLootboxBoons` reads some live inputs (`deityEligible`, level) after the mid-day word is public. REFUTED on EV: the reward (seed/amount/score) is frozen; the only player-mutable input is `deityEligible`, flippable only via a ≥24 ETH irreversible deity purchase — economically absurd for a sub-budget boon.

---

## Refuted / by-design (recorded so they are not re-flagged)

- **Near-future ticket jackpot-stuffing (DOMINANT-class, gemini, divergent)** — REFUTED: the daily ETH/coin jackpot draws from `traitBurnTicket[lvl]` snapshotted pre-RNG via the `_swapAndFreeze` slot-swap; the only live `ticketQueue` read (far-future coin) is rng-locked; write/read/far-future key spaces are bit-disjoint.
- **Affiliate multi-sub claim theft (gemini, divergent)** — REFUTED: `claim` enforces a same-affiliate guard (`Affiliate.sol:651`) — a mixed-upline batch reverts; per-sub base drained from the sub's own slot.
- **Affiliate-score magnitude ~2500× (carried from 380)** — REFUTED: both `payAffiliate` and afking `claim` accumulate `_totalAffiliateScore` in 1e18 BURNIE base units; the differing reward rates are intended economics.
- **Subscriber ticket-scaling DoS (gemini)** — REFUTED: `_queueTicketsScaled` is O(1) per buyer; trait resolution write-budgeted (550).
- **Free hero-wager mint (gemini, 381-06 G1)** — REFUTED: `dailyHeroWagers` is ETH-only, every unit backed by a debited `msg.value`/`claimablePool`.
- **Unbounded `_backfillOrphanedLootboxIndices` (gemini, 381-06 G2)** — REFUTED: breaks on first filled index; `LR_INDEX` structurally ≤1 ahead.
- **Whale `LAST_LEVEL` regression (gemini)** — REFUTED: `_applyWhalePassStats` sets LAST_LEVEL ≥ level+100 (raises, never regresses).
- **Broken-coordinator permanent revert (codex, G1)** — REFUTED: external-VRF dependency, recoverable via governance.
- **Mid-day lootbox boon-roll / redemption-lootbox predictable RNG (C/H)** — REFUTED (see seams; atomic-`rngGate` ordering).
- **Combo-buy revert in jackpot phase (codex 382-F2)** — REFUTED: `_mintCost` retarget matches `_purchaseForWith`; presale leg unreachable in jackpot phase.
- **Curse/smite immunity via `dailyQuantity` (codex 382-F1)** — BY-DESIGN: canonical active-afker predicate; inclusive-eviction lag USER-locked; no EV.
- **Carried FC5 entropy-binding** — ENFORCED on-chain (event-only slimming). **FC6 coordinator-swap backfill** — SAFE. **FC1 mid-day pending stall** — LOW, self-recovering via `retryLootboxRng`.
- **IDegenerusGame interface stubs / vault stETH-strand** — INFO/REFUTED (interfaces inert; Vault pays stETH before ETH).

---

## Reproduction artifacts (test-only, real contracts, committed)

- `test/repro/C1BoxAutoOpen.t.sol` — V62-01 (2/2).
- `test/repro/V62GasBrickCompose.t.sol` — V62-02 (3/3; cold verdict + warm diagnostic + boundary control).
- `test/repro/V62RedemptionReentrancy.t.sol` — V62-03 (1/1, deterministic).

## Recommended remediation order (USER-gated, batched)
1. **V62-03** (HIGH, solvency spine) — reorder `_payEth` (stETH before ETH) / add reentrancy guard.
2. **V62-02** (HIGH, brick) — stage-break before the upstream gap-backfill composition.
3. **V62-01** (MED–HIGH) — `openBoxes`/`boxesPending` read `LR_INDEX − 1` + presale leg.
4. **V62-05/06** (LOW) — pass-path price/ticket-window corrections; **V62-04** monitor; adjudicate the open coinflip-flag MED.

Each fix is a one-/few-line contract change in a single batched diff, re-attested against the FUZZ-01..06 net + the three reproductions (which flip from characterizing-the-bug to asserting-the-fix). No fix is applied in this audit milestone.
