# Gas audit disposition ledger

Generated 2026-06-11 after commits 16f57728 / dd09cb99 / 554f83fd.
Reconciled 2026-06-12 after round 4 (ca0efea5): the 50 round-4 IDs moved from the open table into Handled.
Round 5 applied 2026-06-12 (Game core + Vault + GNRUS): 17 more IDs moved into Handled.
IDs below are HANDLED — do not re-apply. Everything else in GAS-AUDIT-2026-06-10.{md,json} is open.

## Handled (137 + 62 round 3 + 50 round 4 + 17 round 5)

- **ADMIN-01** — APPLIED commit dd09cb99 — proposeFeedSwap: hoisted sDGNRS.votingSupply() into a single `circ` read above the path branch; votingSnapshot now uses 
- **ADMIN-02** — APPLIED commit dd09cb99 — propose: identical hoist — single votingSupply() read above the path branch, votingSnapshot reuses `circ` in contracts/D
- **ADMIN-03** — APPLIED commit dd09cb99 — vote() and voteFeedSwap(): cached (aw, rw) stack copies of p.approveWeight/p.rejectWeight at function top (covers zero-w
- **ADMIN-04** — APPLIED commit dd09cb99 — Extracted decay ladders into private _thresholdFrom(uint40)/_feedThresholdFrom(uint40); vote/canExecute/voteFeedSwap/can
- **ADMIN-11** — APPLIED commit dd09cb99 — Removed never-assigned Expired member from ProposalState enum (values 0-2 unchanged, never stored as 3); aligned the two
- **ADVANCE-01** — APPLIED commit dd09cb99 — _processPhaseTransition now returns nothing (constant 'return true;' dropped); unreachable !-guard at the transition sit
- **ADVANCE-02** — APPLIED commit dd09cb99 — Deleted the unreferenced DEPLOY_IDLE_TIMEOUT_DAYS private constant from the module (live threshold is _DEPLOY_IDLE_TIMEO
- **ADVANCE-03** — APPLIED commit dd09cb99 — Removed four unused imports (IDegenerusCoin, IBurnieCoinflip, IDegenerusQuests, BitPackingLib) — grep re-confirmed each 
- **ADVANCE-04** — APPLIED commit dd09cb99 — Removed the unused psd parameter and both silencer statements ('psd;'/'day;') from _handleGameOverPath; single call site
- **ADVANCE-07** — SKIPPED round 2 — duplicate — its target lines (the three _lrWrite calls in _finalizeRngRequest's !isRetry branch) are fully covered by RT
- **ADVANCE-11** — APPLIED commit dd09cb99 — Coalesced prizePoolsPacked reads via one _getPrizePools() call in both _consolidatePoolsAndRewardJackpots (adjacent read
- **ADVANCE-15** — APPLIED commit dd09cb99 — Inlined the dominated finalize at the daily drain gate: direct lootboxRngWordByIndex[preIdx] = cw + LootboxRngApplied(pr
- **ADVANCE-16** — APPLIED commit dd09cb99 — Mid-day path reads lootboxRngPacked once into a local and extracts the mid-day flag and index with the existing shift/ma
- **ADVANCE-17** — APPLIED commit dd09cb99 — Added bytes32 private constant BONUS_TRAITS_TAG = keccak256("BONUS_TRAITS") next to FUTURE_KEEP_TAG and used it at the l
- **AFFILIATE-05** — APPLIED commit dd09cb99 — contracts/DegenerusAffiliate.sol: removed the dead `infoSet = true;` store terminating the storedCode==0 branch and move
- **AFFILIATE-10** — APPLIED commit dd09cb99 — contracts/DegenerusAffiliate.sol: wrapped _applyLootboxTaper's excess/range/reductionBps computation in unchecked with a
- **AFKING-01** — APPLIED commit dd09cb99 — GameAfkingModule.sol: removed _resolveBuy's unused MintPaymentKind return component (dead computation + return-tuple slo
- **AFKING-05** — SKIPPED round 2 — Already applied in live source (pre-existing in HEAD, no working-tree hunk at the site): the cover-box enqueue is alread
- **AFKING-11** — APPLIED commit dd09cb99 — GameAfkingModule.sol maybeCurse: swapped the two adjacent side-effect-free early-returns so the zero-SLOAD curse-cap mas
- **BURNIE-01** — APPLIED commit 16f57728 (round 1 streams)
- **BURNIE-02** — APPLIED commit 16f57728 (round 1 streams)
- **BURNIE-04** — APPLIED commit dd09cb99 — contracts/BurnieCoinflip.sol _claimCoinflipsInternal: removed dead levelCached flag and hoisted declaration; cachedLevel
- **BURNIE-06** — APPLIED commit dd09cb99 — contracts/BurnieCoin.sol _adjustDecimatorBucket: removed dominated DECIMATOR_ACTIVITY_CAP_BPS re-cap; re-verified sole c
- **BURNIE-14** — APPLIED commit dd09cb99 — contracts/BurnieCoinflip.sol: deleted unreferenced private constant JACKPOT_RESET_TIME (82620); grep re-confirmed exactl
- **BURNIE-15** — APPLIED commit dd09cb99 — contracts/BurnieCoin.sol local IBurnieCoinflip interface: deleted unused creditFlip declaration + natspec; grep re-confi
- **DECIMATOR-01** — SKIPPED round 2 — Already fixed in live source: the external consumeDecClaim chain (module external fn, DegenerusGame wrapper, IDegenerusG
- **DECIMATOR-04** — APPLIED commit dd09cb99 — Hoisted DecClaimRound storage ref (gate + 3 writes) and uint256[13][13] storage levelTotals out of the 11-iteration deno
- **DECIMATOR-07** — APPLIED commit dd09cb99 — Removed always-true `if (fullHalfPasses != 0)` wrapper in _awardDecimatorLootbox (amount > 5 ether forces fullHalfPasses
- **DECIMATOR-12** — APPLIED commit 16f57728 (round 1 streams)
- **DEGENERETTE-01** — APPLIED commit dd09cb99 — Hoisted gold-quadrant count out of the spin loop in _resolveFullTicketBet (computed once per bet as goldCount); _fullTic
- **DEGENERETTE-04** — APPLIED commit dd09cb99 — Cached level once (uint24 lvl, matching the storage declaration) at the top of _placeDegeneretteBet, threaded into _plac
- **DEGENERETTE-06** — APPLIED commit dd09cb99 — Inlined the operatorApprovals lookup at the _resolvePlayer call site (inside the dominating player != msg.sender guard) 
- **DEGENERETTE-07** — APPLIED commit dd09cb99 — Removed the dominated weiAmount == 0 early-return in _addClaimableEth (sole call site in resolveBets is gated on acc.eth
- **DEGENERETTE-08** — APPLIED commit dd09cb99 — Removed the dead bucket < 6 || bucket > 9 range check in _wwxrpFactor (sole call site gated on bucket != 0 with bucket f
- **DEGENERETTE-09** — APPLIED commit dd09cb99 — Deleted the unreferenced MASK_48 private constant (grep across all of contracts/ matched only the declaration; index rea
- **DEITY-02** — APPLIED commit dd09cb99 — _renderSvgInternal caches _nonCryptoSymbolColor in `ncColor` (one storage-string copy instead of two); tokenURI loads re
- **DEITY-03** — APPLIED commit dd09cb99 — Deleted _symbolTranslate (sole call site passed (ICON_VB, ICON_VB)); replaced with single inline `int256 t = -(int256(ui
- **GAME-01** — APPLIED commit 16f57728 (round 1 streams)
- **GAME-02** — APPLIED commit dd09cb99 — Deleted orphaned private pure _ethToBurnieValue + its docstring from contracts/DegenerusGame.sol (~L1674-1686 live; zero
- **GAME-03** — APPLIED commit dd09cb99 — Deleted unreferenced private constant DEPLOY_IDLE_TIMEOUT_DAYS (L153-154) from contracts/DegenerusGame.sol; live livenes
- **GAME-04** — APPLIED commit 16f57728 (round 1 streams)
- **GAME-05** — APPLIED commit 16f57728 (round 1 streams)
- **GAME-06** — APPLIED commit 16f57728 (round 1 streams)
- **GAME-07** — APPLIED commit 16f57728 (round 1 streams)
- **GAME-09** — APPLIED commit 16f57728 (round 1 streams)
- **GAME-10** — APPLIED commit 16f57728 (round 1 streams)
- **GAME-11** — APPLIED commit 16f57728 (round 1 streams)
- **GAME-17** — APPLIED commit 16f57728 (round 1 streams)
- **JACKPOTMOD-01** — APPLIED commit dd09cb99 — Deleted zero-caller private _resolveTraitWinners and its doc block in contracts/modules/DegenerusGameJackpotModule.sol; 
- **JACKPOTMOD-06** — APPLIED commit dd09cb99 — distributeYieldSurplus now unpacks prizePoolsPacked once via _getPrizePools() and caches claimablePool/yieldAccumulator 
- **JACKPOTMOD-07** — APPLIED commit dd09cb99 — Inserted `if (baseAmount == 0) return;` after the baseAmount computation in _awardDailyCoinToTraitWinners, skipping the 
- **JACKPOTMOD-12** — APPLIED commit dd09cb99 — Deleted the unreachable `if (counter >= JACKPOT_LEVEL_CAP - 1) return 10_000;` guard in _dailyCurrentPoolBps and updated
- **JACKPOTMOD-16** — APPLIED commit dd09cb99 — Removed six unused imports (IDegenerusCoin, IBurnieCoinflip, IDegenerusQuests, IStakedDegenerusStonk, DegenerusTraitUtil
- **JACKPOTMOD-19** — APPLIED commit dd09cb99 — Converted checked increments to the file's unchecked idiom in the bounded 4-iteration loops: _pickSoloQuadrant and the _
- **JACKPOTS-01** — APPLIED commit 16f57728 (round 1 streams)
- **JACKPOTS-02** — APPLIED commit 16f57728 (round 1 streams)
- **JACKPOTS-03** — APPLIED commit 16f57728 (round 1 streams)
- **JACKPOTS-04** — APPLIED commit 16f57728 (round 1 streams)
- **JACKPOTS-05** — APPLIED commit 16f57728 (round 1 streams)
- **JACKPOTS-07** — APPLIED commit dd09cb99 — contracts/DegenerusJackpots.sol century scatter targeting (~L418-425): merged the two byte-identical round<8/round<12 br
- **JACKPOTS-08** — APPLIED commit dd09cb99 — contracts/DegenerusJackpots.sol: replaced all 4 entropy-chaining sites (live L298, L315, L357, L413) with EntropyLib.has
- **LIBS-07** — APPLIED commit dd09cb99 — Deleted unreferenced MASK_2 and MASK_1 constants (with their natspec lines) from contracts/libraries/BitPackingLib.sol —
- **LIBS-08** — SKIPPED round 2 — Already applied: BurnieCoinflip.sol no longer contains the JACKPOT_RESET_TIME declaration — it was present at L133 when 
- **LOOTBOX-01** — APPLIED commit dd09cb99 — Removed dead third return `applyPresaleMultiplier` from _resolveLootboxRoll (signature, 4 branch assignments, early retu
- **LOOTBOX-03** — APPLIED commit dd09cb99 — Deleted three unreachable `targetLevel < currentLevel` clamps (in _openLootBoxLeg, at _resolveLootboxCommon entry, and t
- **LOOTBOX-04** — APPLIED commit dd09cb99 — Deleted unsatisfiable `boonBudget > amount` clamp in _lootboxBoonBudget (budget = amount*1000/10000 <= amount, max-budge
- **LOOTBOX-13** — APPLIED commit dd09cb99 — Deleted unreferenced private constant HALF_WHALE_PASS_PRICE (single occurrence in the module; identically-named constant
- **LOOTBOX-15** — APPLIED commit dd09cb99 — Threaded the already-loaded rngWordByDay[day] word into _deityBoonForSlot as a `uint256 rngWord` param (seed derivation 
- **MINT-01** — APPLIED commit 16f57728 (round 1 streams)
- **MINT-02** — APPLIED commit 16f57728 (round 1 streams)
- **MINT-03** — APPLIED commit 16f57728 (round 1 streams)
- **MINT-07** — APPLIED commit dd09cb99 — DegenerusGameMintStreakUtils.sol: added _mintStreakEffectiveFromPacked (pure, operates on the already-loaded mintPacked_
- **MINT-10** — APPLIED commit dd09cb99 — DegenerusGameMintModule.sol _purchaseCoinFor: cached uint24 cachedLevel = level at block entry; used for the _callTicket
- **MINT-13** — APPLIED commit dd09cb99 — DegenerusGameMintModule.sol: deleted dead private _questMint (live at L1891-1913) plus its doc comment; apply-time re-gr
- **MINT-14** — APPLIED commit dd09cb99 — DegenerusGameMintModule.sol: deleted unused LOOTBOX_BOOST_{5,15,25}_BONUS_BPS constants (live at L113-115, zero uses in 
- **MINT-17** — APPLIED commit dd09cb99 — DegenerusGameMintModule.sol first-deposit EV-cap branch (live at L1417-1419): wrapped the lootboxEvBenefitUsedByLevel ac
- **QUESTS-11** — APPLIED commit dd09cb99 — contracts/DegenerusQuests.sol: awardQuestStreakBonus and awardQuestStreakShield now hold the clamped value in a local (n
- **QUESTS-12** — SKIPPED round 2 — Premise no longer holds in live source: the active-quest pair was refactored into a single packed storage slot (activeQu
- **QUESTS-15** — APPLIED commit 16f57728 (round 1 streams)
- **RT-ADVANCE-02** — APPLIED commit dd09cb99 — payDailyJackpot: hoisted counterStep/isFinalPhysicalDay out of the inner scope and deleted the post-block re-derivation 
- **RT-ADVANCE-03** — APPLIED commit dd09cb99 — Replaced the 4-SLOAD/2-SSTORE future->next 0.5% reserve move with one _getPrizePools()/_setPrizePools(next + slice, futu
- **RT-ADVANCE-07** — APPLIED commit dd09cb99 — Item (1): coinflip-credit price lookup now uses the purchaseLevel parameter (== storage level on the only call path — la
- **RT-ADVANCE-08** — APPLIED commit dd09cb99 — Item (1): rngGate early-return caches rngWordByDay[day] into a local before the != 0 check (no store between the former 
- **RT-ADVANCE-09** — APPLIED commit dd09cb99 — Added private helper _lrAdvanceIndexClearPending() — one read of lootboxRngPacked, combined-mask clear of INDEX/PENDING_
- **RT-ADVANCE-13** — APPLIED commit dd09cb99 — _calcDailyCoinBudget now takes (uint24 lvl, uint24 currLevel) and prices via currLevel instead of re-reading storage `le
- **RT-ADVANCE-14** — SKIPPED round 2 — Duplicate of SMALLMODS-13 (same lines, same change in handleFinalSweep); SMALLMODS-13 was applied as the canonical insta
- **RT-AFKING-WHALE-09** — SKIPPED round 2 — duplicate — identical change to WHALEBOON-03 at the same two lines (L325/L647 isBonus conjunct); WHALEBOON-03 applied as
- **RT-AFKING-WHALE-13** — APPLIED commit dd09cb99 — Hoisted `uint24 capKey = level + 1;` at the top of _recordLootboxEntry and used it at all four EV-cap sites, mirroring t
- **RT-AFKING-WHALE-15** — APPLIED commit 16f57728 (round 1 streams)
- **RT-CLAIMS-01** — SKIPPED round 2 — Duplicate of LOOTBOX-01 (same dead third return value on _resolveLootboxRoll, same call site); LOOTBOX-01 applied as the
- **RT-CLAIMS-06** — APPLIED commit 16f57728 (round 1 streams)
- **RT-CLAIMS-07** — APPLIED commit 16f57728 (round 1 streams)
- **RT-CLAIMS-10** — APPLIED commit dd09cb99 — contracts/DegenerusGame.sol _payoutWithStethFallback (~L2146 live): removed the explicit self-balance pre-check before t
- **RT-COINFLIP-01** — APPLIED commit 16f57728 (round 1 streams)
- **RT-COINFLIP-02** — APPLIED commit 16f57728 (round 1 streams)
- **RT-COINFLIP-04** — SKIPPED round 2 — Duplicate of BURNIE-04 — identical lines, identical change; applied once under BURNIE-04.
- **RT-COINFLIP-05** — SKIPPED round 2 — Deleting claimCoinflipsForRedemption requires touching files outside the packet: interfaces/IBurnieCoinflip.sol (L173 de
- **RT-IDIOMS-01** — APPLIED commit 16f57728 (round 1 streams)
- **RT-IDIOMS-02** — APPLIED commit 16f57728 (round 1 streams)
- **RT-IDIOMS-03** — APPLIED commit 16f57728 (round 1 streams)
- **RT-IDIOMS-07** — APPLIED commit 16f57728 (round 1 streams)
- **RT-IDIOMS-13** — APPLIED commit dd09cb99 — contracts/BurnieCoinflip.sol processCoinflipPayouts: CoinflipDayResolved emit now reuses local newBounty computed with t
- **RT-MINT-01** — APPLIED commit 16f57728 (round 1 streams)
- **RT-MINT-03** — APPLIED commit 16f57728 (round 1 streams)
- **RT-MINT-05** — APPLIED commit 16f57728 (round 1 streams)
- **RT-MINT-07** — SKIPPED round 2 — Duplicate of MINT-07 (same _playerActivityScore/_mintStreakEffective lines in DegenerusGameMintStreakUtils.sol); MINT-07
- **RT-MINT-10** — SKIPPED round 2 — Core change (delete _questMint in DegenerusGameMintModule.sol) already applied via MINT-13 — duplicate. The cascade (del
- **RT-PACKING-07** — APPLIED commit 16f57728 (round 1 streams)
- **RT-PACKING-10** — APPLIED commit 16f57728 (round 1 streams)
- **RT-PACKING-11** — APPLIED commit 16f57728 (round 1 streams)
- **SMALLMODS-01** — APPLIED commit dd09cb99 — Collapsed `uint32((uint64(rnd) * 256) >> 32)` to `rnd >> 24` in weightedColorBucket (contracts/DegenerusTraitUtils.sol) 
- **SMALLMODS-04** — APPLIED commit dd09cb99 — Cached bingoClaimed[level][msg.sender] into uint8 claimedBits for the dedup gate + write in claimBingo, contracts/module
- **SMALLMODS-06** — SKIPPED round 2 — Packet rule 3 violation: a state-changing external call (dgnrs.transferFromPool, BingoModule L236) occurs between the ca
- **SMALLMODS-07** — APPLIED commit dd09cb99 — Dropped dominated `score != 0` conjunct from the deity-bonus branch in claimAffiliateDgnrs (reward==0 revert above force
- **SMALLMODS-13** — APPLIED commit dd09cb99 — Cached _goRead(GO_TIME_SHIFT, GO_TIME_MASK) once for both early-return gates in handleFinalSweep, contracts/modules/Dege
- **SMALLMODS-15** — APPLIED commit dd09cb99 — Deleted uncalled approve declaration (+2 @param lines) from module-local IStETH interface, contracts/modules/DegenerusGa
- **SMALLMODS-18** — APPLIED commit dd09cb99 — Replaced (boxEth * 20) / 100 with boxEth / 5 in _creditBoxProceeds (exact identity; 80/20 split and remainder-to-VAULT u
- **SMALLMODS-19** — APPLIED commit dd09cb99 — Replaced div-mul-sub remainder with amount % HALF_WHALE_PASS_PRICE in _queueWhalePassClaimCore (exact identity), contrac
- **SMALLMODS-20** — APPLIED commit dd09cb99 — Changed setSymbols parameter from `string[8] memory` to `string[8] calldata` in contracts/Icons32Data.sol (loop bodies u
- **STORAGE-01** — APPLIED commit dd09cb99 — Removed dead lootboxRngMinLinkBalance field: deleted LR_MIN_LINK_SHIFT/LR_MIN_LINK_MASK constants, dropped the (14 << 17
- **STORAGE-02** — APPLIED commit dd09cb99 — Deleted duplicate IDegenerusQuestView interface and questView constant from contracts/storage/DegenerusGameStorage.sol; 
- **STORAGE-07** — APPLIED commit dd09cb99 — Moved emit TicketsQueued after the _livenessTriggered() revert gate in _queueTickets (contracts/storage/DegenerusGameSto
- **STORAGE-17** — APPLIED commit dd09cb99 — Replaced `if (owed == 0 && rem == 0)` with `if (packed == 0)` at all three queue-helper membership checks (_queueTickets
- **TOKENS-04** — APPLIED commit dd09cb99 — Dropped the dominated '(bitmap != 0)' conjunct from pickCharity's paid condition in contracts/GNRUS.sol (bestSlot is onl
- **TOKENS-11** — APPLIED commit dd09cb99 — Deleted three never-invoked local interface declarations in contracts/GNRUS.sol: ISDGNRSSnapshot.totalSupply, ISDGNRSSna
- **TOKENS-12** — APPLIED commit dd09cb99 — Inlined the single constructor mint (totalSupply/balanceOf[address(this)] = INITIAL_SUPPLY + Transfer event) and deleted
- **TOKENS-17** — APPLIED commit dd09cb99 — Deleted the duplicate vaultMintAllowance() getter from contracts/WrappedWrappedXRP.sol (zero on-chain callers — all thre
- **VAULT-05** — APPLIED commit dd09cb99 — Removed both zero-guards around plain additions: burnCoin now does unconditional 'coinBal += vaultBal + claimable;' (che
- **VAULT-09** — APPLIED commit dd09cb99 — Deleted the never-invoked 'function advanceGame() external;' declaration and its natspec from the local IDegenerusGamePl
- **VAULT-10** — APPLIED commit dd09cb99 — Removed the unreachable 'to == address(0)' check from DegenerusVaultShare.vaultMint plus its stale '@custom:reverts Zero
- **VIEWER-01** — APPLIED commit dd09cb99 — deityBoonSlots: hoisted the two loop-invariant `total` lines above the 3-iteration loop; per-iteration seed derivation l
- **WHALEBOON-03** — APPLIED commit dd09cb99 — Dropped always-true `lvl >= passLevel` conjunct from `isBonus` in both 100-level ticket loops (whale bundle + deity pass
- **WHALEBOON-04** — APPLIED commit dd09cb99 — Removed dead `uint96 buyerDgnrs` return from _rewardDeityPassDgnrs (sole caller discards it; grep-confirmed single call 
- **WHALEBOON-05** — APPLIED commit dd09cb99 — Deleted the three unreferenced private constants LOOTBOX_BOOST_5/15/25_BONUS_BPS (with natspec) from DegenerusGameWhaleM
- **WHALEBOON-07** — APPLIED commit dd09cb99 — Dropped the redundant `s1 = bpLazy.slot1;` re-read on the hasValidBoon path of _purchaseLazyPass and replaced the mislea
- **WHALEBOON-12** — APPLIED commit dd09cb99 — DegenerusGameBoonModule.sol consumeActivityBoon: removed the provably-true guard (currentDay != 0 && bonus != 0) — pendi
- **WHALEBOON-15** — APPLIED commit dd09cb99 — Removed the always-true `if (lootboxAmount != 0)` wrapper in _recordLootboxEntry's subsequent-deposit branch (applied as


### Round 3 (2026-06-12) — JackpotModule / AfkingModule / Quests / Affiliate / BurnieCoinflip

- **AFFILIATE-01** — APPLIED round 3 — _resolveCodeInfo single-SLOAD owner+kickback helper at all 3 payAffiliate resolve blocks
- **AFFILIATE-02** — APPLIED round 3 — dead COIN clause removed from payAffiliate access check (msg.sender != GAME only)
- **AFFILIATE-03** — APPLIED round 3 — _routeAffiliateReward deleted; creditFlip inlined at both distribution sites
- **AFFILIATE-04** — APPLIED round 3 — single hoisted entropy keccak inside affiliateShareBase!=0; %2 / %20 per branch
- **AFFILIATE-06** — APPLIED round 3 — file-local handleAffiliate interface slimmed to returns(uint256 reward)
- **AFFILIATE-07** — APPLIED round 3 — info/vaultInfo memory structs replaced with stack locals at 6 sites
- **AFFILIATE-09** — APPLIED round 3 — variant B: i!=0 guard on _referrerAddress check in claim drain loop
- **AFKING-02** — APPLIED round 3 — guaranteed-no-op _finalizeAfking removed from tombstone-reclaim branch
- **AFKING-04** — APPLIED round 3 — set-removal loop hoists len; unchecked --len at all 3 _removeFromSet sites
- **AFKING-07** — APPLIED round 3 — cancel event funding arg gated on FLAG_EXTERNAL_FUNDING (map read skipped otherwise)
- **AFKING-08** — APPLIED round 3 — single uncapped reinvestSpend computed once; duplicate expression deleted
- **BURNIE-03** — APPLIED round 3 — claimCoinflipsForRedemption deleted (+ IBurnieCoinflip entry); zero production references post-rework; RedemptionGas.t.sol dead mocks pruned
- **BURNIE-05** — APPLIED round 3 — dead recordAmount > uint128.max guard deleted in _addDailyFlip
- **BURNIE-12** — APPLIED round 3 — first-enable branches collapsed to strict ordering (non-strict path production-unreachable)
- **BURNIE-13** — APPLIED round 3 — setCoinflipAutoRebuy routed through _resolvePlayer; _requireApproved deleted
- **JACKPOTMOD-02** — APPLIED round 3 — pair-rolled hero traits via _rollWinningTraitsPair/_applyHeroResult at all 3 same-randWord pairs
- **JACKPOTMOD-03** — APPLIED round 3 — residual: compressedJackpotFlag cached in a local (hoists were already at HEAD)
- **JACKPOTMOD-04** — APPLIED round 3 — curPool local threads currentPrizePool through distribution (entry read merged)
- **JACKPOTMOD-05** — APPLIED round 3 — live parts: futureBal reuse + module-private _addNextPrizePool/_addFuturePrizePool single-RMW helpers at 4 sites
- **JACKPOTMOD-08** — APPLIED round 3 — _runCoinJackpot extracted for both call sites (currLevel param added for the 2-arg _calcDailyCoinBudget)
- **JACKPOTMOD-09** — APPLIED round 3 — shared _deityVirtualCount tier rule for both full-copy sites (composed with RT-ADVANCE-11)
- **JACKPOTMOD-10** — APPLIED round 3 — _executeJackpot/_runJackpotEthFlow/JackpotParams deleted; logic inlined at sole site behind ethPool!=0
- **JACKPOTMOD-11** — APPLIED round 3 — _addClaimableEth wrapper deleted; 7 sites call _creditClaimable directly; distributeYieldSurplus collapsed
- **JACKPOTMOD-13** — APPLIED round 3 — isEthDay/poolBps deleted; purchase-path slice = futureBal/100 (call graph re-verified)
- **JACKPOTMOD-17** — APPLIED round 3 — live parts: entropy locals moved into consuming branches; jackpotCounter cached for read+RMW
- **JACKPOTMOD-18** — APPLIED round 3 — _soloAdjustedEntropy extracted; 3 verbatim splice sites replaced
- **LIBS-09** — APPLIED round 3 — _emitDailyWinningTraits helper shared by both mutually-exclusive branches
- **QUESTS-01** — APPLIED round 3 — dead DailyQuest.flags deleted from pack/unpack (QuestSlotRolled ABI unchanged, emits literal 0)
- **QUESTS-02** — APPLIED round 3 — questVersionCounter/_nextQuestVersion/DailyQuest.version deleted; QuestSlotRolled emits day in version position (no consumer keys on counter)
- **QUESTS-03** — APPLIED round 3 — questGame.level() hoisted once in completion branch; _isLevelQuestEligible parameterized
- **QUESTS-07** — APPLIED round 3 — mint legs use direct slot addressing (MINT_ETH=0, MINT_BURNIE=1); zero-delta ternaries dropped
- **QUESTS-09** — APPLIED round 3 — partial: mint/purchase non-completion returns reuse synced outStreak locals (other handlers already 1-SLOAD)
- **QUESTS-10** — APPLIED round 3 — _questReady reduced to day-tag check; zero-caller _questProgressValidStorage deleted
- **RT-ADVANCE-01** — APPLIED round 3 — _awardDailyCoinToTraitWinners batches winners into one creditFlipBatch call post-loop (per-winner events kept)
- **RT-ADVANCE-04** — APPLIED round 3 — early-bird debit+credit folded into one prizePools RMW at exit
- **RT-ADVANCE-05** — APPLIED round 3 — duplicate of JACKPOTMOD-02 (one implementation)
- **RT-ADVANCE-11** — APPLIED round 3 — _computeBucketCounts returns lens/deities; threaded to a _randTraitTicket overload (ETH path keeps self-reading variant)
- **RT-AFKING-WHALE-01** — APPLIED round 3 — GO_SWEPT swept flag hoisted once per stage chunk, threaded through _resolveBuy
- **RT-AFKING-WHALE-03** — APPLIED round 3 — ticketTargetLevel hoisted per chunk, threaded as _deliverAfkingBuy param
- **RT-AFKING-WHALE-06** — APPLIED round 3 — duplicate of AFKING-08
- **RT-AFKING-WHALE-14** — APPLIED round 3 — _recordAfkingCoverBox single lootboxRngPacked load + one recombined SSTORE
- **RT-AFKING-WHALE-17** — APPLIED round 3 — bounty unit priced lazily per branch (advance leg pre-advanceGame when eligible; open leg after opened>0)
- **RT-AFKING-WHALE-18** — APPLIED round 3 — _settlePendingBurnie extracted; cancel/upsert/claim swapped in with zero-before-creditFlip CEI
- **RT-COINFLIP-03** — APPLIED round 3 — game.level() STATICCALL dropped in BAF block; cachedLevel derived from purchaseInfo snapshot
- **RT-COINFLIP-06** — APPLIED round 3 — onlyBurnieCoin reduced to COIN-only (never-exercised permission narrowed)
- **RT-COINFLIP-08** — APPLIED round 3 — storedAfter local replaces claimableStored re-read (full in-window writer trace re-run post-rework)
- **RT-COINFLIP-09** — APPLIED round 3 — part (a): depositCoinflip routed through _resolvePlayer; part (b) is BurnieCoin.sol — open for that file group
- **RT-COINFLIP-11** — APPLIED round 3 — dominated !inJackpotPhase terms dropped from BAF revert predicate + _coinflipLockedDuringTransition
- **RT-IDIOMS-11** — APPLIED round 3 — duplicate of AFKING-04
- **RT-IDIOMS-14** — APPLIED round 3 — _advanceDueInContext() in-context mirror replaces IGameRouter self-call in mintBurnie; dead advanceDue dropped from file-local IGameRouter
- **RT-QUESTS-AFFILIATE-01** — APPLIED round 3 — via _resolveCodeInfo on the stored-code repeat branch
- **RT-QUESTS-AFFILIATE-02** — APPLIED round 3 — sum>=25 ether break after accumulation in affiliateBonusPointsBest
- **RT-QUESTS-AFFILIATE-06** — APPLIED round 3 — _questSyncProgress writes only day tag when stale, returns effective progress (5 sites)
- **RT-QUESTS-AFFILIATE-08** — APPLIED round 3 — duplicate of QUESTS-03
- **RT-QUESTS-AFFILIATE-09** — APPLIED round 3 — duplicate of AFFILIATE-09
- **RT-QUESTS-AFFILIATE-10** — APPLIED round 3 — duplicate of QUESTS-07
- **RT-QUESTS-AFFILIATE-12** — APPLIED round 3 — slot==1 short-circuit before _maybeCompleteOther in _questCompleteWithPair
- **RT-QUESTS-AFFILIATE-13** — APPLIED round 3 — upfront vaultInfo construction gone; VAULT assigned inline in 3 fallback branches
- **QUESTS-16** — SKIPPED round 3 — getActiveQuests has a live compile-time test dependency + unverifiable frontend-coordination precondition — keep
- **RT-AFKING-WHALE-04** — SKIPPED round 3 — packet conditional triggered: per-debit claimablePool tandem is the documented SOLVENCY-01 auditability convention — keep
- **RT-QUESTS-AFFILIATE-03** — SKIPPED round 3 — premise superseded: both quests pack into single activeQuestsPacked slot (one SLOAD already)
- **RT-QUESTS-AFFILIATE-07** — SKIPPED round 3 — subsumed: packed single-SSTORE landed in earlier rounds; residual version-counter RMW removed by QUESTS-02

### Round 4 (2026-06-12) — Mint / Lootbox / Decimator / Whale / Advance modules + cross Quests-Afking

Commit ca0efea5 (contracts) + 575fdd82 (test recalibrations). Full bodies + verification notes:
`.planning/gas-round4/packet-*.md` and `.planning/gas-round4/APPLIED-LEDGER.md`.

- **MINT-04** — APPLIED round 4 — recordMint's trailing _recordMintDataModule delegatecall-back deleted; direct internal _recordMintData at the self-call return point; ABI narrowed to (player, costWei, payKind); Game dispatch dropped (20,651 → 20,493 bytes)
- **MINT-05** — APPLIED round 4 — per-batch counts/touchedTraits scratch hoisted out of _raritySymbolBatch, threaded by ref, re-zeroed to preserve the all-zero invariant
- **MINT-08** — APPLIED round 4 — _mintCost → _purchaseCostInputs (one read of flag/level/price/ticketCost) forwarded into _purchaseForWithCached (with RT-MINT-09)
- **MINT-09** — APPLIED round 4 — lootboxRngPacked/presaleStatePacked RMWs cached to one masked SSTORE each; enqueue flattened to direct boxPlayers[].push (with RT-MINT-08)
- **MINT-11** — APPLIED round 4 — ticketCursor epilogue writes the packed (cursor,level) slot once per path
- **MINT-16** — APPLIED round 4 — jackpot flag/counter read + nextStep computed once under the cachedJpFlag guard
- **RT-MINT-04** — APPLIED round 4 — recordMintQuestStreak self-call → internal _recordMintStreakForLevel (with RT-IDIOMS-04)
- **RT-MINT-08** — APPLIED round 4 — with MINT-09 (lootbox-slot RMW caching)
- **RT-MINT-09** — APPLIED round 4 — with MINT-08 (_purchaseCostInputs threading)
- **RT-IDIOMS-04** — APPLIED round 4 — with RT-MINT-04 (quest-streak self-call elision)
- **LOOTBOX-02** — APPLIED round 4 — dead deityBoonSlots view + its interface decl deleted (with VIEWER-02)
- **LOOTBOX-05** — APPLIED round 4 — dead zero-guard flattened (callers guarantee nonzero)
- **LOOTBOX-06** — APPLIED round 4 — dead presale zero-guard flattened
- **LOOTBOX-07** — APPLIED round 4 — currentLevel + deityPassCount threaded into boon roll/pool-stats (with RT-CLAIMS-03)
- **LOOTBOX-08** — APPLIED round 4 — openHumanBoxes sweep threads the per-index VRF word + per-entry lootboxEth/presaleBoxEth (the skip-check reads) into _openLootBoxLegWith + presale resolve instead of re-SLOADing in _openBoxBoth (now manual-openBox-only); cache-safety argued in packet
- **VIEWER-02** — APPLIED round 4 — with LOOTBOX-02 (dead view deleted)
- **RT-CLAIMS-02** — APPLIED round 4 — dead compare/branch eliminations on box open
- **RT-CLAIMS-03** — APPLIED round 4 — with LOOTBOX-07 (threaded reads)
- **RT-CLAIMS-05** — APPLIED round 4 — issueDeityBoon lazy-mask; day-rollover zeroing SSTORE dropped
- **RT-CLAIMS-12** — APPLIED round 4 — with LOOTBOX-05/06 (dead zero-guards)
- **DECIMATOR-02** — APPLIED round 4 — decimator packet: claim-batch redundant mapping re-reads cached
- **DECIMATOR-03** — APPLIED round 4 — decimator packet: loop-invariant hoists in the claim loop
- **DECIMATOR-06** — APPLIED round 4 — decimator packet: dominated recordDecBurn checks dropped
- **DECIMATOR-08** — APPLIED round 4 — decimator packet: redundant eligibility compare dropped
- **DECIMATOR-09** — APPLIED round 4 — decimator packet: recordDecBurn/terminal-burn idiom rework
- **DECIMATOR-11** — APPLIED round 4 — decimator packet: >5-ETH claim mod idiom + recursion flattened
- **DECIMATOR-13** — APPLIED round 4 — decimator packet: _consumeTerminalDecClaim returns (amount, lvl) to drop a re-read
- **DECIMATOR-14** — APPLIED round 4 — decimator packet: dead guard on terminal/regular decimator burn removed
- **QUESTS-04** — APPLIED round 4 — decimator packet: terminal-dec boost mintPrice view consults avoided
- **RT-QUESTS-AFFILIATE-04** — APPLIED round 4 — decimator packet: boostTerminalDecimator 2-slot view skip
- **GAME-12** — APPLIED round 4 — whale packet: whale-bundle purchase external-call elision
- **WHALEBOON-01** — APPLIED round 4 — 100-iteration bonus-ticket loop → closed-form two-range queue (whale bundle)
- **WHALEBOON-02** — APPLIED round 4 — 100-iteration bonus-ticket loop → closed-form two-range queue (deity pass)
- **WHALEBOON-08** — APPLIED round 4 — whale packet: lootboxRngPacked SLOADs cached on pass purchase
- **WHALEBOON-09** — APPLIED round 4 — whale packet: first-deposit pass lootbox call elision
- **WHALEBOON-10** — APPLIED round 4 — whale packet: first-deposit pass lootbox self-call elision
- **WHALEBOON-11** — APPLIED round 4 — whale packet: deity purchase SLOAD/keccak hoist
- **WHALEBOON-13** — APPLIED round 4 — whale packet: dead lazy-default branches deleted
- **RT-AFKING-WHALE-11** — APPLIED round 4 — _playerActivityScore internal call on boon-discounted lazy-pass purchase
- **RT-AFKING-WHALE-12** — APPLIED round 4 — whale packet: pass-bundled lootbox first-deposit CALL elision
- **ADVANCE-05** — APPLIED round 4 — advance packet: level-transition external call → internal
- **ADVANCE-08** — APPLIED round 4 — advance packet: dailyIdx/rngLockedFlag hoisted across advanceGame
- **ADVANCE-09** — APPLIED round 4 — advance packet: VRF request struct construction → shared _requestVrfWord
- **ADVANCE-14** — APPLIED round 4 — advance packet: level-1-only path stack plumbing
- **RT-IDIOMS-09** — APPLIED round 4 — advance packet: pool-balance read hoisted
- **ADVANCE-12** — SKIPPED round 4 — already present at HEAD from a prior round (verified no-op)
- **ADVANCE-18** — SKIPPED round 4 — already present at HEAD from a prior round (verified no-op)
- **RT-IDIOMS-10** — SKIPPED round 4 — already present at HEAD from a prior round (verified no-op)
- **QUESTS-13** — APPLIED round 4 — new lean questCompletionToday(player) view in DegenerusQuests (delegates to _questCompleted per slot, day-roll semantics inherited); afking call site swapped off the fat playerQuestStates
- **RT-QUESTS-AFFILIATE-15** — APPLIED round 4 — with QUESTS-13 (module-local IQuestCompletionView interface)

### Round 5 (2026-06-12) — DegenerusGame core / DegenerusVault / GNRUS

Packets + adjudications + applied records: `.planning/gas-round5/packet-{game,vault,gnrus}.md`.
NHR/PARTIAL items were adjudicated in-packet before application; the 3 reviewer fan-out passes
returned 17/17 FAITHFUL with zero unexplained hunks.

- **GAME-08** — APPLIED round 5 (NHR adjudicated) — recordMint + _processMintPayment relocated into MintModule as _recordMintPayment/_processMintPayment with explicit ethForLeg (all 5 msg.value reads converted); value-bearing self-call deleted; Game loses recordMint + dispatcher + ClaimableSpent decl + PURCHASE_TO_FUTURE_BPS; IDegenerusGame.recordMint decl deleted
- **GAME-14** — APPLIED round 5 — merged claimablePool RMW `-= uint128(claimableUsed) + uint128(afkingUsed)` in the relocated payment body; emits unchanged
- **GAME-15** — APPLIED round 5 (NHR adjudicated) — new DegenerusGameStorage._debitClaimableAndAfking (one SLOAD, explicit per-half guards, one SSTORE); call sites _claimWinningsInternal + relocated _processMintPayment; existing four helpers untouched
- **GAME-16** — APPLIED round 5 — degeneretteResolve probe folded into do-while loop-peel (probe SLOAD = iteration 0's read); identical read/resolve interleaving
- **RT-CLAIMS-08** — APPLIED round 5 — subsumed by LOOTBOX-12 (chunk loop now internal to the module)
- **LOOTBOX-12** — APPLIED round 5 (NHR adjudicated) — Game.resolveRedemptionLootbox → delegatecall(msg.data) thin stub; full body (auth → bound → stETH pull → pool credit → chunked resolution w/ identical rehash) in LootboxModule; per-chunk fn → private _resolveRedemptionChunk; Game 20,493 → 19,143 bytes (with GAME-08)
- **VAULT-01** — APPLIED round 5 — unreachable deposit() + _pullSteth + onlyGame + vault-scope Unauthorized deleted; header/diagram/natspec rewritten to what-IS; IVaultCoin.vaultEscrow decl trimmed (vault-only import)
- **VAULT-02** — APPLIED round 5 — write-only coinTracked + _syncCoinReserves deleted; burnCoin reads live vaultMintAllowance(); vault now has zero storage variables
- **VAULT-04** — APPLIED round 5 — dominated `claimable != 0` conjunct dropped in burnEth
- **VAULT-06** — APPLIED round 5 — _netClaimableWinnings() helper dedups the 1-wei-sentinel normalization; _ethReservesView composed from _syncEthReserves
- **VAULT-08** — APPLIED round 5 burnCoin leg ONLY (PARTIAL per skeptic; burnEth leg REJECTED) — DegenerusVaultShare.vaultBurn returns pre-burn supply; burnCoin burns first; burnEth sequence untouched
- **VAULT-13** — APPLIED round 5 — gameDegeneretteBet overpay guard deleted (game-side _collectBetFunds dominates); _combinedValue balance check retained
- **TOKENS-01** — APPLIED round 5 — levelResolved mapping + check + write + REJECT_LEVEL_ALREADY_RESOLVED deleted (currentLevel monotonicity = idempotence); −22.1k per level transition in the advance chain; GNRUS layout shifted (hasVoted→slot 3)
- **TOKENS-02** — APPLIED round 5 — unreachable cap-checks + _futureBitmapAfter + CapExceeded deleted (20-bit structural domain)
- **TOKENS-05** — APPLIED round 5 — observationally-redundant pendingEdit zero-writes removed (cancel branch + flush loop); ceiling-vs-net resolved for the worst-case ceiling
- **TOKENS-06** — APPLIED round 5 — burn() writes cached `burnerBal - amount` (checked; freshness proven across the claim call)
- **TOKENS-08** — APPLIED round 5 sub-changes (b)+(c) ONLY (PARTIAL per skeptic; (a) omitted — never trade worst-case for typical in the advance chain) — flush phase incl. both packed writes gated on pSet != 0; running masks in both pickCharity loops

## Open, non-rejected (93 after round 5)

| id | verdict | category | freq | file | est. save |
|---|---|---|---|---|---|
| RT-PACKING-08 | APPROVED | storage_packing | hot | BurnieCoinflip.sol | Daily resolution: ~15,000/day average (zero-to-nonzero only  |
| ADMIN-05 | APPROVED | idiom | warm | DegenerusAdmin.sol | ~1500-2500 per LINK donation (external self-call frame + ABI |
| ADMIN-06 | APPROVED | redundant_external_call | warm | DegenerusAdmin.sol | ~3000-5000 per donation while no feed is configured (cold st |
| ADMIN-09 | APPROVED | storage_packing | cold | DegenerusAdmin.sol | ~22100 per first-time voter per proposal (one cold SLOAD ~21 |
| ADMIN-10 | APPROVED | bytecode_dedup | cold | DegenerusAdmin.sol | ~100 per killed proposal in void loops (one keccak avoided); |
| DEITY-01 | APPROVED | other | cold | DegenerusDeityPass.sol | 0 on-chain (tokenURI has zero production on-chain callers —  |
| JACKPOTS-06 | APPROVED | bytecode_dedup | cold | DegenerusJackpots.sol | ~0 (a few gas of loop overhead per resolution; negligible) |
| JACKPOTS-09 | APPROVED | idiom | hot | DegenerusJackpots.sol | ~200-3000 per leaderboard-climbing flip settle (one SSTORE + |
| JACKPOTS-11 | APPROVED | redundant_check | hot | DegenerusJackpots.sol | ~25-40 per recordBafFlip (one address compare + short-circui |
| RT-CLAIMS-13 | APPROVED | bytecode_dedup | warm | DegenerusJackpots.sol | 0 (or ~-50 per resolution from the extra internal call) |
| STONK-02 | APPROVED | redundant_check | cold | DegenerusStonk.sol | ~2700 on first call in tx (cold GAME account moves to the ga |
| STONK-03 | APPROVED | dead_code | cold | DegenerusStonk.sol | ~20-30 per post-gameOver burn-through (dead JUMPI + zero-che |
| STONK-04 | APPROVED | bytecode_dedup | warm | DegenerusStonk.sol | ~0 (internal jump overhead ~20 gas added, negligible) |
| LIBS-03 | APPROVED | idiom | warm | libraries/EntropyLib.sol | ~30-60 gas per call site execution (skips free-memory-pointe |
| LIBS-04 | APPROVED | idiom | warm | libraries/EntropyLib.sol | ~40-70 gas per loop iteration (one iteration per 5 ETH of re |
| LIBS-01 | APPROVED | bytecode_dedup | hot | libraries/PriceLookupLib.sol | Levels >=100 (the long-run regime, called per purchase/quote |
| LIBS-02 | APPROVED | idiom | hot | libraries/PriceLookupLib.sol | ~10-20 gas/call vs the branch chain (DIV+SHR+AND+MUL ≈ 4 ops |
| SMALLMODS-03 | APPROVED | loop | warm | modules/DegenerusGameBingoModule.sol | ~50-70 gas/iteration x 7 redundant iterations ≈ 350-500 per  |
| SMALLMODS-05 | APPROVED | redundant_sload | warm | modules/DegenerusGameBingoModule.sol | ~150-250 per quadrant-first/symbol-first claim (1-2 warm SLO |
| SMALLMODS-08 | APPROVED | redundant_check | warm | modules/DegenerusGameBingoModule.sol | ~10 per claimAffiliateDgnrs with an explicit player arg |
| SMALLMODS-09 | APPROVED | dead_code | cold | modules/DegenerusGameBingoModule.sol | 0 |
| SMALLMODS-17 | APPROVED | idiom | warm | modules/DegenerusGameBingoModule.sol | ~150-400 per claimBingo (skips uint32[8] calldata->stack->me |
| DEGENERETTE-02 | APPROVED | bytecode_dedup | hot | modules/DegenerusGameDegeneretteModule.sol | ~0 (one extra internal JUMP); value is consistency with the  |
| DEGENERETTE-05 | APPROVED | redundant_sload | hot | modules/DegenerusGameDegeneretteModule.sol | ~100 gas per resolveBets call that produces no ETH pool-touc |
| DEGENERETTE-10 | APPROVED | idiom | hot | modules/DegenerusGameDegeneretteModule.sol | ~20-40 gas per placement (2-3 duplicate comparisons + a call |
| RT-CLAIMS-11 | APPROVED | idiom | hot | modules/DegenerusGameDegeneretteModule.sol | ~100-120 gas per degenerette bet placement (plus equal savin |
| RT-CLAIMS-14 | APPROVED | redundant_sload | hot | modules/DegenerusGameDegeneretteModule.sol | ~100 gas per ETH degenerette bet placement (0 for BURNIE/WWX |
| MINT-12 | APPROVED | redundant_check | cold | modules/DegenerusGameMintStreakUtils.sol | ~600-1000 per salvage swap (1 warm SLOAD + keccak + encodePa |
| MINT-15 | APPROVED | bytecode_dedup | cold | modules/DegenerusGameMintStreakUtils.sol | ~0 on-chain (marginally shallower selector search in 5 modul |
| RT-AFKING-WHALE-07 | APPROVED | redundant_sload | hot | modules/DegenerusGameMintStreakUtils.sol | ~97 per activity-score computation (warm SLOAD avoided) — fi |
| STONK-01 | APPROVED | redundant_external_call | cold | StakedDegenerusStonk.sol | ~200-600 per post-gameOver wrapped burn (1-2 warm staticcall |
| STONK-08 | APPROVED | redundant_sload | warm | StakedDegenerusStonk.sol | ~100-200 per claim (one duplicate warm SLOAD + field masking |
| STORAGE-03 | APPROVED | loop | warm | storage/DegenerusGameStorage.sol | ~200/iteration (2 warm SLOADs at 100 each, assuming the opti |
| RT-PACKING-02 | APPROVED | storage_packing | warm | storage/DegenerusGameStorage.sol | ~5,000/day on _applyDailyRng (one cold access + one SSTORE o |
| RT-PACKING-03 | APPROVED | storage_packing | warm | storage/DegenerusGameStorage.sol | ~4,200 per boon grant (one cold SLOAD + one cold SSTORE acce |
| RT-PACKING-04 | APPROVED | storage_packing | warm | storage/DegenerusGameStorage.sol | ~2,100 per claimBingo (one cold SLOAD removed); ~21,200 extr |
| RT-PACKING-05 | APPROVED | storage_packing | warm | storage/DegenerusGameStorage.sol | ~2,100 per whale-pass/deity purchase (reserved check: 2 cold |
| RT-PACKING-06 | APPROVED | storage_packing | warm | storage/DegenerusGameStorage.sol | ~2,100 per decimator claim (poolWei+totalBurn now one cold S |
| RT-IDIOMS-08 | APPROVED | loop | warm | storage/DegenerusGameStorage.sol | ~20,000 per 100-level whale bundle purchase (~200/iteration  |
| TOKENS-13 | APPROVED | redundant_check | warm | WrappedWrappedXRP.sol | ~25 per prize mint (lootbox WWXRP outcomes ~10% of opens, de |
| TOKENS-14 | APPROVED | dead_code | warm | WrappedWrappedXRP.sol | ~25 per COINFLIP-path mint (GAME-path mints short-circuit at |
| TOKENS-15 | APPROVED | redundant_check | cold | WrappedWrappedXRP.sol | ~25 per vaultMintTo (vault-owner admin mint, rare) |
| TOKENS-16 | APPROVED | redundant_check | cold | WrappedWrappedXRP.sol | ~15 per vaultMintTo (rare admin path) |
| TOKENS-19 | APPROVED | event | warm | WrappedWrappedXRP.sol | ~1,800 per non-infinite-allowance transferFrom |
| TOKENS-21 | APPROVED | redundant_check | warm | WrappedWrappedXRP.sol | ~22 per WWXRP game-bet burn (modules/DegenerusGameDegenerett |
| RT-COINFLIP-10 | NEEDS_HUMAN_REVIEW | dead_code | hot | BurnieCoin.sol | ~15-20 per third-party transferFrom (one PUSH20+EQ+JUMPI) |
| BURNIE-10 | NEEDS_HUMAN_REVIEW | loop | hot | BurnieCoinflip.sol | ~50 per loop iteration if the compiler hoists the invariant  |
| BURNIE-16 | NEEDS_HUMAN_REVIEW | unused_function | cold | BurnieCoinflip.sol | ~22 dispatcher comparison per call to later selectors (negli |
| AFFILIATE-11 | NEEDS_HUMAN_REVIEW | unused_function | cold | DegenerusAffiliate.sol | 0 (also shortens the function-selector dispatch chain by one |
| AFFILIATE-12 | NEEDS_HUMAN_REVIEW | unused_function | cold | DegenerusAffiliate.sol | 0 |
| JACKPOTS-10 | NEEDS_HUMAN_REVIEW | idiom | warm | DegenerusJackpots.sol | ~5-10 per iteration across ~60 iterations per BAF resolution |
| QUESTS-05 | NEEDS_HUMAN_REVIEW | redundant_sload | hot | DegenerusQuests.sol | ~400-600 on the first action of each day per player (3-5 RMW |
| QUESTS-06 | NEEDS_HUMAN_REVIEW | redundant_sload | warm | DegenerusQuests.sol | ~400-600 per quest completion (at most 2/day/player, inside  |
| RT-QUESTS-AFFILIATE-05 | NEEDS_HUMAN_REVIEW | idiom | hot | DegenerusQuests.sol | ~500-1,500 per completing quest action, ~200-600 per non-com |
| STONK-05 | NEEDS_HUMAN_REVIEW | event | hot | DegenerusStonk.sol | ~1700 per finite-allowance transferFrom (LOG3 = 375 base + 3 |
| JACKPOTMOD-14 | NEEDS_HUMAN_REVIEW | dead_code | warm | libraries/JackpotBucketLib.sol | ~20-40 per daily jackpot sizing call (a few comparisons), po |
| JACKPOTMOD-15 | NEEDS_HUMAN_REVIEW | dead_code | warm | libraries/JackpotBucketLib.sol | ~30-60 in the over-cap corner case only |
| ADVANCE-13 | NEEDS_HUMAN_REVIEW | other | cold | modules/DegenerusGameAdvanceModule.sol | ~10-20 gas per level transition (stack plumbing) |
| RT-ADVANCE-10 | NEEDS_HUMAN_REVIEW | redundant_external_call | warm | modules/DegenerusGameAdvanceModule.sol | ~2,000-3,000 per purchase-phase day: one delegatecall round- |
| WHALEBOON-16 | NEEDS_HUMAN_REVIEW | other | hot | modules/DegenerusGameBoonModule.sol | ~2700-3500 per boonless flip resolution (cold module account |
| DEGENERETTE-03 | NEEDS_HUMAN_REVIEW | redundant_sload | hot | modules/DegenerusGameDegeneretteModule.sol | ~100 gas per ETH or BURNIE bet placement (one warm SLOAD eli |
| SMALLMODS-16 | NEEDS_HUMAN_REVIEW | bytecode_dedup | cold | modules/DegenerusGameGameOverModule.sol | ~2,000-4,000 once at game over (drops one CALL + Game dispat |
| RT-MINT-02 | NEEDS_HUMAN_REVIEW | redundant_external_call | hot | modules/DegenerusGameMintModule.sol | ~7,500-8,500 per fresh-ETH ticket purchase (6,700 net value- |
| RT-MINT-06 | NEEDS_HUMAN_REVIEW | redundant_external_call | hot | modules/DegenerusGameMintModule.sol | ~1,500-3,000 per merged pair with per-leg events preserved ( |
| RT-IDIOMS-06 | NEEDS_HUMAN_REVIEW | redundant_external_call | hot | modules/DegenerusGameMintModule.sol | ~8,000-11,000 per ETH-funded ticket purchase (≈6,700-9,000 n |
| WHALEBOON-06 | NEEDS_HUMAN_REVIEW | redundant_external_call | warm | modules/DegenerusGameWhaleModule.sol | ~1.3k-1.8k per bundle beyond the first (2 warm external call |
| RT-AFKING-WHALE-08 | NEEDS_HUMAN_REVIEW | loop | warm | modules/DegenerusGameWhaleModule.sol | ~170k-190k per whale-bundle purchase (~100 x (event ~1640 +  |
| RT-PACKING-12 | NEEDS_HUMAN_REVIEW | storage_packing | warm | StakedDegenerusStonk.sol | ~4,200 per gambling-burn submit (two cold slot accesses remo |
| STORAGE-10 | NEEDS_HUMAN_REVIEW | event | warm | storage/DegenerusGameStorage.sol | 375 per credit (many credits per day across jackpot/lootbox/ |
| STORAGE-11 | NEEDS_HUMAN_REVIEW | storage_packing | warm | storage/DegenerusGameStorage.sol | ~2,100 per claimBingo read pair + ~2,100-17,100 on the write |
| STORAGE-12 | NEEDS_HUMAN_REVIEW | storage_packing | warm | storage/DegenerusGameStorage.sol | ~2,100 per boon-grant access pair + ~2,900-5,000 saved on th |
| STORAGE-13 | NEEDS_HUMAN_REVIEW | storage_packing | warm | storage/DegenerusGameStorage.sol | ~2,100 per reserved-remainder read (WhaleModule paths) and p |
| DECIMATOR-05 | NEEDS_HUMAN_REVIEW | storage_packing | warm | storage/DegenerusGameStorage.sol | ~22,100 per decimator snapshot (one fewer cold 0->nonzero SS |
| RT-ADVANCE-12 | NEEDS_HUMAN_REVIEW | storage_packing | cold | storage/DegenerusGameStorage.sol | ~20,000-22,000 once per decimator level (one zero→nonzero SS |
| BURNIE-08 | PARTIAL | redundant_sload | hot | BurnieCoinflip.sol | ~100 per deposit (1 warm SLOAD) on the non-auto-rebuy path;  |
| RT-PACKING-09 | PARTIAL | storage_packing | hot | BurnieCoinflip.sol | ~8,500/day average for a daily flipper on the stake write (z |
| AFFILIATE-08 | PARTIAL | redundant_sload | warm | DegenerusAffiliate.sol | ~100 gas per referral registration (warm re-SLOAD of affilia |
| SMALLMODS-02 | PARTIAL | dead_code | cold | DegenerusTraitUtils.sol | 0 |
| LIBS-06 | PARTIAL | idiom | hot | libraries/BitPackingLib.sol | ~6-12 gas per fused field beyond the first; ~30-50 gas per p |
| ADVANCE-06 | PARTIAL | redundant_sload | warm | modules/DegenerusGameAdvanceModule.sol | ~800-900 gas per call (4 avoided warm SLOADs ~400 + 2 avoide |
| ADVANCE-10 | PARTIAL | bytecode_dedup | warm | modules/DegenerusGameAdvanceModule.sol | 0 (runtime-neutral, +1 internal jump) |
| ADVANCE-20 | PARTIAL | redundant_sload | warm | modules/DegenerusGameAdvanceModule.sol | ~150-400 gas per completing daily advance (assumes via_ir do |
| RT-ADVANCE-06 | PARTIAL | redundant_external_call | warm | modules/DegenerusGameAdvanceModule.sol | Option (a): ~200-300 per empty probe = ~800-1,200/day. Optio |
| LOOTBOX-09 | PARTIAL | other | warm | modules/DegenerusGameLootboxModule.sol | ~100-200 per openBoxes call (one merged SSTORE; ~200 more on |
| LOOTBOX-10 | PARTIAL | other | warm | modules/DegenerusGameLootboxModule.sol | ~400-800 per box resolution (assumes ~20-30 gas per eliminat |
| LOOTBOX-14 | PARTIAL | idiom | warm | modules/DegenerusGameLootboxModule.sol | ~20-40 per box resolution combined |
| RT-CLAIMS-04 | PARTIAL | redundant_sload | warm | modules/DegenerusGameLootboxModule.sol | ~200-400 gas per opened box in the daily sweep (2-4 warm SLO |
| RT-AFKING-WHALE-16 | PARTIAL | redundant_sload | warm | modules/DegenerusGameMintStreakUtils.sol | ~100-150 per applied curse stack (warm SLOAD + dominated com |
| RT-AFKING-WHALE-10 | PARTIAL | loop | warm | modules/DegenerusGameWhaleModule.sol | ~300 x (quantity-1) for the reserved hoist alone; ~1.1-1.3k  |
| RT-AFKING-WHALE-05 | PARTIAL | idiom | warm | modules/GameAfkingModule.sol | Up to ~800-1500 per funded subscriber per day if the compile |
| STONK-13 | PARTIAL | bytecode_dedup | warm | StakedDegenerusStonk.sol | ~-30 (adds an internal jump per call site; runtime-neutral) |
| RT-PACKING-13 | PARTIAL | storage_packing | warm | StakedDegenerusStonk.sol | ~2,000 per two-pool transaction (second pool's cold slot acc |
| RT-PACKING-01 | PARTIAL | storage_packing | hot | storage/DegenerusGameStorage.sol | ~17,100 per active lootbox player per level (first bonus-box |
