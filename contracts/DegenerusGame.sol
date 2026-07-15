// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/**
 * @title DegenerusGame
 * @author Burnie Degenerus
 * @notice Core game contract managing state machine, VRF integration, jackpots, and prize pools.
 *
 * @dev ARCHITECTURE:
 *      - Level-centered lifecycle; advanceGame() is permissionless (caller tier gates only the keeper bounty)
 *      - jackpotPhaseFlag selects the daily payout mode within a level: PURCHASE(false) / JACKPOT(true)
 *      - gameOver flag is terminal
 *      - Presale: two independent mechanisms — lootbox-presale flag + coin presale-box (presaleOver) sale
 *      - Chainlink VRF for randomness with RNG lock to prevent manipulation
 *      - Delegatecall modules: advance, boon, decimator, degenerette, jackpot, lootbox, mint, whale (must inherit DegenerusGameStorage)
 *      - Prize pool flow: futurePrizePool (unified reserve) → nextPrizePool → currentPrizePool → claimableWinnings
 *
 * @dev CRITICAL INVARIANTS:
 *      - address(this).balance + steth.balanceOf(this) >= claimablePool
 *        (claimablePool >= Σ claimableWinnings + Σ afkingFunding; both ride in the one reserve.
 *         >= not ==: a resolved decimator round parks its whole pool in claimablePool up front
 *         while winners pull their shares lazily, so the un-itemized remainder over-reserves
 *         until claimed — always in the solvency-safe direction. Equality holds at full settlement,
 *         modulo pro-rata rounding dust.)
 *      - jackpotPhaseFlag is the daily payout mode: false(PURCHASE) / true(JACKPOT); gameOver is terminal
 *      - Lootbox-presale flag starts active; clears after 200 ETH tracked mint-lootbox spend or the level-3+ transition (one-way; no admin setter)
 *
 * @dev SECURITY:
 *      - Pull pattern for ETH/stETH withdrawals (claimWinnings)
 *      - RNG lock prevents state manipulation during VRF callback window
 *      - Access control via msg.sender checks
 *      - Delegatecall modules use constant addresses from ContractAddresses
 *      - 12h VRF timeout, 14-day gameover-RNG fallback, 120-day inactivity guard
 */

import {IDegenerusCoin} from "./interfaces/IDegenerusCoin.sol";
import {ICoinflip} from "./interfaces/ICoinflip.sol";
import {IDegenerusAffiliate} from "./interfaces/IDegenerusAffiliate.sol";
import {IsDGNRS} from "./interfaces/IsDGNRS.sol";
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
    IGameAfkingModule,
    IDegenerusGameFoilPackModule
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
    error SelfBoon(); // Deity attempted to issue a boon to themselves.
    error ValueMismatch(); // Amount is zero or msg.value does not match the required amount.

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
    /// @param cost FLIP burned for this nudge.
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

    /// @dev DGNRS bounty share for biggest flip payout (0.2% of reward pool).
    uint16 private constant COINFLIP_BOUNTY_DGNRS_BPS = 20;
    uint256 private constant COINFLIP_BOUNTY_DGNRS_MIN_BET = 50_000 ether;
    uint256 private constant COINFLIP_BOUNTY_DGNRS_MIN_POOL = 20_000 ether;

    /// @dev Base cost for RNG nudge (100 FLIP), compounds +50% per queued nudge.
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
      |  [128-151] frozenUntilLevel - Whale pass freeze level (0 = none)     |
      |  [152-153] whalePassType  - Pass type (0=none,1=10,3=100)            |
      |  [154-159] (reserved)       - 6 unused bits                          |
      |  [160-183] mintStreakLast  - Mint streak last completed level (24b)  |
      |  [184]    hasDeityPass     - Deity pass holder flag (1b)             |
      |  [185-208] affBonusLevel   - Cached affiliate bonus level (24b)      |
      |  [209-214] affBonusPoints  - Cached affiliate bonus points (6b)      |
      |  [215-222] curseCount      - Cashout/smite curse counter (8b)        |
      |  [223-227] (reserved)      - 5 unused bits                           |
      |  [228-243] unitsAtLevel    - Mints at current level                  |
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
        // SDGNRS via initPerpetualTickets(), keeping GAME's deploy under the per-tx gas cap.
    }

    /// @notice Queue the perpetual vault/SDGNRS tickets for levels 1-100 (advance handles 101+).
    /// @dev Split out of the constructor to keep GAME's deploy under the per-tx gas cap. VAULT and
    ///      SDGNRS each call this exactly once from their own constructor (one deploy tx each), so
    ///      no re-entry path exists. Restricted to those two protocol addresses — the only
    ///      recipients of perpetual tickets — and queues for the caller only.
    function initPerpetualTickets() external {
        address who = msg.sender;
        if (who != ContractAddresses.SDGNRS && who != ContractAddresses.VAULT) revert Unauthorized();
        for (uint24 i = 1; i <= 100; ) {
            _queueEntries(who, i, 16, false); // 16 entries (= 4 whole tickets) per level
            unchecked {
                ++i;
            }
        }
    }

    /*+======================================================================+
      |                           MODIFIERS                                  |
      +======================================================================+*/

    /*+===================================================================================================+
      |                    CORE STATE MACHINE: advanceGame()                                              |
      +===================================================================================================+
      |                                                                                                   |
      |  Progresses one "tick" of work per call. advanceGame() is permissionless — anyone may call it;    |
      |  caller tier gates only the keeper bounty (in mintFlip), never the advance work. gameOver is      |
      |  terminal.                                                                                        |
      |                                                                                                   |
      |  Level-centered lifecycle. jackpotPhaseFlag selects the daily PAYOUT mode, not access:            |
      |  • Each daily tick drains pending ticket + subscriber work, applies the day's VRF, and pays the   |
      |    daily jackpot in the current mode. Purchases stay open in BOTH modes.                          |
      |  • Purchase mode (false): new tickets target level+1; jackpots use the future-pool drip formula.  |
      |    When nextPrizePool reaches the prior level's target, the transition latch is set.              |
      |  • On fresh randomness the level advances: staged tickets activate, pools consolidate, the level  |
      |    quest rolls, and up to 5 logical daily draws begin (compressible via compressedJackpotFlag).   |
      |  • Jackpot mode (true): draws pay out; purchases target the current level, and the final draw     |
      |    routes new purchases to the next level. After the 5th draw, housekeeping clears the payout     |
      |    mode and resets the level-start day.                                                           |
      |                                                                                                   |
      |  Keeper-bounty tiers (reward only, never an advance gate): minted today/yesterday, deity pass,    |
      |  anyone >=30 min since level start, any pass holder >=15 min, active AFKing sub, DGVE majority.   |
      |                                                                                                   |
      |  Presale — two independent mechanisms:                                                            |
      |  • Lootbox-presale flag (presaleStatePacked): starts active, clears after 200 ETH of tracked      |
      |    mint lootbox spend or at the level-3+ transition; labels events and gates VAULT-referral       |
      |    mutability. No admin setter; lootbox ETH is rake-free both in and out of presale.              |
      |  • Coin presale-box sale (presaleOver latch): credit-gated, closes when applied box spend fills   |
      |    exactly 50 ETH; boxes bought before close stay openable afterward.                             |
      +===================================================================================================+*/

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
    ///      7. Credit caller with FLIP bounty during jackpot time when not requesting or unlocking RNG
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
    /// @custom:reverts OnlyAdmin If caller is not ADMIN.
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

    /// @notice Claim color-completion bingo: all 8 colors of one symbol on a level.
    /// @dev Dispatches to GAME_BINGO_MODULE via delegatecall; void return. Sender-or-approved:
    ///      the bingo settles to `player`, so the caller must be the owner or an approved
    ///      operator (address(0) = msg.sender).
    ///      Signature: claimBingo(address player, uint24 level, uint8 symbol, uint32[8] slots) —
    ///      the owner to claim for, the level (uint24 storage-key width), the symbol 0-31
    ///      (quadrant = symbol >> 3, symInQ = symbol & 7), and the per-color positions in
    ///      lvlTraitEntry[level][traitId] the owner occupies. The signature matches the module
    ///      function exactly (identical selector), so the calldata forwards as-is — re-encoding
    ///      here would cost contract-size headroom for no behavior change.
    function claimBingo(
        address,
        uint24,
        uint8,
        uint32[8] calldata
    ) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_BINGO_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
    }

    /*+==========================================================================+
      |                      AFKING DISPATCH STUBS                               |
      +==========================================================================+
      |  Thin delegatecall dispatch stubs into GAME_AFKING_MODULE (the AfKing    |
      |  subscription logic), shaped exactly like claimBingo.                    |
      |  The afking subscriber set / cursors / Sub stamps live in this Game's    |
      |  storage (DegenerusGameStorage), so the module MUST run in this          |
      |  contract's context — delegatecall preserves msg.sender, so the consent  |
      |  gates and the mintFlip bounty payee read the real caller. These are the |
      |  canonical afking entrypoints. `subscribe` is the SINGLE subscription    |
      |  mutator (create / replace / cancel). The afking box-open is reached via |
      |  mintFlip's router (which also drains human boxes after the afking ones, |
      |  the same as openBoxes) and, unrewarded, via openBoxes; the module's     |
      |  cursor walk is exposed as drainAfkingBoxes, not re-stubbed here.        |
      +==========================================================================+*/

    /// @notice Start or extend a daily afking subscription for `player`.
    /// @dev The self-consent / funding-gate consent checks run in-context against the
    ///      Game's operatorApprovals (delegatecall preserves msg.sender).
    ///      msg.value > 0 credits the RESOLVED funding bucket's afkingFunding — the
    ///      non-self (approved) fundingSource for an operator-funded sub, else the
    ///      subscriber (claimablePool in tandem) — so the deposit funds the bucket the
    ///      draws debit.
    ///      Signature: subscribe(address player, bool drainGameCreditFirst, bool useTickets,
    ///      uint8 dailyQuantity, address fundingSource). The signature matches
    ///      the module function exactly (identical selector), so the calldata forwards as-is —
    ///      re-encoding here would cost contract-size headroom for no behavior change.
    function subscribe(
        address,
        bool,
        bool,
        uint8,
        address
    ) external payable {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_AFKING_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
    }

    /// @notice Unified permissionless afking router: do ONE category of pending work
    ///         (advance → afking-box open) and pay ONE bounty. The bounty
    ///         credits msg.sender (preserved via delegatecall).
    /// @dev The signature matches the module function exactly (identical selector), so the calldata
    ///      forwards as-is — re-encoding here would cost contract-size headroom for no behavior change.
    function mintFlip() external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_AFKING_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
    }

    /// @notice Permissionless FLIP claim — pays each listed sub its accrued `pendingFlip`
    ///         (the per-delivered-day quest reward + ticket buyer-bonus) in one creditFlip,
    ///         zeroed. Always credits the sub, never the caller.
    /// @dev Signature: claimAfkingFlip(address[] subs). The signature matches the module
    ///      function exactly (identical selector), so the calldata forwards as-is — re-encoding
    ///      the array here would cost contract-size headroom for no behavior change.
    function claimAfkingFlip(address[] calldata) external {
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
        if (data.length == 0) revert EmptyReturn();
        return abi.decode(data, (uint256));
    }

    /// @notice Permissionless paid cure of `target`'s cashout/smite curse (100 FLIP).
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

    /// @notice Deity-gated smite: add a curse stack to `smitee` for 200 FLIP.
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

    /// @notice Record a secondary/level quest completion against an afking sub's streak base.
    /// @dev QUESTS-only. Thin delegatecall dispatch stub into GameAfkingModule; the module impl
    ///      enforces the QUESTS-only gate under delegatecall (msg.sender preserved).
    ///      Signature: recordAfkingSecondary(address player, uint16 amount) — matches the module selector.
    function recordAfkingSecondary(address, uint16) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_AFKING_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
    }

    /// @notice QUESTS-only (enforced in the afking module): floor an afking sub's streak base
    ///         so a foil-pack purchase's quest-streak guarantee reaches a mid-run afker.
    function floorAfkingStreakBase(address, uint16) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_AFKING_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
    }

    /// @notice Pay the DGNRS kicker to a coinflip bounty collector on a mature pool.
    /// @dev Access: COIN or COINFLIP contract only.
    ///      Pays a share of the DGNRS reward pool when a long-accrued coinflip bounty
    ///      is collected: the collected half-pool slice must reach
    ///      COINFLIP_BOUNTY_DGNRS_MIN_BET (50k FLIP — the pool accrues 1,000 FLIP/day,
    ///      so this means ~100 uncollected days) and the post-collection remainder
    ///      must reach COINFLIP_BOUNTY_DGNRS_MIN_POOL.
    /// @param player Recipient of the DGNRS bounty.
    /// @param bountySlice The collected half-pool bounty slice (FLIP base units).
    /// @param bountyPool The post-collection remaining bounty pool (FLIP base units).
    /// @custom:reverts Unauthorized If caller is not COIN or COINFLIP contract.
    function payCoinflipBountyDgnrs(
        address player,
        uint256 bountySlice,
        uint256 bountyPool
    ) external {
        if (
            msg.sender != ContractAddresses.COIN &&
            msg.sender != ContractAddresses.COINFLIP
        ) revert Unauthorized();
        if (player == address(0)) return;
        if (bountySlice < COINFLIP_BOUNTY_DGNRS_MIN_BET) return;
        if (bountyPool < COINFLIP_BOUNTY_DGNRS_MIN_POOL) return;
        uint256 poolBalance = dgnrs.poolBalance(
            IsDGNRS.Pool.Reward
        );
        if (poolBalance == 0) return;
        uint256 payout = (poolBalance * COINFLIP_BOUNTY_DGNRS_BPS) / 10_000;
        if (payout == 0) return;
        dgnrs.transferFromPool(
            IsDGNRS.Pool.Reward,
            player,
            payout
        );
    }

    /*+======================================================================+
      |                      OPERATOR APPROVALS                              |
      +======================================================================+*/

    /// @notice Approve or revoke an operator to act on your behalf.
    /// @param operator Address to approve or revoke.
    /// @param approved True to approve, false to revoke.
    /// @custom:reverts ZeroAddress If operator is the zero address.
    function setOperatorApproval(address operator, bool approved) external {
        if (operator == address(0)) revert ZeroAddress();
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
      |                       LOOT BOX CONTROLS                              |
      +======================================================================+*/

    /// @notice Current day index.
    function currentDayView() external view returns (uint24) {
        return _simulatedDayIndex();
    }

    /// @notice Update lootbox RNG request threshold (wei).
    /// @dev Access: vault owner only (DGVE majority holder).
    /// @param newThreshold New threshold in wei (must be non-zero).
    /// @custom:reverts OnlyVault If caller is not the vault owner.
    /// @custom:reverts ZeroValue If newThreshold is zero.
    function setLootboxRngThreshold(uint256 newThreshold) external {
        if (!vault.isVaultOwner(msg.sender)) revert OnlyVault();
        if (newThreshold == 0) revert ZeroValue();
        uint256 prev = _unpackMilliEthToWei(uint64(_lrRead(LR_THRESHOLD_SHIFT, LR_THRESHOLD_MASK)));
        if (newThreshold == prev) {
            emit LootboxRngThresholdUpdated(prev, newThreshold);
            return;
        }
        _lrWrite(LR_THRESHOLD_SHIFT, LR_THRESHOLD_MASK, _packEthToMilliEth(newThreshold));
        emit LootboxRngThresholdUpdated(prev, newThreshold);
    }

    /// @notice Purchase any combination of tickets and loot boxes with ETH or claimable.
    /// @dev Main entry point for all ETH/claimable purchases. For FLIP purchases, use redeemFlip().
    ///      Recycling at least 3 tickets' worth of claimable winnings earns a 10% FLIP flip-credit bonus.
    ///      Adds affiliate support for loot box purchases.
    ///      SECURITY: Blocked when RNG is locked.
    /// @param buyer Player address to receive purchases (address(0) = msg.sender).
    /// @param entryQuantityScaled Number of tickets to purchase (2 decimals, scaled by 100; 0 to skip).
    /// @param lootBoxAmount ETH amount for loot boxes, minimum 0.01 ETH (0 to skip).
    /// @param affiliateCode Affiliate/referral code for all purchases.
    /// @param payKind Payment method (DirectEth, Claimable, or Combined).
    /// @param foil True to additively buy one foil pack (10x the level price) in the same
    ///        tx. The foil leg is one-per-cycle and adds to — never replaces — the ticket
    ///        and lootbox legs, sharing the combined spend's affiliate, quest, and streak
    ///        recording so a foil pack counts exactly like a ticket purchase.
    function purchase(
        address buyer,
        uint256 entryQuantityScaled,
        uint256 lootBoxAmount,
        bytes32 affiliateCode,
        MintPaymentKind payKind,
        bool foil
    ) external payable {
        buyer = _resolvePlayer(buyer);
        if (foil) {
            _purchaseWithFoil(
                buyer,
                entryQuantityScaled,
                lootBoxAmount,
                affiliateCode,
                payKind
            );
        } else {
            _purchaseFor(
                buyer,
                entryQuantityScaled,
                lootBoxAmount,
                affiliateCode,
                payKind
            );
        }
    }

    function _purchaseFor(
        address buyer,
        uint256 entryQuantityScaled,
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
                    entryQuantityScaled,
                    lootBoxAmount,
                    affiliateCode,
                    payKind
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @dev Foil branch of purchase(): the foil pack is an additive leg on top of the
    ///      optional ticket/lootbox legs. Fresh ETH is capped at the combined cost (tickets +
    ///      lootbox + a foil pack at ten level prices), and any overpay is credited to the
    ///      payer's withdrawable afking so excess never reverts or strands. The ticket/lootbox
    ///      leg takes fresh ETH first (capped at its own cost) through the mint module's
    ///      purchaseWith, which uses the explicit ethValue and ignores the carried msg.value;
    ///      the foil leg gets the remainder, with claimable covering any foil shortfall,
    ///      through the foil module. Each leg routes its own money/affiliate and completes the
    ///      daily MINT_ETH primary (idempotent across legs). Orchestrated here, not in the mint
    ///      module, so the near-full mint module's purchase body stays within the via-IR stack
    ///      budget and the EIP-170 size limit.
    function _purchaseWithFoil(
        address buyer,
        uint256 entryQuantityScaled,
        uint256 lootBoxAmount,
        bytes32 affiliateCode,
        MintPaymentKind payKind
    ) private {
        // Quote both legs at the routed level (the level the ticket queue and the foil module
        // both deliver to), so the final-jackpot-day reroute to level+1 cannot strand the
        // buyer's overpay or under-quote the foil cost.
        uint256 priceWei = PriceLookupLib.priceForLevel(_activeTicketLevel());
        uint256 mintCost = (priceWei * entryQuantityScaled) /
            (4 * QTY_SCALE) +
            lootBoxAmount;
        uint256 cost = mintCost + FOIL_PACK_TICKETS * priceWei;
        uint256 fresh = payKind == MintPaymentKind.Claimable
            ? 0
            : (msg.value < cost ? msg.value : cost);
        if (msg.value > fresh) _creditAfkingValue(msg.sender, msg.value - fresh);
        uint256 mintFresh = fresh < mintCost ? fresh : mintCost;
        if (mintCost != 0) {
            (bool ok, bytes memory data) = ContractAddresses
                .GAME_MINT_MODULE
                .delegatecall(
                    abi.encodeWithSelector(
                        IDegenerusGameMintModule.purchaseWith.selector,
                        buyer,
                        entryQuantityScaled,
                        lootBoxAmount,
                        affiliateCode,
                        payKind,
                        mintFresh
                    )
                );
            if (!ok) _revertDelegate(data);
        }
        (bool okFoil, bytes memory dataFoil) = ContractAddresses
            .GAME_FOILPACK_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameFoilPackModule.buyFoilPack.selector,
                    buyer,
                    fresh - mintFresh,
                    affiliateCode,
                    payKind
                )
            );
        if (!okFoil) _revertDelegate(dataFoil);
    }

    /// @notice Purchase tickets with FLIP.
    /// @dev Main entry point for FLIP ticket purchases. Mirrors purchase() but for FLIP payments.
    ///      SECURITY: Blocked when RNG is locked.
    /// @param buyer Player address to receive purchases (address(0) = msg.sender).
    /// @param entryQuantityScaled Number of tickets to purchase (2 decimals, scaled by 100; 0 to skip).
    function redeemFlip(
        address buyer,
        uint256 entryQuantityScaled
    ) external {
        buyer = _resolvePlayer(buyer);
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_MINT_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameMintModule.redeemFlip.selector,
                    buyer,
                    entryQuantityScaled
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @notice Buy a credit-gated coin-presale box with ETH and/or claimable.
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

    /// @notice Permissionlessly resolve `player`'s foil match claim (value credits to player).
    /// @dev Signature: claimFoilMatch(address player, uint256 day, uint256 ticketIndex,
    ///      uint8 drawKind). The eligible cycle level is read inside the module from the
    ///      day's sealed draw. The win credits to `player`, never the caller, and a tuple
    ///      pays at most once (CEI marker), so anyone may trigger it. Two draws
    ///      (main/bonus) x four tickets give 8 independent claimables per day. The
    ///      signature matches the module function exactly (identical selector), so the
    ///      calldata forwards as-is — re-encoding would cost size headroom for no change.
    function claimFoilMatch(
        address,
        uint256,
        uint256,
        uint8
    ) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_FOILPACK_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
    }

    /// @notice Permissionlessly resolve a batch of foil match claims (address[] players,
    ///         uint24[] days, uint8[] ticketIndexes, uint8[] drawKinds).
    /// @dev Non-claimable tuples are skipped, not reverted; each settled win credits its
    ///      own player and the caller earns a per-settled-claim FLIP bounty during a live
    ///      game. The signature matches the module function exactly, so the calldata
    ///      forwards as-is.
    function claimFoilMatchMany(
        address[] calldata,
        uint24[] calldata,
        uint8[] calldata,
        uint8[] calldata
    ) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_FOILPACK_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
    }

    /// @notice Buy tickets/lootbox AND a presale box in one tx, sharing one RNG index.
    /// @dev The mint leg earns 25% presale-box credit that gates the box leg. msg.value is
    ///      split across both legs (mint cost first, remainder to the box), so the box is
    ///      funded by the same mix as any other purchase — fresh ETH, claimable, or afking
    ///      per payKind. Both queue at one index for co-resolution.
    /// @param buyer Player to receive both legs (address(0) = msg.sender).
    /// @param entryQuantityScaled Tickets to buy (0 to skip).
    /// @param lootBoxAmount ETH lootbox spend (0 to skip).
    /// @param affiliateCode Affiliate/referral code for the mint leg.
    /// @param payKind Payment method for the mint leg.
    /// @param boxAmount Requested presale-box ETH (claimable-funded).
    function buyLootboxAndPresaleBox(
        address buyer,
        uint256 entryQuantityScaled,
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
                    entryQuantityScaled,
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
    ///         player's ready boxes (the economically-incentivized auto-open bounty path). Box
    ///         rewards always credit the owner, so it needs no approval; address(0) = msg.sender.
    /// @dev Signature: openBox(address player, uint48 index). The signature matches the module
    ///      function exactly (identical selector), so the calldata forwards as-is — re-encoding
    ///      here would cost contract-size headroom for no behavior change.
    function openBox(address, uint48) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_LOOTBOX_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
    }

    /// @notice Purchase whale pass: boosts levelCount, queues 400 tickets, includes lootbox.
    /// @dev Available at any level. Can be purchased multiple times (1-100 per call).
    ///      Price: 2.4 ETH (levels 0-3), 4 ETH (levels 4+), or discounted with boon.
    ///      Queues 4 tickets for each of 100 levels [ticketStart, ticketStart+99].
    ///      Includes lootbox (10% of price).
    ///      Frozen stats don't increment until game reaches the frozen level.
    ///
    ///      Fund distribution - Level 0: 30% next / 70% future.
    ///      Fund distribution - Other levels: 5% next / 95% future.
    ///
    ///      Example at level 1: 4 tickets each for levels 1-100, stats boosted, frozen until 100.
    ///      Example at level 51: 4 tickets each for levels 51-150, stats boosted, frozen until 150.
    /// @param buyer Player address to receive pass rewards (address(0) = msg.sender).
    /// @param quantity Number of passes to purchase.
    /// @param affiliateCode Affiliate/referral code for the purchase (bytes32(0) = stored code).
    function purchaseWhalePass(
        address buyer,
        uint256 quantity,
        bytes32 affiliateCode
    ) external payable {
        buyer = _resolvePlayer(buyer);
        _purchaseWhalePassFor(buyer, quantity, affiliateCode);
    }

    function _purchaseWhalePassFor(
        address buyer,
        uint256 quantity,
        bytes32 affiliateCode
    ) private {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_WHALE_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameWhaleModule.purchaseWhalePass.selector,
                    buyer,
                    quantity,
                    affiliateCode
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @notice Purchase a 10-level lazy pass (direct in-game activation).
    /// @dev Available at levels 0-2 or x9 (9, 19, 29...), or with a valid lazy pass boon.
    ///      Levels 0-2: flat 0.24 ETH. Levels 3+: sum of per-level ticket prices across 10-level window.
    /// @param buyer Player address to receive pass (address(0) = msg.sender).
    /// @param affiliateCode Affiliate/referral code for the purchase (bytes32(0) = stored code).
    function purchaseLazyPass(address buyer, bytes32 affiliateCode) external payable {
        buyer = _resolvePlayer(buyer);
        _purchaseLazyPassFor(buyer, affiliateCode);
    }

    function _purchaseLazyPassFor(address buyer, bytes32 affiliateCode) private {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_WHALE_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameWhaleModule.purchaseLazyPass.selector,
                    buyer,
                    affiliateCode
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
    /// @dev The bet belongs to `player`; the player or an approved operator spends the player's
    ///      funds, any other caller funds the bet itself (a permissionless gift — WWXRP excluded).
    ///      The module resolves the player/funder split, so `player` forwards raw. Signature:
    ///      placeDegeneretteBet(address player, uint8 currency, uint128 amountPerSpin,
    ///      uint8 spinCount, uint32 customTraits, uint8 heroQuadrant). The signature matches the
    ///      module function exactly (identical selector), so the calldata forwards as-is —
    ///      re-encoding here would cost contract-size headroom for no behavior change.
    function placeDegeneretteBet(
        address,
        uint8,
        uint128,
        uint8,
        uint32,
        uint8
    ) external payable {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_DEGENERETTE_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
    }

    /// @notice Resolve multiple Degenerette bets once RNG is available.
    /// @dev Permissionless: settlement only credits the bet owner, so any caller may resolve
    ///      any player's bets (no approval); address(0) resolves to msg.sender. Signature:
    ///      resolveDegeneretteBets(address player, uint64[] betIds). The signature matches the
    ///      module function exactly (identical selector), so the calldata forwards as-is —
    ///      re-encoding here would cost contract-size headroom for no behavior change.
    function resolveDegeneretteBets(
        address,
        uint64[] calldata
    ) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_DEGENERETTE_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
    }

    /// @notice Consume coinflip boon for next coinflip stake bonus.
    /// @dev Access: COIN or COINFLIP contract only.
    ///      Signature: consumeCoinflipBoon(address player) — the player whose boon to consume.
    ///      The signature matches the module function exactly (identical selector), so the
    ///      calldata forwards as-is — re-encoding here would cost contract-size headroom for
    ///      no behavior change.
    /// @return boostBps The boost in basis points to apply.
    /// @custom:reverts Unauthorized If caller is not COIN or COINFLIP contract.
    function consumeCoinflipBoon(
        address
    ) external returns (uint16 boostBps) {
        if (
            msg.sender != ContractAddresses.COIN &&
            msg.sender != ContractAddresses.COINFLIP
        ) revert Unauthorized();
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
    /// @custom:reverts Unauthorized If caller is not COIN contract.
    function consumeDecimatorBoon(
        address player
    ) external returns (uint16 boostBps) {
        if (msg.sender != ContractAddresses.COIN) revert Unauthorized();
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
        uint32 boonPacked = deityBoonPacked[deity];
        usedMask = uint24(boonPacked) == day ? uint8(boonPacked >> 24) : 0;
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
    /// @custom:reverts SelfBoon If deity attempts to issue boon to themselves.
    function issueDeityBoon(
        address deity,
        address recipient,
        uint8 slot
    ) external {
        deity = _resolvePlayer(deity);
        if (recipient == deity) revert SelfBoon();
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

    /*+==========================================================================+
      |                       TICKET QUEUEING                                    |
      +==========================================================================+
      |  Tickets are queued for batch processing rather than minted immediately. |
      |  This prevents gas exhaustion from large purchases.                      |
      +==========================================================================+*/

    /*+================================================================================================================+
      |                    DELEGATE MODULE HELPERS                                                                     |
      +================================================================================================================+
      |  Internal functions that delegatecall into specialized modules.                                                |
      |  All modules MUST inherit DegenerusGameStorage for slot alignment.                                             |
      |                                                                                                                |
      |  Modules:                                                                                                      |
      |  • GAME_ADVANCE_MODULE      - Daily advance, VRF, daily processing                                             |
      |  • GAME_BOON_MODULE         - Deity boon effects and activation                                                |
      |  • GAME_DECIMATOR_MODULE    - Decimator claim credits and lootbox payouts                                      |
      |  • GAME_DEGENERETTE_MODULE  - Degenerette bet placement and resolution                                         |
      |  • GAME_JACKPOT_MODULE      - Jackpot calculations and payouts                                                 |
      |  • GAME_LOOTBOX_MODULE      - Lootbox open, credit, and payout                                                 |
      |  • GAME_MINT_MODULE         - Mint data recording, airdrop multipliers                                         |
      |  • GAME_WHALE_MODULE        - Whale pass purchases and whale pass claims                                       |
      |                                                                                                                |
      |  SECURITY: delegatecall executes module code in this contract's                                                |
      |  context, with access to all storage. Modules are constant addresses.                                          |
      +================================================================================================================+*/

    /// @dev Bubble up revert reason from delegatecall failure.
    ///      Uses assembly to preserve original error data.
    /// @param reason The error bytes from failed delegatecall.
    function _revertDelegate(bytes memory reason) private pure {
        if (reason.length == 0) revert EmptyRevert();
        assembly ("memory-safe") {
            revert(add(32, reason), mload(reason))
        }
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
        if (data.length == 0) revert EmptyReturn();
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
        if (msg.sender != address(this)) revert OnlySelf();
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_DECIMATOR_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
        if (data.length == 0) revert EmptyReturn();
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
        if (msg.sender != address(this)) revert OnlySelf();
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_JACKPOT_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
        if (data.length == 0) revert EmptyReturn();
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
        if (msg.sender != address(this)) revert OnlySelf();
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_DECIMATOR_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
        if (data.length == 0) revert EmptyReturn();
        return abi.decode(data, (uint256));
    }

    /// @notice Terminal decimator window. Open except lastPurchaseDay, gameOver, and
    ///         level 0: the terminal claim round's zero-initialized sentinel reads a
    ///         level-0 gameover as already resolved, so a level-0 round can never pay
    ///         its burners — burns are rejected instead of accepted unwinnable.
    /// @return open True if terminal decimator burns are allowed.
    /// @return lvl Current game level.
    function terminalDecWindow() external view returns (bool open, uint24 lvl) {
        lvl = level;
        open = !gameOver && !lastPurchaseDay && lvl != 0;
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
        if (msg.sender != address(this)) revert OnlySelf();
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_JACKPOT_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
        if (data.length == 0) revert EmptyReturn();
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
        if (msg.sender != address(this)) revert OnlySelf();
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
      |  and endgame payouts through the claimWinnings() function.                             |
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
        _claimWinningsWithCurse(_resolvePlayer(player), type(uint256).max);
    }

    /// @notice Claim a fixed amount of accrued ETH winnings (partial cashout).
    /// @dev Pre-gameOver: draws up to `amount` wei from claimable winnings (capped to leave the
    ///      1-wei sentinel). Post-gameOver: the game is settled, so the claim takes ALL claimable
    ///      + the caller's prepaid afking and the cap is ignored. Runs the cashout curse like the
    ///      full claim — a partial cashout is still a cashout (the curse is activity-gated).
    /// @param player Player to claim for (address(0) = msg.sender; a non-self claim requires approval).
    /// @param amount Maximum wei of claimable winnings to take (pre-gameOver; ignored post-gameOver).
    function claimWinnings(address player, uint256 amount) external {
        _claimWinningsWithCurse(_resolvePlayer(player), amount);
    }

    /// @dev Shared claim body: pull winnings (capped pre-gameOver by `maxClaim`) then set the
    ///      cashout curse. The curse SET runs in the Game's context via delegatecall (hosted in
    ///      GameAfkingModule to keep the Game under the EIP-170 ceiling).
    function _claimWinningsWithCurse(address player, uint256 maxClaim) private {
        _claimWinningsInternal(player, false, maxClaim);
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
        if (msg.sender != ContractAddresses.VAULT) revert OnlyVault();
        _claimWinningsInternal(msg.sender, true, type(uint256).max);
    }

    /// @param maxClaim Maximum claimable winnings (wei) to draw pre-gameOver (partial cashout);
    ///        ignored post-gameOver, when the claim settles ALL claimable + afking.
    function _claimWinningsInternal(address player, bool stethFirst, uint256 maxClaim) private {
        if (_goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0) revert AlreadySwept();
        uint256 amount = _claimableOf(player);
        // Post-gameOver the claim ALSO pays the caller's prepaid
        // afking ETH (lazy per-player merge — no unbounded loop). Pre-gameOver afkingFunding
        // stays its own bucket (spent by afking auto-buys / reclaimed via withdrawAfkingFunding).
        // Both this merge and withdrawAfkingFunding zero the SAME bucket → no double-spend.
        uint256 afking = gameOver ? _afkingOf(player) : 0;
        uint256 claimDebit;
        unchecked {
            if (amount > 1) {
                claimDebit = amount - 1; // available, leaving the 1-wei sentinel
            }
        }
        // Pre-gameOver: cap the claimable draw to maxClaim (partial cashout). Post-gameOver the
        // game is settled, so take everything (all claimable + afking) regardless of the cap.
        if (!gameOver && claimDebit > maxClaim) {
            claimDebit = maxClaim;
        }
        uint256 payout;
        unchecked {
            payout = claimDebit + afking;
        }
        if (payout == 0) revert NothingToClaim();
        // Both halves of the packed per-player slot debited in one load + store.
        _debitClaimableAndAfking(player, claimDebit, afking);
        claimablePool -= uint128(payout); // CEI: update state before external call (checked math)
        emit WinningsClaimed(player, msg.sender, payout);
        if (stethFirst) {
            _payoutWithEthFallback(player, payout);
        } else {
            _payoutWithStethFallback(player, payout);
        }
    }

    /// @notice Fund a player's prepaid afking ETH bucket (consumed by the AfKing afking auto-buy).
    /// @dev Permissionless (fund anyone) — the AfKing subscribe-forward and the
    ///      operator-funding case both route here. The reservation
    ///      rides inside claimablePool (no separate aggregate) — credited in tandem.
    /// @param player The beneficiary whose afkingFunding bucket is credited.
    function depositAfkingFunding(address player) external payable {
        if (player == address(0)) revert ZeroAddress();
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
        if (_goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0) revert AlreadySwept();
        if (amount == 0) return;
        uint256 bal = _afkingOf(msg.sender);
        if (amount > bal) revert Insolvent();
        _debitAfking(msg.sender, amount);
        claimablePool -= uint128(amount); // tandem release (checked math)
        (bool ok, ) = msg.sender.call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit AfkingWithdrew(msg.sender, amount);
    }

    /// @notice The canonical per-player prepaid afking ETH balance (replaces AfKing.poolOf).
    /// @param player The player to query.
    /// @return The player's afkingFunding balance (wei).
    function afkingFundingOf(address player) external view returns (uint256) {
        return _afkingOf(player);
    }

    /// @notice Claim DGNRS affiliate rewards for the current level (single affiliate).
    /// @dev Permissionless: the reward is deterministic and credits the affiliate, so any
    ///      caller may settle any affiliate's claim (address(0) = msg.sender). Thin delegatecall
    ///      dispatch stub into DegenerusGameBingoModule's claimAffiliateDgnrs body. The
    ///      delegatecall MUST be preserved (not a direct module call): the body invokes
    ///      dgnrs.transferFromPool (onlyGame) and coinflip.creditFlip (onlyFlipCreditors), both
    ///      of which authorize on msg.sender == GAME — so the logic has to execute in the Game's
    ///      context. Signature: claimAffiliateDgnrs(address player). The signature matches the
    ///      module function exactly (identical selector), so the calldata forwards as-is —
    ///      re-encoding here would cost contract-size headroom for no behavior change.
    function claimAffiliateDgnrs(address) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_BINGO_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
    }

    /// @notice Permissionless batch affiliate-DGNRS claim; a blank array claims the caller's own.
    /// @dev Per-item isolated: an ineligible / already-claimed affiliate skips instead of
    ///      reverting the batch (the single-affiliate entry above is the catchable boundary).
    /// @param affiliates Affiliates to settle; empty = msg.sender only.
    function claimAffiliateDgnrs(address[] calldata affiliates) external {
        uint256 len = affiliates.length;
        if (len == 0) {
            // Blank array: settle the caller's own claim (propagates if ineligible).
            this.claimAffiliateDgnrs(msg.sender);
            return;
        }
        for (uint256 i; i < len; ) {
            try this.claimAffiliateDgnrs(affiliates[i]) {} catch {}
            unchecked {
                ++i;
            }
        }
    }

    /*+======================================================================+
      |                 AUTO-WORK + AFKING BATCH                             |
      +======================================================================+
      |  Permissionless layer letting any caller settle pending game work    |
      |  on others' behalf for a small gas-pegged FLIP reward paid as        |
      |  coinflip stake credit (deferred mint). Resolution writes game       |
      |  storage directly, so it lives in-game by construction.              |
      +======================================================================+*/

    /// @dev Flat ~1-FLIP "lose" reward for the Degenerette resolve helper, paid ONCE per tx
    ///      at >=3 non-WWXRP resolutions. A count-independent consolation flip-credit;
    ///      the bet-stake gate (>=3 placed bets at the house edge) makes every self-resolve
    ///      farm net-negative, so it is intentionally NOT pegged to the per-resolve marginal.
    uint256 private constant RESOLVE_FLAT_FLIP = 1e18;

    /// @notice Permissionlessly resolve a caller-supplied list of Degenerette bets.
    /// @dev Items are parallel arrays: item i = (players[i], betIds[i]),
    ///      front-to-back. Item 0 is the caller's own probe: if it is already resolved
    ///      (degeneretteBets[players[0]][betIds[0]] == 0) a competitor got ahead, so the
    ///      whole list reverts with BatchAlreadyTaken (a loser-gas cap, reusing the SLOAD
    ///      item 0 needs anyway). Items 1..N are isolated per-item (a stale/reverting item
    ///      skips). The reward is a FLAT ~1-FLIP creditFlip granted ONCE at >=3
    ///      successfully-resolved NON-WWXRP bets; WWXRP (currency == 3) resolves but
    ///      never counts toward the gate. Zero resolutions revert NoWork(); 1-2
    ///      resolved commit UNPAID (never strand the trailing tail). Any caller including a
    ///      self-resolver (no caller restriction).
    /// @param players Bet owners, grouped/ordered by the caller (item 0 is the probe).
    /// @param betIds Bet ids, parallel to players.
    function degeneretteResolve(
        address[] calldata players,
        uint64[] calldata betIds
    ) external {
        uint256 len = players.length;
        if (len == 0 || betIds.length != len) revert LengthMismatch();

        // Short-circuit: probe item 0 (the caller's own choice). A resolved
        // bet is deleted (slot == 0), so a zero slot means a competitor got ahead.
        // The probe read doubles as iteration 0's bet read (do-while; len >= 1 here),
        // so later items load their slot at the loop bottom instead of re-reading item 0.
        uint256 betPacked = degeneretteBets[players[0]][betIds[0]];
        if (betPacked == 0) revert BatchAlreadyTaken();

        uint256 successCount;
        uint256 totalResolved;
        uint256 i;
        // Single-bet array reused each iteration: resolveDegeneretteBets is the
        // catchable external boundary that gives per-item isolation (try/catch needs
        // an external call), so no dedicated self-call wrapper is required.
        uint64[] memory ids = new uint64[](1);
        do {
            // currency bits [40..41]: WWXRP is the most +EV currency, so it is excluded
            // from the >=3 reward gate to keep the faucet closed.
            uint8 currency = uint8((betPacked >> 40) & 0x3);
            ids[0] = betIds[i];
            // Per-item isolation: a stale/reverting/not-ready bet skips, never bricks.
            try this.resolveDegeneretteBets(players[i], ids) {
                // Any resolution counts toward the no-work gate; only non-WWXRP
                // resolutions count toward the >=3 flat-reward gate.
                unchecked {
                    ++totalResolved;
                    if (currency != 3) ++successCount;
                }
            } catch {}
            unchecked {
                ++i;
            }
            if (i == len) break;
            betPacked = degeneretteBets[players[i]][betIds[i]];
        } while (true);

        // Flat ~1-FLIP "lose": pay ONCE at >=3 non-WWXRP resolutions; revert
        // NoWork() if nothing resolved; 1-2 resolved commit UNPAID (never strand the tail).
        if (totalResolved == 0) revert NoWork();
        if (successCount >= 3) coinflip.creditFlip(msg.sender, RESOLVE_FLAT_FLIP);
    }

    /// @notice O(1) discovery: does advanceGame() have pending work?
    /// @dev TRUE for a new-day advance (regardless of rngLock — advance is liveness-critical)
    ///      OR a mid-day partial-drain whose read slot still holds queued tickets. No
    ///      unbounded scan.
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

    /// @notice Would `who` earn the mintFlip advance bounty if they cranked right now?
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
    ///         Unrewarded — only mintFlip() pays a bounty.
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
        (uint256 openedAfking, uint256 afkingSteps) = abi.decode(
            data,
            (uint256, uint256)
        );
        // Then human boxes with the remaining budget — the multi-index sweep lives in the
        // lootbox module (delegatecall runs it in this Game's storage), mirroring the afking
        // leg above. The afking leg's FULL step consumption (opens AND ring-scan skips, in
        // open-step currency) is charged against maxCount, so a long drained-ring scan can
        // never hand the human sweep an uncharged full budget — the same shared-budget rule
        // the rewarded mintFlip crank enforces.
        if (afkingSteps < maxCount) {
            (ok, data) = ContractAddresses
                .GAME_LOOTBOX_MODULE
                .delegatecall(
                    abi.encodeWithSelector(
                        IDegenerusGameLootboxModule.openHumanBoxes.selector,
                        maxCount - afkingSteps
                    )
                );
            if (!ok) _revertDelegate(data);
            opened = abi.decode(data, (uint256));
        }
        opened += openedAfking;
    }

    /*+======================================================================+
      |                    LOOTBOX CLAIMS                                    |
      +======================================================================+*/

    /// @notice Claim deferred whale pass rewards from large lootbox wins (>5 ETH).
    /// @dev Thin, PERMISSIONLESS delegatecall dispatch stub into the whale module — forwards
    ///      `msg.data` verbatim (msg.sender preserved). No approval gate and no address(0)
    ///      self-resolution: the claim only awards the passed player their own deferred
    ///      tickets (it never moves value to the caller), so cranking it for anyone is safe.
    ///      Signature: claimWhalePass(address player) — matches the module selector. Callers
    ///      claiming for themselves pass their own address (sDGNRS / Vault pass address(this)).
    function claimWhalePass(address) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_WHALE_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
    }

    /*+======================================================================+
      |                    REDEMPTION LOOTBOX                                |
      +======================================================================+*/

    /// @notice Resolve redemption lootboxes for an sDGNRS gambling burn claim.
    /// @dev Called by sDGNRS during claimRedemption. Thin delegatecall dispatch stub into
    ///      DegenerusGameLootboxModule's resolveRedemptionLootbox body (auth, funding-mix pull,
    ///      pool credit, and the 5-ETH chunked resolution all live there). The signature matches
    ///      the module function exactly (identical selector), so the calldata + msg.value forward
    ///      as-is — re-encoding here would cost contract-size headroom for no behavior change.
    ///      Signature: resolveRedemptionLootbox(address player, uint256 amount, uint256 rngWord,
    ///      uint16 activityScore).
    function resolveRedemptionLootbox(
        address,
        uint256,
        uint256,
        uint16
    ) external payable {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_LOOTBOX_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertDelegate(data);
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
    /// @custom:reverts OnlySDGNRS If caller is not sDGNRS.
    /// @custom:reverts TransferFailed If the ETH transfer fails.
    /// @custom:reverts Insolvent If neither the ETH nor the stETH leg covers `amount`.
    function pullRedemptionReserve(uint256 amount) external {
        if (msg.sender != ContractAddresses.SDGNRS) revert OnlySDGNRS();
        if (amount == 0) return;

        // ETH leg (as today): the claimable[SDGNRS] ledger AND the game's liquid ETH both cover
        // `amount` — segregate the at-risk ETH out to sDGNRS. CHECKED debit (no unchecked); CEI.
        if (
            _claimableOf(ContractAddresses.SDGNRS) >= amount &&
            address(this).balance >= amount
        ) {
            _debitClaimable(ContractAddresses.SDGNRS, amount);
            claimablePool -= uint128(amount);
            emit ClaimableSpent(ContractAddresses.SDGNRS, amount, _claimableOf(ContractAddresses.SDGNRS), MintPaymentKind.Internal, amount);
            (bool ok, ) = payable(ContractAddresses.SDGNRS).call{value: amount}("");
            if (!ok) revert TransferFailed();
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
        revert Insolvent();
    }

    /// @notice Sell far-future ticket entries to sDGNRS for current-level tickets + cash (-EV exit).
    /// @dev Resolves the seller (operator-honor) then delegatecalls the mint module, which holds the
    ///      far-future salvage logic (kept off this contract for EIP-170 headroom). Quote without
    ///      executing via previewSellFarFutureEntries.
    /// @param player Owner of the far entries / recipient (resolved via _resolvePlayer).
    /// @param levels Target levels to sell from (each 6 <= level - currentLevel <= 100).
    /// @param quantities Entries to sell at each level (4 entries = 1 whole ticket).
    /// @param queueIndices Caller-supplied ticketQueue position of the resolved player at each level.
    function sellFarFutureEntries(
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
                    IDegenerusGameMintModule.sellFarFutureEntries.selector,
                    player,
                    levels,
                    quantities,
                    queueIndices
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @notice Quote a far-future salvage swap WITHOUT executing (the UI offer; -EV by design).
    /// @dev Read-only; shares the exact valuation (curve + daily per-player jitter + ETH/FLIP
    ///      split) the executing path uses, so the displayed offer matches what would be paid.
    ///      Reverts on an ineligible distance / zero quantity; does NOT check ownership (a quote
    ///      for the given bundle). For a bundle too small to fund one current entry,
    ///      ticketWei == totalBudget and the cash legs are 0 (the executing path reverts on that).
    ///      The cash leg splits into ETH + FLIP: when sDGNRS holds no FLIP (or the seed targets
    ///      zero) the whole cash leg is paid in ETH; conserved as ethCashWei + value(flipTokens).
    /// @return totalFaceWei Sum of priceForLevel(L) * n / 4 over all lines (per-entry face; bundle face).
    /// @return totalBudget Total ETH sDGNRS would pay (the -EV offer).
    /// @return ticketWei Portion delivered as current-level tickets.
    /// @return ethCashWei Cash portion delivered as withdrawable ETH claimable.
    /// @return flipTokens Cash portion delivered as FLIP (transferred from sDGNRS).
    /// @dev Signature: previewSellFarFutureEntries(address player, uint32[] levels,
    ///      uint256[] quantities). The signature matches the module function exactly (identical
    ///      selector), so the calldata forwards as-is — re-encoding the arrays here would cost
    ///      contract-size headroom for no behavior change.
    function previewSellFarFutureEntries(
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
            uint256 flipTokens
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
      |  • Daily jackpot - Paid each day to burn ticket holders (day 5 = full pool payout)            |
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
    /// @custom:reverts OnlyAdmin If caller is not ADMIN.
    /// @custom:reverts ZeroAddress If recipient is zero.
    /// @custom:reverts ValueMismatch If amount is zero or msg.value does not match amount.
    /// @custom:reverts Insolvent If the stETH balance is insufficient.
    /// @custom:reverts TransferFailed If the stETH transfer fails.
    function adminSwapEthForStEth(
        address recipient,
        uint256 amount
    ) external payable {
        if (msg.sender != ContractAddresses.ADMIN) revert OnlyAdmin();
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0 || msg.value != amount) revert ValueMismatch();

        uint256 stBal = steth.balanceOf(address(this));
        if (stBal < amount) revert Insolvent();
        if (!steth.transfer(recipient, amount)) revert TransferFailed();
        emit AdminSwapEthForStEth(recipient, amount);
    }

    /// @notice Stake game-held ETH into stETH via Lido.
    /// @dev Access: vault owner only (DGVE majority holder).
    ///      SECURITY: Must retain ETH to cover player claims, excluding vault/DGNRS
    ///      claimable (those addresses accept stETH payouts natively).
    /// @param amount ETH amount to stake.
    /// @custom:reverts OnlyVault If caller is not the vault owner.
    /// @custom:reverts ZeroValue If amount is zero.
    /// @custom:reverts Insolvent If ETH is insufficient or staking would dip into the player-claim ETH reserve.
    /// @custom:reverts TransferFailed If the Lido submit fails.
    function adminStakeEthForStEth(uint256 amount) external {
        if (!vault.isVaultOwner(msg.sender)) revert OnlyVault();
        if (amount == 0) revert ZeroValue();

        uint256 ethBal = address(this).balance;
        if (ethBal < amount) revert Insolvent();
        // Vault and DGNRS claimable can be settled in stETH, so exclude from ETH reserve
        uint256 stethSettleable = _claimableOf(ContractAddresses.VAULT) +
            _claimableOf(ContractAddresses.SDGNRS);
        uint256 reserve = claimablePool > stethSettleable
            ? claimablePool - stethSettleable
            : 0;
        if (ethBal <= reserve) revert Insolvent();
        uint256 stakeable = ethBal - reserve;
        if (amount > stakeable) revert Insolvent();

        // stETH return value intentionally ignored: Lido mints 1:1 for ETH, validated by input checks
        try steth.submit{value: amount}(address(0)) returns (uint256) {} catch {
            revert TransferFailed();
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
      |  • Single 12h timeout retry (vault owner 1h early) per daily request |
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
    /// @custom:reverts OnlyAdmin If caller is not ADMIN.
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

    /// @notice Pay FLIP to nudge the next RNG word by +1.
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
        // Fits uint64: every nudge burns >= RNG_NUDGE_BASE_COST (100 FLIP), so the
        // count is bounded by supply/1e20 << 2^64. Masked RMW preserves the co-resident
        // lastVrfProcessedTimestamp.
        totalFlipReversals = uint64(newCount);
        emit ReverseFlip(msg.sender, newCount, cost);
    }

    /// @dev Calculate nudge cost with compounding.
    ///      Base cost is 100 FLIP, +50% per queued nudge.
    /// @param reversals Number of nudges already queued.
    /// @return cost FLIP cost for the next nudge.
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
            if (!steth.approve(ContractAddresses.SDGNRS, amount)) revert TransferFailed();
            dgnrs.depositSteth(amount);
            return;
        }
        if (!steth.transfer(to, amount)) revert TransferFailed();
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
            if (!ok) revert TransferFailed();
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
        if (ethBal < remaining) revert Insolvent();
        (bool ok, ) = payable(to).call{value: remaining}("");
        if (!ok) revert TransferFailed();
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

    /// @notice Get queued future entry rewards owed for a level.
    /// @param lvl Target level for the queued entries.
    /// @param player Player address to query.
    /// @return The number of entries owed (fractional remainder resolves at batch time).
    function entriesOwedView(
        uint24 lvl,
        address player
    ) external view returns (uint32) {
        return uint32(entriesOwedPacked[_tqWriteKey(lvl)][player] >> 8);
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
        // Routed level so the advertised price matches what a buy-now is charged, including
        // the final-jackpot-day reroute to level+1.
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
    /// @dev Bundles level, state, flags, and price into a single call. lvl is the ACTUAL game
    ///      level (Coinflip keys BAF bracketing / the transition lock on it from this one
    ///      snapshot, avoiding a second level() read); priceWei is the buy-now price at the
    ///      ROUTED level, so a caller following the quote pays what execution charges — the two
    ///      differ during the purchase phase and the final jackpot RNG window (buys route to
    ///      level+1), which is intentional.
    /// @return lvl Actual current game level.
    /// @return inJackpotPhase True if jackpot phase is active.
    /// @return lastPurchaseDay_ True if prize pool target is met.
    /// @return rngLocked_ True if VRF request is pending.
    /// @return priceWei Current buy-now mint price in wei (at the routed ticket level).
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
        lvl = level;
        rngLocked_ = rngLockedFlag;
        priceWei = PriceLookupLib.priceForLevel(_activeTicketLevel());
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
        streak = _mintStreakEffectiveFromPacked(packed, _activeTicketLevel());
    }

    /// @dev The current cashout/smite curse points for `player` (UI view).
    function curseCountOf(address player) external view returns (uint8) {
        return uint8((mintPacked_[player] >> BitPackingLib.CURSE_COUNT_SHIFT) & BitPackingLib.MASK_8);
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
      |    - 10-level pass: +10%                                             |
      |    - 100-level pass: +40%                                            |
      |  • Deity pass bonus: +80% (always active)                            |
      |                                                                      |
      +======================================================================+*/

    /// @notice Calculate player's activity score in whole points.
    /// @dev Activity Score: 50 (streak) + 25 (count) + 100 (quest) + 50 (affiliate) + 40 (whale) = 265 pt max
    ///      Deity pass adds +80 in place of whale pass bonus (305 pt max base).
    ///      Consumers apply their own caps (lootbox EV: 400, degenerette ROI: 305, decimator: 235).
    /// @param player The player address to calculate for.
    /// @return scorePoints Total activity score in whole points.
    function playerActivityScore(
        address player
    ) external view returns (uint256 scorePoints) {
        // Unified effective quest streak: a live afking sub reads the Sub-side compute-on-read
        // (the run's funded days + in-run secondaries); everyone else reads the decay-aware manual
        // streak, which zeroes a lapsed stale-high streak so it can't inflate terminal-decimator
        // weight, lootbox EV, or sDGNRS claims.
        uint32 streak = _effectiveQuestStreak(player);
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
    /// @dev Collapses the afking's per-player claimableWinningsOf STATICCALLs into one
    ///      batched call. Values are byte-identical to the single-value accessors (same
    ///      priceForLevel / rngLockedFlag / swept-gate).
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
            afkingFundings[i] = _afkingOf(players[i]); // raw — mirrors afkingFundingOf
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

    /// @notice Sample up to 4 trait burn entries from a specific level.
    /// @dev Used by BAF scatter to sample the next level's entry holders.
    /// @param targetLvl The level to sample from.
    /// @param entropy Random seed (typically VRF word) for trait and offset selection.
    /// @return traitSel Selected trait ID.
    /// @return entries Array of up to 4 entry holder addresses.
    function sampleTraitEntriesAtLevel(
        uint24 targetLvl,
        uint256 entropy
    ) external view returns (uint8 traitSel, address[] memory entries) {
        traitSel = uint8(entropy >> 24);
        address[] storage arr = lvlTraitEntry[targetLvl][traitSel];
        uint256 len = arr.length;
        if (len == 0) {
            return (traitSel, new address[](0));
        }

        uint256 take = len > 4 ? 4 : len;
        entries = new address[](take);
        uint256 start = (entropy >> 40) % len;
        for (uint256 i; i < take; ) {
            entries[i] = arr[(start + i) % len];
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
      |                    VIEW: TRAIT TICKET QUERIES                        |
      +======================================================================+
      |  Read-only functions for querying trait state and game history.      |
      +======================================================================+*/

    /// @notice Count a player's entries for a specific trait and level.
    /// @dev Paginated for large entry arrays.
    /// @param trait The trait ID.
    /// @param lvl The level to query.
    /// @param offset Starting index for pagination.
    /// @param limit Maximum entries to scan.
    /// @param player The player address to count.
    /// @return count Number of entries found in this page.
    /// @return nextOffset Next offset for pagination.
    /// @return total Total entries in the array.
    function getEntries(
        uint8 trait,
        uint24 lvl,
        uint32 offset,
        uint32 limit,
        address player
    ) external view returns (uint24 count, uint32 nextOffset, uint32 total) {
        address[] storage a = lvlTraitEntry[lvl][trait];
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

    /// @notice Get entries owed to a player for the current level.
    /// @param player The player address.
    /// @return tickets Number of entries owed for current level.
    function getPlayerPurchases(
        address player
    ) external view returns (uint32 tickets) {
        tickets = uint32(entriesOwedPacked[_tqWriteKey(level)][player] >> 8);
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
        if (gameOver) revert GameOver();
        _creditAfkingValue(msg.sender, msg.value);
    }
}
