// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/*
 * TERMS OF INTERACTION — submitting a transaction to this contract accepts them.
 *
 * THIS IS GAMBLING. Outcomes are decided by chance. You can lose everything you put in
 * simply by being unlucky. That is the software working exactly as intended. Do not
 * commit funds you are not prepared to lose entirely.
 *
 * The deployed bytecode is the entire agreement and the exclusive source of truth; any
 * comment, name, document or statement that disagrees with it is in error. It has been
 * audited but is not proven correct: it may contain defects the author did not find, and
 * by interacting with it you accept that risk in full.
 *
 * Any state transition the code permits is authorised — including one that exploits a
 * defect, and including sequences the author did not intend or foresee. A bug is not a
 * breach of these terms. There is no unwritten rule behind the code for a permitted
 * transaction to violate, and no unauthorised access to this contract.
 *
 * You bear all resulting loss, whether it follows from chance or from a defect. There is
 * no refund, no rollback and no privileged party able to restore a position.
 *
 * Provided AS IS, without warranty of any kind. Full text: TERMS.md
 */

import {MintPaymentKind} from "./IDegenerusGame.sol";
import {MineFlipGas} from "../libraries/MineFlipGas.sol";
import {TicketWorkPlan} from "../libraries/JackpotTicketPlan.sol";

/// @dev Frozen daily ETH terms supplied only by the trusted Jackpot delegate dispatcher.
struct DecimatorJackpotTerms {
    uint256 word;
    uint256[4] shares;
    uint16[4] targets;
    uint8 solo;
}

interface IDegenerusGameTicketModule {
    function registerWallet(address owner, bool allocate) external returns (uint32 id);
    function runJackpotTicketAwards(TicketWorkPlan calldata plan, uint256 allowance)
        external returns (MineFlipGas.Result memory);
    function runTicketWork(uint24 anchor, uint256 gasAllowance) external returns (MineFlipGas.Result memory);
}

interface IDegenerusGameMinerModule {
    error NoWork();
    error RngNotReady();
    function mineFlip() external;
    function minerAction() external view returns (uint8);
}

interface IDegenerusGameRngModule {
    error PreResetWindow();
    error InsufficientLink();
    error NoPendingLootbox();
    error BelowThreshold();
    error GasTooHigh();
    function publishRng() external;
    function requestDailyRng(uint24 day) external;
    function requestMinerRng() external;
    function retryRng() external;
}

/// @title IDegenerusGameAdvanceModule
/// @notice Interface for the game advancement module handling VRF and game progression
interface IDegenerusGameAdvanceModule {
    function prepareRequestBoundary(uint24 day) external;
    function applyDailyWord() external;
    function applyDailyGap() external;
    function runDailyPhase(uint256 allowance) external returns (MineFlipGas.Result memory);
    function runTerminalPhase(uint256 allowance) external returns (MineFlipGas.Result memory);
    function setThanosLevel(uint24 targetLevel, uint8 shift) external;
}

/// @title IDegenerusGameGameOverModule
/// @notice Interface for handling game over state and final fund distribution,
///         plus the cold VRF admin surface (deploy wiring + emergency rotation)
///         hosted here for the advance module's EIP-170 headroom.
interface IDegenerusGameGameOverModule {
    function runGameOverAdvance(uint24 day, uint24 level, uint256 allowance)
        external returns (bool shouldReturn, uint8 stage, bool unlock, bool progressed);

    /// @notice Configures the Chainlink VRF coordinator and subscription
    /// @param coordinator_ Address of the VRF coordinator contract
    /// @param subId Chainlink VRF subscription ID
    /// @param keyHash_ Key hash for the VRF request
    function wireVrf(
        address coordinator_,
        uint256 subId,
        bytes32 keyHash_
    ) external;

    /// @notice Updates VRF coordinator, subscription, and key hash configuration
    /// @param newCoordinator New VRF coordinator address
    /// @param newSubId New subscription ID
    /// @param newKeyHash New key hash for VRF requests
    function updateVrfCoordinatorAndSub(
        address newCoordinator,
        uint256 newSubId,
        bytes32 newKeyHash
    ) external;

    /// @notice Claim deterministic-ending shares for account `id`'s terminal-level tickets.
    /// @dev Raw msg.data target of Game.claimDeadVrf (identical selector). Permissionless;
    ///      credits the account by ID.
    /// @param id Owner of every referenced holding (0 = caller; otherwise allocated, else E).
    /// @param refs Holdings to claim (see DegenerusGameGameOverModule.claimDeadVrf).
    function claimDeadVrf(uint32 id, uint256[] calldata refs) external;
}

/// @title IDegenerusGameJackpotModule
/// @notice Interface for managing various jackpot distributions
interface IDegenerusGameJackpotDrawModule {
    function awardDailyFlipJackpot(uint24 minLevel, uint24 maxLevel, uint32 traits, uint256 budget, uint256 word) external;
    function runPurchaseJackpotBattle(uint24 lvl, uint256 word, uint256 allowance)
        external returns (MineFlipGas.Result memory);
    function runBafAwards(uint256 word, uint256 allowance) external returns (MineFlipGas.Result memory);
}

interface IDegenerusGameJackpotModule {
    function runPurchaseJackpotBattle(uint24 lvl, uint256 word, uint256 allowance)
        external returns (MineFlipGas.Result memory);
    function runBafAwards(uint256 word, uint256 allowance) external returns (MineFlipGas.Result memory);
    function runDailyJackpot(bool inJackpot, uint24 lvl, uint256 word, uint256 allowance)
        external returns (MineFlipGas.Result memory);
    function runPurchaseDailyTickets(uint256 word, uint256 allowance) external returns (MineFlipGas.Result memory);
    function runEarlyBirdTickets(uint256 word, uint256 allowance) external returns (MineFlipGas.Result memory);
    function runDailyJackpotTickets(uint256 word, uint256 allowance) external returns (MineFlipGas.Result memory);

    /// @notice Pay the golden-ticket grand to a foil pack holding two all-gold tickets.
    /// @dev Delegatecall-only; pushed by the foil drain (_pushFoilGrand) when a pack
    ///      files with two or more all-gold tickets. Not reachable from claimGoldenTicket.
    /// @param winner The foil buyer whose pack rolled the two all-gold tickets.
    /// @param lvl The pack's cycle level.
    /// @param golds The pack's total gold quadrants across its four tickets (8..16).
    function payGoldenTicketGrand(
        uint32 winner,
        uint24 lvl,
        uint8 golds
    ) external;

    /// @notice Pays level 1's trait-matched FLIP draw on the day's main board
    /// @param lvl Level keying the prize pool snapshot for the budget
    /// @param randWord Random word for the board and winner selection
    /// @param minLevel Minimum target level for the coin distribution (inclusive)
    /// @param maxLevel Maximum target level for the coin distribution (inclusive)
    function payDailyFlipJackpot(uint24 lvl, uint256 randWord, uint24 minLevel, uint24 maxLevel) external;

    /// @notice Roll, record and emit level 1's purchase-day board without running distribution.
    /// @param randWord VRF entropy for the board.
    function emitDailyWinningTraits(uint256 randWord) external;

    /// @notice Execute BAF jackpot distribution.
    /// @param poolWei Total ETH pool for BAF.
    /// @param lvl Current level.
    /// @param rngWord VRF entropy.
    /// @return claimableDelta ETH reserved in claimablePool for the staged award schedule.
    function runBafJackpot(
        uint256 poolWei,
        uint24 lvl,
        uint256 rngWord
    ) external returns (uint256 claimableDelta);

    /// @notice Distribute yield surplus to stakeholders.
    /// @param rngWord Unused — the surplus split is deterministic. Carried only to keep the
    ///        delegatecall signature uniform with the other AdvanceModule entry points.
    function distributeYieldSurplus(uint256 rngWord) external;
}

/// @title IDegenerusGameDecimatorModule
/// @notice Interface for decimator jackpot tracking and resolution
interface IDegenerusGameDecimatorModule {
    function runDecimatorJackpotAwards(DecimatorJackpotTerms calldata terms, uint256 allowance)
        external returns (MineFlipGas.Result memory result, uint256 soloAmount);
    function runDecimatorWork(uint256 gasAllowance) external returns (MineFlipGas.Result memory);
    /// @notice Record a Decimator burn for jackpot eligibility.
    /// @param player Address of the player.
    /// @param lvl Resolution level (current game level + 1).
    /// @param baseAmount Burn amount before multiplier.
    /// @param multBps Multiplier in basis points (10000 = 1x).
    /// @param chips The entry's board: zero to seven named chips, as a normal battle takes them.
    /// @return entryId The wallet's accumulated battle entry.
    function recordDecBurn(
        address player,
        uint24 lvl,
        uint256 baseAmount,
        uint256 multBps,
        uint32 chips
    ) external returns (uint64 entryId);

    /// @notice Seal a Decimator battle for bounded run and payout settlement.
    /// @param poolWei Total ETH prize pool for this level.
    /// @param lvl Level number being resolved.
    /// @param rngWord VRF-derived randomness seed.
    /// @return returnAmountWei Amount to return (no entries or this round was already sealed).
    function runDecimatorJackpot(
        uint256 poolWei,
        uint24 lvl,
        uint256 rngWord
    ) external returns (uint256 returnAmountWei);
}

/// @title IDegenerusGameWhaleModule
/// @notice Interface for whale-tier purchases and premium passes
interface IDegenerusGameWhaleModule {
    /// @notice One-time creator-gated registration and ticket batch for both protocol deities.
    function initProtocolDeity() external;

    /// @notice Purchases a whale pass for the buyer
    /// @param buyer Address receiving the pass
    /// @param quantity Number of passes to purchase
    /// @param affiliateCode Affiliate/referral code for the purchase (bytes32(0) = stored code)
    function purchaseWhalePass(address buyer, uint256 quantity, bytes32 affiliateCode) external payable;

    /// @notice Purchases a 10-level lazy pass for the buyer
    /// @param buyer Address receiving the pass
    /// @param affiliateCode Affiliate/referral code for the purchase (bytes32(0) = stored code)
    function purchaseLazyPass(address buyer, bytes32 affiliateCode) external payable;

    /// @notice Purchases a deity pass for a specific symbol
    /// @param buyer Address receiving the deity pass
    /// @param symbolId Symbol index (0-31) to bind the pass to
    /// @param affiliateCode Affiliate/referral code for the purchase (bytes32(0) = stored code)
    function purchaseDeityPass(
        address buyer,
        uint8 symbolId,
        bytes32 affiliateCode
    ) external payable;

    /// @notice Claim deferred whale pass rewards for account `id`.
    /// @dev Raw msg.data target of Game.claimWhalePass (identical selector). Permissionless;
    ///      moves no value.
    /// @param id Account to claim for (0 = caller; otherwise allocated, else E).
    function claimWhalePass(uint32 id) external;

    /// @notice Awards early-bird or quadrant passes to one fresh recipient.
    /// @dev Nested delegatecall from JackpotModule against frozen GAME inventory: one
    ///      recipient from the bucket of `trait`, drawn with `randWord`. A ticket leg passes
    ///      half-pass units and moves no pools; an ETH quadrant passes its ETH allocation and
    ///      its pass cost credits future. Returns award value (zero for an empty draw).
    function awardWhalePass(
        uint24 lvl,
        uint8 trait,
        uint256 amount,
        uint256 randWord,
        bool ticketLeg
    ) external returns (uint256 spent);

    /// @notice sDGNRS's once-per-level automatic whale purchase (afking process STAGE only).
    /// @dev Delegatecall-only, nested from GameAfkingModule.runSubscriberWork; no facade
    ///      stub forwards it. Buys the largest whole group of five paid passes whose quote fits
    ///      a quarter of sDGNRS's claimable, or nothing (RNG lock / committed word / terminal /
    ///      full lootbox entry / below one group — all a zero return, never a revert; the STAGE
    ///      latches the level on the attempt either way).
    /// @param processDay The STAGE's boundary-pinned process day.
    /// @return paidPasses Paid passes bought (a multiple of five); 0 when nothing was bought.
    function purchaseWhalePassForSdgnrs(uint24 processDay) external returns (uint256 paidPasses);
}

/// @title IDegenerusGameMintModule
/// @notice Interface for minting operations and purchase processing
interface IDegenerusGameMintModule {
    /// @notice Quote a far-future salvage swap WITHOUT executing (read-only -EV offer).
    function previewSellFarFutureEntries(
        address player,
        uint32[] calldata levels,
        uint256[] calldata quantities
    )
        external
        view
        returns (
            uint256 totalFaceWei,
            uint256 totalBudget,
            uint256 ticketWei,
            uint256 ethCashWei,
            uint256 flipTokens
        );

    /// @notice Body of Game.createSmurf (raw msg.data target, identical selector; see
    ///         IDegenerusGame for the full contract). Owner = msg.sender (must hold an ID).
    /// @dev Resolves and locks the owner's referral from `affiliateCode` as a purchase does,
    ///      registers the smurf (`wallets.push(key | ownerId << 160)`, mint word = ID | smurf
    ///      flag, `WalletRegistered` + `SmurfCreated`), calls Affiliate `copyReferral(owner,
    ///      key)`, then buys one whole ticket for the smurf paid by the owner (payer ID threaded
    ///      through the payment path; fresh-ETH overpay to the owner's AFKing balance).
    /// @param affiliateCode Referral code applied to the owner if its referral is unset.
    /// @param payKind How the owner funds the ticket.
    /// @return smurfId The new account's wallet ID.
    function createSmurf(bytes32 affiliateCode, MintPaymentKind payKind)
        external payable returns (uint32 smurfId);

    /// @notice Processes a ticket and lootbox purchase
    /// @param buyer Address of the buyer
    /// @param entryQuantityScaled Ticket quantity in scaled entry units (400 = one whole ticket; 2 decimals, x100)
    /// @param boxOrder Packed box order (0 to skip): [small:8][med:8][large:8][customCount:8][customSize:56 gwei].
    /// @param affiliateCode Affiliate code for referral tracking
    /// @param payKind Payment method used for the purchase
    function purchase(
        address buyer,
        uint256 entryQuantityScaled,
        uint256 boxOrder,
        bytes32 affiliateCode,
        MintPaymentKind payKind
    ) external payable;

    /// @notice Explicit-ethValue ticket-buy entry: the fresh-ETH portion is the `ethValue`
    ///         param rather than msg.value. Callers: the foil purchase, funding the
    ///         ticket/lootbox leg with carved fresh ETH while the buyer's msg.value is in
    ///         flight (ignored — only ethValue is spent), and createSmurf's ticket. payable so
    ///         the carried value does not revert the delegatecall.
    /// @param payerId Ledger the claimable/AFKing legs debit: 0 = the buyer's own, else a
    ///        smurf's owner on its creation ticket.
    function purchaseWith(
        address buyer,
        uint256 entryQuantityScaled,
        uint256 boxOrder,
        bytes32 affiliateCode,
        MintPaymentKind payKind,
        uint256 ethValue,
        uint32 payerId
    ) external payable;

    /// @notice Processes a FLIP purchase of tickets. Raw msg.data target of Game.redeemFlip.
    /// @param id Account receiving the tickets (0 = caller; account rule); FLIP from its payee
    /// @param entryQuantityScaled Ticket quantity in scaled entry units (400 = one whole ticket; 2 decimals, x100)
    function redeemFlip(
        uint32 id,
        uint256 entryQuantityScaled
    ) external;

    /// @notice Sells far-future ticket entries to sDGNRS for current-level tickets + cash (-EV).
    ///         Raw msg.data target of Game.sellFarFutureEntries.
    /// @param id Seller account (0 = caller; account rule)
    /// @param levels Target levels to sell from
    /// @param quantities Entries to sell at each level (4 entries = 1 whole ticket)
    /// @param queueIndices Caller-supplied ticketQueue positions (verified; for swap-pop on sell-out)
    function sellFarFutureEntries(
        uint32 id,
        uint32[] calldata levels,
        uint256[] calldata quantities,
        uint256[] calldata queueIndices
    ) external;

    /// @notice Buys a credit-gated coin-presale box (msg.value, then claimable + afking shortfall).
    ///         Raw msg.data target of Game.buyPresaleBox.
    /// @param id Account receiving the box (0 = caller; account rule)
    /// @param boxAmount Requested box ETH (>= 0.01 ETH, pre-clamp)
    function buyPresaleBox(uint32 id, uint256 boxAmount) external payable;

    /// @notice Buys a mint leg AND a presale box in one tx sharing one RNG index. Raw msg.data
    ///         target of Game.buyLootboxAndPresaleBox.
    /// @param id Account receiving both legs (0 = caller; account rule)
    /// @param entryQuantityScaled Tickets to buy
    /// @param boxOrder Packed box order (0 to skip): [small:8][med:8][large:8][customCount:8][customSize:56 gwei].
    /// @param affiliateCode Affiliate code for the mint leg
    /// @param payKind Payment method for the mint leg
    /// @param boxAmount Requested presale-box ETH (funded by the mint leg's leftover fresh ETH, then claimable, then afking)
    function buyLootboxAndPresaleBox(
        uint32 id,
        uint256 entryQuantityScaled,
        uint256 boxOrder,
        bytes32 affiliateCode,
        MintPaymentKind payKind,
        uint256 boxAmount
    ) external payable;
}

/// @title IDegenerusGameLootboxModule
/// @notice Interface for opening lootboxes and managing boons
interface IDegenerusGameLootboxModule {
    /// @notice Settle one queued box entry (ordinary leg, then presale leg)
    /// @param buffer Physical read buffer (0/1)
    /// @param position The entry's zero-based position in that buffer
    /// @param entry The stored entry word
    /// @param rngWord The buffer's published session word
    /// @param currentLevel Open level (`level + 1`)
    function resolveHumanBoxOrder(uint48 buffer, uint256 position, uint256 entry, uint256 rngWord,
        uint24 currentLevel) external;

    /// @notice Build a purchase's ordinary entry: validate and price, consume a live boost,
    ///         snapshot distress, arm the box bounty. Nothing is queued
    /// @param buyer Player the entry is for
    /// @param buyerId The buyer's wallet ID
    /// @param boxOrder Packed input: [small:8][med:8][large:8][customCount:8][customSize:56 gwei]
    /// @return costWei Total wei the order costs
    /// @return shares Prize-pool shares packed as (future << 128) | next
    /// @return flipCredit Biggest-box bounty claim, to join the buyer's flip credit
    /// @return word The in-flight entry word
    function beginBoxOrder(address buyer, uint32 buyerId, uint256 boxOrder)
        external
        payable
        returns (
            uint256 costWei,
            uint256 shares,
            uint256 flipCredit,
            uint256 word
        );

    /// @notice Append a system-granted box entry (pass purchases, afking cover)
    /// @param player Player receiving the boxes
    /// @param amountWei Box spend in wei
    /// @param score Activity-score snapshot
    /// @param capKey Level key for the shared per-(wallet, level) EV-cap accumulator
    /// @param boost Whether to consume a live lootbox-boost boon and snapshot distress
    /// @param count Custom boxes, one per pass; zero for the afking cover box
    function recordCoverBox(
        address player,
        uint256 amountWei,
        uint16 score,
        uint24 capKey,
        bool boost,
        uint8 count
    ) external payable;

    /// @notice Finalize a purchase's ordinary entry with its post-action score and EV-cap draw
    /// @param word The in-flight entry from `beginBoxOrder`
    /// @param cachedScore Caller's post-action activity score in whole points
    /// @param capLevel Level key for the shared per-(wallet, level) EV-cap accumulator
    /// @param costWei This purchase's box spend
    /// @return The completed ordinary fields
    function applyBoxOrderScore(
        uint256 word,
        uint256 cachedScore,
        uint24 capLevel,
        uint256 costWei
    ) external payable returns (uint256);

    /// @notice Resolves a lootbox directly with provided randomness
    /// @param player Address of the lootbox owner
    /// @param amount Amount associated with the lootbox
    /// @param rngWord Random word for lootbox resolution
    /// @param activityScore Frozen activity score in whole points for the EV multiplier (caller-snapshotted)
    function resolveLootboxDirect(
        address player, uint32 id,
        uint256 amount,
        uint256 rngWord,
        uint16 activityScore
    ) external payable;

    /// @notice Resolve a purchased Degenerette win with a 50 ETH score ceiling if allowance remains.
    /// @dev One combined box per bet; recorded shared usage is clamped to the normal 10 ETH cap.
    function resolveDegeneretteLootboxDirect(
        address player, uint32 id,
        uint256 amount,
        uint256 rngWord,
        uint16 activityScore
    ) external payable;

    /// @notice Resolves an sDGNRS redemption's full lootbox leg (auth, funding-mix pull, pool
    ///         credit, one box order of up to 20 equal boxes) — delegatecall target of the
    ///         Game's thin stub.
    /// @param player Player receiving lootbox rewards
    /// @param amount Total lootbox value (msg.value ETH + the stETH remainder pulled inside)
    /// @param rngWord RNG word for entropy
    /// @param activityScore Raw activity score (whole points) snapshotted at burn submission
    /// @param batchId Redemption batch of the claim (tags the order's seeds and events)
    function resolveRedemptionLootbox(
        address player, uint32 id,
        uint256 amount,
        uint256 rngWord,
        uint16 activityScore,
        uint32 batchId
    ) external payable;

    /// @notice Credit the direct half of an sDGNRS redemption claim to the claimant's claimable winnings.
    /// @param id Claimant wallet ID credited.
    /// @param amount Total direct-half value (msg.value ETH + the stETH remainder pulled here).
    function creditRedemptionDirect(uint32 id, uint256 amount) external payable;

    /// @notice Resolve an AfKing-subscription box at the LIVE level from a caller-passed
    ///         frozen-day word.
    /// @dev The LIVE-level twin of resolveLootboxDirect — the box rolls from the LIVE level
    ///      and the EV-cap RMW is the single draw at open, with two deviations:
    ///      the word is a caller-passed param (_recordedDailyWord(stamp day)) and the seed
    ///      `day` is the FROZEN stamped process day. Called by the GameAfkingModule
    ///      open-leg.
    /// @param player Box owner (resolved from the subscription)
    /// @param amount The stamped spend in wei (boons OFF ⇒ amount == spend)
    /// @param day The boundary-pinned process day stamped at process (frozen seed input)
    /// @param rngWord The frozen stamp day's word _recordedDailyWord(day), passed by the caller
    /// @param activityScore The stamped activity score in whole points (the frozen EV input)
    function resolveAfkingBox(
        address player, uint32 id,
        uint256 amount,
        uint24 day,
        uint256 rngWord,
        uint16 activityScore
    ) external;

}

/// @title IDegenerusGameBoonModule
/// @notice Interface for boon consumption
interface IDegenerusGameBoonModule {
    /// @notice Draw boons for every box in one opened entry, in a single call
    /// @param player Box owner (account key for the mint word and box events)
    /// @param id Box owner's wallet ID (boon and quest state key)
    /// @param perBoxBudget Boon budget of a single box, in wei of ETH-equivalent value
    /// @param boxCount Boxes rolled in this entry
    /// @param originalAmount One box's resolution amount, for the reward events
    /// @param currentLevel Open level (level + 1)
    /// @param seed Player-mixed entry seed; box i draws off a (nonceBase + i)-tagged derivative
    /// @param nonceBase Global box position of this batch's first box within its entry
    function rollBoxBoons(
        address player,
        uint32 id,
        uint256 perBoxBudget,
        uint256 boxCount,
        uint256 originalAmount,
        uint24 currentLevel,
        uint256 seed,
        uint256 nonceBase
    ) external payable;

    /// @notice Draw boons for a mixed box order in one delegatecall
    /// @param player Box owner (account key for the mint word and box events)
    /// @param id Box owner's wallet ID (boon and quest state key)
    /// @param amounts Per-box resolution amount for small/medium/large/custom/cover lanes
    /// @param countsPacked Five uint8 lane counts packed from least significant to most
    /// @param currentLevel Open level (level + 1)
    /// @param seed Player-mixed entry seed; nonces run cumulatively across populated lanes
    function rollBoxBoonTiers(
        address player,
        uint32 id,
        uint256[5] calldata amounts,
        uint40 countsPacked,
        uint24 currentLevel,
        uint256 seed
    ) external payable;

    /// @notice Issues a deity boon from deity account `deityId` (0 = caller; account rule) to the
    ///         existing account `recipientId`. Raw msg.data target of Game.issueDeityBoon.
    function issueDeityBoon(uint32 deityId, uint32 recipientId, uint8 slot) external;


    /// @notice Automatically award both protocol owners' three closed daily draws. Advance-only delegate target.
    function resolveProtocolBoonDraws(uint24 awardDay) external;

    /// @notice Consumes a player's coinflip, craps or WWXRP boon and returns its value
    /// @dev The Game façade authorizes COINFLIP, COIN and WWXRP and forwards its calldata
    ///      unchanged (identical selector to DegenerusGame.consumeCoinflipBoon(uint32)). Each
    ///      caller selects only its own lane; delegatecall preserves the caller for the
    ///      module's dispatch. Boon state is keyed by wallet ID; `id == 0` returns 0.
    /// @param id Wallet ID of the player
    /// @return boonBps Boon value in basis points
    function consumeCoinflipBoon(uint32 id) external returns (uint16 boonBps);

    /// @notice Consumes a player's purchase boost boon
    /// @param id Wallet ID of the player (boon state key)
    /// @return boostBps Boost value in basis points
    function consumePurchaseBoost(uint32 id) external payable returns (uint16 boostBps);

    /// @notice Consumes a player's decimator boost boon
    /// @dev Delegate target of DegenerusGame.consumeDecimatorBoon(uint32). Boon state is keyed
    ///      by wallet ID; `id == 0` returns 0.
    /// @param id Wallet ID of the player
    /// @return boostBps Boost value in basis points
    function consumeDecimatorBoost(uint32 id) external returns (uint16 boostBps);

    /// @notice Consumes a player's degenerette stake boon for a bet in `currency`
    /// @dev Each currency has its own independent boon lane; only the bet currency's
    ///      lane is read and spent.
    /// @param id Wallet ID of the player (boon state key)
    /// @param currency Bet currency (0=ETH, 1=FLIP)
    /// @return boostBps Stake bonus in basis points (0 if the lane is empty or expired)
    function consumeDegeneretteBoon(
        uint32 id,
        uint8 currency
    ) external payable returns (uint16 boostBps);

    /// @notice Clear all expired boons for a player
    /// @param id Wallet ID of the player (boon state key)
    /// @return hasAnyBoon True if any active boon remains
    function checkAndClearExpiredBoon(uint32 id) external payable returns (bool hasAnyBoon);
}

/// @title IDegenerusGameDegeneretteModule
/// @notice Interface for Degenerette betting mechanics (single-symbol selection)
interface IDegenerusGameDegeneretteModule {
    function runDegeneretteWork(uint256 gasAllowance) external returns (MineFlipGas.Result memory);
    /// @notice Places single-symbol bets
    /// @dev Raw msg.data target of Game.placeDegeneretteBet (identical selector). Gift door: an
    ///      authorized caller funds from the account (FLIP from its payee, quest to the account);
    ///      any other caller funds the bet itself as a gift to the existing account `id`.
    /// @param id The betting account (0 = caller; otherwise allocated, else E)
    /// @param currency Currency type (0=ETH, 1=FLIP; all other values unsupported)
    /// @param amountPerSpin Bet amount per ticket
    /// @param spinCount Number of spins (1..25 ETH, 1..15 FLIP). Each spin resolves independently.
    /// @param symbol Chosen hero symbol (0..23: Crypto, Zodiac, Cards); quadrant = symbol >> 3.
    function placeDegeneretteBet(
        uint32 id,
        uint8 currency,
        uint128 amountPerSpin,
        uint8 spinCount,
        uint8 symbol
    ) external payable;

    /// @notice Resolve a lootbox WWXRP roll as a single WWXRP Degenerette spin.
    /// @param player The reward recipient.
    /// @param stake Virtual WWXRP stake in 10^18 sub-units per token (not an ERC20 amount).
    /// @param activityScore Frozen activity score in whole points from the box's commitment.
    /// @param seed Domain-separated spin seed (hash2-tagged off the box seed).
    /// @param symbol Hero symbol 0..23 (no Dice), or 32 for a random eligible hero.
    /// @return wwxrpOut The spin's whole-token WWXRP payout, returned for the box entry's WWXRP lane (the
    ///         caller mints once).
    function resolveWwxrpSpinFromBox(
        address player,
        uint256 stake,
        uint16 activityScore,
        uint256 seed,
        uint8 symbol
    )
        external
        payable
        returns (uint256 wwxrpOut);

    /// @notice Resolve a lootbox roll as three FLIP Degenerette spins under one survival flip.
    /// @param player The reward recipient.
    /// @param totalStake Virtual FLIP budget in 10^18 sub-units per token, split across three spins.
    /// @param activityScore Frozen activity score in whole points from the box's commitment.
    /// @param seed Domain-separated spin seed (hash2-tagged off the box seed).
    /// @param symbol Hero symbol 0..23 (no Dice), or 32 for a random eligible hero.
    /// @return flipOut Whole-token payout after the survival flip, returned for the box entry's
    ///         FLIP lane (credited by the caller at flush).
    function resolveFlipSpinsFromBox(
        address player,
        uint256 totalStake,
        uint16 activityScore,
        uint256 seed,
        uint8 symbol
    )
        external
        payable
        returns (uint256 flipOut);

    /// @notice Resolve a lootbox roll as one ETH Degenerette spin (claimable + recirc split).
    /// @param player The reward recipient.
    /// @param playerId The recipient's wallet ID.
    /// @param stake The ETH bet amount for the one spin (the ticket budget it replaces).
    /// @param activityScore Frozen activity score in whole points from the box's commitment.
    /// @param seed Domain-separated spin seed (hash2-tagged off the box seed).
    /// @param symbol Hero symbol 0..23 (no Dice), or 32 for a random eligible hero.
    function resolveEthSpinFromBox(
        address player,
        uint32 playerId,
        uint256 stake,
        uint16 activityScore,
        uint256 seed,
        uint8 symbol
    ) external payable;
}

/// @title IDegenerusGameBingoModule
/// @notice Interface for color-completion bingo claims + the affiliate-DGNRS claim.
interface IDegenerusGameBingoModule {
    /// @notice Claim color-completion bingo: all 8 colors of one symbol on a level.
    /// @dev Each player may claim one bingo reward per level.
    ///      Raw msg.data target of Game.claimBingo (identical selector); DGNRS to the payee.
    /// @param id Bingo owner to claim for (0 = caller; otherwise allocated, else E); permissionless.
    /// @param level The level to claim on (uint24 storage-key width).
    /// @param symbol Symbol 0-31 (quadrant = symbol >> 3, symInQ = symbol & 7).
    /// @param slots Per-color positions in lvlTraitEntry[level][traitId] the owner occupies.
    function claimBingo(uint32 id, uint24 level, uint8 symbol, uint32[8] calldata slots) external;

    /// @notice Claim DGNRS affiliate rewards for the current level. The Game retains a
    ///         thin delegatecall dispatch stub that targets this selector; the body must
    ///         run in the Game's context for the onlyGame / onlyFlipCreditors external
    ///         calls, which is what that stub provides.
    ///      Permissionless; DGNRS to the account's payee, FLIP bonus by ID.
    /// @param id Affiliate account to claim for (0 = caller; otherwise allocated, else E).
    function claimAffiliateDgnrs(uint32 id) external;
}

/// @title IGameAfkingModule
/// @notice Interface for the AfKing subscription logic.
/// @dev The GameAfkingModule is a delegatecall module operating on the Game's storage
///      (the subscriber set / cursors / Sub stamps live in
///      DegenerusGameStorage). This interface declares the mutating surface
///      so the Game-hosted dispatch stubs and the AdvanceModule process STAGE call
///      resolve against a real ABI. Every function runs IN the Game's storage context
///      (delegatecall), so msg.sender is preserved end-to-end (the consent gates and
///      the bounty payee read the original caller).
interface IGameAfkingModule {
    /// @notice GAME-only atomic stETH fallback funding operation.
    function pullAfkingSteth(uint256 subWord, address source, uint256 shortfall) external returns (uint256);

    function runSubscriberWork(uint24 processDay, uint256 gasAllowance) external returns (MineFlipGas.Result memory);
    function runAfkingWork(uint256 gasAllowance) external returns (MineFlipGas.Result memory);
    function runHumanBoxWork(uint256 gasAllowance) external returns (MineFlipGas.Result memory);

    /// @notice The SINGLE subscription entrypoint: create / replace (dailyQuantity >= 1)
    ///         or cancel (dailyQuantity == 0, tombstone) for account `id` (0 = caller).
    /// @dev Raw msg.data target of Game.subscribe (identical selector; see IDegenerusGame).
    ///      rngLock guard on all of create / replace / cancel; account-rule authorization;
    ///      funding-source consent by ID (the same main wallet as the subscriber, or an operator
    ///      approval of the subscriber's key on the source's ID); a new run burns seat
    ///      `seatId` of the subscriber's payee through AFKING_SUB_TOKEN.consumeSeat before the
    ///      run is written (changes, cancels and the exempt VAULT/SDGNRS subs burn nothing).
    function subscribe(
        uint32 id,
        bool drainGameCreditFirst,
        bool useTickets,
        uint8 dailyQuantity,
        uint32 fundingSourceId,
        uint256 seatId
    ) external payable;

    /// @notice Permissionless FLIP claim — pays each account its accrued pendingFlip (the
    ///         per-delivered-day slot-0 quest reward + ticket buyer-bonus) in one creditFlip
    ///         and zeroes it; always credits the account, never the caller. Off the solvency path.
    /// @dev Raw msg.data target of Game.claimAfkingFlip. `ids[i] == 0` is the caller; an ID with
    ///      nothing accrued (unallocated included) settles nothing and does not revert.
    function claimAfkingFlip(uint32[] calldata ids) external;

    /// @notice Affiliate-only atomic read-and-zero of a sub's accrued affiliateBase (the
    ///         running flat-7% affiliate balance, whole FLIP). Read and zero happen
    ///         together so a duplicate sub drains 0 the second time; there is no separate
    ///         read accessor.
    /// @param sub The subscriber whose affiliate base is drained.
    /// @return base The drained whole-FLIP affiliate base (0 if already drained).
    function drainAffiliateBase(address sub) external returns (uint256 base, uint32 id);

    /// @notice Cashout-curse SET hook, delegatecalled from the Game's claimWinnings.
    function maybeCurse(address player) external;

    /// @notice Permissionless paid cure: clear account `id`'s cashout/smite curse for 100 FLIP
    ///         burned from the caller's own wallet (0 = caller; otherwise allocated, else E).
    function decurse(uint32 id) external;

    /// @notice Deity-gated smite: add a saturating curse stack to account `smiteeId` for 200 FLIP
    ///         burned from the caller, who must own pass `deityId` (0 = caller; otherwise
    ///         allocated, else E).
    function smite(uint256 deityId, uint32 smiteeId) external;
}

/// @title IDegenerusGameFoilPackModule
/// @notice Interface for the foil pack buy + match claim.
/// @dev The Game retains thin delegatecall dispatch stubs targeting these selectors;
///      both bodies run in the Game's storage context (delegatecall), so the resolved
///      player is passed explicitly and msg.value rides through the call.
interface IDegenerusGameFoilPackModule {
    function runFoilWork(uint256 allowance) external returns (MineFlipGas.Result memory);
    /// @notice Queue every deity owner's perpetual ticket for a phase-transition target level.
    function queuePerpetualTickets(uint24 targetLevel) external;

    /// @notice The foil branch of Game.purchase: an additive foil pack on top of optional ticket
    ///         and lootbox legs. Registers the buyer first (paid admission uses the whole quoted
    ///         spend), caps fresh ETH at the combined cost, credits any overpay to the payer's
    ///         afking, runs the ticket/lootbox leg through the mint module, then delivers the pack.
    /// @param buyer Player receiving every leg (already operator-resolved).
    function purchaseWithFoil(
        address buyer,
        uint256 entryQuantityScaled,
        uint256 boxOrder,
        bytes32 affiliateCode,
        MintPaymentKind payKind
    ) external payable;

    /// @notice Claim a foil ticket's match against a day's draw (permissionless).
    /// @dev The win credits to `player`, never the caller, and a tuple pays at most
    ///      once, so anyone may resolve any player's claim. Reverts if the tuple is not
    ///      a claimable win. Claims are valid on the draw day and the following day,
    ///      and close when terminal settlement triggers.
    ///      Raw msg.data target of Game.claimFoilMatch; WWXRP box-spin prizes go to the payee.
    /// @param id Pack owner the win credits to (0 = caller; otherwise allocated, else E).
    /// @param day The draw day to claim against.
    /// @param ticketIndex Which of the pack's four tickets to claim (0-3).
    function claimFoilMatch(
        uint32 id,
        uint256 day,
        uint256 ticketIndex
    ) external;

    /// @notice Claim a foil pack's gold (permissionless).
    /// @dev A FLIP ladder on the pack's total gold count from three up, plus a kicker
    ///      for one all-gold ticket. Two all-gold tickets take the grand instead — pushed
    ///      automatically by the foil drain, so this call reverts for such a pack. The
    ///      pack's lines are re-derived from the sealed word its buy froze
    ///      against, so nothing about the gold is stored. The win credits to `player`,
    ///      never the caller, and a pack pays at most once.
    ///      Raw msg.data target of Game.claimGoldenTicket; payouts go to the payee.
    /// @param id Pack owner the win credits to (0 = caller; otherwise allocated, else E).
    /// @param lvl The pack's cycle level.
    function claimGoldenTicket(uint32 id, uint24 lvl) external;

    /// @notice Permissionlessly resolve a batch of foil match claims.
    /// @dev Non-claimable tuples past index 0 are skipped (not reverted); each settled
    ///      win credits its own player and the caller earns a small per-settled-claim
    ///      FLIP bounty during a live game. A non-claimable tuple AT index 0 reverts the
    ///      whole call (StaleBatch), marking an already-swept list. The three arrays are
    ///      parallel. Claims are valid on the draw day and the following day, and close
    ///      when terminal settlement triggers.
    ///      Raw msg.data target of Game.claimFoilMatchMany; `ids[i] == 0` is the caller.
    /// @param ids Pack owners the wins credit to.
    /// @param drawDays Draw days to claim against.
    /// @param ticketIndexes Which pack ticket (0-3) per claim.
    function claimFoilMatchMany(
        uint32[] calldata ids,
        uint24[] calldata drawDays,
        uint8[] calldata ticketIndexes
    ) external;
}
