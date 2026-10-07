// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {stdError} from "forge-std/StdError.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Coinflip} from "../../contracts/Coinflip.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {DegenerusQuests} from "../../contracts/DegenerusQuests.sol";
import {DegenerusJackpots} from "../../contracts/DegenerusJackpots.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";

/// @title CoinflipWalletIds -- Coinflip keyed by wallet ID on the real protocol
/// @notice Stakes, claim banks, rebuy state, BAF draw entries and record payees use Game IDs.
///         Paid self deposits and gift funders register through Game. Self claims only look up
///         the ordinary ID; an unregistered wallet has no state to settle. Configuring rebuy
///         registers the caller under the same admission policy. Explicit IDs are authorized
///         through Game; credits carry IDs directly and skip zero IDs and amounts.
contract CoinflipWalletIdsTest is DeployProtocol {
    address internal constant GAME = ContractAddresses.GAME;
    address internal constant COIN = ContractAddresses.COIN;
    address internal constant VAULT = ContractAddresses.VAULT;
    address internal constant SDGNRS = ContractAddresses.SDGNRS;
    address internal constant CRAPS = ContractAddresses.CRAPS;

    bytes32 internal constant WALLET_REGISTERED = keccak256("WalletRegistered(uint32,address)");
    bytes32 internal constant STAKE_UPDATED = keccak256("CoinflipStakeUpdated(uint32,uint24,uint256,uint256)");
    bytes32 internal constant BAF_DRAW_ENTERED = keccak256("BafDrawEntered(uint24,uint32,uint32,uint96,uint96)");
    bytes32 internal constant BIG_RECORD = keccak256("BigRecordUpdated(uint8,uint32,uint256,uint128,uint256)");
    bytes32 internal constant BAF_DRAW_TAG = "COINFLIP_BAF_DRAW_WINNER";

    /// @dev Coinflip storage roots (scripts/layout/golden/Coinflip.json).
    uint256 internal constant STAKE_ROOT = 0;
    uint256 internal constant PLAYER_STATE_ROOT = 2;
    uint256 internal constant CLAIMABLE_DAY_SLOT = 4;
    uint256 internal constant BAF_DRAW_ENTRY_ROOT = 8;
    /// @dev DegenerusJackpots storage roots (scripts/layout/golden/DegenerusJackpots.json).
    uint256 internal constant BAF_PLAYER_ROOT = 0;
    uint256 internal constant BAF_TOP_ROOT = 1;
    uint256 internal constant BAF_LEVEL_ROOT = 2;

    uint256 internal constant STAKE_LANE_MAX = type(uint32).max;
    uint256 internal constant SEED = 200_000;
    uint256 internal constant PAST_PAID_ADMISSION = 3_000_000_001;
    uint8 internal constant KIND_SPIN = 1;
    uint8 internal constant KIND_DICE_RUN = 4;

    function setUp() public {
        _deployProtocol();
    }

    // =====================================================================
    //                              helpers
    // =====================================================================

    function _today() internal view returns (uint24) {
        return uint24((block.timestamp - 82_620) / 1 days) - uint24(ContractAddresses.DEPLOY_DAY_BOUNDARY) + 1;
    }

    function _warpToDay(uint24 d) internal {
        vm.warp((uint256(d - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621);
    }

    function _resolve(uint24 d, bool win) internal {
        uint256 word = uint256(keccak256(abi.encodePacked("coinflip_wallet_ids", d)));
        word = win ? word | 1 : word & ~uint256(1);
        vm.prank(GAME);
        coinflip.processCoinflipPayouts(0, word, d);
    }

    function _fund(address p, uint256 amount) internal {
        vm.prank(GAME);
        coin.mintForGame(p, amount);
    }

    function _slotA(address p) internal view returns (uint256) {
        return uint256(vm.load(address(coinflip), keccak256(abi.encode(_gameId(p), PLAYER_STATE_ROOT))));
    }


    function _lastClaim(address p) internal view returns (uint24) {
        return uint24(_slotA(p) >> 128);
    }

    function _claimableDay() internal view returns (uint24) {
        return uint24(uint256(vm.load(address(coinflip), bytes32(CLAIMABLE_DAY_SLOT))));
    }

    /// @dev The Game's wallet ID for `p`, read from its canonical registry slot (no call).
    function _gameId(address p) internal view returns (uint32) {
        return uint32(uint256(vm.load(address(game), GameSlotKeys.walletId(p))));
    }

    function _walletCount() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(GameSlots.WALLETS)));
    }

    function _stakeSlot(uint24 key, uint32 id) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(id), keccak256(abi.encode(uint256(key), STAKE_ROOT))));
    }

    function _lane(uint24 day, uint32 id) internal view returns (uint256) {
        return uint32(uint256(vm.load(address(coinflip), _stakeSlot(day >> 3, id))) >> ((uint256(day) & 7) * 32));
    }

    function _drawEntryRaw(uint24 day, uint32 index) internal view returns (uint256) {
        return uint256(vm.load(
            address(coinflip), keccak256(abi.encode((uint256(day) << 32) | index, BAF_DRAW_ENTRY_ROOT))
        ));
    }

    function _bafTotal(uint24 lvl, uint32 id) internal view returns (uint256) {
        bytes32 slot = keccak256(abi.encode(uint256(id), keccak256(abi.encode(uint256(lvl), BAF_PLAYER_ROOT))));
        return uint192(uint256(vm.load(address(jackpots), slot)));
    }

    /// @dev WalletRegistered events from the Game in `logs`: count, last ID and last owner.
    function _registrations(Vm.Log[] memory logs)
        internal view returns (uint256 n, uint32 lastId, address lastOwner)
    {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics[0] != WALLET_REGISTERED) continue;
            ++n;
            lastId = uint32(uint256(logs[i].topics[1]));
            lastOwner = address(uint160(uint256(logs[i].topics[2])));
        }
    }

    function _count(Vm.Log[] memory logs, address emitter, bytes32 topic) internal pure returns (uint256 n) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == emitter && logs[i].topics[0] == topic) ++n;
        }
    }

    /// @dev No write in `writes` hits the stake ledger under wallet key 0 for any day key up to `maxDay`.
    function _assertNoKeyZeroWrite(bytes32[] memory writes, uint24 maxDay) internal pure {
        for (uint24 k; k <= (maxDay >> 3) + 1; ++k) {
            bytes32 zeroSlot = _stakeSlot(k, 0);
            for (uint256 i; i < writes.length; ++i) {
                assertTrue(writes[i] != zeroSlot, "stake ledger written under wallet key 0");
            }
        }
    }

    /// @dev The BAF draw winner by the reference rule: the first entry whose cumulative endpoint
    ///      exceeds the domain-separated roll.
    function _refDrawWinner(uint24 day, uint256 rngWord) internal view returns (uint32) {
        (, uint96 total, uint32 count) = coinflip.bafDrawInfo();
        if (total == 0) return 0;
        uint256 roll = uint256(keccak256(abi.encodePacked(BAF_DRAW_TAG, address(coinflip), day, rngWord))) % total;
        for (uint32 i; i < count; ++i) {
            uint256 e = _drawEntryRaw(day, i);
            if (uint96(e) > roll) return uint32(e >> 96);
        }
        return 0;
    }


    // =====================================================================
    //                         deposits and admission
    // =====================================================================

    /// @notice A first self deposit registers the wallet once, keys the stake lane
    ///         and the stake event by it, and hands the quest the same ID.
    function test_FirstSelfDeposit_RegistersOnce_StakesAndQuestsById() public {
        address p = makeAddr("first_depositor");
        _fund(p, 10_000);
        uint32 expectedId = uint32(_walletCount());
        assertEq(_gameId(p), 0);

        vm.expectCall(GAME, abi.encodeCall(DegenerusGame.registerWallet, (p, true)), 1);
        vm.expectCall(address(quests), abi.encodeCall(DegenerusQuests.handleFlip, (expectedId, 1_000)), 1);
        vm.recordLogs();
        vm.prank(p);
        coinflip.depositCoinflip(0, 1_000);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        (uint256 n, uint32 rid, address owner) = _registrations(logs);
        assertEq(n, 1, "exactly one WalletRegistered");
        assertEq(rid, expectedId);
        assertEq(owner, p);
        assertEq(_gameId(p), expectedId);
        uint24 target = _today() + 1;
        assertEq(_lane(target, expectedId), 1_000, "stake keyed by the ID");
        bool seen;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(coinflip) || logs[i].topics[0] != STAKE_UPDATED) continue;
            assertEq(uint32(uint256(logs[i].topics[1])), expectedId, "stake event carries the ID");
            assertEq(uint24(uint256(logs[i].topics[2])), target);
            seen = true;
        }
        assertTrue(seen, "stake event emitted");
    }


    /// @notice An approved operator's deposit runs on the PLAYER's ID (who pays), never the
    ///         operator's; the supplied ID needs no registration.
    function test_OperatorDeposit_UsesPlayerIdNotOperator() public {
        address p = makeAddr("op_player");
        address o = makeAddr("op_operator");
        _fund(p, 10_000);
        uint32 expectedId = _giveWalletId(p);
        vm.prank(p);
        game.setOperatorApproval(0, o, true);

        vm.expectCall(GAME, abi.encodeWithSelector(DegenerusGame.registerWallet.selector), 0);
        vm.expectCall(GAME, abi.encodeCall(DegenerusGame.resolveAccount, (expectedId, o)), 1);
        vm.expectCall(address(quests), abi.encodeCall(DegenerusQuests.handleFlip, (expectedId, 1_000)), 1);
        vm.recordLogs();
        vm.prank(o);
        coinflip.depositCoinflip(expectedId, 1_000);

        (uint256 n,,) = _registrations(vm.getRecordedLogs());
        assertEq(n, 0, "no registration on an ID-addressed deposit");
        assertEq(_gameId(o), 0, "operator not registered");
        assertEq(coin.balanceOf(p), 9_000, "the player funds an operator deposit");
        assertEq(_lane(_today() + 1, expectedId), 1_000);
    }

    /// @notice A gift to an unallocated ID reverts the Game's E (a recipient is never
    ///         registered by someone else's payment).
    function test_GiftToUnallocatedId_Reverts() public {
        address f = makeAddr("gift_funder");
        address r = makeAddr("gift_idless_recipient");
        _fund(f, 10_000);
        uint32 unallocated = uint32(_walletCount());
        vm.expectRevert(abi.encodeWithSignature("E()"));
        vm.prank(f);
        coinflip.depositCoinflip(unallocated, 1_000);
        assertEq(_gameId(r), 0);
        assertEq(_gameId(f), 0);
        assertEq(coin.balanceOf(f), 10_000);
    }

    /// @notice A gift to a registered recipient with no prior Coinflip activity works: the recipient
    ///         is resolved by ID; the paying funder registers and its quest
    ///         gets the funder's ID; the stake is the recipient's.
    function test_GiftToRegisteredRecipient_RegistersFunderForQuest() public {
        address f = makeAddr("gift_funder_2");
        address r = makeAddr("gift_recipient");
        uint32 rid = _giveWalletId(r);
        _fund(f, 10_000);
        uint32 fid = uint32(_walletCount());

        vm.expectCall(GAME, abi.encodeCall(DegenerusGame.resolveAccount, (rid, f)), 1);
        vm.expectCall(GAME, abi.encodeWithSelector(DegenerusGame.registerWallet.selector, r), 0);
        vm.expectCall(GAME, abi.encodeCall(DegenerusGame.registerWallet, (f, true)), 1);
        vm.expectCall(address(quests), abi.encodeCall(DegenerusQuests.handleFlip, (fid, 1_000)), 1);
        vm.recordLogs();
        vm.prank(f);
        coinflip.depositCoinflip(rid, 1_000);

        (uint256 n, uint32 regId, address owner) = _registrations(vm.getRecordedLogs());
        assertEq(n, 1, "only the funder registers");
        assertEq(regId, fid);
        assertEq(owner, f);
        uint24 target = _today() + 1;
        assertEq(_lane(target, rid), 1_000, "stake is the recipient's");
        assertEq(_lane(target, fid), 0);
        assertEq(coin.balanceOf(f), 9_000, "the funder pays from its wallet");
    }

    /// @notice Past PAID_ADMISSION_WALLETS the hook refuses new wallets (a new depositor and a new
    ///         gift funder revert with the Game's E); existing IDs, with or without prior deposits, still deposit.
    function test_PastPaidAdmission_NewDepositorReverts_ExistingDeposits() public {
        address repeat = makeAddr("adm_repeat");
        address registered = makeAddr("adm_registered");
        address fresh = makeAddr("adm_new");
        _fund(repeat, 10_000);
        _fund(registered, 10_000);
        _fund(fresh, 10_000);
        vm.prank(repeat);
        coinflip.depositCoinflip(0, 1_000);
        uint32 cid = _gameId(repeat);
        uint32 uid = _giveWalletId(registered);

        vm.store(address(game), bytes32(GameSlots.WALLETS), bytes32(PAST_PAID_ADMISSION));

        vm.expectRevert(abi.encodeWithSignature("E()"));
        vm.prank(fresh);
        coinflip.depositCoinflip(0, 1_000);
        vm.expectRevert(abi.encodeWithSignature("E()"));
        vm.prank(fresh);
        coinflip.depositCoinflip(cid, 1_000);

        vm.prank(repeat);
        coinflip.depositCoinflip(0, 1_000);
        vm.prank(registered);
        coinflip.depositCoinflip(0, 1_000);

        uint24 target = _today() + 1;
        assertEq(_lane(target, cid), 2_000);
        assertEq(_lane(target, uid), 1_000);
        assertEq(_gameId(fresh), 0);
        assertEq(coin.balanceOf(fresh), 10_000);
    }

    // =====================================================================
    //                        credits, claims, ID-less
    // =====================================================================

    /// @notice A credit by ID to a wallet that never touched Coinflip shows in the views through
    ///         walletIdOf; claims resolve that canonical ID without allocation, record BAF by ID
    ///         and mint to the caller.
    function test_CreditById_VisibleBeforeFirstClaim_MintsToCaller() public {
        address p = makeAddr("credited_player");
        uint32 id = _giveWalletId(p);
        uint24 d = _today();
        vm.prank(GAME);
        coinflip.creditFlip(id, 5_000);
        assertEq(coinflip.coinflipAmount(p), 5_000, "view resolves the ID through the Game");

        _warpToDay(d + 1);
        _resolve(d + 1, true);
        (uint16 pct, bool win) = coinflip.getCoinflipDayResult(d + 1);
        assertTrue(win);
        uint256 payout = 5_000 + (5_000 * uint256(pct)) / 100;
        assertEq(coinflip.previewClaimCoinflips(p), payout);

        vm.expectCall(GAME, abi.encodeCall(DegenerusGame.walletIdOf, (p)), 2);
        vm.expectCall(GAME, abi.encodeCall(DegenerusGame.registerWallet, (p, true)), 0);
        vm.expectCall(address(jackpots), abi.encodeWithSelector(DegenerusJackpots.recordBafFlip.selector, id), 1);
        uint256 before = coin.balanceOf(p);
        vm.prank(p);
        uint256 got = coinflip.claimCoinflips(0, type(uint256).max);
        assertEq(got, payout);
        assertEq(coin.balanceOf(p) - before, payout, "minted to the claiming wallet");

        vm.prank(p);
        assertEq(coinflip.claimCoinflips(0, 1), 0, "nothing left to claim");
    }

    /// @notice An ID-less wallet: claims and every FLIP callback return 0 without reverting, the
    ///         views read 0, no account is allocated and no state is written under ID 0.
    function test_IdlessWallet_ClaimsAndCallbacksReturnZero_NeverRegisters() public {
        address q = makeAddr("idless_wallet");
        uint24 d = _today();
        for (uint24 i = 1; i <= 3; ++i) {
            _warpToDay(d + i);
            _resolve(d + i, true);
        }
        uint24 latest = d + 3;
        assertEq(_claimableDay(), latest);

        vm.recordLogs();
        vm.record();
        vm.prank(q);
        assertEq(coinflip.claimCoinflips(0, 100), 0);
        assertEq(_lastClaim(q), 0, "unregistered claims have no cursor");
        vm.startPrank(COIN);
        assertEq(coinflip.claimCoinflipsFromFlip(q, 100), 0);
        assertEq(coinflip.consumeCoinflipsForBurn(q, 100), 0);
        assertEq(coinflip.consumeFlipForSalvage(q, 100), 0);
        vm.stopPrank();
        (, bytes32[] memory writes) = vm.accesses(address(coinflip));
        assertEq(writes.length, 0, "unregistered claims write no account state");
        _assertNoKeyZeroWrite(writes, latest + 1);

        (bool enabled,,, uint24 startDay) = coinflip.coinflipAutoRebuyInfo(q);
        assertFalse(enabled);
        assertEq(startDay, 0);
        assertEq(coinflip.previewClaimCoinflips(q), 0);
        assertEq(coinflip.previewSalvageFlipBacking(q), 0);
        assertEq(coinflip.coinflipAmount(q), 0);
        (uint256 n,,) = _registrations(vm.getRecordedLogs());
        assertEq(n, 0, "no registration");
        assertEq(_gameId(q), 0);
        assertEq(_lane(latest + 1, 0), 0);
    }

    /// @notice Empty self deposits allocate and write nothing; rebuy configuration registers an
    ///         account, whose subsequent empty deposit advances its claim cursor normally.
    function test_ZeroDepositSkipsUnregisteredWallet_RebuyConfigurationRegisters() public {
        address q = makeAddr("idless_zero");
        address r = makeAddr("idless_rebuy");
        uint24 d = _today();
        _warpToDay(d + 1);
        _resolve(d + 1, false);
        _warpToDay(d + 2);
        _resolve(d + 2, true);

        vm.prank(q);
        coinflip.depositCoinflip(0, 0);
        assertEq(_lastClaim(q), 0);

        vm.prank(r);
        coinflip.setCoinflipAutoRebuy(0, true, 0);
        (,,, uint24 start) = coinflip.coinflipAutoRebuyInfo(r);
        assertEq(start, d + 2);
        _warpToDay(d + 3);
        _resolve(d + 3, true);
        _warpToDay(d + 4);
        _resolve(d + 4, false);
        vm.prank(r);
        coinflip.depositCoinflip(0, 0);
        assertEq(_lastClaim(r), d + 4, "registered rebuy cursor lands on the latest resolved day");

        assertEq(_gameId(q), 0);
        assertGt(_gameId(r), 0);
    }

    /// @notice A plain FLIP holder with no ID transfers as before: in-balance transfers succeed and
    ///         a shortfall (covered by an empty coinflip ledger) fails on the balance, not on identity.
    function test_IdlessHolder_FlipTransfersUnchanged() public {
        address q = makeAddr("idless_holder");
        address to = makeAddr("idless_holder_recipient");
        _fund(q, 500);
        vm.prank(q);
        coin.transfer(to, 300);
        assertEq(coin.balanceOf(to), 300);
        vm.expectRevert(stdError.arithmeticError);
        vm.prank(q);
        coin.transfer(to, 600);
        assertEq(_gameId(q), 0);
    }

    /// @notice creditFlip / creditFlipBatch / creditFlipPair skip ID 0 and amount 0 with no
    ///         storage write and no event; mixed batches credit only the valid legs.
    function test_CreditApis_SkipZeroIdAndZeroAmount() public {
        address a = makeAddr("credit_a");
        address b = makeAddr("credit_b");
        uint32 ida = _giveWalletId(a);
        uint32 idb = _giveWalletId(b);
        uint24 target = _today() + 1;

        vm.recordLogs();
        vm.record();
        vm.startPrank(GAME);
        coinflip.creditFlip(0, 1_000);
        coinflip.creditFlip(ida, 0);
        uint32[] memory ids = new uint32[](2);
        uint256[] memory amts = new uint256[](2);
        ids[0] = 0;
        amts[0] = 5;
        ids[1] = idb;
        amts[1] = 0;
        coinflip.creditFlipBatch(ids, amts);
        coinflip.creditFlipPair(0, 7, ida, 0);
        vm.stopPrank();
        (, bytes32[] memory writes) = vm.accesses(address(coinflip));
        assertEq(writes.length, 0, "zero legs write nothing");
        assertEq(_count(vm.getRecordedLogs(), address(coinflip), STAKE_UPDATED), 0, "zero legs emit nothing");

        ids = new uint32[](3);
        amts = new uint256[](3);
        ids[0] = ida;
        amts[0] = 100;
        ids[1] = 0;
        amts[1] = 100;
        ids[2] = idb;
        amts[2] = 0;
        vm.recordLogs();
        vm.prank(GAME);
        coinflip.creditFlipBatch(ids, amts);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_count(logs, address(coinflip), STAKE_UPDATED), 1);
        assertEq(_lane(target, ida), 100);
        assertEq(_lane(target, idb), 0);
        assertEq(_lane(target, 0), 0);

        vm.prank(GAME);
        coinflip.creditFlipPair(idb, 7, 0, 9);
        assertEq(_lane(target, idb), 7);
        assertEq(_lane(target, 0), 0);

        vm.expectRevert(Coinflip.OnlyFlipCreditors.selector);
        vm.prank(a);
        coinflip.creditFlip(ida, 1);
    }

    /// @notice Any mix of IDs (zero and repeats included) and amounts across the three credit
    ///         APIs: each nonzero ID's lane is the saturated sum of its nonzero legs and nothing is
    ///         ever written under key 0.
    /// forge-config: default.fuzz.runs = 256
    function testFuzz_Credits_NeverWriteUnderIdZero(uint32[4] memory rawIds, uint64[4] memory amounts) public {
        uint32[4] memory ids;
        for (uint256 i; i < 4; ++i) ids[i] = uint32(bound(rawIds[i], 0, 6));
        uint24 target = _today() + 1;

        uint32[] memory batchIds = new uint32[](4);
        uint256[] memory batchAmts = new uint256[](4);
        for (uint256 i; i < 4; ++i) {
            batchIds[i] = ids[i];
            batchAmts[i] = amounts[i];
        }
        vm.record();
        vm.startPrank(GAME);
        coinflip.creditFlipBatch(batchIds, batchAmts);
        coinflip.creditFlipPair(ids[0], amounts[1], ids[2], amounts[3]);
        coinflip.creditFlip(ids[3], amounts[0]);
        vm.stopPrank();
        (, bytes32[] memory writes) = vm.accesses(address(coinflip));
        _assertNoKeyZeroWrite(writes, target);
        assertEq(_lane(target, 0), 0);

        // Legs: batch (ids[i], amounts[i]); pair (ids[0], amounts[1]), (ids[2], amounts[3]);
        // single (ids[3], amounts[0]).
        uint32[7] memory legIds = [ids[0], ids[1], ids[2], ids[3], ids[0], ids[2], ids[3]];
        uint256[7] memory legAmts = [
            uint256(amounts[0]), amounts[1], amounts[2], amounts[3], amounts[1], amounts[3], amounts[0]
        ];
        for (uint32 who = 1; who <= 6; ++who) {
            uint256 sum;
            for (uint256 j; j < 7; ++j) {
                if (legIds[j] == who) sum += legAmts[j];
            }
            assertEq(_lane(target, who), sum > STAKE_LANE_MAX ? STAKE_LANE_MAX : sum, "lane = saturated sum");
        }
    }

    /// @notice A credit at the cap saturates (the event reports the accepted delta) and a manual
    ///         deposit past the cap reverts StakeAboveDailyCap.
    function test_Credit_SaturatesAtCap_ManualDepositRevertsPastCap() public {
        address p = makeAddr("cap_player");
        _fund(p, 10_000);
        vm.prank(p);
        coinflip.depositCoinflip(0, 100);
        uint32 id = _gameId(p);
        uint24 target = _today() + 1;

        vm.prank(GAME);
        coinflip.creditFlip(id, STAKE_LANE_MAX - 150);
        assertEq(_lane(target, id), STAKE_LANE_MAX - 50);

        vm.expectRevert(Coinflip.StakeAboveDailyCap.selector);
        vm.prank(p);
        coinflip.depositCoinflip(0, 100);

        vm.recordLogs();
        vm.prank(GAME);
        coinflip.creditFlip(id, 1_000);
        assertEq(_lane(target, id), STAKE_LANE_MAX, "credit saturates");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool seen;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(coinflip) || logs[i].topics[0] != STAKE_UPDATED) continue;
            (uint256 delta, uint256 total) = abi.decode(logs[i].data, (uint256, uint256));
            assertEq(delta, 50, "event reports the accepted delta");
            assertEq(total, STAKE_LANE_MAX);
            assertEq(uint32(uint256(logs[i].topics[1])), id);
            seen = true;
        }
        assertTrue(seen);
        vm.prank(GAME);
        coinflip.creditFlip(id, 1);
        assertEq(_lane(target, id), STAKE_LANE_MAX);
    }

    // =====================================================================
    //                           protocol paths
    // =====================================================================

    /// @notice `depositCoinflip(1, 0)` from GAME, the sDGNRS settlement walk and the sDGNRS
    ///         backing read make no Game identity call; the seed rides IDs 1 and 2 only.
    function test_ProtocolPaths_NoGameLookup_SeedKeyedOnProtocolIds() public {
        vm.expectCall(GAME, abi.encodeWithSelector(DegenerusGame.registerWallet.selector), 0);
        vm.expectCall(GAME, abi.encodeWithSelector(DegenerusGame.walletIdOf.selector), 0);
        vm.recordLogs();
        uint24 d = _today();
        _warpToDay(d + 1);
        _resolve(d + 1, true); // sDGNRS settles its seeded day through the walk
        vm.prank(GAME);
        coinflip.depositCoinflip(1, 0);
        vm.prank(SDGNRS);
        uint256 backing = coinflip.redeemableFlipBacking();

        assertGt(backing, 0, "sDGNRS settled its seed win under ID 2");
        assertGt(uint128(_slotA(VAULT)), 0, "the vault settled its seed win under ID 1");
        uint24 target = _today() + 1;
        assertEq(coinflip.coinflipAmountById(1), SEED + _lane(target, 1), "vault seed on its own ID");
        assertEq(coinflip.coinflipAmountById(2), SEED + _lane(target, 2), "sDGNRS seed on its own ID");
        vm.prank(GAME);
        coinflip.creditFlip(1, 3_000);
        assertEq(coinflip.coinflipAmountById(1), SEED + 3_000, "a credit to ID 1 is the vault's");
        (uint256 n,,) = _registrations(vm.getRecordedLogs());
        assertEq(n, 0);
    }

    // =====================================================================
    //                              BAF draw
    // =====================================================================

    /// @notice On the armed day a direct deposit appends `cum | id << 96`; the views and the
    ///         event return the ID; operator and gift deposits add no entry; the winner is an ID.
    function test_BafDraw_EntryStoresId_WinnerById() public {
        uint24 armed = _today() + 1;
        vm.prank(GAME);
        coinflip.armBafDraw(armed);
        address p1 = makeAddr("draw_1");
        address p2 = makeAddr("draw_2");
        _fund(p1, 10_000);
        _fund(p2, 10_000);

        vm.recordLogs();
        vm.prank(p1);
        coinflip.depositCoinflip(0, 1_000);
        vm.prank(p2);
        coinflip.depositCoinflip(0, 3_000);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint32 id1 = _gameId(p1);
        uint32 id2 = _gameId(p2);

        assertEq(_drawEntryRaw(armed, 0), 1_000 | (uint256(id1) << 96));
        assertEq(_drawEntryRaw(armed, 1), 4_000 | (uint256(id2) << 96));
        (uint32 e0, uint96 c0) = coinflip.bafDrawEntryAt(armed, 0);
        (uint32 e1, uint96 c1) = coinflip.bafDrawEntryAt(armed, 1);
        assertEq(e0, id1);
        assertEq(c0, 1_000);
        assertEq(e1, id2);
        assertEq(c1, 4_000);
        uint256 seen;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(coinflip) || logs[i].topics[0] != BAF_DRAW_ENTERED) continue;
            assertEq(uint24(uint256(logs[i].topics[1])), armed);
            assertEq(uint32(uint256(logs[i].topics[2])), seen == 0 ? id1 : id2, "event carries the ID");
            ++seen;
        }
        assertEq(seen, 2);

        address o = makeAddr("draw_operator");
        vm.prank(p1);
        game.setOperatorApproval(0, o, true);
        vm.prank(o);
        coinflip.depositCoinflip(id1, 500);
        vm.prank(p2);
        coinflip.depositCoinflip(id1, 500);
        (uint24 day, uint96 total, uint32 count) = coinflip.bafDrawInfo();
        assertEq(day, armed);
        assertEq(total, 4_000);
        assertEq(count, 2, "operator and gift deposits carry no draw weight");

        for (uint256 i; i < 16; ++i) {
            uint256 w = uint256(keccak256(abi.encode("baf_draw_word", i)));
            uint32 winner = coinflip.bafDrawWinner(w);
            assertEq(winner, _refDrawWinner(armed, w));
            assertTrue(winner == id1 || winner == id2);
        }
    }

    /// @notice The draw over any set of depositors returns the reference winner's ID.
    /// forge-config: default.fuzz.runs = 64
    function testFuzz_BafDrawWinner_MatchesReference(uint256 seed, uint256 rngWord) public {
        uint24 armed = _today() + 1;
        vm.prank(GAME);
        coinflip.armBafDraw(armed);
        uint256 n = bound(seed, 1, 6);
        for (uint256 i; i < n; ++i) {
            address p = address(uint160(uint256(keccak256(abi.encode("baf_draw_fuzz", i)))));
            uint256 amount = 100 + uint256(keccak256(abi.encode(seed, i))) % 150_000;
            _fund(p, amount);
            vm.prank(p);
            coinflip.depositCoinflip(0, amount);
            (uint32 eid,) = coinflip.bafDrawEntryAt(armed, uint32(i));
            assertEq(eid, _gameId(p));
        }
        assertEq(coinflip.bafDrawWinner(rngWord), _refDrawWinner(armed, rngWord));
    }

    // =====================================================================
    //                               records
    // =====================================================================

    /// @notice Every ratchet asks the Game for the payee: a bare ratchet (above the mark, under
    ///         the fifth bar) passes share 0 and still moves the trophy to the returned payee; a
    ///         claim passes the accrued share; a non-improving candidate asks nothing.
    function test_BareRatchet_PaysShareZero_TrophyToPayee() public {
        address a = makeAddr("record_a");
        address b = makeAddr("record_b");
        uint32 ida = _giveWalletId(a);
        uint32 idb = _giveWalletId(b);

        vm.expectCall(GAME, abi.encodeWithSelector(DegenerusGame.payRecordSdgnrs.selector), 3);
        vm.expectCall(GAME, abi.encodeCall(DegenerusGame.payRecordSdgnrs, (idb, 0)), 1);

        // First mark: no bar to clear, claims the floor share.
        vm.prank(GAME);
        uint256 paidA = coinflip.armRecord(KIND_SPIN, ida, 1 ether);
        assertGt(paidA, 0);
        assertEq(recordBounty.ownerOf(KIND_SPIN), a);

        // Bare ratchet: +10%, under the fifth bar.
        vm.recordLogs();
        vm.prank(GAME);
        uint256 paidB = coinflip.armRecord(KIND_SPIN, idb, 1.1 ether);
        assertEq(paidB, 0, "a bare ratchet claims nothing");
        assertEq(recordBounty.ownerOf(KIND_SPIN), b, "trophy to the payee of the ratcheting ID");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool seen;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(coinflip) || logs[i].topics[0] != BIG_RECORD) continue;
            assertEq(uint8(uint256(logs[i].topics[1])), KIND_SPIN);
            assertEq(uint32(uint256(logs[i].topics[2])), idb, "record event carries the ID");
            (uint256 value, uint128 paid, uint256 sdgnrsPaid) = abi.decode(logs[i].data, (uint256, uint128, uint256));
            assertEq(value, 1.1 ether);
            assertEq(paid, 0);
            assertEq(sdgnrsPaid, 0);
            seen = true;
        }
        assertTrue(seen);

        // A claim on the same day draws the 5% floor of the reduced pool.
        uint256 pool = coinflip.recordPool();
        vm.expectCall(GAME, abi.encodeCall(DegenerusGame.payRecordSdgnrs, (ida, 500)), 1);
        vm.prank(GAME);
        uint256 paidC = coinflip.armRecord(KIND_SPIN, ida, 2 ether);
        assertEq(paidC, (pool * 500) / 10_000);
        assertEq(recordBounty.ownerOf(KIND_SPIN), a);

        // At or below the mark: no ratchet, no Game call (the selector count above stays 3).
        vm.prank(GAME);
        assertEq(coinflip.armRecord(KIND_SPIN, idb, 2 ether), 0);
        assertEq(recordBounty.ownerOf(KIND_SPIN), a);
    }

    /// @notice The trophy goes to whatever payee the Game returns for the ID (Coinflip holds no
    ///         address for it), for the four Game-armed kinds and the dice run alike.
    function test_RecordTrophy_GoesToGameReturnedPayee() public {
        address a = makeAddr("payee_owner");
        address payee = makeAddr("payee_returned");
        uint32 id = _giveWalletId(a);
        vm.mockCall(
            GAME, abi.encodeWithSelector(DegenerusGame.payRecordSdgnrs.selector, id), abi.encode(uint256(0), payee)
        );
        vm.prank(GAME);
        coinflip.armRecord(KIND_SPIN, id, 1 ether);
        assertEq(recordBounty.ownerOf(KIND_SPIN), payee);
        vm.prank(CRAPS);
        coinflip.armDiceRunRecord(id, 1_500_000);
        assertEq(recordBounty.ownerOf(KIND_DICE_RUN), payee);
        assertEq(recordBounty.balanceOf(a), 0);
    }

    /// @notice The dice-run record credits its claim by ID, then the trophy goes to the payee.
    function test_DiceRun_CreditsById_TrophyToPayee() public {
        address a = makeAddr("dice_runner");
        uint32 id = _giveWalletId(a);
        uint256 pool = coinflip.recordPool();
        uint256 expectedPaid = (pool * 500) / 10_000;

        vm.expectCall(GAME, abi.encodeCall(DegenerusGame.payRecordSdgnrs, (id, 500)), 1);
        vm.recordLogs();
        vm.prank(CRAPS);
        uint256 paid = coinflip.armDiceRunRecord(id, 1_500_000);
        assertEq(paid, expectedPaid);
        assertEq(_lane(_today() + 1, id), expectedPaid, "claim credited to the ID's stake lane");
        assertEq(recordBounty.ownerOf(KIND_DICE_RUN), a);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool stake;
        bool rec;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(coinflip)) continue;
            if (logs[i].topics[0] == STAKE_UPDATED) {
                assertEq(uint32(uint256(logs[i].topics[1])), id);
                stake = true;
            }
            if (logs[i].topics[0] == BIG_RECORD) {
                assertEq(uint8(uint256(logs[i].topics[1])), KIND_DICE_RUN);
                assertEq(uint32(uint256(logs[i].topics[2])), id);
                rec = true;
            }
        }
        assertTrue(stake && rec);

        vm.prank(CRAPS);
        assertEq(coinflip.armDiceRunRecord(id, 1_500_000), 0, "no strict improvement");
        vm.expectRevert(Coinflip.OnlyCraps.selector);
        coinflip.armDiceRunRecord(id, 2_000_000);
    }

    // =====================================================================
    //                             claim walk BAF
    // =====================================================================

    /// @notice The claim walk scores BAF by ID for a player, never for sDGNRS (ID 2), and VAULT
    ///         (ID 1) scores but stays off the board.
    function test_ClaimWalk_BafById_SkipsSdgnrs_VaultOffBoard() public {
        address p = makeAddr("baf_walker");
        _fund(p, 10_000);
        uint24 d = _today();
        vm.prank(p);
        coinflip.depositCoinflip(0, 1_000);
        uint32 id = _gameId(p);

        vm.expectCall(address(jackpots), abi.encodeWithSelector(DegenerusJackpots.recordBafFlip.selector, uint32(2)), 0);
        vm.expectCall(address(jackpots), abi.encodeWithSelector(DegenerusJackpots.recordBafFlip.selector, id), 1);
        vm.expectCall(address(jackpots), abi.encodeWithSelector(DegenerusJackpots.recordBafFlip.selector, uint32(1)), 1);

        _warpToDay(d + 1);
        _resolve(d + 1, true); // the sDGNRS walk wins its seed day: no BAF call for ID 2
        vm.prank(p);
        coinflip.claimCoinflips(0, type(uint256).max);
        vm.prank(GAME);
        coinflip.depositCoinflip(1, 0);

        uint24 bracket = 10;
        assertGt(_bafTotal(bracket, id), 0, "player scores by ID");
        assertGt(_bafTotal(bracket, 1), 0, "vault scores under ID 1");
        assertEq(_bafTotal(bracket, 2), 0, "sDGNRS never scores");
        assertEq(jackpots.bafHeadWinner(bracket, 0, 0), id);
        bytes32 base = keccak256(abi.encode(uint256(bracket), BAF_TOP_ROOT));
        uint256 w0 = uint256(vm.load(address(jackpots), base));
        uint256 w1 = uint256(vm.load(address(jackpots), bytes32(uint256(base) + 1)));
        uint256 lv = uint256(vm.load(address(jackpots), keccak256(abi.encode(uint256(bracket), BAF_LEVEL_ROOT))));
        assertEq(uint8(lv >> 64), 1, "board holds the player only");
        assertEq(uint32(uint128(w0) >> 96), id);
        assertEq(w0 >> 128, 0, "vault never takes a board lane");
        assertEq(w1, 0);
    }
}
