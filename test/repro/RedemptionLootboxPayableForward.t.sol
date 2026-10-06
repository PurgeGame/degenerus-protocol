// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {RedemptionCloseTools} from "../fuzz/helpers/RedemptionCloseTools.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @notice Coinflip surface mirror (interface-only) so the submit FLIP leg (settled backing read
///         + backing withdraw) is mockable without importing the coinflip contract. With
///         redeemableFlipBacking forced to 0 the escrowed slice is 0, so the claim-time FLIP leg
///         is skipped and the focus stays on the live-game ETH-forward path.
interface IFlipCoinflipPlayerMock {
    function previewClaimCoinflips(address player) external view returns (uint256);
    function redeemableFlipBacking() external returns (uint256 backing);
    function withdrawRedeemedFlip(uint256 base) external;
}

/// @title RedemptionLootboxPayableForward — regression for the live-game redemption ETH-forward.
///
/// @notice Live redemption settlement (the Redemption-stage worker mineFlip dispatches) forwards
///         sDGNRS's liquid ETH into BOTH game legs:
///         `game.resolveRedemptionLootbox{value: ethForLootbox}` and
///         `game.creditRedemptionDirect{value: ethForDirect}`. The Game-side stubs are payable
///         and DELEGATECALL their module bodies — delegatecall preserves msg.value, so every
///         module function on that path must be payable too. The pinned set:
///
///         1. LootboxModule.resolveRedemptionLootbox — the delegatecall target of the Game's
///            5-ETH-chunk loop. Non-payable, its compiled callvalue guard refuses the whole
///            claim (the keeper drain parks it unpaid) whenever sDGNRS holds ANY liquid ETH
///            (the normal funded state).
///         2. BoonModule.checkAndClearExpiredBoon — a nested delegatecall dispatch inside
///            `_resolveLootboxCommon`, reached whenever the claimant has boon state. Same
///            guard, one frame deeper.
///
///         Every prior suite missed this because the module-side target was mocked
///         (vm.mockCall intercepts a delegatecall BEFORE the callvalue guard runs) or sDGNRS
///         held zero liquid ETH at claim time (msg.value == 0 never trips a non-payable guard).
///         This file runs the REAL module chain with sDGNRS holding liquid ETH.
///
/// @dev TEST-ONLY. Run: forge test --match-path test/repro/RedemptionLootboxPayableForward.t.sol -vv
contract RedemptionLootboxPayableForward is RedemptionCloseTools {
    // =====================================================================
    //                          CONSTANTS / SLOTS
    // =====================================================================

    /// @dev balancesPacked (DegenerusGame) at slot 7 (v61 PACK fold). Low 128 bits = claimable.
    uint256 internal constant GAME_CLAIMABLE_SLOT = GameSlots.BALANCES_PACKED;
    /// @dev claimablePool in the upper 128 bits of slot 1.
    uint256 internal constant GAME_SLOT1 = 1;
    /// @dev boonPacked (DegenerusGame) mapping(address => BoonPacked{slot0, slot1}) at slot 51.
    uint256 internal constant SLOT_BOON_PACKED = GameSlots.BOON_PACKED;
    /// @dev BoonPacked.slot0 bit layout (coinflip fields).
    uint256 internal constant BP_COINFLIP_DAY_SHIFT = 0;
    uint256 internal constant BP_COINFLIP_TIER_SHIFT = 48;

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
        sdgnrs.transferFromPool(sDGNRS.Pool.Reward, player, PLAYER_FUNDING);
        vm.stopPrank();

        // Mock ONLY the coinflip surface (FLIP settle leg + backing preview). The lootbox
        // module delegatecall target is deliberately REAL — that dispatch is the regression
        // under pin.
        vm.mockCall(
            address(coinflip),
            abi.encodeWithSelector(IFlipCoinflipPlayerMock.previewClaimCoinflips.selector),
            abi.encode(uint256(0))
        );
        vm.mockCall(
            address(coinflip),
            abi.encodeWithSelector(IFlipCoinflipPlayerMock.redeemableFlipBacking.selector),
            abi.encode(uint256(0))
        );
        vm.mockCall(
            address(coinflip),
            abi.encodeWithSelector(IFlipCoinflipPlayerMock.withdrawRedeemedFlip.selector),
            abi.encode()
        );
    }

    // =====================================================================
    //                       SEEDING / READER HELPERS
    // =====================================================================

    function _setGameClaimableSdgnrs(uint256 amount) internal {
        bytes32 slot = keccak256(abi.encode(uint256(game.walletIdOf(address(sdgnrs))), GAME_CLAIMABLE_SLOT));
        uint256 word = uint256(vm.load(address(game), slot));
        word = (word & (type(uint256).max << 128)) | uint128(amount);
        vm.store(address(game), slot, bytes32(word));
    }

    function _setGameClaimablePool(uint128 amount) internal {
        uint256 slot1Val = uint256(vm.load(address(game), bytes32(uint256(GAME_SLOT1))));
        slot1Val = (slot1Val & type(uint128).max) | (uint256(amount) << 128);
        vm.store(address(game), bytes32(uint256(GAME_SLOT1)), bytes32(slot1Val));
    }

    /// @dev Session word pinned for the settlement cohort (any word > 1).
    uint256 internal constant SETTLEMENT_WORD = 0x5E771E;

    /// @dev Resolve a day's pool by pranking the game contract (deterministic roll), mirroring the
    ///      Game's resolve hook: the resolve and the settlement-cohort word pin happen together.
    function _resolveDay(uint32 id, uint16 roll) internal { _resolveTestBatch(id, roll); }

    /// @dev Seed the Game's published, not-yet-complete read session for `word` with its ticket
    ///      stage done: the redemption consumer stage (stage 1), the only stage in which a live
    ///      claim settles (the Game's resolve hook pins `word` for the cohort in the same step).
    function _openSettlementStage(uint256 word) internal {
        RecyclingState.seedWord(address(game), RecyclingState.readBuffer(address(game)), bytes32(word));
        uint256 slot0 = uint256(vm.load(address(game), bytes32(0)));
        vm.store(address(game), bytes32(0), bytes32(slot0 | (uint256(1) << 192))); // ticketsFullyProcessed
        assertEq(game.rngConsumerStage(), 1, "fixture: redemption consumer stage open");
    }

    /// @dev The Redemption-stage worker, called as the Game the way mineFlip dispatches it,
    ///      settling the whole cohort. A refused claim would park instead of settling.
    function _settleCohort() internal {
        vm.prank(address(game));
        assertTrue(sdgnrs.runRedemptionWork(batchWord, 9_000_000).done, "fixture: keeper drained the cohort");
        assertFalse(sdgnrs.redemptionSettlementPending(), "fixture: cohort cleared");
    }

    /// @dev Give `who` live boon state: an unexpired coinflip boon (slot0). The claim-time
    ///      lootbox resolution then takes the nested BoonModule delegatecall
    ///      (checkAndClearExpiredBoon via the any-bits gate) with the claim's msg.value in
    ///      flight.
    function _injectBoonState(address who) internal {
        bytes32 base = keccak256(abi.encode(who, SLOT_BOON_PACKED));
        uint24 day = game.currentDayView();
        uint256 s0 = (uint256(day) << BP_COINFLIP_DAY_SHIFT) | (uint256(1) << BP_COINFLIP_TIER_SHIFT);
        vm.store(address(game), base, bytes32(s0));
    }

    /// @dev Drive a full burn → resolve → custody-shape cycle and return the claim's rolled
    ///      halves. After this, sDGNRS holds seedEth liquid ETH (strictly 0 < seedEth <
    ///      lootboxEth) with stETH covering the exact remainder, so the lootbox leg forwards a
    ///      REAL msg.value and pulls the rest as stETH — the mainnet funded state.
    function _burnResolveAndShapeCustody()
        internal
        returns (uint32 dayD, uint256 ethDirect, uint256 lootboxEth)
    {
        dayD = _openBatch();
        _primeCurrentDayRng();
        vm.prank(player);
        sdgnrs.burn(BURN_AMOUNT);

        _closeFunded();
        uint256 owedBase = _batchBase(player, dayD);
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

        // Land the new day's word (the lootbox leg itself keys to the cohort's pinned session word).
        _primeCurrentDayRng();
    }

    // =====================================================================
    //                          THE REGRESSIONS
    // =====================================================================

    /// @notice HEADLINE: a live-game claim with sDGNRS holding liquid ETH must settle. The
    ///         lootbox leg's `{value: seedEth}` rides the Game-side delegatecall chunk loop into
    ///         LootboxModule.resolveRedemptionLootbox — non-payable, the compiled callvalue
    ///         guard would refuse the entire claim (every mainnet claim, since a funded sDGNRS
    ///         always holds some liquid ETH).
    function test_LiveClaimSettlesWithForwardedEthLeg() public {
        (uint32 dayD, uint256 ethDirect, uint256 lootboxEth) = _burnResolveAndShapeCustody();

        uint256 gameValueBefore = address(game).balance + mockStETH.balanceOf(address(game));
        _settleCohort();
        (uint128 owed,) = sdgnrs.pendingRedemptions(game.walletIdOf(player), dayD);
        assertEq(uint256(owed), 0, "the claim settled rather than parking");

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
    ///         delegatecalls BoonModule.checkAndClearExpiredBoon (any-boon-bits gate) while the
    ///         claim's msg.value is still in flight — it must be payable or the claim is refused
    ///         one frame deeper than the outer fix.
    function test_LiveClaimSettlesWithBoonStateAndForwardedEthLeg() public {
        (uint32 dayD, uint256 ethDirect, uint256 lootboxEth) = _burnResolveAndShapeCustody();
        _injectBoonState(player);

        uint256 gameValueBefore = address(game).balance + mockStETH.balanceOf(address(game));
        _settleCohort();
        (uint128 owed,) = sdgnrs.pendingRedemptions(game.walletIdOf(player), dayD);
        assertEq(uint256(owed), 0, "the claim settled rather than parking");

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
}
