// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {CrapsBattleStorage} from "../storage/CrapsBattleStorage.sol";
import {ICoinflipStake} from "../CrapsInterfaces.sol";
import {ContractAddresses} from "../ContractAddresses.sol";

abstract contract CrapsProgressiveActions is CrapsBattleStorage {
    function _jackpotPayProgressive(
        Window memory w,
        uint256 peakFlip,
        uint256 score,
        uint256 winnerId,
        uint256 winnerWord
    ) internal {
        unchecked {
            // RARE FIRST, and it OVERRIDES. The rare cutoff is above the common cutoff, so a run
            // that clears it has cleared both — and takes the rare rung alone,
            // never both. Both cutoffs are INCLUSIVE.
            bool rare = score >= _PROG_RARE;
            // THE RUNG, COUNTED IN DOUBLINGS of the common share: RARE is one doubling, so
            // `500 << shift` is the whole table, 500 common and 1,000 rare.
            uint256 shift;
            if (rare) shift = _PROG_RARE_DOUBLINGS;
            else if (score < _PROG_COMMON) return;

            uint256 bps = _PROG_ROUTINE_COMMON_BPS << shift;
            _payProgressiveShare(w.key, winnerId, winnerWord, peakFlip, score, bps);
        }
    }

    function _payProgressiveShare(bytes32 key, uint256 winnerId, uint256 winnerWord, uint256 peakFlip, uint256 score, uint256 bps) private {
        unchecked {
            uint32 winner = uint32(winnerWord);
            uint256 pool = _progressive;
            uint256 candidate = _jackpotPoolShare(pool, bps);
            if (candidate == 0) return;
            uint256 paid = candidate;
            // The WHOLE gross award leaves the pool, pass slice included — a pass is this award
            // paying in a different shape, and leaving its value behind would count it twice.
            pool -= paid;
            _progressive = pool;
            emit CrapsProgressivePaid(
                winnerId, key, winner, score >= _PROG_RARE, uint16(bps), peakFlip, score, candidate, paid, pool
            );
            // State first, credit second; every qualifying dice result receives the full award.
            paid -= _splitAward(key, winner, _SPLIT_SRC_PROGRESSIVE | paid);
            if (paid != 0) ICoinflipStake(ContractAddresses.COINFLIP).creditFlip_g317(winner, paid);
        }
    }

    function _jackpotPoolShare(uint256 pool, uint256 bps) internal pure returns (uint256) {
        unchecked {
            return (pool / _BPS_DENOMINATOR) * bps + ((pool % _BPS_DENOMINATOR) * bps) / _BPS_DENOMINATOR;
        }
    }
}
