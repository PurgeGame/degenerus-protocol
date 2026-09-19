// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DegenerusGameStorage} from "../../../contracts/storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";

/// @dev Sparse but exact reference state for six maximum-depth cumulative-weight searches.
contract ProtocolBoonDrawSeeder is DegenerusGameStorage {
    function seedPools(uint24 day, uint256 winnerWord) external {
        rngWordByDay[day - 1] = 12345;
        for (uint256 i; i < 2; ++i) {
            address issuer = i == 0 ? ContractAddresses.VAULT : ContractAddresses.SDGNRS;
            uint32 count = type(uint32).max;
            uint64 total = uint64(count) * 800;
            protocolBoonPools[issuer][day - 1] = ProtocolBoonPool(uint112(uint256(count) * 100 ether), total, count, 0);
            // Sparse materialization of the exact nodes a uniform 2^32-1-entry
            // pool searches. All three walks have 32 nodes and genuine distinct
            // final donors; no shortcut or warm setup reads in the measured tx.
            for (uint8 slot; slot < 3; ++slot) {
                uint256 roll = uint256(keccak256(abi.encode(PROTOCOL_BOON_WINNER_TAG, issuer, day - 1, slot, winnerWord))) % total;
                uint32 lo;
                uint32 hi = count;
                while (lo < hi) {
                    uint32 mid = lo + (hi - lo) / 2;
                    uint64 cumulative = (uint64(mid) + 1) * 800;
                    protocolBoonEntries[issuer][day - 1][mid] = ProtocolBoonEntry(
                        address(uint160(0xB000000000 + i * 0x100000000 + mid)), cumulative, 1, 0
                    );
                    if (cumulative <= roll) lo = mid + 1;
                    else hi = mid;
                }
            }
        }
    }
}
