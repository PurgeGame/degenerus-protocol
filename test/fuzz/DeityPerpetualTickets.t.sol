// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {TicketQueueStorage as TQ} from "./helpers/TicketQueueStorage.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {IDegenerusGameFoilPackModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";

contract PerpetualFixture is DegenerusGameStorage {
    function setLevel(uint24 lvl) external { level = lvl; }
    function setJackpotPhase(bool on) external { jackpotPhaseFlag = on; }
    function renew(address module, uint24 target) external {
        (bool ok, bytes memory data) = module.delegatecall(
            abi.encodeCall(IDegenerusGameFoilPackModule.queuePerpetualTickets, (target))
        );
        if (!ok) assembly { revert(add(data, 32), mload(data)) }
    }
    function fillOwners() external {
        for (uint160 i = 2; i < 32; ++i) deityPassOwners.push(address(1000 + i));
    }
    function queue(address owner, uint24 lvl, uint32 count) external {
        _queueEntries(owner, lvl, count, false);
    }
}

contract DeityPerpetualTicketsTest is DeployProtocol {
    DegenerusGameLens private lens;
    PerpetualFixture private fixture;

    function setUp() public {
        _deployProtocol();
        lens = new DegenerusGameLens();
        fixture = new PerpetualFixture();
        vm.warp(block.timestamp + 1 days);
    }
    function _key(uint24 lvl, uint24 purchaseLevel) private pure returns (uint24) {
        // The minted window now ends at level + 1; higher levels use the
        // far-future queue until their preceding purchase phase seals.
        return lvl > purchaseLevel + 1 ? (uint24(1) << 22) | lvl : lvl;
    }
    function _owed(uint24 lvl, address who, uint24 atLevel) private view returns (uint256) {
        return uint32(TQ.owed(address(game), _key(lvl, atLevel), who) >> 8);
    }
    function _assertOnce(uint24 lvl, address who, uint24 atLevel) private view {
        uint24 key = _key(lvl, atLevel);
        bytes32 root = keccak256(abi.encode(uint256(key), uint256(12)));
        uint256 n = uint256(vm.load(address(game), root));
        uint256 seen;
        for (uint256 i; i < n; ++i) if (TQ.ownerAt(address(game), key, lvl, i) == who) ++seen;
        assertEq(seen, 1, "one queue lane despite additive awards");
        TQ.assertQueue(address(game), key);
    }
    function _buy(address who, uint8 symbol, uint256 price, bytes32 code) private {
        vm.deal(who, price);
        vm.prank(who);
        game.purchaseDeityPass{value: price}(who, symbol, code);
    }
    function _fixtureCall(bytes memory data) private {
        bytes memory original = address(game).code;
        vm.etch(address(game), address(fixture).code);
        (bool ok, bytes memory result) = address(game).call(data);
        vm.etch(address(game), original);
        if (!ok) assembly { revert(add(result, 32), mload(result)) }
    }
    function testGenesisOwnsRealPassesAndExactlyOneTicketForFirstHundredLevels() public view {
        assertEq(deityPass.ownerOf(0), address(vault));
        assertEq(deityPass.ownerOf(6), address(sdgnrs));
        assertEq(lens.deityPassSalesCount(address(game)), 0);
        for (uint256 i; i < 2; ++i) {
            address owner = lens.deityOwnerAt(address(game), i);
            assertEq(owner, i == 0 ? address(vault) : address(sdgnrs));
            for (uint24 lvl = 1; lvl <= 100; ++lvl) {
                assertEq(_owed(lvl, owner, 0), 4);
                _assertOnce(lvl, owner, 0);
            }
            assertEq(_owed(101, owner, 0), 0);
        }
    }
    function testPaidInitialPerpetualAddsToExistingBuyerAndDeityAffiliateTickets() public {
        address referrer = makeAddr("deity affiliate");
        address buyer = makeAddr("previously queued buyer");
        _buy(referrer, 1, 24 ether, bytes32(0));
        vm.prank(referrer);
        affiliate.createAffiliateCode(bytes32("DEITY"), 0);
        // Existing ordinary awards share the packed owner registry with the new range.
        _fixtureCall(abi.encodeCall(PerpetualFixture.queue, (buyer, 1, 12)));
        _fixtureCall(abi.encodeCall(PerpetualFixture.queue, (buyer, 10, 8)));
        _buy(buyer, 2, 25 ether, bytes32("DEITY"));
        for (uint24 lvl = 1; lvl <= 100; ++lvl) {
            uint256 prior = lvl == 1 ? 12 : (lvl == 10 ? 8 : 0);
            assertEq(_owed(lvl, buyer, 0), 4 + prior, "buyer gets additive one ticket");
            uint256 affiliateExtra = lvl <= 9 ? 20 : ((lvl - 10) % 2 == 0 ? 4 : 0);
            assertEq(_owed(lvl, referrer, 0), 4 + affiliateExtra, "affiliate retains perma plus whale award");
            _assertOnce(lvl, buyer, 0);
            _assertOnce(lvl, referrer, 0);
        }
        assertEq(lens.deityPassSalesCount(address(game)), 2);
        assertEq(lens.deityOwnerAt(address(game), 3), buyer);
    }
    function testPaidRangeAtLaterLevelStartsAfterCurrentAndEndsAtPlusHundred() public {
        _fixtureCall(abi.encodeCall(PerpetualFixture.setLevel, (uint24(15))));
        address buyer = makeAddr("late deity");
        _buy(buyer, 1, 24 ether, bytes32(0));
        assertEq(_owed(15, buyer, 15), 0);
        for (uint24 lvl = 16; lvl <= 115; ++lvl) {
            assertEq(_owed(lvl, buyer, 15), 4);
            _assertOnce(lvl, buyer, 15);
        }
        assertEq(_owed(116, buyer, 15), 0);
        assertEq(lens.deityOwnerAt(address(game), 2), buyer);
    }
    /// @dev In the jackpot phase the level is already promoted and the next transition
    ///      targets level + 100, so the initial grant stops one level short of it.
    function testPaidRangeInJackpotPhaseStopsShortOfTheNextTransitionTarget() public {
        _fixtureCall(abi.encodeCall(PerpetualFixture.setLevel, (uint24(15))));
        _fixtureCall(abi.encodeCall(PerpetualFixture.setJackpotPhase, (true)));
        address buyer = makeAddr("jackpot-phase deity");
        _buy(buyer, 1, 24 ether, bytes32(0));
        assertEq(_owed(15, buyer, 15), 0);
        for (uint24 lvl = 16; lvl <= 114; ++lvl) {
            assertEq(_owed(lvl, buyer, 15), 4);
            _assertOnce(lvl, buyer, 15);
        }
        assertEq(_owed(115, buyer, 15), 0, "level + 100 is the next transition's grant");
        _fixtureCall(abi.encodeCall(PerpetualFixture.setJackpotPhase, (false)));
        _fixtureCall(abi.encodeCall(PerpetualFixture.renew, (address(foilModule), 115)));
        assertEq(_owed(115, buyer, 15), 4);
        _assertOnce(115, buyer, 15);
    }
    function testRenewThirtyTwoOwnersPreservesPartialPackedTail() public {
        _fixtureCall(abi.encodeCall(PerpetualFixture.fillOwners, ()));
        _fixtureCall(abi.encodeCall(PerpetualFixture.setLevel, (uint24(1))));
        uint24 target = 101;
        for (uint160 i; i < 5; ++i) {
            _fixtureCall(abi.encodeCall(PerpetualFixture.queue, (address(2000 + i), target, 12)));
        }
        // Already queued deity must get +4 without a duplicate lane; remaining 31
        // straddle five packed words after the six-entry tail.
        _fixtureCall(abi.encodeCall(PerpetualFixture.queue, (address(vault), target, 20)));
        _fixtureCall(abi.encodeCall(PerpetualFixture.renew, (address(foilModule), target)));
        for (uint256 i; i < 32; ++i) {
            address owner = lens.deityOwnerAt(address(game), i);
            assertEq(_owed(target, owner, 1), i == 0 ? 24 : 4);
            _assertOnce(target, owner, 1);
        }
        for (uint160 i; i < 5; ++i) {
            assertEq(_owed(target, address(2000 + i), 1), 12);
            _assertOnce(target, address(2000 + i), 1);
        }
    }
    /// @dev Cold worst case for the transition step: 32 fresh owners, none queued at the target.
    function testRenewThirtyTwoFreshOwnersColdGas() public {
        _fixtureCall(abi.encodeCall(PerpetualFixture.fillOwners, ()));
        _fixtureCall(abi.encodeCall(PerpetualFixture.setLevel, (uint24(1))));
        uint256 before = gasleft();
        _fixtureCall(abi.encodeCall(PerpetualFixture.renew, (address(foilModule), 101)));
        emit log_named_uint("renew_32_fresh_owners_cold_gas", before - gasleft());
    }

    function testReservedSymbolsAndRepeatedGenesisRevertWithoutAdvancingPrice() public {
        address buyer = makeAddr("buyer");
        vm.deal(buyer, 24 ether);
        for (uint8 i; i < 2; ++i) {
            vm.expectRevert(); vm.prank(buyer);
            game.purchaseDeityPass{value: 24 ether}(buyer, i == 0 ? 0 : 6, bytes32(0));
        }
        vm.expectRevert(); vm.prank(address(vault)); game.initProtocolDeity();
        vm.expectRevert(); game.initProtocolDeity();
        assertEq(lens.deityPassSalesCount(address(game)), 0);
    }
}

/// @dev Setup is a separate transaction so cold accesses and SSTORE original values
///      match a real purchase. The affiliate has never received any queued tickets.
contract DeityPurchaseColdGasTest is DeployProtocol {
    address private buyer;
    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        PerpetualFixture fixture = new PerpetualFixture();
        bytes memory original = address(game).code;
        vm.etch(address(game), address(fixture).code);
        PerpetualFixture(address(game)).setLevel(15);
        vm.etch(address(game), original);
        address referrer = makeAddr("fresh affiliate");
        vm.prank(referrer); affiliate.createAffiliateCode(bytes32("FRESH"), 0);
        buyer = makeAddr("cold buyer");
        vm.deal(buyer, 24 ether);
    }
    function testColdPaidInitialRangeAndFreshAffiliateFitTransactionCap() public {
        vm.prank(buyer);
        uint256 beforeGas = gasleft();
        game.purchaseDeityPass{value: 24 ether, gas: 16_777_216 - 22_500}(buyer, 1, bytes32("FRESH"));
        uint256 used = beforeGas - gasleft() + 22_500;
        emit log_named_uint("cold deity purchase with new affiliate", used);
        assertLt(used, 16_777_216);
    }
}
