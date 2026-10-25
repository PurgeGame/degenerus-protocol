// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {NativeGasExport} from "../helpers/NativeGasExport.sol";
import {CoinflipStorage} from "../helpers/CoinflipStorage.sol";
import {AffiliateStorage} from "../helpers/AffiliateStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {VaultBackstopHost} from "../fuzz/VaultFlipBackstop.t.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";

/// @dev Full production calls with complete prestate for current90/R90 native comparison.
///      Day 21000 permits a post-Glamsterdam timestamp override without changing compiled pins.
contract StorageReuseNativeTest is DeployProtocol, NativeGasExport {
    uint24 private constant DAY = 21_000; // divisible by 105: all 15 ring homes aligned
    address private constant PLAYER = address(0x8888);
    uint32 private id;

    function _nativeExtraStorage(string memory key, address account) internal override {
        if (account != address(coinflip)) return;
        // Include unvisited siblings so clearing an old eight-lane page has the correct
        // original word and refund; these are explicit fixture IDs, not a general decoder.
        for (uint32 i = 1; i <= id + 32; ++i) {
            uint32 who = i <= id ? i : 1000 + i - id - 1;
            uint256 base = uint256(keccak256(abi.encode(who, uint256(0))));
            for (uint256 j; j < 15; ++j) {
                bytes32 slot = bytes32(base + j);
                bytes32 value = vm.load(account, slot);
                if (value != 0) vm.serializeBytes32(key, vm.toString(slot), value);
            }
            bytes32 overflow = keccak256(abi.encode(uint256(DAY / 7), keccak256(abi.encode(who, uint256(9)))));
            bytes32 extra = vm.load(account, overflow);
            if (extra != 0) vm.serializeBytes32(key, vm.toString(overflow), extra);
        }
    }

    function setUp() public {
        _deployProtocol();
        id = _giveWalletId(PLAYER);
        _clock(DAY, DAY);
    }

    function _clock(uint24 today, uint24 resolved) private {
        vm.warp((uint256(today - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621);
        _seedLogicalFixtureDay(today);
        uint256 word = uint256(vm.load(address(coinflip), bytes32(uint256(4))));
        vm.store(address(coinflip), bytes32(uint256(4)), bytes32((word & ~uint256(type(uint24).max)) | resolved));
    }

    function _cursor(uint32 who, uint24 day, bool rebuy) private {
        bytes32 slot = keccak256(abi.encode(who, uint256(2)));
        vm.store(address(coinflip), slot, bytes32((uint256(day) << 128) | (uint256(day) << 152)
            | (rebuy ? uint256(1) << 176 : 0)));
        vm.store(address(coinflip), bytes32(uint256(slot) + 1), bytes32(rebuy ? uint256(1) : 0));
    }

    function _credit(string memory label, uint256 amount) private {
        _nativeFixture(label, address(game), address(coinflip), abi.encodeCall(coinflip.creditFlip_g317, (id, amount)));
    }

    function test_nativeCreditBranches() public {
        _credit("credit_fresh", 1000);
        _credit("credit_zero", 0);
        CoinflipStorage.set(address(coinflip), id, DAY, 1000);
        _credit("credit_same_page", 1000);
        CoinflipStorage.set(address(coinflip), id, DAY + 1, type(uint32).max);
        _credit("credit_capped", 1000);
    }

    function test_nativeReuseAndOverflow() public {
        CoinflipStorage.set(address(coinflip), id, DAY - 99, 1000);
        _credit("credit_expired_reuse", 1000);
        _clock(DAY, DAY - 15);
        _credit("credit_new_overflow", 1000);
        _cursor(id, DAY - 99, false);
        _credit("credit_consumed_reuse", 1000);
        _cursor(id, 0, false);
        CoinflipStorage.set(address(coinflip), id, DAY, 1000);
        _cursor(id, DAY - 15, false);
        _credit("credit_existing_overflow", 1000);
    }

    function test_nativeDistinctAndRepeatedBatches() public {
        uint32[] memory ids = new uint32[](32);
        uint256[] memory amounts = new uint256[](32);
        for (uint256 i; i < 32; ++i) { ids[i] = uint32(1000 + i); amounts[i] = 1000; }
        _nativeFixture("batch_fresh_32", address(game), address(coinflip), abi.encodeCall(coinflip.creditFlipBatch, (ids, amounts)));
        for (uint256 i; i < 32; ++i) CoinflipStorage.set(address(coinflip), ids[i], DAY - 99, 1000);
        _clock(DAY, DAY - 15);
        _nativeFixture("batch_overflow_32", address(game), address(coinflip), abi.encodeCall(coinflip.creditFlipBatch, (ids, amounts)));
        for (uint256 i; i < 32; ++i) ids[i] = id;
        _nativeFixture("batch_repeated_32", address(game), address(coinflip), abi.encodeCall(coinflip.creditFlipBatch, (ids, amounts)));
    }

    function _history(uint32 who, uint24 count, bool rebuy) private {
        _cursor(who, DAY - count, rebuy);
        for (uint256 d = DAY - count + 1; d <= DAY; ++d) {
            CoinflipStorage.set(address(coinflip), who, uint24(d), 1000);
            bytes32 slot = keccak256(abi.encode(d >> 5, uint256(1)));
            uint256 word = uint256(vm.load(address(coinflip), slot));
            uint256 shift = (d & 31) * 8;
            uint256 result = d == DAY ? 1 : 156;
            vm.store(address(coinflip), slot, bytes32((word & ~(uint256(255) << shift)) | (result << shift)));
        }
    }

    function test_nativeClaimsAndVault() public {
        _history(id, 90, false);
        _nativeFixture("claim_90", PLAYER, address(coinflip), abi.encodeCall(coinflip.claimCoinflips, (0, type(uint256).max)));
        _cursor(id, DAY - 14, false);
        _nativeFixture("claim_14", PLAYER, address(coinflip), abi.encodeCall(coinflip.claimCoinflips, (0, type(uint256).max)));
        _cursor(id, DAY - 1, false);
        CoinflipStorage.set(address(coinflip), id, DAY - 96, 1000); // initialize the fifteenth home
        _nativeFixture("claim_1_full_ring", PLAYER, address(coinflip), abi.encodeCall(coinflip.claimCoinflips, (0, type(uint256).max)));
        _cursor(id, DAY - 90, true);
        _nativeFixture("exit_90_rebuy", PLAYER, address(coinflip), abi.encodeCall(coinflip.setCoinflipAutoRebuy, (0, false, 0)));
        _history(1, 90, false);
        _nativeFixture("vault_90", address(game), address(coinflip), abi.encodeCall(coinflip.playCoinflip, (1, 0)));
    }

    function test_nativeVaultCheckpoint() public {
        vm.etch(address(game), type(VaultBackstopHost).runtimeCode);
        VaultBackstopHost(payable(address(game))).seedPhase(DAY, DAY - 76, 0);
        _history(1, 76, false);
        _nativeFixture("vault_checkpoint_76", PLAYER, address(game), abi.encodeCall(VaultBackstopHost.phase, (9_000_000)));
    }

    function test_nativeVaultFullMinerCheckpoint() public {
        bytes memory original = address(game).code;
        vm.etch(address(game), type(VaultBackstopHost).runtimeCode);
        VaultBackstopHost(payable(address(game))).seedPhase(DAY, DAY - 76, 0);
        vm.etch(address(game), original);
        _history(1, 76, false);
        vm.fee(1 gwei);
        _nativeFixture("vault_miner_checkpoint_76", PLAYER, address(game), abi.encodeCall(game.mineRun, (0)));
    }

    function test_nativeClaimAndDeposit() public {
        _history(id, 14, false);
        vm.prank(address(game)); coin.mintForGame_g152734(PLAYER, 10_000);
        _nativeFixture("claim_and_deposit_14", PLAYER, address(coinflip), abi.encodeCall(coinflip.playCoinflip, (0, 1000)));
    }

    function test_nativeBafFreshExistingAndReuse() public {
        bytes memory data = abi.encodeCall(jackpots.recordBafFlip, (id, 10, 1000));
        _nativeFixture("baf_fresh", address(coinflip), address(jackpots), data);
        vm.prank(address(coinflip)); jackpots.recordBafFlip(id, 10, 1000);
        _nativeFixture("baf_existing", address(coinflip), address(jackpots), data);
        vm.prank(address(game)); jackpots.finalizeBaf(10);
        _nativeFixture("baf_reuse", address(coinflip), address(jackpots), abi.encodeCall(jackpots.recordBafFlip, (id, 30, 1000)));
    }

    function test_nativeAffiliateHistory() public {
        bytes32 code = bytes32("native-reuse");
        vm.prank(PLAYER); affiliate.createAffiliateCode(code, 0);
        uint32 buyer = 100_000;
        while (uint256(keccak256(abi.encodePacked(keccak256("affiliate-payout-roll-v1"),
            GameTimeLib.currentDayIndex(), buyer, code))) % 20 >= 15) ++buyer;
        bytes memory input = abi.encodeCall(affiliate.payAffiliateCombined_g3742656, (code, buyer, (uint256(_fixtureGameDay()) << 24) | 8, 10000, 0, 0, 0, 0));
        _nativeFixture("affiliate_fresh", address(game), address(affiliate), input);
        vm.prank(address(game)); affiliate.payAffiliateCombined_g3742656(code, buyer, (uint256(_fixtureGameDay()) << 24) | 8, 10000, 0, 0, 0, 0);
        _nativeFixture("affiliate_same_level", address(game), address(affiliate), input);
        _nativeFixture("affiliate_next_level", address(game), address(affiliate),
            abi.encodeCall(affiliate.payAffiliateCombined_g3742656, (code, buyer, (uint256(_fixtureGameDay()) << 24) | 9, 10000, 0, 0, 0, 0)));
        _nativeFixture("affiliate_gap_7", address(game), address(affiliate),
            abi.encodeCall(affiliate.payAffiliateCombined_g3742656, (code, buyer, (uint256(_fixtureGameDay()) << 24) | 15, 10000, 0, 0, 0, 0)));
        AffiliateStorage.set(address(affiliate), id, 8, (uint256(1) << 35) - 1);
        _nativeFixture("affiliate_capped", address(game), address(affiliate), input);
    }
}
