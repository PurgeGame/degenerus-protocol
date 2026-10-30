// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
/// @dev ERC-7201 pins verified by scripts/layout/check_recursive_layout.py and XaInitializationAndRollback.
library QaSlots {
    uint256 internal constant QUESTS = 0x04343aaa474371a66bb47cad27e6432f6ed56b02c7b23c6e11e4d1818f7af200;
    uint256 internal constant ACTIVE = QUESTS;
    uint256 internal constant STATE = QUESTS + 1;
    uint256 internal constant LEVEL = QUESTS + 2;
    uint256 internal constant AFFILIATE = 0x93b2738aa52d403a1d6cd7cad14e72a7cda308b6a92d312ff0746cbfb7eec800;
    uint256 internal constant CODE = AFFILIATE;
    uint256 internal constant EARNED = AFFILIATE + 1;
    uint256 internal constant REFERRAL = AFFILIATE + 2;
    uint256 internal constant SCORE = AFFILIATE + 3;
}
