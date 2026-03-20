// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/**
 * @title BurnieCoin
 * @author Burnie Degenerus
 * @notice ERC20 in-game token (BURNIE, 18 decimals) with minting, burning, and supply management.
 *
 * @dev ARCHITECTURE:
 *      - ERC20 standard with game contract transfer bypass
 *      - Mint/burn interface for game contract, coinflip contract, and vault
 *      - Flip credit accounting: credits denominated in BURNIE, delegated to BurnieCoinflip.sol
 *      - Decimator burns: Burn-to-participate for decimator jackpot eligibility
 *      - Quest integration: Daily quest rolls, streak tracking, slot rewards
 *      - Vault escrow: 2M BURNIE virtual reserve, minted only on ContractAddresses.VAULT withdrawal
 *
 * @dev CRITICAL INVARIANTS:
 *      - totalSupply + vaultAllowance = supplyIncUncirculated
 *
 * @dev SECURITY:
 *      - Access control: onlyDegenerusGameContract, onlyFlipCreditors, onlyVault, onlyAdmin
 *      - CEI pattern: burns before external calls
 */

import {IDegenerusGame} from "./interfaces/IDegenerusGame.sol";
import {IDegenerusQuests} from "./interfaces/IDegenerusQuests.sol";
import {ContractAddresses} from "./ContractAddresses.sol";

interface IBurnieCoinflip {
    function previewClaimCoinflips(address player) external view returns (uint256 mintable);
    function claimCoinflipsFromBurnie(address player, uint256 amount) external returns (uint256 claimed);
    function consumeCoinflipsForBurn(address player, uint256 amount) external returns (uint256 consumed);
    function coinflipAmount(address player) external view returns (uint256);
    function coinflipAutoRebuyInfo(address player) external view returns (bool enabled, uint256 stop, uint256 carry, uint48 startDay);
    function creditFlip(address player, uint256 amount) external;
    function creditFlipBatch(address[3] calldata players, uint256[3] calldata amounts) external;
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

    /// @notice Emitted when a player burns BURNIE during a decimator window.
    /// @param player The burner's address.
    /// @param amountBurned The amount burned (18 decimals).
    /// @param bucket The effective bucket weight assigned (lower = more valuable).
    event DecimatorBurn(
        address indexed player,
        uint256 amountBurned,
        uint8 bucket
    );

    /// @notice Emitted on a terminal decimator (death bet) burn.
    event TerminalDecimatorBurn(
        address indexed player,
        uint256 amountBurned
    );

    /// @notice Emitted when the daily quest is rolled for a new day.
    /// @param day The day index (1-indexed, day 1 = deploy day).
    /// @param questType The type of quest rolled (see IDegenerusQuests).
    /// @param highDifficulty Always false (difficulty removed).
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
    event QuestCompleted(
        address indexed player,
        uint8 questType,
        uint32 streak,
        uint256 reward
    );

    /// @notice Emitted when ContractAddresses.ADMIN credits LINK-funded bonus directly.
    /// @param player The recipient of the credit.
    /// @param amount The amount credited as flip stake (18 decimals).
    event LinkCreditRecorded(address indexed player, uint256 amount);

    /// @notice Emitted when virtual coin is escrowed to the vault reserve.
    /// @param sender The contract that escrowed the funds (VAULT or GAME).
    /// @param amount The amount added to vault mint allowance (18 decimals).
    event VaultEscrowRecorded(address indexed sender, uint256 amount);
    /// @notice Emitted when the vault spends from its mint allowance (may or may not mint tokens).
    /// @param spender The contract spending from allowance.
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

    /// @notice Deposit/burn amount is below the minimum threshold (1,000 BURNIE).
    error AmountLTMin();

    /// @notice Zero address not allowed for transfers, mints, or wiring.
    error ZeroAddress();

    /// @notice Decimator burn attempted outside an active decimator window.
    error NotDecimatorWindow();

    /// @notice Caller is not the authorized affiliate contract.
    error OnlyAffiliate();

    /// @notice Caller is not authorized (trusted contracts: GAME, AFFILIATE).
    error OnlyTrustedContracts();

    /// @notice Caller is not authorized (flip creditors: GAME, AFFILIATE).
    error OnlyFlipCreditors();

    /// @notice Caller is not approved to act for the player.
    error NotApproved();

    /// @notice Supply values exceed uint128 bounds.
    error SupplyOverflow();

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
      |  |  0   | _supply (total/vault)       | uint128 + uint128          | |
      |  |  1   | balanceOf                   | mapping(address => uint256)| |
      |  |  2   | allowance                   | mapping(addr => mapping)   | |
      |  +-----------------------------------------------------------------+ |
      +======================================================================+*/

    /// @notice Token name displayed in wallets and explorers.
    string public constant name = "Burnies";

    /// @notice Token symbol (ticker).
    string public constant symbol = "BURNIE";

    /// @dev Minimum BURNIE amount for decimator burns (prevents dust spam).
    uint256 private constant DECIMATOR_MIN = 1_000 ether;

    /// @dev Base bucket denominator for decimator weighting (lower = better odds).
    uint8 private constant DECIMATOR_BUCKET_BASE = 12;

    /// @dev Minimum bucket for normal and level-100 decimators.
    uint8 private constant DECIMATOR_MIN_BUCKET_NORMAL = 5;
    uint8 private constant DECIMATOR_MIN_BUCKET_100 = 2;

    /// @dev Cap for activity score bonus applied to decimator buckets (lazy pass max = 235%).
    uint16 private constant DECIMATOR_ACTIVITY_CAP_BPS = 23_500;

    /// @dev Max base amount eligible for decimator boon boost.
    uint256 private constant DECIMATOR_BOON_CAP = 50_000 ether;

    /// @dev Quest type ids (must match DegenerusQuests).
    uint8 private constant QUEST_TYPE_MINT_ETH = 1;

    /// @dev Basis points denominator (10000 = 1x).
    uint16 private constant BPS_DENOMINATOR = 10_000;

    /// @dev Packed supply state to keep total/vault allowance in a single slot.
    struct Supply {
        uint128 totalSupply;
        uint128 vaultAllowance;
    }

    /// @notice Total circulating supply (excludes ContractAddresses.VAULT's virtual allowance).
    /// @dev Increases on mint, decreases on burn. Always equals sum of all balanceOf entries.
    Supply private _supply = Supply({totalSupply: 0, vaultAllowance: uint128(2_000_000 ether)});

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
      |  • GAME, QUESTS, AFFILIATE                                           |
      |  • VAULT, ADMIN, COINFLIP                                            |
      +======================================================================+*/

    /// @notice The main game contract; provides level, RNG state, and purchase info.
    IDegenerusGame internal constant degenerusGame =
        IDegenerusGame(ContractAddresses.GAME);

    /// @notice The quest module handling daily quests and streak tracking.
    IDegenerusQuests internal constant questModule =
        IDegenerusQuests(ContractAddresses.QUESTS);

    /// @notice BurnieCoinflip contract - handles all coinflip wagering logic.
    /// @dev Fixed at deploy time via ContractAddresses.
    address internal constant coinflipContract = ContractAddresses.COINFLIP;

    // Deploy day boundary moved to ContractAddresses.DEPLOY_DAY_BOUNDARY (compile-time constant)

    /*+======================================================================+
      |                         VAULT ESCROW                                 |
      +======================================================================+
      |  Virtual mint allowance for the ContractAddresses.VAULT. This represents BURNIE that   |
      |  exists "on paper" but hasn't entered circulation. The ContractAddresses.VAULT can     |
      |  mint from this allowance when distributing to players.              |
      +======================================================================+*/
    /// @notice Virtual supply the ContractAddresses.VAULT is authorized to mint (not yet circulating).
    /// @dev Seeded to 2,000,000 BURNIE in `_supply`. Increases via vaultEscrow(), decreases via vaultMintTo().
    ///      supplyIncUncirculated = totalSupply + vaultAllowance.
    /// @custom:security Only ContractAddresses.VAULT/game can increase; only ContractAddresses.VAULT can mint from it.

    /*+======================================================================+
      |                         CONSTRUCTOR                                  |
      +======================================================================+*/

    /// @notice Seeds the sDGNRS backing reserve with 2 M BURNIE (fresh supply).
    constructor() {
        _mint(ContractAddresses.SDGNRS, 2_000_000 ether);
    }

    /*+======================================================================+
      |                         VIEW HELPERS                                 |
      +======================================================================+
      |  Read-only functions for UIs and external contracts to query state.  |
      +======================================================================+*/

    /// @notice View-only helper to estimate claimable coin (flips only) for the caller.
    /// @dev Proxies to BurnieCoinflip contract for coinflip-related claims.
    /// @return The total BURNIE claimable from past winning coinflips.
    function claimableCoin() external view returns (uint256) {
        return IBurnieCoinflip(coinflipContract).previewClaimCoinflips(msg.sender);
    }

    /// @notice Total spendable BURNIE at the current time (balance + claimable coinflips).
    /// @dev For ContractAddresses.VAULT, includes virtual vault allowance + any actual balance.
    /// @param player The address to query.
    /// @return spendable Total spendable amount right now.
    function balanceOfWithClaimable(address player) external view returns (uint256 spendable) {
        spendable = balanceOf[player];
        if (player == ContractAddresses.VAULT) {
            spendable += uint256(_supply.vaultAllowance);
        }
        unchecked {
            spendable += IBurnieCoinflip(coinflipContract).previewClaimCoinflips(player);
        }
    }

    /// @notice Preview the amount claimCoinflips(amount) would mint for a player.
    /// @dev Proxies to BurnieCoinflip contract.
    /// @param player The player to preview for.
    /// @return mintable Amount of BURNIE that would be minted on claim.
    function previewClaimCoinflips(address player) external view returns (uint256 mintable) {
        return IBurnieCoinflip(coinflipContract).previewClaimCoinflips(player);
    }

    /// @notice Get coinflip auto-rebuy settings for a player.
    /// @param player The player's address.
    /// @return enabled True if auto-rebuy is enabled.
    /// @return stopAmount The take profit amount reserved on wins (0 = keep everything in auto-rebuy).
    /// @return carry The current auto-rebuy carry (rolled bankroll).
    function coinflipAutoRebuyInfo(
        address player
    ) external view returns (bool enabled, uint256 stopAmount, uint256 carry) {
        (enabled, stopAmount, carry, ) = IBurnieCoinflip(coinflipContract).coinflipAutoRebuyInfo(player);
    }

    /// @notice Total circulating supply (excludes ContractAddresses.VAULT allowance).
    function totalSupply() external view returns (uint256) {
        return _supply.totalSupply;
    }

    /// @notice Total supply including uncirculated ContractAddresses.VAULT allowance.
    /// @dev Used by ContractAddresses.VAULT share calculations and dashboards.
    /// @return The sum of circulating supply + virtual ContractAddresses.VAULT reserve.
    function supplyIncUncirculated() external view returns (uint256) {
        return uint256(_supply.totalSupply) + uint256(_supply.vaultAllowance);
    }

    /// @notice Virtual coin reserved for the ContractAddresses.VAULT (not yet circulating).
    /// @dev Exposed for the ContractAddresses.VAULT share math and external dashboards.
    /// @return The current ContractAddresses.VAULT mint allowance in BURNIE (18 decimals).
    function vaultMintAllowance() external view returns (uint256) {
        return _supply.vaultAllowance;
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
    function approve(address spender, uint256 amount) external returns (bool) {
        uint256 current = allowance[msg.sender][spender];
        if (current != amount) {
            allowance[msg.sender][spender] = amount;
        }
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /// @notice Transfer `amount` tokens from caller to `to`.
    /// @dev Standard ERC20 transfer. Reverts on insufficient balance.
    /// @param to The recipient address.
    /// @param amount The amount to transfer (18 decimals).
    /// @return True on success.
    function transfer(address to, uint256 amount) external returns (bool) {
        _claimCoinflipShortfall(msg.sender, amount);
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
    ) external returns (bool) {
        // Game contract bypass: no allowance check needed for trusted game operations
        if (msg.sender != ContractAddresses.GAME) {
            uint256 allowed = allowance[from][msg.sender];
            // Infinite approval optimization: skip allowance update for max value
            if (allowed != type(uint256).max && amount != 0) {
                // Solidity 0.8+ will revert on underflow if allowed < amount
                uint256 newAllowance = allowed - amount;
                allowance[from][msg.sender] = newAllowance;
                emit Approval(from, msg.sender, newAllowance);
            }
        }
        _claimCoinflipShortfall(from, amount);
        _transfer(from, to, amount);
        return true;
    }

    function _toUint128(uint256 value) private pure returns (uint128) {
        if (value > type(uint128).max) revert SupplyOverflow();
        return uint128(value);
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
            uint128 amount128 = _toUint128(amount);
            unchecked {
                _supply.totalSupply -= amount128;
                _supply.vaultAllowance += amount128;
            }
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
        uint128 amount128 = _toUint128(amount);
        if (to == ContractAddresses.VAULT) {
            unchecked {
                _supply.vaultAllowance += amount128;
            }
            emit VaultEscrowRecorded(address(0), amount);
            return;
        }
        _supply.totalSupply += amount128;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    /// @notice Internal burn helper - destroys tokens.
    /// @dev Decreases totalSupply and sender balance. Emits Transfer to address(0).
    ///      SECURITY: Burns BEFORE any external calls (CEI pattern) in burnCoin/decimatorBurn/burnForCoinflip/terminalDecimatorBurn.
    /// @param from The address to burn from (cannot be zero).
    /// @param amount The amount to burn (18 decimals).
    function _burn(address from, uint256 amount) internal {
        if (from == address(0)) revert ZeroAddress();
        uint128 amount128 = _toUint128(amount);
        if (from == ContractAddresses.VAULT) {
            uint128 allowanceVault = _supply.vaultAllowance;
            if (amount128 > allowanceVault) revert Insufficient();
            unchecked {
                _supply.vaultAllowance = allowanceVault - amount128;
            }
            emit VaultAllowanceSpent(from, amount);
            return;
        }
        // Solidity 0.8+ reverts on underflow if balanceOf[from] < amount
        balanceOf[from] -= amount;
        _supply.totalSupply -= amount128;
        emit Transfer(from, address(0), amount);
    }

    /*+======================================================================+
      |                  COINFLIP CONTRACT INTEGRATION                       |
      +======================================================================+
      |  Permission functions for BurnieCoinflip contract to burn/mint      |
      |  BURNIE tokens. Only the designated coinflip contract can call.     |
      +======================================================================+*/

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

    /// @notice Mint BURNIE for game payouts (e.g., Degenerette wins).
    /// @dev Only callable by the DegenerusGame contract.
    /// @param to The player's address to mint to.
    /// @param amount The amount of BURNIE to mint (18 decimals).
    function mintForGame(address to, uint256 amount) external {
        if (msg.sender != ContractAddresses.GAME) revert OnlyGame();
        if (amount == 0) return;
        _mint(to, amount);
    }

    /// @notice Credit BURNIE directly to a player's wallet balance.
    /// @dev Only callable by trusted flip creditors (GAME, AFFILIATE).
    /// @param player Recipient address.
    /// @param amount Amount of BURNIE (18 decimals).
    function creditCoin(address player, uint256 amount) external onlyFlipCreditors {
        if (player == address(0) || amount == 0) return;
        _mint(player, amount);
    }

    /// @notice Credit FLIP to a player.
    /// @dev Only callable by trusted contracts (GAME, AFFILIATE).
    ///      Forwards to BurnieCoinflip which implements the actual flip credit logic.
    /// @param player Recipient address.
    /// @param amount Amount of FLIP (18 decimals).
    function creditFlip(address player, uint256 amount) external onlyFlipCreditors {
        IBurnieCoinflip(coinflipContract).creditFlip(player, amount);
    }

    /// @notice Credit FLIP to up to 3 players in a single call (gas optimization).
    /// @dev Only callable by trusted contracts (GAME, AFFILIATE).
    /// @param players Array of 3 recipient addresses (unused slots should be address(0)).
    /// @param amounts Array of 3 amounts corresponding to each player.
    function creditFlipBatch(address[3] calldata players, uint256[3] calldata amounts) external onlyFlipCreditors {
        IBurnieCoinflip(coinflipContract).creditFlipBatch(players, amounts);
    }

    /// @notice Credit BURNIE as flip stake to a player as a reward for donating LINK.
    /// @dev Only callable by ContractAddresses.ADMIN (called from onTokenTransfer after
    ///      LINK is forwarded to the VRF subscription). Credits are given as flip stake
    ///      so the reward is locked into the coinflip system rather than freely transferable.
    /// @param player The recipient of the credit.
    /// @param amount Amount of BURNIE to credit as flip stake (18 decimals).
    function creditLinkReward(address player, uint256 amount) external onlyAdmin {
        if (player == address(0) || amount == 0) return;
        IBurnieCoinflip(coinflipContract).creditFlip(player, amount);
        emit LinkCreditRecorded(player, amount);
    }

    function _claimCoinflipShortfall(address player, uint256 amount) private {
        if (amount == 0) return;
        if (degenerusGame.rngLocked()) return;
        uint256 balance = balanceOf[player];
        if (balance >= amount) return;
        unchecked {
            IBurnieCoinflip(coinflipContract).claimCoinflipsFromBurnie(
                player,
                amount - balance
            );
        }
    }

    function _consumeCoinflipShortfall(address player, uint256 amount) private returns (uint256 consumed) {
        if (amount == 0) return 0;
        if (degenerusGame.rngLocked()) return 0;
        uint256 balance = balanceOf[player];
        if (balance >= amount) return 0;
        unchecked {
            return IBurnieCoinflip(coinflipContract).consumeCoinflipsForBurn(
                player,
                amount - balance
            );
        }
    }

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
      |  |  onlyTrustedContracts  | GAME, AFFILIATE                        | |
      |  |  onlyFlipCreditors     | GAME, AFFILIATE                        | |
      |  |  onlyVault             | VAULT only                             | |
      |  |  onlyAdmin             | ADMIN only                             | |
      |  +-----------------------------------------------------------------+ |
      +======================================================================+*/

    /// @dev Restricts access to the DegenerusGame contract only.
    ///      Used for: processCoinflipPayouts, rollDailyQuest.
    modifier onlyDegenerusGameContract() {
        if (msg.sender != ContractAddresses.GAME) revert OnlyGame();
        _;
    }

    /// @dev Restricts access to game or affiliate contracts.
    ///      Used for: burnCoin (gameplay burns).
    modifier onlyTrustedContracts() {
        address sender = msg.sender;
        if (
            sender != ContractAddresses.GAME &&
            sender != ContractAddresses.AFFILIATE
        ) revert OnlyTrustedContracts();
        _;
    }

    /// @dev Restricts access to contracts that can credit flip stakes.
    ///      Used for: creditFlip, creditFlipBatch.
    modifier onlyFlipCreditors() {
        address sender = msg.sender;
        if (
            sender != ContractAddresses.GAME &&
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

    /// @dev Restricts access to the ContractAddresses.ADMIN contract only.
    ///      Used for: creditLinkReward.
    modifier onlyAdmin() {
        if (msg.sender != ContractAddresses.ADMIN) revert OnlyGame();
        _;
    }

    /*+======================================================================+
      |                     VAULT ESCROW FUNCTIONS                           |
      +======================================================================+
      |  Virtual mint allowance management for the VAULT. vaultEscrow()      |
      |  increases the allowance (called by game/modules), vaultMintTo()     |
      |  mints from the allowance (called by VAULT only).                    |
      +======================================================================+*/

    /// @notice Increase the vault's mint allowance without transferring tokens.
    /// @dev Called by game contract and modules to credit virtual BURNIE to the vault.
    /// @param amount Amount to add to vault's mint allowance.
    function vaultEscrow(uint256 amount) external {
        address sender = msg.sender;
        if (
            sender != ContractAddresses.GAME &&
            sender != ContractAddresses.VAULT
        ) revert OnlyVault();
        uint128 amount128 = _toUint128(amount);
        unchecked {
            _supply.vaultAllowance += amount128;
        }
        emit VaultEscrowRecorded(sender, amount);
    }

    /// @notice Mint tokens to recipient from vault's allowance.
    /// @dev Only callable by VAULT. Reduces vault allowance and mints to recipient.
    /// @param to Recipient address.
    /// @param amount Amount to mint.
    function vaultMintTo(address to, uint256 amount) external onlyVault {
        if (to == address(0)) revert ZeroAddress();
        uint128 amount128 = _toUint128(amount);
        uint128 allowanceVault = _supply.vaultAllowance;
        if (amount128 > allowanceVault) revert Insufficient();
        unchecked {
            _supply.vaultAllowance = allowanceVault - amount128;
            _supply.totalSupply += amount128;
            balanceOf[to] += amount;
        }
        emit VaultAllowanceSpent(address(this), amount);
        emit Transfer(address(0), to, amount);
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
            uint8 questType,
            uint32 streak,
            bool completed
        ) = module.handleAffiliate(player, amount);
        questReward = _questApplyReward(
            player,
            reward,
            questType,
            streak,
            completed
        );
        return questReward;
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

    /// @notice Notify quest module of a mint action.
    /// @dev Access: game contract only. Credits quest rewards as flip stakes and
    ///      notifies the game to update mint streak on slot-0 (MINT_ETH) completion.
    /// @param player The player who minted.
    /// @param quantity Number of mint units.
    /// @param paidWithEth Whether the mint was paid with ETH (vs BURNIE).
    function notifyQuestMint(
        address player,
        uint32 quantity,
        bool paidWithEth
    ) external {
        if (msg.sender != ContractAddresses.GAME) revert OnlyGame();
        IDegenerusQuests module = questModule;
        (
            uint256 reward,
            uint8 questType,
            uint32 streak,
            bool completed
        ) = module.handleMint(player, quantity, paidWithEth);
        uint256 questReward = _questApplyReward(
            player,
            reward,
            questType,
            streak,
            completed
        );
        if (completed && paidWithEth && questType == QUEST_TYPE_MINT_ETH) {
            degenerusGame.recordMintQuestStreak(player);
        }
        if (questReward != 0) {
            IBurnieCoinflip(coinflipContract).creditFlip(player, questReward);
        }
    }

    /// @notice Notify quest module of a loot box purchase.
    /// @dev Access: GAME only. Called from LootboxModule via delegatecall (msg.sender == GAME).
    /// @param player The player who purchased the loot box.
    /// @param amountWei ETH amount spent on the loot box (in wei).
    function notifyQuestLootBox(address player, uint256 amountWei) external {
        address sender = msg.sender;
        if (sender != ContractAddresses.GAME) revert OnlyGame();
        IDegenerusQuests module = questModule;
        (
            uint256 reward,
            uint8 questType,
            uint32 streak,
            bool completed
        ) = module.handleLootBox(player, amountWei);
        uint256 questReward = _questApplyReward(
            player,
            reward,
            questType,
            streak,
            completed
        );
        if (questReward != 0) {
            IBurnieCoinflip(coinflipContract).creditFlip(player, questReward);
        }
    }

    /// @notice Notify quest module of a Degenerette bet.
    /// @dev Access: game contract only. Credits quest rewards as flip stakes.
    /// @param player The player who placed the bet.
    /// @param amount Bet amount (wei for ETH, base units for BURNIE).
    /// @param paidWithEth True if bet was paid with ETH, false for BURNIE.
    function notifyQuestDegenerette(address player, uint256 amount, bool paidWithEth) external {
        address sender = msg.sender;
        if (sender != ContractAddresses.GAME) revert OnlyGame();
        IDegenerusQuests module = questModule;
        (
            uint256 reward,
            uint8 questType,
            uint32 streak,
            bool completed
        ) = module.handleDegenerette(player, amount, paidWithEth);
        uint256 questReward = _questApplyReward(
            player,
            reward,
            questType,
            streak,
            completed
        );
        if (questReward != 0) {
            IBurnieCoinflip(coinflipContract).creditFlip(player, questReward);
        }
    }

    /// @notice Burn BURNIE from `target` during gameplay/affiliate flows.
    /// @dev Access: DegenerusGame, game, or affiliate.
    ///      Used for purchases, fees, and affiliate utilities.
    ///      Reverts on zero address or insufficient balance.
    /// @param target The address to burn from.
    /// @param amount The amount to burn (18 decimals).
    function burnCoin(
        address target,
        uint256 amount
    ) external onlyTrustedContracts {
        uint256 consumed = _consumeCoinflipShortfall(target, amount);
        _burn(target, amount - consumed);
    }

    /*+======================================================================+
      |                          DECIMATOR                                  |
      +======================================================================+
      |  Burn BURNIE during active decimator windows to accrue weighted      |
      |  participation for the decimator jackpot.                            |
      +======================================================================+*/

    /// @notice Burn BURNIE during an active Decimator window to accrue weighted participation.
    /// @dev SECURITY: Burns BEFORE downstream calls (CEI pattern).
    ///      Quest rewards are added to the base amount before bucket calculation.
    ///      Bucket determines jackpot weight (lower = better odds).
    /// @param player Player address to burn for (address(0) = msg.sender).
    /// @param amount Amount (18 decimals) to burn; must satisfy MIN (1,000 BURNIE).
    function decimatorBurn(address player, uint256 amount) external {
        address caller;
        if (player == address(0) || player == msg.sender) {
            caller = msg.sender;
        } else {
            if (!degenerusGame.isOperatorApproved(player, msg.sender)) {
                revert NotApproved();
            }
            caller = player;
        }

        if (amount < DECIMATOR_MIN) revert AmountLTMin();

        (bool open, uint24 lvl) = degenerusGame.decWindow();
        if (!open) revert NotDecimatorWindow();

        uint256 consumed = _consumeCoinflipShortfall(caller, amount);
        // CEI: burn before any downstream calls after coinflip consumption
        _burn(caller, amount - consumed);

        // Quest processing (bonus applies to decimator weight and coinflip credit)
        (
            uint256 reward,
            uint8 questType,
            uint32 streak,
            bool completed
        ) = questModule.handleDecimator(caller, amount);

        uint256 questReward = _questApplyReward(
            caller,
            reward,
            questType,
            streak,
            completed
        );

        if (questReward != 0) {
            IBurnieCoinflip(coinflipContract).creditFlip(caller, questReward);
        }

        uint256 baseAmount = amount + questReward;

        // Activity score bonus (raw bps), capped for decimator scaling.
        uint256 bonusBps = degenerusGame.playerActivityScore(caller);
        if (bonusBps > DECIMATOR_ACTIVITY_CAP_BPS) {
            bonusBps = DECIMATOR_ACTIVITY_CAP_BPS;
        }

        uint256 decBurnMultBps = _decimatorBurnMultiplier(bonusBps);
        uint8 minBucket = (lvl % 100 == 0)
            ? DECIMATOR_MIN_BUCKET_100
            : DECIMATOR_MIN_BUCKET_NORMAL;
        uint8 bucket = _adjustDecimatorBucket(
            bonusBps,
            minBucket
        );

        // Decimator boon: percent boost on base amount (capped to 50k BURNIE).
        uint16 boonBps = degenerusGame.consumeDecimatorBoon(caller);
        if (boonBps > 0) {
            uint256 cappedBase = baseAmount > DECIMATOR_BOON_CAP
                ? DECIMATOR_BOON_CAP
                : baseAmount;
            uint256 boost = (cappedBase * boonBps) / BPS_DENOMINATOR;
            baseAmount += boost;
        }

        uint8 bucketUsed = degenerusGame.recordDecBurn(
            caller,
            lvl,
            bucket,
            baseAmount,
            decBurnMultBps
        );

        emit DecimatorBurn(caller, amount, bucketUsed);
    }

    /*+======================================================================+
      |                   TERMINAL DECIMATOR (DEATH BET)                     |
      +======================================================================+
      |  Always-open burn betting on GAMEOVER. Time multiplier rewards       |
      |  early conviction. Total loss if level completes normally.           |
      +======================================================================+*/

    /// @notice Burn BURNIE as a terminal decimator (death bet).
    /// @dev Always open (no milestone gating). Blocked on lastPurchaseDay
    ///      (level completing, death bet can never fire) and after death clock expires.
    ///      Bucket computed internally using lvl 100 rules (min bucket 2).
    /// @param player Player address to burn for (address(0) = msg.sender).
    /// @param amount Amount (18 decimals) to burn; must satisfy MIN (1,000 BURNIE).
    function terminalDecimatorBurn(address player, uint256 amount) external {
        address caller;
        if (player == address(0) || player == msg.sender) {
            caller = msg.sender;
        } else {
            if (!degenerusGame.isOperatorApproved(player, msg.sender)) {
                revert NotApproved();
            }
            caller = player;
        }

        if (amount < DECIMATOR_MIN) revert AmountLTMin();

        (bool open, uint24 lvl) = degenerusGame.terminalDecWindow();
        if (!open) revert NotDecimatorWindow();

        uint256 consumed = _consumeCoinflipShortfall(caller, amount);
        _burn(caller, amount - consumed);

        degenerusGame.recordTerminalDecBurn(
            caller,
            lvl,
            amount
        );

        emit TerminalDecimatorBurn(caller, amount);
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
        return IBurnieCoinflip(coinflipContract).coinflipAmount(player);
    }

    /*+======================================================================+
      |                    QUEST INTEGRATION HELPERS                         |
      +======================================================================+*/

    /// @dev Adjust decimator bucket based on activity score bonus.
    ///      Higher bonus yields lower bucket (better odds), capped at DECIMATOR_ACTIVITY_CAP_BPS.
    function _adjustDecimatorBucket(
        uint256 bonusBps,
        uint8 minBucket
    ) private pure returns (uint8 adjustedBucket) {
        adjustedBucket = DECIMATOR_BUCKET_BASE;
        if (bonusBps == 0) return adjustedBucket;

        if (bonusBps > DECIMATOR_ACTIVITY_CAP_BPS) {
            bonusBps = DECIMATOR_ACTIVITY_CAP_BPS;
        }

        uint256 range = uint256(DECIMATOR_BUCKET_BASE) - uint256(minBucket);
        uint256 reduction = (range * bonusBps + (DECIMATOR_ACTIVITY_CAP_BPS / 2)) / DECIMATOR_ACTIVITY_CAP_BPS;
        uint256 bucket = uint256(DECIMATOR_BUCKET_BASE) - reduction;
        if (bucket < minBucket) bucket = minBucket;
        adjustedBucket = uint8(bucket);
    }

    /// @dev Decimator burn multiplier: 1x base plus one-third of activity bonus.
    function _decimatorBurnMultiplier(uint256 bonusBps) private pure returns (uint256 decMultBps) {
        if (bonusBps == 0) return BPS_DENOMINATOR;
        return BPS_DENOMINATOR + (bonusBps / 3);
    }

    /// @dev Apply quest reward if quest was completed. Emits QuestCompleted event.
    /// @param player The player who completed the quest.
    /// @param reward The raw reward amount.
    /// @param questType The type of quest completed.
    /// @param streak The player's current streak.
    /// @param completed Whether the quest was actually completed.
    /// @return The reward amount (0 if not completed).
    function _questApplyReward(
        address player,
        uint256 reward,
        uint8 questType,
        uint32 streak,
        bool completed
    ) private returns (uint256) {
        if (!completed) return 0;
        // Event captures quest progress for indexers/UI; raw reward is returned to the caller.
        emit QuestCompleted(
            player,
            questType,
            streak,
            reward
        );
        return reward;
    }}
