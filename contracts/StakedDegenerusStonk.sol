// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {ContractAddresses} from "./ContractAddresses.sol";
import {IStETH} from "./interfaces/IStETH.sol";


/// @notice Interface for game contract player-facing functions
interface IDegenerusGamePlayer {
    function advanceGame() external;
    function setAfKingMode(
        address player,
        bool enabled,
        uint256 ethTakeProfit,
        uint256 coinTakeProfit
    ) external;
    function claimWinnings(address player) external;
    function claimWhalePass(address player) external;
    function claimableWinningsOf(address player) external view returns (uint256);
}

/// @notice Interface for BURNIE coin contract player-facing functions
interface IDegenerusCoinPlayer {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IBurnieCoinflipPlayer {
    function claimCoinflips(address player, uint256 amount) external returns (uint256 claimed);
    function previewClaimCoinflips(address player) external view returns (uint256 mintable);
}

/**
 * @title StakedDegenerusStonk (sDGNRS)
 * @notice Soulbound token backed by ETH, stETH, and BURNIE reserves
 * @dev Receives ETH/stETH from game distributions; rewards are distributed from pre-minted pools.
 *      Creator allocation is minted to the DGNRS wrapper contract; all other holders receive
 *      sDGNRS directly from reward pools (soulbound — no transfer function).
 *
 * ARCHITECTURE:
 * - Receives ETH deposits from game distributions
 * - Receives stETH deposits from game distributions
 * - Accrues BURNIE backing via manual transfers and coinflip claimables (withdrawn on burn)
 * - Pre-minted supply split into DGNRS wrapper allocation + reward pools
 * - Game distributes sDGNRS to players by drawing down pools
 * - Users burn sDGNRS to claim proportional ETH + stETH + BURNIE
 */
contract StakedDegenerusStonk {
    // =====================================================================
    //                              ERRORS
    // =====================================================================

    /// @notice Thrown when caller is not authorized for the operation
    error Unauthorized();

    /// @notice Thrown when amount exceeds available balance or allowance
    error Insufficient();

    /// @notice Thrown when zero address is provided where not allowed
    error ZeroAddress();

    /// @notice Thrown when ETH or token transfer fails
    error TransferFailed();




    // =====================================================================
    //                              EVENTS
    // =====================================================================

    /// @notice Emitted when tokens are transferred between addresses
    /// @param from Source address (address(0) for mints)
    /// @param to Destination address (address(0) for burns)
    /// @param amount Amount of tokens transferred
    event Transfer(address indexed from, address indexed to, uint256 amount);

    /// @notice Emitted when sDGNRS is burned to claim backing assets
    /// @param from Address that burned tokens
    /// @param amount Amount of sDGNRS burned
    /// @param ethOut ETH received
    /// @param stethOut stETH received
    /// @param burnieOut BURNIE received
    event Burn(address indexed from, uint256 amount, uint256 ethOut, uint256 stethOut, uint256 burnieOut);

    /// @notice Emitted when backing assets are deposited into reserves
    /// @param from Address that deposited
    /// @param ethAmount ETH deposited
    /// @param stethAmount stETH deposited
    /// @param burnieAmount BURNIE amount (always 0; BURNIE arrives via manual transfers or coinflip claims)
    event Deposit(address indexed from, uint256 ethAmount, uint256 stethAmount, uint256 burnieAmount);

    /// @notice Emitted when sDGNRS is transferred from a reward pool
    /// @param pool Pool from which tokens were transferred
    /// @param to Recipient address
    /// @param amount Amount transferred
    event PoolTransfer(Pool indexed pool, address indexed to, uint256 amount);

    /// @notice Emitted when sDGNRS is moved between reward pools
    /// @param from Source pool
    /// @param to Destination pool
    /// @param amount Amount transferred
    event PoolRebalance(Pool indexed from, Pool indexed to, uint256 amount);

    // =====================================================================
    //                          ERC20 METADATA
    // =====================================================================

    /// @notice Token name
    string public constant name = "Staked Degenerus Stonk";

    /// @notice Token symbol
    string public constant symbol = "sDGNRS";

    /// @notice Token decimals
    uint8 public constant decimals = 18;

    // =====================================================================
    //                          ERC20 STATE
    // =====================================================================

    /// @notice Total supply of sDGNRS tokens
    uint256 public totalSupply;

    /// @notice Token balance for each address
    mapping(address => uint256) public balanceOf;

    // =====================================================================
    //                          POOL STATE
    // =====================================================================

    /// @notice Enumeration of reward pools
    enum Pool {
        Whale,
        Affiliate,
        Lootbox,
        Reward,
        Earlybird
    }

    /// @notice Balances for each reward pool
    uint256[5] private poolBalances;

    // =====================================================================
    //                          CONSTANTS
    // =====================================================================

    /// @notice Initial supply (1 trillion tokens)
    uint256 private constant INITIAL_SUPPLY = 1_000_000_000_000 * 1e18;

    /// @dev Basis points denominator (100%)
    uint16 private constant BPS_DENOM = 10_000;

    /// @dev Creator allocation (20%)
    uint16 private constant CREATOR_BPS = 2000;

    /// @dev Non-creator pool distribution (BPS of total supply).
    uint16 private constant WHALE_POOL_BPS = 1000;
    uint16 private constant AFFILIATE_POOL_BPS = 3500;
    uint16 private constant LOOTBOX_POOL_BPS = 2000;
    uint16 private constant REWARD_POOL_BPS = 500;
    uint16 private constant EARLYBIRD_POOL_BPS = 1000;

    /// @dev Game contract reference for player actions and claimable queries
    IDegenerusGamePlayer private constant game = IDegenerusGamePlayer(ContractAddresses.GAME);

    /// @dev BURNIE token reference for payout accounting
    IDegenerusCoinPlayer private constant coin = IDegenerusCoinPlayer(ContractAddresses.COIN);
    /// @dev Coinflip contract for claimable BURNIE withdrawals during burns
    IBurnieCoinflipPlayer private constant coinflip =
        IBurnieCoinflipPlayer(ContractAddresses.COINFLIP);

    /// @dev stETH token reference
    IStETH private constant steth = IStETH(ContractAddresses.STETH_TOKEN);

    // =====================================================================
    //                          MODIFIERS
    // =====================================================================

    /// @dev Restricts function to game contract only
    modifier onlyGame() {
        if (msg.sender != ContractAddresses.GAME) revert Unauthorized();
        _;
    }



    // =====================================================================
    //                          CONSTRUCTOR
    // =====================================================================

    /// @notice Initializes token supply, distributes to pools, and claims whale pass for sDGNRS
    /// @dev Mints creator allocation to DGNRS wrapper address and pool allocations to this contract
    constructor() {
        uint256 creatorAmount = (INITIAL_SUPPLY * CREATOR_BPS) / BPS_DENOM;
        uint256 whaleAmount = (INITIAL_SUPPLY * WHALE_POOL_BPS) / BPS_DENOM;
        uint256 earlybirdAmount = (INITIAL_SUPPLY * EARLYBIRD_POOL_BPS) / BPS_DENOM;
        uint256 affiliateAmount = (INITIAL_SUPPLY * AFFILIATE_POOL_BPS) / BPS_DENOM;
        uint256 lootboxAmount = (INITIAL_SUPPLY * LOOTBOX_POOL_BPS) / BPS_DENOM;
        uint256 rewardAmount = (INITIAL_SUPPLY * REWARD_POOL_BPS) / BPS_DENOM;
        uint256 totalAllocated = creatorAmount + whaleAmount + earlybirdAmount + affiliateAmount + lootboxAmount + rewardAmount;
        if (totalAllocated < INITIAL_SUPPLY) {
            uint256 dust;
            unchecked {
                dust = INITIAL_SUPPLY - totalAllocated;
            }
            lootboxAmount += dust;
        }
        uint256 poolTotal =
            whaleAmount + earlybirdAmount + affiliateAmount + lootboxAmount + rewardAmount;

        _mint(ContractAddresses.DGNRS, creatorAmount);
        _mint(address(this), poolTotal);

        poolBalances[uint8(Pool.Whale)] = whaleAmount;
        poolBalances[uint8(Pool.Affiliate)] = affiliateAmount;
        poolBalances[uint8(Pool.Lootbox)] = lootboxAmount;
        poolBalances[uint8(Pool.Reward)] = rewardAmount;
        poolBalances[uint8(Pool.Earlybird)] = earlybirdAmount;

        game.claimWhalePass(address(0));
        game.setAfKingMode(
            address(0),
            true,
            10 ether,
            0
        );
    }

    // =====================================================================
    //                          WRAPPER FUNCTIONS
    // =====================================================================

    /// @notice Transfer sDGNRS from the wrapper to a recipient (wrapper only)
    /// @dev Called by DGNRS contract when creator unwraps DGNRS to soulbound sDGNRS.
    ///      Direct balance manipulation avoids modifying _transfer authorization.
    /// @param to Recipient address
    /// @param amount Amount to transfer
    /// @custom:reverts Unauthorized If caller is not DGNRS contract
    /// @custom:reverts ZeroAddress If to is zero address
    /// @custom:reverts Insufficient If wrapper balance is insufficient
    function wrapperTransferTo(address to, uint256 amount) external {
        if (msg.sender != ContractAddresses.DGNRS) revert Unauthorized();
        if (to == address(0)) revert ZeroAddress();
        uint256 bal = balanceOf[ContractAddresses.DGNRS];
        if (amount > bal) revert Insufficient();
        unchecked {
            balanceOf[ContractAddresses.DGNRS] = bal - amount;
            balanceOf[to] += amount;
        }
        emit Transfer(ContractAddresses.DGNRS, to, amount);
    }

    // =====================================================================
    //                          PLAYER ACTIONS
    // =====================================================================

    /// @notice Advance the game on behalf of sDGNRS
    function gameAdvance() external {
        game.advanceGame();
    }

    /// @notice Claim whale pass on behalf of sDGNRS
    function gameClaimWhalePass() external {
        game.claimWhalePass(address(0));
    }

    /// @notice Resolve pending coinflips without claiming BURNIE out
    /// @dev Advances the flip cursor, compounds auto-rebuy carry, records BAF score.
    ///      Keeps all BURNIE in the flip system — nothing is withdrawn.
    function resolveCoinflips() external {
        coinflip.claimCoinflips(address(0), 0);
    }

    // =====================================================================
    //                          DEPOSITS (Game Only)
    // =====================================================================

    /// @notice Receive ETH deposit from game contract
    /// @dev Only callable by game contract. Adds ETH to reserve without minting new tokens.
    /// @custom:reverts Unauthorized If caller is not game contract
    receive() external payable onlyGame {
        emit Deposit(msg.sender, msg.value, 0, 0);
    }

    /// @notice Receive stETH deposit from game contract
    /// @dev Only callable by game contract. Transfers stETH from caller and adds to reserve.
    /// @param amount Amount of stETH to deposit
    /// @custom:reverts Unauthorized If caller is not game contract
    /// @custom:reverts TransferFailed If stETH transfer fails
    function depositSteth(uint256 amount) external onlyGame {
        if (!steth.transferFrom(msg.sender, address(this), amount)) revert TransferFailed();
        emit Deposit(msg.sender, 0, amount, 0);
    }

    // =====================================================================
    //                          POOL SPENDING (Game Only)
    // =====================================================================

    /// @notice Get remaining balance for a reward pool
    /// @param pool Pool identifier
    /// @return Remaining pool balance
    function poolBalance(Pool pool) external view returns (uint256) {
        return poolBalances[_poolIndex(pool)];
    }

    /// @notice Transfer DGNRS from a reward pool to a recipient
    /// @dev Only callable by game contract. Transfers up to available balance if requested amount exceeds pool.
    /// @param pool Pool identifier
    /// @param to Recipient address
    /// @param amount Requested amount of DGNRS to transfer
    /// @return transferred Actual amount transferred (may be less than requested if pool depleted)
    /// @custom:reverts Unauthorized If caller is not game contract
    /// @custom:reverts ZeroAddress If to is zero address
    function transferFromPool(Pool pool, address to, uint256 amount) external onlyGame returns (uint256 transferred) {
        if (amount == 0) return 0;
        if (to == address(0)) revert ZeroAddress();
        uint8 idx = _poolIndex(pool);
        uint256 available = poolBalances[idx];
        if (available == 0) return 0;
        if (amount > available) {
            amount = available;
        }
        unchecked {
            poolBalances[idx] = available - amount;
            balanceOf[address(this)] -= amount;
            balanceOf[to] += amount;
        }
        emit Transfer(address(this), to, amount);
        emit PoolTransfer(pool, to, amount);
        return amount;
    }

    /// @notice Transfer DGNRS between two reward pools
    /// @dev Only callable by game contract. No token movement — just rebalances internal pool accounting.
    /// @param from Source pool
    /// @param to Destination pool
    /// @param amount Requested amount to move
    /// @return transferred Actual amount transferred (may be less if source pool has insufficient balance)
    function transferBetweenPools(Pool from, Pool to, uint256 amount) external onlyGame returns (uint256 transferred) {
        if (amount == 0) return 0;
        uint8 fromIdx = _poolIndex(from);
        uint8 toIdx = _poolIndex(to);
        uint256 available = poolBalances[fromIdx];
        if (available == 0) return 0;
        if (amount > available) {
            amount = available;
        }
        unchecked {
            poolBalances[fromIdx] = available - amount;
        }
        poolBalances[toIdx] += amount;
        emit PoolRebalance(from, to, amount);
        return amount;
    }

    /// @notice Burn all undistributed pool tokens at game over
    /// @dev Only callable by game contract. Burns this contract's own balance.
    function burnRemainingPools() external onlyGame {
        uint256 bal = balanceOf[address(this)];
        if (bal == 0) return;
        unchecked {
            balanceOf[address(this)] = 0;
            totalSupply -= bal;
        }
        emit Transfer(address(this), address(0), bal);
    }

    // =====================================================================
    //                          BURN (Public)
    // =====================================================================

    /// @notice Burn sDGNRS to claim proportional share of backing assets
    /// @dev BURNIE paid from balance + coinflip claimables. Prioritizes ETH over stETH.
    /// @param amount Amount of sDGNRS to burn
    /// @return ethOut ETH received
    /// @return stethOut stETH received
    /// @return burnieOut BURNIE received
    function burn(
        uint256 amount
    ) external returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {
        address player = msg.sender;
        uint256 bal = balanceOf[player];
        if (amount == 0 || amount > bal) revert Insufficient();
        uint256 supplyBefore = totalSupply;

        uint256 ethBal = address(this).balance;
        uint256 stethBal = steth.balanceOf(address(this));
        uint256 claimableEth = _claimableWinnings();
        uint256 totalMoney = ethBal + stethBal + claimableEth;
        uint256 totalValueOwed = (totalMoney * amount) / supplyBefore;

        uint256 burnieBal = coin.balanceOf(address(this));
        uint256 claimableBurnie = coinflip.previewClaimCoinflips(address(this));
        uint256 totalBurnie = burnieBal + claimableBurnie;
        burnieOut = (totalBurnie * amount) / supplyBefore;

        unchecked {
            balanceOf[player] = bal - amount;
            totalSupply -= amount;
        }
        emit Transfer(player, address(0), amount);

        if (totalValueOwed > ethBal && claimableEth != 0) {
            game.claimWinnings(address(0));
            ethBal = address(this).balance;
            stethBal = steth.balanceOf(address(this));
        }

        if (totalValueOwed <= ethBal) {
            ethOut = totalValueOwed;
        } else {
            ethOut = ethBal;
            stethOut = totalValueOwed - ethOut;
            if (stethOut > stethBal) revert Insufficient();
        }

        uint256 remainingBurnie = burnieOut;
        if (remainingBurnie != 0) {
            uint256 payBal = remainingBurnie <= burnieBal ? remainingBurnie : burnieBal;
            if (payBal != 0) {
                remainingBurnie -= payBal;
                if (!coin.transfer(player, payBal)) revert TransferFailed();
            }
            if (remainingBurnie != 0) {
                coinflip.claimCoinflips(address(0), remainingBurnie);
                if (!coin.transfer(player, remainingBurnie)) revert TransferFailed();
            }
        }

        if (stethOut > 0) {
            if (!steth.transfer(player, stethOut)) revert TransferFailed();
        }

        if (ethOut > 0) {
            (bool success, ) = player.call{value: ethOut}("");
            if (!success) revert TransferFailed();
        }

        emit Burn(player, amount, ethOut, stethOut, burnieOut);
    }

    // =====================================================================
    //                          VIEW FUNCTIONS
    // =====================================================================

    /// @notice Preview ETH, stETH, and BURNIE output for burning sDGNRS
    /// @dev Reflects ETH-preferential payout logic using current balances and claimables.
    ///      BURNIE includes claimable coinflip withdrawals.
    /// @param amount Amount of sDGNRS to burn
    /// @return ethOut ETH that would be received
    /// @return stethOut stETH that would be received
    /// @return burnieOut BURNIE that would be received
    function previewBurn(uint256 amount) external view returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {
        uint256 supply = totalSupply;
        if (amount == 0 || amount > supply) return (0, 0, 0);

        uint256 ethBal = address(this).balance;
        uint256 stethBal = steth.balanceOf(address(this));
        uint256 claimableEth = _claimableWinnings();
        uint256 totalMoney = ethBal + stethBal + claimableEth;
        uint256 totalValueOwed = (totalMoney * amount) / supply;

        uint256 ethAvailable = ethBal + claimableEth;
        if (totalValueOwed <= ethAvailable) {
            ethOut = totalValueOwed;
        } else {
            ethOut = ethAvailable;
            stethOut = totalValueOwed - ethOut;
        }

        uint256 burnieBal = coin.balanceOf(address(this));
        uint256 claimableBurnie = coinflip.previewClaimCoinflips(address(this));
        uint256 totalBurnie = burnieBal + claimableBurnie;
        burnieOut = (totalBurnie * amount) / supply;
    }


    /// @notice Get BURNIE backing (balance + claimable coinflips)
    /// @return BURNIE backing value
    function burnieReserve() external view returns (uint256) {
        uint256 burnieBal = coin.balanceOf(address(this));
        uint256 claimableBurnie = coinflip.previewClaimCoinflips(address(this));
        return burnieBal + claimableBurnie;
    }

    // =====================================================================
    //                          INTERNAL HELPERS
    // =====================================================================

    /// @dev Get claimable game winnings, accounting for dust (returns 0 if stored <= 1)
    /// @return claimable Claimable winnings minus 1 wei dust
    function _claimableWinnings() private view returns (uint256 claimable) {
        uint256 stored = game.claimableWinningsOf(address(this));
        if (stored <= 1) return 0;
        return stored - 1;
    }

    /// @dev Convert Pool enum to array index
    /// @param pool Pool enum value
    /// @return Index into poolBalances array
    function _poolIndex(Pool pool) private pure returns (uint8) {
        return uint8(pool);
    }


    /// @dev Internal mint implementation
    /// @param to Recipient address
    /// @param amount Amount to mint
    function _mint(address to, uint256 amount) private {
        if (to == address(0)) revert ZeroAddress();
        unchecked {
            totalSupply += amount;
            balanceOf[to] += amount;
        }
        emit Transfer(address(0), to, amount);
    }


}
