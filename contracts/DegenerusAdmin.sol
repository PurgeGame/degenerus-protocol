// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {ContractAddresses} from "./ContractAddresses.sol";

/**
 * @title DegenerusAdmin
 * @author Burnie Degenerus
 * @notice Central administration contract for the Degenerus GAME ecosystem.
 *
 * @dev ARCHITECTURE OVERVIEW
 * -----------------------------------------------------------------------------
 * This contract serves as the single point of authority for:
 *   1. VRF subscription ownership and management
 *   2. Emergency recovery during VRF failures
 *   3. LINK token donation handling with reward multipliers
 *   4. LINK/ETH price feed management for reward valuation
 *
 * DEPLOYMENT:
 *   - Deploy with no constructor parameters (VRF config from ContractAddresses)
 *   - VRF subscription created and Game consumer configured atomically on deployment
 *   - No post-deployment setup needed
 *
 * OWNERSHIP MODEL:
 *   - Owner is anyone holding >50.1% of DGVE supply (vault governance token)
 *   - No single-address owner; ownership is transferable via DGVE market
 *
 * VRF SUBSCRIPTION LIFECYCLE:
 *   1. Created atomically during constructor call
 *   2. Consumer (Game contract) added automatically during construction
 *   3. LINK funding via onTokenTransfer (ERC-677)
 *   4. Emergency recovery if stalled 3+ days (see emergencyRecover)
 *   5. Shutdown after GAME-over with LINK refund
 *
 */

// =============================================================================
// EXTERNAL INTERFACES
// =============================================================================

/// @dev Minimal VRF coordinator surface for subscription management.
///      Only the functions needed for admin operations are included.
interface IVRFCoordinatorV2_5Owner {
    /// @notice Add a consumer contract to a VRF subscription.
    /// @param subId The subscription ID to add the consumer to.
    /// @param consumer The address of the consumer contract.
    function addConsumer(uint256 subId, address consumer) external;

    /// @notice Cancel a VRF subscription and refund remaining LINK.
    /// @param subId The subscription ID to cancel.
    /// @param to The address to receive the LINK refund.
    function cancelSubscription(uint256 subId, address to) external;

    /// @notice Create a new VRF subscription.
    /// @return subId The newly created subscription ID.
    function createSubscription() external returns (uint256 subId);

    /// @notice Get subscription details including balance and consumers.
    /// @param subId The subscription ID to query.
    /// @return balance LINK balance in the subscription.
    /// @return nativeBalance Native token balance (if applicable).
    /// @return reqCount Number of requests made.
    /// @return owner The subscription owner.
    /// @return consumers Array of consumer addresses.
    function getSubscription(
        uint256 subId
    )
        external
        view
        returns (
            uint96 balance,
            uint96 nativeBalance,
            uint64 reqCount,
            address owner,
            address[] memory consumers
        );
}

/// @dev Game contract admin interface (VRF + liquidity).
interface IDegenerusGameAdmin {
    /// @notice Check if RNG has been stalled for 3+ days (enables emergency recovery).
    function rngStalledForThreeDays() external view returns (bool);

    /// @notice Current game phase (false=purchase, true=jackpot).
    function jackpotPhase() external view returns (bool);

    /// @notice Terminal gameover flag.
    function gameOver() external view returns (bool);

    /// @notice Emergency update of VRF configuration during recovery.
    /// @param newCoordinator New VRF coordinator address.
    /// @param newSubId New subscription ID.
    /// @param newKeyHash New key hash for the coordinator.
    function updateVrfCoordinatorAndSub(
        address newCoordinator,
        uint256 newSubId,
        bytes32 newKeyHash
    ) external;

    /// @notice Initial VRF wiring during setup.
    function wireVrf(
        address coordinator_,
        uint256 subId,
        bytes32 keyHash_
    ) external;

    /// @notice Swap owner ETH for GAME-held stETH (1:1 exchange).
    /// @param recipient Address to receive the stETH.
    /// @param amount Amount of ETH/stETH to swap.
    function adminSwapEthForStEth(
        address recipient,
        uint256 amount
    ) external payable;

    /// @notice Stake GAME-held ETH into stETH via Lido.
    /// @param amount Amount of ETH to stake.
    function adminStakeEthForStEth(uint256 amount) external;

    /// @notice Update lootbox RNG request threshold (wei).
    /// @param newThreshold New threshold in wei.
    function setLootboxRngThreshold(uint256 newThreshold) external;

    /// @notice Current ticket purchase info including live price.
    /// @return lvl Active ticket level (level+1 during purchase phase, level during jackpot phase; NOT the 0-indexed game level).
    /// @return qty Tickets sold at current level.
    /// @return cap Total tickets per level.
    /// @return jackpotWei Jackpot size in wei.
    /// @return priceWei Current ticket price in wei.
    function purchaseInfo()
        external
        view
        returns (
            uint256 lvl,
            uint256 qty,
            uint256 cap,
            uint256 jackpotWei,
            uint256 priceWei
        );
}

/// @dev LINK token interface (ERC-677 with transferAndCall).
interface ILinkTokenLike {
    function balanceOf(address account) external view returns (uint256);

    /// @notice Standard ERC20 transfer.
    /// @param to Recipient address.
    /// @param value Amount of LINK to transfer.
    /// @return success True if transfer succeeded.
    function transfer(
        address to,
        uint256 value
    ) external returns (bool success);

    /// @notice ERC-677 transfer with callback to recipient.
    /// @param to Recipient address (must implement onTokenTransfer).
    /// @param value Amount of LINK to transfer.
    /// @param data Additional data passed to the callback.
    /// @return success True if transfer and callback succeeded.
    function transferAndCall(
        address to,
        uint256 value,
        bytes calldata data
    ) external returns (bool success);
}

/// @dev Coin contract interface for LINK donation flip credits.
interface IDegenerusCoinLinkReward {
    /// @notice Credit flip stake to a player for LINK donation.
    /// @param player Address to credit.
    /// @param amount Amount of BURNIE to credit as flip stake (18 decimals).
    function creditLinkReward(address player, uint256 amount) external;
}

/// @dev Chainlink price feed interface (AggregatorV3).
interface IAggregatorV3 {
    /// @notice Get latest price data.
    /// @return roundId The round ID.
    /// @return answer The price (sign and decimals vary by feed).
    /// @return startedAt Timestamp when round started.
    /// @return updatedAt Timestamp when answer was updated.
    /// @return answeredInRound The round ID in which the answer was computed.
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    /// @notice Get the number of decimals in the answer.
    function decimals() external view returns (uint8);
}

/// @dev Vault interface for ownership check.
interface IDegenerusVaultOwner {
    /// @notice Check if account holds >50.1% of DGVE supply.
    function isVaultOwner(address account) external view returns (bool);
}

/**
 * @title DegenerusAdmin
 * @notice Central admin contract: owns the VRF subscription and wires VRF
 *         configuration for the GAME. Deployed using precomputed constants.
 */
contract DegenerusAdmin {
    // =========================================================================
    // CUSTOM ERRORS
    // =========================================================================
    // Using custom errors for gas efficiency and clear failure reasons.

    /// @dev Caller does not hold >50.1% of DGVE supply.
    error NotOwner();

    /// @dev Caller is not authorized for this operation (e.g., wrong token sender).
    error NotAuthorized();

    /// @dev A required address parameter was zero.
    error ZeroAddress();

    /// @dev VRF is not stalled; emergency recovery not allowed.
    error NotStalled();

    /// @dev Required component not yet wired.
    error NotWired();

    /// @dev VRF subscription doesn't exist.
    error NoSubscription();

    /// @dev Invalid amount (zero or mismatch).
    error InvalidAmount();

    /// @dev Game-over has started; operation not allowed.
    error GameOver();


    /// @dev Price feed is healthy; replacement not allowed.
    error FeedHealthy();

    /// @dev Price feed decimals do not match expected LINK/ETH decimals.
    error InvalidFeedDecimals();


    // =========================================================================
    // EVENTS
    // =========================================================================
    // Events provide an audit trail for all administrative actions.

    /// @notice Emitted when the VRF coordinator is updated.
    /// @param coordinator New coordinator address.
    /// @param subId Associated subscription ID.
    event CoordinatorUpdated(
        address indexed coordinator,
        uint256 indexed subId
    );

    /// @notice Emitted when a consumer is added to the VRF subscription.
    /// @param consumer Address of the newly added consumer.
    event ConsumerAdded(address indexed consumer);

    /// @notice Emitted when a new VRF subscription is created.
    /// @param subId The newly created subscription ID.
    event SubscriptionCreated(uint256 indexed subId);

    /// @notice Emitted when a VRF subscription is cancelled.
    /// @param subId The cancelled subscription ID.
    /// @param to Address receiving the LINK refund.
    event SubscriptionCancelled(uint256 indexed subId, address indexed to);

    /// @notice Emitted after emergency VRF recovery completes.
    /// @param newCoordinator New coordinator address.
    /// @param newSubId New subscription ID.
    /// @param fundedAmount LINK transferred to new subscription.
    event EmergencyRecovered(
        address indexed newCoordinator,
        uint256 indexed newSubId,
        uint256 fundedAmount
    );

    /// @notice Emitted when subscription is shutdown and LINK swept.
    /// @param subId The shutdown subscription ID.
    /// @param to Address receiving the LINK.
    /// @param sweptAmount LINK amount swept.
    event SubscriptionShutdown(
        uint256 indexed subId,
        address indexed to,
        uint256 sweptAmount
    );

    /// @notice Emitted when LINK donation credit is recorded.
    /// @param player Address receiving the credit.
    /// @param amount BURNIE amount credited.
    event LinkCreditRecorded(address indexed player, uint256 amount);

    /// @notice Emitted when LINK/ETH price feed is updated.
    /// @param feed New feed address (zero disables oracle).
    event LinkEthFeedUpdated(address indexed feed);

    // =========================================================================
    // PRECOMPUTED ADDRESSES
    // =========================================================================
    // Trusted external contracts wired from ContractAddresses (compile-time).

    IVRFCoordinatorV2_5Owner internal constant vrfCoordinator =
        IVRFCoordinatorV2_5Owner(ContractAddresses.VRF_COORDINATOR);
    IDegenerusGameAdmin internal constant gameAdmin =
        IDegenerusGameAdmin(ContractAddresses.GAME);
    ILinkTokenLike internal constant linkToken =
        ILinkTokenLike(ContractAddresses.LINK_TOKEN);
    IDegenerusCoinLinkReward internal constant coinLinkReward =
        IDegenerusCoinLinkReward(ContractAddresses.COIN);

    // =========================================================================
    // VRF STATE
    // =========================================================================
    // Chainlink VRF subscription management.

    /// @notice Current VRF coordinator address.
    /// @dev Can be updated during emergency recovery (stall-gated).
    address public coordinator;

    /// @notice Current VRF subscription ID.
    /// @dev Created atomically during constructor; can change during emergency recovery.
    uint256 public subscriptionId;

    /// @notice VRF key hash for the current coordinator.
    /// @dev Different coordinators may require different key hashes.
    bytes32 public vrfKeyHash;

    // =========================================================================
    // LINK REWARD STATE
    // =========================================================================

    /// @notice Chainlink LINK/ETH price feed address.
    /// @dev Zero address disables oracle-based valuation.
    ///      Only replaceable if current feed is unhealthy.
    ///      Assumes Chainlink LINK/ETH feed with 18 decimals (standard for this pair).
    address public linkEthPriceFeed;

    /// @dev BURNIE conversion constant: 1000 BURNIE = 1e21 base units (18 decimals).
    ///      Used to convert ETH-equivalent value to BURNIE credit amount.
    uint256 private constant PRICE_COIN_UNIT = 1000 ether;

    /// @dev Expected LINK/ETH feed decimals (Chainlink standard).
    uint8 private constant LINK_ETH_FEED_DECIMALS = 18;

    /// @dev Max staleness window before LINK/ETH feed is considered unhealthy.
    uint256 private constant LINK_ETH_MAX_STALE = 1 days;

    // =========================================================================
    // ACCESS CONTROL
    // =========================================================================

    /// @dev Vault contract for ownership check.
    IDegenerusVaultOwner private constant vault =
        IDegenerusVaultOwner(ContractAddresses.VAULT);

    /// @dev Restricts function to anyone holding >50.1% of DGVE.
    modifier onlyOwner() {
        if (!vault.isVaultOwner(msg.sender)) revert NotOwner();
        _;
    }

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    /// @notice Initialize admin contract and configure VRF on deployment.
    /// @dev Atomically creates new VRF subscription and wires the Game consumer.
    ///      VRF coordinator and keyHash are compile-time constants from ContractAddresses.
    constructor() {
        // Create new subscription
        uint256 subId = vrfCoordinator.createSubscription();

        // Store VRF config
        coordinator = ContractAddresses.VRF_COORDINATOR;
        subscriptionId = subId;
        vrfKeyHash = ContractAddresses.VRF_KEY_HASH;

        emit SubscriptionCreated(subId);
        emit CoordinatorUpdated(ContractAddresses.VRF_COORDINATOR, subId);

        // Add Game as consumer
        vrfCoordinator.addConsumer(subId, ContractAddresses.GAME);
        emit ConsumerAdded(ContractAddresses.GAME);
        // Wire Game's VRF config
        gameAdmin.wireVrf(
            ContractAddresses.VRF_COORDINATOR,
            subId,
            ContractAddresses.VRF_KEY_HASH
        );
    }

    // =========================================================================
    // PRICE FEED MANAGEMENT
    // =========================================================================

    /// @notice Configure the LINK/ETH price feed for LINK donation valuation.
    /// @dev Zero address disables oracle-based valuation (LINK donations earn no rewards).
    ///      Only replaceable if current feed is unhealthy (prevents unnecessary changes).
    ///
    ///      SECURITY NOTES:
    ///      - FeedHealthy guard prevents changing a working feed.
    ///      - Enforces 18 decimals (Chainlink LINK/ETH standard).
    ///      - Treats stale feeds (updatedAt too old) as unhealthy.
    ///      - Invalid feed data (answer <= 0) causes linkAmountToEth to return 0.
    ///
    /// @param feed New price feed address (zero to disable).
    function setLinkEthPriceFeed(address feed) external onlyOwner {
        address current = linkEthPriceFeed;
        // Only allow replacement if current feed is unhealthy or doesn't exist.
        if (_feedHealthy(current)) revert FeedHealthy();
        if (
            feed != address(0) &&
            IAggregatorV3(feed).decimals() != LINK_ETH_FEED_DECIMALS
        ) {
            revert InvalidFeedDecimals();
        }
        linkEthPriceFeed = feed;
        emit LinkEthFeedUpdated(feed);
    }

    // =========================================================================
    // LIQUIDITY MANAGEMENT
    // =========================================================================

    /// @notice Swap owner ETH for GAME-held stETH (1:1 exchange).
    /// @dev Allows owner to provide ETH liquidity in exchange for stETH yield.
    ///
    ///      SECURITY NOTES:
    ///      - msg.value must be non-zero.
    ///      - stETH sent to msg.sender (owner), not arbitrary address.
    ///      - Game contract validates the swap internally.
    function swapGameEthForStEth() external payable onlyOwner {
        if (msg.value == 0) revert InvalidAmount();
        gameAdmin.adminSwapEthForStEth{value: msg.value}(msg.sender, msg.value);
    }

    /// @notice Stake GAME-held ETH into stETH via Lido.
    /// @dev Converts idle ETH to yield-bearing stETH.
    /// @param amount Amount of ETH to stake.
    function stakeGameEthToStEth(uint256 amount) external onlyOwner {
        gameAdmin.adminStakeEthForStEth(amount);
    }

    /// @notice Update lootbox RNG request threshold (wei).
    function setLootboxRngThreshold(uint256 newThreshold) external onlyOwner {
        gameAdmin.setLootboxRngThreshold(newThreshold);
    }

    // =========================================================================
    // VRF EMERGENCY RECOVERY (Stall-Gated)
    // =========================================================================

    /// @notice Migrate to a new VRF coordinator/subscription after 3-day stall.
    /// @dev Emergency recovery path when Chainlink VRF becomes unavailable.
    ///
    ///      EXECUTION ORDER:
    ///      1. Verify 3-day stall via GAME.rngStalledForThreeDays()
    ///      2. Cancel old subscription (LINK refunds to this contract)
    ///      3. Create new subscription on new coordinator
    ///      4. Add GAME as consumer
    ///      5. Push new config to game
    ///      6. Transfer any LINK balance to new subscription
    ///
    ///      SECURITY NOTES:
    ///      - 3-day stall requirement prevents premature migration.
    ///      - try/catch on cancelSubscription handles edge cases.
    ///      - New coordinator/keyHash must be non-zero.
    ///      - Game is updated atomically.
    ///
    /// @param newCoordinator Address of the new VRF coordinator.
    /// @param newKeyHash Key hash for the new coordinator.
    /// @return newSubId The newly created subscription ID.
    function emergencyRecover(
        address newCoordinator,
        bytes32 newKeyHash
    ) external onlyOwner returns (uint256 newSubId) {
        if (subscriptionId == 0) revert NotWired();
        // SECURITY: Require provable 3-day VRF stall before allowing migration.
        if (!gameAdmin.rngStalledForThreeDays()) revert NotStalled();
        if (newCoordinator == address(0) || newKeyHash == bytes32(0))
            revert ZeroAddress();

        uint256 oldSub = subscriptionId;
        address oldCoord = coordinator;

        // Cancel old subscription to recover LINK.
        try
            IVRFCoordinatorV2_5Owner(oldCoord).cancelSubscription(
                oldSub,
                address(this)
            )
        {
            emit SubscriptionCancelled(oldSub, address(this));
        } catch {}
        // Create new subscription.
        coordinator = newCoordinator;
        newSubId = IVRFCoordinatorV2_5Owner(newCoordinator)
            .createSubscription();
        subscriptionId = newSubId;
        vrfKeyHash = newKeyHash;
        emit CoordinatorUpdated(newCoordinator, newSubId);
        emit SubscriptionCreated(newSubId);

        // Add consumers to new subscription.
        IVRFCoordinatorV2_5Owner(newCoordinator).addConsumer(
            newSubId,
            ContractAddresses.GAME
        );
        emit ConsumerAdded(ContractAddresses.GAME);
        // Push new config to GAME — must succeed to maintain consistency.
        gameAdmin.updateVrfCoordinatorAndSub(
            newCoordinator,
            newSubId,
            newKeyHash
        );

        // Transfer any LINK to new subscription.
        uint256 bal = linkToken.balanceOf(address(this));
        uint256 funded;
        if (bal != 0) {
            try
                linkToken.transferAndCall(
                    newCoordinator,
                    bal,
                    abi.encode(newSubId)
                )
            returns (bool ok) {
                if (ok) {
                    funded = bal;
                }
            } catch {}
        }

        emit EmergencyRecovered(newCoordinator, newSubId, funded);
    }

    /// @notice Cancel VRF subscription and sweep LINK to vault after GAME-over.
    /// @dev Only callable by the GAME contract (during handleFinalSweep).
    ///      Uses try/catch internally so the caller can safely fire-and-forget.
    ///
    ///      SECURITY NOTES:
    ///      - Only GAME contract can call (trusted, runs during final sweep).
    ///      - LINK refunded to VAULT address.
    ///      - Sets subscriptionId to 0 to prevent re-use.
    function shutdownVrf() external {
        if (msg.sender != ContractAddresses.GAME) revert NotAuthorized();
        uint256 subId = subscriptionId;
        if (subId == 0) return;

        subscriptionId = 0;
        address target = ContractAddresses.VAULT;

        // Cancel subscription; LINK refunds go to vault.
        try IVRFCoordinatorV2_5Owner(coordinator).cancelSubscription(subId, target) {
            emit SubscriptionCancelled(subId, target);
        } catch {}

        // Sweep any LINK sitting on this contract to vault.
        uint256 bal = linkToken.balanceOf(address(this));
        if (bal != 0) {
            try linkToken.transfer(target, bal) returns (bool ok) {
                if (ok) {
                    emit SubscriptionShutdown(subId, target, bal);
                    return;
                }
            } catch {}
        }

        emit SubscriptionShutdown(subId, target, 0);
    }

    // =========================================================================
    // LINK DONATION HANDLING (ERC-677 Callback)
    // =========================================================================

    /// @notice ERC-677 callback: handles LINK donations to fund VRF subscription.
    /// @dev Called automatically when LINK is transferred via transferAndCall().
    ///
    ///      FLOW:
    ///      1. Validate sender is LINK token contract
    ///      2. Calculate reward multiplier based on current subscription balance
    ///      3. Forward LINK to VRF subscription
    ///      4. Convert LINK to ETH-equivalent using price feed
    ///      5. Credit BURNIE reward to donor (live COIN)
    ///
    ///      SECURITY NOTES:
    ///      - msg.sender validation prevents fake LINK attacks.
    ///      - GameOver guard prevents donations after GAME ends.
    ///      - Multiplier decreases as subscription fills (incentivizes early donations).
    ///      - No rewards if price feed unavailable.
    ///
    /// @param from Address that sent the LINK.
    /// @param amount Amount of LINK received.
    function onTokenTransfer(
        address from,
        uint256 amount,
        bytes calldata
    ) external {
        // SECURITY: Only accept calls from the LINK token contract.
        if (msg.sender != ContractAddresses.LINK_TOKEN) revert NotAuthorized();
        if (amount == 0) revert InvalidAmount();

        uint256 subId = subscriptionId;
        if (subId == 0) revert NoSubscription();

        // Prevent donations after GAME-over.
        if (gameAdmin.gameOver()) revert GameOver();
        address coord = coordinator;

        // Calculate reward using tiered multiplier BEFORE forwarding LINK.
        (uint96 bal, , , , ) = IVRFCoordinatorV2_5Owner(coord).getSubscription(
            subId
        );
        uint256 mult = _linkRewardMultiplier(uint256(bal));

        // Forward LINK to VRF subscription.
        try
            linkToken.transferAndCall(coord, amount, abi.encode(subId))
        returns (bool ok) {
            if (!ok) revert InvalidAmount();
        } catch {
            revert InvalidAmount();
        }
        // No reward if subscription is fully funded.
        if (mult == 0) return;

        // Convert LINK amount to ETH-equivalent. Use try/catch to prevent oracle failures from blocking donations.
        uint256 ethEquivalent;
        try this.linkAmountToEth(amount) returns (uint256 eth) {
            ethEquivalent = eth;
        } catch {
            return; // Oracle failed, LINK forwarded but no reward.
        }
        if (ethEquivalent == 0) return; // Disable rewards if oracle unavailable.

        // Calculate BURNIE credit. Divide by live ticket price so 1000 BURNIE = 1 ticket's worth of ETH.
        (, , , , uint256 priceWei) = gameAdmin.purchaseInfo();
        if (priceWei == 0) return;
        uint256 baseCredit = (ethEquivalent * PRICE_COIN_UNIT) / priceWei;
        uint256 credit = (baseCredit * mult) / 1e18;
        if (credit == 0) return;

        coinLinkReward.creditLinkReward(from, credit);
        emit LinkCreditRecorded(from, credit);
    }

    // =========================================================================
    // INTERNAL HELPERS — LINK VALUATION
    // =========================================================================

    /// @dev Convert LINK amount to ETH-equivalent using price feed.
    /// @param amount LINK amount (18 decimals).
    /// @return ethAmount ETH-equivalent amount (18 decimals), or 0 if unavailable.
    ///
    /// SECURITY NOTES:
    /// - Returns 0 on missing feed, zero amount, or invalid price.
    /// - Assumes feed returns 18 decimal price (Chainlink LINK/ETH standard).
    /// - Rejects stale rounds (answeredInRound < roundId), future timestamps, and stale updates.
    /// - Exposed as external to allow try/catch in onTokenTransfer.
    function linkAmountToEth(
        uint256 amount
    ) external view returns (uint256 ethAmount) {
        address feed = linkEthPriceFeed;
        if (feed == address(0) || amount == 0) return 0;

        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = IAggregatorV3(feed).latestRoundData();
        if (answer <= 0 || updatedAt == 0 || answeredInRound < roundId)
            return 0;
        if (updatedAt > block.timestamp) return 0;
        unchecked {
            if (block.timestamp - updatedAt > LINK_ETH_MAX_STALE) return 0;
        }

        ethAmount = (amount * uint256(answer)) / 1 ether;
    }

    /// @dev Calculate reward multiplier based on subscription LINK balance.
    /// @param subBal Current subscription LINK balance (18 decimals).
    /// @return mult Multiplier in 18-decimal fixed point (e.g., 3e18 = 3x).
    ///
    /// TIERED STRUCTURE:
    /// - 0-200 LINK: Linear 3x → 1x (incentivizes early donations)
    /// - 200-1000 LINK: Linear 1x → 0x (diminishing returns)
    /// - 1000+ LINK: 0x (no reward, subscription is fully funded)
    function _linkRewardMultiplier(
        uint256 subBal
    ) private pure returns (uint256 mult) {
        if (subBal >= 1000 ether) return 0; // Fully funded, no reward.
        if (subBal <= 200 ether) {
            // Linear from 3x at 0 LINK down to 1x at 200 LINK.
            uint256 delta = (subBal * 2e18) / 200 ether;
            unchecked {
                return 3e18 - delta; // delta <= 2e18, cannot underflow
            }
        }
        // Between 200 and 1000 LINK: decay from 1x to 0x.
        uint256 excess = subBal - 200 ether;
        uint256 delta2 = (excess * 1e18) / 800 ether;
        if (delta2 >= 1e18) return 0;
        unchecked {
            return 1e18 - delta2; // delta2 < 1e18, cannot underflow
        }
    }

    /// @dev Check if a price feed is healthy (fresh and valid).
    /// @param feed Price feed address.
    /// @return True if feed is responding with valid, fresh data.
    ///
    /// HEALTH CHECKS:
    /// - answer > 0 (positive price)
    /// - updatedAt is within LINK_ETH_MAX_STALE and not in the future
    /// - answeredInRound >= roundId (not stale round)
    function _feedHealthy(address feed) private view returns (bool) {
        if (feed == address(0)) return false;
        try IAggregatorV3(feed).latestRoundData() returns (
            uint80 roundId,
            int256 answer,
            uint256 /*startedAt*/,
            uint256 updatedAt,
            uint80 answeredInRound
        ) {
            if (answer <= 0 || updatedAt == 0 || answeredInRound < roundId)
                return false;
            if (updatedAt > block.timestamp) return false;
            unchecked {
                if (block.timestamp - updatedAt > LINK_ETH_MAX_STALE)
                    return false;
            }
            try IAggregatorV3(feed).decimals() returns (uint8 dec) {
                if (dec != LINK_ETH_FEED_DECIMALS) return false;
            } catch {
                return false;
            }
            return true;
        } catch {
            return false;
        }
    }
}
