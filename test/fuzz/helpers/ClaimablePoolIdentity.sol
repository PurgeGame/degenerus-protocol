// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm} from "forge-std/Vm.sol";
import {GameSlots, GameSlotKeys} from "../../helpers/GameSlots.sol";

/// @title ClaimablePoolIdentity -- every term docs/ACCOUNTING.md lists inside `claimablePool`
/// @notice The documented identity, read from Game storage:
///
///         claimablePool = Σ_id (claimable_id − 1 + afking_id)   balance words, 1-wei sentinel excluded
///                       + unsplit Degenesis volume              cohort headers without GD_SPLIT
///                       + degenesisVaultBudget
///                       + redemption reserve                    _redemptionReserveStored − 1
///                       + staged BAF reservation                jackpotWork.paid while kind == 7
///                       + sealed Decimator round pools          see `decimatorReserved`
///
///         Until the final sweep. The sweep sets claimablePool to zero and forfeits the remaining
///         balance words, so afterwards only `claimablePool == 0` is asserted.
///
///         A sealed Decimator round reserves `poolWei` at phase 1 (sealed, being simulated).
///         Ranking (phase 1 → 2) releases the pass-converted part `recycled` to the future pool;
///         each paid place then credits its ETH to a balance word. At phase 2 the remaining
///         reservation is `poolWei − recycled − ETH credited to places [0, paid)`, with the place
///         amounts from DegenerusGameDecimatorModule._payTerms. Phase 3 reserves nothing.
library ClaimablePoolIdentity {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 internal constant DEGENESIS_UNIT = 0.0001 ether;
    uint256 internal constant GD_SPLIT = uint256(1) << 80;
    uint256 internal constant HALF_WHALE_PASS_PRICE = 2.25 ether;
    uint8 internal constant BAF_KIND = 7;

    struct Terms {
        uint256 claimablePool;
        uint256 balanceWords;
        uint256 missingSentinels;
        uint256 unsplitDegenesis;
        uint256 vaultBudget;
        uint256 redemptionReserve;
        uint256 bafReserved;
        uint256 decimatorReserved;
        uint256 liveDecimatorRounds;
        bool swept;
    }

    function swept(address game) internal view returns (bool) {
        return (uint256(vm.load(game, bytes32(GameSlots.GAME_OVER_STATE_PACKED))) >> 56) & 0xff != 0;
    }

    function claimablePool(address game) internal view returns (uint256) {
        return uint128(uint256(vm.load(game, bytes32(GameSlots.CLAIMABLE_POOL))) >> (GameSlots.CLAIMABLE_POOL_OFFSET * 8));
    }

    /// @dev Σ over every allocated wallet ID (1 .. wallets.length − 1) of claimable above the
    ///      1-wei registration sentinel plus prepaid AFKing. `missing` counts IDs whose claimable
    ///      half is zero, i.e. whose sentinel is gone.
    function balanceWords(address game) internal view returns (uint256 sum, uint256 missing) {
        uint256 n = uint256(vm.load(game, bytes32(GameSlots.WALLETS)));
        for (uint256 id = 1; id < n; ++id) {
            uint256 packed = uint256(vm.load(game, GameSlotKeys.balances(uint32(id))));
            uint256 claimable = uint128(packed);
            if (claimable == 0) ++missing;
            sum += (claimable > 1 ? claimable - 1 : 0) + (packed >> 128);
        }
    }

    function unsplitDegenesis(address game) internal view returns (uint256 sum) {
        for (uint256 c = 1; c <= 7; ++c) {
            uint256 h = uint256(vm.load(game, keccak256(abi.encode(c, GameSlots.DEGENESIS_DAYS))));
            if (h & GD_SPLIT == 0) sum += uint256(uint48(h)) * DEGENESIS_UNIT;
        }
    }

    function vaultBudget(address game) internal view returns (uint256) {
        return uint128(uint256(vm.load(game, bytes32(GameSlots.DEGENESIS_VAULT_BUDGET))));
    }

    function redemptionReserve(address game) internal view returns (uint256) {
        uint256 stored = uint128(uint256(vm.load(game, bytes32(GameSlots.REDEMPTION_RESERVE_STORED))));
        return stored == 0 ? 0 : stored - 1;
    }

    /// @dev jackpotWork: slot 0 = budget(128) | paid(128); slot 1 byte 9 = kind.
    function bafReserved(address game) internal view returns (uint256) {
        uint256 head = uint256(vm.load(game, bytes32(GameSlots.JACKPOT_WORK)));
        uint256 tail = uint256(vm.load(game, bytes32(GameSlots.JACKPOT_WORK + 1)));
        return uint8(tail >> 72) == BAF_KIND ? head >> 128 : 0;
    }

    /// @dev decBattleRounds[lvl] slot 0: poolWei(96) | count(40) | totalCreditedStack(64) |
    ///      openedDay(24) | phase(8) | capacity(8) | winners(8) | paid(8).
    function decimatorReserved(address game, uint256 maxLevel) internal view returns (uint256 sum, uint256 live) {
        for (uint256 lvl = 1; lvl <= maxLevel; ++lvl) {
            uint256 w = uint256(vm.load(game, keccak256(abi.encode(lvl, GameSlots.DEC_BATTLE_ROUNDS))));
            uint256 phase = uint8(w >> 224);
            if (phase != 1 && phase != 2) continue;
            ++live;
            uint256 pool = uint96(w);
            if (phase == 1) {
                sum += pool;
                continue;
            }
            uint256 winners = uint8(w >> 240);
            uint256 paid = uint8(w >> 248);
            (uint256 base, uint256 champ, uint256 champPasses, uint256 perEth, uint256 recycled, bool passMode) =
                _payTerms(pool, winners);
            uint256 credited;
            for (uint256 place; place < paid; ++place) {
                if (place == 0) credited += champ - champPasses * HALF_WHALE_PASS_PRICE;
                else if (!(passMode && place & 1 == 0)) credited += base + perEth;
            }
            sum += pool - recycled - credited;
        }
    }

    /// @dev Mirror of DegenerusGameDecimatorModule._payTerms.
    function _payTerms(uint256 pool, uint256 winners)
        private
        pure
        returns (uint256 base, uint256 champ, uint256 champPasses, uint256 perEth, uint256 recycled, bool passMode)
    {
        if (winners == 0) return (0, 0, 0, 0, 0, false);
        base = (pool - pool / 20) / winners;
        champ = pool - base * (winners - 1);
        champPasses = champ / 2 / HALF_WHALE_PASS_PRICE;
        recycled = champPasses * HALF_WHALE_PASS_PRICE;
        passMode = winners > 1 && base >= HALF_WHALE_PASS_PRICE;
        if (!passMode) return (base, champ, champPasses, 0, recycled, false);
        uint256 passWinners = (winners - 1) / 2;
        uint256 ethWinners = winners - 1 - passWinners;
        uint256 leftover = passWinners * (base % HALF_WHALE_PASS_PRICE);
        perEth = leftover / ethWinners;
        recycled += passWinners * (base - base % HALF_WHALE_PASS_PRICE) + leftover - perEth * ethWinners;
    }

    function terms(address game, uint256 maxLevel) internal view returns (Terms memory t) {
        t.swept = swept(game);
        t.claimablePool = claimablePool(game);
        (t.balanceWords, t.missingSentinels) = balanceWords(game);
        t.unsplitDegenesis = unsplitDegenesis(game);
        t.vaultBudget = vaultBudget(game);
        t.redemptionReserve = redemptionReserve(game);
        t.bafReserved = bafReserved(game);
        (t.decimatorReserved, t.liveDecimatorRounds) = decimatorReserved(game, maxLevel);
    }

    function sum(Terms memory t) internal pure returns (uint256) {
        return t.balanceWords + t.unsplitDegenesis + t.vaultBudget + t.redemptionReserve + t.bafReserved
            + t.decimatorReserved;
    }
}
