// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title BurnieCoin
 * @author Burnie Degenerus
 * @notice ERC20 in-game token (BURNIE, 18 decimals) with integrated coinflip wagering and quest rewards.
 *
 * @dev ARCHITECTURE:
 *      - ERC20 standard with game contract transfer bypass
 *      - Coinflip: Daily stake windows with VRF-based 50/50 outcomes, 50-150% bonus on wins
 *      - Quest integration: Bonus flip credits for gameplay actions (mint/burn)
 *      - Decimator burns: Burn-to-participate for decimator jackpot eligibility
 *      - Bounty: 1000 BURNIE/window accumulator; half removed each window (paid on win)
 *      - Vault escrow: 2M BURNIE virtual reserve, minted only on ContractAddresses.VAULT withdrawal
 *
 * @dev CRITICAL INVARIANTS:
 *      - totalSupply + _vaultMintAllowance = supplyIncUncirculated
 *      - coinflipBalance[day][player] immutable after settlement (day <= flipsClaimableDay)
 *      - Only one bountyOwedTo address at a time
 *
 * @dev SECURITY:
 *      - Access control: onlyDegenerusGameContract, onlyFlipCreditors, onlyVault
 *      - CEI pattern: burns before external calls
 *      - RNG lock prevents stake manipulation during VRF callback
 *      - MIN threshold (10,000 BURNIE) prevents dust spam
 *      - 90-day auto-expiry on unclaimed coinflips (30-day window for first claim)
 */

import {IDegenerusGame} from "./interfaces/IDegenerusGame.sol";
import {IDegenerusJackpots} from "./interfaces/IDegenerusJackpots.sol";
import {IDegenerusQuests} from "./interfaces/IDegenerusQuests.sol";
import {IDegenerusStonk} from "./interfaces/IDegenerusStonk.sol";
import {ContractAddresses} from "./ContractAddresses.sol";

interface IWrappedWrappedXRP {
    function mintPrize(address to, uint256 amount) external;
}

interface IBurnieCoinflip {
    function previewClaimCoinflips(address player) external view returns (uint256 mintable);
    function afKingDailyOnlyMode(address player) external view returns (bool dailyOnly);
    function coinflipAmount(address player) external view returns (uint256);
    function coinflipAutoRebuyInfo(address player) external view returns (bool enabled, uint256 stop, uint256 carry, uint48 startDay);
    function creditFlip(address player, uint256 amount) external;
}

contract BurnieCoin {
    /*+======================================================================+
      |                              EVENTS                                  |
      +======================================================================+
      |  Lightweight ERC20 events plus gameplay signals for off-chain        |
      |  indexers/clients. Events are the primary mechanism for UIs to       |
      |  track coinflip results, quest completions, and bounty state.        |
      +======================================================================+*/

    /// @notice Standard ERC20 transfer event.
    /// @dev Emitted on transfer, mint (from=0), and burn (to=0).
    event Transfer(address indexed from, address indexed to, uint256 amount);

    /// @notice Standard ERC20 approval event.
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 amount
    );

    /// @notice Emitted when a player deposits BURNIE into the coinflip pool.
    /// @param player The depositor's address.
    /// @param creditedFlip The raw amount deposited (excludes quest bonuses credited separately).

    /// @notice Emitted when an afKing flip result is recorded from an RNG word.
    /// @param epoch Monotonic RNG event index for the active afKing stream.
    /// @param rewardPercent Bonus percent on wins (e.g., 150 = 150% bonus).
    /// @param win True if the flip outcome is a win.

    /// @notice Emitted when a player toggles afKing daily-only flip mode.
    /// @param player The player whose mode was updated.
    /// @param dailyOnly True to use daily-only RNG, false for every RNG word.

    /// @notice Emitted when a player toggles coinflip auto-rebuy.

    /// @notice Emitted when a player sets the coinflip auto-rebuy keep multiple.

    /// @notice Emitted when a player burns BURNIE during a decimator window.
    /// @param player The burner's address.
    /// @param amountBurned The amount burned (18 decimals).
    /// @param bucket The effective bucket weight assigned (lower = more valuable).
    event DecimatorBurn(
        address indexed player,
        uint256 amountBurned,
        uint8 bucket
    );

    /// @notice Emitted when a player stakes BURNIE on a turbo flip.
    /// @param player The staker address.
    /// @param lootboxIndex Lootbox RNG index the flip is tied to.
    /// @param amount Amount staked (18 decimals).
    event TurboFlipStaked(
        address indexed player,
        uint48 indexed lootboxIndex,
        uint256 amount
    );

    /// @notice Emitted when a player stakes multiple turbo flips for one RNG word.
    /// @param player The staker address.
    /// @param lootboxIndex Lootbox RNG index the flips are tied to.
    /// @param amountPerFlip Amount per flip (18 decimals).
    /// @param flipCount Number of flips in the batch.
    /// @param totalAmount Total amount staked (amountPerFlip * flipCount).
    event TurboFlipStakedBatch(
        address indexed player,
        uint48 indexed lootboxIndex,
        uint256 amountPerFlip,
        uint8 flipCount,
        uint256 totalAmount
    );

    /// @notice Emitted when a turbo flip is resolved.
    /// @param player The player resolved.
    /// @param lootboxIndex Lootbox RNG index used.
    /// @param win True if the flip won.
    /// @param payout Amount credited as claimable (18 decimals).
    /// @param payoutBps Payout multiplier in basis points (1x = 10000).
    event TurboFlipResolved(
        address indexed player,
        uint48 indexed lootboxIndex,
        bool win,
        uint256 payout,
        uint32 payoutBps
    );

    /// @notice Emitted when a player stakes BURNIE on a turbo decimator lane.
    /// @param player The staker address.
    /// @param lootboxIndex Lootbox RNG index the bet is tied to.
    /// @param lane Selected lane (0-9).
    /// @param amount Amount staked (18 decimals).
    event TurboDecimatorStaked(
        address indexed player,
        uint48 indexed lootboxIndex,
        uint8 lane,
        uint256 amount
    );

    /// @notice Emitted when a turbo decimator bet is resolved.
    /// @param player The player resolved.
    /// @param lootboxIndex Lootbox RNG index used.
    /// @param winningLane The winning lane (0-9).
    /// @param win True if the player picked the winning lane.
    /// @param payout Amount credited as claimable (18 decimals).
    /// @param payoutBps Payout multiplier in basis points (1x = 10000).
    event TurboDecimatorResolved(
        address indexed player,
        uint48 indexed lootboxIndex,
        uint8 winningLane,
        bool win,
        uint256 payout,
        uint32 payoutBps
    );

    /// @notice Emitted when a player stakes DGNRS on a turbo decimator lane.
    /// @param player The staker address.
    /// @param lootboxIndex Lootbox RNG index the bet is tied to.
    /// @param lane Selected lane (0-9).
    /// @param amount Amount staked (18 decimals).
    event TurboDecimatorDgnrsStaked(
        address indexed player,
        uint48 indexed lootboxIndex,
        uint8 lane,
        uint256 amount
    );

    /// @notice Emitted when a turbo decimator DGNRS bet is resolved.
    /// @param player The player resolved.
    /// @param lootboxIndex Lootbox RNG index used.
    /// @param winningLane The winning lane (0-9).
    /// @param win True if the player picked the winning lane.
    /// @param payout Amount credited as claimable (18 decimals).
    /// @param payoutBps Payout multiplier in basis points (1x = 10000).
    event TurboDecimatorDgnrsResolved(
        address indexed player,
        uint48 indexed lootboxIndex,
        uint8 winningLane,
        bool win,
        uint256 payout,
        uint32 payoutBps
    );

    /// @notice Emitted when turbo winnings are claimed and minted.
    /// @param player The recipient address.
    /// @param amount Amount minted (18 decimals).
    event TurboClaimed(address indexed player, uint256 amount);

    /// @notice Emitted when turbo DGNRS winnings are claimed.
    /// @param player The recipient address.
    /// @param amount Amount transferred (18 decimals).
    event TurboDgnrsClaimed(address indexed player, uint256 amount);

    /// @notice Emitted when the daily quest is rolled for a new day.
    /// @param day The day index (1-indexed, day 1 = deploy day).
    /// @param questType The type of quest rolled (see IDegenerusQuests).
    /// @param highDifficulty Whether hard mode is active for this quest.
    event DailyQuestRolled(
        uint48 indexed day,
        uint8 questType,
        bool highDifficulty
    );

    /// @notice Emitted when a player completes a quest.
    /// @param player The player who completed the quest.
    /// @param questType The type of quest completed.
    /// @param streak The player's current completion streak.
    /// @param reward The reward amount credited (as flip stake).
    /// @param hardMode Whether the quest was completed in hard mode.
    event QuestCompleted(
        address indexed player,
        uint8 questType,
        uint32 streak,
        uint256 reward,
        bool hardMode,
        bool completedBoth
    );

    /// @notice Emitted when ContractAddresses.ADMIN credits LINK-funded bonus directly.
    /// @param player The recipient of the credit.
    /// @param amount The amount minted (18 decimals).
    event LinkCredit(address indexed player, uint256 amount);

    /// @notice Emitted when virtual coin is escrowed to the vault reserve.
    /// @param sender The contract that escrowed the funds (VAULT or GAME).
    /// @param amount The amount added to vault mint allowance (18 decimals).
    event VaultEscrowRecorded(address indexed sender, uint256 amount);
    /// @notice Emitted when the vault spends from its mint allowance without minting tokens.
    /// @param spender The vault address.
    /// @param amount The amount consumed from allowance (18 decimals).
    event VaultAllowanceSpent(address indexed spender, uint256 amount);

    /*+======================================================================+
      |                              ERRORS                                  |
      +======================================================================+
      |  Custom errors for gas-efficient reverts. Each error corresponds     |
      |  to a specific access control or validation failure.                 |
      +======================================================================+*/

    /// @notice Caller is not the authorized DegenerusGame contract.
    error OnlyGame();

    /// @notice Caller is not the authorized ContractAddresses.VAULT contract.
    error OnlyVault();

    /// @notice Requested amount exceeds available balance or allowance.
    error Insufficient();

    /// @notice Deposit/burn amount is below the minimum threshold (10,000 BURNIE).
    error AmountLTMin();

    /// @notice Turbo lane index is invalid.
    error TurboLaneInvalid();

    /// @notice Turbo lane mismatch for an existing stake.
    error TurboLaneMismatch();

    /// @notice Turbo RNG word is not ready for this lootbox index.
    error TurboRngNotReady();

    /// @notice Turbo RNG word already known for current lootbox index.
    error TurboRngAlreadyKnown();

    /// @notice No turbo stake exists to resolve.
    error TurboNoStake();

    /// @notice Turbo flip count is invalid (must be 1-10).
    error TurboFlipCountInvalid();

    /// @notice Turbo flip amount mismatch for an existing stake.
    error TurboFlipAmountMismatch();

    /// @notice Turbo flip side mismatch for an existing stake.
    error TurboFlipSideMismatch();

    /// @notice Zero address not allowed for transfers, mints, or wiring.
    error ZeroAddress();
    /// @notice Recipient address is not allowed for this operation.
    error InvalidRecipient();

    /// @notice Decimator burn attempted outside an active decimator window.
    error NotDecimatorWindow();

    /// @notice Caller is not the ContractAddresses.ADMIN address.
    error OnlyAdmin();

    /// @notice Caller is not the authorized affiliate contract.
    error OnlyAffiliate();

    /// @notice Caller is not the authorized gamepiece (gamepieces) contract.
    error OnlyGamepieces();

    /// @notice Coinflip deposits are locked during level jackpot resolution.
    error CoinflipLocked();

    /// @notice RNG is locked (VRF pending).
    error RngLocked();

    /// @notice Caller is not authorized (trusted contracts: GAME, GAMEPIECES, AFFILIATE, ICON_COLOR_REGISTRY).
    error OnlyTrustedContracts();

    /// @notice Caller is not authorized (flip creditors: GAME, GAMEPIECES, AFFILIATE).
    error OnlyFlipCreditors();

    /// @notice Caller is not authorized (vault operations: VAULT or GAME).
    error OnlyVaultOrGame();

    /// @notice Auto-rebuy must be disabled before manual cash-out/claims.
    error AutoRebuyActive();

    /// @notice Auto-rebuy is already enabled.

    /// @notice Auto-rebuy is not enabled.
    /// @notice Auto-rebuy keep multiple is zero (no reservable multiples).
    /// @notice Caller is not approved to act for the player.
    error NotApproved();

    /*+======================================================================+
      |                         ERC20 STATE                                  |
      +======================================================================+
      |  Minimal ERC20 metadata/state. Transfers are protected by Solidity   |
      |  0.8+ overflow checks. No SafeMath needed.                           |
      |                                                                      |
      |  STORAGE LAYOUT:                                                     |
      |  +-----------------------------------------------------------------+ |
      |  | Slot | Variable                    | Type                       | |
      |  +------+-----------------------------+----------------------------+ |
      |  |  0   | totalSupply                 | uint256                    | |
      |  |  1   | balanceOf                   | mapping(address => uint256)| |
      |  |  2   | allowance                   | mapping(addr => mapping)   | |
      |  +-----------------------------------------------------------------+ |
      +======================================================================+*/

    /// @notice Token name displayed in wallets and explorers.
    string public constant name = "Burnies";

    /// @notice Token symbol (ticker).
    string public constant symbol = "BURNIE";

    /// @notice Total circulating supply (excludes ContractAddresses.VAULT's virtual allowance).
    /// @dev Increases on mint, decreases on burn. Always equals sum of all balanceOf entries.
    uint256 public totalSupply;

    /// @notice Token balance for each address.
    /// @dev Standard ERC20 balance mapping.
    mapping(address => uint256) public balanceOf;

    /// @notice Spending allowances: owner => spender => amount.
    /// @dev type(uint256).max indicates infinite approval.
    mapping(address => mapping(address => uint256)) public allowance;

    /*+======================================================================+
      |                         DATA TYPES                                   |
      +======================================================================+
      |  Packed structs for gas-efficient storage. Each struct fits within   |
      |  a single 32-byte slot where possible.                               |
      +======================================================================+*/

    /// @notice Leaderboard entry for tracking top day flip bettors.
    /// @dev Packed into single slot: address (20 bytes) + uint96 (12 bytes) = 32 bytes.
    ///      Score is stored in whole BURNIE tokens (divided by 1 ether) to fit uint96.

    /// @notice Outcome record for a single coinflip day window.
    /// @dev Packed into single slot: uint16 (2 bytes) + bool (1 byte) = 3 bytes.
    ///      rewardPercent is the bonus percentage (not total), e.g., 150 = 150% bonus = 2.5x total payout.

    /*+======================================================================+
      |                    WIRED CONTRACTS & MODULE STATE                    |
      +======================================================================+
      |  All external dependencies are compile-time constants sourced from  |
      |  ContractAddresses. No storage slots are consumed for wiring, and    |
      |  the references cannot be updated post-deploy.                       |
      |                                                                      |
      |  CONSTANT REFERENCES:                                                |
      |  • GAME, QUESTS, JACKPOTS, AFFILIATE                                  |
|  • VAULT, ADMIN, ICON_COLOR_REGISTRY                                  |
      +======================================================================+*/

    /// @notice The main game contract; provides level, RNG state, and purchase info.
    IDegenerusGame internal constant degenerusGame =
        IDegenerusGame(ContractAddresses.GAME);

    /// @notice The quest module handling daily quests and streak tracking.
    IDegenerusQuests internal constant questModule =
        IDegenerusQuests(ContractAddresses.QUESTS);

    /// @notice The jackpots module for decimator burns and BAF flip tracking.
    IDegenerusJackpots internal constant jackpots =
        IDegenerusJackpots(ContractAddresses.JACKPOTS);

    /// @notice WWXRP contract for coinflip loss rewards.
    IWrappedWrappedXRP internal constant wwxrp =
        IWrappedWrappedXRP(ContractAddresses.WWXRP);

    /// @notice DGNRS token contract for turbo decimator payouts.
    IDegenerusStonk internal constant dgnrs =
        IDegenerusStonk(ContractAddresses.DGNRS);

    /// @notice BurnieCoinflip contract - handles all coinflip wagering logic.
    /// @dev Set via setCoinflipContract() after deployment.
    address public coinflipContract;

    /*+======================================================================+
      |                      TURBO FLIP & DECIMATOR                          |
      +======================================================================+
      |  Fast-settlement flip and decimator bets resolved via lootbox RNG.  |
      |  Stakes are stored per lootbox RNG index and resolved on demand.    |
      +======================================================================+*/

    /// @notice Pending turbo flip stakes by lootbox RNG index.
    mapping(uint48 => mapping(address => uint256)) internal turboFlipStake;

    /// @notice Pending turbo flip counts by lootbox RNG index.
    mapping(uint48 => mapping(address => uint8)) internal turboFlipCount;

    /// @notice Pending turbo flip side (true = bet on loss) by lootbox RNG index.
    mapping(uint48 => mapping(address => bool)) internal turboFlipBetOnLoss;

    /// @notice Pending turbo decimator stakes by lootbox RNG index.
    mapping(uint48 => mapping(address => uint256)) internal turboDecimatorStake;

    /// @notice Pending turbo decimator lane selection by lootbox RNG index.
    /// @dev Lane is meaningful only when turboDecimatorStake > 0.
    mapping(uint48 => mapping(address => uint8)) internal turboDecimatorLane;

    /// @notice Pending turbo decimator DGNRS stakes by lootbox RNG index.
    mapping(uint48 => mapping(address => uint256)) internal turboDecimatorDgnrsStake;

    /// @notice Pending turbo decimator DGNRS lane selection by lootbox RNG index.
    /// @dev Lane is meaningful only when turboDecimatorDgnrsStake > 0.
    mapping(uint48 => mapping(address => uint8)) internal turboDecimatorDgnrsLane;

    /// @notice Claimable turbo winnings held for manual claims.
    mapping(address => uint256) internal turboClaimableStored;

    /// @notice Claimable turbo DGNRS winnings held for manual claims.
    mapping(address => uint256) internal turboDgnrsClaimableStored;

    /// @notice Total pending turbo flip BURNIE amount (for manual RNG trigger threshold).
    /// @dev Tracks combined pending stakes across all turbo flips.
    ///      Incremented when staking turboflips, decremented when resolving.
    uint256 internal turboFlipPendingBurnie;

    // Deploy day boundary moved to ContractAddresses.DEPLOY_DAY_BOUNDARY (compile-time constant)

    /*+======================================================================+
      |                         VAULT ESCROW                                 |
      +======================================================================+
      |  Virtual mint allowance for the ContractAddresses.VAULT. This represents BURNIE that   |
      |  exists "on paper" but hasn't entered circulation. The ContractAddresses.VAULT can     |
      |  mint from this allowance when distributing to players.              |
      +======================================================================+*/

    /// @notice Virtual supply the ContractAddresses.VAULT is authorized to mint (not yet circulating).
    /// @dev Seeded to 2,000,000 BURNIE. Increases via vaultEscrow(), decreases via vaultMintTo().
    ///      supplyIncUncirculated = totalSupply + _vaultMintAllowance.
    /// @custom:security Only ContractAddresses.VAULT/game can increase; only ContractAddresses.VAULT can mint from it.
    uint256 private _vaultMintAllowance = 2_000_000 ether;

    /*+======================================================================+
      |                         VIEW HELPERS                                 |
      +======================================================================+
      |  Read-only functions for UIs and external contracts to query state.  |
      +======================================================================+*/

    /// @notice View-only helper to estimate claimable coin (flips only) for the caller.
    /// @dev Proxies to BurnieCoinflip contract for coinflip-related claims.
    /// @return The total BURNIE claimable from past winning coinflips.
    function claimableCoin() external view returns (uint256) {
        if (coinflipContract == address(0)) return 0;
        return IBurnieCoinflip(coinflipContract).previewClaimCoinflips(msg.sender);
    }

    /// @notice Preview the amount claimCoinflips(amount) would mint for a player.
    /// @dev Proxies to BurnieCoinflip contract.
    /// @param player The player to preview for.
    /// @return mintable Amount of BURNIE that would be minted on claim.
    function previewClaimCoinflips(address player) external view returns (uint256 mintable) {
        if (coinflipContract == address(0)) return 0;
        return IBurnieCoinflip(coinflipContract).previewClaimCoinflips(player);
    }

    /// @notice Check if a player is using daily-only afKing flip mode.
    /// @dev Proxies to BurnieCoinflip contract.
    /// @param player The player address to query.
    /// @return dailyOnly True if daily-only mode is enabled.
    function afKingDailyOnlyMode(address player) external view returns (bool dailyOnly) {
        if (coinflipContract == address(0)) return false;
        return IBurnieCoinflip(coinflipContract).afKingDailyOnlyMode(player);
    }

    /// @notice Preview turbo winnings claimable for a player.
    /// @param player The player to preview for.
    /// @return mintable Amount of BURNIE claimable from turbo resolutions.
    function previewClaimTurbo(address player) external view returns (uint256 mintable) {
        return turboClaimableStored[player];
    }

    /// @notice Preview turbo DGNRS winnings claimable for a player.
    /// @param player The player to preview for.
    /// @return mintable Amount of DGNRS claimable from turbo resolutions.
    function previewClaimTurboDgnrs(address player) external view returns (uint256 mintable) {
        return turboDgnrsClaimableStored[player];
    }

    /// @notice Get pending turbo stakes for a player at a lootbox RNG index.
    /// @param player The player address to query.
    /// @param lootboxIndex Lootbox RNG index.
    /// @return flipStake Pending turbo flip stake.
    /// @return decimatorStake Pending turbo decimator stake.
    /// @return lane Selected lane for turbo decimator (0-9).
    function turboStakeInfo(
        address player,
        uint48 lootboxIndex
    ) external view returns (uint256 flipStake, uint256 decimatorStake, uint8 lane) {
        uint8 flipCount = turboFlipCount[lootboxIndex][player];
        uint256 amountPerFlip = turboFlipStake[lootboxIndex][player];
        if (flipCount == 0 && amountPerFlip != 0) {
            flipCount = 1;
        }
        flipStake = flipCount == 0 ? 0 : amountPerFlip * uint256(flipCount);
        decimatorStake = turboDecimatorStake[lootboxIndex][player];
        lane = turboDecimatorLane[lootboxIndex][player];
    }

    /// @notice Get pending turbo flip details for a player at a lootbox RNG index.
    /// @param player The player address to query.
    /// @param lootboxIndex Lootbox RNG index.
    /// @return amountPerFlip Pending amount per flip.
    /// @return flipCount Pending flip count (0-10).
    /// @return totalStake Pending total stake (amountPerFlip * flipCount).
    function turboFlipInfo(
        address player,
        uint48 lootboxIndex
    ) external view returns (uint256 amountPerFlip, uint8 flipCount, uint256 totalStake) {
        amountPerFlip = turboFlipStake[lootboxIndex][player];
        flipCount = turboFlipCount[lootboxIndex][player];
        if (flipCount == 0 && amountPerFlip != 0) {
            flipCount = 1;
        }
        totalStake = flipCount == 0 ? 0 : amountPerFlip * uint256(flipCount);
    }

    /// @notice Get pending turbo flip details including side selection.
    /// @param player The player address to query.
    /// @param lootboxIndex Lootbox RNG index.
    /// @return amountPerFlip Pending amount per flip.
    /// @return flipCount Pending flip count (0-10).
    /// @return totalStake Pending total stake (amountPerFlip * flipCount).
    /// @return betOnLoss True if the stake is on the loss side.
    function turboFlipInfoDetailed(
        address player,
        uint48 lootboxIndex
    )
        external
        view
        returns (
            uint256 amountPerFlip,
            uint8 flipCount,
            uint256 totalStake,
            bool betOnLoss
        )
    {
        amountPerFlip = turboFlipStake[lootboxIndex][player];
        flipCount = turboFlipCount[lootboxIndex][player];
        if (flipCount == 0 && amountPerFlip != 0) {
            flipCount = 1;
        }
        totalStake = flipCount == 0 ? 0 : amountPerFlip * uint256(flipCount);
        betOnLoss = turboFlipBetOnLoss[lootboxIndex][player];
    }

    /// @notice Get pending turbo DGNRS decimator stakes for a player at a lootbox RNG index.
    /// @param player The player address to query.
    /// @param lootboxIndex Lootbox RNG index.
    /// @return decimatorStake Pending turbo decimator DGNRS stake.
    /// @return lane Selected lane for turbo decimator DGNRS (0-9).
    function turboDgnrsStakeInfo(
        address player,
        uint48 lootboxIndex
    ) external view returns (uint256 decimatorStake, uint8 lane) {
        decimatorStake = turboDecimatorDgnrsStake[lootboxIndex][player];
        lane = turboDecimatorDgnrsLane[lootboxIndex][player];
    }

    /// @notice Get coinflip auto-rebuy settings for a player.
    /// @param player The player's address.
    /// @return enabled True if auto-rebuy is enabled.
    /// @return stopAmount The keep multiple reserved on wins (0 = keep everything in auto-rebuy).
    /// @return carry The current auto-rebuy carry (rolled bankroll).
    function coinflipAutoRebuyInfo(
        address player
    ) external view returns (bool enabled, uint256 stopAmount, uint256 carry) {
        if (coinflipContract == address(0)) return (false, 0, 0);
        uint48 startDay;
        (enabled, stopAmount, carry, startDay) = IBurnieCoinflip(coinflipContract).coinflipAutoRebuyInfo(player);
    }

    /// @notice Total supply including uncirculated ContractAddresses.VAULT allowance.
    /// @dev Used by ContractAddresses.VAULT share calculations and dashboards.
    /// @return The sum of circulating supply + virtual ContractAddresses.VAULT reserve.
    function supplyIncUncirculated() external view returns (uint256) {
        return totalSupply + _vaultMintAllowance;
    }

    /// @notice Virtual coin reserved for the ContractAddresses.VAULT (not yet circulating).
    /// @dev Exposed for the ContractAddresses.VAULT share math and external dashboards.
    /// @return The current ContractAddresses.VAULT mint allowance in BURNIE (18 decimals).
    function vaultMintAllowance() external view returns (uint256) {
        return _vaultMintAllowance;
    }

    /// @notice Get total pending turbo flip BURNIE amount.
    /// @dev Used by manual RNG trigger threshold check.
    /// @return The total pending turbo flip BURNIE (18 decimals).
    function turboFlipPendingBurnieAmount() external view returns (uint256) {
        return turboFlipPendingBurnie;
    }

    /*+======================================================================+
      |                         BOUNTY STATE                                 |
      +======================================================================+
      |  Global bounty pool for record-breaking flips. The bounty pool       |
      |  accumulates 1000 BURNIE per coinflip window. When a player sets     |
      |  a new all-time high flip, they arm the bounty. On their next        |
      |  coinflip resolution, half the pool is removed; if they win, that    |
      |  half is credited to their stake, plus a DGNRS reward pool share.    |
      |                                                                      |
      |  STORAGE LAYOUT (packed in slots):                                   |
      |  +-----------------------------------------------------------------+ |
      |  | Slot | Variable         | Type     | Size     | Notes           | |
      |  +------+------------------+----------+----------+-----------------+ |
      |  |  17  | currentBounty    | uint128  | 16 bytes | Pool size       | |
      |  |      | biggestFlipEver  | uint128  | 16 bytes | All-time record | |
      |  |  18  | bountyOwedTo     | address  | 20 bytes | Armed recipient | |
      |  +-----------------------------------------------------------------+ |
      +======================================================================+*/

    /// @notice Current bounty pool size in BURNIE (18 decimals).
    /// @dev Increases by 1000 BURNIE each coinflip window. Half removed per resolution (paid on win).
    ///      Wraps on overflow (effectively resets to small value).

    /// @notice All-time record for biggest raw coinflip deposit (excludes bonuses).
    /// @dev Updated only by direct deposit calls; used as threshold for arming bounty.
    ///      Frozen during RNG lock to prevent manipulation.

    /// @notice Address that has armed the bounty (set new record).
    /// @dev Cleared after payout. Only one player can hold bounty right at a time.

    /*+======================================================================+
      |                       ERC20 DECIMALS                                 |
      +======================================================================+*/

    /// @notice Number of decimal places for BURNIE token.
    /// @dev 18 decimals (standard ERC20). 1 BURNIE = 1e18 base units.
    uint8 public constant decimals = 18;

    /*+======================================================================+
      |                       ERC20 FUNCTIONS                                |
      +======================================================================+
      |  Standard ERC20 interface with game-contract bypass for transferFrom.|
      |  The game contract can transfer on behalf of players without prior   |
      |  approval (trusted contract pattern).                                |
      +======================================================================+*/

    /// @notice Approve `spender` to transfer up to `amount` tokens on behalf of caller.
    /// @dev Standard ERC20 approve. Setting to type(uint256).max indicates infinite approval.
    /// @param spender The address authorized to spend.
    /// @param amount The maximum amount that can be spent.
    /// @return True on success.
    function approve(address spender, uint256 amount) public returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /// @notice Transfer `amount` tokens from caller to `to`.
    /// @dev Standard ERC20 transfer. Reverts on insufficient balance.
    /// @param to The recipient address.
    /// @param amount The amount to transfer (18 decimals).
    /// @return True on success.
    function transfer(address to, uint256 amount) public returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    /// @notice Transfer `amount` tokens from `from` to `to` on behalf of caller.
    /// @dev Standard ERC20 transferFrom with game-contract bypass.
    ///      SECURITY: DegenerusGame can transfer without approval (trusted contract pattern).
    ///      This enables seamless gameplay transactions without pre-approval steps.
    /// @param from The source address.
    /// @param to The destination address.
    /// @param amount The amount to transfer (18 decimals).
    /// @return True on success.
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public returns (bool) {
        // Game contract bypass: no allowance check needed for trusted game operations
        if (msg.sender != ContractAddresses.GAME) {
            uint256 allowed = allowance[from][msg.sender];
            // Infinite approval optimization: skip allowance update for max value
            if (allowed != type(uint256).max) {
                // Solidity 0.8+ will revert on underflow if allowed < amount
                uint256 newAllowance = allowed - amount;
                allowance[from][msg.sender] = newAllowance;
                emit Approval(from, msg.sender, newAllowance);
            }
        }
        _transfer(from, to, amount);
        return true;
    }

    /// @notice Internal transfer helper.
    /// @dev Reverts on zero address or insufficient balance (via Solidity 0.8+ underflow check).
    /// @param from The source address.
    /// @param to The destination address.
    /// @param amount The amount to transfer.
    function _transfer(address from, address to, uint256 amount) internal {
        if (from == address(0) || to == address(0)) revert ZeroAddress();
        // Solidity 0.8+ reverts on underflow if balanceOf[from] < amount
        balanceOf[from] -= amount;

        if (to == ContractAddresses.VAULT) {
            // Vault receives no circulating BURNIE; redirect to mint allowance.
            totalSupply -= amount;
            _vaultMintAllowance += amount;
            emit Transfer(from, address(0), amount);
            emit VaultEscrowRecorded(from, amount);
            return;
        }

        // Overflow is theoretically possible but would require ~2^256 total supply
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }

    /// @notice Internal mint helper - creates new tokens.
    /// @dev Increases totalSupply and recipient balance. Emits Transfer from address(0).
    /// @param to The recipient address (cannot be zero).
    /// @param amount The amount to mint (18 decimals).
    function _mint(address to, uint256 amount) internal {
        if (to == address(0)) revert ZeroAddress();
        if (to == ContractAddresses.VAULT) {
            _vaultMintAllowance += amount;
            emit VaultEscrowRecorded(address(0), amount);
            return;
        }
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    /// @notice Internal burn helper - destroys tokens.
    /// @dev Decreases totalSupply and sender balance. Emits Transfer to address(0).
    ///      SECURITY: Burns BEFORE any external calls (CEI pattern) in depositCoinflip/decimatorBurn.
    /// @param from The address to burn from (cannot be zero).
    /// @param amount The amount to burn (18 decimals).
    function _burn(address from, uint256 amount) internal {
        if (from == address(0)) revert ZeroAddress();
        if (from == ContractAddresses.VAULT) {
            uint256 allowanceVault = _vaultMintAllowance;
            if (amount > allowanceVault) revert Insufficient();
            _vaultMintAllowance = allowanceVault - amount;
            emit VaultAllowanceSpent(from, amount);
            return;
        }
        // Solidity 0.8+ reverts on underflow if balanceOf[from] < amount
        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }

    /*+======================================================================+
      |                  COINFLIP CONTRACT INTEGRATION                       |
      +======================================================================+
      |  Permission functions for BurnieCoinflip contract to burn/mint      |
      |  BURNIE tokens. Only the designated coinflip contract can call.     |
      +======================================================================+*/

    /// @notice Set the BurnieCoinflip contract address.
    /// @dev Admin-only function. Should be called once after BurnieCoinflip deployment.
    /// @param _coinflipContract The address of the BurnieCoinflip contract.
    function setCoinflipContract(address _coinflipContract) external onlyDegenerusGameContract {
        if (_coinflipContract == address(0)) revert ZeroAddress();
        coinflipContract = _coinflipContract;
    }

    /// @notice Burns BURNIE from a player for coinflip deposits.
    /// @dev Only callable by the BurnieCoinflip contract.
    /// @param from The player's address to burn from.
    /// @param amount The amount of BURNIE to burn (18 decimals).
    function burnForCoinflip(address from, uint256 amount) external {
        if (msg.sender != coinflipContract) revert OnlyGame(); // Reusing error for simplicity
        _burn(from, amount);
    }

    /// @notice Mints BURNIE to a player for coinflip claims.
    /// @dev Only callable by the BurnieCoinflip contract.
    /// @param to The player's address to mint to.
    /// @param amount The amount of BURNIE to mint (18 decimals).
    function mintForCoinflip(address to, uint256 amount) external {
        if (msg.sender != coinflipContract) revert OnlyGame(); // Reusing error for simplicity
        _mint(to, amount);
    }

    function _requireApproved(address player) private view {
        if (msg.sender != player && !degenerusGame.isOperatorApproved(player, msg.sender)) {
            revert NotApproved();
        }
    }

    function _resolvePlayer(address player) private view returns (address resolved) {
        if (player == address(0)) return msg.sender;
        if (player != msg.sender) _requireApproved(player);
        return player;
    }

    /*+======================================================================+
      |                         CONSTANTS                                    |
      +======================================================================+
      |  Protocol parameters and unit conversions. These define the          |
      |  economic boundaries of the coinflip and decimator systems.          |
      |                                                                      |
      |  VALUE SUMMARY:                                                      |
      |  • ether (1e18)            - Standard 18-decimal token unit          |
      |  • PRICE_COIN_UNIT (1000)  - Bounty increment per window             |
      |  • MIN (10,000 BURNIE)     - Minimum deposit/burn threshold          |
      |  • COINFLIP_EXTRA [78-115] - Payout multiplier range for normal      |
      |  • BPS_DENOMINATOR (10000) - Basis points conversion                 |
      |  • DECIMATOR_BUCKET (12)   - Base bucket for decimator weighting     |
      |  • JACKPOT_RESET_TIME      - Daily reset boundary (22:57 UTC)        |
      |  • COIN_CLAIM_DAYS (90)    - Max days to claim past winnings         |
      |  • COIN_CLAIM_FIRST_DAYS   - First-claim window (30 days)            |
      +======================================================================+*/

    /// @dev 1000 BURNIE - used for bounty accumulation.
    uint256 private constant PRICE_COIN_UNIT = 1000 ether;

    /// @dev Minimum amount for coinflip deposits and decimator burns (10,000 BURNIE).
    ///      Prevents dust attacks and meaningless micro-stakes.

    /// @dev WWXRP consolation reward per losing coinflip (0.1 WWXRP).

    /// @dev Minimum keep-multiple for afKing coin auto-rebuy (20,000 BURNIE).

    /// @dev Base percentage for normal coinflip payouts (non-extreme outcomes).
    ///      Range: [78, 78+37] = [78%, 115%] when added to principal.

    /// @dev Basis points denominator for percentage calculations (100.00%).
    uint16 private constant BPS_DENOMINATOR = 10_000;

    /// @dev Base bucket denominator for decimator weighting.
    ///      Lower bucket = more valuable. Adjusted based on activity multiplier.
    uint8 private constant DECIMATOR_BUCKET = 12;

    /// @dev Turbo decimator lane count (0-9).
    uint8 private constant TURBO_DECIMATOR_LANES = 10;

    /// @dev Turbo flip max count per RNG word.
    uint8 private constant TURBO_FLIP_MAX_COUNT = 10;

    /// @dev Turbo flip payout multipliers (bps). 1x = 10_000.
    uint32 private constant TURBO_FLIP_PAYOUT_BPS = 19_000; // 1.90x = 95% EV
    uint32 private constant TURBO_FLIP_PAYOUT_BPS_MAX = 19_800; // 1.98x = 99% EV

    /// @dev Turbo flip payout when betting on loss side (bps). 1x = 10_000.
    uint32 private constant TURBO_FLIP_LOSS_PAYOUT_BPS = 18_000; // 1.80x = 90% EV

    /// @dev Turbo flip payout RNG domain tag (prevents collisions with other uses).
    bytes32 private constant TURBO_FLIP_PAYOUT_TAG =
        keccak256("turbo-flip-payout");

    /// @dev Turbo decimator payout multipliers (bps). 1x = 10_000.
    uint32 private constant TURBO_DECIMATOR_PAYOUT_BPS = 95_000; // 9.5x = 95% EV (1/10 win)
    uint32 private constant TURBO_DECIMATOR_PAYOUT_BPS_MAX = 99_000; // 9.9x = 99% EV

    /// @dev Max activity score used for bucket scaling (no whale/trophy):
    ///      50% streak + 25% count + 100% quest + 50% affiliate = 225% bonus.
    uint16 private constant ACTIVITY_SCORE_MAX_NO_EXTRA_BPS = 32_500;

    /// @dev Seconds offset from midnight UTC for daily coinflip reset boundary (22:57 UTC).
    uint48 private constant JACKPOT_RESET_TIME = 82620;

    /// @dev Maximum number of past days a player can claim coinflip winnings.
    ///      After 90 days, unclaimed winnings expire (stakes are forfeit).
    uint8 private constant COIN_CLAIM_DAYS = 90;

    /// @dev First-claim window for players who have never claimed.
    uint8 private constant COIN_CLAIM_FIRST_DAYS = 30;

    /// @dev Max number of days to process when turning auto-rebuy off.
    ///      Bounds gas without dynamic gas checks.
    uint16 private constant AUTO_REBUY_OFF_CLAIM_DAYS_MAX = 1095;

    /// @dev Maximum BAF (Biggest Active Flip) bracket level.
    ///      Levels are grouped into brackets of 10 for leaderboard tracking.
    uint24 private constant MAX_BAF_BRACKET = (type(uint24).max / 10) * 10;

    /*+======================================================================+
      |                         MODIFIERS                                    |
      +======================================================================+
      |  Access control modifiers for privileged operations. Each modifier   |
      |  gates access to a specific set of trusted contracts.                |
      |                                                                      |
      |  MODIFIER HIERARCHY:                                                 |
      |  +-----------------------------------------------------------------+ |
      |  |  Modifier              | Allowed Callers                        | |
      |  +------------------------+----------------------------------------+ |
      |  |  onlyDegenerusGame     | degenerusGame only                     | |
      |  |  onlyTrustedContracts  | GAME, GAMEPIECES, AFFILIATE, ICON_COLOR_REGISTRY | |
      |  |  onlyFlipCreditors     | GAME, GAMEPIECES, AFFILIATE            | |
      |  |  onlyVault             | VAULT only                             | |
      |  +-----------------------------------------------------------------+ |
      +======================================================================+*/

    /// @dev Restricts access to the DegenerusGame contract only.
    ///      Used for: processCoinflipPayouts, rollDailyQuest, notifyQuestBurn.
    modifier onlyDegenerusGameContract() {
        if (msg.sender != ContractAddresses.GAME) revert OnlyGame();
        _;
    }

    /// @dev Restricts access to game, gamepiece, affiliate, or color registry contracts.
    ///      Used for: burnCoin (gameplay burns).
    modifier onlyTrustedContracts() {
        address sender = msg.sender;
        if (
            sender != ContractAddresses.GAME &&
            sender != ContractAddresses.GAMEPIECES &&
            sender != ContractAddresses.AFFILIATE &&
            sender != ContractAddresses.ICON_COLOR_REGISTRY
        ) revert OnlyTrustedContracts();
        _;
    }

    /// @dev Restricts access to contracts that can credit flip stakes.
    ///      Used for: creditFlip, creditFlipBatch.
    modifier onlyFlipCreditors() {
        address sender = msg.sender;
        if (
            sender != ContractAddresses.GAME &&
            sender != ContractAddresses.GAMEPIECES &&
            sender != ContractAddresses.AFFILIATE
        ) revert OnlyFlipCreditors();
        _;
    }

    /// @dev Restricts access to the ContractAddresses.VAULT contract only.
    ///      Used for: vaultMintTo.
    modifier onlyVault() {
        if (msg.sender != ContractAddresses.VAULT) revert OnlyVault();
        _;
    }


    /// @notice Compute affiliate quest rewards while preserving quest module access control.
    /// @dev Access: affiliate contract only. Routes through coin contract to enforce access.
    /// @param player The player who triggered the affiliate action.
    /// @param amount The base amount for quest calculation.
    /// @return questReward The bonus reward earned (if any quest completed).
    function affiliateQuestReward(
        address player,
        uint256 amount
    ) external returns (uint256 questReward) {
        if (msg.sender != ContractAddresses.AFFILIATE) revert OnlyAffiliate();
        IDegenerusQuests module = questModule;
        if (player == address(0) || amount == 0) return 0;
        (
            uint256 reward,
            bool hardMode,
            uint8 questType,
            uint32 streak,
            bool completed,
            bool completedBoth
        ) = module.handleAffiliate(player, amount);
        return
            _questApplyReward(
                player,
                reward,
                hardMode,
                questType,
                streak,
                completed,
                completedBoth
            );
    }

    /*+======================================================================+
      |                       QUEST INTEGRATION                              |
      +======================================================================+
      |  Daily quest lifecycle functions. The coin contract acts as a hub    |
      |  to route quest-related calls to the quest module while maintaining  |
      |  access control and emitting events for indexers.                    |
      +======================================================================+*/

    /// @notice Roll the daily quest for a given day using VRF entropy.
    /// @dev Access: game contract only. Emits DailyQuestRolled for each quest type.
    /// @param day The day index to roll for.
    /// @param entropy VRF-sourced randomness for quest selection.
    function rollDailyQuest(
        uint48 day,
        uint256 entropy
    ) external onlyDegenerusGameContract {
        IDegenerusQuests module = questModule;
        (bool rolled, uint8[2] memory questTypes, bool highDifficulty) = module
            .rollDailyQuest(day, entropy);
        if (rolled) {
            for (uint256 i; i < 2; ) {
                emit DailyQuestRolled(day, questTypes[i], highDifficulty);
                unchecked {
                    ++i;
                }
            }
        }
    }

    /// @notice Roll the daily quest with explicit overrides for quest types.
    /// @dev Access: game contract only. Used when game state requires specific quest types.
    /// @param day The day index to roll for.
    /// @param entropy VRF-sourced randomness.
    /// @param forceMintEth Force a mint-with-ETH quest type.
    /// @param forceBurn Force a burn quest type.
    function rollDailyQuestWithOverrides(
        uint48 day,
        uint256 entropy,
        bool forceMintEth,
        bool forceBurn
    ) external onlyDegenerusGameContract {
        IDegenerusQuests module = questModule;
        (bool rolled, uint8[2] memory questTypes, bool highDifficulty) = module
            .rollDailyQuestWithOverrides(day, entropy, forceMintEth, forceBurn);
        if (rolled) {
            for (uint256 i; i < 2; ) {
                emit DailyQuestRolled(day, questTypes[i], highDifficulty);
                unchecked {
                    ++i;
                }
            }
        }
    }

    /// @notice Notify quest module of a mint action.
    /// @dev Access: gamepiece contract only. Credits quest rewards as flip stakes.
    /// @param player The player who minted.
    /// @param quantity Number of gamepieces minted.
    /// @param paidWithEth Whether the mint was paid with ETH (vs BURNIE).
    function notifyQuestMint(
        address player,
        uint32 quantity,
        bool paidWithEth
    ) external {
        if (msg.sender != ContractAddresses.GAMEPIECES) revert OnlyGamepieces();
        IDegenerusQuests module = questModule;
        (
            uint256 reward,
            bool hardMode,
            uint8 questType,
            uint32 streak,
            bool completed,
            bool completedBoth
        ) = module.handleMint(player, quantity, paidWithEth);
        uint256 questReward = _questApplyReward(
            player,
            reward,
            hardMode,
            questType,
            streak,
            completed,
            completedBoth
        );
        if (questReward != 0 && coinflipContract != address(0)) {
            IBurnieCoinflip(coinflipContract).creditFlip(player, questReward);
        }
    }

    /// @notice Notify quest module of an gamepiece burn.
    /// @dev Access: game contract only. Credits quest rewards as flip stakes.
    /// @param player The player who burned gamepieces.
    /// @param quantity Number of gamepieces burned.
    function notifyQuestBurn(address player, uint32 quantity) external {
        if (msg.sender != ContractAddresses.GAME) revert OnlyGame();
        IDegenerusQuests module = questModule;
        (
            uint256 reward,
            bool hardMode,
            uint8 questType,
            uint32 streak,
            bool completed,
            bool completedBoth
        ) = module.handleBurn(player, quantity);
        uint256 questReward = _questApplyReward(
            player,
            reward,
            hardMode,
            questType,
            streak,
            completed,
            completedBoth
        );
        if (questReward != 0 && coinflipContract != address(0)) {
            IBurnieCoinflip(coinflipContract).creditFlip(player, questReward);
        }
    }

    /// @notice Notify quest module of a loot box purchase.
    /// @dev Access: game contract only. Credits quest rewards as flip stakes.
    /// @param player The player who purchased the loot box.
    /// @param amountWei ETH amount spent on the loot box (in wei).
    function notifyQuestLootBox(address player, uint256 amountWei) external {
        if (msg.sender != ContractAddresses.GAME) revert OnlyGame();
        IDegenerusQuests module = questModule;
        (
            uint256 reward,
            bool hardMode,
            uint8 questType,
            uint32 streak,
            bool completed,
            bool completedBoth
        ) = module.handleLootBox(player, amountWei);
        uint256 questReward = _questApplyReward(
            player,
            reward,
            hardMode,
            questType,
            streak,
            completed,
            completedBoth
        );
        if (questReward != 0 && coinflipContract != address(0)) {
            IBurnieCoinflip(coinflipContract).creditFlip(player, questReward);
        }
    }

    /// @notice Burn BURNIE from `target` during gameplay/affiliate flows.
    /// @dev Access: DegenerusGame, gamepiece, or affiliate.
    ///      Used for purchases, fees, and affiliate utilities.
    ///      Reverts on zero address or insufficient balance.
    /// @param target The address to burn from.
    /// @param amount The amount to burn (18 decimals).
    function burnCoin(
        address target,
        uint256 amount
    ) external onlyTrustedContracts {
        _burn(target, amount);
    }

    /*+======================================================================+
      |                       COINFLIP VIEW FUNCTIONS                        |
      +======================================================================+
      |  Read-only functions for querying coinflip stake amounts.            |
      +======================================================================+*/

    /// @notice Get a player's coinflip stake for the current betting window.
    /// @param player The player address to query.
    /// @return The stake amount for the current target day (18 decimals).
    function coinflipAmount(address player) external view returns (uint256) {
        if (coinflipContract == address(0)) return 0;
        return IBurnieCoinflip(coinflipContract).coinflipAmount(player);
    }

    /// @notice Return the player's coinflip stake for the most recently opened day window.
    /// @dev Proxies to BurnieCoinflip contract.
    ///      Useful for UIs showing "last day's bet" that is now being resolved.
    /// @param player The player address to query.
    /// @return The stake amount from the previous day (18 decimals).
    function coinflipAmountLastDay(
        address player
    ) external view returns (uint256) {
        // Note: This function is deprecated and returns the same as coinflipAmount
        if (coinflipContract == address(0)) return 0;
        return IBurnieCoinflip(coinflipContract).coinflipAmount(player);
    }

    /*+======================================================================+
      |                    QUEST INTEGRATION HELPERS                         |
      +======================================================================+*/

    /// @dev Apply quest reward if quest was completed. Emits QuestCompleted event.
    /// @param player The player who completed the quest.
    /// @param reward The raw reward amount.
    /// @param hardMode Whether completed in hard mode.
    /// @param questType The type of quest completed.
    /// @param streak The player's current streak.
    /// @param completed Whether the quest was actually completed.
    /// @param completedBoth Whether this completion finished both quest slots for the day.
    /// @return The reward amount (0 if not completed).
    function _questApplyReward(
        address player,
        uint256 reward,
        bool hardMode,
        uint8 questType,
        uint32 streak,
        bool completed,
        bool completedBoth
    ) private returns (uint256) {
        if (!completed) return 0;
        // Event captures quest progress for indexers/UI; raw reward is returned to the caller.
        emit QuestCompleted(
            player,
            questType,
            streak,
            reward,
            hardMode,
            completedBoth
        );
        return reward;
    }}
