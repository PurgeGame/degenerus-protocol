# Degenerus Protocol — Access Control Matrix

**Refreshed:** v74.0 As-Built Milestone Audit (frozen `contracts/` tree `f06b1ef6` @ impl `93d17288`).
**Scope:** every in-scope contract's external/public state-changing function + its guard. View/pure
functions are omitted unless load-bearing. Tokens renamed vs the v55-era matrix: BurnieCoin → FLIP,
BurnieCoinflip → Coinflip, StakedDegenerusStonk → sDGNRS, DegenerusStonk → DGNRS, WrappedWrappedXRP →
WWXRP; `EndgameModule` removed; the standalone `DegenerusVaultShare` is now the vault-internal
DGVE/DGVF share classes. New surfaces (permissionless settlement / caller-funded gifts, the sDGNRS
level-start lootbox, and the gas faucet) are folded in.

---

## Summary

| Guard type | Pattern |
|-----------|---------|
| Compile-time constant (`ContractAddresses.*`) | Immutable caller addresses; no admin override, no re-pointing, no proxy |
| `onlyVaultOwner` ( > 50.1% DGVE supply) | Vault ETH/stETH ops, feed, lootbox-RNG threshold, vault's own proxy actions, gas-faucet admin |
| sDGNRS governance | VRF-coordinator / price-feed swap, death-clock gated, decaying vote |
| Permissionless — harvest-inward settlement | Credits the resolved owner only; caller cannot redirect value |
| Permissionless — caller-funded gift | Spend sourced from `msg.sender` (funder); position credited to the player |
| Permissionless — self/owner/operator spend | Cashout/spend requires self, owner, or `operatorApprovals` consent |
| Conditional (`gameOver`, `rngLocked`, liveness, stall) | State-dependent gates |

**Key property:** ALL cross-contract authority is a compile-time constant set via
`ContractAddresses.*`. Zero configurable admin addresses, zero proxy upgrade paths, zero address
re-pointing. The only "roles" are token-balance-derived (vault owner = DGVE majority; governance =
sDGNRS holders) — see `SECURITY.md`.

---

## 1. DegenerusGame (router)

All game-module logic is dispatched via delegatecall; access control is enforced at the router. The
permissionless settlement/gift functions take an explicit player/affiliate address and resolve
consent internally (see the boundary note at the end).

| Function | Visibility | Guard | Guard type |
|----------|-----------|-------|------------|
| `receive()` | external payable | none | Permissionless (accepts ETH; pending-routes under freeze) |
| `advanceGame()` | external | none | Permissionless (public-good crank, bounty) |
| `purchase(...)` | external payable | none | Permissionless (requires msg.value) |
| `purchaseWhalePass(...)` | external payable | none | Permissionless (requires msg.value) |
| `purchaseLazyPass(address)` | external payable | none | Permissionless |
| `purchaseDeityPass(address, uint8)` | external payable | none | Permissionless |
| `placeDegeneretteBet(...)` | external payable | self/operator or caller-funded gift | Spend = funder; position = player; WWXRP gift-excluded |
| `resolveDegeneretteBets(address, uint64[])` | external | none | Permissionless settlement (credits the player) |
| `claimWinnings(address)` / `claimWinnings(address, uint256)` | external | self/operator (cashout to owner) | Settles to the player only |
| `claimWinningsStethFirst()` | external | self | Settles to msg.sender |
| `claimDecimatorJackpot(address, uint24)` | external | none | Harvest-inward (credits the player) |
| `claimTerminalDecimatorJackpot()` | external | self | Claims own |
| `claimWhalePass(address)` | external | none | Harvest-inward (credits the resolved owner) |
| `claimBingo(address, uint24, uint8, uint32[8])` | external | sender-or-operator | Player-keyed dedup; credits the player |
| `claimAffiliateDgnrs(address)` / `(address[])` | external | none | Harvest-inward (credits the affiliate; batch try/catch-isolated) |
| `openBox(address, uint48)` | external | none | Harvest-inward (credits the box owner) |
| `openBoxes(uint256)` | external | none | Permissionless auto-opener (credits each owner) |
| `requestLootboxRng()` | external | none | Permissionless (requires pending lootbox; MidDayActive/RngInFlight gated) |
| `reverseFlip()` | external | none | Permissionless (requires active ticket) |
| `depositAfkingFunding(address)` | external payable | none | Caller-funded (credits the player's afking funding) |
| `withdrawAfkingFunding(uint256)` | external | self | Withdraws own afking funding |
| `decurse(address)` / `smite(uint256, address)` | external | game-internal rules | Curse mechanics (pool-neutral) |
| `setOperatorApproval(address, bool)` | external | none | Sets own approvals (the consent boundary) |
| `setLootboxRngThreshold(uint256)` | external | VAULT only | `msg.sender == VAULT` (else `ZeroValue` on 0) |
| `wireVrf(address, uint256, bytes32)` | external | ADMIN only | One-time VRF wiring |
| `mintFlip()` | external | none | Permissionless (advance/open-leg crank) |
| `claimAfkingFlip(address[])` | external | none | Harvest-inward |
| `drainAffiliateBase(address)` | external | AFFILIATE only | Cross-contract |
| `recordAfkingSecondary(address, uint16)` / `floorAfkingStreakBase(address, uint16)` | external | QUESTS/coin only | Cross-contract |
| `creditRedemptionDirect(address, uint256)` / `pullRedemptionReserve(uint256)` | external payable/ext | sDGNRS only | `msg.sender == SDGNRS` |
| `resolveRedemptionLootbox(...)` | external payable | sDGNRS only | `msg.sender == SDGNRS` |
| `adminStakeEthForStEth(uint256)` | external | ADMIN/VAULT only | Cross-contract staking |
| `boostTerminalDecimator()` | external | none | Permissionless terminal mechanic |
| `initPerpetualTickets()` | external | VAULT/SDGNRS only | Once, at construction |

### Game modules (12, all delegatecalled)

Modules have no independent access control — they execute in `DegenerusGame`'s storage via delegatecall
and are reached only through the router. `OnlyDelegatecall` / `OnlySelf` guards prevent direct calls.
Modules: Mint, Advance, Whale, Jackpot, Decimator, GameOver, Lootbox, Boon, Degenerette, Bingo,
GameAfking, FoilPack. The **sDGNRS level-start lootbox** lives in `GameAfkingModule` and fires inside
`_runSubscriberStage` during the advance (pre-RNG), once per level (`currentLevel > _sdgnrsBonusLevel`)
— not a directly-callable surface.

---

## 2. FLIP (formerly BurnieCoin)

| Function | Visibility | Guard |
|----------|-----------|-------|
| `transfer` / `approve` | external | none (standard ERC-20; transfer-to-VAULT burns; transfer may auto-claim coinflip) |
| `transferFrom` | external | none (GAME bypasses allowance — trusted-contract pattern) |
| `burnForCoinflip(address, uint256)` | external | COINFLIP only |
| `mintForGame(address, uint256)` | external | GAME only |
| `vaultEscrow(uint256)` / `vaultMintTo(address, uint256)` | external | VAULT only |
| `burnCoin` / `burnCoinForSalvage(address, uint256)` | external | GAME only |
| `decimatorBurn` / `terminalDecimatorBurn(address, uint256)` | external | GAME only |
| `tombstoneAtGameOver()` | external | game-over conditional |

---

## 3. Coinflip (formerly BurnieCoinflip)

| Function | Visibility | Guard |
|----------|-----------|-------|
| `depositCoinflip(address player, uint256)` | external | **self/operator OR caller-funded gift** — funder = `msg.sender` on the gift branch; stake credited to `player`; `directDeposit=false` suppresses biggestFlip/bounty on gift/operator deposits |
| `claimCoinflips(address, uint256)` | external | self/operator (settles to player) |
| `redeemableFlipBacking()` / `withdrawRedeemedFlip(uint256)` | external | self (own salvage backing) |
| `getCoinflipDayResult` / `previewClaimCoinflips` / `coinflipAmount` | external view | none |

---

## 4. sDGNRS (soulbound; formerly StakedDegenerusStonk)

| Function | Visibility | Guard |
|----------|-----------|-------|
| `depositSteth` / `transferFromPool` / `transferBetweenPools` / `burnAtGameOver` / `resolveRedemptionPeriod` | external | GAME only (`onlyGame`) |
| `wrapperTransferTo(address, uint256)` | external | DGNRS only |
| `burn` / `burnWrapped(uint256)` | external | none (burns own; proportional ETH/stETH/FLIP payout) |
| `claimRedemption(address, uint24)` / `claimRedemptionMany(address[], uint24)` | external | none (harvest-inward settlement to the beneficiary; delete-before-pay, no double-claim) |
| `resolveRedemptionPeriod(uint16, uint24)` | external | GAME only |
| `gameAdvance()` / `gameClaimWhalePass()` / `gameClaimBingo(...)` | external | none (proxy cranks crediting `address(this)`) |
| `transfer` | external | reverts (soulbound) |

---

## 5. DGNRS (transferable wrapper; formerly DegenerusStonk)

| Function | Visibility | Guard |
|----------|-----------|-------|
| `transfer` / `approve` / `transferFrom` | external | none (standard ERC-20; transfer to self-address reverts `Unauthorized`) |
| `burn(uint256)` | external | none (burns own → proportional sDGNRS backing) |
| `burnForSdgnrs(address, uint256)` | external | sDGNRS only |
| `unwrapTo(address, uint256)` | external | CREATOR only |
| `claimVested()` | external | none (creator vesting schedule) |
| `yearSweep()` | external | conditional (annual backstop) |

---

## 6. DegenerusVault (deploys DGVE + DGVF share ERC-20s internally)

| Function | Visibility | Guard |
|----------|-----------|-------|
| `deposit()` (interface) | external payable | GAME only |
| `burnCoin(uint256)` / `burnEth(uint256)` | external | self (shareholder burns own DGVF/DGVE) |
| `vaultMint` / `vaultBurn` (on the DGVE/DGVF tokens) | external | VAULT only |
| `setLinkPriceFeed` / `swapEthForStEth` / `stakeEthToStEth` / `setLootboxRngThreshold` | external | `onlyVaultOwner` ( > 50.1% DGVE) |
| `gameAdvance` / `gamePurchaseTicketsFlip` / `gamePurchaseDeityPassFromBoon` / `gameClaimWinnings` / `gameClaimWhalePass` / `gameClaimBingo` / `gameResolveDegeneretteBets` / `gameSetOperatorApproval` | external | `onlyVaultOwner` (vault acts as itself) |
| `coinDepositCoinflip` / `coinClaimCoinflips` / `coinDecimatorBurn` / `coinSetAutoRebuy*` | external | `onlyVaultOwner` |
| `wwxrpMint` / `sdgnrsBurn` / `sdgnrsClaimRedemption` | external | `onlyVaultOwner` |
| `setSalvageBuyFallback(bool, uint256)` | external | `onlyVaultOwner` |
| `recoverAfkingFunding()` | external | conditional (post-gameover recovery) |
| `isVaultOwner(address)` | external view | none (the role oracle: `balance*1000 > supply*501` of DGVE) |
| `transfer` / `approve` / `transferFrom` (DGVE/DGVF) | external | DGVF soulbound; DGVE standard ERC-20 |

---

## 7. DegenerusAdmin (VRF + price-feed governance)

| Function | Visibility | Guard |
|----------|-----------|-------|
| `receive()` | external payable | none (best-effort forward to VAULT; **never reverts** — assembly `pop(call)`) |
| `propose(address, bytes32)` | external | vault-owner (44h VRF stall) OR 0.5% sDGNRS (community stall) |
| `vote(uint256, bool)` | external | any sDGNRS holder; **auto-kills on VRF recovery** (`stall < 44h` OR `lastVrfProcessed > createdAt`) |
| `canExecute(uint256)` | external view | mirrors `vote` (stall + recovery-spanning invalidation) |
| `proposeFeedSwap(address)` / `voteFeedSwap(uint256, bool)` | external | feed-unhealthy gated (2d admin / 7d community) + sDGNRS vote |
| `setLinkEthPriceFeed` / `swapGameEthForStEth` / `stakeGameEthToStEth` / `setLootboxRngThreshold` | external | `onlyOwner` (vault-owner) + broken-feed gate where applicable |
| `shutdownVrf()` | external | GAME only |
| `onTokenTransfer(...)` | external | LINK token only (ERC-677) |

`ADMIN_STALL_THRESHOLD = 44 hours`; `PROPOSAL_LIFETIME = 168 hours`; threshold decays 50%→5%.

---

## 8. WWXRP (formerly WrappedWrappedXRP)

| Function | Visibility | Guard |
|----------|-----------|-------|
| `mintPrize(address, uint256)` | external | authorized minters (GAME/COIN/COINFLIP/VAULT) |
| `vaultMintTo(address, uint256)` | external | VAULT only |
| `burnForGame(address, uint256)` | external | GAME only |
| `wrap` / `unwrap` / `donate` / `burn` | external | none (unwrap is first-come-first-served vs reserves) |
| `transfer` / `approve` / `transferFrom` | external | none (standard ERC-20) |

---

## 9. DegenerusDeityPass (ERC-721)

| Function | Visibility | Guard |
|----------|-----------|-------|
| `mint(address, uint256)` | external | GAME only |
| `setRenderer(address)` | external | `onlyOwner` (metadata, non-fund-bearing) |
| `transferFrom` / `safeTransferFrom` / `approve` / `setApprovalForAll` | external | none (standard ERC-721) |

---

## 10. DegenerusAffiliate

| Function | Visibility | Guard |
|----------|-----------|-------|
| `createAffiliateCode(bytes32, uint8)` | external | none (self-referral blocked) |
| `referPlayer(bytes32)` | external | none |
| `creditFlip(address, uint256)` | external | COIN/GAME only |
| `drainAffiliateBase(address)` | external | GAME only |
| `claim(address[])` | external | none (harvest-inward; mints A/U1/U2 directly) |

`payAffiliateCombined` (the folded buy-path roll) returns `winnerCredit` to its MintModule caller and
is module-internal; it emits one `AffiliateEarningsRecorded` (no legacy `Affiliate(...)` on the buy
path — see KNOWN-ISSUES §6).

---

## 11. DegenerusQuests

| Function | Visibility | Guard |
|----------|-----------|-------|
| `rollLevelQuest(uint256)` | external | GAME only (`onlyGame`) |
| `awardQuestStreakBonus(address, uint16, uint24)` / `awardQuestStreakShield(address, uint16)` | external | GAME only |
| `handleMint` / `handleFlip` / `handleDecimator` / `handleAffiliate` / `handleLootBox` / `handleDegenerette` | external | COIN/COINFLIP only (`onlyCoin`) |

---

## 12. DegenerusJackpots

| Function | Visibility | Guard |
|----------|-----------|-------|
| `recordBafFlip(address, uint24, uint256)` | external | COIN/COINFLIP only |
| `runBafJackpot(...)` | external | GAME only |
| `markBafSkipped(uint24)` | external | GAME only |

---

## 13. GNRUS (soulbound charity token)

| Function | Visibility | Guard |
|----------|-----------|-------|
| `burn(uint256)` | external | none (burns own) |
| `burnAtGameOver()` | external | GAME only |
| `pickCharity(uint24)` | external | GAME only |
| `setCharity(uint8, address)` / `vote(uint8)` | external | sDGNRS-governed charity slots |

---

## 14. DegenerusGasFaucet (dormant / unwired, in-scope)

| Function | Visibility | Guard |
|----------|-----------|-------|
| `receive()` | external payable | none (donations; sole inflow) |
| `distribute(address[])` | external | `onlyDistributor` (`approvedDistributor` OR vault owner); per-recipient `affiliateScore >= minAffiliateScore`; CEI + 2300-gas cap |
| `setApprovedDistributor(address, bool)` / `setParams(...)` | external | `onlyVaultOwner` |
| `withdraw(address, uint256)` | external | `onlyVaultOwner` (full-gas to a chosen sink — documented trust boundary) |

No mint/burn/ledger; no protocol-state writes; custodies only donated ETH.

---

## 15. Read-only / library contracts

`DeityBoonViewer` (read-only boon lens, no value custody, not wired into deploy), `Icons32Data`
(on-chain SVG view data), `DegenerusTraitUtils` + the 6 `libraries/*` + `ContractAddresses` (all
`internal`/`pure`/`view`, execute in the caller's context, no external state-changers).

---

## Access-control architecture (design principles)

1. **Compile-time constants.** Every privileged caller address is a `ContractAddresses.*` constant set
   at compile time. No runtime configuration, no setters, no admin re-pointing.
2. **No upgradeability.** No proxy / UUPS / transparent / diamond logic upgrade. Code is immutable
   after deployment.
3. **Minimal privilege.** Each contract exposes only what its callers need; the game router is the
   orchestrator, standalone contracts have narrow interfaces.
4. **Permissionless settlement, gated cashout (locked ruling).** Claims/settlements credit the
   rightful owner; caller-funded gifts spend only from the funder; moving value *out* to a chosen
   address or spending a non-consenting balance requires self / owner / operator approval.
   `setOperatorApproval` is the consent boundary. (See `SECURITY.md`.)
5. **Governance limited scope.** sDGNRS governance can ONLY swap the VRF coordinator / price feed,
   behind a death-clock + decaying-threshold vote + kill-on-recovery. It cannot modify game logic,
   move funds, or change access control.

---

*Refreshed for the v74.0 frozen subject (`f06b1ef6` @ `93d17288`). Function signatures verified against
the in-scope sources; tokens/modules renamed and the permissionless/gift, sDGNRS level-lootbox, and
gas-faucet surfaces folded in.*
