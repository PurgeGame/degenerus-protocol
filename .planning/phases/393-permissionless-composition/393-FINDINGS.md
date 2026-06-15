# 393-FINDINGS — PERMISSIONLESS-COMPOSITION adjudication (ACCESS-01..05 + FC-393-01..04 + 4 inherited cross-refs)

**Subject (byte-frozen):** `a8b702a7` (contracts tree `2934d3d8987a09c5f073549a0cb499f6c5f28620`;
`git diff a8b702a7 -- contracts/` EMPTY before and after every task in this plan).
**Baseline (the audit oracle):** `test/REGRESSION-BASELINE-v63.md` — forge **854 / 0 / 110**, the
expected forge-failure NAME-set is strictly EMPTY (a regression is any failing name at this subject).
Keeper-bounty anchor: `test/fuzz/DecimatorBountyRegression.t.sol` (5 rules — per-box :134, scales :162,
no-pay-already-claimed/non-winner :180, no-pay-post-gameOver :192, ETH-value-holds + `bounty << 500 BURNIE`
burn cost :148-156). Perma-brick gas anchor: the 1460-deep + 365-window regression (`0a2209d4`). **NOT
relied on as already-netted** — recorded as un-netted ROUTED test-hardening items (§4b): (1) the explicit
real-gas-net-negative-after-illiquidity number, (2) a redemption-bounty (24e12) regression mirror, (3) a
same-block-burst burst-solvency oracle, (4) a fresh packed-layout 365/1460 worst-case gas measurement.
**Method:** COUNCIL + CLAUDE both (AUDIT-V63-PLAN §2 — a no-finding verdict for any slice requires BOTH
nets on record). NET 1 = the cross-model council (`393-01-COUNCIL-NET.md` + `council/access.gemini.txt`;
`codex` SKIPPED — hard usage-limit cap, post-reset re-run flagged → 396). NET 2 = the deep Claude
adversarial net (`393-02-CLAUDE-NET.md`, run independently, council folded after).
**Posture:** AUDIT-ONLY. A CONFIRMED finding is DOCUMENTED and ROUTED to a SEPARATE gated USER-hand-review
boundary — never fixed, never auto-committed in this phase. The subject stays byte-frozen and re-freezes
only after a gated fix boundary.
**Threat weighting (AUDIT-V63-PLAN §4, USER-locked):** access-control / reentrancy / MEV =
**LOW/confirmatory**. The SUBSTANTIVE items in this slice are **ACCESS-02** (keeper-bounty economics vs
REAL gas) and **ACCESS-04** (partial-balance burst solvency) — a real grief/faucet/steer or a
burst-solvency strand weighs HIGHER than the LOW baseline.
**Phase consumes 388-392:** the inherited cross-refs' solvency/ECON halves are SETTLED at 390/392
(FC-390-03 REFUTED, FC-390-06 REFUTED, FC-392-08 solvency/CEI REFUTED + ECON cap-RMW BY-DESIGN, FC-392-20
INFO; FC-393-02/-03 solvency-half BY-DESIGN/REFUTED at 390). The ACCESS halves are adjudicated HERE for
cross-ref consistency, NOT re-derived.
**Design-intent anchor (§5):** permissionless / lootbox claim TIMING is by-design
([[lootbox-resolution-timing-by-design]]) — ACCESS-03 turns on MAGNITUDE not timing; operator-approval IS
the trust boundary ([[open-e-operator-approval-trust-boundary]]); the dust-lootbox-drop is by-design
([[redemption-dust-lootbox-drop-bydesign]]) — FC-393-02 turns on per-victim extractability; RTP/EV
by-design.

---

## 1. Both-nets-on-record attestation

A no-finding (REFUTED / BY-DESIGN / MONITOR) verdict for any item below cites BOTH nets.

| Slice | NET 1 (council) | NET 2 (Claude) | both on record? |
|-------|-----------------|----------------|-----------------|
| PERMISSIONLESS-COMPOSITION (ACCESS-01..05 + FC-393-01..04 + FC-390-03/-06, FC-392-08/-20) | `393-01-COUNCIL-NET.md` + `council/access.gemini.txt` — **`gemini` on record** (VERIFIED SOUND across ALL of ACCESS-01..05 + FC-393-04, 0 findings, with REAL-gas numbers + per-item traces); **`codex` SKIPPED** (hard usage-limit cap, recorded in `skipped[]`, NOT a refusal/classifier-trip) → post-reset re-run flagged to **396** | `393-02-CLAUDE-NET.md` — independent per-item attack pass + ACCESS-02 dedicated real-gas faucet economics + ACCESS-04 same-block leg-accounting burst-solvency + ACCESS-03 adjacent-level magnitude + ACCESS-05 gate/CEI enumeration; council folded at §7 | ✓ both (gemini + Claude; codex-skip documented, 396 re-run flagged) |

**Codex-skip handling (T-393-02):** a slice silently treated as on-record with BOTH CLIs unavailable
would be surfaced for re-run — that condition does NOT apply here: `gemini` is on record with a real
substantive audit, so "council on record" is satisfied with the codex skip documented. The **post-reset
codex second-source of the two substantive primes (ACCESS-02 / ACCESS-04) is RECOMMENDED → 396**.
**T-393-04 (subject tampering):** `git diff a8b702a7 -- contracts/` EMPTY throughout (the council ran
read-only `--approval-mode plan` / `--sandbox read-only`; NET 2 read all source via `git show a8b702a7:` —
hardhat never invoked).

---

## 2. Per-item adjudication table

Verdicts: **REFUTED** (claim attacked, holds) · **BY-DESIGN** (intended, sound) · **MONITOR** (no defect,
carried observation) · **CONFIRMED** (a real defect — routed in §4). All 5 reqs + 4 owned leads + 4
inherited cross-refs carry one row.

### 2a. ACCESS requirements (ACCESS-01..05)

| ITEM | What it claims | NET 1 | NET 2 | VERDICT | Settling cite (`a8b702a7`) |
|------|----------------|-------|-------|---------|-----------------------------|
| **ACCESS-01** | every permissionless claim credits ONLY the beneficiary (no third-party ETH push / forced credit) | SOUND | REFUTED | **REFUTED** | **Per-entrypoint beneficiary credit:** `claimDecimatorJackpot`/`Many` credit only `player` (`_creditClaimable(account=player)` DecimatorModule:459; lootbox to `winner=player` :645-658; no ETH leaves); `claimRedemption`/`Many` route both halves to the GAME FOR `player` (`creditRedemptionDirect{value}(player)` sDGNRS:892, `resolveRedemptionLootbox{value}(player)` :884) or to sDGNRS's own claimable for dust (:898), post-gameOver self-claim-only PUSH to `player` (:830, `Unauthorized` revert :775 / `continue` skip :793); `claimCoinflipCarry` mints to `player = _resolvePlayer(player)` (BurnieCoinflip:758/:777). Keeper bounty is a SEPARATE BURNIE flip-credit (§2b ACCESS-02), never the players' ETH. No forced ETH push, no route-to-caller, no forced-then-forfeited credit. |
| **ACCESS-02** | keeper box-bounty net-NEGATIVE vs REAL gas (5-50+ gwei, not the 0.5-gwei peg) + flip-credit illiquidity + un-manufacturable | SOUND (REAL-gas numbers) | REFUTED (dedicated real economics) | **REFUTED** | **DEDICATED REAL ECONOMICS:** decimator `BOX_BOUNTY_ETH_TARGET = 15e12` (DecimatorModule:117), redemption `= 24e12` (sDGNRS:348) — DISTINCT (the surface-map "both 15e12" was wrong; gemini's 24e12 RIGHT, §3). Real-gas cost vs reward: **10x @5 gwei / 40x @20 gwei / 100x @50 gwei** under-water (decimator ~30k gas vs 0.000015 ETH; redemption ~48k gas vs 0.000024 ETH — IDENTICAL ratio by gas-sizing). Flip-credit illiquidity: `creditFlip`→`_addDailyFlip` next-day stake ×0.5 survive-flip × ~0.59 peg ⇒ realized liquid ≈ **0.30× the ETH-target** ⇒ ~130x-330x under-water. **Un-manufacturable:** each settle-able box exists only from a real burn (decimator `e.claimed=1` :399 / sealed `e.bucket` :397; redemption `claim.ethValueOwed==0→return false` sDGNRS:823, ≥1-whole-token floor, `BurnsBlockedBeforeDailyRng` :991). **Issuance bounded (FC-390-06):** one box/real claim; redemption per-(wallet,day) 160-ETH base cap (:1081) + 50%/day supply cap. `_mintPriceInContext()` reproduces `mintPrice()` exactly (:376) so the caller cannot SKEW + the ETH-value is price-independent. **UN-NETTED test-hardening** (§4b): the explicit real-gas-net-negative-after-illiquidity number + a redemption-bounty regression mirror. |
| **ACCESS-03** | forced claim-timing cannot materially reduce a winner's reward or steer an outcome | INERT | BY-DESIGN/REFUTED (MONITOR posture) | **BY-DESIGN/REFUTED** | **ADJACENT-LEVEL MAGNITUDE:** forced timing controls ONLY the LEVEL ANCHOR (`startLevel = level + 1` DecimatorModule:655; `_rollTargetLevel(currentLevel, seed)` LootboxModule:884) — the reward MAGNITUDE (`amountWei` / `round.poolWei`) is FROZEN at resolution, NOT recomputed from the live level; the OFFSET distribution (near 0-4 @80%, far 5-50 @20%) is fully FROZEN-SEED-determined (`_rollTargetLevel` reads the frozen `seed`, only `baseLevel` moves); win/loss + EV multiplier frozen (`round.rngWord` :277, `e.bucket` :397, mixes `player` not `msg.sender`). A forced EARLIER resolution lands the SAME offset distribution on a LOWER anchor (closer-level tickets — beneficial/neutral). No adjacent-level divergence makes a forced resolution materially HARMFUL. Settled on the MAGNITUDE (not a timing dismissal). MONITOR: a genuinely NEW externally-forceable timing surface — recorded so a future level-dependent-magnitude change re-opens it. |
| **ACCESS-04** | partial-balance redemption-leg solvency holds under same-block bursts | SOUND | REFUTED (dedicated leg accounting) | **REFUTED** | **SAME-BLOCK LEG ACCOUNTING:** `totalRolledEth = (ethValueOwed * roll)/100` (sDGNRS:822); branches sum to `totalRolledEth` exactly (gameOver :835; live full :837-838; live dust :846-847); `_pendingRedemptionEthValue -= totalRolledEth` released ONCE BEFORE legs (:854) + `delete` slot (:857, blocks re-claim :823). Each leg recomputes fresh `bal = address(this).balance`, sends `min(bal, legAmount)` ETH (:880/:888/:896), GAME pulls remainder `stethPortion = amount - msg.value` via `transferFrom` reverting fail-closed if short (LootboxModule:932-936/:1009-1011) — each leg moves the FULL `legAmount` of VALUE regardless of `bal`. **Σ legs == Σ rolled == Σ released** over the burst; an ETH-drain by earlier same-block claims only SHIFTS a later claim's ETH/stETH SPLIT, never the total; the MAX(175%) reservation (ETH+stETH ≥ Σ MAX ≥ Σ rolled, segregated at submit :742/:1046-1056) covers each leg's stETH remainder ⇒ no strand, no under-pull. **UN-NETTED test-hardening** (§4b): a same-block-burst multi-claim burst-solvency oracle. |
| **ACCESS-05** | freeze/rngLocked/liveness/gameOver gates intact on all new/widened entrypoints; reentrancy closed across ETH/stETH legs | SOUND | REFUTED (per-entrypoint gate + CEI enum) | **REFUTED** | **PER-ENTRYPOINT GATE + CEI:** decimator `if (prizePoolFrozen) revert E()` (:298/:329) + `e.claimed=1` before lootbox-resolve (:399); redemption live `redemptionPeriods[day]!=0` + burn-side `BurnsBlockedBeforeDailyRng` (:991), post-gameOver self-claim-only (:775/:793), slot `delete` + segregation lowered BEFORE the untrusted `_payEth` (:854/:857/:830), `_payEth` stETH-FIRST / ETH-`.call`-LAST; carry `if (rngLocked()) revert RngLocked()` (BurnieCoinflip:759), carry debited before mint (:773-777). Callees `resolveRedemptionLootbox`/`creditRedemptionDirect` gate `msg.sender != SDGNRS` (LootboxModule:927/:1005). `distributeYieldSurplus` internal-only (advanceGame), credits-only when `totalBal > obligations` — not an independent lever. `_payoutWithStethFallback` reordered (53cd25cf) stETH-out-first / ETH-call-last (DegenerusGame.sol:1888-1914, V62-03 closed). No missing/widened gate; no open reentrancy path. |

### 2b. Owned leads (FC-393-01..04)

| ITEM | What it claims | NET 1 | NET 2 | VERDICT | Settling cite (`a8b702a7`) |
|------|----------------|-------|-------|---------|-----------------------------|
| **FC-393-01** | forced-timing on the winner — verify adjacent-level magnitude | INERT | BY-DESIGN/REFUTED (MONITOR) | **BY-DESIGN/REFUTED (MONITOR)** | Same as ACCESS-03: reward magnitude frozen; offset distribution frozen-seed-invariant; only the level anchor moves; forced earlier = beneficial/neutral. LootboxModule:`_rollTargetLevel`/:884, DecimatorModule:655-658/:277/:397. |
| **FC-393-02** | forfeit-to-self timing benign (per-victim extractability)? | SOUND (non-extractive) | BY-DESIGN/REFUTED | **BY-DESIGN/REFUTED** | Dust/full split DETERMINISTIC from fixed `roll` (sDGNRS:771) + the player's own owed value (:843-848); forfeit credits sDGNRS's OWN claimable (`creditRedemptionDirect{value}(address(this), forfeitEth)` :898) raising backing for ALL holders UNIFORMLY — no per-victim target, no per-victim value extraction. Keeper choice biases only the benign TIMING of uniform backing accrual. Consistent with 390 FC-393-02 solvency-half. |
| **FC-393-03** | partial-balance same-block burst solvency (MED prime) | SOUND | REFUTED | **REFUTED** | Same as ACCESS-04: Σ legs == Σ rolled == Σ released; each leg fresh-`bal` + stETH-remainder fail-closed; MAX(175%) reservation covers; ETH-drain shifts to stETH leg. sDGNRS:822/:854/:880-900, LootboxModule:932-936/:1009-1011. ACCESS half here; solvency half REFUTED at 390 §2c. |
| **FC-393-04** | widened claim-loop gas worst-case | SOUND | REFUTED/INFO | **REFUTED/INFO** | Windows 365/1460 (BurnieCoinflip:136-138) over packed masked sub-word (`coinflipDayResultPacked` :1093); claims USER-PAID + OUT of the advanceGame chain; the advanceGame-chain sDGNRS auto-settle walks `deep=false` ≤365, ~1 day/advance steady state; the unbounded 365/1460 walk is reachable only by a self-paid caller, never bricking advanceGame. Perma-brick gas pinned (`0a2209d4`). **UN-NETTED test-hardening** (§4b): a fresh packed-layout worst-case gas measurement. Same surface as FC-392-20. |

### 2c. Inherited cross-refs (FC-390-03, FC-390-06, FC-392-08, FC-392-20 — ACCESS half here; solvency/ECON half settled at 390/392)

| ITEM | What it claims | NET 1 | NET 2 | VERDICT (ACCESS half) | Settling cite (`a8b702a7`) + consistency |
|------|----------------|-------|-------|------------------------|-------------------------------------------|
| **FC-390-03** | mid-batch gameOver/frozen boundary — permissionless batch cannot split inconsistently | SOUND (cache once) | REFUTED | **REFUTED (ACCESS half)** | `claimDecimatorJackpotMany` caches `bool over = gameOver` ONCE (DecimatorModule:341, invariant comment :335-337); `claimRedemptionMany` caches `isGameOver` ONCE (sDGNRS:791); resolution-into-claimable legs hold no untrusted ETH hook that flips the boundary mid-loop. **Consistent** with 390 §2b (solvency half REFUTED — batch caches over/frozen/offsets/totalBurn once; all value to winner). |
| **FC-390-06** | keeper-bounty creditFlip issuance bounded (no unbounded BURNIE dilution) | SOUND (bounded) | REFUTED | **REFUTED (ACCESS half)** | Downstream-dilution half: one box per real claimed entry (DecimatorModule:364-370); redemption per-(wallet,day) 160-ETH base cap (sDGNRS:1081) + 50%/day supply cap; BURNIE off the direct ETH/stETH spine. Issuance scales ONLY with real burns ⇒ no unbounded dilutive mint. **Consistent** with 390 §2b (issuance bounded REFUTED). Folded into ACCESS-02 un-manufacturability. |
| **FC-392-08** | redemption ETH-spin pool RMW + recirc — permissionless cross-chunk-race half | SOUND (flush-before-recirc) | REFUTED | **REFUTED (ACCESS/permissionless-race half)** | `resolveRedemptionLootbox` credits the pool by `amount` BEFORE the chunk loop (LootboxModule:945-947); chunks run sequentially in ONE delegatecall frame (:951-957) with the ETH-spin reading/writing fresh storage per chunk (no deferred memory accumulator) ⇒ no cross-chunk cap-RMW race even within a multi-chunk claim. **Consistent** with 390 §2c (solvency/CEI REFUTED — flush-before-recirc, stETH-remainder-in-before-credit, chunks sequential one frame) + 392 (ECON cap-RMW BY-DESIGN — recirc depth 1, monotonic cap). |
| **FC-392-20** | widened claim-loop gas — fresh worst-case half (= FC-393-04) | SOUND | REFUTED/INFO | **REFUTED/INFO** | Same as FC-393-04: caller-paid; off advanceGame chain; auto-settle `deep=false` bounded. **Consistent** with 392 (INFO — bounded, caller-paid, off advanceGame chain; fresh worst-case → 393 as FC-393-04). |

---

## 3. Cite reconciliation at the frozen source (the two NET-1 cite-drifts)

393-01 routed two `gemini` cite-drifts to reconcile at the frozen source (this is why the Claude net
matters here — it re-reads every cite). Settled at `a8b702a7`:

| Item | NET-1 (gemini) cite | Frozen-source TRUTH | Resolution |
|------|---------------------|---------------------|------------|
| Redemption bounty constant | `24e12` wei (~48k gas) | `BOX_BOUNTY_ETH_TARGET = 24_000_000_000_000` — **StakedDegenerusStonk.sol:348** | **gemini was RIGHT; the surface-map/plan-cite "both bounties 15e12 identical" was WRONG.** The two bounties are DISTINCT — decimator `15e12` (DecimatorModule:117), redemption `24e12` (sDGNRS:348). The redemption settle (~48k gas, stETH legs) is heavier, so the larger target matches the per-box gas-reimbursement at the 0.5-gwei reference. **The ACCESS-02 net-negative-vs-real-gas conclusion HOLDS at the TRUE constants** — the reward-to-real-gas RATIO is identical for both (sized to settle gas), so both are 10x/40x/100x under-water at 5/20/50 gwei before the ×0.30 illiquidity. |
| `claimCoinflipCarry` carry-mint line | `BurnieCoinflip.sol:787` | entry **:754**; `rngLocked` gate **:759**; `burnie.mintForGame(player, claimed)` mint **:777** | neither @366 (plan entry) nor :787 (gemini). The true entry is :754, gate :759, mint :777. The ACCESS-01 beneficiary-only verdict for the carry rests on the corrected :754/:759/:777 lines (mints to `player = _resolvePlayer(player)`, not `msg.sender`). |

Both cite-drifts are bookkeeping (NOT findings) — the no-finding verdicts now rest on the correct frozen
lines.

---

## 4. Skeptic gate + routing

### 4a. Skeptic gate (run before any CATASTROPHE/HIGH)

**Outcome: 0 items reach CATASTROPHE/HIGH.** Both surface-maps found 0 HIGH on inspection; both nets
converge on NO contract defect across all 13 items (gemini 0 findings, all VERIFIED SOUND; NET 2 all
REFUTED / BY-DESIGN). The gate is recorded for the two SUBSTANTIVE items (ACCESS-02 keeper-bounty,
ACCESS-04 partial-balance burst) and the forced-timing item (ACCESS-03), per the §4 weighting that
elevates a real faucet/grief/steer or a burst-solvency strand above the LOW baseline.

| Substantive item | structural-protection check | 3-condition EV / reachability lens | gate result |
|---|---|---|---|
| **ACCESS-02** (keeper box-bounty faucet) | Bounty is illiquid BURNIE flip-credit (×0.5 ×0.59 ≈ 0.30·V), sized to settle gas at the 0.5-gwei reference; each box requires a real burn (un-manufacturable); issuance bounded by real burns + 160-ETH/50%-day caps. | (1) reachable net-positive faucet? **NO** — 10x/40x/100x under-water at real gas BEFORE the ×0.30 illiquidity; un-manufacturable (no Sybil box fabrication). (2) profitable? NO (net-negative at all real gas). (3) repeatable? n/a (each box one real burn). | **NOT a finding** — fails (1)+(2). REFUTED. A real-gas faucet would be elevated; this is net-negative + un-manufacturable. |
| **ACCESS-04** (partial-balance burst strand) | Each leg recomputes a fresh balance + pulls the stETH remainder fail-closed; the MAX(175%) reservation (ETH+stETH ≥ Σ MAX ≥ Σ rolled) covers every leg; Σ legs == Σ rolled == Σ released. | (1) reachable strand/under-pull in a same-block burst? **NO** — an ETH-drain only shifts a later claim's ETH/stETH SPLIT, never the total; stETH-remainder `transferFrom` reverts fail-closed if short. (2) profitable? n/a. (3) repeatable? n/a. | **NOT a finding** — fails (1). REFUTED. A burst-solvency strand would be elevated; the Σ identity + reservation bound holds. |
| **ACCESS-03 / FC-393-01** (forced-timing magnitude) | Reward magnitude frozen at resolution; offset distribution frozen-seed-invariant; only the level anchor moves; forced earlier = beneficial/neutral (closer-level tickets); win/loss + EV mix `player` not `msg.sender`. | (1) reachable material reward reduction / outcome steer? **NO** — magnitude frozen, offset frozen-seed-determined, anchor shift is beneficial/neutral. (2) profitable to the griefer? NO (no extraction). (3) repeatable? n/a. | **NOT a finding** — fails (1). BY-DESIGN/REFUTED, MONITOR posture (NEW forceable timing surface recorded). |

No item is tagged CATASTROPHE/HIGH. The skeptic gate confirms the two substantive primes are
structurally unreachable as a faucet / burst-strand (fail EV condition 1/2), and the forced-timing item
cannot materially reduce the winner's frozen reward.

### 4b. Routing — CONFIRMED findings + carried INFO/MONITOR + un-netted test-hardening

**0 CONFIRMED contract findings — document-only; ACCESS-01..05 attested at `a8b702a7`.** ACCESS-01..05,
FC-393-01..04, and the 4 inherited cross-ref ACCESS halves are all REFUTED / BY-DESIGN against `a8b702a7`
with BOTH nets on record.

**Carried INFO / MONITOR (no contract change; recorded so a future reader doesn't re-derive):**
- **ACCESS-03 / FC-393-01 forced-timing → MONITOR** — a genuinely NEW externally-forceable timing
  surface (the level anchor). It is INERT today (frozen reward magnitude + frozen-seed-invariant offset
  distribution; forced earlier = beneficial/neutral). Recorded so a FUTURE change that makes the reward
  magnitude level-dependent at the live level would re-open the question. No change.
- **FC-393-02 forfeit-to-self → BY-DESIGN** — deterministic dust/full split, no per-victim extraction,
  uniform backing accrual. The dust-drop policy is by-design ([[redemption-dust-lootbox-drop-bydesign]]).
- **FC-393-04 / FC-392-20 claim-loop gas → INFO** — caller-paid, off the advanceGame chain, auto-settle
  `deep=false` bounded. No advanceGame brick.
- **Cite-drift (§3) — NOT findings, bookkeeping:** redemption bounty is 24e12 (not 15e12); carry entry
  :754 / mint :777 (not @366/:787). The no-finding verdicts rest on the corrected lines.

**Routed UN-NETTED test-hardening items (oracle/gas completeness — NOT contract changes; possible nets at
a later test phase 395/396):**
1. **ACCESS-02** — the explicit real-gas-net-negative-after-illiquidity number (the closed-form 10x/40x/
   100x × 0.30 argument is not a pinned oracle) AND a REDEMPTION-bounty (24e12) regression mirror of the 5
   decimator rules (`DecimatorBountyRegression` pins only the decimator 15e12 bounty at the 0.5-gwei
   reference).
2. **ACCESS-04** — a SAME-BLOCK-BURST multi-claim burst-solvency invariant (the existing
   `RedemptionStethFallback` 10/10 + `RedemptionAccounting` EXERCISE the single-claim partial-balance legs
   + V62-03 CEI, but neither runs an adversarial K-claim same-block drain).
3. **FC-393-04** — a fresh PACKED-LAYOUT worst-case gas measurement of the 365/1460 walk over the new
   masked sub-word layout (beyond the `0a2209d4` perma-brick regression).

Any test-only (oracle-integrity / missing-property) gap is ROUTED, NOT a contract finding.

**Codex second-source owed:** `codex` skipped (usage cap). The slice has `gemini` on record (satisfies
"council on record" with the skip documented). **Post-reset codex re-run → 396** to second-source the
`gemini` SOUND verdicts, especially the two substantive primes (ACCESS-02 / ACCESS-04).

---

## 5. Cross-ref consistency block (each ACCESS half vs its 390/392 solvency/ECON counterpart)

| Cross-ref | Already-adjudicated half (390/392) | ACCESS half reached HERE | consistent? |
|-----------|------------------------------------|--------------------------|-------------|
| **FC-390-03** | REFUTED at 390 §2b (batch caches over/frozen/offsets/totalBurn once; resolution-into-claimable only; all value to winner) | REFUTED — no permissionless batch splits inconsistently across the boundary (caches once; no untrusted hook flips the boundary mid-loop) | ✓ — both REFUTED, same caching fact |
| **FC-390-06** | REFUTED at 390 §2b (per box actually settled; (wallet,day) 160-ETH base + 50%/day supply caps; decimator per real entry; downstream BURNIE-dilution → ACCESS-02/393) | REFUTED — issuance bounded; no unbounded dilutive BURNIE mint; folded into ACCESS-02 un-manufacturability | ✓ — the 390 hand-off (downstream dilution → 393) is settled here, consistent |
| **FC-392-08** | REFUTED solvency/CEI at 390 §2c (flush-before-recirc; stETH-remainder-in-before-credit; chunks sequential one frame) + ECON cap-RMW BY-DESIGN at 392 (recirc depth 1; monotonic cap) | REFUTED — permissionless cross-chunk-race half: pool credited before the chunk loop; chunks sequential in one frame; fresh per-chunk storage (no cross-chunk cap-RMW race) | ✓ — solvency (390) + ECON (392) + permissionless-race (393) all REFUTED/BY-DESIGN, no contradiction |
| **FC-392-20** | INFO at 392 (bounded, caller-paid, off advanceGame chain; fresh worst-case → 393 as FC-393-04) | REFUTED/INFO — caller-paid; off advanceGame chain; auto-settle deep=false bounded | ✓ — both INFO, the fresh worst-case hand-off settled here |
| **FC-393-02** (cross-ref 390 FC-390-02) | BY-DESIGN/REFUTED solvency-half at 390 (dust-forfeit deterministic split; backed by value leaving sDGNRS, fail-closed) | BY-DESIGN/REFUTED — no per-victim extraction; uniform backing accrual | ✓ — both BY-DESIGN/REFUTED |
| **FC-393-03** | REFUTED solvency-half at 390 §2c (each leg fresh `bal`; GAME pulls remainder fail-closed; Σ legs == Σ rolled == Σ released; MAX reservation covers) | REFUTED — same-block burst: Σ identity holds; ETH-drain shifts to stETH leg; no strand/under-pull | ✓ — both REFUTED, same leg-accounting fact |

**No ACCESS half contradicts its 390/392 solvency/ECON counterpart.** The cross-refs are consistent across
390 (solvency/CEI) / 392 (ECON cap-RMW + gas INFO) / 393 (ACCESS / permissionless-race).

---

## 6. Re-attestation line (each req attested-or-finding)

| Req | Status at `a8b702a7` |
|-----|----------------------|
| ACCESS-01 | ATTESTED (beneficiary-only per entrypoint; no third-party ETH push / forced credit) |
| ACCESS-02 | ATTESTED (keeper-bounty net-negative 10x/40x/100x @5/20/50 gwei × 0.30 illiquidity + un-manufacturable + issuance bounded; redemption 24e12 / decimator 15e12 distinct, both net-negative) |
| ACCESS-03 | ATTESTED (forced-timing magnitude inert; reward frozen; offset distribution frozen-seed-invariant; forced earlier beneficial/neutral; MONITOR posture) |
| ACCESS-04 | ATTESTED (partial-balance burst solvency: Σ legs == Σ rolled == Σ released; MAX(175%) reservation covers; ETH-drain shifts to stETH leg fail-closed; no strand/under-pull) |
| ACCESS-05 | ATTESTED (freeze/rngLocked/liveness/gameOver gates intact per entrypoint; CEI stETH-first/ETH-last; SDGNRS-gated callees; internal-only yield-surplus; V62-03 closed) |

**Verdict:** the phase-393 permissionless-composition surface is adjudicated with BOTH nets on record, the
skeptic gate applied (0 HIGH — both nets converge on no contract defect across all 13 items), and every
req + owned lead + inherited cross-ref carrying an explicit verdict backed by a beneficiary-credit / gate /
CEI / reservation / un-manufacturability / magnitude cite. The keeper box-bounty is settled by a dedicated
real-gas economic argument (net-negative at all real gas + un-manufacturable + issuance bounded; the two
bounties 15e12/24e12 distinct, both net-negative); the partial-balance burst-solvency is settled by a
same-block leg-accounting argument (Σ identity + MAX reservation); the forced-timing is settled on the
adjacent-level magnitude question (frozen reward + frozen-seed-invariant offset distribution); the gate +
reentrancy is enumerated on every new/widened entrypoint; the ACCESS halves are consistent with their
390/392 solvency/ECON counterparts. **0 CONFIRMED contract findings.** The byte-frozen subject is attested
document-only at `a8b702a7` throughout (`git diff a8b702a7 -- contracts/` EMPTY). The 2 cite-drifts are
reconciled at the frozen source; 4 un-netted test-hardening items + a post-reset codex second-source are
routed (→ 395/396).
