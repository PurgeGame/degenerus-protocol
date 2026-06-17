# 390-FINDINGS — SOLVENCY-SPINE adjudication (SOLV-01..07 + FC-390-01..07 + 5 inherited cross-refs)

**Subject (byte-frozen):** `a8b702a7` (contracts tree `2934d3d8987a09c5f073549a0cb499f6c5f28620`;
`git diff a8b702a7 -- contracts/` EMPTY before and after every task in this plan).
**Baseline (the audit oracle):** `test/REGRESSION-BASELINE-v63.md` — forge **854 / 0 / 110**, the
expected forge-failure NAME-set is strictly EMPTY (a regression is any failing name at this subject).
Redemption coverage anchors: `RedemptionStethFallback.t.sol` (10/10 branch-proofs, the V62-03 CEI class
EXERCISED) + `RedemptionAccounting.t.sol` (per-(player,day) EXERCISED). **The legacy
`RedemptionInvariants` 7-INV harness is the 388-02 #2 SUPERSEDED HOLE** (un-wired claim/resolve + stale
slots 10/13/14/15 → INV-05/07 vacuous, INV-08 a 0==0 tautology) — NOT relied on for any verdict below.
**Method:** COUNCIL + CLAUDE both (AUDIT-V63-PLAN §2 — a no-finding verdict for any slice requires BOTH
nets on record). NET 1 = the cross-model council (gemini + codex via council.sh), captured in
`390-01-COUNCIL-NET.md` + `council/solv.{gemini,codex}.txt`. NET 2 = the deep Claude adversarial net,
captured in `390-02-CLAUDE-NET.md` (run independently, council leads folded after).
**Posture:** AUDIT-ONLY. A CONFIRMED finding is DOCUMENTED and ROUTED to a SEPARATE gated USER-hand-
review boundary — never fixed, never auto-committed in this phase. The subject stays byte-frozen and
re-freezes only after a gated fix boundary.
**Threat weighting (AUDIT-V63-PLAN §4, USER-locked):** solvency = the **SPINE** — the highest-priority
dimension here. A real `claimablePool` / sDGNRS-backing break is HIGH-or-above; a benign timing/INFO
item is not. DOMINANT = RNG/freeze · HIGH = gas-DoS only in the advanceGame chain · LOW/confirmatory =
access-control + reentrancy + MEV.
**Design-intent anchor (§5):** verify identity/safety, do NOT re-litigate documented intended mechanics.
The dust-drop forfeit-to-claimable is an intended anti-dust-farm mechanism
([[redemption-dust-lootbox-drop-bydesign]]) — VERIFY it is BACKED, do not flag the policy. The keeper
creditFlip bounty's downstream BURNIE dilution is owned by ACCESS-02 / 393.

---

## 1. Both-nets-on-record attestation

A no-finding (REFUTED / BY-DESIGN) verdict for any item below cites BOTH nets.

| Slice | NET 1 (council) | NET 2 (Claude) | both on record? |
|-------|-----------------|----------------|-----------------|
| SOLVENCY (SOLV-01..07 + FC-390-01..07 + FC-389-02/-08, FC-392-08, FC-393-02/-03) | `390-01-COUNCIL-NET.md` + `council/solv.{gemini,codex}.txt` — both CLIs available, 0 skipped. codex: no reachable solvency finding (SOUND across all items, file:line anchored). gemini: SOUND on SOLV-01..06 + the prime targets, but ONE HIGH research-stage lead on SOLV-07 (`whalePassCost` double-credit) — the single material cross-model divergence, routed here. | `390-02-CLAUDE-NET.md` — independent per-item attack pass + SOLV-05 multi-tx ordering (a/b/c) + SOLV-04 dust-forfeit backing proof under the MAX reservation + SOLV-06 CEI trace over 4 payout legs + the SOLV-07 wei-level divergence resolution | ✓ both |

T-390-05 (a no-finding verdict issued with only one net, or leaning on the superseded HOLE) does not
apply: both nets are on record; the superseded `RedemptionInvariants` green is explicitly not relied on,
the EXERCISED `RedemptionStethFallback` (10/10) + `RedemptionAccounting` tests are the anchor. T-390-04
(subject tampering) mitigation: `git diff a8b702a7 -- contracts/` EMPTY throughout (the council ran
read-only `--approval-mode plan` / `--sandbox read-only`; NET 2 read all source via `git show
a8b702a7:` — hardhat never invoked).

---

## 2. Per-item adjudication table

Verdicts: **REFUTED** (claim attacked, holds) · **BY-DESIGN** (intended, sound) · **MONITOR** (no
defect, carried observation) · **CONFIRMED** (a real defect — routed in §4). All 7 reqs + 7 owned leads
+ 5 inherited cross-refs carry one row.

### 2a. SOLV requirements (SOLV-01..07)

| ITEM | What it claims | NET 1 | NET 2 | VERDICT | Settling bound / cite (`a8b702a7`) |
|------|----------------|-------|-------|---------|-------------------------------------|
| **SOLV-01** | `claimablePool == Σ claimable + Σ afking` across every changed credit/debit | SOUND | REFUTED | **REFUTED** | Every spine touch pairs an equal `claimablePool` move: claimWinnings `_debitClaimableAndAfking` + `claimablePool -= payout` (DegenerusGame.sol:1247-1248); creditRedemptionDirect `_creditClaimable` + `claimablePool += amount` (LootboxModule:1013-1014); pullRedemptionReserve `_debitClaimable` + `claimablePool -= amount` (Game:1582-1583); daily delta-fold one `claimablePool += liabilityDelta` (JackpotModule:1117-1120); yield fold `claimablePool = cached + quarterShare*3` (:707-713); deity refund / decimator spend folded once (GameOverModule:130/:169). `_settleShortfall` single sink, paired debits (Storage:867). No unpaired credit/debit. |
| **SOLV-02** | sDGNRS `pendingRedemptionEthValue` backing identity preserved; balance + stETH ≥ obligations | SOUND | REFUTED | **REFUTED** | Backing read `totalMoney = ethBal + stethBal + claimableEth − _pendingRedemptionEthValue` consistent at StakedDegenerusStonk.sol:674/:924/:1023 (segregated reserve excluded so never double-spent). uint96 real-ETH bound: per-(wallet,day) base ≤ 160 ETH (:1081) × 175% ≪ uint96; cumulative ≪ 1.2e26 wei. Every narrowing on a CHECKED expr: submit :1066, resolve :745, claim :854. poolBalances uint128 supply-bounded. (Folds FC-389-02/-08 solvency half.) |
| **SOLV-03** | submit/claim conservation: ethDirect + lootboxEth + forfeitEth == released; no double-count/leak | SOUND | REFUTED | **REFUTED** | Every branch of `_claimRedemptionFor` sums to `totalRolledEth`: gameOver ethDirect=total (:835); live full direct+lootbox=total (:837-838); live dust direct+forfeit=total (forfeit=old lootbox, :846-847). `_pendingRedemptionEthValue -= totalRolledEth` (:854) releases exactly that; MAX−rolled over-pull stays as free backing. Submit reserves MAX (:1063), resolve lowers MAX→rolled (:745), claim releases rolled (:854) — telescopes, no double-count. Fail-closed: a reverting leg unwinds the release. |
| **SOLV-04** | dust-forfeit self-credit always backed by value leaving sDGNRS; never bumps claimable beyond release | SOUND (value-in-before-credit) | REFUTED (dedicated proof) | **REFUTED** | DUST-FORFEIT BACKING PROOF: `creditRedemptionDirect{value: ethForForfeit=min(bal,forfeitEth)}(address(this), forfeitEth)` (StakedDegenerusStonk.sol:898-900); GAME pulls `stethPortion = forfeitEth − msg.value` via `steth.transferFrom`, **reverting the whole tx if it fails** (LootboxModule:1009-1011), THEN `_creditClaimable(SDGNRS, forfeitEth)` + `claimablePool += forfeitEth` (:1013-1014). Credit = ETH-in + stETH-pulled = forfeitEth value LEFT sDGNRS. MAX(175%) reservation guarantees ETH+stETH ≥ rolled ≥ Σ legs, so the remainder pull always covers; fail-closed on shortfall. Value-in-before-credit (CEI). No phantom bump. (= FC-390-02.) |
| **SOLV-05** | redemption CLAIM liveness-window ordering — no strand/double-credit vs handleGameOverDrain snapshot / latch | SOUND (tx-atomicity) | REFUTED (dedicated multi-tx) | **REFUTED** | MULTI-TX ORDERING BOUND: redemption ETH is segregated OUT of the game at submit (pullRedemptionReserve → sDGNRS), so it is NOT in the drain's `totalFunds` (GameOverModule:78, comment :82-84); drain reserves only `claimablePool` (:85). EVM tx atomicity: a claim runs entirely before OR after the drain. BEFORE → its credits are already in claimablePool (counted as reserved). AFTER → `gameOver()` read at top of claim (:775) returns true → post-game 100% direct PUSH from sDGNRS's own segregated balance (never the game ledger). Interleavings (a)/(b)/(c) all impossible: single `isGameOver` snapshot + atomic release(:854)/slot-delete(:857)/credit-legs in one tx; cleared slot (`ethValueOwed==0` :823) blocks any post-game double-pay. Batch caches isGameOver once (:791), no untrusted ETH hook flips gameOver mid-loop. (= FC-390-01.) |
| **SOLV-06** | CEI / yield-surplus reentrancy closed (stETH-before-ETH; V62-03 class) | SOUND (stETH-before-ETH) | REFUTED (dedicated CEI trace) | **REFUTED** | CEI-ORDERING TRACE over the changed legs: claimWinnings debits state (:1247-1248) BEFORE payout; `_payoutWithStethFallback` moves stETH out FIRST (:1902-1907), untrusted ETH `.call` LAST (:1912-1914) — `53cd25cf` reorder, comment :1891-1894; sDGNRS `_payEth` stETH-first (:1108-1115); pullRedemptionReserve debit-before-call (:1582-1585). `distributeYieldSurplus` obligations sum reads all live pools + claimablePool fresh (:688-700), `totalBal ≤ obligations ⟹ return` (:702), so a reentrant call cannot read in-flight stETH as surplus. New credit legs pull value in before crediting (no untrusted reentry). Anchored on RedemptionStethFallback.t.sol 10/10 (V62-03 EXERCISED). |
| **SOLV-07** | JackpotModule delta-fold completeness — no pool credited or deleted twice | **gemini HIGH lead** vs **codex SOUND** (DIVERGENT) | **REFUTED (single-counted; gemini premise false at source)** | **REFUTED** | DIVERGENCE RESOLVED at frozen source (see §3a). `_processSoloBucketWinner` (:1246-1281): claimablePool gets only `ethAmount = perWinner − whalePassCost` (:1268-1269); futurePrizePool gets `whalePassCost` ONCE via `_addFuturePrizePool` (:1274); whale pass is a non-ETH tickets claim (whalePassClaims → claimWhalePass → `_queueTicketRange`, WhaleModule:991-1007, NO claimablePool/ETH). `_handleSoloBucketWinner` adds `wpSpent` into `paidDelta` (:1214-1215) ⟹ `paidDailyEth` INCLUDES whalePassCost ⟹ `unpaidDailyEth = dailyEthBudget − paidDailyEth` (:443) EXCLUDES it; non-final-day `currentPrizePool -= paidDailyEth` (:451) removes it. gemini's premise (paidDailyEth = ETH-only) is FALSE. No double-credit; delta-fold captures every `_creditClaimable` once (`_addClaimableEth` removed, F1). |

### 2b. SOLV owned leads (FC-390-01..07)

| ITEM | What it claims | NET 1 | NET 2 | VERDICT | Settling bound / cite |
|------|----------------|-------|-------|---------|-----------------------|
| **FC-390-01** | claim path has no liveness gate; gameOver read once — strand/double-credit window | SOUND | REFUTED | **REFUTED** | Same as SOLV-05: reserve segregated out of drain totalFunds + tx-atomicity + reserved=claimablePool + atomic release/slot-delete. claimRedemptionMany caches isGameOver once (:791), no mid-batch flip. StakedDegenerusStonk.sol:771-801, GameOverModule:73-182. |
| **FC-390-02** | dust-forfeit self-credit via creditRedemptionDirect — phantom-bump risk | SOUND | REFUTED | **REFUTED** | Same as SOLV-04: GAME pulls `forfeitEth − msg.value` as stETH (reverts if short) before crediting; credit always = value left sDGNRS; MAX reservation covers; fail-closed. StakedDegenerusStonk.sol:897-900, LootboxModule:1004-1014. |
| **FC-390-03** | permissionless decimator/redemption claim + gameOver/freeze edge | SOUND (cache once) | REFUTED | **REFUTED** | Resolution-into-claimable only — all value to the winner, never the caller (DecimatorModule:294-297); reverts on prizePoolFrozen (:298); batch caches over/frozen/offsets/totalBurn once (:338-341) with the explicit invariant comment (:335-337) — claim effects can't flip gameOver/frozen (separate tx). No mid-batch split; live-credited claimable withdrawn normally, post-game uses direct PUSH to avoid forfeiture (StakedDegenerusStonk.sol:768). |
| **FC-390-04** | burnEth `claimValue > combined` dropped `&& claimable != 0` — wasted 0-net claim at last burn | SOUND (equality not `>`) | REFUTED / MONITOR | **REFUTED** | `claimValue ≤ reserve = combined + claimable` for `amount ≤ supplyBefore` ⟹ `claimValue > combined ⟹ claimable > 0` (DegenerusVault.sol:756-761). At `amount==supplyBefore`, `claimValue==reserve` exceeds `combined` iff claimable>0; `_netClaimableWinnings` (:754) dust-nets the sentinel to 0, so sentinel-only ⟹ guard false ⟹ no wasted call. Worst case was a wasted call only. |
| **FC-390-05** | gameDegeneretteBet overpay guard relocated game-side | SOUND (identical) | INFO / VERIFIED | **REFUTED (verified equivalent)** | `_collectBetFunds:596 if (ethPaid > totalBet) revert InvalidBet()` with `totalBet = amountPerTicket*ticketCount` (:535) — identical to the removed vault formula; shortfall settled from claimable (:597-598). Vault forwards combined value. No value-leak. |
| **FC-390-06** | keeper-bounty creditFlip issuance bounded (no unbounded BURNIE) | SOUND (bounded + sub-gas) | REFUTED (bounded) | **REFUTED** | Per box ACTUALLY settled (empty slots skipped, StakedDegenerusStonk.sol:809-814); each (wallet,day) capped 160-ETH base (:1081) + 50%/day supply cap (:1012); decimator per real claimed entry (DecimatorModule:364-370). BURNIE off the direct ETH/stETH spine; downstream dilution owned by ACCESS-02/393. Issuance bounded by real burns. |
| **FC-390-07** | vault deposit() removal complete; no over-mint | SOUND (no caller) | INFO / REFUTED | **REFUTED** | `grep "vault.deposit\|.deposit(" contracts/` EMPTY (no dead caller). `vaultMintTo` checks live allowance before minting (BurnieCoin.sol:542-549) so burnCoin over-mint reverts. No game→vault stETH-pull path remains. |

### 2c. Inherited cross-refs (FC-389-02, FC-389-08, FC-392-08, FC-393-02, FC-393-03)

| ITEM | What it claims | NET 1 | NET 2 | VERDICT | Settling bound / cite |
|------|----------------|-------|-------|---------|-----------------------|
| **FC-389-02** | uint96/uint128 narrowing casts truncate silently (segregation/pool drift) | SOUND (not reachable) | REFUTED | **REFUTED (solvency half)** | Folds into SOLV-02: `_pendingRedemptionEthValue` real-ETH bounded ≪ uint96; every narrowing on a CHECKED expr (submit :1066, resolve :745, claim :854). Narrowing-equivalence half already REFUTED at 389. |
| **FC-389-08** | StakedStonk uint96/uint128 narrowing (solvency confirm no path > 2^96 wei) | SOUND | REFUTED | **REFUTED (solvency half)** | Same surface as FC-389-02; `_totalSupply` monotone ≪ uint128, `_pendingRedemptionEthValue` capped/wallet/day × 175% ≪ uint96 (StakedDegenerusStonk.sol:213/:1081). |
| **FC-392-08** | redemption ETH-spin pool RMW + recirc vs CEI (solvency half) | SOUND (flush-before-recirc) | REFUTED | **REFUTED (solvency/CEI half)** | resolveRedemptionLootbox pulls stETH remainder in (:932-936) then credits pool by `amount` BEFORE chunk resolution (:945-947); ETH-spin flushes claimable/pool writes BEFORE recirc (DegeneretteModule:1439-1447), recirc disables ETH-spin cascade (`allowEthSpin=false` :1453); chunks sequential in one delegatecall frame (no cross-chunk cap-RMW race). `_pendingRedemptionEthValue` release == leg movement (SOLV-03). ECON EV half owned by 392. |
| **FC-393-02** | forfeit-to-self timing extractable by keeper | SOUND (non-extractive) | INFO / REFUTED | **BY-DESIGN / REFUTED** | Per-claim split deterministic from fixed `roll` (:772) + owed value; keeper choice biases only the TIMING of benign backing accrual (forfeit raises backing for ALL holders uniformly, :842) — no per-victim value extraction. Cross-ref 393. |
| **FC-393-03** | partial-balance redemption-leg solvency under same-block bursts | (under SOLV-04) | REFUTED | **REFUTED (solvency half)** | Each leg recomputes fresh `bal` (:880/:888/:898), sends `min(bal,legAmount)` ETH, GAME pulls remainder as stETH (reverts if short). Σ legs over burst = Σ rolled = Σ released `_pendingRedemptionEthValue`; MAX reservation (ETH+stETH ≥ Σ MAX ≥ Σ rolled) covers; ETH drains shift to stETH leg of same held reservation. No strand/under-pull. ACCESS half → 393. |

---

## 3. Skeptic gate (run before any CATASTROPHE/HIGH)

**Outcome: 0 items reach CATASTROPHE/HIGH. The single HIGH research-stage lead (SOLV-07, gemini) is
REFUTED at frozen source and fails the gate's reachability condition.** Both surface-maps found 0 HIGH on
inspection; both nets converge on no contract defect across all 19 items. The gate is recorded for the
divergent HIGH lead and the MED-attention items.

### 3a. SOLV-07 `whalePassCost` divergence — the load-bearing dual-gate

The council DIVERGED: gemini flagged a HIGH `whalePassCost` double-credit (a research-stage lead, self-
described as not-finalized); codex refuted it as single-counted. NET 2 pinned the exact frozen lines and
traced the wei-level flow.

| Gate dimension | Result |
|---|---|
| **Source pin** | `_processSoloBucketWinner` @ DegenerusGameJackpotModule.sol:1246-1281 (gemini's ~1284 + codex's @1265-1275 both inside); `_handleSoloBucketWinner` :1183-1216; `payDailyJackpot` final-day fold :442-452. |
| **Wei-level accounting** | claimablePool += `ethAmount` (perWinner − whalePassCost) only (:1268-1269); futurePrizePool += `whalePassCost` ONCE (:1274); whalePassClaims records a NON-ETH pass redeemed for TICKETS (WhaleModule:991-1007 — no claimablePool, no ETH). `_handleSoloBucketWinner` adds `wpSpent` into `paidDelta` (:1214-1215) ⟹ `paidDailyEth` INCLUDES whalePassCost ⟹ `unpaidDailyEth = budget − paidDailyEth` (:443) EXCLUDES it (the fold at :448 does NOT re-add it); non-final-day `currentPrizePool -= paidDailyEth` (:451) DOES remove it. **gemini's premise (`paidDailyEth` = ETH-only) is FALSE at `a8b702a7`.** |
| **Structural-protection check** | Even hypothetically, a double-fold would inflate a POOL obligation (futurePrizePool), NOT the `claimablePool == Σ claimable + afking` identity (whale-pass value is OUTSIDE that identity, solvency.md F2/F3). `distributeYieldSurplus` includes futurePrizePool in its obligations sum (:691) → an inflated pool only REDUCES computed yield (conservative), never an underbacked PAYOUT. The "insolvency" framing requires pool obligations to exceed balance AND both be paid unconditionally — futurePrizePool pays only via bounded subsequent cycles. |
| **3-condition EV/reachability lens** | (1) reachable? NO — paidDailyEth includes wpSpent, so the double-credit is not present in code (fails condition 1). (2) profitable? n/a. (3) repeatable? n/a. |
| **Gate result** | **NOT a finding — fails reachability condition (1). SOLV-07 single-counted, REFUTED. NET 2 sides with codex.** Even the hypothetical would be a conservative pool over-reservation, not an underbacked payout — sub-HIGH on the structural check. |

### 3b. MED-attention leads (the surface-map MED prime targets)

| Elevated-attention item | structural-protection check | 3-condition EV lens | gate result |
|---|---|---|---|
| **FC-390-01 / SOLV-05** (liveness ordering) | Three independent structural facts: (i) redemption reserve segregated out of the drain's totalFunds, (ii) EVM tx atomicity (no interleaving), (iii) single isGameOver snapshot + atomic release/slot-delete. | (1) reachable? NO interleaving exists (atomicity); (2) profitable? n/a; (3) repeatable? n/a. | **NOT a finding** — fails (1). REFUTED, not elevated. |
| **FC-390-02 / SOLV-04** (dust-forfeit backing) | The GAME pulls the stETH remainder before crediting and reverts on shortfall (value-in-before-credit, fail-closed); MAX(175%) reservation guarantees coverage. | (1) reachable phantom-bump? NO (credit = exactly value pulled in); (2) profitable? n/a; (3) repeatable? n/a. | **NOT a finding** — fails (1). REFUTED. |
| **FC-390-03** (permissionless claim) | Resolution-into-claimable only (no caller value path); batch caches over/frozen once; claim effects can't flip the boundary. | (1) reachable value extraction? NO (all value to winner); (2) n/a; (3) n/a. | **NOT a finding** — fails (1). REFUTED. |
| **FC-392-08** (ETH-spin recirc CEI) | Flush-before-recirc ordering + recirc disables ETH-spin cascade; chunks sequential in one frame. | (1) reachable race/strand? NO; (2) n/a; (3) n/a. | **NOT a finding** (solvency half). ECON EV half → 392. |
| **FC-393-03** (partial-balance burst) | Each leg recomputes fresh balance + pulls stETH remainder fail-closed; MAX reservation covers Σ legs. | (1) reachable strand/under-pull? NO; (2) n/a; (3) n/a. | **NOT a finding** — fails (1). REFUTED. |

No item is tagged CATASTROPHE/HIGH. The skeptic gate confirms the divergent HIGH lead (SOLV-07) is
single-counted at source and every MED-attention lead is structurally unreachable (fails EV condition 1).

---

## 4. Routing — CONFIRMED findings + carried INFO/MONITOR

### 4a. CONFIRMED contract findings

**0 CONFIRMED contract-source findings.** SOLV-01..07, FC-390-01..07, and the 5 inherited cross-refs are
all REFUTED / BY-DESIGN against `a8b702a7` with BOTH nets on record. The byte-frozen subject is attested
document-only at `a8b702a7`. SOLV-01..07 attested.

### 4b. Carried INFO / MONITOR (no contract change; recorded so a future reader doesn't re-derive)

- **SOLV-07 gemini HIGH lead → REFUTED (recorded):** the `whalePassCost` double-credit lead is single-
  counted at frozen source (`paidDailyEth` includes `wpSpent` at :1214-1215). A future reader should NOT
  re-derive it as a finding. Even hypothetically it is a conservative pool over-reservation outside the
  claimablePool identity, not an underbacked payout.
- **Decimator pre-reservation slack (codex caveat, INFO):** `claimablePool` may pre-reserve an unclaimed
  decimator pool before individual winners are credited (DegenerusGameStorage.sol:356-366 documented
  exception) — an OVER-reservation of backing, conservative-only, NOT an underbacked path. Distinct from
  the SOLV-07 daily-jackpot fold (different pool/timing); no interaction. No change.
- **FC-389-02/-08 (INFO):** narrowing-conservation confirmed at the spine — every cast on a checked
  expr with a real-ETH/supply bound far under the type width. No change.
- **EthSolvency redemption-leg test-hardening note (ROUTED to a later test phase, NOT a contract
  change):** `EthSolvency.inv.t.sol` EXERCISES the game-side claimablePool identity but its action set
  does NOT include the redemption credit legs (creditRedemptionDirect / resolveRedemptionLootbox / dust-
  forfeit). The redemption coverage lives in the targeted `RedemptionStethFallback.t.sol` (10/10) +
  `RedemptionAccounting.t.sol` (388-02 #5). A later test phase COULD add a redemption action to the
  EthSolvency invariant handler so the always-on net covers the redemption credit legs too — an oracle-
  completeness item, NOT a contract defect (every redemption leg's solvency is proven above by trace +
  the EXERCISED targeted tests). The superseded legacy `RedemptionInvariants` 7-INV green was NOT relied
  on for any verdict here.
- **Cross-phase owned halves (recorded, not adjudicated here):** FC-390-06 downstream BURNIE dilution →
  ACCESS-02/393; FC-392-08 ECON EV half → 392; FC-393-02/-03 access halves → 393.

Any test-only (oracle-integrity) gap is ROUTED, not a contract finding.

---

## 5. Re-attestation line (each req attested-or-finding)

| Req | Status at `a8b702a7` |
|-----|----------------------|
| SOLV-01 | ATTESTED (claimablePool == Σ claimable + afking; every changed touch pairs a pool move) |
| SOLV-02 | ATTESTED (sDGNRS backing identity; balance + stETH ≥ obligations; widths bounded) |
| SOLV-03 | ATTESTED (ethDirect + lootboxEth + forfeitEth == released in every branch; no double-count/leak) |
| SOLV-04 | ATTESTED (dust-forfeit self-credit fully backed by value leaving sDGNRS; fail-closed) |
| SOLV-05 | ATTESTED (claim-side liveness ordering safe-by-construction; reserve segregated out of drain) |
| SOLV-06 | ATTESTED (CEI on all 4 payout legs; stETH-before-ETH; V62-03 class closed) |
| SOLV-07 | ATTESTED (delta-fold complete; whalePassCost single-counted; gemini HIGH lead REFUTED at source) |

**Verdict:** the phase-390 solvency-spine surface is adjudicated with BOTH nets on record, the skeptic
gate applied (0 HIGH — the single divergent HIGH lead REFUTED at source), and every req + owned lead +
inherited cross-ref carrying an explicit verdict backed by a bound or source-cite. The three prime
targets are settled by dedicated treatment: SOLV-05/FC-390-01 multi-tx ordering bound, SOLV-04/FC-390-02
dust-forfeit backing proof under the MAX reservation, SOLV-06 CEI-ordering trace over the 4 changed
payout legs (RedemptionStethFallback anchor). **0 CONFIRMED contract findings.** The byte-frozen subject
is attested document-only at `a8b702a7` throughout (`git diff a8b702a7 -- contracts/` EMPTY).
