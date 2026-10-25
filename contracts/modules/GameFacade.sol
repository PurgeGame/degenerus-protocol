// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {GameActionInternals} from "./GameActionInternals.sol";
import {GameRngNudge} from "./GameRngNudge.sol";

import {GameEntryInternals} from "./GameEntryInternals.sol";
import {DegenerusGamePayoutUtils} from "./DegenerusGamePayoutUtils.sol";
import {GameAfkingClaims} from "./GameAfkingClaims.sol";

import {RngTags} from "../libraries/RngTags.sol";

import {GameHooks} from "./GameHooks.sol";

import {MineFlipGas} from "../libraries/MineFlipGas.sol";

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

/**
 * @title DegenerusGame
 * @author Burnie Degenerus
 * @notice Core game contract managing state machine, VRF integration, jackpots, and prize pools.
 *
 * @dev ARCHITECTURE:
 *      - Level-centered lifecycle; mineFlip() is permissionless (caller tier gates only the miner bounty)
 *      - jackpotPhaseFlag selects the daily payout mode within a level: PURCHASE(false) / JACKPOT(true)
 *      - gameOver flag is terminal
 *      - Degenesis: seven daily cohorts from GameTimeLib.DEGENESIS_START_DAY, gated by purchase credit
 *      - Chainlink VRF for randomness with RNG lock to prevent manipulation
 *      - Delegatecall modules: advance, afking, bingo, boon, decimator, degenerette, foilpack,
 *        gameover, jackpot, lootbox, mint, whale (must inherit DegenerusGameStorage)
 *      - Prize pool flow: futurePrizePool (unified reserve) → nextPrizePool → currentPrizePool → claimableWinnings
 *
 * @dev CRITICAL INVARIANTS:
 *      - address(this).balance + steth.balanceOf(this) >= claimablePool
 *      - claimablePool >= total payable winnings + total afking funding
 *      - jackpotPhaseFlag is the daily payout mode: false(PURCHASE) / true(JACKPOT); gameOver is terminal
 *      - Unsplit Degenesis volume, the Vault's Degenesis budget and sDGNRS AFKing funding ride in claimablePool
 *
 * @dev SECURITY:
 *      - Pull pattern for ETH/stETH withdrawals (claimWinnings)
 *      - RNG lock prevents state manipulation during VRF callback window
 *      - Access control via msg.sender checks
 *      - Delegatecall modules use constant addresses from ContractAddresses
 *      - 20h VRF retry timeout, 14-day gameover-RNG fallback, 30-day purchase inactivity guard
 */

import {IsDGNRS} from "../interfaces/IsDGNRS.sol";
import {IStETH} from "../interfaces/IStETH.sol";
import {IDegenerusGameBoonModule, IDegenerusGameFoilPackModule, IDegenerusGameDegenesisModule} from "../interfaces/IDegenerusGameModules.sol";
import {MintPaymentKind} from "../interfaces/IDegenerusGame.sol";

import {ContractAddresses} from "../ContractAddresses.sol";
import {BitPackingLib} from "../libraries/BitPackingLib.sol";
import {GameTimeLib} from "../libraries/GameTimeLib.sol";
import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";
import {PackedTicketSampleLib} from "../libraries/PackedTicketSampleLib.sol";
import {EntropyLib} from "../libraries/EntropyLib.sol";

/*+==============================================================================+
  |                     EXTERNAL INTERFACE DEFINITIONS                           |
  +==============================================================================+
  |  Minimal interfaces for external contracts this contract interacts with.     |
  |  These are defined locally to avoid circular import dependencies.            |
  +==============================================================================+*/

/// @dev Vault interface for the pinned governance owner check (admin access control).
interface IDegenerusVaultOwnerGame {
    /// @notice DegenerusVault's pinned governance owner check for `account`.
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
 * @dev Owns shared Game storage. User entry points and the miner dispatcher call internal
 *      components; bounded workers retain their explicit delegatecall frames.
 * @custom:security-contact burnie@degener.us
 */
abstract contract GameFacade is GameEntryInternals, GameActionInternals, GameRngNudge, GameHooks, DegenerusGamePayoutUtils, GameAfkingClaims {
    /*+======================================================================+
      |                              ERRORS                                  |
      +======================================================================+
      |  Custom errors for gas-efficient reverts. Each error maps to a       |
      |  specific failure condition in the game flow.                        |
      +======================================================================+*/

    // error E() — inherited from DegenerusGameStorage
    /// @notice Thrown when the amount is zero or msg.value does not match it.
    error ValueMismatch();
    /// @notice Thrown when a reversal's live cost no longer matches the caller's quote.
    error NudgeCostChanged();

    // error RngLocked(), NotApproved() — inherited from DegenerusGameStorage

    /// @notice mineFlip could not admit any useful execution step with the supplied gas.
    error InsufficientExecutionGas();
    /// @notice A nonzero gas-estimate multiplier must be at least 10,000 basis points.
    error InvalidGasMultiplier();
    /// @notice Thrown when a tunable parameter is set outside its permitted range.
    error OutOfBounds();

    /*+======================================================================+
      |                              EVENTS                                  |
      +======================================================================+
      |  Events for off-chain indexers and UIs. All critical state changes   |
      |  emit events for transparency and auditability.                      |
      +======================================================================+*/

    /// @notice Emitted when the lootbox RNG request threshold is updated.
    event LootboxRngThresholdUpdated(uint256 previous, uint256 current);
    /// @notice Emitted when an account's operator is approved or revoked.
    event OperatorApproval(
        uint32 indexed id,
        address indexed operator,
        bool approved
    );
    /// @notice Emitted when a player nudges the next RNG word.
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


    /*+======================================================================+
      |                           CONSTANTS                                  |
      +======================================================================+
      |  Game parameters and bit manipulation constants. All constants are   |
      |  private to prevent external dependency on specific values.          |
      +======================================================================+*/

    /// @dev The sDGNRS leg of a record claim pays the claim's accrued pool share at
    ///      this scale-down from the sDGNRS reward pool (0.01%-0.15% per claim).
    uint256 private constant RECORD_SDGNRS_SCALE_DIV = 500;


    /*+======================================================================+
      |                          CONSTRUCTOR                                 |
      +======================================================================+
      |  Initialize storage wiring and set up initial approvals.             |
      |  The constructor wires together the entire game ecosystem.           |
      +======================================================================+*/

    /**
     * @notice Initialize the game with precomputed contract references.
     * @dev All addresses and deploy day boundary are compile-time constants from ContractAddresses.
     *      purchaseStartDay starts at the first post-Degenesis logical day.
     *      dailyIdx starts at bootstrap logical day 1 without recording a result.
     *      The deploy day is also the first AFKing reward endpoint: no subscriber pass runs for
     *      it, so runs started that day are checkpointed on it and first buy the next day.
     *      Logical day 1 opens at deployment; the separate wall clock owns daily pacing.
     */
    constructor() {
        uint24 currentDay = 1;
        purchaseStartDay = GameTimeLib.MAIN_LAUNCH_DAY;
        dailyComplete = true;
        lastDailyRequestWallDay = _wallDay();
        lastDailyCompletedAt = uint48(block.timestamp);
        dailyIdx = currentDay;
        _afkingEndpointDay = currentDay;
        _setLevelPrizePool(0, BOOTSTRAP_PRIZE_POOL);
        foilSlotRetained = true;
        // The pending buffer starts empty but nonzero, as every unfreeze leaves it.
        prizePoolPendingPacked = POOL_PENDING_SENTINEL;
        // Level 1 is the first level with tickets (every sink targets level + 1 or later).
        _markTicketGenerationStart(1);
        // Protocol wallets take IDs 1-3 before any public door can register a wallet.
        _registerWallet(ContractAddresses.VAULT, 0);
        _registerWallet(ContractAddresses.SDGNRS, 0);
        _registerWallet(ContractAddresses.GNRUS, 0);

        // Register this contract's ENS reverse name (best-effort; skipped when the
        // registrar is unset — local/test/testnet builds). The setName(string)
        // selector is shared by the L1 ReverseRegistrar and Base's L2ReverseRegistrar.
        address ensReg = ContractAddresses.ENS_REVERSE_REGISTRAR;
        if (ensReg != address(0)) {
            (bool ok, ) = ensReg.call(
                // raw-selectors: justified — best-effort ENS reverse-name; setName(string) has no deploy-wide bound interface and must not revert deployment
                abi.encodeWithSignature("setName(string)", "game.degenerus.eth")
            );
            ok;
        }
    }

    /// @notice Register both protocol deities and their perpetual tickets in one batch.
    /// @dev Caller and one-time guards live in the module; identical selector forwards unchanged.
    function initProtocolDeity() external {
        (bool ok, bytes memory data) = ContractAddresses.GAME_BOON_MODULE.delegatecall(msg.data);
        if (!ok) _revertGameDelegate(data);
    }

    /*+======================================================================+
      |                           MODIFIERS                                  |
      +======================================================================+*/

    /*+========================================================================================+
      |                    ADMIN VRF FUNCTIONS                                                 |
      +========================================================================================+
      |  One-time VRF setup function called by ADMIN during deployment phase.                  |
      +========================================================================================+*/

    /// @notice Wire VRF config from the VRF ADMIN contract.
    /// @dev Access: ADMIN only. Overwrites any existing config on each call.
    ///      SECURITY: Config can be changed via emergency rotation (updateVrfCoordinatorAndSub).
    /// @custom:reverts OnlyAdmin If caller is not ADMIN.
    /// @dev Signature: initVrf(address coordinator_, uint256 subId, bytes32 keyHash_) —
    ///      Chainlink VRF V2.5 coordinator address, VRF subscription ID for native billing,
    ///      and the VRF key hash identifying the oracle and gas lane. The signature matches
    ///      the module function exactly (identical selector), so the calldata forwards as-is —
    ///      re-encoding here would cost contract-size headroom for no behavior change.
    function initVrf(address, uint256, bytes32) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_GAMEOVER_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertGameDelegate(data);
    }

    /// @notice Settle an account's eight-color bingo to its payee. Permissionless; at most one claim per level.
    function claimBingo(uint32 id, uint24 lvl, uint8 symbol, uint32[8] calldata slots) external {
        _gameClaimBingo(id, lvl, symbol, slots);
    }

    /// @notice Claim deterministic-ending shares: after a game over caused by a dead VRF, every
    ///         ticket of the terminal level claims its share of the pot here until the final
    ///         sweep. Permissionless; each share credits the holding's owner account by ID, never
    ///         the caller.
    /// @dev Dispatches to GAME_GAMEOVER_MODULE via delegatecall. Signature:
    ///      claimDeadVrf(uint32 id, uint256[] refs) — the owner account (0 = caller), each ref one
    ///      holding with its top byte the kind (see DegenerusGameGameOverModule.claimDeadVrf). The
    ///      signature matches the module function exactly, so the calldata forwards as-is.
    function claimDeadVrf(uint32, uint256[] calldata) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_GAMEOVER_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertGameDelegate(data);
    }

    /*+==========================================================================+
      |                      AFKING DISPATCH STUBS                               |
      +==========================================================================+
      |  Thin delegatecall dispatch stubs into GAME_AFKING_MODULE (the AfKing    |
      |  subscription logic), shaped exactly like claimBingo.                    |
      |  The afking subscriber set / cursors / lanes live in this Game's        |
      |  storage (DegenerusGameStorage), so the module MUST run in this          |
      |  contract's context — delegatecall preserves msg.sender, so the account  |
      |  gates and the mineFlip bounty payee read the real caller. These are the |
      |  canonical afking entrypoints. `subscribe` is the SINGLE subscription    |
      |  mutator (create / replace / cancel). Afking box opens run only as a     |
      |  mineFlip stage.                                                         |
      +==========================================================================+*/

    /// @notice Start, change or cancel a daily afking subscription for account `id`.
    /// @dev The account check runs in-context (delegatecall preserves msg.sender). A new run
    ///      burns seat `seatId` of the subscriber's payee. msg.value > 0 credits the
    ///      subscriber's prepaid afking ETH (claimablePool in tandem).
    ///      Signature: subscribe(uint32 id, bool useTickets, uint8 dailyQuantity, uint256 seatId).
    ///      The signature matches the module function exactly (identical selector), so the
    ///      calldata forwards as-is.
    function subscribe(
        uint32,
        bool,
        uint8,
        uint256
    ) external payable {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_AFKING_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertGameDelegate(data);
    }

    /// @notice Atomic stETH funding operation, callable only by GAME itself.
    /// @dev Token failures and invalid receipts roll back this atomic attempt;
    ///      the worker then applies the ordinary insufficient-funding policy.
    function pullAfkingSteth(uint32, address, uint256) external returns (uint256) {
        if (msg.sender != address(this)) revert OnlySelf();
        (bool ok, bytes memory data) = ContractAddresses.GAME_AFKING_MODULE.delegatecall(msg.data);
        if (!ok) _revertGameDelegate(data);
        return abi.decode(data, (uint256));
    }

    /// @notice Run the next ordered game actions through safe gas checkpoints.
    /// @dev Rewards follow measured progress. Worker caps, refusal handling and committed prefixes remain in the engine.
    /// @param gasMultiplierBps Gas-estimate factor: 0 or 10,000 = 1x; minimum 2,500 = 0.25x.
    function mineFlip(uint32 gasMultiplierBps) external { _gameMineFlip(gasMultiplierBps); }

    /// @notice The next action for a caller holding no mid-day credit.
    function nextMinerAction() external view returns (uint8) {
        return uint8(_nextMinerAction(address(this)));
    }

    /// @notice Work discovery as msg.sender, including its below-threshold mid-day credit.
    function minerAction() external returns (uint8) { return _gameMinerAction(); }

    /// @notice Permissionless AFKing claim — settles each listed account on both sides: its own
    ///         reward and its affiliate base to the upline, for every day since its last
    ///         settlement. Always credits the accounts and uplines, never the caller.
    /// @dev Signature: claimAfkingFlip(uint32[] ids) (0 = caller). The signature matches the
    ///      module function exactly (identical selector), so the calldata forwards as-is.
    function claimAfkingFlip(uint32[] calldata) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_AFKING_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertGameDelegate(data);
    }

    /// @notice Affiliate-only settlement of up to eight packed subscriptions and their upline bases.
    function drainAffiliateBases(uint256 ids, uint256 uplines) external returns (uint256, uint256, uint256) {
        return _gameDrainAffiliateBases(ids, uplines);
    }

    /// @notice Permissionless paid cure of account `id`'s cashout/smite curse (100 FLIP from
    ///         the caller).
    /// @dev Thin delegatecall dispatch stub into GameAfkingModule's decurse body.
    ///      Signature: decurse(uint32 id) (0 = caller). The signature matches the module function
    ///      exactly (identical selector), so the calldata forwards as-is.
    function decurse(uint32) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_AFKING_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertGameDelegate(data);
    }

    /// @notice Length of the afking subscriber set: live subscriptions, the two exempt
    ///         protocol subscriptions and seized runs awaiting the in-pass removal. The seat
    ///         token's capped vault mint reads it.
    function subscriberSetLength() external view returns (uint256) {
        return _subscribers.length;
    }

    /// @notice Read a raw storage slot. Periphery escape hatch for lens/viewer
    ///         contracts (e.g. DegenerusGameLens): rich packed-state decodes live
    ///         in the lens, and new read surfaces
    ///         can deploy without touching this contract. Read-only — storage is
    ///         already public to off-chain readers via eth_getStorageAt; this
    ///         mirrors that visibility to eth_call/staticcall consumers.
    function extsload_g2807007(bytes32 slot) external view returns (bytes32 value) {
        assembly {
            value := sload(slot)
        }
    }

    /// @notice Wallet-ID hook for trusted protocol contracts: the existing ID, or with `allocate`
    ///         a new one (paid admission applies). The shared hook enforces the caller set.
    function registerWallet_g9539(address owner, bool allocate) external returns (uint32 id) {
        return _gameRegisterWallet_g9539(owner, allocate);
    }

    function registerWalletIdentity(address owner) external returns (uint32 id) {
        return _gameRegisterWalletIdentity(owner);
    }

    /// @notice Wallet-bound identity; does not change when its gameplay account is sold.
    function walletIdentityOf_g8516(address owner) external view returns (uint32) {
        return uint32(walletIds[owner] >> 32);
    }

    /// @notice Borrow up to `amount` against far-future tickets; unrepaid at `dueLevel`, the
    ///         lender takes the account as a sale would.
    function borrow(uint32 id, uint24 dueLevel, uint256 amount, uint256 minEthOut) external {
        _gameBorrow(id, dueLevel, amount, minEthOut);
    }

    function repay(uint32 id) external payable {
        _gameRepay(id);
    }

    function acquiredBuyer(uint32 id) external view returns (uint32 buyerId) {
        return _acquiredBuyer(id);
    }

    /// @notice Collect subaccount ETH and settled FLIP for its current owner; only sDGNRS's are permissionless.
    function sweepAccounts(uint32[] calldata ids) external returns (uint256 ethCollected, uint256 flipCollected) {
        return _gameSweepAccounts(ids);
    }

    /// @notice Deity-gated smite: add a curse stack to account `smiteeId` for 200 FLIP.
    /// @dev Thin delegatecall dispatch stub into GameAfkingModule's smite body.
    ///      Signature: smite(uint256 deityId, uint32 smiteeId) (0 = caller). The signature
    ///      matches the module function exactly, so the calldata forwards as-is.
    function smite(uint256, uint32) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_AFKING_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertGameDelegate(data);
    }

    /// @notice Record a secondary/level quest completion against an afking sub's streak base.
    /// @dev QUESTS-only; the shared hook checks the caller.
    function recordAfkingSecondary_g3316(uint32 id, uint16 amount) external {
        _gameRecordAfkingSecondary(id, amount);
    }

    /// @notice QUESTS-only: floor an afking sub's streak base
    ///         so a foil-pack purchase's quest-streak guarantee reaches a mid-run afker.
    function floorAfkingStreakBase(uint32 id, uint16 floor) external {
        _gameFloorAfkingStreakBase(id, floor);
    }

    /// @notice Pay the sDGNRS leg of an all-time record claim and name the record's payee.
    /// @dev Access: COINFLIP only, which owns the all-time records (flip, spin, luckbox,
    ///      buy, dice run) and computes the claim's accrued pool share. Pays that share
    ///      at 1/500 scale from the sDGNRS reward pool — 0.01% to 0.15% of the pool per
    ///      claim across the share curve. transferFromPool clamps to the available
    ///      balance and returns the exact decrement, zero on an empty pool. The payee is
    ///      returned on every call, a zero share included: Coinflip mints the record
    ///      trophy to it on every ratchet.
    /// @return paid The sDGNRS actually transferred.
    /// @return payee The address paid the sDGNRS and the trophy.
    function payRecordSdgnrs(
        uint32 id,
        uint256 shareBps
    ) external returns (uint256 paid, address payee) {
        return _gamePayRecordSdgnrs(id, shareBps);
    }

    /*+======================================================================+
      |                      OPERATOR APPROVALS                              |
      +======================================================================+*/

    /// @notice Approve or revoke `operator` for account `id` (0 = the caller's own account).
    /// @dev The caller's own account must already hold an ID. A nonzero `id` must be allocated
    ///      and the caller must be its payee: the key itself or a smurf's owner (operators
    ///      cannot approve operators).
    /// @custom:reverts ZeroAddress If operator is the zero address.
    function setOperatorApproval(uint32 id, address operator, bool approved) external {
        _gameSetOperatorApproval(id, operator, approved);
    }

    /// @notice Resolve account `id` for `caller`: its key, its payee and whether `caller` may
    ///         act for it (the key, a smurf's owner, or an operator approved for `id`). Never
    ///         reverts on authorization.
    /// @custom:reverts E If `id == 0` or `id` is unallocated.
    function resolveAccount_g7029(uint32 id, address caller)
        external
        view
        returns (address key, address payee, bool authorized)
    {
        return _account(id, caller);
    }

    /// @notice Create a smurf account owned and referred by the caller and
    ///         buy it one ticket, all in one call.
    /// @return smurfId The new account's wallet ID.
    function createSmurf(bytes32 affiliateCode, MintPaymentKind payKind)
        external
        payable
        returns (uint32 smurfId)
    {
        return _gameCreateSmurf(affiliateCode, payKind);
    }

    /// @notice Vault-owner-only permanent increase to an ordinary main ID's base smurf allowance.
    function raiseSmurfBaseAllowance(uint32 mainId, uint16 newBase) external {
        _gameRaiseSmurfBaseAllowance(mainId, newBase);
    }

    /*+======================================================================+
      |                       LOOT BOX CONTROLS                              |
      +======================================================================+*/

    /// @notice Most recently requested normal logical round; bootstrap is day 1.
    function currentDayView_g542950() external view returns (uint24) {
        return _gameDay();
    }

    /// @notice Calendar reset window, relative to deployment; resets at 22:57 UTC.
    function currentWallDayView() external view returns (uint24) { return _wallDay(); }

    /// @notice Current daily commitment completion and its real-time clocks.
    function dailySessionState() external view returns (bool complete, uint24 requestWallDay, uint48 completedAt) {
        return (dailyComplete, lastDailyRequestWallDay, lastDailyCompletedAt);
    }

    /// @notice Latest applied daily result, independent of an unresolved request.
    function latestDailyResultDay() external view returns (uint24) { return _latestDailyResultDay(); }

    /// @notice Scheduled admissions require the current reset's request and published terms.
    function dailyScheduleOpen_g214() external view returns (bool) {
        return !_livenessTriggered() && !_dailyRequestDue() && _recordedDailyWord(dailyIdx) != 0;
    }

    /// @dev Shared by the vault-owner controls; preserve the same external check and error.

    /// @notice Update lootbox RNG request threshold (wei).
    /// @dev Access: vault owner only (DGVE governance executor).
    /// @custom:reverts OnlyVault If caller is not the vault owner.
    /// @custom:reverts ZeroValue If newThreshold is zero.
    function setLootboxRngThreshold(uint256 newThreshold) external {
        _gameSetLootboxRngThreshold(newThreshold);
    }

    /// @notice Update the basefee ceiling above which mid-day RNG requests are refused.
    /// @dev Access: vault owner only (DGVE governance executor). Zero disables the gate.
    ///      Bounds what a mid-day fulfillment can cost the subscription by declining to
    ///      issue the request while the block is expensive; the daily advance is never
    ///      gated, so the game's own RNG is unaffected and pending boxes simply wait for
    ///      it. A lower ceiling narrows the gap a fulfillment can open between its own
    ///      price and the basefee its redemption was charged at.
    /// @custom:reverts OnlyVault If caller is not the vault owner.
    /// @custom:reverts OutOfBounds If newGwei exceeds the packed field's range.
    function setMiddayMaxBasefee(uint256 newGwei) external {
        _gameSetMiddayMaxBasefee(newGwei);
    }

    /// @notice Declare a future level a thanos level: every entry drained for
    ///         targetLevel onward divides by 2^shift.
    /// @dev Thin delegatecall dispatch stub into DegenerusGameGameOverModule, which holds the
    ///      bounds, the vault-owner check and the declaration body. Signature:
    ///      setThanosLevel(uint24 targetLevel, uint8 shift); identical selector, calldata
    ///      forwards as-is.
    /// @custom:reverts OnlyVault If caller is not the vault owner.
    /// @custom:reverts ThanosBounds If any declaration bound is violated.
    function setThanosLevel(uint24, uint8) external {
        (bool ok, bytes memory data) = ContractAddresses.GAME_GAMEOVER_MODULE.delegatecall(msg.data);
        if (!ok) _revertGameDelegate(data);
    }

    /// @notice Purchase any combination of tickets and loot boxes with ETH or claimable.
    /// @dev Main entry point for all ETH/claimable purchases. For FLIP purchases, use redeemFlip().
    ///      Recycling at least 3 tickets' worth of claimable winnings earns a 10% FLIP flip-credit bonus.
    ///      Adds affiliate support for loot box purchases.
    ///      Account `id` (0 = caller) receives the purchases; the caller must be authorized
    ///      for it. Fresh ETH comes from the caller; claimable and AFKing legs spend the account's.
    /// @param id Account receiving the purchases (0 = caller).
    /// @param entryQuantityScaled Scaled entry quantity (400 units = 1 whole ticket; 0 to skip).
    /// @param boxOrder Packed box order (0 to skip): [quantity:7][kind:2][customUnits:21], every
    ///        bit at or above 30 zero. One box type per purchase: kind 0/1/2 is 1x/5x/25x the
    ///        active level's ticket price, kind 3 a custom of customUnits x 0.001 ETH per box
    ///        (0.01 to 2,000 ETH). Quantity 1-100; each purchase is its own queue entry.
    /// @param affiliateCode Affiliate/referral code for all purchases.
    /// @param payKind Payment method (DirectEth, Claimable, or Combined).
    /// @param foil True to additively buy one foil pack (10x the price scaled by the level's
    ///        snap exponent) in the same tx. The foil leg is one-per-cycle and adds to — never
    ///        replaces — the ticket and lootbox legs, sharing the combined spend's affiliate,
    ///        quest, and streak recording so a foil pack counts exactly like a ticket purchase.
    function purchase(
        uint32 id,
        uint256 entryQuantityScaled,
        uint256 boxOrder,
        bytes32 affiliateCode,
        MintPaymentKind payKind,
        bool foil
    ) external payable {
        if (foil) {
            (bool ok, bytes memory data) = ContractAddresses
                .GAME_FOILPACK_MODULE
                .delegatecall(
                    abi.encodeWithSelector(
                        IDegenerusGameFoilPackModule.purchaseWithFoil.selector,
                        id,
                        entryQuantityScaled,
                        boxOrder,
                        affiliateCode,
                        payKind
                    )
                );
            if (!ok) _revertGameDelegate(data);
        } else {
            _gamePurchase(
                id,
                entryQuantityScaled,
                boxOrder,
                affiliateCode,
                payKind
            );
        }
    }

    /// @notice Purchase tickets with FLIP.
    /// @dev Main entry point for FLIP ticket purchases. Mirrors purchase() but for FLIP payments.
    ///      SECURITY: The redemption window latches open only with no RNG in flight;
    ///      once open it stays usable through the jackpot days' locks until the final
    ///      jackpot request clears it.
    ///      The FLIP is burned from the account's payee.
    ///      Signature: redeemFlip(uint32 id, uint256 entryQuantityScaled) — the account receiving
    ///      the tickets (0 = caller) and the purchase units (400 = one whole ticket = 4 entries).
    function redeemFlip(
        uint32 id,
        uint256 entryQuantityScaled
    ) external {
        _gameRedeemFlip(id, entryQuantityScaled);
    }

    /// @notice Buy a credit-gated Degenesis box with ETH and/or claimable.
    /// @dev Gated by degenesisCredit (25% of qualifying spend), consumed 1:1; the order joins
    ///      today's cohort and settles after the cohort is priced.
    ///      Signature: buyDegenesisBox(uint32 id, uint256 amount) — the account receiving the order
    ///      (0 = caller) and the Degenesis ETH. The module resolves the account, so the
    ///      arguments use the module's low-selector entry; caller and value are preserved.
    function buyDegenesisBox(uint32, uint256) external payable {
        (uint32 id, uint256 amount) = abi.decode(msg.data[4:], (uint32, uint256));
        (bool ok, bytes memory data) = ContractAddresses.GAME_DEGENESIS_MODULE.delegatecall(
            abi.encodeWithSelector(IDegenerusGameDegenesisModule.buyDegenesisBox_g1442.selector, id, amount)
        );
        if (!ok) _revertGameDelegate(data);
    }

    /// @notice Vault-only: spend the Vault's Degenesis budget on tickets and lootboxes, or whale
    ///         passes, for an allocated recipient at their normal price.
    /// @dev Signature: spendDegenesis(uint32 recipientId, bool whalePass, uint256 quantity, uint256 boxOrder,
    ///      uint256 maxCost). Forwards as-is so the module sees the Vault as msg.sender.
    function spendDegenesis(uint32, bool, uint256, uint256, uint256) external {
        (bool ok, bytes memory data) = ContractAddresses.GAME_DEGENESIS_MODULE.delegatecall(msg.data);
        if (!ok) _revertGameDelegate(data);
    }

    /// @notice Permissionlessly resolve account `id`'s foil match claim (value credits to the account).
    /// @dev Signature: claimFoilMatch(uint32 id, uint256 day, uint256 ticketIndex) (0 = caller). The
    ///      eligible cycle level is read inside the module from the day's sealed draw. The win
    ///      credits to the account, never the caller, and a tuple pays at most once (CEI marker),
    ///      so anyone may trigger it. The day's one board x four tickets give 4 independent
    ///      claimables per day. Claims are valid on the draw day and the following day,
    ///      revert with RngLocked under the daily RNG lock, and close when terminal
    ///      settlement triggers. The signature matches the module
    ///      function exactly (identical selector), so the calldata forwards as-is —
    ///      re-encoding would cost size headroom for no change.
    function claimFoilMatch(
        uint32,
        uint256,
        uint256
    ) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_FOILPACK_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertGameDelegate(data);
    }

    /// @notice Permissionlessly resolve a batch of foil match claims (uint32[] ids,
    ///         uint24[] days, uint8[] ticketIndexes; an id of 0 is the caller).
    /// @dev Non-claimable tuples past index 0 are skipped, not reverted; each settled win
    ///      credits its own account. A non-claimable tuple AT index 0 reverts the whole call
    ///      (StaleBatch), so a second sender handed an already-swept list sees the failure
    ///      in simulation instead of paying to walk it; the daily RNG lock reverts it up
    ///      front (RngLocked). Claims are valid on the draw day and the following day, and
    ///      close when terminal settlement triggers. The signature matches the module
    ///      function exactly, so the calldata forwards as-is.
    function claimFoilMatchMany(
        uint32[] calldata,
        uint24[] calldata,
        uint8[] calldata
    ) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_FOILPACK_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertGameDelegate(data);
    }

    /// @notice Claim a foil pack's gold: a FLIP ladder from three golds up, or the
    ///         golden-ticket grand when two whole tickets came out all gold.
    /// @dev Signature: claimGoldenTicket(uint32 id, uint24 lvl) (0 = caller). The pack's four
    ///      lines are re-derived inside the module from the sealed word its buy froze
    ///      against, so nothing about the gold is stored and the drain stays untouched.
    ///      The win credits to the account, never the caller, and a pack pays at most once
    ///      (CEI marker), so anyone may trigger it. The signature matches the module
    ///      function exactly (identical selector), so the calldata forwards as-is.
    function claimGoldenTicket(uint32, uint24) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_FOILPACK_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertGameDelegate(data);
    }

    /// @notice Purchase whale pass: boosts levelCount, queues 100 levels of ticket entries, includes lootbox.
    /// @dev Available at any level. Can be purchased multiple times (1-100 per call).
    ///      Price: 2.4 ETH (levels 0-3), 4 ETH (levels 4+), or discounted with boon.
    ///      Per pass x quantity: 20 entries/level for [passLevel..9]; the rest of the 100-level
    ///      span from passLevel = level+1 pays 2 x quantity half-passes as whole tickets
    ///      (4 entries = 1 whole ticket), strided so one pass earns a ticket every 2nd level.
    ///      Every 5 passes in one purchase award one more pass's entries; price, lootbox and
    ///      credits follow the paid quantity.
    ///      Includes lootbox (10% of price, one box per pass bought).
    ///      Frozen stats don't increment until game reaches the frozen level.
    ///
    ///      Fund distribution - Level 0: 30% next / 70% future.
    ///      Fund distribution - Other levels: 5% next / 95% future.
    ///
    ///      Example at level 1 (passLevel 2): 20 entries/lvl for 2-9, one whole ticket every 2nd
    ///      level over 10-101, frozen until 101.
    ///      Example at level 51 (passLevel 52): no bonus levels, one whole ticket every 2nd level
    ///      over 52-151, frozen until 151.
    ///        free-tranche seat go to its payee.
    function purchaseWhalePass(uint32, uint256, bytes32) external payable {
        (bool ok, bytes memory data) = ContractAddresses.GAME_WHALE_MODULE.delegatecall(msg.data);
        if (!ok) _revertGameDelegate(data);
    }

    /// @notice Purchase a 10-level lazy pass (direct in-game activation).
    /// @dev Available at levels 0-2 or x9 (9, 19, 29...), or with a valid lazy pass boon.
    ///      Levels 0-2: flat 0.24 ETH. Levels 3+: sum of per-level ticket prices across 10-level window.
    function purchaseLazyPass(uint32, bytes32) external payable {
        (bool ok, bytes memory data) = ContractAddresses.GAME_WHALE_MODULE.delegatecall(msg.data);
        if (!ok) _revertGameDelegate(data);
    }

    /// @notice Purchase a deity pass for a specific symbol (0-31).
    /// @dev One deity per main wallet (the payee); the pass NFT mints to that main wallet.
    function purchaseDeityPass(uint32, uint8, bytes32) external payable {
        (bool ok, bytes memory data) = ContractAddresses.GAME_WHALE_MODULE.delegatecall(msg.data);
        if (!ok) _revertGameDelegate(data);
    }

    /// @notice Place a funded ETH or FLIP bet for an account; an unauthorised funder pays for its gift.
    function placeDegeneretteBet(uint32 id, uint8 currency, uint128 amountPerSpin, uint8 spinCount, uint8 symbol)
        external payable
    {
        _gamePlaceBet(id, currency, amountPerSpin, spinCount, symbol);
    }

    /// @notice Consume the trusted caller's coinflip, craps or WWXRP boon lane.
    function consumeCoinflipBoon_g2902(uint32 id) external returns (uint16 boostBps) {
        if (msg.sender != ContractAddresses.COIN && msg.sender != ContractAddresses.COINFLIP
            && msg.sender != ContractAddresses.WWXRP) revert Unauthorized();
        return _gameConsumeActionBoon(id);
    }

    /// @notice Consume the account's decimator boon; only COIN may spend this lane.
    function consumeDecimatorBoon(uint32 id) external returns (uint16 boostBps) {
        if (msg.sender != ContractAddresses.COIN) revert Unauthorized();
        return _gameConsumeDecimatorBoost(id);
    }

    /// @notice Get raw deity boon state for off-chain or viewer contract computation.
    /// @return dailySeed Yesterday's finalized RNG word (0 if unavailable). Automatic
    ///         protocol draws then use today's word, available through rngWordForDay.
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
        return deityBoonDataById(_walletIdOf(deity));
    }

    function deityBoonDataById(
        uint32 deityId
    )
        public
        view
        returns (
            uint256 dailySeed,
            uint24 day,
            uint8 usedMask,
            bool decimatorOpen,
            bool deityPassAvailable
        )
    {
        day = _gameDay();
        uint32 boonPacked = uint32(deityBoonPacked[deityId]);
        usedMask = uint24(boonPacked) == day ? uint8(boonPacked >> 24) : 0;
        decimatorOpen = _decWindowOpen();
        deityPassAvailable = _deityCount() < 32; // DEITY_PASS_MAX_TOTAL (see LootboxModule)
        // The issuance day's menu is fixed by the preceding day's finalized word.
        // Manual gifts need this predecessor. Automatic protocol draws fall back
        // to the award-day word when no predecessor exists.
        dailySeed = _recordedDailyWord(day - 1);
    }

    /// @notice Issue one deity account's daily boon to an existing recipient account.
    function issueDeityBoon(uint32 deityId, uint32 recipientId, uint8 slot) external {
        _gameIssueDeityBoon(deityId, recipientId, slot);
    }

    /*+==========================================================================+
      |                       TICKET QUEUEING                                    |
      +==========================================================================+
      |  Tickets are queued for batch processing rather than minted immediately. |
      |  This prevents gas exhaustion from large purchases.                      |
      +==========================================================================+*/

    // Worker facades preserve explicit delegatecall frames in Game storage.
    // Targets and bundle aliases come from the canonical deployment manifest.

    /*+========================================================================================+
      |                    DECIMATOR JACKPOT LOGIC                                             |
      +========================================================================================+*/

    /// @notice Add chips to a wallet's accumulated Decimator battle entry (COIN only).
    function recordDecBurn_g1271(uint32, uint24, uint256, uint256, uint32) external returns (uint64) {
        (bool ok, bytes memory data) = ContractAddresses.GAME_DECIMATOR_MODULE.delegatecall(msg.data);
        if (!ok) _revertGameDelegate(data);
        return abi.decode(data, (uint64));
    }

    /// @notice Seal a Decimator battle for bounded run and payout settlement.
    /// @dev Access: Game-only (self-call).
    ///      Signature: runDecimatorJackpot(uint256 poolWei, uint24 lvl, uint256 rngWord) — the
    ///      total ETH prize pool for this level, the level being resolved, and the
    ///      VRF-derived randomness seed. The signature matches the module function exactly
    ///      (identical selector), so the calldata forwards as-is — re-encoding here would cost
    ///      contract-size headroom for no behavior change.
    /// @return returnAmountWei Amount to return (no entries or this round was already sealed).
    function runDecimatorJackpot(
        uint256,
        uint24,
        uint256
    ) external returns (uint256 returnAmountWei) {
        if (msg.sender != address(this)) revert OnlySelf();
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_DECIMATOR_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertGameDelegate(data);
        return abi.decode(data, (uint256));
    }

    /// @notice Arm the staged BAF jackpot at a level-multiple-of-10 transition.
    /// @dev Access: Game-only (self-call from AdvanceModule orchestration).
    ///      Signature: runBafJackpot(uint256 poolWei, uint24 lvl, uint256 rngWord) — the ETH
    ///      allocated to this BAF tier, the level being resolved, and the VRF-derived randomness
    ///      seed. The signature matches the module function exactly (identical selector), so the
    ///      calldata forwards as-is — re-encoding here would cost contract-size headroom for no
    ///      behavior change.
    /// @return claimableDelta ETH reserved in the claimable pool for the award schedule.
    function runBafJackpot(
        uint256,
        uint24,
        uint256
    ) external returns (uint256 claimableDelta) {
        if (msg.sender != address(this)) revert OnlySelf();
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_JACKPOT_DRAW_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertGameDelegate(data);
        return abi.decode(data, (uint256));
    }

    /// @notice Continue the frozen terminal payout through the shared gas allowance.
    /// @dev Access: Game-only (self-call). Delegatecalls to JackpotModule; updates claimablePool
    ///      internally, so callers must not double-count.
    function runTerminalJackpotWork(uint256, uint24, uint256, uint256)
        external returns (MineFlipGas.Result memory result, uint256 paidDelta)
    {
        if (msg.sender != address(this)) revert OnlySelf();
        (bool ok, bytes memory data) = ContractAddresses.GAME_JACKPOT_MODULE.delegatecall(msg.data);
        if (!ok) _revertGameDelegate(data);
        return abi.decode(data, (MineFlipGas.Result, uint256));
    }

    /// @notice Roll, record and emit level 1's purchase-day board via jackpot module.
    /// @dev Access: Game-only (self-call). Delegatecalls to JackpotModule.
    ///      Used at purchaseLevel==1 where runDailyJackpot is skipped.
    ///      Signature: emitDailyWinningTraits(uint256 randWord). The signature matches the
    ///      module function exactly (identical selector), so the calldata forwards as-is —
    ///      re-encoding here would cost contract-size headroom for no behavior change.
    function emitDailyWinningTraits(uint256) external {
        if (msg.sender != address(this)) revert OnlySelf();
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_JACKPOT_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertGameDelegate(data);
    }

    /*+========================================================================================+
      |                    CLAIMING WINNINGS (ETH)                                             |
      +========================================================================================+
      |  Players claim accumulated winnings from ContractAddresses.JACKPOTS, affiliates,       |
      |  and endgame payouts through the claimWinnings() function.                             |
      |                                                                                        |
      |  SECURITY:                                                                             |
      |  • Uses CEI pattern (Checks-Effects-Interactions)                                      |
      |  • Never pays the account's unbacked 1-wei claimable sentinel                          |
      |  • Falls back to stETH if ETH balance insufficient                                     |
      |  • claimablePool is decremented before external call                                   |
      +========================================================================================+*/

    /// @notice Emitted when claimable ETH winnings are paid out.
    /// @param amount Total value paid — native ETH plus any stETH fallback (never the 1-wei sentinel).
    /// @param claimableAfter Raw claimable left after the claim (including the 1-wei sentinel). Not
    ///        derivable from `amount`: claimWinnings(player, amount) is a partial cashout, so the
    ///        residual is arbitrary pre-gameOver.
    event WinningsClaimed(
        uint32 indexed player,
        uint256 amount,
        uint128 claimableAfter
    );

    /// @notice Claim accrued ETH winnings.
    /// @dev Aggregates all winnings: affiliates, ContractAddresses.JACKPOTS, endgame payouts.
    ///      Uses pull pattern for security (CEI: check balance, update state, then transfer).
    ///
    ///      Every account is created holding a 1-wei claimable sentinel outside claimablePool;
    ///      the claim never pays it, so later credits always write a nonzero slot.
    ///
    ///      SECURITY: Reverts if balance ≤ 1 wei (nothing to claim).
    ///      Debits account `id` and pays its payee; the caller must be authorized for it.
    function claimWinnings(uint32 id) external {
        _gameClaimWinnings(id);
    }

    /// @notice Claim a fixed amount of accrued ETH winnings (partial cashout).
    /// @dev Draws up to `amount` wei from claimable winnings (capped to leave the 1-wei sentinel).
    ///      Post-gameOver the claim also takes the caller's whole prepaid afking, which
    ///      `withdrawAfkingFunding` can draw down in parts first. The cap holding after game over
    ///      is what lets a claimant take the ETH that exists while a stETH leg cannot move. Runs
    ///      the cashout curse like the full claim — a partial cashout is still a cashout (the
    ///      curse is activity-gated).
    /// @param amount Maximum wei of claimable winnings to take.
    function claimWinnings(uint32 id, uint256 amount) external {
        _gameClaimWinnings(id, amount);
    }

    /// @dev Shared claim body: pull winnings (capped pre-gameOver by `maxClaim`) to the account's
    ///      payee, then set the account's cashout curse in the same storage context.


    /// @notice Claim accrued ETH winnings with stETH-first payout.
    /// @dev Restricted to self-claims by the vault contract.
    function claimWinningsStethFirst() external {
        _gameClaimWinningsStethFirst();
    }

    ///        claim also settles the whole afking half.


    /// @notice Fund account `id`'s prepaid afking ETH bucket (consumed by the AfKing auto-buy).
    /// @dev Permissionless (fund anyone). `id` is a third-party recipient: nonzero and allocated.
    ///      The reservation rides inside claimablePool (no separate aggregate) — credited in tandem.
    ///      Blocked once the game is over, like receive(): post-sweep afking is unwithdrawable.
    function depositAfkingFunding(uint32 id) external payable {
        _gameDepositAfkingFunding(id);
    }

    /// @notice Withdraw prepaid afking ETH from account `id` (0 = caller) to its payee.
    /// @dev Un-brickable strict CEI: the GO_SWEPT guard is LINE 1 (before any debit), so a
    ///      post-final-sweep withdraw reverts cleanly instead of underflowing claimablePool
    ///      (which the sweep zeroes). Both debits land BEFORE the .call, so a re-entrant second
    ///      call re-reads the already-debited balance and reverts. Available always pre-sweep
    ///      (mid-game, after cancel, post-gameOver). The claimablePool debit stays checked math.
    /// @param amount ETH amount (wei) to withdraw from the account's afkingFunding bucket.
    function withdrawAfkingFunding(uint32 id, uint256 amount) external {
        _gameWithdrawAfkingFunding(id, amount);
    }

    /// @notice The canonical per-player prepaid afking ETH balance.
    /// @return The player's afkingFunding balance (wei).
    function afkingFundingOf(address player) external view returns (uint256) {
        return _afkingOf(_walletIdOf(player));
    }

    /// @notice Settle an account's affiliate reward to its payee.
    function claimAffiliateDgnrs(uint32 id) external { _gameClaimAffiliateDgnrs(id); }

    /// @notice Permissionless batch affiliate-DGNRS claim; a blank array claims the caller's own.
    /// @dev Per-item isolated: an ineligible / already-claimed affiliate skips instead of
    ///      reverting the batch (the single-affiliate entry above is the catchable boundary).
    ///      The isolating self-call runs with msg.sender == this contract, so an ID of 0 maps to
    ///      the caller's own ID first; for a caller with no ID that stays 0, which the body
    ///      rejects (propagated for the blank array, skipped inside a batch).
    function claimAffiliateDgnrs(uint32[] calldata ids) external {
        uint256 len = ids.length;
        uint32 self = _walletIdOf(msg.sender);
        if (len == 0) {
            // Blank array: settle the caller's own claim (propagates if ineligible).
            this.claimAffiliateDgnrs(self);
            return;
        }
        for (uint256 i; i < len; ) {
            uint32 id = ids[i];
            try this.claimAffiliateDgnrs(id == 0 ? self : id) {} catch {}
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

    /// @notice O(1) discovery: does mineFlip() have pending work for a creditless caller?
    /// @dev Queries the same derived action selector used by the miner engine.
    function advanceDue() external view returns (bool) {
        uint8 action = uint8(_nextMinerAction(address(this)));
        return action != uint8(MinerAction.Idle) && action != uint8(MinerAction.Wait);
    }

    /// @notice Every address passes the miner participation gate.
    /// @dev Payment still requires sufficient measured work and a nonterminal successful call.
    function bountyEligible(address) external pure returns (bool) {
        return true;
    }

    /// @notice O(1) discovery hint: does the delivered read cohort still need miner work?
    /// @dev Includes empty-frontier skips and Craps-only cohorts, so miners do not idle
    ///      while fresh RNG waits for completion. FALSE during the daily lock or liveness.
    function boxesPending() external view returns (bool) {
        if (rngLockedFlag || _livenessTriggered()) return false;
        return _rngSessionPublished() && _currentRngWord() != 0 && !_lootboxReadComplete();
    }

    /// @notice Whether boxes and Degenerette bets in the current read buffer have finished.
    /// @dev Physical tags are reused; this view makes no statement about historical sessions.
    function boxIndexComplete(uint48 index) external view returns (bool) {
        return index == _rngReadBuffer() && humanReadComplete && degeneretteCursor >= degeneretteReadCount;
    }

    /*+======================================================================+
      |                    LOOTBOX CLAIMS                                    |
      +======================================================================+*/

    /// @notice Claim deferred whale pass rewards. `whalePassClaims` is fed in half-pass units by
    ///         large lootbox wins (>5 ETH), the solo jackpot bucket, golden tickets, the lootbox
    ///         whale-pass boon and foil tier 8.
    /// @dev Thin, PERMISSIONLESS delegatecall dispatch stub into the whale module — forwards
    ///      `msg.data` verbatim (msg.sender preserved). No approval gate: the claim only awards
    ///      the account its own deferred tickets (it never moves value to the caller), so
    ///      cranking it for anyone is safe. Signature: claimWhalePass(uint32 id) (0 = caller) —
    ///      matches the module selector.
    function claimWhalePass(uint32) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_WHALE_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertGameDelegate(data);
    }

    /*+======================================================================+
      |                    REDEMPTION LOOTBOX                                |
      +======================================================================+*/

    /// @notice Resolve redemption lootboxes for an sDGNRS gambling burn claim.
    /// @dev Called by sDGNRS during the miner's live redemption settlement. Delegatecall stub into
    ///      DegenerusGameLootboxModule's resolveRedemptionLootbox body (auth, reserve debit,
    ///      pool credit, and the one-order box resolution all live there). The signature matches
    ///      the module function exactly (identical selector), so the calldata forwards as-is —
    ///      re-encoding here would cost contract-size headroom for no behavior change.
    ///      Signature: resolveRedemptionLootbox(uint32 playerId, uint256 amount,
    ///      uint256 rngWord, uint16 activityScore, uint32 batchId).
    function resolveRedemptionLootbox(
        uint32,
        uint256,
        uint256,
        uint16,
        uint32
    ) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_LOOTBOX_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertGameDelegate(data);
    }

    /// @notice Credit the direct half of an sDGNRS redemption claim to `player`'s claimable winnings.
    /// @dev Called by sDGNRS while it settles a live redemption. The value is drawn from the
    ///      redemption reserve, which already sits inside claimablePool. Body lives in the lootbox
    ///      module; the thin stub forwards the calldata.
    ///      Signature: creditRedemptionDirect(uint32 playerId, uint256 amount).
    function creditRedemptionDirect(uint32, uint256) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_LOOTBOX_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertGameDelegate(data);
    }

    /*+===============================================================================================+
      |                    JACKPOT PAYOUT FUNCTIONS                                                   |
      +===============================================================================================+
      |  Functions for distributing jackpot winnings. Most jackpot logic                              |
      |  lives in the ContractAddresses.GAME_JACKPOT_MODULE (via delegatecall).                       |
      |                                                                                               |
      |  Jackpot Types:                                                                               |
      |  • Daily jackpot - Paid each day to the level's trait-entry holders (final day = full pool)       |
      |  • BAF (Big Ass Flip) - At every x10 level, and only if that day's flip won: 10% of the       |
      |    future pool, raised to 20% at level 50 and at every x00. A losing flip marks the           |
      |    bracket skipped and leaves the pool in place; at x00 a share of the FLIP that day's         |
      |    depositors lost is credited to one WWXRP burner drawn from the level-x99 incinerator entries. |
      |  • Decimator - 10% of the future pool at x5 levels (excluding x95), 30% at every x00.         |
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
      |  • Swaps are unit-for-unit in nominal terms (no fund extraction);    |
      |    economic parity depends on stETH trading at par, not checked here |
      +======================================================================+*/

    /// @notice Admin-only swap: caller sends ETH in and receives game-held stETH.
    /// @dev Used to rebalance when stETH yield should be converted to ETH.
    ///      Admin must send exact ETH amount equal to stETH received.
    ///      SECURITY: Value-neutral swap, ADMIN cannot extract funds.
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
        _gameAdminSwapEthForStEth(recipient, amount);
    }

    /// @notice Stake game-held ETH into stETH via Lido.
    /// @dev Access: vault owner only (DGVE governance executor).
    ///      SECURITY: Must retain ETH to cover player claims, excluding vault/DGNRS
    ///      claimable (those addresses accept stETH payouts natively).
    /// @param amount ETH amount to stake.
    /// @custom:reverts OnlyVault If caller is not the vault owner.
    /// @custom:reverts ZeroValue If amount is zero.
    /// @custom:reverts Insolvent If ETH is insufficient or staking would dip into the player-claim ETH reserve.
    /// @custom:reverts TransferFailed If the Lido submit fails.
    function adminStakeEthForStEth(uint256 amount) external {
        _gameAdminStakeEthForStEth(amount);
    }

    /*+======================================================================+
      |                    VRF (CHAINLINK) INTEGRATION                       |
      +======================================================================+
      |  Chainlink VRF V2.5 integration for provably fair randomness.        |
      |                                                                      |
      |  LIFECYCLE:                                                          |
      |  1. mineFlip() calls requestDailyRng() as its final normal action    |
      |  2. Chainlink calls rawFulfillRandomWords(); the word is stored      |
      |  3. A later mineFlip() calls publishRng() to publish the word        |
      |  4. After processing, _unlockRng() resets for next cycle             |
      |                                                                      |
      |  SECURITY:                                                           |
      |  • RNG lock prevents state manipulation during VRF window            |
      |  • Single 20h timeout retry (vault owner via Admin) per request      |
      |  • Governance-gated coordinator rotation via Admin                   |
      |  • Nudge system allows players to influence (not predict) RNG        |
      +======================================================================+*/

    /// @notice Emergency VRF coordinator rotation (governance-gated).
    /// @dev Access: ADMIN only. Stall duration enforced by Admin governance.
    ///      Signature: updateVrfCoordinatorAndSub(address newCoordinator, uint256 newSubId,
    ///      bytes32 newKeyHash, uint32 newCallbackGasLimit) — the new VRF coordinator address, the
    ///      new subscription ID, the new key hash for the gas lane and the callback gas limit. The signature matches the module function exactly
    ///      (identical selector), so the calldata forwards as-is — re-encoding here would cost
    ///      contract-size headroom for no behavior change.
    /// @custom:reverts OnlyAdmin If caller is not ADMIN.
    function updateVrfCoordinatorAndSub(
        address,
        uint256,
        bytes32,
        uint32
    ) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_GAMEOVER_MODULE
            .delegatecall(msg.data);
        if (!ok) _revertGameDelegate(data);
    }

    /// @notice Retry an unanswered request through the authorized Admin entry after 20 hours.
    /// @dev The RNG module enforces ADMIN access, terminal precedence and the single retry limit.
    function retryRng() external {
        (bool ok, bytes memory data) = ContractAddresses.GAME_RNG_MODULE.delegatecall(msg.data);
        if (!ok) _revertGameDelegate(data);
    }

    /// @notice Mint mid-day RNG credit to a native ETH donor.
    /// @dev Access: ADMIN only — called from the native donation hook once the donated native ETH
    ///      has reached the VRF coordinator, so credit only ever trails native ETH the subscription
    ///      already holds. A donation is a payment, so the donor registers a wallet ID; the
    ///      RNG module holds the body. Signature: creditMiddayRng(address to, uint256
    ///      amount) — matches the module selector, so the calldata forwards as-is.
    /// @return The donor's wallet ID.
    function creditMiddayRng(address, uint256) external returns (uint32) {
        (bool ok, bytes memory data) = ContractAddresses.GAME_RNG_MODULE.delegatecall(msg.data);
        if (!ok) _revertGameDelegate(data);
        // The trusted RNG module returns the identical one-word ABI result.
        assembly ("memory-safe") { return(add(data, 32), mload(data)) }
    }

    /// @notice Read a donor's unspent mid-day RNG credit, in wei.
    function middayRngCredits(address account) external view returns (uint256) {
        return middayRngCredit[_walletIdOf(account)];
    }

    error NudgeCapReached();

    /// @notice Pay the quoted FLIP cost to nudge the next daily RNG word by +1.
    /// @dev Cost scales +50% per queued nudge, rounds up to a whole FLIP, and resets after
    ///      the queued nudges are applied. The caller-supplied quote prevents a transaction
    ///      from paying a higher price if another nudge lands first.
    ///      Only available while RNG is unlocked (before VRF request is in-flight).
    ///      MECHANISM: Adds 1 to the VRF word for each nudge, changing outcomes.
    ///      SECURITY: Players cannot predict the base word, only influence it.
    /// @custom:reverts RngLocked If RNG is currently locked (VRF request pending).
    /// @custom:reverts NudgeCostChanged If the live quote differs from expectedCost.
    /// @custom:reverts E Once the liveness timeout has fired (see the gate below).
    function reverseFlip(uint256 expectedCost) external {
        _gameReverseFlip(expectedCost);
    }

    /// @notice Return the queued nudge count and exact cost of the next nudge.
    /// @return queued Number of nudges waiting for the next daily RNG word.
    /// @return cost Whole-FLIP price required by reverseFlip.
    function rngNudgeQuote() external view returns (uint256 queued, uint256 cost) {
        queued = _nudgeCount();
        cost = queued >= RNG_NUDGE_CAP ? 0 : _currentNudgeCost(queued);
    }

    /// @dev Calculate nudge cost with compounding.
    ///      Base cost is 100 FLIP. Each +50% step floors to a whole token:
    ///      100, 150, 225, 337, 505, ... .
    /// @return cost FLIP cost for the next nudge.


    /// @notice Chainlink VRF callback for random word fulfillment.
    /// @dev Accepts the coordinator's response to the active request and stores the final
    ///      session word; publication is a later miner action. A daily lock adds the frozen
    ///      nudge count. Final values 0/1 leave the request pending for retry. The coordinator
    ///      fulfills each request once, so only a superseded request (retry or re-issue) can
    ///      arrive late; its ID no longer matches and it is ignored, not reverted. Runs in the
    ///      base contract so the Native-paid callback carries no delegatecall overhead.
    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external {
        uint256 vrf;
        // The coordinator and request ID share one slot.
        assembly ("memory-safe") { vrf := sload(vrfCoordinator.slot) }
        if (msg.sender != address(uint160(vrf))) revert OnlyCoordinator();
        uint16 flags;
        bool daily;
        uint64 id;
        uint256 word;
        assembly ("memory-safe") {
            let state := sload(rngFlagsAndNudges.slot)
            flags := shr(mul(rngFlagsAndNudges.offset, 8), state)
            daily := and(shr(mul(rngLockedFlag.offset, 8), state), 1)
            id := shr(mul(vrfRequestId.offset, 8), vrf)
            // The coordinator always sends the one requested word; no further decoding.
            word := calldataload(randomWords.offset)
        }
        if (flags & (uint16(1) << 14) == 0 || uint64(requestId) != id) return;

        // Addition preserves the uniform distribution. The two reserved final values
        // leave this request waiting for its existing retry path (probability 2 / 2^256).
        if (daily) {
            // The frozen count is the low byte of the same slot-0 snapshot: no extra SLOAD.
            unchecked { word += flags & 0xFF; }
        }
        if (word < 2) return;
        rngWordCurrent = word;
    }

    /*+======================================================================+
      |                    PAYMENT HELPERS                                   |
      +======================================================================+
      |  Internal functions for ETH/stETH payouts.                           |
      |  Implements fallback logic when one asset is insufficient.           |
      +======================================================================+*/

    /// @dev Send stETH first, then ETH for remainder. Reached only from
    ///      claimWinningsStethFirst, which is VAULT-gated — sDGNRS and players claim
    ///      through the ETH-first path.
    /// @param to Recipient address.
    /// @param amount Total wei to send.


    /*+======================================================================+
      |                   VIEW: GAME STATUS & STATE                          |
      +======================================================================+
      |  Lightweight view functions for UI/frontend consumption. Off-chain   |
      |  eth_call reads are free; on-chain callers still pay gas.            |
      +======================================================================+*/

    /// @notice Get the next-pool ratchet target for level progression.
    /// @dev Returns the pre-skim nextPrizePool captured at the previous level
    ///      transition, raised at century levels (x00) to the curved multiple of
    ///      the previous century's achieved pool (2x, tapering to 1.5x above 500k
    ///      ETH and 1.3x above 1M ETH). The current level must accumulate
    ///      strictly more than this in nextPrizePool to trigger lastPurchaseDay.
    /// @return The ratchet target value (ETH wei).
    function prizePoolTargetView() external view returns (uint256) {
        uint256 pool = _prizePoolTarget(level + 1);
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
    /// @dev Sums every key space an entry for `lvl` can occupy: the committed read cohort, the
    ///      accumulating write cohort, and the far-future space that buys land in while
    ///      `lvl > _mintCeiling()`. Reading one space alone under-reports — the write key drops the
    ///      committed cohort at every daily slot swap, and misses far-future buys entirely. The
    ///      three keys are pairwise distinct (slot bit 23, far-future bit 22), so nothing is
    ///      counted twice. No overflow guard on the sum: each lane is a uint32 entry count,
    ///      and a combined total past 2^32 entries needs ~1.07 billion whole tickets at one
    ///      level (4 entries each), the same economically unreachable scale the uint32
    ///      caps were stripped at.
    /// @param lvl Target level for the queued entries.
    /// @param player Player address to query.
    /// @return The number of entries owed (fractional remainder resolves at batch time).
    function entriesOwedView(
        uint24 lvl,
        address player
    ) external view returns (uint32) {
        unchecked {
            return
                _entriesOwedTotal(lvl, _walletIdOf(player));
        }
    }

    /// @notice Pinned table mirrors the authoritative zero/nonzero pending transition.
    /// @dev Separate parity flags prevent write battles from gating their own request.
    function setCrapsRngPending_g1406(uint48 index, bool pending) external {
        if (msg.sender != ContractAddresses.CRAPS || index > 1) revert E();
        assembly ("memory-safe") {
            let mask := shl(add(LR_CRAPS_PENDING_SHIFT, and(index, 1)), 1)
            sstore(lootboxRngPacked.slot, or(and(sload(lootboxRngPacked.slot), not(mask)), mul(mask, pending)))
        }
        if (pending) {
            // Write-side battles do not invalidate completion of the preceding read cycle.
            if (index == _rngReadBuffer()) _setRngComplete(false);
        } else {
            _tryCompleteRng();
        }
    }

    /// @notice Current allowed read-consumer category for the ordered miner chain.
    function rngConsumerStage_g379() external view returns (uint8) {
        return _rngConsumerStage();
    }

    /// @notice View a queued Degenerette bet word (zero once resolved or unknown).
    /// @param index Lootbox RNG index the bet was placed at.
    /// @param betId Bet id within `index` (queue position + 1).
    /// @return packed The logical bet word, matching its placement event.
    function degeneretteBetInfo(
        uint48 index,
        uint64 betId
    ) external view returns (uint256 packed) {
        if (!_lootboxBufferValid(index) || betId == 0
            || betId > (index == _rngWriteBuffer() ? uint32(lootboxRngPacked >> LR_BET_COUNT_SHIFT) : degeneretteReadCount)
        ) return 0;
        if (index == _rngReadBuffer()) {
            uint256 active = _activeDegeneretteCursor();
            uint256 cursor = active == 0 ? degeneretteCursor : active - 1;
            if (betId <= cursor) return 0;
        }
        return _loadDegeneretteBet(index, betId - 1);
    }

    /// @notice Spendable Degenesis credit accrued by a player.
    /// @param player Player to query.
    /// @return credit Remaining credit (consumed 1:1 by Degenesis purchases).
    function degenesisCreditOf(address player) external view returns (uint256 credit) {
        return degenesisCredit[_walletIdOf(player)];
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

    /// @notice Whether the game-over trigger is currently active.
    /// @dev An existing ending stays latched. In every phase, 14 elapsed days without
    ///      full daily completion or an expired VRF commitment selects the hard ending.
    ///      Otherwise an unmet purchase target ends after 30 completed purchase rounds,
    ///      no earlier than the next reset after their final completion. Degenesis rounds
    ///      do not count. Callbacks, retries and partial workers cannot refresh the deadline.
    function livenessTriggered() external view returns (bool) {
        return _livenessTriggered();
    }

    /// @notice Get the yield surplus (stETH appreciation above all pool obligations).
    /// @dev Calculated as: (ETH balance + stETH balance) - (current + next + future +
    ///      claimable pools + yieldAccumulator + pending next/future freeze buffers).
    /// @return The yield surplus value (ETH wei).
    function yieldPoolView() external view returns (uint256) {
        uint256 totalBalance = address(this).balance +
            steth.balanceOf(address(this));
        uint256 obligations = _getCurrentPrizePool() +
            _getNextPrizePool() +
            claimablePool +
            _getFuturePrizePool() +
            yieldAccumulator;
        // Freeze-window revenue lands in balance but routes to prizePoolPendingPacked
        // (outside the live pools above) until _unfreezePool folds it back. Count it as
        // a live liability so the view matches distributeYieldSurplus and never reports
        // that pending buffer as distributable surplus. Reads 0 when not frozen.
        (uint128 pNext, uint128 pFuture) = _getPendingPools();
        obligations += uint256(pNext) + uint256(pFuture);
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
        return _retainedDailyWord(day);
    }

    /// @notice Check if RNG is currently locked (daily jackpot resolution).
    /// @dev When locked, burns and certain operations are blocked.
    /// @return True if RNG lock is active.
    function rngLocked() external view returns (bool) {
        return rngLockedFlag;
    }

    /// @notice True once the previous RNG cycle has finished and a fresh request may be considered.
    /// @dev Other request rules (funding, price and daily staging) still apply.
    function rngComplete() external view returns (bool) {
        return _lootboxReadComplete();
    }

    /// @notice Check if VRF has been fulfilled for current request.
    /// @return True if random word is available for use.
    function isRngFulfilled() external view returns (bool) {
        return _rngRequestActive() && rngWordCurrent != RNG_WORD_WAITING;
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
        return _decWindowOpen() && !gameOver;
    }

    /// @notice Selected jackpot duration: one day for turbo, otherwise three days.
    function jackpotDuration() external view returns (uint8) {
        return _jackpotDays();
    }

    /// @notice Returns true when jackpot phase is active.
    function jackpotPhase() external view returns (bool) {
        return jackpotPhaseFlag;
    }

    /// @notice Everything the growth-bet parimutuel reads out of this contract.
    /// @dev One call rather than five: PARIMUTUEL is a standalone contract, so each term
    ///      it needs would otherwise be its own staticcall.
    ///
    ///      The three terms are RATCHET ENTRIES, not the live next/current/future prize
    ///      pools. An ordinary entry is zero before its transition or after its
    ///      four-slot history retires; settled outcomes remain in Parimutuel. A round's benchmark is the ratio ratchetRound / ratchetPrev and its
    ///      subject is ratchetNext / ratchetRound; the market cross-multiplies the two, so
    ///      every term stays unsigned and a level that achieves less than its predecessor
    ///      is simply a ratio below 1.
    ///
    ///      Century levels are read through _growthRatchet rather than levelPrizePool,
    ///      because _endPhase overwrites _levelPrizePool(x00) with 40% of futurePool once the
    ///      century's jackpot phase ends. Serving the pushed achieved pool instead keeps
    ///      each term write-once: a boundary round scores the growth the game actually
    ///      delivered, and its answer can never change after it first settles.
    ///
    ///      ratchetNext == 0 is therefore the settled/unsettled predicate, and it is a
    ///      sounder one than the level number: `level` is promoted one RNG request BEFORE
    ///      the transition writes the entry, so a round whose successor level already
    ///      exists can still be unsettled.
    ///
    ///      bettingOpen deliberately ignores the RNG lock: the market consumes no
    ///      randomness and its terms are write-once, so a bet is placeable the whole
    ///      jackpot phase — including while a day's word is in flight. The stake burn is
    ///      ungated too: its FLIP top-up reaches only settled claimable winnings, which the
    ///      pending word cannot reprice.
    /// @param round The round to report ratchet terms for; 0 skips those reads (the
    ///        placement path only needs the phase half, and has no round to name yet).
    /// @return ratchetPrev The ratchet entry for round - 1.
    /// @return ratchetRound The ratchet entry for round.
    /// @return ratchetNext The ratchet entry for round + 1 (0 until the successor banks).
    /// @return currentLevel The current game level — the round a bet placed now joins.
    /// @return bettingOpen True while the jackpot phase is live, its draws have not ended,
    ///         and the phase is not armed to collapse. Three legs, each closing a window
    ///         that is not a real one:
    ///
    ///         phaseTransitionActive — _endPhase seals the level but leaves
    ///         jackpotPhaseFlag up until the transition advance closes the phase, a span
    ///         that answers to advance timing rather than to anything about the
    ///         market. _endPhase also zeroes the day counter, so that
    ///         span would quote the FIRST day's quest reward to the last mover, inverting
    ///         the decay exactly where it should bite hardest. This is the standalone
    ///         "this level's draws have ended" signal, read the same way by
    ///         _activeTicketLevel.
    ///
    ///         A turbo phase pays its entire jackpot in one advance cycle, so it has
    ///         no betting window. Standard three-day phases keep a real open market.
    ///
    ///         Game over has no leg of its own: GameOver latches `gameOver = true` without
    ///         touching `jackpotPhaseFlag` or `phaseTransitionActive`, so a deadman-triggered
    ///         game over inside a jackpot phase leaves the phase flags exactly as they stood —
    ///         `bettingOpen` can still read true, and the market can keep taking bets on a
    ///         round that will never settle.
    /// @return phaseDay Physical jackpot draws completed: 0 before the first draw,
    ///         then 1 or 2 while a standard phase remains open. The third draw closes
    ///         betting; turbo's only draw closes its phase without opening a market.
    function growthState(
        uint24 round
    )
        external
        view
        returns (
            uint256 ratchetPrev,
            uint256 ratchetRound,
            uint256 ratchetNext,
            uint24 currentLevel,
            bool bettingOpen,
            uint8 phaseDay
        )
    {
        if (round != 0) {
            ratchetPrev = _growthRatchet(round - 1);
            ratchetRound = _growthRatchet(round);
            ratchetNext = _growthRatchet(round + 1);
        }
        currentLevel = level;
        bettingOpen =
            jackpotPhaseFlag &&
            !phaseTransitionActive &&
            (jackpotFlags & JACKPOT_TURBO) == 0;
        phaseDay = jackpotCounter;
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
    /// @return rngLocked_ True during daily RNG processing, from request through the day seal.
    /// @return priceWei Current buy-now mint price in wei (at the routed ticket level).
    function purchaseInfo_g1027()
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
      |  Field positions: the layout header and shift constants in          |
      |  libraries/BitPackingLib.sol, the single source of truth.            |
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
        uint256 packed = mintPacked_[_walletIdOf(player)];
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
        return uint8((mintPacked_[_walletIdOf(player)] >> BitPackingLib.CURSE_COUNT_SHIFT) & BitPackingLib.MASK_5);
    }

    /*+======================================================================+
      |                  VIEW: ACTIVITY SCORE CALCULATION                    |
      +======================================================================+
      |  Player activity score multiplier determines airdrop rewards.        |
      |                                                                      |
      |  Activity Score Components — all in WHOLE POINTS, not percentages.   |
      |  Reward curves over the score are nonlinear (see ActivityCurveLib).  |
      |  • Mint streak: +1 pt per consecutive level minted (cap 50)          |
      |  • Mint count: +25 pts for 100% participation, scaled proportionally |
      |  • Quest streak: +1 pt per 2 quests completed (uncapped)             |
      |  • Affiliate points: +1 pt per affiliate point (cap 50)              |
      |  • Pass bonus (active only while frozen):                            |
      |    - lazy pass (10-level): +10 pts                                   |
      |    - whale pass (100-level): +40 pts                                 |
      |  • Deity pass bonus: +80 pts (always active)                         |
      |  • Cashout/smite curse: -1 pt per curse point, floored at 0          |
      |                                                                      |
      +======================================================================+*/

    /// @notice Calculate player's activity score in whole points.
    /// @dev Activity Score: 50 (streak) + 25 (count) + questStreak/2 (uncapped) + 50 (affiliate) + 40 (whale)
    ///      Deity pass adds +80 in place of the whale bonus; cashout/smite curse points subtract 1 each,
    ///      floored at 0. Global hard cap: 65,534 points.
    ///      Consumers map the score through their own ActivityCurveLib curve. 400 (lootbox EV),
    ///      305 (degenerette ROI) and 235 (decimator) are that curve's first knee, not a cap — each
    ///      curve keeps rising past its knee and saturates at ACTIVITY_EFFECTIVE_CAP_POINTS (30,000).
    /// @param player The player address to calculate for.
    /// @return scorePoints Total activity score in whole points.
    /// @return walletId The player's wallet ID (zero if unregistered), read beside the score so a
    ///         address-based consumers can identify the account without a second lookup.
    function playerActivityScore(
        address player
    ) external view returns (uint256 scorePoints, uint32 walletId) {
        // Unified effective quest streak: a live afking sub reads the Sub-side compute-on-read
        // (the run's funded days + in-run secondaries); everyone else reads the decay-aware manual
        // streak, which zeroes a lapsed stale-high streak so it can't inflate
        // lootbox EV or sDGNRS claims.
        walletId = _walletIdOf(player);
        scorePoints = _playerActivityScore(walletId, _effectiveQuestStreak(walletId));
    }

    /// @notice Activity score for transactions; refreshes the current-level affiliate cache.
    /// @dev The read-only playerActivityScore remains available for STATICCALL consumers. The
    ///      wallet ID comes from the canonical registry; it is 0 for an unregistered wallet
    ///      (never allocated here).
    function playerActivityScoreCached(address player) external returns (uint256 score, uint32 id) {
        id = _walletIdOf(player);
        return (_activityScoreCached(id), id);
    }

    function playerActivityScoreById(uint32 id) external view returns (uint256) {
        return _playerActivityScore(id, _effectiveQuestStreak(id));
    }

    function playerActivityScoreCachedById_g975(uint32 id) external returns (uint256) {
        return _activityScoreCached(id);
    }

    function _activityScoreCached(uint32 id) private returns (uint256) {
        uint256 packed = mintPacked_[id];
        if (uint24(packed >> BitPackingLib.AFFILIATE_BONUS_LEVEL_SHIFT) == level
            || (packed & ((BitPackingLib.MASK_24 << BitPackingLib.LAST_LEVEL_SHIFT)
                | (BitPackingLib.MASK_24 << BitPackingLib.LEVEL_COUNT_SHIFT)
                | (BitPackingLib.MASK_24 << BitPackingLib.DAY_SHIFT))) == 0) {
            return _playerActivityScore(id, _effectiveQuestStreak(id));
        }
        return _playerActivityScoreCached(id, _effectiveQuestStreak(id));
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
        uint256 stored = _claimableOf(_walletIdOf(msg.sender));
        if (stored <= 1) return 0;
        unchecked {
            return stored - 1;
        }
    }

    /// @notice Get a player's raw claimable balance (includes the 1 wei sentinel).
    /// @param player Player address to query.
    /// @return Raw claimable balance in wei (includes the account's 1-wei sentinel).
    function claimableWinningsOf(
        address player
    ) external view returns (uint256) {
        if (_goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0) return 0;
        return _claimableOf(_walletIdOf(player));
    }

    /// @notice Game-held value reserved for sDGNRS redemption settlement.
    function redemptionReserve() external view returns (uint256) {
        return _redemptionReserve();
    }

    /// @notice Get a player's deferred whale-pass claims.
    /// @param player Player address to query.
    /// @return Number of half whale passes owed (100 entries each).
    function whalePassClaimAmount(
        address player
    ) external view returns (uint256) {
        return _halfPassCount(_walletIdOf(player));
    }

    /// @notice Whether a player holds a deity pass.
    function hasDeityPass(address player) external view returns (bool) {
        return mintPacked_[_walletIdOf(player)] >> BitPackingLib.HAS_DEITY_PASS_SHIFT & 1 != 0;
    }

    /// @notice A wallet's permanent ID (its wallet-table position), or zero if unregistered.
    function walletIdOf_g3120(address player) external view returns (uint32) {
        return _walletIdOf(player);
    }

    /// @notice Returns the packed mint data for a player.
    /// @dev External view accessor for DegenerusQuests (IDegenerusGame.mintPackedFor).
    /// @param player Player address to query.
    /// @return Raw packed uint256 from mintPacked_.
    function mintPackedFor(address player) external view returns (uint256) {
        return mintPacked_[_walletIdOf(player)];
    }

    /// @dev Mint word of an allocated wallet ID, resolved through the wallet table here so a
    ///      caller holding only the ID needs one call (DegenerusQuests level-quest eligibility).
    /// @param id Allocated wallet ID.
    /// @return Raw packed uint256 from mintPacked_ for the ID's account key.
    function mintPackedOfId_g5372(uint32 id) external view returns (uint256) {
        return mintPacked_[id];
    }

    /*+======================================================================+
      |                    TRAIT TICKET SAMPLING                             |
      +======================================================================+
      |  View function for sampling burn ticket holders from recent levels.  |
      |  Used for scatter draws and promotional mechanics.                   |
      +======================================================================+*/

    /// @notice Sample up to 4 entries from a prepared BAF trait buffer.
    /// @dev BAF scatter reads a random packed word and rotates its lanes. Tail padding
    ///      is redrawn over valid entries so the last word keeps equal entry weighting.
    ///      The bucket's data root is hashed once for all four draws. Entries are the wallet
    ///      IDs the bucket lanes store.
    ///      BAF runs on even levels and prepares both buffers when armed. The flag selects
    ///      the physical buffer directly; this reader does not resolve or validate a level.
    /// @param nextLevel False selects the even/current BAF buffer; true selects the odd/next buffer.
    /// @param traitSel Trait bucket to sample; BAF passes a non-solo trait from the main board.
    /// @param entropy Random seed (typically derived from VRF) for entry selection.
    /// @return entries Up to 4 entry holders' wallet IDs (IDs may repeat).
    function sampleTraitEntries(
        bool nextLevel,
        uint8 traitSel,
        uint256 entropy
    ) external view returns (uint32[] memory entries) {
        uint256 len;
        uint256 take;
        uint256 header;
        uint256 wordsBase;
        {
            uint24 buffer = nextLevel ? 1 : 0;
            uint256 headerSlot = _traitBufferBase(buffer) + traitSel;
            assembly ("memory-safe") {
                if iszero(and(sload(traitBucketStale.slot),
                    shl(add(mul(traitBucketStale.offset, 8), buffer), 1))) {
                    if and(sload(add(traitBucketLive.slot, buffer)), shl(traitSel, 1)) {
                        header := sload(headerSlot)
                    }
                }
            }
            len = uint32(header);
            take = len > 4 ? 4 : len;
            entries = new uint32[](take);
            if (len == 0) return entries;
            // Every draw uses the same bucket. Hash its data root once, including for a
            // padding redraw that selects a different packed word.
            assembly ("memory-safe") {
                mstore(0, headerSlot)
                wordsBase := keccak256(0, 32)
            }
        }

        PackedTicketSampleLib.Cursor memory cursor;
        uint256 selectedWord;
        {
            uint256 base = PackedTicketSampleLib.begin(cursor, len, entropy >> 40);
            assembly ("memory-safe") {
                switch eq(shr(3, base), shr(3, len))
                case 1 { selectedWord := shr(32, header) }
                default { selectedWord := sload(add(wordsBase, shr(3, base))) }
            }
        }
        for (uint256 i; i < take; ) {
            (uint256 index, bool redrawn) = PackedTicketSampleLib.next(cursor, len);
            uint256 word = selectedWord;
            assembly ("memory-safe") {
                if redrawn {
                    switch eq(shr(3, index), shr(3, len))
                    case 1 { word := shr(32, header) }
                    default { word := sload(add(wordsBase, shr(3, index))) }
                }
                mstore(add(add(entries, 32), shl(5, i)), and(shr(shl(5, and(index, 7)), word), 0xffffffff))
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Sample two BAF rounds' worth of unminted future-level candidates.
    /// @dev Four packs, each an independent level (uniform in [fromLevel, toLevel], empty
    ///      levels skipped) and a random eight-lane window of its queue (one lane per wallet
    ///      registration): a uniform lane plus a distinct lane among the next seven, wrapping.
    ///      Every registered wallet at the level is equally likely in either slot. Pack p's
    ///      first lane goes to slot p (the first round's four candidates, slots 0..3) and its
    ///      second to slot p + 4 (the second round's, slots 4..7), so both rounds draw their
    ///      four candidates from four different packs. At most 12 attempts
    ///      bound the gas; an unfilled slot stays 0, which scores zero. BAF runs
    ///      after level+1 has minted, so every candidate level is still unminted.
    /// @param entropy Random entropy for the level, word and lane draws.
    /// @param fromLevel Lowest candidate level (inclusive; the BAF passes unminted levels only).
    /// @param toLevel Highest candidate level (inclusive, >= fromLevel).
    /// @return tickets Eight candidate slots as the wallet IDs the queue lanes store (0 where
    ///         unfilled).
    function sampleFarFutureTickets(
        uint256 entropy,
        uint24 fromLevel,
        uint24 toLevel
    ) external view returns (uint32[] memory tickets) {
        uint256 span = uint256(toLevel - fromLevel) + 1;
        tickets = new uint32[](8);
        uint256 packs;
        for (uint256 attempt; packs < 4 && attempt < 12; ) {
            entropy = EntropyLib.hash3(RngTags.BAF_FUTURE_ATTEMPT, entropy, attempt);
            uint24 target;
            // span is derived from checked uint24 bounds, so this remains within toLevel.
            assembly ("memory-safe") { target := add(fromLevel, mod(entropy, span)) }
            uint256[] storage queue = ticketQueue[_ticketQueueStorageKey(_tqFarFutureKey(target))];
            uint256 len = _ticketQueueLength(_tqFarFutureKey(target));
            if (len != 0) {
                // Lane a is uniform over the whole queue; lane b is one of the next
                // min(8, len) - 1 lanes after it, wrapping at the end. Every lane is a with
                // probability 1/len and b with probability 1/len, so a queue position (the
                // append order) carries no edge — a word-first pick would over-weight a
                // partial tail word.
                uint256 a = (entropy >> 64) % len;
                uint32 first = _tqPositionAt(queue, a);
                // packs < 4 and the result array has eight slots.
                assembly ("memory-safe") { mstore(add(add(tickets, 32), shl(5, packs)), first) }
                uint256 window = len < 8 ? len : 8;
                if (window > 1) {
                    uint256 b;
                    // Registry-backed lengths fit uint32 and window is at most eight.
                    assembly ("memory-safe") { b := mod(add(add(a, 1), mod(shr(128, entropy), sub(window, 1))), len) }
                    uint32 second = _tqPositionAt(queue, b);
                    assembly ("memory-safe") { mstore(add(add(tickets, 160), shl(5, packs)), second) }
                }
                unchecked { ++packs; }
            }
            unchecked { ++attempt; }
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
        if (_ticketLevelRetired(lvl)) return (0, 0, 0);
        total = uint32(_bucketLength(lvl, trait));
        if (offset >= total) return (0, total, total);

        uint256 end = offset + limit;
        if (end > total) end = total;

        uint32 id = _walletIdOf(player);
        for (uint256 i = offset; i < end; ) {
            if (_bucketIdAtUnchecked(lvl, trait, i) == id) count++;
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
        // Both near cohorts, so the count survives the daily slot swap: entries queued before
        // it sit under what is now the read key. The far-future space is included for the case
        // where a level's far-future buys have not yet been drained across the transition.
        uint24 lvl = level;
        unchecked {
            tickets =
                _entriesOwedTotal(lvl, _walletIdOf(player));
        }
    }

    /*+======================================================================+
      |                    DEGENERETTE TRACKING VIEWS                        |
      +======================================================================+*/

    /// @notice Get hero weights for the sealed request day - 1, or the accumulating pool for today.
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
        uint256 packed = _dailyHeroWagerWord(day, quadrant);
        wagerUnits = (packed >> (uint256(symbol) * 32)) & 0xFFFFFFFF;
    }

    /// @notice Get the leading hero in the sealed or accumulating pool; other days return zeros.
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
        for (uint8 q = 0; q < DEGENERETTE_HERO_COUNT / 8; ++q) {
            uint256 packed = _dailyHeroWagerWord(day, q);
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
        _creditAfkingValue(_requireWalletId(msg.sender), msg.value);
    }
    function _revertGameDelegate(bytes memory reason) private pure {
        if (reason.length == 0) revert EmptyRevert();
        assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
    }
}
