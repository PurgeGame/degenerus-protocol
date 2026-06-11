// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/**
 * @title DegenerusGame
 * @author Burnie Degenerus
 * @notice Core game contract managing state machine, VRF integration, jackpots, and prize pools.
 *
 * @dev ARCHITECTURE:
 *      - 2-state FSM: PURCHASE(false) ↔ JACKPOT(true) → (cycle)
 *      - gameOver flag is terminal
 *      - Presale is a toggle (packed in presaleStatePacked), not a state
 *      - Chainlink VRF for randomness with RNG lock to prevent manipulation
 *      - Delegatecall modules: advance, boon, decimator, degenerette, jackpot, lootbox, mint, whale (must inherit DegenerusGameStorage)
 *      - Prize pool flow: futurePrizePool (unified reserve) → nextPrizePool → currentPrizePool → claimableWinnings
 *
 * @dev CRITICAL INVARIANTS:
 *      - address(this).balance + steth.balanceOf(this) >= claimablePool
 *        (claimablePool == Σ claimableWinnings + Σ afkingFunding; both ride in the one reserve)
 *      - jackpotPhaseFlag transitions: false(PURCHASE) ↔ true(JACKPOT); gameOver is terminal
 *      - Presale starts active, auto-ends at PURCHASE→JACKPOT or via admin (one-way: never re-enables)
 *
 * @dev SECURITY:
 *      - Pull pattern for ETH/stETH withdrawals (claimWinnings)
 *      - RNG lock prevents state manipulation during VRF callback window
 *      - Access control via msg.sender checks
 *      - Delegatecall modules use constant addresses from ContractAddresses
 *      - 12h VRF timeout, 3-day stall detection, 120-day inactivity guard
 */

import {IDegenerusCoin} from "./interfaces/IDegenerusCoin.sol";
import {IBurnieCoinflip} from "./interfaces/IBurnieCoinflip.sol";
import {IDegenerusAffiliate} from "./interfaces/IDegenerusAffiliate.sol";
import {IStakedDegenerusStonk} from "./interfaces/IStakedDegenerusStonk.sol";
import {IStETH} from "./interfaces/IStETH.sol";
import {
    IDegenerusGameAdvanceModule,
    IDegenerusGameDecimatorModule,
    IDegenerusGameJackpotModule,
    IDegenerusGameMintModule,
    IDegenerusGameWhaleModule,
    IDegenerusGameLootboxModule,
    IDegenerusGameBoonModule,
    IDegenerusGameDegeneretteModule,
    IDegenerusGameBingoModule,
    IGameAfkingModule
} from "./interfaces/IDegenerusGameModules.sol";
import {MintPaymentKind} from "./interfaces/IDegenerusGame.sol";
import {
    DegenerusGameMintStreakUtils
} from "./modules/DegenerusGameMintStreakUtils.sol";
import {ContractAddresses} from "./ContractAddresses.sol";
import {BitPackingLib} from "./libraries/BitPackingLib.sol";
import {GameTimeLib} from "./libraries/GameTimeLib.sol";
import {PriceLookupLib} from "./libraries/PriceLookupLib.sol";

/*+==============================================================================+
  |                     EXTERNAL INTERFACE DEFINITIONS                           |
  +==============================================================================+
  |  Minimal interfaces for external contracts this contract interacts with.     |
  |  These are defined locally to avoid circular import dependencies.            |
  +==============================================================================+*/

/// @dev Vault interface for DGVE ownership check (admin function access control).
interface IDegenerusVaultOwnerGame {
    function isVaultOwner(address account) external view returns (bool);
}

// ===========================================================================
// Contract
// ===========================================================================

/**
 * @title DegenerusGame
 * @author Burnie Degenerus
 * @notice Core game contract implementing the game state machine, VRF integration,
 *         and orchestration of all gameplay mechanics.
 * @dev Inherits DegenerusGameStorage for shared storage layout with delegate modules.
 *      Uses delegatecall pattern for complex logic (8 modules: advance, boon, decimator, degenerette, jackpot, lootbox, mint, whale).
 * @custom:security-contact burnie@degener.us
 */
contract DegenerusGame is DegenerusGameMintStreakUtils {
    /*+======================================================================+
      |                              ERRORS                                  |
      +======================================================================+
      |  Custom errors for gas-efficient reverts. Each error maps to a       |
      |  specific failure condition in the game flow.                        |
      +======================================================================+*/

    // error E() — inherited from DegenerusGameStorage

    // error RngLocked() — inherited from DegenerusGameStorage

    /// @notice Caller is not approved to act for the requested player.
    error NotApproved();

    /// @notice Caller-supplied work list is already resolved (a competitor got ahead).
    error BatchAlreadyTaken();

    /// @notice No resolvable work in the supplied batch (degeneretteResolve at zero resolutions).
    error NoWork();

    /*+======================================================================+
      |                              EVENTS                                  |
      +======================================================================+
      |  Events for off-chain indexers and UIs. All critical state changes   |
      |  emit events for transparency and auditability.                      |
      +======================================================================+*/

    /// @notice Emitted when the lootbox RNG request threshold is updated.
    /// @param previous Previous threshold in wei.
    /// @param current New threshold in wei.
    event LootboxRngThresholdUpdated(uint256 previous, uint256 current);
    /// @notice Emitted when a player approves or revokes an operator.
    /// @param owner The player granting approval.
    /// @param operator The approved operator.
    /// @param approved True if approved, false if revoked.
    event OperatorApproval(
        address indexed owner,
        address indexed operator,
        bool approved
    );
    /// @notice Emitted when a player nudges the next RNG word.
    /// @param caller The player who paid the nudge cost.
    /// @param totalQueued Total nudges queued for the next VRF word.
    /// @param cost BURNIE burned for this nudge.
    event ReverseFlip(
        address indexed caller,
        uint256 totalQueued,
        uint256 cost
    );

    /*+=======================================================================+
      |                   PRECOMPUTED ADDRESSES (CONSTANT)                    |
      +=======================================================================+
      |  Core contract references are read from ContractAddresses and baked   |
      |  into bytecode. They cannot change after deployment.                  |
      +=======================================================================+*/

    IStETH internal constant steth = IStETH(ContractAddresses.STETH_TOKEN);

    /// @notice Vault contract for owner verification.
    IDegenerusVaultOwnerGame private constant vault =
        IDegenerusVaultOwnerGame(ContractAddresses.VAULT);

    /*+======================================================================+
      |                           CONSTANTS                                  |
      +======================================================================+
      |  Game parameters and bit manipulation constants. All constants are   |
      |  private to prevent external dependency on specific values.          |
      +======================================================================+*/

    /// @dev Share of ticket purchases routed to future prize pool (10%).
    uint16 private constant PURCHASE_TO_FUTURE_BPS = 1000;

    /// @dev DGNRS bounty share for biggest flip payout (0.2% of reward pool).
    uint16 private constant COINFLIP_BOUNTY_DGNRS_BPS = 20;
    uint256 private constant COINFLIP_BOUNTY_DGNRS_MIN_BET = 50_000 ether;
    uint256 private constant COINFLIP_BOUNTY_DGNRS_MIN_POOL = 20_000 ether;

    /// @dev Base cost for RNG nudge (100 BURNIE), compounds +50% per queued nudge.
    uint256 private constant RNG_NUDGE_BASE_COST = 100 ether;

    /*+======================================================================+
      |                    MINT PACKED BIT LAYOUT                            |
      +======================================================================+
      |  Player mint history is packed into a single uint256 for gas         |
      |  efficiency. Layout (LSB first):                                     |
      |                                                                      |
      |  [0-23]   lastEthLevel     - Last level where player minted with ETH |
      |  [24-47]  ethLevelCount    - Total levels with ETH mints             |
      |  [48-71]  ethLevelStreak   - Consecutive levels with ETH mints       |
      |  [72-103] lastEthDay       - Day index of last ETH mint              |
      |  [104-127] unitsLevel      - Level index for unitsAtLevel tracking   |
      |  [128-151] frozenUntilLevel - Whale bundle freeze level (0 = none)   |
      |  [152-153] whaleBundleType  - Bundle type (0=none,1=10,3=100)        |
      |  [154-159] (reserved)       - 6 unused bits                           |
      |  [160-183] mintStreakLast  - Mint streak last completed level (24b)   |
      |  [184]    hasDeityPass     - Deity pass holder flag (1b)             |
      |  [185-208] affBonusLevel   - Cached affiliate bonus level (24b)     |
      |  [209-214] affBonusPoints  - Cached affiliate bonus points (6b)     |
      |  [215-227] (reserved)      - 13 unused bits                          |
      |  [228-243] unitsAtLevel    - Mints at current level                  |
      |  [244]    (deprecated)     - Previously used for bonus tracking      |
      +======================================================================+*/

    /*+======================================================================+
      |                          CONSTRUCTOR                                 |
      +======================================================================+
      |  Initialize storage wiring and set up initial approvals.             |
      |  The constructor wires together the entire game ecosystem.           |
      +======================================================================+*/

    /**
     * @notice Initialize the game with precomputed contract references.
     * @dev All addresses and deploy day boundary are compile-time constants from ContractAddresses.
     *      purchaseStartDay is initialized to the deploy day index.
     *      dailyIdx is set to the current day index so gap detection starts from deploy day.
     *      Deploy day boundary determines which calendar day is "day 1" in the game.
     */
    constructor() {
        uint24 currentDay = GameTimeLib.currentDayIndex();
        purchaseStartDay = currentDay;
        dailyIdx = currentDay;
        levelPrizePool[0] = BOOTSTRAP_PRIZE_POOL;
        // Vault addresses get deity-equivalent score boost (no symbol, not in deityPassOwners)
        mintPacked_[ContractAddresses.SDGNRS] = BitPackingLib.setPacked(mintPacked_[ContractAddresses.SDGNRS], BitPackingLib.HAS_DEITY_PASS_SHIFT, 1, 1);
        mintPacked_[ContractAddresses.VAULT] = BitPackingLib.setPacked(mintPacked_[ContractAddresses.VAULT], BitPackingLib.HAS_DEITY_PASS_SHIFT, 1, 1);
        // Perpetual vault/SDGNRS tickets (levels 1-100) are queued post-deploy by VAULT and
        // SDGNRS via initPerpetualTickets() — moved out of this constructor so GAME's deploy
        // stays under the per-tx gas cap.
    }

    /// @notice Queue the perpetual vault/SDGNRS tickets for levels 1-100 (advance handles 101+).
    /// @dev Split out of the constructor to keep GAME's deploy under the per-tx gas cap. VAULT and
    ///      SDGNRS each call this exactly once from their own constructor (one deploy tx each), so
    ///      no re-entry path exists. Restricted to those two protocol addresses — the only
    ///      recipients of perpetual tickets — and queues for the caller only.
    function initPerpetualTickets() external {
        address who = msg.sender;
        if (who != ContractAddresses.SDGNRS && who != ContractAddresses.VAULT) revert E();
        for (uint24 i = 1; i <= 100; ) {
            _queueTickets(who, i, 16, false);
            unchecked {
                ++i;
            }
        }
    }

    /*+======================================================================+
      |                           MODIFIERS                                  |
      +======================================================================+*/

    /*+========================================================================================+
      |                    CORE STATE MACHINE: advanceGame()                                   |
      +========================================================================================+
      |  The heart of the game. This function progresses the state machine                     |
      |  through its 2 active phases: PURCHASE (jackpotPhaseFlag=false), JACKPOT (jackpotPhaseFlag=true). |
      |  Each call performs one "tick" of work. gameOver is terminal.                          |
      |                                                                                        |
      |  State Transitions:                                                                    |
      |  • PURCHASE (jackpotPhaseFlag=false): Process ticket batches until target met, then → JACKPOT|
      |  • JACKPOT (jackpotPhaseFlag=true): Pay daily jackpots, wait for burns, then → PURCHASE      |
      |  • GAMEOVER (gameOver=true): Terminal state, no transitions                             |
      |                                                                                        |
      |  Gating (tiered bypass):                                                                |
      |  • Deity pass holder — always bypasses                                                 |
      |  • Anyone — bypasses after 30+ min since level start                                   |
      |  • Pass holder (lazy/whale) — bypasses after 15+ min                                   |
      |  • DGVE majority holder — always bypasses (last resort, external call)                 |
      |  • RNG must be ready (not locked) or recently stale (12h timeout)                      |
      |                                                                                        |
      |  Presale: packed presale-active toggle (orthogonal to state machine)                    |
      |  • Starts active: 62% bonus BURNIE from loot boxes                                       |
      |  • Auto-ends when PURCHASE→JACKPOT, or admin can end manually (one-way, cannot re-enable) |
      +========================================================================================+*/

    /// @notice Advance the game state machine by one tick.
    /// @dev Anyone can call, but standard flows require an ETH mint today.
    ///      This is the primary driver of game progression - called repeatedly
    ///      to move through states and process batched operations.
    ///
    ///      FLOW OVERVIEW:
    ///      1. Check liveness guards (1yr deploy timeout, 120-day inactivity)
    ///      2. Apply tiered daily gate (deity > anyone after 30min > pass after 15min > DGVE majority)
    ///      3. Process transition housekeeping during jackpot→purchase transition
    ///      4. Gate on RNG readiness (request new VRF if needed)
    ///      5. Process ticket batches
    ///      6. Execute state-specific logic:
    ///         - TRANSITION: Housekeeping + near-future ticket prep after burn completes
    ///         - PURCHASE/JACKPOT: Process phase-specific logic
    ///      7. Credit caller with BURNIE bounty during jackpot time when not requesting or unlocking RNG
    ///
    ///      SECURITY:
    ///      - Liveness guards prevent abandoned game lockup
    ///      - Daily gate prevents non-participants from advancing
    ///      - RNG gating ensures fairness (no manipulation during VRF window)
    ///      - Batched processing prevents DoS from large queues
    ///
    ///      The signature matches the module function exactly (identical selector), so the calldata
    ///      forwards as-is — re-encoding here would cost contract-size headroom for no behavior change.
    function advanceGame() external returns (uint8 mult) {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_ADVANCE_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
        mult = abi.decode(data, (uint8));
    }

    /*+========================================================================================+
      |                    ADMIN VRF FUNCTIONS                                                 |
      +========================================================================================+
      |  One-time VRF setup function called by ADMIN during deployment phase.                  |
      +========================================================================================+*/

    /// @notice Wire VRF config from the VRF ADMIN contract.
    /// @dev Access: ADMIN only. Overwrites any existing config on each call.
    ///      SECURITY: Config can be changed via emergency rotation (updateVrfCoordinatorAndSub).
    /// @custom:reverts E If caller is not ADMIN.
    /// @dev Signature: wireVrf(address coordinator_, uint256 subId, bytes32 keyHash_) —
    ///      Chainlink VRF V2.5 coordinator address, VRF subscription ID for LINK billing,
    ///      and the VRF key hash identifying the oracle and gas lane. The signature matches
    ///      the module function exactly (identical selector), so the calldata forwards as-is —
    ///      re-encoding here would cost contract-size headroom for no behavior change.
    function wireVrf(address, uint256, bytes32) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_ADVANCE_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
    }

    /// @notice Claim color-completion bingo: all 8 colors of one symbol on a level (v51.0).
    /// @dev Dispatches to GAME_BINGO_MODULE via delegatecall; void return.
    ///      Signature: claimBingo(uint24 level, uint8 symbol, uint32[8] slots) — the level to
    ///      claim on (uint24 storage-key width), the symbol 0-31 (quadrant = symbol >> 3,
    ///      symInQ = symbol & 7), and the per-color positions in traitBurnTicket[level][traitId]
    ///      the caller occupies. The signature matches the module function exactly (identical
    ///      selector), so the calldata forwards as-is — re-encoding here would cost contract-size
    ///      headroom for no behavior change.
    function claimBingo(
        uint24,
        uint8,
        uint32[8] calldata
    ) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_BINGO_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
    }

    /*+======================================================================+
      |              AFKING DISPATCH STUBS (v55.0 ARCH-02/03)               |
      +======================================================================+
      |  Thin delegatecall dispatch stubs into GAME_AFKING_MODULE (the AfKing     |
      |  subscription logic), shaped exactly like claimBingo.                     |
      |  The afking subscriber set / cursors / Sub stamps live in this Game's     |
      |  storage (DegenerusGameStorage), so the module MUST run in this           |
      |  contract's context — delegatecall preserves msg.sender, so the SUB-02 /  |
      |  OPENE-04 consent gates and the mintBurnie bounty payee read the real         |
      |  caller. These are the canonical entrypoints (there is no longer a        |
      |  separate afking logic host). `subscribe` is the SINGLE subscription       |
      |  mutator (create / replace / cancel — the 4 per-field setters are folded  |
      |  into it), so only 2 stubs remain (subscribe / mintBurnie); none is            |
      |  `view`. The afking box-open is reached via mintBurnie's router (the          |
      |  module's autoOpen would collide with this Game's existing human-box      |
      |  autoOpen(uint256) selector, so it is not re-exposed as a stub here).     |
      +======================================================================+*/

    /// @notice Start or extend a daily afking subscription for `player`.
    /// @dev CONSENT-01 (SUB-02 self-consent / OPENE-04 funding gate) runs in-context
    ///      against the Game's operatorApprovals (delegatecall preserves msg.sender).
    ///      msg.value > 0 credits the RESOLVED funding bucket's afkingFunding — the
    ///      non-self (OPENE-04-approved) fundingSource for an operator-funded sub, else the
    ///      subscriber (claimablePool in tandem) — so the deposit funds the bucket the
    ///      draws debit.
    ///      Signature: subscribe(address player, bool drainGameCreditFirst, bool useTickets,
    ///      uint8 dailyQuantity, uint8 reinvestPct, address fundingSource). The signature matches
    ///      the module function exactly (identical selector), so the calldata forwards as-is —
    ///      re-encoding here would cost contract-size headroom for no behavior change.
    function subscribe(
        address,
        bool,
        bool,
        uint8,
        uint8,
        address
    ) external payable {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_AFKING_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
    }

    /// @notice Unified permissionless afking router: do ONE category of pending work
    ///         (advance → afking-box open) and pay ONE bounty (PLACE-02). The bounty
    ///         credits msg.sender (preserved via delegatecall).
    /// @dev The signature matches the module function exactly (identical selector), so the calldata
    ///      forwards as-is — re-encoding here would cost contract-size headroom for no behavior change.
    function mintBurnie() external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_AFKING_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
    }

    /// @notice Permissionless BURNIE claim — pays each listed sub its accrued `pendingBurnie`
    ///         (the per-delivered-day quest reward + ticket buyer-bonus) in one creditFlip,
    ///         zeroed. Always credits the sub, never the caller.
    /// @dev Signature: claimAfkingBurnie(address[] subs). The signature matches the module
    ///      function exactly (identical selector), so the calldata forwards as-is — re-encoding
    ///      the array here would cost contract-size headroom for no behavior change.
    function claimAfkingBurnie(address[] calldata) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_AFKING_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
    }

    /// @notice Affiliate-only drain of a sub's accrued `affiliateBase`, zeroed and
    ///         returned to the caller. Routed from DegenerusAffiliate.claim(); the
    ///         module impl enforces the AFFILIATE-only access gate under delegatecall.
    /// @dev Signature: drainAffiliateBase(address sub). The signature matches the module
    ///      function exactly (identical selector), so the calldata forwards as-is — re-encoding
    ///      here would cost contract-size headroom for no behavior change.
    function drainAffiliateBase(address) external returns (uint256) {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_AFKING_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
        if (data.length == 0) revert E();
        return abi.decode(data, (uint256));
    }

    /// @notice Permissionless paid cure of `target`'s cashout/smite curse (100 BURNIE).
    /// @dev Thin delegatecall dispatch stub into GameAfkingModule's decurse body.
    ///      Signature: decurse(address target). The signature matches the module function
    ///      exactly (identical selector), so the calldata forwards as-is — re-encoding here
    ///      would cost contract-size headroom for no behavior change.
    function decurse(address) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_AFKING_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
    }

    /// @notice Deity-gated smite: add a curse stack to `smitee` for 200 BURNIE.
    /// @dev Thin delegatecall dispatch stub into GameAfkingModule's smite body.
    ///      Signature: smite(uint256 deityId, address smitee). The signature matches the module
    ///      function exactly (identical selector), so the calldata forwards as-is — re-encoding
    ///      here would cost contract-size headroom for no behavior change.
    function smite(uint256, address) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_AFKING_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
    }

    /*+======================================================================+
      |                       MINT RECORDING                                 |
      +======================================================================+
      |  Functions called by the game contract to record mints and process         |
      |  payments. ETH and claimable winnings can both fund purchases.       |
      +======================================================================+*/

    /// @notice Record a mint, funded by ETH or claimable winnings.
    /// @dev Access: self-call only (from delegate modules).
    ///      Payment modes:
    ///      - DirectEth: msg.value must be >= costWei (overage ignored for accounting)
    ///      - Claimable: deduct from claimableWinnings (msg.value must be 0)
    ///      - Combined: ETH first, then claimable for remainder
    ///
    ///      SECURITY: Validates minimum payment amounts; overage is ignored for accounting.
    ///      Prize contribution is split between nextPrizePool and futurePrizePool.
    ///
    /// @param player The player address to record mint for.
    /// @param lvl The level at which mint is occurring.
    /// @param costWei Total cost in wei for this mint.
    /// @param mintUnits Number of mint units purchased.
    /// @param payKind Payment method (DirectEth, Claimable, or Combined).
    /// @return newClaimableBalance Player's claimable balance after deduction (0 if DirectEth).
    /// @custom:reverts E If caller is not self-call context or payment validation fails.
    function recordMint(
        address player,
        uint24 lvl,
        uint256 costWei,
        uint32 mintUnits,
        MintPaymentKind payKind
    ) external payable returns (uint256 newClaimableBalance) {
        if (msg.sender != address(this)) revert E();
        uint256 prizeContribution;
        (prizeContribution, newClaimableBalance) = _processMintPayment(
            player,
            costWei,
            payKind
        );
        if (prizeContribution != 0) {
            uint256 futureShare = (prizeContribution * PURCHASE_TO_FUTURE_BPS) /
                10_000;
            uint256 nextShare = prizeContribution - futureShare;
            if (prizePoolFrozen) {
                (uint128 pNext, uint128 pFuture) = _getPendingPools();
                _setPendingPools(
                    pNext + uint128(nextShare),
                    pFuture + uint128(futureShare)
                );
            } else {
                (uint128 next, uint128 future) = _getPrizePools();
                _setPrizePools(
                    next + uint128(nextShare),
                    future + uint128(futureShare)
                );
            }
        }

        _recordMintDataModule(player, lvl, mintUnits);
    }

    /// @notice Pay DGNRS bounty for the biggest flip record holder.
    /// @dev Access: COIN or COINFLIP contract only.
    ///      Pays a share of the remaining DGNRS reward pool.
    /// @param player Recipient of the DGNRS bounty.
    /// @param winningBet The winning bet amount (must exceed COINFLIP_BOUNTY_DGNRS_MIN_BET).
    /// @param bountyPool The bounty pool size (must exceed COINFLIP_BOUNTY_DGNRS_MIN_POOL).
    /// @custom:reverts E If caller is not COIN or COINFLIP contract.
    function payCoinflipBountyDgnrs(
        address player,
        uint256 winningBet,
        uint256 bountyPool
    ) external {
        if (
            msg.sender != ContractAddresses.COIN &&
            msg.sender != ContractAddresses.COINFLIP
        ) revert E();
        if (player == address(0)) return;
        if (winningBet < COINFLIP_BOUNTY_DGNRS_MIN_BET) return;
        if (bountyPool < COINFLIP_BOUNTY_DGNRS_MIN_POOL) return;
        uint256 poolBalance = dgnrs.poolBalance(
            IStakedDegenerusStonk.Pool.Reward
        );
        if (poolBalance == 0) return;
        uint256 payout = (poolBalance * COINFLIP_BOUNTY_DGNRS_BPS) / 10_000;
        if (payout == 0) return;
        dgnrs.transferFromPool(
            IStakedDegenerusStonk.Pool.Reward,
            player,
            payout
        );
    }

    /*+======================================================================+
      |                      OPERATOR APPROVALS                             |
      +======================================================================+*/

    /// @notice Approve or revoke an operator to act on your behalf.
    /// @param operator Address to approve or revoke.
    /// @param approved True to approve, false to revoke.
    /// @custom:reverts E If operator is the zero address.
    function setOperatorApproval(address operator, bool approved) external {
        if (operator == address(0)) revert E();
        operatorApprovals[msg.sender][operator] = approved;
        emit OperatorApproval(msg.sender, operator, approved);
    }

    /// @notice Check if an operator is approved to act for a player.
    /// @param owner The player who granted approval.
    /// @param operator The operator address.
    /// @return approved True if operator is approved.
    function isOperatorApproved(
        address owner,
        address operator
    ) external view returns (bool approved) {
        return operatorApprovals[owner][operator];
    }

    function _requireApproved(address player) private view {
        if (msg.sender != player && !operatorApprovals[player][msg.sender]) {
            revert NotApproved();
        }
    }

    function _resolvePlayer(
        address player
    ) private view returns (address resolved) {
        if (player == address(0)) return msg.sender;
        if (player != msg.sender) _requireApproved(player);
        return player;
    }

    /*+======================================================================+
      |                       LOOT BOX CONTROLS                             |
      +======================================================================+*/

    /// @notice Current day index.
    function currentDayView() external view returns (uint24) {
        return _simulatedDayIndex();
    }

    /// @notice Update lootbox RNG request threshold (wei).
    /// @dev Access: vault owner only (DGVE majority holder).
    /// @param newThreshold New threshold in wei (must be non-zero).
    /// @custom:reverts E If caller is not vault owner or newThreshold is zero.
    function setLootboxRngThreshold(uint256 newThreshold) external {
        if (!vault.isVaultOwner(msg.sender)) revert E();
        if (newThreshold == 0) revert E();
        uint256 prev = _unpackMilliEthToWei(uint64(_lrRead(LR_THRESHOLD_SHIFT, LR_THRESHOLD_MASK)));
        if (newThreshold == prev) {
            emit LootboxRngThresholdUpdated(prev, newThreshold);
            return;
        }
        _lrWrite(LR_THRESHOLD_SHIFT, LR_THRESHOLD_MASK, _packEthToMilliEth(newThreshold));
        emit LootboxRngThresholdUpdated(prev, newThreshold);
    }

    /// @notice Purchase any combination of tickets and loot boxes with ETH or claimable.
    /// @dev Main entry point for all ETH/claimable purchases. For BURNIE purchases, use purchaseCoin().
    ///      Spending all claimable winnings earns a 10% bonus across the combined purchase.
    ///      Adds affiliate support for loot box purchases.
    ///      SECURITY: Blocked when RNG is locked.
    /// @param buyer Player address to receive purchases (address(0) = msg.sender).
    /// @param ticketQuantity Number of tickets to purchase (2 decimals, scaled by 100; 0 to skip).
    /// @param lootBoxAmount ETH amount for loot boxes, minimum 0.01 ETH (0 to skip).
    /// @param affiliateCode Affiliate/referral code for all purchases.
    /// @param payKind Payment method (DirectEth, Claimable, or Combined).
    function purchase(
        address buyer,
        uint256 ticketQuantity,
        uint256 lootBoxAmount,
        bytes32 affiliateCode,
        MintPaymentKind payKind
    ) external payable {
        buyer = _resolvePlayer(buyer);
        _purchaseFor(
            buyer,
            ticketQuantity,
            lootBoxAmount,
            affiliateCode,
            payKind
        );
    }

    function _purchaseFor(
        address buyer,
        uint256 ticketQuantity,
        uint256 lootBoxAmount,
        bytes32 affiliateCode,
        MintPaymentKind payKind
    ) private {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_MINT_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameMintModule.purchase.selector,
                    buyer,
                    ticketQuantity,
                    lootBoxAmount,
                    affiliateCode,
                    payKind
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @notice Purchase tickets with BURNIE.
    /// @dev Main entry point for BURNIE ticket purchases. Mirrors purchase() but for BURNIE payments.
    ///      SECURITY: Blocked when RNG is locked.
    /// @param buyer Player address to receive purchases (address(0) = msg.sender).
    /// @param ticketQuantity Number of tickets to purchase (2 decimals, scaled by 100; 0 to skip).
    function purchaseCoin(
        address buyer,
        uint256 ticketQuantity
    ) external {
        buyer = _resolvePlayer(buyer);
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_MINT_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameMintModule.purchaseCoin.selector,
                    buyer,
                    ticketQuantity
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @notice Buy a credit-gated coin-presale box with ETH and/or claimable (CPAY-02).
    /// @dev Box is gated by presaleBoxCredit (earned 25% on prior ETH buys), consumes
    ///      credit 1:1, caps cumulatively at 50 ETH, and queues for later resolution.
    /// @param buyer Player to receive the box (address(0) = msg.sender).
    /// @param boxAmount Requested box ETH (>= 0.01 ETH; excess refunded if clamped).
    function buyPresaleBox(
        address buyer,
        uint256 boxAmount
    ) external payable {
        buyer = _resolvePlayer(buyer);
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_MINT_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameMintModule.buyPresaleBox.selector,
                    buyer,
                    boxAmount
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @notice Buy tickets/lootbox AND a presale box in one tx, sharing one RNG index.
    /// @dev The mint leg earns 25% presale-box credit that gates the box leg. msg.value is
    ///      split across both legs (mint cost first, remainder to the box), so the box is
    ///      funded by the same mix as any other purchase — fresh ETH, claimable, or afking
    ///      per payKind. Both queue at one index for co-resolution.
    /// @param buyer Player to receive both legs (address(0) = msg.sender).
    /// @param ticketQuantity Tickets to buy (0 to skip).
    /// @param lootBoxAmount ETH lootbox spend (0 to skip).
    /// @param affiliateCode Affiliate/referral code for the mint leg.
    /// @param payKind Payment method for the mint leg.
    /// @param boxAmount Requested presale-box ETH (claimable-funded).
    function buyLootboxAndPresaleBox(
        address buyer,
        uint256 ticketQuantity,
        uint256 lootBoxAmount,
        bytes32 affiliateCode,
        MintPaymentKind payKind,
        uint256 boxAmount
    ) external payable {
        buyer = _resolvePlayer(buyer);
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_MINT_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameMintModule.buyLootboxAndPresaleBox.selector,
                    buyer,
                    ticketQuantity,
                    lootBoxAmount,
                    affiliateCode,
                    payKind,
                    boxAmount
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @notice Open every box queued at an RNG index — the ETH-lootbox leg, the coin-presale-box
    ///         leg, or both (each robust to being empty). Permissionless: anyone may open another
    ///         player's ready boxes (the economically-incentivized auto-open bounty path).
    /// @param player Player that owns the box(es) (address(0) = msg.sender).
    /// @param index The RNG index the box(es) queued at.
    function openBox(address player, uint48 index) external {
        player = _resolvePlayer(player);
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_LOOTBOX_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameLootboxModule.openBox.selector,
                    player,
                    index
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @notice Purchase whale bundle: boosts levelCount, queues 400 tickets, includes lootbox.
    /// @dev Available at any level. Can be purchased multiple times (1-100 per call).
    ///      Price: 2.4 ETH (levels 0-3), 4 ETH (levels 4+), or discounted with boon.
    ///      Queues 4 tickets for each of 100 levels [ticketStart, ticketStart+99].
    ///      Includes lootbox (20% of price during presale, 10% after).
    ///      Frozen stats don't increment until game reaches the frozen level.
    ///
    ///      Fund distribution - Level 0: 30% next / 70% future.
    ///      Fund distribution - Other levels: 5% next / 95% future.
    ///
    ///      Example at level 1: 4 tickets each for levels 1-100, stats boosted, frozen until 100.
    ///      Example at level 51: 4 tickets each for levels 51-150, stats boosted, frozen until 150.
    /// @param buyer Player address to receive bundle rewards (address(0) = msg.sender).
    /// @param quantity Number of bundles to purchase.
    function purchaseWhaleBundle(
        address buyer,
        uint256 quantity
    ) external payable {
        buyer = _resolvePlayer(buyer);
        _purchaseWhaleBundleFor(buyer, quantity);
    }

    function _purchaseWhaleBundleFor(address buyer, uint256 quantity) private {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_WHALE_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameWhaleModule.purchaseWhaleBundle.selector,
                    buyer,
                    quantity
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @notice Purchase a 10-level lazy pass (direct in-game activation).
    /// @dev Available at levels 0-2 or x9 (9, 19, 29...), or with a valid lazy pass boon.
    ///      Levels 0-2: flat 0.24 ETH. Levels 3+: sum of per-level ticket prices across 10-level window.
    /// @param buyer Player address to receive pass (address(0) = msg.sender).
    function purchaseLazyPass(address buyer) external payable {
        buyer = _resolvePlayer(buyer);
        _purchaseLazyPassFor(buyer);
    }

    function _purchaseLazyPassFor(address buyer) private {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_WHALE_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameWhaleModule.purchaseLazyPass.selector,
                    buyer
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @notice Purchase a deity pass for a specific symbol (0-31).
    /// @param buyer Player address to receive pass (address(0) = msg.sender).
    /// @param symbolId Symbol to claim (0-31: Q0 Crypto 0-7, Q1 Zodiac 8-15, Q2 Cards 16-23, Q3 Dice 24-31).
    function purchaseDeityPass(address buyer, uint8 symbolId) external payable {
        buyer = _resolvePlayer(buyer);
        _purchaseDeityPassFor(buyer, symbolId);
    }

    function _purchaseDeityPassFor(address buyer, uint8 symbolId) private {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_WHALE_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameWhaleModule.purchaseDeityPass.selector,
                    buyer,
                    symbolId
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @notice Place Full Ticket Degenerette bets (4 traits, match-based payouts).
    /// @param player The betting player (address(0) = msg.sender).
    /// @param currency Currency type (0=ETH, 1=BURNIE, 2=unsupported, 3=WWXRP).
    /// @param amountPerTicket Bet amount per ticket.
    /// @param ticketCount Number of spins (1-10). Each spin resolves independently.
    /// @param customTicket Custom packed traits.
    /// @param heroQuadrant Hero quadrant (0-3) for payout boost, or 0xFF for no hero.
    function placeDegeneretteBet(
        address player,
        uint8 currency,
        uint128 amountPerTicket,
        uint8 ticketCount,
        uint32 customTicket,
        uint8 heroQuadrant
    ) external payable {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_DEGENERETTE_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameDegeneretteModule
                        .placeDegeneretteBet
                        .selector,
                    _resolvePlayer(player),
                    currency,
                    amountPerTicket,
                    ticketCount,
                    customTicket,
                    heroQuadrant
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @notice Resolve multiple Degenerette bets once RNG is available.
    /// @param player The betting player (address(0) = msg.sender).
    /// @param betIds Bet ids for the player.
    function resolveDegeneretteBets(
        address player,
        uint64[] calldata betIds
    ) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_DEGENERETTE_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameDegeneretteModule.resolveBets.selector,
                    _resolvePlayer(player),
                    betIds
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @notice Consume coinflip boon for next coinflip stake bonus.
    /// @dev Access: COIN or COINFLIP contract only.
    ///      Signature: consumeCoinflipBoon(address player) — the player whose boon to consume.
    ///      The signature matches the module function exactly (identical selector), so the
    ///      calldata forwards as-is — re-encoding here would cost contract-size headroom for
    ///      no behavior change.
    /// @return boostBps The boost in basis points to apply.
    /// @custom:reverts E If caller is not COIN or COINFLIP contract.
    function consumeCoinflipBoon(
        address
    ) external returns (uint16 boostBps) {
        if (
            msg.sender != ContractAddresses.COIN &&
            msg.sender != ContractAddresses.COINFLIP
        ) revert E();
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_BOON_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
        return abi.decode(data, (uint16));
    }

    /// @notice Consume decimator boon for burn bonus.
    /// @dev Access: COIN contract only.
    /// @param player The player whose boon to consume.
    /// @return boostBps The boost in basis points to apply.
    /// @custom:reverts E If caller is not COIN contract.
    function consumeDecimatorBoon(
        address player
    ) external returns (uint16 boostBps) {
        if (msg.sender != ContractAddresses.COIN) revert E();
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_BOON_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameBoonModule.consumeDecimatorBoost.selector,
                    player
                )
            );
        if (!ok) _revertDelegate(data);
        return abi.decode(data, (uint16));
    }

    /// @notice Get raw deity boon state for off-chain or viewer contract computation.
    /// @param deity The deity address to query.
    /// @return dailySeed RNG seed for today's boon generation (0 until today's VRF word lands).
    /// @return day Current day index.
    /// @return usedMask Bitmask of slots already used (bit i = slot i used).
    /// @return decimatorOpen Whether decimator boons are available.
    /// @return deityPassAvailable Whether deity pass boons can be generated.
    function deityBoonData(
        address deity
    )
        external
        view
        returns (
            uint256 dailySeed,
            uint24 day,
            uint8 usedMask,
            bool decimatorOpen,
            bool deityPassAvailable
        )
    {
        day = _simulatedDayIndex();
        usedMask = deityBoonDay[deity] == day ? deityBoonUsedMask[deity] : 0;
        decimatorOpen = decWindowOpen;
        deityPassAvailable = deityPassOwners.length < 32; // DEITY_PASS_MAX_TOTAL (see LootboxModule)
        // 0 until today's VRF word lands — callers render no boons while it's 0
        // (mirrors the rngWordByDay[day] gate on issueDeityBoon). No placeholder
        // seed: a preview built from fake entropy wouldn't match the real boons.
        dailySeed = rngWordByDay[day];
    }

    /// @notice Issue a deity boon to a recipient.
    /// @param deity Deity issuing the boon (address(0) = msg.sender).
    /// @param recipient Recipient of the boon.
    /// @param slot Slot index (0-2).
    /// @custom:reverts E If deity attempts to issue boon to themselves.
    function issueDeityBoon(
        address deity,
        address recipient,
        uint8 slot
    ) external {
        deity = _resolvePlayer(deity);
        if (recipient == deity) revert E();
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_LOOTBOX_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameLootboxModule.issueDeityBoon.selector,
                    deity,
                    recipient,
                    slot
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @dev Process mint payment and return amount contributed to prize pool.
    ///      Handles three payment modes with strict validation:
    ///
    ///      DirectEth: msg.value must be >= amount (overage ignored for accounting)
    ///      Claimable: msg.value must be 0, deduct from claimableWinnings
    ///      Combined: ETH first (any amount ≤ cost), then claimable for rest
    ///
    ///      SECURITY: Leaves 1 wei sentinel in claimable to prevent zeroing.
    ///      INVARIANT: claimablePool is decremented by claimableUsed.
    ///
    /// @param player Player whose claimable balance to check/deduct.
    /// @param amount Total cost in wei to cover.
    /// @param payKind Payment method enum.
    /// @return prizeContribution Amount contributing to next/future prize pools.
    /// @return newClaimableBalance Player's claimable balance after deduction (0 if DirectEth).
    function _processMintPayment(
        address player,
        uint256 amount,
        MintPaymentKind payKind
    ) private returns (uint256 prizeContribution, uint256 newClaimableBalance) {
        uint256 ethUsed;
        uint256 claimableUsed;
        if (payKind == MintPaymentKind.DirectEth) {
            // Direct ETH: fresh ETH first (overpay ignored), afking covers any shortfall;
            // claimable is skipped on this kind.
            ethUsed = msg.value < amount ? msg.value : amount;
        } else if (payKind == MintPaymentKind.Claimable) {
            // No fresh ETH allowed: draw claimable to the 1-wei sentinel, then afking.
            if (msg.value != 0) revert E();
            uint256 claimable = _claimableOf(player);
            if (claimable > 1) {
                uint256 available = claimable - 1; // Preserve 1 wei sentinel
                claimableUsed = amount < available ? amount : available;
                if (claimableUsed != 0) {
                    unchecked {
                        newClaimableBalance = claimable - claimableUsed;
                    }
                    _debitClaimable(player, claimableUsed);
                }
            }
        } else if (payKind == MintPaymentKind.Combined) {
            // ETH first, then claimable to the sentinel, then afking for any remainder.
            if (msg.value > amount) revert E();
            ethUsed = msg.value;
            uint256 remaining = amount - msg.value;
            if (remaining != 0) {
                uint256 claimable = _claimableOf(player);
                if (claimable > 1) {
                    uint256 available = claimable - 1; // Preserve 1 wei sentinel
                    claimableUsed = remaining < available
                        ? remaining
                        : available;
                    if (claimableUsed != 0) {
                        unchecked {
                            newClaimableBalance = claimable - claimableUsed;
                        }
                        _debitClaimable(player, claimableUsed);
                    }
                }
            }
        } else {
            revert E();
        }

        // Afking tier: the player's prepaid afking covers whatever fresh ETH + claimable did
        // not. afking is fresh-ETH-equivalent (own deposited principal), so it counts toward
        // prizeContribution. Reverts when the three tiers together fall short of the cost.
        uint256 afkingUsed;
        uint256 shortfall = amount - ethUsed - claimableUsed;
        if (shortfall != 0) {
            if (_afkingOf(player) < shortfall) revert E();
            afkingUsed = shortfall;
            _debitAfking(player, afkingUsed);
        }
        prizeContribution = ethUsed + claimableUsed + afkingUsed;

        if (claimableUsed != 0) {
            claimablePool -= uint128(claimableUsed);
            emit ClaimableSpent(
                player,
                claimableUsed,
                newClaimableBalance,
                payKind,
                amount
            );
        }
        if (afkingUsed != 0) {
            claimablePool -= uint128(afkingUsed);
            emit AfkingSpent(player, afkingUsed);
        }
    }

    /*+======================================================================+
      |                       TICKET QUEUEING                                |
      +======================================================================+
      |  Tickets are queued for batch processing rather than minted immediately.|
      |  This prevents gas exhaustion from large purchases.                  |
      +======================================================================+*/

    /*+================================================================================================================+
      |                    DELEGATE MODULE HELPERS                                                                     |
      +================================================================================================================+
      |  Internal functions that delegatecall into specialized modules.                                                |
      |  All modules MUST inherit DegenerusGameStorage for slot alignment.                                             |
      |                                                                                                                |
      |  Modules:                                                                                                      |
      |  • GAME_ADVANCE_MODULE      - Daily advance, VRF, daily processing                                             |
      |  • GAME_BOON_MODULE         - Deity boon effects and activation                                                |
      |  • GAME_DECIMATOR_MODULE    - Decimator claim credits and lootbox payouts                                       |
      |  • GAME_DEGENERETTE_MODULE  - Degenerette bet placement and resolution                                          |
      |  • GAME_JACKPOT_MODULE      - Jackpot calculations and payouts                                                  |
      |  • GAME_LOOTBOX_MODULE      - Lootbox open, credit, and payout                                                  |
      |  • GAME_MINT_MODULE         - Mint data recording, airdrop multipliers                                          |
      |  • GAME_WHALE_MODULE        - Whale bundle purchases and whale pass claims                                      |
      |                                                                                                                |
      |  SECURITY: delegatecall executes module code in this contract's                                                |
      |  context, with access to all storage. Modules are constant addresses.                                          |
      +================================================================================================================+*/

    /// @dev Bubble up revert reason from delegatecall failure.
    ///      Uses assembly to preserve original error data.
    /// @param reason The error bytes from failed delegatecall.
    function _revertDelegate(bytes memory reason) private pure {
        if (reason.length == 0) revert E();
        assembly ("memory-safe") {
            revert(add(32, reason), mload(reason))
        }
    }

    /// @dev Record mint data via mint module delegatecall.
    ///      Updates player's mint history.
    /// @param player Player address being credited.
    /// @param lvl Level at which mint occurred.
    /// @param mintUnits Number of mint units purchased.
    function _recordMintDataModule(
        address player,
        uint24 lvl,
        uint32 mintUnits
    ) private {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_MINT_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameMintModule.recordMintData.selector,
                    player,
                    lvl,
                    mintUnits
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /*+========================================================================================+
      |                    DECIMATOR JACKPOT LOGIC                                             |
      +========================================================================================+*/

    /// @notice Record a Decimator burn for jackpot eligibility.
    /// @dev Access: COIN contract only (enforced in module).
    ///      Signature: recordDecBurn(address player, uint24 lvl, uint8 bucket, uint256 baseAmount,
    ///      uint256 multBps) — the player, the current game level, the player's chosen denominator
    ///      (2-12), the burn amount before multiplier, and the multiplier in basis points
    ///      (10000 = 1x). The signature matches the module function exactly (identical selector),
    ///      so the calldata forwards as-is — re-encoding here would cost contract-size headroom for
    ///      no behavior change.
    /// @return bucketUsed The bucket actually used (may differ from requested if not an improvement).
    function recordDecBurn(
        address,
        uint24,
        uint8,
        uint256,
        uint256
    ) external returns (uint8 bucketUsed) {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_DECIMATOR_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
        if (data.length == 0) revert E();
        return abi.decode(data, (uint8));
    }

    /// @notice Snapshot Decimator jackpot winners for deferred claims.
    /// @dev Access: Game-only (self-call).
    ///      Signature: runDecimatorJackpot(uint256 poolWei, uint24 lvl, uint256 rngWord) — the
    ///      total ETH prize pool for this level, the level number being resolved, and the
    ///      VRF-derived randomness seed. The signature matches the module function exactly
    ///      (identical selector), so the calldata forwards as-is — re-encoding here would cost
    ///      contract-size headroom for no behavior change.
    /// @return returnAmountWei Amount to return (non-zero if no winners or already snapshotted).
    function runDecimatorJackpot(
        uint256,
        uint24,
        uint256
    ) external returns (uint256 returnAmountWei) {
        if (msg.sender != address(this)) revert E();
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_DECIMATOR_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
        if (data.length == 0) revert E();
        return abi.decode(data, (uint256));
    }

    /// @notice Execute BAF jackpot at a level-multiple-of-10 transition.
    /// @dev Access: Game-only (self-call from AdvanceModule orchestration).
    ///      Signature: runBafJackpot(uint256 poolWei, uint24 lvl, uint256 rngWord) — the ETH
    ///      allocated to this BAF tier, the level being resolved, and the VRF-derived randomness
    ///      seed. The signature matches the module function exactly (identical selector), so the
    ///      calldata forwards as-is — re-encoding here would cost contract-size headroom for no
    ///      behavior change.
    /// @return claimableDelta ETH added to claimable pool.
    function runBafJackpot(
        uint256,
        uint24,
        uint256
    ) external returns (uint256 claimableDelta) {
        if (msg.sender != address(this)) revert E();
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_JACKPOT_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
        if (data.length == 0) revert E();
        return abi.decode(data, (uint256));
    }

    // -------------------------------------------------------------------------
    // Terminal Decimator (Death Bet)
    // -------------------------------------------------------------------------

    /// @notice Record a terminal decimator burn.
    /// @dev Delegatecalls to DecimatorModule. Access: coin contract only.
    ///      Signature: recordTerminalDecBurn(address player, uint24 lvl, uint256 baseAmount) —
    ///      the player performing the burn, the current game level, and the burn amount before
    ///      the time-weighted multiplier. The signature matches the module function exactly
    ///      (identical selector), so the calldata forwards as-is — re-encoding here would cost
    ///      contract-size headroom for no behavior change.
    function recordTerminalDecBurn(
        address,
        uint24,
        uint256
    ) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_DECIMATOR_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
    }

    /// @notice Apply the caller's final-day terminal decimator streak boost.
    /// @dev Delegatecalls to DecimatorModule. Permissionless; credits msg.sender.
    ///      The signature matches the module function exactly (identical selector), so the calldata
    ///      forwards as-is — re-encoding here would cost contract-size headroom for no behavior change.
    function boostTerminalDecimator() external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_DECIMATOR_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
    }

    /// @notice Resolve terminal decimator at GAMEOVER.
    /// @dev Access: Game-only (self-call from handleGameOverDrain).
    ///      Signature: runTerminalDecimatorJackpot(uint256 poolWei, uint24 lvl, uint256 rngWord) —
    ///      the total ETH prize pool for terminal decimator resolution, the level number at which
    ///      gameover was triggered, and the VRF-derived randomness seed for winner selection. The
    ///      signature matches the module function exactly (identical selector), so the calldata
    ///      forwards as-is — re-encoding here would cost contract-size headroom for no behavior change.
    /// @return returnAmountWei Amount to return (non-zero if no winners or already resolved).
    function runTerminalDecimatorJackpot(
        uint256,
        uint24,
        uint256
    ) external returns (uint256 returnAmountWei) {
        if (msg.sender != address(this)) revert E();
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_DECIMATOR_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
        if (data.length == 0) revert E();
        return abi.decode(data, (uint256));
    }

    /// @notice Terminal decimator window. Always open except lastPurchaseDay and gameOver.
    /// @return open True if terminal decimator burns are allowed.
    /// @return lvl Current game level.
    function terminalDecWindow() external view returns (bool open, uint24 lvl) {
        lvl = level;
        open = !gameOver && !lastPurchaseDay;
    }

    /// @notice Terminal jackpot for x00 levels: Day-5-style bucket distribution.
    /// @dev Access: Game-only (self-call). Delegatecalls to JackpotModule.
    ///      Updates claimablePool internally — callers must NOT double-count.
    ///      Signature: runTerminalJackpot(uint256 poolWei, uint24 targetLvl, uint256 rngWord) —
    ///      the total ETH to distribute, the level to sample winners from, and the VRF entropy
    ///      seed. The signature matches the module function exactly (identical selector), so the
    ///      calldata forwards as-is — re-encoding here would cost contract-size headroom for no
    ///      behavior change.
    /// @return paidWei Total ETH distributed.
    function runTerminalJackpot(
        uint256,
        uint24,
        uint256
    ) external returns (uint256 paidWei) {
        if (msg.sender != address(this)) revert E();
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_JACKPOT_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
        if (data.length == 0) revert E();
        return abi.decode(data, (uint256));
    }

    /// @notice Emit DailyWinningTraits via jackpot module.
    /// @dev Access: Game-only (self-call). Delegatecalls to JackpotModule.
    ///      Used at purchaseLevel==1 where payDailyJackpot is skipped.
    ///      Signature: emitDailyWinningTraits(uint24 lvl, uint256 randWord, uint24 bonusTargetLevel)
    ///      — lvl is unused (preserved for signature compatibility), then the VRF entropy seed and
    ///      the target level for the first coin distribution. The signature matches the module
    ///      function exactly (identical selector), so the calldata forwards as-is — re-encoding
    ///      here would cost contract-size headroom for no behavior change.
    function emitDailyWinningTraits(
        uint24,
        uint256,
        uint24
    ) external {
        if (msg.sender != address(this)) revert E();
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_JACKPOT_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
    }

    /// @notice Permissionlessly resolve `player`'s Decimator jackpot claim (value credits to player).
    /// @dev Signature: claimDecimatorJackpot(address player, uint24 lvl) — the winner whose
    ///      claim to resolve, and the level to claim from (must be the last decimator). The
    ///      signature matches the module function exactly (identical selector), so the calldata
    ///      forwards as-is — re-encoding here would cost contract-size headroom for no behavior change.
    function claimDecimatorJackpot(address, uint24) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_DECIMATOR_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
    }

    /// @notice Permissionlessly resolve Decimator jackpot claims for a batch of players
    ///         (address[] players, uint24 lvl).
    /// @dev Non-claimable entries are skipped, not reverted. The signature matches the module
    ///      function exactly (identical selector), so the calldata forwards as-is — re-encoding
    ///      the array here would cost contract-size headroom for no behavior change.
    function claimDecimatorJackpotMany(
        address[] calldata,
        uint24
    ) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_DECIMATOR_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
    }

    /// @notice Claim terminal Decimator jackpot for caller.
    /// @dev Only callable post-GAMEOVER. Level is read from the resolved claim round.
    ///      The signature matches the module function exactly (identical selector), so the calldata
    ///      forwards as-is — re-encoding here would cost contract-size headroom for no behavior change.
    function claimTerminalDecimatorJackpot() external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_DECIMATOR_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
    }


    /*+========================================================================================+
      |                    CLAIMING WINNINGS (ETH)                                             |
      +========================================================================================+
      |  Players claim accumulated winnings from ContractAddresses.JACKPOTS, affiliates,       |
      |  and endgame payouts through the claimWinnings() function.                              |
      |                                                                                        |
      |  SECURITY:                                                                             |
      |  • Uses CEI pattern (Checks-Effects-Interactions)                                      |
      |  • Leaves 1 wei sentinel for gas optimization on future credits                        |
      |  • Falls back to stETH if ETH balance insufficient                                     |
      |  • claimablePool is decremented before external call                                   |
      +========================================================================================+*/

    /// @notice Emitted when claimable ETH winnings are paid out.
    /// @param player Player whose balance is claimed.
    /// @param caller Address that initiated the claim.
    /// @param amount ETH amount paid (excludes 1 wei sentinel).
    event WinningsClaimed(
        address indexed player,
        address indexed caller,
        uint256 amount
    );

    /// @notice Emitted when a funding source withdraws its prepaid afking ETH.
    /// @param player The funding source (msg.sender) whose bucket was debited.
    /// @param amount ETH amount withdrawn (wei).
    event AfkingWithdrew(address indexed player, uint256 amount);

    /// @notice Emitted when claimable winnings are spent during a mint payment.
    /// @param player The player whose claimable balance was used.
    /// @param amount Amount of claimable ETH spent.
    /// @param newBalance Player's new claimable balance after spending.
    /// @param payKind Payment method used for the mint.
    /// @param costWei Total mint cost in wei.
    event ClaimableSpent(
        address indexed player,
        uint256 amount,
        uint256 newBalance,
        MintPaymentKind payKind,
        uint256 costWei
    );

    /// @notice Claim accrued ETH winnings.
    /// @dev Aggregates all winnings: affiliates, ContractAddresses.JACKPOTS, endgame payouts.
    ///      Uses pull pattern for security (CEI: check balance, update state, then transfer).
    ///
    ///      GAS OPTIMIZATION: Leaves 1 wei sentinel so subsequent credits remain
    ///      non-zero → cheaper SSTORE (cold→warm vs cold→zero→warm).
    ///
    ///      SECURITY: Reverts if balance ≤ 1 wei (nothing to claim).
    /// @param player Player address to claim for (address(0) = msg.sender).
    function claimWinnings(address player) external {
        player = _resolvePlayer(player);
        _claimWinningsInternal(player, false);
        // Cashout-curse SET runs in the Game's context via delegatecall (hosted in
        // GameAfkingModule to keep the Game under the EIP-170 ceiling).
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_AFKING_MODULE
            .delegatecall(
                abi.encodeWithSelector(IGameAfkingModule.maybeCurse.selector, player)
            );
        if (!ok) _revertDelegate(data);
    }

    /// @notice Claim accrued ETH winnings with stETH-first payout.
    /// @dev Restricted to self-claims by the vault contract.
    function claimWinningsStethFirst() external {
        if (msg.sender != ContractAddresses.VAULT) revert E();
        _claimWinningsInternal(msg.sender, true);
    }

    function _claimWinningsInternal(address player, bool stethFirst) private {
        if (_goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0) revert E();
        uint256 amount = _claimableOf(player);
        // Decision B (GAMEOVER-01): post-gameOver the claim ALSO pays the caller's prepaid
        // afking ETH (lazy per-player merge — no unbounded loop). Pre-gameOver afkingFunding
        // stays its own bucket (spent by afking auto-buys / reclaimed via withdrawAfkingFunding).
        // Both this merge and withdrawAfkingFunding zero the SAME bucket → no double-spend.
        uint256 afking = gameOver ? _afkingOf(player) : 0;
        if (amount <= 1 && afking == 0) revert E();
        uint256 payout;
        unchecked {
            if (amount > 1) {
                _debitClaimable(player, amount - 1); // Leave sentinel
                payout = amount - 1;
            }
            if (afking != 0) {
                _debitAfking(player, afking);
                payout += afking;
            }
        }
        claimablePool -= uint128(payout); // CEI: update state before external call (checked math)
        emit WinningsClaimed(player, msg.sender, payout);
        if (stethFirst) {
            _payoutWithEthFallback(player, payout);
        } else {
            _payoutWithStethFallback(player, payout);
        }
    }

    /// @notice Fund a player's prepaid afking ETH bucket (consumed by the AfKing afking auto-buy).
    /// @dev Permissionless (fund anyone) — the AfKing subscribe-forward (A2) and the OPEN-E
    ///      operator-funding case both route here. The Game's bare receive() routes msg.value to
    ///      the prize pool, so afking deposits MUST use this dedicated entrypoint. The reservation
    ///      rides inside claimablePool (no separate aggregate) — credited in tandem.
    /// @param player The beneficiary whose afkingFunding bucket is credited.
    function depositAfkingFunding(address player) external payable {
        if (player == address(0)) revert E();
        _creditAfkingValue(player, msg.value);
    }

    /// @notice Withdraw prepaid afking ETH — the funding source reclaims its own balance.
    /// @dev Un-brickable strict CEI: the GO_SWEPT guard is LINE 1 (before any debit), so a
    ///      post-final-sweep withdraw reverts cleanly instead of underflowing claimablePool
    ///      (which the sweep zeroes). Both debits land BEFORE the .call, so a re-entrant second
    ///      call re-reads the already-debited balance and reverts. Available always pre-sweep
    ///      (mid-game, after cancel, post-gameOver). The claimablePool debit stays checked math.
    /// @param amount ETH amount (wei) to withdraw from the caller's afkingFunding bucket.
    function withdrawAfkingFunding(uint256 amount) external {
        if (_goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0) revert E();
        if (amount == 0) return;
        uint256 bal = _afkingOf(msg.sender);
        if (amount > bal) revert E();
        _debitAfking(msg.sender, amount);
        claimablePool -= uint128(amount); // tandem release (checked math)
        (bool ok, ) = msg.sender.call{value: amount}("");
        if (!ok) revert E();
        emit AfkingWithdrew(msg.sender, amount);
    }

    /// @notice The canonical per-player prepaid afking ETH balance (replaces AfKing.poolOf).
    /// @param player The player to query.
    /// @return The player's afkingFunding balance (wei).
    function afkingFundingOf(address player) external view returns (uint256) {
        return _afkingOf(player);
    }

    /// @notice Claim DGNRS affiliate rewards for the current level.
    /// @dev Thin delegatecall dispatch stub into DegenerusGameBingoModule's
    ///      claimAffiliateDgnrs body. The delegatecall MUST be preserved (not a direct
    ///      module call): the body invokes dgnrs.transferFromPool (onlyGame) and
    ///      coinflip.creditFlip (onlyFlipCreditors), both of which authorize on
    ///      msg.sender == GAME — so the logic has to execute in the Game's context.
    ///      Signature: claimAffiliateDgnrs(address player) — the affiliate address to claim for
    ///      (address(0) = msg.sender). The signature matches the module function exactly
    ///      (identical selector), so the calldata forwards as-is — re-encoding here would cost
    ///      contract-size headroom for no behavior change.
    function claimAffiliateDgnrs(address) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_BINGO_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
    }

    /*+======================================================================+
      |                 AUTO-WORK + AFKING BATCH                        |
      +======================================================================+
      |  Permissionless layer letting any caller settle pending game work    |
      |  on others' behalf for a small gas-pegged BURNIE reward paid as       |
      |  coinflip stake credit (deferred mint). Resolution writes game        |
      |  storage directly, so it lives in-game by construction.               |
      +======================================================================+*/

    /// @dev Flat ~1-BURNIE "lose" reward for the Degenerette resolve helper, paid ONCE per tx
    ///      at >=3 non-WWXRP resolutions (D-05b). A count-independent consolation flip-credit;
    ///      the bet-stake gate (>=3 placed bets at the house edge) makes every self-resolve
    ///      farm net-negative, so it is intentionally NOT pegged to the per-resolve marginal.
    uint256 private constant RESOLVE_FLAT_BURNIE = 1e18;

    /// @notice Permissionlessly resolve a caller-supplied list of Degenerette bets.
    /// @dev AUTO-01/02. Items are parallel arrays: item i = (players[i], betIds[i]),
    ///      front-to-back. Item 0 is the caller's own probe: if it is already resolved
    ///      (degeneretteBets[players[0]][betIds[0]] == 0) a competitor got ahead, so the
    ///      whole list reverts with BatchAlreadyTaken (a loser-gas cap, reusing the SLOAD
    ///      item 0 needs anyway). Items 1..N are isolated per-item (a stale/reverting item
    ///      skips). The reward is a FLAT ~1-BURNIE creditFlip granted ONCE (REW-02) at >=3
    ///      successfully-resolved NON-WWXRP bets (D-05b); WWXRP (currency == 3) resolves but
    ///      never counts toward the gate (AUTO-04). Zero resolutions revert NoWork(); 1-2
    ///      resolved commit UNPAID (never strand the trailing tail). Any caller including a
    ///      self-resolver (REW-04, no caller restriction).
    /// @param players Bet owners, grouped/ordered by the caller (item 0 is the probe).
    /// @param betIds Bet ids, parallel to players.
    function degeneretteResolve(
        address[] calldata players,
        uint64[] calldata betIds
    ) external {
        uint256 len = players.length;
        if (len == 0 || betIds.length != len) revert E();

        // AUTO-02 short-circuit: probe item 0 (the caller's own choice). A resolved
        // bet is deleted (slot == 0), so a zero slot means a competitor got ahead.
        if (degeneretteBets[players[0]][betIds[0]] == 0) revert BatchAlreadyTaken();

        uint256 successCount;
        uint256 totalResolved;
        for (uint256 i; i < len; ) {
            uint256 betPacked = degeneretteBets[players[i]][betIds[i]];
            // currency bits [42..43]: WWXRP is the most +EV currency, so it is excluded
            // from the >=3 reward gate to keep the faucet closed (AUTO-04).
            uint8 currency = uint8((betPacked >> 42) & 0x3);
            // Per-item isolation: a stale/reverting/not-ready bet skips, never bricks.
            try this._degeneretteResolveBet(players[i], betIds[i]) {
                // Any resolution counts toward the no-work gate; only non-WWXRP
                // resolutions count toward the >=3 flat-reward gate (AUTO-04).
                unchecked {
                    ++totalResolved;
                    if (currency != 3) ++successCount;
                }
            } catch {}
            unchecked {
                ++i;
            }
        }

        // Flat ~1-BURNIE "lose" (D-05b): pay ONCE at >=3 non-WWXRP resolutions; revert
        // NoWork() if nothing resolved; 1-2 resolved commit UNPAID (never strand the tail).
        if (totalResolved == 0) revert NoWork();
        if (successCount >= 3) coinflip.creditFlip(msg.sender, RESOLVE_FLAT_BURNIE);
    }

    /// @notice O(1) discovery: does advanceGame() have pending work?
    /// @dev TRUE for a new-day advance (regardless of rngLock — advance is liveness-critical)
    ///      OR a mid-day partial-drain whose read slot still holds queued tickets. No
    ///      unbounded scan (ROUTER-04).
    function advanceDue() external view returns (bool) {
        if (_simulatedDayIndex() != dailyIdx) return true;
        if (!ticketsFullyProcessed) {
            uint24 lvl = level;
            uint24 purchaseLevel = (!jackpotPhaseFlag &&
                lastPurchaseDay &&
                rngLockedFlag)
                ? lvl
                : lvl + 1;
            if (ticketQueue[_tqReadKey(purchaseLevel)].length > 0) return true;
        }
        return false;
    }

    /// @notice Would `who` earn the mintBurnie advance bounty if they cranked right now?
    /// @dev The advance work is always permitted; this only reflects pay-eligibility
    ///      (the soft must-mint gate), so off-chain keepers can pre-check before cranking.
    function bountyEligible(address who) external view returns (bool) {
        return _bountyEligible(who);
    }

    /// @notice O(1) discovery hint: is there an openable box at the current open frontier?
    /// @dev rngLock/liveness-aware: FALSE during the freeze (the open leg no-ops). Checks the
    ///      frontier index (boxCursorIndex, clamped to the genesis index 1) against LR_INDEX-1
    ///      where words land. O(1), no scan; a drained frontier with boxes at a higher finalized
    ///      index self-heals as the next sweep advances the frontier.
    function boxesPending() external view returns (bool) {
        if (rngLockedFlag || _livenessTriggered()) return false;
        uint48 active = uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK));
        if (active <= 1) return false;
        uint48 finalized = active - 1; // words land at LR_INDEX-1 (the just-finalized index)
        uint48 idx = boxCursorIndex == 0 ? 1 : boxCursorIndex; // the open frontier
        if (idx > finalized) return false; // swept up to the un-finalized active index
        if (lootboxRngWordByIndex[idx] == 0) return false; // frontier index not yet worded
        uint256 effectiveCursor = boxCursorIndex == idx ? boxCursor : 0;
        return boxPlayers[idx].length > effectiveCursor;
    }

    /// @notice True once the permissionless sweep has fully distributed every box at `index`
    ///         (the monotonic open frontier boxCursorIndex has advanced past it). The active /
    ///         finalizing index is not yet complete; indices below the frontier are drained.
    /// @param index Lootbox RNG index to query.
    function boxIndexComplete(uint48 index) external view returns (bool) {
        return index < boxCursorIndex;
    }

    /// @notice Permissionless liveness valve: open ready boxes — AFKING boxes FIRST (up to maxCount),
    ///         then the human-box multi-index sweep with the remaining budget — so any backlog of
    ///         either type clears in caller-sized chunks that stay under the 16.7M per-tx ceiling.
    ///         The caller picks a maxCount their gas affords. For the afking leg maxCount caps boxes
    ///         opened; for the human sweep the remaining budget caps ENTRIES SCANNED (opens + skips),
    ///         which keeps the tx gas-bounded even past a long already-opened / presale-only prefix and
    ///         lets successive calls catch the open frontier up across many finalized indices.
    ///         Unrewarded — only mintBurnie() pays a bounty.
    /// @param maxCount Afking boxes opened + human-sweep entries scanned, both bounded by this.
    /// @return opened Total boxes opened (afking + human).
    function openBoxes(uint256 maxCount) external returns (uint256 opened) {
        if (maxCount == 0) return 0;
        // AfKing boxes first — delegatecall the afking module so the open runs in this Game's
        // storage; drainAfkingBoxes is the afking-side cursor walk (the human-box leg follows).
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_AFKING_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IGameAfkingModule.drainAfkingBoxes.selector,
                    maxCount
                )
            );
        if (!ok) _revertDelegate(data);
        uint256 openedAfking = abi.decode(data, (uint256));
        // Then human boxes with the remaining budget — the multi-index sweep lives in the
        // lootbox module (delegatecall runs it in this Game's storage), mirroring the afking
        // leg above. AUTO-03 walk + per-entry both-leg open are byte-equivalent there.
        if (openedAfking < maxCount) {
            (ok, data) = ContractAddresses
                .GAME_LOOTBOX_MODULE
                .delegatecall(
                    abi.encodeWithSelector(
                        IDegenerusGameLootboxModule.openHumanBoxes.selector,
                        maxCount - openedAfking
                    )
                );
            if (!ok) _revertDelegate(data);
            opened = abi.decode(data, (uint256));
        }
        opened += openedAfking;
    }

    /// @notice Self-call wrapper resolving a single Degenerette bet (per-item isolation).
    /// @dev onlySelf. Reuses the degenerette module's resolveBets machinery with the
    ///      approval gate relaxed for the resolve path only (placement stays gated).
    /// @param player Bet owner.
    /// @param betId Bet id to resolve.
    function _degeneretteResolveBet(address player, uint64 betId) external {
        if (msg.sender != address(this)) revert E();
        uint64[] memory ids = new uint64[](1);
        ids[0] = betId;
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_DEGENERETTE_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameDegeneretteModule.resolveBets.selector,
                    player,
                    ids
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /*+======================================================================+
      |                    LOOTBOX CLAIMS                                   |
      +======================================================================+*/

    /// @notice Claim deferred whale pass rewards from large lootbox wins (>5 ETH).
    /// @dev Unified claim function for all large lootbox rewards.
    ///      Delegates to whale module for deferred whale pass ticket awards.
    /// @param player Player address to claim for (address(0) = msg.sender).
    function claimWhalePass(address player) external {
        player = _resolvePlayer(player);
        _claimWhalePassFor(player);
    }

    function _claimWhalePassFor(address player) private {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_WHALE_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameWhaleModule.claimWhalePass.selector,
                    player
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /*+======================================================================+
      |                    REDEMPTION LOOTBOX                               |
      +======================================================================+*/

    /// @notice Resolve redemption lootboxes for an sDGNRS gambling burn claim.
    /// @dev Called by sDGNRS during claimRedemption. The owed value arrives as forwarded ETH
    ///      (msg.value) plus a stETH top-up for any remainder: msg.value covers 0..amount and the
    ///      rest is pulled via transferFrom (sDGNRS pre-approves GAME for max). This lets a
    ///      partial- or zero-ETH sDGNRS (mid-game depletion) still settle — an ETH-only forward
    ///      would revert and strand the whole claim. Both media credit futurePrizePool and count
    ///      toward the game's claimablePool backing identically. No claimableWinnings[SDGNRS]
    ///      debit occurs — the value was already pulled out of claimable at submit via
    ///      pullRedemptionReserve, so reclassifying claimable here would double-spend it. Splits
    ///      into 5 ETH boxes and resolves each via lootbox module delegatecall.
    /// @param player Player receiving lootbox rewards
    /// @param amount Total lootbox value to resolve (msg.value ETH + the stETH remainder pulled here)
    /// @param rngWord RNG entropy for lootbox resolution
    /// @param activityScore Snapshotted activity score (bps) from burn submission
    function resolveRedemptionLootbox(
        address player,
        uint256 amount,
        uint256 rngWord,
        uint16 activityScore
    ) external payable {
        if (msg.sender != ContractAddresses.SDGNRS) revert E();
        if (amount == 0) return;
        // Forwarded ETH (msg.value) funds the leg; any remainder is pulled as stETH so a
        // partial-ETH sDGNRS can still settle. msg.value must not exceed the leg amount.
        if (msg.value > amount) revert E();
        uint256 stethPortion;
        unchecked { stethPortion = amount - msg.value; }
        if (stethPortion != 0) {
            if (!steth.transferFrom(msg.sender, address(this), stethPortion)) revert E();
        }

        // Credit the just-arrived value to the future prize pool (respects freeze state). The
        // value was segregated out of claimableWinnings[SDGNRS] at submit, so there is no
        // claimable debit here — only a real-value-in credit.
        if (prizePoolFrozen) {
            (uint128 pNext, uint128 pFuture) = _getPendingPools();
            _setPendingPools(pNext, pFuture + uint128(amount));
        } else {
            (uint128 next, uint128 future) = _getPrizePools();
            _setPrizePools(next, future + uint128(amount));
        }

        // Resolve lootboxes in 5 ETH chunks via delegatecall to lootbox module
        uint256 remaining = amount;
        while (remaining != 0) {
            uint256 box = remaining > 5 ether ? 5 ether : remaining;
            (bool ok, bytes memory data) = ContractAddresses
                .GAME_LOOTBOX_MODULE
                .delegatecall(
                    abi.encodeWithSelector(
                        IDegenerusGameLootboxModule
                            .resolveRedemptionLootbox
                            .selector,
                        player,
                        box,
                        rngWord,
                        activityScore
                    )
                );
            if (!ok) _revertDelegate(data);
            remaining -= box;
            rngWord = uint256(keccak256(abi.encode(rngWord)));
        }
    }

    /// @notice Credit the direct half of an sDGNRS redemption claim to `player`'s claimable winnings.
    /// @dev Called by sDGNRS during a live-game claimRedemption. The value arrives with the same
    ///      funding mix as resolveRedemptionLootbox: msg.value covers 0..amount and the rest is
    ///      pulled as stETH via transferFrom (sDGNRS pre-approves GAME for max). The credit rides
    ///      the claimable reserve (claimablePool in tandem). Body lives in the lootbox module (the
    ///      sole redemption-side payable entry); the thin stub forwards the calldata + msg.value.
    ///      Signature: creditRedemptionDirect(address player, uint256 amount). `amount` is the
    ///      total direct-half value (msg.value ETH + the stETH remainder pulled in the module).
    function creditRedemptionDirect(address, uint256) external payable {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_LOOTBOX_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
    }

    /// @notice Physically segregate the sDGNRS redemption reservation as pure ETH or pure stETH.
    /// @dev Called by sDGNRS at gambling-burn submit to reserve the MAX (175%) owed for this burn so
    ///      it can never be re-spent by a concurrent claimable drain (AfKing self-sub, claimWinnings,
    ///      a second same-day claimant). Pure-ETH OR pure-stETH (no mix), fail-closed, donation-robust:
    ///      - ETH leg: if claimableWinnings[SDGNRS] AND the game's liquid ETH both cover `amount`,
    ///        physically move the at-risk ETH out to sDGNRS (CHECKED debit, CEI).
    ///      - stETH leg: otherwise (mid-game ETH depletion, or a stETH donation inflating the submit
    ///        base beyond claimable), sDGNRS's own stETH already backs the reservation in safe custody,
    ///        so no game-side move or ledger debit is needed — the caller's pendingRedemptionEthValue
    ///        records it and the claim pays stETH. Coverage is checked against sDGNRS's stETH balance.
    ///      - Neither pure leg covers => revert (fail-closed; not a realistic state).
    /// @param amount The MAX 175% reservation for this burn.
    /// @custom:reverts E If caller is not sDGNRS, neither pure leg covers `amount`, or the ETH transfer fails.
    function pullRedemptionReserve(uint256 amount) external {
        if (msg.sender != ContractAddresses.SDGNRS) revert E();
        if (amount == 0) return;

        // ETH leg (as today): the claimable[SDGNRS] ledger AND the game's liquid ETH both cover
        // `amount` — segregate the at-risk ETH out to sDGNRS. CHECKED debit (no unchecked); CEI.
        if (
            _claimableOf(ContractAddresses.SDGNRS) >= amount &&
            address(this).balance >= amount
        ) {
            _debitClaimable(ContractAddresses.SDGNRS, amount);
            claimablePool -= uint128(amount);
            (bool ok, ) = payable(ContractAddresses.SDGNRS).call{value: amount}("");
            if (!ok) revert E();
            return;
        }

        // stETH leg (fallback): the ETH side cannot cover (mid-game ETH depletion, or a stETH
        // donation inflated the submit base beyond claimable[SDGNRS]). sDGNRS already holds its own
        // stETH backing in safe custody, so NO game-side move or ledger debit is needed — the
        // reservation is recorded by the caller's pendingRedemptionEthValue and paid in stETH at
        // claim. Coverage is checked against sDGNRS's stETH balance (the basis a donation inflates).
        if (steth.balanceOf(ContractAddresses.SDGNRS) >= amount) {
            return;
        }

        // Neither pure leg covers => fail-closed.
        revert E();
    }

    /// @notice Sell far-future ticket entries to sDGNRS for current-level tickets + cash (-EV exit).
    /// @dev Resolves the seller (operator-honor) then delegatecalls the mint module, which holds the
    ///      far-future salvage logic (kept off this contract for EIP-170 headroom). Quote without
    ///      executing via previewSellFarFutureTickets.
    /// @param player Owner of the far entries / recipient (resolved via _resolvePlayer).
    /// @param levels Target levels to sell from (each 6 <= level - currentLevel <= 100).
    /// @param quantities Whole far tickets to sell at each level.
    /// @param queueIndices Caller-supplied ticketQueue position of the resolved player at each level.
    function sellFarFutureTickets(
        address player,
        uint32[] calldata levels,
        uint256[] calldata quantities,
        uint256[] calldata queueIndices
    ) external {
        player = _resolvePlayer(player);
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_MINT_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameMintModule.sellFarFutureTickets.selector,
                    player,
                    levels,
                    quantities,
                    queueIndices
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @notice Quote a far-future salvage swap WITHOUT executing (the UI offer; -EV by design).
    /// @dev Read-only; shares the exact valuation (curve + daily per-player jitter + ETH/BURNIE
    ///      split) the executing path uses, so the displayed offer matches what would be paid.
    ///      Reverts on an ineligible distance / zero quantity; does NOT check ownership (a quote
    ///      for the given bundle). For a bundle too small to fund one whole current ticket,
    ///      ticketWei == totalBudget and the cash legs are 0 (the executing path reverts on that).
    ///      The cash leg splits into ETH + BURNIE: when sDGNRS holds no BURNIE (or the seed targets
    ///      zero) the whole cash leg is paid in ETH; conserved as ethCashWei + value(burnieTokens).
    /// @return totalFaceWei Sum of priceForLevel(L) * n over all lines (the bundle's face value).
    /// @return totalBudget Total ETH sDGNRS would pay (the -EV offer).
    /// @return ticketWei Portion delivered as current-level tickets.
    /// @return ethCashWei Cash portion delivered as withdrawable ETH claimable.
    /// @return burnieTokens Cash portion delivered as BURNIE (transferred from sDGNRS).
    /// @dev Signature: previewSellFarFutureTickets(address player, uint32[] levels,
    ///      uint256[] quantities). The signature matches the module function exactly (identical
    ///      selector), so the calldata forwards as-is — re-encoding the arrays here would cost
    ///      contract-size headroom for no behavior change.
    function previewSellFarFutureTickets(
        address,
        uint32[] calldata,
        uint256[] calldata
    )
        external
        returns (
            uint256 totalFaceWei,
            uint256 totalBudget,
            uint256 ticketWei,
            uint256 ethCashWei,
            uint256 burnieTokens
        )
    {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_MINT_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
        return
            abi.decode(
                data,
                (uint256, uint256, uint256, uint256, uint256)
            );
    }

    /*+===============================================================================================+
      |                    JACKPOT PAYOUT FUNCTIONS                                                   |
      +===============================================================================================+
      |  Functions for distributing jackpot winnings. Most jackpot logic                              |
      |  lives in the ContractAddresses.GAME_JACKPOT_MODULE (via delegatecall).                       |
      |                                                                                               |
      |  Jackpot Types:                                                                               |
      |  • Daily jackpot - Paid each day to burn ticket holders (day 5 = full pool payout)             |
      |  • Decimator - Special 100-level milestone jackpot (30% of pool)                              |
      |  • BAF - Big-ass-flip jackpot (20% of pool at L%100=0)                                        |
      +===============================================================================================+*/

    /*+======================================================================+
      |                    ADMIN: REWARD VAULT & LIQUIDITY                   |
      +======================================================================+
      |  Admin-only functions for managing ETH/stETH liquidity.              |
      |  Used to optimize yield and maintain sufficient ETH for payouts.     |
      |                                                                      |
      |  SECURITY:                                                           |
      |  • Admin-only access (VRF owner contract)                            |
      |  • Cannot touch claimablePool reserve (protected for player claims)  |
      |  • All operations are value-preserving (no fund extraction)          |
      +======================================================================+*/

    /// @notice Admin-only swap: caller sends ETH in and receives game-held stETH.
    /// @dev Used to rebalance when stETH yield should be converted to ETH.
    ///      Admin must send exact ETH amount equal to stETH received.
    ///      SECURITY: Value-neutral swap, ADMIN cannot extract funds.
    /// @param recipient Address to receive stETH.
    /// @param amount ETH amount to swap (must match msg.value).
    /// @custom:reverts E If caller is not ADMIN, recipient is zero, amount is zero,
    ///                   msg.value doesn't match amount, or insufficient stETH balance.
    function adminSwapEthForStEth(
        address recipient,
        uint256 amount
    ) external payable {
        if (msg.sender != ContractAddresses.ADMIN) revert E();
        if (recipient == address(0)) revert E();
        if (amount == 0 || msg.value != amount) revert E();

        uint256 stBal = steth.balanceOf(address(this));
        if (stBal < amount) revert E();
        if (!steth.transfer(recipient, amount)) revert E();
        emit AdminSwapEthForStEth(recipient, amount);
    }

    /// @notice Stake game-held ETH into stETH via Lido.
    /// @dev Access: vault owner only (DGVE majority holder).
    ///      SECURITY: Must retain ETH to cover player claims, excluding vault/DGNRS
    ///      claimable (those addresses accept stETH payouts natively).
    /// @param amount ETH amount to stake.
    /// @custom:reverts E If caller is not vault owner, amount is zero, insufficient ETH,
    ///                   or staking would dip into player-claim ETH reserve.
    function adminStakeEthForStEth(uint256 amount) external {
        if (!vault.isVaultOwner(msg.sender)) revert E();
        if (amount == 0) revert E();

        uint256 ethBal = address(this).balance;
        if (ethBal < amount) revert E();
        // Vault and DGNRS claimable can be settled in stETH, so exclude from ETH reserve
        uint256 stethSettleable = _claimableOf(ContractAddresses.VAULT) +
            _claimableOf(ContractAddresses.SDGNRS);
        uint256 reserve = claimablePool > stethSettleable
            ? claimablePool - stethSettleable
            : 0;
        if (ethBal <= reserve) revert E();
        uint256 stakeable = ethBal - reserve;
        if (amount > stakeable) revert E();

        // stETH return value intentionally ignored: Lido mints 1:1 for ETH, validated by input checks
        try steth.submit{value: amount}(address(0)) returns (uint256) {} catch {
            revert E();
        }
        emit AdminStakeEthForStEth(amount);
    }

    /*+======================================================================+
      |                    VRF (CHAINLINK) INTEGRATION                       |
      +======================================================================+
      |  Chainlink VRF V2.5 integration for provably fair randomness.        |
      |                                                                      |
      |  LIFECYCLE:                                                          |
      |  1. advanceGame() calls rngGate()                                    |
      |  2. If no valid RNG word, _requestRng() is called                    |
      |  3. Chainlink calls rawFulfillRandomWords() with random word         |
      |  4. Next advanceGame() uses the fulfilled word                       |
      |  5. After processing, _unlockRng() resets for next cycle             |
      |                                                                      |
      |  SECURITY:                                                           |
      |  • RNG lock prevents state manipulation during VRF window            |
      |  • 12-hour timeout allows recovery from stale requests               |
      |  • Governance-gated coordinator rotation via Admin                   |
      |  • Nudge system allows players to influence (not predict) RNG        |
      +======================================================================+*/

    /// @notice Emergency VRF coordinator rotation (governance-gated).
    /// @dev Access: ADMIN only. Stall duration enforced by Admin governance.
    ///      Signature: updateVrfCoordinatorAndSub(address newCoordinator, uint256 newSubId,
    ///      bytes32 newKeyHash) — the new VRF coordinator address, the new subscription ID, and
    ///      the new key hash for the gas lane. The signature matches the module function exactly
    ///      (identical selector), so the calldata forwards as-is — re-encoding here would cost
    ///      contract-size headroom for no behavior change.
    /// @custom:reverts E If caller is not ADMIN.
    function updateVrfCoordinatorAndSub(
        address,
        uint256,
        bytes32
    ) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_ADVANCE_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
    }

    /// @notice Request lootbox RNG when activity threshold and LINK conditions are met.
    /// @dev Callable by anyone. Reverts if daily RNG has not been consumed, if request
    ///      windows are locked, or if pending lootbox value is below threshold.
    ///      The signature matches the module function exactly (identical selector), so the calldata
    ///      forwards as-is — re-encoding here would cost contract-size headroom for no behavior change.
    function requestLootboxRng() external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_ADVANCE_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
    }

    /// @notice Retry a stalled mid-day lootbox RNG request after the timeout window.
    /// @dev Callable by anyone. Reverts unless a mid-day swap is committed, the VRF
    ///      callback has not delivered, and the retry timeout has elapsed.
    ///      The signature matches the module function exactly (identical selector), so the calldata
    ///      forwards as-is — re-encoding here would cost contract-size headroom for no behavior change.
    function retryLootboxRng() external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_ADVANCE_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
    }

    /// @notice Pay BURNIE to nudge the next RNG word by +1.
    /// @dev Cost scales +50% per queued nudge and resets after fulfillment.
    ///      Only available while RNG is unlocked (before VRF request is in-flight).
    ///      MECHANISM: Adds 1 to the VRF word for each nudge, changing outcomes.
    ///      SECURITY: Players cannot predict the base word, only influence it.
    /// @custom:reverts RngLocked If RNG is currently locked (VRF request pending).
    function reverseFlip() external {
        if (rngLockedFlag) revert RngLocked();
        uint256 reversals = totalFlipReversals;
        uint256 cost = _currentNudgeCost(reversals);
        coin.burnCoin(msg.sender, cost);
        uint256 newCount = reversals + 1;
        totalFlipReversals = newCount;
        emit ReverseFlip(msg.sender, newCount, cost);
    }

    /// @dev Calculate nudge cost with compounding.
    ///      Base cost is 100 BURNIE, +50% per queued nudge.
    /// @param reversals Number of nudges already queued.
    /// @return cost BURNIE cost for the next nudge.
    function _currentNudgeCost(
        uint256 reversals
    ) private pure returns (uint256 cost) {
        cost = RNG_NUDGE_BASE_COST;
        while (reversals != 0) {
            cost = (cost * 15) / 10;
            unchecked {
                --reversals;
            }
        }
    }

    /// @notice Chainlink VRF callback for random word fulfillment.
    /// @dev Access: VRF coordinator only.
    ///      Applies any queued nudges before storing the word.
    ///      SECURITY: Validates requestId and coordinator address.
    ///      Signature: rawFulfillRandomWords(uint256 requestId, uint256[] randomWords) — the
    ///      request ID to match, and the array containing the random word (length 1). The
    ///      coordinator-only msg.sender gate lives in the module body (delegatecall preserves
    ///      msg.sender). The signature matches the module function exactly (identical selector),
    ///      so the calldata forwards as-is — re-encoding the array here would cost contract-size
    ///      headroom for no behavior change.
    function rawFulfillRandomWords(
        uint256,
        uint256[] calldata
    ) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_ADVANCE_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
    }

    /*+======================================================================+
      |                    PAYMENT HELPERS                                   |
      +======================================================================+
      |  Internal functions for ETH/stETH payouts.                           |
      |  Implements fallback logic when one asset is insufficient.           |
      +======================================================================+*/

    function _transferSteth(address to, uint256 amount) private {
        if (amount == 0) return;
        if (to == ContractAddresses.SDGNRS) {
            if (!steth.approve(ContractAddresses.SDGNRS, amount)) revert E();
            dgnrs.depositSteth(amount);
            return;
        }
        if (!steth.transfer(to, amount)) revert E();
    }

    /// @dev Send ETH first, then stETH for remainder.
    ///      Used for player claim payouts (ETH preferred).
    ///      Includes retry logic if stETH is short but ETH arrives.
    /// @param to Recipient address.
    /// @param amount Total wei to send.
    function _payoutWithStethFallback(address to, uint256 amount) private {
        if (amount == 0) return;

        // ETH is preferred for player claims, but the untrusted ETH .call MUST run LAST (CEI):
        // _claimWinningsInternal has already debited claimablePool by the full payout, so sending
        // ETH while the stETH remainder is still held would let a reentrant distributeYieldSurplus
        // read that in-flight stETH as unreserved backing and over-distribute it. Mirrors the
        // stETH-before-ETH ordering of _payoutWithEthFallback and the sDGNRS _payEth path.
        uint256 ethBal = address(this).balance;
        uint256 ethSend = amount <= ethBal ? amount : ethBal;
        uint256 remaining = amount - ethSend;

        // Move the stETH leg out first (a stETH transfer hands no control to `to`); any stETH
        // shortfall is folded into the single ETH .call below.
        if (remaining != 0) {
            uint256 stBal = steth.balanceOf(address(this));
            uint256 stSend = remaining <= stBal ? remaining : stBal;
            _transferSteth(to, stSend);
            ethSend += remaining - stSend;
        }

        // Untrusted ETH .call LAST — all ledger debits and the stETH transfer have completed.
        // An insufficient self-balance fails the value transfer itself (callee never runs),
        // so the !ok revert below covers the shortfall case.
        if (ethSend != 0) {
            (bool ok, ) = payable(to).call{value: ethSend}("");
            if (!ok) revert E();
        }
    }

    /// @dev Send stETH first, then ETH for remainder.
    ///      Used for vault/DGNRS reserve claims (stETH preferred).
    /// @param to Recipient address.
    /// @param amount Total wei to send.
    function _payoutWithEthFallback(address to, uint256 amount) private {
        if (amount == 0) return;

        uint256 stBal = steth.balanceOf(address(this));
        uint256 stSend = amount <= stBal ? amount : stBal;
        _transferSteth(to, stSend);

        uint256 remaining = amount - stSend;
        if (remaining == 0) return;

        uint256 ethBal = address(this).balance;
        if (ethBal < remaining) revert E();
        (bool ok, ) = payable(to).call{value: remaining}("");
        if (!ok) revert E();
    }

    /*+======================================================================+
      |                   VIEW: GAME STATUS & STATE                          |
      +======================================================================+
      |  Lightweight view functions for UI/frontend consumption. These       |
      |  provide read-only access to game state without gas costs.           |
      +======================================================================+*/

    /// @notice Get the next-pool ratchet target for level progression.
    /// @dev Returns the pre-skim nextPrizePool captured at the previous level
    ///      transition. The current level must accumulate at least this much
    ///      in nextPrizePool to trigger lastPurchaseDay.
    ///      Threshold check uses levelPrizePool[purchaseLevel - 1] = levelPrizePool[level].
    /// @return The ratchet target value (ETH wei).
    function prizePoolTargetView() external view returns (uint256) {
        uint256 pool = levelPrizePool[level];
        return pool != 0 ? pool : BOOTSTRAP_PRIZE_POOL;
    }

    /// @notice Get the prize pool accumulated for the next level.
    /// @dev Mint fees flow into nextPrizePool until target is met.
    /// @return The nextPrizePool value (ETH wei).
    function nextPrizePoolView() external view returns (uint256) {
        return _getNextPrizePool();
    }

    /// @notice Get the unified future pool reserve.
    /// @return The futurePrizePool value (ETH wei).
    function futurePrizePoolView() external view returns (uint256) {
        return _getFuturePrizePool();
    }

    /// @notice Get queued future ticket rewards owed for a level.
    /// @param lvl Target level for the queued tickets.
    /// @param player Player address to query.
    /// @return The number of whole ticket rewards owed (fractional remainder resolves at batch time).
    function ticketsOwedView(
        uint24 lvl,
        address player
    ) external view returns (uint32) {
        return uint32(ticketsOwedPacked[_tqWriteKey(lvl)][player] >> 8);
    }

    /// @notice Get loot box status for a player/index.
    /// @param player Player address to query.
    /// @param lootboxIndex Lootbox RNG index assigned at purchase time.
    /// @return amount ETH amount recorded for the loot box (wei).
    /// @return presale True if presale mode is currently active.
    function lootboxStatus(
        address player,
        uint48 lootboxIndex
    ) external view returns (uint256 amount, bool presale) {
        // Direct storage access - lootboxEth stores the box amount in the low 128 bits.
        uint256 packed = lootboxEth[lootboxIndex][player];
        amount = packed & LB_AMOUNT_MASK;
        presale = _psRead(PS_ACTIVE_SHIFT, PS_ACTIVE_MASK) != 0;
    }

    /// @notice View Degenerette packed bet info for a player/betId.
    /// @param player Player address to query.
    /// @param betId Bet identifier for the player.
    function degeneretteBetInfo(
        address player,
        uint64 betId
    ) external view returns (uint256 packed) {
        return degeneretteBets[player][betId];
    }

    /// @notice Check whether lootbox presale mode is currently active.
    /// @return active True if presale is active.
    function lootboxPresaleActiveFlag() external view returns (bool active) {
        return _psRead(PS_ACTIVE_SHIFT, PS_ACTIVE_MASK) != 0;
    }

    /// @notice Spendable coin-presale-box credit accrued by a player.
    /// @param player Player to query.
    /// @return credit Remaining credit (consumed 1:1 when buying a box).
    function presaleBoxCreditOf(address player) external view returns (uint256 credit) {
        return presaleBoxCredit[player];
    }

    /// @notice Remaining coin-presale-box ETH capacity before the 50-ETH close.
    /// @return remaining ETH still buyable in boxes (0 once presaleOver / sold out).
    function presaleBoxEthRemaining() external view returns (uint256 remaining) {
        if (presaleOver) return 0;
        uint256 sold = presaleBoxEthSold;
        return sold >= PRESALE_BOX_ETH_CAP ? 0 : PRESALE_BOX_ETH_CAP - sold;
    }

    /// @notice Get the current prize pool (jackpots are paid from this).
    /// @return The currentPrizePool value (ETH wei).
    function currentPrizePoolView() external view returns (uint256) {
        return _getCurrentPrizePool();
    }

    /// @notice Get the claimable pool (reserved for player winnings claims).
    /// @return The claimablePool value (ETH wei).
    function claimablePoolView() external view returns (uint256) {
        if (_goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0) return 0;
        return claimablePool;
    }

    /// @notice Check if the final fund forfeiture has executed (all funds forfeited).
    function isFinalSwept() external view returns (bool) {
        return _goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0;
    }

    /// @notice Timestamp when gameover was triggered (0 if game still active).
    function gameOverTimestamp() external view returns (uint48) {
        return uint48(_goRead(GO_TIME_SHIFT, GO_TIME_MASK));
    }

    /// @notice Whether the liveness-timeout game-over trigger is currently active.
    /// @dev Returns true either on day-timeout (365/120) with VRF healthy, or
    ///      whenever VRF has been stalled for _VRF_GRACE_PERIOD. During a sub-grace
    ///      VRF stall, returns false so proposal-based coordinator rotation is possible.
    function livenessTriggered() external view returns (bool) {
        return _livenessTriggered();
    }

    /// @notice Get the yield surplus (stETH appreciation above all pool obligations).
    /// @dev Calculated as: (ETH balance + stETH balance) - (current + next + claimable + future pools)
    /// @return The yield surplus value (ETH wei).
    function yieldPoolView() external view returns (uint256) {
        uint256 totalBalance = address(this).balance +
            steth.balanceOf(address(this));
        uint256 obligations = _getCurrentPrizePool() +
            _getNextPrizePool() +
            claimablePool +
            _getFuturePrizePool() +
            yieldAccumulator;
        if (totalBalance <= obligations) return 0;
        return totalBalance - obligations;
    }

    /// @notice Get the yield accumulator balance (segregated stETH yield reserve).
    /// @return The yield accumulator balance (ETH wei).
    function yieldAccumulatorView() external view returns (uint256) {
        return yieldAccumulator;
    }

    /// @notice Get the current mint price in wei.
    /// @dev Price tiers: intro 0.01/0.02, then cycle 0.04/0.08/0.12/0.16/0.24 ETH.
    /// @return Current price in wei.
    function mintPrice() external view returns (uint256) {
        return PriceLookupLib.priceForLevel(_activeTicketLevel());
    }

    /// @notice Get the VRF random word recorded for a specific day.
    /// @dev Days are indexed from deploy time (day 1 = deploy day).
    /// @param day The day index to query.
    /// @return The random word (0 if no word recorded for that day).
    function rngWordForDay(uint24 day) external view returns (uint256) {
        return rngWordByDay[day];
    }

    /// @notice Check if RNG is currently locked (daily jackpot resolution).
    /// @dev When locked, burns and certain operations are blocked.
    /// @return True if RNG lock is active.
    function rngLocked() external view returns (bool) {
        return rngLockedFlag;
    }

    /// @notice Check if VRF has been fulfilled for current request.
    /// @return True if random word is available for use.
    function isRngFulfilled() external view returns (bool) {
        return rngWordCurrent != 0;
    }

    /// @notice Timestamp of the last successfully processed VRF word.
    /// @dev Used by governance contracts to detect VRF stalls (time-based).
    function lastVrfProcessed() external view returns (uint48) {
        return lastVrfProcessedTimestamp;
    }

    /*+======================================================================+
      |                   VIEW: DECIMATOR & PURCHASE INFO                    |
      +======================================================================+
      |  Status views for decimator window and purchase state.               |
      +======================================================================+*/

    /// @notice Check if decimator window is currently open.
    function decWindow() external view returns (bool) {
        return decWindowOpen;
    }

    /// @notice Jackpot compression tier: 0=normal, 1=compressed (3d), 2=turbo (1d).
    function jackpotCompressionTier() external view returns (uint8) {
        return compressedJackpotFlag;
    }

    /// @notice Returns true when jackpot phase is active.
    function jackpotPhase() external view returns (bool) {
        return jackpotPhaseFlag;
    }

    /// @notice Comprehensive purchase info for UI consumption.
    /// @dev Bundles level, state, flags, and price into single call.
    ///      NOTE: lvl is the active direct-ticket level.
    /// @return lvl Active direct-ticket level.
    /// @return inJackpotPhase True if jackpot phase is active.
    /// @return lastPurchaseDay_ True if prize pool target is met.
    /// @return rngLocked_ True if VRF request is pending.
    /// @return priceWei Current mint price in wei.
    function purchaseInfo()
        external
        view
        returns (
            uint24 lvl,
            bool inJackpotPhase,
            bool lastPurchaseDay_,
            bool rngLocked_,
            uint256 priceWei
        )
    {
        inJackpotPhase = jackpotPhaseFlag;
        lastPurchaseDay_ = (!inJackpotPhase) && lastPurchaseDay;
        lvl = _activeTicketLevel();
        rngLocked_ = rngLockedFlag;
        priceWei = PriceLookupLib.priceForLevel(lvl);
    }

    /*+======================================================================+
      |                   VIEW: PLAYER MINT STATISTICS                       |
      +======================================================================+
      |  Unpack player mint history from the bit-packed mintPacked_ storage. |
      |  See MINT PACKED BIT LAYOUT above for field positions.               |
      +======================================================================+*/

    /// @notice Get combined mint statistics for a player.
    /// @dev Batches multiple stats into single call for gas efficiency.
    /// @param player The player address to query.
    /// @return lvl Current game level.
    /// @return levelCount Total levels with ETH mints.
    /// @return streak Consecutive level mint streak.
    function ethMintStats(
        address player
    ) external view returns (uint24 lvl, uint24 levelCount, uint24 streak) {
        uint256 packed = mintPacked_[player];
        if (packed >> BitPackingLib.HAS_DEITY_PASS_SHIFT & 1 != 0) {
            uint24 currLevel = level;
            return (currLevel, currLevel, currLevel);
        }
        lvl = level;
        levelCount = uint24(
            (packed >> BitPackingLib.LEVEL_COUNT_SHIFT) & BitPackingLib.MASK_24
        );
        streak = _mintStreakEffective(player, _activeTicketLevel());
    }

    /*+======================================================================+
      |                  VIEW: ACTIVITY SCORE CALCULATION                    |
      +======================================================================+
      |  Player activity score multiplier determines airdrop rewards.        |
      |                                                                      |
      |  Activity Score Components (player engagement/loyalty metrics):      |
      |  • Mint streak: +1% per consecutive level minted (cap 50%)           |
      |  • Mint count: +25% for 100% participation, scaled proportionally    |
      |  • Quest streak: +1% per consecutive quest (cap 100%)                |
      |  • Affiliate points: +1% per affiliate point (cap 50%)               |
      |  • Whale pass bonus (active only while frozen):                      |
      |    - 10-level bundle: +10%                                           |
      |    - 100-level bundle: +40%                                          |
      |  • Deity pass bonus: +80% (always active)                            |
      |                                                                      |
      +======================================================================+*/

    /// @notice Calculate player's activity score in basis points.
    /// @dev Activity Score: 50% (streak) + 25% (count) + 100% (quest) + 50% (affiliate) + 40% (whale) = 265% max
    ///      Deity pass adds +80% in place of whale bundle bonus (305% max base).
    ///      Consumers apply their own caps (lootbox EV: 255%, degenerette ROI: 305%, decimator: 235%).
    /// @param player The player address to calculate for.
    /// @return scoreBps Total activity score in basis points.
    function playerActivityScore(
        address player
    ) external view returns (uint256 scoreBps) {
        // Decay-aware effective reward streak: effectiveBaseStreak zeroes a streak that lapsed
        // past its shields, so a stale-high RAW streak (built then abandoned with no quest sync)
        // can no longer inflate terminal-decimator weight, lootbox EV, or sDGNRS claims. Cheap
        // read (decay logic only — no quest-view materialization).
        uint32 streak = quests.effectiveBaseStreak(player);
        return _playerActivityScore(player, streak);
    }

    /*+======================================================================+
      |                   VIEW: CLAIMS & LOOTBOX COUNTS                      |
      +======================================================================+
      |  Read-only accessors for claim balances and deferred lootbox totals. |
      +======================================================================+*/

    /// @notice Get the caller's claimable winnings balance.
    /// @dev Returns 0 if balance is only the 1 wei sentinel.
    /// @return Claimable amount in wei (excludes sentinel).
    function getWinnings() external view returns (uint256) {
        if (_goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0) return 0;
        uint256 stored = _claimableOf(msg.sender);
        if (stored <= 1) return 0;
        unchecked {
            return stored - 1;
        }
    }

    /// @notice Get a player's raw claimable balance (includes the 1 wei sentinel).
    /// @param player Player address to query.
    /// @return Raw claimable balance in wei (includes 1 wei sentinel if any balance exists).
    function claimableWinningsOf(
        address player
    ) external view returns (uint256) {
        if (_goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0) return 0;
        return _claimableOf(player);
    }

    /// @notice Batched afking read — mintPrice + rngLock + per-player claimable in ONE call.
    /// @dev GASOPT-03 (SUBSUMES GASOPT-02): collapses the afking's per-player
    ///      claimableWinningsOf STATICCALLs into one batched call. Values are byte-identical
    ///      to the single-value accessors (same priceForLevel / rngLockedFlag / swept-gate).
    /// @param players The chunk of players to snapshot.
    /// @return mintPriceWei Current mint price (== mintPrice()).
    /// @return rngLocked_ Whether RNG is currently locked (== rngLocked()).
    /// @return claimables Per-player claimable winnings (== claimableWinningsOf(players[i])).
    /// @return afkingFundings Per-player prepaid afking ETH (== afkingFundingOf(players[i])).
    function afkingSnapshot(address[] calldata players) external view returns (uint256 mintPriceWei, bool rngLocked_, uint256[] memory claimables, uint256[] memory afkingFundings) {
        mintPriceWei = PriceLookupLib.priceForLevel(_activeTicketLevel());
        rngLocked_ = rngLockedFlag;
        bool swept = _goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0;
        uint256 n = players.length;
        claimables = new uint256[](n);
        afkingFundings = new uint256[](n);
        for (uint256 i; i < n; ) {
            claimables[i] = swept ? 0 : _claimableOf(players[i]);
            afkingFundings[i] = _afkingOf(players[i]); // raw — mirrors afkingFundingOf (D-MR-01)
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Get pending whale pass claim amount for a player.
    /// @param player Player address to query.
    /// @return Amount of ETH claimable as whale pass tickets.
    function whalePassClaimAmount(
        address player
    ) external view returns (uint256) {
        return whalePassClaims[player];
    }

    /// @notice Whether a player holds a deity pass.
    function hasDeityPass(address player) external view returns (bool) {
        return mintPacked_[player] >> BitPackingLib.HAS_DEITY_PASS_SHIFT & 1 != 0;
    }

    /// @notice Returns the packed mint data for a player.
    /// @dev External view accessor for DegenerusQuests (IDegenerusGame.mintPackedFor).
    /// @param player Player address to query.
    /// @return Raw packed uint256 from mintPacked_.
    function mintPackedFor(address player) external view returns (uint256) {
        return mintPacked_[player];
    }

    /*+======================================================================+
      |                    TRAIT TICKET SAMPLING                             |
      +======================================================================+
      |  View function for sampling burn ticket holders from recent levels.  |
      |  Used for scatter draws and promotional mechanics.                   |
      +======================================================================+*/

    /// @notice Sample up to 4 trait burn tickets from a specific level.
    /// @dev Used by BAF scatter to sample the next level's ticket holders.
    /// @param targetLvl The level to sample from.
    /// @param entropy Random seed (typically VRF word) for trait and offset selection.
    /// @return traitSel Selected trait ID.
    /// @return tickets Array of up to 4 ticket holder addresses.
    function sampleTraitTicketsAtLevel(
        uint24 targetLvl,
        uint256 entropy
    ) external view returns (uint8 traitSel, address[] memory tickets) {
        traitSel = uint8(entropy >> 24);
        address[] storage arr = traitBurnTicket[targetLvl][traitSel];
        uint256 len = arr.length;
        if (len == 0) {
            return (traitSel, new address[](0));
        }

        uint256 take = len > 4 ? 4 : len;
        tickets = new address[](take);
        uint256 start = (entropy >> 40) % len;
        for (uint256 i; i < take; ) {
            tickets[i] = arr[(start + i) % len];
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Sample up to 4 far-future ticket holders from ticketQueue.
    /// @dev View function for BAF far-future selection; samples levels [current+5, current+99].
    ///      Tries up to 10 random levels, returns however many non-zero holders are found (max 4).
    /// @param entropy Random entropy for sampling (typically from VRF).
    /// @return tickets Array of player addresses (length 0-4).
    function sampleFarFutureTickets(
        uint256 entropy
    ) external view returns (address[] memory tickets) {
        uint24 currentLvl = level;
        address[4] memory tmp;
        uint8 found;
        uint256 word = entropy;

        for (uint8 s; s < 10 && found < 4; ) {
            word = uint256(keccak256(abi.encodePacked(word, s)));
            uint24 candidate = currentLvl + 5 + uint24(word % 95);

            address[] storage queue = ticketQueue[_tqFarFutureKey(candidate)];
            uint256 len = queue.length;
            if (len != 0) {
                uint256 idx = (word >> 32) % len;
                address winner = queue[idx];
                if (winner != address(0)) {
                    tmp[found] = winner;
                    unchecked {
                        ++found;
                    }
                }
            }
            unchecked {
                ++s;
            }
        }

        tickets = new address[](found);
        for (uint8 i; i < found; ) {
            tickets[i] = tmp[i];
            unchecked {
                ++i;
            }
        }
    }

    /*+======================================================================+
      |                    VIEW: TRAIT TICKET QUERIES                         |
      +======================================================================+
      |  Read-only functions for querying trait state and game history.      |
      +======================================================================+*/

    /// @notice Count a player's tickets for a specific trait and level.
    /// @dev Paginated for large ticket arrays.
    /// @param trait The trait ID.
    /// @param lvl The level to query.
    /// @param offset Starting index for pagination.
    /// @param limit Maximum entries to scan.
    /// @param player The player address to count.
    /// @return count Number of tickets found in this page.
    /// @return nextOffset Next offset for pagination.
    /// @return total Total tickets in the array.
    function getTickets(
        uint8 trait,
        uint24 lvl,
        uint32 offset,
        uint32 limit,
        address player
    ) external view returns (uint24 count, uint32 nextOffset, uint32 total) {
        address[] storage a = traitBurnTicket[lvl][trait];
        total = uint32(a.length);
        if (offset >= total) return (0, total, total);

        uint256 end = offset + limit;
        if (end > total) end = total;

        for (uint256 i = offset; i < end; ) {
            if (a[i] == player) count++;
            unchecked {
                ++i;
            }
        }
        nextOffset = uint32(end);
    }

    /// @notice Get tickets owed to a player for the current level.
    /// @param player The player address.
    /// @return tickets Number of tickets owed for current level.
    function getPlayerPurchases(
        address player
    ) external view returns (uint32 tickets) {
        tickets = uint32(ticketsOwedPacked[_tqWriteKey(level)][player] >> 8);
    }

    /*+======================================================================+
      |                    DEGENERETTE TRACKING VIEWS                        |
      +======================================================================+*/

    /// @notice Get daily hero wager for a specific quadrant/symbol on a given day.
    /// @param day Day index (from GameTimeLib).
    /// @param quadrant Quadrant (0-3).
    /// @param symbol Symbol index within quadrant (0-7).
    /// @return wagerUnits Amount wagered in 1e14 wei units.
    function getDailyHeroWager(
        uint24 day,
        uint8 quadrant,
        uint8 symbol
    ) external view returns (uint256 wagerUnits) {
        if (quadrant >= 4 || symbol >= 8) return 0;
        uint256 packed = dailyHeroWagers[day][quadrant];
        wagerUnits = (packed >> (uint256(symbol) * 32)) & 0xFFFFFFFF;
    }

    /// @notice Get the winning hero symbol for a given day (most wagered across all quadrants).
    /// @param day Day index (from GameTimeLib).
    /// @return winQuadrant The winning quadrant.
    /// @return winSymbol The winning symbol within that quadrant.
    /// @return winAmount The wagered units for the winner.
    function getDailyHeroWinner(
        uint24 day
    )
        external
        view
        returns (uint8 winQuadrant, uint8 winSymbol, uint256 winAmount)
    {
        for (uint8 q = 0; q < 4; ++q) {
            uint256 packed = dailyHeroWagers[day][q];
            for (uint8 s = 0; s < 8; ++s) {
                uint256 amount = (packed >> (uint256(s) * 32)) & 0xFFFFFFFF;
                if (amount > winAmount) {
                    winAmount = amount;
                    winQuadrant = q;
                    winSymbol = s;
                }
            }
        }
    }

    /*+======================================================================+
      |                    RECEIVE FUNCTION                                  |
      +======================================================================+
      |  Accept plain ETH and credit it to the sender's prepaid afking       |
      |  balance (withdrawable; not a prize-pool donation).                  |
      +======================================================================+*/

    /// @notice Accept plain ETH and credit it to the sender's prepaid afking balance.
    /// @dev Bare transfers become the sender's own withdrawable afking funds (not a prize-pool
    ///      donation). Blocked once the game is over, since post-sweep afking is unwithdrawable.
    receive() external payable {
        if (gameOver) revert E();
        _creditAfkingValue(msg.sender, msg.value);
    }
}
