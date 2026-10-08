// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";

/// @dev Etched over the game: writes the read-cohort flags directly (StallCreditSeeder pattern).
contract CertifyReadSeeder is DegenerusGame {
    /// @notice Published, delivered, unlocked, request inactive, every consumer clear, no
    ///         certificate: the selector reads stage 7 and selects CertifyRead.
    function seedStageSevenUncertified(uint256 word) external {
        uint24 today = _simulatedDayIndex();
        dailyIdx = today;
        _afkingResetDay = today;
        purchaseStartDay = today;
        subsFullyProcessed = true;
        ticketsFullyProcessed = true;
        humanReadComplete = true;
        rngLockedFlag = false;
        prizePoolFrozen = false;
        rngRequestTime = uint48(block.timestamp);
        rngWordCurrent = word;
        rngFlagsAndNudges &= ~(uint16(1) << 13);
        _setRngRequestActive(false);
        _setRngSessionPublished(true);
        _setRngComplete(false);
        _lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 0);
        if (_recordedDailyWord(today) == 0) _recordDailyRng(today, word);
        _pendingBoxCount = 0;
        degeneretteCursor = uint48(degeneretteQueue[_rngReadBuffer() & 1].length);
        decBattleQueue = 0;
        lootboxRngPacked &= ~(uint256(1) << (LR_CRAPS_PENDING_SHIFT + _rngReadBuffer()));
    }

    function consumersComplete() external view returns (bool) { return _rngConsumersComplete(); }
}

/// @title DegradeCertifyRead — CertifyRead certifies from the selector's own stage-7 read
/// @notice The selector picks CertifyRead only when `_rngConsumerStage() == 7` with no
///         certificate. The miner now writes the certificate from that read instead of asking
///         `_tryCompleteRng` and reverting on a decline, so the action can never be reselected
///         in an unchanged state. A decline cannot be seeded: `_rngConsumerStage` and
///         `_rngConsumersComplete` read the same ten fields, and every early-out of
///         `_tryCompleteRng` forces stage 0. This test therefore pins the pairing itself:
///         selection implies certification, with no ETH moving.
contract DegradeCertifyReadTest is DeployProtocol {
    bytes internal realCode;
    uint8 private constant CERTIFY_READ = 14;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        realCode = address(game).code;
    }

    function _seeder() internal returns (CertifyReadSeeder s) {
        vm.etch(address(game), type(CertifyReadSeeder).runtimeCode);
        s = CertifyReadSeeder(payable(address(game)));
    }

    function _restore() internal { vm.etch(address(game), realCode); }

    function testCertifyReadCertifiesFromTheSelectorRead() public {
        CertifyReadSeeder s = _seeder();
        s.seedStageSevenUncertified(uint256(keccak256("degrade-certify")) | 2);
        bool consumersComplete = s.consumersComplete();
        _restore();

        assertTrue(consumersComplete, "fixture: the read cohort is drained");
        assertEq(game.rngConsumerStage(), 7, "fixture: stage 7");
        assertFalse(game.rngComplete(), "fixture: no certificate yet");
        assertEq(game.minerAction(), CERTIFY_READ, "fixture: selector picks CertifyRead");

        uint256 nextBefore = game.nextPrizePoolView();
        uint256 futureBefore = game.futurePrizePoolView();
        uint256 claimableBefore = game.claimablePoolView();
        uint256 balanceBefore = address(game).balance;

        vm.prank(makeAddr("certify-miner"));
        game.mineFlip(0);

        assertTrue(game.rngComplete(), "the call certified the session");
        assertTrue(game.minerAction() != CERTIFY_READ, "CertifyRead is not reselected");
        assertEq(game.nextPrizePoolView(), nextBefore, "next pool untouched");
        assertEq(game.futurePrizePoolView(), futureBefore, "future pool untouched");
        assertEq(game.claimablePoolView(), claimableBefore, "claimable pool untouched");
        assertEq(address(game).balance, balanceBefore, "no ETH left the game");
    }
}
