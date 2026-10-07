// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {DegenerusGameBoonModule} from "../../contracts/modules/DegenerusGameBoonModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";

/// @dev The production Game plus test doors (module delegatecall, boon and window seeders).
///      Every production function is unchanged.
contract BoonGameExt is DegenerusGame {
    function x_delegate(address module, bytes calldata data) external payable returns (bytes memory r) {
        bool ok;
        (ok, r) = module.delegatecall(data);
        if (!ok) assembly ("memory-safe") { revert(add(r, 32), mload(r)) }
    }

    function x_seedWallet(address a) external returns (uint32 id) {
        (id, ) = _registerWallet(a, type(uint256).max);
    }

    function x_setBoon(uint32 id, uint256 s0, uint256 s1) external {
        boonPacked[id] = BoonPacked(s0, s1);
    }

    function x_boonPackedSlot() external pure returns (uint256 s) {
        assembly { s := boonPacked.slot }
    }

    function x_grantDeity(address a) external {
        mintPacked_[a] |= uint256(1) << BitPackingLib.HAS_DEITY_PASS_SHIFT;
    }

    function x_openDecWindow() external {
        _setDecWindowOpen(true);
        decBattleRounds[level + 1].openedDay = _simulatedDayIndex();
    }
}

/// @title BoonPackedWalletIds -- boon state is keyed by wallet ID end to end
/// @notice Producers (box rolls, deity gifts, protocol draws) write `boonPacked[id]`; every consumer
///         reads and clears by ID and reports `BoonConsumed(id, …)`; consumers called with ID 0
///         return 0 and write nothing; an unregistered pass buyer pays full price and registers.
///         The WWXRP raw read lands on the same slot the getter reads.
contract BoonPackedWalletIds is DeployProtocol {
    bytes32 private constant BOON_CONSUMED = keccak256("BoonConsumed(uint32,uint8,uint16)");
    bytes32 private constant BOOST_USED = keccak256("BoostUsed(address,uint24,uint256,uint256,uint16)");
    bytes32 private constant WALLET_REGISTERED = keccak256("WalletRegistered(uint32,address)");
    bytes32 private constant DEITY_PURCHASED = keccak256("DeityPassPurchased(address,uint8,uint256,uint24)");
    bytes32 private constant PROTOCOL_BOON_AWARDED =
        keccak256("ProtocolBoonDrawAwarded(address,address,uint24,uint8,uint32,uint8)");

    // boonPacked bit positions (DegenerusGameStorage BP_* layout).
    uint256 private constant COINFLIP_TIER = 48;
    uint256 private constant LOOTBOX_DAY = 56;
    uint256 private constant LOOTBOX_TIER = 104;
    uint256 private constant PURCHASE_DAY = 112;
    uint256 private constant PURCHASE_TIER = 160;
    uint256 private constant DECIMATOR_TIER = 168;
    uint256 private constant WHALE_DAY = 200;
    uint256 private constant WHALE_TIER = 248;
    uint256 private constant DEITY_PASS_TIER = 72;
    uint256 private constant DEITY_PASS_DAY = 80;
    uint256 private constant LAZY_DAY = 128;
    uint256 private constant LAZY_TIER = 176;
    uint256 private constant DEGEN_ETH_LANE = 184;
    uint256 private constant DEGEN_FLIP_LANE = 208;
    uint256 private constant WWXRP_LANE = 232;
    uint256 private constant BOON_PACKED_SLOT = 47;

    BoonGameExt private ext;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        vm.etch(address(game), address(new BoonGameExt()).code);
        ext = BoonGameExt(payable(address(game)));
        vm.deal(address(game), 1_000 ether);
        RecyclingState.seedWriteBuffer(address(game), 1);
        // Degenerette ETH wins need a funded future pool.
        uint256 pools = uint256(vm.load(address(game), bytes32(GameSlots.PRIZE_POOLS_PACKED)));
        vm.store(
            address(game),
            bytes32(GameSlots.PRIZE_POOLS_PACKED),
            bytes32((pools & type(uint128).max) | (uint256(1_000 ether) << 128))
        );
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    function _today() private view returns (uint256) {
        return game.currentDayView();
    }

    /// @dev A fresh, live lane value (tier | day << 3) for the shared 24-bit lane encoding.
    function _lane(uint256 tier) private view returns (uint256) {
        return tier | ((_today() & 0x1FFFFF) << 3);
    }

    function _wallet(string memory name) private returns (address a, uint32 id) {
        a = makeAddr(name);
        id = ext.x_seedWallet(a);
    }

    function _boon(uint32 id) private view returns (uint256 s0, uint256 s1) {
        (s0, s1) = game.boonPacked(id);
    }

    function _assertIdZeroEmpty() private view {
        (uint256 s0, uint256 s1) = _boon(0);
        assertEq(s0, 0, "boonPacked[0].slot0 stays empty");
        assertEq(s1, 0, "boonPacked[0].slot1 stays empty");
    }

    /// @dev The one BoonConsumed in `logs`: its ID topic, type and bps.
    function _consumed(Vm.Log[] memory logs) private view returns (uint256 n, uint32 id, uint8 kind, uint16 bps) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics[0] != BOON_CONSUMED) continue;
            ++n;
            id = uint32(uint256(logs[i].topics[1]));
            (kind, bps) = abi.decode(logs[i].data, (uint8, uint16));
        }
    }

    function _assertConsumedBy(Vm.Log[] memory logs, uint32 id, uint8 kind) private view {
        (uint256 n, uint32 topicId, uint8 k, uint16 bps) = _consumed(logs);
        assertEq(n, 1, "one BoonConsumed");
        assertEq(topicId, id, "BoonConsumed topic is the wallet ID");
        assertEq(k, kind, "boon type");
        assertGt(bps, 0, "live boon pays");
    }

    function _assertNoWritesTo(bytes32 a, bytes32 b) private {
        (, bytes32[] memory writes) = vm.accesses(address(game));
        for (uint256 i; i < writes.length; ++i) {
            assertTrue(writes[i] != a && writes[i] != b, "no write under ID 0");
        }
    }

    function _price() private view returns (uint256) {
        return PriceLookupLib.priceForLevel(game.level() + 1);
    }

    function _placeBet(address who, uint8 currency, uint128 perSpin, uint8 spins, uint8 symbol) private {
        vm.prank(who);
        game.placeDegeneretteBet{value: currency == 0 ? uint256(perSpin) * spins : 0}(
            address(0), currency, perSpin, spins, symbol
        );
    }

    // ---------------------------------------------------------------------
    // (a) Producers write boonPacked[id]
    // ---------------------------------------------------------------------

    function test_BoxRollSingleTierWritesById() public {
        (address player, uint32 id) = _wallet("roll_single");
        uint24 lvl = game.level() + 1;
        bool wrote;
        for (uint256 k; k < 64 && !wrote; ++k) {
            uint256 snap = vm.snapshotState();
            ext.x_delegate(
                ContractAddresses.GAME_BOON_MODULE,
                abi.encodeCall(
                    DegenerusGameBoonModule.rollBoxBoons,
                    (player, id, 100 ether, 4, 1 ether, lvl, uint256(keccak256(abi.encode("single", k))), 0)
                )
            );
            (uint256 s0, uint256 s1) = _boon(id);
            if (s0 | s1 == 0) {
                vm.revertToState(snap);
                continue;
            }
            wrote = true;
            _assertIdZeroEmpty();
        }
        assertTrue(wrote, "fixture: a box roll stored a boon");
    }

    function test_BoxRollMixedTiersWritesById() public {
        (address player, uint32 id) = _wallet("roll_mixed");
        uint24 lvl = game.level() + 1;
        uint256[5] memory amounts = [uint256(1 ether), 5 ether, 25 ether, 2 ether, 0];
        uint40 counts = uint40(1) | (uint40(1) << 8) | (uint40(1) << 16) | (uint40(1) << 24);
        bool wrote;
        for (uint256 k; k < 64 && !wrote; ++k) {
            uint256 snap = vm.snapshotState();
            ext.x_delegate(
                ContractAddresses.GAME_BOON_MODULE,
                abi.encodeCall(
                    DegenerusGameBoonModule.rollBoxBoonTiers,
                    (player, id, amounts, counts, lvl, uint256(keccak256(abi.encode("mixed", k))))
                )
            );
            (uint256 s0, uint256 s1) = _boon(id);
            if (s0 | s1 == 0) {
                vm.revertToState(snap);
                continue;
            }
            wrote = true;
            _assertIdZeroEmpty();
        }
        assertTrue(wrote, "fixture: a mixed-tier roll stored a boon");
    }

    function test_DeityGiftWritesRecipientId() public {
        (address deity,) = _wallet("gift_deity");
        ext.x_grantDeity(deity);
        uint24 day = uint24(_today());
        RecyclingState.seedDailyWord(address(game), day - 1, uint256(keccak256("gift_menu")));
        bool applied;
        for (uint8 slot; slot < 3; ++slot) {
            (address recipient, uint32 rid) = _wallet(string(abi.encodePacked("gift_recipient_", vm.toString(slot))));
            vm.recordLogs();
            vm.prank(deity);
            game.issueDeityBoon(deity, recipient, slot);
            Vm.Log[] memory logs = vm.getRecordedLogs();
            (uint256 s0, uint256 s1) = _boon(rid);
            (uint256 n, uint32 topicId,,) = _consumed(logs);
            // A stored boon lands in the recipient's ID lanes; an activity award reports its ID.
            if (s0 | s1 != 0) applied = true;
            if (n != 0) {
                assertEq(topicId, rid, "activity award keyed by the recipient ID");
                applied = true;
            }
        }
        assertTrue(applied, "a deity gift reached the recipient ID");
        _assertIdZeroEmpty();
    }

    function test_ProtocolDrawWritesWinnerId() public {
        (address player, uint32 id) = _wallet("protocol_draw_player");
        vm.deal(player, 10 ether);
        uint24 betDay = uint24(_today());
        // Symbol 0 is the VAULT's protocol deity symbol: an ETH bet on it enters the VAULT draw.
        _placeBet(player, 0, 0.05 ether, 1, 0);

        vm.warp(block.timestamp + 1 days);
        uint24 awardDay = uint24(_today());
        RecyclingState.seedDailyWord(address(game), betDay, uint256(keccak256("protocol_menu")));
        RecyclingState.seedDailyWord(address(game), awardDay, uint256(keccak256("protocol_winner")));

        vm.recordLogs();
        ext.x_delegate(
            ContractAddresses.GAME_BOON_MODULE,
            abi.encodeCall(DegenerusGameBoonModule.resolveProtocolBoonDraws, (awardDay))
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 awards;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == PROTOCOL_BOON_AWARDED) {
                ++awards;
                assertEq(address(uint160(uint256(logs[i].topics[2]))), player, "the only entrant wins");
            }
            if (logs[i].emitter == address(game) && logs[i].topics[0] == BOON_CONSUMED) {
                assertEq(uint32(uint256(logs[i].topics[1])), id, "activity award keyed by the winner ID");
            }
        }
        assertEq(awards, 3, "three awards drawn");
        (uint256 s0, uint256 s1) = _boon(id);
        (uint256 n,,,) = _consumed(logs);
        assertTrue(s0 | s1 != 0 || n != 0, "the winner's ID received the award");
        _assertIdZeroEmpty();
    }

    // ---------------------------------------------------------------------
    // (b) Consumers read and clear by ID; (f) BoonConsumed carries the ID
    // ---------------------------------------------------------------------

    function test_CoinflipDepositConsumesById() public {
        (address player, uint32 id) = _wallet("cf_boon");
        ext.x_setBoon(id, (uint256(1) << COINFLIP_TIER) | _today(), 0);
        vm.prank(address(game));
        coin.mintForGame(player, 10_000);

        vm.recordLogs();
        vm.prank(player);
        coinflip.depositCoinflip(player, 1_000);

        _assertConsumedBy(vm.getRecordedLogs(), id, 1);
        (uint256 s0,) = _boon(id);
        assertEq((s0 >> COINFLIP_TIER) & 0xFF, 0, "coinflip lane cleared");
        _assertIdZeroEmpty();
    }

    function test_CrapsLaneConsumedByIdThroughFlip() public {
        (address player, uint32 id) = _wallet("craps_boon");
        ext.x_setBoon(id, 0, _lane(1));
        vm.prank(address(game));
        coin.mintForGame(player, 10_000);

        vm.recordLogs();
        vm.prank(ContractAddresses.CRAPS);
        uint8 mask = coin.burnCoinForCraps(player, id, uint256(1_000) << 8);

        assertEq(mask, 1, "tier-1 craps boon mask");
        _assertConsumedBy(vm.getRecordedLogs(), id, 6);
        (, uint256 s1) = _boon(id);
        assertEq(s1 & 0xFFFFFF, 0, "craps lane cleared");
        _assertIdZeroEmpty();
    }

    function test_WwxrpEnterConsumesById() public {
        (address player, uint32 id) = _wallet("wwxrp_enter_boon");
        ext.x_setBoon(id, 0, _lane(1) << WWXRP_LANE);
        vm.prank(ContractAddresses.VAULT);
        wwxrp.vaultMintTo(player, 1_000);

        // The WWXRP raw read lands on the getter's slot.
        bytes32 slot1 = bytes32(uint256(keccak256(abi.encode(uint256(id), BOON_PACKED_SLOT))) + 1);
        (, uint256 s1) = _boon(id);
        assertEq(uint256(vm.load(address(game), slot1)), s1, "raw slot1 equals the getter");

        vm.recordLogs();
        vm.prank(player);
        wwxrp.enter(100);

        _assertConsumedBy(vm.getRecordedLogs(), id, 7);
        (, s1) = _boon(id);
        assertEq((s1 >> WWXRP_LANE) & 0xFFFFFF, 0, "WWXRP lane cleared");
        _assertIdZeroEmpty();
    }

    function test_WwxrpTrustedMinterConsumesById() public {
        (address player, uint32 id) = _wallet("wwxrp_minter_boon");
        ext.x_setBoon(id, 0, _lane(2) << WWXRP_LANE);
        address owner = makeAddr("wwxrp_owner");
        address minter = makeAddr("wwxrp_minter");
        vm.mockCall(ContractAddresses.VAULT, abi.encodeWithSignature("isVaultOwner(address)", owner), abi.encode(true));
        vm.prank(owner);
        wwxrp.setTrustedMinter(minter, true);

        vm.recordLogs();
        vm.prank(minter);
        uint16 bps = wwxrp.consumeBoon(player);

        assertEq(bps, 800, "tier-2 WWXRP boon");
        _assertConsumedBy(vm.getRecordedLogs(), id, 7);
        // A wallet without an ID has no boon.
        vm.prank(minter);
        assertEq(wwxrp.consumeBoon(makeAddr("wwxrp_no_id")), 0, "no ID, no boon");
        _assertIdZeroEmpty();
    }

    function test_PurchaseBoostConsumedById() public {
        (address buyer, uint32 id) = _wallet("purchase_boon");
        ext.x_setBoon(id, (uint256(1) << PURCHASE_TIER) | (_today() << PURCHASE_DAY), 0);
        vm.deal(buyer, 10 ether);

        uint256 value = 4 * _price();
        vm.recordLogs();
        vm.prank(buyer);
        game.purchase{value: value}(buyer, 1_600, 0, bytes32(0), MintPaymentKind.DirectEth, false);

        _assertConsumedBy(vm.getRecordedLogs(), id, 2);
        (uint256 s0,) = _boon(id);
        assertEq((s0 >> PURCHASE_TIER) & 0xFF, 0, "purchase lane cleared");
        _assertIdZeroEmpty();
    }

    function test_DecimatorBurnConsumesById() public {
        (address player, uint32 id) = _wallet("decimator_boon");
        ext.x_setBoon(id, uint256(1) << DECIMATOR_TIER, 0);
        ext.x_openDecWindow();
        vm.prank(address(game));
        coin.mintForGame(player, 10_000);

        vm.recordLogs();
        vm.prank(player);
        coin.decimatorBurn(address(0), 2_000, 0);

        _assertConsumedBy(vm.getRecordedLogs(), id, 3);
        (uint256 s0,) = _boon(id);
        assertEq((s0 >> DECIMATOR_TIER) & 0xFF, 0, "decimator lane cleared");
        _assertIdZeroEmpty();
    }

    function test_DegeneretteEthLaneConsumedById() public {
        (address player, uint32 id) = _wallet("degen_eth_boon");
        ext.x_setBoon(id, 0, _lane(1) << DEGEN_ETH_LANE);
        vm.deal(player, 10 ether);

        vm.recordLogs();
        _placeBet(player, 0, 0.01 ether, 1, 9);

        _assertConsumedBy(vm.getRecordedLogs(), id, 4);
        (, uint256 s1) = _boon(id);
        assertEq((s1 >> DEGEN_ETH_LANE) & 0xFFFFFF, 0, "ETH lane cleared");
        _assertIdZeroEmpty();
    }

    function test_DegeneretteFlipLaneConsumedById() public {
        (address player, uint32 id) = _wallet("degen_flip_boon");
        ext.x_setBoon(id, 0, (_lane(1) << DEGEN_FLIP_LANE) | (_lane(1) << DEGEN_ETH_LANE));
        vm.prank(address(game));
        coin.mintForGame(player, 100_000);

        vm.recordLogs();
        _placeBet(player, 1, 1_000, 1, 9);

        _assertConsumedBy(vm.getRecordedLogs(), id, 4);
        (, uint256 s1) = _boon(id);
        assertEq((s1 >> DEGEN_FLIP_LANE) & 0xFFFFFF, 0, "FLIP lane cleared");
        assertTrue((s1 >> DEGEN_ETH_LANE) & 0xFFFFFF != 0, "the other currency's lane is untouched");
        _assertIdZeroEmpty();
    }

    function test_LootboxBoostConsumedByIdOnPurchase() public {
        (address buyer, uint32 id) = _wallet("box_boost_buyer");
        ext.x_setBoon(id, (uint256(1) << LOOTBOX_TIER) | (_today() << LOOTBOX_DAY), 0);
        vm.deal(buyer, 10 ether);

        uint256 value = _price();
        vm.recordLogs();
        vm.prank(buyer);
        game.purchase{value: value}(buyer, 0, 1, bytes32(0), MintPaymentKind.DirectEth, false);

        _assertBoostUsed(vm.getRecordedLogs(), buyer);
        (uint256 s0,) = _boon(id);
        assertEq((s0 >> LOOTBOX_TIER) & 0xFF, 0, "lootbox lane cleared");
        _assertIdZeroEmpty();
    }

    function test_LootboxBoostConsumedByIdOnPassCover() public {
        (address buyer, uint32 id) = _wallet("cover_boost_buyer");
        ext.x_setBoon(id, (uint256(1) << LOOTBOX_TIER) | (_today() << LOOTBOX_DAY), 0);
        vm.deal(buyer, 10 ether);

        vm.recordLogs();
        vm.prank(buyer);
        game.purchaseWhalePass{value: 4 ether}(buyer, 1, bytes32(0));

        _assertBoostUsed(vm.getRecordedLogs(), buyer);
        (uint256 s0,) = _boon(id);
        assertEq((s0 >> LOOTBOX_TIER) & 0xFF, 0, "lootbox lane cleared by the cover box");
        _assertIdZeroEmpty();
    }

    function _assertBoostUsed(Vm.Log[] memory logs, address player) private view {
        uint256 n;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == BOOST_USED) {
                ++n;
                assertEq(address(uint160(uint256(logs[i].topics[1]))), player, "boost used by the buyer");
            }
        }
        assertEq(n, 1, "one BoostUsed");
    }

    /// @dev Afking overpay of a pass purchase (the discount shows as a larger overpay).
    function _whaleOverpay(address buyer) private returns (uint256) {
        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        game.purchaseWhalePass{value: 5 ether}(buyer, 1, bytes32(0));
        return game.afkingFundingOf(buyer);
    }

    function _whaleCost(address buyer, uint256 quantity) private returns (uint256) {
        vm.deal(buyer, 30 ether);
        vm.prank(buyer);
        game.purchaseWhalePass{value: 20 ether}(buyer, quantity, bytes32(0));
        return 20 ether - game.afkingFundingOf(buyer);
    }

    function _lazyOverpay(address buyer) private returns (uint256) {
        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        game.purchaseLazyPass{value: 2 ether}(buyer, bytes32(0));
        return game.afkingFundingOf(buyer);
    }

    function _deityPrice(address buyer, uint8 symbol) private returns (uint256 price) {
        vm.deal(buyer, 500 ether);
        vm.recordLogs();
        vm.prank(buyer);
        game.purchaseDeityPass{value: 400 ether}(buyer, symbol, bytes32(0));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == DEITY_PURCHASED) {
                (, price,) = abi.decode(logs[i].data, (uint8, uint256, uint24));
            }
        }
        assertGt(price, 0, "DeityPassPurchased emitted");
    }

    /// @notice A whale boon only ever lowers the quote: its tier comes off the level's price for
    ///         the first pass and every further pass pays that same price, so at the intro levels a
    ///         boon buyer never pays more than a boonless one.
    function testFuzz_WhaleBoonNeverPricesAboveTheBoonlessQuote(uint8 tierSeed, uint8 qtySeed) public {
        uint256 tier = 1 + uint256(tierSeed) % 3;
        uint256 quantity = 1 + uint256(qtySeed) % 5;
        uint256 bps = tier == 3 ? 3500 : tier == 2 ? 2000 : 1000;

        (address plain,) = _wallet("whale_plain_q");
        uint256 snap = vm.snapshotState();
        uint256 plainCost = _whaleCost(plain, quantity);
        vm.revertToState(snap);

        (address boosted, uint32 id) = _wallet("whale_boosted_q");
        ext.x_setBoon(id, (tier << WHALE_TIER) | (_today() << WHALE_DAY), 0);
        uint256 boostedCost = _whaleCost(boosted, quantity);

        assertEq(plainCost, quantity * 2.4 ether, "boonless intro quote");
        assertEq(boostedCost, 2.4 ether * (10_000 - bps) / 10_000 + (quantity - 1) * 2.4 ether, "boon off the intro price");
        assertLt(boostedCost, plainCost, "a boon never raises the quote");
    }

    function test_WhaleDiscountReadsAndClearsById() public {
        (address plain,) = _wallet("whale_plain");
        uint256 snap = vm.snapshotState();
        uint256 plainOverpay = _whaleOverpay(plain);
        vm.revertToState(snap);

        (address boosted, uint32 id) = _wallet("whale_boosted");
        ext.x_setBoon(id, (uint256(1) << WHALE_TIER) | (_today() << WHALE_DAY), 0);
        uint256 boostedOverpay = _whaleOverpay(boosted);

        // A live boon takes its tier (10%) off the level's price: the level-1 pass costs the
        // 2.4 ETH intro price without one and 2.16 ETH with it.
        assertEq(5 ether - plainOverpay, 2.4 ether, "boonless intro price");
        assertEq(5 ether - boostedOverpay, 2.16 ether, "the ID's whale boon priced the pass");
        (uint256 s0,) = _boon(id);
        assertEq(s0 >> WHALE_TIER, 0, "whale lane cleared");
        _assertIdZeroEmpty();
    }

    function test_LazyDiscountReadsAndClearsById() public {
        (address plain,) = _wallet("lazy_plain");
        uint256 snap = vm.snapshotState();
        uint256 plainOverpay = _lazyOverpay(plain);
        vm.revertToState(snap);

        (address boosted, uint32 id) = _wallet("lazy_boosted");
        ext.x_setBoon(id, 0, (uint256(1) << LAZY_TIER) | (_today() << LAZY_DAY));
        uint256 boostedOverpay = _lazyOverpay(boosted);

        assertGt(boostedOverpay, plainOverpay, "the ID's lazy boon discounts the price");
        (, uint256 s1) = _boon(id);
        assertEq((s1 >> LAZY_TIER) & 0xFF, 0, "lazy lane cleared");
        _assertIdZeroEmpty();
    }

    function test_DeityDiscountReadsAndClearsById() public {
        (address plain,) = _wallet("deity_plain");
        uint256 snap = vm.snapshotState();
        uint256 plainPrice = _deityPrice(plain, 3);
        vm.revertToState(snap);

        (address boosted, uint32 id) = _wallet("deity_boosted");
        ext.x_setBoon(id, 0, (uint256(1) << DEITY_PASS_TIER) | (_today() << DEITY_PASS_DAY));
        uint256 boostedPrice = _deityPrice(boosted, 3);

        assertEq(boostedPrice, plainPrice * 9_000 / 10_000, "tier-1 deity boon: 10% off");
        (, uint256 s1) = _boon(id);
        assertEq((s1 >> DEITY_PASS_TIER) & 0xFF, 0, "deity lane cleared");
        _assertIdZeroEmpty();
    }

    // ---------------------------------------------------------------------
    // (c) Consumers called with ID 0 return 0 and write nothing
    // ---------------------------------------------------------------------

    function test_IdZeroConsumersReturnZeroAndWriteNothing() public {
        bytes32 s0Slot = GameSlotKeys.byId(0, BOON_PACKED_SLOT);
        bytes32 s1Slot = bytes32(uint256(s0Slot) + 1);
        vm.record();

        vm.prank(ContractAddresses.COINFLIP);
        assertEq(game.consumeCoinflipBoon(0), 0, "coinflip lane");
        vm.prank(ContractAddresses.COIN);
        assertEq(game.consumeCoinflipBoon(0), 0, "craps lane");
        vm.prank(ContractAddresses.WWXRP);
        assertEq(game.consumeCoinflipBoon(0), 0, "WWXRP lane");
        vm.prank(ContractAddresses.COIN);
        assertEq(game.consumeDecimatorBoon(0), 0, "decimator");

        // The module bodies themselves (past the façade's tier early-out).
        address boon = ContractAddresses.GAME_BOON_MODULE;
        assertEq(abi.decode(ext.x_delegate(boon, abi.encodeCall(DegenerusGameBoonModule.consumeCoinflipBoon, (0))), (uint16)), 0);
        assertEq(abi.decode(ext.x_delegate(boon, abi.encodeCall(DegenerusGameBoonModule.consumeDecimatorBoost, (0))), (uint16)), 0);
        assertEq(abi.decode(ext.x_delegate(boon, abi.encodeCall(DegenerusGameBoonModule.consumePurchaseBoost, (0))), (uint16)), 0);
        assertEq(abi.decode(ext.x_delegate(boon, abi.encodeCall(DegenerusGameBoonModule.consumeDegeneretteBoon, (0, 0))), (uint16)), 0);
        assertEq(abi.decode(ext.x_delegate(boon, abi.encodeCall(DegenerusGameBoonModule.consumeDegeneretteBoon, (0, 1))), (uint16)), 0);
        assertFalse(abi.decode(ext.x_delegate(boon, abi.encodeCall(DegenerusGameBoonModule.checkAndClearExpiredBoon, (0))), (bool)));

        _assertNoWritesTo(s0Slot, s1Slot);
        _assertIdZeroEmpty();
    }

    // ---------------------------------------------------------------------
    // (d) An unregistered pass buyer gets no discount and registers
    // ---------------------------------------------------------------------

    function _assertRegisteredOnce(Vm.Log[] memory logs, address who) private view returns (uint32 id) {
        uint256 n;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == WALLET_REGISTERED
                && address(uint160(uint256(logs[i].topics[2]))) == who) {
                ++n;
                id = uint32(uint256(logs[i].topics[1]));
            }
        }
        assertEq(n, 1, "registered exactly once");
        assertEq(game.walletIdOf(who), id, "walletIdOf");
        assertEq(game.mintPackedFor(who) >> BitPackingLib.WALLET_ID_SHIFT, id, "mint word carries the ID");
        assertEq(address(uint160(uint256(vm.load(address(game), GameSlotKeys.walletElement(id))))), who, "element holds the key");
    }

    function test_UnregisteredWhaleBuyerPaysFullAndRegisters() public {
        (address plain,) = _wallet("whale_registered_plain");
        uint256 snap = vm.snapshotState();
        uint256 plainOverpay = _whaleOverpay(plain);
        vm.revertToState(snap);

        address fresh = makeAddr("whale_unregistered");
        vm.recordLogs();
        uint256 freshOverpay = _whaleOverpay(fresh);
        _assertRegisteredOnce(vm.getRecordedLogs(), fresh);
        assertEq(freshOverpay, plainOverpay, "no discount: the same price as a boonless buyer");
        _assertIdZeroEmpty();
    }

    function test_UnregisteredLazyBuyerPaysFullAndRegisters() public {
        (address plain,) = _wallet("lazy_registered_plain");
        uint256 snap = vm.snapshotState();
        uint256 plainOverpay = _lazyOverpay(plain);
        vm.revertToState(snap);

        address fresh = makeAddr("lazy_unregistered");
        vm.recordLogs();
        uint256 freshOverpay = _lazyOverpay(fresh);
        _assertRegisteredOnce(vm.getRecordedLogs(), fresh);
        assertEq(freshOverpay, plainOverpay, "no discount: the same price as a boonless buyer");
        _assertIdZeroEmpty();
    }

    function test_UnregisteredDeityBuyerPaysFullAndRegisters() public {
        (address plain,) = _wallet("deity_registered_plain");
        uint256 snap = vm.snapshotState();
        uint256 plainPrice = _deityPrice(plain, 5);
        vm.revertToState(snap);

        address fresh = makeAddr("deity_unregistered");
        vm.recordLogs();
        vm.deal(fresh, 500 ether);
        vm.prank(fresh);
        game.purchaseDeityPass{value: 400 ether}(fresh, 5, bytes32(0));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _assertRegisteredOnce(logs, fresh);
        uint256 freshPrice;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == DEITY_PURCHASED) {
                (, freshPrice,) = abi.decode(logs[i].data, (uint8, uint256, uint24));
            }
        }
        assertEq(freshPrice, plainPrice, "no discount: the base price");
        _assertIdZeroEmpty();
    }

    // ---------------------------------------------------------------------
    // (e) Slot pin
    // ---------------------------------------------------------------------

    function test_BoonPackedSlotPin() public {
        assertEq(ext.x_boonPackedSlot(), BOON_PACKED_SLOT, "boonPacked.slot");
        assertEq(GameSlots.BOON_PACKED, BOON_PACKED_SLOT, "GameSlots pin");
        (, uint32 id) = _wallet("slot_pin");
        uint256 s0 = (uint256(2) << COINFLIP_TIER) | _today();
        uint256 s1 = (_lane(3) << WWXRP_LANE) | _lane(1);
        ext.x_setBoon(id, s0, s1);
        bytes32 base = keccak256(abi.encode(uint256(id), BOON_PACKED_SLOT));
        (uint256 g0, uint256 g1) = _boon(id);
        assertEq(uint256(vm.load(address(game), base)), g0, "raw slot0 equals the getter");
        assertEq(uint256(vm.load(address(game), bytes32(uint256(base) + 1))), g1, "raw slot1 equals the getter");
        assertEq((g1 >> WWXRP_LANE) & 3, 3, "WWXRP lane tier at its shift");
    }
}
