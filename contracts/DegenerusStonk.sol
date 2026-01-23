// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ContractAddresses} from "./ContractAddresses.sol";
import {MintPaymentKind} from "./interfaces/IDegenerusGame.sol";
import {IStETH} from "./interfaces/IStETH.sol";

interface IDegenerusGamePlayer {
    function advanceGame(uint32 cap) external;
    function mintPrice() external view returns (uint256);
    function setAfKingMode(
        address player,
        bool enabled,
        uint256 ethKeepMultiple,
        uint256 coinKeepMultiple
    ) external;
    function purchase(
        address buyer,
        uint256 gamepieceQuantity,
        uint256 ticketQuantity,
        uint256 lootBoxAmount,
        bytes32 affiliateCode,
        MintPaymentKind payKind
    ) external payable;
    function openLootBox(address player, uint48 lootboxIndex) external;
    function claimWinnings(address player) external;
    function claimWinningsStethFirst() external;
    function claimWhalePass(address player) external;
    function claimableWinningsOf(address player) external view returns (uint256);
    function isOperatorApproved(address owner, address operator) external view returns (bool);
}

interface IDegenerusCoinPlayer {
    function depositCoinflip(address player, uint256 amount) external;
    function decimatorBurn(address player, uint256 amount) external;
    function claimCoinflips(address player, uint256 amount) external returns (uint256 claimed);
    function previewClaimCoinflips(address player) external view returns (uint256 mintable);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

/**
 * @title DegenerusStonk (DGNRS)
 * @notice Standalone token backed by ETH, stETH, and BURNIE reserves
 * @dev Receives ETH/stETH from game distributions; rewards are distributed from pre-minted pools
 *
 * ARCHITECTURE:
 * - Receives ETH deposits from game distributions
 * - Receives stETH deposits from game distributions
 * - Can receive virtual BURNIE allowance via vaultEscrow()
 * - Pre-minted supply split into creator allocation + reward pools
 * - Game distributes DGNRS to players by drawing down pools
 * - Users burn DGNRS to claim proportional ETH + stETH + BURNIE
 */
contract DegenerusStonk {
    // =====================================================================
    //                              ERRORS
    // =====================================================================
    error Unauthorized();
    error Insufficient();
    error ZeroAddress();
    error TransferFailed();
    error InvalidPool();
    error NotHolder();
    error ActionAlreadyUsed();
    error ActionLimitExceeded();
    error NotApproved();

    // =====================================================================
    //                              EVENTS
    // =====================================================================
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);
    event Burn(address indexed from, uint256 amount, uint256 ethOut, uint256 stethOut, uint256 burnieOut);
    event Deposit(address indexed from, uint256 ethAmount, uint256 stethAmount, uint256 burnieVirtualAmount);
    event PoolTransfer(Pool indexed pool, address indexed to, uint256 amount);

    // =====================================================================
    //                          ERC20 METADATA
    // =====================================================================
    string public constant name = "Degenerus Stonk";
    string public constant symbol = "DGNRS";
    uint8 public constant decimals = 18;

    // =====================================================================
    //                          ERC20 STATE
    // =====================================================================
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // =====================================================================
    //                          RESERVES
    // =====================================================================
    /// @notice ETH backing for DGNRS tokens
    uint256 public ethReserve;

    /// @notice stETH backing for DGNRS tokens
    uint256 public stethReserve;

    /// @notice Virtual BURNIE mint allowance (like vault's vaultMintAllowance)
    /// @dev This is not actual BURNIE tokens, but allowance to mint from COIN contract
    uint256 public vaultMintAllowance;

    // =====================================================================
    //                          POOL STATE
    // =====================================================================
    enum Pool {
        Exterminator,
        Whale,
        Affiliate,
        Lootbox,
        Reward,
        Earlybird
    }

    uint256[6] private poolBalances;

    // =====================================================================
    //                          CONSTANTS
    // =====================================================================
    /// @notice Initial supply (1 trillion), split between creator and reward pools
    uint256 private constant INITIAL_SUPPLY = 1_000_000_000_000 * 1e18;

    uint16 private constant BPS_DENOM = 10_000;
    uint16 private constant CREATOR_BPS = 2000;
    uint16 private constant EXTERMINATOR_POOL_BPS = 1000;
    uint16 private constant WHALE_POOL_BPS = 1000;
    uint16 private constant EARLYBIRD_POOL_BPS = 1000;
    uint16 private constant AFFILIATE_POOL_BPS = 3000;
    uint16 private constant LOOTBOX_POOL_BPS = 1000;
    uint16 private constant REWARD_POOL_BPS = 1000;
    uint48 private constant JACKPOT_RESET_TIME = 82620;
    bytes32 private constant AFFILIATE_CODE_VAULT = bytes32("VAULT");

    mapping(address => uint48) private lastActionDay;

    /// @dev Game contract reference (player actions + claimable queries).
    IDegenerusGamePlayer private constant game = IDegenerusGamePlayer(ContractAddresses.GAME);

    /// @dev BURNIE token reference (coinflip/decimator + balances).
    IDegenerusCoinPlayer private constant coin = IDegenerusCoinPlayer(ContractAddresses.COIN);

    /// @dev stETH token reference
    IStETH private constant steth = IStETH(ContractAddresses.STETH_TOKEN);

    // =====================================================================
    //                          MODIFIERS
    // =====================================================================
    modifier onlyGame() {
        if (msg.sender != ContractAddresses.GAME) revert Unauthorized();
        _;
    }

    modifier onlyCoin() {
        if (msg.sender != ContractAddresses.COIN) revert Unauthorized();
        _;
    }

    modifier onlyHolder() {
        if (balanceOf[msg.sender] == 0) revert NotHolder();
        _;
    }

    function _requireApproved(address player) private view {
        if (msg.sender != player && !game.isOperatorApproved(player, msg.sender)) {
            revert NotApproved();
        }
    }

    modifier oneActionPerDay() {
        uint48 day = _currentDayIndex();
        if (lastActionDay[msg.sender] == day) revert ActionAlreadyUsed();
        _;
        lastActionDay[msg.sender] = day;
    }

    // =====================================================================
    //                          CONSTRUCTOR
    // =====================================================================
    constructor() {
        uint256 creatorAmount = (INITIAL_SUPPLY * CREATOR_BPS) / BPS_DENOM;
        uint256 exterminatorAmount = (INITIAL_SUPPLY * EXTERMINATOR_POOL_BPS) / BPS_DENOM;
        uint256 whaleAmount = (INITIAL_SUPPLY * WHALE_POOL_BPS) / BPS_DENOM;
        uint256 earlybirdAmount = (INITIAL_SUPPLY * EARLYBIRD_POOL_BPS) / BPS_DENOM;
        uint256 affiliateAmount = (INITIAL_SUPPLY * AFFILIATE_POOL_BPS) / BPS_DENOM;
        uint256 rewardAmount = (INITIAL_SUPPLY * REWARD_POOL_BPS) / BPS_DENOM;
        uint256 lootboxAmount =
            INITIAL_SUPPLY -
                creatorAmount -
                exterminatorAmount -
                whaleAmount -
                earlybirdAmount -
                affiliateAmount -
                rewardAmount;
        uint256 poolTotal =
            exterminatorAmount +
            whaleAmount +
            earlybirdAmount +
            affiliateAmount +
            lootboxAmount +
            rewardAmount;

        _mint(ContractAddresses.CREATOR, creatorAmount);
        _mint(address(this), poolTotal);

        poolBalances[uint8(Pool.Exterminator)] = exterminatorAmount;
        poolBalances[uint8(Pool.Whale)] = whaleAmount;
        poolBalances[uint8(Pool.Affiliate)] = affiliateAmount;
        poolBalances[uint8(Pool.Lootbox)] = lootboxAmount;
        poolBalances[uint8(Pool.Reward)] = rewardAmount;
        poolBalances[uint8(Pool.Earlybird)] = earlybirdAmount;

        game.claimWhalePass(address(0));
        game.setAfKingMode(
            address(0),
            true,
            5 ether / ContractAddresses.COST_DIVISOR,
            0
        );
    }

    // =====================================================================
    //                          ERC20 FUNCTIONS
    // =====================================================================
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        // BurnieCoin is a trusted spender inside the ecosystem; skip allowance checks.
        if (msg.sender != ContractAddresses.COIN) {
            uint256 allowed = allowance[from][msg.sender];
            if (allowed != type(uint256).max) {
                if (allowed < amount) revert Insufficient();
                unchecked {
                    allowance[from][msg.sender] = allowed - amount;
                }
                emit Approval(from, msg.sender, allowance[from][msg.sender]);
            }
        }
        _transfer(from, to, amount);
        return true;
    }

    // =====================================================================
    //                          PLAYER ACTIONS
    // =====================================================================
    function gameAdvance(uint32 cap) external onlyHolder oneActionPerDay {
        game.advanceGame(cap);
    }

    function gamePurchase(
        uint256 ticketQuantity,
        uint256 lootBoxAmount,
        MintPaymentKind payKind
    ) external payable onlyHolder oneActionPerDay {
        uint256 priceWei = game.mintPrice();
        uint256 ticketCost = (priceWei * ticketQuantity) / 4;
        uint256 totalCost = ticketCost + lootBoxAmount;
        if (totalCost > _maxEthAction(msg.sender)) revert ActionLimitExceeded();
        game.purchase{value: msg.value}(
            address(0),
            0,
            ticketQuantity,
            lootBoxAmount,
            AFFILIATE_CODE_VAULT,
            payKind
        );
    }

    function gameOpenLootBox(uint48 lootboxIndex) external onlyHolder oneActionPerDay {
        game.openLootBox(address(0), lootboxIndex);
    }

    function gameClaimWinnings() external onlyHolder oneActionPerDay {
        game.claimWinningsStethFirst();
    }

    function gameClaimWhalePass() external onlyHolder oneActionPerDay {
        game.claimWhalePass(address(0));
    }

    function coinDepositCoinflip(uint256 amount) external onlyHolder oneActionPerDay {
        if (amount > _maxBurnieAction(msg.sender)) revert ActionLimitExceeded();
        coin.depositCoinflip(address(0), amount);
    }

    function coinDecimatorBurn(uint256 amount) external onlyHolder oneActionPerDay {
        if (amount > _maxBurnieAction(msg.sender)) revert ActionLimitExceeded();
        coin.decimatorBurn(address(0), amount);
    }

    // =====================================================================
    //                          DEPOSITS (Game Only)
    // =====================================================================

    /// @notice Receive ETH deposit (adds to reserve, no minting)
    /// @dev Game contract only. Called when game sends ETH to DGNRS reserves.
    receive() external payable onlyGame {
        unchecked {
            ethReserve += msg.value;
        }
        emit Deposit(msg.sender, msg.value, 0, 0);
    }

    /// @notice Receive stETH deposit (adds to reserve, no minting)
    /// @dev Game contract only. Called when game sends stETH to DGNRS reserves.
    /// @param amount Amount of stETH to deposit
    function depositSteth(uint256 amount) external onlyGame {
        unchecked {
            stethReserve += amount;
        }
        if (!steth.transferFrom(msg.sender, address(this), amount)) revert TransferFailed();
        emit Deposit(msg.sender, 0, amount, 0);
    }

    /// @notice Escrow virtual BURNIE mint allowance (like vault's vaultEscrow)
    /// @dev Called by COIN contract when it escrows virtual BURNIE to DGNRS.
    /// @param amount Amount of BURNIE mint allowance to escrow
    function vaultEscrow(uint256 amount) external onlyCoin {
        unchecked {
            vaultMintAllowance += amount;
        }
        emit Deposit(msg.sender, 0, 0, amount);
    }

    // =====================================================================
    //                          POOL SPENDING (Game Only)
    // =====================================================================

    /// @notice Return remaining balance for a pool.
    /// @param pool Pool identifier.
    /// @return Remaining pool balance.
    function poolBalance(Pool pool) external view returns (uint256) {
        return poolBalances[_poolIndex(pool)];
    }

    /// @notice Transfer DGNRS from a pool to a recipient.
    /// @param pool Pool identifier.
    /// @param to Recipient address.
    /// @param amount Amount of DGNRS to transfer.
    /// @return transferred Amount actually transferred.
    function transferFromPool(Pool pool, address to, uint256 amount) external onlyGame returns (uint256 transferred) {
        if (amount == 0) return 0;
        uint8 idx = _poolIndex(pool);
        uint256 available = poolBalances[idx];
        if (available == 0) return 0;
        if (amount > available) {
            amount = available;
        }
        unchecked {
            poolBalances[idx] = available - amount;
        }
        _transfer(address(this), to, amount);
        emit PoolTransfer(pool, to, amount);
        return amount;
    }

    // =====================================================================
    //                          BURN (Public)
    // =====================================================================

    /// @notice Burn DGNRS to claim proportional balances + claimables.
    /// @dev Includes claimable ETH (GAME) and claimable BURNIE (COIN) in the share.
    ///      Claims from GAME/COIN only if needed; prioritizes ETH over stETH.
    /// @param player Player address to burn for (address(0) = msg.sender).
    /// @param amount Amount of DGNRS to burn
    /// @return ethOut ETH received
    /// @return stethOut stETH received
    /// @return burnieOut BURNIE received
    function burn(
        address player,
        uint256 amount
    ) external returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {
        if (player == address(0)) {
            player = msg.sender;
        } else if (player != msg.sender) {
            _requireApproved(player);
        }
        return _burnFor(player, amount);
    }

    function _burnFor(
        address player,
        uint256 amount
    ) private returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {
        if (amount == 0 || amount > balanceOf[player]) revert Insufficient();

        uint256 supplyBefore = totalSupply;

        uint256 ethBal = address(this).balance;
        uint256 stethBal = steth.balanceOf(address(this));
        uint256 claimableEth = _claimableWinnings();
        uint256 totalMoney = ethBal + stethBal + claimableEth;
        uint256 totalValueOwed = (totalMoney * amount) / supplyBefore;

        uint256 burnieBal = coin.balanceOf(address(this));
        uint256 claimableBurnie = coin.previewClaimCoinflips(address(this));
        uint256 totalBurnie = burnieBal + claimableBurnie;
        burnieOut = (totalBurnie * amount) / supplyBefore;

        _burn(player, amount);

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

        if (burnieOut > burnieBal) {
            uint256 needed = burnieOut - burnieBal;
            coin.claimCoinflips(address(0), needed);
            burnieBal = coin.balanceOf(address(this));
            if (burnieOut > burnieBal) revert Insufficient();
        }

        if (ethOut > 0) {
            (bool success, ) = player.call{value: ethOut}("");
            if (!success) revert TransferFailed();
        }
        if (stethOut > 0) {
            if (!steth.transfer(player, stethOut)) revert TransferFailed();
        }
        if (burnieOut > 0) {
            if (!coin.transfer(player, burnieOut)) revert TransferFailed();
        }

        emit Burn(player, amount, ethOut, stethOut, burnieOut);
    }

    // =====================================================================
    //                          VIEW FUNCTIONS
    // =====================================================================

    /// @notice Preview ETH, stETH, and BURNIE output for burning DGNRS
    /// @dev Reflects the ETH-preferential payout logic using balances + claimables.
    /// @param amount Amount of DGNRS to burn
    /// @return ethOut ETH that would be received
    /// @return stethOut stETH that would be received
    /// @return burnieOut BURNIE that would be received
    function previewBurn(uint256 amount) external view returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {
        if (amount == 0 || amount > totalSupply) return (0, 0, 0);

        uint256 ethBal = address(this).balance;
        uint256 stethBal = steth.balanceOf(address(this));
        uint256 claimableEth = _claimableWinnings();
        uint256 totalMoney = ethBal + stethBal + claimableEth;
        uint256 totalValueOwed = (totalMoney * amount) / totalSupply;

        uint256 ethAvailable = ethBal + claimableEth;
        if (totalValueOwed <= ethAvailable) {
            ethOut = totalValueOwed;
        } else {
            ethOut = ethAvailable;
            stethOut = totalValueOwed - ethOut;
        }

        uint256 burnieBal = coin.balanceOf(address(this));
        uint256 claimableBurnie = coin.previewClaimCoinflips(address(this));
        uint256 totalBurnie = burnieBal + claimableBurnie;
        burnieOut = (totalBurnie * amount) / totalSupply;
    }

    /// @notice Get total backing value (ETH + stETH + virtual BURNIE)
    /// @return Total backing (ETH reserve + stETH reserve + BURNIE allowance)
    function totalBacking() external view returns (uint256) {
        return ethReserve + stethReserve + vaultMintAllowance;
    }

    /// @notice Get BURNIE reserve (alias for vaultMintAllowance for compatibility)
    /// @return Virtual BURNIE reserve
    function burnieReserve() external view returns (uint256) {
        return vaultMintAllowance;
    }

    /// @notice Get stETH reserve
    /// @return stETH reserve
    function getStethReserve() external view returns (uint256) {
        return stethReserve;
    }

    // =====================================================================
    //                          INTERNAL HELPERS
    // =====================================================================
    function _currentDayIndex() private view returns (uint48) {
        uint48 currentDayBoundary = uint48((block.timestamp - JACKPOT_RESET_TIME) / 1 days);
        return currentDayBoundary - ContractAddresses.DEPLOY_DAY_BOUNDARY + 1;
    }

    function _holderClaimableValues(
        address holder
    ) private view returns (uint256 ethValue, uint256 burnieValue) {
        uint256 supply = totalSupply;
        uint256 balance = balanceOf[holder];
        if (supply == 0 || balance == 0) return (0, 0);

        uint256 ethBal = address(this).balance;
        uint256 stethBal = steth.balanceOf(address(this));
        uint256 claimableEth = _claimableWinnings();
        uint256 totalMoney = ethBal + stethBal + claimableEth;
        ethValue = (totalMoney * balance) / supply;

        uint256 burnieBal = coin.balanceOf(address(this));
        uint256 claimableBurnie = coin.previewClaimCoinflips(address(this));
        uint256 totalBurnie = burnieBal + claimableBurnie;
        burnieValue = (totalBurnie * balance) / supply;
    }

    function _maxEthAction(address holder) private view returns (uint256 maxEth) {
        (uint256 ethValue, ) = _holderClaimableValues(holder);
        return ethValue * 10;
    }

    function _maxBurnieAction(address holder) private view returns (uint256 maxBurnie) {
        (, uint256 burnieValue) = _holderClaimableValues(holder);
        return burnieValue * 10;
    }

    function _claimableWinnings() private view returns (uint256 claimable) {
        uint256 stored = game.claimableWinningsOf(address(this));
        if (stored <= 1) return 0;
        return stored - 1;
    }

    function _poolIndex(Pool pool) private pure returns (uint8) {
        uint8 idx = uint8(pool);
        if (idx > uint8(Pool.Earlybird)) revert InvalidPool();
        return idx;
    }

    function _transfer(address from, address to, uint256 amount) private {
        if (to == address(0)) revert ZeroAddress();
        if (from == address(0)) revert ZeroAddress();
        uint256 bal = balanceOf[from];
        if (amount > bal) revert Insufficient();
        unchecked {
            balanceOf[from] = bal - amount;
            balanceOf[to] += amount;
        }
        emit Transfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) private {
        if (to == address(0)) revert ZeroAddress();
        totalSupply += amount;
        unchecked {
            balanceOf[to] += amount;
        }
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) private {
        uint256 bal = balanceOf[from];
        if (amount > bal) revert Insufficient();
        unchecked {
            balanceOf[from] = bal - amount;
            totalSupply -= amount;
        }
        emit Transfer(from, address(0), amount);
    }
}
