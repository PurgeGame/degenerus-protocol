# v62.0 Audit — Running Findings Ledger

> Mutable working ledger; consolidated into `audit/FINDINGS-v62.0.md` (chmod 444) at Phase 387 TERMINAL.
> Subject = frozen `c4d48008`. Method = CROSS-MODEL-LED (gemini + codex primary; Claude adjudicates vs
> frozen source + reproduces convergent findings on the harness). v62 is **document-only** — every CONFIRMED
> finding routes to a USER-gated, batched contract fix; NOTHING is fixed/committed autonomously.

## Severity legend
CRIT (fund-loss / permanent brick) · HIGH (exploitable edge or broken core guarantee) · MED (degraded
guarantee, bounded impact) · LOW/INFO · REFUTED · BY-DESIGN.

---

## CONFIRMED FINDINGS (route to USER-gated batched fix)

### V62-01 — Permissionless lootbox auto-open is structurally dead for human + presale boxes — **MED–HIGH**
- **Origin:** 381-06 council (codex C1); adjudicated + **empirically reproduced** (`test/repro/C1BoxAutoOpen.t.sol`, 2/2, re-run by orchestrator; zero contract mutation).
- **Defect:** boxes enqueue at `boxPlayers[LR_INDEX]` but VRF words land at `LR_INDEX − 1` (request pre-increments). `_openHumanBoxes`/`boxesPending` read the active `LR_INDEX` (DegenerusGame.sol:1889/1899) → finalized box at `LR_INDEX − 1` never auto-opens; presale boxes also skipped by `lootboxEthBase==0` guard (:1912). Afking-cover leg immune (keys off `rngWordByDay`).
- **Impact:** re-opens the WHALE-01 anti-timing vector for mainline human/presale boxes — owner solely controls open timing. No fund-loss / no solvency or RNG-freeze break.
- **Fix (gated, NOT applied):** point `openBoxes`/`boxesPending` reads at `LR_INDEX − 1`; include the presale leg.

### V62-02 — advanceGame gas brick: subscriber-evict chunk + 120-day gap-backfill compose in one tx — **HIGH**
- **Origin:** 384 council — **CONVERGENT (gemini + codex)**; adjudicated vs source (measured pieces on the real harness).
- **Defect:** the new-day path runs the afking subscriber STAGE then falls through to `rngGate`→`_backfillGapDays` with **no intervening stage-break** (AdvanceModule.sol:336→341). On a 121+ day VRF-stall recovery with a large funded subscriber set, a saturated final all-evict chunk (~13.6M, measured `testResidualR1`) + the 120-day backfill (~7.1M) ≈ **~20.7M > 16,777,216** in ONE `advanceGame` tx → permanent game-over-advance brick. The v60 decouple (`6d2c8d0c`, AdvanceModule:363) covers backfill↔terminal-jackpot only, NOT finalSubscriberChunk↔backfill.
- **Coverage hole:** the binding pieces are proven only in isolation (13.6M evict chunk; 7.3M backfill with 24 trivial subs); no gas test composes a saturated final chunk WITH the backfill. `AdvanceGasCeiling.sol`/`GameSeeder` seeds `rngWordByDay[day]` non-zero (bypassing backfill) + no subscribers.
- **Reproduction:** see `test/repro/V62GasBrickCompose.t.sol` (orchestrator) — drives the composed tx and asserts > 16.7M.
- **Fix (gated, NOT applied):** insert a stage-break between subscriber-stage completion and `rngGate`/`_backfillGapDays` (mirror the v60 gap decouple on the upstream side), so the two heavy stages never share a tx.

### V62-03 — sDGNRS redemption reentrancy → stETH double-counted as backing — **HIGH (solvency spine)**
- **Origin:** 386 council (codex); adjudicated vs source (order-of-operations + no-guard + worked numeric model).
- **Defect:** `claimRedemption` decrements `pendingRedemptionEthValue` and deletes the claim BEFORE payout (StakedDegenerusStonk.sol:728/733); `_payEth` mixed branch sends direct ETH via `player.call` BEFORE transferring the stETH remainder (:948 then :953) with NO reentrancy guard anywhere in the contract. In the ETH receive hook the attacker reentrantly calls `burn()` (reachable when `!gameOver && !rngLocked`); the reentrant backing calc `ethBal + stethBal + claimableEth − pending` (:867-869) still counts the in-flight `stethOut` (not yet sent, no longer reserved) as free backing → over-reserves a new redemption (`pullRedemptionReserve`, +175%) → `pendingRedemptionEthValue` exceeds ETH+stETH held → breaks SOLVENCY-01; dilutes/strands later redeemers.
- **Reproduction:** see `test/repro/V62RedemptionReentrancy.t.sol` (orchestrator).
- **Fix (gated, NOT applied):** transfer stETH BEFORE the untrusted ETH `.call` (exactly as `DegenerusVault.burnEth` :846-847 already does), or add a reentrancy guard to the claim/burn paths.

### V62-04 — False game-over from a >120-day VRF stall consuming the death clock — **LOW–MED**
- **Origin:** 384 council (gemini G2); adjudicated CONFIRMED, bounded.
- **Defect:** `_handleGameOverPath` runs BEFORE the `purchaseStartDay`-extending `_backfillGapDays` (AdvanceModule:208 vs :1235); `_livenessTriggered` checks `currentDay − psd > 120` on the un-extended psd → a 120+ day stall latches game-over before the stall-credit applies.
- **Bounded:** needs a 4-month governance failure to rotate the coordinator (normal recovery 20h–7d); the design intent is that a long unrecoverable VRF outage SHOULD drain to players — so the "false" framing is debatable. Document; no urgent fix.

### V62-05 — Deity pass `ticketStartLevel` 50-boundary overshoot drops 1–2 paid levels — **LOW** (CONVERGENT codex+gemini)
- WhaleModule.sol:639-641 `((passLevel+1)/50)*50+1` → passLevel 49→start 51 (loses 49,50); whale anchors at `passLevel`. Buyer-only under-delivery; no solvency/theft. Fix: `ticketStartLevel = passLevel` for whale parity.

### V62-06 — Lazy-pass boon price-basis: box/lootbox sized on undiscounted value — **LOW**
- WhaleModule.sol:491/519 size presale-box credit + lootbox-10% on undiscounted `benefitValue` while the buyer pays a boon-discounted price; whale/deity use the discounted `totalPrice`. Bounded by the boon discount; gated behind earning a boon.

### V62-07 — `resolveLootboxDirect` seed omits index/betId → correlated rewards — **LOW/INFO**
- LootboxModule.sol:762 `seed = keccak(rngWord, player, amount)`; same player + same lootbox index batch + same summed `betLootboxShare` → identical box reward. No EV / no freshness break (all inputs frozen at commitment); a fairness/diversity quirk only.

---

## NET-GAPS / DESIGN SEAMS (not findings)
- **NETGAP-02 — advanceGame non-revert liveness:** no invariant forbids `advanceGame()` reverting in a due/unlocked state. G1 (broken-coordinator revert) is an external-VRF dependency recoverable via `updateVrfCoordinatorAndSub` (Admin gate keys on `lastVrfProcessed`, independent of liveness) → not a contract bug. The non-revert property is still worth folding as an invariant (deferred).
- **Mid-day lootbox boon-roll live-state seam (codex C, 385):** `_rollLootboxBoons` reads some live inputs (`deityEligible`, level) after the mid-day word is public (no `rngLockedFlag`). REFUTED on EV: the reward (seed/amount/score) is frozen; the only player-mutable input is `deityEligible`, flippable only via a ≥24 ETH irreversible deity purchase — economically absurd for a sub-budget boon. Defensible seam; documented, no fix.

---

## RESOLVED CANDIDATE — coinflip bonus freshness (was the OPEN coinflip presale-flag MED)
- **Coinflip presale-bonus-flag freshness (codex 385 F2) — RESOLVED by redesign (USER-directed), applied UNCOMMITTED.**
  The daily coinflip bonus read `lootboxPresaleActiveFlag()` LIVE at payout (not frozen at the daily VRF request);
  a lootbox buy crossing `LOOTBOX_PRESALE_ETH_CAP` (200 ETH) clears `PS_ACTIVE`, so a player could toggle the bonus
  after the day's word was public (payout-parameter manipulation — new stake can't join the resolving day,
  `_targetFlipDay = wall-day+1`). **Fix:** dropped the presale-flag read entirely; the bonus is now keyed to the
  FROZEN, protocol-advanced level. `advanceGame` precomputes `uint8 coinflipBonus` and passes it to
  `processCoinflipPayouts` (which just does `rewardPercent += bonus`): **0** on a normal day, **+2** on a bonus day
  (level 0 or a level's first jackpot day), **+6** on a post-BAF x0-level first-jackpot-day (levels 10/20/30…;
  level 0 excluded — no BAF precedes it). Backfilled gap days and gameover settlement always pass **0** (never a
  bonus). Tiers sized so a recycling (auto-rebuy) player nets ~99.9% / ~101.9% RTP once the 0.75% recycle bonus
  compounds (fresh-money bettors land ~0.75% under). Touches BurnieCoinflip + IBurnieCoinflip + AdvanceModule
  (+ a DegenerusGame banner comment); the `processCoinflipPayouts` signature changed `(bool,uint256,uint24)` →
  `(uint8,uint256,uint24)`. Full suite 814/3/110 (baseline parity).

---

## REFUTED / BY-DESIGN (recorded so they are not re-flagged)
- **B near-future ticket jackpot-stuffing (DOMINANT-class, gemini)** — REFUTED: the daily ETH/coin jackpot draws from `traitBurnTicket[lvl]` snapshotted pre-RNG via the `_swapAndFreeze` slot-swap; the only live `ticketQueue` read (far-future coin) is rng-locked; write/read/far-future key spaces are bit-disjoint. gemini misread the buffer.
- **E affiliate multi-sub claim theft (gemini)** — REFUTED: `claim` enforces a same-affiliate guard `if (_referrerAddress(sub) != a) revert` (Affiliate.sol:651) — a mixed-upline batch reverts; per-sub base drained from the sub's own slot; crediting `a` is correct.
- **Affiliate-score magnitude ~2500× (carried 380)** — REFUTED: both `payAffiliate` and afking `claim` accumulate `_totalAffiliateScore` in 1e18 BURNIE base units; differing reward rates (20–25% vs flat-7%) are intended economics.
- **F subscriber ticket-scaling DoS (gemini)** — REFUTED: `_queueTicketsScaled` is O(1) per buyer (single packed `ticketsOwedPacked` slot, ≤1 `push` per (level,buyer)); trait resolution write-budgeted (550).
- **G1 broken-coordinator permanent revert (codex)** — REFUTED: external-VRF dependency, recoverable via governance `updateVrfCoordinatorAndSub`.
- **C mid-day boon-roll / H redemption-lootbox RNG** — REFUTED (see seams / atomic-rngGate ordering).
- **Whale LAST_LEVEL regression (gemini)** — REFUTED: `_applyWhalePassStats` sets LAST_LEVEL to ≥ level+100 (raises, never regresses); `recordMintData` skips LEVEL_COUNT while frozen.
- **382-F1 curse/smite immunity via dailyQuantity (codex)** — BY-DESIGN: `dailyQuantity!=0` is the canonical active-afker predicate; the inclusive-eviction lag is USER-locked; no EV.
- **382-F2 combo-buy revert (codex)** — REFUTED: `_mintCost` retarget matches `_purchaseForWith`; presale leg unreachable in jackpot phase.
- **FC5 entropy-binding** — ENFORCED on-chain (event-only slimming). **FC6 coordinator-swap backfill** — SAFE (reissues same reserved index). **G1/G2 liveness** — see V62-04.
- **F4 IDegenerusGame interface stubs / F5 vault stETH-strand** — INFO/REFUTED: interfaces are inert; `DegenerusVault.burnEth` pays stETH before ETH (the safe ordering sDGNRS lacks — see V62-03).
- **FC1 mid-day pending ticket RNG stalls next advance (codex 385 F3)** — LOW: temporary, self-recovering via `retryLootboxRng` after `MIDDAY_RNG_RETRY_TIMEOUT` (no index increment, no permanent brick).

---

## SWEEP PROGRESS
- [x] 381-06 FUZZ-06 — V62-01.
- [x] 382 PRIME — 0 new confirmed (F1 by-design, F2 refuted, afking solvency/packing/FC4 clean).
- [x] 383 ASYM — V62-05 (deity, convergent), V62-06 (lazy boon), V62-07 (seed collision); affiliate-score + LAST_LEVEL + jackpot symmetry refuted.
- [x] 384 COMPO — **V62-02 (HIGH gas brick, convergent)** + V62-04 (LOW–MED stall game-over); F/G1 refuted.
- [x] 385 LOOP — bounded loops re-verified; B refuted; FC1 LOW; coinflip-presale-flag MED OPEN; FC5/FC6 clean.
- [x] 386 PERIPH — **V62-03 (HIGH redemption reentrancy)** + V62-05 (deity, convergent); E + affiliate-score + F4/F5 refuted; BURNIE/deity/admin/Vault clean.
- [ ] 387 TERMINAL — reproduce V62-02/03 → consolidate → audit/FINDINGS-v62.0.md + closure.

## TALLY
3 actionable (V62-01 MED–HIGH, V62-02 HIGH, V62-03 HIGH) + 4 LOW (V62-04..07) + 1 MED OPEN (coinflip-presale-flag) + 2 design seams + 2 GAS (V62-GAS-01/02) surfaced during remediation. ~15 council candidates refuted/by-design.

## GAS / EFFICIENCY FINDINGS (surfaced during V62-01 remediation review)
- **V62-GAS-01 — vestigial `lootboxEthBase`.** Written on every lootbox deposit (`MintModule:1263`,
  `WhaleModule:907`, `GameAfkingModule:1017`), read-and-discarded in `openLootBox:507-510` (the local is
  never consumed; the reward uses the boosted `lootboxEth` amount + `adj`), zeroed on open (`:548`). ~2
  SSTOREs/box of dead state; its documented "first-deposit signal" role is stale (the enqueue gates on the
  `lootboxEth` amount, `MintModule:1241`). DECISION (USER): remove the slot, or wire the floor in.
- **V62-GAS-02 — oversized `lootboxEth` amount field (232-bit).** ETH fits in ~88 bits; ~140 spare bits.
  Right-size + reclaim to fold other per-box fields into fewer slots.

## REMEDIATION TRACK (USER-gated fixes for the v62 findings — separate from the closed audit milestone)
The audit (380–387) is closed; these are the follow-on fix phases. NO fix committed without USER diff review.
- **R / V62-03** (HIGH, solvency) — sDGNRS redemption reentrancy: stETH-before-ETH ordering / guard.
- **R / V62-02** (HIGH) — advanceGame gas brick: stage-break before the upstream gap-backfill composition.
  **DONE** (applied, UNCOMMITTED, 814/3/110 green — see REMEDIATION OUTCOME below).
- **R / V62-01** (MED–HIGH) — lootbox auto-open: off-by-one (`LR_INDEX-1`) + gas-bounded MULTI-INDEX sweep
  (step budget) + presale leg included + `boxIndexComplete` frontier view. **IN PROGRESS** (contract edits
  applied, not committed; 3 encoded-bug tests to recalibrate; worst-case fuzz pending).
- **R / V62-GAS lootbox repack** — re-examine the box-state model + pack tighter (V62-GAS-01/02). Plan:
  `.planning/PLAN-V62-REMEDIATION-LOOTBOX-PACK.md`. SPEC → IMPL → TST → GAS; storage-layout change, so it
  carries the slot-hardcoded-test recalibration landmine.

## REMEDIATION OUTCOME — V62-01 + lootbox repack + openBox unification + presale-leg gate (applied, UNCOMMITTED, green)
Status: applied to the working tree, NOT committed (USER diff review + commit gate pending). Forge suite
**814 pass / 3 carried-VRFPath fail / 110 skip** (baseline parity). All mainnet contracts fit EIP-170.

### Changes
- **V62-01 robust auto-open** — off-by-one fixed (read `LR_INDEX-1`), gas-bounded MULTI-INDEX step-budget
  sweep (skips count against the budget → no gas-wall), presale leg included, `boxIndexComplete` frontier
  view. Sweep relocated `DegenerusGame` → `DegenerusGameLootboxModule.openHumanBoxes`.
- **Lootbox storage repack** — 4 box mappings → 1 folded `lootboxEth` word
  (amount128 | adj64 | score16 | distress48 @ 0.01-ETH). Removed `lootboxEthBase` / `lootboxPurchasePacked`
  / `lootboxBurnie` / `lootboxDistressEth`. Frozen-input parity preserved (only distress rounds to 0.01 ETH).
- **openBox unification** — `openLootBox` + `openPresaleBox` + `openLootboxAndPresaleBox` → ONE
  `openBox(player, index)` (both legs, each robust to empty; reverts `E` if neither queued). Nested
  self-delegatecall → direct internal call (`_openLootBoxLeg`). `Vault.gameOpenLootBox` removed (opening is
  permissionless — anyone may open via `game.openBox(owner, index)`).
- **Presale-leg gas gate** — `presaleDrained` (one-way bool in slot 0, the hot global-flags slot every open
  path already SLOADs → free read; ZERO downstream slot-shift) + `presaleCloseIndex` (uint48, set once when
  presale closes, co-located in the cursor slot → free sweep read). The in-order sweep flips `presaleDrained`
  once its cursor advances PAST the close index — i.e. every box at indices <= close is opened — after which
  both the sweep AND manual opens skip the cold `presaleBoxEth` SLOAD via the `!presaleDrained` gate. The
  sweep-only flip + cursor-past-close trigger means an out-of-order manual open of the closing box can't trip
  it early and strand a still-queued box.

### Gas / size Outcome
**EIP-170 (empirical, before → after):**
- `DegenerusGame`: c4d48008 + in-flight sweep **24,701 (125 OVER)** → repack 24,125 (+451) → openBox unify
  **23,882 (+694 margin)**.
- `DegenerusGameLootboxModule`: 18,563 → **17,030** (−1,533 bytes; nested-delegatecall + 2 dispatchers removed).

**Runtime gas — structural deltas (worst-case-first opcode accounting):**
- Lootbox deposit (first at an index): 3–4 cold SSTOREs → **1** (distress packs into the folded word) →
  −2 SSTOREs (−3 in distress) ≈ **−40k–60k gas / first-deposit**.
- Lootbox open: 3–4 zeroing SSTOREs + 1 dead `baseAmount` SLOAD → 1 zeroing SSTORE, no dead SLOAD →
  −2 SSTOREs (−3 distress) − 1 SLOAD ≈ **−12k–17k gas / open**.
- Both-leg open: nested delegatecall (encode + delegatecall + decode + redundant `lootboxEth` guard SLOAD)
  → direct internal call ≈ **−0.7k–2.5k gas / open**.
- Post-presale opens (sweep AND manual): once the sweep has drained presale (`presaleDrained` set), the cold
  `presaleBoxEth` SLOAD is eliminated → **−2,100 gas / box** (the slot-0 flag read is free; cost is a
  one-time flag flip — no per-open writes).

**AFTER empirical anchors (current tree, `forge --gas-report`, SweepWorstCaseDrain):**
`buyPresaleBox` 168,355 · `openBoxes` avg 233,483 / median 183,878 / max 698,316 ·
`openHumanBoxes` (module leg) avg 189,453 / median 138,730 / max 659,988.

> Empirical cross-version before/after not captured: the dedicated box-open gas harnesses are SKIPPED on
> HEAD (superseded by `V56AfkingGasMarginal`), and `SweepWorstCaseDrain` post-dates c4d48008, so no
> controlled common scenario exists across the two trees. The win is established by the EIP-170 trajectory
> (empirical) + the worst-case structural opcode accounting + the AFTER anchors above.

## REMEDIATION OUTCOME — V62-02 (advanceGame gas brick) — stage-break before the upstream gap-backfill (applied, UNCOMMITTED, green)
Status: applied to the working tree, NOT committed (USER diff review + commit gate pending). Forge suite
**814 pass / 3 carried-VRFPath fail / 110 skip** (exact baseline parity). `DegenerusGame` EIP-170 unchanged
(23,882) — the fix lives in the separately-deployed `DegenerusGameAdvanceModule` (19,057, well under cap).

### Change (`contracts/modules/DegenerusGameAdvanceModule.sol`)
- New stage `STAGE_SUBS_BACKFILL_DEFERRED` (13). When the afking subscriber STAGE drains the funded set to its
  end in a chunk AND a multi-day VRF-stall gap backfill is pending, `advanceGame` breaks BEFORE `rngGate` — the
  **upstream** mirror of the v60 `STAGE_GAP_BACKFILLED` decouple. The heavy completing subscriber chunk runs
  alone in one tx; the backfill (then the jackpot) run in their own subsequent txs, each under the per-tx ceiling.
- The defer gate is the EXACT condition `rngGate` uses to enter `_backfillGapDays`
  (`rngWordCurrent != 0 && rngRequestTime != 0 && day > dailyIdx+1 && rngWordByDay[dailyIdx+1] == 0`), so it
  defers IFF `rngGate` would actually backfill this call: normal (no-gap) days fall through unchanged (NO extra
  tx), and the empty-subscriber-set case still falls through (a lone backfill is already under ceiling).
- `dailyIdx` unadvanced + `rngWordByDay[day]` unset on the break → `advanceDue()` stays true; the next advance
  runs the idempotent `rngGate` (backfills, then defers the jackpot via `STAGE_GAP_BACKFILLED`). Liveness /
  monotonic progress preserved (NETGAP-02 respected: no revert in a due/unlocked state).

### Proof (worst-case-first, EIP-7825 = 16,777,216)
- `test/repro/V62GasBrickCompose.t.sol` — flipped from brick-repro to fix regression guard. COLD binding regime:
  the all-evict subscriber chunk (tx1 **13.45M**) and the 120-day gap backfill (tx2 **6.83M**) were composing to
  **~20.3M > cap** (the brick); now two txs, each < cap, with `advanceDue` true between them. Boundary control
  (≥500-weight chunk breaks at the partial-drain check → no compose) intact.
- `V56AfkingGasMarginal::testGapResumePerAdvanceCeilingAndDecouple` — updated to the 3-leg sequence
  (STAGE-defer N **0.51M** → gap backfill N+1 **6.80M** → deferred jackpot N+2 **0.27M**), each < cap;
  same-frozen-word + exactly-once `purchaseStartDay`-bump invariants preserved across the resume.
- Full suite 814/3/110. The 3 residual reds are the documented carried bucket-A `VRFPathInvariants`
  (gap-backfill / coordinator-swap / stall) — UNCHANGED by this fix (same failure messages; stash-compare
  vs baseline confirms no new violation, only the non-deterministic counter shifts 61→28). The fix addresses a
  GAS composition, not the gap-backfill correctness modeling those invariants probe (FC1/FC6), so it correctly
  does NOT clear them.
