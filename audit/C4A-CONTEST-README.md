# Degenerus Protocol — C4A Contest README

Frozen subject: `contracts/` tree `19272c1f` @ tag `degenerus-c4a` (post-v75.0 hardening freeze).
Checkout: `git checkout degenerus-c4a`.

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

---

## Scope

Authoritative file lists: **`scope.txt`** (in-scope) and **`out_of_scope.txt`** (excluded), both in
the repository root. The in-scope set = the 26 contracts `scripts/deploy.js` deploys (DegenerusVault
additionally deploys two inner DGVE/DGVF share-class ERC-20s) + their linked module bases, shared
storage, libraries, and interfaces + one standalone in-scope production contract
(`DeityBoonViewer`, read-only). (`DegenerusGasFaucet` was relocated to the `degenerus-utilities` repo.)

| Group | Files | nSLOC |
|-------|------:|------:|
| Core deployed contracts | 14 | 7,385 |
| Deployed delegatecall game modules | 12 | 9,659 |
| Linked abstract module bases | 2 | 456 |
| Shared storage | 1 | 1,114 |
| Libraries (incl. ContractAddresses) | 8 | 561 |
| Interfaces | 11 | 667 |
| Standalone in-scope (boon viewer, read-only) | 1 | 154 |
| **Total** | **49** | **19,996** |

nSLOC = non-blank, non-comment source lines (comment-and-string-aware count). Per-file breakdown is in
`scope.txt`.

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

# Main Invariants (MAN-01)

> Canonical runtime oracle shared verbatim by the adversarial agent (`agent/src/oracle.js`, which asserts a subset at runtime) and this section of the C4A README. Subject (re-pinned Phase 474): v74 frozen `contracts/` tree `f06b1ef6` @ impl `93d17288`; closure `MILESTONE_V74_AT_HEAD_93d17288ba6719e0a77723d6167c0ba4796b8467` (the concrete terminal sha is emitted Phase 478). Verdict: 0 open findings — 8-cluster as-built audit clean; cross-model (Codex, Phase 475) found 1 MEDIUM (recovery-spanning VRF-swap proposal), fixed at 93d17288. Numeraire: ETH wei (18 decimals); stETH valued 1:1 with ETH (protocol sums at parity).

> Generated from `agent/manifest/invariants.json` (34 invariants: 28 re-validated against the frozen subject + 6 new-surface MAN-02 additions). Each non-DEG getter entry is evaluable purely from public chain state (a getter plus, for SOLV-01, one mandated `eth_getStorageAt` slot-11 read; SOLV-04 a slot-7 read; REDEEM-05 a per-day `pendingByDay` slot-7 mapping read); DEG entries are statistical over the `FullTicketResult` stream. The six MAN-02 additions (SOLV-06/07/08, VRF-03, ACCESS-01, RNG-03) are manifest/doc-only until the Phase 476 soak re-attest decides whether to wire them into the runtime asserter.


## Solvency & backing

| ID | Severity | Invariant | On-chain check | Comparator | Source |
|----|----------|-----------|----------------|------------|--------|
| `SOLV-01-ETH-SOLVENCY` | critical | The game contract's live ETH balance always covers its canonical ETH-obligation set. LIVE (not gameOver): obligations = currentPrizePool + nextPrizePool + futurePrizePool + claimablePool + yieldAcc... | If game.gameOver()==true: obligations = game.claimablePoolView(). Else: game.currentPrizePoolView() + game.nextPrizePoolView() + game.futurePrizePoolView() + game.claimablePoolV... | assertGe(eth_getBalance(game), obligations); tolerance = exact (>=, 0 wei slack) | `test/fuzz/invariant/EthSolvency.inv.t.sol:36-47; helper test/fuzz/helpers/SolvencyObligations.sol:52-68` |
| `SOLV-02-FULL-BACKING-ETH-STETH` | critical | The summed four-pool obligation (current+next+future+claimable) is always fully backed by the ETH+stETH the game holds — no pool transfer (future->next->current consolidation, the time-based future... | sumPools = game.currentPrizePoolView() + game.nextPrizePoolView() + game.futurePrizePoolView() + game.claimablePoolView(); backing = eth_getBalance(game) + IERC20(STETH_TOKEN).b... | assertLe(sumPools, backing); tolerance = exact (<=, 0 wei slack) | `test/fuzz/invariant/PoolConservation.inv.t.sol:91-102` |
| `SOLV-03-NO-UNBACKED-CREDIT` | critical | Conservation: the summed four-pool obligation can never exceed the real ETH that entered the contract (starting backing captured at session start + cumulative real ETH inflow from buys). An interna... | sumPools (as SOLV-02) compared to startingBacking + ghost_realInflow, where startingBacking = eth_getBalance(game)+stETH balance sampled at session connect and ghost_realInflow ... | assertLe(sumPools, startingBacking + realInflow); tolerance = exact (<=) | `test/fuzz/invariant/PoolConservation.inv.t.sol:115-125` |
| `SOLV-04-CLAIMABLE-EQUALS-HALVES` | critical | Master SOLVENCY-01 identity: claimablePool equals the sum over all addresses of (claimable low-half + afking high-half) of their packed balance slot. The afking reservation rides INSIDE claimablePo... | For each tracked address a: packed = eth_getStorageAt(game, keccak256(abi.encode(a, 7))); sum += uint128(packed) + (packed>>128). Per-address public surrogates: game.claimableWi... | assertEq(game.claimablePoolView(), sum-over-addresses(halves)); tolerance = exact (==) | `test/fuzz/invariant/V61SolvencyAfpay.inv.t.sol:84-96` |
| `SOLV-05-CLAIMABLE-BACKED` | critical | claimablePool never exceeds the game's liquid backing (ETH + stETH) — the claim liability is always covered after any afking-funded buy, packed credit/debit, stale cashout, or smite. | game.claimablePoolView() compared to eth_getBalance(game) + IERC20(STETH_TOKEN).balanceOf(game). | assertLe(game.claimablePoolView(), eth_getBalance(game)+stETH); tolerance = exact (<=) | `test/fuzz/invariant/V61SolvencyAfpay.inv.t.sol:103-110` |
| `SOLV-06-FOLD-CONSERVATION` | critical | Purchase/mint fold conservation: the single combined claimablePool -= totalClaimableDraw exactly equals the per-tier sum of every per-player claimable + afking debit across all payKind branches (Di... | Per-transaction conservation: snapshot game.claimablePoolView() and the per-actor packed halves (slot 7, keccak256(abi.encode(a, 7)); claimable=lo128, afking=hi128) before and a... | assertEq(delta claimablePoolView, sum delta per-actor halves) across a buy; at-rest sur... | `.planning/phases/468-audit-solv/468-FINDINGS.md (SOLV-01/SOLV-02); at-rest surrogate test/fuzz/invariant/V61SolvencyAfpay.inv.t.sol:84-96` |
| `SOLV-07-SDGNRS-BOX-ROUTING` | critical | sDGNRS level-start bonus box conservation: the claimablePool debit equals the box prize-pool credit (claimable down `box` == pool up `box`, box = min(cl/20, 6 ether) floored at mp), and the 1-wei s... | Across the level-start STAGE box buy: game.claimablePoolView() decreases by exactly the amount the sDGNRS box prize pool increases by, and game.claimableWinningsOf(SDGNRS) drops... | assertEq(delta box-prize-pool, -delta claimablePoolView) for the box buy; assertLe(box,... | `.planning/phases/468-audit-solv/468-FINDINGS.md (SOLV-05); contracts/modules/GameAfkingModule.sol:1170-1198` |
| `SOLV-08-AFFILIATE-WINNERCREDIT-FLIP-ONLY` | critical | payAffiliateCombined credit conservation: the returned winnerCredit is FLIP coin only (never ETH-backed) and is conserved at the single batched MintModule creditFlipBatch([buyer, affWinner]) call s... | The FLIP supply identity COIN-01 (coin.totalSupply() + coin.vaultMintAllowance() == coin.supplyIncUncirculated()) holds across an affiliate-credited buy — the winnerCredit mint ... | COIN-01 identity holds across the affiliate credit; the affiliate leg moves 0 ETH and 0... | `.planning/phases/468-audit-solv/468-FINDINGS.md (SOLV-04); FLIP-supply surrogate test/fuzz/invariant/CoinSupply.inv.t.sol:36-46` |

## Redemption desk

| ID | Severity | Invariant | On-chain check | Comparator | Source |
|----|----------|-----------|----------------|------------|--------|
| `REDEEM-01-ETH-SEGREGATION` | critical | Segregated redemption ETH on sDGNRS never exceeds what the sDGNRS contract can cover in ETH+stETH — redemption obligations stay solvent and segregated from game pools. | sdgnrs.pendingRedemptionEthValue() (sDGNRS.sol:538) compared to eth_getBalance(sdgnrs) + IERC20(STETH_TOKEN).balanceOf(sdgnrs). | assertGe(ethBal+stethBal, sdgnrs.pendingRedemptionEthValue()); tolerance = exact (>=) | `test/fuzz/invariant/RedemptionInvariants.inv.t.sol:42-51` |
| `REDEEM-02-NO-DOUBLE-CLAIM` | critical | A redemption claim is deleted before payout; a second claim for the same (beneficiary, period) reverts. No double-claim ever succeeds. | Behavioral: off-chain client issues claimRedemption for a resolved (beneficiary, period), then re-issues the same claim and asserts the second reverts. Public state probe: the p... | second-claim must revert; ghost_doubleClaim == 0; tolerance = exact (count == 0) | `test/fuzz/invariant/RedemptionInvariants.inv.t.sol:60-66` |
| `REDEEM-03-PERIOD-MONOTONIC` | critical | The redemption period index is monotonically non-decreasing across observations (it is day-keyed: currentPeriod = GameTimeLib.currentDayIndex()), so it never regresses. | Client samples the resolving/pending day index over time. Day progression is observable via game.level() (public, DegenerusGameStorage.sol:266) and block.timestamp-derived day; ... | assertEq(ghost_periodIndexDecreased, 0) i.e. successive samples non-decreasing; toleran... | `test/fuzz/invariant/RedemptionInvariants.inv.t.sol:75-81` |
| `REDEEM-04-SUPPLY-CONSISTENCY` | critical | sDGNRS totalSupply equals initialSupply + cumulative mints - cumulative burns (no unbacked share mint or lost burn). | sdgnrs.totalSupply() (sDGNRS.sol:532) compared to client-tracked initialSupply + totalMinted - totalBurned (client samples totalSupply at connect as initial, accumulates observe... | assertEq(sdgnrs.totalSupply(), initialSupply + minted - burned); tolerance = exact (==) | `test/fuzz/invariant/RedemptionInvariants.inv.t.sol:90-97` |
| `REDEEM-05-FIFTY-PCT-CAP` | critical | Within a redemption period, cumulative burned never exceeds half the period's supply snapshot (50% cap enforced). | Per-day cap. supplySnapshot and burned are packed into the per-day DayPending struct (internal mapping pendingByDay at slot 7, keyed by uint24 day: word = eth_getStorageAt(sdgnr... | assertLe(periodBurned, supplySnapshot/2); tolerance = exact (<=) | `test/fuzz/invariant/RedemptionInvariants.inv.t.sol:105-115` |
| `REDEEM-06-ROLL-BOUNDS` | critical | Every resolved redemption period's roll lies in [25, 175]. | Parse RedemptionResolved(uint24 periodIndex, uint16 roll) events (sDGNRS.sol:198) and assert 25 <= roll <= 175 for each. | assertEq(ghost_rollOutOfBounds, 0) i.e. every observed roll in [25,175]; tolerance = ex... | `test/fuzz/invariant/RedemptionInvariants.inv.t.sol:124-130` |
| `REDEEM-07-LOOTBOX-SPLIT-CONSERVE` | critical | For every redemption claim, ethDirect + lootboxEth == totalRolledEth (the rolled ETH is conserved across the direct/lootbox split). | Parse RedemptionClaimed(player, roll, ethPayout, lootboxEth, flipPaid) events emitted by sDGNRS on claim (declared sDGNRS.sol:203, emitted :904; ethPayout = the direct half); as... | assertEq(totalEthDirect+totalLootboxEth, totalRolledEth); tolerance = exact (==) | `test/fuzz/invariant/RedemptionInvariants.inv.t.sol:198-204` |

## Token supply

| ID | Severity | Invariant | On-chain check | Comparator | Source |
|----|----------|-----------|----------------|------------|--------|
| `COIN-01-FLIP-SUPPLY` | critical | FLIP accounting identity: totalSupply + vaultMintAllowance == supplyIncUncirculated at all times (no token minted outside the tracked supply struct). | coin.totalSupply() (FLIP.sol:274) + coin.vaultMintAllowance() (FLIP.sol:288) compared to coin.supplyIncUncirculated() (FLIP.sol:281). | assertEq(totalSupply+vaultMintAllowance, supplyIncUncirculated); tolerance = exact (==) | `test/fuzz/invariant/CoinSupply.inv.t.sol:36-46` |
| `VAULT-01-ALLOWANCE-BOUNDED` | critical | The vault's FLIP mint allowance never exceeds supplyIncUncirculated (the allowance is a subset of the uncirculated total; it cannot mint beyond the bookkept ceiling). | coin.vaultMintAllowance() (FLIP.sol:288) compared to coin.supplyIncUncirculated() (FLIP.sol:281). | assertLe(coin.vaultMintAllowance(), coin.supplyIncUncirculated()); tolerance = exact (<... | `test/fuzz/invariant/VaultShare.inv.t.sol:42-67` |
| `VAULT-02-SUPPLY-AFTER-VAULT-OPS` | critical | The FLIP supply identity (COIN-01) still holds after vault burn/escrow operations (burnCoin/burnEth/vaultEscrow do not corrupt totalSupply + vaultMintAllowance == supplyIncUncirculated). | Same reads as COIN-01 (coin.totalSupply() + coin.vaultMintAllowance() vs coin.supplyIncUncirculated()), re-evaluated after any vault-touching action. | assertEq(totalSupply+vaultMintAllowance, supplyIncUncirculated); tolerance = exact (==) | `test/fuzz/invariant/VaultShareMath.inv.t.sol:61-71` |

## Liveness / no-brick (FSM)

| ID | Severity | Invariant | On-chain check | Comparator | Source |
|----|----------|-----------|----------------|------------|--------|
| `FSM-01-LEVEL-MONOTONIC` | high | The game level is monotonically non-decreasing — it only ever increases (advanceGame increments; no path decrements). | game.level() (public state var, DegenerusGameStorage.sol:266). Client samples successive level() reads and asserts each >= the previous max. | successive game.level() samples non-decreasing (ghost_levelDecreaseCount==0); tolerance... | `test/fuzz/invariant/GameFSM.inv.t.sol:23-29; test/fuzz/invariant/Composition.inv.t.sol:55-61; test/fuzz/invariant/MultiLevel.inv.t.sol:46-61` |
| `FSM-02-GAMEOVER-TERMINAL` | high | gameOver is a one-way latch: once it reads true it never reverts to false (terminality of the end state). | game.gameOver() (public bool, DegenerusGameStorage.sol:306). Client samples over time; once observed true, every later read must remain true. | no true->false transition (ghost_gameOverRevival==0); tolerance = exact | `test/fuzz/invariant/GameFSM.inv.t.sol:33-39; test/fuzz/invariant/Composition.inv.t.sol:65-71` |
| `FSM-03-NO-BRICK-LIVENESS` | high | Liveness / no-brick: while the game is live (not gameOver) the core external surface (purchase, advanceGame, placeDegeneretteBet/resolve, claimWinnings) must not revert for a well-formed call due t... | Behavioral: client drives the external action surface and observes success/expected-revert; reads game.gameOver(), game.jackpotPhase() (DegenerusGame.sol:2244), game.level() to ... | every well-formed live action succeeds or reverts only on an allowlisted guard; resolve... | `test/fuzz/invariant/GameFSM.inv.t.sol:46-60; test/fuzz/DegeneretteV73SolvencyFuzz.t.sol:18-19,91` |

## Ticket & box accounting

| ID | Severity | Invariant | On-chain check | Comparator | Source |
|----|----------|-----------|----------------|------------|--------|
| `TICKET-01-OWED-CONSISTENT` | medium | Ticket-owed tracking is consistent: an address that never purchased has zero ticketsOwed at every level, and no player carries corrupted/negative owed state. | game.ticketsOwedView(level, player) (DegenerusGame.sol:2088). For a never-participating address (e.g. 0xDEAD) assert ticketsOwedView(currentLevel, a)==0 and ticketsOwedView(curr... | assertEq(game.ticketsOwedView(lvl, nonParticipant), 0); tolerance = exact (==0) | `test/fuzz/invariant/TicketQueue.inv.t.sol:31-58` |
| `BOX-01-EVERY-PERSISTED-BOX-ENQUEUED` | medium | Every persisted (not-yet-opened) lootbox/presale box record (base != 0) for an active index is present in the permissionless openBoxes() auto-open queue (boxPlayers[index]) until opened — a box own... | Internal maps lootboxEth[index][who], presaleBoxEth[index][who], boxPlayers[index] have no production external view; off-chain the client tracks box-creating actions and the aut... | for every (index,owner) with base != 0: enqueued == true; tolerance = exact (boolean) | `test/fuzz/invariant/BoxEnqueue.inv.t.sol:112-141` |

## RNG-freeze & VRF lifecycle

| ID | Severity | Invariant | On-chain check | Comparator | Source |
|----|----------|-----------|----------------|------------|--------|
| `RNG-01-INWINDOW-SLOADS-FROZEN` | medium | While the VRF window is open (rngLocked()==true), no player-controllable action mutates, in isolation, any storage slot the pending RNG consumption reads — the enumerated in-window read set is froz... | Client polls game.rngLocked() (DegenerusGame.sol:2211); when true it snapshots the enumerated slots — game.rngWordForDay(currentDay) (DegenerusGame.sol:2204) for (1), and eth_ge... | assertEq(slot_after, slot_before) for every enumerated in-window slot (ghost_frozenSlot... | `test/fuzz/invariant/RngWindowFreeze.inv.t.sol:73-79` |
| `RNG-02-DRAIN-BEFORE-SWAP` | medium | Ordering: _swapAndFreeze cannot advance the lootbox read index while any read-slot ticket remains undrained — captured entropy always equals the populated lootboxRngWordByIndex[X] and is never zero... | Parse TraitsGenerated emissions and the lootbox word at the consumed index; assert each emit's captured entropy == game.rngWordForDay/lootboxRngWordByIndex at that index (eth_ge... | assertEq(capturedEntropy, lootboxRngWordByIndex[X]) and capturedEntropy != 0 (ghost_bin... | `test/fuzz/invariant/RngIndexDrainOrdering.inv.t.sol:32-52` |
| `VRF-01-INDEX-LIFECYCLE` | medium | lootboxRngIndex never skips a value and never double-increments on a single request, and every unlocked index has a nonzero VRF-derived word (no orphaned index). | Client tracks the lootbox index cursor across VRF fulfillments (eth_getStorageAt slot 34 low 48 bits, the index field) and reads the word per index (slot 35 keyed by index, or v... | assertEq(ghost_indexSkipViolations,0); assertEq(ghost_doubleIncrementCount,0); assertEq... | `test/fuzz/invariant/VRFPathInvariants.inv.t.sol:28-52` |
| `VRF-02-SWAP-PRESERVES-LOCK` | medium | A VRF coordinator swap never flips rngLocked in either direction: a daily request in flight keeps the lock until the re-issued word lands; an idle/mid-day-only state stays unlocked. Gap days are ba... | game.rngLocked() (DegenerusGame.sol:2211) sampled before/after a coordinator swap must be unchanged; for each gap day d after recovery assert game.rngWordForDay(d) != 0 (Degener... | rngLocked unchanged across swap (ghost_stateViolations==0); assertNe(game.rngWordForDay... | `test/fuzz/invariant/VRFPathInvariants.inv.t.sol:60-90` |
| `VRF-03-DEADMAN-MONOTONIC-LATCH` | high | _vrfDeadmanFired (_simulatedDayIndex() - dailyIdx > 120) is a pure monotonic latch: it cannot false-fire on a healthy game (dailyIdx advances on every sealed day, so a 120-sealed-day gap only opens... | Derived (not a single getter). Client tracks dailyIdx (slot 0 byte 3, mask 0xFFFFFF) and the simulated day index; asserts _simulatedDayIndex() - dailyIdx never exceeds 120 on a ... | deadman gap (_simulatedDayIndex - dailyIdx) <= 120 on a live game; once fired the latch... | `.planning/phases/469-audit-rng-liveness/469-FINDINGS.md (RNG-01); contracts/storage/DegenerusGameStorage.sol:1502-1504; gameOver-latch surrogate test/fuzz/invariant/GameFSM.inv.t.sol:33-39` |
| `RNG-03-QUEUE-WINDOW-NO-TERMINAL-JACKPOT` | high | Tickets queued during the liveness-timeout / RNG-locked window (the per-sink liveness queue-gate was removed from _queueTickets / _queueTicketsScaled / _queueTicketRange) are provably never process... | Behavioral: client attempts a purchase/queue during the liveness/game-over window and asserts the purchase entry reverts (no player ticket can enter the window); the far-future ... | an in-window purchase reverts (liveness-gated); no window-queued player ticket resolves... | `.planning/phases/469-audit-rng-liveness/469-FINDINGS.md (RNG-03); the v45 VRF-freeze invariant` |

## Access control & gift sourcing

| ID | Severity | Invariant | On-chain check | Comparator | Source |
|----|----------|-----------|----------------|------------|--------|
| `ACCESS-01-GIFT-FUNDER-SOURCING` | high | A caller-funded gift never burns a non-consenting party's FLIP: on the gift branch the spend sources from msg.sender (funder = msg.sender), while the self/operator-approved branch funds from the pl... | Behavioral: client drives a coinflip/Degenerette gift placement from a funder distinct from the player and asserts (a) the funder's FLIP balance decreases and the player's does ... | gift spend sources from msg.sender only; no non-consenting party's FLIP is burned; WWXR... | `.planning/phases/470-audit-access/470-FINDINGS.md (ACCESS-02); contracts/Coinflip.sol:258-268` |

## Degenerette economics

| ID | Severity | Invariant | On-chain check | Comparator | Source |
|----|----------|-----------|----------------|------------|--------|
| `DEG-01-PER-N-EV-CEILING` | high | For every (N goldQuadrants, heroIsGold) sub-case, the honest Degenerette base payout EV over that sub-case's own Variant-2 score distribution is never EV-positive: EV <= 100 centi-x (and ~neutral, ... | Per resolved honest (FLIP) spin the client reads FullTicketResult(player, betId, ticketIndex, playerTicket, matches, payout) (declared DegenerusGameDegeneretteModule.sol:103, em... | realized honest EV <= 100 centi-x (and per-spin decoded base <= S9_PIN[N]); statistical... | `test/stat/DegenerettePerNEvExactness.test.js:382-401; on-chain check test/fuzz/DegeneretteV73SolvencyFuzz.t.sol:100-106` |
| `DEG-02-PS9-RTP-ROI-PINS` | high | The held-fixed economic pins are unchanged by the Variant-2 diff: the activity ROI curve is 90%->99.9% (ROI_MIN 9000 -> 9990 bps), the WWXRP RTP curve is 70%->115%->118%->120% with a 70% floor, and... | Statistical/source pins. Realized ROI is observable from honest spin payout vs wager (FullTicketResult payout/wager trends to 90-99.9%); realized WWXRP RTP from WWXRP-currency F... | realized ROI within [90%,99.9%]; realized WWXRP RTP tracks 70/115/118/120% floor-70%; S... | `test/stat/DegeneretteV73Invariants.test.js:108-167; pins also asserted at test/fuzz/DegeneretteV73SolvencyFuzz.t.sol:46-48` |
| `DEG-03-WWXRP-RIG-NEVER-S9` | high | The WWXRP rig only ever LIFTS the score (rigged S in [honestS, honestS+2]) and can NEVER fabricate the S=9 jackpot: a rigged S==9 requires the honest pre-rig reel to already be a full 8-axis match ... | For a WWXRP-currency spin the client reads FullTicketResult.matches (the rigged score s) (DegenerusGameDegeneretteModule.sol:807). To evaluate the never-fabricate bound it indep... | assertGe(s, honestS) && assertLe(s, honestS+2); if s==9 then assertEq(honestM, 8); P(S=... | `test/fuzz/DegeneretteV73SolvencyFuzz.t.sol:107-118; P(S=9) invariance test/stat/DegenerettePerNEvExactness.test.js:450-459` |

## Curse neutrality

| ID | Severity | Invariant | On-chain check | Comparator | Source |
|----|----------|-----------|----------------|------------|--------|
| `CURSE-01-CURSE-NONNEGATIVE-NEUTRAL` | medium | The per-player curse counter is well-formed (a uint8 stack count) and curse-only operations (smite / decurse / stale-cashout curse-set) are pool-neutral — they move claimablePool by exactly zero an... | game.curseCountOf(player) (DegenerusGame.sol:2303) read before/after a smite/decurse/stale-cashout; assert the curse count changes as expected (e.g. +2 on smite, 0 after decurse... | assertEq(claimablePoolView_after, claimablePoolView_before) for curse-only ops (pool-ne... | `test/fuzz/invariant/V61SolvencyAfpay.inv.t.sol:240-267` |

---

## Trusted roles / trust model

Full enumeration with powers and bounds is in **`SECURITY.md`**. Summary:

| Role | Who | Power | Bound |
|------|-----|-------|-------|
| sDGNRS majority governance | voting-sDGNRS holders via `DegenerusAdmin` | swap VRF coordinator / price feed | 44h VRF death-clock; 50%→5% decaying vote; auto-killed on VRF recovery (`lastVrfProcessed > createdAt`, 475 fix); payable `receive()` never reverts |
| Vault owner | holder of >50.1% DGVE supply | vault ETH↔stETH, feed, lootbox-RNG threshold, vault's own `game*`/`coin*` proxy actions | acts only on the vault's own custodied position; cannot reach player balances or claimablePool |
| approvedDistributor | gas-faucet operators + vault owner | `distribute` donated gas-dust to high-affiliate-score players | faucet is dormant/unwired, custody-free, CEI-safe, no protocol-state writes |
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
| NatSpec / comment wording | Swept; the frozen tree's stale-comment doc-corrections are listed in `KNOWN-ISSUES.md` §5 and are not being re-touched this milestone. |
| Known automated-tool findings | Slither v0.11.5 + 4naly3er pre-triaged in `KNOWN-ISSUES.md` §7. |
| Deployment scripts / off-chain infra | Nonce-predicted addresses baked at compile time; wrong addresses = nothing works (self-auditing). |
| Frontend / indexer / website / papers | Not deployed on-chain in this repo. |
| ERC-20 deviations in FLIP / DGNRS | Intentional; documented in `KNOWN-ISSUES.md` §8. |
| "ERC-20 compliance" vs sDGNRS / GNRUS | Soulbound, not ERC-20 — invalid. |
| Wiring `DegenerusGasFaucet` into deploy | In scope to audit; stays dormant/unwired by decision. |

---

## Known issues

See **`KNOWN-ISSUES.md`** (repo root). It is a precise perimeter — design decisions, by-design rulings
(EV>100% RTP, positive-EV lootbox/coinflip, WWXRP worthless, capBucketCounts imprecision, lootbox
open-level non-manipulability, presale over-credit, redemption-dust drop, afking eviction boundary,
claimBingo no-level-guard, genesis admin self-break), the v74 cross-model dispositions (the >120-day
VRF-death deadman fallback; post-gameover ticket-insertion and sDGNRS-box-sizing invariants), carried
defended items (mid-day requestId guard re-check, VRF rotation-timer governance-malice, affiliate
floor-of-sum), stale-NatSpec doc-corrections, the indexer-parity delta, automated-tool findings, and
ERC-20 deviations. **If a finding's mechanism + impact appears there, it is not eligible.**

---

## Architecture

`DegenerusGame` is a router that dispatches to **12 delegatecall modules**, all sharing
`DegenerusGameStorage` and executing in the router's context. Chainlink VRF V2.5 for randomness; Lido
stETH for yield. All addresses are immutable compile-time constants. No proxy patterns, no
upgradeability. (The former `EndgameModule` was removed this batch — its logic folded into the
Advance / GameOver / Jackpot modules.)

### Core deployed contracts (14)

| Contract | Description |
|----------|-------------|
| DegenerusGame | Router / delegatecall dispatcher |
| DegenerusAdmin | VRF + price-feed governance (sDGNRS vote, death-clock gated), payable `receive()` |
| DegenerusAffiliate | Affiliate codes, referral tracking, bonus points, combined affiliate roll |
| FLIP | ERC-20 (coinflip auto-claim + vault virtual-reserve burn) — formerly "BURNIE" |
| Coinflip | Coinflip resolution, bounty, caller-funded gift deposits — formerly "BurnieCoinflip" |
| sDGNRS | Soulbound; holds reserves/pools, redemption desk, gambling burn — formerly "StakedDegenerusStonk" |
| DGNRS | Transferable ERC-20 wrapper over sDGNRS — formerly "DegenerusStonk" |
| DegenerusVault | stETH yield vault; deploys DGVE/DGVF share-class ERC-20s |
| DegenerusJackpots | Jackpot state + BAF helper logic |
| DegenerusQuests | Quest streaks + activity score |
| DegenerusDeityPass | ERC-721 deity passes, triangular pricing |
| Icons32Data | On-chain SVG icon data |
| GNRUS | Soulbound charity token, sDGNRS-governed level donations |
| WWXRP | wXRP utility token (value = whale-pass position) — formerly "WrappedWrappedXRP" |

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
- **Build/test:** Hardhat + Foundry. Full suite green at the frozen subject (≥ 893/0 floor;
  VRFGovernance 74/74 kill-on-recovery era). The invariant manifest (`agent/manifest/invariants.json`
  / `MAIN-INVARIANTS.md`) is the single source the Main-Invariants section above mirrors verbatim and
  the live adversarial agent asserts a subset of.
- **Companion docs:** `audit/ACCESS-CONTROL-MATRIX.md` (every external state-changing function + guard)
  and `audit/ETH-FLOW-MAP.md` (every ETH entry/exit + conservation proof), both refreshed for this
  subject's permissionless/gift, sDGNRS level-lootbox, and gas-faucet surfaces.
