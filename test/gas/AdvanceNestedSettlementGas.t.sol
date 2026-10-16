// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

// The stage-by-stage composed-transaction checks that lived here (word apply / daily stage /
// ticket stage each held to a whole-transaction limit) were retired with the advanceGame stage
// table: one admitted chunk between checkpoints is what is bounded now (MineFlipGasBounds), and
// those chunks are measured by DirectJackpotAdvanceGas, JackpotTicketAwardChunks and the
// *Checkpoints repro suites. The storage seeders stay: AdvanceCenturyConsolidationGas reuses
// VaultHistorySeeder.

import {Coinflip} from "../../contracts/Coinflip.sol";
import {CoinflipStakeSetter} from "../helpers/CoinflipStakeSetter.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

contract DailyGasExtrasSeeder is DegenerusGame {
    function armGolden(uint256 word) external {
        uint8[4] memory traits = JackpotBucketLib.getRandomTraits(word);
        goldenTicket = uint256(uint160(address(0xA57A))) | (uint256(traits[0] & 7) << 162)
            | (uint256(dailyIdx - 1) << 165) | (uint256(1) << 189);
    }
}

/// @dev The vault's auto-rebuy claim backlog: `span` staked, resolved days ending at `latest`,
///      one loss among them.
contract VaultHistorySeeder is CoinflipStakeSetter {
    function seedVaultHistory(bool sufficient, uint24 latest, uint24 span) external {
        address player = ContractAddresses.VAULT;
        PlayerCoinflipState storage s = playerState[degenerusGame.walletIdOf(player)];
        uint24 last = latest - span;
        s.claimableStored = 0;
        s.lastClaim = last;
        s.autoRebuyStartDay = last;
        s.autoRebuyEnabled = true;
        s.autoRebuyStop = 1;
        s.autoRebuyCarry = 0;
        uint24 lossDay = last + span / 2;
        for (uint24 day = last + 1; day <= latest; ++day) {
            // Stake lanes hold whole FLIP: the insufficient history stakes 1 FLIP a day.
            _setFlipStake(day, 1, sufficient ? 1000 : 1);
            _storeDayResult(day, 150, day != lossDay);
        }
    }
}
