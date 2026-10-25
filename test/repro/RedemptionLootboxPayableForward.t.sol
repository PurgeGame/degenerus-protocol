// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {RedemptionCloseTools} from "../fuzz/helpers/RedemptionCloseTools.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {claimableBalance} from "../helpers/ClaimableBalance.sol";

/// @notice Coinflip surface mirror (interface-only) so the submit FLIP leg (settled backing read
///         + backing withdraw) is mockable without importing the coinflip contract. With
///         redeemableFlipBacking forced to 0 the escrowed slice is 0, so the claim-time FLIP leg
///         is skipped and the focus stays on the live-game ETH-forward path.
interface IFlipCoinflipPlayerMock {
    function previewClaimCoinflips(address player) external view returns (uint256);
    function redeemableFlipBacking() external returns (uint256 backing);
    function withdrawRedeemedFlip(uint256 base) external;
}

/// @title RedemptionLootboxReserveLeg -- live redemption legs settle from the Game reserve alone.
///
/// @notice Live redemption settlement (the Redemption-stage worker mineFlip dispatches) calls
///         `game.resolveRedemptionLootbox` and `game.creditRedemptionDirect` with no ETH. Both
///         Game stubs DELEGATECALL their module bodies, which draw the full amount from the
///         redemption reserve. The pinned set, run through the REAL module chain:
///
///         1. LootboxModule.resolveRedemptionLootbox -- the delegatecall target of the Game's
///            5-ETH-chunk loop.
///         2. BoonModule.checkAndClearExpiredBoon -- a nested delegatecall dispatch inside
///            `_resolveLootboxCommon`, reached whenever the claimant has boon state.
///
///         The Game holds exactly the reserve; no ETH moves between the Game and sDGNRS.

contract RedemptionLootboxReserveLeg is RedemptionCloseTools {
    // =====================================================================
    //                          CONSTANTS / SLOTS
    // =====================================================================

    /// @dev balancesPacked (DegenerusGame) at slot 7 (v61 PACK fold). Low 128 bits = claimable.
    uint256 internal constant GAME_CLAIMABLE_SLOT = GameSlots.BALANCES_PACKED;
    /// @dev claimablePool in the upper 128 bits of slot 1.
    uint256 internal constant GAME_SLOT1 = 1;
    /// @dev boonPacked (DegenerusGame) mapping(uint32 => BoonPacked{slot0, slot1}) at slot 47.
    uint256 internal constant SLOT_BOON_PACKED = GameSlots.BOON_PACKED;
    /// @dev BoonPacked.slot0 bit layout (coinflip fields).
    uint256 internal constant BP_COINFLIP_DAY_SHIFT = 0;
    uint256 internal constant BP_COINFLIP_TIER_SHIFT = 48;

    /// @dev sDGNRS funding / burn sizing mirrors V62RedemptionReentrancy: large enough that the
    ///      175% MAX roll yields a multi-ETH lootbox half (so the Game-side 5-ETH-chunk loop
    ///      runs more than once).
    uint256 internal constant PLAYER_FUNDING = 80_000_000_000e12;
    uint256 internal constant BURN_AMOUNT = 10_000_000_000e12;

    address internal player;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        player = makeAddr("redeemer");
        _giveWalletId(player);
        vm.deal(player, 1 ether);

        // Fund the game with ETH backing and credit claimable[SDGNRS] so the batch close
        // can move the 175% MAX into the Game reserve.
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
        bytes32 slot = keccak256(abi.encode(uint256(game.walletIdOf_g3120(address(sdgnrs))), GAME_CLAIMABLE_SLOT));
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
        assertEq(game.rngConsumerStage_g379(), 1, "fixture: redemption consumer stage open");
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
    ///      (checkAndClearExpiredBoon via the any-bits gate).
    function _injectBoonState(address who) internal {
        bytes32 base = keccak256(abi.encode(uint256(_giveWalletId(who)), SLOT_BOON_PACKED));
        uint24 day = game.currentDayView_g542950();
        uint256 s0 = (uint256(day) << BP_COINFLIP_DAY_SHIFT) | (uint256(1) << BP_COINFLIP_TIER_SHIFT);
        vm.store(address(game), base, bytes32(s0));
    }

    /// @dev Drive a full burn -> resolve cycle and return the claim's rolled halves. The Game
    ///      then holds exactly the reserve, so both legs spend only the protected reserve.
    function _burnResolveAndFundReserve()
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

        // The close moved the whole pull into the reserve; leave the Game holding exactly it.
        uint256 reserve = sdgnrs.pendingRedemptionEthValue();
        assertEq(game.redemptionReserve(), reserve, "the close funds the whole reserve");
        vm.deal(address(game), reserve);
        _setGameClaimableSdgnrs(0);
        _setGameClaimablePool(uint128(reserve));

        // Land the new day's word (the lootbox leg itself keys to the cohort's pinned session word).
        _primeCurrentDayRng();
    }

    // =====================================================================
    //                          THE REGRESSIONS
    // =====================================================================

    /// @notice HEADLINE: a live-game claim settles from the reserve with no ETH forwarded to the
    ///         lootbox or direct leg.
    function test_LiveClaimSettlesFromReserveOnly() public {
        (uint32 dayD, uint256 ethDirect, uint256 lootboxEth) = _burnResolveAndFundReserve();

        uint256 gameValueBefore = address(game).balance + mockStETH.balanceOf(address(game));
        uint256 sdgnrsEthBefore = address(sdgnrs).balance;
        _settleCohort();
        (uint128 owed,) = sdgnrs.pendingRedemptions(game.walletIdOf_g3120(player), dayD);
        assertEq(uint256(owed), 0, "the claim settled rather than parking");

        assertEq(
            claimableBalance(game, player),
            ethDirect,
            "direct half must credit the claimant's game claimable"
        );
        assertEq(address(game).balance + mockStETH.balanceOf(address(game)), gameValueBefore, "no ETH moves");
        assertEq(address(sdgnrs).balance, sdgnrsEthBefore, "sDGNRS sends no ETH");
        assertEq(game.redemptionReserve(), 0, "the reserve funds the whole rolled value");
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0, "reservation must be fully released");
        assertGt(lootboxEth, 0);
    }

    /// @notice Same claim with the claimant holding live boon state. The lootbox resolution then
    ///         delegatecalls BoonModule.checkAndClearExpiredBoon (any-boon-bits gate) one frame
    ///         deeper and must still settle.
    function test_LiveClaimSettlesWithBoonStateFromReserve() public {
        (uint32 dayD, uint256 ethDirect,) = _burnResolveAndFundReserve();
        _injectBoonState(player);

        uint256 gameValueBefore = address(game).balance + mockStETH.balanceOf(address(game));
        _settleCohort();
        (uint128 owed,) = sdgnrs.pendingRedemptions(game.walletIdOf_g3120(player), dayD);
        assertEq(uint256(owed), 0, "the claim settled rather than parking");

        assertEq(
            claimableBalance(game, player),
            ethDirect,
            "direct half must credit the claimant's game claimable"
        );
        assertEq(address(game).balance + mockStETH.balanceOf(address(game)), gameValueBefore, "no ETH moves");
        assertEq(game.redemptionReserve(), 0, "the reserve funds the whole rolled value");
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0, "reservation must be fully released");
    }
}
