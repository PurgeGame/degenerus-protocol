// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {MockVRFCoordinator} from "../../contracts/mocks/MockVRFCoordinator.sol";

/// @dev The engine can leave a mid-day request outstanding after a daily completes (a scheduled
///      Craps window arms one at once), and no further mining happens until its word lands.
///      Fixtures that crank toward the next daily request answer such a request first.
library OpenVrfRequest {
    /// @return answered True when a still-open request was fulfilled with `word`.
    function answer(MockVRFCoordinator vrf, uint256 word) internal returns (bool answered) {
        uint256 id = vrf.lastRequestId();
        if (id == 0) return false;
        (,, bool fulfilled) = vrf.pendingRequests(id);
        if (fulfilled) return false;
        vrf.fulfillRandomWords(id, word);
        return true;
    }
}
