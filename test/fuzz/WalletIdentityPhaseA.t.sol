// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @dev Reads and fixture writes against the live Game layout, etched over the Game for one call.
contract WalletIdentityProbe is DegenerusGameStorage {
    function walletsLength() external view returns (uint256) { return wallets.length; }
    function element(uint32 id) external view returns (uint256) { return _walletElement(id); }
    function mintWord(address owner) external view returns (uint256) { return mintPacked_[owner]; }
    function setWalletsLength(uint256 n) external { assembly { sstore(wallets.slot, n) } }
    function register(address owner, uint256 spend) external returns (uint32 id) { (id, ) = _registerWallet(owner, spend); }
    function addHalf(uint32 id, uint256 n) external { _addHalfPasses(id, n); }
    function takeHalf(uint32 id) external returns (uint256) { return _takeHalfPasses(id); }
    function seedLevel(uint24 lvl) external {
        level = lvl;
        purchaseStartDay = _simulatedDayIndex();
        dailyIdx = purchaseStartDay;
        rngRequestTime = uint48(block.timestamp);
        jackpotPhaseFlag = false;
        lastPurchaseDay = false;
        rngLockedFlag = false;
        phaseTransitionActive = false;
        presaleOver = true;
        _setPrizePools(10 ether, 10 ether);
    }
}

/// @notice Phase A wallet identity: table, codec, door registration, paid admission and the
///         existing-ID rule for non-paying paths.
contract WalletIdentityPhaseATest is DeployProtocol {
    bytes32 private constant WALLET_REGISTERED = keccak256("WalletRegistered(uint32,address)");
    bytes private gameCode;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 20 days);
        gameCode = address(game).code;
    }

    function _probe() private returns (WalletIdentityProbe) {
        vm.etch(address(game), type(WalletIdentityProbe).runtimeCode);
        return WalletIdentityProbe(address(game));
    }

    function _restore() private { vm.etch(address(game), gameCode); }

    function _length() private returns (uint256 n) { n = _probe().walletsLength(); _restore(); }

    function _price() private view returns (uint256) { return PriceLookupLib.priceForLevel(game.level() + 1); }

    function _buyTickets(address buyer, uint256 tickets) private {
        uint256 value = _price() * tickets;
        vm.deal(buyer, value + 1 ether);
        vm.prank(buyer);
        game.purchase{value: value}(0, tickets * 400, 0, 0, MintPaymentKind.DirectEth, false);
    }

    function _registeredLogs(Vm.Log[] memory logs) private view returns (uint256 n) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == WALLET_REGISTERED) ++n;
        }
    }

    // ----- wallet table -----

    function test_ProtocolIdsAndElementZero() public {
        assertEq(game.walletIdOf(ContractAddresses.VAULT), 1, "vault");
        assertEq(game.walletIdOf(ContractAddresses.SDGNRS), 2, "sdgnrs");
        assertEq(game.walletIdOf(ContractAddresses.GNRUS), 3, "gnrus");
        WalletIdentityProbe probe = _probe();
        assertEq(probe.element(0), 0, "element 0 never assigned");
        assertEq(address(uint160(probe.element(1))), ContractAddresses.VAULT, "id 1 key");
        _restore();
    }

    function test_IdIsTablePositionAndRegistersOnce() public {
        address buyer = address(0xB0B);
        uint256 before = _length();
        vm.recordLogs();
        _buyTickets(buyer, 1);
        _buyTickets(buyer, 1);
        assertEq(_registeredLogs(vm.getRecordedLogs()), 1, "one WalletRegistered per wallet");
        assertEq(game.walletIdOf(buyer), before, "ID = prior table length");
        WalletIdentityProbe probe = _probe();
        assertEq(address(uint160(probe.element(uint32(before)))), buyer, "reverse direction");
        assertEq(probe.mintWord(buyer) >> BitPackingLib.WALLET_ID_SHIFT, before, "forward direction");
        _restore();
    }

    function test_HalfPassLanePreservesKey() public {
        address who = address(0xCAFE);
        WalletIdentityProbe probe = _probe();
        uint32 id = probe.register(who, 0);
        probe.addHalf(id, 5);
        assertEq(address(uint160(probe.element(id))), who, "key survives add");
        assertEq(probe.element(id) >> 192, 5, "count in top lane");
        assertEq(probe.takeHalf(id), 5, "take returns count");
        assertEq(probe.element(id), uint256(uint160(who)), "clear keeps key and owner lane");
        vm.expectRevert(DegenerusGameStorage.E.selector);
        probe.addHalf(0, 1);
        _restore();
    }

    // ----- mintPacked_ codec -----

    function test_MintWordFieldsDisjointAndComplete() public pure {
        uint256[16] memory masks = [
            BitPackingLib.MASK_24 << BitPackingLib.LAST_LEVEL_SHIFT,
            BitPackingLib.MASK_24 << BitPackingLib.LEVEL_COUNT_SHIFT,
            BitPackingLib.MASK_24 << BitPackingLib.LEVEL_STREAK_SHIFT,
            BitPackingLib.MASK_24 << BitPackingLib.DAY_SHIFT,
            BitPackingLib.MASK_24 << BitPackingLib.LEVEL_UNITS_LEVEL_SHIFT,
            BitPackingLib.MASK_24 << BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT,
            uint256(3) << BitPackingLib.WHALE_PASS_TYPE_SHIFT,
            uint256(1) << BitPackingLib.SEAT_CLAIMED_SHIFT,
            uint256(1) << BitPackingLib.SMURF_FLAG_SHIFT,
            BitPackingLib.MASK_24 << BitPackingLib.MINT_STREAK_LAST_COMPLETED_SHIFT,
            uint256(1) << BitPackingLib.HAS_DEITY_PASS_SHIFT,
            BitPackingLib.MASK_24 << BitPackingLib.AFFILIATE_BONUS_LEVEL_SHIFT,
            BitPackingLib.MASK_6 << BitPackingLib.AFFILIATE_BONUS_POINTS_SHIFT,
            BitPackingLib.MASK_5 << BitPackingLib.CURSE_COUNT_SHIFT,
            BitPackingLib.MASK_16 << BitPackingLib.LEVEL_UNITS_SHIFT,
            uint256(type(uint32).max) << BitPackingLib.WALLET_ID_SHIFT
        ];
        uint256 union;
        for (uint256 i; i < masks.length; ++i) {
            assertEq(union & masks[i], 0, "fields overlap");
            union |= masks[i];
        }
        assertEq(union, type(uint256).max, "fields cover the word");
        assertGe(BitPackingLib.MASK_5, 20, "curse cap fits");
        assertEq(BitPackingLib.MASK_24, type(uint24).max, "day is uint24");
    }

    // ----- registration at the doors -----

    function test_EntryPointsRegister() public {
        address boxBuyer = address(0xB0C5);
        uint256 price = _price();
        vm.deal(boxBuyer, 10 ether);
        vm.prank(boxBuyer);
        game.purchase{value: price}(0, 0, 1, 0, MintPaymentKind.DirectEth, false);
        assertGt(game.walletIdOf(boxBuyer), 0, "box-only buyer");

        address whale = address(0x3A1E);
        vm.deal(whale, 10 ether);
        vm.prank(whale);
        game.purchaseWhalePass{value: 4 ether}(0, 1, 0);
        assertGt(game.walletIdOf(whale), 0, "whale pass buyer");

        address lazy = address(0x1A2E);
        vm.deal(lazy, 10 ether);
        vm.prank(lazy);
        game.purchaseLazyPass{value: 1 ether}(0, 0);
        assertGt(game.walletIdOf(lazy), 0, "lazy pass buyer");

        address deity = address(0xDE17);
        vm.deal(deity, 200 ether);
        vm.prank(deity);
        game.purchaseDeityPass{value: 200 ether}(0, 3, 0);
        assertGt(game.walletIdOf(deity), 0, "deity buyer");
    }

    function test_DegeneretteBetRegistersOwner() public {
        _probe().seedLevel(24);
        _restore();
        address bettor = address(0xBE77);
        vm.deal(bettor, 1 ether);
        vm.prank(bettor);
        game.placeDegeneretteBet{value: 0.01 ether}(0, 0, uint128(0.01 ether), 1, 3);
        assertGt(game.walletIdOf(bettor), 0, "bet owner registered");
    }

    // ----- paid admission and exhaustion -----

    function test_PaidAdmissionAtThreshold() public {
        WalletIdentityProbe probe = _probe();
        probe.setWalletsLength(3_000_000_001); // 3B registered
        _restore();
        address small = address(0x5A11);
        uint256 price = _price();
        assertLt(price, 0.04 ether, "fixture prices below the admission spend");
        vm.deal(small, 10 ether);
        vm.prank(small);
        vm.expectRevert(DegenerusGameStorage.E.selector);
        game.purchase{value: price}(0, 400, 0, 0, MintPaymentKind.DirectEth, false);

        uint256 tickets = (0.04 ether + price - 1) / price;
        _buyTickets(small, tickets);
        assertEq(game.walletIdOf(small), 3_000_000_001, "qualifying spend admits");

        vm.prank(ContractAddresses.AFFILIATE);
        vm.expectRevert(DegenerusGameStorage.E.selector);
        game.registerWallet(address(0xA77), true);
        vm.prank(ContractAddresses.AFFILIATE);
        assertEq(game.registerWallet(address(0xA77), false), 0, "non-allocating returns zero");
        vm.prank(ContractAddresses.AFFILIATE);
        assertEq(game.registerWallet(small, true), 3_000_000_001, "existing ID keeps working");
    }

    function test_BelowThresholdHookAllocates() public {
        WalletIdentityProbe probe = _probe();
        probe.setWalletsLength(3_000_000_000); // 2,999,999,999 registered
        _restore();
        vm.prank(ContractAddresses.AFFILIATE);
        assertEq(game.registerWallet(address(0xA78), true), 3_000_000_000, "below threshold");
    }

    function test_Uint32Exhaustion() public {
        WalletIdentityProbe probe = _probe();
        probe.setWalletsLength(uint256(type(uint32).max));
        _restore();
        address last = address(0x1A57);
        uint256 tickets = (0.04 ether + _price() - 1) / _price();
        _buyTickets(last, tickets);
        assertEq(game.walletIdOf(last), type(uint32).max, "last valid ID");
        address next = address(0x2A57);
        uint256 value = _price() * tickets;
        vm.deal(next, value);
        vm.prank(next);
        vm.expectRevert(DegenerusGameStorage.E.selector);
        game.purchase{value: value}(0, tickets * 400, 0, 0, MintPaymentKind.DirectEth, false);
        _buyTickets(last, 1);
    }

    function test_HookCallerSet() public {
        vm.expectRevert(DegenerusGameStorage.E.selector);
        game.registerWallet(address(0xA79), true);
    }

    // ----- non-paying paths require an existing ID -----

    function test_NonPayingPathsRequireId() public {
        address fresh = address(0xF4E5);
        vm.deal(fresh, 10 ether);
        vm.prank(fresh);
        (bool ok,) = address(game).call{value: 1 ether}("");
        assertFalse(ok, "receive() needs an ID");

        vm.prank(fresh);
        vm.expectRevert(DegenerusGameStorage.E.selector);
        game.depositAfkingFunding{value: 1 ether}(0);

        vm.prank(fresh);
        vm.expectRevert(DegenerusGameStorage.E.selector);
        game.claimWhalePass(0);

        assertEq(game.claimableWinningsOf(fresh), 0, "no ID, no balance");
        assertEq(game.afkingFundingOf(fresh), 0, "no ID, no afking");

        // Overpayment by a payer that is not the beneficiary needs the payer's ID; exact payment does not.
        address buyer = address(0xB1);
        _buyTickets(buyer, 1);
        uint32 buyerId = game.walletIdOf(buyer);
        vm.prank(buyer);
        game.setOperatorApproval(0, fresh, true);
        uint256 price = _price();
        vm.prank(fresh);
        vm.expectRevert(DegenerusGameStorage.E.selector);
        game.purchase{value: price * 2}(buyerId, 400, 0, 0, MintPaymentKind.DirectEth, false);
        vm.prank(fresh);
        game.purchase{value: price}(buyerId, 400, 0, 0, MintPaymentKind.DirectEth, false);
        assertEq(game.walletIdOf(fresh), 0, "operator stays unregistered");
    }

    // ----- participation is separate from identity -----

    function test_IdOnlyWalletIsNotParticipant() public {
        address owner = address(0xC0DE);
        vm.prank(ContractAddresses.AFFILIATE);
        uint32 id = game.registerWallet(owner, true);
        assertGt(id, 0);
        (bool mayBet,,) = quests.marketBetGates(owner, game.level() + 1);
        assertFalse(mayBet, "registration alone does not open the markets");
    }

    // ----- suite-wide ID truth -----

    function testFuzz_IdTruthAcrossPurchases(uint256 seed) public {
        uint256 start = _length();
        vm.recordLogs();
        for (uint256 i; i < 12; ++i) {
            address who = address(uint160(0x10000 + uint256(keccak256(abi.encode(seed, i))) % 6));
            if ((seed >> i) & 1 == 0) _buyTickets(who, 1);
            else {
                uint256 price = _price();
                vm.deal(who, price + 1 ether);
                vm.prank(who);
                game.purchase{value: price}(0, 0, 1, 0, MintPaymentKind.DirectEth, false);
            }
        }
        uint256 end = _length();
        assertEq(_registeredLogs(vm.getRecordedLogs()), end - start, "one event per allocated ID");
        WalletIdentityProbe probe = _probe();
        for (uint32 id = 1; id < end; ++id) {
            address key = address(uint160(probe.element(id)));
            assertEq(probe.mintWord(key) >> BitPackingLib.WALLET_ID_SHIFT, id, "forward matches reverse");
        }
        _restore();
    }
}
