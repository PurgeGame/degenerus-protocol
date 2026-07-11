# Degenerus Protocol — audit details

- Total Prize Pool: `$TBD` <!-- fill at contest setup: HM / QA / Judge / Validator / Scout / Mitigation split -->
- Read our [guidelines](https://docs.code4rena.com) for more details
- Starts `TBD`
- Ends `TBD`

**Frozen subject:** `contracts/` tree `d6abb363` @ tag `degenerus-c4a`.
Checkout: `git checkout degenerus-c4a`. Everything a warden audits is that tree; nothing else in the
repo history is in scope.

**Note re: risk level upgrades/downgrades**

Two important notes about judging-phase risk adjustments:
- High- or Medium-risk submissions downgraded to Low-risk (QA) will be ineligible for awards.
- Upgrading a Low-risk finding from a QA report to a Medium- or High-risk finding is not supported.

As such, wardens are encouraged to select the appropriate risk level carefully during submission.

---

## Automated Findings / Publicly Known Issues

Automated tool output (Slither 0.11.5 + Aderyn 0.6.8) for the frozen subject is committed in
[`audit/automated/`](./automated/), and the pre-triaged categories are catalogued in
[`KNOWN-ISSUES.md`](../KNOWN-ISSUES.md) §5.

The full pre-disclosure perimeter — design decisions/assumptions, accepted issues and scope
boundaries, the >120-day deadman fallback, out-of-scope and immaterial items, automated-tool findings,
and ERC-20 deviations — is in [`KNOWN-ISSUES.md`](../KNOWN-ISSUES.md). It is a *precise* perimeter:
every entry names the exact mechanism and impact.

_Anything in this section (including everything in `KNOWN-ISSUES.md`) is a publicly known issue and is
ineligible for awards._

---

## Overview

Degenerus is an on-chain ETH game of repeating levels, prize pools, and stacked jackpot systems.
Players buy tickets (price escalates per level); each purchase splits ETH across the current/next/
future prize pools, the claimable pool, and a stETH-yield vault. Chainlink VRF V2.5 is the sole
randomness source and drives level advancement, jackpots, lootboxes, Degenerette spins, foil packs,
and the terminal release. The game runs until a terminal condition (a multi-month liveness stall or a
pool deficit) triggers game-over, after which the remaining pools distribute to participants.

stETH staking yield makes the system positive-sum, which is why several sub-games are calibrated above
100% RTP by design (see Known Issues). Solvency is never funded by yield, though: the invariant
`game ETH+stETH balance >= obligations` holds independent of rebases.

**No upgradeability. No proxies. No configurable privileged addresses.** Every cross-contract
authority is a compile-time constant in `ContractAddresses.sol`, fixed by nonce prediction at deploy.

## Links

- **Previous audits:** none — no prior third-party audit.
- **Documentation:** `audit/C4A-CONTEST-README.md` (this file), `SECURITY.md`, `audit/ACCESS-CONTROL-MATRIX.md`, `audit/ETH-FLOW-MAP.md`, `docs/JACKPOT-PAYOUT-REFERENCE.md`
- **Website:** `TBD`
- **X/Twitter:** `TBD`

---

## Scope

Authoritative file lists: **`scope.txt`** (in-scope) and **`out_of_scope.txt`** (excluded), both in
the repository root. The in-scope set = the 26 contracts `scripts/deploy.js` deploys (DegenerusVault
additionally deploys two inner DGVE/DGVF share-class ERC-20s) + their linked module bases, shared
storage, libraries, and interfaces + one standalone in-scope production contract
(`DeityBoonViewer`, read-only). (`DegenerusGasFaucet` was relocated to the `degenerus-utilities` repo.)

| Group | Files | nSLOC |
|-------|------:|------:|
| Core deployed contracts | 14 | 7,435 |
| Deployed delegatecall game modules | 12 | 9,709 |
| Linked abstract module bases | 2 | 461 |
| Shared storage | 1 | 1,125 |
| Libraries (incl. ContractAddresses) | 8 | 561 |
| Interfaces | 11 | 667 |
| Standalone in-scope (boon viewer, read-only) | 1 | 154 |
| **Total** | **49** | **20,112** |

nSLOC = non-blank, non-comment source lines (comment-and-string-aware count). Per-file breakdown is in
`scope.txt`.

---

## Scoping Q & A

### General questions

| Question | Answer |
|----------|--------|
| ERC20 used by the protocol | External: **stETH** (Lido, rebasing), **LINK**, **wXRP**. Native: **FLIP**, **DGNRS**, vault shares **DGVE/DGVF**. (`sDGNRS`, `GNRUS` are soulbound — not ERC-20.) |
| ERC721 used by the protocol | **DegenerusDeityPass** (deity passes, triangular pricing). |
| ERC777 used by the protocol | None. |
| ERC1155 used by the protocol | None. |
| Chains the protocol will be deployed on | **Ethereum mainnet** only. |
| Test coverage | 993 Foundry tests (153 `.t.sol`; incl. 18 invariant suites + 6 halmos symbolic) and ~1,545 Hardhat specs (89 `.test.js`), green at the frozen subject (107 Foundry / 22 Hardhat documented skips). A line/branch % is **not** reported: `forge coverage` is infeasible on this codebase — its instrumentation disables/minimizes `viaIR`, and the largest modules then hit solc "stack too deep" (both plain and `--ir-minimum`). Assurance rests on suite breadth + the Main-Invariants properties below, not a percentage. |

### ERC20 token behaviors in scope

The protocol touches only known tokens (stETH, LINK, wXRP, and its own FLIP/DGNRS). What materially matters:

| Behavior | In scope? | Note |
|----------|-----------|------|
| Balance changes outside of transfers (rebasing) | **Yes** | stETH rebases (±); prize growth depends on it, solvency does not. Negative rebases absorbed by an 8% buffer. |
| Missing return values / doesn't revert on failure | Yes | `.transfer`/`.transferFrom` return-checked; only bool-returning known tokens touched. |
| Fee on transfer | No | None of the touched tokens charge fees. |
| Low (<6) / high (>18) decimals | No | All touched tokens are 18-decimal. |
| Upgradeability / Pausability / Blocklists / Flash-mint / Approval-race | No | Not applicable to the touched token set. |

### External integrations in scope

| Integration | In scope | Note |
|-------------|----------|------|
| Lido stETH | Yes | Rebase (incl. negative) and yield-to-zero handled; solvency invariant independent of yield. |
| Chainlink VRF V2.5 | Yes | Sole randomness source. Coordinator swap is sDGNRS-governance-gated behind a death-clock. |
| Chainlink LINK/ETH price feed | Yes | Values LINK donations only; a stale/down feed suspends FLIP donation credit (the donation still processes). |

### EIP compliance

| Contract | EIP | Note |
|----------|-----|------|
| FLIP, DGNRS, DGVE, DGVF | ERC-20 | Intentional documented deviations (`KNOWN-ISSUES.md` §6). |
| DegenerusDeityPass | ERC-721 | — |
| sDGNRS, GNRUS | (none) | Soulbound / non-transferable by design; ERC-20-compliance findings invalid. |

---

## Areas of concern (where to focus for bugs)

We have audited this heavily. In priority order, these three are where we believe the real risk lives
and where we most want warden attention:

1. **RNG integrity (DOMINANT).** VRF is the sole randomness source. Every input to an RNG-dependent
   calculation must be committed before the VRF request. Any path where a player alters state between
   request and fulfillment to influence their outcome, or where a proposer/validator biases a *live*
   result, is a high finding. (The > 120-day dead-coordinator terminal fallback is the documented
   exception — see Known Issues.)

2. **Gas-ceiling safety (HIGH).** `advanceGame` and its same-tx composition must complete within the
   block gas limit under any achievable on-chain state, not just typical load. Target worst-case
   < 10M; provably never > 16.7M (= game-over). Any path an attacker forces past the ceiling is high.

3. **Money correctness (SPINE).** ETH and token accounting must be exact. Wei-scale rounding is not a
   finding — all rounding favors solvency by design. Any unauthorized extraction — by a player,
   external attacker, or compromised admin — is high. **Assume a hostile admin key:** a compromised
   admin must not extract funds or manipulate RNG as long as the sDGNRS community is engaged. Admin
   power is bounded by an sDGNRS-governance death-clock (44h VRF-stall gate, decaying vote threshold,
   kill-on-recovery); governance-malice scenarios are pre-documented in `KNOWN-ISSUES.md`.

These three are our priority, not the boundary of the contest. All in-scope findings are judged on
standard C4 severity regardless of area — but a report that breaks one of the three above is the one
we're most eager to receive.

---

# Main Invariants

> The properties below are what the protocol guarantees; each is backed by the referenced test or source site. Numeraire: ETH wei (stETH valued 1:1 with ETH). Subject: the frozen `contracts/` tree `d6abb363` @ tag `degenerus-c4a`. `DEG-*` entries are statistical (realized EV/RTP/ROI over the resolved-spin stream); the rest are exact.

## Solvency & backing

| ID | Severity | Invariant | Source |
|----|----------|-----------|--------|
| `SOLV-01-ETH-SOLVENCY` | critical | The game contract's live ETH balance always covers its canonical ETH-obligation set. LIVE (not gameOver): obligations = currentPrizePool + nextPrizePool + futurePrizePool + claimablePool + yieldAccumulator + (freeze-window pending buffer: pendingNext + pendingFuture). POST-game-over: the live pools are dead/zeroed and the only withdrawable obligation is claimablePool, so obligations collapses to claimablePool alone. | `test/fuzz/invariant/EthSolvency.inv.t.sol:36-47; test/fuzz/helpers/SolvencyObligations.sol:52-68` |
| `SOLV-02-FULL-BACKING-ETH-STETH` | critical | The summed four-pool obligation (current+next+future+claimable) is always fully backed by the ETH+stETH the game holds — no pool transfer (future->next->current consolidation, the time-based future skim, or a jackpot settlement crediting claimable) can inflate the total above real liquid backing. | `test/fuzz/invariant/PoolConservation.inv.t.sol:91-102` |
| `SOLV-03-NO-UNBACKED-CREDIT` | critical | Conservation: the summed four-pool obligation can never exceed the real ETH that entered the contract (starting backing captured at session start + cumulative real ETH inflow from buys). An internal transfer only reshapes the split across the four pools; it adds nothing to real inflow, so it can never mint unbacked credit. (Off-chain client tracks startingBacking once at connect and accumulates msg.value of its own successful buys as the realInflow lower bound; SOLV-02 is the always-evaluable on-chain-only form of the same property.) | `test/fuzz/invariant/PoolConservation.inv.t.sol:115-125` |
| `SOLV-04-CLAIMABLE-EQUALS-HALVES` | critical | Master SOLVENCY identity: claimablePool >= the sum over all addresses of (claimable low-half + afking high-half) of their packed balance slot; equality holds outside decimator settlement, which transiently over-reserves the pool (claimablePool strictly greater) until per-winner claims credit. The afking reservation rides INSIDE claimablePool; every afking/claimable mutation pairs a claimablePool move, so a dropped paired += or a double-counted half breaks the equality. | `test/fuzz/invariant/V61SolvencyAfpay.inv.t.sol:84-96` |
| `SOLV-05-CLAIMABLE-BACKED` | critical | claimablePool never exceeds the game's liquid backing (ETH + stETH) — the claim liability is always covered after any afking-funded buy, packed credit/debit, stale cashout, or smite. | `test/fuzz/invariant/V61SolvencyAfpay.inv.t.sol:103-110` |
| `SOLV-06-FOLD-CONSERVATION` | critical | Purchase/mint fold conservation: the single combined claimablePool -= totalClaimableDraw exactly equals the per-tier sum of every per-player claimable + afking debit across all payKind branches (DirectEth / Claimable / Combined), with or without a lootbox leg — no branch drops a paired debit or double-counts a half. The fold sums ticketClaimableDraw (from _recordMintPayment) + lootboxPoolDraw (from _settleShortfallNoPool) into one decrement; sequential _claimableOf re-reads after the lootbox debit prevent double-draw, and claimablePool >= buyer balance prevents underflow. | `test/fuzz/invariant/V61SolvencyAfpay.inv.t.sol:84-96` |
| `SOLV-07-SDGNRS-BOX-ROUTING` | critical | sDGNRS level-start bonus box conservation: the claimablePool debit equals the box prize-pool credit (claimable down `box` == pool up `box`, box = min(cl/20, 6 ether) floored at mp), and the 1-wei sentinel (box <= cl-1) is preserved for every claimable cl given the cl>mp guard + mp floor (cl/20 <= cl-1 for cl>=2; mp <= cl-1 under cl>mp; 6 ether cap when cl>120 ether). The once-per-level latch (currentLevel > _sdgnrsBonusLevel) plus the pinned-sub loop-skip guarantee exactly one box per level — no double debit across stage chunks/txs. | `contracts/modules/GameAfkingModule.sol:1170-1198` |
| `SOLV-08-AFFILIATE-WINNERCREDIT-FLIP-ONLY` | critical | payAffiliateCombined credit conservation: the returned winnerCredit is FLIP coin only (never ETH-backed) and is conserved at the single batched MintModule creditFlipBatch([buyer, affWinner]) call site — collision-safe when winner==buyer (referrer branch returns winnerCredit 0) and accumulating (_addDailyFlip sums duplicate addresses, never overwrites). The affiliate path touches only leaderboard SCORE and FLIP; it never moves ETH or claimablePool, so no unbacked ETH credit can be minted. | `test/fuzz/invariant/CoinSupply.inv.t.sol:36-46` |

## Redemption desk

| ID | Severity | Invariant | Source |
|----|----------|-----------|--------|
| `REDEEM-01-ETH-SEGREGATION` | critical | Segregated redemption ETH on sDGNRS never exceeds what the sDGNRS contract can cover in ETH+stETH — redemption obligations stay solvent and segregated from game pools. | `test/fuzz/invariant/RedemptionInvariants.inv.t.sol:42-51` |
| `REDEEM-02-NO-DOUBLE-CLAIM` | critical | A redemption claim is deleted before payout; a second claim for the same (beneficiary, period) reverts. No double-claim ever succeeds. | `test/fuzz/invariant/RedemptionInvariants.inv.t.sol:60-66` |
| `REDEEM-03-PERIOD-MONOTONIC` | critical | The redemption period index is monotonically non-decreasing across observations (it is day-keyed: currentPeriod = GameTimeLib.currentDayIndex()), so it never regresses. | `test/fuzz/invariant/RedemptionInvariants.inv.t.sol:75-81` |
| `REDEEM-04-SUPPLY-CONSISTENCY` | critical | sDGNRS never mints post-deploy: totalSupply is fixed at initialSupply at construction and only ever decreases via burns (monotonically non-increasing) — no unbacked share mint, no lost burn. | `test/fuzz/invariant/RedemptionInvariants.inv.t.sol:90-97` |
| `REDEEM-05-FIFTY-PCT-CAP` | critical | Within a redemption period, cumulative burned never exceeds half the period's supply snapshot (50% cap enforced). | `test/fuzz/invariant/RedemptionInvariants.inv.t.sol:105-115` |
| `REDEEM-06-ROLL-BOUNDS` | critical | Every resolved redemption period's roll lies in [25, 175]. | `test/fuzz/invariant/RedemptionInvariants.inv.t.sol:124-130` |
| `REDEEM-07-LOOTBOX-SPLIT-CONSERVE` | critical | For every redemption claim, ethDirect + lootboxEth == totalRolledEth (the rolled ETH is conserved across the direct/lootbox split). | `test/fuzz/invariant/RedemptionInvariants.inv.t.sol:198-204` |

## Token supply

| ID | Severity | Invariant | Source |
|----|----------|-----------|--------|
| `COIN-01-FLIP-SUPPLY` | critical | FLIP accounting identity: totalSupply + vaultMintAllowance == supplyIncUncirculated at all times (no token minted outside the tracked supply struct). | `test/fuzz/invariant/CoinSupply.inv.t.sol:36-46` |
| `VAULT-01-ALLOWANCE-BOUNDED` | critical | The vault's FLIP mint allowance never exceeds supplyIncUncirculated (the allowance is a subset of the uncirculated total; it cannot mint beyond the bookkept ceiling). | `test/fuzz/invariant/VaultShare.inv.t.sol:42-67` |
| `VAULT-02-SUPPLY-AFTER-VAULT-OPS` | critical | The FLIP supply identity (COIN-01) still holds after vault burn/escrow operations (burnCoin/burnEth/vaultEscrow do not corrupt totalSupply + vaultMintAllowance == supplyIncUncirculated). | `test/fuzz/invariant/VaultShareMath.inv.t.sol:61-71` |

## Liveness / no-brick (FSM)

| ID | Severity | Invariant | Source |
|----|----------|-----------|--------|
| `FSM-01-LEVEL-MONOTONIC` | high | The game level is monotonically non-decreasing — it only ever increases (advanceGame increments; no path decrements). | `test/fuzz/invariant/GameFSM.inv.t.sol:23-29; test/fuzz/invariant/Composition.inv.t.sol:55-61; test/fuzz/invariant/MultiLevel.inv.t.sol:46-61` |
| `FSM-02-GAMEOVER-TERMINAL` | high | gameOver is a one-way latch: once it reads true it never reverts to false (terminality of the end state). | `test/fuzz/invariant/GameFSM.inv.t.sol:33-39; test/fuzz/invariant/Composition.inv.t.sol:65-71` |
| `FSM-03-NO-BRICK-LIVENESS` | high | Liveness / no-brick: while the game is live (not gameOver) the core external surface (purchase, advanceGame, placeDegeneretteBet/resolve, claimWinnings) must not revert for a well-formed call due to an internal state corruption — every reachable action either succeeds or reverts only on a documented guard, never on a permanent dead-state. Every Degenerette resolve in particular must succeed (no revert/brick) for any ticket/hero/seed. | `test/fuzz/invariant/GameFSM.inv.t.sol:46-60; test/fuzz/DegeneretteV73SolvencyFuzz.t.sol:18-19,91` |

## Ticket & box accounting

| ID | Severity | Invariant | Source |
|----|----------|-----------|--------|
| `BOX-01-EVERY-PERSISTED-BOX-ENQUEUED` | medium | Every persisted (not-yet-opened) lootbox/presale box record (base != 0) for an active index is present in the permissionless openBoxes() auto-open queue (boxPlayers[index]) until opened — a box owner cannot hold a persisted box un-enqueued and time its open to a favorable level/boon (the WHALE-01 property). | `test/fuzz/invariant/BoxEnqueue.inv.t.sol:112-141` |
| `TICKET-01-OWED-CONSISTENT` | medium | Ticket-owed tracking is consistent: an address that never purchased has zero ticketsOwed at every level, and no player carries corrupted/negative owed state. | `test/fuzz/invariant/TicketQueue.inv.t.sol:31-58` |

## RNG-freeze & VRF lifecycle

| ID | Severity | Invariant | Source |
|----|----------|-----------|--------|
| `RNG-01-INWINDOW-SLOADS-FROZEN` | medium | While the VRF window is open (rngLocked()==true), no player-controllable action mutates, in isolation, any storage slot the pending RNG consumption reads — the enumerated in-window read set is frozen: (1) rngWordByDay[currentDay], (2) lootboxRngWordByIndex[index], (3) the lootboxRngPacked cursor (low 48 bits), (4) dailyIdx. advanceGame (the exempt heartbeat) is never measured against the property. | `test/fuzz/invariant/RngWindowFreeze.inv.t.sol:73-79` |
| `RNG-02-DRAIN-BEFORE-SWAP` | medium | Ordering: _swapAndFreeze cannot advance the lootbox read index while any read-slot ticket remains undrained — captured entropy always equals the populated lootboxRngWordByIndex[X] and is never zero (no drain runs against an unpopulated slot). | `test/fuzz/invariant/RngIndexDrainOrdering.inv.t.sol:32-52` |
| `RNG-03-QUEUE-WINDOW-NO-TERMINAL-JACKPOT` | high | The terminal payout uses one phase-correct, entropy-committed ticket snapshot: next-level during ordinary purchase phase, current-level during jackpot phase, and the already-promoted current level during a locked final-purchase transition. If no entropy boundary exists, the terminal path freezes the selected write cohort before requesting entropy. Once any boundary exists, it drains only the selected read snapshot and never promotes the later write buffer. The mint entry rejects purchases once `_livenessTriggered` is active, and an expired VRF-grace timer remains latched after fallback entropy commits until the separate terminal-drain transaction completes. | `contracts/storage/DegenerusGameStorage.sol:_gameOverTicketLevel; contracts/modules/DegenerusGameAdvanceModule.sol:_handleGameOverPath; test/repro/TerminalJackpotCohortIsolation.t.sol` |
| `VRF-01-INDEX-LIFECYCLE` | medium | lootboxRngIndex never skips a value and never double-increments on a single request, and every unlocked index has a nonzero VRF-derived word (no orphaned index). | `test/fuzz/invariant/VRFPathInvariants.inv.t.sol:28-52` |
| `VRF-02-SWAP-PRESERVES-LOCK` | medium | A VRF coordinator swap never flips rngLocked in either direction: a daily request in flight keeps the lock until the re-issued word lands; an idle/mid-day-only state stays unlocked. Gap days are backfilled with nonzero rngWordForDay after recovery. | `test/fuzz/invariant/VRFPathInvariants.inv.t.sol:60-90` |
| `VRF-03-DEADMAN-MONOTONIC-LATCH` | high | _vrfDeadmanFired (_simulatedDayIndex() - dailyIdx > 120) is a pure monotonic latch: it cannot false-fire on a healthy game (dailyIdx advances on every sealed day, so a 120-sealed-day gap only opens when VRF is genuinely dead/abandoned), there is no uint24 underflow (dailyIdx <= current day always), it stays latched true through the multi-tx game-over drain until the terminal _unlockRng, and a fired deadman commits only a non-steerable historical fallback word (sealed rngWordByDay + block.prevrandao, with the reverseFlip nudge cancelled-and-consumed via totalFlipReversals) — never a player-steerable word. | `contracts/storage/DegenerusGameStorage.sol:1502-1504; test/fuzz/invariant/GameFSM.inv.t.sol:33-39` |

## Access control & gift sourcing

| ID | Severity | Invariant | Source |
|----|----------|-----------|--------|
| `ACCESS-01-GIFT-FUNDER-SOURCING` | high | A caller-funded gift never burns a non-consenting party's FLIP: on the gift branch the spend sources from msg.sender (funder = msg.sender), while the self/operator-approved branch funds from the player (the FLIP owner). The gift funder forfeits the entire stake (winnings go to the player), so a funder cannot farm a quest streak and cannot grief a player (the player only ever receives value). WWXRP is gift-excluded, and directDeposit=false on operator/gift deposits suppresses biggestFlip / bounty / coinflip-boon consume. | `contracts/Coinflip.sol:258-268` |

## Degenerette economics

| ID | Severity | Invariant | Source |
|----|----------|-----------|--------|
| `DEG-01-PER-N-EV-CEILING` | high | For every (N goldQuadrants, heroIsGold) sub-case, the honest Degenerette base payout EV over that sub-case's own Variant-2 score distribution is never EV-positive: EV <= 100 centi-x (and ~neutral, >= 99.95). No (N, heroIsGold) configuration yields a positive-expectation honest bet. | `test/stat/DegenerettePerNEvExactness.test.js:382-401; test/fuzz/DegeneretteV73SolvencyFuzz.t.sol:100-106` |
| `DEG-02-PS9-RTP-ROI-PINS` | high | The held-fixed economic pins are unchanged by the Variant-2 diff: the activity ROI curve is 90%->99.9% (ROI_MIN 9000 -> 9990 bps), the WWXRP RTP curve is 70%->115%->118%->120% with a 70% floor, and the per-N S=9 jackpot payout pins are exactly [10756411, 12583037, 14792939, 17512324, 20916435]. P(S=9) is placement-independent and equals the all-8-axes match event. Together these fix the realized WWXRP RTP at the jackpot tier. | `test/stat/DegeneretteV73Invariants.test.js:108-167; test/fuzz/DegeneretteV73SolvencyFuzz.t.sol:46-48` |
| `DEG-03-WWXRP-RIG-NEVER-S9` | high | The WWXRP rig only ever LIFTS the score (rigged S in [honestS, honestS+2]) and can NEVER fabricate the S=9 jackpot: a rigged S==9 requires the honest pre-rig reel to already be a full 8-axis match (M==8). The rig forces at most one score-bearing cell when M<=6 (a +1 cell or a +2 color-unlock cell), is a no-op when M>=7, and so a fired roll stays S<=8 — leaving P(S=9) exactly invariant vs the honest reel. | `test/fuzz/DegeneretteV73SolvencyFuzz.t.sol:107-118; test/stat/DegenerettePerNEvExactness.test.js:450-459` |

## Curse neutrality

| ID | Severity | Invariant | Source |
|----|----------|-----------|--------|
| `CURSE-01-CURSE-NONNEGATIVE-NEUTRAL` | medium | The per-player curse counter is well-formed (a uint8 stack count) and curse-only operations (smite / decurse / stale-cashout curse-set) are pool-neutral — they move claimablePool by exactly zero and leave the SOLV-04 half-sum identity byte-unchanged. | `test/fuzz/invariant/V61SolvencyAfpay.inv.t.sol:240-267` |

---

## Trusted roles / trust model

Full enumeration with powers and bounds is in **`SECURITY.md`**. Summary:

| Role | Who | Power | Bound |
|------|-----|-------|-------|
| sDGNRS majority governance | voting-sDGNRS holders via `DegenerusAdmin` | swap VRF coordinator / price feed | 44h VRF death-clock; 50%→5% decaying vote; auto-killed on VRF recovery (`lastVrfProcessed > createdAt`, 475 fix); payable `receive()` never reverts |
| Vault owner | holder of >50.1% DGVE supply | vault ETH↔stETH, feed, lootbox-RNG threshold, vault's own `game*`/`coin*` proxy actions | acts only on the vault's own custodied position; cannot reach player balances or claimablePool |
| VRF coordinator | Chainlink (+ any governance-installed coordinator) | deliver VRF words | request-id + `rngWordCurrent==0` drop stale fulfillments; > 120d death → non-steerable historical fallback |

**Permissionless-settlement boundary (locked ruling):** a permissionless action is allowed iff value
can only settle *to* the rightful owner **and** any spend is sourced only from a consenting party
(`msg.sender` / owner / operator-approved). Harvest-inward settlement and caller-funded gifts (spend =
funder) are ungated; cashout and spending a non-consenting balance are gated. A finding here must show
a permissionless path that settles to a non-owner or spends from a non-consenting party. Detail in
`SECURITY.md`.

---

## Out of scope

| Category | Reason |
|----------|--------|
| Gas-optimization suggestions | Optimized over multiple dedicated phases; worst-case ceiling proven < 16.7M. |
| Code style / naming / formatting | Intentional, consistently applied across ~20k nSLOC. |
| NatSpec / comment wording | Descriptive only; not a source of eligible findings. |
| Known automated-tool findings | Slither v0.11.5 + Aderyn 0.6.8 pre-triaged in `KNOWN-ISSUES.md` §5. |
| Deployment scripts / off-chain infra | Nonce-predicted addresses baked at compile time; wrong addresses = nothing works (self-auditing). |
| Frontend / indexer / website / papers | Not deployed on-chain in this repo. |
| ERC-20 deviations in FLIP / DGNRS | Intentional; documented in `KNOWN-ISSUES.md` §6. |
| "ERC-20 compliance" vs sDGNRS / GNRUS | Soulbound, not ERC-20 — invalid. |

---

## Known issues

See **`KNOWN-ISSUES.md`** (repo root). It is a precise perimeter — design decisions/assumptions;
accepted issues and scope boundaries (presale over-credit, genesis admin self-break); the >120-day
VRF-death deadman fallback; out-of-scope and immaterial items (VRF rotation-timer governance-malice,
affiliate floor-of-sum rounding); automated-tool findings; and ERC-20 deviations. **If a finding's
mechanism + impact appears there, it is not eligible.**

---

## Running tests

```bash
git clone <repo> && cd degenerus-audit
npm install
git checkout degenerus-c4a          # the frozen subject (contracts/ tree d6abb363)

# Foundry (REQUIRED preprocessing — bare `forge test` panics in setUp without it):
make test-foundry                   # runs the 5 source gates + patchForFoundry + forge test

# Hardhat:
make test-hardhat

# Both + all source gates:
make test
```

`forge coverage` is not runnable here (see the Test-coverage Q&A above — `viaIR` "stack too deep").
The five source gates (`check-rng-window`, `check-pool-writes`, `check-delegatecall`,
`check-interfaces`, `check-raw-selectors`) are machine-checkable invariants over the source and run as
prerequisites of `make test`.

---

## Miscellaneous

Employees of Degenerus and their family members are ineligible to participate in this audit.

Code4rena's rules cannot be overridden by the contents of this README. In case of doubt, check with
C4 staff.

---

## Architecture

`DegenerusGame` is a router that dispatches to **12 delegatecall modules**, all sharing
`DegenerusGameStorage` and executing in the router's context. Chainlink VRF V2.5 for randomness; Lido
stETH for yield. All addresses are immutable compile-time constants. No proxy patterns, no
upgradeability.

### Core deployed contracts (14)

| Contract | Description |
|----------|-------------|
| DegenerusGame | Router / delegatecall dispatcher |
| DegenerusAdmin | VRF + price-feed governance (sDGNRS vote, death-clock gated), payable `receive()` |
| DegenerusAffiliate | Affiliate codes, referral tracking, bonus points, combined affiliate roll |
| FLIP | ERC-20 (coinflip auto-claim + vault virtual-reserve burn) |
| Coinflip | Coinflip resolution, bounty, caller-funded gift deposits |
| sDGNRS | Soulbound; holds reserves/pools, redemption desk, gambling burn |
| DGNRS | Transferable ERC-20 wrapper over sDGNRS |
| DegenerusVault | stETH yield vault; deploys DGVE/DGVF share-class ERC-20s |
| DegenerusJackpots | Jackpot state + BAF helper logic |
| DegenerusQuests | Quest streaks + activity score |
| DegenerusDeityPass | ERC-721 deity passes, triangular pricing |
| Icons32Data | On-chain SVG icon data |
| GNRUS | Soulbound charity token, sDGNRS-governed level donations |
| WWXRP | wXRP utility token (value = whale-pass position) |

### Delegatecall game modules (12)

AdvanceModule (advance / VRF / gap-backfill / >120d deadman), MintModule (purchase, ETH split,
combined affiliate roll), WhaleModule (whale/lazy/deity passes), JackpotModule (daily jackpots + BAF),
DecimatorModule, GameOverModule (terminal drain + refunds), LootboxModule, BoonModule,
DegeneretteModule, BingoModule, GameAfkingModule (afking + sDGNRS level-start box), FoilPackModule.
Two abstract bases (MintStreakUtils, PayoutUtils) are inherited, not separately deployed.

### Libraries (8)

ContractAddresses (nonce-predicted constants), DegenerusGameStorage* (shared layout — listed under
storage), DegenerusTraitUtils, ActivityCurveLib, BitPackingLib, EntropyLib, GameTimeLib,
JackpotBucketLib, PriceLookupLib.

---

## Additional context

- **Compiler:** Solidity 0.8.34, `viaIR = true`, optimizer `runs = 1000`, `evmVersion = osaka`.
- **Build/test:** Hardhat + Foundry. Full suite green at the frozen subject — 993 Foundry (0 failed,
  107 skipped) + ~1,545 Hardhat (0 failed, 22 pending); see the Test-coverage Q&A.
- **Companion docs:** `audit/ACCESS-CONTROL-MATRIX.md` (every external state-changing function + guard)
  and `audit/ETH-FLOW-MAP.md` (every ETH entry/exit + conservation proof), both refreshed for this
  subject's permissionless/gift and sDGNRS level-lootbox surfaces.
