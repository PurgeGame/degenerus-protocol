// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {StakedDegenerusStonk} from "../../contracts/StakedDegenerusStonk.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @notice Coinflip surface mirror (interface-only) so the BURNIE settle leg and the backing
///         preview are mockable without importing the coinflip contract.
interface IBurnieCoinflipPlayerMock {
    function previewClaimCoinflips(address player) external view returns (uint256);
    function redeemBurnieShare(address player, uint256 burnieAmount) external;
}

/// @title RedemptionLootboxPayableForward — regression for the live-game redemption ETH-forward.
///
/// @notice A live-game `claimRedemption` forwards sDGNRS's liquid ETH into BOTH game legs:
///         `game.resolveRedemptionLootbox{value: ethForLootbox}` and
///         `game.creditRedemptionDirect{value: ethForDirect}`. The Game-side stubs are payable
///         and DELEGATECALL their module bodies — delegatecall preserves msg.value, so every
///         module function on that path must be payable too. The pinned set:
///
///         1. LootboxModule.resolveRedemptionLootbox — the delegatecall target of the Game's
///            5-ETH-chunk loop. Non-payable, its compiled callvalue guard reverts the whole
///            claim whenever sDGNRS holds ANY liquid ETH (the normal funded state).
///         2. BoonModule.checkAndClearExpiredBoon and BoonModule.consumeActivityBoon — nested
///            delegatecall dispatches inside `_resolveLootboxCommon`, reached whenever the
///            claimant has boon state. Same guard, one frame deeper.
///
///         Every prior suite missed this because the module-side target was mocked
///         (vm.mockCall intercepts a delegatecall BEFORE the callvalue guard runs) or sDGNRS
///         held zero liquid ETH at claim time (msg.value == 0 never trips a non-payable guard).
///         This file runs the REAL module chain with sDGNRS holding liquid ETH.
///
/// @dev TEST-ONLY. Run: forge test --match-path test/repro/RedemptionLootboxPayableForward.t.sol -vv
contract RedemptionLootboxPayableForward is DeployProtocol {
    // =====================================================================
    //                          CONSTANTS / SLOTS
    // =====================================================================

    /// @dev balancesPacked (DegenerusGame) at slot 7 (v61 PACK fold). Low 128 bits = claimable.
    uint256 internal constant GAME_CLAIMABLE_SLOT = 7;
    /// @dev claimablePool in the upper 128 bits of slot 1.
    uint256 internal constant GAME_SLOT1 = 1;
    /// @dev boonPacked (DegenerusGame) mapping(address => BoonPacked{slot0, slot1}) at slot 51.
    uint256 internal constant SLOT_BOON_PACKED = 51;
    /// @dev BoonPacked.slot0 bit layout (coinflip fields).
    uint256 internal constant BP_COINFLIP_DAY_SHIFT = 0;
    uint256 internal constant BP_COINFLIP_TIER_SHIFT = 48;
    /// @dev BoonPacked.slot1 bit layout: pending activity bonus (uint24) at bit 0.
    uint256 internal constant BP_ACTIVITY_PENDING_SHIFT = 0;

    /// @dev sDGNRS funding / burn sizing mirrors V62RedemptionReentrancy: large enough that the
    ///      175% MAX roll yields a multi-ETH lootbox half (so the Game-side 5-ETH-chunk loop
    ///      runs more than once and each chunk's delegatecall carries the in-flight msg.value).
    uint256 internal constant PLAYER_FUNDING = 80_000_000_000 ether;
    uint256 internal constant BURN_AMOUNT = 10_000_000_000 ether;

    address internal player;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        player = makeAddr("redeemer");
        vm.deal(player, 1 ether);

        // Fund the game with ETH backing and credit claimable[SDGNRS] so the submit-time
        // pullRedemptionReserve ETH leg can segregate the 175% MAX into sDGNRS's balance.
        vm.deal(address(game), 1000 ether);
        _setGameClaimableSdgnrs(1000 ether);
        _setGameClaimablePool(uint128(1000 ether));

        // Fund the player with sDGNRS via the Reward pool (game is the authorized caller).
        vm.startPrank(address(game));
        sdgnrs.transferFromPool(StakedDegenerusStonk.Pool.Reward, player, PLAYER_FUNDING);
        vm.stopPrank();

        // Mock ONLY the coinflip surface (BURNIE settle leg + backing preview). The lootbox
        // module delegatecall target is deliberately REAL — that dispatch is the regression
        // under pin.
        vm.mockCall(
            address(coinflip),
            abi.encodeWithSelector(IBurnieCoinflipPlayerMock.previewClaimCoinflips.selector),
            abi.encode(uint256(0))
        );
        vm.mockCall(
            address(coinflip),
            abi.encodeWithSelector(IBurnieCoinflipPlayerMock.redeemBurnieShare.selector),
            abi.encode()
        );
    }

    // =====================================================================
    //                       SEEDING / READER HELPERS
    // =====================================================================

    function _setGameClaimableSdgnrs(uint256 amount) internal {
        bytes32 slot = keccak256(abi.encode(address(sdgnrs), GAME_CLAIMABLE_SLOT));
        uint256 word = uint256(vm.load(address(game), slot));
        word = (word & (type(uint256).max << 128)) | uint128(amount);
        vm.store(address(game), slot, bytes32(word));
    }

    function _setGameClaimablePool(uint128 amount) internal {
        uint256 slot1Val = uint256(vm.load(address(game), bytes32(uint256(GAME_SLOT1))));
        slot1Val = (slot1Val & type(uint128).max) | (uint256(amount) << 128);
        vm.store(address(game), bytes32(uint256(GAME_SLOT1)), bytes32(slot1Val));
    }

    /// @dev Resolve a day's pool by pranking the game contract (deterministic roll).
    function _resolveDay(uint32 dayToResolve, uint16 roll) internal {
        vm.prank(address(game));
        sdgnrs.resolveRedemptionPeriod(roll, uint24(dayToResolve));
    }

    /// @dev Give `who` live boon state: an unexpired coinflip boon (slot0) and a pending
    ///      activity bonus (slot1). The claim-time lootbox resolution then takes BOTH nested
    ///      BoonModule delegatecalls (checkAndClearExpiredBoon via the any-bits gate,
    ///      consumeActivityBoon via the pending-bits gate) with the claim's msg.value in flight.
    function _injectBoonState(address who) internal {
        bytes32 base = keccak256(abi.encode(who, SLOT_BOON_PACKED));
        uint24 day = game.currentDayView();
        uint256 s0 = (uint256(day) << BP_COINFLIP_DAY_SHIFT) | (uint256(1) << BP_COINFLIP_TIER_SHIFT);
        vm.store(address(game), base, bytes32(s0));
        uint256 s1 = uint256(100) << BP_ACTIVITY_PENDING_SHIFT;
        vm.store(address(game), bytes32(uint256(base) + 1), bytes32(s1));
    }

    /// @dev Drive a full burn → resolve → custody-shape cycle and return the claim's rolled
    ///      halves. After this, sDGNRS holds seedEth liquid ETH (strictly 0 < seedEth <
    ///      lootboxEth) with stETH covering the exact remainder, so the lootbox leg forwards a
    ///      REAL msg.value and pulls the rest as stETH — the mainnet funded state.
    function _burnResolveAndShapeCustody()
        internal
        returns (uint24 dayD, uint256 ethDirect, uint256 lootboxEth)
    {
        dayD = game.currentDayView();
        _primeCurrentDayRng();
        vm.prank(player);
        sdgnrs.burn(BURN_AMOUNT);

        (uint96 owedBase, ) = sdgnrs.pendingRedemptions(player, dayD);
        assertGt(uint256(owedBase), 0, "precondition: burn must record a positive claim base");

        vm.warp(block.timestamp + 1 days);
        _resolveDay(dayD, 175);

        uint256 totalRolledEth = (uint256(owedBase) * 175) / 100;
        ethDirect = totalRolledEth / 2;
        lootboxEth = totalRolledEth - ethDirect;

        // Liquid ETH strictly between 0 and the lootbox half; stETH covers the remainder of the
        // full reservation. msg.value on the lootbox leg is then seedEth (> 0).
        uint256 seedEth = lootboxEth / 4;
        assertGt(seedEth, 0, "precondition: seedEth must be > 0");
        uint256 pendingNow = sdgnrs.pendingRedemptionEthValue();
        vm.deal(address(sdgnrs), seedEth);
        mockStETH.mint(address(sdgnrs), pendingNow - seedEth);

        // The claim's value must arrive from sDGNRS custody alone, not a game-side reserve.
        vm.deal(address(game), 0);
        _setGameClaimableSdgnrs(0);
        _setGameClaimablePool(0);

        // Land the new day's word: the lootbox leg keys to rngWordForDay(dayD + 1).
        _primeCurrentDayRng();
    }

    // =====================================================================
    //                          THE REGRESSIONS
    // =====================================================================

    /// @notice HEADLINE: a live-game claim with sDGNRS holding liquid ETH must settle. The
    ///         lootbox leg's `{value: seedEth}` rides the Game-side delegatecall chunk loop into
    ///         LootboxModule.resolveRedemptionLootbox — non-payable, the compiled callvalue
    ///         guard reverts the entire claim (every mainnet claim, since a funded sDGNRS
    ///         always holds some liquid ETH).
    function test_LiveClaimSettlesWithForwardedEthLeg() public {
        (uint24 dayD, uint256 ethDirect, uint256 lootboxEth) = _burnResolveAndShapeCustody();

        uint256 gameValueBefore = address(game).balance + mockStETH.balanceOf(address(game));
        vm.prank(player);
        sdgnrs.claimRedemption(player, dayD);

        // Direct half lands as a game-claimable credit; the full rolled value reaches the game
        // (seed ETH as msg.value across both legs, the remainder as stETH pulls).
        assertEq(
            game.claimableWinningsOf(player),
            ethDirect,
            "direct half must credit the claimant's game claimable"
        );
        assertEq(
            address(game).balance + mockStETH.balanceOf(address(game)) - gameValueBefore,
            ethDirect + lootboxEth,
            "full rolled value must arrive at the game"
        );
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0, "reservation must be fully released");
    }

    /// @notice Same claim with the claimant holding live boon state. The lootbox resolution then
    ///         delegatecalls BoonModule.checkAndClearExpiredBoon (any-boon-bits gate) and
    ///         BoonModule.consumeActivityBoon (pending-activity gate) while the claim's
    ///         msg.value is still in flight — both must be payable or the claim reverts one
    ///         frame deeper than the outer fix.
    function test_LiveClaimSettlesWithBoonStateAndForwardedEthLeg() public {
        (uint24 dayD, uint256 ethDirect, uint256 lootboxEth) = _burnResolveAndShapeCustody();
        _injectBoonState(player);

        uint256 gameValueBefore = address(game).balance + mockStETH.balanceOf(address(game));
        vm.prank(player);
        sdgnrs.claimRedemption(player, dayD);

        assertEq(
            game.claimableWinningsOf(player),
            ethDirect,
            "direct half must credit the claimant's game claimable"
        );
        assertEq(
            address(game).balance + mockStETH.balanceOf(address(game)) - gameValueBefore,
            ethDirect + lootboxEth,
            "full rolled value must arrive at the game"
        );
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0, "reservation must be fully released");

        // The pending activity bonus was consumed by the real BoonModule dispatch.
        bytes32 base = keccak256(abi.encode(player, SLOT_BOON_PACKED));
        uint256 s1 = uint256(vm.load(address(game), bytes32(uint256(base) + 1)));
        assertEq(
            uint24(s1 >> BP_ACTIVITY_PENDING_SHIFT),
            0,
            "consumeActivityBoon must consume the pending bonus during the claim"
        );
    }
}
